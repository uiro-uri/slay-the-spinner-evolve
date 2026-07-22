extends RefCounted

## launch_standoff.gd のテスト。発射位置と敵予告の「立ち合いの間合い」を押さえる。
##
## 至近スポーン殴り(予告の真横に置いて動く前に殴る)の封鎖が本体。間合いの値
## そのものは調整で動くので、ここでは「間合い以上へ必ず押し出される」「壁の
## 内側に留まる」「詰み配置でも壊れない」という値に依存しない性質を固定する。

const EPS := 1e-3


func run(check: Callable) -> void:
	_test_required_distance(check)
	_test_noop_when_far(check)
	_test_push_out(check)
	_test_wall_interplay(check)
	_test_multi_spawn(check)
	_test_degenerate_on_spawn(check)
	_test_infeasible_stays_inside(check)
	_test_policies_respect_standoff(check)


func _field() -> FieldData:
	return FieldData.make(
		"FIELD_TEST", Rect2(0, 0, 10, 10), ArenaWall.WallShape.RECT,
		SpinnerPhysics.StageShape.DISH, 4.9
	)


func _inside_rect(field: FieldData, pos: Vector2, radius: float) -> bool:
	var b := field.arena_bounds
	return (pos.x >= b.position.x + radius - EPS and pos.x <= b.end.x - radius + EPS
		and pos.y >= b.position.y + radius - EPS and pos.y <= b.end.y - radius + EPS)


## 間合いの式: 基本は両者の半径+GAP(縁の自由距離が一定)、上限はinradius-自半径
## (出現点の反対側の壁際には必ず置ける)、負にはならない。
func _test_required_distance(check: Callable) -> void:
	var base := LaunchStandoff.required_distance(0.7, 0.4, 5.0)
	check.call(
		absf(base - (0.7 + 0.4 + LaunchStandoff.GAP)) < EPS,
		"間合い: 基本は 自半径+敵半径+GAP (%.2f)" % base
	)
	var capped := LaunchStandoff.required_distance(0.7, 3.0, 5.0)
	check.call(
		absf(capped - (5.0 - 0.7)) < EPS,
		"間合い: 上限は inradius-自半径 (%.2f)" % capped
	)
	check.call(
		LaunchStandoff.required_distance(0.7, 1.0, 5.0)
			>= LaunchStandoff.required_distance(0.7, 0.4, 5.0),
		"間合い: 敵が大きいほど広い(単調)"
	)
	check.call(
		LaunchStandoff.required_distance(6.0, 1.0, 5.0) == 0.0,
		"間合い: 負にはならない(0でクランプ)"
	)


## 間合いの外の位置はそのまま(制約は近づいた時にだけ効く)。
func _test_noop_when_far(check: Callable) -> void:
	var field := _field()
	var pos := field.clamp_launch(
		Vector2(2, 5), PackedVector2Array([Vector2(8, 5)]),
		PackedFloat32Array([0.4]), 0.7
	)
	check.call(pos == Vector2(2, 5), "間合いの外の位置は動かさない (%s)" % str(pos))


## 予告の至近に置こうとすると、ちょうど間合いの距離まで押し出される。
func _test_push_out(check: Callable) -> void:
	var field := _field()
	var spawn := Vector2(7, 5)
	var req := LaunchStandoff.required_distance(0.7, 0.4, field.inradius())
	var pos := field.clamp_launch(
		Vector2(6.5, 5), PackedVector2Array([spawn]), PackedFloat32Array([0.4]), 0.7
	)
	check.call(
		pos.distance_to(spawn) >= req - EPS,
		"至近置きは間合いまで押し出す (距離 %.2f / 間合い %.2f)" % [pos.distance_to(spawn), req]
	)
	check.call(
		pos.distance_to(spawn) <= req + 0.1,
		"押し出しは間合いちょうどまで(過剰に飛ばさない) (距離 %.2f)" % pos.distance_to(spawn)
	)
	check.call(_inside_rect(field, pos, 0.7), "押し出し後も壁の内側 (%s)" % str(pos))


## 敵が壁際のとき、壁側へ押し出しても壁クランプで戻される。反復とフォールバックで
## 「壁の内側かつ間合いの外」の点(反対側)へ必ず抜けること。
func _test_wall_interplay(check: Callable) -> void:
	var field := _field()
	var spawn := Vector2(9, 5)
	var req := LaunchStandoff.required_distance(0.7, 0.4, field.inradius())
	# 敵と壁に挟まれた位置から始める。素朴な半径方向の押し出しは壁の外に出る。
	var pos := field.clamp_launch(
		Vector2(9.6, 5), PackedVector2Array([spawn]), PackedFloat32Array([0.4]), 0.7
	)
	check.call(
		pos.distance_to(spawn) >= req - EPS,
		"壁際の敵でも間合いの外へ抜ける (距離 %.2f / 間合い %.2f)" % [pos.distance_to(spawn), req]
	)
	check.call(_inside_rect(field, pos, 0.7), "壁際の敵でも壁の内側 (%s)" % str(pos))


## 乱戦: 複数の予告の間合いを同時に満たす。
func _test_multi_spawn(check: Callable) -> void:
	var field := _field()
	var spawns := PackedVector2Array([Vector2(6, 5), Vector2(5, 6)])
	var radii := PackedFloat32Array([0.4, 0.4])
	var pos := field.clamp_launch(Vector2(5, 5), spawns, radii, 0.7)
	var ok := true
	for i in spawns.size():
		var req := LaunchStandoff.required_distance(0.7, radii[i], field.inradius())
		if pos.distance_to(spawns[i]) < req - EPS:
			ok = false
	check.call(ok, "乱戦: 全ての敵の間合いを同時に満たす (%s)" % str(pos))
	check.call(_inside_rect(field, pos, 0.7), "乱戦: 壁の内側 (%s)" % str(pos))


## 出現点に完全に重なった位置(押し出す向きが決められない)でも壊れない。
func _test_degenerate_on_spawn(check: Callable) -> void:
	var field := _field()
	var spawn := Vector2(8, 5)
	var req := LaunchStandoff.required_distance(0.7, 0.4, field.inradius())
	var pos := field.clamp_launch(
		spawn, PackedVector2Array([spawn]), PackedFloat32Array([0.4]), 0.7
	)
	check.call(
		pos.distance_to(spawn) >= req - EPS,
		"出現点に重なった位置も間合いの外へ (距離 %.2f)" % pos.distance_to(spawn)
	)


## 幾何的に間合いを満たせない詰み配置(狭い土俵に予告が敷き詰められた乱戦)でも、
## 壁の内側に留まり、届く中で最も間合いに近い点を決定的に返す。
func _test_infeasible_stays_inside(check: Callable) -> void:
	var field := FieldData.make(
		"FIELD_TINY", Rect2(0, 0, 6, 6), ArenaWall.WallShape.RECT,
		SpinnerPhysics.StageShape.DISH, 4.9
	)
	var spawns := PackedVector2Array([
		Vector2(2, 2), Vector2(2, 4), Vector2(4, 2), Vector2(4, 4)
	])
	var radii := PackedFloat32Array([0.4, 0.4, 0.4, 0.4])
	var a := field.clamp_launch(Vector2(3, 3), spawns, radii, 1.0)
	var b := field.clamp_launch(Vector2(3, 3), spawns, radii, 1.0)
	check.call(_inside_rect(field, a, 1.0), "詰み配置: 壁の内側に留まる (%s)" % str(a))
	check.call(a == b, "詰み配置: 結果が決定的")
	# 満たせないなりに、素朴に中央へ置くよりは全予告から離れた点を選ぶこと。
	var nearest := INF
	for s in spawns:
		nearest = minf(nearest, a.distance_to(s))
	check.call(
		nearest >= 1.2,
		"詰み配置: 届く中で間合いに最も近い点を選ぶ (最寄り %.2f)" % nearest
	)


## ボットの全方針が間合いを守ること。ここが割れると、bot統計だけ至近スポーン
## 殴りが可能な別ゲームを測ることになる(実UI・CLIとの三面一致)。
func _test_policies_respect_standoff(check: Callable) -> void:
	var field := _field()
	var rng := RandomNumberGenerator.new()
	for kind in LaunchPolicy.NAMES:
		var violations := 0
		for i in 60:
			rng.seed = i * 7 + int(kind) * 1000
			var plans: Array[EnemySpawn.Plan] = [
				EnemySpawn.Plan.new(Vector2(8, 5), Vector2(-4, 0)),
				EnemySpawn.Plan.new(Vector2(5, 8), Vector2(0, -4)),
			]
			var radii := PackedFloat32Array([0.5, 0.9])
			var launch := LaunchPolicy.decide(kind, field, 0.7, plans, radii, rng)
			for j in plans.size():
				var req := LaunchStandoff.required_distance(0.7, radii[j], field.inradius())
				if launch.position.distance_to(plans[j].position) < req - EPS:
					violations += 1
		check.call(
			violations == 0,
			"発射方針 %s が間合いを守る (%d件違反)" % [LaunchPolicy.NAMES[kind], violations]
		)
