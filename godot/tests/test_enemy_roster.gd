extends RefCounted

## EnemyRoster の強さに関するテスト。数値そのものではなく、チューニングで値が
## 変わっても崩れてはいけない性質を固定する。
##
##  - 乱戦メンバーが弱められないこと: 頭数でrpsを割らず、各体を1段下のレベルの
##    まま戦わせる(手強さの見返りは頭数ぶんの報酬。pick_group_for_step参照)。
##    ここが1未満に落ちたら、どこかで頭数割りが復活している。
##  - レベルの梯子: 耐久(rps×質量×半径²=「耐えられる衝突回数の目安」)がレベルが
##    上がるほど強くなること。rpsもレベル順に上げているが(回転ゲージ=強さの見た目)、
##    強さは硬さ・質量・rpsの複合なので、レベルの梯子は複合結果である耐久で見る。
##    どれか1つだけ弄って梯子を壊すと、ここが落ちる。
##
## 耐久の式は playtest の RunSim.toughness() を使い回す(式の二重持ちを避ける)。

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_swarm_members_unweakened(check)
	_test_toughness_ladder(check)


## 乱戦メンバーはどれも頭数で弱められていないこと。各体の耐久(=rps×質量×半径²)が、
## 同名の元(フルrps)の耐久とちょうど一致する(比が1.0)。頭数割りを復活させると
## rpsが下がって比が1未満になり、ここが落ちる。
func _test_swarm_members_unweakened(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240718
	var worst_ratio := INF   # (メンバー耐久 / 元のフルrps耐久) の最小。1未満なら弱められている。
	var seen_swarm := false
	for _iter in 2000:
		for step in range(1, MapTree.STEP_GOAL + 1):
			var group := EnemyRoster.pick_group_for_step(step, rng)
			if group.size() <= 1:
				continue
			seen_swarm = true
			for member in group:
				var solo := _solo_toughness(member)
				if solo <= 0.0:
					continue
				worst_ratio = minf(worst_ratio, RunSim.toughness(member.stats) / solo)
	check.call(seen_swarm, "乱戦(複数体)グループが実際に生成された")
	check.call(
		worst_ratio >= 1.0 - EPS,
		"乱戦メンバーが頭数で弱められていない (最悪比 %.3f、1.0であるべき)" % worst_ratio
	)


## 同レベルの敵の中で、そのメンバーの元(フルrps)の耐久を引く。メンバーは
## display_name で元をたどれる。見つからなければ0を返す(判定を飛ばすだけ)。
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
