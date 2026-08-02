extends RefCounted

## boss_mark.gd のテスト。マップのゴールに打つ「決戦の星」の幾何と、
## 対戦画面が出す一言の切り替えを確かめる。
##
## 見た目そのものは静止画では確かめられない(CLAUDE.mdの方針)ので、ここで固定するのは
## 「調整で数値を動かしても生き残る性質」だけ:
##   - 星が出るのは段9のゴールだけ。道中のどの段・どの列にも出ない
##   - 先端と谷が交互に並ぶ「星」であること(全部同じ半径なら多角形であって星ではない)
##   - 先端は真上を向く(回転がずれると「傾いた星」になる)
##   - ノード本体(八角形)の内側に収まり、既存の表示(敵数ピップ・脅威メーター)と
##     場所を取り合わない
##   - ノード半径に比例する(ホバーで膨らんでも縦画面で拡大されても一緒に動く)
##   - 中心の平行移動にそのまま追随する
##   - 決戦の一言は道中と別のキーで、どちらも訳がある

const EPS := 1e-4

## マップの実レイアウト定数(ノード半径・ピップと脅威メーターの位置)を借りて、
## 星が既存の表示と重なっていないことを決め打ちの数値ではなく実定数で確かめる。
const MapScreenScript := preload("res://scenes/map/MapScreen.gd")


func run(check: Callable) -> void:
	_test_only_the_goal(check)
	_test_vertex_count_and_alternation(check)
	_test_first_spike_points_up(check)
	_test_inside_node(check)
	_test_scales_with_node(check)
	_test_follows_center(check)
	_test_empty_cases(check)
	_test_prompt_key(check)


## 星が出るのは段9のゴールだけ。道中の全段・全列で出ないこと。
func _test_only_the_goal(check: Callable) -> void:
	check.call(BossMark.is_boss(MapTree.GOAL_COORD), "決戦の星: ゴール(段9)には出る")

	var stray: Array[Vector2i] = []
	for step in MapTree.STEP_GOAL:
		for column in MapTree.COLUMN_COUNT:
			var coord := Vector2i(step, column)
			if BossMark.is_boss(coord):
				stray.append(coord)
	check.call(stray.is_empty(), "決戦の星: 段0〜8には出ない (出た: %s)" % [stray])

	# ゴールの段なら列がずれていても決戦(マップ生成が列2に固定しているが、
	# 「段9＝決戦」という規則の方を固定する)。
	check.call(
		BossMark.is_boss(Vector2i(MapTree.STEP_GOAL, 0)),
		"決戦の星: 判定は段で決まる(列に依らない)"
	)


## 先端と谷が交互に並ぶこと。頂点の数と、中心からの距離の2値性を見る。
func _test_vertex_count_and_alternation(check: Callable) -> void:
	var center := Vector2(120.0, 340.0)
	var radius := 18.0
	var pts := BossMark.points(center, radius)

	check.call(
		pts.size() == BossMark.SPIKES * 2,
		"決戦の星: 頂点は先端%d個＋谷%d個 (実際 %d)" % [BossMark.SPIKES, BossMark.SPIKES, pts.size()]
	)

	var outer := radius * BossMark.OUTER_SHARE
	var inner := radius * BossMark.INNER_SHARE
	check.call(outer > inner, "決戦の星: 先端は谷より外 (%.2f > %.2f)" % [outer, inner])

	var alternates := true
	for i in pts.size():
		var want := outer if i % 2 == 0 else inner
		if absf(center.distance_to(pts[i]) - want) > EPS:
			alternates = false
	check.call(alternates, "決戦の星: 先端と谷が交互(全部同じ半径なら星ではない)")


## 先端が真上を向くこと。ここがずれると「傾いた星」になる。
func _test_first_spike_points_up(check: Callable) -> void:
	var center := Vector2(0.0, 0.0)
	var pts := BossMark.points(center, 20.0)
	var first := pts[0]
	check.call(
		absf(first.x) < EPS and first.y < 0.0,
		"決戦の星: 最初の先端は真上 (%s)" % str(first)
	)


## 星がノード本体の内側に収まること。八角形ノードの内接半径 cos(PI/8)*r を
## 突き破らないので、輪郭から食み出さず、外側のピップ／脅威メーターにも触れない。
func _test_inside_node(check: Callable) -> void:
	var center := Vector2(500.0, 90.0)
	var radius: float = MapScreenScript.NODE_RADIUS
	var pts := BossMark.points(center, radius)

	var octagon_inradius := radius * cos(PI / 8.0)
	var farthest := 0.0
	for p in pts:
		farthest = maxf(farthest, center.distance_to(p))
	check.call(
		farthest <= octagon_inradius + EPS,
		"決戦の星: 八角形ノードの内側に収まる (%.2f <= %.2f)" % [farthest, octagon_inradius]
	)

	# 敵数ピップ(下辺の外側)と脅威メーター(さらに下)には届かない。
	var pip_y: float = center.y + radius + MapScreenScript.PIP_OFFSET
	var lowest := center.y
	for p in pts:
		lowest = maxf(lowest, p.y)
	check.call(
		lowest < pip_y - MapScreenScript.PIP_RADIUS,
		"決戦の星: 敵数ピップに掛からない (%.2f < %.2f)" % [lowest, pip_y]
	)


## ノード半径に比例すること。ホバーで膨らんでも縦画面で拡大されても星が一緒に動く。
func _test_scales_with_node(check: Callable) -> void:
	var center := Vector2(10.0, 20.0)
	var small := BossMark.points(center, 12.0)
	var big := BossMark.points(center, 24.0)

	check.call(small.size() == big.size(), "決戦の星: 半径を変えても頂点数は同じ")
	var proportional := true
	for i in small.size():
		var a := small[i] - center
		var b := big[i] - center
		if (a * 2.0 - b).length() > EPS:
			proportional = false
	check.call(proportional, "決戦の星: 半径2倍で頂点の変位も2倍")


## 中心の平行移動にそのまま追随すること(形は変わらない)。
func _test_follows_center(check: Callable) -> void:
	var radius := 15.0
	var here := BossMark.points(Vector2(0.0, 0.0), radius)
	var shift := Vector2(313.0, -47.0)
	var there := BossMark.points(shift, radius)

	var moved := true
	for i in here.size():
		if (here[i] + shift - there[i]).length() > EPS:
			moved = false
	check.call(moved, "決戦の星: 中心を動かすと形はそのままで平行移動する")


## 描けない場合は空を返す(呼び出し側が描かずに済む)。
func _test_empty_cases(check: Callable) -> void:
	var center := Vector2(1.0, 2.0)
	check.call(BossMark.points(center, 0.0).is_empty(), "決戦の星: 半径0では出さない")
	check.call(BossMark.points(center, -3.0).is_empty(), "決戦の星: 負の半径では出さない")


## 対戦画面の一言。決戦だけ別のキーで、どちらも訳がある。
func _test_prompt_key(check: Callable) -> void:
	var normal := BossMark.prompt_key(false)
	var final_bout := BossMark.prompt_key(true)
	check.call(normal != final_bout, "決戦の一言: 道中と決戦でキーが違う (%s / %s)" % [normal, final_bout])
	check.call(normal == "BATTLE_DRAG_TO_SHOOT", "決戦の一言: 道中は従来のキーのまま")

	var previous := TranslationServer.get_locale()
	for locale in ["ja", "en"]:
		TranslationServer.set_locale(locale)
		for key in [normal, final_bout]:
			check.call(
				tr(key) != key,
				"決戦の一言: %s に%sの訳がある" % [key, locale]
			)
	TranslationServer.set_locale(previous)
