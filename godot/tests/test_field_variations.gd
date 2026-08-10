extends RefCounted

## フィールドバリエーション(壁の形・障害物・土俵抽選)のテスト。
##
## spinner_physics.gd / arena_wall.gd と同じく、向き・単調性・不変量で確かめる。
## 生の数値照合はせず、手触りの調整で定数が変わっても壊れない性質を見る。

const EPS := 1e-4

## Battle.gd の enemy_spawn_radius 既定値。障害物がこのリングと重ならないことを確かめる。
const SPAWN_RING := 4.0

## 道中の土俵の一辺(FieldRoster._BOUNDS)。決戦だけこれより広い。
const _BOUNDS_SIDE := 10.0


func run(check: Callable) -> void:
	_test_obstacle_hit(check)
	_test_obstacle_bounce(check)
	_test_from_polygon(check)
	_test_inradius(check)
	_test_clamp_inside_circle(check)
	_test_push_out_of_obstacles(check)
	_test_clamp_placement(check)
	_test_roster(check)
	_test_step_obstacles(check)
	_test_boss_octagon(check)
	_test_localization(check)
	_test_serialization(check)


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


## 柱に重なった初期配置の押し出し。柱に重なったまま発射・出現すると、毎ステップ
## 柱に弾かれ続ける見えない拘束になる(2026-07-29のコールドプレイ: 発射が柱に
## 0.33めり込み、3.75秒で壁系22ヒット・接触0回で決着した)。
func _test_push_out_of_obstacles(check: Callable) -> void:
	var obstacles: Array[Vector3] = [Vector3(3, 3, 0.6), Vector3(7, 7, 0.6)]
	var radius := 0.7

	# 重なっていなければそのまま
	var free := Vector2(5, 5)
	check.call(
		ArenaWall.push_out_of_obstacles(free, obstacles, radius).is_equal_approx(free),
		"柱押し出し: 重なっていない位置は動かさない"
	)

	# 重なっていたら柱の外(柱半径+コマ半径以上)へ出る。押し出しの向きは中心から放射方向。
	var overlapping := Vector2(7.687, 7.687)
	var pushed := ArenaWall.push_out_of_obstacles(overlapping, obstacles, radius)
	check.call(
		pushed.distance_to(Vector2(7, 7)) >= 0.6 + radius - EPS,
		"柱押し出し: めり込みは柱の外へ出る (%.3f)" % pushed.distance_to(Vector2(7, 7))
	)
	check.call(
		((pushed - Vector2(7, 7)).normalized()
			- (overlapping - Vector2(7, 7)).normalized()).length() < EPS,
		"柱押し出し: 元の位置の方向へ押し出す(反対側へ飛ばない)"
	)

	# 柱の真上(向きが決められない)でもfallback方向へ決定的に出る
	var centered := ArenaWall.push_out_of_obstacles(
		Vector2(3, 3), obstacles, radius, Vector2.UP)
	check.call(
		centered.distance_to(Vector2(3, 3)) >= 0.6 + radius - EPS,
		"柱押し出し: 柱の真上からでも外へ出る"
	)


## FieldData.clamp_placement: 壁の内側かつ柱の外。発射(実UI/CLI/bot)の共通経路。
func _test_clamp_placement(check: Callable) -> void:
	var pillars: FieldData = null
	for field in FieldRoster.all():
		if not field.obstacles.is_empty():
			pillars = field
			break
	check.call(pillars != null, "柱配置: 障害物つき土俵がロスターにある")
	if pillars == null:
		return

	var radius := 0.7
	# コールドプレイの実例: CLIの発射リング(inradius-半径-0.5)の対角45度は柱に重なる。
	var ring := pillars.inradius() - radius - 0.5
	var want := pillars.center() + Vector2.RIGHT.rotated(deg_to_rad(45.0)) * ring
	var placed := pillars.clamp_placement(want, radius)
	var clear := true
	for o in pillars.obstacles:
		if placed.distance_to(Vector2(o.x, o.y)) < o.z + radius - EPS:
			clear = false
	check.call(clear, "柱配置: 発射リング対角の柱めり込みが解消される (%s)" % str(placed))
	var inside := pillars.clamp_inside(placed, radius)
	check.call(inside.is_equal_approx(placed), "柱配置: 押し出し後も壁の内側に収まる")

	# 柱から離れた位置は動かさない(過剰な介入をしない)
	var free := pillars.center()
	check.call(
		pillars.clamp_placement(free, radius).is_equal_approx(free),
		"柱配置: 柱から離れた位置は動かさない"
	)

	# 発射クランプ(間合い込み)を通しても柱に重ならない
	var spawn := PackedVector2Array([pillars.center() + Vector2(0, -4)])
	var launched := pillars.clamp_launch(want, spawn, PackedFloat32Array([0.5]), radius)
	var launch_clear := true
	for o in pillars.obstacles:
		if launched.distance_to(Vector2(o.x, o.y)) < o.z + radius - EPS:
			launch_clear = false
	check.call(launch_clear, "柱配置: 間合いクランプを通しても柱に重ならない")


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


## ボス段(レベル5)の土俵は必ず八角形闘技場で固定されること。決戦の特別感。
## ボス以外の段は従来どおりランダム(形が固定されない)ことも合わせて見る。
## 柱の本数が段で間引かれる(FieldRoster.step_field)。位置・半径・壁・傾斜は不変。
##
## 見るのは「浅い段では減り、深い段では表のまま」という向きと、間引きが
## **抽選の両方の入口**(pick_for_step と MapTree の引き直し)を通ること。
## 本数そのものの値は手触りで動く定数なので、定数を読んで照合する。
func _test_step_obstacles(check: Callable) -> void:
	var listed: FieldData = null
	for field in FieldRoster.all():
		if field.obstacles.size() >= 2:
			listed = field
			break
	check.call(listed != null, "段別の柱: 表に柱2本以上の土俵がある")
	if listed == null:
		return

	# 浅い段(Lv1・Lv2)は間引かれ、深い段(Lv3以上)は表のまま。
	var early_steps: Array[int] = []
	var full_steps: Array[int] = []
	for step in range(1, MapTree.STEP_GOAL):
		if EnemyRoster.level_for_step(step) >= FieldRoster.OBSTACLE_FULL_LEVEL:
			full_steps.append(step)
		else:
			early_steps.append(step)
	check.call(
		not early_steps.is_empty() and not full_steps.is_empty(),
		"段別の柱: 間引く段と表のままの段が両方ある (浅%d 深%d)"
			% [early_steps.size(), full_steps.size()]
	)

	var early_ok := true
	for step in early_steps:
		var f := FieldRoster.step_field(listed, step)
		if f.obstacles.size() != FieldRoster.OBSTACLE_EARLY_COUNT:
			early_ok = false
	check.call(
		early_ok,
		"段別の柱: 浅い段は%d本に間引かれる" % FieldRoster.OBSTACLE_EARLY_COUNT
	)
	check.call(
		FieldRoster.OBSTACLE_EARLY_COUNT < listed.obstacles.size(),
		"段別の柱: 間引きが実際に本数を減らしている(表%d本)" % listed.obstacles.size()
	)

	var full_ok := true
	for step in full_steps:
		if FieldRoster.step_field(listed, step).obstacles.size() != listed.obstacles.size():
			full_ok = false
	check.call(full_ok, "段別の柱: 深い段は表の本数のまま")

	# 深い段では複製せず同一インスタンスを返す＝従来と厳密に一致。
	check.call(
		FieldRoster.step_field(listed, full_steps[0]) == listed,
		"段別の柱: 間引くものが無い段は土俵をそのまま返す"
	)

	# 柱の無い土俵はどの段でも0本のまま(間引きが余計なことをしない)。
	var plain_ok := true
	for field in FieldRoster.all():
		if not field.obstacles.is_empty():
			continue
		for step in range(1, MapTree.STEP_GOAL):
			if not FieldRoster.step_field(field, step).obstacles.is_empty():
				plain_ok = false
	check.call(plain_ok, "段別の柱: 柱の無い土俵はどの段でも0本")

	# 残った柱は表の先頭そのまま(位置も半径も作り変えない)。
	var trimmed := FieldRoster.step_field(listed, early_steps[0])
	check.call(
		not trimmed.obstacles.is_empty()
			and trimmed.obstacles[0].is_equal_approx(listed.obstacles[0]),
		"段別の柱: 残る柱は表の先頭と同じ位置・半径"
	)
	check.call(
		trimmed.title_key == listed.title_key
			and trimmed.wall_shape == listed.wall_shape
			and trimmed.stage_shape == listed.stage_shape
			and is_equal_approx(trimmed.stage_strength, listed.stage_strength)
			and trimmed.arena_bounds == listed.arena_bounds,
		"段別の柱: 間引いても土俵の他の性質は変わらない"
	)
	check.call(
		listed.obstacles.size() >= 2,
		"段別の柱: 間引きが表そのものを書き換えていない(表は%d本)" % listed.obstacles.size()
	)

	# 入口1: 抽選。浅い段では、どの土俵を引いても柱は上限本数を超えない。
	var picked_ok := true
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260810
	for i in 400:
		var step: int = early_steps[i % early_steps.size()]
		var f := FieldRoster.pick_for_step(step, rng)
		if f != null and f.obstacles.size() > FieldRoster.OBSTACLE_EARLY_COUNT:
			picked_ok = false
	check.call(picked_ok, "段別の柱: pick_for_step が浅い段で間引きを通す")

	# 入口2: マップ生成。引き直し(_ensure_distinct_field)を通った盤面でも同じ。
	var map_ok := true
	var saw_early_pillar := false
	for seed_i in 40:
		var map_rng := RandomNumberGenerator.new()
		map_rng.seed = seed_i
		var tree := MapTree.generate(map_rng)
		for coord: Vector2i in tree.nodes:
			var node: MapTree.MapNode = tree.nodes[coord]
			if node == null or node.field == null:
				continue
			# その段に許される上限は「表の最大本数」を投げ込んで引き出す。
			var cap := FieldRoster.obstacle_count_for_step(coord.x, listed.obstacles.size())
			if node.field.obstacles.size() > cap:
				map_ok = false
			if (
				EnemyRoster.level_for_step(coord.x) < FieldRoster.OBSTACLE_FULL_LEVEL
				and not node.field.obstacles.is_empty()
			):
				saw_early_pillar = true
	check.call(map_ok, "段別の柱: 生成された地図のどのノードも段の上限を超えない")
	check.call(saw_early_pillar, "段別の柱: 浅い段にも柱は残る(0本にはしない)")


func _test_boss_octagon(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	var all_octa := true
	for i in range(20):
		rng.seed = i
		var field: FieldData = FieldRoster.pick_for_step(MapTree.STEP_GOAL, rng)
		if field.wall_shape != ArenaWall.WallShape.OCTAGON:
			all_octa = false
	check.call(all_octa, "土俵抽選: ボス段は必ず八角形闘技場")

	# 形は道中のFIELD_ARENAと同じだが、広さは決戦専用。広さの縛りは
	# tests/test_boss_arena.gd が幾何で見る。
	rng.seed = 0
	var boss: FieldData = FieldRoster.pick_for_step(MapTree.STEP_GOAL, rng)
	check.call(
		boss.arena_bounds.size.x > _BOUNDS_SIDE,
		"土俵抽選: ボス段の土俵は道中より広い (%.1f > %.1f)" % [
			boss.arena_bounds.size.x, _BOUNDS_SIDE]
	)

	# ボス以外(段1)は形が固定されず、複数の形が出る。
	var shapes := {}
	for i in range(60):
		rng.seed = i + 100
		var field: FieldData = FieldRoster.pick_for_step(1, rng)
		shapes[field.wall_shape] = true
	check.call(shapes.size() > 1, "土俵抽選: ボス以外は形が固定されない (%d種)" % shapes.size())


func _test_localization(check: Callable) -> void:
	TranslationServer.set_locale("ja")
	var untranslated: Array[String] = []
	# 決戦の土俵はall()に入っていない(段9専用)ので、明示的に足して漏らさない。
	var fields := FieldRoster.all()
	fields.append(FieldRoster.boss_field())
	for field in fields:
		if tr(field.title_key) == field.title_key:
			untranslated.append(field.title_key)
	check.call(untranslated.is_empty(), "土俵: 名前に訳がある (未訳: %s)" % [untranslated])


func _test_serialization(check: Callable) -> void:
	var r := BattleRequest.new()
	r.player = BattleRequest.Launch.new(_stats(1.5, 0.5, 15.0), Vector2(2, 8), Vector2(6, -6))
	r.enemies = [BattleRequest.Launch.new(_stats(1.0, 0.5, 15.0), Vector2(8, 2), Vector2(-3, 4))]
	r.wall_shape = ArenaWall.WallShape.OCTAGON
	r.obstacles = [Vector3(3, 3, 0.6), Vector3(7, 7, 0.6)]

	var revived := BattleRequest.from_dict(r.to_dict())
	check.call(revived.wall_shape == r.wall_shape, "直列化: wall_shapeが往復する")
	check.call(revived.obstacles.size() == r.obstacles.size(), "直列化: 障害物の数が往復する")
	check.call(
		revived.obstacles.size() == 2 and revived.obstacles[0].is_equal_approx(Vector3(3, 3, 0.6)),
		"直列化: 障害物の値が往復する"
	)

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
