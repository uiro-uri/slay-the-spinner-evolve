extends RefCounted

## 敵が失った削りのうち「プレイヤーが殴った分」だけを分けて数える
## (State.lost_drain_by_player → BattleResult.enemy_rps_loss["drain_by_player"])のテスト。
##
## 決着リザルトの「相手が失った回転」行はこの事実を出す。乱戦では敵同士の同士討ちも
## 敵の lost_drain に入るので、総量をそのまま「自分の削り」と呼ぶと自分の手柄が
## 水増しされる(コールドプレイでボスに連敗しても何を変えればいいのか分からない、が
## 元の動機なので、並べる数字が嘘だと改善の意味そのものが消える)。
##
## ここで固定するのは:
##  - プレイヤーが殴れば、その敵の drain_by_player が総削りと一致する(単体戦)
##  - プレイヤーが触れていない敵は、同士討ちで削られていても drain_by_player が0
##  - プレイヤー自身の内訳は常に drain_by_player = 0(意味を持たない側)
##  - 別勘定を足しても既存の総削り(drain)・勝敗は1ptも動かない(表示専用の追加である証明)

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_player_hit_is_attributed(check)
	_test_friendly_fire_is_not_attributed(check)
	_test_player_dict_is_zero(check)
	_test_totals_unchanged(check)
	_test_serialization(check)


## プレイヤーが敵1体に正面から当たるだけの理想環境。自然減衰・傾斜は切る。
static func _duel_request() -> BattleRequest:
	var pstats := SpinnerStats.default_player()
	var e := SpinnerStats.new()
	e.radius = 0.5
	e.rps = 20.0

	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	r.max_duration = 0.5
	r.player = BattleRequest.Launch.new(pstats, Vector2(4, 5), Vector2(6, 0))
	r.enemies = [BattleRequest.Launch.new(e, Vector2(6, 5), Vector2(-6, 0))]
	return r


## 敵2体が正面衝突し、プレイヤーは遠くに静止したまま触れない理想環境
## (test_enemy_mutual_drain と同じ形)。敵のrps減少は同士討ちだけになる。
static func _friendly_fire_request() -> BattleRequest:
	var pstats := SpinnerStats.default_player()
	var e1 := SpinnerStats.new()
	e1.radius = 0.5
	e1.rps = 20.0
	var e2 := SpinnerStats.new()
	e2.radius = 0.5
	e2.rps = 20.0

	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	r.enemy_mutual_drain_scale = 1.0
	r.max_duration = 0.5
	r.player = BattleRequest.Launch.new(pstats, Vector2(1, 9), Vector2.ZERO)
	r.enemies = [
		BattleRequest.Launch.new(e1, Vector2(4, 5), Vector2(6, 0)),
		BattleRequest.Launch.new(e2, Vector2(6, 5), Vector2(-6, 0)),
	]
	return r


## 単体戦ではプレイヤーが唯一の削り手なので、drain_by_player は総削りと一致する。
func _test_player_hit_is_attributed(check: Callable) -> void:
	var result := BattleResolver.resolve(_duel_request())
	check.call(not result.impacts.is_empty(), "attribution: プレイヤーと敵が衝突した")
	if result.enemy_rps_loss.is_empty():
		check.call(false, "attribution: 敵の内訳が記録された")
		return
	var loss: Dictionary = result.enemy_rps_loss[0]
	var drain := float(loss.get("drain", 0.0))
	var by_player := float(loss.get("drain_by_player", -1.0))
	check.call(drain > EPS, "attribution: 敵が削られた (drain=%.4f)" % drain)
	check.call(
		absf(by_player - drain) < EPS,
		"attribution: 単体戦では自分の削り=総削り (%.4f vs %.4f)" % [by_player, drain]
	)


## プレイヤーが一度も触れていない敵は、同士討ちで削られていても寄与は0。
## これが0にならないと、乱戦で敵が勝手に潰れただけの部屋を「自分が削った」と表示する。
func _test_friendly_fire_is_not_attributed(check: Callable) -> void:
	var result := BattleResolver.resolve(_friendly_fire_request())
	check.call(not result.impacts.is_empty(), "attribution: 敵同士が衝突した")
	if result.enemy_rps_loss.size() < 2:
		check.call(false, "attribution: 敵2体ぶんの内訳が記録された")
		return
	for i in 2:
		var loss: Dictionary = result.enemy_rps_loss[i]
		var drain := float(loss.get("drain", 0.0))
		var by_player := float(loss.get("drain_by_player", -1.0))
		check.call(drain > EPS, "attribution: 敵%dは同士討ちで削られた (drain=%.4f)" % [i, drain])
		check.call(
			absf(by_player) < EPS,
			"attribution: 敵%dの同士討ちは自分の削りに数えない (%.4f)" % [i, by_player]
		)


## プレイヤー自身の内訳の drain_by_player は常に0(「自分が自分を殴った分」は無い)。
func _test_player_dict_is_zero(check: Callable) -> void:
	var result := BattleResolver.resolve(_duel_request())
	var by_player := float(result.player_rps_loss.get("drain_by_player", -1.0))
	check.call(
		absf(by_player) < EPS,
		"attribution: プレイヤー側は常に0 (%.4f)" % by_player
	)
	check.call(
		float(result.player_rps_loss.get("drain", 0.0)) > EPS,
		"attribution: プレイヤーは削られている(0固定が「無風だから0」ではない証明)"
	)


## 別勘定を足しても物理・勝敗・既存の内訳は1ptも動かない。表示のための事実追加で
## あってバランス変更ではない、という約束をここで固定する。
func _test_totals_unchanged(check: Callable) -> void:
	var result := BattleResolver.resolve(_duel_request())
	if result.enemy_rps_loss.is_empty() or result.enemy_tracks.is_empty():
		check.call(false, "attribution: 結果が記録された")
		return
	# drain+wall+decay = 初期rps - 最終rps の恒等式(_record_losses の約束)が
	# 別勘定の追加後も成り立つ。drain_by_player は drain の内訳であって加算項ではない。
	var loss: Dictionary = result.enemy_rps_loss[0]
	var summed := (
		float(loss.get("drain", 0.0))
		+ float(loss.get("wall", 0.0))
		+ float(loss.get("decay", 0.0))
	)
	var last_rps: float = result.enemy_tracks[0][-1].rps
	var spent := 20.0 - last_rps
	check.call(
		absf(summed - spent) < EPS,
		"attribution: 内訳の和が実際の喪失と一致 (%.4f vs %.4f)" % [summed, spent]
	)


## シリアライズ往復で事実が保たれる(BattleResult は to_dict で丸ごと運ばれる)。
func _test_serialization(check: Callable) -> void:
	var result := BattleResolver.resolve(_duel_request())
	var revived := BattleResult.from_dict(result.to_dict())
	var before := float(result.enemy_rps_loss[0].get("drain_by_player", -1.0))
	var after := float(revived.enemy_rps_loss[0].get("drain_by_player", -2.0))
	check.call(
		absf(before - after) < EPS,
		"attribution: 往復で自分の削りが保たれる (%.4f vs %.4f)" % [before, after]
	)
