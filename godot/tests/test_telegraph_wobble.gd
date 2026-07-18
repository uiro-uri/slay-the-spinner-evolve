extends RefCounted

## telegraph_wobble.gd / EnemyTelegraph の揺らぎのテスト。
##
## 一番大事なのは「揺れるのは見た目だけで、実際に撃たれる値は動かない」こと。
## ここが崩れると予告が本当に嘘になる。表示値で撃ってしまう実装ミスは
## 起こりやすいので、テストで固定する。

const EPS := 1e-4

const TRUE_POS := Vector2(8.0, 2.0)
const TRUE_VEL := Vector2(-3.0, 4.0)


func run(check: Callable) -> void:
	_test_wave_bounded(check)
	_test_within_amplitude(check)
	_test_centered_on_truth(check)
	_test_smooth(check)
	_test_starts_at_truth(check)
	_test_zero_amplitude(check)
	_test_launch_unaffected(check)
	_test_level_scales_amplitude(check)
	_test_aim_clamped_to_arena(check)


func _telegraph() -> EnemyTelegraph:
	var t := EnemyTelegraph.new()
	t.show_plan(TRUE_POS, TRUE_VEL)
	return t


## 揺らぎの素が必ず-1〜1に収まること。ここが崩れると揺れ幅の保証が全部崩れる。
func _test_wave_bounded(check: Callable) -> void:
	var worst := 0.0
	for i in 5000:
		var t := i * 0.01
		worst = maxf(worst, absf(TelegraphWobble.wave(t, 2.2, TelegraphWobble.FREQ_X)))
	check.call(worst <= 1.0 + EPS, "揺らぎ: 素の値が-1〜1に収まる (最大 %.4f)" % worst)


## 設定した揺れ幅を超えないこと。超えると予告が的外れになる。
func _test_within_amplitude(check: Callable) -> void:
	var pos_amp := 0.22
	var angle_amp := 7.0
	var len_amp := 0.14

	var worst_pos := 0.0
	var worst_angle := 0.0
	var worst_len := 0.0

	for i in 3000:
		var t := i * 0.01
		var p := TelegraphWobble.position_at(TRUE_POS, t, pos_amp, 2.2)
		# 各軸が揺れ幅以内
		worst_pos = maxf(worst_pos, maxf(absf(p.x - TRUE_POS.x), absf(p.y - TRUE_POS.y)))

		var v := TelegraphWobble.velocity_at(TRUE_VEL, t, angle_amp, len_amp, 2.2)
		worst_angle = maxf(worst_angle, rad_to_deg(absf(TRUE_VEL.angle_to(v))))
		worst_len = maxf(worst_len, absf(v.length() / TRUE_VEL.length() - 1.0))

	check.call(
		worst_pos <= pos_amp + EPS,
		"揺らぎ: 位置が揺れ幅%.2f以内 (最大 %.4f)" % [pos_amp, worst_pos]
	)
	check.call(
		worst_angle <= angle_amp + 0.01,
		"揺らぎ: 向きが揺れ幅%.1f度以内 (最大 %.3f度)" % [angle_amp, worst_angle]
	)
	check.call(
		worst_len <= len_amp + EPS,
		"揺らぎ: 長さが揺れ幅%.0f%%以内 (最大 %.2f%%)" % [len_amp * 100, worst_len * 100]
	)

	# ちゃんと揺れていること(振れ幅が0では意味がない)
	check.call(worst_pos > pos_amp * 0.5, "揺らぎ: 位置が実際に揺れている (%.3f)" % worst_pos)
	check.call(worst_angle > angle_amp * 0.5, "揺らぎ: 向きが実際に揺れている (%.2f度)" % worst_angle)
	check.call(worst_len > len_amp * 0.5, "揺らぎ: 長さが実際に揺れている (%.1f%%)" % [worst_len * 100])


## 確定値を中心に振れること。偏っていると、平均を取っても真の値に寄らず
## 「予告が systematically ずれている」ことになる。
func _test_centered_on_truth(check: Callable) -> void:
	var sum_pos := Vector2.ZERO
	var sum_angle := 0.0
	var samples := 4000
	for i in samples:
		var t := i * 0.013
		sum_pos += TelegraphWobble.position_at(TRUE_POS, t, 0.22, 2.2) - TRUE_POS
		var v := TelegraphWobble.velocity_at(TRUE_VEL, t, 7.0, 0.14, 2.2)
		sum_angle += TRUE_VEL.angle_to(v)

	var mean_pos := sum_pos / samples
	var mean_angle := rad_to_deg(sum_angle / samples)
	check.call(
		mean_pos.length() < 0.02,
		"揺らぎ: 位置の平均が確定値に寄る (ずれ %.4f)" % mean_pos.length()
	)
	check.call(
		absf(mean_angle) < 0.5,
		"揺らぎ: 向きの平均が確定値に寄る (ずれ %.3f度)" % mean_angle
	)


## 滑らかであること。フレームごとにランダムだとチカチカして読めない。
func _test_smooth(check: Callable) -> void:
	var worst := 0.0
	var dt := 1.0 / 60.0
	for i in 2000:
		var t := i * dt
		var a := TelegraphWobble.position_at(TRUE_POS, t, 0.22, 2.2)
		var b := TelegraphWobble.position_at(TRUE_POS, t + dt, 0.22, 2.2)
		worst = maxf(worst, a.distance_to(b))
	# 1フレームで揺れ幅の半分も飛んだら、それは揺らぎではなくノイズ
	check.call(worst < 0.11, "揺らぎ: 1フレームの移動が滑らか (最大 %.4f ユニット)" % worst)


func _test_starts_at_truth(check: Callable) -> void:
	# t=0で確定値そのものであること。ずれていると、予告が出た瞬間にコマが飛ぶ。
	var p := TelegraphWobble.position_at(TRUE_POS, 0.0, 0.22, 2.2)
	check.call(p.is_equal_approx(TRUE_POS), "揺らぎ: t=0は確定値そのもの (位置 %s)" % p)
	var v := TelegraphWobble.velocity_at(TRUE_VEL, 0.0, 7.0, 0.14, 2.2)
	check.call(v.is_equal_approx(TRUE_VEL), "揺らぎ: t=0は確定値そのもの (速度 %s)" % v)


func _test_zero_amplitude(check: Callable) -> void:
	var p := TelegraphWobble.position_at(TRUE_POS, 3.7, 0.0, 2.2)
	check.call(p.is_equal_approx(TRUE_POS), "揺らぎ: 揺れ幅0なら確定値そのまま (位置)")
	var v := TelegraphWobble.velocity_at(TRUE_VEL, 3.7, 0.0, 0.0, 2.2)
	check.call(v.is_equal_approx(TRUE_VEL), "揺らぎ: 揺れ幅0なら確定値そのまま (速度)")


## 一番大事なテスト。揺らぎは見た目だけで、撃たれる値は動かないこと。
##
## show_plan()で渡した確定値が、時間が経っても書き換わらないこと。
## Battleはここから読んで撃つので、これが揺れると予告が嘘になる。
func _test_launch_unaffected(check: Callable) -> void:
	var t := _telegraph()

	# 時間を進める(揺らぎが動く)
	for i in 120:
		t._process(1.0 / 60.0)

	# 表示は揺れている
	var moved := t.display_position().distance_to(TRUE_POS) > 0.01
	check.call(moved, "揺らぎ: 時間が経つと表示が動く (%.4f)" % t.display_position().distance_to(TRUE_POS))

	# しかし確定値は不動
	check.call(
		t._origin.is_equal_approx(TRUE_POS),
		"揺らぎ: 確定した位置は動かない (%s → %s)" % [TRUE_POS, t._origin]
	)
	check.call(
		t._velocity.is_equal_approx(TRUE_VEL),
		"揺らぎ: 確定した速度は動かない (%s → %s)" % [TRUE_VEL, t._velocity]
	)

	# show_plan()し直すと揺らぎがリセットされ、その瞬間は確定値と一致する
	t.show_plan(TRUE_POS, TRUE_VEL)
	check.call(
		t.display_position().distance_to(TRUE_POS) < EPS,
		"揺らぎ: 出した直後は確定値と一致する"
	)
	t.free()


## 敵レベルが高いほど予告が大きくブレること。弱い敵は読みやすく、強い敵は
## 読みにくくする調整。倍率が単調に増え、実際の表示の振れ幅も増えることを見る。
func _test_level_scales_amplitude(check: Callable) -> void:
	check.call(
		TelegraphWobble.level_scale(1) < TelegraphWobble.level_scale(5),
		"揺らぎ: 高レベルほど揺れ幅の倍率が大きい (%.3f < %.3f)" % [
			TelegraphWobble.level_scale(1), TelegraphWobble.level_scale(5)
		]
	)

	# レベルが上がると倍率が減らない(単調)
	var prev := TelegraphWobble.level_scale(1)
	var monotonic := true
	for lv in range(2, 6):
		var s := TelegraphWobble.level_scale(lv)
		if s < prev - EPS:
			monotonic = false
		prev = s
	check.call(monotonic, "揺らぎ: レベルが上がると揺れ幅倍率が減らない")

	# 範囲外はクランプ(レベル0はレベル1、レベル9はレベル5と同じ)
	check.call(
		is_equal_approx(TelegraphWobble.level_scale(0), TelegraphWobble.level_scale(1))
		and is_equal_approx(TelegraphWobble.level_scale(9), TelegraphWobble.level_scale(5)),
		"揺らぎ: レベルは範囲外でクランプされる"
	)

	# 実際の予告表示の振れ幅がレベルで増えること
	var low := _max_deviation(1)
	var high := _max_deviation(5)
	check.call(
		high > low + EPS,
		"揺らぎ: レベル5の予告はレベル1より大きくブレる (%.3f < %.3f)" % [low, high]
	)


## そのレベルの予告を一定時間動かし、確定値からの表示ずれの最大を返す。
func _max_deviation(level: int) -> float:
	var t := _telegraph()
	t.apply_level(level)
	var worst := 0.0
	for i in 600:
		t._process(1.0 / 60.0)
		worst = maxf(worst, t.display_position().distance_to(TRUE_POS))
	t.free()
	return worst


## 発射地点がアリーナの外へ出ないこと。
##
## マウス位置をそのままコマの位置にしていたので、アリーナの外どこからでも
## 発射できた。外から内向きに撃つと壁の反射判定(内向きの間は当たらない)を
## すり抜けて助走をつけられる。実際に(14, 0.3)から撃てていた。
func _test_aim_clamped_to_arena(check: Callable) -> void:
	var radius := 0.5
	var b := Arena.BOUNDS
	var outside := [
		Vector2(14.0, 0.3), Vector2(-5.0, 5.0), Vector2(5.0, 20.0),
		Vector2(-100.0, -100.0), Vector2(999.0, 999.0),
	]
	var worst := ""
	for p in outside:
		var c: Vector2 = ArenaWall.clamp_inside(b, p, radius)
		# コマ全体がアリーナに収まること
		var ok: bool = (
			c.x >= b.position.x + radius - EPS and c.x <= b.end.x - radius + EPS
			and c.y >= b.position.y + radius - EPS and c.y <= b.end.y - radius + EPS
		)
		if not ok:
			worst = "%s → %s" % [p, c]
	check.call(worst == "", "発射地点: アリーナの外を狙っても中へ収まる (%s)" % worst)

	# 中を狙っているときは動かさないこと。勝手に寄せると狙いがずれる。
	var inside := Vector2(3.0, 7.0)
	check.call(
		ArenaWall.clamp_inside(b, inside, radius).is_equal_approx(inside),
		"発射地点: アリーナの中ならそのまま"
	)

	# 大きいコマほど内側にしか置けない
	var big: Vector2 = ArenaWall.clamp_inside(b, Vector2(999.0, 999.0), 3.0)
	check.call(
		big.is_equal_approx(Vector2(7.0, 7.0)),
		"発射地点: 大きいコマは半径の分だけ内側で止まる (%s)" % big
	)

	# アリーナより大きいコマでも壊れない(0除算や反転した範囲にしない)
	var huge: Vector2 = ArenaWall.clamp_inside(b, Vector2(999.0, 999.0), 99.0)
	check.call(huge.is_equal_approx(b.get_center()), "発射地点: コマがアリーナより大きくても壊れない")
