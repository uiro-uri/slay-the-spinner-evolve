extends RefCounted

## playback_pacing.gd(押している間だけ早送り)のテスト。純粋関数と配線を検証する。
##
## 大事なのは (1) 押していないときは必ず等速(勝手に早送りしない)、(2) 決着ズーム
## 演出の最中は押していても等速(スロー演出と倍速が相殺して一番熱い瞬間が流れる
## 事故の防止)、(3) 無効化(multiplier=1)が効くこと、(4) Battle側の配線。


func run(check: Callable) -> void:
	_test_not_held_is_realtime(check)
	_test_held_is_fast(check)
	_test_climax_guard(check)
	_test_disabled(check)
	_test_battle_wires_pacing(check)
	_test_fast_forward_string(check)


## 押していなければ、どんな時刻・演出状態でも等速1.0。勝手に早送りしてはいけない。
func _test_not_held_is_realtime(check: Callable) -> void:
	var worst := 0.0
	for i in 100:
		var t := i * 0.2
		worst = maxf(worst, PlaybackPacing.speed_at(false, 3.0, t, 8.0, 0.28))
		worst = maxf(worst, PlaybackPacing.speed_at(false, 3.0, t, -1.0, 0.28))
	check.call(is_equal_approx(worst, 1.0), "速度: 押していなければ常に等速 (最大 %.2f)" % worst)


## 押している間はmultiplier倍。演出なし(decisive=-1)なら決着までずっと効く。
func _test_held_is_fast(check: Callable) -> void:
	check.call(
		is_equal_approx(PlaybackPacing.speed_at(true, 3.0, 5.0, -1.0, 0.28), 3.0),
		"速度: 押していれば倍速(演出なしの戦い)"
	)
	check.call(
		is_equal_approx(PlaybackPacing.speed_at(true, 3.0, 2.0, 10.0, 0.28), 3.0),
		"速度: 決着演出のずっと手前では押せば倍速"
	)
	# 1.0未満の倍率を渡されても遅回しにはしない(早送りの道具であって巻き戻しではない)。
	check.call(
		PlaybackPacing.speed_at(true, 0.5, 5.0, -1.0, 0.28) >= 1.0,
		"速度: 倍率が1未満でも等速を下回らない"
	)


## 決着ズーム演出(lead区間〜決着後)の間は、押していても等速へ戻す。
func _test_climax_guard(check: Callable) -> void:
	var dt := 8.0
	var lead := 0.28
	check.call(
		is_equal_approx(PlaybackPacing.speed_at(true, 3.0, dt - lead * 0.5, dt, lead), 1.0),
		"演出ガード: lead区間内は押していても等速"
	)
	check.call(
		is_equal_approx(PlaybackPacing.speed_at(true, 3.0, dt, dt, lead), 1.0),
		"演出ガード: 決着時刻ちょうども等速"
	)
	check.call(
		is_equal_approx(PlaybackPacing.speed_at(true, 3.0, dt + 0.3, dt, lead), 1.0),
		"演出ガード: 決着後(強さ1に張り付く区間)も等速"
	)
	check.call(
		is_equal_approx(PlaybackPacing.speed_at(true, 3.0, dt - lead - 0.01, dt, lead), 3.0),
		"演出ガード: lead開始の手前までは倍速のまま"
	)


## multiplier=1.0で無効(押しても等速)。Inspectorから早送りを切れること。
func _test_disabled(check: Callable) -> void:
	check.call(
		is_equal_approx(PlaybackPacing.speed_at(true, 1.0, 5.0, -1.0, 0.28), 1.0),
		"速度: multiplier=1.0は押しても等速"
	)


## Battle.gdが早送りをPlaybackPacingで配線している(退行検知)。
func _test_battle_wires_pacing(check: Callable) -> void:
	var source := FileAccess.get_file_as_string("res://scenes/battle/Battle.gd")
	check.call(
		source.contains("PlaybackPacing.speed_at("),
		"Battle.gdが再生速度をPlaybackPacingから得る"
	)
	check.call(
		source.contains("delta * pace"),
		"Battle.gdが再生時刻の進みに速度を掛ける"
	)
	check.call(
		source.contains("_fast_forward_held()"),
		"Battle.gdが押下状態を速度計算へ渡す"
	)
	check.call(
		source.contains("finish_zoom_lead\n\t)") or source.contains("finish_zoom_lead)"),
		"Battle.gdが決着演出の窓(lead)を速度計算へ渡す(演出ガードの配線)"
	)
	check.call(
		source.contains("BATTLE_FAST_FORWARD"),
		"Battle.gdが早送り中の表示を出す"
	)


## 早送り表示の訳が両localeにあり、記号▶のグリフを既定フォントが持つ(豆腐防止)。
func _test_fast_forward_string(check: Callable) -> void:
	var saved_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var en := TranslationServer.translate("BATTLE_FAST_FORWARD")
	check.call(en != "BATTLE_FAST_FORWARD", "en: BATTLE_FAST_FORWARDの訳がある (%s)" % en)
	TranslationServer.set_locale("ja")
	var ja := TranslationServer.translate("BATTLE_FAST_FORWARD")
	check.call(ja != "BATTLE_FAST_FORWARD", "ja: BATTLE_FAST_FORWARDの訳がある (%s)" % ja)
	check.call(ja.contains("早送り"), "ja: 早送りだと分かる (%s)" % ja)
	TranslationServer.set_locale(saved_locale)

	var font_path: String = ProjectSettings.get_setting("gui/theme/custom_font", "")
	var font := load(font_path) as Font
	if font != null and en.contains("▶"):
		check.call(font.has_char("▶".unicode_at(0)), "既定フォントが▶のグリフを持つ")
