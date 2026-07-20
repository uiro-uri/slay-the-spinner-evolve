extends RefCounted

## rps喪失内訳(BattleResolver → BattleResult.player_rps_loss / enemy_rps_loss)のテスト。
##
## 死因ラベル(loser_death_cause)は「閾値を割った最後の一撃」しか語らないため、
## 壁で大半を削られた負けが「衝突0・死因decay」に見え、コールドプレイの敗因分析
## (一次証拠)が壊れた実例がある(壁5回で18中11.8を喪失した負けが謎のdecay負けに
## 見えた)。内訳が機構ごとに正しく数えられ、合計が実際のrps減少と一致し、
## dict往復で保存されることをここで固定する。

const EPS := 1e-3


func run(check: Callable) -> void:
	_test_wall_breakdown(check)
	_test_drain_breakdown(check)
	_test_decay_breakdown(check)
	_test_serialization(check)
	_test_cli_loss_text(check)


func _enemy_stats(rps: float) -> SpinnerStats:
	var s := SpinnerStats.new()
	s.mass = 1.0
	s.radius = 0.5
	s.friction = 0.0
	s.restitution = 1.0
	s.rps = rps
	return s


## 内訳の合計 = 初期rps - 最終フレームのrps。床打ち(0クランプ)込みの実減少量と
## 一致しなければ、どこかの機構が数え漏れている。
func _check_sum(check: Callable, label: String, loss: Dictionary, rps0: float, frames: Array) -> void:
	var final_rps: float = frames[frames.size() - 1].rps
	var total: float = (
		float(loss.get("drain", 0.0)) + float(loss.get("wall", 0.0)) + float(loss.get("decay", 0.0))
	)
	check.call(
		absf(total - (rps0 - final_rps)) < EPS,
		"%s: 内訳の合計が実rps減少と一致する (%.3f vs %.3f)" % [label, total, rps0 - final_rps]
	)


## 壁バウンドだけがrpsを大きく削る環境: プレイヤーは高速で左右の壁を往復し、
## 敵は進路から外れた場所で静止して自然減衰だけで尽きる。接触は起きない。
func _test_wall_breakdown(check: Callable) -> void:
	var pstats := SpinnerStats.default_player()
	pstats.friction = 0.0
	pstats.restitution = 1.0
	var r := BattleRequest.new()
	r.stage_strength = 0.0
	r.natural_damping = 0.1
	r.player = BattleRequest.Launch.new(pstats, Vector2(5, 5), Vector2(12, 0))
	r.enemies = [BattleRequest.Launch.new(_enemy_stats(0.5), Vector2(8, 9), Vector2.ZERO)]
	var result := BattleResolver.resolve(r)

	check.call(result.impacts.is_empty(), "壁内訳: 検証環境でコマ同士の衝突が起きていない")
	var p: Dictionary = result.player_rps_loss
	check.call(float(p.get("wall", 0.0)) > 0.0, "壁内訳: プレイヤーの壁喪失が正で記録される")
	check.call(int(p.get("wall_hits", 0)) >= 2, "壁内訳: 壁バウンド回数が数えられる (%d)" % int(p.get("wall_hits", 0)))
	check.call(absf(float(p.get("drain", 0.0))) < EPS, "壁内訳: 接触なしなら削り喪失は0")
	check.call(float(p.get("decay", 0.0)) > 0.0, "壁内訳: 自然減衰の喪失も並記される")
	_check_sum(check, "壁内訳(自分)", p, pstats.rps, result.player_frames)

	check.call(result.enemy_rps_loss.size() == 1, "壁内訳: 敵の内訳が敵の数だけ返る")
	var e: Dictionary = result.enemy_rps_loss[0]
	check.call(int(e.get("wall_hits", 0)) == 0, "壁内訳: 静止した敵は壁に当たらない")
	check.call(float(e.get("decay", 0.0)) > 0.0, "壁内訳: 敵は自然減衰だけで尽きる")
	_check_sum(check, "壁内訳(敵)", e, 0.5, result.enemy_tracks[0])


## 正面衝突だけがrpsを削る環境(自然減衰・傾斜なし)。削りが両者のdrainに載る。
func _test_drain_breakdown(check: Callable) -> void:
	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	r.player = BattleRequest.Launch.new(SpinnerStats.default_player(), Vector2(3, 5), Vector2(4, 0))
	r.enemies = [BattleRequest.Launch.new(_enemy_stats(0.2), Vector2(7, 5), Vector2(-4, 0))]
	var result := BattleResolver.resolve(r)

	check.call(result.impacts.size() >= 1, "削り内訳: 検証環境で衝突が起きている")
	var p: Dictionary = result.player_rps_loss
	var e: Dictionary = result.enemy_rps_loss[0]
	check.call(float(p.get("drain", 0.0)) > 0.0, "削り内訳: プレイヤーの被削りが記録される")
	check.call(float(e.get("drain", 0.0)) > 0.0, "削り内訳: 敵の被削りが記録される")
	check.call(absf(float(p.get("decay", 0.0))) < EPS, "削り内訳: 減衰なし環境でdecayは0")
	_check_sum(check, "削り内訳(自分)", p, SpinnerStats.default_player().rps, result.player_frames)
	_check_sum(check, "削り内訳(敵)", e, 0.2, result.enemy_tracks[0])


## 接触も壁も起きない環境では、内訳が自然減衰のみになる。
func _test_decay_breakdown(check: Callable) -> void:
	var r := BattleRequest.new()
	r.stage_strength = 0.0
	r.player = BattleRequest.Launch.new(SpinnerStats.default_player(), Vector2(2, 5), Vector2.ZERO)
	r.enemies = [BattleRequest.Launch.new(_enemy_stats(0.5), Vector2(8, 5), Vector2.ZERO)]
	var result := BattleResolver.resolve(r)

	var p: Dictionary = result.player_rps_loss
	check.call(absf(float(p.get("drain", 0.0))) < EPS, "減衰内訳: 接触なしで削り0")
	check.call(absf(float(p.get("wall", 0.0))) < EPS, "減衰内訳: 壁に触れず壁喪失0")
	check.call(float(p.get("decay", 0.0)) > 0.0, "減衰内訳: 自然減衰が記録される")
	_check_sum(check, "減衰内訳(自分)", p, SpinnerStats.default_player().rps, result.player_frames)


## dict往復(JSON経由)で内訳が保存されること。旧dict(キーなし)は空で読める。
func _test_serialization(check: Callable) -> void:
	var result := BattleResult.new()
	result.outcome = BattleResult.Outcome.PLAYER_WIN
	result.player_rps_loss = {"drain": 2.5, "wall": 11.8, "decay": 6.2, "wall_hits": 5}
	result.enemy_rps_loss = [{"drain": 7.0, "wall": 0.0, "decay": 4.0, "wall_hits": 0}]
	var revived := BattleResult.from_dict(JSON.parse_string(JSON.stringify(result.to_dict())))
	check.call(
		absf(float(revived.player_rps_loss.get("wall", 0.0)) - 11.8) < EPS,
		"往復: プレイヤー内訳がJSON往復で保存される"
	)
	check.call(int(revived.player_rps_loss.get("wall_hits", 0)) == 5, "往復: 壁回数が保存される")
	check.call(
		revived.enemy_rps_loss.size() == 1
			and absf(float(revived.enemy_rps_loss[0].get("drain", 0.0)) - 7.0) < EPS,
		"往復: 敵の内訳がJSON往復で保存される"
	)

	var old_dict := result.to_dict()
	old_dict.erase("player_rps_loss")
	old_dict.erase("enemy_rps_loss")
	var old := BattleResult.from_dict(old_dict)
	check.call(
		old.player_rps_loss.is_empty() and old.enemy_rps_loss.is_empty(),
		"往復: 内訳キーの無い旧dictは空で読める(後方互換)"
	)


## CLI表示(naive_play.loss_text)が内訳を数値で出し、キー欠落でも落ちないこと。
func _test_cli_loss_text(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	var text: String = NaivePlay.loss_text(
		"自分", {"drain": 2.5, "wall": 11.8, "decay": 6.2, "wall_hits": 5}
	)
	check.call(
		text.contains("壁11.8") and text.contains("(5回)") and text.contains("削り2.5")
			and text.contains("減衰6.2"),
		"CLI表示: 内訳が機構別の数値で出る (%s)" % text
	)
	var empty_text: String = NaivePlay.loss_text("自分", {})
	check.call(
		empty_text.contains("壁0.0"),
		"CLI表示: キー欠落(旧結果)は0表示で落ちない (%s)" % empty_text
	)
