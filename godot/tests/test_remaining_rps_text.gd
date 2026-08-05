extends RefCounted

## remaining_rps_text.gd のテスト。決着リザルトに出す「どちらがどれだけ回転を残して
## 立っていたか」の行が、軌跡の事実を両言語で正しく文にすることを確かめる。
##
## 見た目(位置・色)は静止画で確かめられない(CLAUDE.mdの方針)ので、ここでは
## 値の転記・割合の計算・頭数の畳み方・フレームなしの非表示という、レイアウトを
## 手触りで変えても生き残る性質だけを固定する。
##
## 眼目は **0.2/40.1 のような「割合では0%だが実数はまだ残っている」決着**が
## 両方の顔で出ること。これがこの行を足した理由そのもの(ボス6連敗の最後の1敗)。


func run(check: Callable) -> void:
	var saved_locale := TranslationServer.get_locale()
	_test_margin(check)
	_test_percent(check)
	_test_totals_sum_melee(check)
	_test_values_appear(check)
	_test_near_miss_shows_both_faces(check)
	_test_empty_hides(check)
	_test_locales(check)
	TranslationServer.set_locale(saved_locale)


## 先頭フレームが開始rps、末尾フレームが決着時のrps。途中の山谷は拾わない。
func _test_margin(check: Callable) -> void:
	var m := RemainingRpsText.margin(_frames([15.0, 22.0, 9.0, 3.5]))
	check.call(is_equal_approx(float(m["start"]), 15.0), "開始は先頭フレーム: %s" % m)
	check.call(is_equal_approx(float(m["final"]), 3.5), "残りは末尾フレーム: %s" % m)
	check.call(RemainingRpsText.margin([]).is_empty(), "フレームなしは空Dictionary")


## 割合は満タン比の四捨五入で、0〜100に収まる。開始0は0%(0除算しない)。
func _test_percent(check: Callable) -> void:
	check.call(
		RemainingRpsText.percent({"start": 40.0, "final": 10.0}) == 25, "10/40は25%"
	)
	check.call(
		RemainingRpsText.percent({"start": 3.0, "final": 1.0}) == 33, "1/3は33%(四捨五入)"
	)
	check.call(RemainingRpsText.percent({"start": 0.0, "final": 5.0}) == 0, "空回りは0%")
	check.call(RemainingRpsText.percent({}) == 0, "空は0%")
	# 開始が0**近傍**(回っていなかった)を名指しする。ここを門で止めないと
	# 5.0/0.0005 = 1000000% が頭打ちで100%になり、「満タンで生き残った」と嘘をつく。
	# 厳密な0だけで確かめると門を外しても int(round(INF)) が偶然0へ落ちて通ってしまい、
	# 門はテストに映らない枝になる(journal「防御的な既定値」の系)。
	check.call(
		RemainingRpsText.percent({"start": 0.0005, "final": 5.0}) == 0,
		"開始が0近傍なら0%(頭打ちで100%と偽らない)"
	)
	# 残りが開始を超える結果(将来の回復要素・浮動小数の塵)でも100%で頭打ち。
	check.call(
		RemainingRpsText.percent({"start": 10.0, "final": 12.0}) == 100, "超過は100%止まり"
	)


## 乱戦は頭数ぶん足す(「この部屋はあとどれだけ残っていたか」が答えるべき問い)。
## 1体でもフレームを持たなければ行ごと出さない=一部だけ足して満タンを縮めない。
func _test_totals_sum_melee(check: Callable) -> void:
	var t := RemainingRpsText.totals([
		_frames([20.0, 0.0]),   # 落ちた敵
		_frames([18.0, 6.0]),   # 生き残り
	])
	check.call(is_equal_approx(float(t["start"]), 38.0), "満タンは頭数ぶんの和: %s" % t)
	check.call(is_equal_approx(float(t["final"]), 6.0), "残りも頭数ぶんの和: %s" % t)
	check.call(RemainingRpsText.percent(t) == 16, "6/38は16%")

	check.call(RemainingRpsText.totals([]).is_empty(), "敵が居なければ空")
	check.call(
		RemainingRpsText.totals([_frames([18.0, 6.0]), []]).is_empty(),
		"1体でもフレーム欠落なら空(残りの1体だけで満タンを縮めない)"
	)


## 4つの値(自分の残り/自分の割合/相手の残り/相手の割合)が全部、行に転記される。
func _test_values_appear(check: Callable) -> void:
	TranslationServer.set_locale("ja")
	var line := RemainingRpsText.remaining_line(
		_frames([30.0, 12.34]), [_frames([40.0, 20.0])]
	)
	check.call(line.contains("12.3"), "自分の残り12.34が'12.3'として出る: %s" % line)
	check.call(line.contains("41"), "自分の割合12.34/30=41%が出る: %s" % line)
	check.call(line.contains("20.0"), "相手の残り20.0が出る: %s" % line)
	check.call(line.contains("50"), "相手の割合20/40=50%が出る: %s" % line)


## この行を足した当の決着: 相手の残り 0.2/40.1。割合は0%へ丸まるが実数は残る。
## 割合だけなら「歯が立たなかった」と読め、実数だけなら別個体(満タン38.6〜40.1)の
## 試行と比較できない。両方出て初めて「あと一撃」が読める。
func _test_near_miss_shows_both_faces(check: Callable) -> void:
	TranslationServer.set_locale("ja")
	var line := RemainingRpsText.remaining_line(
		_frames([36.2, 0.0]), [_frames([40.1, 0.2])]
	)
	check.call(line.contains("0.2"), "実数0.2が残る: %s" % line)
	check.call(line.contains("(0%)"), "割合は0%へ丸まる: %s" % line)
	# 同じ0%でも「まったく削れていない」決着とは字面が違う(実数が効いている)。
	var untouched := RemainingRpsText.remaining_line(
		_frames([36.2, 0.0]), [_frames([40.1, 0.0])]
	)
	check.call(line != untouched, "残り0.2と残り0.0が同じ文にならない: %s / %s" % [line, untouched])


## 軌跡を持たない結果(to_dict/from_dictの旧データ)は空文字＝ラベルは見えないまま。
func _test_empty_hides(check: Callable) -> void:
	check.call(
		RemainingRpsText.remaining_line([], [_frames([40.0, 1.0])]) == "",
		"自分のフレームなしは空文字"
	)
	check.call(
		RemainingRpsText.remaining_line(_frames([30.0, 1.0]), []) == "",
		"敵の軌跡なしは空文字"
	)


## 両言語に訳があり、現在ロケールの言葉で出る(訳抜けならキーがそのまま出て気付ける)。
func _test_locales(check: Callable) -> void:
	var mine := _frames([30.0, 9.0])
	var theirs: Array = [_frames([40.0, 4.0])]

	TranslationServer.set_locale("ja")
	var ja := RemainingRpsText.remaining_line(mine, theirs)
	check.call(ja.contains("残った回転"), "ja: '残った回転'を含む: %s" % ja)
	check.call(ja.contains("自分"), "ja: '自分'を含む: %s" % ja)
	check.call(ja.contains("相手"), "ja: '相手'を含む: %s" % ja)
	check.call(not ja.contains("BATTLE_RPS_REMAINING"), "ja: キーが素通りしていない: %s" % ja)

	TranslationServer.set_locale("en")
	var en := RemainingRpsText.remaining_line(mine, theirs)
	check.call(en.contains("left standing"), "en: 'left standing'を含む: %s" % en)
	check.call(en.contains("you"), "en: 'you'を含む: %s" % en)
	check.call(en.contains("them"), "en: 'them'を含む: %s" % en)
	check.call(not en.contains("BATTLE_RPS_REMAINING"), "en: キーが素通りしていない: %s" % en)


## rpsの並びから軌跡(Snapshotの配列)を作る。位置・速度はこの行が読まないので固定値。
func _frames(rps_values: Array) -> Array:
	var frames: Array = []
	for rps in rps_values:
		frames.append(BattleResult.Snapshot.new(Vector2.ZERO, Vector2.ZERO, float(rps)))
	return frames
