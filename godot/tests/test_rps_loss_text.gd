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
	_test_dealt_values_appear(check)
	_test_dealt_sums_melee(check)
	_test_dealt_uses_player_share(check)
	_test_dealt_shows_mutual(check)
	_test_dealt_mutual_sums_and_reconciles(check)
	_test_dealt_hides_zero_mutual(check)
	_test_dealt_mutual_locales(check)
	_test_dealt_locales(check)
	_test_dealt_hides_without_facts(check)
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


## 相手側の行(dealt_line)の4値が全部、行に転記される。単体戦。
func _test_dealt_values_appear(check: Callable) -> void:
	var line := RpsLossText.dealt_line([
		{"drain": 12.55, "drain_by_player": 12.55, "wall": 8.24, "decay": 4.31, "wall_hits": 3}
	])
	check.call(line.contains("12.6"), "削り12.55が'12.6'として出る: %s" % line)
	check.call(line.contains("8.2"), "壁8.24が'8.2'として出る: %s" % line)
	check.call(line.contains("3"), "壁回数3が出る: %s" % line)
	check.call(line.contains("4.3"), "減衰4.31が'4.3'として出る: %s" % line)


## 乱戦は敵ごとの内訳の和を出す。片付けるべき部屋の総量が答えなので、
## 頭数ぶん積むのが正しい集約(最大や平均だと2体目の存在が消える)。
func _test_dealt_sums_melee(check: Callable) -> void:
	var line := RpsLossText.dealt_line([
		{"drain": 5.0, "drain_by_player": 5.0, "wall": 1.0, "decay": 2.0, "wall_hits": 1},
		{"drain": 6.0, "drain_by_player": 6.0, "wall": 3.0, "decay": 4.0, "wall_hits": 2},
	])
	check.call(line.contains("11.0"), "削りは和(5+6=11.0): %s" % line)
	check.call(line.contains("4.0"), "壁は和(1+3=4.0): %s" % line)
	check.call(line.contains("6.0"), "減衰は和(2+4=6.0): %s" % line)
	check.call(line.contains("3"), "壁回数は和(1+2=3): %s" % line)


## 削りの欄は相手の総喪失(drain)ではなく、プレイヤーが殴った分(drain_by_player)。
## 乱戦の同士討ちを自分の手柄に数えると「与えた削り」が水増しされる。
func _test_dealt_uses_player_share(check: Callable) -> void:
	# 総削り20.0のうち、プレイヤーの寄与は6.0だけ(残り14.0は同士討ち)。
	var line := RpsLossText.dealt_line([
		{"drain": 20.0, "drain_by_player": 6.0, "wall": 0.0, "decay": 0.0, "wall_hits": 0}
	])
	check.call(line.contains("6.0"), "自分の削り6.0が出る: %s" % line)
	check.call(not line.contains("20.0"), "同士討ち込みの20.0は出ない: %s" % line)


## 同士討ち(総削り − 自分の削り)が独立した欄として出る。単体戦では常に0なので
## この欄は乱戦だけのもの。落とすと相手の行の数字が実際の喪失に足りなくなる。
func _test_dealt_shows_mutual(check: Callable) -> void:
	# 総削り20.0のうち自分は6.0＝同士討ちは14.0。
	var line := RpsLossText.dealt_line([
		{"drain": 20.0, "drain_by_player": 6.0, "wall": 0.0, "decay": 0.0, "wall_hits": 0}
	])
	check.call(line.contains("6.0"), "自分の削り6.0が出る: %s" % line)
	check.call(line.contains("14.0"), "同士討ち14.0が出る: %s" % line)
	check.call(not line.contains("20.0"), "総削り20.0を自分の手柄として出さない: %s" % line)


## 乱戦は敵ごとの同士討ちも和を取り、「自分の削り＋同士討ち」が敵の総削りに一致する
## (＝リザルトの数字が実際の喪失と帳尻を合わせる)。2026-08-04 のコールドプレイで
## 段2(3体)の同士討ち49%がどこにも出ていなかったのが、この検査の元。
func _test_dealt_mutual_sums_and_reconciles(check: Callable) -> void:
	var enemies := [
		{"drain": 17.1, "drain_by_player": 9.0, "wall": 0.8, "decay": 0.1, "wall_hits": 1},
		{"drain": 16.6, "drain_by_player": 7.8, "wall": 0.0, "decay": 1.0, "wall_hits": 0},
		{"drain": 16.7, "drain_by_player": 8.8, "wall": 0.8, "decay": 0.1, "wall_hits": 1},
	]
	var line := RpsLossText.dealt_line(enemies)
	# 自分の削り 9.0+7.8+8.8 = 25.6、同士討ち (17.1-9.0)+(16.6-7.8)+(16.7-8.8) = 24.8。
	check.call(line.contains("25.6"), "自分の削りは和(25.6): %s" % line)
	check.call(line.contains("24.8"), "同士討ちも和(24.8): %s" % line)
	var total := 0.0
	for loss in enemies:
		total += float(loss["drain"])
	check.call(
		absf((25.6 + 24.8) - total) < 0.05,
		"自分の削り+同士討ちが敵の総削り%.1fに一致する" % total
	)


## 単体戦(同士討ちが厳密に0)と、丸めで0.0にしかならない塵は欄ごと出さない。
## 「同士討ち0.0」は毎戦出る無意味な雑音になる。
func _test_dealt_hides_zero_mutual(check: Callable) -> void:
	var solo := RpsLossText.dealt_line([
		{"drain": 12.5, "drain_by_player": 12.5, "wall": 1.0, "decay": 1.0, "wall_hits": 1}
	])
	check.call(solo != "", "単体戦でも行そのものは出る: %s" % solo)
	TranslationServer.set_locale("ja")
	solo = RpsLossText.dealt_line([
		{"drain": 12.5, "drain_by_player": 12.5, "wall": 1.0, "decay": 1.0, "wall_hits": 1}
	])
	check.call(not solo.contains("同士討ち"), "同士討ち0は欄ごと出ない: %s" % solo)
	var dust := RpsLossText.dealt_line([
		{"drain": 12.5001, "drain_by_player": 12.5, "wall": 1.0, "decay": 1.0, "wall_hits": 1}
	])
	check.call(not dust.contains("同士討ち"), "丸めて0.0になる塵も出ない: %s" % dust)
	# 総削りを持たない旧結果は同士討ち0扱い(欠落を「全部同士討ち」と読まない)。
	var legacy := RpsLossText.dealt_line([
		{"drain_by_player": 5.0, "wall": 1.0, "decay": 1.0, "wall_hits": 1}
	])
	check.call(not legacy.contains("同士討ち"), "drainを持たない旧結果は同士討ち0扱い: %s" % legacy)

	# drain欠落の敵が混ざっても、他の敵の同士討ちを食い減らさない。
	# (欠落を0.0で埋めると mutual が負に振れ、和で正の同士討ちを打ち消す)
	var mixed := RpsLossText.dealt_line([
		{"drain_by_player": 5.0, "wall": 0.0, "decay": 0.0, "wall_hits": 0},
		{"drain": 10.0, "drain_by_player": 2.0, "wall": 0.0, "decay": 0.0, "wall_hits": 0},
	])
	check.call(mixed.contains("8.0"), "旧結果が混ざっても同士討ち8.0は目減りしない: %s" % mixed)

	# drain < drain_by_player という壊れた内訳を、体ごとに0で止める(表示の防衛)。
	# 和を取ってから潰すのでは足りない: 負のまま積むと、まともな敵の同士討ちを
	# その体が食い減らす。単体で見ると欄が消えるだけなので気付けず、混在で初めて出る。
	var broken := RpsLossText.dealt_line([
		{"drain": 1.0, "drain_by_player": 9.0, "wall": 0.0, "decay": 0.0, "wall_hits": 0},
		{"drain": 12.0, "drain_by_player": 2.0, "wall": 0.0, "decay": 0.0, "wall_hits": 0},
	])
	check.call(broken.contains("10.0"), "壊れた内訳が他の敵の同士討ち10.0を食わない: %s" % broken)
	check.call(not broken.contains("-"), "壊れた内訳でも負の同士討ちを出さない: %s" % broken)


## 同士討ちの欄も両言語に訳がある(訳抜けならキーがそのまま出て気付ける)。
func _test_dealt_mutual_locales(check: Callable) -> void:
	var enemies := [
		{"drain": 10.0, "drain_by_player": 4.0, "wall": 2.0, "decay": 3.0, "wall_hits": 4}
	]

	TranslationServer.set_locale("ja")
	var ja := RpsLossText.dealt_line(enemies)
	check.call(ja.contains("同士討ち"), "ja: '同士討ち'を含む: %s" % ja)
	check.call(not ja.contains("BATTLE_RPS_DEALT_BREAKDOWN_MUTUAL"), "ja: キーが素通りしていない: %s" % ja)

	TranslationServer.set_locale("en")
	var en := RpsLossText.dealt_line(enemies)
	check.call(en.contains("each other"), "en: 'each other'を含む: %s" % en)
	check.call(not en.contains("BATTLE_RPS_DEALT_BREAKDOWN_MUTUAL"), "en: キーが素通りしていない: %s" % en)


## 両言語に訳があり、自分の行と見分けが付く(訳抜けならキーがそのまま出て気付ける)。
func _test_dealt_locales(check: Callable) -> void:
	var enemies := [
		{"drain": 1.0, "drain_by_player": 1.0, "wall": 2.0, "decay": 3.0, "wall_hits": 4}
	]

	TranslationServer.set_locale("ja")
	var ja := RpsLossText.dealt_line(enemies)
	check.call(ja.contains("相手"), "ja: '相手'を含む: %s" % ja)
	check.call(ja.contains("削り"), "ja: '削り'を含む: %s" % ja)
	check.call(ja != RpsLossText.summary_line(enemies[0]), "ja: 自分の行と別文言: %s" % ja)

	TranslationServer.set_locale("en")
	var en := RpsLossText.dealt_line(enemies)
	check.call(en.contains("clash"), "en: 'clash'を含む: %s" % en)
	check.call(en.contains("they"), "en: 'they'を含む(相手側と分かる): %s" % en)
	check.call(not en.contains("BATTLE_RPS_DEALT_BREAKDOWN"), "en: キーが素通りしていない: %s" % en)


## 敵が居ない/内訳が事実を持たない(drain_by_playerが1件も無い旧結果)なら空文字。
## 0埋めして「自分の削り0.0」と出すと、実際には殴っているのに嘘をつく。
func _test_dealt_hides_without_facts(check: Callable) -> void:
	check.call(RpsLossText.dealt_line([]) == "", "敵が居なければ空文字")
	var legacy := RpsLossText.dealt_line([{"drain": 9.0, "wall": 1.0, "decay": 1.0, "wall_hits": 1}])
	check.call(legacy == "", "drain_by_playerを持たない旧結果は行ごと出さない: %s" % legacy)
