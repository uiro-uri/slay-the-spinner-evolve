extends RefCounted

## map_glow.gd のテスト。マップの明滅と入場フェードの純粋関数を数値で確かめる。
##
## 見た目の演出は静止画では検証できない(CLAUDE.mdの方針)。値域・単調性・滑らかさ
## といった、チューニングで数値が変わっても崩れない性質を固定する。

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_pulse_bounded(check)
	_test_pulse_starts_dim(check)
	_test_pulse_actually_pulses(check)
	_test_pulse_smooth(check)
	_test_entrance_endpoints(check)
	_test_entrance_monotonic(check)
	_test_entrance_zero_duration(check)


## 明滅の素が必ず0〜1に収まること。ここが崩れるとアルファ計算が破綻する。
func _test_pulse_bounded(check: Callable) -> void:
	var lo := 1.0
	var hi := 0.0
	for i in 5000:
		var t := i * 0.01
		var g := MapGlow.pulse(t)
		lo = minf(lo, g)
		hi = maxf(hi, g)
	check.call(lo >= -EPS and hi <= 1.0 + EPS, "明滅: 値域が0〜1に収まる (%.4f〜%.4f)" % [lo, hi])


## t=0では最も淡い側(0)から始まること。出た瞬間に明るさが跳ねないため。
func _test_pulse_starts_dim(check: Callable) -> void:
	check.call(absf(MapGlow.pulse(0.0)) < EPS, "明滅: t=0は休止側 (%.4f)" % MapGlow.pulse(0.0))


## ちゃんと最も暗い側と明るい側の両方に届くこと。振れ幅が無ければ演出にならない。
func _test_pulse_actually_pulses(check: Callable) -> void:
	var lo := 1.0
	var hi := 0.0
	for i in 5000:
		var t := i * 0.01
		var g := MapGlow.pulse(t)
		lo = minf(lo, g)
		hi = maxf(hi, g)
	check.call(lo < 0.05, "明滅: 最も淡い側までしっかり暗くなる (%.4f)" % lo)
	check.call(hi > 0.95, "明滅: 最も明るい側までしっかり明るくなる (%.4f)" % hi)


## 滑らかであること。フレームごとに大きく飛ぶとチカチカして安っぽい。
func _test_pulse_smooth(check: Callable) -> void:
	var worst := 0.0
	var dt := 1.0 / 60.0
	for i in 3000:
		var t := i * dt
		worst = maxf(worst, absf(MapGlow.pulse(t + dt) - MapGlow.pulse(t)))
	# 1フレームで値域の1割も飛んだら、それは明滅ではなくノイズ
	check.call(worst < 0.1, "明滅: 1フレームの変化が滑らか (最大 %.4f)" % worst)


## フェードが両端で0と1になること。出た瞬間は透明、完了で不透明。
func _test_entrance_endpoints(check: Callable) -> void:
	var d := 0.35
	check.call(absf(MapGlow.entrance(0.0, d)) < EPS, "フェード: 開始は0 (%.4f)" % MapGlow.entrance(0.0, d))
	check.call(absf(MapGlow.entrance(d, d) - 1.0) < EPS, "フェード: 完了で1 (%.4f)" % MapGlow.entrance(d, d))
	check.call(
		absf(MapGlow.entrance(d * 5.0, d) - 1.0) < EPS,
		"フェード: 完了後も1に張り付く (%.4f)" % MapGlow.entrance(d * 5.0, d)
	)


## フェードが単調非減少で、値域[0,1]に収まること。途中で暗転や超過をしない。
func _test_entrance_monotonic(check: Callable) -> void:
	var d := 0.35
	var prev := -1.0
	var mono := true
	var in_range := true
	for i in 400:
		var e := MapGlow.entrance(i * (d / 200.0), d)
		if e < prev - EPS:
			mono = false
		if e < -EPS or e > 1.0 + EPS:
			in_range = false
		prev = e
	check.call(mono, "フェード: 単調に増える(逆戻りしない)")
	check.call(in_range, "フェード: 値域が0〜1に収まる")


## duration<=0でも0除算で壊れず、即1.0扱いになること。
func _test_entrance_zero_duration(check: Callable) -> void:
	check.call(MapGlow.entrance(0.0, 0.0) == 1.0, "フェード: 長さ0なら即完了(0除算しない)")
	check.call(MapGlow.entrance(1.0, -1.0) == 1.0, "フェード: 長さが負でも壊れない")
