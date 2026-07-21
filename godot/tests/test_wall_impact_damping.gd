extends RefCounted

## 壁の回転喪失の衝突激しさ比例(impact_scaled_wall_damping)のテスト。
##
## 従来は壁に触れるたび一律 wall_damping 倍(0.75なら25%喪失)で、そっと縁を擦る
## 接触と全力の激突が同じ代償だった。ここで固定するのは:
##  - 純関数の向き: 進入速度が遅いほど無損失(1.0)へ近づき、ref_speed以上でbase
##  - ref_speed<=0 でスケール無効=旧挙動と厳密一致(古い保存データの再現)
##  - リゾルバが実際に進入速度で損失を変えること(1回衝突の理想環境で)
##  - wall_keep(RAGE札)がスケール後の損失にも同じ比率で効くこと
##  - シリアライズ往復と、キーの無い旧データの既定0(=旧挙動)
##  - BattleMetricsがスケール後の壁死を"drain"に誤分類しないこと

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_scaling_function(check)
	_test_resolver_scales_wall_loss(check)
	_test_wall_keep_applies_after_scaling(check)
	_test_serialization(check)
	_test_metrics_classifies_scaled_wall_death(check)


func _test_scaling_function(check: Callable) -> void:
	check.call(
		absf(SpinnerPhysics.impact_scaled_wall_damping(0.75, 3.0, 0.0) - 0.75) < EPS,
		"impact_scaled: ref_speed=0はスケール無効で常にbase(旧挙動)"
	)
	check.call(
		absf(SpinnerPhysics.impact_scaled_wall_damping(0.75, 0.0, 12.0) - 1.0) < EPS,
		"impact_scaled: 進入速度0なら無損失(1.0)"
	)
	check.call(
		absf(SpinnerPhysics.impact_scaled_wall_damping(0.75, 12.0, 12.0) - 0.75) < EPS,
		"impact_scaled: 基準速度ちょうどの激突でbaseそのまま"
	)
	check.call(
		absf(SpinnerPhysics.impact_scaled_wall_damping(0.75, 40.0, 12.0) - 0.75) < EPS,
		"impact_scaled: 基準超の激突もbaseで頭打ち(それ以上ひどくならない)"
	)
	check.call(
		absf(SpinnerPhysics.impact_scaled_wall_damping(0.75, 6.0, 12.0) - 0.875) < EPS,
		"impact_scaled: 半分の速度なら損失も半分(線形)"
	)
	# 単調性: 速い衝突ほど残る回転(係数)が小さい。
	var prev := 2.0
	for speed in [0.0, 2.0, 4.0, 8.0, 12.0]:
		var damping := SpinnerPhysics.impact_scaled_wall_damping(0.75, speed, 12.0)
		check.call(
			damping < prev + EPS,
			"impact_scaled: 単調性 speed=%s で係数が増えない" % str(speed)
		)
		prev = damping


## 壁へ1回だけぶつかる理想環境。自然減衰・傾斜を切るので、rpsの減少は壁だけ。
## 敵は遠くに静止させて接触させない。
func _one_wall_hit_request(launch_speed: float, ref_speed: float, wall_keep: float) -> BattleRequest:
	var pstats := SpinnerStats.default_player()
	pstats.wall_keep = wall_keep
	var estats := SpinnerStats.new()
	estats.radius = 0.5
	estats.rps = 20.0

	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	r.wall_impact_ref_speed = ref_speed
	r.max_duration = 0.5
	# 下の壁(y=0)へ一直線。半径0.7なので0.8進むと接触する。
	r.player = BattleRequest.Launch.new(pstats, Vector2(5, 1.5), Vector2(0, -launch_speed))
	r.enemies = [BattleRequest.Launch.new(estats, Vector2(8, 8), Vector2.ZERO)]
	return r


func _test_resolver_scales_wall_loss(check: Callable) -> void:
	var initial := SpinnerStats.default_player().rps
	var fast := BattleResolver.resolve(_one_wall_hit_request(20.0, 12.0, 0.0))
	var slow := BattleResolver.resolve(_one_wall_hit_request(3.0, 12.0, 0.0))
	var slow_unscaled := BattleResolver.resolve(_one_wall_hit_request(3.0, 0.0, 0.0))

	check.call(
		int(fast.player_rps_loss.get("wall_hits", 0)) == 1
			and int(slow.player_rps_loss.get("wall_hits", 0)) == 1,
		"リゾルバ: 検証環境で壁ヒットがちょうど1回ずつ"
	)
	var fast_loss: float = fast.player_rps_loss.get("wall", 0.0)
	var slow_loss: float = slow.player_rps_loss.get("wall", 0.0)
	check.call(
		absf(fast_loss - initial * 0.25) < EPS,
		"リゾルバ: 基準速度以上の激突は従来どおり25%%喪失 (%.4f)" % fast_loss
	)
	check.call(
		slow_loss > EPS and slow_loss < fast_loss * 0.5,
		"リゾルバ: 遅い接触の喪失は激突よりはっきり小さい (%.4f < %.4f/2)" % [slow_loss, fast_loss]
	)
	var unscaled_loss: float = slow_unscaled.player_rps_loss.get("wall", 0.0)
	check.call(
		absf(unscaled_loss - initial * 0.25) < EPS,
		"リゾルバ: ref_speed=0なら遅い接触でも旧挙動の25%%喪失 (%.4f)" % unscaled_loss
	)


func _test_wall_keep_applies_after_scaling(check: Callable) -> void:
	var bare := BattleResolver.resolve(_one_wall_hit_request(6.0, 12.0, 0.0))
	var kept := BattleResolver.resolve(_one_wall_hit_request(6.0, 12.0, 0.5))
	var bare_loss: float = bare.player_rps_loss.get("wall", 0.0)
	var kept_loss: float = kept.player_rps_loss.get("wall", 0.0)
	check.call(
		bare_loss > EPS,
		"wall_keep連携: スケール後も損失自体は残っている"
	)
	check.call(
		absf(kept_loss - bare_loss * 0.5) < EPS,
		"wall_keep連携: RAGE札はスケール後の損失を同じ比率で軽減する (%.4f ≒ %.4f/2)"
			% [kept_loss, bare_loss]
	)


func _test_serialization(check: Callable) -> void:
	var r := _one_wall_hit_request(6.0, 7.5, 0.0)
	var round_trip := BattleRequest.from_dict(r.to_dict())
	check.call(
		absf(round_trip.wall_impact_ref_speed - 7.5) < EPS,
		"シリアライズ: wall_impact_ref_speedが往復で保存される"
	)
	var legacy := r.to_dict()
	legacy.erase("wall_impact_ref_speed")
	check.call(
		absf(BattleRequest.from_dict(legacy).wall_impact_ref_speed) < EPS,
		"シリアライズ: キーの無い旧データは0(スケール無効=旧挙動)で補われる"
	)


## 基準未満の速度の壁バウンドだけで死ぬ環境。壁損失が0.75^nの固定署名でなくなった
## 後も、BattleMetricsが壁死をdrain(衝突削り)へ誤分類しないことを固定する。
func _test_metrics_classifies_scaled_wall_death(check: Callable) -> void:
	var pstats := SpinnerStats.new()
	pstats.mass = 1.5
	pstats.radius = 0.7
	pstats.friction = 0.0
	pstats.restitution = 1.0
	pstats.rps = 1.0
	var estats := SpinnerStats.new()
	estats.radius = 0.5
	estats.rps = 20.0

	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	r.wall_impact_ref_speed = 12.0
	# 速度6=基準の半分。壁1回あたり12.5%喪失を左右の壁で繰り返して死ぬ。
	r.player = BattleRequest.Launch.new(pstats, Vector2(5, 5), Vector2(6, 0))
	r.enemies = [BattleRequest.Launch.new(estats, Vector2(8, 2), Vector2.ZERO)]
	var result := BattleResolver.resolve(r)
	var m := BattleMetrics.classify(r, result)

	check.call(not result.player_won(), "metrics壁死: 壁の減衰でプレイヤーが尽きる")
	check.call(result.impacts.is_empty(), "metrics壁死: コマ同士の衝突が起きていない")
	check.call(
		m.get("death_cause") == "wall",
		"metrics壁死: スケール後の壁死がwallと推定される (%s)" % str(m.get("death_cause"))
	)
	check.call(
		int(m.get("hits_taken", -1)) == 0,
		"metrics壁死: コマ衝突ゼロなら被弾も0 (%s)" % str(m.get("hits_taken"))
	)
	check.call(
		int(m.get("wall_hits", 0)) == int(result.player_rps_loss.get("wall_hits", -1)),
		"metrics壁死: 壁ヒット数が記録された事実と一致する (%s / %s)"
			% [str(m.get("wall_hits")), str(result.player_rps_loss.get("wall_hits"))]
	)
