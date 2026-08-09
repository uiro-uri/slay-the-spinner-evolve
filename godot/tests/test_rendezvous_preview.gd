extends RefCounted

## rendezvous_preview.gd(発射前の先読み)のテスト。
##
## この機能の値打ちは一点、**先読みが嘘をつかないこと**にある。「噛み合う」と
## 描いておいて本番で当たらないなら、予告が嘘になるのと同じ罪で、三角形だけの
## 頃より悪い。だから単体の性質だけでなく、**実リゾルバ(BattleResolver)に同じ
## 発射を解かせて、予告した交差時刻に本当に衝突が記録されるか**まで見る。
##
## もう一つの約束は「置き撃ちの情報になっていること」——敵の**今の位置**を狙うと
## 外し、**先読みの点**を狙うと当たる、が同じ状況で両方成り立つこと。ここが
## 崩れると、この輪はただの飾りになる。


func run(check: Callable) -> void:
	_test_advance_matches_free_flight(check)
	_test_advance_matches_resolver_frames(check)
	_test_advance_friction_and_slope(check)
	_test_step_matches_request(check)
	_test_head_on_contacts(check)
	_test_miss_reports_gap(check)
	_test_lead_beats_aiming_at_spawn(check)
	_test_wall_cuts_preview(check)
	_test_horizon_bounds(check)
	_test_degenerate_step(check)
	_test_overlap_at_start(check)
	_test_radius_widens_contact(check)
	_test_pure(check)
	_test_primary_index(check)
	_test_agrees_with_resolver(check)
	_test_pillars_cut_preview(check)
	_test_seated_pillar_cuts_when_driven_into(check)
	_test_rect_walls_not_inscribed_circle(check)
	_test_cut_side(check)
	_test_cut_hint_key(check)
	_test_cut_translations(check)
	_test_launch_controller_wires_lead(check)
	_test_cut_mark_wired(check)


## 壁を見ない指定(調整・テスト用)。以前は inradius=0.0 がこれを意味していた。
const _NO_WALLS: Array[ArenaWall] = []


## 中心 center・辺までの距離 inradius の矩形の壁。先読みは本番と同じ半平面の列を
## 受けるので、テストも4枚で渡す。軸方向の当たりは内接円と一致し、**隅だけが変わる**
## ——それがこの直しの中身なので、既存のテストは軸方向の意図を保ったまま移せる。
func _rect_walls(center: Vector2, inradius: float) -> Array[ArenaWall]:
	return ArenaWall.from_rect(
		Rect2(center - Vector2.ONE * inradius, Vector2.ONE * inradius * 2.0))


func _stats(radius: float, friction: float = 0.0, grip: float = 1.0) -> SpinnerStats:
	var s := SpinnerStats.new()
	s.mass = 1.0
	s.radius = radius
	s.friction = friction
	s.restitution = 0.75
	s.rps = 20.0
	s.slope_grip = grip
	return s


## 摩擦も傾斜も無ければ、自由飛行はただの等速直線。刻みを重ねても p+v*t に乗る。
func _test_advance_matches_free_flight(check: Callable) -> void:
	var stats := _stats(0.5)
	var pos := Vector2(1.0, 2.0)
	var vel := Vector2(3.0, -1.0)
	var dt := 1.0 / 60.0
	for i in 30:
		var next := RendezvousPreview.advance(
			pos, vel, stats, Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, dt
		)
		pos = next[0]
		vel = next[1]
	var expected := Vector2(1.0, 2.0) + Vector2(3.0, -1.0) * (30 * dt)
	check.call(
		pos.distance_to(expected) < 0.001,
		"先読み: 摩擦も傾斜も無ければ等速直線 (誤差 %.4f)" % pos.distance_to(expected)
	)


## 自由飛行が**本番の1歩と同じ歩き方**であること。BattleResolverに実際に解かせて、
## 記録されたフレームと1歩ずつ突き合わせる。
##
## 「_integrateと同じ式」はコメントで言えても、順序(位置を進めてから加速度を足す)
## までは式の見た目では守られない。傾斜を進む前の位置で見るように書き換えても
## 交差時刻は1刻みぶんしかずれず、決着時刻の照合(誤差0.05秒)では素通りする
## ——だから軌道そのものを照合する。衝突・壁が混ざらないよう、相手を遠くに
## 置いて短い窓だけ見る。
func _test_advance_matches_resolver_frames(check: Callable) -> void:
	var mine := SpinnerStats.default_player()
	var theirs := SpinnerStats.default_player()

	var start := Vector2(3.0, 5.0)
	var vel := Vector2(2.0, 1.5)
	var request := BattleRequest.new()
	request.player = BattleRequest.Launch.new(mine, start, vel)
	# 相手は反対の隅で静止。短い窓の間はぶつからない。
	request.enemies = [
		BattleRequest.Launch.new(theirs, Vector2(8.5, 1.5), Vector2.ZERO)
	] as Array[BattleRequest.Launch]
	request.arena_bounds = Rect2(0, 0, 10, 10)
	request.wall_shape = ArenaWall.WallShape.RECT

	var result := BattleResolver.resolve(request)
	var center := request.arena_bounds.get_center()
	var pos := start
	var v := vel
	var worst := 0.0
	var frames := mini(30, result.player_frames.size() - 1)
	for i in frames:
		var n := RendezvousPreview.advance(
			pos, v, mine, center,
			request.stage_strength, request.stage_shape, request.time_step
		)
		pos = n[0]
		v = n[1]
		worst = maxf(worst, pos.distance_to(result.player_frames[i + 1].position))
	check.call(frames >= 20, "先読み: 照合に足りるフレームが録れた (%d)" % frames)
	check.call(
		worst < 0.0005,
		"先読み: 自由飛行が本番のフレームと1歩ずつ一致する (最大ずれ %.6f)" % worst
	)


## 摩擦は縮め、傾斜は中心へ引く。どちらも符号が逆だと当たらない未来を描く。
func _test_advance_friction_and_slope(check: Callable) -> void:
	var center := Vector2(5, 5)
	var dt := 1.0 / 60.0

	var slow := _stats(0.5, 4.0)
	var pos := Vector2(1.0, 5.0)
	var vel := Vector2(6.0, 0.0)
	for i in 30:
		var n := RendezvousPreview.advance(
			pos, vel, slow, center, 0.0, SpinnerPhysics.StageShape.DISH, dt
		)
		pos = n[0]
		vel = n[1]
	check.call(
		vel.length() < 6.0,
		"先読み: 摩擦があれば速さが落ちる (%.2f < 6.00)" % vel.length()
	)

	# 静止したコマを傾斜だけで動かす。中心へ寄れば符号が正しい。
	var still := _stats(0.5)
	var p2 := Vector2(1.0, 5.0)
	var v2 := Vector2.ZERO
	var before := p2.distance_to(center)
	for i in 30:
		var n2 := RendezvousPreview.advance(
			p2, v2, still, center, 6.0, SpinnerPhysics.StageShape.DISH, dt
		)
		p2 = n2[0]
		v2 = n2[1]
	check.call(
		p2.distance_to(center) < before,
		"先読み: 傾斜は中心へ引く (%.2f → %.2f)" % [before, p2.distance_to(center)]
	)

	# 低重心(grip>1)は同じ傾斜でもより強く引かれる。本番と同じ規則を通していること。
	var gripped := _stats(0.5, 0.0, 2.0)
	var p3 := Vector2(1.0, 5.0)
	var v3 := Vector2.ZERO
	for i in 30:
		var n3 := RendezvousPreview.advance(
			p3, v3, gripped, center, 6.0, SpinnerPhysics.StageShape.DISH, dt
		)
		p3 = n3[0]
		v3 = n3[1]
	check.call(
		p3.distance_to(center) < p2.distance_to(center),
		"先読み: 低重心ほど強く中心へ引かれる (%.2f < %.2f)"
			% [p3.distance_to(center), p2.distance_to(center)]
	)


## 刻み幅が本番(BattleRequest.time_step)と同じであること。ずれると先読みと
## リゾルバが別の軌道を歩き、予告した交差時刻が本番とずれる。
func _test_step_matches_request(check: Callable) -> void:
	var request := BattleRequest.new()
	check.call(
		is_equal_approx(RendezvousPreview.DEFAULT_STEP, request.time_step),
		"先読み: 刻み幅が本番のtime_stepと同じ (%.5f / %.5f)"
			% [RendezvousPreview.DEFAULT_STEP, request.time_step]
	)


## 正面から寄せれば触れる。時刻は0より後で、gapは負(食い込み)になる。
func _test_head_on_contacts(check: Callable) -> void:
	var r := RendezvousPreview.closest_approach(
		Vector2(1, 5), Vector2(6, 0), _stats(0.5),
		Vector2(9, 5), Vector2(-6, 0), _stats(0.5),
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, _NO_WALLS, [], 2.0
	)
	check.call(bool(r["contact"]), "先読み: 正面から寄せれば噛み合うと出る")
	check.call(float(r["time"]) > 0.0, "先読み: 噛み合う時刻は発射より後 (%.2f)" % r["time"])
	check.call(float(r["gap"]) <= 0.0, "先読み: 噛み合うときのgapは0以下 (%.3f)" % r["gap"])
	check.call(
		(r["player_point"] as Vector2).distance_to(r["enemy_point"] as Vector2) <= 1.0 + 0.001,
		"先読み: 噛み合う2点は半径の和まで近づく"
	)


## すれ違うなら「噛み合わない」と出て、gapに外した幅が残る。
func _test_miss_reports_gap(check: Callable) -> void:
	var r := RendezvousPreview.closest_approach(
		Vector2(1, 5), Vector2(6, 0), _stats(0.5),
		Vector2(1, 9), Vector2(6, 0), _stats(0.5),
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, _NO_WALLS, [], 2.0
	)
	check.call(not bool(r["contact"]), "先読み: 平行に走る2体は噛み合わない")
	check.call(float(r["gap"]) > 0.0, "先読み: 外すならgapが正 (%.2f)" % r["gap"])


## この機能の存在理由そのもの: **敵の今の位置を狙うと外し、先読みの点を狙うと
## 当たる**。同じ盤面で両方が成り立たなければ、輪はただの飾りになる。
func _test_lead_beats_aiming_at_spawn(check: Callable) -> void:
	var center := Vector2(5, 5)
	var mine := _stats(0.5)
	var theirs := _stats(0.5)
	var start := Vector2(5, 1)
	var enemy_pos := Vector2(1, 5)
	var enemy_vel := Vector2(7, 0)   # 右へ走り抜ける
	var speed := 7.0

	# (1) 出現点をそのまま狙う＝素直な初見の撃ち方。
	var at_spawn := RendezvousPreview.closest_approach(
		start, (enemy_pos - start).normalized() * speed, mine,
		enemy_pos, enemy_vel, theirs,
		center, 0.0, SpinnerPhysics.StageShape.DISH, _NO_WALLS, [], 2.0
	)
	check.call(
		not bool(at_spawn["contact"]),
		"先読み: 出現点を狙うと外す (gap %.2f)" % at_spawn["gap"]
	)

	# (2) 先読みが出した「相手が居るはずの点」を狙う。同じ初速のまま向きだけ変える。
	var lead_point: Vector2 = at_spawn["enemy_point"]
	var led := RendezvousPreview.closest_approach(
		start, (lead_point - start).normalized() * speed, mine,
		enemy_pos, enemy_vel, theirs,
		center, 0.0, SpinnerPhysics.StageShape.DISH, _NO_WALLS, [], 2.0
	)
	check.call(
		float(led["gap"]) < float(at_spawn["gap"]),
		"先読み: 先読みの点を狙うと確実に近づく (gap %.2f → %.2f)"
			% [at_spawn["gap"], led["gap"]]
	)
	check.call(bool(led["contact"]), "先読み: 先読みの点を狙えば噛み合う")


## 壁へ届いたら打ち切る。跳ね返った先まで描くと「当たらない未来」を語ることになる。
func _test_wall_cuts_preview(check: Callable) -> void:
	# 中心から離れる向きへ撃つ。相手は反対の縁でじっとしている。
	var cut := RendezvousPreview.closest_approach(
		Vector2(5, 5), Vector2(0, -8), _stats(0.5),
		Vector2(5, 9), Vector2.ZERO, _stats(0.5),
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, _rect_walls(Vector2(5, 5), 4.0), [], 3.0
	)
	check.call(bool(cut["cut_short"]), "先読み: 壁へ届いたら打ち切る")
	check.call(not bool(cut["contact"]), "先読み: 壁で打ち切ったなら噛み合いは出さない")
	check.call(
		(cut["player_point"] as Vector2).distance_to(Vector2(5, 5)) <= 4.0,
		"先読み: 打ち切り点は土俵の内側"
	)

	# inradius=0 は壁を見ない(調整・テスト用)。同じ発射で打ち切りが起きないこと。
	var no_wall := RendezvousPreview.closest_approach(
		Vector2(5, 5), Vector2(0, -8), _stats(0.5),
		Vector2(5, 9), Vector2.ZERO, _stats(0.5),
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, _NO_WALLS, [], 3.0
	)
	check.call(
		not bool(no_wall["cut_short"]),
		"先読み: inradius=0なら壁を見ない"
	)


## 時刻は必ず[0, horizon]に収まる。horizonを縮めれば先の噛み合いは見えなくなる。
func _test_horizon_bounds(check: Callable) -> void:
	var far_contact := RendezvousPreview.closest_approach(
		Vector2(1, 5), Vector2(3, 0), _stats(0.5),
		Vector2(9, 5), Vector2(-3, 0), _stats(0.5),
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, _NO_WALLS, [], 3.0
	)
	check.call(bool(far_contact["contact"]), "先読み: 長く見れば遠い噛み合いも出る")
	check.call(
		float(far_contact["time"]) >= 0.0 and float(far_contact["time"]) <= 3.0 + 0.02,
		"先読み: 時刻はhorizonに収まる (%.2f)" % far_contact["time"]
	)

	var short := RendezvousPreview.closest_approach(
		Vector2(1, 5), Vector2(3, 0), _stats(0.5),
		Vector2(9, 5), Vector2(-3, 0), _stats(0.5),
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, _NO_WALLS, [], 0.3
	)
	check.call(not bool(short["contact"]), "先読み: horizonの手前までしか見ない")
	check.call(
		float(short["time"]) <= 0.3 + 0.02,
		"先読み: 短いhorizonなら時刻もその中 (%.2f)" % short["time"]
	)


## dtが0でも固まらず、発射の瞬間だけを見て返る(無限ループの門)。
func _test_degenerate_step(check: Callable) -> void:
	var r := RendezvousPreview.closest_approach(
		Vector2(1, 5), Vector2(6, 0), _stats(0.5),
		Vector2(9, 5), Vector2(-6, 0), _stats(0.5),
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, _NO_WALLS, [], 2.0, 0.0
	)
	check.call(not bool(r["contact"]), "先読み: dt=0なら先へ進まない")
	check.call(is_equal_approx(float(r["time"]), 0.0), "先読み: dt=0の時刻は0")


## 発射の瞬間から食い込んでいるなら、その場で噛み合いと出す(進める前に返る)。
func _test_overlap_at_start(check: Callable) -> void:
	var r := RendezvousPreview.closest_approach(
		Vector2(5.0, 5.0), Vector2(1, 0), _stats(0.5),
		Vector2(5.4, 5.0), Vector2(-1, 0), _stats(0.5),
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, _NO_WALLS, [], 2.0
	)
	check.call(bool(r["contact"]), "先読み: 最初から食い込んでいれば噛み合い")
	check.call(is_equal_approx(float(r["time"]), 0.0), "先読み: その時刻は0")


## 大きいコマほど早く触れる。接触の判定が半径の和で決まっていること。
func _test_radius_widens_contact(check: Callable) -> void:
	var small := RendezvousPreview.closest_approach(
		Vector2(1, 5), Vector2(6, 0), _stats(0.3),
		Vector2(9, 5), Vector2(-6, 0), _stats(0.3),
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, _NO_WALLS, [], 2.0
	)
	var big := RendezvousPreview.closest_approach(
		Vector2(1, 5), Vector2(6, 0), _stats(1.2),
		Vector2(9, 5), Vector2(-6, 0), _stats(1.2),
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, _NO_WALLS, [], 2.0
	)
	check.call(
		float(big["time"]) < float(small["time"]),
		"先読み: 大きいコマほど早く触れる (%.2f < %.2f)" % [big["time"], small["time"]]
	)

	# すれ違いの幅も半径で変わる。小さければ外す間合いでも、大きければ噛み合う
	# (真横に並走すると本番の述語では永久に「近づいていない」ので、わずかに寄せる)。
	var thin := RendezvousPreview.closest_approach(
		Vector2(1, 5), Vector2(6, 0), _stats(0.2),
		Vector2(1, 5.9), Vector2(6, -0.2), _stats(0.2),
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, _NO_WALLS, [], 2.0
	)
	var fat := RendezvousPreview.closest_approach(
		Vector2(1, 5), Vector2(6, 0), _stats(0.6),
		Vector2(1, 5.9), Vector2(6, -0.2), _stats(0.6),
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, _NO_WALLS, [], 2.0
	)
	check.call(
		not bool(thin["contact"]) and bool(fat["contact"]),
		"先読み: 同じすれ違いでも半径の和が届けば噛み合う"
	)


## 純粋関数であること。同じ入力なら何度呼んでも同じ答えで、渡したstatsも壊さない。
func _test_pure(check: Callable) -> void:
	var mine := _stats(0.5, 2.0)
	var theirs := _stats(0.4, 2.0)
	var radius_before := mine.radius
	var first := RendezvousPreview.closest_approach(
		Vector2(1, 5), Vector2(6, 0), mine,
		Vector2(9, 5), Vector2(-6, 0), theirs,
		Vector2(5, 5), 4.9, SpinnerPhysics.StageShape.DISH, _rect_walls(Vector2(5, 5), 4.6), [], 1.4
	)
	var second := RendezvousPreview.closest_approach(
		Vector2(1, 5), Vector2(6, 0), mine,
		Vector2(9, 5), Vector2(-6, 0), theirs,
		Vector2(5, 5), 4.9, SpinnerPhysics.StageShape.DISH, _rect_walls(Vector2(5, 5), 4.6), [], 1.4
	)
	check.call(
		is_equal_approx(float(first["time"]), float(second["time"]))
			and is_equal_approx(float(first["gap"]), float(second["gap"])),
		"先読み: 同じ入力なら同じ答え"
	)
	check.call(
		is_equal_approx(mine.radius, radius_before),
		"先読み: 渡したstatsを書き換えない"
	)


## 乱戦で見せる1体の選び方: 触れる相手が居れば一番早いもの、居なければ一番近づくもの。
func _test_primary_index(check: Callable) -> void:
	var empty: Array[Dictionary] = []
	check.call(RendezvousPreview.primary_index(empty) == -1, "先読み: 空なら-1(非表示)")

	var mixed: Array[Dictionary] = [
		{"contact": false, "time": 0.2, "gap": 0.5},
		{"contact": true, "time": 0.9, "gap": -0.1},
		{"contact": true, "time": 0.4, "gap": -0.2},
	]
	check.call(
		RendezvousPreview.primary_index(mixed) == 2,
		"先読み: 噛み合う相手のうち一番早いものを選ぶ"
	)

	var all_miss: Array[Dictionary] = [
		{"contact": false, "time": 0.2, "gap": 1.5},
		{"contact": false, "time": 0.8, "gap": 0.3},
		{"contact": false, "time": 0.5, "gap": 2.0},
	]
	check.call(
		RendezvousPreview.primary_index(all_miss) == 1,
		"先読み: 全部外すなら一番近づくものを選ぶ"
	)

	var single: Array[Dictionary] = [{"contact": false, "time": 0.2, "gap": 9.0}]
	check.call(RendezvousPreview.primary_index(single) == 0, "先読み: 1体ならそれを選ぶ")


## この機能でいちばん守りたい性質: **先読みが嘘をつかない**。同じ発射を実際の
## BattleResolverに解かせて、予告した時刻の近くに本当に衝突が記録されること。
## 単体の性質(上のテスト群)は式が自己完結して正しいだけで、本番の物理と同じ道を
## 歩いている保証にはならない。
func _test_agrees_with_resolver(check: Callable) -> void:
	var mine := SpinnerStats.default_player()
	var theirs := SpinnerStats.default_player()
	theirs.radius = 0.45
	theirs.mass = 0.8

	var center := Vector2(5, 5)
	var start := Vector2(1.2, 5.0)
	var my_vel := Vector2(9.0, 0.0)
	var their_pos := Vector2(8.8, 5.0)
	var their_vel := Vector2(-9.0, 0.0)

	var request := BattleRequest.new()
	request.player = BattleRequest.Launch.new(mine, start, my_vel)
	request.enemies = [BattleRequest.Launch.new(theirs, their_pos, their_vel)] as Array[BattleRequest.Launch]
	request.arena_bounds = Rect2(0, 0, 10, 10)
	request.wall_shape = ArenaWall.WallShape.RECT

	var predicted := RendezvousPreview.closest_approach(
		start, my_vel, mine, their_pos, their_vel, theirs,
		center, request.stage_strength, request.stage_shape,
		ArenaWall.build(request.wall_shape, request.arena_bounds), [], 2.0
	)
	check.call(bool(predicted["contact"]), "先読み: この発射は噛み合うと予告する")

	var result := BattleResolver.resolve(request)
	check.call(not result.impacts.is_empty(), "先読み: 本番でも実際に衝突が起きる")
	if result.impacts.is_empty() or not bool(predicted["contact"]):
		return
	var actual: float = result.impacts[0].time
	var diff: float = absf(actual - float(predicted["time"]))
	check.call(
		diff < 0.05,
		"先読み: 予告した時刻に本番の初衝突が来る (予告%.3f / 本番%.3f 差%.3f)"
			% [predicted["time"], actual, diff]
	)
	# 本番の接触点は「半径で重み付けした中点」(BattleResolver)なので、
	# 先読みの2点から同じ規則で作った点と比べる。
	var pp: Vector2 = predicted["player_point"]
	var ep: Vector2 = predicted["enemy_point"]
	var meet := (pp * theirs.radius + ep * mine.radius) / (mine.radius + theirs.radius)
	check.call(
		meet.distance_to(result.impacts[0].point) < 0.3,
		"先読み: 予告した場所で本番の初衝突が起きる (差 %.2f)"
			% meet.distance_to(result.impacts[0].point)
	)


## 柱(障害物)も壁と同じに扱う。柱を素通りする先読みは「柱に弾かれて起きない交差」を
## 描くことになり、壁を素通りするのと同じ嘘になる。
##
## ただし**発射時に既に接している柱は数えない**。発射位置は柱の縁へ寄せて
## クランプされるので(FieldData.clamp_placement)、素直に「触れているか」で切ると
## 柱際から撃った瞬間に先読みが消える(実測: FIELD_PILLARSの柱際の発射で、
## 1刻み目に打ち切られて何も出なかった)。
func _test_pillars_cut_preview(check: Callable) -> void:
	var center := Vector2(5, 5)
	var pillar: Array[Vector3] = [Vector3(5.0, 3.0, 0.6)]

	# 柱を突っ切る道。柱を見なければ噛み合い、見れば打ち切られる。
	var through := RendezvousPreview.closest_approach(
		Vector2(1, 3), Vector2(6, 0), _stats(0.3),
		Vector2(9, 3), Vector2(-6, 0), _stats(0.3),
		center, 0.0, SpinnerPhysics.StageShape.DISH, _NO_WALLS, [], 2.0
	)
	check.call(bool(through["contact"]), "先読み: 柱を見なければ柱越しに噛み合うと出る")
	var blocked := RendezvousPreview.closest_approach(
		Vector2(1, 3), Vector2(6, 0), _stats(0.3),
		Vector2(9, 3), Vector2(-6, 0), _stats(0.3),
		center, 0.0, SpinnerPhysics.StageShape.DISH, _NO_WALLS, pillar, 2.0
	)
	check.call(bool(blocked["cut_short"]), "先読み: 柱へ届いたら打ち切る")
	check.call(not bool(blocked["contact"]), "先読み: 柱で打ち切ったなら噛み合いは出さない")

	# 柱の縁に座った状態から、ゆっくり離れる向きへ撃つ。数刻みは柱の間合いに
	# 居続けるので、「触れているか」で切る実装なら1刻み目で消える。
	var seated := RendezvousPreview.closest_approach(
		Vector2(5.0, 3.85), Vector2(0, 1.2), _stats(0.3),
		Vector2(5.0, 7.5), Vector2(0, -8), _stats(0.3),
		center, 0.0, SpinnerPhysics.StageShape.DISH, _NO_WALLS, pillar, 2.0
	)
	check.call(
		bool(seated["contact"]),
		"先読み: 発射時から接している柱では打ち切らない (cut=%s)" % str(seated["cut_short"])
	)


## 発射時に接しているものへの免除は「離れるまで」ではなく「発射時の深さまで」。
##
## 一次証拠(コールドプレイ 2026-08-09, seed=48219 段3 FIELD_PILLARS)。矩形10×10の
## 隅 (8.17, 8.17) から中央を狙った。当時の先読みは壁を内接円(半径5)1本で見ており、
## この**矩形としては合法**な点を発射の瞬間から「壁に接している」と見ていた
## (壁を辺の列で見る今はもう接していない)。従来の実装は
## 打ち切りを bool 1本の**遷移**で見ていたため、その免除が壁だけでなく
## **同じ線上の柱(7,7)にも効き**、先読みは柱の芯(中心から0.09ユニット)を素通りして
## 「0.30秒で噛み合う」と **contact=true で**予告した。本番は1歩目で柱に弾かれ、
## 敵に一度も触れないまま壁で削られて敗北(衝突1回・壁34回・自分の喪失の92%が壁)。
## **打ち切りの無言ではなく「噛み合う」という嘘**なので、輪の破線でも文言でも
## 救えない。深さで見れば、免除は壁のぶんだけ・その深さまでに閉じる。
##
## ここが縛るのは3点: (a)貫く狙いは打ち切る (b)同じ狙いでも柱を見なければ
## 噛み合う=**柱を貫通していたことの証明** (c)柱から離れる狙いは今までどおり残る
## (_test_pillars_cut_preview の seated と対)。
func _test_seated_pillar_cuts_when_driven_into(check: Callable) -> void:
	var center := Vector2(5, 5)
	var pillar: Array[Vector3] = [Vector3(7.0, 7.0, 0.6)]
	var seat := Vector2(8.167433, 8.167433)
	var into := Vector2(12, 0).rotated(deg_to_rad(-135))
	var foe := Vector2(2.008389, 7.655232)
	var foe_vel := Vector2(7.1, 0).rotated(deg_to_rad(-45))
	var me := _stats(1.05, 0.98)
	var them := _stats(0.55, 0.98)

	var through := RendezvousPreview.closest_approach(
		seat, into, me, foe, foe_vel, them,
		center, 4.9, SpinnerPhysics.StageShape.DISH, _rect_walls(Vector2(5, 5), 5.0), [], 1.4
	)
	check.call(
		bool(through["contact"]),
		"隅からの狙い: 柱を見なければ噛み合うと出る(=柱を貫通していた証明)"
	)

	var driven := RendezvousPreview.closest_approach(
		seat, into, me, foe, foe_vel, them,
		center, 4.9, SpinnerPhysics.StageShape.DISH, _rect_walls(Vector2(5, 5), 5.0), pillar, 1.4
	)
	check.call(
		bool(driven["cut_short"]),
		"隅からの狙い: 線上の柱で打ち切る (cut=%s)" % str(driven["cut_short"])
	)
	check.call(
		not bool(driven["contact"]),
		"隅からの狙い: 柱越しの「噛み合う」は出さない (contact=%s)" % str(driven["contact"])
	)
	check.call(
		int(driven["cut_by"]) == int(RendezvousPreview.CutBy.PLAYER),
		"隅からの狙い: 打ち切ったのは自分の側 (cut_by=%d)" % int(driven["cut_by"])
	)
	check.call(
		float(driven["time"]) < float(through["time"]),
		"隅からの狙い: 貫き終わるまで待たない (t=%.3f < 貫通時の%.3f)"
			% [float(driven["time"]), float(through["time"])]
	)

	# 壁を見ない同じ配置。当時この免除の出所は壁だった(柱だけなら従来の実装でも
	# 切れた)。壁を辺で見るようになった今はどちらでも柱で切るが、
	# 「免除は壁ごと・柱ごとに閉じる」の縛りとしてそのまま残す。
	var no_wall := RendezvousPreview.closest_approach(
		seat, into, me, foe, foe_vel, them,
		center, 4.9, SpinnerPhysics.StageShape.DISH, _NO_WALLS, pillar, 1.4
	)
	check.call(
		bool(no_wall["cut_short"]) and not bool(no_wall["contact"]),
		"隅からの狙い: 壁を見なくても柱で打ち切る(免除は壁ごとに閉じる)"
	)

	# 柱の乗っていない対角の隅から、同じように中央へ降りる狙い。壁の免除そのものは
	# 残っていること——隅発射を丸ごと無言にする直し方(免除を捨てる)との差を作る。
	var clear_corner := RendezvousPreview.closest_approach(
		Vector2(8.167433, 1.832567), Vector2(5, 0).rotated(deg_to_rad(135)), me,
		Vector2(2.0, 5.0), Vector2.ZERO, them,
		center, 4.9, SpinnerPhysics.StageShape.DISH, _rect_walls(Vector2(5, 5), 5.0), pillar, 0.5
	)
	check.call(
		not RendezvousPreview.cut_player(clear_corner),
		"隅からの狙い: 線上に柱が無ければ隅からでも打ち切らない (cut_by=%d)"
			% int(clear_corner["cut_by"])
	)

	# 免除は**一度抜け出したら消える**。壁の外(内接円の外)から中央へ降り、すり鉢に
	# 押し戻されて反対側の壁へ戻ってくる道: 戻りの深さ(0.24)は発射時(0.45)より浅いので、
	# 免除を発射時の深さのまま持ち続ける実装だと1.4秒のあいだ一度も打ち切らない。
	# 相手は傾斜も摩擦も効かない置物(grip=0/friction=0)にして、打ち切りの出所を
	# 自分の側だけに絞る。
	var returns := RendezvousPreview.closest_approach(
		Vector2(5.0, 9.4), Vector2(0, -3), me,
		Vector2(1.5, 5.0), Vector2.ZERO, _stats(0.55, 0.0, 0.0),
		center, 4.9, SpinnerPhysics.StageShape.DISH, _rect_walls(Vector2(5, 5), 5.0), [], 1.4
	)
	check.call(
		RendezvousPreview.cut_player(returns),
		"壁の免除: 一度離れて戻ってきたら、発射時より浅くても打ち切る (cut_by=%d t=%.2f)"
			% [int(returns["cut_by"]), float(returns["time"])]
	)


## 矩形の土俵の壁は**内接円ではなく4枚の辺**。以前の先読みは壁を内接半径1本に
## 畳んでいたので、10×10 の土俵では中心から 5.0 を超える隅——`clamp_inside` が
## 合法と認め、実UIならマウスで普通に置ける領域——が丸ごと壁の外に見えていた。
##
## 害は2つで、どちらも「先読みが嘘をつく」形:
##  (a) **対角へ撃つと実際の辺の手前で打ち切る**。隅までは 7.07 あるのに 5.0 で
##      切るので、届く狙いに「壁だ」と言う。
##  (b) **隅に置いたコマが発射の瞬間から食い込み扱い**になり、免除の敷居
##      (_cut_gates)が立つ。前サイクルはその免除が柱まで貫通させる嘘を生んでいた。
##
## 非矩形(多角形)の土俵では内接円とほぼ同じ答えのままであることも併せて縛る
## ——「隅まで見る」を全形状へ一律に広げると、今度は円い土俵で壁を素通りする。
func _test_rect_walls_not_inscribed_circle(check: Callable) -> void:
	var center := Vector2(5, 5)
	var rect := _rect_walls(center, 5.0)
	# 相手は打ち切りの出所にならない置物(傾斜も摩擦も効かない)。返り値の
	# player_point は「一番近づいた瞬間」なので、自分が近づき続ける位置に置く
	# ——そうしないと点が発射位置に張り付いて、どこで切ったのか読めない。
	var idle := _stats(0.1, 0.0, 0.0)

	# (a) 中心から45°へ真っ直ぐ。内接円なら中心から4.5で切るが、実際の右壁は
	#     x=9.5 まで無い。打ち切りまでに内接円の外まで走れていることが、
	#     壁を辺で見た証拠になる。
	var diagonal := RendezvousPreview.closest_approach(
		center, Vector2(5, 5), _stats(0.5),
		Vector2(9.6, 8.4), Vector2.ZERO, idle,
		center, 0.0, SpinnerPhysics.StageShape.DISH, rect, [], 1.2
	)
	check.call(
		bool(diagonal["cut_short"]) and not bool(diagonal["contact"]),
		"矩形の壁: 対角へ撃てばいつかは辺で打ち切る (cut=%s)" % str(diagonal["cut_short"])
	)
	check.call(
		int(diagonal["cut_by"]) == int(RendezvousPreview.CutBy.PLAYER),
		"矩形の壁: 打ち切ったのは自分の側 (cut_by=%d)" % int(diagonal["cut_by"])
	)
	var cut_point: Vector2 = diagonal["player_point"]
	check.call(
		cut_point.distance_to(center) > 5.0,
		"矩形の壁: 打ち切りまでに内接円(5.0)の外まで走れる＝隅まで見ている (%.2f)"
			% cut_point.distance_to(center)
	)

	# (b) 矩形として合法な隅 (8.167, 8.167) に半径0.7 のコマを置く。右壁までは
	#     まだ 1.13 空いているのに、内接円で見ると深さ +0.18 の「食い込み」になる。
	#     そこから外向きへ撃つと、円で見る実装は発射時より深くなった1刻み目で
	#     即座に打ち切る——まだ壁まで 0.38 秒あるのに「壁だ」と言う。
	var seat := Vector2(8.167433, 8.167433)
	var outward := Vector2(3, 3)
	var early := RendezvousPreview.closest_approach(
		seat, outward, _stats(0.7),
		Vector2(1, 5), Vector2.ZERO, idle,
		center, 0.0, SpinnerPhysics.StageShape.DISH, rect, [], 0.2
	)
	check.call(
		not bool(early["cut_short"]),
		"矩形の壁: 隅から外向きでも、辺(x=9.3)まで余裕がある間は打ち切らない (cut=%s)"
			% str(early["cut_short"])
	)
	# ただし「隅なら何も見ない」ではない。同じ狙いを辺へ届くまで伸ばせば切る。
	var late := RendezvousPreview.closest_approach(
		seat, outward, _stats(0.7),
		Vector2(1, 5), Vector2.ZERO, idle,
		center, 0.0, SpinnerPhysics.StageShape.DISH, rect, [], 0.6
	)
	check.call(
		RendezvousPreview.cut_player(late),
		"矩形の壁: 隅からでも辺へ届けば打ち切る (cut_by=%d)" % int(late["cut_by"])
	)

	# (c) 円い土俵(32角形)は今までどおり内接円とほぼ同じ。同じ対角の発射で、
	#     打ち切りは内接円のすぐ内側に戻る。「隅まで見る」を全形状へ一律に
	#     広げると、ここが矩形と同じ 5.0 超えになって円い土俵で壁を素通りする。
	var round_walls := ArenaWall.build(ArenaWall.WallShape.ROUND, Rect2(0, 0, 10, 10))
	var circular := RendezvousPreview.closest_approach(
		center, Vector2(5, 5), _stats(0.5),
		Vector2(9.6, 8.4), Vector2.ZERO, idle,
		center, 0.0, SpinnerPhysics.StageShape.DISH, round_walls, [], 1.2
	)
	var round_point: Vector2 = circular["player_point"]
	check.call(
		bool(circular["cut_short"]),
		"円い土俵: 対角でも打ち切る (cut=%s)" % str(circular["cut_short"])
	)
	check.call(
		round_point.distance_to(center) < 5.0
			and round_point.distance_to(center) > 4.2,
		"円い土俵: 打ち切り点は内接円のすぐ内側のまま (%.2f)"
			% round_point.distance_to(center)
	)

	# (d) 実際に先読みへ渡るのは FieldData.walls()。**置ける場所の規則
	#     (clamp_placement)と壁の見方が食い違わないこと**をここで縛る
	#     ——矩形の土俵で clamp が合法と認めた点が、先読みでは壁の中、が今回の穴だった。
	var rect_field := FieldData.make(
		"", Rect2(0, 0, 10, 10), ArenaWall.WallShape.RECT,
		SpinnerPhysics.StageShape.DISH, 4.9)
	var placed := rect_field.clamp_placement(Vector2(20, 20), 0.7)
	var deepest := -1e9
	for w in rect_field.walls():
		deepest = maxf(deepest, SpinnerPhysics.wall_gap(w.point, w.normal, placed, 0.7))
	check.call(
		deepest <= 0.001,
		"土俵の壁: clamp_placement が置いた隅(%.2f, %.2f)は先読みの壁にも食い込まない (%.3f)"
			% [placed.x, placed.y, deepest]
	)


## 打ち切りは**どちら側が届いたのか**まで返す。自分が先に届く(＝満引きの罰)と
## 相手が先に届く(＝待てば跳ね返って噛み合う)は打ち手が反対なので、同じ絵・
## 同じ文言にしてはいけない。
func _test_cut_side(check: Callable) -> void:
	var center := Vector2(5, 5)

	# 自分だけが縁へ突っ込む。相手は最初から縁の外側扱い(=数えない)で止まっている。
	var mine := RendezvousPreview.closest_approach(
		center, Vector2(0, -8), _stats(0.5),
		Vector2(5, 9), Vector2.ZERO, _stats(0.5),
		center, 0.0, SpinnerPhysics.StageShape.DISH, _rect_walls(Vector2(5, 5), 4.0), [], 3.0
	)
	check.call(bool(mine["cut_short"]), "打ち切りの側: 自分が壁へ届いたら打ち切る")
	check.call(
		int(mine["cut_by"]) == int(RendezvousPreview.CutBy.PLAYER),
		"打ち切りの側: 自分だけならPLAYER (cut_by=%d)" % int(mine["cut_by"])
	)
	check.call(RendezvousPreview.cut_player(mine), "打ち切りの側: cut_playerが立つ")
	check.call(not RendezvousPreview.cut_enemy(mine), "打ち切りの側: cut_enemyは立たない")

	# 相手だけが縁へ突っ込む。自分は中央でほとんど動かず、二人は離れていく。
	var theirs := RendezvousPreview.closest_approach(
		center, Vector2(0.1, 0), _stats(0.5),
		Vector2(5, 2), Vector2(0, -8), _stats(0.5),
		center, 0.0, SpinnerPhysics.StageShape.DISH, _rect_walls(Vector2(5, 5), 4.0), [], 3.0
	)
	check.call(bool(theirs["cut_short"]), "打ち切りの側: 相手が壁へ届いても打ち切る")
	check.call(
		int(theirs["cut_by"]) == int(RendezvousPreview.CutBy.ENEMY),
		"打ち切りの側: 相手だけならENEMY (cut_by=%d)" % int(theirs["cut_by"])
	)

	# 左右対称に離れていく。同じ刻みで両者が届くので、片方を見つけた時点で
	# 抜けている実装だと片側しか立たない。
	var both := RendezvousPreview.closest_approach(
		Vector2(4, 5), Vector2(-8, 0), _stats(0.5),
		Vector2(6, 5), Vector2(8, 0), _stats(0.5),
		center, 0.0, SpinnerPhysics.StageShape.DISH, _rect_walls(Vector2(5, 5), 4.0), [], 3.0
	)
	check.call(
		int(both["cut_by"]) == int(RendezvousPreview.CutBy.BOTH),
		"打ち切りの側: 同じ刻みで両者が届いたらBOTH (cut_by=%d)" % int(both["cut_by"])
	)

	# 打ち切っていない結果は必ずNONE。噛み合う結果・ただの外し・壁を見ない設定。
	var hit := RendezvousPreview.closest_approach(
		Vector2(1, 5), Vector2(6, 0), _stats(0.5),
		Vector2(9, 5), Vector2(-6, 0), _stats(0.5),
		center, 0.0, SpinnerPhysics.StageShape.DISH, _NO_WALLS, [], 2.0
	)
	check.call(bool(hit["contact"]), "打ち切りの側: 前提として噛み合う配置")
	check.call(
		int(hit["cut_by"]) == int(RendezvousPreview.CutBy.NONE),
		"打ち切りの側: 噛み合う結果はNONE"
	)
	var no_wall := RendezvousPreview.closest_approach(
		center, Vector2(0, -8), _stats(0.5),
		Vector2(5, 9), Vector2.ZERO, _stats(0.5),
		center, 0.0, SpinnerPhysics.StageShape.DISH, _NO_WALLS, [], 3.0
	)
	check.call(
		not bool(no_wall["cut_short"]) and int(no_wall["cut_by"]) == 0,
		"打ち切りの側: 壁を見ない設定ではNONEのまま"
	)


## 訳キーへの畳み込み。「言うことが無ければ空文字」＝呼び手が行ごと出さない。
func _test_cut_hint_key(check: Callable) -> void:
	var center := Vector2(5, 5)
	var mine := RendezvousPreview.closest_approach(
		center, Vector2(0, -8), _stats(0.5),
		Vector2(5, 9), Vector2.ZERO, _stats(0.5),
		center, 0.0, SpinnerPhysics.StageShape.DISH, _rect_walls(Vector2(5, 5), 4.0), [], 3.0
	)
	check.call(
		RendezvousPreview.hint_key(mine) == "BATTLE_LEAD_CUT_PLAYER",
		"打ち切りの文: 自分側のキー (%s)" % RendezvousPreview.hint_key(mine)
	)
	var theirs := RendezvousPreview.closest_approach(
		center, Vector2(0.1, 0), _stats(0.5),
		Vector2(5, 2), Vector2(0, -8), _stats(0.5),
		center, 0.0, SpinnerPhysics.StageShape.DISH, _rect_walls(Vector2(5, 5), 4.0), [], 3.0
	)
	check.call(
		RendezvousPreview.hint_key(theirs) == "BATTLE_LEAD_CUT_ENEMY",
		"打ち切りの文: 相手側のキー (%s)" % RendezvousPreview.hint_key(theirs)
	)
	var both := RendezvousPreview.closest_approach(
		Vector2(4, 5), Vector2(-8, 0), _stats(0.5),
		Vector2(6, 5), Vector2(8, 0), _stats(0.5),
		center, 0.0, SpinnerPhysics.StageShape.DISH, _rect_walls(Vector2(5, 5), 4.0), [], 3.0
	)
	check.call(
		RendezvousPreview.hint_key(both) == "BATTLE_LEAD_CUT_BOTH",
		"打ち切りの文: 両者のキー (%s)" % RendezvousPreview.hint_key(both)
	)

	# 噛み合う結果とただの外しは無言。ここが鳴ると「当たる」と描いた狙いに
	# 警告が出る＝先読みが自分で自分を打ち消す。
	var hit := RendezvousPreview.closest_approach(
		Vector2(1, 5), Vector2(6, 0), _stats(0.5),
		Vector2(9, 5), Vector2(-6, 0), _stats(0.5),
		center, 0.0, SpinnerPhysics.StageShape.DISH, _NO_WALLS, [], 2.0
	)
	check.call(RendezvousPreview.hint_key(hit) == "", "打ち切りの文: 噛み合うなら無言")
	var miss := RendezvousPreview.closest_approach(
		Vector2(1, 5), Vector2(6, 0), _stats(0.5),
		Vector2(9, 8), Vector2(-6, 0), _stats(0.5),
		center, 0.0, SpinnerPhysics.StageShape.DISH, _NO_WALLS, [], 2.0
	)
	check.call(not bool(miss["contact"]), "打ち切りの文: 前提として外す配置")
	check.call(
		RendezvousPreview.hint_key(miss) == "",
		"打ち切りの文: 打ち切っていない外しは無言"
	)
	check.call(RendezvousPreview.hint_key({}) == "", "打ち切りの文: 空の先読みは無言")
	check.call(
		not RendezvousPreview.cut_player({}) and not RendezvousPreview.cut_enemy({}),
		"打ち切りの側: 空の先読みはどちらも立たない"
	)


## 3つの訳キーが日英とも埋まっていること。キーのまま出るとプレイヤーには
## 「BATTLE_LEAD_CUT_PLAYER」という呪文が見える。
func _test_cut_translations(check: Callable) -> void:
	var keys := ["BATTLE_LEAD_CUT_PLAYER", "BATTLE_LEAD_CUT_ENEMY", "BATTLE_LEAD_CUT_BOTH"]
	var saved := TranslationServer.get_locale()
	for locale in ["ja", "en"]:
		TranslationServer.set_locale(locale)
		for key in keys:
			var got := TranslationServer.translate(key)
			check.call(got != key and got.length() > 0, "打ち切りの訳: %s/%s" % [locale, key])
	# 3つが同じ文言だと「どちらが届いたのか」を出した意味がない。
	TranslationServer.set_locale("ja")
	var texts := []
	for key in keys:
		texts.append(TranslationServer.translate(key))
	check.call(
		texts[0] != texts[1] and texts[1] != texts[2] and texts[0] != texts[2],
		"打ち切りの訳: 3つの文言が互いに違う"
	)
	TranslationServer.set_locale(saved)


## 配線。LaunchController も Battle も自動読み込み(AudioManager/GameState)に
## 依存していて **`--script` のヘッドレスでは実体化できない**(journal 2026-08-05
## で実測済み)ので、ここはソースを読んで配線を照合する。実UIでの描画確認は
## CIの verify.sh stage 6/7 が担当する。
func _test_launch_controller_wires_lead(check: Callable) -> void:
	var src := FileAccess.get_file_as_string("res://scenes/battle/LaunchController.gd")
	check.call(src.length() > 0, "配線: LaunchController.gd を読めた")
	check.call(
		src.contains("signal aim_changed(origin: Vector2, velocity: Vector2)"),
		"配線: 狙いの内容(位置と初速)を通知する信号がある"
	)
	check.call(
		src.contains("func set_lead("), "配線: 先読みの受け口(set_lead)がある"
	)
	# 狙いの通知と発射が**同じ関数**で初速を出していること。別々に組み立てると
	# 先読みが「実際には撃たない弾道」を描く。
	check.call(
		src.contains("aim_changed.emit(_origin, _launch_velocity())"),
		"配線: 狙いの通知は発射と同じ初速の関数を通る"
	)
	check.call(
		_function_body(src, "func _release() -> void:")
			.contains("launched.emit(_origin, _launch_velocity())"),
		"配線: 発射も同じ初速の関数を通る"
	)
	# **発射は先読みを見ない**。_release の本体に _lead が出てきたら、表示専用の
	# はずの先読みが発射内容に混ざっている。
	var release := _function_body(src, "func _release() -> void:")
	check.call(release.length() > 0, "配線: _release の本体を取れた")
	check.call(
		not release.contains("_lead"),
		"配線: 発射(_release)は先読みを見ない"
	)
	# 逆に描画は見ていること(見ていなければ輪はどこにも出ない)。
	check.call(
		_function_body(src, "func _draw_lead() -> void:").contains("_lead["),
		"配線: 描画は先読みの結果を読む"
	)
	check.call(
		_function_body(src, "func _draw() -> void:").contains("_draw_lead()"),
		"配線: 狙いの描画から先読みの描画を呼ぶ"
	)

	# Battle側の受け口と既定値。
	var battle_src := FileAccess.get_file_as_string("res://scenes/battle/Battle.gd")
	check.call(
		battle_src.contains("_launcher.aim_changed.connect(_on_aim_changed)"),
		"配線: Battleが狙いの通知を受けている"
	)
	check.call(
		battle_src.contains("_telegraphs[i].display_position()")
			and battle_src.contains("_telegraphs[i].display_velocity()"),
		"配線: 先読みの相手側は予告の表示値(揺れたもの)を使う"
	)
	# 傾斜は本番(build_request)と同じ関数を通ること。先読みだけ違う土俵を歩くと
	# 交差時刻が本番とずれる。
	check.call(
		_function_body(battle_src, "func build_request(").contains("_stage_strength()"),
		"配線: 本番のリクエストも先読みと同じ傾斜の関数を通る"
	)


## 打ち切りの印と1行の配線。判定を画面まで引かないと、cut_by は「誰も見ない
## 正しい値」になる(この変更のまるごとが空回りする形)。
func _test_cut_mark_wired(check: Callable) -> void:
	var src := FileAccess.get_file_as_string("res://scenes/battle/LaunchController.gd")
	var draw_lead := _function_body(src, "func _draw_lead() -> void:")
	check.call(draw_lead.length() > 0, "打ち切りの印: _draw_lead の本体を取れた")
	check.call(
		draw_lead.contains("RendezvousPreview.cut_player(_lead)")
			and draw_lead.contains("RendezvousPreview.cut_enemy(_lead)"),
		"打ち切りの印: どちらの輪に印を置くかは RendezvousPreview が決める"
	)
	check.call(
		draw_lead.contains("_draw_cut_mark("), "打ち切りの印: 印を描く関数を呼ぶ"
	)
	var mark := _function_body(src, "func _draw_cut_mark(at: Vector2, radius: float) -> void:")
	check.call(
		mark.contains("Palette.STAT_DOWN"),
		"打ち切りの印: 色は Palette 由来(自機色・敵色のどちらでもない)"
	)
	# 印の色が輪の色と同じだと、印が付いているかどうかが見て分からない。
	check.call(
		Palette.STAT_DOWN != Palette.AIM and Palette.STAT_DOWN != Palette.ENEMY,
		"打ち切りの印: 印の色は自機色とも敵色とも別"
	)

	var battle_src := FileAccess.get_file_as_string("res://scenes/battle/Battle.gd")
	var aim := _function_body(battle_src, "func _on_aim_changed(origin: Vector2, velocity: Vector2) -> void:")
	check.call(aim.length() > 0, "打ち切りの文: _on_aim_changed の本体を取れた")
	check.call(
		aim.contains("_set_lead_hint(RendezvousPreview.hint_key("),
		"打ち切りの文: 実UIの1行は hint_key を通る(自前の判定を持たない)"
	)
	# 先読みが消える経路では行も消えること。残ると「もう当てはまらない警告」が居座る。
	check.call(
		aim.count("_set_lead_hint(\"\")") >= 2,
		"打ち切りの文: 先読みを消す経路では行も消す"
	)
	# 発射の瞬間に消える(決着後は同じ行へ相手の内訳が入る)。
	check.call(
		_function_body(battle_src, "func _begin(player_pos: Vector2, player_vel: Vector2) -> void:")
			.contains("_dealt_label.text = \"\""),
		"打ち切りの文: 発射で消える"
	)

	# CLIも同じ判定を通ること(ハーネスと実UIの情報量を対等に保つ約束)。
	var cli := FileAccess.get_file_as_string("res://playtest/naive_play.gd")
	check.call(
		_function_body(cli, "static func lead_text(lead: Dictionary) -> String:")
			.contains("RendezvousPreview.hint_key(lead)"),
		"打ち切りの文: CLIも hint_key を通る"
	)


## ソースから関数1つ分の本体を切り出す。次の "\nfunc " まで。
func _function_body(src: String, header: String) -> String:
	var start := src.find(header)
	if start < 0:
		return ""
	start += header.length()
	var end := src.find("\nfunc ", start)
	return src.substr(start) if end < 0 else src.substr(start, end - start)
