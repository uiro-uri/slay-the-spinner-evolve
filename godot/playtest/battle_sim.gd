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


## 1戦。シードが同じなら結果も同じ。
static func play_one(
	seed_value: int,
	enemy: EnemyData,
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

	# Battle._plan_enemy_spawn と同じ手順で出現を決める
	var plan := EnemySpawn.plan(
		arena.get_center(), SPAWN_RING, enemy.launch_speed,
		SPAWN_SPREAD_DEG, rng, enemy.stats.radius, arena.size.x * 0.5
	)

	var launch := LaunchPolicy.decide(policy, arena, player_stats.radius, plan, rng)

	request.player = BattleRequest.Launch.new(player_stats, launch.position, launch.velocity)
	request.enemy = BattleRequest.Launch.new(enemy.stats, plan.position, plan.velocity)

	var result := BattleResolver.resolve(request)
	var violations := PlaytestInvariants.check(request, result)

	var record := {
		"seed": seed_value,
		"level": enemy.level,
		"enemy": enemy.display_name,
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
