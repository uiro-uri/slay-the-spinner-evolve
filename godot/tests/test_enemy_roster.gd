extends RefCounted

## EnemyRoster の強さに関するテスト。数値そのものではなく、チューニングで値が
## 変わっても崩れてはいけない性質を固定する。
##
##  - 乱戦メンバーの緩め方が質量だけであること: 頭数ぶんの報酬に見合うよう質量に
##    倍率(EnemyRoster.MELEE_MASS_EXP)を掛けるが、rps・半径・spin_decayは素のまま。
##    ここが崩れると、かつて撤廃された「rpsの頭数割り」(寿命が縮んで受け身支配が
##    戻る)や「1段下げ」(表示レベルと報酬の実レベルが動く)が復活している。
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
	_test_melee_mass_scale(check)
	_test_melee_room_still_harder(check)
	_test_toughness_ladder(check)
	_test_lifetime_sane_decay(check)
	_test_lifetime_floor(check)
	_test_lifetime_ladder(check)
	_test_contact_trade_floor(check)
	_test_intra_level_trade_evenness(check)
	_test_vanguard_steps(check)
	_test_vanguard_group_rules(check)
	_test_reroll_group(check)
	_test_find_by_name(check)
	_test_band_second_step_shape(check)
	_test_band_ramp_only_on_second_step(check)
	_test_band_ramp_survives_reroll(check)
	_test_band_ramp_wiring(check)
	_test_band_ramp_on_generated_maps(check)


## 乱戦メンバーの緩め方は**質量だけ**であること。実際に生成したグループの各体を
## 同名の素の個体と突き合わせ、
##  - 単体戦(1体)は素と厳密に一致する(質量倍率が漏れていない)
##  - 乱戦(2〜3体)は質量がちょうど melee_mass_scale(頭数)倍
##  - rpsは**頭数によらず** step_rps_scale(段) 倍ちょうど(=頭数割りの復活を許さない)
##  - 半径・spin_decay は素のまま
##  - レベルが下がらない(表示レベルと報酬の実レベルを動かさない)
## を固定する。rps割りや1段下げを復活させるとここが落ちる。
##
## rpsの期待値に段の倍率(BAND_SECOND_STEP_RPS_RAMP)を掛けるのは、帯の2段目のランプが
## **段の軸**で、乱戦の緩め(頭数の軸)とは別だから。掛ける相手を頭数から独立させて
## あるので、「乱戦だけrpsを割る」を戻すとここは依然として落ちる。
func _test_melee_mass_scale(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240718
	var seen_swarm := false
	var seen_solo := false
	var violations: Array[String] = []
	for _iter in 2000:
		for step in range(1, MapTree.STEP_GOAL + 1):
			var group := EnemyRoster.pick_group_for_step(step, rng)
			if group.size() > 1:
				seen_swarm = true
			else:
				seen_solo = true
			var expected_scale := EnemyRoster.melee_mass_scale(group.size())
			var expected_rps_scale := EnemyRoster.step_rps_scale(step)
			for member in group:
				var base := _solo_of(member)
				if base == null:
					violations.append("素の個体が引けない: %s" % member.display_name)
					continue
				if not is_equal_approx(member.stats.mass, base.stats.mass * expected_scale):
					violations.append("%d体の%s: 質量%.4f (素%.4f×%.4f を期待)" % [
						group.size(), member.display_name,
						member.stats.mass, base.stats.mass, expected_scale])
				if not is_equal_approx(member.stats.rps, base.stats.rps * expected_rps_scale):
					violations.append("段%dの%d体の%s: rps%.4f (素%.4f×%.4f を期待)" % [
						step, group.size(), member.display_name,
						member.stats.rps, base.stats.rps, expected_rps_scale])
				if not is_equal_approx(member.stats.radius, base.stats.radius):
					violations.append("%d体の%s: 半径が動いた" % [
						group.size(), member.display_name])
				if not is_equal_approx(member.stats.spin_decay, base.stats.spin_decay):
					violations.append("%d体の%s: spin_decayが動いた(寿命が変わる)" % [
						group.size(), member.display_name])
				if member.level < base.level:
					violations.append("%d体の%s: レベルが下がった" % [
						group.size(), member.display_name])
	check.call(seen_swarm, "乱戦(複数体)グループが実際に生成された")
	check.call(seen_solo, "単体グループも生成された(1体の一致を実際に見ている)")
	check.call(
		violations.is_empty(),
		"乱戦の緩めは質量だけ・単体は素のまま%s" % (
			"" if violations.is_empty() else " / 例: " + violations[0])
	)


## 質量を緩めても、**部屋としては頭数ぶん手強いまま**であること。
## 群の質量和は 頭数×頭数^-exp = 頭数^(1-exp) なので、exp<1 である限り頭数に対して
## 真に増える。ここが単調でなくなると「頭数が多いほど楽な部屋」になり、
## 頭数ぶんの報酬(MapNode.reward_count)がただの上振れになってしまう。
## 併せて倍率そのものの性質(1体はちょうど1.0・頭数に対して単調減少・正)も見る。
func _test_melee_room_still_harder(check: Callable) -> void:
	var scale_one := EnemyRoster.melee_mass_scale(1)
	check.call(
		is_equal_approx(scale_one, 1.0),
		"melee_mass_scale(1)=1.0 (単体戦は従来と厳密に同じ) 実際=%.4f" % scale_one
	)
	var monotone_down := true
	var positive := true
	var room_monotone_up := true
	var prev_scale := scale_one
	var prev_room := scale_one
	for count in range(2, 6):
		var scale := EnemyRoster.melee_mass_scale(count)
		if scale >= prev_scale:
			monotone_down = false
		if scale <= 0.0:
			positive = false
		var room := count * scale
		if room <= prev_room + EPS:
			room_monotone_up = false
		prev_scale = scale
		prev_room = room
	check.call(monotone_down and positive, "melee_mass_scale: 頭数が増えるほど小さく、常に正")
	check.call(
		room_monotone_up,
		"乱戦の部屋は頭数ぶん手強いまま (群の質量和が頭数に対して真に増える=倍率の指数<1)"
	)


## 同レベルの敵の中から、そのメンバーの素の個体を display_name で引く。
## 見つからなければ null。
func _solo_of(member: EnemyData) -> EnemyData:
	for base in EnemyRoster.of_level(member.level):
		if base.display_name == member.display_name:
			return base
	return null


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


## 斥候段の割当: 段1と帯の2段目(段2・4・6)で、斥候レベルはその段の基準+1。
## 帯の1段目のうち段3(Lv3が2段先取りで重すぎる)・段5・段7(次レベル初対面の崖)と
## 段8(Lv5=ボスの先取り)は対象外。is_vanguard_stepの条件を弄るとここが落ちる。
func _test_vanguard_steps(check: Callable) -> void:
	var expected := {1: 2, 2: 2, 3: 0, 4: 3, 5: 0, 6: 4, 7: 0, 8: 0, 9: 0}
	var ok := true
	var detail := ""
	for step in expected:
		var got := EnemyRoster.vanguard_level_for_step(step)
		if got != expected[step]:
			ok = false
			detail = " / 段%d: 期待Lv%d 実際Lv%d" % [step, expected[step], got]
			break
	check.call(
		ok,
		"斥候段: 段1・2→Lv2 / 段4→Lv3 / 段6→Lv4、段3・5・7・8は無し%s" % detail
	)


## 斥候の出現規則: (1)斥候は必ず単体(乱戦にならない)、(2)レベルは基準+1ちょうど、
## (3)出現率がVANGUARD_CHANCEの近傍、(4)allow_vanguard=falseと非斥候段では
## 基準レベル以外が絶対に出ない。斥候ロールを頭数ロールの後に移す・単体限定を
## 外す・封印引数を無視する、のどれを壊してもここが落ちる。
func _test_vanguard_group_rules(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260729
	const DRAWS := 3000
	var violations: Array[String] = []
	for step in [1, 2, 4, 6]:
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
	# 非斥候段(段3と、崖の段5・7、段8)は常に基準レベルのみ。
	for step in [3, 5, 7, 8]:
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


## リトライの個体入れ替え(reroll_group)。位置しか変わらない再戦は「同じ相手に
## 同じ負け方」を繰り返す徒労だった(コールドプレイで段5 ENEMY_3_1と3連戦・
## 段8 同型ペアに4連敗が一次証拠)。守る性質:
##  - 頭数と各スロットのレベルが保たれる(マップ表示のLv[体数]と報酬の実レベルを
##    嘘にしない。斥候ノードのLv+1もそのまま)
##  - 各スロットは必ず別個体になる(同レベルに他の個体がいる限り。現状全レベル5種)
##  - **乱戦の質量倍率が掛かり直す**(素の表から引き直すと、リトライしただけで
##    乱戦が元の手強さに戻り、予告に出る硬さも嘘になる)
##  - シード付きRNGで決定的(CLIがbseedから予告と同じ相手を復元する前提)
func _test_reroll_group(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260731
	var count_ok := true
	var level_ok := true
	var changed_ok := true
	var scale_ok := true
	var seen_swarm_reroll := false
	for _i in 300:
		var step := rng.randi_range(1, 9)
		var group := EnemyRoster.pick_group_for_step(step, rng)
		var rerolled := EnemyRoster.reroll_group(group, rng)
		if rerolled.size() != group.size():
			count_ok = false
			continue
		if group.size() > 1:
			seen_swarm_reroll = true
		var expected_scale := EnemyRoster.melee_mass_scale(group.size())
		for i in group.size():
			if rerolled[i].level != group[i].level:
				level_ok = false
			var alternatives := EnemyRoster.of_level(group[i].level).size() > 1
			if alternatives and rerolled[i].display_name == group[i].display_name:
				changed_ok = false
			var base := _solo_of(rerolled[i])
			if base == null or not is_equal_approx(
				rerolled[i].stats.mass, base.stats.mass * expected_scale
			):
				scale_ok = false
	check.call(count_ok, "reroll_group: 頭数が保たれる")
	check.call(level_ok, "reroll_group: 各スロットのレベルが保たれる(表示と報酬を嘘にしない)")
	check.call(changed_ok, "reroll_group: 各スロットは必ず別個体になる(同じ負けの繰り返し防止)")
	check.call(seen_swarm_reroll, "reroll_group: 乱戦の入れ替えを実際に見ている")
	check.call(scale_ok, "reroll_group: 入れ替えた個体にも乱戦の質量倍率が掛かり直す")

	# 決定性: 同じシードなら同じ入れ替え(CLIのretryがbseedから引く前提)。
	var base_rng := RandomNumberGenerator.new()
	base_rng.seed = 77
	var base := EnemyRoster.pick_group_for_step(8, base_rng)
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 1234
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 1234
	var a := EnemyRoster.reroll_group(base, rng_a)
	var b := EnemyRoster.reroll_group(base, rng_b)
	var deterministic := a.size() == b.size()
	if deterministic:
		for i in a.size():
			if a[i].display_name != b[i].display_name:
				deterministic = false
	check.call(deterministic, "reroll_group: シード付きRNGで決定的(予告=実戦の前提)")


## 表示名からの逆引き(find_by_name)。CLIのretryが保存した名前列から相手を
## 復元するのに使う。知らない名前はnull(呼び側がノード生成時の個体へ戻す)。
func _test_find_by_name(check: Callable) -> void:
	var all_ok := true
	for enemy in EnemyRoster.all():
		var found := EnemyRoster.find_by_name(enemy.display_name)
		if found == null or found.display_name != enemy.display_name \
				or found.level != enemy.level:
			all_ok = false
	check.call(all_ok, "find_by_name: 全個体が表示名で逆引きできる")
	check.call(
		EnemyRoster.find_by_name("ENEMY_9_9") == null,
		"find_by_name: 知らない名前はnull")


## 帯(同じレベルが2段続く区間)の形。段1と、レベルが切り替わる段は「1段目」、
## 直前の段と同レベルなら「2段目」。**ボス段(段9)は必ず1段目**＝ランプが乗らない
## (roster の「ボスは据え置き」の約束をここで固定する)。
## is_band_second_step を偶数判定に書き換えても現行の level_for_step では同じ答えに
## なるが、レベル表を触ったときに黙って嘘にならないよう、レベルの一致で確かめる。
func _test_band_second_step_shape(check: Callable) -> void:
	var violations: Array[String] = []
	for step in range(1, MapTree.STEP_GOAL + 1):
		var same_as_prev := (
			step > 1 and EnemyRoster.level_for_step(step) == EnemyRoster.level_for_step(step - 1)
		)
		if EnemyRoster.is_band_second_step(step) != same_as_prev:
			violations.append("段%d: 帯の2段目判定が直前の段のレベルと食い違う" % step)
		var expected := 1.0 + EnemyRoster.BAND_SECOND_STEP_RPS_RAMP if same_as_prev else 1.0
		if not is_equal_approx(EnemyRoster.step_rps_scale(step), expected):
			violations.append("段%d: 倍率%.4f (期待%.4f)" % [
				step, EnemyRoster.step_rps_scale(step), expected])
	check.call(
		not EnemyRoster.is_band_second_step(MapTree.STEP_GOAL),
		"帯: ボス段(段%d)は帯の1段目=ランプが乗らない(ボス据え置き)" % MapTree.STEP_GOAL
	)
	check.call(
		EnemyRoster.is_band_second_step(2) and not EnemyRoster.is_band_second_step(1),
		"帯: 段1は1段目・段2は2段目(判定が空回りしていない)"
	)
	# 値そのものは調整対象なので固定しないが、**向き**は固定する。0にすると仕組みごと
	# 黙って無効になり、全テストが期待値を定数から組んでいるぶん全行一致で素通りする。
	check.call(
		EnemyRoster.BAND_SECOND_STEP_RPS_RAMP > 0.0
			and EnemyRoster.step_rps_scale(2) > EnemyRoster.step_rps_scale(1),
		"帯: 2段目のランプは正(0にすると仕組みごと無効になる) 実際=%.4f" % [
			EnemyRoster.BAND_SECOND_STEP_RPS_RAMP]
	)
	check.call(
		violations.is_empty(),
		"帯: 2段目判定と倍率が全段で一致%s" % (
			"" if violations.is_empty() else " / 例: " + violations[0])
	)


## 実際に生成した敵に、段のランプが**rpsだけ**・**2段目だけ**に乗ること。
## 帯の1段目とボス段は素の表と厳密一致(ランプが全段に漏れたら落ちる)。
## 質量は乱戦倍率のみ、半径・spin_decay は不変(ランプを別の軸へ移したら落ちる)。
func _test_band_ramp_only_on_second_step(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260808
	var violations: Array[String] = []
	var seen_ramped := false
	var seen_plain := false
	for _iter in 300:
		for step in range(1, MapTree.STEP_GOAL + 1):
			# 期待値は step_rps_scale を呼ばず**定数と段の並びから**組み立てる。
			# 被検査の関数から期待値を借りると、ランプを丸ごと落としても
			# 期待値まで一緒に1.0へ落ちて「全行一致」の嘘が通る。
			var second := step > 1 and (
				EnemyRoster.level_for_step(step) == EnemyRoster.level_for_step(step - 1)
			)
			var scale := 1.0 + EnemyRoster.BAND_SECOND_STEP_RPS_RAMP if second else 1.0
			if second:
				seen_ramped = true
			else:
				seen_plain = true
			for member in EnemyRoster.pick_group_for_step(step, rng):
				var base := _solo_of(member)
				if base == null:
					violations.append("素の個体が引けない: %s" % member.display_name)
					continue
				if not is_equal_approx(member.stats.rps, base.stats.rps * scale):
					violations.append("段%dの%s: rps%.4f (素%.4f×%.4f を期待)" % [
						step, member.display_name, member.stats.rps, base.stats.rps, scale])
				if not is_equal_approx(member.stats.radius, base.stats.radius):
					violations.append("段%dの%s: 半径が動いた(ランプはrpsだけのはず)" % [
						step, member.display_name])
				if not is_equal_approx(member.stats.spin_decay, base.stats.spin_decay):
					violations.append("段%dの%s: spin_decayが動いた" % [
						step, member.display_name])
	check.call(seen_ramped and seen_plain, "帯: ランプの有る段と無い段を両方見ている")
	check.call(
		violations.is_empty(),
		"帯: ランプはrpsだけ・帯の2段目だけに乗る%s" % (
			"" if violations.is_empty() else " / 例: " + violations[0])
	)


## **リトライで入れ替えた個体にもランプが乗り直すこと**。乱戦の質量倍率が同じ穴を
## 空けていた(素の表から引くとリトライしただけで元の手強さに戻る)ので、段の軸でも
## 同じ約束を守る。reroll_group に段を渡さない実装へ戻すと落ちる。
func _test_band_ramp_survives_reroll(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260809
	var violations: Array[String] = []
	var seen := 0
	for step in range(1, MapTree.STEP_GOAL + 1):
		# 期待値は定数から組む(被検査の関数から借りない。上の注釈と同じ理由)。
		var scale := 1.0 + EnemyRoster.BAND_SECOND_STEP_RPS_RAMP if (
			step > 1 and EnemyRoster.level_for_step(step) == EnemyRoster.level_for_step(step - 1)
		) else 1.0
		for _iter in 40:
			var group := EnemyRoster.pick_group_for_step(step, rng)
			for member in EnemyRoster.reroll_group(group, rng, step):
				var base := _solo_of(member)
				if base == null:
					continue
				seen += 1
				if not is_equal_approx(member.stats.rps, base.stats.rps * scale):
					violations.append("段%dの入れ替え個体%s: rps%.4f (素%.4f×%.4f を期待)" % [
						step, member.display_name, member.stats.rps, base.stats.rps, scale])
	check.call(seen > 0, "帯: リトライの入れ替えを実際に見ている (%d体)" % seen)
	check.call(
		violations.is_empty(),
		"帯: リトライで入れ替えてもランプが乗り直す%s" % (
			"" if violations.is_empty() else " / 例: " + violations[0])
	)


## **配線のテスト**。ランプの規則が正しくても、リトライ経路とコールドプレイCLIの
## 復元経路が段を渡し忘れると、その局面だけ敵が素の強さへ戻る——しかも
## 「ランプは難易度を1ミリも動かさない」という嘘の測定結果が出る。
## 前サイクルの BattleSim 配線落ち(素通り)と同じ穴なので、経路ごとに実際の値で見る。
func _test_band_ramp_wiring(check: Callable) -> void:
	const STEP := 2  # 帯の2段目。段9(ボス)と違って必ずランプが乗る。
	# 期待値は定数から組む(被検査の関数から借りない)。
	var scale := 1.0 + EnemyRoster.BAND_SECOND_STEP_RPS_RAMP
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260810
	var group := EnemyRoster.pick_group_for_step(STEP, rng, false)

	# 経路1: リトライ(相手を替える)。RetryPlan が段を落とすと素の値に戻る。
	var retry_ok := true
	for member in RetryPlan.next_enemies(group, false, rng, STEP):
		var base := _solo_of(member)
		if base != null and not is_equal_approx(member.stats.rps, base.stats.rps * scale):
			retry_ok = false
	check.call(retry_ok, "配線: RetryPlan.next_enemies が段のランプを引き継ぐ")

	# 経路2: CLI(naive_play)の名前列からの復元。段を落とすと素の値に戻る。
	var names: Array = []
	for member in group:
		names.append(member.display_name)
	# naive_play.gd は SceneTree 直下のスクリプトで class_name を持たないので load する
	# (test_playtest.gd と同じ流儀)。
	var naive_play = load("res://playtest/naive_play.gd")
	var restored: Array[EnemyData] = naive_play.group_from_names(names, group, STEP)
	var cli_ok := true
	for member in restored:
		var base := _solo_of(member)
		if base != null and not is_equal_approx(member.stats.rps, base.stats.rps * scale):
			cli_ok = false
	check.call(cli_ok, "配線: NaivePlay.group_from_names が段のランプを掛け直す")

	# 経路3: 実UIのリトライ(Main)とCLIのリトライが、段を**実際に渡している**こと。
	# 既定引数0(=倍率1.0)のまま呼べてしまうので、値のテストでは捕まらない。
	var main := FileAccess.get_file_as_string("res://scenes/main/Main.gd")
	check.call(
		main.contains("GameState.map_tree.current_step()"),
		"配線: Main のリトライが RetryPlan へ現在の段を渡している"
	)
	var cli := FileAccess.get_file_as_string("res://playtest/naive_play.gd")
	check.call(
		cli.contains("node.coord.x"),
		"配線: CLI のリトライが RetryPlan へノードの段を渡している"
	)
	var sim := FileAccess.get_file_as_string("res://playtest/run_sim.gd")
	check.call(
		sim.contains("EnemyRoster.reroll_group(group, rng, tree.current_step())"),
		"配線: run_sim のリトライが段を渡している(統計が実プレイとずれない)"
	)


## **生成されたマップの全戦闘ノード**でランプが乗っていること。抽選の入り口
## (pick_group_for_step)だけを見ていると、マップ生成の別経路が素の表から組んでいても
## 気づけない——実際 `MapTree._promote_compensation`(1体部屋保証の埋め合わせで
## 単体ノードを乱戦へ昇格する)は `group_of` を直接呼ぶので、そこが段を渡し忘れると
## **昇格した部屋だけ敵が素の強さに戻る**。ここはノードの座標(段)を真として、
## 盤面に実際に置かれた敵で確かめる。
func _test_band_ramp_on_generated_maps(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260811
	var violations: Array[String] = []
	var checked := 0
	var ramped := 0
	for _iter in 60:
		var tree := MapTree.generate(rng)
		if tree == null:
			continue
		for coord in tree.nodes:
			var node: MapTree.MapNode = tree.nodes[coord]
			if not node.has_encounter():
				continue
			# 期待値は定数から組む(被検査の関数から借りない)。
			var step: int = coord.x
			var second := step > 1 and (
				EnemyRoster.level_for_step(step) == EnemyRoster.level_for_step(step - 1)
			)
			var scale := 1.0 + EnemyRoster.BAND_SECOND_STEP_RPS_RAMP if second else 1.0
			for member in node.enemies:
				var base := _solo_of(member)
				if base == null:
					continue
				checked += 1
				if second:
					ramped += 1
				if not is_equal_approx(member.stats.rps, base.stats.rps * scale):
					violations.append("段%d列%dの%s(%d体): rps%.4f (素%.4f×%.4f を期待)" % [
						step, coord.y, member.display_name, node.enemy_count(),
						member.stats.rps, base.stats.rps, scale])
	check.call(
		checked > 0 and ramped > 0,
		"帯: 生成マップの戦闘ノードを実際に見ている (検査%d体 / うち2段目%d体)" % [checked, ramped]
	)
	check.call(
		violations.is_empty(),
		"帯: 生成マップの全戦闘ノードにランプが乗る(昇格補償の経路も含む)%s" % (
			"" if violations.is_empty() else " / 例: " + violations[0])
	)
