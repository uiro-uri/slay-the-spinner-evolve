extends RefCounted

## stat_readout.gd のテスト。対戦画面に出すステータス行の内容と数値の整形を固定する。
##
## 見た目そのものは静止画では確かめられない(CLAUDE.mdの方針)。ここでは行数・順序・
## 翻訳キー・整形済みの値という、UIノードに依らず決まる部分を数値で押さえる。


func run(check: Callable) -> void:
	_test_rows(check)
	_test_ghost_row(check)
	_test_format(check)


func _test_rows(check: Callable) -> void:
	var stats := SpinnerStats.default_player()
	var rows := StatReadout.rows(stats)

	check.call(rows.size() == 4, "行数は4(重さ/大きさ/反発/初期回転数): %d" % rows.size())

	# 順序とキーを固定する。承認済みプレビューの並び。
	var keys := ["STAT_MASS", "STAT_RADIUS", "STAT_RESTITUTION", "STAT_RPS_INITIAL"]
	for i in keys.size():
		check.call(
			rows[i]["label_key"] == keys[i],
			"row[%d].label_key == %s (got %s)" % [i, keys[i], rows[i]["label_key"]]
		)

	# default_player(): mass 1.5, radius 0.7, restitution 0.75, rps 15.0
	check.call(rows[0]["value"] == "1.5", "重さの値 -> '%s'" % rows[0]["value"])
	check.call(rows[1]["value"] == "0.7", "大きさの値 -> '%s'" % rows[1]["value"])
	check.call(rows[2]["value"] == "0.75", "反発の値 -> '%s'" % rows[2]["value"])
	# rps は末尾ゼロが落ちて整数表記になる(初期回転数として静的表示)。
	check.call(rows[3]["value"] == "15", "初期回転数の値 -> '%s'" % rows[3]["value"])


func _test_ghost_row(check: Callable) -> void:
	var stats := SpinnerStats.default_player()

	# ゴースト未取得(0秒)なら無敵時間の行は出ない。基本4行のまま。
	check.call(
		StatReadout.rows(stats, 0.0).size() == 4,
		"ゴースト0秒なら行を足さない: %d" % StatReadout.rows(stats, 0.0).size()
	)

	# 取得している(>0)なら末尾に無敵時間の行が付く。
	var prev_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("ja")
	var rows := StatReadout.rows(stats, 2.0)
	check.call(rows.size() == 5, "ゴースト取得時は5行になる: %d" % rows.size())
	check.call(
		rows[4]["label_key"] == "STAT_GHOST",
		"末尾は無敵時間の行 -> %s" % rows[4]["label_key"]
	)
	check.call(rows[4]["value"] == "2秒", "ja: 無敵時間の値に単位が付く -> '%s'" % rows[4]["value"])
	# 小数の秒も末尾ゼロを落として単位付きで出す。
	check.call(
		StatReadout.rows(stats, 2.5)[4]["value"] == "2.5秒",
		"ja: 2.5秒 -> '%s'" % StatReadout.rows(stats, 2.5)[4]["value"]
	)
	TranslationServer.set_locale("en")
	check.call(
		StatReadout.rows(stats, 2.0)[4]["value"] == "2s",
		"en: 無敵時間の値 -> '%s'" % StatReadout.rows(stats, 2.0)[4]["value"]
	)
	TranslationServer.set_locale(prev_locale)


func _test_format(check: Callable) -> void:
	# 末尾ゼロと小数点を落とす。ここを外すと "1.50"/"15.00" が出る。
	check.call(StatReadout._format(1.5) == "1.5", "1.5 -> '%s'" % StatReadout._format(1.5))
	check.call(StatReadout._format(15.0) == "15", "15.0 -> '%s'" % StatReadout._format(15.0))
	check.call(StatReadout._format(0.75) == "0.75", "0.75 -> '%s'" % StatReadout._format(0.75))
	# 小数第2位までに丸める(0.98 はそのまま)。
	check.call(StatReadout._format(0.98) == "0.98", "0.98 -> '%s'" % StatReadout._format(0.98))
