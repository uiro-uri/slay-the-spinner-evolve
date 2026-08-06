class_name LaunchController
extends Node2D

## 引っ張って離すとコマが飛ぶ（スリングショット式）。
##
## プロトタイプはmousedown/mousemove/mouseupで初速を作り、フォームを
## サーバーへ送って全ステップを計算させていた。ここでは押している間に
## 狙いを描き、離した瞬間にその場で発射する。
##
## 座標はアリーナのユニット系。ArenaRootの子として置くこと。

## プロトタイプの velocityArrow と同じ lime 系。純緑は暗い床でも十分映えるが、
## Palette.AIM に寄せて予告(赤)と対の彩度に揃える。
const ARROW_COLOR := Palette.AIM

## 打ち切りの印(破線の外輪)の見た目。コマの輪の外側に置く余白・破線の本数・
## 1本ぶんの角度。破線にするのは実線の輪が2本並ぶと「どちらが何か」が
## 読めなくなるため。
const CUT_MARK_MARGIN := 0.12
const CUT_MARK_DASHES := 8
const CUT_MARK_DASH_RAD := TAU / 16.0

## これ以上引いても速くならない上限(ユニット)。full pull(=この距離)で初速がLaunchSpeed.MAXになる。
@export_range(0.5, 10.0, 0.1) var max_pull: float = 4.0

## 発射位置と速度が決まった。
signal launched(pos: Vector2, velocity: Vector2)

## 発射地点(三角形の頂点)が動いた。コマをそこへ置くために使う。
## 押していない間もマウスを追うので、どこから飛ぶのかが常に見える。
signal aim_moved(origin: Vector2)

## 狙いの内容(発射地点と初速)が変わった。引いている間だけ出る。
## Battleが先読み(RendezvousPreview)を計算してset_lead()で戻すために使う。
## aim_movedと分けてあるのは、あちらが押す前も出る「位置だけ」の通知だから
## ——先読みには初速が要り、初速は引き始めるまで決まらない。
signal aim_changed(origin: Vector2, velocity: Vector2)

var _dragging: bool = false
var _origin: Vector2 = Vector2.ZERO
var _current: Vector2 = Vector2.ZERO
var _enabled: bool = true

## 先読み(RendezvousPreview.closest_approach)の結果。Battleが狙いのたびに入れる。
## **表示専用**で、_release()はここを一切見ない(発射は引き量から決まるまま)。
## 空なら描かない。
var _lead: Dictionary = {}
var _lead_player_radius: float = 0.0
var _lead_enemy_radius: float = 0.0


func set_enabled(value: bool) -> void:
	_enabled = value
	if not value:
		if _dragging:
			# 引いている途中で無効化(発射で戦闘へ入るなど)されたらチャージ音を止める。
			AudioManager.stop_charge()
		_dragging = false
		# 戦闘へ入ったら先読みは用済み。_drawは_dragging前提で早期returnするので
		# 見えはしないが、次に狙うときへ古い結果を持ち越さないために捨てておく。
		_lead = {}
	queue_redraw()


## 先読みの結果を受け取る。radiiは円を描く大きさ(それぞれのコマの半径)。
## 空Dictionaryで消える。
func set_lead(lead: Dictionary, player_radius: float, enemy_radius: float) -> void:
	_lead = lead
	_lead_player_radius = player_radius
	_lead_enemy_radius = enemy_radius
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_origin = get_local_mouse_position()
			_current = _origin
			aim_moved.emit(_origin)
			# 押した瞬間は引き量0＝初速0。先読みは「動かない自分」を出しても
			# 意味がないので、Battle側が速度0を見て消す。
			aim_changed.emit(_origin, Vector2.ZERO)
			# 引き始め。引き量0から鳴らし始め、動かすほど高く・大きくする。
			AudioManager.start_charge()
			queue_redraw()
		elif _dragging:
			_dragging = false
			_release()
		get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		if _dragging:
			_current = get_local_mouse_position()
			AudioManager.update_charge(_effective_pull().length() / max_pull)
			# 発射と同じ_launch_velocity()で通知する。別々に組み立てると、
			# 先読みが「実際には撃たない弾道」を描くことになる。
			aim_changed.emit(_origin, _launch_velocity())
			queue_redraw()
		else:
			# 押す前もコマがマウスを追うので、どこから飛ぶのかが常に見える。
			_origin = get_local_mouse_position()
			aim_moved.emit(_origin)


## 引いた向きと逆に飛ぶ（パチンコと同じ）。max_pullで頭打ちにする。
func _effective_pull() -> Vector2:
	var pull := _origin - _current
	if pull.length() > max_pull:
		return pull.normalized() * max_pull
	return pull


## 今の引き量で撃ったときの初速。自機・敵で共通のレンジ(LaunchSpeed)から、
## 引き量比をMAXにマップする。
##
## 発射(_release)と狙いの通知(aim_changed)が**同じものを使うための1箇所**。
## 2つに分かれると、先読みが実際には撃たない弾道を描いても誰も気づかない。
func _launch_velocity() -> Vector2:
	var pull := _effective_pull()
	return pull.normalized() * LaunchSpeed.from_pull(pull.length(), max_pull)


func _release() -> void:
	# 離した瞬間にチャージ音を止める。発射音は launched の購読側(Battle)で鳴らす。
	AudioManager.stop_charge()
	queue_redraw()
	launched.emit(_origin, _launch_velocity())


## 塗り潰しの三角形で狙いを示す。頂点が発射地点で、そのまま飛んでいく向きを指す。
## 敵の予告(EnemyTelegraph)と同じ意匠を使う。
func _draw() -> void:
	if not _dragging:
		return

	# 上限まで引いたらそれ以上は伸びない。見た目と実際の初速をずらさないため、
	# 描画も頭打ちにした位置で行う（プロトタイプに上限はなかった）。
	#
	# 長さは引き量ではなく**初速**から出す。敵の予告と同じ規則(AimTriangle)を
	# 通すためで、こうしないと同じ速度でも自機と敵で三角形の長さが違ってしまう。
	# 自機は引き量比＝初速比なので、この経路でも底辺は従来どおりカーソル位置に来る
	# (数値は完全に一致する。手触りは変わらない)。
	var pull := _effective_pull()
	var speed := LaunchSpeed.from_pull(pull.length(), max_pull)
	var points := AimTriangle.points(_origin, pull, AimTriangle.length_for_speed(speed, max_pull))
	if points.is_empty():
		return
	draw_colored_polygon(points, ARROW_COLOR)

	_draw_lead()


## 先読み: 「同じ時刻に自分はここ・相手はそこ」を、それぞれの色の輪で置く。
##
## 三角形は向きと速さしか語らないので、当てるのに要る「着いた頃に相手がどこに
## 居るか」が読めなかった。輪を2つ同時刻で置き、間を線で結ぶと、外している
## ときは**外している幅がそのまま線の長さ**になる——狙いをどちらへ動かせば
## いいかが、当てる前に分かる。
##
## 噛み合うときだけ線を金色の実線にして、輪も塗る。当たり判定そのものではなく
## 「予告の見えているとおりに飛べば触れる」という読みなので、予告の揺れぶんは
## 揺れる(Battleが揺れた表示値を渡している)。
##
## 先読みが壁・柱で打ち切られた側には破線の外輪を重ねる。打ち切りの輪は
## 「一番近づく点」ではなく「ここで読むのをやめた点」なので、無印だと
## **惜しくも外した**と同じ絵になる(コールドプレイ2026-08-06)。どちら側が
## 届いたかは RendezvousPreview が決める——ここは印を置くだけ。
func _draw_lead() -> void:
	if _lead.is_empty():
		return
	var pp: Vector2 = _lead["player_point"]
	var ep: Vector2 = _lead["enemy_point"]
	var contact: bool = _lead["contact"]

	var link := Palette.GOLD_CARD if contact else Palette.TEXT_PRIMARY
	link.a = 0.9 if contact else 0.3
	draw_line(pp, ep, link, 0.05)

	var mine := ARROW_COLOR
	mine.a = 0.85 if contact else 0.45
	var theirs := Palette.ENEMY
	theirs.a = 0.85 if contact else 0.45
	draw_arc(pp, _lead_player_radius, 0.0, TAU, 32, mine, 0.06)
	draw_arc(ep, _lead_enemy_radius, 0.0, TAU, 32, theirs, 0.06)

	if RendezvousPreview.cut_player(_lead):
		_draw_cut_mark(pp, _lead_player_radius)
	if RendezvousPreview.cut_enemy(_lead):
		_draw_cut_mark(ep, _lead_enemy_radius)


## 「ここで先読みを打ち切った」の破線の外輪。コマの輪より一回り大きくして
## 重ならないようにし、色は見積もりの「下がった値」と同じ Palette.STAT_DOWN
## ——自機色(緑)・敵色(赤)のどちらとも別の色でないと、どちらの輪に印が
## 付いているのか読めない。
func _draw_cut_mark(at: Vector2, radius: float) -> void:
	var mark := Palette.STAT_DOWN
	mark.a = 0.9
	var ring := radius + CUT_MARK_MARGIN
	for i in CUT_MARK_DASHES:
		var from := TAU * float(i) / float(CUT_MARK_DASHES)
		draw_arc(at, ring, from, from + CUT_MARK_DASH_RAD, 4, mark, 0.05)
