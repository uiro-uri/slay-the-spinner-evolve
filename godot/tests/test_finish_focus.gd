extends RefCounted

## finish_focus.gd(決着演出の計算)のテスト。純粋関数だけを検証する。
##
## 大事なのは (1)「決着衝突」の判定が消耗戦・時間切れを弾くこと、(2) 強さが
## 決着へ向けて滑らかに立ち上がること、(3) 変換が strength=0 で恒等・strength=1 で
## 衝突点を画面中心へ寄せること。ここが崩れると演出が的外れになる。

const EPS := 1e-4

const VIEWPORT := Vector2(1280.0, 720.0)
const BASE_POS := Vector2(390.0, 110.0)
const BASE_SCALE := Vector2(50.0, 50.0)


func run(check: Callable) -> void:
	_test_decisive_within_window(check)
	_test_decisive_rejects_far(check)
	_test_decisive_rejects_empty(check)
	_test_decisive_rejects_timeout(check)
	_test_strength_shape(check)
	_test_strength_monotonic(check)
	_test_strength_no_effect(check)
	_test_transform_identity(check)
	_test_transform_centered(check)
	_test_transform_between(check)


## 末尾のコマ衝突が finish_time に近ければ、その時刻を決着衝突として返す。
func _test_decisive_within_window(check: Callable) -> void:
	var r := _result([1.0, 2.4, 2.9], 3.0, false)
	var d := FinishFocus.decisive_impact_time(r, 0.5)
	check.call(is_equal_approx(d, 2.9), "決着判定: window内の末尾衝突を採用 (%.3f)" % d)


## 最後の衝突が finish_time からずっと前(消耗戦)なら演出しない。
func _test_decisive_rejects_far(check: Callable) -> void:
	var r := _result([1.0, 1.5], 3.0, false)
	var d := FinishFocus.decisive_impact_time(r, 0.5)
	check.call(d < 0.0, "決着判定: window外の消耗戦は -1 (%.3f)" % d)


## 一度も衝突していなければ演出しない。
func _test_decisive_rejects_empty(check: Callable) -> void:
	var r := _result([], 3.0, false)
	var d := FinishFocus.decisive_impact_time(r, 0.5)
	check.call(d < 0.0, "決着判定: 衝突なしは -1 (%.3f)" % d)


## 時間切れ(決着が付かず打ち切り)は、末尾衝突が近くても演出しない。
func _test_decisive_rejects_timeout(check: Callable) -> void:
	var r := _result([1.0, 2.9], 3.0, true)
	var d := FinishFocus.decisive_impact_time(r, 0.5)
	check.call(d < 0.0, "決着判定: 時間切れは -1 (%.3f)" % d)


## lead前は0、decisive_timeで1、以後1に張り付く。
func _test_strength_shape(check: Callable) -> void:
	var dt := 2.9
	var lead := 0.3
	check.call(
		FinishFocus.strength_at(dt - lead, dt, lead) <= EPS,
		"強さ: lead開始点は0"
	)
	check.call(
		FinishFocus.strength_at(dt - lead - 0.5, dt, lead) <= EPS,
		"強さ: lead前はずっと0"
	)
	check.call(
		absf(FinishFocus.strength_at(dt, dt, lead) - 1.0) <= EPS,
		"強さ: 決着時刻で1"
	)
	check.call(
		absf(FinishFocus.strength_at(dt + 1.0, dt, lead) - 1.0) <= EPS,
		"強さ: 決着後も1に張り付く"
	)


## lead区間内で単調増加すること。途中で下がると演出がガタつく。
func _test_strength_monotonic(check: Callable) -> void:
	var dt := 2.9
	var lead := 0.3
	var prev := -1.0
	var ok := true
	for i in 61:
		var t := (dt - lead) + lead * (i / 60.0)
		var s := FinishFocus.strength_at(t, dt, lead)
		if s < prev - EPS:
			ok = false
		prev = s
	check.call(ok, "強さ: lead区間で単調増加")


## 決着なし(-1)なら強さは常に0。演出しない戦いでカメラが動いてはいけない。
func _test_strength_no_effect(check: Callable) -> void:
	var worst := 0.0
	for i in 200:
		worst = maxf(worst, FinishFocus.strength_at(i * 0.05, -1.0, 0.3))
	check.call(worst <= EPS, "強さ: 決着なしは常に0 (最大 %.4f)" % worst)


## strength=0 は恒等。衝突点が base 変換と同じスクリーン座標へ写ること。
func _test_transform_identity(check: Callable) -> void:
	var focus := Vector2(5.0, 3.0)
	var x := FinishFocus.arena_transform(BASE_POS, BASE_SCALE, focus, VIEWPORT, 2.0, 0.0)
	check.call(x["position"].is_equal_approx(BASE_POS), "変換: strength=0で位置が素のまま")
	check.call(x["scale"].is_equal_approx(BASE_SCALE), "変換: strength=0で倍率が素のまま")
	# 恒等なら衝突点は base 変換どおりの位置に写る
	var screen: Vector2 = x["position"] + x["scale"] * focus
	var base_screen := BASE_POS + BASE_SCALE * focus
	check.call(screen.is_equal_approx(base_screen), "変換: strength=0で衝突点は素の位置")


## strength=1 で衝突点が画面中心へ、倍率が base*zoom になること。
func _test_transform_centered(check: Callable) -> void:
	var focus := Vector2(5.0, 3.0)
	var zoom := 2.0
	var x := FinishFocus.arena_transform(BASE_POS, BASE_SCALE, focus, VIEWPORT, zoom, 1.0)
	check.call((x["scale"] as Vector2).is_equal_approx(BASE_SCALE * zoom), "変換: strength=1で base*zoom 倍")
	var screen: Vector2 = x["position"] + x["scale"] * focus
	check.call(
		screen.is_equal_approx(VIEWPORT * 0.5),
		"変換: strength=1で衝突点が画面中心 (%s)" % screen
	)


## 中間では衝突点のスクリーン座標が base位置→中心 の間に収まること。
func _test_transform_between(check: Callable) -> void:
	var focus := Vector2(5.0, 3.0)
	var base_screen := BASE_POS + BASE_SCALE * focus
	var center := VIEWPORT * 0.5
	var ok := true
	for i in 11:
		var s := i / 10.0
		var x := FinishFocus.arena_transform(BASE_POS, BASE_SCALE, focus, VIEWPORT, 2.0, s)
		var screen: Vector2 = x["position"] + x["scale"] * focus
		# base_screen と center を結ぶ線分上に乗っているはず(線形補間なので)
		var expected := base_screen.lerp(center, s)
		if screen.distance_to(expected) > 1e-3:
			ok = false
	check.call(ok, "変換: 中間で衝突点が base→中心 を線形に辿る")


## 指定した衝突時刻の列と finish_time / timed_out を持つ BattleResult を作る。
func _result(impact_times: Array, finish_time: float, timed_out: bool) -> BattleResult:
	var r := BattleResult.new()
	var impacts: Array[BattleResult.Impact] = []
	for t in impact_times:
		impacts.append(BattleResult.Impact.new(t, Vector2(5.0, 3.0)))
	r.impacts = impacts
	r.finish_time = finish_time
	r.timed_out = timed_out
	return r
