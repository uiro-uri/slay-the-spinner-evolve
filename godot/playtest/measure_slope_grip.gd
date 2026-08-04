extends SceneTree

## 自機の**傾斜の効き**(`SpinnerStats.slope_grip`)を1.0未満まで振って、
## 「離れて待つ」が戦術として成立するかを測る診断。
##
##   godot --headless --path godot --script res://playtest/measure_slope_grip.gd -- [--count=400]
##
## 動機: 2026-08-03 と 2026-08-04 のコールドプレイが2サイクル続けて同じことを書いた
## ——低出力で土俵の端に置いても、傾斜に中央へ引き戻されて結局は密着の殴り合いに
## なる。決着は「先に回転が尽きた方が負け」で自然減衰でも決まるのだから、寿命で
## 勝っている相手からは逃げ切れてよいはずなのに、**距離を取るという選択肢が物理的に
## 存在しない**。既存の低重心(GRIP, id=14)は傾斜を**強める**方向しかなく、逆向きの札は
## 無い。
##
## そこで grip を下げると何が起きるかを、敵・土俵・シードを揃えて grip だけ振って測る。
## 引き量(フォース)も併せて振るのは、「弱く撃って離れる」が実プレイヤーの取る手で、
## 満引き固定のままでは待ちの成否が統計に一度も現れないため
## (measure_launch_force.gd と同じ理由)。
##
## 出力は grip × 引き量の 勝率 / 平均決着 / 平均衝突回数 / 自機の rps 喪失内訳。
## **衝突回数が減り、減衰の取り分が増える**なら「離れて待つ」が効いている証拠になる。

const GRIPS := [0.4, 0.6, 0.8, 1.0, 1.4]
const FORCES := [1.0, 0.25]
const LEVELS := [1, 3, 5]


func _init() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var eq := arg.find("=")
			args[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	var count := int(args.get("count", "400"))
	var policy := LaunchPolicy.by_name(args.get("policy", "intercept"))

	print("# 傾斜の効き(slope_grip)別の成績 (方針=%s, 各セル%d戦)" % [
		LaunchPolicy.NAMES[policy], count
	])
	print("# 自機は素の初期性能から grip だけ差し替え。シードは grip 間で共通。")
	print("# 引き量1.00=満引き(従来)、0.25=弱く撃って離れる手。")
	print("")
	print("| Lv | grip | 引き量 | 勝率 | 平均決着 | 平均衝突 | 自機 削り/壁/減衰 |")
	print("|---|---|---|---|---|---|---|")
	for level in LEVELS:
		for grip in GRIPS:
			for force in FORCES:
				_row(level, grip, force, count, policy)
	quit(0)


func _row(level: int, grip: float, force: float, count: int, policy: LaunchPolicy.Kind) -> void:
	var pool := EnemyRoster.of_level(level)
	var stats := SpinnerStats.default_player()
	stats.slope_grip = grip
	var overrides := BattleSim.Overrides.new()
	overrides.launch_force_scale = force

	var wins := 0
	var finish := 0.0
	var impacts := 0.0
	var drain := 0.0
	var wall := 0.0
	var decay := 0.0
	for i in count:
		var pick_rng := RandomNumberGenerator.new()
		pick_rng.seed = i
		var enemies: Array[EnemyData] = [pool[pick_rng.randi_range(0, pool.size() - 1)]]
		var record := BattleSim.play_one(i, enemies, policy, stats, overrides)
		if record["win"]:
			wins += 1
		finish += float(record["finish_time"])
		impacts += float(record["impacts"])
		var loss: Dictionary = record["player_rps_loss"]
		drain += float(loss.get("drain", 0.0))
		wall += float(loss.get("wall", 0.0))
		decay += float(loss.get("decay", 0.0))

	var total := maxf(drain + wall + decay, 0.0001)
	print("| %d | %.1f | %.2f | %.1f%% | %.2fs | %.1f | %d%% / %d%% / %d%% |" % [
		level, grip, force,
		float(wins) / float(count) * 100.0,
		finish / float(count),
		impacts / float(count),
		roundi(drain / total * 100.0),
		roundi(wall / total * 100.0),
		roundi(decay / total * 100.0),
	])
