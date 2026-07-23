extends RefCounted

## ドリルビット(drill / Drill Bit札)のテスト。
##
## drillは「衝突ごとに相手の硬さ(質量×半径²)に依存しない追加削りを与える」
## 対巨体の攻めステータス。追加量は pierce(自分と同じ硬さの相手への素の削り)×drill。
## edge(乗算強化)は素の削りごと硬さ反比例で痩せるため、攻め特化ビルドが
## Lv4〜ボス帯で構造的に詰んでいた(edge0.60でボスに与0.6/hit vs 被1.5/hitで
## 6連敗、が一次証拠)。ここで固定するのは:
##  - 純関数drilled_spin_drainの向きとクランプ(drill=0で従来と厳密一致)
##  - リゾルバのdrillボーナスが相手の硬さに依存しないこと(1回衝突の理想環境)
##  - 受け手のhit_guardがdrillの追加分にも効くこと(貫通で防御札が無意味にならない)
##  - DRILL札の加算と上限(重ねがけで貫通が青天井にならない)
##  - シリアライズ往復(サーバー化とリプレイの前提)での保存
##  - 説明文と訳(効果テキストだけで報酬を選ぶコールドプレイの約束)

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_drilled_drain_function(check)
	_test_resolver_drill_vs_giants(check)
	_test_drill_and_guard_compose(check)
	_test_drill_part_stacks_with_cap(check)
	_test_stats_copy_and_serialization(check)
	_test_catalog_and_describe(check)


func _test_drilled_drain_function(check: Callable) -> void:
	check.call(
		absf(SpinnerPhysics.drilled_spin_drain(2.0, 0.0, 5.0) - 2.0) < EPS,
		"drilled_spin_drain: drill=0で削りは変わらない(従来と厳密一致)"
	)
	check.call(
		absf(SpinnerPhysics.drilled_spin_drain(2.0, 0.5, 4.0) - 4.0) < EPS,
		"drilled_spin_drain: drill=0.5でpierceの半分が上乗せされる"
	)
	# 素の削りがゼロ(超巨体)でも、drillぶんは必ず食い込む。
	check.call(
		absf(SpinnerPhysics.drilled_spin_drain(0.0, 1.0, 3.0) - 3.0) < EPS,
		"drilled_spin_drain: 素の削り0でもpierce×drillが丸ごと通る"
	)
	# 負のdrillは0でクランプ。削りを減らす方向には働かない(デバフ札を置かない原則)。
	check.call(
		absf(SpinnerPhysics.drilled_spin_drain(2.0, -0.5, 4.0) - 2.0) < EPS,
		"drilled_spin_drain: 負のdrillは0でクランプ(削りが減らない)"
	)
	# 負のpierceも0でクランプ(呼び出し側の事故に対して防御的に)。
	check.call(
		absf(SpinnerPhysics.drilled_spin_drain(2.0, 0.5, -4.0) - 2.0) < EPS,
		"drilled_spin_drain: 負のpierceは0でクランプ"
	)


## 巨体(自分より硬い相手)戦の1回衝突環境。test_sharp_edgeの_giant_requestと同じ
## 理想化: 自然減衰・傾斜を切り、壁を遠ざけ、短時間で打ち切る。敵のrps減少は
## 衝突の削りだけになり、衝突前の軌道はdrillに依存しないので、drillの追加分が
## そのまま差になって読める。
func _giant_request(player_drill: float, enemy_mass: float, enemy_guard: float = 0.0) -> BattleRequest:
	var pstats := SpinnerStats.default_player()
	pstats.drill = player_drill
	var estats := SpinnerStats.new()
	estats.mass = enemy_mass
	estats.radius = 0.5
	estats.friction = 0.0
	estats.restitution = 1.0
	estats.rps = 15.0
	estats.hit_guard = enemy_guard

	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	r.max_duration = 1.0
	r.arena_bounds = Rect2(-100, -100, 200, 200)
	r.player = BattleRequest.Launch.new(pstats, Vector2(3, 5), Vector2(4, 0))
	r.enemies = [BattleRequest.Launch.new(estats, Vector2(7, 5), Vector2(-4, 0))]
	return r


func _final_enemy_rps(result: BattleResult) -> float:
	var track: Array = result.enemy_tracks[0]
	return track[track.size() - 1].rps


## drillの追加削りは相手の硬さに依存しない。素の削りは硬さ反比例で痩せるが、
## drillボーナス(drill有り−無しの差)は攻め手自身のpierce基準なので、硬さを
## 倍にしても変わらない=巨体にもそのまま食い込む。
func _test_resolver_drill_vs_giants(check: Callable) -> void:
	# どちらもプレイヤー(硬さ mass1.5×0.7²=0.735)よりはるかに硬い巨体。
	var hard_bonus := (
		_final_enemy_rps(BattleResolver.resolve(_giant_request(0.0, 12.0)))
		- _final_enemy_rps(BattleResolver.resolve(_giant_request(1.0, 12.0)))
	)
	var harder_bonus := (
		_final_enemy_rps(BattleResolver.resolve(_giant_request(0.0, 24.0)))
		- _final_enemy_rps(BattleResolver.resolve(_giant_request(1.0, 24.0)))
	)
	check.call(
		hard_bonus > EPS,
		"リゾルバ: 巨体相手でもdrillは削りを実際に増やす (%.4f > 0)" % hard_bonus
	)
	check.call(
		absf(hard_bonus - harder_bonus) < EPS,
		"リゾルバ: drillボーナスは相手の硬さに依存しない (%.4f ≒ %.4f)" % [
			hard_bonus, harder_bonus]
	)
	# drill=0の素の削りは硬さ反比例のまま(drill導入が既存の削りを底上げしていない)。
	var hard_base := 15.0 - _final_enemy_rps(BattleResolver.resolve(_giant_request(0.0, 12.0)))
	var harder_base := 15.0 - _final_enemy_rps(BattleResolver.resolve(_giant_request(0.0, 24.0)))
	check.call(
		harder_base < hard_base - EPS,
		"リゾルバ: drill=0の素の削りは硬いほど小さいまま (%.4f < %.4f)" % [
			harder_base, hard_base]
	)


## 受け手のhit_guardはdrillの追加分にも効く(guardの内側でdrillが乗る)。
## 貫通が防御札を素通りすると、GUARDを積んだビルドだけ一方的に割を食う。
func _test_drill_and_guard_compose(check: Callable) -> void:
	var plain_loss := 15.0 - _final_enemy_rps(
		BattleResolver.resolve(_giant_request(1.0, 12.0)))
	var guarded_loss := 15.0 - _final_enemy_rps(
		BattleResolver.resolve(_giant_request(1.0, 12.0, 0.5)))
	check.call(
		absf(guarded_loss - plain_loss * 0.5) < EPS,
		"リゾルバ: hit_guard=0.5はdrill込みの削りを半減する (%.4f ≒ %.4f)" % [
			guarded_loss, plain_loss * 0.5]
	)


func _test_drill_part_stacks_with_cap(check: Callable) -> void:
	var part := CustomPartCatalog.by_id(13)
	var stats := SpinnerStats.default_player()
	var before_mass := stats.mass
	var before_rps := stats.rps
	var before_edge := stats.edge

	part.apply_to(stats)
	check.call(
		absf(stats.drill - CustomPartCatalog.DRILL_STEP) < EPS,
		"DRILL札: 1枚でdrillが+%.2f" % CustomPartCatalog.DRILL_STEP
	)
	part.apply_to(stats)
	part.apply_to(stats)
	part.apply_to(stats)
	check.call(
		absf(stats.drill - CustomPartCatalog.DRILL_MAX) < EPS,
		"DRILL札: 重ねがけは上限%.2fで頭打ち(貫通が青天井にならない)" % CustomPartCatalog.DRILL_MAX
	)
	check.call(
		absf(stats.mass - before_mass) < EPS and absf(stats.rps - before_rps) < EPS
			and absf(stats.edge - before_edge) < EPS,
		"DRILL札: 他のステータス(edge含む)には触らない"
	)
	# 上限到達後は死にカード(取っても何も変わらない)としてフィルタに弾かれること。
	check.call(
		not part.would_change_anything(stats),
		"DRILL札: 上限到達後はwould_change_anythingが偽(死にカード除外が効く)"
	)


func _test_stats_copy_and_serialization(check: Callable) -> void:
	var stats := SpinnerStats.default_player()
	stats.drill = 0.5

	# duplicate_statsの写し忘れはgreedy botの値踏み(probe)と死にカード判定を静かに狂わせる。
	check.call(
		absf(stats.duplicate_stats().drill - 0.5) < EPS,
		"duplicate_stats: drillを写す"
	)

	# BattleRequestのdict往復。落ちるとリプレイ再現とサーバー化で別の勝敗になる。
	var launch := BattleRequest.Launch.new(stats, Vector2(1, 2), Vector2(3, 4))
	var revived := BattleRequest.Launch.from_dict(launch.to_dict())
	check.call(
		absf(revived.stats.drill - 0.5) < EPS,
		"BattleRequest: dict往復でdrillが保存される"
	)

	# 旧いdict(キーなし)は既定0で読める(後方互換=過去の保存結果を同じ勝敗で再現)。
	var old_dict := launch.to_dict()
	old_dict.erase("drill")
	check.call(
		absf(BattleRequest.Launch.from_dict(old_dict).stats.drill) < EPS,
		"BattleRequest: drillキーの無い旧dictは0で読める"
	)

	# naive_play(コールドプレイCLI)のstate往復。落ちると札の主効果が次の
	# コマンドで消える(MOMENTUM/RAGEで実際に起きた事故の再発防止)。
	var NaivePlay = load("res://playtest/naive_play.gd")
	var roundtrip: SpinnerStats = NaivePlay.stats_from(NaivePlay.stats_dict(stats))
	check.call(
		absf(roundtrip.drill - 0.5) < EPS,
		"naive_play: state往復でdrillが保存される"
	)
	check.call(
		absf(NaivePlay.stats_from({"mass": 1.5, "radius": 0.7, "friction": 0.98,
			"restitution": 0.75, "rps": 15.0}).drill) < EPS,
		"naive_play: drillキーの無い旧stateは0で読める"
	)


func _test_catalog_and_describe(check: Callable) -> void:
	var part := CustomPartCatalog.by_id(13)
	check.call(part != null, "カタログ: id=13(Drill Bit)が引ける")
	if part == null:
		return
	check.call(part.effect == CustomPart.Effect.DRILL, "カタログ: id=13はDRILL効果")
	check.call(part.rarity == CustomPart.Rarity.COMMON,
		"カタログ: id=13はCOMMON(対巨体の対抗札が引き運のRAREでは詰みが残る)")

	# 説明文。効果テキストだけで報酬を選ぶので、貫通率・上限と
	# 核心(相手の硬さで減らない)が読めること。
	var prev_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("ja")
	var desc := part.describe()
	check.call("25" in desc and "75" in desc, "説明文: 貫通率25%%と上限75%%が読める (%s)" % desc)
	check.call("硬さ" in desc and "巨体" in desc,
		"説明文: 注記が「相手の硬さで減らない・巨体に食い込む」に触れる (%s)" % desc)
	check.call(not ("質量" in desc), "説明文: STAT_MULTIPLY分岐に落ちて嘘をつかない")
	TranslationServer.set_locale("en")
	check.call(tr(part.title_key) != part.title_key, "訳: 英名がある")
	TranslationServer.set_locale("ja")
	check.call(tr(part.title_key) != part.title_key, "訳: 和名がある")
	TranslationServer.set_locale(prev_locale)

	# コールドプレイCLIの表記も嘘をつかないこと。
	var NaivePlay = load("res://playtest/naive_play.gd")
	var text: String = NaivePlay.card_text(part)
	check.call("貫通" in text and "硬さ" in text,
		"naive_play: DRILL札は貫通と硬さ無視を謳う (%s)" % text)
	check.call(not ("質量" in text), "naive_play: DRILL札の表記に質量が混ざらない")
