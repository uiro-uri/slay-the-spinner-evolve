extends RefCounted

## 衝突削りの噛み合い床(bite_floor_speed / SpinnerPhysics.bitten_speed)のテスト。
##
## 長引いた戦いは摩擦・非弾性衝突で速度が沈み、低速の微衝突の応酬(泥仕合)になる。
## 削りは相手の速さに比例するため微衝突はほぼ何も生まず、決着が壁・自然減衰任せに
## なっていた。床は「遅い接触でも最低限噛み合う」ようにする。ここで固定するのは:
##  - 純関数の向き: 床未満の速さは床へ引き上げ、床以上は実速度のまま
##  - floor<=0 で床なし=旧挙動と厳密一致(古い保存データの再現)
##  - リゾルバが実際に床を削りに使うこと(低速1回衝突の理想環境で、両者とも)
##  - 高速の衝突は床の影響を受けないこと
##  - シリアライズ往復と、キーの無い旧データの既定0(=旧挙動)

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_floor_function(check)
	_test_resolver_applies_floor(check)
	_test_fast_collision_unaffected(check)
	_test_serialization(check)


func _test_floor_function(check: Callable) -> void:
	check.call(
		absf(SpinnerPhysics.bitten_speed(0.5, 0.0) - 0.5) < EPS,
		"bitten_speed: floor=0は床なしで実速度のまま(旧挙動)"
	)
	check.call(
		absf(SpinnerPhysics.bitten_speed(0.5, -3.0) - 0.5) < EPS,
		"bitten_speed: 負のfloorも床なし扱い"
	)
	check.call(
		absf(SpinnerPhysics.bitten_speed(0.5, 4.0) - 4.0) < EPS,
		"bitten_speed: 床未満の速さは床へ引き上げ"
	)
	check.call(
		absf(SpinnerPhysics.bitten_speed(9.0, 4.0) - 9.0) < EPS,
		"bitten_speed: 床以上の速さはそのまま"
	)
	check.call(
		absf(SpinnerPhysics.bitten_speed(0.0, 4.0) - 4.0) < EPS,
		"bitten_speed: 静止していても床ぶんは噛み合う"
	)


## 低速の正面衝突が1回だけ起きる理想環境。摩擦・傾斜・自然減衰を切るので、
## rpsの減少は衝突削りだけ。壁は遠く、速度が遅いので届かない。
func _slow_collision_request(floor_speed: float) -> BattleRequest:
	var req := BattleRequest.new()
	req.arena_bounds = Rect2(0, 0, 100, 100)
	req.stage_strength = 0.0
	req.natural_damping = 0.0
	req.bite_floor_speed = floor_speed
	req.max_duration = 3.0

	var pstats := SpinnerStats.new()
	pstats.mass = 1.5
	pstats.radius = 0.5
	pstats.friction = 0.0
	pstats.restitution = 1.0
	pstats.rps = 20.0
	var estats := SpinnerStats.new()
	estats.mass = 1.5
	estats.radius = 0.5
	estats.friction = 0.0
	estats.restitution = 1.0
	estats.rps = 20.0

	# 中央で0.5ずつの速さの正面衝突。相対1.0でも床(既定4.0)より遅い。
	req.player = BattleRequest.Launch.new(pstats, Vector2(48.0, 50.0), Vector2(0.5, 0.0))
	var launches: Array[BattleRequest.Launch] = []
	launches.append(BattleRequest.Launch.new(estats, Vector2(52.0, 50.0), Vector2(-0.5, 0.0)))
	req.enemies = launches
	return req


func _test_resolver_applies_floor(check: Callable) -> void:
	var bare := BattleResolver.resolve(_slow_collision_request(0.0))
	var floored := BattleResolver.resolve(_slow_collision_request(4.0))
	check.call(bare.impacts.size() == 1, "床なし: 衝突がちょうど1回起きる")
	check.call(floored.impacts.size() == 1, "床あり: 衝突がちょうど1回起きる")

	# 期待値は式から手組みする。対称な2体なので両者同じ削りを受ける。
	# drain = violence × (相手質量×相手の実効速さ) / (自質量×自半径²)
	var req := _slow_collision_request(0.0)
	var expected_bare := SpinnerPhysics.spin_drain(1.5, 0.5, 1.5, 0.5, req.violence)
	var expected_floored := SpinnerPhysics.spin_drain(1.5, 4.0, 1.5, 0.5, req.violence)
	check.call(
		absf(bare.player_rps_loss["drain"] - expected_bare) < EPS,
		"床なし: 削りは実速度0.5ぶん(旧挙動)"
	)
	check.call(
		absf(floored.player_rps_loss["drain"] - expected_floored) < EPS,
		"床あり: 自分の削りが床速度4.0ぶんに引き上がる"
	)
	check.call(
		absf(floored.enemy_rps_loss[0]["drain"] - expected_floored) < EPS,
		"床あり: 敵の削りも床速度4.0ぶんに引き上がる"
	)
	check.call(
		floored.player_rps_loss["drain"] > bare.player_rps_loss["drain"] + EPS,
		"床あり: 低速の接触でも床なしより確かに削れる"
	)


func _test_fast_collision_unaffected(check: Callable) -> void:
	# 床(4.0)より速い正面衝突は床の影響を受けない。
	var bare_req := _slow_collision_request(0.0)
	bare_req.player.velocity = Vector2(6.0, 0.0)
	bare_req.enemies[0].velocity = Vector2(-6.0, 0.0)
	var floored_req := _slow_collision_request(4.0)
	floored_req.player.velocity = Vector2(6.0, 0.0)
	floored_req.enemies[0].velocity = Vector2(-6.0, 0.0)
	var bare := BattleResolver.resolve(bare_req)
	var floored := BattleResolver.resolve(floored_req)
	check.call(
		absf(floored.player_rps_loss["drain"] - bare.player_rps_loss["drain"]) < EPS,
		"床より速い衝突の削りは床の有無で変わらない"
	)


func _test_serialization(check: Callable) -> void:
	var req := _slow_collision_request(2.5)
	var round_trip := BattleRequest.from_dict(req.to_dict())
	check.call(
		absf(round_trip.bite_floor_speed - 2.5) < EPS,
		"bite_floor_speed がdict往復で保存される"
	)
	var before := BattleResolver.resolve(req)
	var after := BattleResolver.resolve(round_trip)
	check.call(
		absf(before.player_rps_loss["drain"] - after.player_rps_loss["drain"]) < EPS,
		"dict往復で削り結果が変わらない"
	)

	var legacy := req.to_dict()
	legacy.erase("bite_floor_speed")
	check.call(
		absf(BattleRequest.from_dict(legacy).bite_floor_speed) < EPS,
		"キーの無い旧dictは床なし(0)で読む=当時の結果を再現"
	)
