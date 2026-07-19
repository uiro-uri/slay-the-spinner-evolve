extends SceneTree

## 全敵の「自滅」度合いを測る診断。ボスで得た知見(高速発射だと壁に突撃して
## rpsを壁で失い自滅する＝戦闘でなく自滅レースになる)を一般ステージへ展開する。
##
##   godot --headless --path godot --script res://playtest/measure_selfdestruct.gd -- [--count=1500] [--speed-scale=1.0]
##
## 各敵を素の初期性能プレイヤーと戦わせ、敵がrpsを削り(drain)/壁(wall)/自然減衰
## (decay)のどの割合で失うかを出す。壁+減衰が高い＝プレイヤーの手を借りず自滅
## している＝発射が速すぎる/軌道が悪い兆候。発射速度はいまは自機と共通のレンジ
## (LaunchSpeed)から抽選するので、ここでは上限(LaunchSpeed.MAX)を基準にし、
## --speed-scaleでそれを一律倍して、下げると自滅(特に壁)が減るかを見る。

const SPAWN_RING := 4.0
const SPAWN_SPREAD_DEG := 30.0


func _init() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var eq := arg.find("=")
			args[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	var count := int(args.get("count", "1500"))
	var policy := LaunchPolicy.by_name(args.get("policy", "intercept"))
	var speed_scale := float(args.get("speed-scale", "1.0"))

	print("# 全敵の自滅度合い (発射=%s, count=%d, speed_scale=%.2f)" % [
		LaunchPolicy.NAMES[policy], count, speed_scale])
	print("# 敵がrpsを失う割合。壁+減衰が高い=プレイヤーの手を借りず自滅。")
	print("| 敵 | Lv | 速度 | 勝率 | 被ダメ割合 削り/壁/減衰 |")
	print("|---|---|---|---|---|")
	for level in [1, 2, 3, 4, 5]:
		for enemy in EnemyRoster.of_level(level):
			# 共通レンジの上限を基準に、speed_scaleで振る。
			var speed := LaunchSpeed.MAX * speed_scale
			var e := EnemyData.make(level, enemy.display_name, enemy.stats.duplicate_stats())
			var wins := 0
			var drain := 0.0
			var wall := 0.0
			var decay := 0.0
			for i in count:
				var r := _resolve(e, speed, SpinnerStats.default_player(), policy, i)
				if r["win"]:
					wins += 1
				drain += r["drain"]
				wall += r["wall"]
				decay += r["decay"]
			var total := drain + wall + decay
			var prop := "n/a"
			if total > 0.0:
				prop = "%.0f%% / %.0f%% / %.0f%%" % [
					100.0 * drain / total, 100.0 * wall / total, 100.0 * decay / total]
			print("| %s | %d | %.1f | %.1f%% | %s |" % [
				enemy.display_name, level, speed, 100.0 * wins / count, prop])
	quit(0)


func _resolve(enemy: EnemyData, speed: float, player_stats: SpinnerStats, policy: LaunchPolicy.Kind,
		seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var field := BattleSim.default_field()

	var request := BattleRequest.new()
	request.arena_bounds = field.arena_bounds
	request.wall_shape = field.wall_shape
	request.obstacles = field.obstacles
	request.stage_strength = field.stage_strength
	request.stage_shape = field.stage_shape

	var plan := EnemySpawn.plan(
		field.center(), SPAWN_RING, speed, SPAWN_SPREAD_DEG,
		rng, enemy.stats.radius, field.inradius())
	var launch := LaunchPolicy.decide(policy, field, player_stats.radius, plan, rng)
	request.player = BattleRequest.Launch.new(player_stats, launch.position, launch.velocity)
	request.enemies = [BattleRequest.Launch.new(enemy.stats, plan.position, plan.velocity)]

	var result := BattleResolver.resolve(request)
	var breakdown := _enemy_damage(request, result, enemy.stats)
	breakdown["win"] = result.player_won()
	return breakdown


## 敵(enemy_tracks[0])のrps喪失を drain/wall/decay に分解する(measure_boss_launchと同じ)。
func _enemy_damage(request: BattleRequest, result: BattleResult,
		enemy_stats: SpinnerStats) -> Dictionary:
	var track: Array = result.enemy_tracks[0]
	var dt := request.time_step
	var thr := request.lose_threshold
	var decay_step := enemy_stats.radius * request.natural_damping * enemy_stats.spin_decay * dt

	var init_rps: float = track[0].rps
	var final_rps: float = track[track.size() - 1].rps

	var alive_steps := 0
	for i in track.size():
		if track[i].rps <= thr:
			break
		alive_steps += 1
	var decay_total := decay_step * alive_steps

	var player_track: Array = result.player_frames
	var wall_total := 0.0
	for imp in result.wall_impacts:
		var frame := int(round(imp.time / dt))
		if frame < 0 or frame >= track.size():
			continue
		var enemy_pos: Vector2 = track[frame].position
		var player_pos: Vector2 = player_track[frame].position if frame < player_track.size() else Vector2.INF
		if imp.point.distance_to(enemy_pos) <= imp.point.distance_to(player_pos):
			wall_total += track[frame].rps * (1.0 - request.wall_damping)

	var total_loss := maxf(init_rps - final_rps, 0.0)
	var drain_total := maxf(total_loss - decay_total - wall_total, 0.0)
	return {"drain": drain_total, "wall": wall_total, "decay": minf(decay_total, total_loss)}
