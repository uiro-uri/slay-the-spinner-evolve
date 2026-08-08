extends RefCounted

## threat_meter.gd のテスト。マップのノードに出す「相手の打たれ強さの取り分」メーターの、
## 値・出す相手の選び方・バーの幾何を確かめる。
##
## 見た目そのものは静止画では確かめられない(CLAUDE.mdの方針)ので、ここで固定するのは
## 「調整で数値を動かしても生き残る性質」だけ:
##   - 取り分が対戦画面の1行目「打たれ強さ 相手」と**同じ値**であること(定義の二重化を防ぐ)
##   - 互角でちょうど PARITY、格上で越える、格下で下回る(向き)
##   - メーターが rps を読むこと(硬さだけでは体力の差が出ない)
##   - 乱戦の脅威は頭数ぶんの和で、頭数が増えれば取り分も上がる
##   - 出すのは**進める先の戦闘ノードだけ**(遠いノードにもスタートにも出さない)
##   - バーはノードの下・ノードの直径ぶんの幅で、目盛りは必ず幅の中央

const EPS := 1e-4

## マップの実レイアウト定数(ピップの位置・段の間隔)を借りるため。メーターが既存の
## 表示と場所を取り合っていないことを、決め打ちの数値ではなく実定数で確かめる。
const MapScreenScript := preload("res://scenes/map/MapScreen.gd")


func run(check: Callable) -> void:
	_test_share_direction(check)
	_test_share_reads_rps(check)
	_test_share_matches_stat_readout(check)
	_test_group_counts_heads(check)
	_test_share_degenerate(check)
	_test_levels_are_ordered(check)
	_test_reachable_only(check)
	_test_hardest_is_one_body_not_the_room(check)
	_test_geometry(check)


## 硬さの取り分の向き。互角でちょうど PARITY、相手が硬いほど1へ寄る。
func _test_share_direction(check: Callable) -> void:
	var player := SpinnerStats.default_player()

	var even := ThreatMeter.share(player, [_enemy(player.mass, player.radius)])
	check.call(
		absf(even - StatReadout.PARITY) < EPS,
		"同じ硬さの相手はちょうど互角の目盛り: %.4f" % even
	)

	# 質量だけを倍にした相手。硬さ=質量×半径² なので確実に格上。
	var tough := ThreatMeter.share(player, [_enemy(player.mass * 2.0, player.radius)])
	check.call(tough > StatReadout.PARITY, "硬い相手は目盛りを越える: %.4f" % tough)

	var soft := ThreatMeter.share(player, [_enemy(player.mass * 0.25, player.radius)])
	check.call(soft < StatReadout.PARITY, "柔らかい相手は目盛りに届かない: %.4f" % soft)

	# 取り分なので上端を決め打たなくても頭打ちにならない。100倍差でも1未満に収まる。
	var huge := ThreatMeter.share(player, [_enemy(player.mass * 100.0, player.radius * 3.0)])
	check.call(
		huge > tough and huge < 1.0,
		"桁違いに硬い相手でも0〜1に収まりつつ単調に増える: %.4f" % huge
	)


## **定義の二重化を防ぐ検査**。マップの取り分は、対戦画面のビルド表示が出す
## 1行目「打たれ強さ 相手」と1ptも違ってはいけない。片方だけ別式に直されたらここが落ちる。
func _test_share_matches_stat_readout(check: Callable) -> void:
	var player := SpinnerStats.default_player()
	var cases := [
		[_enemy(0.8, 0.38)],
		[_enemy(2.1, 0.92), _enemy(1.8, 0.94)],
		[_enemy(6.0, 1.4)],
	]
	for enemies in cases:
		var typed: Array[EnemyData] = []
		typed.assign(enemies)
		var mine := ThreatMeter.share(player, typed)
		var rows := StatReadout.enemy_rows(player, ThreatMeter.stats_of(typed))
		check.call(
			rows.size() == 3 and absf(float(rows[0]["fraction"]) - mine) < EPS,
			"マップの取り分が対戦画面の「打たれ強さ 相手」と一致: %.4f" % mine
		)


## **メーターが rps を読むこと**。硬さ(質量×半径²)だけの軸だった頃、体力が2倍違う
## 相手が同じ長さのメーターで並んでいた。
##
## 一次証拠(コールドプレイ 2026-08-08 深夜, seed=4711): 段4で「取り分0.55 格上」と
## 出た部屋に入って3連敗した。0.55 は互角の目盛りのすぐ隣なので五分に見えるが、
## 実際は自分の rps 18 に対し相手が 31 で、回転の持ち分が 1.7倍 違う部屋だった。
## 統計でも自機の rps だけを 12→36 に振ると Lv2×2体の勝率は 34%→99% と動くのに、
## 硬さ取り分は 0.51 で不動(playtest/measure_threat_axis.gd)。
func _test_share_reads_rps(check: Callable) -> void:
	var player := SpinnerStats.default_player()

	# 硬さは同じ・回転だけ2倍の相手。旧軸(硬さ)なら互角、新軸なら格上。
	var same := _enemy(player.mass, player.radius)
	var spun := _enemy(player.mass, player.radius)
	spun.stats.rps = player.rps * 2.0
	var sames: Array[EnemyData] = [same]
	var spuns: Array[EnemyData] = [spun]
	var flat := ThreatMeter.share(player, sames)
	var fast := ThreatMeter.share(player, spuns)
	check.call(
		absf(flat - StatReadout.PARITY) < EPS,
		"回転も同じ相手はちょうど互角: %.4f" % flat
	)
	check.call(
		fast > flat + 0.05,
		"硬さが同じでも回転が2倍なら格上に出る: %.4f -> %.4f" % [flat, fast]
	)
	# 硬さの軸では**同じ値**にしか見えない2部屋であることを、旧軸で直に押さえる。
	# ここが等しくなければ、上の差は硬さ由来で rps を読んだ証拠にならない。
	check.call(
		absf(StatReadout.toughness_share(player, ThreatMeter.stats_of(sames))
			- StatReadout.toughness_share(player, ThreatMeter.stats_of(spuns))) < EPS,
		"この2部屋は硬さの取り分では見分けが付かない"
	)

	# 自分の回転が伸びれば同じ部屋の脅威は下がる。撃破ボーナス(+1.0)や回転札の効きが
	# マップに出る、ということ。硬さの軸ではここも動かなかった。
	var wound := SpinnerStats.default_player()
	wound.rps = player.rps * 2.0
	check.call(
		ThreatMeter.share(wound, spuns) < fast,
		"自分の回転が伸びると同じ部屋の取り分は下がる"
	)
	check.call(
		absf(StatReadout.toughness_share(wound, ThreatMeter.stats_of(spuns))
			- StatReadout.toughness_share(player, ThreatMeter.stats_of(spuns))) < EPS,
		"硬さの取り分は自分の回転では動かない(比較用の錨)"
	)


## 乱戦の脅威は**頭数ぶんの和**。最大にしていた頃は、同じレベルなら1体でも3体でも
## メーターが同じ長さになり、部屋を選ぶ材料として頭数が完全に抜け落ちていた
## (コールドプレイ 2026-08-03: 段5の「Lv3 2体」と隣の「Lv3 1体」がどちらも0.6台で、
## 実測の勝率は 24.8% と 91.2%)。
func _test_group_counts_heads(check: Callable) -> void:
	var player := SpinnerStats.default_player()
	var strong := _enemy(3.0, 1.0)
	var weak := _enemy(0.2, 0.3)

	var alone: Array[EnemyData] = [strong]
	var mixed: Array[EnemyData] = [weak, strong, weak]
	check.call(
		ThreatMeter.share(player, mixed) > ThreatMeter.share(player, alone),
		"弱い個体でも足せば取り分は上がる(頭数はそれ自体が脅威)"
	)

	var only_weak: Array[EnemyData] = [weak, weak, weak]
	check.call(
		ThreatMeter.share(player, only_weak) < ThreatMeter.share(player, mixed),
		"硬い個体が混ざれば取り分は上がる"
	)

	# 同じ個体を並べたときの単調性。ここが「1体でも3体でも同じ長さ」を潰している。
	var two: Array[EnemyData] = [strong, strong]
	var three: Array[EnemyData] = [strong, strong, strong]
	var s1 := ThreatMeter.share(player, alone)
	var s2 := ThreatMeter.share(player, two)
	var s3 := ThreatMeter.share(player, three)
	check.call(s1 < s2 and s2 < s3, "同じ相手でも頭数で取り分が上がる: %.3f/%.3f/%.3f" % [s1, s2, s3])

	# 実ロスターで、コールドプレイが読み違えた並びを直接押さえる。
	# 「Lv3 2体」は「Lv3 1体」より上で、「Lv3 3体」は「Lv4 1体」を越える
	# (実測勝率は Lv3×3体 8.2% / Lv4×1体 5.2% でほぼ同じきつさ)。
	var lv3 := EnemyRoster.of_level(3)[0]
	var lv4 := EnemyRoster.of_level(4)[0]
	var lv3_one: Array[EnemyData] = [lv3]
	var lv3_two: Array[EnemyData] = [lv3, lv3]
	var lv3_three: Array[EnemyData] = [lv3, lv3, lv3]
	var lv4_one: Array[EnemyData] = [lv4]
	check.call(
		ThreatMeter.share(player, lv3_two) > ThreatMeter.share(player, lv3_one) + 0.05,
		"Lv3の2体は1体よりはっきり上: %.3f vs %.3f" % [
			ThreatMeter.share(player, lv3_two), ThreatMeter.share(player, lv3_one)
		]
	)
	check.call(
		ThreatMeter.share(player, lv3_three) > ThreatMeter.share(player, lv4_one),
		"Lv3の3体はLv4単体を越える: %.3f vs %.3f" % [
			ThreatMeter.share(player, lv3_three), ThreatMeter.share(player, lv4_one)
		]
	)


## 値が取れないときは互角に倒す。0埋めは「相手が弱い」という別の嘘になる。
func _test_share_degenerate(check: Callable) -> void:
	var player := SpinnerStats.default_player()
	var empty: Array[EnemyData] = []
	check.call(
		absf(ThreatMeter.share(player, empty) - StatReadout.PARITY) < EPS,
		"相手が居なければ互角扱い"
	)
	var nulls: Array[EnemyData] = [null]
	check.call(
		absf(ThreatMeter.share(player, nulls) - StatReadout.PARITY) < EPS,
		"中身がnullでも互角扱い(0埋めしない)"
	)
	check.call(
		absf(ThreatMeter.share(null, [_enemy(1.0, 0.5)]) - StatReadout.PARITY) < EPS,
		"自分のstatsが無ければ互角扱い"
	)
	check.call(ThreatMeter.stats_of(nulls).is_empty(), "nullの敵はstats_ofが捨てる")


## **コールドプレイの主張そのもの**: 初期ビルドから見て Lv1 は目盛りの下、
## Lv3 以上は目盛りの上に出る。ここが崩れたらメーターは部屋を選ぶ役に立たない。
## 実ロスター(EnemyRoster)から引くので、敵の数値を触ったときにも効く。
func _test_levels_are_ordered(check: Callable) -> void:
	var player := SpinnerStats.default_player()
	var shares: Array[float] = []
	for level in range(1, 6):
		# **1体だけ**渡す。部屋の硬さは頭数ぶんの和なので、レベル内の全個体を
		# 1部屋にすると「レベルの差」ではなく「そのレベルの個体数」を測ってしまう。
		var one: Array[EnemyData] = [EnemyRoster.of_level(level)[0]]
		shares.append(ThreatMeter.share(player, one))

	var ordered := true
	for i in range(1, shares.size()):
		if shares[i] <= shares[i - 1]:
			ordered = false
	check.call(ordered, "レベルが上がるほど取り分も上がる: %s" % [shares])
	check.call(
		shares[0] < StatReadout.PARITY,
		"初期ビルドから見てLv1は格下(目盛りの下): %.4f" % shares[0]
	)
	check.call(
		shares[2] > StatReadout.PARITY,
		"初期ビルドから見てLv3は格上(目盛りの上・4連敗した段5の相手): %.4f" % shares[2]
	)


## 出すのは**進める先の戦闘ノードだけ**。遠いノードの取り分は今のビルドとの比なので
## そこへ着く頃には嘘になっているし、スタート(遭遇なし)には相手が居ない。
func _test_reachable_only(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260802
	var tree := MapTree.generate(rng)
	var player := SpinnerStats.default_player()

	var shares := ThreatMeter.reachable_shares(tree, player)
	var reachable := tree.next_coords()

	check.call(not shares.is_empty(), "進める先があればメーターも出る: %d件" % shares.size())
	check.call(
		shares.size() == reachable.size(),
		"進める先の数と一致(段1は全部が戦闘ノード): %d/%d" % [shares.size(), reachable.size()]
	)

	var all_reachable := true
	var all_encounter := true
	for coord in shares:
		if not coord in reachable:
			all_reachable = false
		if not tree.nodes[coord].has_encounter():
			all_encounter = false
	check.call(all_reachable, "進める先以外のノードには出さない")
	check.call(all_encounter, "戦闘ノードにだけ出す")
	check.call(
		not shares.has(tree.current_coord), "今いるノードには出さない(もう選ぶ対象ではない)"
	)


	# 値がノードごとの相手から引かれていること(全ノード同じ定数を返していない)。
	for coord in shares:
		var expected := ThreatMeter.share(player, tree.nodes[coord].enemies)
		check.call(
			absf(float(shares[coord]) - expected) < EPS,
			"ノード%s の取り分がそのノードの相手から出ている" % [coord]
		)

	check.call(ThreatMeter.reachable_shares(null, player).is_empty(), "マップが無ければ空")

	# 遭遇除けを空振りさせない。今の生成では進める先は必ず戦闘ノードなので、
	# 相手を空にしたノードを混ぜて「相手が居ないノードは落とす」を実際に踏ませる
	# (踏まないと、除けを消しても誰も落ちない=検査していないのと同じ)。
	var emptied: Vector2i = reachable[0]
	tree.nodes[emptied].enemies = [] as Array[EnemyData]
	var after := ThreatMeter.reachable_shares(tree, player)
	check.call(
		not after.has(emptied) and after.size() == shares.size() - 1,
		"相手が居ないノードは落とす: %d→%d件" % [shares.size(), after.size()]
	)


## バーの幾何。ノードの下・直径ぶんの幅で、目盛りは必ず幅の中央。
func _test_geometry(check: Callable) -> void:
	var center := Vector2(200.0, 120.0)
	var radius := 18.0
	var track := ThreatMeter.track_rect(center, radius, 1.0)

	check.call(
		absf(track.size.x - radius * 2.0) < EPS,
		"幅はノードの直径: %.2f" % track.size.x
	)
	check.call(
		absf((track.position.x + track.size.x * 0.5) - center.x) < EPS,
		"ノードの中心に揃う"
	)
	check.call(track.position.y > center.y + radius, "ノードの下辺より下に置く")

	# **既存の表示と場所を取り合っていないこと**。マップのノードの下辺には既に敵数ピップが
	# 並び、その下には次の段のノード(報酬ピップが上に付く)が来る。純粋関数のテストだけでは
	# 「値は正しいが画面では他の要素の上に描かれている」を見逃すので、MapScreen の
	# 実定数からピップの実占有域を組み立てて挟み撃ちにする。目盛りは外枠より縦に長いので
	# 外枠ではなく目盛りの上下端で見る。
	var tick_design := ThreatMeter.parity_rect(track, 1.0)
	var pips_bottom := center.y + radius + MapScreenScript.PIP_OFFSET + MapScreenScript.PIP_RADIUS
	# 次の段のノード中心は CELL.y だけ下。その報酬ピップは中心の上 NODE_RADIUS+PIP_OFFSET。
	var below_top := (
		center.y + MapScreenScript.CELL.y
		- MapScreenScript.NODE_RADIUS - MapScreenScript.PIP_OFFSET - MapScreenScript.PIP_RADIUS
	)
	check.call(
		tick_design.position.y >= pips_bottom + 1.0,
		"敵数ピップの下端(%.1f)より下に置く: %.1f" % [pips_bottom, tick_design.position.y]
	)
	check.call(
		tick_design.end.y <= below_top - 1.0,
		"次の段の報酬ピップの上端(%.1f)より上で収まる: %.1f" % [below_top, tick_design.end.y]
	)

	# 縦画面の拡大率。オフセットも高さも一緒に伸びないと、拡大したときだけ
	# ノードに食い込む/離れすぎる。
	var scaled := ThreatMeter.track_rect(center, radius * 2.0, 2.0)
	check.call(
		absf(scaled.size.y - track.size.y * 2.0) < EPS,
		"拡大率が高さに掛かる: %.2f" % scaled.size.y
	)
	check.call(
		absf((scaled.position.y - (center.y + radius * 2.0)) - (track.position.y - (center.y + radius)) * 2.0) < EPS,
		"拡大率がノード下辺からの距離にも掛かる"
	)

	# 埋まりは左詰めで取り分に比例し、範囲外は端で頭打ち。
	check.call(ThreatMeter.fill_rect(track, 0.0).size.x < EPS, "取り分0なら埋まらない")
	check.call(
		absf(ThreatMeter.fill_rect(track, 1.0).size.x - track.size.x) < EPS,
		"取り分1で満タン"
	)
	check.call(
		absf(ThreatMeter.fill_rect(track, 2.0).size.x - track.size.x) < EPS,
		"1を超えても溢れない"
	)
	check.call(ThreatMeter.fill_rect(track, -1.0).size.x < EPS, "負でも0で止まる")
	var half := ThreatMeter.fill_rect(track, 0.5)
	check.call(
		absf(half.size.x - track.size.x * 0.5) < EPS and absf(half.position.x - track.position.x) < EPS,
		"埋まりは左詰めで取り分に比例"
	)
	check.call(
		absf(half.size.y - track.size.y) < EPS, "埋まりの高さは外枠と同じ"
	)

	# 目盛りは互角の位置=幅のちょうど中央。埋まりの先端と見分けるため上下へはみ出す。
	var tick := ThreatMeter.parity_rect(track, 1.0)
	check.call(
		absf((tick.position.x + tick.size.x * 0.5) - (track.position.x + track.size.x * StatReadout.PARITY)) < EPS,
		"目盛りは互角(=幅の中央)に立つ"
	)
	check.call(
		absf((tick.position.x + tick.size.x * 0.5) - (half.position.x + half.size.x)) < EPS,
		"取り分0.5のときだけ埋まりの先端が目盛りに一致する"
	)
	check.call(
		tick.position.y < track.position.y and tick.end.y > track.end.y,
		"目盛りは外枠の上下へはみ出す"
	)


## 報酬画面の攻め力(PartPreview.attack)の基準にする相手。
##
## **1体ぶんの最大であって、部屋の和ではない**。攻め力は「1接触で相手から削れるrps」
## なので、頭数を足し込むと3体の部屋で攻め力が1/3に見え、「乱戦ほど攻め札が無価値」
## という逆の嘘になる(部屋の脅威 room_toughness が和なのは「この部屋を抜けられるか」
## の話で、1回の噛み合いの相手はそのうちの1体でしかない)。
##
## 進める先が無ければ -1.0。決戦のあとがそれで、そこでは攻めの行を出さない。
func _test_hardest_is_one_body_not_the_room(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260806
	var tree := MapTree.generate(rng)

	var hardest := ThreatMeter.reachable_hardest_toughness(tree)
	# 進める先の全個体を素で舐めた最大と一致すること(和でも平均でもない)。
	var expected := -1.0
	var total := 0.0
	var bodies := 0
	for coord in tree.next_coords():
		var node: MapTree.MapNode = tree.nodes[coord]
		if not node.has_encounter():
			continue
		for stats in ThreatMeter.stats_of(node.enemies):
			expected = maxf(expected, PartPreview.toughness(stats))
			total += PartPreview.toughness(stats)
			bodies += 1
	check.call(bodies > 1, "検査に使う段に相手が複数居る: %d体" % bodies)
	check.call(
		absf(hardest - expected) < EPS,
		"進める先のいちばん硬い1体: %.4f (期待 %.4f)" % [hardest, expected]
	)
	check.call(
		hardest < total - EPS,
		"頭数ぶんの和ではない: 最大%.4f < 和%.4f" % [hardest, total]
	)

	# 進める先が無い(ゴールに立っている)なら基準の相手も無い。
	var goal := MapTree.generate(rng)
	goal.current_coord = MapTree.GOAL_COORD
	check.call(
		goal.next_coords().is_empty()
		and ThreatMeter.reachable_hardest_toughness(goal) < 0.0,
		"進める先が無ければ基準の相手も無い(-1)"
	)
	check.call(
		ThreatMeter.reachable_hardest_toughness(null) < 0.0,
		"マップが無ければ基準の相手も無い(-1)"
	)


## 硬さ(質量×半径²)だけを指定した相手を作る。他の数値は既定のまま。
func _enemy(mass: float, radius: float) -> EnemyData:
	var stats := SpinnerStats.default_player()
	stats.mass = mass
	stats.radius = radius
	return EnemyData.make(1, "TEST", stats)
