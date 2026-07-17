extends RefCounted

## テストプレイハーネス自体のテスト。
##
## 検査器(PlaytestInvariants)が本当に壊れた結果を拾えるかを、壊れた結果を
## 手で作って確かめる。ここが節穴だと大量試行の意味がなくなる。
## リゾルバへの細工(sabotage)は開発時に手でやったが、これは常設の裏付け。

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_invariants_catch_bad_results(check)
	_test_invariants_pass_healthy_result(check)
	_test_battle_sim_deterministic(check)
	_test_policies_stay_legal(check)
	_test_run_sim_consistent(check)


func _request() -> BattleRequest:
	var r := BattleRequest.new()
	r.player = BattleRequest.Launch.new(SpinnerStats.default_player(), Vector2(2, 8), Vector2(6, -6))
	var enemy := EnemyRoster.of_level(1)[0]
	r.enemy = BattleRequest.Launch.new(enemy.stats, Vector2(8, 2), Vector2(-3, 4))
	return r


func _healthy_result(request: BattleRequest) -> BattleResult:
	return BattleResolver.resolve(request)


func _test_invariants_catch_bad_results(check: Callable) -> void:
	var request := _request()

	# nan
	var bad := _healthy_result(request)
	bad.player_frames[3] = BattleResult.Snapshot.new(Vector2(NAN, 1.0), Vector2.ZERO, 5.0)
	check.call(
		not PlaytestInvariants.check(request, bad).is_empty(),
		"検査器: nanを拾う"
	)

	# アリーナ脱出
	bad = _healthy_result(request)
	bad.enemy_frames[2] = BattleResult.Snapshot.new(Vector2(30.0, 5.0), Vector2.ZERO, 5.0)
	check.call(
		not PlaytestInvariants.check(request, bad).is_empty(),
		"検査器: アリーナ脱出を拾う"
	)

	# rpsの増加
	bad = _healthy_result(request)
	var f := bad.player_frames[5]
	bad.player_frames[5] = BattleResult.Snapshot.new(f.position, f.velocity, 999.0)
	check.call(
		not PlaytestInvariants.check(request, bad).is_empty(),
		"検査器: rpsの増加を拾う"
	)

	# 戦闘の外の衝突時刻
	bad = _healthy_result(request)
	bad.impacts.append(BattleResult.Impact.new(bad.finish_time + 10.0, Vector2(5, 5)))
	check.call(
		not PlaytestInvariants.check(request, bad).is_empty(),
		"検査器: 範囲外の衝突時刻を拾う"
	)

	# フレーム数の不一致
	bad = _healthy_result(request)
	bad.enemy_frames.pop_back()
	check.call(
		not PlaytestInvariants.check(request, bad).is_empty(),
		"検査器: フレーム数の不一致を拾う"
	)


func _test_invariants_pass_healthy_result(check: Callable) -> void:
	var request := _request()
	var violations := PlaytestInvariants.check(request, _healthy_result(request))
	check.call(
		violations.is_empty(),
		"検査器: 健全な結果は素通しする (%s)" % [violations]
	)


func _test_battle_sim_deterministic(check: Callable) -> void:
	var enemy := EnemyRoster.of_level(2)[0]
	var stats := SpinnerStats.default_player()

	var a := BattleSim.play_one(42, enemy, LaunchPolicy.Kind.INTERCEPT, stats)
	var b := BattleSim.play_one(42, enemy, LaunchPolicy.Kind.INTERCEPT, stats)
	check.call(
		JSON.stringify(a) == JSON.stringify(b),
		"battle_sim: 同じシードなら同じレコード"
	)

	for key in ["seed", "level", "policy", "win", "finish_time", "impacts"]:
		check.call(a.has(key), "battle_sim: レコードに %s がある" % key)

	var c := BattleSim.play_one(43, enemy, LaunchPolicy.Kind.INTERCEPT, stats)
	check.call(
		JSON.stringify(a) != JSON.stringify(c),
		"battle_sim: シードが違えば別の戦いになる"
	)


func _test_policies_stay_legal(check: Callable) -> void:
	var arena := Rect2(0, 0, 10, 10)
	var radius := 0.5
	var rng := RandomNumberGenerator.new()
	var worst_speed := 0.0
	var out_of_bounds := 0

	for kind in LaunchPolicy.NAMES:
		for i in 50:
			rng.seed = i
			var plan := EnemySpawn.plan(Vector2(5, 5), 4.0, 5.0, 30.0, rng, 0.5, 5.0)
			var launch := LaunchPolicy.decide(kind, arena, radius, plan, rng)
			worst_speed = maxf(worst_speed, launch.velocity.length())
			if (launch.position.x < radius - EPS or launch.position.x > 10.0 - radius + EPS
					or launch.position.y < radius - EPS or launch.position.y > 10.0 - radius + EPS):
				out_of_bounds += 1

	check.call(out_of_bounds == 0, "発射方針: 発射位置がアリーナ内 (%d件はみ出し)" % out_of_bounds)
	check.call(
		worst_speed <= LaunchPolicy.MAX_SPEED + EPS,
		"発射方針: 初速が上限以下 (最大 %.2f / 上限 %.0f)" % [worst_speed, LaunchPolicy.MAX_SPEED]
	)


func _test_run_sim_consistent(check: Callable) -> void:
	for seed_value in [7, 8, 9]:
		var r := RunSim.play_one(seed_value, LaunchPolicy.Kind.INTERCEPT, RunSim.RewardPolicy.GREEDY)
		check.call(not r.has("error"), "run_sim: ランが完走する (seed %d)" % seed_value)
		check.call(r["battles"].size() > 0, "run_sim: 戦闘が記録される (seed %d)" % seed_value)

		# パーツはボス以外の勝利ごとに1枚。クリアなら最後の勝利(ボス)には付かない。
		var expected_parts: int = r["battles_won"] - (1 if r["cleared"] else 0)
		check.call(
			r["parts"].size() == expected_parts,
			"run_sim: パーツ数が勝利数と整合 (seed %d: %d枚 / 期待 %d)" % [
				seed_value, r["parts"].size(), expected_parts
			]
		)

		if r["cleared"]:
			check.call(r["died_at_step"] == -1, "run_sim: クリアなら死亡段がない")
		else:
			check.call(r["died_at_step"] >= 1, "run_sim: 死亡段が記録される")
