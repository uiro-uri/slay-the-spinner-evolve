class_name Disc
extends Node2D

## コマ1体。座標も半径もアリーナのユニット系で、表示上の拡大は親のArenaRootの
## scaleが担う。
##
## 物理の計算そのものはBattleResolverが持ち、Battleが結果を流し込む。
## このノードは状態の保持と描画だけを受け持つ。
##
##
## 回転の見せ方について
##
## RPSは体力そのものなので、残りがどれだけあるかが見た目で読めないと困る。
## ところが素直に実速度で回すと、速すぎて読めないどころか止まって見える。
##
## 60fpsでは rps=15(初期値) が 90°/frame、上限の rps=40 なら 240°/frame。
## 一方、模様が正しく見える限界(ナイキスト)は「模様の周期の半分/frame」。
## 以前の破線8本は周期45°なので限界が 3.75rps しかなく、初期値の15rpsでは
## ちょうど2周期分/frameとなって完全に静止して見えていた。
##
## そこで2本立てにしている:
##
##  1. **非対称なマーク**が回転そのものを示す。周期が360°なので限界は30rps。
##     破線8本の8倍で、通常の戦闘域(15rpsから下)を丸ごと賄える。
##  2. **速さの尾**が速度の大きさを示す。マークから伸びる弧の長さがRPSに比例し、
##     速いほど長く、上限付近では円周を一周して"ブレたリング"になる。
##
## 高速域でマークが破綻するのは避けられない(40rpsは非対称でも限界30rpsを超える)
## が、そこでは尾が一周してマークを覆うので、破綻したマークは目立たない。
## そもそも毎秒40回転するコマは現実でもただのブレなので、これは嘘ではない。
##
##  3. **半透明のオーラとパーティクル**が勢いの存在感を示す。コマの背後に本体色の
##     薄いオーラを敷き、縁から粒が流れ出る。勢い(RPS比)が減ればオーラは細り、
##     粒は減り、力尽きれば消える。数式は SpinAura(純粋関数)が持つ。粒は回転する
##     ローカル座標系に描くので visual_rps() で自動的に公転する(実rpsで公転させると
##     マークと同じくナイキストを超えて逆回転に見えるため、そちらはしない)。
##
## マークの回転は限界の手前で頭打ちにしてある。超えた分は逆回転に見えてしまい、
## それは明確な嘘になるため。速さは尾が担うので情報は失われない。

## 非対称マークの角度の幅。狭いほど位置がはっきりするが、速いと見失う。
const MARK_ARC := 0.5

## 尾の太さ(半径に対する割合)。
const TAIL_WIDTH_RATIO := 0.28

## 60fpsを前提にしたときの、マークが正しく見える上限(rps)。
## ナイキスト(30rps)の手前に置く。ちょうど30だと前後どちらに回っているか
## 定まらず、超えると逆回転に見える。
@export_range(1.0, 30.0, 0.5) var max_visual_rps: float = 25.0

## 尾が円周を一周しきるRPS。これ以上は見た目が変わらない。
## 上限(40)に合わせてあるので、上限のコマは完全なリングになる。
@export_range(1.0, 60.0, 1.0) var tail_full_rps: float = 40.0

@export var stats: SpinnerStats
@export var body_color: Color = Palette.PLAYER

var velocity: Vector2 = Vector2.ZERO

## 現在の回転数。尽きた方が負け。stats.rpsは初期値としてだけ使う。
var rps: float = 0.0

## 決着後に色を落とすためのフラグ。
var defeated: bool = false

## パーティクルの流れの位相に使う経過時刻。_processで進める。
var _time: float = 0.0


func _ready() -> void:
	if stats == null:
		stats = SpinnerStats.new()
	reset_spin()


## statsの初期値から回転をやり直す。
func reset_spin() -> void:
	rps = stats.rps
	defeated = false
	queue_redraw()


## 見た目を回す速さ。実速度そのままではナイキストを超えて逆回転に見えるので、
## 正しく見える範囲で頭打ちにする。速さの情報は尾が持つ。
func visual_rps() -> float:
	return minf(rps, max_visual_rps)


## 尾が円周のどれだけを占めるか(0〜1)。速さの大きさはこれが持つ。
func tail_ratio() -> float:
	if tail_full_rps <= 0.0:
		return 0.0
	return clampf(rps / tail_full_rps, 0.0, 1.0)


## オーラとパーティクルに使う勢い(0〜1)。尾と同じ尺度を使い、力尽きたコマは
## 勢いゼロ扱いにする(オーラも粒も消える)。ヘッドレスでテストできるよう関数にする。
func aura_ratio() -> float:
	return 0.0 if defeated else tail_ratio()


func _process(delta: float) -> void:
	_time += delta
	rotation += visual_rps() * TAU * delta
	queue_redraw()


func _draw() -> void:
	var radius := stats.radius

	# 本体の前に、勢いを示すオーラと流れる粒を敷く。力尽きた/止まったコマでは
	# aura_ratio()が0になり、このブロックは丸ごと素通りする(敗北表示は不変)。
	var ar := aura_ratio()
	if ar > 0.001:
		_draw_aura(radius, ar)
		_draw_particles(radius, ar)

	var fill := body_color
	if defeated:
		fill = fill.darkened(0.7)
	draw_circle(Vector2.ZERO, radius, fill)

	if defeated:
		# 力尽きたコマは回っていない。マークだけ残して尾は出さない。
		_draw_mark(radius, Color(Palette.SPIN_MARK, 0.25))
		return

	_draw_tail(radius)
	_draw_mark(radius, Color(Palette.SPIN_MARK, 0.95))


## 本体色の薄い同心円を重ねて、勢いのオーラにする。回転不変なので回転座標系の
## ままでよい。色はbody_color由来+呼び出し側alpha(SPIN_MARKと同じ規約)。
func _draw_aura(radius: float, ratio: float) -> void:
	# 外側の淡い輪から内側の濃い輪へ重ねて、柔らかいグラデーションに見せる。
	for k in range(SpinAura.RING_COUNT - 1, -1, -1):
		var ring := SpinAura.aura_ring(ratio, radius, k)
		draw_circle(Vector2.ZERO, ring.radius, Color(body_color, ring.alpha))


## コマの縁から流れ出る半透明の粒。回転座標系に描くので自動的に公転する。
## 本体色を少し白へ寄せて、地のコマより明るく浮かせる。
func _draw_particles(radius: float, ratio: float) -> void:
	var tint := body_color.lerp(Color.WHITE, 0.35)
	for i in SpinAura.PARTICLE_COUNT:
		var p := SpinAura.particle_state(_time, i, ratio, radius)
		if p.alpha > 0.003:
			draw_circle(p.offset, p.radius, Color(tint, p.alpha))


## マークの後ろへ伸びる弧。長いほど速い。一周すればブレたリングになる。
func _draw_tail(radius: float) -> void:
	var ratio := tail_ratio()
	if ratio <= 0.001:
		return

	var width := radius * TAIL_WIDTH_RATIO
	var span := TAU * ratio
	# マークの手前(回転方向の後ろ)へ伸ばす。回転は反時計回りが正。
	var start := -MARK_ARC * 0.5
	# 根元を濃く、先を薄く。どちらが先端かが分かる。
	var steps := maxi(int(span / 0.15), 3)
	for i in steps:
		var t := float(i) / steps
		var a0 := start - span * t
		var a1 := start - span * (t + 1.0 / steps)
		var color := Color(Palette.SPIN_MARK, lerpf(0.55, 0.0, t))
		draw_arc(Vector2.ZERO, radius - width * 0.5, a1, a0, 4, color, width)


## 回転そのものを示す非対称なマーク。1つしかないので周期は360°。
func _draw_mark(radius: float, color: Color) -> void:
	var width := radius * TAIL_WIDTH_RATIO
	draw_arc(
		Vector2.ZERO, radius - width * 0.5,
		-MARK_ARC * 0.5, MARK_ARC * 0.5, 8, color, width
	)
	# 縁から少し飛び出させて、円周のどこにいるかを掴みやすくする。
	draw_circle(Vector2.RIGHT * radius, width * 0.42, color)
