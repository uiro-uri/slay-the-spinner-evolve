extends RefCounted

## custom_part.gd / custom_part_catalog.gd のテスト。

const TRIALS := 300

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_apply(check)
	_test_caps(check)
	_test_description_matches_effect(check)
	_test_selection(check)
	_test_rarity_weighting(check)
	_test_rarity_by_level(check)
	_test_titles_translated(check)
	_test_no_debuffs(check)
	_test_set_lives(check)
	_test_ghost(check)
	_test_rage(check)
	_test_growth(check)
	_test_dead_card_filter(check)
	_test_rejected_cooldown(check)
	_test_contact_trade_ceiling(check)
	_test_spin_up(check)


func _stats() -> SpinnerStats:
	var s := SpinnerStats.new()
	s.mass = 1.5
	s.radius = 0.5
	s.friction = 0.98
	s.restitution = 1.0
	s.rps = 15.0
	return s


func _test_apply(check: Callable) -> void:
	var s := _stats()
	CustomPart.make(0, "T", CustomPart.Rarity.COMMON, CustomPart.Stat.MASS, 0.5).apply_to(s)
	check.call(is_equal_approx(s.mass, 0.75), "パーツ: 質量が半分になる (%.3f)" % s.mass)

	s = _stats()
	CustomPart.make(0, "T", CustomPart.Rarity.COMMON, CustomPart.Stat.RADIUS, 2.0).apply_to(s)
	check.call(is_equal_approx(s.radius, 1.0), "パーツ: 直径が倍になる (%.3f)" % s.radius)

	# 名前どおり「勢いを保つ」＝摩擦(速度減衰)と回転減衰の両方が減ること。
	# 摩擦だけ下げていた頃は戦績ほぼ0の死に札だったので、回転減衰にも効かせた。
	var before_friction := _stats().friction
	var before_decay := _stats().spin_decay
	s = _stats()
	CustomPartCatalog.by_id(5).apply_to(s)
	check.call(
		s.friction < before_friction,
		"パーツ: Full Steam Aheadで摩擦が減る (%.3f -> %.3f)" % [before_friction, s.friction]
	)
	check.call(
		s.spin_decay < before_decay,
		"パーツ: Full Steam Aheadで回転減衰も減る (%.3f -> %.3f)" % [before_decay, s.spin_decay]
	)
	# spin_decayは下限FULL_STEAM_FLOORでクランプ(重ねても無限には回らない)。
	s = _stats()
	for i in 12:
		CustomPartCatalog.by_id(5).apply_to(s)
	check.call(
		s.spin_decay >= CustomPartCatalog.FULL_STEAM_FLOOR - EPS,
		"パーツ: Full Steamのspin_decayが下限%.2fで止まる (%.3f)" % [
			CustomPartCatalog.FULL_STEAM_FLOOR, s.spin_decay
		]
	)

	# 掛け算なので繰り返し取ると積み上がる
	s = _stats()
	var part := CustomPart.make(0, "T", CustomPart.Rarity.COMMON, CustomPart.Stat.MASS, 2.0)
	part.apply_to(s)
	part.apply_to(s)
	check.call(is_equal_approx(s.mass, 6.0), "パーツ: 重ねがけで積み上がる (%.3f)" % s.mass)


func _test_caps(check: Callable) -> void:
	# 上限を超えない
	var s := _stats()
	s.rps = 39.0
	CustomPartCatalog.by_id(7).apply_to(s)
	check.call(
		is_equal_approx(s.rps, CustomPartCatalog.RPS_CAP),
		"パーツ: 回転数が上限%.0fで止まる (%.2f)" % [CustomPartCatalog.RPS_CAP, s.rps]
	)

	s = _stats()
	s.restitution = 1.95
	CustomPartCatalog.by_id(6).apply_to(s)
	check.call(
		is_equal_approx(s.restitution, CustomPartCatalog.RESTITUTION_CAP),
		"パーツ: 反発が上限%.1fで止まる (%.2f)" % [CustomPartCatalog.RESTITUTION_CAP, s.restitution]
	)

	# 上限に届かないうちは普通に掛かる
	s = _stats()
	s.rps = 10.0
	var spin: CustomPart = CustomPartCatalog.by_id(7)
	spin.apply_to(s)
	check.call(
		is_equal_approx(s.rps, 10.0 * spin.multiplier),
		"パーツ: 上限未満なら倍率どおり (%.2f)" % s.rps
	)

	# 報酬は全部プラスなので、取るほど強くなる一方。上限がないと
	# アリーナをコマが埋め尽くすので、伸びるステータスには全部上限がある。
	for part in CustomPartCatalog.all():
		if part.multiplier > 1.0:
			check.call(
				part.cap > 0.0,
				"パーツ%d(%s): 強化札には上限がある" % [part.id, part.title_key]
			)
		# GROWTHの質量側も同じ理屈で上限が要る(青天井なら複利で発散する)。
		if part.mass_multiplier > 1.0:
			check.call(
				part.mass_cap > 0.0,
				"パーツ%d(%s): 質量強化にも上限がある" % [part.id, part.title_key]
			)


## 説明文が実際の効果と食い違わないこと。
##
## プロトタイプは説明文が手書きで、2回嘘になっていた(「50%上昇(最大20)」で
## 実際は上限40、その後「10%上昇」と書いて実際は1.2倍=20%)。しかも直前の
## コミットが「パーツ説明が嘘だったので修正」。生成にした狙いはここなので、
## 実際に数値を適用した結果と説明文の数字が一致することまで確かめる。
func _test_description_matches_effect(check: Callable) -> void:
	TranslationServer.set_locale("en")
	for part in CustomPartCatalog.all():
		var text := part.describe()

		# 説明にキーがそのまま出ていない＝訳がある
		if text.contains("PART_EFFECT"):
			check.call(false, "パーツ%d: 効果の訳がない (%s)" % [part.id, text])
			continue

		# 残機札は倍率でも注記でもなく、引き上げ先の残機を出す単行の説明。
		# 倍率・上限・注記・改行の検査はステータス札向けなので飛ばす。
		if part.effect == CustomPart.Effect.SET_LIVES:
			check.call(
				text.contains(str(part.lives)),
				"パーツ%d(%s): 残機の説明に数値が出ている (%s に %d)" % [
					part.id, part.title_key, text, part.lives
				]
			)
			continue

		# ゴーストは倍率を持たない。説明に無敵秒数が出ていることだけ確かめる。
		if part.effect == CustomPart.Effect.GHOST:
			check.call(
				text.contains(CustomPart._trim(part.ghost_seconds)),
				"パーツ%d(%s): 説明に無敵秒数が出ている (%s)" % [part.id, part.title_key, text]
			)
			continue

		# 勢い維持は摩擦と回転減衰の両方に効く。倍率と、挙動注記(回転が長持ち=
		# 寿命が延びる)が出ていることを確かめる(capはspin_decayの下限であって
		# 表示する上限ではない)。「摩擦×0.8」だけでは下がる=良いことが初見に
		# 読めない札だった。
		if part.effect == CustomPart.Effect.MOMENTUM:
			check.call(
				text.contains(CustomPart._trim(part.multiplier)),
				"パーツ%d(%s): 勢い維持の説明に倍率が出ている (%s)" % [part.id, part.title_key, text]
			)
			check.call(
				not text.contains("PART_NOTE") and text.contains("\n")
					and text.to_lower().contains("longer"),
				"パーツ%d(%s): 勢い維持の注記が長持ち(lasts longer)に触れる (%s)" % [
					part.id, part.title_key, text
				]
			)
			continue

		# 衝撃吸収は倍率でなく軽減率(%)と上限(%)の単行の説明。両方の数字が
		# 出ていることを確かめる(倍率・注記・改行の検査はステータス札向け)。
		if part.effect == CustomPart.Effect.GUARD:
			check.call(
				text.contains(CustomPart._trim(part.hit_guard_step * 100.0))
					and text.contains(CustomPart._trim(part.hit_guard_max * 100.0)),
				"パーツ%d(%s): 衝撃吸収の説明に軽減率と上限が出ている (%s)" % [
					part.id, part.title_key, text
				]
			)
			continue

		# シャープエッジもGUARDと同型の増強率(%)と上限(%)の単行の説明。
		if part.effect == CustomPart.Effect.EDGE:
			check.call(
				text.contains(CustomPart._trim(part.edge_step * 100.0))
					and text.contains(CustomPart._trim(part.edge_max * 100.0)),
				"パーツ%d(%s): シャープエッジの説明に増強率と上限が出ている (%s)" % [
					part.id, part.title_key, text
				]
			)
			continue

		# 巨大化は直径と質量の複合。両方の倍率と、代償(自然減衰の悪化)の注記が
		# 出ていることを確かめる。旧版(直径のみ)は代償が読めない罠札だった。
		if part.effect == CustomPart.Effect.GROWTH:
			check.call(
				text.contains(CustomPart._trim(part.multiplier))
					and text.contains(CustomPart._trim(part.mass_multiplier)),
				"パーツ%d(%s): 巨大化の説明に直径と質量の倍率が出ている (%s)" % [
					part.id, part.title_key, text
				]
			)
			check.call(
				not text.contains("PART_NOTE") and text.contains("\n")
					and text.to_lower().contains("decay"),
				"パーツ%d(%s): 巨大化の注記が自然減衰の代償に触れる (%s)" % [
					part.id, part.title_key, text
				]
			)
			continue

		# 回転加算は倍率でなく加算量と上限の説明。両方の数字と、挙動注記
		# (寿命が延びる=lasts longer)が出ていることを確かめる。
		if part.effect == CustomPart.Effect.SPIN_UP:
			check.call(
				text.contains(CustomPart._trim(part.rps_step))
					and text.contains(CustomPart._trim(part.cap)),
				"パーツ%d(%s): 回転加算の説明に加算量と上限が出ている (%s)" % [
					part.id, part.title_key, text
				]
			)
			check.call(
				not text.contains("PART_NOTE") and text.contains("\n")
					and text.to_lower().contains("longer"),
				"パーツ%d(%s): 回転加算の注記が寿命(lasts longer)に触れる (%s)" % [
					part.id, part.title_key, text
				]
			)
			continue

		# 怒りの反射は反発倍率と壁rps保持の複合。反発倍率が出ていることを確かめる。
		if part.effect == CustomPart.Effect.RAGE:
			check.call(
				text.contains(CustomPart._trim(part.multiplier)),
				"パーツ%d(%s): 怒りの反射の説明に反発倍率が出ている (%s)" % [part.id, part.title_key, text]
			)
			continue

		# 説明に書かれた倍率が、実際に適用される倍率と一致すること
		var shown := CustomPart._trim(part.multiplier)
		check.call(
			text.contains(shown),
			"パーツ%d(%s): 説明の倍率が実際と一致 (%s に %s)" % [part.id, part.title_key, text, shown]
		)

		# 上限があるなら説明にも出ていること
		if part.cap > 0.0:
			check.call(
				text.contains(CustomPart._trim(part.cap)),
				"パーツ%d: 説明に上限が出ている (%s)" % [part.id, text]
			)

		# 倍率だけでは挙動が読めないので、実際の効果を一言添えている。
		# キーが素のまま残っている＝訳がない、を弾く。現行パーツは全部
		# 倍率≠1なので必ず注記が付く。
		check.call(
			not text.contains("PART_NOTE"),
			"パーツ%d(%s): 効果注記の訳がある (%s)" % [part.id, part.title_key, text]
		)
		check.call(
			text.contains("\n"),
			"パーツ%d(%s): 倍率行に続けて効果注記が付く (%s)" % [part.id, part.title_key, text]
		)

	# 半径は上げると衝突被害が減る一方で自然減衰が上がる二面性がある。
	# 倍率だけでは伝わらないので、その挙動が注記に出ていることをピンする。
	var radius_part := CustomPart.make(
		0, "T", CustomPart.Rarity.COMMON, CustomPart.Stat.RADIUS, 1.35
	)
	var radius_note := radius_part.describe().to_lower()
	check.call(
		radius_note.contains("decay"),
		"パーツ: 半径UPの注記が自然減衰に触れる (%s)" % radius_note
	)
	TranslationServer.set_locale("ja")
	check.call(
		radius_part.describe().contains("減衰"),
		"パーツ: 半径UPの注記(ja)が減衰に触れる (%s)" % radius_part.describe()
	)

	# 勢い維持(MOMENTUM)の注記もja側をピンする。enは上のカタログ一巡で確認済み。
	var momentum_part := CustomPart.make_momentum(
		0, "T", CustomPart.Rarity.COMMON, 0.8, 0.4
	)
	check.call(
		momentum_part.describe().contains("長持ち"),
		"パーツ: 勢い維持の注記(ja)が長持ちに触れる (%s)" % momentum_part.describe()
	)


func _test_selection(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	var dup_seen := false
	var wrong_count := false
	for trial in TRIALS:
		rng.seed = trial
		var picks := CustomPartCatalog.pick_choices(3, rng)
		if picks.size() != 3:
			wrong_count = true
		var ids := {}
		for p in picks:
			if ids.has(p.id):
				dup_seen = true
			ids[p.id] = true

	check.call(not wrong_count, "パーツ抽選: 常に指定した枚数を返す")
	check.call(not dup_seen, "パーツ抽選: %d回引いて重複が出ない" % TRIALS)

	# プロトタイプは引数nを無視して常に3個だった。ここは指定どおりになる。
	rng.seed = 1
	check.call(CustomPartCatalog.pick_choices(2, rng).size() == 2, "パーツ抽選: 2枚を頼めば2枚返る")
	rng.seed = 1
	check.call(CustomPartCatalog.pick_choices(1, rng).size() == 1, "パーツ抽選: 1枚を頼めば1枚返る")
	# 母集団より多く頼まれても壊れない
	rng.seed = 1
	var everything := CustomPartCatalog.pick_choices(99, rng)
	check.call(
		everything.size() == CustomPartCatalog.all().size(),
		"パーツ抽選: 母集団より多く頼まれても全部返して止まる (%d枚)" % everything.size()
	)


func _test_rarity_weighting(check: Callable) -> void:
	# レアはcommonより出にくいこと。厳密な比率ではなく向きだけ見る。
	var rng := RandomNumberGenerator.new()
	var rare_hits := 0
	var common_hits := 0
	for trial in TRIALS:
		rng.seed = trial + 5000
		for part in CustomPartCatalog.pick_choices(1, rng):
			if part.rarity == CustomPart.Rarity.RARE:
				rare_hits += 1
			else:
				common_hits += 1

	check.call(
		rare_hits < common_hits,
		"パーツ抽選: レアはcommonより出にくい (rare=%d common=%d)" % [rare_hits, common_hits]
	)
	check.call(rare_hits > 0, "パーツ抽選: レアもちゃんと出る (%d回)" % rare_hits)


## 倒した敵のレベルが高いほどレアが出やすいこと。厳密な比率ではなく向きだけ見る。
func _test_rarity_by_level(check: Callable) -> void:
	var low_rares := _count_rares(1)
	var high_rares := _count_rares(5)
	check.call(
		high_rares > low_rares,
		"パーツ抽選: 高レベルほどレアが出やすい (lv1=%d lv5=%d)" % [low_rares, high_rares]
	)
	check.call(
		CustomPartCatalog.rare_weight_for_level(1) < CustomPartCatalog.rare_weight_for_level(5),
		"パーツ抽選: RAREの重みは高レベルで増える (%d < %d)" % [
			CustomPartCatalog.rare_weight_for_level(1), CustomPartCatalog.rare_weight_for_level(5)
		]
	)


## そのレベルで1枚引きをTRIALS回して、レアを引いた回数を返す。
func _count_rares(level: int) -> int:
	var rng := RandomNumberGenerator.new()
	var rares := 0
	for trial in TRIALS:
		rng.seed = trial + 9000
		for part in CustomPartCatalog.pick_choices(1, rng, level):
			if part.rarity == CustomPart.Rarity.RARE:
				rares += 1
	return rares


func _test_titles_translated(check: Callable) -> void:
	TranslationServer.set_locale("ja")
	var untranslated: Array[String] = []
	for part in CustomPartCatalog.all():
		if tr(part.title_key) == part.title_key:
			untranslated.append(part.title_key)
	check.call(untranslated.is_empty(), "パーツ: 名前に訳がある (未訳: %s)" % [untranslated])


## 報酬にマイナスの札が混じっていないこと。
##
## プロトタイプには Gravity Negator(質量×0.5) と Shrink(直径×0.5) があり、
## どちらも純粋なデバフだった。特に半径は削られるRPSに2乗で効くので、
## Shrinkは耐えられる衝突回数を1/4にする。勝った報酬の3枚に自分を弱くする
## 札が混じっているのは罠でしかない。
##
## 「マイナス」は名前ではなく実際の効果で判定する。硬さ(rps×質量×半径²)が
## 下がる札は、何と名乗っていてもデバフ。
func _test_no_debuffs(check: Callable) -> void:
	for part in CustomPartCatalog.all():
		var before := _stats()
		var after := _stats()
		part.apply_to(after)

		var tough_before := before.rps * before.mass * before.radius * before.radius
		var tough_after := after.rps * after.mass * after.radius * after.radius
		check.call(
			tough_after >= tough_before - EPS,
			"パーツ%d(%s): 硬さを下げない (%.2f -> %.2f)" % [
				part.id, part.title_key, tough_before, tough_after
			]
		)

		# 硬さに関わらないステータス(摩擦・反発)も、悪い方へ動かさない
		check.call(
			after.friction <= before.friction + EPS,
			"パーツ%d(%s): 摩擦を増やさない (%.3f -> %.3f)" % [
				part.id, part.title_key, before.friction, after.friction
			]
		)
		check.call(
			after.restitution >= before.restitution - EPS,
			"パーツ%d(%s): 反発を減らさない (%.3f -> %.3f)" % [
				part.id, part.title_key, before.restitution, after.restitution
			]
		)

	# 反発の上限は1.0以下であること。超えると壁で跳ねるたびに加速して発散する。
	check.call(
		CustomPartCatalog.RESTITUTION_CAP <= 1.0,
		"反発の上限が1.0以下 (%.2f)。超えると壁で加速して発散する" % CustomPartCatalog.RESTITUTION_CAP
	)


## ゴースト札。ステータスは変えず、無敵時間だけを枚数に比例して伸ばす。
func _test_ghost(check: Callable) -> void:
	var ghost := CustomPartCatalog.by_id(9)
	check.call(ghost != null, "ゴースト: カタログにID9がある")
	check.call(
		ghost.effect == CustomPart.Effect.GHOST,
		"ゴースト: 効果種別がGHOST"
	)

	# apply_toはステータスを一切変えない。
	var before := _stats()
	var after := _stats()
	ghost.apply_to(after)
	check.call(
		is_equal_approx(after.mass, before.mass)
		and is_equal_approx(after.radius, before.radius)
		and is_equal_approx(after.friction, before.friction)
		and is_equal_approx(after.restitution, before.restitution)
		and is_equal_approx(after.rps, before.rps),
		"ゴースト: apply_toはステータスを変えない"
	)

	# 説明が訳されていること(キーが素で出ていない)。
	TranslationServer.set_locale("ja")
	check.call(
		ghost.describe() != "PART_EFFECT_GHOST" and not ghost.describe().contains("PART_EFFECT"),
		"ゴースト: 説明に訳がある (%s)" % ghost.describe()
	)

	# 合計無敵時間は枚数×1枚あたり秒数。ゴースト以外のIDは無視する。
	var per := CustomPartCatalog.GHOST_SECONDS_PER_STACK
	check.call(
		is_equal_approx(CustomPartCatalog.total_ghost_seconds([] as Array[int]), 0.0),
		"ゴースト: 未取得なら0秒"
	)
	check.call(
		is_equal_approx(CustomPartCatalog.total_ghost_seconds([9] as Array[int]), per),
		"ゴースト: 1枚で%.1f秒 (%.2f)" % [per, CustomPartCatalog.total_ghost_seconds([9] as Array[int])]
	)
	check.call(
		is_equal_approx(CustomPartCatalog.total_ghost_seconds([9, 9] as Array[int]), per * 2.0),
		"ゴースト: 2枚で%.1f秒 (線形延長)" % [per * 2.0]
	)
	# ステータス札(ID2)も残機札(ID8)もゴーストではないので無敵時間に数えない。
	check.call(
		is_equal_approx(CustomPartCatalog.total_ghost_seconds([2, 8, 9] as Array[int]), per),
		"ゴースト: 非ゴースト札(ID2/ID8)は無敵時間に数えない"
	)


## 残機を引き上げる札(スペアコア)の検証。コマの性能には触らず、GameState.apply_partで
## コンティニュー回数を底上げする。上書きではなくmaxiなので既に多ければ下げない。
##
## GameStateはオートロードだが、--scriptランナーではツリーに載らず参照できないので、
## ここではスクリプトを直接new()した独立インスタンスで検証する（グローバルも汚さない）。
const GameStateScript := preload("res://autoloads/GameState.gd")


## 怒りの反射(RAGE)札。反発を上げつつ(cap上限)、壁rps保持(wall_keep)も上げる複合。
func _test_rage(check: Callable) -> void:
	var rage := CustomPartCatalog.by_id(6)
	check.call(rage.effect == CustomPart.Effect.RAGE, "怒りの反射: 効果種別がRAGE")

	# 1枚で反発が上がり、壁rps保持も上がる（複合）。
	# 実プレイの初期反発は0.75(上限1.0未満)なので、そこから上がることを見る。
	var s := _stats()
	s.restitution = 0.75
	var before_rest := s.restitution
	var before_keep := s.wall_keep
	rage.apply_to(s)
	check.call(s.restitution > before_rest, "怒りの反射: 反発が上がる (%.3f -> %.3f)" % [before_rest, s.restitution])
	check.call(s.wall_keep > before_keep, "怒りの反射: 壁rps保持が上がる (%.3f -> %.3f)" % [before_keep, s.wall_keep])

	# 反発はRESTITUTION_CAP(1.0)を超えない。壁rps保持はRAGE_WALL_KEEP_MAXで頭打ち
	# (1.0=完全無損失まで許すと無敵化するため低く抑える)。
	s = _stats()
	for i in 10:
		rage.apply_to(s)
	check.call(
		s.restitution <= CustomPartCatalog.RESTITUTION_CAP + EPS,
		"怒りの反射: 反発が上限%.1fで止まる (%.3f)" % [CustomPartCatalog.RESTITUTION_CAP, s.restitution]
	)
	check.call(
		s.wall_keep <= CustomPartCatalog.RAGE_WALL_KEEP_MAX + EPS,
		"怒りの反射: 壁rps保持が上限%.2fで止まる (%.3f)" % [CustomPartCatalog.RAGE_WALL_KEEP_MAX, s.wall_keep]
	)
	check.call(
		s.wall_keep >= CustomPartCatalog.RAGE_WALL_KEEP_MAX - EPS,
		"怒りの反射: 重ねがけで壁rps保持が上限へ届く (%.3f)" % s.wall_keep
	)
	check.call(
		CustomPartCatalog.RAGE_WALL_KEEP_MAX < 1.0,
		"怒りの反射: 壁rps保持の上限は1.0未満(完全無損失=無敵化を防ぐ) (%.2f)" % CustomPartCatalog.RAGE_WALL_KEEP_MAX
	)


## 巨大化(GROWTH)札。直径と質量の両方が上がる複合。直径だけ(旧GIANT_GROWTH)は
## 自然減衰の悪化が上回る唯一の純マイナス札=罠だったので、質量で釣り合わせた。
func _test_growth(check: Callable) -> void:
	var growth := CustomPartCatalog.by_id(2)
	check.call(growth.effect == CustomPart.Effect.GROWTH, "巨大化: 効果種別がGROWTH")

	# 1枚で直径と質量の両方が上がる(複合)。
	var s := _stats()
	var before_radius := s.radius
	var before_mass := s.mass
	growth.apply_to(s)
	check.call(
		s.radius > before_radius,
		"巨大化: 直径が上がる (%.3f -> %.3f)" % [before_radius, s.radius]
	)
	check.call(
		s.mass > before_mass,
		"巨大化: 質量も上がる (%.3f -> %.3f)" % [before_mass, s.mass]
	)
	check.call(
		is_equal_approx(s.radius, before_radius * growth.multiplier),
		"巨大化: 直径は倍率どおり (%.3f)" % s.radius
	)
	check.call(
		is_equal_approx(s.mass, before_mass * growth.mass_multiplier),
		"巨大化: 質量は倍率どおり (%.3f)" % s.mass
	)

	# 重ねがけしても両方の上限で止まる(直径はアリーナ埋め尽くし、質量は複利発散を防ぐ)。
	s = _stats()
	for i in 20:
		growth.apply_to(s)
	check.call(
		s.radius <= CustomPartCatalog.RADIUS_CAP + EPS,
		"巨大化: 直径が上限%.1fで止まる (%.3f)" % [CustomPartCatalog.RADIUS_CAP, s.radius]
	)
	check.call(
		s.mass <= CustomPartCatalog.MASS_CAP + EPS,
		"巨大化: 質量が上限%.1fで止まる (%.3f)" % [CustomPartCatalog.MASS_CAP, s.mass]
	)

	# 説明(ja)が両方の倍率を出し、注記が代償(自然減衰)に触れること。
	TranslationServer.set_locale("ja")
	var text := growth.describe()
	check.call(
		text.contains(CustomPart._trim(growth.multiplier))
			and text.contains(CustomPart._trim(growth.mass_multiplier)),
		"巨大化: 説明(ja)に直径と質量の倍率が出る (%s)" % text
	)
	check.call(
		text.contains("減衰"),
		"巨大化: 注記(ja)が自然減衰の代償に触れる (%s)" % text
	)
	# 注記は利点(衝突耐性と弾き)も必ず謳うこと。代償だけの文は、タンク型の敵への
	# 唯一の対抗札を「デメリット札」と読ませる罠になる(コールドプレイの一次証拠)。
	check.call(
		text.contains("衝突に強く") and text.contains("弾く"),
		"巨大化: 注記(ja)が利点(衝突耐性と弾き)にも触れる (%s)" % text
	)
	# 代償の由来(大きくなるぶん)を明示すること。自然減衰の悪化は半径経由なので、
	# ステータスのspin_decay表示は1.00のまま変わらず、無条件の「自然減衰が上がる」
	# 表記は表示と食い違って見えていた。
	check.call(
		text.contains("大きくなる"),
		"巨大化: 注記(ja)が代償の由来(大きさ)を明示する (%s)" % text
	)


func _test_set_lives(check: Callable) -> void:
	var part := CustomPart.make_set_lives(8, "PART_SPARE_CORE", CustomPart.Rarity.RARE, 5)
	check.call(part.effect == CustomPart.Effect.SET_LIVES, "残機札: 効果種別がSET_LIVES")
	check.call(part.lives == 5, "残機札: 引き上げ先が5 (%d)" % part.lives)

	# コマの性能には一切触らない。倍率/上限を非1に汚してもSET_LIVESなら書き込まない
	# ＝apply_toのガードが効いていることの検証（倍率が既定1.0だと恒等で素通りしてしまう）。
	var tampered := CustomPart.make_set_lives(8, "PART_SPARE_CORE", CustomPart.Rarity.RARE, 5)
	tampered.multiplier = 2.0
	tampered.cap = 99.0
	var s := _stats()
	var base := _stats()
	tampered.apply_to(s)
	check.call(
		is_equal_approx(s.mass, base.mass) and is_equal_approx(s.radius, base.radius)
		and is_equal_approx(s.friction, base.friction)
		and is_equal_approx(s.restitution, base.restitution)
		and is_equal_approx(s.rps, base.rps),
		"残機札: ステータスを一切変えない (mass=%.3f radius=%.3f rps=%.3f)" % [s.mass, s.radius, s.rps]
	)

	# 説明に引き上げ先の数値が出る（en/jaとも）。
	TranslationServer.set_locale("en")
	check.call(part.describe().contains("5"), "残機札: 説明(en)に5が出る (%s)" % part.describe())
	TranslationServer.set_locale("ja")
	check.call(part.describe().contains("5"), "残機札: 説明(ja)に5が出る (%s)" % part.describe())

	var gs: Node = GameStateScript.new()

	# apply_partで残機が引き上がり、取得IDに残る。
	gs.reset_run()
	check.call(
		gs.continues_left == GameStateScript.MAX_CONTINUES,
		"残機札: 適用前は初期コンティニュー数 (%d)" % gs.continues_left
	)
	gs.apply_part(part)
	check.call(gs.continues_left == 5, "残機札: 適用後は残機5 (%d)" % gs.continues_left)
	check.call(gs.acquired_part_ids.has(8), "残機札: 取得IDに8が残る")

	# 底上げのみ。既に5超なら下げない（上書き実装なら5へ下がって落ちる）。
	gs.continues_left = 7
	gs.apply_part(part)
	check.call(gs.continues_left == 7, "残機札: 既に多ければ下げない (%d)" % gs.continues_left)

	# ステータス札はapply_partでも残機を動かさない（lives=0）が、性能は上がる。
	gs.reset_run()
	var before_rps: float = gs.player_stats.rps
	var stat_part: CustomPart = CustomPartCatalog.by_id(7)  # Spin Engine (rps×1.25)
	gs.apply_part(stat_part)
	check.call(
		gs.continues_left == GameStateScript.MAX_CONTINUES,
		"残機札: ステータス札は残機を変えない (%d)" % gs.continues_left
	)
	check.call(
		gs.player_stats.rps > before_rps,
		"残機札: ステータス札はちゃんと性能を上げる (%.2f -> %.2f)" % [before_rps, gs.player_stats.rps]
	)

	gs.free()
	TranslationServer.set_locale("ja")


## 死にカード除外: 上限に達して効果ゼロになった札は、statsを渡した抽選から出ない。
## 今回のコールドプレイでrps上限40到達後もSPIN_ENGINEが提示され続け、
## 「取っても何も起きない札」で報酬選択が腐ったのが動機。
func _test_dead_card_filter(check: Callable) -> void:
	# rpsが上限40のとき: SPIN_ENGINE(id=7)は適用しても何も変わらない=死にカード。
	var capped := _stats()
	capped.rps = SpinnerStats.RPS_CAP
	check.call(
		not CustomPartCatalog.by_id(7).would_change_anything(capped),
		"死にカード: rps上限でSPIN_ENGINEは効果なし判定"
	)
	# 初期性能なら全札が有効(死にカードなし)。
	var fresh := SpinnerStats.default_player()
	var all_alive := true
	for part in CustomPartCatalog.all():
		if not part.would_change_anything(fresh, 3):
			all_alive = false
	check.call(all_alive, "死にカード: 初期性能では全札が有効")

	# 抽選: rps上限のstatsを渡すと、何度引いてもSPIN_ENGINEが出ない。
	var rng := RandomNumberGenerator.new()
	var spin_engine_offered := false
	for trial in TRIALS:
		rng.seed = trial + 20000
		for part in CustomPartCatalog.pick_choices(3, rng, 5, capped, 3):
			if part.id == 7:
				spin_engine_offered = true
	check.call(
		not spin_engine_offered,
		"死にカード: rps上限の抽選%d回でSPIN_ENGINEが一度も提示されない" % TRIALS
	)
	# statsを渡さない従来の呼び出しでは出る(除外はopt-in。既存挙動の回帰確認)。
	var offered_without_stats := false
	for trial in TRIALS:
		rng.seed = trial + 20000
		for part in CustomPartCatalog.pick_choices(3, rng, 5):
			if part.id == 7:
				offered_without_stats = true
	check.call(
		offered_without_stats,
		"死にカード: statsなしの抽選では従来どおりSPIN_ENGINEも出る"
	)

	# 残機札(SPARE_CORE id=8): 残機が既に5なら死に、3なら有効、不明(-1)なら有効扱い。
	check.call(
		not CustomPartCatalog.by_id(8).would_change_anything(fresh, 5),
		"死にカード: 残機5でSPARE_COREは効果なし判定"
	)
	check.call(
		CustomPartCatalog.by_id(8).would_change_anything(fresh, 3),
		"死にカード: 残機3ならSPARE_COREは有効"
	)
	check.call(
		CustomPartCatalog.by_id(8).would_change_anything(fresh, -1),
		"死にカード: 残機不明ならSPARE_COREは有効扱い"
	)

	# 全上限まで積んだビルド: 生き残るのはGHOST(常時有効)とFULL_STEAM(摩擦に
	# 下限がない)だけ。提示枚数は3枚に満たなくてよい(死に札で埋めるより誠実)。
	var maxed := _stats()
	maxed.mass = CustomPartCatalog.MASS_CAP
	maxed.radius = CustomPartCatalog.RADIUS_CAP
	maxed.restitution = CustomPartCatalog.RESTITUTION_CAP
	maxed.rps = SpinnerStats.RPS_CAP
	maxed.wall_keep = CustomPartCatalog.RAGE_WALL_KEEP_MAX
	maxed.hit_guard = CustomPartCatalog.GUARD_HIT_MAX
	maxed.edge = CustomPartCatalog.EDGE_MAX
	maxed.spin_decay = CustomPartCatalog.FULL_STEAM_FLOOR
	var only_alive_ids := true
	var sizes_ok := true
	for trial in 50:
		rng.seed = trial + 30000
		var picks := CustomPartCatalog.pick_choices(3, rng, 5, maxed, 5)
		if picks.size() != 2:
			sizes_ok = false
		for part in picks:
			if part.id != 5 and part.id != 9:
				only_alive_ids = false
	check.call(only_alive_ids, "死にカード: 全上限ビルドの提示はGHOSTとFULL_STEAMだけ")
	check.call(sizes_ok, "死にカード: 有効札が2枚しか無ければ提示も2枚に減る")

	# ほぼ死にカード: RAGE3枚後の実ビルド。反発は0.75×1.1³=0.99825(表示は1.00)、
	# wall_keepは上限0.5に到達済みで、4枚目の効果は反発+0.00175だけ——表示にすら
	# 現れない。厳密比較(is_equal_approx)では「変化あり」とされ提示され続けた
	# (2026-07-21のコールドプレイで上限到達後の段7・段8にRAGEが並び、報酬が実質
	# 2択になった)。意味のある変化(相対1%)未満は死に札として弾く。
	var nearly_capped := _stats()
	nearly_capped.restitution = 0.75 * 1.1 * 1.1 * 1.1
	nearly_capped.wall_keep = CustomPartCatalog.RAGE_WALL_KEEP_MAX
	check.call(
		not CustomPartCatalog.by_id(6).would_change_anything(nearly_capped),
		"ほぼ死にカード: 反発+0.002しか動かないRAGEは効果なし判定"
	)
	var rage_offered := false
	for trial in TRIALS:
		rng.seed = trial + 40000
		for part in CustomPartCatalog.pick_choices(3, rng, 4, nearly_capped, 3):
			if part.id == 6:
				rage_offered = true
	check.call(
		not rage_offered,
		"ほぼ死にカード: 抽選%d回でRAGEが一度も提示されない" % TRIALS
	)
	# 回帰: RAGE2枚後(反発0.9075・wall_keep0.34)は反発+0.09と保持+0.16が本物に
	# 動くので、閾値導入後も有効なまま。
	var two_rage := _stats()
	two_rage.restitution = 0.75 * 1.1 * 1.1
	two_rage.wall_keep = CustomPartCatalog.RAGE_WALL_KEEP_STEP * 2.0
	check.call(
		CustomPartCatalog.by_id(6).would_change_anything(two_rage),
		"ほぼ死にカード: 上限までまだ遠いRAGEは有効なまま"
	)
	# SPIN_ENGINEも同じ構図: rps39.9では上限40まで+0.1(0.25%)しか動かず死に札。
	var rps_shy := _stats()
	rps_shy.rps = 39.9
	check.call(
		not CustomPartCatalog.by_id(7).would_change_anything(rps_shy),
		"ほぼ死にカード: rps39.9のSPIN_ENGINEは+0.1しか動かず効果なし判定"
	)
	# 回帰: rps35なら+5.0の本物の成長なので有効なまま。
	var rps_room := _stats()
	rps_room.rps = 35.0
	check.call(
		CustomPartCatalog.by_id(7).would_change_anything(rps_room),
		"ほぼ死にカード: rps35のSPIN_ENGINEは有効なまま"
	)


## 見送り札のクールダウン: 直前の報酬画面で選ばなかった札は次の画面に出さない。
## 発見の経緯: 2026-07-22のコールドプレイで、8回の報酬画面のうちGIANT_GROWTHが
## 5回・SHOCK_ABSORBERが5回提示され、顔ぶれの繰り返しが選択の退屈に直結していた
## (過去サイクルでもGHOST 6/9・RAGE 5/9と再発し続けた積み残し)。
func _test_rejected_cooldown(check: Callable) -> void:
	# 純関数rejected_ids: 提示から選んだ1枚を除いた残り=見送り札。
	var offered: Array[CustomPart] = [
		CustomPartCatalog.by_id(2), CustomPartCatalog.by_id(10), CustomPartCatalog.by_id(11),
	]
	var rejected := CustomPartCatalog.rejected_ids(offered, 10)
	check.call(
		rejected == ([2, 11] as Array[int]),
		"見送り札: rejected_idsは選ばなかった2枚のidを返す (%s)" % str(rejected)
	)
	check.call(
		CustomPartCatalog.rejected_ids([] as Array[CustomPart], 10).is_empty(),
		"見送り札: 提示が空ならrejected_idsも空"
	)

	# 抽選: 見送り札を渡すと、その札は何度引いても提示されない。
	var rng := RandomNumberGenerator.new()
	var cooled_offered := false
	for trial in TRIALS:
		rng.seed = trial + 50000
		for part in CustomPartCatalog.pick_choices(3, rng, 3, null, -1, [2, 10] as Array[int]):
			if part.id == 2 or part.id == 10:
				cooled_offered = true
	check.call(
		not cooled_offered,
		"見送り札: 抽選%d回で見送った2枚が一度も提示されない" % TRIALS
	)
	# 取った札(見送りに入らない)は普通に出る=重ね取り戦略は妨げない。
	var picked_again := false
	for trial in TRIALS:
		rng.seed = trial + 50000
		for part in CustomPartCatalog.pick_choices(3, rng, 3, null, -1, [2, 10] as Array[int]):
			if part.id == 11:
				picked_again = true
	check.call(picked_again, "見送り札: 直前に取った札は次の画面にも出る")
	# 既定(見送りなし)は従来どおり全札から出る(回帰)。
	var default_offered := false
	for trial in TRIALS:
		rng.seed = trial + 50000
		for part in CustomPartCatalog.pick_choices(3, rng, 3):
			if part.id == 2:
				default_offered = true
	check.call(default_offered, "見送り札: 除外なしの抽選では従来どおり全札が出る")

	# 提示枚数を満たせないほど除外が広いときは、枚数を痩せさせず除外を諦める。
	# 全9枚中7枚を見送り扱いにすると残り2枚<3枚なので、見送り札も再掲される。
	var wide: Array[int] = []
	for part in CustomPartCatalog.all():
		if part.id != 9 and part.id != 5:
			wide.append(part.id)
	var sizes_ok := true
	var refill_seen := false
	for trial in 50:
		rng.seed = trial + 60000
		var picks := CustomPartCatalog.pick_choices(3, rng, 3, null, -1, wide)
		if picks.size() != 3:
			sizes_ok = false
		for part in picks:
			if wide.has(part.id):
				refill_seen = true
	check.call(sizes_ok, "見送り札: 除外で3枚を切るときも提示は3枚のまま")
	check.call(refill_seen, "見送り札: そのときは見送り札も再掲される(除外を諦める)")

	# 死にカード除外との共存: rps上限のSPIN_ENGINE除外は見送りと無関係に効き続ける。
	var capped := _stats()
	capped.rps = SpinnerStats.RPS_CAP
	var spin_offered := false
	for trial in TRIALS:
		rng.seed = trial + 70000
		for part in CustomPartCatalog.pick_choices(3, rng, 5, capped, 3, [2] as Array[int]):
			if part.id == 7 or part.id == 2:
				spin_offered = true
	check.call(
		not spin_offered,
		"見送り札: 死にカード除外と併用しても両方とも提示されない"
	)


## 1枚の札が接触トレードを一方的にしないこと(質量倍率の天井)。
##
## 衝突で削られるrpsは violence×(相手質量×相手速さ)÷(自質量×自半径²) なので、
## 質量は「与える削り×倍率」と「受ける削り÷倍率」の両側に効き、接触トレードは
## 倍率の2乗で動く。OVERENCUMBERED ×1.5時代は1枚でスイング2.25倍となり、単独計測で
## Lv3 +45.9pt/枚(次点RAREのSPIN_ENGINE +13.5の3.4倍)・2枚で勝率6.6%→92.6%の
## 実質勝ち確定札だった。ここが割れると「引けたら勝ち確」の運ゲー札が生まれる。
## 寿命(rps÷(半径×spin_decay))に代償を払う札(GIANT_GROWTHの半径経由の減衰悪化など)は
## トレードと寿命の交換なので対象外。
## 回転加算札(Extra Winding)。rpsを定数だけ足し、上限RPS_CAPで止まる。
## 回転成長の軸がRARE(SPIN_ENGINE)の引き運に全依存だったのを、COMMONの
## 確実な積み上げで下支えする札(経緯はCustomPartCatalog.SPIN_UP_STEP参照)。
func _test_spin_up(check: Callable) -> void:
	var part := CustomPartCatalog.by_id(12)
	check.call(part != null, "回転加算: カタログにID12がある")
	if part == null:
		return
	check.call(
		part.effect == CustomPart.Effect.SPIN_UP and part.rarity == CustomPart.Rarity.COMMON,
		"回転加算: SPIN_UP効果のCOMMON札(引き運に依存しない下支えなのでRAREにしない)"
	)

	# 適用でrpsだけが加算され、他のステータスは触らない。
	var s := _stats()
	var before_rps := s.rps
	part.apply_to(s)
	check.call(
		is_equal_approx(s.rps, before_rps + CustomPartCatalog.SPIN_UP_STEP),
		"回転加算: rpsが+%.1fされる (%.1f -> %.1f)" % [
			CustomPartCatalog.SPIN_UP_STEP, before_rps, s.rps
		]
	)
	var fresh := _stats()
	check.call(
		is_equal_approx(s.mass, fresh.mass) and is_equal_approx(s.radius, fresh.radius)
			and is_equal_approx(s.friction, fresh.friction)
			and is_equal_approx(s.restitution, fresh.restitution)
			and is_equal_approx(s.spin_decay, fresh.spin_decay),
		"回転加算: rps以外のステータスは変えない"
	)

	# 重ねがけは線形に積み上がる(倍率札と違い現在値に依存しない)。
	s = _stats()
	for i in 3:
		part.apply_to(s)
	check.call(
		is_equal_approx(s.rps, before_rps + 3.0 * CustomPartCatalog.SPIN_UP_STEP),
		"回転加算: 3枚で+%.1f (%.1f)" % [3.0 * CustomPartCatalog.SPIN_UP_STEP, s.rps]
	)

	# 上限RPS_CAPで止まる(勝利成長と同じ天井)。
	s = _stats()
	s.rps = CustomPartCatalog.RPS_CAP - 0.5
	part.apply_to(s)
	check.call(
		is_equal_approx(s.rps, CustomPartCatalog.RPS_CAP),
		"回転加算: 上限%.0fで止まる (%.2f)" % [CustomPartCatalog.RPS_CAP, s.rps]
	)

	# 上限到達・上限間際は死にカード判定に落ち、抽選から外れる。
	s = _stats()
	s.rps = CustomPartCatalog.RPS_CAP
	check.call(
		not part.would_change_anything(s),
		"回転加算: rps上限では死にカード"
	)
	s.rps = CustomPartCatalog.RPS_CAP - 0.1
	check.call(
		not part.would_change_anything(s),
		"回転加算: 上限間際(+0.1しか動かない)もほぼ死にカードとして弾く"
	)
	s.rps = 30.0
	check.call(
		part.would_change_anything(s),
		"回転加算: 上限まで余裕があれば有効"
	)

	# ja側の効果文ピン(en側はカタログ一巡の説明文テストで確認済み)。
	TranslationServer.set_locale("ja")
	var text := part.describe()
	check.call(
		text.contains("回転 +3") and text.contains("40") and text.contains("寿命"),
		"回転加算: ja効果文に加算量・上限・寿命の注記が出る (%s)" % text
	)


func _test_contact_trade_ceiling(check: Callable) -> void:
	const SWING_CAP := 2.0
	const ENEMY_MASS := 2.0
	const ENEMY_RADIUS := 0.8
	const SPEED := 6.0
	const VIOLENCE := 0.07
	for part in CustomPartCatalog.all():
		var before := SpinnerStats.default_player()
		var after := SpinnerStats.default_player()
		part.apply_to(after)

		# 寿命に代償を払う札はこの天井の対象外(スイングは寿命との交換)。
		var life_before := before.rps / (before.radius * before.spin_decay)
		var life_after := after.rps / (after.radius * after.spin_decay)
		if life_after < life_before - EPS:
			continue

		var dealt_before := SpinnerPhysics.sharpened_spin_drain(
			SpinnerPhysics.spin_drain(before.mass, SPEED, ENEMY_MASS, ENEMY_RADIUS, VIOLENCE),
			before.edge
		)
		var dealt_after := SpinnerPhysics.sharpened_spin_drain(
			SpinnerPhysics.spin_drain(after.mass, SPEED, ENEMY_MASS, ENEMY_RADIUS, VIOLENCE),
			after.edge
		)
		var recv_before := SpinnerPhysics.guarded_spin_drain(
			SpinnerPhysics.spin_drain(ENEMY_MASS, SPEED, before.mass, before.radius, VIOLENCE),
			before.hit_guard
		)
		var recv_after := SpinnerPhysics.guarded_spin_drain(
			SpinnerPhysics.spin_drain(ENEMY_MASS, SPEED, after.mass, after.radius, VIOLENCE),
			after.hit_guard
		)
		var swing := (dealt_after / dealt_before) * (recv_before / recv_after)
		check.call(
			swing <= SWING_CAP + EPS,
			"パーツ%d(%s): 1枚の接触トレードスイング%.2f倍が天井%.1f以下" % [
				part.id, part.title_key, swing, SWING_CAP
			]
		)
