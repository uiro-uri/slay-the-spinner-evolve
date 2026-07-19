extends RefCounted

## stat_readout.gd のテスト。対戦画面(と各画面)に出すステータス行の内容と、バーの
## 埋まり具合(割合)を確かめる。
##
## 見た目そのものは静止画では確かめられない(CLAUDE.mdの方針)。ここでは行数・順序・
## 翻訳キーと、割合の値域・単調性・端での頭打ちという、表示レンジを手触りで変えても
## 生き残る性質を固定する。具体的なレンジ定数は詰め直す前提なので数値は縛らない。

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_rows(check)
	_test_fraction_range(check)
	_test_ghost_row(check)


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

	# どの行も割合は 0〜1 に収まる(バーが溢れない/負にならない)。
	for row in rows:
		var f: float = row["fraction"]
		check.call(f >= 0.0 and f <= 1.0, "%s の割合が0〜1: %f" % [row["label_key"], f])


func _test_fraction_range(check: Callable) -> void:
	# 値が大きいほどバーが埋まる(単調)。重さで代表して確かめる。
	var low := SpinnerStats.default_player()
	low.mass = 1.0
	var high := SpinnerStats.default_player()
	high.mass = 2.0
	check.call(
		StatReadout.rows(high)[0]["fraction"] > StatReadout.rows(low)[0]["fraction"],
		"重さが大きいほどバーが埋まる"
	)

	# 上端を超えても満タンで頭打ち。下端(0)で空。
	var huge := SpinnerStats.default_player()
	huge.mass = StatReadout.MASS_MAX * 3.0
	check.call(
		absf(StatReadout.rows(huge)[0]["fraction"] - 1.0) < EPS,
		"上端超えは満タン(1.0)で頭打ち: %f" % StatReadout.rows(huge)[0]["fraction"]
	)
	var zero := SpinnerStats.default_player()
	zero.mass = 0.0
	check.call(
		absf(StatReadout.rows(zero)[0]["fraction"]) < EPS,
		"0は空(0.0): %f" % StatReadout.rows(zero)[0]["fraction"]
	)


func _test_ghost_row(check: Callable) -> void:
	var stats := SpinnerStats.default_player()

	# ゴースト未取得(0秒)なら無敵時間の行は出ない。基本4行のまま。
	check.call(
		StatReadout.rows(stats, 0.0).size() == 4,
		"ゴースト0秒なら行を足さない: %d" % StatReadout.rows(stats, 0.0).size()
	)

	# 取得している(>0)なら末尾に無敵時間の行が付き、割合は0〜1。
	var rows := StatReadout.rows(stats, StatReadout.GHOST_MAX * 0.5)
	check.call(rows.size() == 5, "ゴースト取得時は5行になる: %d" % rows.size())
	check.call(
		rows[4]["label_key"] == "STAT_GHOST",
		"末尾は無敵時間の行 -> %s" % rows[4]["label_key"]
	)
	var f: float = rows[4]["fraction"]
	check.call(f > 0.0 and f <= 1.0, "無敵時間の割合が0〜1: %f" % f)

	# 秒数が多いほど埋まり、上端超えは満タン頭打ち。
	check.call(
		StatReadout.rows(stats, StatReadout.GHOST_MAX)[4]["fraction"] > f,
		"無敵秒数が多いほどバーが埋まる"
	)
	check.call(
		absf(StatReadout.rows(stats, StatReadout.GHOST_MAX * 5.0)[4]["fraction"] - 1.0) < EPS,
		"無敵時間も上端超えは満タンで頭打ち"
	)
