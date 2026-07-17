extends RefCounted

## audio_levels.gd(回転音・チャージ音のパラメータ計算)のテスト。純粋関数だけを検証する。
##
## 数値そのものは手触りで変わるので、調整で崩れない性質だけを見る:
##  - 回転音: rps で単調に高く・大きくなる。lose_threshold 以下は無音。範囲内に収まる。
##  - チャージ音: 引き量で単調に高く・大きくなる。ratio=0 は無音。範囲内に収まる。
##  - reference rps が 0 以下でも落ちない(ゼロ除算・NaN を出さない)。

const EPS := 1e-5
const REF := 15.0
const LOSE := 0.03


func run(check: Callable) -> void:
	_test_rotation_freq_monotonic(check)
	_test_rotation_freq_bounds(check)
	_test_rotation_amp_silent_below_threshold(check)
	_test_rotation_amp_monotonic(check)
	_test_rotation_amp_bounds(check)
	_test_rotation_zero_ref_safe(check)
	_test_charge_freq_monotonic(check)
	_test_charge_amp_zero_at_rest(check)
	_test_charge_amp_monotonic(check)
	_test_charge_bounds_and_clamp(check)


## 回転音の周波数は rps が増えるほど下がらない(単調非減少)。
func _test_rotation_freq_monotonic(check: Callable) -> void:
	var prev := -1.0
	var ok := true
	for i in 41:
		var rps := i * 0.5
		var f := AudioLevels.rotation_freq(rps, REF)
		if f < prev - EPS:
			ok = false
		prev = f
	check.call(ok, "回転音: 周波数は rps で単調非減少")


## 周波数は [MIN, MAX] に収まる(reference を超える rps でも上限で頭打ち)。
func _test_rotation_freq_bounds(check: Callable) -> void:
	var lo := AudioLevels.rotation_freq(0.0, REF)
	var hi := AudioLevels.rotation_freq(REF * 3.0, REF)
	check.call(
		absf(lo - AudioLevels.ROT_FREQ_MIN) <= EPS,
		"回転音: rps=0 で下限 (%.2f)" % lo
	)
	check.call(
		absf(hi - AudioLevels.ROT_FREQ_MAX) <= EPS,
		"回転音: 高rpsで上限に張り付く (%.2f)" % hi
	)


## lose_threshold 以下の rps では無音。力尽きたコマの音が残ってはいけない。
func _test_rotation_amp_silent_below_threshold(check: Callable) -> void:
	check.call(
		AudioLevels.rotation_amplitude(0.0, REF, LOSE) <= EPS,
		"回転音: rps=0 で無音"
	)
	check.call(
		AudioLevels.rotation_amplitude(LOSE, REF, LOSE) <= EPS,
		"回転音: 閾値ちょうどで無音"
	)
	check.call(
		AudioLevels.rotation_amplitude(LOSE + 0.5, REF, LOSE) > EPS,
		"回転音: 閾値を超えれば鳴る"
	)


## 閾値より上では rps が増えるほど大きくなる(単調非減少)。
func _test_rotation_amp_monotonic(check: Callable) -> void:
	var prev := -1.0
	var ok := true
	for i in 40:
		var rps := LOSE + i * 0.4
		var a := AudioLevels.rotation_amplitude(rps, REF, LOSE)
		if a < prev - EPS:
			ok = false
		prev = a
	check.call(ok, "回転音: 振幅は rps で単調非減少")


## 振幅は [0, ROT_AMP_MAX] に収まる。
func _test_rotation_amp_bounds(check: Callable) -> void:
	var a := AudioLevels.rotation_amplitude(REF * 3.0, REF, LOSE)
	check.call(
		a <= AudioLevels.ROT_AMP_MAX + EPS and a >= 0.0,
		"回転音: 振幅が上限を超えない (%.4f)" % a
	)


## reference が 0 以下でもゼロ除算・NaN を出さず、無音・下限周波数で安全に返す。
func _test_rotation_zero_ref_safe(check: Callable) -> void:
	var f := AudioLevels.rotation_freq(10.0, 0.0)
	var a := AudioLevels.rotation_amplitude(10.0, 0.0, LOSE)
	check.call(is_finite(f) and is_finite(a), "回転音: ref=0 でも有限")
	check.call(a <= EPS, "回転音: ref=0 なら無音")


## チャージ音の周波数は引き量 ratio が増えるほど下がらない(単調非減少)。
func _test_charge_freq_monotonic(check: Callable) -> void:
	var prev := -1.0
	var ok := true
	for i in 21:
		var f := AudioLevels.charge_freq(i / 20.0)
		if f < prev - EPS:
			ok = false
		prev = f
	check.call(ok, "チャージ音: 周波数は引き量で単調非減少")


## 引いていない(ratio=0)ときは無音。
func _test_charge_amp_zero_at_rest(check: Callable) -> void:
	check.call(
		AudioLevels.charge_amplitude(0.0) <= EPS,
		"チャージ音: ratio=0 で無音"
	)
	check.call(
		AudioLevels.charge_amplitude(0.5) > EPS,
		"チャージ音: 引けば鳴る"
	)


## 振幅は引き量で単調非減少。
func _test_charge_amp_monotonic(check: Callable) -> void:
	var prev := -1.0
	var ok := true
	for i in 21:
		var a := AudioLevels.charge_amplitude(i / 20.0)
		if a < prev - EPS:
			ok = false
		prev = a
	check.call(ok, "チャージ音: 振幅は引き量で単調非減少")


## 範囲外の ratio はクランプされ、周波数・振幅とも上限/下限を超えない。
func _test_charge_bounds_and_clamp(check: Callable) -> void:
	# ratio>1 は 1 と同じ(引き切り)、ratio<0 は 0 と同じ(無音)。
	check.call(
		absf(AudioLevels.charge_freq(2.0) - AudioLevels.charge_freq(1.0)) <= EPS,
		"チャージ音: ratio>1 は引き切りにクランプ"
	)
	check.call(
		AudioLevels.charge_amplitude(-1.0) <= EPS,
		"チャージ音: ratio<0 は無音にクランプ"
	)
	var a := AudioLevels.charge_amplitude(1.0)
	check.call(
		absf(a - AudioLevels.CHARGE_AMP_MAX) <= EPS,
		"チャージ音: 引き切りで振幅が上限 (%.4f)" % a
	)
