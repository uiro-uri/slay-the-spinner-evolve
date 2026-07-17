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
	_test_titles_translated(check)
	_test_no_debuffs(check)


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

	# 名前どおり「速くなる」＝摩擦が減ること。プロトタイプはここが逆で、
	# 速度減衰を改善すると称して実際は遅くなっていた。
	var before := _stats().friction
	s = _stats()
	CustomPartCatalog.by_id(5).apply_to(s)
	check.call(
		s.friction < before,
		"パーツ: Full Steam Aheadで摩擦が減る＝速くなる (%.3f -> %.3f)" % [before, s.friction]
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
