extends RefCounted

## stage_slope_mark.gd のテスト。マップのノードの縁に打つ「傾斜のケバ」を確かめる。
##
## 見た目そのものは静止画では確かめられない(CLAUDE.mdの方針)ので、ここで固定するのは
## 「調整で数値を動かしても生き残る性質」だけ:
##   - 目盛りは壁での引き戻し加速度そのもの。すり鉢は内接半径が効き、円錐は効かない
##   - 急な土俵ほどケバが多く・長い(単調)。土俵未設定(スタート)には1本も出ない
##   - 線分はノードの縁から内側へ伸び、ノードの外へ出ない
##   - ノードの半径に比例する(ホバーで膨らんでも縦画面で拡大されても一緒に動く)
##   - レベルの数字と場所を取り合わない
##   - **実際の土俵一覧(FieldRoster)で、外周形状と柱が同じ土俵はケバの本数で必ず割れる**
##     ——これが今回の眼目。ここが割れないと、マップ上で見分けの付かない部屋が残る
##   - 目盛りの満杯(PULL_FULL)がロスターの最大以上。急な土俵を足したら落ちる

const EPS := 1e-4

## マップの実レイアウト定数(ノード半径・レベルの数字の大きさ)を借りて、ケバが
## 既存の表示と重なっていないことを決め打ちの数値ではなく実定数で確かめる。
const MapScreenScript := preload("res://scenes/map/MapScreen.gd")


func run(check: Callable) -> void:
	_test_empty_cases(check)
	_test_rim_pull_definition(check)
	_test_monotonic(check)
	_test_geometry(check)
	_test_scales_with_node(check)
	_test_clear_of_level_text(check)
	_test_roster_distinguishable(check)
	_test_scale_covers_roster(check)


## ケバが0本になるべき場合。土俵未設定(スタート)・半径0。
func _test_empty_cases(check: Callable) -> void:
	var center := Vector2(100.0, 200.0)

	check.call(
		StageSlopeMark.ticks(center, 18.0, null).is_empty(),
		"土俵が無いノード(スタート)にはケバを出さない"
	)
	check.call(
		StageSlopeMark.tick_count(null) == 0,
		"土俵が無いノードのケバの本数は0"
	)
	check.call(
		is_equal_approx(StageSlopeMark.rim_pull(null), 0.0),
		"土俵が無いノードの引き戻しは0"
	)

	var field := _dish(4.9)
	check.call(
		StageSlopeMark.ticks(center, 0.0, field).is_empty(),
		"半径0のノードにはケバを出さない"
	)


## 目盛りの実体は「壁のところで中心へ引き戻される加速度」。すり鉢(DISH)は変位に
## 比例するので内接半径が効き、円錐(CONE)はどこでも一定なので効かない。
## 場合分けを書き写さず SpinnerPhysics に測らせているので、物理側を変えれば追従する。
func _test_rim_pull_definition(check: Callable) -> void:
	var dish := _dish(4.9)
	check.call(
		absf(StageSlopeMark.rim_pull(dish) - 4.9 * dish.inradius()) < EPS,
		"すり鉢の引き戻し = 強さ × 内接半径 (%.2f)" % StageSlopeMark.rim_pull(dish)
	)

	var cone := FieldData.make(
		"T_CONE", Rect2(0, 0, 10, 10), ArenaWall.WallShape.RECT,
		SpinnerPhysics.StageShape.CONE, 3.0)
	check.call(
		absf(StageSlopeMark.rim_pull(cone) - 3.0) < EPS,
		"円錐の引き戻し = 強さそのもの (%.2f)" % StageSlopeMark.rim_pull(cone)
	)

	# 同じ強さでも土俵が広いほど、すり鉢は壁で強く引き戻す(円錐は変わらない)。
	var wide := FieldData.make(
		"T_WIDE", Rect2(0, 0, 20, 20), ArenaWall.WallShape.RECT,
		SpinnerPhysics.StageShape.DISH, 4.9)
	check.call(
		StageSlopeMark.rim_pull(wide) > StageSlopeMark.rim_pull(dish) + EPS,
		"すり鉢は広い土俵ほど壁での引き戻しが強い"
	)

	# 目盛りは頭打ちする。満杯を超える土俵でも1.0で止まり、負にはならない。
	check.call(
		is_equal_approx(StageSlopeMark.share(_dish(1000.0)), 1.0),
		"満杯を超える傾斜は 1.0 で頭打ち"
	)


## 急な土俵ほどケバが多く・長い。値を決め打たず、強さを振って単調性だけ見る。
func _test_monotonic(check: Callable) -> void:
	var center := Vector2.ZERO
	var radius := 18.0
	var prev_count := -1
	var prev_length := -1.0
	var rising_count := false
	var rising_length := false
	for strength in [1.0, 3.0, 5.0, 7.0, 8.0]:
		var field := _dish(strength)
		var count := StageSlopeMark.tick_count(field)
		var length := _tick_length(StageSlopeMark.ticks(center, radius, field))
		if prev_count >= 0:
			if count < prev_count or length < prev_length - EPS:
				check.call(false, "傾斜を強めたのにケバが減った(強さ=%.1f)" % strength)
				return
			if count > prev_count:
				rising_count = true
			if length > prev_length + EPS:
				rising_length = true
		prev_count = count
		prev_length = length
	check.call(rising_count, "傾斜が強いほどケバの本数が増える")
	check.call(rising_length, "傾斜が強いほどケバが長い")

	# 一番緩い土俵でも「ケバが1本も無い」＝土俵未設定と同じ絵にはしない。
	check.call(
		StageSlopeMark.tick_count(_dish(0.001)) >= 2,
		"どんなに緩い土俵でもケバは残る(スタートと見分けが付く)"
	)


## 線分はノードの縁から内側へ。外端はちょうど縁に載り、内端は中心側にある。
func _test_geometry(check: Callable) -> void:
	var center := Vector2(140.0, 90.0)
	var radius := 18.0
	var field := _dish(4.9)
	var points := StageSlopeMark.ticks(center, radius, field)

	check.call(
		points.size() == StageSlopeMark.tick_count(field) * 2,
		"線分は1本につき2点 (%d点 / %d本)" % [points.size(), StageSlopeMark.tick_count(field)]
	)

	var outer_on_rim := true
	var inner_inside := true
	var pointing_inward := true
	var i := 0
	while i + 1 < points.size():
		var outer: Vector2 = points[i]
		var inner: Vector2 = points[i + 1]
		var ro := (outer - center).length()
		var ri := (inner - center).length()
		if absf(ro - radius) > EPS:
			outer_on_rim = false
		if ri >= ro - EPS or ri < 0.0:
			inner_inside = false
		# 内端は外端と同じ向き(中心から見て)。ケバが横倒しになっていないこと。
		if (outer - center).normalized().distance_to((inner - center).normalized()) > EPS:
			pointing_inward = false
		i += 2
	check.call(outer_on_rim, "ケバの外端はノードの縁にちょうど載る")
	check.call(inner_inside, "ケバの内端は縁より内側(ノードの外へ出ない)")
	check.call(pointing_inward, "ケバは中心を向く(縁の法線方向)")

	# 向きが重ならない＝縁をぐるりと均等に回る。
	var angles := {}
	i = 0
	while i < points.size():
		angles[snappedf((points[i] - center).angle(), 1e-3)] = true
		i += 2
	check.call(
		angles.size() == StageSlopeMark.tick_count(field),
		"ケバは互いに別の向きに並ぶ (%d通り)" % angles.size()
	)


## ノードの半径に比例する。ホバーで膨らんでも縦画面で拡大されても一緒に動く。
func _test_scales_with_node(check: Callable) -> void:
	var center := Vector2(50.0, 60.0)
	var field := _dish(6.0)
	var small := StageSlopeMark.ticks(center, 18.0, field)
	var big := StageSlopeMark.ticks(center, 36.0, field)

	check.call(small.size() == big.size(), "ノードが大きくなってもケバの本数は同じ")
	check.call(
		absf(_tick_length(big) - _tick_length(small) * 2.0) < EPS,
		"ノードが2倍ならケバも2倍 (%.2f → %.2f)" % [_tick_length(small), _tick_length(big)]
	)

	var moved := StageSlopeMark.ticks(center + Vector2(200.0, -70.0), 18.0, field)
	check.call(
		absf(_tick_length(moved) - _tick_length(small)) < EPS,
		"ノードの位置を動かしてもケバの長さは変わらない"
	)


## ケバがノードの中央を明け渡す。中央はレベルの数字の場所。
##
## 「一切重ならない」は要求しない——柱の印も星も数字の下に潜る設計で、数字は最後に
## 上から描かれるし、ケバは縁と同じ墨なので数字の字形を汚さない(星が縁取りを要る
## のは星だけが明るい橙だから)。求めるのは**縁のバンドに収まる**ことだけ。
## 数字の横幅は get_string_size がちょうど字送りを返すので、そこは厳密に測れる
## (縦は行の高さ＝CJKぶんの余白込みでノード直径より大きく、字形の境界にならない)。
const CENTER_KEEP_OUT := 0.6

func _test_clear_of_level_text(check: Callable) -> void:
	var radius: float = MapScreenScript.NODE_RADIUS
	var font := ThemeDB.fallback_font
	var fs := int(MapScreenScript.LEVEL_FONT)
	# レベルは1桁(EnemyRoster の最大が5)。一番幅の出る字形で見る。
	var widest := 0.0
	for digit in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
		widest = maxf(widest, font.get_string_size(digit, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var half_width := widest * 0.5

	var worst := radius
	for field in FieldRoster.all():
		var points := StageSlopeMark.ticks(Vector2.ZERO, radius, field)
		var i := 1
		while i < points.size():
			worst = minf(worst, points[i].length())
			i += 2
	check.call(
		worst > half_width,
		"ケバの内端(半径%.1f)が数字の字送り(半径%.1f)に食い込まない" % [worst, half_width]
	)
	check.call(
		worst >= radius * CENTER_KEEP_OUT,
		"ケバは縁のバンドに収まる(内端 半径%.1f >= %.1f)" % [worst, radius * CENTER_KEEP_OUT]
	)


## **今回の眼目**。実際の土俵一覧で、マップ上の見た目が同じになる土俵が無いこと。
## ノードが描くのは (外周形状, 柱の配置, ケバの本数)。ケバを足す前は
## CLASSIC/BOWL/PLATE の3つが「矩形・柱なし」で完全に同じ絵だった。
func _test_roster_distinguishable(check: Callable) -> void:
	var seen := {}
	var collisions: Array[String] = []
	for field in FieldRoster.all():
		var key := _visual_key(field)
		if seen.has(key):
			collisions.append("%s と %s" % [seen[key], field.title_key])
		seen[key] = field.title_key
	check.call(
		collisions.is_empty(),
		"マップ上で同じ絵になる土俵は無い%s" % ("" if collisions.is_empty() else ": " + ", ".join(collisions))
	)

	# ケバを外すと実際に潰れることまで見る(この検査が何も見ていない状態にならない)。
	var without := {}
	var without_collisions := 0
	for field in FieldRoster.all():
		var key := "%d/%d" % [field.wall_shape, field.obstacles.size()]
		if without.has(key):
			without_collisions += 1
		without[key] = true
	check.call(
		without_collisions > 0,
		"ケバが無ければ見分けの付かない土俵が実在する (%d組)" % without_collisions
	)


## 目盛りの満杯がロスターの最大以上。これより急な土俵を足すと満杯で頭打ちになって
## 差が出なくなるので、そのときはここが落ちて PULL_FULL を上げろと言う。
func _test_scale_covers_roster(check: Callable) -> void:
	var strongest := 0.0
	var strongest_name := ""
	for field in FieldRoster.all():
		var pull := StageSlopeMark.rim_pull(field)
		if pull > strongest:
			strongest = pull
			strongest_name = field.title_key
	check.call(
		strongest <= StageSlopeMark.PULL_FULL + EPS,
		"目盛りの満杯 %.1f が最急の土俵 %s (%.1f) を覆う" % [
			StageSlopeMark.PULL_FULL, strongest_name, strongest
		]
	)
	# 満杯が遠すぎても差が潰れる。最急の土俵はちゃんと満杯付近まで届くこと。
	check.call(
		strongest >= StageSlopeMark.PULL_FULL * 0.75,
		"最急の土俵が目盛りの上端付近まで届く (取り分 %.2f)" % (strongest / StageSlopeMark.PULL_FULL)
	)


## マップのノードが1つ描く絵の同一性: 外周形状・柱の配置・ケバの本数。
func _visual_key(field: FieldData) -> String:
	var pillars: Array[String] = []
	for o in field.obstacles:
		pillars.append("%.2f,%.2f,%.2f" % [o.x, o.y, o.z])
	pillars.sort()
	return "%d|%s|%d" % [field.wall_shape, ",".join(pillars), StageSlopeMark.tick_count(field)]


## ケバ1本の長さ(すべて同じ長さなので先頭を見る)。
func _tick_length(points: PackedVector2Array) -> float:
	if points.size() < 2:
		return 0.0
	return points[0].distance_to(points[1])


func _dish(strength: float) -> FieldData:
	return FieldData.make(
		"T_DISH", Rect2(0, 0, 10, 10), ArenaWall.WallShape.RECT,
		SpinnerPhysics.StageShape.DISH, strength)
