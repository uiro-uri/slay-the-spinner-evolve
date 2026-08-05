extends RefCounted

## 報酬カードの「取るとどうなるか」見積もり(scripts/ui/part_preview.gd)のテスト。
##
## 大事なのは (1) 硬さ・寿命・打たれ強さが物理と同じ式であること(表示だけ別式だと
## 嘘になる)、(2) プレビューが元のステータスを壊さないこと、(3) 変化の向き(better)が
## 実際の増減と一致すること、(4) 硬さ・打たれ強さの行は変化しない札でも必ず出ること、
## (5) コマの性能を変えない札(残機・ゴースト)でも見積もりが空にならないこと、
## (6) RewardScreen/Mainの配線と訳の存在。
##
## (7) **2行目が寿命でないこと**。寿命は自然減衰の軸で、実測では決着にほぼ効かない
## (敵の敗因の自然減衰は全レベル0.0%)のに、カード間で最も大きく動く行だった。
## 結果として最下位の札(FULL_STEAM_AHEAD)が最も得に見え、1位の札(GIANT_GROWTH)が
## 損に見えていた——その逆立ちを戻さないための検査。経緯は part_preview.gd の
## 冒頭コメントと docs/evolve/journal.md の当該サイクル。
##
## サボタージュ検証(CLAUDE.md「壊した実装を落とせて初めて完成」)は
## docs/evolve/journal.md の当該サイクルに記録。


func run(check: Callable) -> void:
	_test_derived_matches_physics(check)
	_test_preview_does_not_mutate(check)
	_test_growth_shows_both_gains(check)
	_test_second_row_tracks_drain_not_decay(check)
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


## 巨大化(GROWTH)は硬さも打たれ強さも上がる、実測1位(measure_parts Lv3・3枚で
## +95.2pt)の札。効果テキストは「直径×1.25・質量×1.15・自然減衰が速まる」までしか
## 言わないので、**得の側が数字で出ること**が今回の眼目。
##
## 以前の2行目(寿命)では、この札だけが唯一「悪くなる側」を表示する札で、
## コールドプレイが2度とも見送る原因になっていた。
func _test_growth_shows_both_gains(check: Callable) -> void:
	var stats := _player()
	var growth := _find_effect(CustomPart.Effect.GROWTH)
	check.call(growth != null, "カタログに巨大化札がある")
	if growth == null:
		return
	var rows := PartPreview.rows(stats, growth, 3, 0.0)
	var tough := _row_of(rows, "STAT_TOUGHNESS")
	var endure := _row_of(rows, "STAT_ENDURANCE")
	check.call(tough["better"] == 1, "巨大化: 硬さは良くなる側 (%.2f→%.2f)" % [
		tough["before"], tough["after"]])
	check.call(endure["better"] == 1, "巨大化: 打たれ強さも良くなる側 (%.1f→%.1f)" % [
		endure["before"], endure["after"]])
	# 寿命の行はもう出さない。出すと「最も大きく動く行」が実測1位の札に
	# 唯一のマイナスを付ける状態へ戻る。
	check.call(
		_row_of(rows, "STAT_LIFETIME").is_empty(),
		"報酬カードに寿命の行を出さない(自然減衰は決着にほぼ効かない)"
	)

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

	# カタログには現在「下がる行」を出す札が無いので、-1の枝は合成の値で押さえる
	# (将来デメリット札が入ったときに向きを取り違えないため)。
	var worse := PartPreview._row("STAT_ENDURANCE", 20.0, 12.0, 1)
	check.call(worse["better"] == -1, "下がる行は悪くなる側として出る (%d)" % worse["better"])


## 2行目が「削られる側」を測っていること。打たれ強さは
## **1接触で削られるrpsに何回耐えられるか**に比例していなければならない。
##
## 物理側(spin_drain × guarded_spin_drain)から耐久回数を実際に組み立て、
## 打たれ強さの比と一致することを見る。式を2箇所に書くと表示だけが嘘になるので、
## ここでは PartPreview を信用せず物理から作り直して突き合わせる。
func _test_second_row_tracks_drain_not_decay(check: Callable) -> void:
	var a := _player()
	var b := _player()
	b.mass = 2.4
	b.radius = 0.9
	b.rps = 21.0
	b.hit_guard = 0.34
	# 相手・速さ・violence は任意でよい(打たれ強さの定義から約分されるため、
	# ここで違う値を入れても比が変わらないことが主張そのもの)。
	var hits_a := _hits_survived(a, 3.1, 6.0, 0.16)
	var hits_b := _hits_survived(b, 3.1, 6.0, 0.16)
	var by_physics := hits_b / hits_a
	var by_preview := PartPreview.endurance(b) / PartPreview.endurance(a)
	check.call(
		is_equal_approx(by_physics, by_preview),
		"打たれ強さの比 = 耐えられる接触回数の比 (物理 %.4f / 表示 %.4f)" % [
			by_physics, by_preview]
	)
	# 相手も速さも変えて同じ比になる(＝相手を知らずに出してよい量である証拠)。
	var other := _hits_survived(b, 0.7, 12.0, 0.5) / _hits_survived(a, 0.7, 12.0, 0.5)
	check.call(
		is_equal_approx(other, by_preview),
		"打たれ強さの比は相手・速さ・violenceに依らない (%.4f / %.4f)" % [other, by_preview]
	)

	# 衝突軽減(SHOCK_ABSORBER)が効くこと。以前は硬さも寿命も凍っていて、
	# **見積もりが一言も語らない札**だった。
	var guarded := _player()
	guarded.hit_guard = 0.5
	check.call(
		PartPreview.endurance(guarded) > PartPreview.endurance(_player()) * 1.5,
		"衝突軽減0.5で打たれ強さが1.5倍超 (%.1f → %.1f)" % [
			PartPreview.endurance(_player()), PartPreview.endurance(guarded)]
	)
	var absorber := _find_effect(CustomPart.Effect.GUARD)
	check.call(absorber != null, "カタログに衝突軽減札がある")
	if absorber != null:
		var row := _row_of(PartPreview.rows(_player(), absorber, 3, 0.0), "STAT_ENDURANCE")
		check.call(
			row["better"] == 1,
			"衝突軽減札: 打たれ強さの行が伸びる側で出る (%.1f→%.1f)" % [
				row["before"], row["after"]]
		)

	# 自然減衰だけを動かす札(MOMENTUM)は、どちらの行も動かさない。
	# measure_parts(Lv3・3枚)で全11札中最下位(+0.5pt)の札が、以前は寿命 +5.4 と
	# 「最も大きく得をする札」に見えていた。
	var momentum := _find_effect(CustomPart.Effect.MOMENTUM)
	check.call(momentum != null, "カタログに勢い維持札がある")
	if momentum != null:
		var rows := PartPreview.rows(_player(), momentum, 3, 0.0)
		check.call(
			_row_of(rows, "STAT_TOUGHNESS")["better"] == 0
			and _row_of(rows, "STAT_ENDURANCE")["better"] == 0,
			"勢い維持札: 硬さも打たれ強さも動かない(自然減衰しか触らないため)"
		)

	# ゼロ除算でinf/nanを出さない(将来の札が軽減を1.0にしても壊れない)。
	var immune := _player()
	immune.hit_guard = 1.0
	check.call(
		is_finite(PartPreview.endurance(immune))
		and PartPreview.endurance(immune) > PartPreview.endurance(guarded),
		"打たれ強さ: 軽減1.0でもinf/nanにならない (%.1f)" % PartPreview.endurance(immune)
	)


## 1回の接触で削られるrpsから逆算した「耐えられる接触回数」。物理の関数だけで組む。
func _hits_survived(
	stats: SpinnerStats, foe_mass: float, foe_speed: float, violence: float
) -> float:
	var drain := SpinnerPhysics.guarded_spin_drain(
		SpinnerPhysics.spin_drain(foe_mass, foe_speed, stats.mass, stats.radius, violence),
		stats.hit_guard
	)
	return stats.rps / drain


## 硬さ・打たれ強さは「この札では伸びない」ことも情報なので、動かない札でも必ず出す。
## (行が出たり消えたりするとカードの高さも揺れる)
func _test_rows_always_show_the_deciding_pair(check: Callable) -> void:
	var stats := _player()
	var missing: Array[String] = []
	var stale: Array[String] = []
	for part in CustomPartCatalog.all():
		var rows := PartPreview.rows(stats, part, 3, 0.0)
		if _row_of(rows, "STAT_TOUGHNESS").is_empty() or _row_of(rows, "STAT_ENDURANCE").is_empty():
			missing.append(part.title_key)
		if not _row_of(rows, "STAT_LIFETIME").is_empty():
			stale.append(part.title_key)
	check.call(
		missing.is_empty(),
		"全ての札で硬さ・打たれ強さの行が出る (欠け: %s)" % ", ".join(missing)
	)
	check.call(
		stale.is_empty(),
		"どの札にも寿命の行を出さない (残り: %s)" % ", ".join(stale)
	)

	# 攻めの札(EDGE)は硬さも打たれ強さも動かさない。それが見えることが選択の材料になる。
	var edge := _find_effect(CustomPart.Effect.EDGE)
	if edge != null:
		var rows := PartPreview.rows(stats, edge, 3, 0.0)
		check.call(
			_row_of(rows, "STAT_TOUGHNESS")["better"] == 0
			and _row_of(rows, "STAT_ENDURANCE")["better"] == 0,
			"シャープエッジ: 硬さも打たれ強さも動かない(変化なしとして出る)"
		)


## 残機札・ゴースト札はSpinnerStatsを一切変えない。硬さ・打たれ強さだけだと
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
		"報酬画面に硬さ・打たれ強さの意味の注記がある"
	)


## 新しい表示キーの訳が両localeにある。欠けるとキーが素で画面に出る。
func _test_translations(check: Callable) -> void:
	var saved := TranslationServer.get_locale()
	for locale in ["en", "ja"]:
		TranslationServer.set_locale(locale)
		for key in ["STAT_TOUGHNESS", "STAT_ENDURANCE",
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
