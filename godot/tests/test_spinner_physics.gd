extends RefCounted

## spinner_physics.gd のテスト。
##
## プロトタイプ(simulation.py)との数値照合はしない。Vector2の成分は32bitで
## GDScriptのfloat(64bit)ともnumpyのfloat64とも一致せず、衝突が誤差を
## 指数的に増幅するため、軌跡の厳密一致は原理的に不可能。追いかけると
## 永遠に緑にならないテストになる。
##
## 代わりに、数値をどう調整しても成り立つべき「物理法則の不変量」を検証する:
## 運動量保存、弾性衝突での運動エネルギー保存、力の向き、など。
## これらは移植ミスを確実に捕まえる一方、手触りの調整では壊れない。

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_spring(check)
	_test_friction(check)
	_test_collision_detection(check)
	_test_elastic_conserves_momentum(check)
	_test_elastic_conserves_energy(check)
	_test_elastic_separates(check)
	_test_spin_drain(check)
	_test_spin_kick(check)
	_test_wall(check)
	_test_natural_decay(check)


func _test_spring(check: Callable) -> void:
	var center := Vector2(5, 5)
	# 中心にいれば力は働かない
	check.call(
		SpinnerPhysics.spring_accel(center, center, 4.9).length() < EPS,
		"バネ: 中心では力ゼロ"
	)
	# 常に中心を向く
	var accel := SpinnerPhysics.spring_accel(Vector2(8, 5), center, 4.9)
	check.call(accel.x < 0.0 and absf(accel.y) < EPS, "バネ: 中心を向く")
	# 変位に比例する（2倍離れれば2倍の力）
	var near := SpinnerPhysics.spring_accel(Vector2(6, 5), center, 4.9).length()
	var far := SpinnerPhysics.spring_accel(Vector2(7, 5), center, 4.9).length()
	check.call(absf(far - near * 2.0) < EPS, "バネ: 変位に比例 (%.3f vs %.3f)" % [far, near * 2.0])


func _test_friction(check: Callable) -> void:
	var vel := Vector2(3, 4)  # 長さ5
	var accel := SpinnerPhysics.friction_accel(vel, 2.0)
	check.call(absf(accel.length() - 2.0) < EPS, "摩擦: 大きさは速度によらず一定")
	check.call(accel.normalized().dot(vel.normalized()) < -0.999, "摩擦: 進行方向と逆向き")
	# 速度ゼロで0除算しない（プロトタイプはここでnanになる）
	var stopped := SpinnerPhysics.friction_accel(Vector2.ZERO, 2.0)
	check.call(stopped == Vector2.ZERO, "摩擦: 停止時はゼロ(nanにならない)")


func _test_collision_detection(check: Callable) -> void:
	var approaching_a := Vector2(0, 0)
	var approaching_b := Vector2(0.9, 0)
	check.call(
		SpinnerPhysics.is_colliding(approaching_a, 0.5, Vector2(1, 0), approaching_b, 0.5, Vector2(-1, 0)),
		"衝突判定: 接触して近づいていれば真"
	)
	# 接触していても離れていく最中なら偽（多重衝突を防ぐ）
	check.call(
		not SpinnerPhysics.is_colliding(approaching_a, 0.5, Vector2(-1, 0), approaching_b, 0.5, Vector2(1, 0)),
		"衝突判定: 離れていく最中は偽"
	)
	# 離れていれば偽
	check.call(
		not SpinnerPhysics.is_colliding(Vector2(0, 0), 0.5, Vector2(1, 0), Vector2(5, 0), 0.5, Vector2(-1, 0)),
		"衝突判定: 離れていれば偽"
	)


func _test_elastic_conserves_momentum(check: Callable) -> void:
	var pos_a := Vector2(0, 0); var vel_a := Vector2(2, 1); var mass_a := 1.5
	var pos_b := Vector2(0.9, 0.2); var vel_b := Vector2(-1, 0.5); var mass_b := 3.0

	var before := mass_a * vel_a + mass_b * vel_b
	var result := SpinnerPhysics.elastic_velocities(pos_a, vel_a, mass_a, pos_b, vel_b, mass_b)
	var after := mass_a * result[0] + mass_b * result[1]

	check.call(
		(after - before).length() < EPS,
		"弾性衝突: 運動量が保存する (%s -> %s)" % [before, after]
	)


func _test_elastic_conserves_energy(check: Callable) -> void:
	var pos_a := Vector2(0, 0); var vel_a := Vector2(2, 1); var mass_a := 1.5
	var pos_b := Vector2(0.9, 0.2); var vel_b := Vector2(-1, 0.5); var mass_b := 3.0

	var before := 0.5 * mass_a * vel_a.length_squared() + 0.5 * mass_b * vel_b.length_squared()
	var result := SpinnerPhysics.elastic_velocities(pos_a, vel_a, mass_a, pos_b, vel_b, mass_b)
	var after := 0.5 * mass_a * result[0].length_squared() + 0.5 * mass_b * result[1].length_squared()

	check.call(
		absf(after - before) < 1e-3,
		"弾性衝突: 運動エネルギーが保存する (%.5f -> %.5f)" % [before, after]
	)


func _test_elastic_separates(check: Callable) -> void:
	# 正面衝突したら離れる向きになること
	var pos_a := Vector2(0, 0); var pos_b := Vector2(0.9, 0)
	var result := SpinnerPhysics.elastic_velocities(
		pos_a, Vector2(1, 0), 1.0, pos_b, Vector2(-1, 0), 1.0
	)
	var closing := (result[0] - result[1]).dot(pos_a - pos_b)
	check.call(closing > 0.0, "弾性衝突: 衝突後は離れていく (closing=%.3f)" % closing)

	# 完全に重なっている場合は向きが定まらないので何もしない
	var overlapped := SpinnerPhysics.elastic_velocities(
		Vector2.ZERO, Vector2(1, 0), 1.0, Vector2.ZERO, Vector2(-1, 0), 1.0
	)
	check.call(
		overlapped[0] == Vector2(1, 0) and overlapped[1] == Vector2(-1, 0),
		"弾性衝突: 完全に重なった時は変化なし(0除算しない)"
	)


func _test_spin_drain(check: Callable) -> void:
	# 相手が重いほど削られる
	var light := SpinnerPhysics.spin_drain(1.0, 5.0, 2.0, 0.5, 0.08)
	var heavy := SpinnerPhysics.spin_drain(4.0, 5.0, 2.0, 0.5, 0.08)
	check.call(heavy > light, "RPS減少: 相手が重いほど大きい")

	# 相手が速いほど削られる
	var slow := SpinnerPhysics.spin_drain(2.0, 1.0, 2.0, 0.5, 0.08)
	var fast := SpinnerPhysics.spin_drain(2.0, 9.0, 2.0, 0.5, 0.08)
	check.call(fast > slow, "RPS減少: 相手が速いほど大きい")

	# 自分が重い/大きいほど削られにくい
	var frail := SpinnerPhysics.spin_drain(2.0, 5.0, 1.0, 0.5, 0.08)
	var sturdy := SpinnerPhysics.spin_drain(2.0, 5.0, 4.0, 0.5, 0.08)
	check.call(sturdy < frail, "RPS減少: 自分が重いほど小さい")
	var small := SpinnerPhysics.spin_drain(2.0, 5.0, 2.0, 0.5, 0.08)
	var big := SpinnerPhysics.spin_drain(2.0, 5.0, 2.0, 1.5, 0.08)
	check.call(big < small, "RPS減少: 自分が大きいほど小さい")

	# ゼロ除算しない
	check.call(SpinnerPhysics.spin_drain(2.0, 5.0, 0.0, 0.5, 0.08) == 0.0, "RPS減少: 質量0でも落ちない")


func _test_spin_kick(check: Callable) -> void:
	var pos_self := Vector2(0, 0)
	var pos_other := Vector2(1, 0)
	var kick := SpinnerPhysics.spin_kick(pos_self, pos_other, 0.5, 2.0, 1.0)
	# 相手から離れる向き（プロトタイプはここが逆で引き寄せ合っていた）
	check.call(kick.x < 0.0, "回転キック: 相手から離れる向き (%s)" % kick)
	# 削られた量が多いほど強く弾ける
	var weak := SpinnerPhysics.spin_kick(pos_self, pos_other, 0.5, 1.0, 1.0).length()
	var strong := SpinnerPhysics.spin_kick(pos_self, pos_other, 0.5, 3.0, 1.0).length()
	check.call(strong > weak, "回転キック: RPS減少が大きいほど強い")


func _test_wall(check: Callable) -> void:
	# 左の壁: x=0にあり、内側(+x)を向く
	var wall_point := Vector2(0, 5)
	var wall_normal := Vector2(1, 0)

	check.call(
		SpinnerPhysics.wall_hit(wall_point, wall_normal, Vector2(0.3, 5), Vector2(-1, 0), 0.5),
		"壁: めり込んで壁へ向かっていれば真"
	)
	check.call(
		not SpinnerPhysics.wall_hit(wall_point, wall_normal, Vector2(0.3, 5), Vector2(1, 0), 0.5),
		"壁: めり込んでいても離れる向きなら偽"
	)
	check.call(
		not SpinnerPhysics.wall_hit(wall_point, wall_normal, Vector2(5, 5), Vector2(-1, 0), 0.5),
		"壁: 離れていれば偽"
	)

	# 反射: 法線方向が反転し、接線方向は保たれる
	var bounced := SpinnerPhysics.wall_bounce(Vector2(-2, 3), wall_normal, 1.0)
	check.call(absf(bounced.x - 2.0) < EPS, "壁: 法線方向が反転する (x=%.3f)" % bounced.x)
	check.call(absf(bounced.y - 3.0) < EPS, "壁: 接線方向は保たれる (y=%.3f)" % bounced.y)

	# restitutionで勢いが落ちる
	var damped := SpinnerPhysics.wall_bounce(Vector2(-2, 0), wall_normal, 0.5)
	check.call(absf(damped.x - 1.0) < EPS, "壁: restitutionで勢いが落ちる (x=%.3f)" % damped.x)


func _test_natural_decay(check: Callable) -> void:
	var small := SpinnerPhysics.natural_spin_decay(0.5, 1.0, 0.1)
	var big := SpinnerPhysics.natural_spin_decay(1.5, 1.0, 0.1)
	check.call(big > small, "自然減衰: 大きいコマほど速く回転を失う")
	check.call(absf(small - 0.05) < EPS, "自然減衰: radius*rate*delta (%.4f)" % small)
