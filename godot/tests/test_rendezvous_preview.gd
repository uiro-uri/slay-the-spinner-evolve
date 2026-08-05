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
	_test_launch_controller_wires_lead(check)


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
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, 0.0, [], 2.0
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
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, 0.0, [], 2.0
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
		center, 0.0, SpinnerPhysics.StageShape.DISH, 0.0, [], 2.0
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
		center, 0.0, SpinnerPhysics.StageShape.DISH, 0.0, [], 2.0
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
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, 4.0, [], 3.0
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
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, 0.0, [], 3.0
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
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, 0.0, [], 3.0
	)
	check.call(bool(far_contact["contact"]), "先読み: 長く見れば遠い噛み合いも出る")
	check.call(
		float(far_contact["time"]) >= 0.0 and float(far_contact["time"]) <= 3.0 + 0.02,
		"先読み: 時刻はhorizonに収まる (%.2f)" % far_contact["time"]
	)

	var short := RendezvousPreview.closest_approach(
		Vector2(1, 5), Vector2(3, 0), _stats(0.5),
		Vector2(9, 5), Vector2(-3, 0), _stats(0.5),
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, 0.0, [], 0.3
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
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, 0.0, [], 2.0, 0.0
	)
	check.call(not bool(r["contact"]), "先読み: dt=0なら先へ進まない")
	check.call(is_equal_approx(float(r["time"]), 0.0), "先読み: dt=0の時刻は0")


## 発射の瞬間から食い込んでいるなら、その場で噛み合いと出す(進める前に返る)。
func _test_overlap_at_start(check: Callable) -> void:
	var r := RendezvousPreview.closest_approach(
		Vector2(5.0, 5.0), Vector2(1, 0), _stats(0.5),
		Vector2(5.4, 5.0), Vector2(-1, 0), _stats(0.5),
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, 0.0, [], 2.0
	)
	check.call(bool(r["contact"]), "先読み: 最初から食い込んでいれば噛み合い")
	check.call(is_equal_approx(float(r["time"]), 0.0), "先読み: その時刻は0")


## 大きいコマほど早く触れる。接触の判定が半径の和で決まっていること。
func _test_radius_widens_contact(check: Callable) -> void:
	var small := RendezvousPreview.closest_approach(
		Vector2(1, 5), Vector2(6, 0), _stats(0.3),
		Vector2(9, 5), Vector2(-6, 0), _stats(0.3),
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, 0.0, [], 2.0
	)
	var big := RendezvousPreview.closest_approach(
		Vector2(1, 5), Vector2(6, 0), _stats(1.2),
		Vector2(9, 5), Vector2(-6, 0), _stats(1.2),
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, 0.0, [], 2.0
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
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, 0.0, [], 2.0
	)
	var fat := RendezvousPreview.closest_approach(
		Vector2(1, 5), Vector2(6, 0), _stats(0.6),
		Vector2(1, 5.9), Vector2(6, -0.2), _stats(0.6),
		Vector2(5, 5), 0.0, SpinnerPhysics.StageShape.DISH, 0.0, [], 2.0
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
		Vector2(5, 5), 4.9, SpinnerPhysics.StageShape.DISH, 4.6, [], 1.4
	)
	var second := RendezvousPreview.closest_approach(
		Vector2(1, 5), Vector2(6, 0), mine,
		Vector2(9, 5), Vector2(-6, 0), theirs,
		Vector2(5, 5), 4.9, SpinnerPhysics.StageShape.DISH, 4.6, [], 1.4
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
		ArenaWall.inradius_for(request.wall_shape, request.arena_bounds), [], 2.0
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
		center, 0.0, SpinnerPhysics.StageShape.DISH, 0.0, [], 2.0
	)
	check.call(bool(through["contact"]), "先読み: 柱を見なければ柱越しに噛み合うと出る")
	var blocked := RendezvousPreview.closest_approach(
		Vector2(1, 3), Vector2(6, 0), _stats(0.3),
		Vector2(9, 3), Vector2(-6, 0), _stats(0.3),
		center, 0.0, SpinnerPhysics.StageShape.DISH, 0.0, pillar, 2.0
	)
	check.call(bool(blocked["cut_short"]), "先読み: 柱へ届いたら打ち切る")
	check.call(not bool(blocked["contact"]), "先読み: 柱で打ち切ったなら噛み合いは出さない")

	# 柱の縁に座った状態から、ゆっくり離れる向きへ撃つ。数刻みは柱の間合いに
	# 居続けるので、「触れているか」で切る実装なら1刻み目で消える。
	var seated := RendezvousPreview.closest_approach(
		Vector2(5.0, 3.85), Vector2(0, 1.2), _stats(0.3),
		Vector2(5.0, 7.5), Vector2(0, -8), _stats(0.3),
		center, 0.0, SpinnerPhysics.StageShape.DISH, 0.0, pillar, 2.0
	)
	check.call(
		bool(seated["contact"]),
		"先読み: 発射時から接している柱では打ち切らない (cut=%s)" % str(seated["cut_short"])
	)


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


## ソースから関数1つ分の本体を切り出す。次の "\nfunc " まで。
func _function_body(src: String, header: String) -> String:
	var start := src.find(header)
	if start < 0:
		return ""
	start += header.length()
	var end := src.find("\nfunc ", start)
	return src.substr(start) if end < 0 else src.substr(start, end - start)
