extends RefCounted

## 衝撃吸収(hit_guard / Shock Absorber札)のテスト。
##
## hit_guardは「コマ同士の衝突で受けるrps削りを減らす」防御ステータスで、
## 壁のwall_keep(RAGE札)と対になる。ここで固定するのは:
##  - 純関数guarded_spin_drainの向きとクランプ
##  - リゾルバが実際にhit_guardぶん削りを減らすこと(検証は1回衝突の理想環境で)
##  - GUARD札の加算と上限(重ねがけで衝突無敵にならない)
##  - シリアライズ往復(サーバー化とリプレイの前提)での保存
##  - 説明文と訳(効果テキストだけで報酬を選ぶコールドプレイの約束)

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_guarded_drain_function(check)
	_test_resolver_honors_hit_guard(check)
	_test_guard_part_stacks_with_cap(check)
	_test_stats_copy_and_serialization(check)
	_test_catalog_and_describe(check)


func _test_guarded_drain_function(check: Callable) -> void:
	check.call(
		absf(SpinnerPhysics.guarded_spin_drain(2.0, 0.0) - 2.0) < EPS,
		"guarded_spin_drain: hit_guard=0で削りは変わらない"
	)
	check.call(
		absf(SpinnerPhysics.guarded_spin_drain(2.0, 0.5) - 1.0) < EPS,
		"guarded_spin_drain: hit_guard=0.5で削りが半分になる"
	)
	# 範囲外はクランプ。1超で負の削り(回復)、負で削り増幅になってはいけない。
	check.call(
		absf(SpinnerPhysics.guarded_spin_drain(2.0, 1.5)) < EPS,
		"guarded_spin_drain: hit_guard>1は1でクランプ(削り0止まり、回復しない)"
	)
	check.call(
		absf(SpinnerPhysics.guarded_spin_drain(2.0, -0.5) - 2.0) < EPS,
		"guarded_spin_drain: 負のhit_guardは0でクランプ(削りが増えない)"
	)


## 正面衝突1回だけの理想環境を作る。自然減衰・傾斜を切り、短時間で打ち切るので、
## rpsの減少は衝突の削りだけになる。削りは衝突前の速さから決まり、衝突前の軌道は
## hit_guardに依存しないので、guard=0.5のランはguard=0のランのちょうど半分削られる。
func _one_hit_request(guard: float) -> BattleRequest:
	var pstats := SpinnerStats.default_player()
	pstats.hit_guard = guard
	var estats := SpinnerStats.new()
	estats.mass = 1.0
	estats.radius = 0.5
	estats.friction = 0.0
	estats.restitution = 1.0
	estats.rps = 15.0

	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	r.max_duration = 1.0
	r.player = BattleRequest.Launch.new(pstats, Vector2(3, 5), Vector2(4, 0))
	r.enemies = [BattleRequest.Launch.new(estats, Vector2(7, 5), Vector2(-4, 0))]
	return r


func _final_player_rps(result: BattleResult) -> float:
	return result.player_frames[result.player_frames.size() - 1].rps


func _test_resolver_honors_hit_guard(check: Callable) -> void:
	var base := BattleResolver.resolve(_one_hit_request(0.0))
	var guarded := BattleResolver.resolve(_one_hit_request(0.5))

	check.call(base.impacts.size() >= 1, "リゾルバ: 検証環境で衝突が起きている")
	var base_loss := SpinnerStats.default_player().rps - _final_player_rps(base)
	var guarded_loss := SpinnerStats.default_player().rps - _final_player_rps(guarded)
	check.call(base_loss > EPS, "リゾルバ: hit_guard=0では衝突でrpsが削られる")
	check.call(
		guarded_loss < base_loss - EPS,
		"リゾルバ: hit_guard=0.5は素より削られない (%.4f < %.4f)" % [guarded_loss, base_loss]
	)
	check.call(
		absf(guarded_loss - base_loss * 0.5) < EPS,
		"リゾルバ: 1回衝突の削りがちょうど(1-hit_guard)倍 (%.4f ≒ %.4f)" % [
			guarded_loss, base_loss * 0.5]
	)


func _test_guard_part_stacks_with_cap(check: Callable) -> void:
	var part := CustomPartCatalog.by_id(10)
	var stats := SpinnerStats.default_player()
	var before_mass := stats.mass
	var before_rps := stats.rps

	part.apply_to(stats)
	check.call(
		absf(stats.hit_guard - CustomPartCatalog.GUARD_HIT_STEP) < EPS,
		"GUARD札: 1枚でhit_guardが+%.2f" % CustomPartCatalog.GUARD_HIT_STEP
	)
	part.apply_to(stats)
	part.apply_to(stats)
	part.apply_to(stats)
	check.call(
		absf(stats.hit_guard - CustomPartCatalog.GUARD_HIT_MAX) < EPS,
		"GUARD札: 重ねがけは上限%.2fで頭打ち(衝突無敵にならない)" % CustomPartCatalog.GUARD_HIT_MAX
	)
	check.call(
		absf(stats.mass - before_mass) < EPS and absf(stats.rps - before_rps) < EPS,
		"GUARD札: 他のステータスには触らない"
	)


func _test_stats_copy_and_serialization(check: Callable) -> void:
	var stats := SpinnerStats.default_player()
	stats.hit_guard = 0.34

	# duplicate_statsの写し忘れはgreedy botの値踏み(probe)を静かに狂わせる。
	check.call(
		absf(stats.duplicate_stats().hit_guard - 0.34) < EPS,
		"duplicate_stats: hit_guardを写す"
	)

	# BattleRequestのdict往復。落ちるとリプレイ再現とサーバー化で別の勝敗になる。
	var launch := BattleRequest.Launch.new(stats, Vector2(1, 2), Vector2(3, 4))
	var revived := BattleRequest.Launch.from_dict(launch.to_dict())
	check.call(
		absf(revived.stats.hit_guard - 0.34) < EPS,
		"BattleRequest: dict往復でhit_guardが保存される"
	)

	# 旧いdict(キーなし)は既定0で読める(後方互換)。
	var old_dict := launch.to_dict()
	old_dict.erase("hit_guard")
	check.call(
		absf(BattleRequest.Launch.from_dict(old_dict).stats.hit_guard) < EPS,
		"BattleRequest: hit_guardキーの無い旧dictは0で読める"
	)

	# naive_play(コールドプレイCLI)のstate往復。落ちると札の主効果が次の
	# コマンドで消える(MOMENTUM/RAGEで実際に起きた事故の再発防止)。
	var NaivePlay = load("res://playtest/naive_play.gd")
	var roundtrip: SpinnerStats = NaivePlay.stats_from(NaivePlay.stats_dict(stats))
	check.call(
		absf(roundtrip.hit_guard - 0.34) < EPS,
		"naive_play: state往復でhit_guardが保存される"
	)
	check.call(
		absf(NaivePlay.stats_from({"mass": 1.5, "radius": 0.7, "friction": 0.98,
			"restitution": 0.75, "rps": 15.0}).hit_guard) < EPS,
		"naive_play: hit_guardキーの無い旧stateは0で読める"
	)


func _test_catalog_and_describe(check: Callable) -> void:
	var part := CustomPartCatalog.by_id(10)
	check.call(part != null, "カタログ: id=10(Shock Absorber)が引ける")
	if part == null:
		return
	check.call(part.effect == CustomPart.Effect.GUARD, "カタログ: id=10はGUARD効果")
	check.call(part.rarity == CustomPart.Rarity.COMMON, "カタログ: id=10はCOMMON(防御の常連枠)")

	# 説明文。効果テキストだけで報酬を選ぶので、軽減率と上限が読めること。
	var prev_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("ja")
	var desc := part.describe()
	check.call("17" in desc and "50" in desc, "説明文: 軽減率17%%と上限50%%が読める (%s)" % desc)
	check.call(not ("質量" in desc), "説明文: STAT_MULTIPLY分岐に落ちて嘘をつかない")
	TranslationServer.set_locale("en")
	check.call(tr(part.title_key) != part.title_key, "訳: 英名がある")
	TranslationServer.set_locale("ja")
	check.call(tr(part.title_key) != part.title_key, "訳: 和名がある")
	TranslationServer.set_locale(prev_locale)

	# コールドプレイCLIの表記も嘘をつかないこと。
	var NaivePlay = load("res://playtest/naive_play.gd")
	var text: String = NaivePlay.card_text(part)
	check.call("衝突" in text and "軽減" in text, "naive_play: GUARD札は衝突削り軽減を謳う (%s)" % text)
	check.call(not ("質量" in text), "naive_play: GUARD札の表記に質量が混ざらない")
	# 実UI(describe)と同じ%表記であること。生の「+0.17」は加算札の「回転+3.0」と
	# 並ぶと誤差にしか見えず、割合(17%軽減)だと読めないまま2回見送って、段5の
	# 僅差負け(敵残り4〜7%)3連発を落とした——が一次証拠。
	check.call("17%" in text and "50%" in text,
		"naive_play: GUARD札は実UIと同じ%%表記 (%s)" % text)
	check.call(not ("0.17" in text), "naive_play: GUARD札に生の小数を出さない (%s)" % text)
