extends RefCounted

## victory_growth_text.gd のテスト。決着リザルトに出す「勝利で回転がどれだけ育つか」の
## 行が、実際の成長(SpinnerStats.grow_rps_by_victory)と食い違わないことを固定する。
##
## 見た目(位置・色)は静止画で確かめられない(CLAUDE.mdの方針)ので、ここでは
## 数値の転記・上限での正直表示・訳の存在・実成長との一致・Battle側の配線という、
## レイアウトを手触りで変えても生き残る性質だけを固定する。


func run(check: Callable) -> void:
	var saved_locale := TranslationServer.get_locale()
	_test_values_appear(check)
	_test_capped_is_honest(check)
	_test_overflow_line(check)
	_test_locales(check)
	_test_matches_real_growth(check)
	_test_margin_line(check)
	_test_battle_wires_label(check)
	_test_knockout_color_readable(check)
	TranslationServer.set_locale(saved_locale)


## 成長量と成長後rpsが行に転記され、撃破ボーナスと通常勝利で文言が分かれる。
func _test_values_appear(check: Callable) -> void:
	TranslationServer.set_locale("ja")
	var ko := VictoryGrowthText.growth_line(true, 1.0, 16.0)
	check.call(ko.contains("1.0"), "撃破: 成長+1.0が出る: %s" % ko)
	check.call(ko.contains("16.0"), "撃破: 成長後16.0が出る: %s" % ko)
	check.call(ko.contains("撃破ボーナス"), "撃破: ボーナスだと分かる: %s" % ko)

	var passive := VictoryGrowthText.growth_line(false, 0.5, 16.5)
	check.call(passive.contains("0.5"), "通常: 成長+0.5が出る: %s" % passive)
	check.call(passive.contains("16.5"), "通常: 成長後16.5が出る: %s" % passive)
	check.call(not passive.contains("撃破ボーナス"), "通常: 撃破ボーナスを名乗らない: %s" % passive)


## 上限到達(表示丸めで+0.0)の成長は「頭打ち」と正直に言い、+0.0を成長と呼ばない。
## 閾値はCLI(naive_play.victory_text)と同じ0.05で、丸め表示との食い違いを防ぐ。
func _test_capped_is_honest(check: Callable) -> void:
	TranslationServer.set_locale("ja")
	var ko := VictoryGrowthText.growth_line(true, 0.0, 40.0)
	check.call(ko.contains("頭打ち"), "撃破+上限: 頭打ちと言う: %s" % ko)
	check.call(ko.contains("撃破ボーナス"), "撃破+上限: 接触で仕留めた事実は残す: %s" % ko)
	check.call(not ko.contains("+0.0"), "撃破+上限: +0.0を出さない: %s" % ko)

	var passive := VictoryGrowthText.growth_line(false, 0.0, 40.0)
	check.call(passive.contains("頭打ち"), "通常+上限: 頭打ちと言う: %s" % passive)
	check.call(not passive.contains("撃破ボーナス"), "通常+上限: ボーナスを名乗らない: %s" % passive)

	var boundary := VictoryGrowthText.growth_line(true, 0.04, 40.0)
	check.call(boundary.contains("頭打ち"), "丸めで+0.0になる0.04も頭打ち扱い: %s" % boundary)


## 余勢転化(上限で堰き止められた撃破ボーナスがspin_decayへ)の行。前後の実値が
## 転記され、表示丸め(%.2f)で見えない低下は「長持ち」と呼ばない。
func _test_overflow_line(check: Callable) -> void:
	TranslationServer.set_locale("ja")
	var line := VictoryGrowthText.growth_line(true, 0.0, 40.0, 0.80, 0.76)
	check.call(line.contains("0.80") and line.contains("0.76"), "余勢: 減衰の前後値が出る: %s" % line)
	check.call(line.contains("長持ち"), "余勢: 寿命が伸びたと読める: %s" % line)
	check.call(line.contains("撃破ボーナス"), "余勢: ボーナスだと分かる: %s" % line)
	check.call(not line.contains("頭打ち"), "余勢: 頭打ちと矛盾しない: %s" % line)

	# 丸め表示で同じ値になる低下(閾値DECAY_SHOWN_MIN未満)は従来の頭打ち表示。
	var tiny := VictoryGrowthText.growth_line(true, 0.0, 40.0, 0.402, 0.400)
	check.call(tiny.contains("頭打ち"), "余勢: 見えない低下は頭打ちのまま: %s" % tiny)

	# 受け身の勝ちは機構が転化しない。仮に値が来ても撃破と偽らない(knockoutゲート)。
	var passive := VictoryGrowthText.growth_line(false, 0.0, 40.0, 0.80, 0.76)
	check.call(not passive.contains("撃破ボーナス"), "余勢: 受け身は撃破を名乗らない: %s" % passive)


## 両言語に訳があり、キーが素通りしない(訳抜けならキーがそのまま出て気付ける)。
func _test_locales(check: Callable) -> void:
	TranslationServer.set_locale("en")
	var ko := VictoryGrowthText.growth_line(true, 1.0, 16.0)
	check.call(ko.containsn("knockout"), "en撃破: 'knockout'を含む: %s" % ko)
	check.call(not ko.contains("BATTLE_GROWTH_KNOCKOUT"), "en撃破: キーが素通りしていない: %s" % ko)
	var capped := VictoryGrowthText.growth_line(false, 0.0, 40.0)
	check.call(capped.containsn("cap"), "en上限: 'cap'を含む: %s" % capped)
	check.call(not capped.contains("BATTLE_GROWTH_CAPPED"), "en上限: キーが素通りしていない: %s" % capped)
	var overflow := VictoryGrowthText.growth_line(true, 0.0, 40.0, 0.80, 0.76)
	check.call(overflow.containsn("decay"), "en余勢: 'decay'を含む: %s" % overflow)
	check.call(
		not overflow.contains("BATTLE_GROWTH_KNOCKOUT_OVERFLOW"),
		"en余勢: キーが素通りしていない: %s" % overflow
	)


## 実際の成長関数に複製を通した値で行を作ると、適用される成長と数字が一致する。
## (Battle._finishはこの手順で表示するので、ここが通れば表示=適用が保たれる)
func _test_matches_real_growth(check: Callable) -> void:
	TranslationServer.set_locale("ja")
	var stats := SpinnerStats.default_player()
	stats.rps = 15.0
	var preview := stats.duplicate_stats()
	var gained := preview.grow_rps_by_victory(true)
	var line := VictoryGrowthText.growth_line(true, gained, preview.rps)
	check.call(line.contains("%.1f" % gained), "実成長の増分がそのまま出る: %s" % line)
	check.call(line.contains("%.1f" % preview.rps), "実成長後のrpsがそのまま出る: %s" % line)

	# 上限のコマの撃破勝利は余勢転化が起き、Battleと同じ手順(前後のspin_decayを渡す)で
	# 「長持ち」表示になる。実際の低下量がそのまま行に出る。
	var capped_stats := stats.duplicate_stats()
	capped_stats.rps = SpinnerStats.RPS_CAP
	var capped_preview := capped_stats.duplicate_stats()
	var decay_before := capped_preview.spin_decay
	var capped_gain := capped_preview.grow_rps_by_victory(true)
	var capped_line := VictoryGrowthText.growth_line(
		true, capped_gain, capped_preview.rps, decay_before, capped_preview.spin_decay
	)
	check.call(capped_line.contains("長持ち"), "上限rpsの撃破勝利は余勢転化の表示になる: %s" % capped_line)
	check.call(
		capped_line.contains("%.2f" % capped_preview.spin_decay),
		"転化後のspin_decayがそのまま出る: %s" % capped_line
	)

	# spin_decayが床(OVERFLOW_DECAY_FLOOR)のコマは転化できず、頭打ちの正直表示に戻る。
	var floored := capped_stats.duplicate_stats()
	floored.spin_decay = SpinnerStats.OVERFLOW_DECAY_FLOOR
	var floored_before := floored.spin_decay
	var floored_gain := floored.grow_rps_by_victory(true)
	var floored_line := VictoryGrowthText.growth_line(
		true, floored_gain, floored.rps, floored_before, floored.spin_decay
	)
	check.call(floored_line.contains("頭打ち"), "床に達したコマは頭打ち表示に戻る: %s" % floored_line)


## Battle.gdが成長行をこのヘルパーで組み立て、発射時に消している(配線の退行検知)。
func _test_battle_wires_label(check: Callable) -> void:
	var source := FileAccess.get_file_as_string("res://scenes/battle/Battle.gd")
	check.call(
		source.contains("VictoryGrowthText.growth_line("),
		"Battle.gdが成長行をVictoryGrowthTextで組み立てる"
	)
	check.call(
		source.contains("_growth_label.text = \"\""),
		"Battle.gdが成長行をクリアする経路を持つ"
	)
	check.call(
		source.contains("grow_rps_by_victory("),
		"Battle.gdが表示額を実成長関数(複製適用)から得る"
	)
	check.call(
		source.contains("decay_before"),
		"Battle.gdが余勢転化の前後spin_decayをヘルパーへ渡す(渡し忘れ退行の検知)"
	)


## 撃破ボーナスの金色文字が、出る場所(土俵の床の上)で読めるコントラストを持つ。
func _test_knockout_color_readable(check: Callable) -> void:
	var vs_floor := ColorContrast.ratio(Palette.GOLD_CARD, Palette.FLOOR)
	check.call(vs_floor >= 4.5, "金色は床に対しWCAG AA(4.5)以上: %.2f" % vs_floor)
	var vs_outline := ColorContrast.ratio(Palette.GOLD_CARD, Palette.TEXT_OUTLINE)
	check.call(vs_outline >= 4.5, "金色は縁取りに対しWCAG AA(4.5)以上: %.2f" % vs_outline)


## 余力(残り回転)を渡した撃破の行には残量が出る。成長量が余力で伸び縮みする
## (SpinnerStats.KNOCKOUT_MARGIN_MIN/MAX)のに数字だけ黙って変わると、
## 「なぜ今回は +0.8 なのか」がどこにも出ない。渡さない経路は従来の文言のまま。
func _test_margin_line(check: Callable) -> void:
	TranslationServer.set_locale("ja")
	var narrow := VictoryGrowthText.growth_line(true, 0.8, 15.8, -1.0, -1.0, 0.11)
	check.call(narrow.contains("11"), "余力: 残り11%%が行に出る: %s" % narrow)
	check.call(narrow.contains("0.8"), "余力: 成長量も残る: %s" % narrow)
	check.call(narrow.contains("撃破ボーナス"), "余力: 撃破ボーナスだと分かる: %s" % narrow)

	var clean := VictoryGrowthText.growth_line(true, 2.2, 17.2, -1.0, -1.0, 0.9)
	check.call(clean.contains("90"), "余力: 残り90%%が行に出る: %s" % clean)

	# 余力を渡さない(不明)経路は従来の文言のまま＝互換。
	var unknown := VictoryGrowthText.growth_line(true, 1.0, 16.0)
	check.call(
		unknown == TranslationServer.translate("BATTLE_GROWTH_KNOCKOUT").format(["1.0", "16.0"]),
		"余力: 不明なら従来の撃破文言のまま: %s" % unknown
	)
	# 受け身の勝ちは余力を渡しても残量を名乗らない(係数が掛からない側なので嘘になる)。
	var passive := VictoryGrowthText.growth_line(false, 0.5, 15.5, -1.0, -1.0, 0.9)
	check.call(
		passive == TranslationServer.translate("BATTLE_GROWTH_VICTORY").format(["0.5", "15.5"]),
		"余力: 受け身の勝ちは残量を出さない: %s" % passive
	)
	# 丸めはリザルトの残量行(RemainingRpsText.percent)と同じ規則。
	check.call(
		VictoryGrowthText.share_percent(0.114) == 11
			and VictoryGrowthText.share_percent(0.116) == 12
			and VictoryGrowthText.share_percent(1.5) == 100
			and VictoryGrowthText.share_percent(-0.5) == 0,
		"余力: 百分率の丸めと頭打ち"
	)
	# 英日どちらの訳もキー名のまま出ない(訳漏れの検知)。
	for locale in ["ja", "en"]:
		TranslationServer.set_locale(locale)
		var line := VictoryGrowthText.growth_line(true, 1.2, 16.2, -1.0, -1.0, 0.42)
		check.call(
			not line.contains("BATTLE_GROWTH_KNOCKOUT_MARGIN") and line.contains("42"),
			"余力: %s の訳がある: %s" % [locale, line]
		)
