class_name SpinnerPhysics
extends RefCounted

## コマ同士のぶつかり合いの計算。すべて純粋な静的関数で、Nodeにもシーンにも
## 依存しないため、ヘッドレステストから直接呼べる。
##
## 式はプロトタイプ(archive/flask-prototype/simulation.py)を出発点にしているが、
## 数値は引き継がない。「コマらしく動くか」を基準に呼び出し側で調整する。
##
## これはゲームのための嘘物理であり、系全体としての保存則は成り立たない。
## 特にspin_kickは回転をエネルギー源にして運動を足すので、エネルギーは増える。
## 個々の関数のテストで保存を確認している箇所があるが、それはその関数単体の
## 性質（式が正しいか）を見ているだけで、ゲームの設計上の制約ではない。
## 手触りのために保存を破る変更は歓迎されるべきで、テストの方を直すこと。
##
## プロトタイプから意図的に変えた点:
##  - 衝突時の回転キックを、互いに引き寄せる向きから弾き合う向きに変えた。
##    プロトタイプは両者を近づける符号になっており、弾性衝突の反発を
##    打ち消していた。「角運動量→運動量」というコメントの意図と逆。
##  - 同キックで相手側にも自分の半径とRPS減少量を使っていたのを対称にした。


## ステージの形。ベイブレードのスタジアムのように中央へ向かって傾斜している。
enum StageShape {
	## 放物面のすり鉢。中心から離れるほど傾斜が急になる。実物のスタジアムに近い。
	## プロトタイプのコードが実際にやっていた挙動。
	DISH,
	## 一定傾斜の円錐。どこでも同じ角度で中心へ滑り落ちる。
	## プロトタイプの g = 9.81*sin(30°) という定数はこちらの意図を示唆する。
	CONE,
}


## ステージの傾斜でコマが中央へ滑り落ちる加速度。
##
## DISH: 変位に比例する（放物面のすり鉢＝バネと同じ式）。中心付近は緩やかで
##       外側ほど強く戻される。
## CONE: 大きさ一定で中心を向く（一定傾斜の斜面を滑る成分）。
static func stage_slope_accel(
	pos: Vector2, center: Vector2, strength: float, shape: StageShape = StageShape.DISH
) -> Vector2:
	var toward_center := center - pos
	if shape == StageShape.CONE:
		# normalized()はゼロベクトルにゼロを返すので、中心では力ゼロになる。
		return strength * toward_center.normalized()
	return strength * toward_center


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


## 反発係数付き衝突後の速度を [a, b] で返す。
##
## restitution=1.0 で完全弾性衝突（従来の挙動と厳密一致）。1未満で非弾性になり、
## 中心線方向の分離速度が e 倍に落ちる（e=0で法線方向に一体化）。一般化は
## 弾性の係数 2 を (1+e) に置き換えるだけ。壁のrestitutionと同じ意味の係数を
## コマ同士の衝突にも効かせるための引数（Rage Reflectionの想定）。
## e>1は壁と同様に衝突ごとに加速して発散するので、呼び出し側で[0,1]にクランプする。
static func elastic_velocities(
	pos_a: Vector2, vel_a: Vector2, mass_a: float,
	pos_b: Vector2, vel_b: Vector2, mass_b: float,
	restitution: float = 1.0
) -> Array[Vector2]:
	var delta := pos_a - pos_b
	var dist_sq := delta.length_squared()
	if dist_sq < 1e-12:
		# 完全に重なっていると向きが定まらない。何もしない方が安全。
		return [vel_a, vel_b]

	var total_mass := mass_a + mass_b
	# 中心線方向の相対速度成分だけを、質量比と反発係数に応じて交換する。
	var impulse := (vel_a - vel_b).dot(delta) / dist_sq * delta
	var factor := 1.0 + restitution
	var new_a := vel_a - (factor * mass_b / total_mass) * impulse
	var new_b := vel_b + (factor * mass_a / total_mass) * impulse
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


## 壁での実効rpsダンピング。wall_keep(0..1)のぶんだけ無損失(1.0)へ寄せる。
## wall_keep=0で従来のbase、1で1.0(壁でrpsを失わない)。Rage Reflectionが上げる。
static func effective_wall_damping(base: float, wall_keep: float) -> float:
	return base + (1.0 - base) * clampf(wall_keep, 0.0, 1.0)


## 壁ダンピングを衝突の激しさ(壁法線方向の進入速度)でスケールした値。
## 従来は壁に触れるだけで一律 base 倍(0.75なら25%喪失)で、そっと縁を擦った
## 接触と全力の激突が同じ代償だった。その理不尽さが「壁こそが真の敵」の手触りと
## 「当てにいかず低速で待つのが最適」という逆立ちした戦略の原因になっていたので、
## normal_speed が ref_speed 以上の激突でちょうど base(従来どおり)、それ未満は
## 無損失(1.0)へ線形に寄せる。ref_speed<=0 は速度スケール無効=常に base
## (旧挙動と厳密一致。古い保存データの再現用)。
static func impact_scaled_wall_damping(
	base: float, normal_speed: float, ref_speed: float
) -> float:
	if ref_speed <= 0.0:
		return base
	return lerpf(1.0, base, clampf(normal_speed / ref_speed, 0.0, 1.0))


## 衝突で受けるrps削りの実効値。hit_guard(0..1)のぶんだけ削りを打ち消す。
## 壁のeffective_wall_dampingと対になる、コマ同士の衝突版の防御(Shock Absorber)。
## 削りが減るぶんspin_kick(削り量に比例する弾き)も弱まる=回転を守る代わりに
## 逃げの弾きも小さくなる。
static func guarded_spin_drain(drain: float, hit_guard: float) -> float:
	return drain * (1.0 - clampf(hit_guard, 0.0, 1.0))


## 攻め手のedge(0..)のぶんだけ、相手に与えるrps削りを増やす。edge=0.2で+20%。
## guarded_spin_drain(受け手の軽減)と対になる攻め側の係数で、両方掛かるときは
## 乗算なので順序によらない。負のedgeは0でクランプ(削りを減らす方向には使わない。
## デバフ札を置かないカタログの原則と同じ向き)。
##
## pierce_drainは「相手が攻め手自身と同じ硬さだったときの素の削り」
## (spin_drainに自分の質量・半径を渡した値)。素の削りは相手の硬さ(質量×半径²)に
## 反比例するため、巨体相手ではedgeの乗算ボーナスがほぼゼロに消え、攻め札が
## 終盤に無価値になる非対称があった(edge=0.60でもLv4に約0.2/hit)。edgeのボーナス
## 基準を maxf(drain, pierce_drain) にすることで、刃の食い込みは相手の硬さで
## 無効化されない: 柔らかい相手には従来どおり(1+edge)倍、硬い相手には
## 自分基準の追加削りが下限になる。pierce_drain=0(既定)は従来の乗算と厳密一致。
static func sharpened_spin_drain(drain: float, edge: float, pierce_drain: float = 0.0) -> float:
	return drain + maxf(edge, 0.0) * maxf(drain, pierce_drain)


## 障害物(固定された円)にめり込んでいて、かつ障害物へ向かって進んでいるか。
## 壁のwall_hitと同じ構造で、法線が固定でなく中心からの放射方向になるだけ。
## 反射は wall_bounce(vel, (pos - obstacle_center).normalized(), restitution) を使う。
## 完全に中心が重なっている(delta=0)時はnormalized()がゼロを返し、
## Vector2.bounce(ゼロ)は元の速度をそのまま返すのでNaNにならない。
static func obstacle_hit(
	obstacle_center: Vector2, obstacle_radius: float,
	pos: Vector2, vel: Vector2, radius: float
) -> bool:
	var delta := pos - obstacle_center
	var sum := obstacle_radius + radius
	if delta.length_squared() >= sum * sum:
		return false
	return vel.dot(delta) < 0.0


## 何もしなくても回転は落ちていく。大きいコマほど速く落ちる。
static func natural_spin_decay(radius: float, rate: float, delta: float) -> float:
	return radius * rate * delta
