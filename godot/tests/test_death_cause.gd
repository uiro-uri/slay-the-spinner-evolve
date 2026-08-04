extends RefCounted

## 敗者の死因記録(BattleResolver → BattleResult.loser_death_cause)と
## 撃破判定(finished_by_knockout)のテスト。
##
## 「弱発射で敵から離れて自然減衰を待つ」受け身戦法が支配的で、当てにいく方の
## 遊びが報われない。その対策の撃破ボーナス(勝利成長の増額)は「接触で決着したか」
## の判定に懸かっているので、リゾルバが3つの死因(drain/wall/decay)を取り違えずに
## 記録することをここで固定する。各ケースは他の死因が起こり得ない理想環境を組む。
##
## 死因は「最も多くrpsを奪った機構」で分類する(_dominant_cause)。閾値を割らせた
## 最後の一滴で分類すると、削りや壁で大半を失った死が最後の微小な減衰で"decay"に
## 化け、敗因分析と撃破ボーナスが実態とずれる(コールドプレイの一次証拠あり)。

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_decay_kill(check)
	_test_drain_kill(check)
	_test_wall_kill(check)
	_test_wall_kill_with_contact(check)
	_test_mutual_drain_no_contact(check)
	_test_melee_partial_knockout(check)
	_test_player_loss(check)
	_test_dominant_cause_unit(check)
	_test_dominant_drain_over_final_decay(check)
	_test_dominant_decay_over_final_drain(check)
	_test_knockout_records_unit(check)
	_test_serialization(check)


func _enemy_stats(rps: float) -> SpinnerStats:
	var s := SpinnerStats.new()
	s.mass = 1.0
	s.radius = 0.5
	s.friction = 0.0
	s.restitution = 1.0
	s.rps = rps
	return s


## 接触なし: プレイヤーは静止、敵は遠くで静止。敵のrpsが低く自然減衰だけで尽きる。
func _test_decay_kill(check: Callable) -> void:
	var r := BattleRequest.new()
	r.stage_strength = 0.0
	r.player = BattleRequest.Launch.new(SpinnerStats.default_player(), Vector2(2, 5), Vector2.ZERO)
	r.enemies = [BattleRequest.Launch.new(_enemy_stats(0.5), Vector2(8, 5), Vector2.ZERO)]
	var result := BattleResolver.resolve(r)

	check.call(result.player_won(), "死因decay: 接触せず敵の自然減衰を待てば勝つ")
	check.call(result.impacts.is_empty(), "死因decay: 検証環境で衝突が起きていない")
	check.call(
		result.loser_death_cause == "decay",
		"死因decay: 敗者の死因がdecayと記録される (%s)" % result.loser_death_cause
	)
	check.call(not result.finished_by_knockout(), "死因decay: 減衰待ちの勝ちは撃破扱いにしない")
	# 体ごとの停止事実。生き残ったプレイヤーは空、尽きた敵は死因と時刻を持つ。
	check.call(result.player_death.is_empty(), "停止事実: 生存したプレイヤーは空Dictionary")
	check.call(
		result.enemy_deaths.size() == 1
		and result.enemy_deaths[0].get("cause", "") == "decay",
		"停止事実: 敵の死因decayが体ごとに記録される (%s)" % str(result.enemy_deaths)
	)
	check.call(
		result.enemy_deaths.size() == 1
		and float(result.enemy_deaths[0].get("time", -1.0)) >= 0.0
		and float(result.enemy_deaths[0].get("time", -1.0)) <= result.finish_time + EPS,
		"停止事実: 敵の停止時刻が0以上・決着時刻以下 (%s)" % str(result.enemy_deaths)
	)


## 正面衝突: 自然減衰・傾斜を切り、敵のrpsを削り1発ぶんより低くする。
## rpsが減る機構が衝突削りしか無いので、死因はdrain以外あり得ない。
func _test_drain_kill(check: Callable) -> void:
	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	r.player = BattleRequest.Launch.new(SpinnerStats.default_player(), Vector2(3, 5), Vector2(4, 0))
	r.enemies = [BattleRequest.Launch.new(_enemy_stats(0.2), Vector2(7, 5), Vector2(-4, 0))]
	var result := BattleResolver.resolve(r)

	check.call(result.player_won(), "死因drain: 衝突で敵のrpsを削り切れば勝つ")
	check.call(result.impacts.size() >= 1, "死因drain: 検証環境で衝突が起きている")
	check.call(
		result.loser_death_cause == "drain",
		"死因drain: 敗者の死因がdrainと記録される (%s)" % result.loser_death_cause
	)
	check.call(
		result.loser_hit_by_player,
		"死因drain: プレイヤーとの接触が事実として記録される"
	)
	check.call(result.finished_by_knockout(), "死因drain: 接触で仕留めた勝ちは撃破扱い")


## 壁死(接触ゼロ): 自然減衰・傾斜・摩擦を切り、敵を高速で壁へ向かわせる。
## プレイヤーは遠くで静止して一度も接触しない。壁の減衰だけが敵のrpsを減らすが、
## プレイヤーは何もしていないので、この勝ちは撃破(接触で仕留めた)扱いにしない。
## かつては死因=wallだけで撃破+1.0が付き、「待てば自滅」の受け身まで複利で
## 報われていた(コールドプレイの一次証拠あり)。
func _test_wall_kill(check: Callable) -> void:
	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	r.player = BattleRequest.Launch.new(SpinnerStats.default_player(), Vector2(2, 2), Vector2.ZERO)
	r.enemies = [BattleRequest.Launch.new(_enemy_stats(1.0), Vector2(5, 5), Vector2(12, 0))]
	var result := BattleResolver.resolve(r)

	check.call(result.player_won(), "死因wall: 壁の減衰で敵のrpsが尽きれば勝つ")
	check.call(result.wall_impacts.size() >= 1, "死因wall: 検証環境で壁衝突が起きている")
	check.call(result.impacts.is_empty(), "死因wall: 検証環境でプレイヤーとの接触がない")
	check.call(
		result.loser_death_cause == "wall",
		"死因wall: 敗者の死因がwallと記録される (%s)" % result.loser_death_cause
	)
	check.call(
		not result.loser_hit_by_player,
		"死因wall: 接触ゼロの事実が記録される"
	)
	check.call(
		not result.finished_by_knockout(),
		"死因wall: 接触ゼロの壁自滅は撃破扱いにしない"
	)


## 壁死(プレイヤーの弾き飛ばし): プレイヤーが敵に当たり、弾かれた敵が壁で果てる。
## 削りがほぼ入らないようviolenceを絞り、壁の減衰だけで死ぬ環境を組む。
## 接触の事実があるので、この壁死は従来どおり撃破扱い。
func _test_wall_kill_with_contact(check: Callable) -> void:
	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	# violenceを絞って削りでは死なず、壁を重くして(速度スケールも切って)最初の
	# 壁激突で確実に尽きる環境を組む: 弾かれた敵は一直線に右壁で果てる。
	r.violence = 0.0001
	r.wall_damping = 0.1
	r.wall_impact_ref_speed = 0.0
	r.player = BattleRequest.Launch.new(SpinnerStats.default_player(), Vector2(3, 5), Vector2(8, 0))
	r.enemies = [BattleRequest.Launch.new(_enemy_stats(0.15), Vector2(6, 5), Vector2.ZERO)]
	var result := BattleResolver.resolve(r)

	check.call(result.player_won(), "死因wall(接触): 弾き飛ばした敵が壁で尽きれば勝つ")
	check.call(result.impacts.size() >= 1, "死因wall(接触): プレイヤーが敵に当たっている")
	var loss: Dictionary = result.enemy_rps_loss[0]
	check.call(
		float(loss.get("wall", 0.0)) > float(loss.get("drain", 0.0)),
		"死因wall(接触): 検証環境で壁の喪失が支配的 (%s)" % str(loss)
	)
	check.call(
		result.loser_death_cause == "wall",
		"死因wall(接触): 敗者の死因がwallと記録される (%s)" % result.loser_death_cause
	)
	check.call(
		result.loser_hit_by_player,
		"死因wall(接触): プレイヤーとの接触が事実として記録される"
	)
	check.call(
		result.finished_by_knockout(),
		"死因wall(接触): 壁へ弾き飛ばした勝ちは撃破扱いのまま"
	)


## 同士討ち(接触ゼロ): 敵2体が正面衝突で削り合って果てる。プレイヤーは遠くで
## 静止して一切触れない。死因はdrain(接触系)だが、削ったのはプレイヤーではないので
## 撃破扱いにしない。乱戦の「敵が勝手に潰し合う部屋」で+1.0が付いていた穴を塞ぐ。
func _test_mutual_drain_no_contact(check: Callable) -> void:
	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	# 敵2体が正面衝突の削り合いで相討ちになる筋書きそのものが検証対象なので、1撃の
	# 削りを切る天井は外す(天井が入ると削り合いきれず、死因の帳簿を見る前に話が変わる)。
	r.drain_cap_share = 0.0
	r.player = BattleRequest.Launch.new(SpinnerStats.default_player(), Vector2(1, 5), Vector2.ZERO)
	r.enemies = [
		BattleRequest.Launch.new(_enemy_stats(0.2), Vector2(6, 5), Vector2(3, 0)),
		BattleRequest.Launch.new(_enemy_stats(0.2), Vector2(8, 5), Vector2(-3, 0)),
	]
	var result := BattleResolver.resolve(r)

	check.call(result.player_won(), "同士討ち: 敵同士が削り合って全滅すれば勝つ")
	check.call(result.impacts.size() >= 1, "同士討ち: 検証環境で敵同士の衝突が起きている")
	check.call(
		result.loser_death_cause == "drain",
		"同士討ち: 敗者の死因がdrainと記録される (%s)" % result.loser_death_cause
	)
	check.call(
		not result.loser_hit_by_player,
		"同士討ち: 接触ゼロの事実が記録される"
	)
	check.call(
		not result.finished_by_knockout(),
		"同士討ち: 敵が勝手に潰し合った勝ちは撃破扱いにしない"
	)


## 乱戦の部分撃破: 自分の接触で1体を落とし、残る1体は離れた所で壁に自滅する。
## 決着を付ける(最後に落ちる)のは自滅した方なので、**決着1体だけを見る旧判定では
## 「接触ゼロの自滅勝ち」**に化けて撃破ボーナスが消えていた。2026-08-04の
## コールドプレイ 段2(Lv1×3体)の再現: 自分が2体を0.85秒で削り落としたのに、
## 3体目が6.5秒に壁で勝手に果てたせいで成長が受け身の+0.5だった。
## 乱戦は報酬が頭数ぶん多い代わりに危険な部屋で、そこで自分の手柄が敵の自滅で
## 取り消されるのは、部屋選びの動機を直接壊す。
func _test_melee_partial_knockout(check: Callable) -> void:
	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	# 「1体を初撃で確実に落とす」が筋書きの前提なので、1撃の削りを切る天井は外す
	# (天井が入ると敵1が生き延びて壁へ流れ、死因の帳簿の話が変わる)。
	r.drain_cap_share = 0.0
	r.player = BattleRequest.Launch.new(SpinnerStats.default_player(), Vector2(3, 5), Vector2(8, 0))
	r.enemies = [
		# 敵1: 正面から突っ込んできて初撃で落ちる(自分が落とした相手)。
		BattleRequest.Launch.new(_enemy_stats(0.1), Vector2(7, 5), Vector2(-4, 0)),
		# 敵2: 別の高さを高速で走り、誰にも触れないまま壁で果てる(自滅)。
		BattleRequest.Launch.new(_enemy_stats(3.0), Vector2(2, 8.5), Vector2(12, 0)),
	]
	var result := BattleResolver.resolve(r)

	check.call(result.player_won(), "乱戦部分撃破: 敵2体が全滅して勝つ")
	var killed: Dictionary = result.enemy_deaths[0]
	var suicide: Dictionary = result.enemy_deaths[1]
	check.call(
		killed.get("cause", "") == "drain" and bool(killed.get("by_player", false)),
		"乱戦部分撃破: 敵1は自分の削りで落ちた事実が記録される (%s)" % str(killed)
	)
	check.call(
		suicide.get("cause", "") == "wall" and not bool(suicide.get("by_player", true)),
		"乱戦部分撃破: 敵2は接触ゼロで壁に自滅した事実が記録される (%s)" % str(suicide)
	)
	check.call(
		float(suicide.get("time", -1.0)) > float(killed.get("time", -1.0)),
		"乱戦部分撃破: 検証環境で自滅した敵2の方が後に落ちる (%s / %s)" % [str(killed), str(suicide)]
	)
	# 決着を付けたのは自滅した敵2なので、旧判定の材料(loser_*)は「接触ゼロ」を指す。
	check.call(
		result.loser_death_cause == "wall" and not result.loser_hit_by_player,
		"乱戦部分撃破: 決着1体の事実は接触ゼロの壁自滅のまま (%s/%s)"
		% [result.loser_death_cause, str(result.loser_hit_by_player)]
	)
	check.call(
		result.player_finished_any_enemy(),
		"乱戦部分撃破: 自分が落とした敵が居ると判定される"
	)
	check.call(
		result.finished_by_knockout(),
		"乱戦部分撃破: 最後の1体が自滅しても、自分が落とした敵が居れば撃破扱い"
	)


## 敗北時も敗者(プレイヤー)の死因が記録され、撃破扱いにはならないこと。
func _test_player_loss(check: Callable) -> void:
	var pstats := SpinnerStats.default_player()
	pstats.rps = 0.2
	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	r.player = BattleRequest.Launch.new(pstats, Vector2(3, 5), Vector2(4, 0))
	r.enemies = [BattleRequest.Launch.new(_enemy_stats(15.0), Vector2(7, 5), Vector2(-4, 0))]
	var result := BattleResolver.resolve(r)

	check.call(not result.player_won(), "死因(敗北): プレイヤーが削り殺される")
	check.call(
		result.loser_death_cause == "drain",
		"死因(敗北): 敗者=プレイヤーの死因が記録される (%s)" % result.loser_death_cause
	)
	check.call(not result.finished_by_knockout(), "死因(敗北): 敗北は撃破扱いにしない")
	# 体ごとの停止事実の敗北側: プレイヤーが死因と時刻を持ち、生存した敵は空。
	check.call(
		result.player_death.get("cause", "") == "drain",
		"停止事実(敗北): プレイヤーの死因drainが記録される (%s)" % str(result.player_death)
	)
	check.call(
		float(result.player_death.get("time", -1.0)) >= 0.0
		and float(result.player_death.get("time", -1.0)) <= result.finish_time + EPS,
		"停止事実(敗北): プレイヤーの停止時刻が0以上・決着時刻以下 (%s)" % str(result.player_death)
	)
	check.call(
		result.enemy_deaths.size() == 1 and result.enemy_deaths[0].is_empty(),
		"停止事実(敗北): 生存した敵は空Dictionary (%s)" % str(result.enemy_deaths)
	)


## 分類規則そのもの(_mark_if_dead → _dominant_cause)の単体テスト。
## 累計を直接組んで、最後の一滴と支配的機構がずれる全パターンを固定する。
func _test_dominant_cause_unit(check: Callable) -> void:
	var req := BattleRequest.new()

	# 壁が支配的なのに最後の一滴が減衰 → wall。
	var s := _dead_state(1.0, 6.0, 3.0)
	BattleResolver._mark_if_dead(s, "decay", req, 1.0)
	check.call(
		s.death_cause == "wall",
		"支配的死因: 壁が最大なら最後の一滴が減衰でもwall (%s)" % s.death_cause
	)

	# 削りが支配的なのに最後の一滴が減衰 → drain。
	s = _dead_state(6.0, 1.0, 3.0)
	BattleResolver._mark_if_dead(s, "decay", req, 1.0)
	check.call(
		s.death_cause == "drain",
		"支配的死因: 削りが最大なら最後の一滴が減衰でもdrain (%s)" % s.death_cause
	)

	# 減衰が支配的なのに最後の一滴が削り(受け身の末の一撫で) → decay。
	s = _dead_state(1.0, 0.0, 6.0)
	BattleResolver._mark_if_dead(s, "drain", req, 1.0)
	check.call(
		s.death_cause == "decay",
		"支配的死因: 減衰が最大なら最後の一撫ではdecay (%s)" % s.death_cause
	)

	# 同率は最後の一滴の機構に倒す(1機構だけの戦いは従来と厳密一致)。
	s = _dead_state(2.0, 2.0, 2.0)
	BattleResolver._mark_if_dead(s, "wall", req, 1.0)
	check.call(
		s.death_cause == "wall",
		"支配的死因: 同率は最後の一滴に倒す (%s)" % s.death_cause
	)

	# 一度確定した死因は上書きされない。
	s = _dead_state(6.0, 1.0, 0.0)
	BattleResolver._mark_if_dead(s, "drain", req, 1.0)
	s.lost_decay = 100.0
	BattleResolver._mark_if_dead(s, "decay", req, 2.0)
	check.call(
		s.death_cause == "drain" and is_equal_approx(s.death_time, 1.0),
		"支配的死因: 確定済みの死因と時刻は上書きされない (%s@%f)" % [s.death_cause, s.death_time]
	)


## rps0で機構別の累計だけを持つ死亡直後のState。
func _dead_state(drain: float, wall: float, decay: float) -> BattleResolver.State:
	var s := BattleResolver.State.new(
		BattleRequest.Launch.new(_enemy_stats(10.0), Vector2.ZERO, Vector2.ZERO)
	)
	s.rps = 0.0
	s.lost_drain = drain
	s.lost_wall = wall
	s.lost_decay = decay
	return s


## E2E: 強打で大半を削った敵が生き延び、残りを自然減衰で落とす。最後の一滴は
## 減衰だが、支配的なのは削りなので死因はdrain=撃破扱い。当てて仕留めたのに
## 最後の一滴のせいで受け身勝ち(+0.5)扱いになっていた実戦(コールドプレイ段4)の再現。
func _test_dominant_drain_over_final_decay(check: Callable) -> void:
	var r := BattleRequest.new()
	r.stage_strength = 0.0
	# 「大半を削られた敵が一瞬生き延び、最後の一滴は自然減衰」という配分そのものが
	# 筋書きなので、削り/減衰の比を既定値の調整に委ねずこの場で固定する。
	r.violence = 0.07
	r.natural_damping = 0.75
	# 同じ理由で1撃の削りを切る天井も外す(「強打で大半を削る」が筋書きの前提)。
	r.drain_cap_share = 0.0
	var pstats := SpinnerStats.default_player()
	var estats := _enemy_stats(3.0)
	estats.friction = 3.0
	r.player = BattleRequest.Launch.new(pstats, Vector2(3, 5), Vector2(6, 0))
	r.enemies = [BattleRequest.Launch.new(estats, Vector2(5.5, 5), Vector2.ZERO)]
	var result := BattleResolver.resolve(r)

	check.call(result.player_won(), "支配drain/最後decay: プレイヤーが勝つ")
	check.call(result.impacts.size() >= 1, "支配drain/最後decay: 衝突が起きている")
	var loss: Dictionary = result.enemy_rps_loss[0]
	check.call(
		float(loss.get("drain", 0.0)) > float(loss.get("decay", 0.0))
		and float(loss.get("drain", 0.0)) > float(loss.get("wall", 0.0)),
		"支配drain/最後decay: 検証環境で削りが支配的 (%s)" % str(loss)
	)
	var last_impact: float = result.impacts[result.impacts.size() - 1].time
	check.call(
		float(result.enemy_deaths[0].get("time", -1.0)) > last_impact + r.time_step,
		"支配drain/最後decay: 敵は最後の接触を生き延びてから尽きる(最後の一滴は減衰)"
	)
	check.call(
		result.loser_death_cause == "drain",
		"支配drain/最後decay: 死因は支配的なdrain (%s)" % result.loser_death_cause
	)
	check.call(
		result.finished_by_knockout(),
		"支配drain/最後decay: 削りで大半を奪った勝ちは撃破扱い"
	)


## E2E: 遠くからゆっくり近づく間に敵が減衰でほぼ尽き、最後の一撫でで落とす。
## 最後の一滴は削りだが、支配的なのは減衰なので死因はdecay=撃破扱いにしない
## (減衰待ちの末のタップを「接触で仕留めた」と呼ばない)。
func _test_dominant_decay_over_final_drain(check: Callable) -> void:
	var r := BattleRequest.new()
	r.stage_strength = 0.0
	# 「近づく間に減衰でほぼ尽き、最後の一撫でで落ちる」配分が筋書きなので、
	# 削り/減衰の比を既定値の調整に委ねずこの場で固定する。
	r.violence = 0.07
	r.natural_damping = 0.75
	var pstats := SpinnerStats.default_player()
	pstats.friction = 0.0
	var estats := _enemy_stats(2.0)
	r.player = BattleRequest.Launch.new(pstats, Vector2(1, 5), Vector2(1.5, 0))
	r.enemies = [BattleRequest.Launch.new(estats, Vector2(8, 5), Vector2.ZERO)]
	var result := BattleResolver.resolve(r)

	check.call(result.player_won(), "支配decay/最後drain: プレイヤーが勝つ")
	check.call(result.impacts.size() >= 1, "支配decay/最後drain: 最後の一撫でが当たっている")
	var loss: Dictionary = result.enemy_rps_loss[0]
	check.call(
		float(loss.get("decay", 0.0)) > float(loss.get("drain", 0.0))
		and int(loss.get("wall_hits", -1)) == 0,
		"支配decay/最後drain: 検証環境で減衰が支配的・壁なし (%s)" % str(loss)
	)
	var last_impact: float = result.impacts[result.impacts.size() - 1].time
	check.call(
		float(result.enemy_deaths[0].get("time", -1.0)) <= last_impact + r.time_step + EPS,
		"支配decay/最後drain: 敵は最後の接触で尽きる(最後の一滴は削り)"
	)
	check.call(
		result.loser_death_cause == "decay",
		"支配decay/最後drain: 死因は支配的なdecay (%s)" % result.loser_death_cause
	)
	check.call(
		not result.finished_by_knockout(),
		"支配decay/最後drain: 減衰待ちの末の一撫では撃破扱いにしない"
	)


## 撃破判定が読む「記録」そのものの規則(BattleResult側の単体)。E2Eでは踏めない
## 混在・欠落を、停止事実を直に組んで固定する。
func _test_knockout_records_unit(check: Callable) -> void:
	var r := BattleResult.new()
	r.outcome = BattleResult.Outcome.PLAYER_WIN
	# 接触系でない死因(減衰)は、自分が触れた相手でも「落とした」に数えない。
	r.enemy_deaths = [{"cause": "decay", "time": 1.0, "by_player": true}]
	check.call(
		not r.player_finished_any_enemy(),
		"撃破記録: 減衰で果てた敵は、触れていても落とした敵に数えない"
	)
	# by_playerを持たない記録は証拠が無い＝「落とした」と数えない(既定は安全側)。
	r.enemy_deaths = [{"cause": "drain", "time": 1.0}]
	check.call(
		not r.player_finished_any_enemy(),
		"撃破記録: by_playerを持たない記録は落とした敵に数えない"
	)
	# 記録が混在(片方だけby_playerを持つ)なら、新判定は使わず決着1体の事実へ落とす。
	# 中途半端な記録で「1体でも落としていれば撃破」を名乗ると、根拠の無い+1.0になる。
	r.enemy_deaths = [
		{"cause": "drain", "time": 0.5, "by_player": true},
		{"cause": "wall", "time": 2.0},
	]
	r.loser_death_cause = "wall"
	r.loser_hit_by_player = false
	check.call(
		not r.finished_by_knockout(),
		"撃破記録: by_playerが揃っていない結果は決着1体の事実で判定される"
	)
	# 生存(空Dictionary)は記録の欠落ではない。全滅していない敵が居ても、
	# 落とした敵の記録が揃っていれば新判定を使う。
	r.enemy_deaths = [{"cause": "drain", "time": 0.5, "by_player": true}, {}]
	check.call(
		r.finished_by_knockout(),
		"撃破記録: 生存の空Dictionaryは記録の欠落として扱わない"
	)


func _test_serialization(check: Callable) -> void:
	# dict往復で死因が保存されること。落ちるとサーバー化・リプレイで撃破ボーナスが消える。
	var result := BattleResult.new()
	result.outcome = BattleResult.Outcome.PLAYER_WIN
	result.loser_death_cause = "drain"
	var revived := BattleResult.from_dict(result.to_dict())
	check.call(
		revived.loser_death_cause == "drain",
		"往復: loser_death_causeがdict往復で保存される"
	)
	check.call(revived.finished_by_knockout(), "往復: 復元後も撃破判定が立つ")

	# 接触ゼロの事実もdict往復で保存される。落ちるとサーバー化・リプレイで
	# 自滅勝ちに撃破ボーナスが復活する。
	result.loser_hit_by_player = false
	var revived_nc := BattleResult.from_dict(result.to_dict())
	check.call(
		not revived_nc.loser_hit_by_player,
		"往復: loser_hit_by_player=falseがdict往復で保存される"
	)
	check.call(
		not revived_nc.finished_by_knockout(),
		"往復: 復元後も接触ゼロの勝ちは撃破扱いにしない"
	)
	result.loser_hit_by_player = true

	# 接触キーの無い旧dictは接触あり扱いで読み、当時の撃破判定(死因だけで決まる)を
	# 当時のまま再現する。
	var no_hit_key := result.to_dict()
	no_hit_key.erase("loser_hit_by_player")
	var legacy := BattleResult.from_dict(no_hit_key)
	check.call(
		legacy.loser_hit_by_player and legacy.finished_by_knockout(),
		"往復: 接触キーの無い旧dictは従来どおり死因だけで撃破判定される"
	)

	# 体ごとの停止事実もdict往復で保存される。
	result.player_death = {"cause": "wall", "time": 1.25}
	result.enemy_deaths = [{"cause": "drain", "time": 2.5}, {}]
	var revived2 := BattleResult.from_dict(result.to_dict())
	check.call(
		revived2.player_death.get("cause", "") == "wall"
		and is_equal_approx(float(revived2.player_death.get("time", -1.0)), 1.25),
		"往復: player_deathがdict往復で保存される (%s)" % str(revived2.player_death)
	)
	check.call(
		revived2.enemy_deaths.size() == 2
		and revived2.enemy_deaths[0].get("cause", "") == "drain"
		and revived2.enemy_deaths[1].is_empty(),
		"往復: enemy_deaths(生存の空Dictionary込み)が保存される (%s)" % str(revived2.enemy_deaths)
	)

	# 撃破判定の材料(by_player)もdict往復で保存される。落ちるとサーバー化・リプレイで
	# 乱戦の撃破ボーナスが「最後に落ちた1体」だけの判定に戻る。
	result.enemy_deaths = [
		{"cause": "drain", "time": 0.5, "by_player": true},
		{"cause": "wall", "time": 2.0, "by_player": false},
	]
	result.loser_death_cause = "wall"
	result.loser_hit_by_player = false
	var revived3 := BattleResult.from_dict(result.to_dict())
	check.call(
		bool(revived3.enemy_deaths[0].get("by_player", false))
		and not bool(revived3.enemy_deaths[1].get("by_player", true)),
		"往復: enemy_deathsのby_playerが保存される (%s)" % str(revived3.enemy_deaths)
	)
	check.call(
		revived3.finished_by_knockout(),
		"往復: 復元後も乱戦の部分撃破は撃破扱いのまま"
	)
	# by_playerを持たない旧dictは、決着1体の事実(loser_*)で当時のまま判定される。
	var legacy_deaths := result.to_dict()
	legacy_deaths["enemy_deaths"] = [{"cause": "drain", "time": 0.5}, {"cause": "wall", "time": 2.0}]
	var legacy_melee := BattleResult.from_dict(legacy_deaths)
	check.call(
		not legacy_melee.finished_by_knockout(),
		"往復: by_playerの無い旧dictは決着1体の事実で判定される(接触ゼロ=撃破外)"
	)
	result.enemy_deaths = [{"cause": "drain", "time": 2.5}, {}]
	result.loser_death_cause = "drain"
	result.loser_hit_by_player = true

	# 旧いdict(キーなし)は空文字で読める(後方互換)。
	var old_dict := result.to_dict()
	old_dict.erase("loser_death_cause")
	old_dict.erase("player_death")
	old_dict.erase("enemy_deaths")
	var old := BattleResult.from_dict(old_dict)
	check.call(
		old.loser_death_cause == "",
		"往復: loser_death_causeキーの無い旧dictは空文字で読める"
	)
	check.call(not old.finished_by_knockout(), "往復: 旧dictは撃破扱いにしない(安全側)")
	check.call(
		old.player_death.is_empty() and old.enemy_deaths.is_empty(),
		"往復: 停止事実キーの無い旧dictは空(生存扱い)で読める"
	)
