extends RefCounted

## SpinAura(オーラとパーティクル)の見せ方のテスト。
##
## 見た目のバグはスクショ1枚では分からない。ここでは値非依存の性質だけを
## 押さえる: 勢いゼロで消える・半透明を超えない・勢いに単調・envの継ぎ目で
## 飛ばない・NaNを出さない。数値そのものは手触りで動くので断定しない
## (test_disc_visual.gd と同じ流儀)。

const EPS := 1e-4

## パーティクルの中心からの最大距離(コマ半径比)。particle_state の dist の上限。
const MAX_REACH := 1.02 + SpinAura.DRIFT_RATIO

## 走査に使うRPS比のサンプル。境界(0,1)と外側(2.0=クランプ確認)を含む。
const RATIOS := [0.0, 0.05, 0.25, 0.375, 0.7, 1.0, 2.0]


func run(check: Callable) -> void:
	_test_zero_when_stopped(check)
	_test_translucent(check)
	_test_aura_monotonic(check)
	_test_particle_bounded(check)
	_test_continuous(check)
	_test_more_when_faster(check)
	_test_disc_integration(check)


## 止まっていれば(ratio=0)オーラも粒も完全に消えること。
func _test_zero_when_stopped(check: Callable) -> void:
	var all_zero := true
	for step in 181:
		var t := step / 60.0
		for k in SpinAura.RING_COUNT:
			if SpinAura.aura_ring(0.0, 0.5, k).alpha > EPS:
				all_zero = false
		for i in SpinAura.PARTICLE_COUNT:
			if SpinAura.particle_state(t, i, 0.0, 0.5).alpha > EPS:
				all_zero = false
	check.call(all_zero, "オーラ: 止まっていれば(ratio=0)何も出ない")


## 半透明の保証。どのalphaも1.0に届かず、オーラは AURA_ALPHA_MAX 以下。
## 「半透明で表現」なので不透明になった時点で嘘になる。定数自体も確認する。
func _test_translucent(check: Callable) -> void:
	check.call(SpinAura.AURA_ALPHA_MAX < 1.0, "オーラ: 上限alphaが1.0未満(半透明) (%.2f)" % SpinAura.AURA_ALPHA_MAX)
	check.call(SpinAura.PARTICLE_ALPHA_MAX < 1.0, "粒: 上限alphaが1.0未満(半透明) (%.2f)" % SpinAura.PARTICLE_ALPHA_MAX)

	var aura_max := 0.0
	var part_max := 0.0
	for ratio in RATIOS:
		for k in SpinAura.RING_COUNT:
			aura_max = maxf(aura_max, SpinAura.aura_ring(ratio, 0.5, k).alpha)
		for step in 181:
			var t := step / 60.0
			for i in SpinAura.PARTICLE_COUNT:
				part_max = maxf(part_max, SpinAura.particle_state(t, i, ratio, 0.5).alpha)
	check.call(aura_max <= SpinAura.AURA_ALPHA_MAX + EPS, "オーラ: どのリングもAURA_ALPHA_MAX以下 (最大 %.3f)" % aura_max)
	check.call(aura_max < 1.0, "オーラ: どのリングも不透明にならない")
	check.call(part_max <= SpinAura.PARTICLE_ALPHA_MAX + EPS, "粒: PARTICLE_ALPHA_MAX以下 (最大 %.3f)" % part_max)
	check.call(part_max < 1.0, "粒: 不透明にならない")


## オーラの各リングのalphaと半径が、勢い(ratio)に単調で伸びること。
## RPSは体力なので、増えて薄くなる/縮むのは嘘になる。
func _test_aura_monotonic(check: Callable) -> void:
	var radius := 0.5
	var alpha_ok := true
	var radius_ok := true
	var bound_ok := true
	for k in SpinAura.RING_COUNT:
		var prev_a := -1.0
		var prev_r := -1.0
		for i in 51:
			var ratio := i / 50.0
			var ring := SpinAura.aura_ring(ratio, radius, k)
			if ring.alpha < prev_a - EPS:
				alpha_ok = false
			if ring.radius < prev_r - EPS:
				radius_ok = false
			if ring.radius < radius - EPS or ring.radius > radius * SpinAura.AURA_RADIUS_RATIO + EPS:
				bound_ok = false
			prev_a = ring.alpha
			prev_r = ring.radius
	check.call(alpha_ok, "オーラ: 勢いが上がればalphaが濃くなる(薄くならない)")
	check.call(radius_ok, "オーラ: 勢いが上がれば広がる(縮まない)")
	check.call(bound_ok, "オーラ: 半径は本体径〜本体径×AURA_RADIUS_RATIOに収まる")


## パーティクルが有限の袋に収まり、NaN/INFを出さないこと。
func _test_particle_bounded(check: Callable) -> void:
	var radius := 0.5
	var within := true
	var finite := true
	var size_ok := true
	for ratio in RATIOS:
		for step in 361:
			var t := step / 120.0
			for i in SpinAura.PARTICLE_COUNT:
				var s := SpinAura.particle_state(t, i, ratio, radius)
				var off: Vector2 = s.offset
				if off.length() > radius * MAX_REACH + EPS:
					within = false
				if not (is_finite(off.x) and is_finite(off.y) and is_finite(s.alpha) and is_finite(s.radius)):
					finite = false
				if s.radius <= 0.0 or s.radius > radius * SpinAura.PARTICLE_SIZE_RATIO + EPS:
					size_ok = false
	check.call(within, "粒: 中心からの距離が上限(本体径×%.2f)を超えない" % MAX_REACH)
	check.call(finite, "粒: offset/alpha/sizeにNaN・INFが出ない")
	check.call(size_ok, "粒: サイズが正で上限を超えない")

	# tail_full_rps=0 相当(ratioがおかしくても)壊れないこと。負のratioも0扱い。
	var s0 := SpinAura.particle_state(0.5, 0, -1.0, radius)
	check.call(s0.alpha <= EPS, "粒: 負のratioはalpha0扱いで壊れない")


## envの継ぎ目やt=0で不連続に飛ばないこと。
## alphaは細かい刻みで連続に変化し、位置(offset)の跳びは両側のalphaが
## ほぼ0の継ぎ目でしか起きないこと(そこでの再散布は見えないので許容)。
func _test_continuous(check: Callable) -> void:
	var radius := 0.5
	var dt := 1.0 / 240.0
	var alpha_smooth := true
	var offset_jump_ok := true
	# 1フレーム(1/240s)での最大alpha変化の許容量。env=4p(1-p)の傾きの上限
	# 4/PARTICLE_LIFE に PARTICLE_ALPHA_MAX を掛け、少し余裕を持たせる。
	var alpha_bound := SpinAura.PARTICLE_ALPHA_MAX * (4.0 / SpinAura.PARTICLE_LIFE) * dt * 2.0
	for i in SpinAura.PARTICLE_COUNT:
		for step in 720:
			var t := step * dt
			var a := SpinAura.particle_state(t, i, 1.0, radius)
			var b := SpinAura.particle_state(t + dt, i, 1.0, radius)
			if absf(b.alpha - a.alpha) > alpha_bound:
				alpha_smooth = false
			# offsetが大きく跳ぶのは、両サンプルとも消えかけ(alpha≈0)のときだけ許す。
			if a.offset.distance_to(b.offset) > radius * 0.5:
				if a.alpha > 0.02 or b.alpha > 0.02:
					offset_jump_ok = false
	check.call(alpha_smooth, "粒: alphaが1フレームで飛ばない(継ぎ目で滑らか)")
	check.call(offset_jump_ok, "粒: 位置の跳びはalpha≈0の継ぎ目でしか起きない")

	# t=0でも既に定常状態(消えかけから始まる粒があってもalphaは連続)。
	var jump_at_start := true
	for i in SpinAura.PARTICLE_COUNT:
		var a := SpinAura.particle_state(0.0, i, 1.0, radius)
		var b := SpinAura.particle_state(dt, i, 1.0, radius)
		if absf(b.alpha - a.alpha) > alpha_bound:
			jump_at_start = false
	check.call(jump_at_start, "粒: t=0でalphaが跳ねない(出た瞬間に光が弾けない)")


## 速いほど点灯するスロットが多いこと。速さの大きさをこれが持つ。
func _test_more_when_faster(check: Callable) -> void:
	var prev := -1
	var monotonic := true
	for i in 51:
		var ratio := i / 50.0
		var lit := 0
		for slot in SpinAura.PARTICLE_COUNT:
			if SpinAura.slot_weight(slot, SpinAura.PARTICLE_COUNT, ratio) > 0.02:
				lit += 1
		if lit < prev:
			monotonic = false
		prev = lit
	check.call(monotonic, "粒: 勢いが上がれば点灯スロットが減らない")

	var lit_low := 0
	var lit_high := 0
	for slot in SpinAura.PARTICLE_COUNT:
		if SpinAura.slot_weight(slot, SpinAura.PARTICLE_COUNT, 0.25) > 0.02:
			lit_low += 1
		if SpinAura.slot_weight(slot, SpinAura.PARTICLE_COUNT, 1.0) > 0.02:
			lit_high += 1
	check.call(lit_high > lit_low, "粒: 満速(%d灯)は低速(%d灯)より多い" % [lit_high, lit_low])

	# slot_weightが0〜1に収まること。
	var bounded := true
	for ratio in RATIOS:
		for slot in SpinAura.PARTICLE_COUNT:
			var w := SpinAura.slot_weight(slot, SpinAura.PARTICLE_COUNT, ratio)
			if w < -EPS or w > 1.0 + EPS:
				bounded = false
	check.call(bounded, "粒: slot_weightが0〜1に収まる")


## Discと繋いだときの挙動。aura_ratio()が敗北で0になり、rpsに単調なこと。
func _test_disc_integration(check: Callable) -> void:
	var d := _disc()

	d.rps = 0.0
	check.call(d.aura_ratio() <= EPS, "Disc: rps=0でオーラの勢いが0")

	d.rps = 40.0
	d.defeated = false
	var alive := d.aura_ratio()
	d.defeated = true
	check.call(d.aura_ratio() <= EPS, "Disc: 力尽きたコマはオーラの勢いが0(生存時 %.2f)" % alive)

	# rpsに単調(下がって濃くなることはない)。
	d.defeated = false
	var prev := -1.0
	var monotonic := true
	for i in 41:
		d.rps = float(i)
		var r := d.aura_ratio()
		if r < prev - EPS:
			monotonic = false
		prev = r
	check.call(monotonic, "Disc: rpsが上がってオーラの勢いが下がることはない")

	# tail_full_rps=0でも壊れない(0除算しない)。
	d.tail_full_rps = 0.0
	d.rps = 15.0
	check.call(d.aura_ratio() == 0.0, "Disc: tail_full_rps=0でもオーラの勢いが壊れない")

	d.free()


func _disc() -> Disc:
	var d := Disc.new()
	var s := SpinnerStats.new()
	s.radius = 0.5
	s.rps = 15.0
	d.stats = s
	return d
