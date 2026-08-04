extends SceneTree

## 乱戦の敵が「プレイヤーの手を借りずに開幕で消える」度合いを測る診断。
##
##   godot --headless --path godot --script res://playtest/measure_melee_selfkill.gd -- [--count=400]
##
## 動機: コールドプレイ 2026-08-04 で、段4(Lv2×2体)の enemy1 が **0.78秒**で落ちた。
## 内訳の削り14.6 に `(自分…)` が付かない＝**私は一度も触っていない**。段3(2体)も
## 両方が1.2秒台で終わり、乱戦の部屋が私と無関係に片付いた。原因は EnemySpawn.plan()
## が全員を `中心方向 ± spread` へ撃つことで、リング上の全員が同時刻に中央へ集まり、
## 開幕で正面衝突するため。「報酬が頭数ぶん増える危険な部屋」が、実は**危険ですら
## 無い自壊ショー**になっている。
##
## 出す数字(敵1体を1件として数える):
##  - 自力到達不可: プレイヤーの削り(drain_by_player)がほぼ0のまま落ちた敵の割合
##  - 開幕落ち: 1.5秒以内に落ちた敵の割合
##  - 同士討ち率: 敵が削りで失ったrpsのうちプレイヤー由来でない割合の平均
##  - 敵同士の初衝突: 敵同士が最初にぶつかった時刻の中央値(単体戦は n/a)

##
## `--swirl=<度>` で乱戦の回り込み(EnemySpawn.group_swirl_deg)を振れる。0が導入前。

const SPAWN_RING := BattleSim.SPAWN_RING
const SPAWN_SPREAD_DEG := BattleSim.SPAWN_SPREAD_DEG

const LEVELS := [1, 2, 3, 4]
const SIZES := [1, 2, 3]

## 「触っていない」とみなす削りの上限。表示は小数1桁なのでこの下は0と同じ。
const TOUCH_EPS := 0.05

## 「開幕で落ちた」とみなす秒数。コールドプレイの0.78s/1.18s/1.28sを含む帯。
const EARLY_SEC := 1.5


func _init() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var eq := arg.find("=")
			args[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	var count := int(args.get("count", "400"))
	var policy := LaunchPolicy.by_name(args.get("policy", "intercept"))
	var swirl_deg := float(args.get("swirl", str(EnemySpawn.DEFAULT_SWIRL_DEG)))

	print("# 乱戦の開幕自壊 (方針=%s, 各セル%d戦, 回り込み=%.0f度)" % [
		LaunchPolicy.NAMES[policy], count, swirl_deg])
	print("# 敵1体を1件として数える。自機は素の初期性能・土俵は既定。")
	print("")
	print("| Lv | 頭数 | 敵件数 | 自力到達不可 | 開幕落ち(<%.1fs) | 同士討ち率 | 敵同士の初衝突 | 自機勝率 | 決着中央値 |" % EARLY_SEC)
	print("|---|---|---|---|---|---|---|---|---|")
	for level in LEVELS:
		for size in SIZES:
			_row(level, size, count, policy, swirl_deg)
	quit(0)


func _row(level: int, size: int, count: int, policy: LaunchPolicy.Kind, swirl_deg: float) -> void:
	var pool := EnemyRoster.of_level(level)
	if pool.is_empty():
		return

	var enemies_seen := 0
	var untouched_deaths := 0
	var early_deaths := 0
	var mutual_sum := 0.0
	var mutual_n := 0
	var clashes: Array[float] = []
	var wins := 0
	var finishes: Array[float] = []

	for i in count:
		var group: Array[EnemyData] = []
		for k in size:
			var proto: EnemyData = pool[(i + k) % pool.size()]
			group.append(EnemyData.make(level, proto.display_name, proto.stats.duplicate_stats()))
		var pair := _resolve(group, policy, i, swirl_deg)
		var request: BattleRequest = pair["request"]
		var result: BattleResult = pair["result"]
		if result.player_won():
			wins += 1
		finishes.append(result.finish_time)

		for e in result.enemy_deaths.size():
			enemies_seen += 1
			var death: Dictionary = result.enemy_deaths[e]
			var loss: Dictionary = {}
			if e < result.enemy_rps_loss.size():
				loss = result.enemy_rps_loss[e]
			var by_player := float(loss.get("drain_by_player", 0.0))
			var drain := float(loss.get("drain", 0.0))
			if drain > 0.0:
				mutual_sum += clampf((drain - by_player) / drain, 0.0, 1.0)
				mutual_n += 1
			if death.is_empty():
				continue
			if by_player <= TOUCH_EPS:
				untouched_deaths += 1
			if float(death.get("time", 0.0)) < EARLY_SEC:
				early_deaths += 1

		if size > 1:
			var clash := _first_enemy_clash(request, result)
			if clash >= 0.0:
				clashes.append(clash)

	var pct := func(n: int) -> String:
		if enemies_seen == 0:
			return "n/a"
		return "%.1f%%" % (100.0 * n / enemies_seen)
	var mutual := "n/a" if mutual_n == 0 else "%.1f%%" % (100.0 * mutual_sum / mutual_n)
	clashes.sort()
	var median := "n/a"
	if not clashes.is_empty():
		median = "%.2fs" % clashes[clashes.size() / 2]
	finishes.sort()
	var finish := "n/a"
	if not finishes.is_empty():
		finish = "%.2fs" % finishes[finishes.size() / 2]

	print("| %d | %d | %d | %s | %s | %s | %s | %.1f%% | %s |" % [
		level, size, enemies_seen, pct.call(untouched_deaths), pct.call(early_deaths),
		mutual, median, 100.0 * wins / count, finish,
	])


## 実プレイ(Battle._spawn_enemy)・BattleSim と同じ順で1戦を組み立てて解く。
## 集計に BattleResult そのもの(enemy_deaths / enemy_rps_loss)が要るので、
## record だけを返す BattleSim.play_one() ではなく同じ手順をここで踏む。
func _resolve(
	enemies: Array[EnemyData], policy: LaunchPolicy.Kind, seed_value: int, swirl_deg: float
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var field := BattleSim.default_field()

	var request := BattleRequest.new()
	request.arena_bounds = field.arena_bounds
	request.wall_shape = field.wall_shape
	request.obstacles = field.obstacles
	request.stage_strength = field.stage_strength
	request.stage_shape = field.stage_shape

	var plans: Array[EnemySpawn.Plan] = []
	var enemy_radii := PackedFloat32Array()
	var enemy_launches: Array[BattleRequest.Launch] = []
	var group := EnemySpawn.Group.new()
	var swirl := EnemySpawn.group_swirl_deg(enemies.size(), swirl_deg, rng)
	for enemy in enemies:
		var plan := EnemySpawn.plan(
			field.center(), SPAWN_RING, LaunchSpeed.random(rng, enemy.stats.radius),
			SPAWN_SPREAD_DEG, rng, enemy.stats.radius, field.inradius(),
			group.avoid(), group.min_gap(enemy.stats.radius), field.obstacles, swirl
		)
		group.add(plan.position, enemy.stats.radius)
		plans.append(plan)
		enemy_radii.append(enemy.stats.radius)
		enemy_launches.append(
			BattleRequest.Launch.new(enemy.stats, plan.position, plan.velocity)
		)

	var launch := LaunchPolicy.decide(
		policy, field, SpinnerStats.default_player().radius, plans, enemy_radii, rng
	)
	request.player = BattleRequest.Launch.new(
		SpinnerStats.default_player(), launch.position, launch.velocity
	)
	request.enemies = enemy_launches
	return {"request": request, "result": BattleResolver.resolve(request)}


## 敵同士が最初にぶつかった時刻。コマ同士の衝突(result.impacts)のうち、その時刻に
## プレイヤーがどの敵よりも遠い点で起きたものを敵同士とみなす。軌跡からの推定なので
## 厳密さより単純さを取る(BattleMetrics と同じ立場の診断用ヘルパー)。
func _first_enemy_clash(request: BattleRequest, result: BattleResult) -> float:
	for impact in result.impacts:
		var player_snap := result.sample(result.player_frames, impact.time)
		var player_gap := player_snap.position.distance_to(impact.point)
		var enemies_near := 0
		for track in result.enemy_tracks:
			var snap := result.sample(track, impact.time)
			if snap.position.distance_to(impact.point) < player_gap:
				enemies_near += 1
		if enemies_near >= 2:
			return impact.time
	return -1.0
