class_name SpinAura
extends RefCounted

## 回転の勢い(RPS比)を、半透明のオーラとパーティクルで見せるための純粋関数。
##
## RPSは体力そのものだが、マーク(回転の有無)と尾(速さの弧)だけでは
## コマの「勢い」が画面全体の印象として伝わらない。そこでコマの周囲へ
## 本体色の薄いオーラを敷き、縁から流れ出るパーティクルを足す。勢いが
## 減ればオーラは細り、粒は減り、力尽きれば消える。
##
## **Nodeにもシーンにも乱数にも依存しない純粋関数。** telegraph_wobble.gd /
## map_glow.gd と同じ設計で、_process/_draw に数式を埋めるとテストできないため
## 数式だけをここへ切り出す。時刻とRPS比を渡せば同じ値が返る。
##
## 勢いの正規化(RPS比)は Disc.tail_ratio() を再利用する前提で、ここでは
## 0〜1の ratio を受け取る。尾とオーラが同じ尺度で動くので齟齬が出ない。
##
## 半透明の保証: どのalphaも1.0には届かない(「半透明」の定義)。オーラは
## AURA_ALPHA_MAX、粒は PARTICLE_ALPHA_MAX を上限にする。tests/test_spin_aura.gd
## がこれを固定する。

## オーラの同心円の枚数。内側から外側へ薄くしていく偽グラデーション。
const RING_COUNT := 3

## オーラの最も濃い部分のalpha。半透明の上限。1.0には決して届かせない。
const AURA_ALPHA_MAX := 0.30

## 満速時のオーラ外径(コマ半径に対する倍率)。勢いゼロでは本体径そのまま。
const AURA_RADIUS_RATIO := 1.45

## パーティクルの固定スロット数。生成/破棄はせず、常にこの数を使い回す。
const PARTICLE_COUNT := 10

## パーティクル1粒の寿命(秒)。この周期で縁から外へ流れて消える。
const PARTICLE_LIFE := 0.9

## パーティクルの最大alpha。半透明の上限。
const PARTICLE_ALPHA_MAX := 0.6

## 寿命の間にコマの縁から外へ流れ出る距離(コマ半径に対する倍率)。
const DRIFT_RATIO := 0.9

## 寿命の間に回転の後方へ流れる角度(ラジアン)。渦を巻いて見える。
const SWIRL := 1.2

## スロットごとの角度の散らし。整数比だと同じ形を繰り返して読まれるので、
## 割り切れない黄金角を使う(乱数の代わり)。
const GOLDEN_ANGLE := 2.399963

## パーティクルの大きさ(コマ半径に対する倍率)。
const PARTICLE_SIZE_RATIO := 0.10


## k番目(0〜RING_COUNT-1)のオーラの輪の半径とalpha。
## 内側(k=0)ほど濃く小さく、外側ほど淡く大きい。ratio=0では全て消える。
## alphaは AURA_ALPHA_MAX を超えず、半径は本体径〜本体径×AURA_RADIUS_RATIO。
static func aura_ring(ratio: float, disc_radius: float, k: int) -> Dictionary:
	var r := clampf(ratio, 0.0, 1.0)
	# 外側の輪ほど遠くに置く。0番は本体のすぐ外、最後の輪が外径。
	var reach := float(k + 1) / float(RING_COUNT)
	var outer := disc_radius * lerpf(1.0, AURA_RADIUS_RATIO, r)
	var radius := lerpf(disc_radius, outer, reach)
	# 内側ほど濃い。勢い(r)に線形。全体を AURA_ALPHA_MAX に収める。
	var falloff := float(RING_COUNT - k) / float(RING_COUNT)
	var alpha := AURA_ALPHA_MAX * r * falloff
	return {"radius": radius, "alpha": alpha}


## スロットの点灯度(0〜1)。ratioが上がるほど多くのスロットが滑らかに点く。
## 離散的にN個→N+1個と増やすと出現の瞬間がポップするので、重みで連続にする。
static func slot_weight(index: int, count: int, ratio: float) -> float:
	return clampf(ratio * float(count) - float(index), 0.0, 1.0)


## パーティクル1粒の状態。回転するコマのローカル座標系でのオフセット。
## {"offset": Vector2, "alpha": float, "radius": float} を返す。
## (キー名に "size" を使うと Dictionary.size() と衝突しうるので radius にする)
##
## 回転座標系に描く前提なので、visual_rps() で自動的に公転する。実rpsで手動
## 公転させるとナイキストを超えて逆回転に見えるため、そちらはしない(マークと
## 同じ妥協)。速さの大きさは点灯するスロット数(slot_weight)が持つ。
static func particle_state(
	t: float, index: int, ratio: float, disc_radius: float
) -> Dictionary:
	var r := clampf(ratio, 0.0, 1.0)
	# スロットごとに位相をずらして、粒がばらけて流れ続けるようにする。
	var phase := t / PARTICLE_LIFE + float(index) / float(PARTICLE_COUNT)
	var p := fposmod(phase, 1.0)
	var cycle := floorf(phase)
	# 周期ごとに黄金角で角度を振り直す。振り直しは下のenvがちょうど0になる
	# 継ぎ目で起きるので、位置が飛んでも見えない。
	var angle := (float(index) + cycle) * GOLDEN_ANGLE - SWIRL * p
	# 縁(1.02倍)から外へ流れ出る。
	var dist := disc_radius * (1.02 + DRIFT_RATIO * p)
	# 包絡。両端(p=0,1)で厳密に0。周期の継ぎ目とt=0で絶対に飛ばないための肝。
	var env := 4.0 * p * (1.0 - p)
	var alpha := PARTICLE_ALPHA_MAX * env * slot_weight(index, PARTICLE_COUNT, r)
	# 流れるほど小さくなって消えていく。
	var dot_radius := disc_radius * PARTICLE_SIZE_RATIO * lerpf(1.0, 0.4, p)
	return {
		"offset": Vector2(cos(angle), sin(angle)) * dist,
		"alpha": alpha,
		"radius": dot_radius,
	}
