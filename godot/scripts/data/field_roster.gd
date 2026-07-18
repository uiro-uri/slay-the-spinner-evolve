class_name FieldRoster
extends RefCounted

## 土俵(フィールド)の一覧と抽選。EnemyRosterに倣う。
##
## どのフィールドもどの段でも成立するので、段によらず一様ランダムで選ぶ。
## nullを返さないので進行が止まらない（EnemyRosterのテストと同じ保証）。
##
## 数値は手触りで調整する前提。壁の形・傾斜・障害物を組み合わせて、
## 各戦闘の土俵に個性を出す。

const _BOUNDS := Rect2(0, 0, 10, 10)


static func all() -> Array[FieldData]:
	return [
		# 現状同等の安全な既定。すり鉢の標準的な土俵。
		FieldData.make(
			"FIELD_CLASSIC", _BOUNDS, ArenaWall.WallShape.RECT,
			SpinnerPhysics.StageShape.DISH, 4.9),
		# 急なすり鉢。中央へ素早く戻される。
		FieldData.make(
			"FIELD_BOWL", _BOUNDS, ArenaWall.WallShape.RECT,
			SpinnerPhysics.StageShape.DISH, 8.0),
		# 浅い一定傾斜の皿。端で粘りやすい。
		FieldData.make(
			"FIELD_PLATE", _BOUNDS, ArenaWall.WallShape.RECT,
			SpinnerPhysics.StageShape.CONE, 3.0),
		# 八角形の闘技場。
		FieldData.make(
			"FIELD_ARENA", _BOUNDS, ArenaWall.WallShape.OCTAGON,
			SpinnerPhysics.StageShape.DISH, 4.9),
		# 円形の土俵。
		FieldData.make(
			"FIELD_ROUND", _BOUNDS, ArenaWall.WallShape.ROUND,
			SpinnerPhysics.StageShape.DISH, 6.0),
		# 障害物あり。柱は中心・出現リングを避けて配置する。
		FieldData.make(
			"FIELD_PILLARS", _BOUNDS, ArenaWall.WallShape.RECT,
			SpinnerPhysics.StageShape.DISH, 4.9,
			[Vector3(3, 3, 0.6), Vector3(7, 7, 0.6)]),
	]


## その段の土俵を1つ選ぶ。ボス(レベル5)は八角形闘技場で固定、それ以外は全フィールド一様。
static func pick_for_step(step: int, rng: RandomNumberGenerator = null) -> FieldData:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	# 決戦の舞台は八角形の闘技場で固定して特別感を出す。
	if EnemyRoster.level_for_step(step) >= 5:
		return _octagon()
	var candidates := all()
	if candidates.is_empty():
		push_error("FieldRoster: 出せる土俵がない")
		return null
	return candidates[rng.randi_range(0, candidates.size() - 1)]


## ボス用の八角形闘技場(FIELD_ARENA)を返す。
static func _octagon() -> FieldData:
	for field in all():
		if field.title_key == "FIELD_ARENA":
			return field
	push_error("FieldRoster: FIELD_ARENAが見つからない")
	return all()[0]
