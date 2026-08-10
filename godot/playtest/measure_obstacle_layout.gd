extends SceneTree

## 柱(障害物)の**配置**が勝敗にどれだけ効いているかを測る診断。
##
##   godot --headless --path godot --script res://playtest/measure_obstacle_layout.gd -- [--count=600]
##
## 動機: `measure_field.gd` は FIELD_PILLARS が**柱2本だけ**の差で FIELD_CLASSIC から
## Lv1で -2pt・Lv2で -21pt 動くことを出すが、**その20ptがどのつまみに乗っているか**は
## 出さない。段に応じて柱を手加減するなら、効くつまみ(太さか・本数か・位置か)を
## 先に特定する必要がある。
##
## 方法は measure_field.gd と揃える(自機は既定ステータス固定・満引き・シードは行間で共通)
## ので、`2本 r0.60` の行はあちらの FIELD_PILLARS の行と一致し、`柱なし` の行は
## FIELD_CLASSIC の行と一致する——両端が既知の表に重なることが、この表の検算になる。
##
## 変種は3系統:
##  - **太さ**: 現行位置のまま半径だけを振る
##  - **本数**: 2本 → 1本 → 0本
##  - **位置**: 中心からの距離を振る(現行は中心(5,5)から2.83、発射リングは3.80)

const LEVELS := [1, 2, 3, 4]

## 現行の柱の中心距離。(3,3) と (7,7) の中心(5,5)からの距離 = 2√2。
const CURRENT_DIST := 2.8284271


func _init() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var eq := arg.find("=")
			args[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	var count := int(args.get("count", "600"))
	var policy := LaunchPolicy.by_name(args.get("policy", "intercept"))

	var base := _pillars_field()
	if base == null:
		push_error("measure_obstacle_layout: FIELD_PILLARS が見つからない")
		quit(1)
		return

	print("# 柱の配置別の成績 (方針=%s, 各セル%d戦)" % [LaunchPolicy.NAMES[policy], count])
	print("# 土俵は FIELD_PILLARS 固定で柱だけを差し替える。柱なしは FIELD_CLASSIC 相当。")
	print("# 自機は既定ステータス固定・満引き。シードは行間で共通＝同じ敵に柱だけ差し替える。")
	print("")
	print("| 変種 | Lv | 勝率 | 平均決着 | 自機の壁回数 | 自機 削り/壁/減衰 |")
	print("|---|---|---|---|---|---|")
	for variant: Array in _variants():
		for level: int in LEVELS:
			_row(base, variant[0], variant[1], level, count, policy)
	quit(0)


## [表示名, 柱の配列] の一覧。
func _variants() -> Array:
	var out: Array = []
	out.append(["柱なし", [] as Array[Vector3]])
	for r: float in [0.12, 0.30, 0.60]:
		out.append(["2本 r%.2f" % r, _ring(2, CURRENT_DIST, r)])
	for r: float in [0.12, 0.30, 0.60]:
		out.append(["1本 r%.2f" % r, _ring(1, CURRENT_DIST, r)])
	for d: float in [1.6, 2.2, 3.4, 4.0]:
		out.append(["2本 距離%.1f r0.60" % d, _ring(2, d, 0.60)])
	return out


## 中心(5,5)から距離distの対角線上に、柱をcount本 等間隔に置く。
## count=2 は現行と同じ (3,3)-(7,7) の並び(dist=2.83のとき)。
func _ring(count: int, dist: float, radius: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var offset := dist / sqrt(2.0)
	var spots := [Vector2(5.0 - offset, 5.0 - offset), Vector2(5.0 + offset, 5.0 + offset)]
	for i in count:
		out.append(Vector3(spots[i].x, spots[i].y, radius))
	return out


func _pillars_field() -> FieldData:
	for field in FieldRoster.all():
		if field.title_key == "FIELD_PILLARS":
			return field
	return null


func _row(
	base: FieldData, label: String, obstacles: Array[Vector3],
	level: int, count: int, policy: LaunchPolicy.Kind
) -> void:
	var pool := EnemyRoster.of_level(level)
	if pool.is_empty():
		return
	var field := FieldData.make(
		base.title_key, base.arena_bounds, base.wall_shape,
		base.stage_shape, base.stage_strength, obstacles
	)

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
	print("| %s | %d | %.1f%% | %.2fs | %.2f | %d%% / %d%% / %d%% |" % [
		label,
		level,
		100.0 * wins / count,
		finish / count,
		wall_hits / count,
		roundi(100.0 * drain / total),
		roundi(100.0 * wall / total),
		roundi(100.0 * decay / total),
	])
