extends SceneTree

## 発射の「フォース(引き量)」を振って、勝率と自機のrps喪失内訳がどう動くかを測る診断。
##
##   godot --headless --path godot --script res://playtest/measure_launch_force.gd -- [--count=300]
##
## 動機: ボットの狙う方針(AIM_CENTER/AIM_SPAWN/INTERCEPT)はどれも満引き固定なので、
## 「どれくらいの力で撃つか」という実プレイヤーの選択が統計に一度も現れていなかった。
## コールドプレイでは満引きが壁で自滅し、半分ほどの引きが安定して勝つ手触りだったので、
## その手触りが統計に出るかを確かめる。
##
## 出力は段(=敵レベル)ごとの、フォース別の 勝率 / 自機の壁ヒット回数 / rps喪失の内訳。
## 壁の取り分がフォースに比例して伸びるなら、満引きは「壁への突撃」で、
## LaunchSpeed が大型の敵にだけ敷いている上限が自機に無いのと同じ問題になる。

const FORCES := [0.15, 0.30, 0.45, 0.60, 0.75, 1.00]
const LEVELS := [1, 2, 3, 4, 5]


func _init() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var eq := arg.find("=")
			args[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	var count := int(args.get("count", "300"))
	var policy := LaunchPolicy.by_name(args.get("policy", "intercept"))

	print("# 発射フォースのスイープ (方針=%s, 各セル%d戦)" % [LaunchPolicy.NAMES[policy], count])
	print("# 自機は既定ステータス固定。フォース1.00=満引き(=従来のボット)。")

	for level in LEVELS:
		var pool := EnemyRoster.of_level(level)
		if pool.is_empty():
			continue
		print("\n## Lv%d" % level)
		print("| フォース | 初速 | 勝率 | 平均決着 | 自機の壁回数 | 自機 削り/壁/減衰 | 敵が受けた削り |")
		print("|---|---|---|---|---|---|---|")
		for force in FORCES:
			_row(pool, level, count, policy, force)
	quit(0)


func _row(pool: Array[EnemyData], level: int, count: int,
		policy: LaunchPolicy.Kind, force: float) -> void:
	var overrides := BattleSim.Overrides.new()
	overrides.launch_force_scale = force

	var wins := 0
	var finish := 0.0
	var wall_hits := 0.0
	var drain := 0.0
	var wall := 0.0
	var decay := 0.0
	var enemy_drain := 0.0
	for i in count:
		# シードはフォース間で共通。同じ敵の湧きに対して引き量だけを変える。
		var enemies: Array[EnemyData] = [pool[i % pool.size()]]
		var record := BattleSim.play_one(
			i, enemies, policy, SpinnerStats.default_player(), overrides
		)
		if record["win"]:
			wins += 1
		finish += record["finish_time"]
		var loss: Dictionary = record["player_rps_loss"]
		wall_hits += loss.get("wall_hits", 0)
		drain += loss.get("drain", 0.0)
		wall += loss.get("wall", 0.0)
		decay += loss.get("decay", 0.0)
		for entry in record["enemy_rps_loss"]:
			enemy_drain += entry.get("drain", 0.0)

	var total := drain + wall + decay
	var share := "n/a"
	if total > 0.0:
		share = "%.0f%% / %.0f%% / %.0f%%" % [
			100.0 * drain / total, 100.0 * wall / total, 100.0 * decay / total]
	print("| %.2f | %.1f | %.1f%% | %.2fs | %.2f | %s | %.1f |" % [
		force, LaunchSpeed.MAX * force, 100.0 * wins / count, finish / count,
		wall_hits / count, share, enemy_drain / count])
