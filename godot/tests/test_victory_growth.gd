extends RefCounted

## 勝利成長(SpinnerStats.grow_rps_by_victory)のテスト。
## 敵rpsは段と共に上がるのに自分の成長が引き運頼みだった問題への下支えなので、
## 「勝つたびに必ず増える」「上限を絶対に超えない」の2点を守る。

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_grows_by_constant(check)
	_test_knockout_grows_more(check)
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
