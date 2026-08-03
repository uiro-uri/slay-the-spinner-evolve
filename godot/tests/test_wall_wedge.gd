extends RefCounted

## 壁・柱の「くさび」(コマより狭い隙間に挟まったまま毎ステップ課金される)のテスト。
##
## 反射は速度しか変えず位置を戻さないので、コマの直径より狭い隙間(柱と壁の隅)に
## 入ったコマは面から離れられない。反発0.75は法線方向の勢いをほとんど残すため、
## 進む距離ゼロのまま毎フレーム衝突が成立し、衝突回数がフレームレートで決まる。
## 実測(コールドプレイ2026-08-03)では敵1体が柱(7,7)と右壁の間でxを8.75↔8.85と
## 往復しながら0.27秒で27.2→15.7rpsを失い、プレイヤー側も接触0回・壁54回で敗北した。
##
## ここで固定するのは:
##  - 押し出し量の純関数(符号付きのgapと、0で切ったpenetration)
##  - リゾルバが跳ね返りのたびにめり込みを解くこと(面の上に置き直す)
##  - 続いている接触は1回しか課金されないこと(くさびの再現環境で)
##  - 普通の往復バウンドは従来どおり毎回課金されること(課金を殺しすぎない)
##  - 衝撃波の接触点が面のちょうど上にあること(BattleMetricsが距離で持ち主を引く)

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_gap_and_penetration(check)
	_test_resolver_pushes_out(check)
	_test_wedge_is_billed_once(check)
	_test_normal_bounces_still_billed(check)
	_test_impact_point_sits_on_surface(check)


func _test_gap_and_penetration(check: Callable) -> void:
	# 内向き法線 (1,0) の壁が x=0 にある。半径1のコマ。
	var p := Vector2.ZERO
	var n := Vector2.RIGHT
	check.call(
		absf(SpinnerPhysics.wall_gap(p, n, Vector2(0.4, 0), 1.0) - 0.6) < EPS,
		"gap: めり込んでいれば正(0.6)"
	)
	check.call(
		absf(SpinnerPhysics.wall_gap(p, n, Vector2(1.0, 0), 1.0)) < EPS,
		"gap: ちょうど接触なら0"
	)
	check.call(
		SpinnerPhysics.wall_gap(p, n, Vector2(3.0, 0), 1.0) < -EPS,
		"gap: 離れていれば負(押し出しの0切りと違い符号が残る)"
	)
	check.call(
		absf(SpinnerPhysics.wall_penetration(p, n, Vector2(0.4, 0), 1.0) - 0.6) < EPS,
		"penetration: めり込み量はgapと同じ"
	)
	check.call(
		absf(SpinnerPhysics.wall_penetration(p, n, Vector2(3.0, 0), 1.0)) < EPS,
		"penetration: 離れていれば0(引き戻さない)"
	)
	# 柱: 中心(0,0) 半径2、コマ半径1 → 接触は距離3。
	check.call(
		absf(SpinnerPhysics.obstacle_gap(Vector2.ZERO, 2.0, Vector2(2.5, 0), 1.0) - 0.5) < EPS,
		"柱gap: めり込んでいれば正(0.5)"
	)
	check.call(
		absf(SpinnerPhysics.obstacle_gap(Vector2.ZERO, 2.0, Vector2(3.0, 0), 1.0)) < EPS,
		"柱gap: ちょうど接触なら0"
	)
	check.call(
		SpinnerPhysics.obstacle_gap(Vector2.ZERO, 2.0, Vector2(5.0, 0), 1.0) < -EPS,
		"柱gap: 離れていれば負"
	)
	check.call(
		absf(SpinnerPhysics.obstacle_penetration(
			Vector2.ZERO, 2.0, Vector2(5.0, 0), 1.0)) < EPS,
		"柱penetration: 離れていれば0"
	)


## まっすぐ壁へ撃ち込むだけの環境。跳ね返った後のコマが壁へ食い込んだままでない
## ことを、軌跡の全フレームで見る。
func _test_resolver_pushes_out(check: Callable) -> void:
	var r := _bounce_request()
	var result := BattleResolver.resolve(r)
	var walls := ArenaWall.build(r.wall_shape, r.arena_bounds)
	var worst := -INF
	for f in result.player_frames:
		for w in walls:
			worst = maxf(
				worst,
				SpinnerPhysics.wall_gap(w.point, w.normal, f.position, r.player.stats.radius)
			)
	check.call(
		worst < BattleResolver.SURFACE_CONTACT_SKIN,
		"押し出し: 跳ね返り後のコマが壁へ食い込んだまま残らない (最大めり込み %.5f)" % worst
	)


## くさびの再現: 柱と壁の隙間がコマの直径より狭い場所へ、すり鉢に押し戻される
## 向きで置く。1回の接触が何ステップ続こうと課金は1回であること。
func _test_wedge_is_billed_once(check: Callable) -> void:
	var r := _wedge_request()
	var result := BattleResolver.resolve(r)
	var hits := int(result.player_rps_loss.get("wall_hits", 0))
	var steps := result.player_frames.size()
	check.call(
		steps >= 60,
		"くさび: 検証環境が十分な長さ回っている (%dフレーム)" % steps
	)
	# 面から一度も離れないので、課金は接触の始まりだけ。初手は壁と柱の両方へ
	# 同時にめり込んだ状態から始まる(隙間が直径より狭い)ので上限は2。
	# 掛け金が無いと課金はフレーム数ぶん(この環境で200超)まで膨らむ。
	check.call(
		hits <= 2,
		"くさび: 挟まったまま毎ステップ課金されない (壁ヒット %d回 / %dフレーム)"
			% [hits, steps]
	)
	var lost: float = result.player_rps_loss.get("wall", 0.0)
	check.call(
		lost < r.player.stats.rps * 0.2,
		"くさび: 挟まっただけで回転を溶かされない (喪失 %.2f / %.2f)"
			% [lost, r.player.stats.rps]
	)
	# 挟まっている間も反射自体は続く=面をすり抜けて外へ出ていかない。
	var out := false
	for f in result.player_frames:
		if not r.arena_bounds.has_point(f.position):
			out = true
	check.call(not out, "くさび: 課金を止めても面をすり抜けて場外へ出ない")


## 課金を殺しすぎていないことの対。左右の壁を往復するコマは、跳ね返るたびに
## 毎回課金される(接触のたびに面から離れているため)。
func _test_normal_bounces_still_billed(check: Callable) -> void:
	var r := _bounce_request()
	var result := BattleResolver.resolve(r)
	var hits := int(result.player_rps_loss.get("wall_hits", 0))
	check.call(
		hits >= 3,
		"通常バウンド: 離れて戻る往復は毎回課金される (壁ヒット %d回)" % hits
	)
	check.call(
		result.wall_impacts.size() == hits,
		"通常バウンド: 衝撃波の数が課金回数と一致する (%d / %d)"
			% [result.wall_impacts.size(), hits]
	)


## 衝撃波の接触点は面のちょうど上=そのフレームのコマ位置から半径ぶん。
## BattleMetricsはこの距離で「その衝撃波が誰のものか」を引くので、押し出しで
## 位置が動いた後に点を採らないと、壁の事象が衝突削りへ誤分類される。
func _test_impact_point_sits_on_surface(check: Callable) -> void:
	var r := _bounce_request()
	var result := BattleResolver.resolve(r)
	var radius := r.player.stats.radius
	var dt := result.time_step
	check.call(result.wall_impacts.size() > 0, "接触点: 検証環境で壁衝突が起きている")
	var worst := 0.0
	for imp in result.wall_impacts:
		var i := int(round(imp.time / dt)) + 1
		if i < 1 or i >= result.player_frames.size():
			continue
		var f: BattleResult.Snapshot = result.player_frames[i]
		worst = maxf(worst, absf(imp.point.distance_to(f.position) - radius))
	check.call(
		worst <= 1e-3,
		"接触点: 押し出し後の位置から半径ぶんの点に乗っている (ずれ %.5f)" % worst
	)


## 左右の壁を往復するだけの環境(すり鉢と摩擦と自然減衰を切る)。
func _bounce_request() -> BattleRequest:
	var pstats := SpinnerStats.new()
	pstats.mass = 1.5
	pstats.radius = 0.7
	pstats.friction = 0.0
	pstats.restitution = 1.0
	pstats.rps = 40.0
	var estats := SpinnerStats.new()
	estats.radius = 0.4
	estats.rps = 40.0
	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	r.max_duration = 4.0
	# 敵は隅で静止させ、往復の線から外す(この検証は壁だけを見る)。
	r.player = BattleRequest.Launch.new(pstats, Vector2(5, 5), Vector2(12, 0))
	r.enemies = [BattleRequest.Launch.new(estats, Vector2(1.0, 9.0), Vector2.ZERO)]
	return r


## くさびの再現環境。柱を壁際に置き、その隙間をコマの直径より狭くする。
## すり鉢の傾斜が中心へ押し戻すので、コマは柱と壁の間から出られない。
func _wedge_request() -> BattleRequest:
	var pstats := SpinnerStats.new()
	pstats.mass = 2.0
	pstats.radius = 1.2
	pstats.friction = 0.0
	pstats.restitution = 0.75
	pstats.rps = 30.0
	var estats := SpinnerStats.new()
	estats.radius = 0.4
	estats.rps = 40.0
	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.max_duration = 4.0
	# 柱(7.4,5)半径0.6 と 右壁(x=10)の隙間は 10-7.4-0.6=2.0 < 直径2.4。
	r.obstacles = [Vector3(7.4, 5.0, 0.6)]
	# 隙間のまん中へ、壁へ向かう速度で置く。以後は傾斜が柱側へ押し戻し続ける。
	r.player = BattleRequest.Launch.new(pstats, Vector2(9.0, 5.0), Vector2(2.0, 0.0))
	r.enemies = [BattleRequest.Launch.new(estats, Vector2(1.0, 1.0), Vector2.ZERO)]
	return r
