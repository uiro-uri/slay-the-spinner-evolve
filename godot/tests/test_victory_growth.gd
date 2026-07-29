extends RefCounted

## 勝利成長(SpinnerStats.grow_rps_by_victory)のテスト。
## 敵rpsは段と共に上がるのに自分の成長が引き運頼みだった問題への下支えなので、
## 「勝つたびに必ず増える」「上限を絶対に超えない」の2点を守る。

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_grows_by_constant(check)
	_test_knockout_grows_more(check)
	_test_knockout_scales_with_rps(check)
	_test_knockout_floor_below_breakeven(check)
	_test_passive_victory_does_not_scale(check)
	_test_returns_actual_gain(check)
	_test_knockout_caps_at_rps_cap(check)
	_test_caps_at_rps_cap(check)
	_test_stays_at_cap(check)
	_test_cap_single_source(check)


func _stats(rps: float) -> SpinnerStats:
	var s := SpinnerStats.default_player()
	s.rps = rps
	return s


func _test_grows_by_constant(check: Callable) -> void:
	var s := _stats(15.0)
	s.grow_rps_by_victory()
	check.call(
		absf(s.rps - (15.0 + SpinnerStats.VICTORY_RPS_GROWTH)) < EPS,
		"勝利成長: rpsがVICTORY_RPS_GROWTH(%.2f)ぶん増える (15.0→%.2f)" % [
			SpinnerStats.VICTORY_RPS_GROWTH, s.rps]
	)
	check.call(SpinnerStats.VICTORY_RPS_GROWTH > 0.0, "勝利成長: 成長量は正")
	# rps以外に触らないこと(質量などが巻き添えで変わると別のバランスが壊れる)
	var base := SpinnerStats.default_player()
	check.call(
		is_equal_approx(s.mass, base.mass) and is_equal_approx(s.radius, base.radius)
			and is_equal_approx(s.spin_decay, base.spin_decay),
		"勝利成長: rps以外のステータスは変わらない"
	)


func _test_knockout_grows_more(check: Callable) -> void:
	# 撃破ボーナス: 接触で仕留めた勝利(knockout=真)は受け身の勝利より大きく育つ。
	# 「弱発射で自然減衰を待つ」受け身戦法だけが最適にならないための差なので、
	# 増分そのものと「受け身より厳密に大きい」ことの両方を守る。
	var s := _stats(15.0)
	s.grow_rps_by_victory(true)
	check.call(
		absf(s.rps - (15.0 + SpinnerStats.KNOCKOUT_RPS_GROWTH)) < EPS,
		"撃破ボーナス: knockout勝利はKNOCKOUT_RPS_GROWTH(%.2f)ぶん増える (15.0→%.2f)" % [
			SpinnerStats.KNOCKOUT_RPS_GROWTH, s.rps]
	)
	check.call(
		SpinnerStats.KNOCKOUT_RPS_GROWTH > SpinnerStats.VICTORY_RPS_GROWTH,
		"撃破ボーナス: 接触で仕留めた勝利は受け身の勝利より大きく育つ"
	)


func _test_knockout_scales_with_rps(check: Callable) -> void:
	# 撃破ボーナスは現在rpsに比例する。+1.0固定はrpsが育つほど相対的に空気になり、
	# 後半ほど当てにいく理由が薄れる問題への手当て。rps30なら30×RATEぶん増える。
	var s := _stats(30.0)
	var gained := s.grow_rps_by_victory(true)
	check.call(
		absf(gained - 30.0 * SpinnerStats.KNOCKOUT_RPS_GROWTH_RATE) < EPS,
		"撃破ボーナス: rps30では30×RATE(%.2f)ぶん増える (+%.2f)" % [
			SpinnerStats.KNOCKOUT_RPS_GROWTH_RATE, gained]
	)
	# 比例部分が下限を上回るrps帯でも、受け身の勝利より厳密に大きいまま。
	check.call(
		gained > SpinnerStats.VICTORY_RPS_GROWTH,
		"撃破ボーナス: 高rpsでも受け身の勝利より大きく育つ (+%.2f)" % gained
	)


func _test_knockout_floor_below_breakeven(check: Callable) -> void:
	# 比例成長が下限(KNOCKOUT_RPS_GROWTH)を下回る低rps帯では下限が働く。
	# 序盤(rps15前後)の手触りを従来から変えないための床。
	var s := _stats(10.0)
	var gained := s.grow_rps_by_victory(true)
	check.call(
		absf(gained - SpinnerStats.KNOCKOUT_RPS_GROWTH) < EPS,
		"撃破ボーナス: 低rpsでは下限KNOCKOUT_RPS_GROWTH(%.2f)が働く (+%.2f)" % [
			SpinnerStats.KNOCKOUT_RPS_GROWTH, gained]
	)


func _test_passive_victory_does_not_scale(check: Callable) -> void:
	# 受け身の勝利(knockout=偽)は高rpsでも定数のまま。逃げ切りまで複利にすると
	# 「当てにいく方が報われる」という撃破ボーナスの存在意義が崩れる。
	var s := _stats(30.0)
	var gained := s.grow_rps_by_victory()
	check.call(
		absf(gained - SpinnerStats.VICTORY_RPS_GROWTH) < EPS,
		"勝利成長: 受け身の勝利は高rpsでも定数VICTORY_RPS_GROWTH(%.2f)のまま (+%.2f)" % [
			SpinnerStats.VICTORY_RPS_GROWTH, gained]
	)


func _test_returns_actual_gain(check: Callable) -> void:
	# 戻り値は「実際に増えた量」。上限をまたぐ成長では要求より小さくなる。
	# CLI・UIの表示が定数の受け売りでなく事実を出すために使う。
	var s := _stats(SpinnerStats.RPS_CAP - 0.2)
	var gained := s.grow_rps_by_victory(true)
	check.call(
		absf(gained - 0.2) < EPS,
		"撃破ボーナス: 戻り値は上限で頭打ちした実増加量 (+%.2f)" % gained
	)


func _test_knockout_caps_at_rps_cap(check: Callable) -> void:
	var s := _stats(SpinnerStats.RPS_CAP - SpinnerStats.KNOCKOUT_RPS_GROWTH * 0.5)
	s.grow_rps_by_victory(true)
	check.call(
		absf(s.rps - SpinnerStats.RPS_CAP) < EPS,
		"撃破ボーナス: 上限をまたぐ成長もRPS_CAP(%.1f)で止まる (%.2f)" % [SpinnerStats.RPS_CAP, s.rps]
	)


func _test_caps_at_rps_cap(check: Callable) -> void:
	var s := _stats(SpinnerStats.RPS_CAP - SpinnerStats.VICTORY_RPS_GROWTH * 0.5)
	s.grow_rps_by_victory()
	check.call(
		absf(s.rps - SpinnerStats.RPS_CAP) < EPS,
		"勝利成長: 上限をまたぐ成長はRPS_CAP(%.1f)で止まる (%.2f)" % [SpinnerStats.RPS_CAP, s.rps]
	)


func _test_stays_at_cap(check: Callable) -> void:
	var s := _stats(SpinnerStats.RPS_CAP)
	s.grow_rps_by_victory()
	check.call(
		s.rps <= SpinnerStats.RPS_CAP + EPS,
		"勝利成長: 上限到達後は増えない (%.2f)" % s.rps
	)


func _test_cap_single_source(check: Callable) -> void:
	# SPIN_ENGINE札の上限(CustomPartCatalog.RPS_CAP)と勝利成長の上限は同じ値を共有する。
	# 別々の値になると「札では40まで、成長では41まで」のような食い違いが起きる。
	check.call(
		is_equal_approx(CustomPartCatalog.RPS_CAP, SpinnerStats.RPS_CAP),
		"勝利成長: CustomPartCatalog.RPS_CAPはSpinnerStats.RPS_CAPと同値 (%.1f)" % CustomPartCatalog.RPS_CAP
	)
