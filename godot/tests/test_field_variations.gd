extends RefCounted

## フィールドバリエーション(壁の形・障害物・リングアウト・土俵抽選)のテスト。
##
## spinner_physics.gd / arena_wall.gd と同じく、向き・単調性・不変量で確かめる。
## 生の数値照合はせず、手触りの調整で定数が変わっても壊れない性質を見る。

const EPS := 1e-4

## Battle.gd の enemy_spawn_radius 既定値。障害物がこのリングと重ならないことを確かめる。
const SPAWN_RING := 4.0


func run(check: Callable) -> void:
	_test_obstacle_hit(check)
	_test_obstacle_bounce(check)
	_test_from_polygon(check)
	_test_inradius(check)
	_test_clamp_inside_circle(check)
	_test_point_inside(check)
	_test_roster(check)
	_test_localization(check)
	_test_serialization(check)
	_test_ring_out(check)


func _stats(mass: float, radius: float, rps: float) -> SpinnerStats:
	var s := SpinnerStats.new()
	s.mass = mass
	s.radius = radius
	s.friction = 0.98
	s.restitution = 1.0
	s.rps = rps
	return s


func _test_obstacle_hit(check: Callable) -> void:
	var c := Vector2(5, 5)
	# めり込んで中心へ向かっていれば真
	check.call(
		SpinnerPhysics.obstacle_hit(c, 1.0, Vector2(5.8, 5), Vector2(-1, 0), 0.5),
		"障害物: めり込んで中心へ向かっていれば真"
	)
	# めり込んでいても離れる向きなら偽（多重衝突を防ぐ）
	check.call(
		not SpinnerPhysics.obstacle_hit(c, 1.0, Vector2(5.8, 5), Vector2(1, 0), 0.5),
		"障害物: めり込んでいても離れる向きなら偽"
	)
	# 離れていれば偽
	check.call(
		not SpinnerPhysics.obstacle_hit(c, 1.0, Vector2(9, 5), Vector2(-1, 0), 0.5),
		"障害物: 離れていれば偽"
	)
	# 完全に中心が重なっていても0除算せず、偽を返す（NaN・クラッシュ無し）
	check.call(
		not SpinnerPhysics.obstacle_hit(c, 1.0, c, Vector2(1, 0), 0.5),
		"障害物: 中心が重なっても壊れない"
	)


func _test_obstacle_bounce(check: Callable) -> void:
	# 障害物を原点に置き、法線＝中心からの放射方向で反射する。
	var obstacle_center := Vector2(0, 0)
	var pos := Vector2(1, 0)
	var normal := (pos - obstacle_center).normalized()
	var bounced := SpinnerPhysics.wall_bounce(Vector2(-2, 3), normal, 1.0)
	check.call(absf(bounced.x - 2.0) < EPS, "障害物: 放射方向が反転する (x=%.3f)" % bounced.x)
	check.call(absf(bounced.y - 3.0) < EPS, "障害物: 接線方向は保たれる (y=%.3f)" % bounced.y)


func _test_from_polygon(check: Callable) -> void:
	var center := Vector2(0, 0)
	var r := 5.0
	var sides := 8
	var walls := ArenaWall.from_polygon(center, r, sides)

	check.call(walls.size() == sides, "多角形: 辺の数だけ壁ができる (%d)" % walls.size())

	var apothem := r * cos(PI / float(sides))
	var normal_sum := Vector2.ZERO
	var all_unit := true
	var all_inward := true
	var all_apothem := true
	for wall in walls:
		normal_sum += wall.normal
		if absf(wall.normal.length() - 1.0) >= EPS:
			all_unit = false
		# 内向き＝中心へ向かう成分が正
		if wall.normal.dot(center - wall.point) <= 0.0:
			all_inward = false
		if absf(wall.point.distance_to(center) - apothem) >= EPS:
			all_apothem = false
	check.call(all_unit, "多角形: 法線はすべて単位ベクトル")
	check.call(all_inward, "多角形: 法線はすべて内向き")
	check.call(all_apothem, "多角形: 辺の点は内接円(apothem)上にある")
	check.call(normal_sum.length() < EPS, "多角形: 内向き法線の総和はゼロ(対称)")


func _test_inradius(check: Callable) -> void:
	var bounds := Rect2(0, 0, 10, 10)
	var rect := ArenaWall.inradius_for(ArenaWall.WallShape.RECT, bounds)
	var octa := ArenaWall.inradius_for(ArenaWall.WallShape.OCTAGON, bounds)
	var round_ := ArenaWall.inradius_for(ArenaWall.WallShape.ROUND, bounds)

	check.call(absf(rect - 5.0) < EPS, "内接円: 矩形は短辺の半分 (%.3f)" % rect)
	# 辺が多いほど内接円は外接円(5)に近づく: 八角形 < 円(32角形) < 矩形
	check.call(octa < rect, "内接円: 八角形は矩形より内側")
	check.call(round_ > octa and round_ < rect, "内接円: 円は八角形と矩形の間")


func _test_clamp_inside_circle(check: Callable) -> void:
	var center := Vector2(5, 5)
	var inradius := 5.0
	var radius := 0.5

	# 内側の点はそのまま
	var inside := ArenaWall.clamp_inside_circle(center, inradius, Vector2(5.5, 5), radius)
	check.call(inside.is_equal_approx(Vector2(5.5, 5)), "円クランプ: 内側の点は不変")

	# 外側の点は inradius - radius の円周へ寄る
	var outside := ArenaWall.clamp_inside_circle(center, inradius, Vector2(100, 5), radius)
	check.call(
		absf(outside.distance_to(center) - (inradius - radius)) < EPS,
		"円クランプ: 外側は内接円-半径へ寄る (%.3f)" % outside.distance_to(center)
	)


func _test_point_inside(check: Callable) -> void:
	var bounds := Rect2(0, 0, 10, 10)
	var rect_walls := ArenaWall.build(ArenaWall.WallShape.RECT, bounds)
	check.call(ArenaWall.point_inside(rect_walls, Vector2(5, 5)), "内外判定(矩形): 中心は内側")
	check.call(not ArenaWall.point_inside(rect_walls, Vector2(11, 5)), "内外判定(矩形): 場外は外側")
	check.call(not ArenaWall.point_inside(rect_walls, Vector2(5, -1)), "内外判定(矩形): 場外(上)は外側")

	var octa_walls := ArenaWall.build(ArenaWall.WallShape.OCTAGON, bounds)
	check.call(ArenaWall.point_inside(octa_walls, Vector2(5, 5)), "内外判定(八角形): 中心は内側")
	check.call(
		not ArenaWall.point_inside(octa_walls, Vector2(100, 100)),
		"内外判定(八角形): 遠くの点は外側"
	)


func _test_roster(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for step in range(1, MapTree.STEP_GOAL + 1):
		var field: FieldData = FieldRoster.pick_for_step(step, rng)
		check.call(
			field != null and field.title_key != "" and field.inradius() > 0.0,
			"土俵抽選: 段%d に出せる土俵がある" % step
		)

	# 全フィールドの障害物が土俵内に収まり、出現リング(半径4)と重ならない。
	var ring_ok := true
	var in_bounds := true
	var strength_ok := true
	for field in FieldRoster.all():
		if field.stage_strength < 0.0:
			strength_ok = false
		var arena_center := field.center()
		var inr := field.inradius()
		for o in field.obstacles:
			var oc := Vector2(o.x, o.y)
			var dist := oc.distance_to(arena_center)
			# 障害物全体が内接円の内側に収まる
			if dist + o.z > inr:
				in_bounds = false
			# 障害物が出現リングを跨がない（リング上の敵と初期重なりを避ける）
			if absf(dist - SPAWN_RING) <= o.z:
				ring_ok = false
	check.call(strength_ok, "土俵抽選: 傾斜の強さは非負")
	check.call(in_bounds, "土俵抽選: 障害物は土俵内に収まる")
	check.call(ring_ok, "土俵抽選: 障害物は出現リングと重ならない")


func _test_localization(check: Callable) -> void:
	TranslationServer.set_locale("ja")
	var untranslated: Array[String] = []
	for field in FieldRoster.all():
		if tr(field.title_key) == field.title_key:
			untranslated.append(field.title_key)
	check.call(untranslated.is_empty(), "土俵: 名前に訳がある (未訳: %s)" % [untranslated])


func _test_serialization(check: Callable) -> void:
	var r := BattleRequest.new()
	r.player = BattleRequest.Launch.new(_stats(1.5, 0.5, 15.0), Vector2(2, 8), Vector2(6, -6))
	r.enemy = BattleRequest.Launch.new(_stats(1.0, 0.5, 15.0), Vector2(8, 2), Vector2(-3, 4))
	r.wall_shape = ArenaWall.WallShape.OCTAGON
	r.obstacles = [Vector3(3, 3, 0.6), Vector3(7, 7, 0.6)]
	r.ring_out = true

	var revived := BattleRequest.from_dict(r.to_dict())
	check.call(revived.wall_shape == r.wall_shape, "直列化: wall_shapeが往復する")
	check.call(revived.obstacles.size() == r.obstacles.size(), "直列化: 障害物の数が往復する")
	check.call(
		revived.obstacles.size() == 2 and revived.obstacles[0].is_equal_approx(Vector3(3, 3, 0.6)),
		"直列化: 障害物の値が往復する"
	)
	check.call(revived.ring_out == r.ring_out, "直列化: ring_outが往復する")

	# JSONを通しても壊れない（サーバーへ送る前提）
	var parsed = JSON.parse_string(JSON.stringify(r.to_dict()))
	check.call(parsed != null, "直列化: JSONにできる")
	if parsed != null:
		var from_json := BattleRequest.from_dict(parsed)
		check.call(
			from_json.wall_shape == r.wall_shape and from_json.obstacles.size() == 2,
			"直列化: JSONを通しても土俵が変わらない"
		)

	# 障害物ありのリクエストでも解決が終わり決定的
	r.max_duration = 10.0
	var a := BattleResolver.resolve(r)
	var b := BattleResolver.resolve(BattleRequest.from_dict(r.to_dict()))
	check.call(a.outcome == b.outcome, "直列化: 障害物ありでも同じ結果")


func _test_ring_out(check: Callable) -> void:
	# 壁のない土俵で、外向きに強く撃つと場外へ出て即敗北になる。
	# 傾斜を0にして中心へ引き戻されないようにし、確実に外へ抜けさせる。
	var r := BattleRequest.new()
	r.ring_out = true
	r.wall_shape = ArenaWall.WallShape.RECT
	r.stage_strength = 0.0
	r.player = BattleRequest.Launch.new(_stats(1.5, 0.5, 15.0), Vector2(9, 5), Vector2(10, 0))
	r.enemy = BattleRequest.Launch.new(_stats(1.5, 0.5, 15.0), Vector2(5, 5), Vector2.ZERO)

	var result := BattleResolver.resolve(r)
	check.call(result.ring_out, "リングアウト: 場外で決着したフラグが立つ")
	check.call(not result.timed_out, "リングアウト: 上限前に決着する")
	check.call(
		result.outcome == BattleResult.Outcome.ENEMY_WIN,
		"リングアウト: 場外へ出たコマが負ける (%s)" % ["draw", "player", "enemy"][result.outcome]
	)
	# リングアウトの土俵は壁で弾かないので、壁衝突は記録されない。
	check.call(result.wall_impacts.is_empty(), "リングアウト: 壁で弾かず衝突も記録しない")

	# 対照: 同じ発射でも ring_out=false なら壁で弾き返し、場外にはならない。
	var r2 := BattleRequest.new()
	r2.ring_out = false
	r2.wall_shape = ArenaWall.WallShape.RECT
	r2.stage_strength = 0.0
	r2.max_duration = 5.0
	r2.player = BattleRequest.Launch.new(_stats(1.5, 0.5, 15.0), Vector2(9, 5), Vector2(10, 0))
	r2.enemy = BattleRequest.Launch.new(_stats(1.5, 0.5, 15.0), Vector2(5, 5), Vector2.ZERO)
	var result2 := BattleResolver.resolve(r2)
	check.call(not result2.ring_out, "リングアウト: 壁ありの土俵では場外にならない")
	check.call(result2.wall_impacts.size() > 0, "リングアウト: 壁ありなら弾き返す")
