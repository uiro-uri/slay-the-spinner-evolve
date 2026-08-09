extends SceneTree

## 発射前の先読み(RendezvousPreview)が**引き量ごとにどれだけ無言になるか**を測る診断。
##
##   godot --headless --path godot --script res://playtest/measure_lead_cut.gd -- [--count=400]
##
## 動機(コールドプレイ 2026-08-06): 満引き(force=1.0)で段1〜6を勝ち上がったあと、
## 段7(Lv4 2体・FIELD_PLATE)で満引きのまま2連敗し、3回目に force=0.2 で撃って勝った。
## journal に4サイクル連続で載っている「force を初見が逆に学習する」の5回目。
##
## 先読みは「壁か柱へ届いた時点で打ち切る」ので、強く引くほど**相手に届く前に
## 打ち切られる**はず——つまり満引きの罰が現れる場所で、先読みが一番黙る。
## ここではその相関を数える: 引き量ごとに、先読みが打ち切られた割合と、
## その内訳(自分が先に届いた/相手が先に届いた/両者)。
##
## 「自分が先に届いた」が引き量とともに伸びるなら、打ち切りを画面に出すことは
## そのまま「引きすぎ」の警告になる。逆に「相手が先に届いた」は引き量にあまり
## 依らないはずで、こちらは待てば跳ね返って噛み合う形＝別の合図になる。

const FORCES := [0.20, 0.40, 0.60, 0.80, 1.00]
const STEPS := [1, 3, 5, 7, 8]
const SPAWN_RING := 4.0
const SPAWN_SPREAD_DEG := 30.0
const SPAWN_SWIRL_DEG := EnemySpawn.DEFAULT_SWIRL_DEG


func _init() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var eq := arg.find("=")
			args[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	var count := int(args.get("count", "400"))
	var seed_base := int(args.get("seed", "91000"))
	var policy := LaunchPolicy.by_name(args.get("policy", "intercept"))

	print("# 先読みの打ち切り率 (方針=%s, 各セル%d件)" % [LaunchPolicy.NAMES[policy], count])
	print("# 打ち切り = 相手へ届く前にどちらかが壁か柱に着き、先読みがそこで終わること。")
	print("# シードは引き量の間で共通＝同じ湧きに対して引きだけを変える。")
	print("")
	print("| 段 | 自機半径 | 引き | 初速 | 噛み合う予告 | 打ち切り | うち自分 | うち相手 | うち両者 |")
	print("|---|---|---|---|---|---|---|---|---|")
	for step in STEPS:
		for force in FORCES:
			_row(step, force, count, seed_base, policy)
	quit(0)


## 段ごとの自機半径の目安。素0.70から始まり、巨大化(直径×1.25、上限1.05)を
## 中盤までに2枚積む——2026-08-05 サイクルで上限を2枚ぶんに締めた後の伸び方。
func _player_radius(step: int) -> float:
	if step <= 2:
		return 0.70
	if step <= 4:
		return 0.88
	return 1.05


func _row(step: int, force: float, count: int, seed_base: int, policy: LaunchPolicy.Kind) -> void:
	var prad := _player_radius(step)
	var stats := SpinnerStats.default_player()
	stats.radius = prad

	var contact := 0
	var cut := 0
	var cut_mine := 0
	var cut_theirs := 0
	var cut_both := 0

	for i in count:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_base + step * 1000 + i
		var field := FieldRoster.pick_for_step(step, rng)
		var enemies := EnemyRoster.pick_group_for_step(step, rng)

		var plans: Array[EnemySpawn.Plan] = []
		var radii := PackedFloat32Array()
		var group := EnemySpawn.Group.new()
		var swirl := EnemySpawn.group_swirl_deg(enemies.size(), SPAWN_SWIRL_DEG, rng)
		for e in enemies:
			var plan := EnemySpawn.plan(
				field.center(), SPAWN_RING, LaunchSpeed.random(rng, e.stats.radius),
				SPAWN_SPREAD_DEG, rng, e.stats.radius, field.inradius(),
				group.avoid(), group.min_gap(e.stats.radius), field.obstacles, swirl
			)
			group.add(plan.position, e.stats.radius)
			plans.append(plan)
			radii.append(e.stats.radius)

		# 発射はボットと同じ規則で決める(引き量だけを振る)。
		var launch := LaunchPolicy.decide(policy, field, prad, plans, radii, rng, force)

		var results: Array[Dictionary] = []
		for k in enemies.size():
			results.append(RendezvousPreview.closest_approach(
				launch.position, launch.velocity, stats,
				plans[k].position, plans[k].velocity, enemies[k].stats,
				field.center(), field.stage_strength, field.stage_shape,
				field.walls(), field.obstacles
			))
		# 実UIが輪で見せる1件だけを数える(乱戦でも画面に出るのは1つ)。
		var index := RendezvousPreview.primary_index(results)
		if index < 0:
			continue
		var lead: Dictionary = results[index]
		if bool(lead["contact"]):
			contact += 1
			continue
		if not bool(lead["cut_short"]):
			continue
		cut += 1
		var mine := RendezvousPreview.cut_player(lead)
		var theirs := RendezvousPreview.cut_enemy(lead)
		if mine and theirs:
			cut_both += 1
		elif mine:
			cut_mine += 1
		else:
			cut_theirs += 1

	var n := float(count)
	print("| %d | %.2f | %.2f | %.1f | %.1f%% | %.1f%% | %.1f%% | %.1f%% | %.1f%% |" % [
		step, prad, force, LaunchSpeed.MAX * force,
		100.0 * contact / n, 100.0 * cut / n,
		100.0 * cut_mine / n, 100.0 * cut_theirs / n, 100.0 * cut_both / n,
	])
