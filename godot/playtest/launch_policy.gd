class_name LaunchPolicy
extends RefCounted

## テストプレイボットの発射方針。
##
## ボットの腕は人間と同じにはならないので、1つの方針で「人間ならこう」とは
## 言わない。下手の代理(RANDOM)から上手い寄り(INTERCEPT)まで並べて、
## 勝率を「RANDOMでX%〜INTERCEPTでY%」という幅で読む。
##
## 純粋・シード可能。同じrng状態なら同じ発射になる。

enum Kind {
	## 位置も向きも力も一様ランダム。下手な人間の下界。
	RANDOM,
	## 外周から中心へ最大力。何も考えない突進。
	AIM_CENTER,
	## 敵の出現位置へ最大力。予告の見た目だけ読む人。
	AIM_SPAWN,
	## 敵の確定速度を先読みして未来位置へ。予告を完全に読み切る上界寄り。
	## (出現内容は入力として確定しているので、ボットには読める)
	INTERCEPT,
}

const NAMES := {
	Kind.RANDOM: "random",
	Kind.AIM_CENTER: "aim_center",
	Kind.AIM_SPAWN: "aim_spawn",
	Kind.INTERCEPT: "intercept",
}


## **立ち位置**(リング上のどこから撃つか)。Kind(どこを狙うか)と直交する軸。
##
## 動機(コールドプレイ 2026-08-08, seed=4821): 9戦を**全部同じ一手**で勝った——
## 「狙う敵の出現位置の**真反対**のリング点から、満引きで、その敵を狙う」。
## 残機を1つも使わずクリアし、force を落とす理由も角度を変える理由も最後まで
## 出てこなかった。ところが既存のボット方針(AIM_CENTER/AIM_SPAWN/INTERCEPT)は
## **どれも立ち位置を `_ring_position` の一様ランダムで決めている**ので、
## report.md のクリア率も measure_* の勝率も**人間が誰も取らない立ち方**で
## 測られていた。狙いと引き量は方針とフォースのスイープで測れるのに、
## 立ち位置だけが統計に現れない軸として残っている。
##
## 助走が効く理屈: 接触の削りは相対速さに比例する(SpinnerPhysics.spin_drain)。
## 真反対から撃つと、敵とすれ違うまでの距離が最も長くなり、傾斜で加速したまま
## 噛み合える。真横や敵側から撃つと、間合い(LaunchStandoff)へ押し出されたぶん
## 助走が短いか、そもそも敵から遠ざかる向きに転がる。
##
## RANDOM(下手の下界)はリングに乗らない方針なので、立ち位置は無視する。
enum Stance {
	## リング上の一様ランダムな一点。従来の挙動そのもの(既定)。
	RING_RANDOM,
	## 狙う敵(plans[0])の出現位置の真反対。助走を最大化する。
	RING_OPPOSITE,
	## 狙う敵の出現位置と同じ側。助走が最短になる下界の対照。
	RING_NEAR,
}

const STANCE_NAMES := {
	Stance.RING_RANDOM: "random",
	Stance.RING_OPPOSITE: "opposite",
	Stance.RING_NEAR: "near",
}

## 自機の初速上限。自機・敵で共通のレンジ(LaunchSpeed)の上限に揃える。
const MAX_SPEED := LaunchSpeed.MAX

## 「真反対/同じ側」を決める向きが取れないとみなす距離(出現が中心に重なった場合)。
## この長さ未満ならランダムな立ち位置へ落とす(正規化でNaNを出さない)。
const _CENTER_EPS := 0.001


class Launch:
	extends RefCounted

	var position: Vector2
	var velocity: Vector2

	func _init(position_: Vector2, velocity_: Vector2) -> void:
		position = position_
		velocity = velocity_


static func by_name(name: String) -> Kind:
	for kind in NAMES:
		if NAMES[kind] == name:
			return kind
	push_error("LaunchPolicy: 未知の方針 '%s'" % name)
	return Kind.RANDOM


static func stance_by_name(name: String) -> Stance:
	for stance in STANCE_NAMES:
		if STANCE_NAMES[stance] == name:
			return stance
	push_error("LaunchPolicy: 未知の立ち位置 '%s'" % name)
	return Stance.RING_RANDOM


## 発射位置と初速を決める。plansは予告済みの全敵の確定値(＝ボットにも見える情報)で、
## 狙う基準は先頭plans[0](乱戦でも発射は1回きりなので基準を1つに固定)。
## enemy_radiiはplansと同indexの敵半径で、立ち合いの間合い(LaunchStandoff)に使う。
## fieldは戦う土俵。壁の形で発射できる範囲が変わるので、矩形決め打ちにはしない。
##
## 実UI(Battle)と同じく、位置を決めて間合いへ寄せてから向きを計算する。
## 逆順にすると「間合いで動かされた位置から古い向きで撃つ」ズレが出る。
##
## force_scaleは実UIの引き量比。既定1.0で満引き(=速度MAX)。ボットの狙う方針は
## どれも満引き固定なので、これを振らないと「どれだけ引くか」という実プレイヤーの
## 選択が統計に現れない。初速への変換は LaunchSpeed.from_pull(=実UIと同じ経路)で、
## 0でも下限 PLAYER_MIN を割らない。
##
## stanceは立ち位置の**向き**(Stance参照)、ring_scaleは立ち位置の**中心からの距離**
## (外周リングを1.0とした比。0で中心)。どちらも既定で従来と厳密一致。
## 「どこを狙うか(kind)」「どれだけ引くか(force_scale)」と直交する軸で、
## 実UI(Battle._clamp_launch)は土俵の内側ならどこへでも置けるのに、ボットは
## 外周リングの1点しか撃てなかった(ring_scale が無かった)。
static func decide(
	kind: Kind,
	field: FieldData,
	player_radius: float,
	plans: Array[EnemySpawn.Plan],
	enemy_radii: PackedFloat32Array,
	rng: RandomNumberGenerator,
	force_scale: float = 1.0,
	stance: Stance = Stance.RING_RANDOM,
	ring_scale: float = 1.0
) -> Launch:
	var center := field.center()
	var target: EnemySpawn.Plan = plans[0]
	var spawn_points := PackedVector2Array()
	for plan in plans:
		spawn_points.append(plan.position)
	# 実UI(LaunchController)と同じ経路で初速にする。かつてここは MAX_SPEED*force の
	# 素の掛け算で、自機の下限(LaunchSpeed.PLAYER_MIN)が入った後もボットだけが
	# 下限より遅く撃てた——つまり**実プレイでは選べない発射を統計に混ぜていた**。
	# force_scaleは引き量比なので、from_pullを通すのが定義どおり。
	var speed := LaunchSpeed.from_pull(clampf(force_scale, 0.0, 1.0), 1.0)

	match kind:
		Kind.RANDOM:
			var bounds := field.arena_bounds
			var pos := field.clamp_launch(Vector2(
				rng.randf_range(bounds.position.x, bounds.end.x),
				rng.randf_range(bounds.position.y, bounds.end.y)
			), spawn_points, enemy_radii, player_radius)
			var dir := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
			# RANDOMは引き量もランダムなので、force_scaleは抽選の上限を動かす。
			# 抽選するのは**引き量**で、初速への変換は他の方針と同じ from_pull。
			# 速度を直に[0,speed]から引くと自機の下限を割った発射が混ざり、
			# 「下手の下界」が実プレイでは選べないところまで下がってしまう。
			var pull := rng.randf_range(0.0, clampf(force_scale, 0.0, 1.0))
			return Launch.new(pos, dir * LaunchSpeed.from_pull(pull, 1.0))

		Kind.AIM_CENTER:
			var pos := _ring_position(
				field, player_radius, spawn_points, enemy_radii, rng,
				stance, target.position, ring_scale
			)
			return Launch.new(pos, (center - pos).normalized() * speed)

		Kind.AIM_SPAWN:
			var pos := _ring_position(
				field, player_radius, spawn_points, enemy_radii, rng,
				stance, target.position, ring_scale
			)
			return Launch.new(pos, (target.position - pos).normalized() * speed)

		_:
			var pos := _ring_position(
				field, player_radius, spawn_points, enemy_radii, rng,
				stance, target.position, ring_scale
			)
			# 敵の未来位置を単純な等速仮定で先読みする。傾斜で曲がるので
			# 完璧ではないが、序盤の交差には十分当たる。
			# 先読みは実際に出す速度(speed)で合わせる。満引き固定のままだと
			# 弱く撃ったときに到達時刻がずれて、狙いが下手になったぶんまで
			# フォースの効果として測ってしまう。
			var to_enemy := target.position.distance_to(pos)
			var closing_speed := speed + target.velocity.length()
			var t := to_enemy / maxf(closing_speed, 0.01)
			var predicted := target.position + target.velocity * t
			return Launch.new(pos, (predicted - pos).normalized() * speed)


## 外周寄りの一点。実プレイヤーも大抵は縁から撃つ。
## 敵予告の間合いに入る角度を引いたら、間合いの外まで押し出される。
##
## 角度の決め方は stance が決める(Stance参照)。RING_RANDOM は従来どおり一様乱数。
## RING_OPPOSITE / RING_NEAR は target_position(狙う敵の出現位置)から向きを引く。
## **どの stance でも rng を1回引く**のは、立ち位置を変えても以降の乱数列が
## ずれないようにするため——ずれると「立ち位置の効果」に敵の湧きの違いが混ざる。
##
## ring_scale は中心からの距離の比(1.0=外周リング=従来、0.0=中心)。負・1超は
## クランプする。実UIは土俵の内側ならどこへでも置けるので、外周だけを撃つ
## ボットは実UIの入力の**1自由度ぶんしか使っていない**。
static func _ring_position(
	field: FieldData,
	player_radius: float,
	spawn_points: PackedVector2Array,
	enemy_radii: PackedFloat32Array,
	rng: RandomNumberGenerator,
	stance: Stance = Stance.RING_RANDOM,
	target_position: Vector2 = Vector2.ZERO,
	ring_scale: float = 1.0
) -> Vector2:
	var ring := (field.inradius() - player_radius - 0.5) * clampf(ring_scale, 0.0, 1.0)
	var center := field.center()
	var random_dir := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
	var dir := random_dir
	var to_target := target_position - center
	if stance != Stance.RING_RANDOM and to_target.length() >= _CENTER_EPS:
		# 真反対=助走が最長、同じ側=最短。出現が中心に重なっていたら向きが
		# 取れないのでランダムのまま(正規化でNaNを出さない)。
		dir = -to_target.normalized() if stance == Stance.RING_OPPOSITE \
			else to_target.normalized()
	var pos := center + dir * ring
	return field.clamp_launch(pos, spawn_points, enemy_radii, player_radius)
