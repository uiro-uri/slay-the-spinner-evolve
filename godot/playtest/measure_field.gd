extends SceneTree

## 土俵(FIELD_*)が勝敗にどれだけ効いているかを測る診断。
##
##   godot --headless --path godot --script res://playtest/measure_field.gd -- [--count=500]
##
## 動機: run_sim は土俵を毎戦ランダムに選ぶので、統計はいつも6つの土俵の**平均**に
## なっていて、「どの土俵が難しいか」は一度も分けて出ていなかった。マップのノードは
## 土俵の外周形状(矩形/八角/円)で描かれる一方、傾斜の強さと**柱**は入場するまで
## 見えない——見えない差がどれだけ大きいかを、敵とシードを揃えて土俵だけ振って測る。
##
## 出力は土俵×敵レベルの 勝率 / 平均決着 / 自機の壁ヒット回数 / rps喪失の内訳。
## 自機は既定ステータス固定・発射方針も固定なので、行の差は土俵の差だけになる。

const LEVELS := [1, 2, 3, 4]


func _init() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var eq := arg.find("=")
			args[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	var count := int(args.get("count", "500"))
	var policy := LaunchPolicy.by_name(args.get("policy", "intercept"))

	print("# 土俵別の成績 (方針=%s, 各セル%d戦)" % [LaunchPolicy.NAMES[policy], count])
	print("# 自機は既定ステータス固定・満引き。シードは土俵間で共通＝同じ敵に土俵だけ差し替える。")
	print("")
	print("| 土俵 | 傾斜 | 形 | 柱 | Lv | 勝率 | 平均決着 | 自機の壁回数 | 自機 削り/壁/減衰 |")
	print("|---|---|---|---|---|---|---|---|---|")
	for field in FieldRoster.all():
		for level in LEVELS:
			_row(field, level, count, policy)
	quit(0)


func _row(field: FieldData, level: int, count: int, policy: LaunchPolicy.Kind) -> void:
	var pool := EnemyRoster.of_level(level)
	if pool.is_empty():
		return

	var wins := 0
	var finish := 0.0
	var wall_hits := 0.0
	var drain := 0.0
	var wall := 0.0
	var decay := 0.0
	for i in count:
		var enemies: Array[EnemyData] = [pool[i % pool.size()]]
		var record := BattleSim.play_one(
			i, enemies, policy, SpinnerStats.default_player(), null, field
		)
		if record["win"]:
			wins += 1
		finish += record["finish_time"]
		var loss: Dictionary = record["player_rps_loss"]
		wall_hits += loss["wall_hits"]
		drain += loss["drain"]
		wall += loss["wall"]
		decay += loss["decay"]

	var total := maxf(drain + wall + decay, 0.001)
	print("| %s | %.1f | %s | %d | %d | %.1f%% | %.2fs | %.2f | %d%% / %d%% / %d%% |" % [
		field.title_key,
		field.stage_strength,
		"すり鉢" if field.stage_shape == SpinnerPhysics.StageShape.DISH else "円錐",
		field.obstacles.size(),
		level,
		100.0 * wins / count,
		finish / count,
		wall_hits / count,
		roundi(100.0 * drain / total),
		roundi(100.0 * wall / total),
		roundi(100.0 * decay / total),
	])
