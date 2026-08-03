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

## 決戦専用の土俵の一辺。道中の10より広い。
##
## ボスは全敵で最も大きい(半径1.91)のに、決戦の土俵は八角形＝全土俵で最も内接半径が
## 小さい(4.62)ままだった。「中心のボスに触れずにいられる隙間」
## (内接半径 − ボス半径 − 自機半径)は道中が段1〜8で3.01〜3.83あるのに、決戦だけ2.01と
## 3分の2に落ちる。結果、決戦は発射直後から密着が切れず、被弾/秒が道中の倍近くになって
## 「何が起きたか分からないうちに終わる」戦闘になっていた(段別の被弾/秒 中央値は
## 段8が1.42に対し段9が2.34)。
##
## 12にすると隙間が3.04＝道中の最小値(段7・段8の3.01)と並ぶ。ボスの数値は動かさない:
## 硬さ・寿命・接触トレードはtests/test_enemy_roster.gdの不変条件が縛っており、
## ここで直したいのは強さではなく間合いの方だから。
## 広さを変えたら scripts/playtest.sh と playtest/measure_boss_arena.gd で測り直すこと。
const BOSS_ARENA_SIDE := 12.0


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


## その段の土俵を1つ選ぶ。ボス(レベル5)は決戦専用の大闘技場で固定、それ以外は
## all()から一様。決戦の土俵はall()に入れない(道中で引けてしまうと専用ではなくなる)。
static func pick_for_step(step: int, rng: RandomNumberGenerator = null) -> FieldData:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	# 決戦の舞台は広い八角形の闘技場で固定して特別感を出す。
	if EnemyRoster.level_for_step(step) >= 5:
		return boss_field()
	var candidates := all()
	if candidates.is_empty():
		push_error("FieldRoster: 出せる土俵がない")
		return null
	return candidates[rng.randi_range(0, candidates.size() - 1)]


## 決戦専用の八角形闘技場。形と傾斜は道中のFIELD_ARENAと同じで、広さだけが違う。
static func boss_field() -> FieldData:
	return FieldData.make(
		"FIELD_GRAND_ARENA", Rect2(0, 0, BOSS_ARENA_SIDE, BOSS_ARENA_SIDE),
		ArenaWall.WallShape.OCTAGON, SpinnerPhysics.StageShape.DISH, 4.9)
