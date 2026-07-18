extends RefCounted

## DiscGradient(コマ本体の直線グラデーション)のテスト。
##
## 見た目のバグはスクショ1枚では分からない。ここでは値非依存の性質だけを押さえる:
## 方向(明側/暗側)・単調性・両端が異なること・近端が基準色・alpha保存・NaNなし。
## 明度のずらし量そのものは手触りで動くので断定しない(test_spin_aura.gd と同じ流儀)。

const EPS := 1e-4

## 走査に使う t のサンプル。境界(0,1)と外側(クランプ確認)を含む。
const TS := [-0.5, 0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0, 1.5]

## 走査に使う基準色。プレイヤー/敵の実色に加え、中間グレーも混ぜる。
const BASES := [Palette.PLAYER, Palette.ENEMY, Color(0.5, 0.5, 0.5, 0.8)]


func run(check: Callable) -> void:
	_test_near_is_base(check)
	_test_direction(check)
	_test_monotonic(check)
	_test_endpoints_differ(check)
	_test_alpha_preserved(check)
	_test_no_nan(check)


## 色の相対輝度(単調性・明暗判定に使う簡易輝度)。
func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## t=0(近端)は基準色そのもの。片端は必ず基準色という約束を固定する。
func _test_near_is_base(check: Callable) -> void:
	var ok := true
	for base in BASES:
		for toward in [true, false]:
			var c: Color = DiscGradient.sample(base, toward, 0.0)
			if not c.is_equal_approx(base):
				ok = false
	check.call(ok, "グラデ: t=0 は基準色そのもの")


## toward_light=true は遠端が基準より明るく、false は暗い。方向が陣営で固定される。
func _test_direction(check: Callable) -> void:
	var light_ok := true
	var dark_ok := true
	for base in BASES:
		var far_light: Color = DiscGradient.sample(base, true, 1.0)
		var far_dark: Color = DiscGradient.sample(base, false, 1.0)
		if _luma(far_light) <= _luma(base) + EPS:
			light_ok = false
		if _luma(far_dark) >= _luma(base) - EPS:
			dark_ok = false
	check.call(light_ok, "グラデ: プレイヤー(明側)は遠端が基準より明るい")
	check.call(dark_ok, "グラデ: 敵(暗側)は遠端が基準より暗い")


## t が増えるほど輝度が単調(明側は増加・暗側は減少)。ムラなく一方向へ流れる。
func _test_monotonic(check: Callable) -> void:
	var ok := true
	for base in BASES:
		for toward in [true, false]:
			var prev := _luma(DiscGradient.sample(base, toward, 0.0))
			for i in range(1, 21):
				var t := i / 20.0
				var l := _luma(DiscGradient.sample(base, toward, t))
				if toward and l < prev - EPS:
					ok = false
				if not toward and l > prev + EPS:
					ok = false
				prev = l
	check.call(ok, "グラデ: 輝度は t について単調")


## 両端点が実際に異なる(勾配がフラットに潰れていない)。
func _test_endpoints_differ(check: Callable) -> void:
	var ok := true
	for base in BASES:
		for toward in [true, false]:
			var near: Color = DiscGradient.sample(base, toward, 0.0)
			var far: Color = DiscGradient.sample(base, toward, 1.0)
			if absf(_luma(near) - _luma(far)) < EPS:
				ok = false
	check.call(ok, "グラデ: 両端点は異なる(勾配がある)")


## alpha は base のものが全 t で保たれる(明度いじりが透明度に漏れない)。
func _test_alpha_preserved(check: Callable) -> void:
	var ok := true
	for base in BASES:
		for toward in [true, false]:
			for t in TS:
				var c: Color = DiscGradient.sample(base, toward, t)
				if absf(c.a - base.a) > EPS:
					ok = false
	check.call(ok, "グラデ: alpha は基準色のものを保つ")


## どの t でも NaN を出さない(クランプ域外を含む)。
func _test_no_nan(check: Callable) -> void:
	var ok := true
	for base in BASES:
		for toward in [true, false]:
			for t in TS:
				var c: Color = DiscGradient.sample(base, toward, t)
				if is_nan(c.r) or is_nan(c.g) or is_nan(c.b) or is_nan(c.a):
					ok = false
	check.call(ok, "グラデ: NaN を出さない")
