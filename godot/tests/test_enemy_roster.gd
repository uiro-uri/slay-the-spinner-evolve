extends RefCounted

## EnemyRoster の強さに関するテスト。数値そのものではなく、チューニングで値が
## 変わっても崩れてはいけない性質を固定する。
##
##  - 乱戦メンバーの耐久下限: 頭数割りで「1衝突で終わる」コマを作らない。
##    これが無いと3体乱戦のLv1メンバーが耐久2.1まで落ち、実測で12.7%が最初の
##    1衝突で死んでいた(pick_group_for_step / MIN_GROUP_TOUGHNESS参照)。
##  - レベルの梯子: 耐久(rps×質量×半径²=「耐えられる衝突回数の目安」)がレベルが
##    上がるほど強くなること。rpsは硬さを補う都合でレベル順に単調でない(32→…→
##    10.5→26)ので、単調性は耐久で見る。rpsを単独でいじると崩れやすい。
##
## 耐久の式は playtest の RunSim.toughness() を使い回す(式の二重持ちを避ける)。

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_group_toughness_floor(check)
	_test_toughness_ladder(check)


## 乱戦メンバーはどれも耐久下限を下回らないこと。ただし単体の耐久が既に下限より
## 低い敵は下限まで上げようがない(係数は1で頭打ち)ので、その敵の単体耐久と
## 下限の小さい方を下限とみなす。下限を外して 1/頭数 に戻すと、3体Lv1メンバーが
## この下限を割って落ちる。
func _test_group_toughness_floor(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240718
	var worst_ratio := INF   # (メンバー耐久 / 期待下限) の最小。1未満なら違反。
	var seen_swarm := false
	for _iter in 2000:
		for step in range(1, MapTree.STEP_GOAL + 1):
			var group := EnemyRoster.pick_group_for_step(step, rng)
			if group.size() <= 1:
				continue
			seen_swarm = true
			for member in group:
				var member_tough := RunSim.toughness(member.stats)
				var expected_floor := minf(
					EnemyRoster.MIN_GROUP_TOUGHNESS, _solo_toughness(member)
				)
				worst_ratio = minf(worst_ratio, member_tough / expected_floor)
	check.call(seen_swarm, "乱戦(複数体)グループが実際に生成された")
	check.call(
		worst_ratio >= 1.0 - EPS,
		"乱戦メンバーの耐久が下限を満たす (最悪比 %.3f、1.0以上であるべき)" % worst_ratio
	)


## 同レベルの敵の中で、そのメンバーの元(フルrps)の耐久を引く。メンバーは
## display_name で元をたどれる。見つからなければ0を返す(下限判定が緩くなるだけ)。
func _solo_toughness(member: EnemyData) -> float:
	for base in EnemyRoster.of_level(member.level):
		if base.display_name == member.display_name:
			return RunSim.toughness(base.stats)
	return 0.0


## 耐久がレベル間で単調増(あるレベルの最大 < 次のレベルの最小)であること。
## rpsを1体だけ弄って梯子を壊すと、ここが落ちる。
func _test_toughness_ladder(check: Callable) -> void:
	for level in range(1, 5):
		var here_max := -INF
		for e in EnemyRoster.of_level(level):
			here_max = maxf(here_max, RunSim.toughness(e.stats))
		var next_min := INF
		for e in EnemyRoster.of_level(level + 1):
			next_min = minf(next_min, RunSim.toughness(e.stats))
		check.call(
			here_max < next_min,
			"耐久の梯子: Lv%d最大(%.1f) < Lv%d最小(%.1f)" % [level, here_max, level + 1, next_min]
		)
