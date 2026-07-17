class_name BattleSim
extends RefCounted

## 1戦を組み立てて解き、検査して、集計用の1レコードにする。
##
## Battle.gdが実プレイでやっていること(出現を決める→発射→resolve)を、
## シーンなしで同じ順に踏む。設定の既定値はBattleRequestの既定値
## (＝Battle.tscnの@exportの既定値)をそのまま使うので、何も上書きしなければ
## 本番と同じ条件になる。

## Battle.tscnと同じ出現条件。
const SPAWN_RING := 4.0
const SPAWN_SPREAD_DEG := 30.0


## 設定の上書き(スイープ用)。nullなら既定のまま。
class Overrides:
	extends RefCounted

	var stage_shape := -1  # -1なら既定
	var violence := -1.0

	func apply(request: BattleRequest) -> void:
		if stage_shape >= 0:
			request.stage_shape = stage_shape as SpinnerPhysics.StageShape
		if violence >= 0.0:
			request.violence = violence


## 1戦。シードが同じなら結果も同じ。敵は複数体(乱戦)もありうる。
static func play_one(
	seed_value: int,
	enemies: Array[EnemyData],
	policy: LaunchPolicy.Kind,
	player_stats: SpinnerStats,
	overrides: Overrides = null
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var request := BattleRequest.new()
	if overrides != null:
		overrides.apply(request)

	var arena := request.arena_bounds

	# Battle._spawn_enemy と同じ手順で、各敵の出現を index順に決める。
	var plans: Array[EnemySpawn.Plan] = []
	var enemy_launches: Array[BattleRequest.Launch] = []
	var top_level := 0
	for enemy in enemies:
		var plan := EnemySpawn.plan(
			arena.get_center(), SPAWN_RING, enemy.launch_speed,
			SPAWN_SPREAD_DEG, rng, enemy.stats.radius, arena.size.x * 0.5
		)
		plans.append(plan)
		enemy_launches.append(
			BattleRequest.Launch.new(enemy.stats, plan.position, plan.velocity)
		)
		top_level = maxi(top_level, enemy.level)

	# 発射方針には先頭の敵の予告を渡す。乱戦でもプレイヤーの発射は1回きりなので、
	# 狙う基準を1つに固定して決定性を保つ。
	var launch := LaunchPolicy.decide(policy, arena, player_stats.radius, plans[0], rng)

	request.player = BattleRequest.Launch.new(player_stats, launch.position, launch.velocity)
	request.enemies = enemy_launches

	var result := BattleResolver.resolve(request)
	var violations := PlaytestInvariants.check(request, result)

	var record := {
		"seed": seed_value,
		"level": top_level,
		"count": enemies.size(),
		"enemy": enemies[0].display_name,
		"policy": LaunchPolicy.NAMES[policy],
		"shape": int(request.stage_shape),
		"violence": request.violence,
		"win": result.player_won(),
		"outcome": int(result.outcome),
		"finish_time": result.finish_time,
		"timed_out": result.timed_out,
		"impacts": result.impacts.size(),
	}
	if not violations.is_empty():
		record["violations"] = violations
		# from_dict()で即再現できるよう、入力を丸ごと残す
		record["request"] = request.to_dict()
	return record
