extends RefCounted

## シャープエッジ(edge / Sharp Edge札)のテスト。
##
## edgeは「コマ同士の衝突で相手に与えるrps削りを増やす」攻めのステータスで、
## 受け側のhit_guard(GUARD札)と対になる。ここで固定するのは:
##  - 純関数sharpened_spin_drainの向きとクランプ
##  - リゾルバが攻め手のedgeぶん相手の削りを実際に増やすこと(1回衝突の理想環境)
##  - 受け手のhit_guardと乗算で共存すること(どちらかが他方を消さない)
##  - EDGE札の加算と上限(重ねがけで削りが青天井にならない)
##  - シリアライズ往復(サーバー化とリプレイの前提)での保存
##  - 説明文と訳(効果テキストだけで報酬を選ぶコールドプレイの約束)

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_sharpened_drain_function(check)
	_test_resolver_honors_edge(check)
	_test_edge_and_guard_compose(check)
	_test_edge_part_stacks_with_cap(check)
	_test_stats_copy_and_serialization(check)
	_test_catalog_and_describe(check)


func _test_sharpened_drain_function(check: Callable) -> void:
	check.call(
		absf(SpinnerPhysics.sharpened_spin_drain(2.0, 0.0) - 2.0) < EPS,
		"sharpened_spin_drain: edge=0で削りは変わらない"
	)
	check.call(
		absf(SpinnerPhysics.sharpened_spin_drain(2.0, 0.6) - 3.2) < EPS,
		"sharpened_spin_drain: edge=0.6で削りが1.6倍になる"
	)
	# 負のedgeは0でクランプ。与ダメを減らす方向には働かない(デバフ札を置かない原則)。
	check.call(
		absf(SpinnerPhysics.sharpened_spin_drain(2.0, -0.5) - 2.0) < EPS,
		"sharpened_spin_drain: 負のedgeは0でクランプ(削りが減らない)"
	)


## 正面衝突1回だけの理想環境を作る。自然減衰・傾斜を切り、短時間で打ち切るので、
## 敵のrps減少は衝突の削りだけになる。削りは衝突前の速さから決まり、衝突前の軌道は
## edgeに依存しないので、edge=0.6のランでは敵がちょうど1.6倍削られる。
func _one_hit_request(player_edge: float, enemy_guard: float = 0.0) -> BattleRequest:
	var pstats := SpinnerStats.default_player()
	pstats.edge = player_edge
	var estats := SpinnerStats.new()
	estats.mass = 1.0
	estats.radius = 0.5
	estats.friction = 0.0
	estats.restitution = 1.0
	estats.rps = 15.0
	estats.hit_guard = enemy_guard

	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	r.max_duration = 1.0
	r.player = BattleRequest.Launch.new(pstats, Vector2(3, 5), Vector2(4, 0))
	r.enemies = [BattleRequest.Launch.new(estats, Vector2(7, 5), Vector2(-4, 0))]
	return r


func _final_enemy_rps(result: BattleResult) -> float:
	var track: Array = result.enemy_tracks[0]
	return track[track.size() - 1].rps


func _test_resolver_honors_edge(check: Callable) -> void:
	var base := BattleResolver.resolve(_one_hit_request(0.0))
	var sharpened := BattleResolver.resolve(_one_hit_request(0.6))

	check.call(base.impacts.size() >= 1, "リゾルバ: 検証環境で衝突が起きている")
	var base_loss := 15.0 - _final_enemy_rps(base)
	var sharp_loss := 15.0 - _final_enemy_rps(sharpened)
	check.call(base_loss > EPS, "リゾルバ: edge=0でも衝突で敵のrpsが削られる")
	check.call(
		sharp_loss > base_loss + EPS,
		"リゾルバ: edge=0.6は素より敵を多く削る (%.4f > %.4f)" % [sharp_loss, base_loss]
	)
	check.call(
		absf(sharp_loss - base_loss * 1.6) < EPS,
		"リゾルバ: 1回衝突の敵の削りがちょうど(1+edge)倍 (%.4f ≒ %.4f)" % [
			sharp_loss, base_loss * 1.6]
	)


## 攻め手のedgeと受け手のhit_guardは乗算で共存する。どちらかが他方を
## 打ち消す実装(上書きや取り違え)になっていないことを固定する。
func _test_edge_and_guard_compose(check: Callable) -> void:
	var base := BattleResolver.resolve(_one_hit_request(0.0))
	var both := BattleResolver.resolve(_one_hit_request(0.6, 0.5))
	var base_loss := 15.0 - _final_enemy_rps(base)
	var both_loss := 15.0 - _final_enemy_rps(both)
	check.call(
		absf(both_loss - base_loss * 1.6 * 0.5) < EPS,
		"リゾルバ: edge=0.6×hit_guard=0.5の敵の削りは素の0.8倍 (%.4f ≒ %.4f)" % [
			both_loss, base_loss * 0.8]
	)


func _test_edge_part_stacks_with_cap(check: Callable) -> void:
	var part := CustomPartCatalog.by_id(11)
	var stats := SpinnerStats.default_player()
	var before_mass := stats.mass
	var before_rps := stats.rps

	part.apply_to(stats)
	check.call(
		absf(stats.edge - CustomPartCatalog.EDGE_STEP) < EPS,
		"EDGE札: 1枚でedgeが+%.2f" % CustomPartCatalog.EDGE_STEP
	)
	part.apply_to(stats)
	part.apply_to(stats)
	part.apply_to(stats)
	check.call(
		absf(stats.edge - CustomPartCatalog.EDGE_MAX) < EPS,
		"EDGE札: 重ねがけは上限%.2fで頭打ち(与ダメが青天井にならない)" % CustomPartCatalog.EDGE_MAX
	)
	check.call(
		absf(stats.mass - before_mass) < EPS and absf(stats.rps - before_rps) < EPS,
		"EDGE札: 他のステータスには触らない"
	)
	# 上限到達後は死にカード(取っても何も変わらない)としてフィルタに弾かれること。
	check.call(
		not part.would_change_anything(stats),
		"EDGE札: 上限到達後はwould_change_anythingが偽(死にカード除外が効く)"
	)


func _test_stats_copy_and_serialization(check: Callable) -> void:
	var stats := SpinnerStats.default_player()
	stats.edge = 0.4

	# duplicate_statsの写し忘れはgreedy botの値踏み(probe)と死にカード判定を静かに狂わせる。
	check.call(
		absf(stats.duplicate_stats().edge - 0.4) < EPS,
		"duplicate_stats: edgeを写す"
	)

	# BattleRequestのdict往復。落ちるとリプレイ再現とサーバー化で別の勝敗になる。
	var launch := BattleRequest.Launch.new(stats, Vector2(1, 2), Vector2(3, 4))
	var revived := BattleRequest.Launch.from_dict(launch.to_dict())
	check.call(
		absf(revived.stats.edge - 0.4) < EPS,
		"BattleRequest: dict往復でedgeが保存される"
	)

	# 旧いdict(キーなし)は既定0で読める(後方互換)。
	var old_dict := launch.to_dict()
	old_dict.erase("edge")
	check.call(
		absf(BattleRequest.Launch.from_dict(old_dict).stats.edge) < EPS,
		"BattleRequest: edgeキーの無い旧dictは0で読める"
	)

	# naive_play(コールドプレイCLI)のstate往復。落ちると札の主効果が次の
	# コマンドで消える(MOMENTUM/RAGEで実際に起きた事故の再発防止)。
	var NaivePlay = load("res://playtest/naive_play.gd")
	var roundtrip: SpinnerStats = NaivePlay.stats_from(NaivePlay.stats_dict(stats))
	check.call(
		absf(roundtrip.edge - 0.4) < EPS,
		"naive_play: state往復でedgeが保存される"
	)
	check.call(
		absf(NaivePlay.stats_from({"mass": 1.5, "radius": 0.7, "friction": 0.98,
			"restitution": 0.75, "rps": 15.0}).edge) < EPS,
		"naive_play: edgeキーの無い旧stateは0で読める"
	)


func _test_catalog_and_describe(check: Callable) -> void:
	var part := CustomPartCatalog.by_id(11)
	check.call(part != null, "カタログ: id=11(Sharp Edge)が引ける")
	if part == null:
		return
	check.call(part.effect == CustomPart.Effect.EDGE, "カタログ: id=11はEDGE効果")
	check.call(part.rarity == CustomPart.Rarity.COMMON, "カタログ: id=11はCOMMON(攻めの常連枠)")

	# 説明文。効果テキストだけで報酬を選ぶので、増強率と上限が読めること。
	var prev_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("ja")
	var desc := part.describe()
	check.call("20" in desc and "60" in desc, "説明文: 増強率20%%と上限60%%が読める (%s)" % desc)
	check.call(not ("質量" in desc), "説明文: STAT_MULTIPLY分岐に落ちて嘘をつかない")
	TranslationServer.set_locale("en")
	check.call(tr(part.title_key) != part.title_key, "訳: 英名がある")
	TranslationServer.set_locale("ja")
	check.call(tr(part.title_key) != part.title_key, "訳: 和名がある")
	TranslationServer.set_locale(prev_locale)

	# コールドプレイCLIの表記も嘘をつかないこと。
	var NaivePlay = load("res://playtest/naive_play.gd")
	var text: String = NaivePlay.card_text(part)
	check.call("相手" in text and "増強" in text, "naive_play: EDGE札は与ダメ増強を謳う (%s)" % text)
	check.call(not ("質量" in text), "naive_play: EDGE札の表記に質量が混ざらない")
