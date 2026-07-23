extends RefCounted

## スパークの強弱表現のテスト。
##
## (1) SparkScale.scale_for 純関数: 無効弁(ref<=0)・√カーブ・単調性・クランプ。
## (2) リゾルバが Impact.strength に「その瞬間に実際に失われたrps」を記録する事実:
##     衝突は両者の合計、壁は1体の喪失で、内訳(lost_drain/lost_wall)と保存則で一致する。
##     激突ほど強度が大きい(壁の速度比例が強度に写る)ことも固定する。
## (3) dict往復で強度が保存され、旧3要素dictは強度1.0(=従来サイズ)で読める後方互換。

const EPS := 1e-3


func run(check: Callable) -> void:
	_test_scale_function(check)
	_test_collision_strength(check)
	_test_wall_strength(check)
	_test_serialization(check)


func _test_scale_function(check: Callable) -> void:
	check.call(
		absf(SparkScale.scale_for(99.0, 0.0, 0.4, 2.0) - 1.0) < EPS
			and absf(SparkScale.scale_for(0.0, 0.0, 0.4, 2.0) - 1.0) < EPS,
		"scale: ref_loss=0はスケール無効で常に1.0(旧固定サイズ)"
	)
	check.call(
		absf(SparkScale.scale_for(3.0, 3.0, 0.4, 2.0) - 1.0) < EPS,
		"scale: 喪失=基準で倍率1.0"
	)
	check.call(
		absf(SparkScale.scale_for(12.0, 3.0, 0.1, 10.0) - 2.0) < EPS,
		"scale: 4倍の喪失で半径2倍(面積4倍)の√カーブ"
	)
	check.call(
		absf(SparkScale.scale_for(0.0, 3.0, 0.4, 2.0) - 0.4) < EPS
			and absf(SparkScale.scale_for(-1.0, 3.0, 0.4, 2.0) - 0.4) < EPS,
		"scale: 喪失0以下は下限倍率"
	)
	check.call(
		absf(SparkScale.scale_for(1000.0, 3.0, 0.4, 2.0) - 2.0) < EPS,
		"scale: 巨大な喪失は上限でクランプ"
	)
	var prev := -1.0
	var monotonic := true
	for strength in [0.0, 0.5, 1.0, 3.0, 6.0, 12.0, 50.0]:
		var s := SparkScale.scale_for(strength, 3.0, 0.4, 2.0)
		if s < prev - EPS:
			monotonic = false
		prev = s
	check.call(monotonic, "scale: 喪失に対して単調非減少")


func _enemy_stats(rps: float) -> SpinnerStats:
	var s := SpinnerStats.new()
	s.mass = 1.0
	s.radius = 0.5
	s.friction = 0.0
	s.restitution = 1.0
	s.rps = rps
	return s


## 正面衝突環境(減衰・傾斜なし)。衝突スパークの強度の合計が、両者のlost_drainの
## 合計と一致する=強度が「実際に失われたrps」の事実であること。
func _test_collision_strength(check: Callable) -> void:
	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	r.player = BattleRequest.Launch.new(SpinnerStats.default_player(), Vector2(3, 5), Vector2(4, 0))
	r.enemies = [BattleRequest.Launch.new(_enemy_stats(0.2), Vector2(7, 5), Vector2(-4, 0))]
	var result := BattleResolver.resolve(r)

	check.call(result.impacts.size() >= 1, "衝突強度: 検証環境で衝突が起きている")
	var all_positive := true
	var total := 0.0
	for imp in result.impacts:
		if imp.strength <= 0.0:
			all_positive = false
		total += imp.strength
	check.call(all_positive, "衝突強度: 全ての衝突スパークの強度が正")
	var drains: float = (
		float(result.player_rps_loss.get("drain", 0.0))
		+ float(result.enemy_rps_loss[0].get("drain", 0.0))
	)
	check.call(
		absf(total - drains) < EPS,
		"衝突強度: 強度の合計=両者の削り喪失の合計 (%.3f vs %.3f)" % [total, drains]
	)


## 壁往復環境(接触なし)。壁スパークの強度の合計がプレイヤーのlost_wallと一致し、
## 進入速度が速いほど1発目の強度が大きい(速度比例の自傷が強度に写る)。
func _test_wall_strength(check: Callable) -> void:
	var slow := _wall_run(4.0)
	var fast := _wall_run(12.0)

	check.call(
		not fast.wall_impacts.is_empty() and not slow.wall_impacts.is_empty(),
		"壁強度: 検証環境で壁バウンドが起きている"
	)
	var total := 0.0
	for imp in fast.wall_impacts:
		total += imp.strength
	check.call(
		absf(total - float(fast.player_rps_loss.get("wall", 0.0))) < EPS,
		"壁強度: 強度の合計=壁喪失の合計(敵は壁に触れない環境)"
	)
	check.call(
		fast.wall_impacts[0].strength > slow.wall_impacts[0].strength + EPS,
		"壁強度: 速い激突ほど強度が大きい (%.3f > %.3f)"
			% [fast.wall_impacts[0].strength, slow.wall_impacts[0].strength]
	)


func _wall_run(speed: float) -> BattleResult:
	var pstats := SpinnerStats.default_player()
	pstats.friction = 0.0
	pstats.restitution = 1.0
	var r := BattleRequest.new()
	r.stage_strength = 0.0
	r.natural_damping = 0.1
	r.player = BattleRequest.Launch.new(pstats, Vector2(5, 5), Vector2(speed, 0))
	r.enemies = [BattleRequest.Launch.new(_enemy_stats(0.5), Vector2(8, 9), Vector2.ZERO)]
	return BattleResolver.resolve(r)


## dict往復で強度が保存されること。旧dict(3要素)は強度1.0で読める後方互換。
func _test_serialization(check: Callable) -> void:
	var result := BattleResult.new()
	result.impacts = [BattleResult.Impact.new(0.5, Vector2(1, 2), 7.5)]
	result.wall_impacts = [BattleResult.Impact.new(0.7, Vector2(3, 4), 2.25)]
	var revived := BattleResult.from_dict(JSON.parse_string(JSON.stringify(result.to_dict())))
	check.call(
		absf(revived.impacts[0].strength - 7.5) < EPS
			and absf(revived.wall_impacts[0].strength - 2.25) < EPS,
		"往復: 衝突・壁とも強度がJSON往復で保存される"
	)

	var old_dict := result.to_dict()
	old_dict["impacts"] = [[0.5, 1.0, 2.0]]
	old_dict["wall_impacts"] = [[0.7, 3.0, 4.0]]
	var old := BattleResult.from_dict(old_dict)
	check.call(
		absf(old.impacts[0].strength - 1.0) < EPS
			and absf(old.wall_impacts[0].strength - 1.0) < EPS,
		"往復: 強度の無い旧dictは1.0(従来サイズ)で読める(後方互換)"
	)
	check.call(
		old.impacts[0].point.is_equal_approx(Vector2(1, 2)),
		"往復: 旧dictでも時刻と接触点は従来どおり読める"
	)
