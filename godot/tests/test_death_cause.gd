extends RefCounted

## 敗者の死因記録(BattleResolver → BattleResult.loser_death_cause)と
## 撃破判定(finished_by_knockout)のテスト。
##
## 「弱発射で敵から離れて自然減衰を待つ」受け身戦法が支配的で、当てにいく方の
## 遊びが報われない。その対策の撃破ボーナス(勝利成長の増額)は「接触で決着したか」
## の判定に懸かっているので、リゾルバが3つの死因(drain/wall/decay)を取り違えずに
## 記録することをここで固定する。各ケースは他の死因が起こり得ない理想環境を組む。

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_decay_kill(check)
	_test_drain_kill(check)
	_test_wall_kill(check)
	_test_player_loss(check)
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
	check.call(result.finished_by_knockout(), "死因drain: 接触で仕留めた勝ちは撃破扱い")


## 壁死: 自然減衰・傾斜・摩擦を切り、敵を高速で壁へ向かわせる。プレイヤーは
## 遠くで静止して接触しない。壁の減衰(×wall_damping)だけが敵のrpsを減らす。
func _test_wall_kill(check: Callable) -> void:
	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	r.player = BattleRequest.Launch.new(SpinnerStats.default_player(), Vector2(2, 2), Vector2.ZERO)
	r.enemies = [BattleRequest.Launch.new(_enemy_stats(1.0), Vector2(5, 5), Vector2(12, 0))]
	var result := BattleResolver.resolve(r)

	check.call(result.player_won(), "死因wall: 壁の減衰で敵のrpsが尽きれば勝つ")
	check.call(result.wall_impacts.size() >= 1, "死因wall: 検証環境で壁衝突が起きている")
	check.call(
		result.loser_death_cause == "wall",
		"死因wall: 敗者の死因がwallと記録される (%s)" % result.loser_death_cause
	)
	check.call(result.finished_by_knockout(), "死因wall: 壁へ弾き飛ばした勝ちは撃破扱い")


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

	# 旧いdict(キーなし)は空文字で読める(後方互換)。
	var old_dict := result.to_dict()
	old_dict.erase("loser_death_cause")
	var old := BattleResult.from_dict(old_dict)
	check.call(
		old.loser_death_cause == "",
		"往復: loser_death_causeキーの無い旧dictは空文字で読める"
	)
	check.call(not old.finished_by_knockout(), "往復: 旧dictは撃破扱いにしない(安全側)")
