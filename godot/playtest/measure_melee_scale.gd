extends SceneTree

## 乱戦(複数体)の**リスクとリターンの釣り合い**を測る診断。
##
##   godot --headless --path godot --script res://playtest/measure_melee_scale.gd -- [--count=400]
##
## 動機: 乱戦は「倒した頭数だけ報酬が選べる(レア重みも頭数倍)」代わりに手強い、という
## **選べるリスク**の設計になっている。ところが measure_group_size.gd が出した勝率は
## Lv1〜2で 98.8〜100%(頭数によらず)、Lv3で 91.2% → 24.8% → 8.2%。
## 期待値(報酬枚数 × 勝率)で見ると
##   Lv2: 1.00 / 2.00 / 2.96(頭数を増やすほど得＝ただの上位互換)
##   Lv3: 0.91 / 0.50 / 0.25(頭数を増やすほど損＝ただの罠)
## で、**どの段でも「選ぶ」意味が無い**。序盤は取らない理由が無く、中盤以降は取る理由が無い。
##
## この診断は、乱戦のメンバーだけ**質量に倍率**を掛けたときに勝率と期待値がどう動くかを
## 掃引する。質量を選ぶ理由:
##  - 被削りは相手の質量に**比例**し、与削りは相手の硬さ(質量×半径²)に**反比例**するので、
##    頭数が増えたぶんの「殴られる回数」を1回あたりの軽さで相殺できる。
##  - **寿命(rps÷(半径×spin_decay))は質量を含まない**ので、かつて撤廃された
##    「rpsの頭数割り」(EnemyRoster参照)と違って自滅待ちの受け身支配を呼び戻さない。
##  - 1撃死も戻らない: 与削りには `capped_spin_drain`(相手ゲージの50%)の天井があり、
##    質量を下げても1衝突で倒せるようにはならない。
##
## 掃引する倍率は `count^-exp` の形(1体は必ず1.00)。exp=0 が現行。

const LEVELS := [2, 3]
const SIZES := [1, 2, 3]
const EXPONENTS := [0.0, 0.25, 0.35, 0.5, 0.65, 0.8]


func _init() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var eq := arg.find("=")
			args[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	var count := int(args.get("count", "400"))
	var policy := LaunchPolicy.by_name(args.get("policy", "intercept"))
	var build := String(args.get("build", "mid"))

	print("# 乱戦メンバーの質量倍率の掃引 (方針=%s, 自機=%s, 各セル%d戦)" % [
		LaunchPolicy.NAMES[policy], build, count
	])
	print("# 倍率 = 頭数^-exp。exp=0.00 が現行(据え置き)。1体の行は掃引しても不変。")
	print("# 期待値 = 報酬枚数(=頭数) × 勝率。頭数を跨いでほぼ横並びなら「選べる」。")
	print("")
	for level in LEVELS:
		print("## Lv%d" % level)
		print("")
		print("| exp | 倍率(2体/3体) | 1体 | 2体 | 3体 | 期待値 1/2/3体 |")
		print("|---|---|---|---|---|---|")
		for exp in EXPONENTS:
			_row(level, exp, count, policy, build)
		print("")
	quit(0)


## 自機。measure_group_size.gd の mid と同じ中盤ビルド(比較できるように揃える)。
func _player(build: String) -> SpinnerStats:
	var stats := SpinnerStats.default_player()
	if build != "mid":
		return stats
	stats.mass = 1.95
	stats.rps = 28.9
	stats.edge = 0.20
	stats.drill = 0.25
	return stats


func _row(level: int, exp: float, count: int, policy: LaunchPolicy.Kind, build: String) -> void:
	var rates: Array[float] = []
	for size in SIZES:
		rates.append(_win_rate(level, size, exp, count, policy, build))
	print("| %.2f | %.2f / %.2f | %.1f%% | %.1f%% | %.1f%% | %.2f / %.2f / %.2f |" % [
		exp,
		pow(2.0, -exp), pow(3.0, -exp),
		100.0 * rates[0], 100.0 * rates[1], 100.0 * rates[2],
		1.0 * rates[0], 2.0 * rates[1], 3.0 * rates[2],
	])


func _win_rate(
	level: int, size: int, exp: float, count: int, policy: LaunchPolicy.Kind, build: String
) -> float:
	var pool := EnemyRoster.of_level(level)
	if pool.is_empty():
		return 0.0
	var scale := pow(float(size), -exp)
	var player := _player(build)
	var wins := 0
	for i in count:
		# measure_group_size.gd と同じ引き方(頭数を跨いで顔ぶれが揃う)。
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		var enemies: Array[EnemyData] = []
		for _k in size:
			var picked: EnemyData = pool[rng.randi_range(0, pool.size() - 1)]
			enemies.append(_scaled(picked, scale))
		if BattleSim.play_one(i, enemies, policy, player)["win"]:
			wins += 1
	return float(wins) / count


## 質量だけ倍率を掛けた複製。同じ個体が群に2度入りうるので必ず複製する。
func _scaled(data: EnemyData, scale: float) -> EnemyData:
	if is_equal_approx(scale, 1.0):
		return data
	var stats := data.stats.duplicate_stats()
	stats.mass *= scale
	return EnemyData.make(data.level, data.display_name, stats)
