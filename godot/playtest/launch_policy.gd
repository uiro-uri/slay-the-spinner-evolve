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

## LaunchControllerの max_pull(4.0) × pull_to_speed(5.0) に相当する上限。
const MAX_SPEED := 20.0


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


## 発射位置と初速を決める。enemy_planは予告済みの確定値(＝ボットにも見える情報)。
## fieldは戦う土俵。壁の形で発射できる範囲が変わるので、矩形決め打ちにはしない。
static func decide(
	kind: Kind,
	field: FieldData,
	player_radius: float,
	enemy_plan: EnemySpawn.Plan,
	rng: RandomNumberGenerator
) -> Launch:
	var center := field.center()

	match kind:
		Kind.RANDOM:
			var bounds := field.arena_bounds
			var pos := _clamp(field, Vector2(
				rng.randf_range(bounds.position.x, bounds.end.x),
				rng.randf_range(bounds.position.y, bounds.end.y)
			), player_radius)
			var dir := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
			return Launch.new(pos, dir * rng.randf_range(0.0, MAX_SPEED))

		Kind.AIM_CENTER:
			var pos := _ring_position(field, player_radius, rng)
			return Launch.new(pos, (center - pos).normalized() * MAX_SPEED)

		Kind.AIM_SPAWN:
			var pos := _ring_position(field, player_radius, rng)
			return Launch.new(pos, (enemy_plan.position - pos).normalized() * MAX_SPEED)

		_:
			var pos := _ring_position(field, player_radius, rng)
			# 敵の未来位置を単純な等速仮定で先読みする。傾斜で曲がるので
			# 完璧ではないが、序盤の交差には十分当たる。
			var to_enemy := enemy_plan.position.distance_to(pos)
			var closing_speed := MAX_SPEED + enemy_plan.velocity.length()
			var t := to_enemy / maxf(closing_speed, 0.01)
			var predicted := enemy_plan.position + enemy_plan.velocity * t
			return Launch.new(pos, (predicted - pos).normalized() * MAX_SPEED)


## Battle._clamp_launch と同じ寄せ方。矩形は矩形クランプ、非矩形は内接円。
static func _clamp(field: FieldData, pos: Vector2, player_radius: float) -> Vector2:
	if field.wall_shape == ArenaWall.WallShape.RECT:
		return ArenaWall.clamp_inside(field.arena_bounds, pos, player_radius)
	return ArenaWall.clamp_inside_circle(field.center(), field.inradius(), pos, player_radius)


## 外周寄りのランダムな一点。実プレイヤーも大抵は縁から撃つ。
static func _ring_position(field: FieldData, player_radius: float, rng: RandomNumberGenerator) -> Vector2:
	var ring := field.inradius() - player_radius - 0.5
	var pos := field.center() + Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU)) * ring
	return _clamp(field, pos, player_radius)
