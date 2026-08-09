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
	_test_share_values(check)
	_test_share_sums_to_100(check)
	_test_share_order_matches_summary(check)
	_test_share_hides_without_loss(check)
	_test_share_ignores_negative_and_missing(check)
	_test_share_locales(check)
	_test_share_screen_wiring(check)
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


## ---- 報酬画面へ持って行く「直前の戦いの喪失の構成比」(share_line/shares) ----
##
## 割合であることが要件そのもの。軽減札(RAGE=壁の喪失-17% / SHOCK_ABSORBER=衝突削りの
## 喪失-17%)は鏡写しの同率なので、どちらが得かは自分の喪失の**構成比**で決まる。
## 絶対量はリザルト画面(summary_line)が既に言っており、こちらが言うべき量ではない。


## 3機構の割合が、内訳Dictionaryの比のとおりに出る。
func _test_share_values(check: Callable) -> void:
	var s := RpsLossText.shares({"drain": 5.0, "wall": 3.0, "decay": 2.0, "wall_hits": 4})
	check.call(s == [50, 30, 20], "5:3:2 が 50/30/20 になる: %s" % [s])

	var line := RpsLossText.share_line(
		{"drain": 5.0, "wall": 3.0, "decay": 2.0, "wall_hits": 4})
	check.call(line.contains("50"), "削り50%%が行に出る: %s" % line)
	check.call(line.contains("30"), "壁30%%が行に出る: %s" % line)
	check.call(line.contains("20"), "減衰20%%が行に出る: %s" % line)
	check.call(line.contains("4"), "壁回数4が行に出る: %s" % line)


## どんな内訳でも合計はちょうど100。四捨五入だけだと99や101になり、
## 「内訳の割合」を名乗る行として壊れて見える(最大剰余法で端数を配っている)。
func _test_share_sums_to_100(check: Callable) -> void:
	var cases := [
		{"drain": 1.0, "wall": 1.0, "decay": 1.0},
		{"drain": 2.0, "wall": 1.0, "decay": 0.0},
		{"drain": 7.1, "wall": 7.6, "decay": 1.9},
		{"drain": 16.1, "wall": 9.7, "decay": 0.8},
		{"drain": 0.0, "wall": 1.0, "decay": 2.0},
		{"drain": 1.0, "wall": 0.0, "decay": 0.0},
		{"drain": 23.6, "wall": 11.5, "decay": 0.6},
	]
	for loss in cases:
		var s := RpsLossText.shares(loss)
		var total := 0
		for v in s:
			total += v
		check.call(total == 100, "合計100%%: %s → %s" % [loss, s])
		var non_negative := true
		for v in s:
			non_negative = non_negative and v >= 0
		check.call(non_negative, "負の割合が出ない: %s → %s" % [loss, s])


## 並びは summary_line と同じ 削り→壁→減衰。2つの画面で順が入れ替わると、
## 縦に読み比べる相手が入れ替わる。
func _test_share_order_matches_summary(check: Callable) -> void:
	# 削りだけの戦い・壁だけの戦い・減衰だけの戦いで、100が立つ位置を見る。
	check.call(
		RpsLossText.shares({"drain": 9.0}) == [100, 0, 0],
		"1つ目の欄が削り: %s" % [RpsLossText.shares({"drain": 9.0})]
	)
	check.call(
		RpsLossText.shares({"wall": 9.0}) == [0, 100, 0],
		"2つ目の欄が壁: %s" % [RpsLossText.shares({"wall": 9.0})]
	)
	check.call(
		RpsLossText.shares({"decay": 9.0}) == [0, 0, 100],
		"3つ目の欄が減衰: %s" % [RpsLossText.shares({"decay": 9.0})]
	)


## 内訳なし・総量0(戦闘を経ずに報酬画面が開かれた場合や旧結果)は行ごと出さない。
## 0/0/0 を「33%/33%/34%」と割ると、起きていない戦いの構成比を語ることになる。
func _test_share_hides_without_loss(check: Callable) -> void:
	check.call(RpsLossText.share_line({}) == "", "内訳なしは空文字")
	check.call(RpsLossText.shares({}).is_empty(), "内訳なしは空配列")
	check.call(
		RpsLossText.share_line({"drain": 0.0, "wall": 0.0, "decay": 0.0, "wall_hits": 0}) == "",
		"総量0は空文字"
	)
	check.call(
		RpsLossText.shares({"drain": 0.0, "wall": 0.0, "decay": 0.0}).is_empty(),
		"総量0は空配列"
	)


## キー欠落は0扱い、負値は0に潰す(summary_line と同じ表示の防衛)。
func _test_share_ignores_negative_and_missing(check: Callable) -> void:
	var s := RpsLossText.shares({"drain": -5.0, "wall": 3.0, "decay": 1.0})
	check.call(s == [0, 75, 25], "負の削りは0として配る: %s" % [s])
	var missing := RpsLossText.shares({"drain": 3.0, "wall": 1.0})
	check.call(missing == [75, 25, 0], "欠落キーは0として配る: %s" % [missing])


## 両言語に訳があり、キーが素通りしていない。
func _test_share_locales(check: Callable) -> void:
	var loss := {"drain": 5.0, "wall": 3.0, "decay": 2.0, "wall_hits": 4}

	TranslationServer.set_locale("ja")
	var ja := RpsLossText.share_line(loss)
	check.call(ja.contains("削り"), "ja: '削り'を含む: %s" % ja)
	check.call(ja.contains("壁"), "ja: '壁'を含む: %s" % ja)
	check.call(ja.contains("減衰"), "ja: '減衰'を含む: %s" % ja)
	check.call(not ja.contains("REWARD_RECENT_LOSS"), "ja: キーが素通りしていない: %s" % ja)

	TranslationServer.set_locale("en")
	var en := RpsLossText.share_line(loss)
	check.call(en.contains("clash"), "en: 'clash'を含む: %s" % en)
	check.call(en.contains("wall"), "en: 'wall'を含む: %s" % en)
	check.call(en.contains("decay"), "en: 'decay'を含む: %s" % en)
	check.call(not en.contains("REWARD_RECENT_LOSS"), "en: キーが素通りしていない: %s" % en)


## 配線。数字が正しくても、画面まで届いていなければ1画面前で消えたままになる
## ——それがこの改善の動機そのものなので、経路の4点(リゾルバの内訳→Battleの
## signal→Mainの持ち回し→RewardScreenの表示)を揃って押さえる。
## 呼び出しの存在だけを見ると条件を殺したサボタージュを素通しするので、
## 受け取り・代入・出し隠しの3点を見る(test_part_preview._test_screen_wiring と同じ流儀)。
func _test_share_screen_wiring(check: Callable) -> void:
	var battle := FileAccess.get_file_as_string("res://scenes/battle/Battle.gd")
	check.call(
		battle.contains("player_rps_loss: Dictionary"),
		"Battle.gdのfinishedが自分の喪失内訳を運ぶ"
	)
	# `_result.player_rps_loss` はリザルト行(_loss_label)でも読まれるので、
	# ファイル全体に含まれるかを見ると emit から外すサボタージュを素通しする
	# (実際に外して1件も落ちなかった)。emit の呼び出しそのものを切り出して見る。
	var emit_at := battle.find("finished.emit(")
	var emit_call := battle.substr(emit_at, 160) if emit_at >= 0 else ""
	check.call(
		emit_call.contains("_result.player_rps_loss"),
		"Battle.gdのfinished.emitがリゾルバの内訳を渡す(リザルト行と同じDictionary)"
	)

	var main := FileAccess.get_file_as_string("res://scenes/main/Main.gd")
	check.call(
		main.contains("_last_player_rps_loss = player_rps_loss"),
		"Main.gdが戦闘終了時に内訳を受け取って持つ"
	)
	check.call(
		main.contains("ThreatMeter.reachable_hardest_stats(GameState.map_tree),\n\t\t_last_player_rps_loss"),
		"Main.gdが報酬画面のsetup()へ内訳を渡す"
	)

	var screen := FileAccess.get_file_as_string("res://scenes/reward/RewardScreen.gd")
	check.call(
		screen.contains("recent_loss: Dictionary = {}"),
		"RewardScreen.gdがsetup()で直前の戦いの内訳を受け取る"
	)
	check.call(
		screen.contains("RpsLossText.share_line(recent_loss)"),
		"RewardScreen.gdが割合の文をRpsLossTextから得る(自前で割らない)"
	)
	check.call(
		screen.contains("_recent_loss.text = recent"),
		"RewardScreen.gdが作った文をラベルへ入れる"
	)
	check.call(
		screen.contains('_recent_loss.visible = recent != ""'),
		"RewardScreen.gdが空の内訳では行ごと隠す"
	)

	var tscn := FileAccess.get_file_as_string("res://scenes/reward/RewardScreen.tscn")
	check.call(
		tscn.contains('[node name="RecentLoss" type="Label"'),
		"RewardScreen.tscnにRecentLossのラベルがある"
	)
	check.call(
		tscn.contains("auto_translate_mode = 2"),
		"RecentLossは自動翻訳を切ってある(数字を差し込んだ訳済みの文なので)"
	)

	var cli := FileAccess.get_file_as_string("res://playtest/naive_play.gd")
	check.call(
		cli.contains("RpsLossText.share_line(state.get(\"last_loss\", {}))"),
		"naive_playの報酬にも同じ行が出る(ハーネスと実ゲームの情報量を対等に保つ)"
	)
