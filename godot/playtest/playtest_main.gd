extends SceneTree

## テストプレイのCLIエントリ。
##
##   godot --headless --path godot --script res://playtest/playtest_main.gd -- \
##     --mode=battle --seed-start=0 --count=500 --policy=random --level=3 \
##     [--shape=0|1] [--violence=0.08] --out=/tmp/out.jsonl
##
##   godot --headless --path godot --script res://playtest/playtest_main.gd -- \
##     --mode=run --seed-start=0 --count=100 --policy=intercept \
##     --reward=greedy --out=/tmp/runs.jsonl
##
## 1行1レコードのJSONLを書く。集計はscripts/playtest_report.pyがやる。
## シード範囲が同じなら出力も同じ(決定的)。並列化はシード範囲を分けて
## このプロセスを複数起動する(scripts/playtest.sh)。


func _init() -> void:
	var args := _parse_args()

	var mode: String = args.get("mode", "battle")
	var seed_start := int(args.get("seed-start", "0"))
	var count := int(args.get("count", "100"))
	var out_path: String = args.get("out", "")

	if out_path.is_empty():
		printerr("--out=<path> が必要")
		quit(2)
		return

	var out := FileAccess.open(out_path, FileAccess.WRITE)
	if out == null:
		printerr("出力を開けない: %s" % out_path)
		quit(2)
		return

	var overrides := BattleSim.Overrides.new()
	if args.has("shape"):
		overrides.stage_shape = int(args["shape"])
	if args.has("violence"):
		overrides.violence = float(args["violence"])

	var policy := LaunchPolicy.by_name(args.get("policy", "random"))
	var violations := 0

	match mode:
		"battle":
			var level := int(args.get("level", "1"))
			var pool := EnemyRoster.of_level(level)
			if pool.is_empty():
				printerr("レベル%dの敵がいない" % level)
				quit(2)
				return
			var stats := SpinnerStats.default_player()
			for i in count:
				var seed_value := seed_start + i
				# 敵の個体はシードで決める(同レベルに2体いる)
				var pick_rng := RandomNumberGenerator.new()
				pick_rng.seed = seed_value
				var enemy := pool[pick_rng.randi_range(0, pool.size() - 1)]
				var record := BattleSim.play_one(seed_value, enemy, policy, stats, overrides)
				if record.has("violations"):
					violations += 1
				out.store_line(JSON.stringify(record))
		"run":
			var reward := RunSim.reward_by_name(args.get("reward", "random"))
			for i in count:
				var record := RunSim.play_one(seed_start + i, policy, reward, overrides)
				for battle in record.get("battles", []):
					if battle.has("violations"):
						violations += 1
				out.store_line(JSON.stringify(record))
		_:
			printerr("未知のmode: %s" % mode)
			quit(2)
			return

	out.close()
	print("done mode=%s seeds=[%d..%d) violations=%d -> %s" % [
		mode, seed_start, seed_start + count, violations, out_path
	])
	quit(0)


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var eq := arg.find("=")
			parsed[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	return parsed
