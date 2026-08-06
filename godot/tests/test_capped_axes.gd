extends RefCounted

## 報酬カードの「この軸はもう上限」注記(CustomPart.capped_axes / capped_note)のテスト。
##
## 一次証拠(コールドプレイ 2026-08-06, seed=48231): GIANT_GROWTH を積んで段5で
## 直径が上限2.00に達した後も、段6・段7・段8の報酬に同じ札が出続けた。効果文は
## 「直径 ×1.25（上限 2）＆質量 ×1.15（上限 8）」と両方を謳い続けるので、
## **半分が死んでいることがカードのどこにも出ていなかった**。
##
## 大事なのは
## (1) 上限に達した軸だけを挙げること(達していない軸を挙げると別の嘘になる)、
## (2) 死にカード判定(would_change_anything)と閾値を共有すること
##     ——「提示はされるのに全軸が上限」も「全軸が動くのに死に札」も食い違い、
## (3) 判定が元のステータスを壊さないこと、
## (4) 軸を持たない札(残機・ゴースト)で空になること、
## (5) 注記が空のときは1文字も出さないこと、
## (6) RewardScreen/naive_play の配線と訳の存在。
##
## サボタージュ検証(CLAUDE.md「壊した実装を落とせて初めて完成」)は
## docs/evolve/journal.md の当該サイクルに記録。


func run(check: Callable) -> void:
	_test_growth_reports_only_the_capped_half(check)
	_test_rage_and_momentum_report_their_capped_half(check)
	_test_agrees_with_dead_card_filter(check)
	_test_does_not_mutate(check)
	_test_axisless_parts_report_nothing(check)
	_test_note_is_empty_or_names_the_axis(check)
	_test_catalog_axes_are_translated(check)
	_test_wiring(check)


func _player() -> SpinnerStats:
	return SpinnerStats.default_player()


func _find_effect(effect: CustomPart.Effect) -> CustomPart:
	for part in CustomPartCatalog.all():
		if part.effect == effect:
			return part
	return null


## PackedStringArray を Array にして has() で読めるようにするだけの補助。
func _axes(part: CustomPart, stats: SpinnerStats) -> Array:
	return Array(part.capped_axes(stats))


## その札を何枚も重ねて、動く軸が1本も残らなくなったビルド。
##
## 「全軸を上限へ振り切った値」を手で並べる表は作らない——上限の向きは軸ごとに
## 逆(質量は上へ、摩擦と回転減衰は下へ)で、しかも下限値は札ごとに違うので、
## 手書きの表は札を1枚足すたびに古くなる。札自身の apply_to を繰り返せば、
## その札にとっての飽和点へ必ず着く(倍率は上限で、加算は上限で、1未満の倍率は
## 0へ収束して _nearly_same の閾値に沈む)。
func _saturated_for(part: CustomPart) -> SpinnerStats:
	var stats := _mid_build()
	for i in 60:
		part.apply_to(stats)
	return stats


## 上限の手前に居るビルド(どの軸もまだ伸びる)。
func _mid_build() -> SpinnerStats:
	var stats := _player()
	stats.mass = 1.5
	stats.radius = 0.9
	stats.rps = 18.0
	return stats


## 巨大化は直径と質量の複合。片方だけが上限に達している間は、その片方だけを挙げる。
## コールドプレイが踏んだのはまさにこの状態(直径2.00・質量3.02で上限8.00)だった。
func _test_growth_reports_only_the_capped_half(check: Callable) -> void:
	var growth := _find_effect(CustomPart.Effect.GROWTH)
	check.call(growth != null, "カタログに巨大化札がある")
	if growth == null:
		return

	# 初期ビルド: どちらの軸も上限に遠い。
	var fresh := _player()
	check.call(
		growth.capped_axes(fresh).is_empty(),
		"初期ビルドでは巨大化の上限注記が出ない (%s)" % [growth.capped_axes(fresh)]
	)

	# 直径だけ上限。質量はまだ伸びる=挙げてはいけない。
	var wide := _player()
	wide.radius = growth.cap
	wide.mass = growth.mass_cap * 0.25
	var axes := _axes(growth, wide)
	check.call(axes.has("PART_AXIS_RADIUS"), "直径が上限なら直径を挙げる (%s)" % [axes])
	check.call(
		not axes.has("PART_AXIS_MASS"),
		"質量がまだ伸びるなら質量は挙げない (%s)" % [axes]
	)
	# 数字の裏取り: 実際に取ってみて直径が動かず質量だけが動くこと。
	var after := wide.duplicate_stats()
	growth.apply_to(after)
	check.call(
		is_equal_approx(after.radius, wide.radius) and after.mass > wide.mass,
		"直径上限のビルドでは実際に質量だけが伸びる (半径 %.3f→%.3f / 質量 %.3f→%.3f)"
			% [wide.radius, after.radius, wide.mass, after.mass]
	)

	# 質量だけ上限(直径はまだ伸びる)。上の裏返しで、軸の取り違えを捕まえる。
	var heavy := _player()
	heavy.radius = growth.cap * 0.25
	heavy.mass = growth.mass_cap
	var heavy_axes := _axes(growth, heavy)
	check.call(
		heavy_axes.has("PART_AXIS_MASS") and not heavy_axes.has("PART_AXIS_RADIUS"),
		"質量だけが上限なら質量だけを挙げる (%s)" % [heavy_axes]
	)


## 怒りの反射(反発/壁軽減)と勢い維持(摩擦/回転減衰)も複合札なので、片側だけが
## 止まる状態がある。巨大化と同じ規則で挙げられること。
## 勢い維持の cap は「回転減衰の下限」——上限が上向きとは限らないことの検査でもある。
func _test_rage_and_momentum_report_their_capped_half(check: Callable) -> void:
	var rage := _find_effect(CustomPart.Effect.RAGE)
	if rage != null:
		var bouncy := _player()
		bouncy.restitution = rage.cap
		bouncy.wall_keep = 0.0
		var axes := _axes(rage, bouncy)
		check.call(
			axes.has("PART_AXIS_RESTITUTION") and not axes.has("PART_AXIS_WALL_KEEP"),
			"反発だけが上限の怒りの反射は反発だけを挙げる (%s)" % [axes]
		)
		var kept := _player()
		kept.restitution = rage.cap * 0.5
		kept.wall_keep = rage.wall_keep_max
		var kept_axes := _axes(rage, kept)
		check.call(
			kept_axes.has("PART_AXIS_WALL_KEEP")
				and not kept_axes.has("PART_AXIS_RESTITUTION"),
			"壁軽減だけが上限の怒りの反射は壁軽減だけを挙げる (%s)" % [kept_axes]
		)

	var momentum := _find_effect(CustomPart.Effect.MOMENTUM)
	if momentum != null:
		var slick := _player()
		slick.spin_decay = momentum.cap
		var axes := _axes(momentum, slick)
		check.call(
			axes.has("PART_AXIS_SPIN_DECAY") and not axes.has("PART_AXIS_FRICTION"),
			"回転減衰が下限の勢い維持は回転減衰だけを挙げる (%s)" % [axes]
		)


## 死にカード判定と同じ閾値を共有していること。
##
## 「would_change_anything が false」と「謳っている軸が全部止まっている」が
## 両向きに一致しないと、報酬画面が「提示されているのに全軸が上限」か
## 「全軸が動くのに死に札」のどちらかを出す。カタログ全札 × 4段階のビルドで見る。
func _test_agrees_with_dead_card_filter(check: Callable) -> void:
	var mismatches := 0
	var checked := 0
	var saturated_seen := 0
	for part in CustomPartCatalog.all():
		# 残機札は軸を持たず、判定が GameState 側の残機で決まるので対象外。
		# ゴーストは上限が無く重ねるほど伸びる(軸も持たない)ので対象外。
		if part.effect == CustomPart.Effect.SET_LIVES:
			continue
		if part.effect == CustomPart.Effect.GHOST:
			continue
		var total := part.capped_axes(_saturated_for(part)).size()
		check.call(total > 0, "%s が飽和ビルドで軸を挙げる" % part.title_key)
		for build in [_player(), _mid_build(), _stacked(part, 3), _saturated_for(part)]:
			checked += 1
			var capped := part.capped_axes(build).size()
			var all_capped := total > 0 and capped == total
			if all_capped:
				saturated_seen += 1
			if all_capped == part.would_change_anything(build):
				mismatches += 1
	check.call(
		checked > 0 and saturated_seen > 0,
		"突き合わせが空回りしていない (検査 %d件 / うち全軸上限 %d件)"
			% [checked, saturated_seen]
	)
	check.call(
		mismatches == 0,
		"全軸が上限 ⇔ 死にカード が一致する (食い違い %d/%d)" % [mismatches, checked]
	)


## その札を count 枚重ねたビルド。上限の途中(半分だけ止まった状態)を作るために使う。
func _stacked(part: CustomPart, count: int) -> SpinnerStats:
	var stats := _mid_build()
	for i in count:
		part.apply_to(stats)
	return stats


## 見積もりと同じく、判定はプレビューなので元のステータスを壊さない。
func _test_does_not_mutate(check: Callable) -> void:
	var growth := _find_effect(CustomPart.Effect.GROWTH)
	if growth == null:
		return
	var stats := _player()
	var mass := stats.mass
	var radius := stats.radius
	growth.capped_axes(stats)
	growth.capped_note(stats)
	check.call(
		is_equal_approx(stats.mass, mass) and is_equal_approx(stats.radius, radius),
		"上限判定が元のステータスを壊さない (質量 %.3f 半径 %.3f)" % [stats.mass, stats.radius]
	)


## コマの軸を1本も動かさない札(残機・ゴースト)は、どんなビルドでも注記を出さない。
## ここが空にならないと「残機は上限に達している」のような無意味な行が出る。
func _test_axisless_parts_report_nothing(check: Callable) -> void:
	for effect in [CustomPart.Effect.SET_LIVES, CustomPart.Effect.GHOST]:
		var part := _find_effect(effect)
		if part == null:
			continue
		check.call(
			part.capped_axes(_saturated_for(part)).is_empty()
				and part.capped_note(_saturated_for(part)) == "",
			"軸を持たない札(%s)は重ねきっても注記を出さない" % part.title_key
		)


## 注記は「空か、止まった軸の名前を含むか」のどちらか。
## 空でないのに軸名が入っていない(=キーのまま/固定文言)状態を捕まえる。
func _test_note_is_empty_or_names_the_axis(check: Callable) -> void:
	var growth := _find_effect(CustomPart.Effect.GROWTH)
	if growth == null:
		return
	var saved := TranslationServer.get_locale()
	TranslationServer.set_locale("ja")

	check.call(
		growth.capped_note(_player()) == "",
		"上限に達していないビルドでは注記が空 ('%s')" % growth.capped_note(_player())
	)

	var wide := _player()
	wide.radius = growth.cap
	var note := growth.capped_note(wide)
	var axis_name := TranslationServer.translate("PART_AXIS_RADIUS")
	check.call(note != "", "直径が上限のビルドでは注記が出る")
	check.call(
		note.contains(axis_name),
		"注記が止まった軸の名前('%s')を含む ('%s')" % [axis_name, note]
	)
	check.call(
		not note.contains(TranslationServer.translate("PART_AXIS_MASS")),
		"まだ伸びる軸の名前は注記に出ない ('%s')" % note
	)
	check.call(
		not note.contains("PART_"), "注記に生の翻訳キーが残っていない ('%s')" % note
	)
	TranslationServer.set_locale(saved)


## カタログの全札が挙げうる軸名と、注記そのものの訳が両ロケールにある。
## 訳が抜けるとキーが素で出る(リポジトリの流儀どおり穴が見える)ので検査で塞ぐ。
func _test_catalog_axes_are_translated(check: Callable) -> void:
	var keys := {}
	for part in CustomPartCatalog.all():
		for key in part.capped_axes(_saturated_for(part)):
			keys[key] = true
	check.call(keys.size() > 0, "カタログから軸名が引けている (%d種)" % keys.size())

	var saved := TranslationServer.get_locale()
	for locale in ["en", "ja"]:
		TranslationServer.set_locale(locale)
		for key in keys.keys():
			var got := TranslationServer.translate(key)
			check.call(got != key, "%s: %s の訳がある (%s)" % [locale, key, got])
		for key in ["PART_CAPPED_NOTE", "PART_CAPPED_JOIN"]:
			var got := TranslationServer.translate(key)
			check.call(got != key, "%s: %s の訳がある (%s)" % [locale, key, got])
	TranslationServer.set_locale(saved)


## 実UIとCLIハーネスの両方が注記を出していること(情報量を対等に保つ約束)。
func _test_wiring(check: Callable) -> void:
	var screen := FileAccess.get_file_as_string("res://scenes/reward/RewardScreen.gd")
	check.call(
		screen.contains("part.capped_note(_stats)"),
		"RewardScreen.gdが上限注記をCustomPartから得る"
	)
	check.call(
		screen.contains("if capped_text != \"\":"),
		"RewardScreen.gdが空の注記ではラベルを足さない"
	)
	var cli := FileAccess.get_file_as_string("res://playtest/naive_play.gd")
	check.call(
		cli.contains("card_capped_text(stats, part)"),
		"naive_play.gdが報酬カードに上限注記を出す"
	)
	check.call(
		cli.contains("part.capped_axes(stats)"),
		"naive_play.gdの注記がCustomPart.capped_axes由来(別実装の予測を持たない)"
	)
