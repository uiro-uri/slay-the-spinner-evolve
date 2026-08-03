extends SceneTree

## 決戦の土俵の広さを振って、ボス戦の密着度と勝率を測る診断(使い捨てではなく常設)。
##
##   godot --headless --path godot --script res://playtest/measure_boss_arena.gd -- [--count=400]
##
## 動機: 決戦だけ被弾数が桁違いに多い。ボスの半径は自機の2.6倍あるのに、決戦の
## 土俵(八角形)は全土俵で最も内接半径が小さい。「触れずにいられる隙間」がどれだけ
## 残っているかを幾何で出し、実際に解いた勝率・被弾数と並べる。

const SPAWN_RING := 4.0
const SPAWN_SPREAD_DEG := 30.0


func _init() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var eq := arg.find("=")
			args[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	var count := int(args.get("count", "400"))
	var policy := LaunchPolicy.by_name(args.get("policy", "intercept"))

	var player := _endgame_player()
	print("# 決戦の土俵の広さ診断 (発射=%s, count=%d/条件)" % [LaunchPolicy.NAMES[policy], count])
	print("# 自機: mass=%.2f radius=%.2f rps=%.1f edge=%.2f drill=%.2f" % [
		player.mass, player.radius, player.rps, player.edge, player.drill])

	print("\n## 段別の土俵の内接半径と「触れずにいられる隙間」")
	print("| 段 | 敵Lv | 敵半径(最大) | 土俵の内接半径 | 隙間 |")
	print("|---|---|---|---|---|")
	for step in range(1, 10):
		var level := EnemyRoster.level_for_step(step)
		var biggest := 0.0
		for enemy in EnemyRoster.of_level(level):
			biggest = maxf(biggest, enemy.stats.radius)
		var field := FieldRoster.pick_for_step(step, _rng(step))
		var inner := _inradius(field)
		print("| %d | %d | %.2f | %.2f | %.2f |" % [
			step, level, biggest, inner, inner - biggest - player.radius])

	print("\n## ボス戦: 土俵の一辺を振る (八角形・傾斜はFIELD_ARENAのまま)")
	print("| 一辺 | 内接半径 | 隙間 | 勝率 | 決着中央値 | 被弾中央値 | 被弾/秒 | 自分の喪失 削り/壁 |")
	print("|---|---|---|---|---|---|---|---|")
	for side in [10.0, 11.0, 12.0, 13.0, 14.0]:
		_row(side, count, policy, player)
	quit(0)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## 土俵の内接半径(中心から壁までの最短距離)。
func _inradius(field: FieldData) -> float:
	return ArenaWall.inradius_for(field.wall_shape, field.arena_bounds)


## コールドプレイが決戦まで持ち込んだ実際のビルド。
func _endgame_player() -> SpinnerStats:
	var stats := SpinnerStats.default_player()
	stats.mass = 2.5
	stats.rps = 40.0
	stats.spin_decay = 0.92
	stats.wall_keep = 0.17
	stats.hit_guard = 0.17
	stats.edge = 0.40
	stats.drill = 0.50
	return stats


func _boss_field(side: float) -> FieldData:
	var base := FieldRoster.pick_for_step(9)
	var bounds := Rect2(Vector2.ZERO, Vector2(side, side))
	return FieldData.make(
		base.title_key, bounds, base.wall_shape, base.stage_shape,
		base.stage_strength, base.obstacles)


func _row(side: float, count: int, policy: LaunchPolicy.Kind, player: SpinnerStats) -> void:
	var field := _boss_field(side)
	var bosses := EnemyRoster.of_level(5)
	var wins := 0
	var times := PackedFloat32Array()
	var hits := PackedFloat32Array()
	var drain := 0.0
	var wall := 0.0
	for i in count:
		var enemies: Array[EnemyData] = [bosses[i % bosses.size()]]
		var rec := BattleSim.play_one(i, enemies, policy, player.duplicate_stats(), null, field)
		if rec["win"]:
			wins += 1
		times.append(rec["finish_time"])
		hits.append(rec["hits_taken"])
		var loss: Dictionary = rec["player_rps_loss"]
		drain += loss["drain"]
		wall += loss["wall"]
	var inner := _inradius(field)
	var med_t := _median(times)
	print("| %.0f | %.2f | %.2f | %5.1f%% | %.2fs | %.0f | %.2f | %.1f/%.1f |" % [
		side, inner, inner - 1.8 - player.radius, 100.0 * wins / count,
		med_t, _median(hits), _median(hits) / maxf(med_t, 0.001),
		drain / count, wall / count])


func _median(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := Array(values)
	sorted.sort()
	return sorted[sorted.size() / 2]
