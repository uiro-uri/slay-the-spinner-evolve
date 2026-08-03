extends RefCounted

## slope_contour.gd のテスト。対戦画面の床に描く「傾斜の等高線」を確かめる。
##
## 見た目そのものは静止画では確かめられない(CLAUDE.mdの方針)ので、ここで固定するのは
## 「調整で数値を動かしても生き残る性質」だけ:
##   - 高さは傾斜の加速度の積分。すり鉢は半径の2乗、円錐は半径に比例する
##     ——その場合分けを書き写さず SpinnerPhysics に測らせているので、物理を変えれば追従する
##   - 輪は内から外へ単調で、最外周はちょうど内接半径(壁)。土俵の外へ出ない
##   - **すり鉢は縁に寄って混み、円錐は等間隔**。傾斜の「形」が線の詰まり方に出る
##   - 本数はマップのケバと同数。ノードの絵と入場後の床が対で読める
##   - **実際の土俵一覧(FieldRoster)で、外周形状と柱が同じ土俵は床の絵で必ず割れる**
##     ——これが今回の眼目。ここが割れないと、入場しても土俵の違いが分からないまま
##   - 従来の「どの土俵も4等分の同心円」に戻すと落ちる

const EPS := 1e-4

## 半径の相対誤差の許容。逆引きの線形補間ぶんだけ理論値からずれる(SAMPLES=512)。
const R_TOL := 1e-3


func run(check: Callable) -> void:
	_test_empty_cases(check)
	_test_height_definition(check)
	_test_ordering(check)
	_test_shape_spacing(check)
	_test_count_matches_map(check)
	_test_roster_distinguishable(check)
	_test_not_uniform_rings(check)


## 輪が0本になるべき場合。土俵が無い(テスト・単体起動のフォールバック前)とき。
func _test_empty_cases(check: Callable) -> void:
	check.call(SlopeContour.radii(null).is_empty(), "土俵が無ければ等高線を出さない")
	check.call(SlopeContour.ring_count(null) == 0, "土俵が無ければ本数は0")
	check.call(is_equal_approx(SlopeContour.height(null, 5.0), 0.0), "土俵が無ければ高さ0")
	check.call(is_equal_approx(SlopeContour.height(_dish(4.9), 0.0), 0.0), "半径0の高さは0")

	# 傾斜ゼロの土俵。高さで割れないので半径の等分へ落ちる(輪が消えたり
	# ゼロ除算でnanになったりしない)。
	var flat := SlopeContour.radii(_dish(0.0))
	check.call(not flat.is_empty(), "傾斜ゼロの土俵でも輪は出る")
	var flat_even := true
	for k in flat.size():
		var want := 5.0 * float(k + 1) / float(flat.size())
		if absf(flat[k] - want) > R_TOL * 5.0:
			flat_even = false
	check.call(flat_even, "傾斜ゼロの土俵は半径の等分(平らな床の目盛り)")


## 高さは傾斜の加速度を中心から積んだもの。すり鉢は変位比例なので半径の2乗、
## 円錐は一定なので半径に比例する。式は書き写さず物理に測らせている。
func _test_height_definition(check: Callable) -> void:
	var dish := _dish(4.9)
	check.call(
		absf(SlopeContour.height(dish, 5.0) - 4.9 * 25.0 * 0.5) < 1e-3,
		"すり鉢の高さ = 強さ × 半径² ÷ 2 (%.4f)" % SlopeContour.height(dish, 5.0)
	)
	check.call(
		absf(SlopeContour.height(dish, 2.5) - 4.9 * 6.25 * 0.5) < 1e-3,
		"すり鉢の高さは半径の2乗に比例(半分の半径で1/4)"
	)

	var cone := _cone(3.0)
	check.call(
		absf(SlopeContour.height(cone, 5.0) - 3.0 * 5.0) < 1e-3,
		"円錐の高さ = 強さ × 半径 (%.4f)" % SlopeContour.height(cone, 5.0)
	)
	check.call(
		absf(SlopeContour.height(cone, 2.5) - 3.0 * 2.5) < 1e-3,
		"円錐の高さは半径に比例(半分の半径で1/2)"
	)

	# 中心はどちらの形でも高さ0で、外へ行くほど単調に高くなる。
	var rising := true
	var prev := -1.0
	for i in range(0, 11):
		var h := SlopeContour.height(dish, 0.5 * float(i))
		if h < prev - EPS:
			rising = false
		prev = h
	check.call(rising, "高さは中心から外へ単調に増える")


## 輪は内から外へ並び、最外周はちょうど壁の上。土俵をはみ出さない。
func _test_ordering(check: Callable) -> void:
	for field: FieldData in [_dish(4.9), _dish(8.0), _cone(3.0), _octagon()]:
		var rings := SlopeContour.radii(field)
		var rim := field.inradius()
		check.call(rings.size() == SlopeContour.ring_count(field), "輪の本数が ring_count と一致")

		var sorted := true
		var inside := true
		var prev := 0.0
		for r in rings:
			if r <= prev + EPS:
				sorted = false
			if r <= 0.0 or r > rim + EPS:
				inside = false
			prev = r
		check.call(sorted, "%s: 輪は内から外へ単調" % field.stage_shape)
		check.call(inside, "%s: 輪は中心より外・壁より内(半径%.2f)" % [field.stage_shape, rim])
		check.call(
			absf(rings[rings.size() - 1] - rim) < EPS,
			"%s: 最外周はちょうど内接半径に載る" % field.stage_shape
		)


## 傾斜の「形」が線の詰まり方に出る。等しい高さで割るので、
## すり鉢(外ほど急)は縁に寄って混み、円錐(どこも同じ)は等間隔になる。
func _test_shape_spacing(check: Callable) -> void:
	var cone := _cone(3.0)
	var cone_rings := SlopeContour.radii(cone)
	var rim := cone.inradius()
	var cone_even := true
	for k in cone_rings.size():
		var want := rim * float(k + 1) / float(cone_rings.size())
		if absf(cone_rings[k] - want) > rim * R_TOL:
			cone_even = false
	check.call(cone_even, "円錐の等高線は等間隔(どこでも同じ傾斜)")

	var dish := _dish(4.9)
	var dish_rings := SlopeContour.radii(dish)
	var n := dish_rings.size()
	var dish_sqrt := true
	for k in n:
		# 高さ ∝ r² を等分するので r_k = R√(k/n)。等分の r_k = R·k/n より必ず外側。
		var want := dish.inradius() * sqrt(float(k + 1) / float(n))
		if absf(dish_rings[k] - want) > dish.inradius() * R_TOL:
			dish_sqrt = false
	check.call(dish_sqrt, "すり鉢の等高線は √ に沿って外へ寄る")

	# 詰まり方そのもの: すり鉢は外側の間隔の方が内側より狭い。円錐は等しい。
	var dish_gaps := _gaps(dish_rings)
	check.call(
		dish_gaps[dish_gaps.size() - 1] < dish_gaps[0] - EPS,
		"すり鉢は縁ほど輪が詰まる(内%.3f → 外%.3f)" % [dish_gaps[0], dish_gaps[dish_gaps.size() - 1]]
	)
	var cone_gaps := _gaps(cone_rings)
	check.call(
		absf(cone_gaps[cone_gaps.size() - 1] - cone_gaps[0]) < rim * R_TOL,
		"円錐は内も外も同じ間隔"
	)


## 本数はマップのノードのケバと同数。「ケバ7本の部屋に入ったら床の輪も7本」で
## 対が取れることが、この変更の目的そのもの。
func _test_count_matches_map(check: Callable) -> void:
	var matched := true
	var counts := {}
	for field in FieldRoster.all():
		var rings := SlopeContour.radii(field)
		if rings.size() != StageSlopeMark.tick_count(field):
			matched = false
		counts[field.title_key] = rings.size()
	check.call(matched, "全土俵で 輪の本数 = マップのケバの本数 %s" % [counts])

	# 急な土俵ほど輪が多い(ケバと同じ単調性。目盛りを借りている以上ここは崩れない)。
	var rising := false
	var prev := -1
	var ok := true
	for strength in [1.0, 3.0, 5.0, 7.0, 8.0]:
		var count := SlopeContour.ring_count(_dish(strength))
		if prev >= 0:
			if count < prev:
				ok = false
			elif count > prev:
				rising = true
		prev = count
	check.call(ok and rising, "傾斜が強いほど輪が多い")


## **今回の眼目**。外周形状と柱が同じ土俵は、床の絵(輪の本数か半径の並び)で必ず割れる。
## ここが割れないと、入場しても土俵の違いが分からないまま——コールドプレイで
## FIELD_PLATE / FIELD_BOWL / FIELD_CLASSIC を最後まで見分けられなかった状態に戻る。
func _test_roster_distinguishable(check: Callable) -> void:
	var fields := FieldRoster.all()
	var same_looking := 0
	var collisions: Array[String] = []
	for i in fields.size():
		for j in range(i + 1, fields.size()):
			var a: FieldData = fields[i]
			var b: FieldData = fields[j]
			if not _same_outline(a, b):
				continue
			same_looking += 1
			if _same_contour(a, b):
				collisions.append("%s/%s" % [a.title_key, b.title_key])
	check.call(
		same_looking > 0,
		"外周と柱だけでは見分けの付かない土俵が実在する(%d組)" % same_looking
	)
	check.call(
		collisions.is_empty(),
		"外周が同じ土俵は等高線で割れる(割れなかった組: %s)" % [collisions]
	)


## 従来の描き方(どの土俵も半径を4等分した同心円)に戻ると落ちる。
## この検査が本体で、傾斜を無視した実装は必ずここで止まる。
func _test_not_uniform_rings(check: Callable) -> void:
	var uniform: Array[String] = []
	for field in FieldRoster.all():
		var rings := SlopeContour.radii(field)
		if rings.size() != 4:
			continue
		var rim := field.inradius()
		var is_quarter := true
		for k in rings.size():
			if absf(rings[k] - rim * float(k + 1) / 4.0) > rim * R_TOL:
				is_quarter = false
		if is_quarter:
			uniform.append(field.title_key)
	# 4等分になってよいのは「4本かつ円錐」の土俵だけ(円錐は本当に等間隔)。
	var allowed := true
	for key in uniform:
		for field in FieldRoster.all():
			if field.title_key == key and field.stage_shape != SpinnerPhysics.StageShape.CONE:
				allowed = false
	check.call(allowed, "すり鉢の土俵が4等分の同心円になっていない(旧実装 %s)" % [uniform])
	check.call(
		uniform.size() < FieldRoster.all().size(),
		"全土俵が同じ4等分の同心円ではない"
	)


## 2つの土俵が「外周形状・柱・大きさ」まで同じ＝床の輪郭だけでは見分けが付かないか。
func _same_outline(a: FieldData, b: FieldData) -> bool:
	if a.wall_shape != b.wall_shape or a.arena_bounds != b.arena_bounds:
		return false
	if a.obstacles.size() != b.obstacles.size():
		return false
	for i in a.obstacles.size():
		if not a.obstacles[i].is_equal_approx(b.obstacles[i]):
			return false
	return true


## 2つの土俵の等高線が(本数も半径の並びも)同じか。
func _same_contour(a: FieldData, b: FieldData) -> bool:
	var ra := SlopeContour.radii(a)
	var rb := SlopeContour.radii(b)
	if ra.size() != rb.size():
		return false
	for i in ra.size():
		if absf(ra[i] - rb[i]) > EPS:
			return false
	return true


## 隣り合う輪の間隔(内側の1本目は中心からの距離)。
func _gaps(rings: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var prev := 0.0
	for r in rings:
		out.append(r - prev)
		prev = r
	return out


func _dish(strength: float) -> FieldData:
	return FieldData.make(
		"T_DISH", Rect2(0, 0, 10, 10), ArenaWall.WallShape.RECT,
		SpinnerPhysics.StageShape.DISH, strength)


func _cone(strength: float) -> FieldData:
	return FieldData.make(
		"T_CONE", Rect2(0, 0, 10, 10), ArenaWall.WallShape.RECT,
		SpinnerPhysics.StageShape.CONE, strength)


func _octagon() -> FieldData:
	return FieldData.make(
		"T_OCT", Rect2(0, 0, 10, 10), ArenaWall.WallShape.OCTAGON,
		SpinnerPhysics.StageShape.DISH, 4.9)
