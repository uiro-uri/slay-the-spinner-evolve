extends SceneTree

## 「勝敗を決めているのは壁か、削りか」を段ごとに数える計測スクリプト。
##
## rpsの喪失には3つの機構がある: 削り(コマ同士の衝突)・壁(壁と柱)・自然減衰。
## このうち壁だけが「現在rpsへの乗算」なので、rpsを積んだ後半ほど1回の壁が高くつく。
## その偏りを実際のラン進行(RunSim)で測る。
##
##   godot --headless --path godot --script res://playtest/measure_wall_share.gd -- --runs=300
##
## 出力は段ごとの「自分/敵のrps喪失に壁が占める割合」と敗者の死因分布。

const STEPS := 9


func _init() -> void:
	var runs := 300
	var seed_base := 90000
	var overrides: BattleSim.Overrides = null
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--runs="):
			runs = int(arg.split("=")[1])
		elif arg.begins_with("--seed="):
			seed_base = int(arg.split("=")[1])
		elif arg.begins_with("--wallabs="):
			if overrides == null:
				overrides = BattleSim.Overrides.new()
			overrides.wall_absolute_share = float(arg.split("=")[1])
		elif arg.begins_with("--violence="):
			if overrides == null:
				overrides = BattleSim.Overrides.new()
			overrides.violence = float(arg.split("=")[1])
		elif arg.begins_with("--emass="):
			if overrides == null:
				overrides = BattleSim.Overrides.new()
			overrides.enemy_mass_scale = float(arg.split("=")[1])
		elif arg.begins_with("--erps="):
			if overrides == null:
				overrides = BattleSim.Overrides.new()
			overrides.enemy_rps_scale = float(arg.split("=")[1])
		elif arg.begins_with("--decay="):
			if overrides == null:
				overrides = BattleSim.Overrides.new()
			overrides.natural_damping = float(arg.split("=")[1])

	# 段ごとの累計。[0]は未使用(段は1始まり)。
	var mine := []
	var theirs := []
	var causes := []
	for _i in STEPS + 1:
		mine.append({"drain": 0.0, "wall": 0.0, "decay": 0.0, "hits": 0.0, "n": 0})
		theirs.append({"drain": 0.0, "wall": 0.0, "decay": 0.0, "hits": 0.0, "n": 0})
		causes.append({"drain": 0, "wall": 0, "decay": 0, "none": 0})

	var cleared := 0
	var total_time := 0.0
	var total_battles := 0
	for i in runs:
		var run := RunSim.play_one(
			seed_base + i, LaunchPolicy.Kind.INTERCEPT, RunSim.RewardPolicy.GREEDY, overrides
		)
		if run.get("cleared", false):
			cleared += 1
		for b in run.get("battles", []):
			var step: int = b["step"]
			if step < 1 or step > STEPS:
				continue
			total_time += float(b.get("finish_time", 0.0))
			total_battles += 1
			_add(mine[step], b.get("player_rps_loss", {}))
			for e in b.get("enemy_rps_loss", []):
				_add(theirs[step], e)
			var cause: String = b.get("death_cause", "none")
			if not causes[step].has(cause):
				cause = "none"
			causes[step][cause] += 1

	print("runs=%d seed_base=%d cleared=%.1f%% 平均決着=%.2fs" % [
		runs, seed_base, cleared * 100.0 / runs,
		total_time / maxf(total_battles, 1.0),
	])
	print("段 | 自分: 壁割合 削り 壁 減衰 (壁回数/戦) | 敵: 壁割合 削り 壁 減衰 | 敗者死因 drain/wall/decay")
	var all_mine := {"drain": 0.0, "wall": 0.0, "decay": 0.0, "hits": 0.0, "n": 0}
	var all_theirs := {"drain": 0.0, "wall": 0.0, "decay": 0.0, "hits": 0.0, "n": 0}
	for step in range(1, STEPS + 1):
		var m: Dictionary = mine[step]
		var th: Dictionary = theirs[step]
		for k in m:
			all_mine[k] += m[k]
			all_theirs[k] += th[k]
		print(
			"%d | %5.1f%% %6.1f %6.1f %6.1f (%4.1f) | %5.1f%% %6.1f %6.1f %6.1f | %d/%d/%d"
			% [
				step, _share(m) * 100.0, _avg(m, "drain"), _avg(m, "wall"), _avg(m, "decay"),
				_avg(m, "hits"),
				_share(th) * 100.0, _avg(th, "drain"), _avg(th, "wall"), _avg(th, "decay"),
				causes[step]["drain"], causes[step]["wall"], causes[step]["decay"],
			]
		)
	print("全段 自分 壁割合=%.1f%%  敵 壁割合=%.1f%%" % [
		_share(all_mine) * 100.0, _share(all_theirs) * 100.0
	])
	quit()


func _add(acc: Dictionary, loss: Dictionary) -> void:
	if loss.is_empty():
		return
	acc["drain"] += float(loss.get("drain", 0.0))
	acc["wall"] += float(loss.get("wall", 0.0))
	acc["decay"] += float(loss.get("decay", 0.0))
	acc["hits"] += float(loss.get("wall_hits", 0))
	acc["n"] += 1


func _share(acc: Dictionary) -> float:
	var total: float = acc["drain"] + acc["wall"] + acc["decay"]
	if total <= 0.0:
		return 0.0
	return acc["wall"] / total


func _avg(acc: Dictionary, key: String) -> float:
	if acc["n"] == 0:
		return 0.0
	return acc[key] / float(acc["n"])
