extends SceneTree

## 乱戦(複数体)の出現が「重なって湧いていないか」を数える計測スクリプト。
##
## 間隔の規則は EnemySpawn.Group が持っていて、実プレイ(Battle._spawn_enemy)・
## ボット(BattleSim)・CLI(naive_play)の3経路が通る。かつてボット/CLIだけが
## これを通しておらず、敵同士が縁を食い込ませて湧いていた。そうなると発射前に
## 敵同士が潰し合い、乱戦は「実プレイには無い、簡単で報酬だけ多い部屋」として
## 測られる。ここでは規則あり/なしを同じ抽選で並べて、その差を数える。
##
##   godot --headless --path godot --script res://playtest/measure_spawn_gap.gd -- --samples=4000
##
## 出力は段ごとの「重なり率(縁が食い込んで湧いた組の割合)」と縁間隔の分布。

const SPAWN_RING := 4.0
const SPAWN_SPREAD_DEG := 30.0
const STEPS := 9
## Battle.gd の spawn_clearance 既定値。
const CLEARANCE := 0.6


func _init() -> void:
	var samples := 4000
	var seed_base := 70000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--samples="):
			samples = int(arg.split("=")[1])
		elif arg.begins_with("--seed="):
			seed_base = int(arg.split("=")[1])

	# 段ごとの累計。[0]は未使用(段は1始まり)。
	var stats := []
	for _i in STEPS + 1:
		stats.append({
			"groups": 0, "multi": 0, "pairs": 0,
			"overlap": 0, "touch": 0, "gap_sum": 0.0, "gap_min": INF,
			"g_pairs": 0, "g_overlap": 0, "g_touch": 0, "g_gap_sum": 0.0, "g_gap_min": INF,
		})
	var totals := {
		"multi": 0, "pairs": 0, "overlap": 0, "touch": 0,
		"g_pairs": 0, "g_overlap": 0, "g_touch": 0,
	}
	# 乱戦を実際に解いた結果。規則なし/ありを同じ抽選で並べる。
	var fights := {}
	for prefix in ["", "g_", "ov_", "ok_"]:
		for key in ["n", "win", "early", "no_contact", "time"]:
			fights[prefix + key] = 0.0

	for i in samples:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_base + i
		var step := 1 + (i % STEPS)
		var enemies := EnemyRoster.pick_group_for_step(step, rng)
		var field := FieldRoster.pick_for_step(step, rng)
		var s: Dictionary = stats[step]
		s["groups"] += 1
		if enemies.size() < 2:
			continue
		s["multi"] += 1
		totals["multi"] += 1

		# 同じ抽選を2経路で組む。速度抽選まで含めて乱数列を揃えたいので、
		# rngの状態を控えてから2度回す。
		var state := rng.state
		var bot := _spawn_all(enemies, field, rng, false)
		rng.state = state
		var spaced := _spawn_all(enemies, field, rng, true)

		_tally(s, totals, "", bot, enemies)
		_tally(s, totals, "g_", spaced, enemies)

		# 同じ抽選・同じ発射方針で1戦ずつ解いて、乱戦の手応えの差を見る。
		var st2 := rng.state
		_fight(fights, "", enemies, field, bot, rng)
		rng.state = st2
		_fight(fights, "g_", enemies, field, spaced, rng)
		# 規則なし側で実際に重なっていた戦だけを別立てで数える(重なりが
		# 早死にを起こしているのか、それとも別の要因なのかを切り分ける)。
		rng.state = st2
		_fight(fights, ("ov_" if _has_overlap(bot, enemies) else "ok_"), enemies, field, bot, rng)

	_report("間隔の規則なし(かつてのボット/CLI経路)", stats, totals, "")
	_report("EnemySpawn.Group あり(現行の3経路)", stats, totals, "g_")
	_report_fights(fights)
	quit()


## 乱戦を1戦解いて、勝敗と「敵が勝手に落ちたか」を数える。
func _fight(
	fights: Dictionary, prefix: String, enemies: Array[EnemyData],
	field: FieldData, plans: Array[EnemySpawn.Plan], rng: RandomNumberGenerator
) -> void:
	var request := BattleRequest.new()
	request.arena_bounds = field.arena_bounds
	request.wall_shape = field.wall_shape
	request.obstacles = field.obstacles
	request.stage_strength = field.stage_strength
	request.stage_shape = field.stage_shape

	var radii := PackedFloat32Array()
	var launches: Array[BattleRequest.Launch] = []
	for i in enemies.size():
		radii.append(enemies[i].stats.radius)
		launches.append(BattleRequest.Launch.new(
			enemies[i].stats, plans[i].position, plans[i].velocity
		))
	var player := SpinnerStats.default_player()
	var launch := LaunchPolicy.decide(
		LaunchPolicy.Kind.INTERCEPT, field, player.radius, plans, radii, rng
	)
	request.player = BattleRequest.Launch.new(player, launch.position, launch.velocity)
	request.enemies = launches

	var result := BattleResolver.resolve(request)
	fights[prefix + "n"] += 1.0
	fights[prefix + "time"] += result.finish_time
	if result.player_won():
		fights[prefix + "win"] += 1.0
	# プレイヤーが着く前(0.5秒以内)に落ちた敵が居たか＝重なり出現の症状。
	var first_impact := INF
	for impact in result.impacts:
		first_impact = minf(first_impact, impact.time)
	for track in result.enemy_tracks:
		var died := _death_time(track, request)
		if died >= 0.0 and died <= 0.5:
			fights[prefix + "early"] += 1.0
			break
	if result.impacts.is_empty():
		fights[prefix + "no_contact"] += 1.0


## そのコマが力尽きた時刻。最後まで生きていれば-1。
func _death_time(track: Array[BattleResult.Snapshot], request: BattleRequest) -> float:
	for i in track.size():
		if track[i].rps <= request.lose_threshold:
			return i * request.time_step
	return -1.0


## 規則なし側の出現に重なりが含まれるか。
func _has_overlap(plans: Array[EnemySpawn.Plan], enemies: Array[EnemyData]) -> bool:
	for a in plans.size():
		for b in range(a + 1, plans.size()):
			var gap := plans[a].position.distance_to(plans[b].position) \
				- enemies[a].stats.radius - enemies[b].stats.radius
			if gap < 0.0:
				return true
	return false


func _fight_label(prefix: String) -> String:
	match prefix:
		"": return "規則なし全体  "
		"g_": return "Group あり全体"
		"ov_": return "└重なった戦のみ"
	return "└重ならなかった戦"


func _report_fights(fights: Dictionary) -> void:
	print("=== 乱戦を実際に解いた結果(intercept・同じ抽選) ===")
	print("経路 | 戦数 | プレイヤー勝率 | 0.5秒以内に落ちた敵が居た率 | 接触0回 | 平均決着")
	for prefix in ["", "g_", "ov_", "ok_"]:
		var n: float = fights[prefix + "n"]
		if n <= 0.0:
			continue
		print("%s | %4d | %5.1f%% | %5.1f%% | %4.1f%% | %5.2fs" % [
			_fight_label(prefix), int(n),
			100.0 * fights[prefix + "win"] / n,
			100.0 * fights[prefix + "early"] / n,
			100.0 * fights[prefix + "no_contact"] / n,
			fights[prefix + "time"] / n,
		])


## 1グループぶんの出現を決める。game=true なら Battle._spawn_enemy と同じく、
## 既に決めた敵を avoid に、縁が CLEARANCE 空く距離を min_gap に渡す。
func _spawn_all(
	enemies: Array[EnemyData], field: FieldData, rng: RandomNumberGenerator, game: bool
) -> Array[EnemySpawn.Plan]:
	var plans: Array[EnemySpawn.Plan] = []
	var group := EnemySpawn.Group.new(CLEARANCE)
	for enemy in enemies:
		var avoid: Array[Vector2] = []
		var min_gap := 0.0
		if game:
			avoid = group.avoid()
			min_gap = group.min_gap(enemy.stats.radius)
		var plan := EnemySpawn.plan(
			field.center(), SPAWN_RING, LaunchSpeed.random(rng, enemy.stats.radius),
			SPAWN_SPREAD_DEG, rng, enemy.stats.radius, field.inradius(),
			avoid, min_gap, field.obstacles
		)
		plans.append(plan)
		group.add(plan.position, enemy.stats.radius)
	return plans


func _tally(
	s: Dictionary, totals: Dictionary, prefix: String,
	plans: Array[EnemySpawn.Plan], enemies: Array[EnemyData]
) -> void:
	for a in plans.size():
		for b in range(a + 1, plans.size()):
			var gap := plans[a].position.distance_to(plans[b].position) \
				- enemies[a].stats.radius - enemies[b].stats.radius
			s[prefix + "pairs"] += 1
			totals[prefix + "pairs"] += 1
			s[prefix + "gap_sum"] += gap
			s[prefix + "gap_min"] = minf(s[prefix + "gap_min"], gap)
			if gap < 0.0:
				s[prefix + "overlap"] += 1
				totals[prefix + "overlap"] += 1
			if gap < CLEARANCE:
				s[prefix + "touch"] += 1
				totals[prefix + "touch"] += 1


func _report(title: String, stats: Array, totals: Dictionary, prefix: String) -> void:
	print("=== 乱戦の出現間隔: %s ===" % title)
	print("段 | 乱戦数 | 組数 | 重なり(gap<0) | 近すぎ(gap<%.2f) | 平均gap | 最小gap" % CLEARANCE)
	for step in range(1, STEPS + 1):
		var s: Dictionary = stats[step]
		if s[prefix + "pairs"] == 0:
			print("%2d |      0" % step)
			continue
		print("%2d | %6d | %4d | %5d (%4.1f%%) | %5d (%4.1f%%) | %7.2f | %7.2f" % [
			step, s["multi"], s[prefix + "pairs"],
			s[prefix + "overlap"], 100.0 * s[prefix + "overlap"] / s[prefix + "pairs"],
			s[prefix + "touch"], 100.0 * s[prefix + "touch"] / s[prefix + "pairs"],
			s[prefix + "gap_sum"] / s[prefix + "pairs"], s[prefix + "gap_min"],
		])
	if totals[prefix + "pairs"] > 0:
		print("合計: 乱戦 %d / 組 %d / 重なり %d (%.1f%%) / 近すぎ %d (%.1f%%)\n" % [
			totals["multi"], totals[prefix + "pairs"],
			totals[prefix + "overlap"], 100.0 * totals[prefix + "overlap"] / totals[prefix + "pairs"],
			totals[prefix + "touch"], 100.0 * totals[prefix + "touch"] / totals[prefix + "pairs"],
		])
