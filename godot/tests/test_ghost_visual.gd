extends RefCounted

## ghost_visual.gd のテスト。ゴースト(無敵)中のコマの半透明シマーの数式。
##
## 見た目の数式なので、固定するのは「半透明であり続けること」と「実際に脈打つこと」。
## alphaが1に達すると無敵に見えず、0に達するとコマが消える。振幅が0だと明滅しない。

const SAMPLES := 200


func run(check: Callable) -> void:
	_test_always_translucent(check)
	_test_within_band(check)
	_test_actually_shimmers(check)
	_test_center_at_zero(check)
	_test_modulate(check)
	_test_disc_applies_shimmer(check)


## どの時刻でもalphaは(0,1)の内側。完全不透明にも完全透明にもならない。
func _test_always_translucent(check: Callable) -> void:
	var ok := true
	for i in SAMPLES:
		var t := float(i) / SAMPLES * 4.0    # 数周期ぶんなめる
		var a := GhostVisual.alpha(t)
		if a <= 0.0 or a >= 1.0:
			ok = false
	check.call(ok, "ゴースト表示: alphaは常に(0,1)＝半透明を保つ")


## alphaは中心±振幅の帯に収まる。
func _test_within_band(check: Callable) -> void:
	var lo := GhostVisual.ALPHA_BASE - GhostVisual.ALPHA_AMP
	var hi := GhostVisual.ALPHA_BASE + GhostVisual.ALPHA_AMP
	var ok := true
	for i in SAMPLES:
		var t := float(i) / SAMPLES * 4.0
		var a := GhostVisual.alpha(t)
		if a < lo - 1e-5 or a > hi + 1e-5:
			ok = false
	check.call(ok, "ゴースト表示: alphaは中心±振幅の帯に収まる (%.2f〜%.2f)" % [lo, hi])


## 実際に脈打つこと。振幅を0にすると静止するので、それを弾く。
func _test_actually_shimmers(check: Callable) -> void:
	var lo := INF
	var hi := -INF
	for i in SAMPLES:
		var t := float(i) / SAMPLES * 4.0
		var a := GhostVisual.alpha(t)
		lo = minf(lo, a)
		hi = maxf(hi, a)
	# 山と谷の差が振幅ぶん(≒2*AMP)開くこと。少なくともAMP以上は動く。
	check.call(
		hi - lo > GhostVisual.ALPHA_AMP,
		"ゴースト表示: alphaが実際に明滅する (振れ幅 %.3f)" % (hi - lo)
	)


## t=0では中心値(sin(0)=0)。予告と同じく開始の瞬間に飛ばない。
func _test_center_at_zero(check: Callable) -> void:
	check.call(
		is_equal_approx(GhostVisual.alpha(0.0), GhostVisual.ALPHA_BASE),
		"ゴースト表示: t=0は中心alpha (%.3f)" % GhostVisual.alpha(0.0)
	)


## Disc がゴースト中に実際に半透明シマーを modulate へ載せ、解除で不透明へ戻すこと。
## 純関数だけでなく、コマ側の適用と復帰まで一気通貫で見る(止まった1枚では
## 分からないので、_processを進めてalphaが帯に入ること・白へ戻ることを測る)。
func _test_disc_applies_shimmer(check: Callable) -> void:
	var disc := Disc.new()
	disc.stats = SpinnerStats.new()

	# 既定は不透明。
	check.call(
		disc.modulate.is_equal_approx(Color(1.0, 1.0, 1.0, 1.0)),
		"ゴースト表示: 既定のコマは不透明 (%s)" % disc.modulate
	)

	# ゴーストON → _processで位相が進むとmodulateがシマーの帯に入る。
	disc.set_ghosting(true)
	disc._process(0.13)
	var lo := GhostVisual.ALPHA_BASE - GhostVisual.ALPHA_AMP - 1e-5
	var hi := GhostVisual.ALPHA_BASE + GhostVisual.ALPHA_AMP + 1e-5
	check.call(
		disc.modulate.a >= lo and disc.modulate.a <= hi,
		"ゴースト表示: コマがシマーの帯で半透明になる (a=%.3f)" % disc.modulate.a
	)

	# ゴーストOFF → 実体化して不透明へ戻る。
	disc.set_ghosting(false)
	check.call(
		disc.modulate.is_equal_approx(Color(1.0, 1.0, 1.0, 1.0)),
		"ゴースト表示: 解除でコマが実体化(不透明)へ戻る (%s)" % disc.modulate
	)

	disc.free()


## modulateは色にTINT、alphaにalpha(t)を載せる。
func _test_modulate(check: Callable) -> void:
	var t := 0.37
	var m := GhostVisual.modulate(t)
	check.call(is_equal_approx(m.a, GhostVisual.alpha(t)), "ゴースト表示: modulateのaがalpha(t)と一致")
	check.call(
		is_equal_approx(m.r, GhostVisual.TINT.r)
		and is_equal_approx(m.g, GhostVisual.TINT.g)
		and is_equal_approx(m.b, GhostVisual.TINT.b),
		"ゴースト表示: modulateの色がTINT"
	)
