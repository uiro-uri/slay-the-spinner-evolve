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
	_test_overflow_extends_longevity(check)
	_test_overflow_partial_crossing(check)
	_test_overflow_floor(check)
	_test_passive_no_overflow(check)
	_test_below_cap_no_overflow(check)
	_test_overflow_floor_single_source(check)
	_test_margin_factor_monotone(check)
	_test_margin_unknown_is_neutral(check)
	_test_margin_scales_knockout(check)
	_test_margin_does_not_touch_passive(check)
	_test_narrow_knockout_still_beats_passive(check)
	_test_margin_from_result_frames(check)
	_test_margin_wiring(check)


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


func _test_overflow_extends_longevity(check: Callable) -> void:
	# 余勢転化: 上限で堰き止められた撃破ボーナスの余りはspin_decayの低下=寿命へ。
	# 寿命目安はrps/(radius×spin_decay)なので、「堰き止められたrpsが入っていた場合」と
	# 厳密に同じだけ寿命が伸びることが転化率の定義。
	var s := _stats(SpinnerStats.RPS_CAP)
	var decay_before := s.spin_decay
	var gained := s.grow_rps_by_victory(true)
	var requested := maxf(
		SpinnerStats.KNOCKOUT_RPS_GROWTH,
		SpinnerStats.RPS_CAP * SpinnerStats.KNOCKOUT_RPS_GROWTH_RATE
	)
	check.call(gained < EPS, "余勢転化: rpsは上限のまま増えない (+%.2f)" % gained)
	check.call(
		s.spin_decay < decay_before - EPS,
		"余勢転化: 上限での撃破勝利はspin_decayが下がる (%.3f→%.3f)" % [decay_before, s.spin_decay]
	)
	var lifespan_after := s.rps / (s.radius * s.spin_decay)
	var lifespan_equiv := (SpinnerStats.RPS_CAP + requested) / (s.radius * decay_before)
	check.call(
		absf(lifespan_after - lifespan_equiv) < 1e-3,
		"余勢転化: 寿命目安の伸びが堰き止められたrpsぶんと等価 (%.2f vs %.2f)" % [
			lifespan_after, lifespan_equiv]
	)


func _test_overflow_partial_crossing(check: Callable) -> void:
	# 上限をまたぐ勝利: 入り切ったぶんはrpsへ、余りだけがspin_decayへ。
	var s := _stats(SpinnerStats.RPS_CAP - 0.5)
	var decay_before := s.spin_decay
	var gained := s.grow_rps_by_victory(true)
	var requested := maxf(
		SpinnerStats.KNOCKOUT_RPS_GROWTH,
		(SpinnerStats.RPS_CAP - 0.5) * SpinnerStats.KNOCKOUT_RPS_GROWTH_RATE
	)
	var overflow := requested - 0.5
	check.call(absf(gained - 0.5) < EPS, "余勢転化: またぎの実増加は上限まで (+%.2f)" % gained)
	check.call(
		absf(s.spin_decay - decay_before * SpinnerStats.RPS_CAP / (SpinnerStats.RPS_CAP + overflow)) < EPS,
		"余勢転化: 余りぶんだけspin_decayが下がる (%.4f)" % s.spin_decay
	)


func _test_overflow_floor(check: Callable) -> void:
	# 転化の床: spin_decayはOVERFLOW_DECAY_FLOORより下がらない(無限に回るコマを防ぐ)。
	var s := _stats(SpinnerStats.RPS_CAP)
	s.spin_decay = SpinnerStats.OVERFLOW_DECAY_FLOOR + 0.001
	s.grow_rps_by_victory(true)
	check.call(
		absf(s.spin_decay - SpinnerStats.OVERFLOW_DECAY_FLOOR) < EPS,
		"余勢転化: 床の直前からは床ちょうどで止まる (%.4f)" % s.spin_decay
	)
	s.grow_rps_by_victory(true)
	check.call(
		s.spin_decay >= SpinnerStats.OVERFLOW_DECAY_FLOOR - EPS,
		"余勢転化: 床に達したら何度勝っても割らない (%.4f)" % s.spin_decay
	)


func _test_passive_no_overflow(check: Callable) -> void:
	# 受け身の勝ち(knockout=偽)は上限でも転化しない。上限後こそ「当てにいく方が
	# 報われる」差を付けたい場面だから(撃破ボーナスの存在意義)。
	var s := _stats(SpinnerStats.RPS_CAP)
	var decay_before := s.spin_decay
	s.grow_rps_by_victory()
	check.call(
		is_equal_approx(s.spin_decay, decay_before),
		"余勢転化: 受け身の勝利はspin_decayに触らない (%.3f)" % s.spin_decay
	)


func _test_below_cap_no_overflow(check: Callable) -> void:
	# 上限に届かない成長は全額rpsへ入り、spin_decayには触らない(従来と厳密一致)。
	var s := _stats(20.0)
	var decay_before := s.spin_decay
	s.grow_rps_by_victory(true)
	check.call(
		is_equal_approx(s.spin_decay, decay_before),
		"余勢転化: 上限未満の勝利はspin_decayに触らない (%.3f)" % s.spin_decay
	)


func _test_overflow_floor_single_source(check: Callable) -> void:
	# 転化の床はMOMENTUM札の床(CustomPartCatalog.FULL_STEAM_FLOOR)と同じ値を共有する。
	# 別々の値になると「札では0.4まで、転化では0.3まで」のような食い違いが起きる。
	check.call(
		is_equal_approx(SpinnerStats.OVERFLOW_DECAY_FLOOR, CustomPartCatalog.FULL_STEAM_FLOOR),
		"余勢転化: OVERFLOW_DECAY_FLOORはFULL_STEAM_FLOORと同値 (%.2f)" % SpinnerStats.OVERFLOW_DECAY_FLOOR
	)


func _test_margin_factor_monotone(check: Callable) -> void:
	# 余力係数: 残量が多いほど大きく、両端は定数そのもの。範囲外は端で頭打ち
	# (相打ちの丸め誤差で負の残量が来ても下端を割らない)。
	check.call(
		absf(SpinnerStats.knockout_margin_factor(0.0) - SpinnerStats.KNOCKOUT_MARGIN_MIN) < EPS,
		"余力係数: 残り0%%は下端 (%.3f)" % SpinnerStats.knockout_margin_factor(0.0)
	)
	check.call(
		absf(SpinnerStats.knockout_margin_factor(1.0) - SpinnerStats.KNOCKOUT_MARGIN_MAX) < EPS,
		"余力係数: 残り100%%は上端 (%.3f)" % SpinnerStats.knockout_margin_factor(1.0)
	)
	var prev := -1.0
	for i in 11:
		var f := SpinnerStats.knockout_margin_factor(float(i) / 10.0)
		check.call(f > prev, "余力係数: 残り%d%%で単調に増える (%.3f)" % [i * 10, f])
		prev = f
	check.call(
		absf(SpinnerStats.knockout_margin_factor(2.0) - SpinnerStats.KNOCKOUT_MARGIN_MAX) < EPS
			and absf(SpinnerStats.knockout_margin_factor(0.0)
				- SpinnerStats.knockout_margin_factor(-0.0)) < EPS,
		"余力係数: 1を超える残量は上端で頭打ち"
	)
	# 下端は1未満・上端は1超。片側だけだと「快勝で伸びる」か「辛勝で縮む」の
	# 一方しか起きず、平均が従来からずれる。
	check.call(
		SpinnerStats.KNOCKOUT_MARGIN_MIN < 1.0 and SpinnerStats.KNOCKOUT_MARGIN_MAX > 1.0,
		"余力係数: 1.0をまたぐ(辛勝は縮み・快勝は伸びる)"
	)


func _test_margin_unknown_is_neutral(check: Callable) -> void:
	# 余力が分からない(負)なら係数1.0＝従来の成長と厳密に一致する。フレームを
	# 持たない旧dictの結果や、成長だけを直接呼ぶ経路が壊れないための互換。
	check.call(
		absf(SpinnerStats.knockout_margin_factor(-1.0) - 1.0) < EPS,
		"余力係数: 不明(-1)は1.0"
	)
	var unknown := _stats(24.0)
	var omitted := _stats(24.0)
	var g_unknown := unknown.grow_rps_by_victory(true, -1.0)
	var g_omitted := omitted.grow_rps_by_victory(true)
	check.call(
		absf(g_unknown - g_omitted) < EPS
			and absf(g_unknown - 24.0 * SpinnerStats.KNOCKOUT_RPS_GROWTH_RATE) < EPS,
		"余力不明: 省略時と同じ＝従来の比例成長そのまま (+%.3f)" % g_unknown
	)


func _test_margin_scales_knockout(check: Callable) -> void:
	# 撃破ボーナスは余力で伸び縮みする。同じrps・同じ撃破でも、快勝は辛勝より
	# 厳密に大きく育つ——これが今回の変更の本体。
	var narrow := _stats(30.0)
	var mid := _stats(30.0)
	var clean := _stats(30.0)
	var g_narrow := narrow.grow_rps_by_victory(true, 0.0)
	var g_mid := mid.grow_rps_by_victory(true, 0.5)
	var g_clean := clean.grow_rps_by_victory(true, 1.0)
	check.call(
		g_narrow < g_mid and g_mid < g_clean,
		"余力: 撃破ボーナスは残量が多いほど大きい (%.3f < %.3f < %.3f)" % [
			g_narrow, g_mid, g_clean]
	)
	# 額そのものも照合する(向きだけだと係数の大きさを1/100にしても通る)。
	var base := 30.0 * SpinnerStats.KNOCKOUT_RPS_GROWTH_RATE
	check.call(
		absf(g_clean - base * SpinnerStats.KNOCKOUT_MARGIN_MAX) < EPS,
		"余力: 残り100%%は基準額×上端 (%.3f)" % g_clean
	)
	check.call(
		absf(g_narrow - base * SpinnerStats.KNOCKOUT_MARGIN_MIN) < EPS,
		"余力: 残り0%%は基準額×下端 (%.3f)" % g_narrow
	)


func _test_margin_does_not_touch_passive(check: Callable) -> void:
	# 受け身の勝ち(VICTORY_RPS_GROWTH)は引き運の振れ幅を狭める下支えなので、
	# 余力では動かさない。ここに勾配を掛けると弱いランほど成長も細り、
	# 下支えの目的そのものが裏返る。
	var lo := _stats(20.0)
	var hi := _stats(20.0)
	var g_lo := lo.grow_rps_by_victory(false, 0.0)
	var g_hi := hi.grow_rps_by_victory(false, 1.0)
	check.call(
		absf(g_lo - SpinnerStats.VICTORY_RPS_GROWTH) < EPS
			and absf(g_hi - SpinnerStats.VICTORY_RPS_GROWTH) < EPS,
		"余力: 受け身の勝ちは残量で変わらない (%.3f / %.3f)" % [g_lo, g_hi]
	)


func _test_narrow_knockout_still_beats_passive(check: Callable) -> void:
	# 抜け道封じ。残量は「触らずに逃げ回る」ほど増えるので、辛勝の撃破が
	# 快勝の逃げ切りより小さくなると「当てにいくな」という逆の教えになる。
	# 下端でも撃破が受け身を上回ることを定数レベルで固定する。
	check.call(
		SpinnerStats.KNOCKOUT_RPS_GROWTH * SpinnerStats.KNOCKOUT_MARGIN_MIN
			> SpinnerStats.VICTORY_RPS_GROWTH,
		"余力: 最悪の撃破(下限×下端 %.3f)でも受け身(%.3f)より大きい" % [
			SpinnerStats.KNOCKOUT_RPS_GROWTH * SpinnerStats.KNOCKOUT_MARGIN_MIN,
			SpinnerStats.VICTORY_RPS_GROWTH]
	)
	# 実際に呼んでも同じ順序になること(下限が効くrps帯で相打ち撃破 vs 無傷の逃げ切り)。
	var ko := _stats(15.0)
	var passive := _stats(15.0)
	var g_ko := ko.grow_rps_by_victory(true, 0.0)
	var g_passive := passive.grow_rps_by_victory(false, 1.0)
	check.call(
		g_ko > g_passive,
		"余力: 相打ち寸前の撃破(+%.3f)は無傷の逃げ切り(+%.3f)より大きい" % [g_ko, g_passive]
	)


func _test_margin_from_result_frames(check: Callable) -> void:
	# 余力の出どころ。BattleResult.player_rps_share は先頭/末尾フレームの比で、
	# フレームが無ければ -1.0(不明)。0.0(相打ち)と取り違えないことまで見る。
	var result := BattleResult.new()
	check.call(
		result.player_rps_share() < 0.0,
		"余力の出どころ: フレームの無い結果は不明(-1) (%.2f)" % result.player_rps_share()
	)
	result.player_frames = [
		BattleResult.Snapshot.new(Vector2.ZERO, Vector2.ZERO, 20.0),
		BattleResult.Snapshot.new(Vector2.ZERO, Vector2.ZERO, 5.0),
	]
	check.call(
		absf(result.player_rps_share() - 0.25) < EPS,
		"余力の出どころ: 20.0→5.0 は 0.25 (%.3f)" % result.player_rps_share()
	)
	var dead := BattleResult.new()
	dead.player_frames = [
		BattleResult.Snapshot.new(Vector2.ZERO, Vector2.ZERO, 20.0),
		BattleResult.Snapshot.new(Vector2.ZERO, Vector2.ZERO, 0.0),
	]
	check.call(
		absf(dead.player_rps_share()) < EPS,
		"余力の出どころ: 相打ちは0.0(不明の-1ではない) (%.3f)" % dead.player_rps_share()
	)
	# 開始rpsが0近傍の結果を「満タン生還」と読まない(0除算避けではなく嘘避け)。
	var stopped := BattleResult.new()
	stopped.player_frames = [
		BattleResult.Snapshot.new(Vector2.ZERO, Vector2.ZERO, 0.0),
		BattleResult.Snapshot.new(Vector2.ZERO, Vector2.ZERO, 0.0),
	]
	check.call(
		absf(stopped.player_rps_share()) < EPS,
		"余力の出どころ: 開始0は0%%(100%%ではない) (%.3f)" % stopped.player_rps_share()
	)
	# JSON往復でも同じ余力が出ること(結果は辞書で運ばれる=サーバー交換点)。
	var revived := BattleResult.from_dict(result.to_dict())
	check.call(
		absf(revived.player_rps_share() - result.player_rps_share()) < EPS,
		"余力の出どころ: JSON往復で変わらない (%.3f)" % revived.player_rps_share()
	)


## 余力が「戦いの事実」から「ランの成長」まで実際に届いているかの配線検知。
##
## 単体テストは grow_rps_by_victory(true, share) を直に呼ぶので、呼び出し側が
## share を渡し忘れても全部 green のまま **既定の -1.0＝従来の成長** へ静かに
## 戻る——機能まるごとが消えても誰も落ちない。実プレイ(Battle→Main→GameState)と
## シミュレーション(BattleSim→RunSim)とCLI(naive_play)の3経路を源で押さえる。
func _test_margin_wiring(check: Callable) -> void:
	var battle := FileAccess.get_file_as_string("res://scenes/battle/Battle.gd")
	check.call(
		battle.contains("_result.player_rps_share()"),
		"配線: Battle.gdが結果から余力を読む"
	)
	check.call(
		battle.contains("grow_rps_by_victory(knockout, share)"),
		"配線: Battle.gdの表示プレビューが余力込みで成長させる"
	)
	var main := FileAccess.get_file_as_string("res://scenes/main/Main.gd")
	check.call(
		main.contains("grow_after_victory(knockout, rps_share)"),
		"配線: Mainが余力をGameStateへ渡す"
	)
	var gamestate := FileAccess.get_file_as_string("res://autoloads/GameState.gd")
	check.call(
		gamestate.contains("grow_rps_by_victory(knockout, rps_share)"),
		"配線: GameStateが余力を成長へ渡す"
	)
	var sim := FileAccess.get_file_as_string("res://playtest/battle_sim.gd")
	check.call(
		sim.contains("\"rps_share\": result.player_rps_share()"),
		"配線: BattleSimの記録に余力が載る"
	)
	var run_sim := FileAccess.get_file_as_string("res://playtest/run_sim.gd")
	check.call(
		run_sim.contains("record.get(\"rps_share\""),
		"配線: RunSimが記録の余力を成長へ渡す(統計が実ゲームとずれない)"
	)
	var cli := FileAccess.get_file_as_string("res://playtest/naive_play.gd")
	check.call(
		cli.contains("grow_rps_by_victory(knockout, share)"),
		"配線: naive_playが余力込みで成長させる"
	)
