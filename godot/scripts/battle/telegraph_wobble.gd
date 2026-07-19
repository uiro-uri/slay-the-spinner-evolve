class_name TelegraphWobble
extends RefCounted

## 敵の予告を「一定範囲でブレて」見せるための揺らぎ。
##
## **見た目だけの揺らぎで、実際の発射内容は動かない。** 敵の出現は発射前に
## 確定していて(EnemySpawn.plan)、その確定値のまま撃たれる。ここが揺らすのは
## 予告の描画だけ。取り違えると予告が本当に嘘になるので、Battleは発射時に
## 必ず確定値を使うこと。
##
## 揺らぎの中心は確定値からわざと偏らせる(bias_dir)。真の値は揺れの範囲には
## 入っているが中心ではないので、長く眺めて平均を取っても真の値は割り出せない。
## 「一瞬では読み切れない」だけでなく「じっと平均しても当てられない」ことを狙う。
## 偏りはt=0で0から立ち上がるので、予告が出た瞬間はやはり確定値そのもの
## (コマが飛ばない)。偏りの向きは呼び出し側(Battle)が毎回決めて渡す。
##
## Nodeにもシーンにも乱数にも依存しない純粋関数。時刻と偏りの向きを渡せば
## 同じ値が返る。乱数は呼び出し側が持つ。

## 位置の揺れ幅(ユニット)。読み取りにくさを重視して大きめに取ってある。
const DEFAULT_POSITION_AMPLITUDE := 1.2

## 揺れの中心を確定値からずらす割合(揺れ幅に対して)。0で従来どおり確定値が中心。
## 揺れ幅より小さくしてあるので、真の値は必ず揺れの範囲に残る(=予告は嘘にならない)。
const POSITION_BIAS := 0.7

## 中心ずらしの立ち上がりの速さ。bias_ramp が 0→1 になる目安。
const BIAS_RAMP_RATE := 1.8

## 向きの揺れ幅(度)。
const DEFAULT_ANGLE_AMPLITUDE := 7.0

## 長さの揺れ幅(割合)。0.14なら±14%。
const DEFAULT_LENGTH_AMPLITUDE := 0.14

## 揺れの速さ。
const DEFAULT_SPEED := 2.2

## 揺らす対象ごとの周波数の組。整数比にすると同じ形を繰り返して読まれるので、
## 割り切れない比を選んである。組を変えることで各軸の動きが揃わなくなる。
const FREQ_X := Vector2(1.0, 1.7)
const FREQ_Y := Vector2(1.3, 2.1)
const FREQ_ANGLE := Vector2(0.8, 1.9)
const FREQ_LENGTH := Vector2(1.1, 2.4)

## 敵レベル(1..5)に対する揺れ幅の倍率。強い敵ほど予告が大きくブレて読みにくく、
## 弱い敵ほど読みやすい。レベル1で MIN、レベル5で MAX まで線形に上げる。
## DEFAULT_*_AMPLITUDE を基準にこの倍率を掛ける。手触りで調整するつまみ。
const LEVEL_MIN_SCALE := 0.6
const LEVEL_MAX_SCALE := 1.6
const MAX_LEVEL := 5


## 敵レベル(1..5)→揺れ幅の倍率。範囲外はクランプする。
static func level_scale(level: int) -> float:
	var t := clampf(float(level - 1) / float(MAX_LEVEL - 1), 0.0, 1.0)
	return lerpf(LEVEL_MIN_SCALE, LEVEL_MAX_SCALE, t)


## -1〜1の滑らかな揺らぎ。
##
## 正弦を2本重ねて機械的な往復に見えないようにしつつ、振幅の和をちょうど1に
## してあるので必ず-1〜1に収まる(揺れ幅を超えないことがこれで保証される)。
##
## 位相ではなく周波数で散らすのは、t=0で必ず0にするため。位相をずらすと
## 出た瞬間に確定値からずれた位置に現れ、コマが1フレーム飛ぶ。
static func wave(t: float, speed: float, freq: Vector2) -> float:
	return sin(t * speed * freq.x) * 0.6 + sin(t * speed * freq.y) * 0.4


## 中心ずらしの立ち上がり。0→1に滑らかに増える。t=0では0(=偏りなし)で、
## t=0での傾きも0にしてあるので、予告が出た瞬間にコマがカクッと動かない。
static func bias_ramp(t: float) -> float:
	return 1.0 - exp(-pow(t * BIAS_RAMP_RATE, 2.0))


## 予告に見せる位置。確定値の「周り」を漂うが、中心は bias_dir 方向へずらす。
## t=0では確定値そのもの。bias_dir は単位ベクトル(向きだけ)。Vector2.ZERO なら
## 従来どおり確定値が揺れの中心になる。
static func position_at(
	true_position: Vector2, t: float,
	amplitude: float = DEFAULT_POSITION_AMPLITUDE, speed: float = DEFAULT_SPEED,
	bias_dir: Vector2 = Vector2.ZERO
) -> Vector2:
	var bias := bias_dir * amplitude * POSITION_BIAS * bias_ramp(t)
	return true_position + bias + Vector2(
		wave(t, speed, FREQ_X) * amplitude,
		wave(t, speed, FREQ_Y) * amplitude
	)


## 予告に見せる速度。向きと大きさの両方が揺れる。t=0では確定値そのもの。
static func velocity_at(
	true_velocity: Vector2, t: float,
	angle_amplitude_deg: float = DEFAULT_ANGLE_AMPLITUDE,
	length_amplitude: float = DEFAULT_LENGTH_AMPLITUDE,
	speed: float = DEFAULT_SPEED
) -> Vector2:
	var angle := deg_to_rad(wave(t, speed, FREQ_ANGLE) * angle_amplitude_deg)
	var scale := 1.0 + wave(t, speed, FREQ_LENGTH) * length_amplitude
	return true_velocity.rotated(angle) * scale
