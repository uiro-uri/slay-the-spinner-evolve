extends SceneTree

## 発射の「立ち位置」を振って、勝率と自機のrps喪失内訳がどう動くかを測る診断。
##
##   godot --headless --path godot --script res://playtest/measure_launch_stance.gd -- [--count=400]
##
## 動機(コールドプレイ 2026-08-08, seed=4821): 9戦を全部同じ一手で勝った——
## 「狙う敵の出現位置の**真反対**のリング点から、満引きで、その敵を狙う」。
## 残機を1つも使わずクリアし、force を落とす理由も角度を変える理由も出てこなかった。
## ところが既存のボット方針は AIM_CENTER も AIM_SPAWN も INTERCEPT も、**立ち位置を
## 一様ランダムで引いている**(LaunchPolicy._ring_position)。狙い(方針)と引き量
## (measure_launch_force)は振れるのに、**立ち位置だけが統計に一度も現れていない**。
##
## report.md のクリア率も measure_* の勝率も、その「誰も取らない立ち方」で測った値
## なので、立ち位置が勝率をどれだけ動かすかは、この診断が出す差そのものになる。
##
## 立ち位置は2自由度ある: **向き**(敵の真反対か同じ側か)と**中心からの距離**。
## 実UI(Battle._clamp_launch)は土俵の内側ならどこへでも置けるのに、ボットも
## コールドプレイCLIも長らく外周リングの1点しか撃てなかった。ここでは両方を振る。
##
## 出力は敵レベルごとの、立ち位置別の 勝率 / 平均決着 / 自機の壁ヒット回数 /
## rps喪失の内訳 / 敵が受けた削り。頭数も振れる(--sizes=1,3)、
## 中心からの距離も振れる(--rings=1.0,0.6,0.2)。
##
## `--build=mid` は素の自機だとLv3以降が床(0%)に潰れて差が読めないため、中盤で
## 実際に組めるビルドを使う(measure_group_size の `_player` と同じ値)。

const STANCES := [
	LaunchPolicy.Stance.RING_NEAR,
	LaunchPolicy.Stance.RING_RANDOM,
	LaunchPolicy.Stance.RING_OPPOSITE,
]
const LEVELS := [1, 2, 3, 4, 5]


func _init() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var eq := arg.find("=")
			args[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	var count := int(args.get("count", "400"))
	var policy := LaunchPolicy.by_name(args.get("policy", "intercept"))
	var build := String(args.get("build", "default"))
	var force := float(args.get("force", "1.0"))
	var sizes: Array[int] = []
	for token in String(args.get("sizes", "1")).split(",", false):
		sizes.append(int(token))
	var rings: Array[float] = []
	for token in String(args.get("rings", "1.0")).split(",", false):
		rings.append(float(token))

	print("# 立ち位置のスイープ (方針=%s, 自機=%s, フォース=%.2f, 各セル%d戦)" % [
		LaunchPolicy.NAMES[policy], build, force, count
	])
	print("# near=敵と同じ側(助走最短) / random=従来のボット / opposite=真反対(助走最長)")
	print("# 距離=中心からの距離(外周リング=1.00、0.00で中心)。従来のボットは1.00だけ。")
	print("# シードは立ち位置間で共通。同じ敵の湧きに対して立ち方だけを変える。")

	for level in LEVELS:
		var pool := EnemyRoster.of_level(level)
		if pool.is_empty():
			continue
		for size in sizes:
			print("\n## Lv%d %d体" % [level, size])
			print("| 立ち位置 | 距離 | 勝率 | 平均決着 | 自機の壁回数 | 自機 削り/壁/減衰 | 敵が受けた削り |")
			print("|---|---|---|---|---|---|---|")
			for ring in rings:
				for stance in STANCES:
					_row(pool, size, count, policy, stance, force, build, ring)
	quit(0)


## 自機。default=素、mid=中盤の実ビルド(measure_group_size._player と同じ)。
func _player(build: String) -> SpinnerStats:
	var stats := SpinnerStats.default_player()
	if build != "mid":
		return stats
	stats.mass = 1.95
	stats.rps = 28.9
	stats.edge = 0.20
	stats.drill = 0.25
	return stats


func _row(
	pool: Array[EnemyData], size: int, count: int, policy: LaunchPolicy.Kind,
	stance: LaunchPolicy.Stance, force: float, build: String, ring: float
) -> void:
	var overrides := BattleSim.Overrides.new()
	overrides.launch_force_scale = force
	overrides.launch_stance = stance
	overrides.launch_ring_scale = ring

	var wins := 0
	var finish := 0.0
	var wall_hits := 0.0
	var drain := 0.0
	var wall := 0.0
	var decay := 0.0
	var enemy_drain := 0.0
	for i in count:
		var enemies: Array[EnemyData] = []
		for k in size:
			enemies.append(pool[(i + k) % pool.size()])
		var record := BattleSim.play_one(i, enemies, policy, _player(build), overrides)
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
	print("| %s | %.2f | %.1f%% | %.2fs | %.2f | %s | %.1f |" % [
		LaunchPolicy.STANCE_NAMES[stance], ring, 100.0 * wins / count, finish / count,
		wall_hits / count, share, enemy_drain / count])
