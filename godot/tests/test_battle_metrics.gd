extends RefCounted

## BattleMetrics.classify(死因の軌跡推定)がコマ自身の実効値で照合することのテスト。
##
## リゾルバは自然減衰に spin_decay 倍率(MOMENTUM札)、壁に wall_keep(RAGE札)を
## 掛けるが、classify が土俵の素の値で署名照合すると、これらの札を持つコマの
## 減衰・壁イベントがすべて "drain"(衝突削り)に誤分類される。実際にコールドプレイで
## 「衝突2回なのに hits_taken=8、死因drain(実際はdecay)」という嘘の読み出しが出て、
## 敗因分析の一次証拠が壊れた。ここでは他の死因が起こり得ない理想環境を組み、
## 推定(classify)がリゾルバの記録した事実(loser_death_cause)と一致することを固定する。


func run(check: Callable) -> void:
	_test_momentum_decay_death(check)
	_test_rage_wall_death(check)
	_test_default_drain_death(check)


## spin_decay<1 のプレイヤーが接触ゼロで自然減衰死 → 死因は decay、被弾は 0。
## 照合が spin_decay を無視すると全フレームが drain に化ける。
func _test_momentum_decay_death(check: Callable) -> void:
	var pstats := SpinnerStats.default_player()
	pstats.rps = 0.5
	pstats.spin_decay = 0.5
	var estats := SpinnerStats.new()
	estats.radius = 0.5
	estats.rps = 20.0
	var r := BattleRequest.new()
	r.stage_strength = 0.0
	r.player = BattleRequest.Launch.new(pstats, Vector2(2, 5), Vector2.ZERO)
	r.enemies = [BattleRequest.Launch.new(estats, Vector2(8, 5), Vector2.ZERO)]
	var result := BattleResolver.resolve(r)
	var m := BattleMetrics.classify(r, result)

	check.call(not result.player_won(), "momentum減衰死: 接触せずプレイヤーが先に尽きる")
	check.call(result.impacts.is_empty(), "momentum減衰死: 検証環境で衝突が起きていない")
	check.call(
		m.get("death_cause") == "decay",
		"momentum減衰死: spin_decay持ちの自然減衰死がdecayと推定される (%s)" % str(m.get("death_cause"))
	)
	check.call(
		int(m.get("hits_taken", -1)) == 0,
		"momentum減衰死: 接触ゼロなら被弾も0 (%s)" % str(m.get("hits_taken"))
	)
	check.call(
		m.get("death_cause") == result.loser_death_cause,
		"momentum減衰死: 推定がリゾルバの記録と一致する (%s / %s)"
			% [str(m.get("death_cause")), result.loser_death_cause]
	)


## wall_keep>0 のプレイヤーが壁バウンドだけでrpsを失って死ぬ → 死因は wall、被弾は 0。
## 照合が wall_keep を無視すると壁の乗算が drain に化ける。
func _test_rage_wall_death(check: Callable) -> void:
	var pstats := SpinnerStats.new()
	pstats.mass = 1.5
	pstats.radius = 0.7
	pstats.friction = 0.0
	pstats.restitution = 1.0
	pstats.rps = 1.0
	pstats.wall_keep = 0.4
	var estats := SpinnerStats.new()
	estats.radius = 0.5
	estats.rps = 20.0
	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	r.player = BattleRequest.Launch.new(pstats, Vector2(5, 5), Vector2(12, 0))
	r.enemies = [BattleRequest.Launch.new(estats, Vector2(2, 2), Vector2.ZERO)]
	var result := BattleResolver.resolve(r)
	var m := BattleMetrics.classify(r, result)

	check.call(not result.player_won(), "rage壁死: 壁の減衰でプレイヤーが尽きる")
	check.call(result.impacts.is_empty(), "rage壁死: 検証環境でコマ同士の衝突が起きていない")
	check.call(result.wall_impacts.size() >= 1, "rage壁死: 検証環境で壁衝突が起きている")
	check.call(
		m.get("death_cause") == "wall",
		"rage壁死: wall_keep持ちの壁死がwallと推定される (%s)" % str(m.get("death_cause"))
	)
	check.call(
		int(m.get("hits_taken", -1)) == 0,
		"rage壁死: コマ衝突ゼロなら被弾も0 (%s)" % str(m.get("hits_taken"))
	)
	check.call(
		int(m.get("wall_hits", 0)) >= 1,
		"rage壁死: 壁ヒットが数えられている (%s)" % str(m.get("wall_hits"))
	)


## 札なし(既定値)の削り死は従来どおり drain と推定される(回帰)。
func _test_default_drain_death(check: Callable) -> void:
	var pstats := SpinnerStats.default_player()
	pstats.rps = 0.2
	var estats := SpinnerStats.new()
	estats.radius = 0.5
	estats.friction = 0.0
	estats.restitution = 1.0
	estats.rps = 15.0
	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	r.player = BattleRequest.Launch.new(pstats, Vector2(3, 5), Vector2(4, 0))
	r.enemies = [BattleRequest.Launch.new(estats, Vector2(7, 5), Vector2(-4, 0))]
	var result := BattleResolver.resolve(r)
	var m := BattleMetrics.classify(r, result)

	check.call(not result.player_won(), "既定drain死: プレイヤーが削り殺される")
	check.call(
		m.get("death_cause") == "drain",
		"既定drain死: 札なしの削り死がdrainと推定される (%s)" % str(m.get("death_cause"))
	)
	check.call(
		int(m.get("hits_taken", 0)) >= 1,
		"既定drain死: 被弾が数えられている (%s)" % str(m.get("hits_taken"))
	)
