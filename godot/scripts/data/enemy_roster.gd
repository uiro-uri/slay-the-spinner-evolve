class_name EnemyRoster
extends RefCounted

## 敵の一覧と、どの段でどのレベルが出るか。
## archive/flask-prototype/enemy.py の ENEMY_LIST と get_random_enemy に相当する。
##
## 数値はプロトタイプを出発点にしているだけで、手触りで調整する前提。


## 段(1..9)に対する敵レベル(1..5)。ゴール(段9)がレベル5のボスになる。
## プロトタイプに「エネミーが強くなる周期が変だったので修正（ボスがレベル5に
## なるようにしたい）」というコミットがあり、この式に落ち着いている。
static func level_for_step(step: int) -> int:
	return clampi((step + 1) / 2, 1, 5)


static func all() -> Array[EnemyData]:
	return [
		_enemy(1, "ENEMY_1_1", Vector2(0, 0), Vector2(2, 1), 0.5, 0.5, 0.97, 1.0, 15.0),
		_enemy(1, "ENEMY_1_2", Vector2(1, 0), Vector2(1, 2), 0.5, 0.25, 0.98, 1.0, 15.0),
		_enemy(2, "ENEMY_2_1", Vector2(0, 1), Vector2(4, 1), 1.0, 1.0, 0.97, 1.0, 20.0),
		_enemy(2, "ENEMY_2_2", Vector2(1, 1), Vector2(1, 4), 1.0, 0.25, 0.98, 1.0, 20.0),
		_enemy(3, "ENEMY_3_1", Vector2(0, 2), Vector2(5, 2), 2.0, 1.5, 0.98, 1.0, 40.0),
		_enemy(3, "ENEMY_3_2", Vector2(1, 2), Vector2(2, 5), 2.0, 0.5, 0.985, 1.0, 40.0),
		_enemy(4, "ENEMY_4_1", Vector2(0, 3), Vector2(6, 2), 3.0, 2.0, 0.98, 1.0, 50.0),
		_enemy(4, "ENEMY_4_2", Vector2(1, 3), Vector2(2, 6), 3.0, 0.5, 0.985, 1.0, 50.0),
		_enemy(5, "ENEMY_5_1", Vector2(0, 4), Vector2(10, 10), 5.0, 3.0, 0.98, 1.0, 60.0),
	]


static func of_level(level: int) -> Array[EnemyData]:
	var result: Array[EnemyData] = []
	for enemy in all():
		if enemy.level == level:
			result.append(enemy)
	return result


## その段にふさわしい敵を1体選ぶ。
static func pick_for_step(step: int, rng: RandomNumberGenerator = null) -> EnemyData:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var candidates := of_level(level_for_step(step))
	if candidates.is_empty():
		push_error("EnemyRoster: 段%dに出せる敵がいない" % step)
		return null
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _enemy(
	level: int, name_: String, pos: Vector2, vel: Vector2,
	mass: float, radius: float, friction: float, restitution: float, rps: float
) -> EnemyData:
	var stats := SpinnerStats.new()
	stats.mass = mass
	stats.radius = radius
	stats.friction = friction
	stats.restitution = restitution
	stats.rps = rps
	return EnemyData.make(level, name_, pos, vel, stats)
