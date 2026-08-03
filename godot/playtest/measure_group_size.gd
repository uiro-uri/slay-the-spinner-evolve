extends SceneTree

## 乱戦の**頭数**が勝敗にどれだけ効いているかを測る診断。
##
##   godot --headless --path godot --script res://playtest/measure_group_size.gd -- [--count=500]
##
## 動機: マップの脅威メーターは `StatReadout.toughness_share` = **群のうち最大の硬さ**の
## 取り分なので、同じレベルなら1体でも3体でも**同じ値**を出す。頭数はピップで別に
## 描かれてはいるが、「格上/格下」という判定を下しているのはメーターの側で、そこに
## 頭数が一切入っていない。実際に頭数がどれだけ勝率を動かすのかを、敵レベル・自機・
## シードを揃えて頭数だけ振って測る。
##
## 出力はレベル×頭数の 勝率 / 平均決着 / 自機の壁ヒット回数 / rps喪失の内訳、
## そして現行の脅威メーターがその行に出す取り分。
##
## `--build=mid` は素の自機だとLv3以降が全滅(0%)で頭数の差が床に潰れるため、
## 中盤で実際に組めるビルド(コールドプレイ 2026-08-03 の段5時点)を使う。

const LEVELS := [1, 2, 3, 4]
const SIZES := [1, 2, 3]


func _init() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var eq := arg.find("=")
			args[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	var count := int(args.get("count", "500"))
	var policy := LaunchPolicy.by_name(args.get("policy", "intercept"))
	var build := String(args.get("build", "default"))

	print("# 頭数別の成績 (方針=%s, 自機=%s, 各セル%d戦)" % [
		LaunchPolicy.NAMES[policy], build, count
	])
	print("# 自機は固定・満引き・土俵固定。シードは頭数間で共通。")
	print("# 「現行メーター」は StatReadout.toughness_share = 群の最大硬さの取り分。")
	print("")
	print("| Lv | 頭数 | 勝率 | 平均決着 | 自機の壁回数 | 自機 削り/壁/減衰 | 現行メーター |")
	print("|---|---|---|---|---|---|---|")
	for level in LEVELS:
		for size in SIZES:
			_row(level, size, count, policy, build)
	quit(0)


## 自機。default=素、mid=中盤の実ビルド(質量↑・回転↑・EDGE/DRILL1枚ずつ)。
func _player(build: String) -> SpinnerStats:
	var stats := SpinnerStats.default_player()
	if build != "mid":
		return stats
	stats.mass = 1.95
	stats.rps = 28.9
	stats.edge = 0.20
	stats.drill = 0.25
	return stats


func _row(level: int, size: int, count: int, policy: LaunchPolicy.Kind, build: String) -> void:
	var pool := EnemyRoster.of_level(level)
	if pool.is_empty():
		return

	var player := _player(build)
	var wins := 0
	var finish := 0.0
	var wall_hits := 0.0
	var drain := 0.0
	var wall := 0.0
	var decay := 0.0
	var share := 0.0
	for i in count:
		# 頭数を跨いで同じ敵の並びを使う(3体の先頭2体が2体戦の顔ぶれ)。
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		var enemies: Array[EnemyData] = []
		for _k in size:
			# 乱戦の質量倍率(EnemyRoster.melee_mass_scale)を通す。素の表から組むと
			# 実プレイに存在しない相手を測ることになり、数字だけが嘘になる。
			enemies.append(EnemyRoster.melee_member(pool[rng.randi_range(0, pool.size() - 1)], size))
		var record := BattleSim.play_one(i, enemies, policy, player)
		if record["win"]:
			wins += 1
		finish += record["finish_time"]
		var loss: Dictionary = record["player_rps_loss"]
		wall_hits += loss["wall_hits"]
		drain += loss["drain"]
		wall += loss["wall"]
		decay += loss["decay"]
		share += ThreatMeter.share(player, enemies)

	var total := maxf(drain + wall + decay, 0.001)
	print("| %d | %d体 | %.1f%% | %.2fs | %.2f | %d%% / %d%% / %d%% | %.2f |" % [
		level,
		size,
		100.0 * wins / count,
		finish / count,
		wall_hits / count,
		roundi(100.0 * drain / total),
		roundi(100.0 * wall / total),
		roundi(100.0 * decay / total),
		share / count,
	])
