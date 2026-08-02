extends RefCounted

## obstacle_marks.gd のテスト。マップのノードの中に打つ「柱の印」の幾何を確かめる。
##
## 見た目そのものは静止画では確かめられない(CLAUDE.mdの方針)ので、ここで固定するのは
## 「調整で数値を動かしても生き残る性質」だけ:
##   - 印の数は土俵の柱の数そのもの(柱なしの土俵とスタートでは0個)
##   - 位置は土俵の実座標を縮めたもの。中心から見た向きが土俵と一致する
##   - 大きさも実比率。柱の半径が2倍なら印も2倍
##   - ノードの半径に比例する(ホバーで膨らんでも縦画面で拡大されても一緒に動く)
##   - 印はノード本体の内側に収まり、既存の表示(レベルの数字・ピップ・脅威メーター)
##     と場所を取り合わない
##   - 実際の土俵一覧(FieldRoster)で、柱があるのは印が出る土俵だけ

const EPS := 1e-4

## マップの実レイアウト定数(ノード半径・ピップの位置・脅威メーターの位置)を借りて、
## 印が既存の表示と重なっていないことを決め打ちの数値ではなく実定数で確かめる。
const MapScreenScript := preload("res://scenes/map/MapScreen.gd")


func run(check: Callable) -> void:
	_test_empty_cases(check)
	_test_positions_follow_arena(check)
	_test_radius_follows_arena(check)
	_test_scales_with_node(check)
	_test_inside_node(check)
	_test_clear_of_existing_marks(check)
	_test_uniform_scale(check)
	_test_roster_agrees(check)


## 印が0個になるべき場合。柱の無い土俵・土俵未設定(スタート)・半径0。
func _test_empty_cases(check: Callable) -> void:
	var center := Vector2(100.0, 200.0)

	check.call(
		ObstacleMarks.marks(center, 18.0, null).is_empty(),
		"土俵が無いノード(スタート)には印を出さない"
	)
	check.call(
		ObstacleMarks.marks(center, 18.0, _field([])).is_empty(),
		"柱の無い土俵には印を出さない"
	)
	check.call(
		ObstacleMarks.marks(center, 0.0, _field([Vector3(3, 3, 0.6)])).is_empty(),
		"半径0のノードには印を出さない"
	)


## 位置は土俵の実座標。中心から見た向き(左上/右下)が土俵と一致し、
## 中心にある柱はノードの中心に来る。
func _test_positions_follow_arena(check: Callable) -> void:
	var center := Vector2(100.0, 200.0)
	var radius := 18.0
	var field := _field([Vector3(3, 3, 0.6), Vector3(7, 7, 0.6), Vector3(5, 5, 0.6)])
	var marks := ObstacleMarks.marks(center, radius, field)

	check.call(marks.size() == 3, "柱3本の土俵には印が3つ: %d" % marks.size())

	var upper_left := Vector2(marks[0].x, marks[0].y) - center
	var lower_right := Vector2(marks[1].x, marks[1].y) - center
	var middle := Vector2(marks[2].x, marks[2].y) - center

	check.call(
		upper_left.x < 0.0 and upper_left.y < 0.0,
		"土俵の左上(3,3)の柱はノードの左上に出る: (%.2f, %.2f)" % [upper_left.x, upper_left.y]
	)
	check.call(
		lower_right.x > 0.0 and lower_right.y > 0.0,
		"土俵の右下(7,7)の柱はノードの右下に出る: (%.2f, %.2f)" % [lower_right.x, lower_right.y]
	)
	check.call(middle.length() < EPS, "土俵の中心の柱はノードの中心に出る: %.4f" % middle.length())

	# 縮尺は土俵の半辺(5.0)をノード半径に合わせた比。(3,3)は中心から (-2,-2)。
	var expected := -2.0 * radius / 5.0
	check.call(
		absf(upper_left.x - expected) < EPS and absf(upper_left.y - expected) < EPS,
		"位置は土俵の変位をそのまま縮めた値 (期待 %.3f): (%.3f, %.3f)" % [
			expected, upper_left.x, upper_left.y
		]
	)


## 大きさも実比率。柱の半径が2倍なら印も2倍で、土俵に対する割合が保たれる。
func _test_radius_follows_arena(check: Callable) -> void:
	var center := Vector2.ZERO
	var radius := 18.0
	var small := ObstacleMarks.marks(center, radius, _field([Vector3(3, 3, 0.6)]))
	var big := ObstacleMarks.marks(center, radius, _field([Vector3(3, 3, 1.2)]))

	check.call(
		absf(small[0].z - 0.6 * radius / 5.0) < EPS,
		"印の半径は柱の半径を同じ縮尺で縮めた値: %.4f" % small[0].z
	)
	check.call(
		absf(big[0].z - small[0].z * 2.0) < EPS,
		"柱が2倍太ければ印も2倍: %.4f vs %.4f" % [big[0].z, small[0].z]
	)


## ノードの半径に比例する。ホバーで膨らんだ半径や縦画面の拡大率をそのまま渡せば、
## 印も位置ごと一緒に動く(ピップと同じ振る舞い)。
func _test_scales_with_node(check: Callable) -> void:
	var center := Vector2(50.0, 60.0)
	var field := _field([Vector3(3, 3, 0.6)])
	var base := ObstacleMarks.marks(center, 18.0, field)
	var doubled := ObstacleMarks.marks(center, 36.0, field)

	var base_offset := Vector2(base[0].x, base[0].y) - center
	var doubled_offset := Vector2(doubled[0].x, doubled[0].y) - center
	check.call(
		(doubled_offset - base_offset * 2.0).length() < EPS,
		"ノードが2倍なら印の位置も中心から2倍離れる: %.4f" % doubled_offset.length()
	)
	check.call(
		absf(doubled[0].z - base[0].z * 2.0) < EPS,
		"ノードが2倍なら印も2倍の大きさ: %.4f vs %.4f" % [doubled[0].z, base[0].z]
	)

	# ノードを動かせば印も同じだけ動く(平行移動)。
	var moved := ObstacleMarks.marks(center + Vector2(7.0, -3.0), 18.0, field)
	check.call(
		absf(moved[0].x - base[0].x - 7.0) < EPS and absf(moved[0].y - base[0].y + 3.0) < EPS,
		"ノードを動かすと印も同じだけ動く"
	)


## 印はノード本体の内側に収まる。土俵の中の柱がノードからはみ出したら、
## 「土俵の中身」という読み方が壊れる。
##
## 矩形の土俵は一辺2×半径の正方形として描かれるので、内側かどうかは軸ごとに見る
## (壁に接する柱はノードの辺にちょうど接するのが正しい)。実際の土俵の柱は
## 中央寄りなので、円いノード・八角のノードに置いても収まることを別に確かめる。
func _test_inside_node(check: Callable) -> void:
	var center := Vector2(120.0, 90.0)
	var radius := 18.0
	# 土俵の隅ぎりぎり(壁に接する柱)まで含めて確かめる。
	var field := _field([
		Vector3(3, 3, 0.6), Vector3(7, 7, 0.6), Vector3(0.6, 0.6, 0.6), Vector3(9.4, 9.4, 0.6),
	])
	for mark in ObstacleMarks.marks(center, radius, field):
		var offset := Vector2(mark.x, mark.y) - center
		check.call(
			absf(offset.x) + mark.z <= radius + EPS and absf(offset.y) + mark.z <= radius + EPS,
			"印は矩形ノードの内側に収まる: (%.2f, %.2f) 半径 %.2f" % [offset.x, offset.y, mark.z]
		)

	for roster_field in FieldRoster.all():
		for mark in ObstacleMarks.marks(center, radius, roster_field):
			var reach := (Vector2(mark.x, mark.y) - center).length() + mark.z
			check.call(
				reach <= radius + EPS,
				"%s: 実際の柱は円いノードにも収まる: 中心から %.2f (半径 %.2f)" % [
					roster_field.title_key, reach, radius
				]
			)


## 既存の表示と場所を取り合わない。レベルの数字はこの印の**後**に描かれるので
## 重なっても数字が勝つが、ノードの外に並ぶピップと脅威メーターは印より外側に
## あって、印がそこへ食い込まないことを実定数で確かめる。
func _test_clear_of_existing_marks(check: Callable) -> void:
	var radius: float = MapScreenScript.NODE_RADIUS
	var center := Vector2.ZERO
	var field := _field([Vector3(3, 3, 0.6), Vector3(7, 7, 0.6)])

	# 敵数ピップの上端(ノード下辺のさらに外)と、報酬ピップの下端(上辺の外)。
	var pip_top: float = radius + MapScreenScript.PIP_OFFSET - MapScreenScript.PIP_RADIUS
	var reward_bottom: float = -radius - MapScreenScript.PIP_OFFSET + MapScreenScript.PIP_RADIUS
	# 脅威メーターの上端。
	var meter_top: float = ThreatMeter.track_rect(center, radius, 1.0).position.y

	for mark in ObstacleMarks.marks(center, radius, field):
		check.call(
			mark.y + mark.z < pip_top and mark.y + mark.z < meter_top,
			"印は下のピップ・脅威メーターに届かない: 下端 %.2f (ピップ %.2f / メーター %.2f)" % [
				mark.y + mark.z, pip_top, meter_top
			]
		)
		check.call(
			mark.y - mark.z > reward_bottom,
			"印は上の報酬ピップに届かない: 上端 %.2f (報酬ピップ %.2f)" % [
				mark.y - mark.z, reward_bottom
			]
		)


## 縮尺は縦横で同じ。x/yを別々にノードへ合わせると、正方形でない土俵で柱が楕円に
## 潰れて「円い柱」という見た目が嘘になる。今の土俵はすべて正方形なので違いが出ない
## ——差が出る土俵を用意して踏ませる(踏まない検査は検査していないのと同じ)。
func _test_uniform_scale(check: Callable) -> void:
	var center := Vector2.ZERO
	var radius := 20.0
	# 横長(20×10)の土俵。中心(10, 5)から x に +4、y に +4 ずらした柱を置く。
	var field := FieldData.make(
		"FIELD_WIDE", Rect2(0, 0, 20, 10), ArenaWall.WallShape.RECT,
		SpinnerPhysics.StageShape.DISH, 4.9, [Vector3(14, 9, 0.6)]
	)
	var marks := ObstacleMarks.marks(center, radius, field)
	check.call(marks.size() == 1, "横長の土俵でも印は柱の数どおり: %d" % marks.size())
	check.call(
		absf(marks[0].x - marks[0].y) < EPS,
		"縦横で同じ縮尺: 同じ変位が同じpxになる (%.3f, %.3f)" % [marks[0].x, marks[0].y]
	)


## 実際の土俵一覧との突き合わせ。柱を持つ土俵だけが印を出し、その数は一致する。
## 「印は出るが数が違う」「柱があるのに出ない」をここで捕まえる。
func _test_roster_agrees(check: Callable) -> void:
	var with_obstacles := 0
	for field in FieldRoster.all():
		var marks := ObstacleMarks.marks(Vector2.ZERO, 18.0, field)
		check.call(
			marks.size() == field.obstacles.size(),
			"%s: 印の数が柱の数と一致 (%d)" % [field.title_key, marks.size()]
		)
		if not field.obstacles.is_empty():
			with_obstacles += 1
	check.call(with_obstacles > 0, "柱を持つ土俵が一覧に少なくとも1つある: %d" % with_obstacles)


## 柱だけを差し替えたテスト用の土俵。他の値は既定(10×10の矩形すり鉢)。
func _field(obstacles: Array[Vector3]) -> FieldData:
	return FieldData.make(
		"FIELD_TEST", Rect2(0, 0, 10, 10), ArenaWall.WallShape.RECT,
		SpinnerPhysics.StageShape.DISH, 4.9, obstacles
	)
