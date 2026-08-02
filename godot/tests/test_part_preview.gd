extends RefCounted

## 報酬カードの「取るとどうなるか」見積もり(scripts/ui/part_preview.gd)のテスト。
##
## 大事なのは (1) 硬さ・寿命が物理と同じ式であること(表示だけ別式だと嘘になる)、
## (2) プレビューが元のステータスを壊さないこと、(3) 変化の向き(better)が
## 実際の増減と一致すること、(4) 硬さ・寿命の行は変化しない札でも必ず出ること、
## (5) コマの性能を変えない札(残機・ゴースト)でも見積もりが空にならないこと、
## (6) RewardScreen/Mainの配線と訳の存在。
##
## サボタージュ検証(CLAUDE.md「壊した実装を落とせて初めて完成」)は
## docs/evolve/journal.md の当該サイクルに記録。


func run(check: Callable) -> void:
	_test_derived_matches_physics(check)
	_test_preview_does_not_mutate(check)
	_test_growth_trades_toughness_for_lifetime(check)
	_test_rows_always_show_the_deciding_pair(check)
	_test_non_stat_parts_still_show_something(check)
	_test_format_hides_unchanged(check)
	_test_screen_wiring(check)
	_test_translations(check)


func _player() -> SpinnerStats:
	return SpinnerStats.default_player()


## 硬さ・寿命は「表示用の別式」ではなく物理そのもの。
## 硬さ: 1衝突の削りが 質量×半径² に反比例する(SpinnerPhysics.spin_drain)。
## 寿命: 自然減衰が 半径×spin_decay に比例する(SpinnerPhysics.natural_spin_decay)。
func _test_derived_matches_physics(check: Callable) -> void:
	var stats := _player()
	stats.mass = 2.0
	stats.radius = 0.8
	stats.rps = 24.0
	stats.spin_decay = 0.8

	# 硬さ: 素の削りは violence*(相手質量*相手速さ)/硬さ。硬さを2倍にすれば削りは半分。
	var drain_1 := SpinnerPhysics.spin_drain(1.0, 5.0, stats.mass, stats.radius, 0.16)
	var drain_2 := SpinnerPhysics.spin_drain(1.0, 5.0, stats.mass * 2.0, stats.radius, 0.16)
	check.call(
		is_equal_approx(PartPreview.toughness(stats), 2.0 * 0.8 * 0.8),
		"硬さ = 質量×半径² (%.4f)" % PartPreview.toughness(stats)
	)
	check.call(
		is_equal_approx(drain_1 / drain_2, 2.0),
		"硬さ2倍で素の削りが半分 (比 %.4f)" % (drain_1 / drain_2)
	)

	# 寿命: rpsを1秒あたりの自然減衰量で割った秒数。
	var per_second := SpinnerPhysics.natural_spin_decay(stats.radius, stats.spin_decay, 1.0)
	check.call(
		is_equal_approx(PartPreview.lifetime(stats), stats.rps / per_second),
		"寿命 = rps ÷ 1秒あたりの自然減衰 (%.2f秒)" % PartPreview.lifetime(stats)
	)

	# ゼロ除算でinf/nanを出さない(将来の札が半径や減衰を0にしても壊れない)。
	var degenerate := _player()
	degenerate.radius = 0.0
	check.call(
		PartPreview.lifetime(degenerate) == 0.0,
		"寿命: 半径0でもinf/nanにならない"
	)


## プレビューは見積もりなので、渡されたステータスを絶対に変えてはいけない。
## (ここが壊れると、報酬画面を開くだけでビルドが勝手に強くなる)
func _test_preview_does_not_mutate(check: Callable) -> void:
	var stats := _player()
	var before_mass := stats.mass
	var before_radius := stats.radius
	var before_rps := stats.rps
	for part in CustomPartCatalog.all():
		PartPreview.rows(stats, part, 3, 0.0)
	check.call(
		is_equal_approx(stats.mass, before_mass)
		and is_equal_approx(stats.radius, before_radius)
		and is_equal_approx(stats.rps, before_rps),
		"見積もりは元のステータスを変えない (質量 %.3f / 直径 %.3f / rps %.2f)" % [
			stats.mass, stats.radius, stats.rps]
	)


## 巨大化(GROWTH)は硬さが上がり寿命が下がる両刃。効果テキストは「直径×1.25・
## 質量×1.15」までしか言わないので、この2方向が見積もりに出ることが今回の眼目。
func _test_growth_trades_toughness_for_lifetime(check: Callable) -> void:
	var stats := _player()
	var growth := _find_effect(CustomPart.Effect.GROWTH)
	check.call(growth != null, "カタログに巨大化札がある")
	if growth == null:
		return
	var rows := PartPreview.rows(stats, growth, 3, 0.0)
	var tough := _row_of(rows, "STAT_TOUGHNESS")
	var life := _row_of(rows, "STAT_LIFETIME")
	check.call(tough["better"] == 1, "巨大化: 硬さは良くなる側 (%.2f→%.2f)" % [
		tough["before"], tough["after"]])
	check.call(life["better"] == -1, "巨大化: 寿命は悪くなる側 (%.1f→%.1f)" % [
		life["before"], life["after"]])

	# betterの符号は実際の増減と一致していること(全札・全行で確認する)。
	var mismatched := 0
	for part in CustomPartCatalog.all():
		for row in PartPreview.rows(stats, part, 3, 0.0):
			var delta: float = row["after"] - row["before"]
			var sign_of := 0
			if not is_equal_approx(row["before"], row["after"]):
				sign_of = 1 if delta > 0.0 else -1
			if row["better"] != sign_of:
				mismatched += 1
	check.call(mismatched == 0, "betterの符号が実際の増減と一致 (不一致 %d 件)" % mismatched)


## 硬さ・寿命は「この札では伸びない」ことも情報なので、動かない札でも必ず出す。
## (行が出たり消えたりするとカードの高さも揺れる)
func _test_rows_always_show_the_deciding_pair(check: Callable) -> void:
	var stats := _player()
	var missing: Array[String] = []
	for part in CustomPartCatalog.all():
		var rows := PartPreview.rows(stats, part, 3, 0.0)
		if _row_of(rows, "STAT_TOUGHNESS").is_empty() or _row_of(rows, "STAT_LIFETIME").is_empty():
			missing.append(part.title_key)
	check.call(
		missing.is_empty(),
		"全ての札で硬さ・寿命の行が出る (欠け: %s)" % ", ".join(missing)
	)

	# 攻めの札(EDGE)は硬さも寿命も動かさない。それが見えることが選択の材料になる。
	var edge := _find_effect(CustomPart.Effect.EDGE)
	if edge != null:
		var rows := PartPreview.rows(stats, edge, 3, 0.0)
		check.call(
			_row_of(rows, "STAT_TOUGHNESS")["better"] == 0
			and _row_of(rows, "STAT_LIFETIME")["better"] == 0,
			"シャープエッジ: 硬さも寿命も動かない(変化なしとして出る)"
		)


## 残機札・ゴースト札はSpinnerStatsを一切変えない。硬さ・寿命だけだと
## 「何も起きない札」に見えるので、ラン側の効果を行として補う。
func _test_non_stat_parts_still_show_something(check: Callable) -> void:
	var stats := _player()
	var lives := _find_effect(CustomPart.Effect.SET_LIVES)
	check.call(lives != null, "カタログに残機札がある")
	if lives != null:
		var rows := PartPreview.rows(stats, lives, 2, 0.0)
		var row := _row_of(rows, "STAT_LIVES")
		check.call(
			row["better"] == 1 and int(row["after"]) == lives.lives,
			"残機札: 残機の行が伸びる側で出る (%d→%d)" % [int(row["before"]), int(row["after"])]
		)
		# 既に多いときは下げない(GameState.apply_partのmaxiと同じ)。
		var already := _row_of(PartPreview.rows(stats, lives, 9, 0.0), "STAT_LIVES")
		check.call(
			already["better"] == 0,
			"残機札: 既に残機が多ければ変化なし (%d→%d)" % [
				int(already["before"]), int(already["after"])]
		)
		# 残機を渡さない呼び出し(continues<0)では行を出さない。
		check.call(
			_row_of(PartPreview.rows(stats, lives), "STAT_LIVES").is_empty(),
			"残機札: 残機が未指定なら残機の行は出さない"
		)

	var ghost := _find_effect(CustomPart.Effect.GHOST)
	check.call(ghost != null, "カタログにゴースト札がある")
	if ghost != null:
		var row := _row_of(PartPreview.rows(stats, ghost, 3, 2.0), "STAT_GHOST")
		check.call(
			row["better"] == 1 and is_equal_approx(row["after"], 2.0 + ghost.ghost_seconds),
			"ゴースト札: 無敵時間が累積して伸びる (%.1f→%.1f)" % [row["before"], row["after"]]
		)


## 変化しない行に「0.73 → 0.73」と出すと、変化があると誤読させる。
func _test_format_hides_unchanged(check: Callable) -> void:
	var same := {"label_key": "STAT_TOUGHNESS", "before": 0.735, "after": 0.735,
		"digits": 2, "better": 0}
	var moved := {"label_key": "STAT_TOUGHNESS", "before": 0.735, "after": 0.97,
		"digits": 2, "better": 1}
	check.call(
		not PartPreview.format_row(same).contains("→"),
		"変化なしの行に矢印を出さない (%s)" % PartPreview.format_row(same)
	)
	check.call(
		PartPreview.format_row(moved).contains("→"),
		"変化する行は 今の値 → 取った後の値 (%s)" % PartPreview.format_row(moved)
	)


## 画面側の配線。純粋関数が正しくても、呼ばれていなければ何も出ない。
##
## 報酬画面は@onreadyとレイアウトのフレームを要求するので、このランナー
## (SceneTreeの_init中)では実体化して中身を見られない。そこでBattle.gdに対する
## test_playback_pacing.gdと同じく、スクリプトの形を読んで配線を押さえる。
## **呼び出しの存在だけを見ると、条件を殺して到達しなくしたサボタージュを素通しする**
## (実際に `if _stats != null:` を `if false:` にして1件も落ちなかった)。
## 受け取り・条件・呼び出しの3点を揃って見ること。
func _test_screen_wiring(check: Callable) -> void:
	var screen := FileAccess.get_file_as_string("res://scenes/reward/RewardScreen.gd")
	check.call(
		screen.contains("_stats = stats"),
		"RewardScreen.gdがsetup()で今のビルドを受け取る"
	)
	check.call(
		screen.contains("if _stats != null:"),
		"RewardScreen.gdがビルドを受け取っているときに見積もりを出す(到達可能な条件)"
	)
	check.call(
		screen.contains("PartPreview.rows(_stats, part, _continues, _ghost_seconds)"),
		"RewardScreen.gdが見積もりをPartPreviewから得る(受け取った値をそのまま渡す)"
	)
	check.call(
		screen.contains("PartPreview.format_row("),
		"RewardScreen.gdが見積もりの表示文字列をPartPreviewから得る"
	)
	check.call(
		screen.contains("Palette.STAT_UP") and screen.contains("Palette.STAT_DOWN"),
		"RewardScreen.gdが良し悪しを色で見せる"
	)
	var main := FileAccess.get_file_as_string("res://scenes/main/Main.gd")
	check.call(
		main.contains("GameState.player_stats") and main.contains("GameState.continues_left")
		and main.contains("total_ghost_seconds(GameState.acquired_part_ids)"),
		"Main.gdが今のビルド(ステータス・残機・無敵時間)を報酬画面へ渡す"
	)
	var scene := FileAccess.get_file_as_string("res://scenes/reward/RewardScreen.tscn")
	check.call(
		scene.contains("REWARD_PREVIEW_HINT"),
		"報酬画面に硬さ・寿命の意味の注記がある"
	)


## 新しい表示キーの訳が両localeにある。欠けるとキーが素で画面に出る。
func _test_translations(check: Callable) -> void:
	var saved := TranslationServer.get_locale()
	for locale in ["en", "ja"]:
		TranslationServer.set_locale(locale)
		for key in ["STAT_TOUGHNESS", "STAT_LIFETIME",
				"REWARD_PREVIEW_HEADING", "REWARD_PREVIEW_HINT"]:
			var got := TranslationServer.translate(key)
			check.call(got != key, "%s: %s の訳がある (%s)" % [locale, key, got])
	TranslationServer.set_locale(saved)


## 良し悪しの色が実際に読めるかは test_contrast.gd が見る(色はPaletteの持ち物)。
func _find_effect(effect: CustomPart.Effect) -> CustomPart:
	for part in CustomPartCatalog.all():
		if part.effect == effect:
			return part
	return null


func _row_of(rows: Array[Dictionary], label_key: String) -> Dictionary:
	for row in rows:
		if row["label_key"] == label_key:
			return row
	return {}
