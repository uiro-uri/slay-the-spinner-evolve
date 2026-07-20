extends RefCounted

## rps_loss_text.gd のテスト。決着リザルトに出す「回転をどこで失ったか」の内訳行が、
## 内訳Dictionaryの事実を両言語で正しく文にすることを確かめる。
##
## 見た目(位置・色)は静止画で確かめられない(CLAUDE.mdの方針)ので、ここでは
## 数値の転記・書式の安定・訳の存在・内訳なしの非表示という、レイアウトを
## 手触りで変えても生き残る性質だけを固定する。


func run(check: Callable) -> void:
	var saved_locale := TranslationServer.get_locale()
	_test_values_appear(check)
	_test_locales(check)
	_test_empty_hides(check)
	_test_defaults_and_clamp(check)
	TranslationServer.set_locale(saved_locale)


## 内訳の4値(削り/壁/壁回数/減衰)が全部、行に転記される。
func _test_values_appear(check: Callable) -> void:
	var line := RpsLossText.summary_line(
		{"drain": 3.14, "wall": 19.04, "decay": 5.66, "wall_hits": 6}
	)
	check.call(line.contains("3.1"), "削り3.14が'3.1'として出る: %s" % line)
	check.call(line.contains("19.0"), "壁19.04が'19.0'として出る: %s" % line)
	check.call(line.contains("6"), "壁回数6が出る: %s" % line)
	check.call(line.contains("5.7"), "減衰5.66が四捨五入で'5.7'として出る: %s" % line)


## 両言語に訳があり、現在ロケールの言葉で出る(訳抜けならキーがそのまま出て気付ける)。
func _test_locales(check: Callable) -> void:
	var loss := {"drain": 1.0, "wall": 2.0, "decay": 3.0, "wall_hits": 4}

	TranslationServer.set_locale("ja")
	var ja := RpsLossText.summary_line(loss)
	check.call(ja.contains("削り"), "ja: '削り'を含む: %s" % ja)
	check.call(ja.contains("壁"), "ja: '壁'を含む: %s" % ja)
	check.call(ja.contains("減衰"), "ja: '減衰'を含む: %s" % ja)

	TranslationServer.set_locale("en")
	var en := RpsLossText.summary_line(loss)
	check.call(en.contains("clash"), "en: 'clash'を含む: %s" % en)
	check.call(en.contains("wall"), "en: 'wall'を含む: %s" % en)
	check.call(en.contains("decay"), "en: 'decay'を含む: %s" % en)
	check.call(not en.contains("BATTLE_RPS_LOSS_BREAKDOWN"), "en: キーが素通りしていない: %s" % en)


## 内訳を持たない結果(旧データ)では空文字＝ラベルは見えないまま。
func _test_empty_hides(check: Callable) -> void:
	check.call(RpsLossText.summary_line({}) == "", "内訳なしは空文字")


## キー欠落は0.0扱い、負値は0に潰す(表示の防衛)。クラッシュしないことも兼ねる。
func _test_defaults_and_clamp(check: Callable) -> void:
	var line := RpsLossText.summary_line({"drain": 1.5})
	check.call(line != "", "drainだけでも行が出る: %s" % line)
	check.call(line.contains("1.5"), "drain=1.5が出る: %s" % line)
	check.call(line.contains("0.0"), "欠落キーは0.0として出る: %s" % line)

	var negative := RpsLossText.summary_line({"drain": -2.0, "wall": 1.0, "decay": 1.0, "wall_hits": 1})
	check.call(not negative.contains("-"), "負値は0に潰れて'-'が出ない: %s" % negative)
