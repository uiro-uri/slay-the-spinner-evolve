extends RefCounted

## wall_cost_preview.gd(発射前の「届くまでに壁でいくら失うか」)のテスト。
##
## この機能の値打ちは RendezvousPreview とまったく同じ一点、**見積もりが
## 嘘をつかないこと**にある。「壁で22%持っていかれる」と言っておいて本番が
## 別の数字なら、無いほうがましになる。だから単体の性質だけでなく、
## **実リゾルバ(BattleResolver)に同じ発射を解かせて、同じ窓のあいだに
## 記録された壁の衝撃波の合計と一致するか**まで見る。
##
## もう一つの約束は「引きを比べる道具になっていること」——同じ狙いで引きだけを
## 強めたら見積もりが増える、が成り立つこと。ここが崩れると、
## コールドプレイで見えなかった「満引きの罰」は見えるようにならない。


func run(check: Callable) -> void:
	_test_no_wall_no_cost(check)
	_test_charges_a_wall_hit(check)
	_test_agrees_with_resolver(check)
	_test_agrees_with_resolver_over_random_launches(check)
	_test_stronger_pull_costs_more(check)
	_test_wall_keep_cuts_the_bill(check)
	_test_sliding_contact_billed_once(check)
	_test_window_is_monotone(check)
	_test_obstacles_are_billed(check)
	_test_degenerate_step(check)
	_test_pure(check)
	_test_notable_threshold(check)
	_test_hint_text(check)
	_test_translations(check)
	_test_shares_the_resolver_formula(check)
	_test_wired_into_battle(check)
	_test_wired_into_cli(check)


const _NO_OBSTACLES: Array[Vector3] = []


func _rect_walls(center: Vector2, inradius: float) -> Array[ArenaWall]:
	return ArenaWall.from_rect(
		Rect2(center - Vector2.ONE * inradius, Vector2.ONE * inradius * 2.0))


func _stats(radius: float = 0.7, rps: float = 20.0) -> SpinnerStats:
	var s := SpinnerStats.new()
	s.mass = 1.5
	s.radius = radius
	s.friction = 0.0
	s.restitution = 0.75
	s.rps = rps
	return s


## 傾斜も摩擦も無い既定のリクエスト。壁の調整値は BattleRequest の既定のまま
## (＝本番の既定と同じ)なので、見積もりの検算は本番の式そのものになる。
func _request() -> BattleRequest:
	var r := BattleRequest.new()
	r.arena_bounds = Rect2(0, 0, 10, 10)
	r.wall_shape = ArenaWall.WallShape.RECT
	r.stage_strength = 0.0
	r.natural_damping = 0.0
	return r


func _cost(
	pos: Vector2, vel: Vector2, stats: SpinnerStats, req: BattleRequest,
	walls: Array[ArenaWall], obstacles: Array[Vector3] = _NO_OBSTACLES,
	until: float = RendezvousPreview.DEFAULT_HORIZON
) -> Dictionary:
	return WallCostPreview.approach_cost(
		pos, vel, stats, Vector2(5, 5), req.stage_strength, req.stage_shape,
		walls, obstacles, req, until
	)


## 壁へ向かわない狙いには何も請求しない。ここが0でないと、全部の狙いに
## 警告が出て1行が意味を失う。
func _test_no_wall_no_cost(check: Callable) -> void:
	var stats := _stats()
	var req := _request()
	# 中心へ向かって撃つ。地平(1.4s)のあいだ壁へは届かない。
	var cost := _cost(Vector2(1.5, 5.0), Vector2(2.0, 0.0), stats, req, _rect_walls(Vector2(5, 5), 5.0))
	check.call(int(cost["hits"]) == 0, "壁の代償: 壁へ向かわない狙いは0回")
	check.call(is_zero_approx(float(cost["rps_loss"])), "壁の代償: 0回なら喪失も0")
	check.call(is_zero_approx(float(cost["loss_share"])), "壁の代償: 0回なら割合も0")
	check.call(
		is_zero_approx(float(cost["first_time"])) and is_zero_approx(float(cost["first_speed"])),
		"壁の代償: 0回なら初回の時刻も進入速度も0"
	)


## 壁へ真っ直ぐ撃てば請求が立つ。時刻・進入速度・割合がそろって埋まること。
func _test_charges_a_wall_hit(check: Callable) -> void:
	var stats := _stats()
	var req := _request()
	# 右壁(x=10)まで 10-6.0-0.7 = 3.3 ユニット。速さ10なら 0.33 秒。
	var cost := _cost(Vector2(6.0, 5.0), Vector2(10.0, 0.0), stats, req, _rect_walls(Vector2(5, 5), 5.0))
	check.call(int(cost["hits"]) >= 1, "壁の代償: 壁へ撃てば請求が立つ")
	check.call(float(cost["rps_loss"]) > 0.0, "壁の代償: 請求が立てば回転を失う")
	check.call(
		absf(float(cost["first_time"]) - 0.33) < 0.05,
		"壁の代償: 初回の時刻が幾何どおり (%.3fs)" % cost["first_time"]
	)
	check.call(
		absf(float(cost["first_speed"]) - 10.0) < 0.5,
		"壁の代償: 初回の進入速度が発射の速さ (%.2f)" % cost["first_speed"]
	)
	check.call(
		absf(float(cost["loss_share"]) - float(cost["rps_loss"]) / stats.rps) < 1e-5,
		"壁の代償: 割合は喪失÷回転ゲージ"
	)


## 本丸。**同じ発射を本番のリゾルバに解かせ、同じ窓のあいだに自分が受けた
## 壁の衝撃波の合計と一致するか**を見る。ここが合っていなければ、見積もりは
## ただの別の数字であって「発射前に本番を覗く」ことにならない。
##
## 相手は窓のあいだ届かない位置へ置く(接触が挟まると自由飛行が本番とずれるのは
## 当たり前で、そこは見積もりの守備範囲の外)。
func _test_agrees_with_resolver(check: Callable) -> void:
	# 本番の傾斜つき・1回だけ当たる形(窓は初接触0.77sの手前で切る)。
	_check_against_resolver(
		check, "傾斜あり", Rect2(0, 0, 10, 10), Vector2(5, 5), 4.9,
		Vector2(6.0, 5.6), Vector2(11.0, 1.5), Vector2(1.2, 1.2), 0.70, 1
	)
	# 狭い土俵で2回当たる形。回数の数え方(課金の切れ目)まで照合するには
	# 複数回のケースが要る。傾斜を切って相手を窓の外へ遠ざけてある。
	_check_against_resolver(
		check, "2回", Rect2(0, 0, 6, 6), Vector2(3, 3), 0.0,
		Vector2(4.0, 3.0), Vector2(12.0, 0.5), Vector2(1.0, 5.0), 1.20, 2
	)
	# **柱の縁へ密着したまま柱へ突っ込む**形。発射位置は FieldData.clamp_placement が
	# 柱の縁へ寄せるので実際に起きる配置で、しかもいちばん痛い狙い。
	# 「密着しているなら接触中として始める」ともっともらしく書くと、ここで1回目の
	# 課金が消えて見積もりが本番の半分(1回/2.25 対 2回/4.50)になる——見積もりが
	# 本番より軽く出るのがこの機能で最悪の嘘なので、名指しで縛る。
	_check_against_resolver(
		check, "柱に密着した発射", Rect2(0, 0, 10, 10), Vector2(5, 5), 0.0,
		Vector2(5.0, 5.2), Vector2(0.0, 9.0), Vector2(1.0, 1.0), 1.00, 2,
		[Vector3(5.0, 6.5, 0.6)] as Array[Vector3]
	)


func _check_against_resolver(
	check: Callable, label: String, bounds: Rect2, center: Vector2, slope: float,
	start: Vector2, my_vel: Vector2, their_pos: Vector2, until: float, want_hits: int,
	obstacles: Array[Vector3] = _NO_OBSTACLES
) -> void:
	var mine := SpinnerStats.default_player()
	var theirs := SpinnerStats.default_player()

	var req := BattleRequest.new()
	req.arena_bounds = bounds
	req.wall_shape = ArenaWall.WallShape.RECT
	req.stage_strength = slope
	req.obstacles = obstacles
	req.player = BattleRequest.Launch.new(mine, start, my_vel)
	# 窓のあいだ自分とは噛み合わない位置に静止させておく。
	req.enemies = [
		BattleRequest.Launch.new(theirs, their_pos, Vector2.ZERO)
	] as Array[BattleRequest.Launch]

	var walls := ArenaWall.build(req.wall_shape, req.arena_bounds)
	var predicted := WallCostPreview.approach_cost(
		start, my_vel, mine, center, req.stage_strength, req.stage_shape,
		walls, req.obstacles, req, until
	)
	check.call(
		int(predicted["hits"]) == want_hits,
		"壁の代償(%s): 検算に使う発射は壁に%d回当たる (%d回)"
			% [label, want_hits, predicted["hits"]]
	)

	var result := BattleResolver.resolve(req)
	var actual_loss := 0.0
	var actual_hits := 0
	for impact in result.wall_impacts:
		if impact.owner != BattleResult.Impact.OWNER_PLAYER:
			continue
		if impact.time > until:
			continue
		actual_loss += impact.strength
		actual_hits += 1
	# 相手に触れる前だけを比べる(触れた後は自由飛行が嘘になる=見積もりの守備範囲の外)。
	var first_contact: float = result.impacts[0].time if not result.impacts.is_empty() else INF
	check.call(
		first_contact > until,
		"壁の代償(%s): 検算の窓のあいだ相手には触れない (初接触%.2fs)" % [label, first_contact]
	)
	check.call(
		actual_hits == int(predicted["hits"]),
		"壁の代償(%s): 本番と同じ回数を数える (見積もり%d / 本番%d)"
			% [label, predicted["hits"], actual_hits]
	)
	check.call(
		absf(actual_loss - float(predicted["rps_loss"])) < 0.01,
		"壁の代償(%s): 本番と同じ量を請求する (見積もり%.3f / 本番%.3f)"
			% [label, predicted["rps_loss"], actual_loss]
	)


## 手で選んだ数例では足りない。壁の課金には「面から離れずに続く接触は1回」
## (billable)・「めり込みを解いてから次の刻みへ」といった、**特定の1フレームでしか
## 差の出ない**規則が並んでいて、狙って踏むのが難しいため。実測でも、課金ガードを
## 外す/めり込み解消を省く改変は上の3例をすべてすり抜けた。
##
## そこで**ランダムな発射を多数**流し、そのたび本番のリゾルバに解かせて
## 「相手に触れる前の窓」で1件ずつ突き合わせる。1件でも合わなければ落とす。
## 種を固定してあるので、落ちたときは同じ発射がそのまま再現する。
func _test_agrees_with_resolver_over_random_launches(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260809
	var pillars: Array[Vector3] = [Vector3(7.0, 3.0, 0.6), Vector3(3.0, 7.0, 0.6)]
	var none: Array[Vector3] = []
	var walls := ArenaWall.build(ArenaWall.WallShape.RECT, Rect2(0, 0, 10, 10))
	var corners := [Vector2(10, 10), Vector2(0, 10), Vector2(10, 0), Vector2(0, 0)]

	# 集計は辞書1つに積む(compared/with_hits/first_mismatch)。
	var tally := {"compared": 0, "with_hits": 0, "mismatch": ""}

	# 1) 土俵じゅうから満遍なく。ふつうの狙いで嘘をつかないこと。
	for trial in 60:
		var obstacles: Array[Vector3] = pillars if trial % 2 == 0 else none
		_compare_one(
			tally, walls, obstacles, [0.0, 4.9, 8.0][trial % 3],
			Vector2(rng.randf_range(1.0, 9.0), rng.randf_range(1.0, 9.0)),
			Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0))
		)

	# 2) **隅と柱を名指しで狙う**。課金の切れ目(billable)もめり込み解消も、
	# 「面を続けて踏む」ときにしか差が出ない規則なので、満遍なく撒くだけでは
	# 数百発に1発しか踏まない(実測: 一様サンプルでは4000発で3発)。
	# 隅・柱へ向けて撃つと分離率が1〜2%まで上がるので、そこを厚く撃つ。
	for trial in 400:
		var target: Vector2 = (
			corners[trial % 4] if trial % 2 == 0
			else Vector2(pillars[trial % 2].x, pillars[trial % 2].y)
		)
		var dir := (target - Vector2(5, 5)).normalized()
		var start := (
			target - dir * rng.randf_range(2.0, 5.0)
			+ Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2))
		)
		var aim := (
			(target - start).normalized().rotated(rng.randf_range(-0.25, 0.25))
			* rng.randf_range(7.0, 12.0)
		)
		_compare_one(tally, walls, pillars, [0.0, 4.9, 8.0][trial % 3], start, aim)

	check.call(
		int(tally["compared"]) >= 300,
		"壁の代償(乱撃): 比べた発射が十分ある (%d件)" % tally["compared"]
	)
	check.call(
		int(tally["with_hits"]) >= 150,
		"壁の代償(乱撃): そのうち壁に当たる発射が十分ある (%d件)" % tally["with_hits"]
	)
	check.call(
		tally["mismatch"] == "",
		"壁の代償(乱撃): 全件で本番と一致する (最初の不一致: %s)" % tally["mismatch"]
	)


## 発射1件を本番と突き合わせて tally へ積む。置けない場所からは撃たない。
func _compare_one(
	tally: Dictionary, walls: Array[ArenaWall], obstacles: Array[Vector3],
	slope: float, start: Vector2, vel: Vector2
) -> void:
	var mine := SpinnerStats.default_player()
	if not _legal_start(start, mine.radius, walls, obstacles):
		return

	var req := BattleRequest.new()
	req.arena_bounds = Rect2(0, 0, 10, 10)
	req.wall_shape = ArenaWall.WallShape.RECT
	req.stage_strength = slope
	req.obstacles = obstacles
	# 見るのは先読みの地平(1.4s)までなので、そこを少し越えたら本番も打ち切る。
	# 既定の120秒ぶんを解かせると、この1件だけでスイート全体より時間を食う。
	req.max_duration = RendezvousPreview.DEFAULT_HORIZON + 0.1
	req.player = BattleRequest.Launch.new(mine, start, vel)
	req.enemies = [
		BattleRequest.Launch.new(SpinnerStats.default_player(), Vector2(1.5, 1.5), Vector2.ZERO)
	] as Array[BattleRequest.Launch]

	var result := BattleResolver.resolve(req)
	var first_contact: float = result.impacts[0].time if not result.impacts.is_empty() else INF
	# 窓は「相手に触れる手前」まで。触れた後は自由飛行が嘘になるので比べない。
	var until: float = minf(RendezvousPreview.DEFAULT_HORIZON, first_contact - 0.02)
	if until <= 0.0:
		return

	var predicted := WallCostPreview.approach_cost(
		start, vel, mine, Vector2(5, 5), req.stage_strength, req.stage_shape,
		walls, obstacles, req, until
	)
	var actual_loss := 0.0
	var actual_hits := 0
	for impact in result.wall_impacts:
		if impact.owner != BattleResult.Impact.OWNER_PLAYER or impact.time > until:
			continue
		actual_loss += impact.strength
		actual_hits += 1

	tally["compared"] = int(tally["compared"]) + 1
	if actual_hits > 0:
		tally["with_hits"] = int(tally["with_hits"]) + 1
	var agrees := (
		actual_hits == int(predicted["hits"])
		and absf(actual_loss - float(predicted["rps_loss"])) < 0.01
	)
	if not agrees and tally["mismatch"] == "":
		tally["mismatch"] = "pos=%s vel=%s 傾斜%.1f 柱%d 窓%.2fs → 見積もり%d回/%.3f 本番%d回/%.3f" % [
			str(start), str(vel), slope, obstacles.size(), until,
			predicted["hits"], predicted["rps_loss"], actual_hits, actual_loss
		]


## 発射位置として合法か(壁の内側・柱の外)。
func _legal_start(
	pos: Vector2, radius: float, walls: Array[ArenaWall], obstacles: Array[Vector3]
) -> bool:
	for w in walls:
		if SpinnerPhysics.wall_gap(w.point, w.normal, pos, radius) > 0.0:
			return false
	for o in obstacles:
		if SpinnerPhysics.obstacle_gap(Vector2(o.x, o.y), o.z, pos, radius) > 0.0:
			return false
	return true


## 引きを強めたら見積もりも増える。コールドプレイで見えなかった「満引きの罰」が
## 見えるようになる、の中身がこれ。値ではなく向きを縛るので調整に強い。
func _test_stronger_pull_costs_more(check: Callable) -> void:
	var stats := _stats()
	var req := _request()
	var walls := _rect_walls(Vector2(5, 5), 5.0)
	var weak := _cost(Vector2(6.0, 5.0), Vector2(5.0, 0.0), stats, req, walls)
	var strong := _cost(Vector2(6.0, 5.0), Vector2(12.0, 0.0), stats, req, walls)
	check.call(
		int(weak["hits"]) > 0 and int(strong["hits"]) > 0,
		"壁の代償: 弱い引きも強い引きも壁までは届く(比較が成立する)"
	)
	check.call(
		float(strong["rps_loss"]) > float(weak["rps_loss"]),
		"壁の代償: 強く引くほど壁が高くつく (弱%.2f < 強%.2f)"
			% [weak["rps_loss"], strong["rps_loss"]]
	)
	check.call(
		float(strong["first_speed"]) > float(weak["first_speed"]),
		"壁の代償: 強く引くほど進入速度が速い"
	)


## Rage Reflection(wall_keep)を積んだコマは同じ狙いでも請求が軽い。
## 札の効果が見積もりに映らないと、「積んだのに数字が動かない」になる。
func _test_wall_keep_cuts_the_bill(check: Callable) -> void:
	var bare := _stats()
	var tough := _stats()
	tough.wall_keep = 0.4
	var req := _request()
	var walls := _rect_walls(Vector2(5, 5), 5.0)
	var a := _cost(Vector2(6.0, 5.0), Vector2(11.0, 0.0), bare, req, walls)
	var b := _cost(Vector2(6.0, 5.0), Vector2(11.0, 0.0), tough, req, walls)
	check.call(int(a["hits"]) > 0, "壁の代償: 比較に使う発射は壁に当たる")
	check.call(
		float(b["rps_loss"]) < float(a["rps_loss"]),
		"壁の代償: 壁強さ(wall_keep)を積むと請求が軽くなる (素%.2f > 積%.2f)"
			% [a["rps_loss"], b["rps_loss"]]
	)


## 面から離れずに続く接触は「1回」。本番(BattleResolver の touching_surface)と
## 同じ規則で数えないと、壁に沿って滑る狙いが毎刻み課金されて見積もりが跳ね上がる
## ——1.4秒で84回、といった桁で嘘をつくことになる。
func _test_sliding_contact_billed_once(check: Callable) -> void:
	var stats := _stats()
	var req := _request()
	req.stage_strength = 6.0
	req.stage_shape = SpinnerPhysics.StageShape.DISH
	var walls := _rect_walls(Vector2(5, 5), 5.0)
	# 右壁へ押しつけながら壁沿いに滑らせる(傾斜が壁側へ押し戻し続ける配置)。
	var cost := WallCostPreview.approach_cost(
		Vector2(9.28, 5.0), Vector2(1.0, 6.0), stats, Vector2(5, 5),
		req.stage_strength, req.stage_shape, walls, req.obstacles, req, 1.4
	)
	check.call(int(cost["hits"]) > 0, "壁の代償: 壁沿いの狙いも1回は課金される")
	check.call(
		int(cost["hits"]) <= 8,
		"壁の代償: 壁沿いに滑っても毎刻み課金しない (%d回 / 84刻み)" % cost["hits"]
	)
	# 定数が本番とずれると切れ目がずれる。同じ値であることを名指しで縛る。
	check.call(
		WallCostPreview._SURFACE_CONTACT_SKIN == BattleResolver.SURFACE_CONTACT_SKIN,
		"壁の代償: 接触の遊びは本番と同じ値"
	)


## 窓(until)を伸ばしても請求は減らない。噛み合いが早いほど通行料が安く見えるのは
## 「早く届けば壁を舐める前に触れる」という本当のことで、逆転してはいけない。
func _test_window_is_monotone(check: Callable) -> void:
	var stats := _stats()
	var req := _request()
	var walls := _rect_walls(Vector2(5, 5), 5.0)
	var prev := -1.0
	var prev_hits := -1
	for w in [0.2, 0.5, 1.0, 1.4]:
		var c := _cost(Vector2(6.0, 5.0), Vector2(11.0, 0.0), stats, req, walls, _NO_OBSTACLES, w)
		check.call(
			float(c["rps_loss"]) >= prev and int(c["hits"]) >= prev_hits,
			"壁の代償: 窓%.1fs の請求は前より減らない (%.2f rps, %d回)"
				% [w, c["rps_loss"], c["hits"]]
		)
		prev = float(c["rps_loss"])
		prev_hits = int(c["hits"])
	check.call(prev > 0.0, "壁の代償: 窓を伸ばせば請求が立つ")


## 柱も壁と同じに請求する。FIELD_PILLARS で柱へ突っ込む狙いが「壁の代償0」と
## 出たら、いちばん痛い狙いにいちばん静かなことになる。
func _test_obstacles_are_billed(check: Callable) -> void:
	var stats := _stats()
	var req := _request()
	var pillar: Array[Vector3] = [Vector3(8.0, 5.0, 0.6)]
	var walls := _rect_walls(Vector2(5, 5), 5.0)
	var without := _cost(Vector2(5.0, 5.0), Vector2(11.0, 0.0), stats, req, walls)
	var with_pillar := _cost(Vector2(5.0, 5.0), Vector2(11.0, 0.0), stats, req, walls, pillar)
	check.call(
		int(with_pillar["hits"]) > int(without["hits"]),
		"壁の代償: 進路上の柱も請求に入る (柱なし%d回 → 柱あり%d回)"
			% [without["hits"], with_pillar["hits"]]
	)
	check.call(
		float(with_pillar["first_time"]) < float(without["first_time"]),
		"壁の代償: 柱の方が手前なら初回の時刻も手前になる"
	)


## dt<=0 は刻み0回=発射の瞬間だけを見て返る(RendezvousPreview と同じ約束)。
## 落ちないこと・0を返すことの両方。
func _test_degenerate_step(check: Callable) -> void:
	var stats := _stats()
	var req := _request()
	var cost := WallCostPreview.approach_cost(
		Vector2(6.0, 5.0), Vector2(11.0, 0.0), stats, Vector2(5, 5),
		req.stage_strength, req.stage_shape, _rect_walls(Vector2(5, 5), 5.0),
		req.obstacles, req, 1.4, 0.0
	)
	check.call(int(cost["hits"]) == 0, "壁の代償: dt=0 は刻まずに0回で返る")


## 見積もりは入力を書き換えない(表示専用の関数なので、狙っている間に
## 自機のstatsが減っていくようなことがあってはいけない)。
func _test_pure(check: Callable) -> void:
	var stats := _stats()
	var req := _request()
	var walls := _rect_walls(Vector2(5, 5), 5.0)
	var before_rps := stats.rps
	var a := _cost(Vector2(6.0, 5.0), Vector2(11.0, 0.0), stats, req, walls)
	var b := _cost(Vector2(6.0, 5.0), Vector2(11.0, 0.0), stats, req, walls)
	check.call(stats.rps == before_rps, "壁の代償: 自機のrpsを書き換えない")
	check.call(
		float(a["rps_loss"]) == float(b["rps_loss"]) and int(a["hits"]) == int(b["hits"]),
		"壁の代償: 同じ入力は同じ答え"
	)


## 敷居。掠り1回で毎フレーム喋ると、本当に痛い狙いの1行が埋もれる。
func _test_notable_threshold(check: Callable) -> void:
	check.call(
		not WallCostPreview.is_notable({"hits": 0, "loss_share": 0.0}),
		"壁の代償: 0回は言うに値しない"
	)
	check.call(
		not WallCostPreview.is_notable({"hits": 1, "loss_share": 0.01}),
		"壁の代償: 敷居未満は言わない"
	)
	check.call(
		WallCostPreview.is_notable({"hits": 1, "loss_share": 0.2}),
		"壁の代償: 敷居を超えたら言う"
	)
	check.call(
		WallCostPreview.is_notable({"hits": 1, "loss_share": 0.05}),
		"壁の代償: ちょうど敷居でも言う(境界は含む)"
	)
	# 敷居は呼び手が動かせる(実UIは@exportで持つ)。
	check.call(
		WallCostPreview.is_notable({"hits": 1, "loss_share": 0.01}, 0.0),
		"壁の代償: 敷居0なら1回でも言う"
	)


## 1行の文。数字が入ること・敷居の下では空になること。
func _test_hint_text(check: Callable) -> void:
	check.call(
		WallCostPreview.hint_text({"hits": 0, "loss_share": 0.0}) == "",
		"壁の代償の文: 言うことが無ければ空(呼び手は行ごと消す)"
	)
	var text := WallCostPreview.hint_text({"hits": 3, "loss_share": 0.22})
	check.call(text != "", "壁の代償の文: 敷居を超えたら文が出る")
	check.call(text.contains("22"), "壁の代償の文: 割合が入る (%s)" % text)
	check.call(text.contains("3"), "壁の代償の文: 回数が入る (%s)" % text)
	# 差し込みが効いていない(キーがそのまま出ている)のを弾く。
	check.call(
		not text.contains("{pct}") and not text.contains("{hits}"),
		"壁の代償の文: 差し込みが残らない (%s)" % text
	)
	check.call(
		text != "BATTLE_LEAD_WALL_COST",
		"壁の代償の文: 訳が引けている(キーが素通りしていない)"
	)


## 訳が両言語そろっていて、どちらにも差し込みがあること。片方だけ差し込みを
## 落とすと、その言語でだけ数字の無い警告になる。
func _test_translations(check: Callable) -> void:
	var csv := FileAccess.get_file_as_string("res://translations/strings.csv")
	var row := ""
	for line in csv.split("\n"):
		if line.begins_with("BATTLE_LEAD_WALL_COST,"):
			row = line
			break
	check.call(row != "", "壁の代償の訳: キーが strings.csv にある")
	var cols := row.split(",")
	check.call(cols.size() >= 3, "壁の代償の訳: en/ja の両方がある")
	if cols.size() < 3:
		return
	for i in [1, 2]:
		check.call(
			cols[i].contains("{pct}") and cols[i].contains("{hits}"),
			"壁の代償の訳: 列%d に {pct} と {hits} がある (%s)" % [i, cols[i]]
		)


## 見積もりと本番が**同じ式**を通ること。ここが分かれた瞬間、見積もりは
## 静かに嘘になる(調整値を動かしても片方しか追随しない)。
## 式そのものは上の _test_agrees_with_resolver が数字で照合するが、
## 「書き写しに戻す」改変はソースでしか止められない。
func _test_shares_the_resolver_formula(check: Callable) -> void:
	var resolver := FileAccess.get_file_as_string("res://scripts/battle/battle_resolver.gd")
	var body := _function_body(
		resolver,
		"static func _wall_damaged_rps(s: State, normal_speed: float, req: BattleRequest) -> float:"
	)
	check.call(body.length() > 0, "壁の代償: 本番の壁ダメージ関数を取れた")
	check.call(
		body.contains("SpinnerPhysics.wall_damaged_rps("),
		"壁の代償: 本番は SpinnerPhysics.wall_damaged_rps を通す"
	)
	# 本番側に式が書き戻されていないこと(共有の1本だけが式を持つ)。
	check.call(
		not body.contains("lerpf(proportional"),
		"壁の代償: 本番に式が書き戻されていない"
	)
	var preview := FileAccess.get_file_as_string("res://scripts/battle/wall_cost_preview.gd")
	check.call(
		preview.contains("SpinnerPhysics.wall_damaged_rps("),
		"壁の代償: 見積もりも同じ1本を通す"
	)
	check.call(
		not preview.contains("lerpf(proportional"),
		"壁の代償: 見積もりが式を書き写していない"
	)
	# 積分も本番と同じ1本(RendezvousPreview.advance = BattleResolver._integrate)。
	check.call(
		preview.contains("RendezvousPreview.advance("),
		"壁の代償: 積分も先読みと同じ1本を通す"
	)


## 実UIに配線されていること。1行が出ない実装は、テストが全部緑でも遊びに届かない。
func _test_wired_into_battle(check: Callable) -> void:
	var src := FileAccess.get_file_as_string("res://scenes/battle/Battle.gd")
	var body := _function_body(
		src,
		"func _lead_hint_text(lead: Dictionary, origin: Vector2, velocity: Vector2) -> String:"
	)
	check.call(body.length() > 0, "壁の代償の配線: _lead_hint_text がある")
	check.call(
		body.contains("WallCostPreview.approach_cost("),
		"壁の代償の配線: 実UIが見積もりを呼ぶ"
	)
	check.call(
		body.contains("WallCostPreview.hint_text("),
		"壁の代償の配線: 文の組み立ても共有の1本を通す"
	)
	# 窓は噛み合いの時刻で切る(触れた後の未来は嘘になるので伸ばさない)。
	check.call(
		body.contains("lead[\"time\"]") and body.contains("lead_horizon"),
		"壁の代償の配線: 噛み合うなら其の時刻まで・噛み合わないなら地平まで"
	)
	# 打ち切りの行と並ぶこと。片方が出たらもう片方を隠すと、
	# 「噛み合うのに壁で負ける」というこの機能の主戦場で行が消える。
	check.call(
		body.contains("RendezvousPreview.hint_key("),
		"壁の代償の配線: 打ち切りの行と両立する"
	)
	check.call(
		src.contains("var show_wall_cost") and src.contains("var wall_cost_notable_share"),
		"壁の代償の配線: on/off と敷居が @export で出ている"
	)


## CLI(ハーネス)にも同じ数字が出ること。実UIだけが知っている情報があると、
## 次のサイクルのコールドプレイが実UIより不利な目で遊ぶことになる。
func _test_wired_into_cli(check: Callable) -> void:
	var src := FileAccess.get_file_as_string("res://playtest/naive_play.gd")
	var body := _function_body(
		src,
		"func _wall_cost_line("
	)
	check.call(body.length() > 0, "壁の代償の配線: CLIに1行を出す関数がある")
	check.call(
		body.contains("WallCostPreview.approach_cost("),
		"壁の代償の配線: CLIも同じ見積もりを呼ぶ"
	)
	check.call(
		_function_body(src, "func _aim(").contains("_wall_cost_line("),
		"壁の代償の配線: aim がその行を出す"
	)


## ソースから関数1つ分の本体を切り出す。次の "\nfunc " まで。
func _function_body(src: String, header: String) -> String:
	var start := src.find(header)
	if start < 0:
		return ""
	start += header.length()
	var end := src.find("\nfunc ", start)
	if end < 0:
		end = src.length()
	return src.substr(start, end - start)
