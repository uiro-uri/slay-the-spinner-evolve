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
	_test_carryover_values(check)
	_test_carryover_hides_without_loss(check)
	_test_carryover_locales(check)
	_test_carryover_screen_wiring(check)
	_test_accumulate_sums(check)
	_test_accumulate_is_pure(check)
	_test_accumulate_ignores_empty_and_negative(check)
	_test_accumulate_weighs_by_absolute_amount(check)
	_test_accumulate_survives_json(check)
	_test_run_carryover_beats_single_battle(check)
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
		main.contains("GameState.record_battle_rps_loss(player_rps_loss)"),
		"Main.gdが戦闘終了時に内訳を受け取ってGameStateへ置く"
	)
	check.call(
		main.contains(
			"ThreatMeter.reachable_hardest_stats(GameState.map_tree),\n\t\tGameState.last_battle_rps_loss"
		),
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


## ---- 次の戦いの発射前に据え置きで出す「このランの喪失の構成比」(carryover_line) ----
##
## 一次証拠(コールドプレイ 2026-08-09 昼, seed=48213): 段1で満引きして勝ったが自分の
## 喪失の63%が壁で、それを知ったのは報酬画面へ移った後だった。段5(壁52%)・段6(壁47%)も
## 同じで、**発射を決める画面では毎回この事実が消えていた**。発射前の見積もり
## (WallCostPreview)は相手に届くまでしか見ないので、噛み合った後に払った壁は
## こちらの実測でしか出せない。
##
## 渡す内訳を1戦ぶんからランの累計へ替えたのは、次のコールドプレイ(2026-08-09 夜,
## seed=4821)の一次証拠。壁で1度死んだランなのに、行の壁の欄は戦いごとに
## 60%→5%→21%→13%→25%→5%→10% と暴れ、段4では「壁5%」と出た(同時点の累計は壁55%)。


## 割合と壁回数が、share_line と同じ値で行に転記される。中身が同じであることが要件
## ——同じ内訳を2つの画面が別々に割ると、報酬画面と発射前で数字が食い違う。
func _test_carryover_values(check: Callable) -> void:
	var loss := {"drain": 5.0, "wall": 3.0, "decay": 2.0, "wall_hits": 4}
	var line := RpsLossText.carryover_line(loss)
	check.call(line.contains("50"), "削り50%% が行に出る: %s" % line)
	check.call(line.contains("30"), "壁30%% が行に出る: %s" % line)
	check.call(line.contains("20"), "減衰20%% が行に出る: %s" % line)
	check.call(line.contains("4"), "壁回数4が行に出る: %s" % line)

	# 壁が最大の出費だった戦い(コールドプレイ段1: 削り2.5 / 壁5.9 / 減衰1.0)。
	# 壁の欄が3つの中で最大になっていること＝この行を出す動機そのもの。
	var cold := {"drain": 2.5, "wall": 5.9, "decay": 1.0, "wall_hits": 4}
	var s := RpsLossText.shares(cold)
	check.call(
		s[1] > s[0] and s[1] > s[2],
		"壁が最大の欄になる(段1の実測 2.5/5.9/1.0): %s" % [s]
	)
	# 欄の並びも share_line/summary_line と同じ 削り→壁→減衰。3つの値が別々の
	# 数字になる内訳(26/63/11)で、行の中の**出現位置**まで見る——contains だけだと
	# 差し込む順を入れ替えるサボタージュを素通しする。
	var cold_line := RpsLossText.carryover_line(cold)
	var at_drain := cold_line.find(str(s[0]))
	var at_wall := cold_line.find(str(s[1]))
	var at_decay := cold_line.find(str(s[2]))
	check.call(at_wall >= 0, "壁の割合がそのまま行に出る: %s" % cold_line)
	check.call(
		at_drain >= 0 and at_drain < at_wall and at_wall < at_decay,
		"並びが 削り→壁→減衰 (%d/%d/%d): %s" % [at_drain, at_wall, at_decay, cold_line]
	)
	# 壁回数は割合とは別の数字(9回)で見る。上の 26/63/11 とも桁が被らない。
	var many := {"drain": 2.5, "wall": 5.9, "decay": 1.0, "wall_hits": 9}
	check.call(
		RpsLossText.carryover_line(many).contains("9"),
		"壁回数が行に出る: %s" % RpsLossText.carryover_line(many)
	)


## ランの1戦目(まだ積んでいない)・総量0では行ごと出さない。0/0/0 を割って
## 「33/33/34」と出すと、起きていない戦いの構成比を語ることになる。
func _test_carryover_hides_without_loss(check: Callable) -> void:
	check.call(RpsLossText.carryover_line({}) == "", "内訳なし(ランの1戦目)は空文字")
	check.call(
		RpsLossText.carryover_line({"drain": 0.0, "wall": 0.0, "decay": 0.0, "wall_hits": 0}) == "",
		"総量0は空文字"
	)


## 両言語に訳があり、キーが素通し(訳が無いとキー名がそのまま出る)になっていない。
## 報酬画面の行(REWARD_RECENT_LOSS)とは別のキー＝「このラン」と断る文言を持つ。
## 報酬画面の行は「直前の1戦」のままなので、同じ文言だと2つの画面が同じ範囲の話を
## しているように読める。
func _test_carryover_locales(check: Callable) -> void:
	var loss := {"drain": 1.0, "wall": 2.0, "decay": 3.0, "wall_hits": 4}
	for locale in ["ja", "en"]:
		TranslationServer.set_locale(locale)
		var line := RpsLossText.carryover_line(loss)
		check.call(
			not line.contains("BATTLE_RUN_LOSS_CARRYOVER"),
			"%s に訳がある(キーが素通ししていない): %s" % [locale, line]
		)
		check.call(line != "", "%s で空にならない" % locale)
		check.call(
			line != RpsLossText.share_line(loss),
			"%s で報酬画面の行とは別の文になる: %s" % [locale, line]
		)


## 画面側の配線。発射前の据え置き行は「実UIとCLIとGameStateの3点が同じ
## Dictionaryを読む」ことで成り立つので、その3本を名指しで見る。
func _test_carryover_screen_wiring(check: Callable) -> void:
	var state := FileAccess.get_file_as_string("res://autoloads/GameState.gd")
	check.call(
		state.contains("var last_battle_rps_loss: Dictionary = {}"),
		"GameStateが直前の戦いの内訳を持つ(頭数ぶん続く報酬画面が読む)"
	)
	check.call(
		state.contains("var run_rps_loss: Dictionary = {}"),
		"GameStateがランの累計を持つ(画面を2つまたぐので Main のローカルでは足りない)"
	)
	check.call(
		state.contains("run_rps_loss = {}\n\troll_spawn_seed()"),
		"reset_run()が新しいランで累計を捨てる(前のランの戦いを持ち越さない)"
	)
	check.call(
		state.contains("run_rps_loss = RpsLossText.accumulate(run_rps_loss, loss)"),
		"GameStateが累計をRpsLossText.accumulateで畳む(自前で足さない)"
	)

	var main := FileAccess.get_file_as_string("res://scenes/main/Main.gd")
	check.call(
		main.contains("GameState.record_battle_rps_loss(player_rps_loss)"),
		"Mainが決着のたびに記録する(直前の1戦と累計を同時に更新する1本の口)"
	)
	# 勝敗を見る前に記録すること。負けた戦いこそ「何で死んだか」の一次証拠で、
	# ここを勝ち筋の中へ移すと、いちばん効く警告だけが累計から落ちる。
	var finished_at := main.find("func _on_battle_finished(")
	var record_at := main.find("GameState.record_battle_rps_loss(", finished_at)
	var lose_at := main.find("if not player_won:", finished_at)
	check.call(
		finished_at >= 0 and record_at >= 0 and lose_at >= 0 and record_at < lose_at,
		"記録が敗北の分岐より前にある(負けた戦いも積む): %d < %d" % [record_at, lose_at]
	)

	var battle := FileAccess.get_file_as_string("res://scenes/battle/Battle.gd")
	check.call(
		battle.contains("RpsLossText.carryover_line(GameState.run_rps_loss)"),
		"Battle.gdが発射前の行をランの累計からRpsLossText経由で得る(自前で割らない)"
	)
	check.call(
		battle.contains("show_last_loss"),
		"Battle.gdに据え置き行のon/offがある"
	)
	# 発射の瞬間に消えること。_begin が残り回転の行を空にするのは決着後の
	# リザルトが同じ行を使うためで、消し忘れると戦闘中ずっと前の戦いの話が残る。
	var begin_at := battle.find("func _begin(")
	var begin_body := battle.substr(begin_at, 400) if begin_at >= 0 else ""
	check.call(
		begin_body.contains('_remain_label.text = ""'),
		"_begin()が発射の瞬間に据え置き行を消す"
	)

	var cli := FileAccess.get_file_as_string("res://playtest/naive_play.gd")
	check.call(
		cli.contains('RpsLossText.carryover_line(state.get("run_loss", {}))'),
		"naive_playの予告にも同じ行が出る(ハーネスと実ゲームの情報量を対等に保つ)"
	)
	check.call(
		cli.contains("RpsLossText.accumulate(\n\t\tstate.get(\"run_loss\", {}), result.player_rps_loss)"),
		"naive_playも実UIと同じaccumulateで畳む(別々に足すとハーネスだけ違う数字になる)"
	)


## ---- ランを通した蓄積(accumulate) ----


## 2戦ぶんの内訳が機構ごとに足され、壁回数も足される。
func _test_accumulate_sums(check: Callable) -> void:
	var a := {"drain": 2.0, "wall": 3.0, "decay": 1.0, "wall_hits": 2}
	var b := {"drain": 4.0, "wall": 1.0, "decay": 0.5, "wall_hits": 3}
	var total := RpsLossText.accumulate(RpsLossText.accumulate({}, a), b)
	check.call(is_equal_approx(float(total["drain"]), 6.0), "削りが足される: %s" % total)
	check.call(is_equal_approx(float(total["wall"]), 4.0), "壁が足される: %s" % total)
	check.call(is_equal_approx(float(total["decay"]), 1.5), "減衰が足される: %s" % total)
	check.call(int(total["wall_hits"]) == 5, "壁回数が足される: %s" % total)
	# 累計を行にすると、和の構成比がそのまま出る(6/4/1.5 → 52/35/13、壁回数5)。
	var line := RpsLossText.carryover_line(total)
	check.call(line.contains("5"), "壁回数の累計が行に出る: %s" % line)
	check.call(
		RpsLossText.shares(total) == RpsLossText.shares({
			"drain": 6.0, "wall": 4.0, "decay": 1.5}),
		"累計の構成比は和の構成比と同じ: %s" % [RpsLossText.shares(total)]
	)


## 引数を書き換えない。GameState は `run_rps_loss = accumulate(run_rps_loss, loss)` と
## 自分自身を渡すので、その場で足す実装だと二重に積まれる(そして loss 側を書き換えると
## 報酬画面が読む last_battle_rps_loss まで壊れる——同じ Dictionary を共有している)。
func _test_accumulate_is_pure(check: Callable) -> void:
	var total := {"drain": 2.0, "wall": 3.0, "decay": 1.0, "wall_hits": 2}
	var loss := {"drain": 4.0, "wall": 1.0, "decay": 0.5, "wall_hits": 3}
	var out := RpsLossText.accumulate(total, loss)
	check.call(is_equal_approx(float(total["drain"]), 2.0), "引数のtotalが元のまま: %s" % total)
	check.call(int(total["wall_hits"]) == 2, "引数のtotalの壁回数が元のまま: %s" % total)
	check.call(is_equal_approx(float(loss["drain"]), 4.0), "引数のlossが元のまま: %s" % loss)
	check.call(int(loss["wall_hits"]) == 3, "引数のlossの壁回数が元のまま: %s" % loss)
	check.call(is_equal_approx(float(out["drain"]), 6.0), "返り値には足されている: %s" % out)


## 空の内訳(旧結果・未解決)は素通し。負の値は0に潰す。
## 空を足して欄が生えると、1戦も終えていないランで「33/33/34」が出る。
func _test_accumulate_ignores_empty_and_negative(check: Callable) -> void:
	check.call(
		RpsLossText.carryover_line(RpsLossText.accumulate({}, {})) == "",
		"空に空を足しても総量0＝行は出ない"
	)
	var base := {"drain": 5.0, "wall": 1.0, "decay": 0.0, "wall_hits": 1}
	var kept := RpsLossText.accumulate(base, {})
	check.call(
		is_equal_approx(float(kept.get("drain", -1.0)), 5.0)
			and int(kept.get("wall_hits", -1)) == 1,
		"空を足しても累計は減らない: %s" % kept
	)
	# 行そのものでも見る。上の欄ごとの比較は、累計を丸ごと空にするサボタージュだと
	# 欄が消えて**実行時エラーで関数が中断**し、check が1件も走らないまま
	# スイートは「完走」扱いになる(GDScriptの実行時エラーは関数を抜けるだけ)。
	# 行の比較なら空Dictionaryは空文字になるので、必ず値の不一致として落ちる。
	check.call(
		RpsLossText.carryover_line(kept) == RpsLossText.carryover_line(base),
		"空を足しても行が変わらない: '%s' / '%s'" % [
			RpsLossText.carryover_line(kept), RpsLossText.carryover_line(base)]
	)
	var neg := RpsLossText.accumulate({}, {"drain": -3.0, "wall": 2.0, "decay": 0.0, "wall_hits": -1})
	check.call(is_equal_approx(float(neg["drain"]), 0.0), "負の削りは0に潰す: %s" % neg)
	check.call(int(neg["wall_hits"]) == 0, "負の壁回数は0に潰す: %s" % neg)


## 割合ではなく**絶対量**で積む。1戦ごとに割ってから平均すると、総喪失1.0の小競り合いが
## 総喪失20.0の総力戦と同じ重みになる。ここでは 壁だけの小さい戦い1回と
## 削りだけの大きい戦い1回を積み、大きい方が構成比を支配することで測る
## (割合の平均なら 50/50 になり、絶対量の和なら 5/95 になる)。
func _test_accumulate_weighs_by_absolute_amount(check: Callable) -> void:
	var small := {"drain": 0.0, "wall": 1.0, "decay": 0.0, "wall_hits": 1}
	var big := {"drain": 19.0, "wall": 0.0, "decay": 0.0, "wall_hits": 0}
	var s := RpsLossText.shares(RpsLossText.accumulate(RpsLossText.accumulate({}, small), big))
	check.call(
		s[0] > 90 and s[1] < 10,
		"大きい戦いが構成比を支配する(割合の単純平均なら50/50になる): %s" % [s]
	)


## JSON往復で壊れない。naive_play は state をJSONで持ち越すので、wall_hits が
## float(5.0)で戻ってくる。int() を通していないと壁回数の欄が「5.0回」になる。
func _test_accumulate_survives_json(check: Callable) -> void:
	var total := RpsLossText.accumulate({}, {"drain": 2.0, "wall": 3.0, "decay": 1.0, "wall_hits": 5})
	var back: Dictionary = JSON.parse_string(JSON.stringify(total))
	var line := RpsLossText.carryover_line(back)
	check.call(not line.contains("5.0"), "壁回数が整数で出る(JSON往復後): %s" % line)
	check.call(
		line == RpsLossText.carryover_line(total),
		"JSON往復で行が変わらない: %s / %s" % [line, RpsLossText.carryover_line(total)]
	)


## この変更の動機そのもの。コールドプレイ(2026-08-09 夜, seed=4821)の段1〜段3の実測を
## 順に積み、段4の発射前に何が出るかを見る。1戦ぶん(段3)なら壁5%で「壁はもう
## 気にしなくていい」と読めるが、累計では壁が最大の欄になる——実際このランは
## 段2で壁に6回当たって死んでいる。
func _test_run_carryover_beats_single_battle(check: Callable) -> void:
	var s1 := {"drain": 2.2, "wall": 0.0, "decay": 0.6, "wall_hits": 0}   # 段1
	var s2 := {"drain": 2.2, "wall": 13.0, "decay": 0.8, "wall_hits": 6}  # 段2(壁で敗北)
	var s2r := {"drain": 3.1, "wall": 6.3, "decay": 1.1, "wall_hits": 3}  # 段2リトライ
	var s3 := {"drain": 5.7, "wall": 0.3, "decay": 0.6, "wall_hits": 1}   # 段3
	var single := RpsLossText.shares(s3)
	check.call(
		single[1] < 10,
		"1戦ぶん(段3)では壁は1割未満に見える: %s" % [single]
	)
	var total := {}
	for loss in [s1, s2, s2r, s3]:
		total = RpsLossText.accumulate(total, loss)
	var run := RpsLossText.shares(total)
	check.call(
		run[1] > run[0] and run[1] > run[2],
		"累計では壁が最大の欄になる(このランは壁で死んでいる): %s" % [run]
	)
	check.call(
		int(total["wall_hits"]) == 10,
		"壁回数もランを通して積む: %s" % total
	)
