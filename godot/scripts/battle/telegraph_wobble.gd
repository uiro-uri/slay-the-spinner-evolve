class_name TelegraphWobble
extends RefCounted

## 敵の予告を「一定範囲でブレて」見せるための揺らぎ。
##
## **見た目だけの揺らぎで、実際の発射内容は動かない。** 敵の出現は発射前に
## 確定していて(EnemySpawn.plan)、その確定値のまま撃たれる。ここが揺らすのは
## 予告の描画だけ。取り違えると予告が本当に嘘になるので、Battleは発射時に
## 必ず確定値を使うこと。
##
## 揺らぎは確定値を中心に振れるので、長く見ていれば平均は真の値に寄る。
## つまり「読めなくする」のではなく「一瞬では読み切れなくする」もの。
##
## Nodeにもシーンにも乱数にも依存しない純粋関数。時刻を渡せば同じ値が返る。

## 位置の揺れ幅(ユニット)。
const DEFAULT_POSITION_AMPLITUDE := 0.22

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


## 予告に見せる位置。確定値の周りを漂う。t=0では確定値そのもの。
static func position_at(
	true_position: Vector2, t: float,
	amplitude: float = DEFAULT_POSITION_AMPLITUDE, speed: float = DEFAULT_SPEED
) -> Vector2:
	return true_position + Vector2(
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
