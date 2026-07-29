extends RefCounted

## EnemyRoster の強さに関するテスト。数値そのものではなく、チューニングで値が
## 変わっても崩れてはいけない性質を固定する。
##
##  - 乱戦メンバーが弱められないこと: 頭数でrpsを割らず、各体を1段下のレベルの
##    まま戦わせる(手強さの見返りは頭数ぶんの報酬。pick_group_for_step参照)。
##    ここが1未満に落ちたら、どこかで頭数割りが復活している。
##  - 寿命の床と梯子: 寿命目安(rps÷(半径×spin_decay))がLv3以上でプレイヤー初期を
##    明確に上回り、レベル間で逆転しないこと。逆転すると「待てば自滅」が強敵ほど
##    有効になる(受け身支配)。
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
	_test_lifetime_sane_decay(check)
	_test_lifetime_floor(check)
	_test_lifetime_ladder(check)
	_test_contact_trade_floor(check)
	_test_intra_level_trade_evenness(check)
	_test_vanguard_steps(check)
	_test_vanguard_group_rules(check)


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


## 寿命目安 = rps ÷ (半径 × spin_decay)。自然減衰が「半径×spin_decay」に比例するため、
## 殴られなくてもこの目安(を土俵のnatural_dampingで割った秒数)で力尽きる。
## プレイヤーと同じ土俵の上での比較なので、natural_dampingは共通で約分できる。
static func lifetime(stats: SpinnerStats) -> float:
	return stats.rps / maxf(stats.radius * stats.spin_decay, 0.0001)


## 全敵のspin_decayが(0,1]に収まること。0以下は不死身、1超えは意図しない自滅加速。
func _test_lifetime_sane_decay(check: Callable) -> void:
	var all_sane := true
	for e in EnemyRoster.all():
		if e.stats.spin_decay <= 0.0 or e.stats.spin_decay > 1.0:
			all_sane = false
	check.call(all_sane, "全敵のspin_decayが(0,1]に収まる")


## Lv3以上の敵の寿命目安が、プレイヤー初期寿命を明確に(1.15倍以上)上回ること。
## ここが割れると「弱発射で離れて置き、敵の自然減衰を待つ」だけで強敵に勝てる
## 受け身支配が復活する(かつて寿命がLv1≈42→Lv5≈19と逆転しており、Lv4+戦とボス戦の
## 最適解が放置だった)。低レベル(Lv1〜2)は接触で瞬殺できる導入なので対象外。
func _test_lifetime_floor(check: Callable) -> void:
	var player_life := lifetime(SpinnerStats.default_player())
	var floor_life := player_life * 1.15
	for level in range(3, 6):
		var worst := INF
		for e in EnemyRoster.of_level(level):
			worst = minf(worst, lifetime(e.stats))
		check.call(
			worst >= floor_life,
			"寿命の床: Lv%d最小(%.1f) ≧ プレイヤー初期(%.1f)×1.15=%.1f" % [
				level, worst, player_life, floor_life]
		)


## 接触トレードの床: 敵との接触戦が、攻めを積み切ったプレイヤーにとって
## 一方的すぎないこと。等速衝突1回の「受ける削り ÷ 与える削り(edge上限込み)」が
## 上限を超えない。削りは speed と violence に線形なので比は両者に依存しない
## (v=1, violence=1で評価)。
##
## ここが割れると「攻め札を上限まで積んでも接触するだけ損」なレベルが生まれ、
## 回避はすり鉢が許さないので、そのレベル帯が全戦法詰みの崖になる(段7の
## Lv4戦がコールドプレイで5連敗した一次証拠。当時の比は2.1〜3.2だった)。
##
## ボス(Lv5)は「最強の敵」として上限を別に持つ(接触だけで楽に沈まないが、
## 接触が常に大損でもない帯)。かつては据え置き原則で対象外だったが、比4.0〜5.3の
## 時代にコールドプレイでボス5連敗×2サイクル(全て惜敗・戦法の影響が消える)が続き、
## 「壁・減衰でしか仕留められない」が理不尽側に振れていたため上限を敷いた。
const TRADE_RATIO_CAP := 2.7
const BOSS_TRADE_RATIO_CAP := 4.5


## 等速衝突1回の「受ける削り ÷ 与える削り(edge上限込み)」。床テストと格差テストで共用。
static func trade_ratio(e: EnemyData) -> float:
	var player := SpinnerStats.default_player()
	var pierce := SpinnerPhysics.spin_drain(player.mass, 1.0, player.mass, player.radius, 1.0)
	var received := SpinnerPhysics.spin_drain(
		e.stats.mass, 1.0, player.mass, player.radius, 1.0)
	var dealt := SpinnerPhysics.sharpened_spin_drain(
		SpinnerPhysics.spin_drain(player.mass, 1.0, e.stats.mass, e.stats.radius, 1.0),
		CustomPartCatalog.EDGE_MAX, pierce)
	return received / maxf(dealt, EPS)


func _test_contact_trade_floor(check: Callable) -> void:
	for level in range(1, 6):
		var cap := TRADE_RATIO_CAP if level < 5 else BOSS_TRADE_RATIO_CAP
		for e in EnemyRoster.of_level(level):
			check.call(
				trade_ratio(e) <= cap,
				"接触トレードの床: %s の被/与比(%.2f) ≦ %.1f" % [
					e.display_name, trade_ratio(e), cap]
			)


## 接触トレードの同レベル内格差: 同レベルの敵どうしで被/与比が開きすぎないこと。
## 硬さ・耐久・寿命は同レベルで揃えてあるのに、被削りは相手の質量だけで決まる
## ため、質量の突出した個体だけ「同レベルなのに別格に強い」が起きる。回避は
## すり鉢が許さないので、その個体を引いたランだけ全戦法が同じ削り負けに収束し、
## リトライが出現ガチャになる(コールドプレイでENEMY_3_3に5連敗・ENEMY_4_3に
## 4連敗、素プレイヤーの戦闘勝率が同Lv内で6倍差、が一次証拠)。
## 接触が勝敗を決めるLv3以上が対象(Lv1〜2は一撃で終わる導入なので、質量の個性を
## 広く残してよい)。
const TRADE_SPREAD_CAP := 1.4


func _test_intra_level_trade_evenness(check: Callable) -> void:
	for level in range(3, 6):
		var worst := -INF
		var best := INF
		for e in EnemyRoster.of_level(level):
			var ratio := trade_ratio(e)
			worst = maxf(worst, ratio)
			best = minf(best, ratio)
		check.call(
			best > 0.0 and worst / best <= TRADE_SPREAD_CAP,
			"トレード格差: Lv%d の被/与比の開き(%.2f = %.2f/%.2f) ≦ %.1f" % [
				level, worst / maxf(best, EPS), worst, best, TRADE_SPREAD_CAP]
		)


## レベル平均の寿命目安がLv3→4→5で下がらないこと(高レベルほど短命の逆転を防ぐ)。
## spin_decayを1.0に戻す(または高レベルだけ上げる)とここが落ちる。
func _test_lifetime_ladder(check: Callable) -> void:
	var prev_avg := 0.0
	for level in range(3, 6):
		var total := 0.0
		var n := 0
		for e in EnemyRoster.of_level(level):
			total += lifetime(e.stats)
			n += 1
		var avg := total / maxf(n, 1)
		check.call(
			avg >= prev_avg,
			"寿命の梯子: Lv%d平均(%.1f) ≧ Lv%d平均(%.1f)" % [level, avg, level - 1, prev_avg]
		)
		prev_avg = avg


## 斥候段の割当: 各レベル帯の2段目(段2・4・6)だけが斥候段で、斥候レベルは
## その段の基準+1。段8(Lv5=ボスの先取り)と帯の1段目(崖)は対象外。
## is_vanguard_stepの条件(偶数段・レベル上限)を弄るとここが落ちる。
func _test_vanguard_steps(check: Callable) -> void:
	var expected := {1: 0, 2: 2, 3: 0, 4: 3, 5: 0, 6: 4, 7: 0, 8: 0, 9: 0}
	var ok := true
	var detail := ""
	for step in expected:
		var got := EnemyRoster.vanguard_level_for_step(step)
		if got != expected[step]:
			ok = false
			detail = " / 段%d: 期待Lv%d 実際Lv%d" % [step, expected[step], got]
			break
	check.call(ok, "斥候段: 段2→Lv2・段4→Lv3・段6→Lv4、他は無し%s" % detail)


## 斥候の出現規則: (1)斥候は必ず単体(乱戦にならない)、(2)レベルは基準+1ちょうど、
## (3)出現率がVANGUARD_CHANCEの近傍、(4)allow_vanguard=falseと非斥候段では
## 基準レベル以外が絶対に出ない。斥候ロールを頭数ロールの後に移す・単体限定を
## 外す・封印引数を無視する、のどれを壊してもここが落ちる。
func _test_vanguard_group_rules(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260729
	const DRAWS := 3000
	var violations: Array[String] = []
	for step in [2, 4, 6]:
		var base := EnemyRoster.level_for_step(step)
		var vanguards := 0
		for _i in DRAWS:
			var group := EnemyRoster.pick_group_for_step(step, rng)
			var top := 0
			for e in group:
				top = maxi(top, e.level)
			if top > base:
				vanguards += 1
				if group.size() != 1:
					violations.append("段%d: 斥候が%d体の乱戦になった" % [step, group.size()])
				if top != base + 1:
					violations.append("段%d: 斥候Lv%d(基準+1でない)" % [step, top])
		var rate := float(vanguards) / DRAWS
		if absf(rate - EnemyRoster.VANGUARD_CHANCE) > 0.05:
			violations.append("段%d: 斥候率%.3f が VANGUARD_CHANCE(%.2f)から外れた" % [
				step, rate, EnemyRoster.VANGUARD_CHANCE])
		# 封印(allow_vanguard=false)では基準レベルしか出ない。
		for _i in 1000:
			var group := EnemyRoster.pick_group_for_step(step, rng, false)
			for e in group:
				if e.level != base:
					violations.append("段%d: 封印中にLv%dが出た" % [step, e.level])
	# 非斥候段(帯の1段目と段7・8)は常に基準レベルのみ。
	for step in [1, 3, 5, 7, 8]:
		var base := EnemyRoster.level_for_step(step)
		for _i in 1000:
			for e in EnemyRoster.pick_group_for_step(step, rng):
				if e.level != base:
					violations.append("段%d(非斥候段): Lv%dが出た" % [step, e.level])
	check.call(
		violations.is_empty(),
		"斥候の出現規則(単体・+1レベル・率・封印)%s" % (
			"" if violations.is_empty() else " / 例: " + violations[0])
	)
