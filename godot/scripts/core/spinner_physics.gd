class_name SpinnerPhysics
extends RefCounted

## コマ同士のぶつかり合いの計算。すべて純粋な静的関数で、Nodeにもシーンにも
## 依存しないため、ヘッドレステストから直接呼べる。
##
## 式はプロトタイプ(archive/flask-prototype/simulation.py)を出発点にしているが、
## 数値は引き継がない。「コマらしく動くか」を基準に呼び出し側で調整する。
##
## プロトタイプから意図的に変えた点:
##  - 中心へ引く力を「重力」ではなくバネと呼ぶ。変位に比例する力であり、
##    距離に依らない重力とは別物のため（挙動は同じ式のまま）。
##  - 衝突時の回転キックを、互いに引き寄せる向きから弾き合う向きに変えた。
##    プロトタイプは両者を近づける符号になっており、弾性衝突の反発を
##    打ち消していた。「角運動量→運動量」というコメントの意図と逆。
##  - 同キックで相手側にも自分の半径とRPS減少量を使っていたのを対称にした。


## 中心へ引き戻すバネの加速度。変位に比例する（＝調和振動子）。
static func spring_accel(pos: Vector2, center: Vector2, stiffness: float) -> Vector2:
	return stiffness * (center - pos)


## 進行方向と逆向きの一定減速度。
## 停止時はゼロが返る。GodotのVector2.normalized()はゼロベクトルに対して
## ゼロを返すので、プロトタイプのnumpyのように0除算でnanにはならない。
static func friction_accel(vel: Vector2, decel: float) -> Vector2:
	return -decel * vel.normalized()


## 2体が接触していて、かつ近づいているか。離れていく最中の再衝突を防ぐ。
static func is_colliding(
	pos_a: Vector2, radius_a: float, vel_a: Vector2,
	pos_b: Vector2, radius_b: float, vel_b: Vector2
) -> bool:
	if pos_a.distance_squared_to(pos_b) > (radius_a + radius_b) ** 2:
		return false
	return (vel_a - vel_b).dot(pos_a - pos_b) < 0.0


## 完全弾性衝突後の速度を [a, b] で返す。
static func elastic_velocities(
	pos_a: Vector2, vel_a: Vector2, mass_a: float,
	pos_b: Vector2, vel_b: Vector2, mass_b: float
) -> Array[Vector2]:
	var delta := pos_a - pos_b
	var dist_sq := delta.length_squared()
	if dist_sq < 1e-12:
		# 完全に重なっていると向きが定まらない。何もしない方が安全。
		return [vel_a, vel_b]

	var total_mass := mass_a + mass_b
	# 中心線方向の相対速度成分だけを、質量比に応じて交換する。
	var impulse := (vel_a - vel_b).dot(delta) / dist_sq * delta
	var new_a := vel_a - (2.0 * mass_b / total_mass) * impulse
	var new_b := vel_b + (2.0 * mass_a / total_mass) * impulse
	return [new_a, new_b]


## 衝突で削られるRPS量。相手が重く速いほど大きく、自分が重く大きいほど小さい。
static func spin_drain(
	opponent_mass: float, opponent_speed: float,
	own_mass: float, own_radius: float, violence: float
) -> float:
	if own_mass <= 0.0 or own_radius <= 0.0:
		return 0.0
	return violence * (opponent_mass * opponent_speed) / (own_mass * own_radius * own_radius)


## 回転が並進運動に変わって弾き合う分の速度。相手から離れる向きに働く。
## 完全に重なっている時は向きが定まらないが、normalized()がゼロを返すので
## 結果もゼロになる。
static func spin_kick(
	pos_self: Vector2, pos_other: Vector2, own_radius: float, drain: float, scale: float
) -> Vector2:
	return scale * own_radius * drain * (pos_self - pos_other).normalized()


## 壁にめり込んでいて、かつ壁に向かって進んでいるか。
## normalはアリーナ内側を向いた単位ベクトル。
static func wall_hit(
	wall_point: Vector2, wall_normal: Vector2,
	pos: Vector2, vel: Vector2, radius: float
) -> bool:
	if wall_normal.dot(pos - wall_point) >= radius:
		return false
	return wall_normal.dot(vel) < 0.0


## 壁で反射した後の速度。restitutionで勢いが変わる。
static func wall_bounce(vel: Vector2, wall_normal: Vector2, restitution: float) -> Vector2:
	return vel.bounce(wall_normal) * restitution


## 何もしなくても回転は落ちていく。大きいコマほど速く落ちる。
static func natural_spin_decay(radius: float, rate: float, delta: float) -> float:
	return radius * rate * delta
