extends RefCounted

## reward_quality.gd のテスト。マップの報酬ピップに載せた「この部屋の報酬の質
## (RAREの出やすさ)」の、倍率の値・ノードからの引き方・色の向きを確かめる。
##
## 見た目そのものは静止画では確かめられない(CLAUDE.mdの方針)ので、ここで固定するのは
## 「調整で数値を動かしても生き残る性質」だけ:
##   - 倍率が抽選側(CustomPartCatalog.rare_weight_for)と**同じ定義**であること
##     (表示と実際の抽選がずれる二重定義を防ぐ)
##   - 基準の部屋はちょうど1.0、斥候(格上)と乱戦(頭数)で上がる(向き)
##   - 頭数の上限(MELEE_RARE_COUNT_MAX)とレベルの上限で頭打ちになる
##   - 報酬の無いノード(ボス)と null は1.0
##   - 色は基準でちょうど従来の色（既存ノードの見た目を変えない）、質が上がるほど
##     単調に明るくなり、上限で頭打ち

const EPS := 1e-4

## マップの実定数(報酬ピップの色)を借りるため。決め打ちの色ではなく実際に描く色で
## 「基準の部屋は見た目が変わらない」を確かめる。
const MapScreenScript := preload("res://scenes/map/MapScreen.gd")


func run(check: Callable) -> void:
	_test_ratio_matches_catalog(check)
	_test_ratio_direction(check)
	_test_ratio_caps(check)
	_test_node_ratio(check)
	_test_pip_color(check)


## 倍率の定義は抽選側と同じ。ここが独自計算になっていると、画面が「×2」と
## 言いながら実際の重みは違う、という嘘が作れてしまう。
func _test_ratio_matches_catalog(check: Callable) -> void:
	for base_level in range(1, 6):
		for level in range(base_level, 6):
			for count in range(1, 5):
				var expected := (
					float(CustomPartCatalog.rare_weight_for(level, count))
					/ float(CustomPartCatalog.rare_weight_for(base_level, 1))
				)
				var got := RewardQuality.weight_ratio(level, count, base_level)
				check.call(
					absf(got - expected) < EPS,
					"倍率は抽選の重み比と一致(base=%d lv=%d %d体): %.3f" % [
						base_level, level, count, got]
				)


## 向き: 段の基準どおりの単体はちょうど1.0。斥候(レベル+1)でも乱戦(頭数)でも上がる。
func _test_ratio_direction(check: Callable) -> void:
	for level in range(1, 6):
		check.call(
			absf(RewardQuality.weight_ratio(level, 1, level) - 1.0) < EPS,
			"基準の部屋(段のレベル・単体)はちょうど1.0: Lv%d" % level
		)

	# 斥候: 段2(基準Lv1)にLv2が単体で出ると重み1→2。
	check.call(
		RewardQuality.weight_ratio(2, 1, 1) > 1.0 + EPS,
		"斥候(格上の単体)は基準より上がる: %.2f" % RewardQuality.weight_ratio(2, 1, 1)
	)
	# 乱戦: 同じレベルでも頭数ぶん。
	check.call(
		RewardQuality.weight_ratio(3, 2, 3) > RewardQuality.weight_ratio(3, 1, 3) + EPS,
		"乱戦は頭数ぶん上がる: %.2f" % RewardQuality.weight_ratio(3, 2, 3)
	)
	check.call(
		RewardQuality.weight_ratio(3, 3, 3) > RewardQuality.weight_ratio(3, 2, 3) + EPS,
		"3体は2体より上がる: %.2f" % RewardQuality.weight_ratio(3, 3, 3)
	)


## 頭打ち: 頭数はMELEE_RARE_COUNT_MAX、レベルはRARE_WEIGHT_MAXで止まる。
## 縮退した入力(0体・レベル0)でも倍率が壊れない(0除算・負値を出さない)。
func _test_ratio_caps(check: Callable) -> void:
	check.call(
		absf(RewardQuality.weight_ratio(3, 9, 3)
			- RewardQuality.weight_ratio(3, CustomPartCatalog.MELEE_RARE_COUNT_MAX, 3)) < EPS,
		"頭数は上限で頭打ち: %.2f" % RewardQuality.weight_ratio(3, 9, 3)
	)
	check.call(
		absf(RewardQuality.weight_ratio(9, 1, 5) - 1.0) < EPS,
		"レベルは上限で頭打ち(Lv5基準に対しLv9でも1.0): %.2f"
			% RewardQuality.weight_ratio(9, 1, 5)
	)
	check.call(
		RewardQuality.weight_ratio(1, 0, 1) > 0.0,
		"0体でも倍率は正: %.2f" % RewardQuality.weight_ratio(1, 0, 1)
	)
	check.call(
		RewardQuality.weight_ratio(0, 1, 0) > 0.0,
		"レベル0でも倍率は正(重みの下限クランプで分母が0にならない): %.2f" % RewardQuality.weight_ratio(0, 1, 0)
	)


## ノードから引く経路。段の基準レベルは EnemyRoster.level_for_step、実レベルは
## MapNode.level。報酬の無いノード(ボス)とnullは1.0。
func _test_node_ratio(check: Callable) -> void:
	var step := 2
	var base_level := EnemyRoster.level_for_step(step)

	var plain := _node(step, [_enemy(base_level)])
	check.call(
		absf(RewardQuality.ratio_for_node(plain) - 1.0) < EPS,
		"段の基準どおりの単体ノードは1.0: %.2f" % RewardQuality.ratio_for_node(plain)
	)

	var vanguard := _node(step, [_enemy(base_level + 1)])
	check.call(
		vanguard.is_vanguard(),
		"検査用のノードが斥候として認識される"
	)
	check.call(
		RewardQuality.ratio_for_node(vanguard) > 1.0 + EPS,
		"斥候ノードは1.0より上: %.2f" % RewardQuality.ratio_for_node(vanguard)
	)

	var melee := _node(step, [_enemy(base_level), _enemy(base_level)])
	check.call(
		RewardQuality.ratio_for_node(melee) > 1.0 + EPS,
		"乱戦ノードは1.0より上: %.2f" % RewardQuality.ratio_for_node(melee)
	)

	var boss := _node(MapTree.STEP_GOAL, [_enemy(5)])
	check.call(
		boss.reward_count() == 0 and absf(RewardQuality.ratio_for_node(boss) - 1.0) < EPS,
		"報酬の無いゴールは1.0: %.2f" % RewardQuality.ratio_for_node(boss)
	)
	check.call(
		absf(RewardQuality.ratio_for_node(null) - 1.0) < EPS,
		"nullは1.0"
	)


## 色: 基準ではマップが今描いている色そのまま。質が上がるほど単調に明るくなり、
## 表示上限で頭打ち。範囲外の倍率でも端で止まる。
func _test_pip_color(check: Callable) -> void:
	var plain: Color = MapScreenScript.COLOR_REWARD_PIP

	var at_base := RewardQuality.pip_color(plain, 1.0)
	check.call(
		at_base.is_equal_approx(plain),
		"基準の部屋の報酬ピップは従来の色のまま: %s" % str(at_base)
	)

	var prev := _luminance(at_base)
	for ratio in [1.5, 2.0, 2.5, 3.0]:
		var lum := _luminance(RewardQuality.pip_color(plain, ratio))
		check.call(lum > prev + EPS, "倍率×%.1f で明るくなる: %.3f" % [ratio, lum])
		prev = lum

	var capped := RewardQuality.pip_color(plain, 99.0)
	check.call(
		capped.is_equal_approx(RewardQuality.pip_color(plain, RewardQuality.RATIO_FULL)),
		"表示上限を超えた倍率は頭打ち: %s" % str(capped)
	)
	check.call(
		RewardQuality.pip_color(plain, 0.0).is_equal_approx(plain),
		"1.0未満の倍率でも基準の色より暗くならない"
	)
	# 金の語彙から離れないこと(純白まで飛ばさない)。
	check.call(
		capped.b < 1.0 - EPS,
		"振り切っても純白にはしない(金色の語彙を保つ): %s" % str(capped)
	)

	# マップが実際に使う経路。ここが素の COLOR_REWARD_PIP のままだと、質の表示は
	# 純関数の中だけに存在して画面には一生出ない。
	var step := 2
	var base_level := EnemyRoster.level_for_step(step)
	var plain_node := _node(step, [_enemy(base_level)])
	var rich_node := _node(step, [_enemy(base_level + 1)])
	check.call(
		MapScreenScript.reward_pip_color(plain_node).is_equal_approx(plain),
		"マップ: 基準の部屋の報酬ピップは従来の色"
	)
	check.call(
		_luminance(MapScreenScript.reward_pip_color(rich_node)) > _luminance(plain) + EPS,
		"マップ: 質の上がる部屋の報酬ピップは明るくなる"
	)


func _luminance(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _enemy(level: int) -> EnemyData:
	var stats := SpinnerStats.new()
	stats.mass = 1.0
	stats.radius = 0.5
	stats.rps = 15.0
	return EnemyData.make(level, "TEST_ENEMY_%d" % level, stats)


func _node(step: int, enemies: Array[EnemyData]) -> MapTree.MapNode:
	var node := MapTree.MapNode.new(Vector2i(step, 2))
	node.enemies = enemies
	return node
