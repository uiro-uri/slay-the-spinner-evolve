extends SceneTree

## マップの脅威メーターが**どの量で**部屋の危険を測るべきかを比べる診断。
##
##   godot --headless --path godot --script res://playtest/measure_threat_axis.gd -- [--count=120]
##
## 動機: 現行のメーターは `PartPreview.toughness`(硬さ = 質量×半径²)の取り分で、
## **rps を一切読まない**。ところが rps はこのゲームの体力そのもの(先に尽きた方が
## 負ける)なので、硬さが同じでも rps が違えば同じ部屋の勝率は別物になる。
## 実際、素のコマの rps だけを振ると Lv2×2体 の勝率は 34%→99% と動くのに、
## メーターは 0.51 のまま1ミリも動かない。
##
## 比べる2つの量はどちらも既存の定義をそのまま借りる(新しい式を作らない):
##   硬さ       PartPreview.toughness  = 質量 × 半径²
##   打たれ強さ PartPreview.endurance  = rps × 硬さ ÷ (1 − 衝突軽減)
## 打たれ強さは**報酬カードが毎回約束している行**で、doc のとおり
## 「接触に何回耐えられるか」に比例する量——つまり体力に相当する。
##
## 出力は 敵レベル×頭数×自機ビルド のセルごとの 勝率 / 2つの取り分と、
## **メーターとしての正しさ**の要約: 全セル対のうち「メーターは A の方が安全だと
## 言うのに、実測の勝率は A の方が低い」組の割合(=順序の嘘)と、同じ目盛りに
## 見えるセル対(取り分の差が0.02未満)の勝率の開き。

const LEVELS := [1, 2, 3, 4]
const SIZES := [1, 2]
## 自機ビルド(質量, rps)。ラン中に実際に通る範囲を粗く覆う。
## 素のコマは (1.5, 15)。GROWTH を積むと質量が、撃破ボーナスと回転札で rps が伸びる。
const BUILDS := [
	[1.5, 12.0], [1.5, 15.0], [1.5, 20.0], [1.5, 25.0], [1.5, 30.0], [1.5, 36.0],
	[2.2, 15.0], [2.2, 22.0], [2.2, 30.0], [2.2, 38.0],
	[3.0, 18.0], [3.0, 30.0],
]
## 「同じ目盛りに見える」とみなす取り分の差。メーターの幅はノード直径(36px)なので
## 0.02 は 0.7px ——人間には同じ長さにしか見えない。
const SAME_TICK := 0.02


func _init() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var eq := arg.find("=")
			args[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	var count := int(args.get("count", "120"))
	var policy := LaunchPolicy.by_name(args.get("policy", "intercept"))

	print("# 脅威メーターの軸くらべ (方針=%s, 各セル%d戦)" % [LaunchPolicy.NAMES[policy], count])
	print("# 土俵・シードはセル間で共通。自機は満引き固定。")
	print("")
	print("| Lv | 頭数 | 自機(質量/rps) | 勝率 | 硬さ取り分 | 打たれ強さ取り分 |")
	print("|---|---|---|---|---|---|")

	var cells: Array[Dictionary] = []
	for level in LEVELS:
		for size in SIZES:
			for build in BUILDS:
				cells.append(_row(level, size, build[0], build[1], count, policy))

	_summary(cells)
	quit(0)


func _player(mass: float, rps: float) -> SpinnerStats:
	var stats := SpinnerStats.default_player()
	stats.mass = mass
	stats.rps = rps
	return stats


func _row(
	level: int, size: int, mass: float, rps: float, count: int, policy: LaunchPolicy.Kind
) -> Dictionary:
	var pool := EnemyRoster.of_level(level)
	if pool.is_empty():
		return {}

	var player := _player(mass, rps)
	var wins := 0
	var tough := 0.0
	var endure := 0.0
	for i in count:
		# 頭数を跨いで同じ敵の並びを使う(measure_group_size と同じ組み方)。
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		var enemies: Array[EnemyData] = []
		for _k in size:
			enemies.append(EnemyRoster.melee_member(pool[rng.randi_range(0, pool.size() - 1)], size))
		var record := BattleSim.play_one(i, enemies, policy, player)
		if record["win"]:
			wins += 1
		var stats := ThreatMeter.stats_of(enemies)
		tough += StatReadout.toughness_share(player, stats)
		endure += StatReadout.endurance_share(player, stats)

	var cell := {
		"win": float(wins) / count,
		"tough": tough / count,
		"endure": endure / count,
	}
	print("| %d | %d体 | %.1f/%.0f | %.1f%% | %.2f | %.2f |" % [
		level, size, mass, rps, 100.0 * cell["win"], cell["tough"], cell["endure"],
	])
	return cell


## メーターとしての正しさ。**取り分の絶対値そのものではなく順序**を見る——
## プレイヤーが1本のバーから読むのは「隣の部屋よりどれだけ危ないか」だから。
func _summary(cells: Array[Dictionary]) -> void:
	print("")
	print("## メーターとしての正しさ(全セル対で評価)")
	print("| 軸 | 順序の嘘 | 同じ目盛りに見える対 | その対の勝率の開き(平均/最大) |")
	print("|---|---|---|---|")
	_score("硬さ(現行)", cells, "tough")
	_score("打たれ強さ", cells, "endure")


func _score(label: String, cells: Array[Dictionary], key: String) -> void:
	var pairs := 0
	var lies := 0
	var tied := 0
	var tied_gap := 0.0
	var tied_worst := 0.0
	for i in cells.size():
		for j in range(i + 1, cells.size()):
			var a: Dictionary = cells[i]
			var b: Dictionary = cells[j]
			if a.is_empty() or b.is_empty():
				continue
			var d_meter: float = a[key] - b[key]
			var d_win: float = a["win"] - b["win"]
			if absf(d_meter) < SAME_TICK:
				tied += 1
				tied_gap += absf(d_win)
				tied_worst = maxf(tied_worst, absf(d_win))
				continue
			# 勝率が同じ対は順序を問わない(メーターが何を言っても嘘にならない)。
			if absf(d_win) < 0.005:
				continue
			pairs += 1
			# メーターは「大きいほど危ない」。危ない方の勝率が高ければ嘘。
			if (d_meter > 0.0) == (d_win > 0.0):
				lies += 1
	print("| %s | %.1f%% (%d/%d) | %d | %.1fpt / %.1fpt |" % [
		label,
		100.0 * lies / maxi(pairs, 1), lies, pairs,
		tied,
		100.0 * tied_gap / maxi(tied, 1),
		100.0 * tied_worst,
	])
