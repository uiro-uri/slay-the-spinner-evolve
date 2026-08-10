extends SceneTree

## 発射の「フォース(引き量)」を振って、勝率と自機のrps喪失内訳がどう動くかを測る診断。
##
##   godot --headless --path godot --script res://playtest/measure_launch_force.gd -- [--count=300]
##
## 動機: ボットの狙う方針(AIM_CENTER/AIM_SPAWN/INTERCEPT)はどれも満引き固定なので、
## 「どれくらいの力で撃つか」という実プレイヤーの選択が統計に一度も現れていなかった。
## コールドプレイでは満引きが壁で自滅する手触りが繰り返し出ていたので、
## その手触りが統計に出るかを確かめる。
##
## 出力は段(=敵レベル)ごとの、フォース別の 勝率 / 自機の壁ヒット回数 / rps喪失の内訳。
##
## **結論(2026-08-10、成長0〜3枚 × Lv1〜5 × 1体/3体 で取り直し): 手触りは間違い。**
## 弱く撃って勝率が上がるセルが1つも無い。壁の取り分は確かにフォースに比例して伸びる
## (成長2枚Lv2で0%→24%)が、決着が速くなるぶんが必ず上回る。効きが最大の
## 成長3枚Lv3単体でフォース0.15が13.2%、満引きが62.8%(各400戦)。乱戦(3体)では
## フォースの差自体がほぼ消える(成長1枚Lv2で55.7〜63.3%＝雑音の幅)。
## この結果を受けて自機にも下限 LaunchSpeed.PLAYER_MIN を敷いた——弱撃ちは
## 「慎重な選択肢」ではなく罰でしかなかったので、選べる幅から外した。

const FORCES := [0.15, 0.30, 0.45, 0.60, 0.75, 1.00]
const LEVELS := [1, 2, 3, 4, 5]

## 自機のビルド。素のコマだけを測っていたのが、この診断の元々の穴だった
## (journal 2026-08-09「満引きが罰されるという手触りは統計と食い違う」の
## 「中盤ビルド・乱戦で取り直す価値がある」)。実プレイで満引きが壁に食われるのは
## 巨大化したあと——コールドプレイ 2026-08-10 は段8〜9(半径1.05・質量2.88)で
## force=1.00/0.80が負け、0.50で勝った。素のコマ(半径0.70)だけでは再現しようがない。
##
## GROWTHはradiusとmassを同時に伸ばす実際の成長経路そのもの。枚数は
## 実プレイの到達点(3枚で半径が上限1.05)に合わせてある。
const GROWTH_PART_ID := 2
const BUILDS := [0, 1, 2, 3]

## 乱戦の頭数。1体だけを測っていたのがもう一つの穴で、実プレイの前半は3体戦が主。
const GROUP_SIZES := [1, 3]


func _init() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var eq := arg.find("=")
			args[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	var count := int(args.get("count", "300"))
	var policy := LaunchPolicy.by_name(args.get("policy", "intercept"))
	var builds: Array = BUILDS
	if args.has("growth"):
		builds = [int(args["growth"])]
	var groups: Array = GROUP_SIZES
	if args.has("group"):
		groups = [int(args["group"])]

	print("# 発射フォースのスイープ (方針=%s, 各セル%d戦)" % [LaunchPolicy.NAMES[policy], count])
	print("# フォース1.00=満引き(=従来のボット)。成長=PART_GIANT_GROWTHの枚数。")

	for growth in builds:
		var stats := _build(growth)
		print("\n# 成長%d枚 (半径%.2f 質量%.2f 硬さ%.2f)" % [
			growth, stats.radius, stats.mass, stats.mass * stats.radius * stats.radius])
		for group_size in groups:
			for level in LEVELS:
				var pool := EnemyRoster.of_level(level)
				if pool.is_empty():
					continue
				print("\n## Lv%d %d体" % [level, group_size])
				print("| フォース | 初速 | 勝率 | 平均決着 | 自機の壁回数 | 自機 削り/壁/減衰 | 敵が受けた削り |")
				print("|---|---|---|---|---|---|---|")
				for force in FORCES:
					_row(pool, level, count, policy, force, stats, group_size)
	quit(0)


## GROWTHをcopies枚積んだ自機。0枚は素のコマ(=この診断の従来の測り方)。
func _build(copies: int) -> SpinnerStats:
	var stats := SpinnerStats.default_player()
	if copies <= 0:
		return stats
	var part := CustomPartCatalog.by_id(GROWTH_PART_ID)
	for i in copies:
		part.apply_to(stats)
	return stats


func _row(pool: Array[EnemyData], level: int, count: int,
		policy: LaunchPolicy.Kind, force: float, player_stats: SpinnerStats,
		group_size: int) -> void:
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
		var enemies: Array[EnemyData] = []
		for k in group_size:
			enemies.append(pool[(i + k) % pool.size()])
		var record := BattleSim.play_one(i, enemies, policy, player_stats, overrides)
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
		force, LaunchSpeed.from_pull(force, 1.0), 100.0 * wins / count, finish / count,
		wall_hits / count, share, enemy_drain / count])
