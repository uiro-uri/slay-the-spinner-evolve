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
	_test_fact_over_signature(check)
	_test_signature_fallback_for_old_result(check)


## 支配的死因と最後の一滴がずれる戦い(強打で大半を削り、残りを減衰が落とす)では、
## 署名照合(最後の一滴=decay)でなくリゾルバの記録した事実(drain)が優先される。
## これが無いとレポートの死因内訳が壁・削りの寄与を隠す(死因分類の壁過小計上)。
func _mismatch_request() -> BattleRequest:
	var r := BattleRequest.new()
	r.stage_strength = 0.0
	# 「大半を削られた敵が一瞬生き延び、最後の一滴は自然減衰」という配分そのものが
	# 筋書きなので、削り/減衰の比を既定値の調整に委ねずこの場で固定する。
	r.violence = 0.07
	r.natural_damping = 0.75
	# 同じ理由で1撃の削りを切る天井も外す(「強打で大半を削る」が筋書きの前提)。
	r.drain_cap_share = 0.0
	var estats := SpinnerStats.new()
	estats.mass = 1.0
	estats.radius = 0.5
	estats.friction = 3.0
	estats.restitution = 1.0
	estats.rps = 3.0
	r.player = BattleRequest.Launch.new(SpinnerStats.default_player(), Vector2(3, 5), Vector2(6, 0))
	r.enemies = [BattleRequest.Launch.new(estats, Vector2(5.5, 5), Vector2.ZERO)]
	return r


func _test_fact_over_signature(check: Callable) -> void:
	var r := _mismatch_request()
	var result := BattleResolver.resolve(r)
	var m := BattleMetrics.classify(r, result)

	check.call(result.player_won(), "事実優先: プレイヤーが勝つ")
	check.call(
		result.loser_death_cause == "drain",
		"事実優先: リゾルバは支配的なdrainを記録している (%s)" % result.loser_death_cause
	)
	check.call(
		m.get("death_cause") == "drain",
		"事実優先: classifyが署名(最後の一滴=decay)でなく事実のdrainを返す (%s)"
			% str(m.get("death_cause"))
	)
	check.call(
		m.get("death_cause") == result.loser_death_cause,
		"事実優先: 推定とリゾルバの記録が一致する (%s / %s)"
			% [str(m.get("death_cause")), result.loser_death_cause]
	)


## 停止事実キーの無い旧結果(dict往復で欠落)では従来の署名照合に落ちる(後方互換)。
func _test_signature_fallback_for_old_result(check: Callable) -> void:
	var r := _mismatch_request()
	# 署名照合は「壁の喪失は現在rpsの割合」を前提にした旧経路なので、絶対量への
	# 寄せは切って当時の環境で読ませる(絶対量が乗ると値では切り分けられない)。
	r.wall_absolute_share = 0.0
	var d := BattleResolver.resolve(r).to_dict()
	d.erase("player_death")
	d.erase("enemy_deaths")
	var old := BattleResult.from_dict(d)
	var m := BattleMetrics.classify(r, old)

	check.call(
		m.get("death_cause") == "decay",
		"旧結果互換: 事実が無ければ署名照合(最後の一滴=decay)で読める (%s)"
			% str(m.get("death_cause"))
	)


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
