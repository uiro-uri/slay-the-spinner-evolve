extends RefCounted

## 低重心(slope_grip / Low Center札)のテスト。
##
## slope_gripは「土俵の傾斜に自分だけ余分に引かれる」ステータスで、壁対策の
## 2本目の軸。RAGE(wall_keep)が「壁に当たった時の代償を軽くする」のに対し、
## こちらは中心へ引き戻す力を強めて「壁まで届く距離と、届いたときの速さ」を削る。
## 壁の喪失は進入速度に比例する(impact_scaled_wall_damping)ので、遅く着くこと
## 自体が軽減になる。
##
## ここで固定するのは:
##  - 純関数gripped_slope_strengthの向きとクランプ
##  - リゾルバが実際にgripぶん傾斜を強めること(外へ届く距離が縮む/壁の喪失が減る)
##  - grip=1.0が従来と厳密一致であること(既存の全戦闘を動かさない保証)
##  - GRIP札の加算と上限(重ねがけで壁に一切触れない無敵ビルドにならない)
##  - シリアライズ往復(サーバー化とリプレイの前提)での保存
##  - 説明文と訳(効果テキストだけで報酬を選ぶコールドプレイの約束)

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_strength_function(check)
	_test_resolver_pulls_harder(check)
	_test_resolver_identity_at_one(check)
	_test_wall_loss_drops(check)
	_test_grip_part_stacks_with_cap(check)
	_test_stats_copy_and_serialization(check)
	_test_catalog_and_describe(check)


func _test_strength_function(check: Callable) -> void:
	check.call(
		absf(SpinnerPhysics.gripped_slope_strength(8.0, 1.0) - 8.0) < EPS,
		"gripped_slope_strength: grip=1.0で傾斜は変わらない"
	)
	check.call(
		absf(SpinnerPhysics.gripped_slope_strength(8.0, 1.5) - 12.0) < EPS,
		"gripped_slope_strength: grip=1.5で傾斜が1.5倍"
	)
	# 負のgripは向きが反転して「中心から遠ざかる力」になる。デバフ札を置かない
	# カタログの原則(報酬は全部プラス)に反するので0で止める。
	check.call(
		absf(SpinnerPhysics.gripped_slope_strength(8.0, -1.0)) < EPS,
		"gripped_slope_strength: 負のgripは0でクランプ(斜面が反転しない)"
	)
	# 傾斜0の土俵(平面)はgripを掛けても平面のまま。
	check.call(
		absf(SpinnerPhysics.gripped_slope_strength(0.0, 2.0)) < EPS,
		"gripped_slope_strength: 傾斜0の土俵はgripでも平面のまま"
	)


## 決着が付くと解決が止まるので、隅に「動かない・尽きない」敵を1体だけ置く。
## 傾斜で滑ってこないよう、こちらのgripを0にして斜面から外す(接触は起きない)。
func _idle_enemy() -> BattleRequest.Launch:
	var estats := SpinnerStats.new()
	estats.radius = 0.5
	estats.friction = 0.0
	estats.rps = 1000.0
	estats.slope_grip = 0.0
	return BattleRequest.Launch.new(estats, Vector2(8.5, 8.5), Vector2.ZERO)


## 中心から真横へ撃ち出すだけの理想環境。摩擦も自然減衰も無いので、
## 外へどこまで届くかは傾斜だけで決まる(すり鉢＝バネなので最大変位は v/√k)。
func _outward_request(grip: float) -> BattleRequest:
	var pstats := SpinnerStats.default_player()
	pstats.friction = 0.0
	pstats.slope_grip = grip

	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 8.0
	r.stage_shape = SpinnerPhysics.StageShape.DISH
	r.max_duration = 2.0
	r.player = BattleRequest.Launch.new(pstats, Vector2(5, 5), Vector2(8, 0))
	r.enemies = [_idle_enemy()]
	return r


func _max_distance_from_center(result: BattleResult) -> float:
	var farthest := 0.0
	for frame in result.player_frames:
		farthest = maxf(farthest, frame.position.distance_to(Vector2(5, 5)))
	return farthest


func _test_resolver_pulls_harder(check: Callable) -> void:
	var plain := _max_distance_from_center(BattleResolver.resolve(_outward_request(1.0)))
	var gripped := _max_distance_from_center(BattleResolver.resolve(_outward_request(1.9)))
	check.call(plain > 1.0, "リゾルバ: 検証環境で実際に外まで届いている (%.3f)" % plain)
	check.call(
		gripped < plain - EPS,
		"リゾルバ: gripが高いほど外へ届かない (%.3f < %.3f)" % [gripped, plain]
	)
	# すり鉢(変位比例=バネ)の最大変位は v/√k なので、k を1.9倍すれば 1/√1.9 倍。
	# 向きだけでなく大きさまで見るのは、gripを「速度に掛ける」等の別の場所へ
	# 実装してしまっても向きの検査だけなら通ってしまうため。
	check.call(
		absf(gripped - plain / sqrt(1.9)) < 0.05,
		"リゾルバ: すり鉢の到達距離が 1/√grip 倍 (%.3f ≒ %.3f)" % [gripped, plain / sqrt(1.9)]
	)


## grip=1.0(既定)は従来の解決と厳密に一致すること。既存の全戦闘・保存済みの
## リプレイがこの変更で1ドットも動かないことの保証で、実装をstats経由でなく
## 一律に強めてしまう事故を捕まえる。
func _test_resolver_identity_at_one(check: Callable) -> void:
	var without := _outward_request(1.0)
	# slope_grip を触っていない素のstatsで組んだ同じ戦い。
	var pristine := _outward_request(1.0)
	pristine.player.stats.slope_grip = SpinnerStats.new().slope_grip
	var a := BattleResolver.resolve(without)
	var b := BattleResolver.resolve(pristine)
	var same := a.player_frames.size() == b.player_frames.size()
	if same:
		for i in a.player_frames.size():
			if not a.player_frames[i].position.is_equal_approx(b.player_frames[i].position):
				same = false
				break
	check.call(same, "リゾルバ: slope_gripの既定は1.0で、従来の軌道と一致する")


## 壁へ向かって撃ち、壁で失うrpsを比べる。gripが高いほど壁へ着くのが遅く
## (あるいは届かず)、進入速度比例の壁喪失が減る——これがこの札の本体。
func _wallward_request(grip: float) -> BattleRequest:
	var pstats := SpinnerStats.default_player()
	pstats.friction = 0.0
	pstats.slope_grip = grip

	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 8.0
	r.stage_shape = SpinnerPhysics.StageShape.DISH
	r.max_duration = 3.0
	r.player = BattleRequest.Launch.new(pstats, Vector2(5, 5), Vector2(14, 0))
	r.enemies = [_idle_enemy()]
	return r


func _test_wall_loss_drops(check: Callable) -> void:
	var plain := BattleResolver.resolve(_wallward_request(1.0))
	var gripped := BattleResolver.resolve(_wallward_request(1.9))
	var plain_loss: float = plain.player_rps_loss.get("wall", 0.0)
	var gripped_loss: float = gripped.player_rps_loss.get("wall", 0.0)
	check.call(
		plain.wall_impacts.size() > 0,
		"リゾルバ: 検証環境で実際に壁へ当たっている (%d回)" % plain.wall_impacts.size()
	)
	check.call(plain_loss > EPS, "リゾルバ: grip=1.0では壁でrpsを失う (%.3f)" % plain_loss)
	check.call(
		gripped_loss < plain_loss - EPS,
		"リゾルバ: gripが高いほど壁で失うrpsが減る (%.3f < %.3f)" % [gripped_loss, plain_loss]
	)


func _test_grip_part_stacks_with_cap(check: Callable) -> void:
	var part := CustomPartCatalog.by_id(14)
	var stats := SpinnerStats.default_player()
	var before_mass := stats.mass
	var before_rps := stats.rps

	part.apply_to(stats)
	check.call(
		absf(stats.slope_grip - (1.0 + CustomPartCatalog.GRIP_STEP)) < EPS,
		"GRIP札: 1枚でslope_gripが+%.2f (%.2f)" % [CustomPartCatalog.GRIP_STEP, stats.slope_grip]
	)
	for i in 6:
		part.apply_to(stats)
	check.call(
		absf(stats.slope_grip - CustomPartCatalog.GRIP_MAX) < EPS,
		"GRIP札: 重ねがけは上限%.2fで頭打ち(壁に触れない無敵ビルドにならない)" % (
			CustomPartCatalog.GRIP_MAX
		)
	)
	check.call(
		absf(stats.mass - before_mass) < EPS and absf(stats.rps - before_rps) < EPS,
		"GRIP札: 他のステータスには触らない"
	)
	# 上限に達した後は死にカード判定で提示から外れること(既存の仕組みへの接続)。
	check.call(
		not part.would_change_anything(stats),
		"GRIP札: 上限到達後は死にカードとして提示から外れる"
	)
	var fresh := SpinnerStats.default_player()
	check.call(part.would_change_anything(fresh), "GRIP札: 素のビルドでは有効")


func _test_stats_copy_and_serialization(check: Callable) -> void:
	var stats := SpinnerStats.default_player()
	stats.slope_grip = 1.6

	# duplicate_statsの写し忘れは死にカード判定(probeへapply_to)を静かに狂わせる。
	check.call(
		absf(stats.duplicate_stats().slope_grip - 1.6) < EPS,
		"duplicate_stats: slope_gripを写す"
	)

	# BattleRequestのdict往復。落ちるとリプレイ再現とサーバー化で別の勝敗になる。
	var launch := BattleRequest.Launch.new(stats, Vector2(1, 2), Vector2(3, 4))
	var revived := BattleRequest.Launch.from_dict(launch.to_dict())
	check.call(
		absf(revived.stats.slope_grip - 1.6) < EPS,
		"BattleRequest: dict往復でslope_gripが保存される"
	)

	# 旧いdict(キーなし)は既定1.0＝割り増しなしで読めること(後方互換)。
	var old_dict := launch.to_dict()
	old_dict.erase("slope_grip")
	check.call(
		absf(BattleRequest.Launch.from_dict(old_dict).stats.slope_grip - 1.0) < EPS,
		"BattleRequest: slope_gripキーの無い旧dictは1.0で読める"
	)

	# naive_play(コールドプレイCLI)のstate往復。落ちると札の主効果が次の
	# コマンドで消える(MOMENTUM/RAGEで実際に起きた事故の再発防止)。
	var NaivePlay = load("res://playtest/naive_play.gd")
	var roundtrip: SpinnerStats = NaivePlay.stats_from(NaivePlay.stats_dict(stats))
	check.call(
		absf(roundtrip.slope_grip - 1.6) < EPS,
		"naive_play: state往復でslope_gripが保存される"
	)
	check.call(
		absf(NaivePlay.stats_from({"mass": 1.5, "radius": 0.7, "friction": 0.98,
			"restitution": 0.75, "rps": 15.0}).slope_grip - 1.0) < EPS,
		"naive_play: slope_gripキーの無い旧stateは1.0で読める"
	)


func _test_catalog_and_describe(check: Callable) -> void:
	var part := CustomPartCatalog.by_id(14)
	check.call(part != null, "カタログ: id=14(Low Center)が引ける")
	if part == null:
		return
	check.call(part.effect == CustomPart.Effect.GRIP, "カタログ: id=14はGRIP効果")
	check.call(part.rarity == CustomPart.Rarity.COMMON, "カタログ: id=14はCOMMON(壁対策の常連枠)")

	# 壁の軸に札が2枚以上あること。1枚(RAGE)しか無かったせいで、敗因の半分が
	# 壁なのに対策が引き運任せだった(コールドプレイ2026-08-03: 決戦4連敗、
	# 14回の提示中RAGEは2回)。この本数が1に戻ったら気付けるようにする。
	var wall_parts := 0
	for p in CustomPartCatalog.all():
		if p.effect == CustomPart.Effect.RAGE or p.effect == CustomPart.Effect.GRIP:
			wall_parts += 1
	check.call(wall_parts >= 2, "カタログ: 壁に効く札が2枚以上ある (%d枚)" % wall_parts)

	# 説明文。効果テキストだけで報酬を選ぶので、効きと上限が読めること。
	var prev_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("ja")
	var desc := part.describe()
	check.call("40" in desc and "120" in desc, "説明文: 効き40%%と上限120%%が読める (%s)" % desc)
	check.call("壁" in desc, "説明文: 何に効くか(壁)が読める (%s)" % desc)
	check.call(not ("質量" in desc), "説明文: STAT_MULTIPLY分岐に落ちて嘘をつかない")
	TranslationServer.set_locale("en")
	check.call(tr(part.title_key) != part.title_key, "訳: 英名がある")
	TranslationServer.set_locale("ja")
	check.call(tr(part.title_key) != part.title_key, "訳: 和名がある")
	TranslationServer.set_locale(prev_locale)

	# コールドプレイCLIの表記も嘘をつかないこと。
	var NaivePlay = load("res://playtest/naive_play.gd")
	var text: String = NaivePlay.card_text(part)
	check.call("壁" in text, "naive_play: GRIP札は壁への効果を謳う (%s)" % text)
	check.call("40%" in text and "120%" in text,
		"naive_play: GRIP札は実UIと同じ%%表記 (%s)" % text)
	check.call(not ("0.4" in text), "naive_play: GRIP札に生の小数を出さない (%s)" % text)
