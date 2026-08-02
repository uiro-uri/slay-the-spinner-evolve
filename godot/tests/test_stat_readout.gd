extends RefCounted

## stat_readout.gd のテスト。対戦画面(と各画面)に出すステータス行の内容と、バーの
## 埋まり具合(割合)を確かめる。
##
## 見た目そのものは静止画では確かめられない(CLAUDE.mdの方針)。ここでは行数・順序・
## 翻訳キーと、割合の値域・単調性・端での頭打ちという、表示レンジを手触りで変えても
## 生き残る性質を固定する。具体的なレンジ定数は詰め直す前提なので数値は縛らない。

const EPS := 1e-4

## 行の並びは _test_rows がキーで固定する。ここは「何番目か」に依存する検査の索引。
const TOUGHNESS_ROW := 0
const LIFETIME_ROW := 1
const MASS_ROW := 2
const GHOST_ROW := 6


func run(check: Callable) -> void:
	_test_rows(check)
	_test_fraction_range(check)
	_test_ghost_row(check)
	_test_composite_rows(check)


func _test_rows(check: Callable) -> void:
	var stats := SpinnerStats.default_player()
	var rows := StatReadout.rows(stats)

	check.call(
		rows.size() == 6,
		"行数は6(硬さ/寿命/重さ/大きさ/反発/初期回転数): %d" % rows.size()
	)

	# 順序とキーを固定する。承認済みプレビューの並び。勝敗を決める複合量
	# (硬さ・寿命)が先頭で、生の4本はその材料として後ろに続く。
	var keys := [
		"STAT_TOUGHNESS", "STAT_LIFETIME",
		"STAT_MASS", "STAT_RADIUS", "STAT_RESTITUTION", "STAT_RPS_INITIAL",
	]
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
		StatReadout.rows(high)[MASS_ROW]["fraction"] > StatReadout.rows(low)[MASS_ROW]["fraction"],
		"重さが大きいほどバーが埋まる"
	)

	# 上端を超えても満タンで頭打ち。下端(0)で空。
	var huge := SpinnerStats.default_player()
	huge.mass = StatReadout.MASS_MAX * 3.0
	check.call(
		absf(StatReadout.rows(huge)[MASS_ROW]["fraction"] - 1.0) < EPS,
		"上端超えは満タン(1.0)で頭打ち: %f" % StatReadout.rows(huge)[MASS_ROW]["fraction"]
	)
	var zero := SpinnerStats.default_player()
	zero.mass = 0.0
	check.call(
		absf(StatReadout.rows(zero)[MASS_ROW]["fraction"]) < EPS,
		"0は空(0.0): %f" % StatReadout.rows(zero)[MASS_ROW]["fraction"]
	)


func _test_ghost_row(check: Callable) -> void:
	var stats := SpinnerStats.default_player()

	# ゴースト未取得(0秒)なら無敵時間の行は出ない。基本4行のまま。
	check.call(
		StatReadout.rows(stats, 0.0).size() == 6,
		"ゴースト0秒なら行を足さない: %d" % StatReadout.rows(stats, 0.0).size()
	)

	# 取得している(>0)なら末尾に無敵時間の行が付き、割合は0〜1。
	var rows := StatReadout.rows(stats, StatReadout.GHOST_MAX * 0.5)
	check.call(rows.size() == 7, "ゴースト取得時は7行になる: %d" % rows.size())
	check.call(
		rows[GHOST_ROW]["label_key"] == "STAT_GHOST",
		"末尾は無敵時間の行 -> %s" % rows[GHOST_ROW]["label_key"]
	)
	var f: float = rows[GHOST_ROW]["fraction"]
	check.call(f > 0.0 and f <= 1.0, "無敵時間の割合が0〜1: %f" % f)

	# 秒数が多いほど埋まり、上端超えは満タン頭打ち。
	check.call(
		StatReadout.rows(stats, StatReadout.GHOST_MAX)[GHOST_ROW]["fraction"] > f,
		"無敵秒数が多いほどバーが埋まる"
	)
	check.call(
		absf(StatReadout.rows(stats, StatReadout.GHOST_MAX * 5.0)[GHOST_ROW]["fraction"] - 1.0) < EPS,
		"無敵時間も上端超えは満タンで頭打ち"
	)


## 硬さ・寿命の行が、生の4本ではなく複合量そのものを見せていることを固定する。
##
## この2つを足した動機は「カードが約束した硬さ・寿命が、取った後どこにも出ない」
## だったので、**報酬カードのプレビューと同じ定義**であることが本質。別々に
## 実装されて片方だけ直されると、カードの予告とビルド表示が食い違う。
func _test_composite_rows(check: Callable) -> void:
	# 定義の共有: PartPreview の値を StatReadout のレンジで割ったものと一致する。
	var stats := SpinnerStats.default_player()
	var rows := StatReadout.rows(stats)
	check.call(
		absf(rows[TOUGHNESS_ROW]["fraction"]
			- PartPreview.toughness(stats) / StatReadout.TOUGHNESS_MAX) < EPS,
		"硬さの行は PartPreview.toughness と同じ定義: %f" % rows[TOUGHNESS_ROW]["fraction"]
	)
	check.call(
		absf(rows[LIFETIME_ROW]["fraction"]
			- PartPreview.lifetime(stats) / StatReadout.LIFETIME_MAX) < EPS,
		"寿命の行は PartPreview.lifetime と同じ定義: %f" % rows[LIFETIME_ROW]["fraction"]
	)

	# 硬さは半径の2乗で効く(重さと大きさの生バーだけでは読めない性質)。
	# 質量を2倍にした場合と、半径を√2倍にした場合が同じ硬さになる。
	var heavy := SpinnerStats.default_player()
	heavy.mass = stats.mass * 2.0
	var wide := SpinnerStats.default_player()
	wide.radius = stats.radius * sqrt(2.0)
	check.call(
		absf(StatReadout.rows(heavy)[TOUGHNESS_ROW]["fraction"]
			- StatReadout.rows(wide)[TOUGHNESS_ROW]["fraction"]) < EPS,
		"硬さは質量×半径²: 質量2倍と半径√2倍が一致する"
	)

	# 寿命は半径・回転減衰に反比例し、rpsに比例する。大きくすると縮むのが要点で、
	# 「大きさのバーが伸びた=強くなった」と読めてしまう生バーの穴をここで塞ぐ。
	var bigger := SpinnerStats.default_player()
	bigger.radius = stats.radius * 1.25
	check.call(
		StatReadout.rows(bigger)[LIFETIME_ROW]["fraction"]
			< rows[LIFETIME_ROW]["fraction"],
		"大きくすると寿命は縮む(大きさのバーは伸びるのに)"
	)
	check.call(
		StatReadout.rows(bigger)[TOUGHNESS_ROW]["fraction"]
			> rows[TOUGHNESS_ROW]["fraction"],
		"大きくすると硬さは伸びる(寿命とのトレードオフが2行で見える)"
	)
	var spun := SpinnerStats.default_player()
	spun.rps = stats.rps * 1.5
	check.call(
		StatReadout.rows(spun)[LIFETIME_ROW]["fraction"] > rows[LIFETIME_ROW]["fraction"],
		"回転が増えると寿命は延びる"
	)

	# 上端超え・0はほかの行と同じく頭打ち/空(バーが溢れない)。
	var monster := SpinnerStats.default_player()
	monster.mass = 100.0
	monster.rps = 10000.0
	for row in StatReadout.rows(monster):
		var f: float = row["fraction"]
		check.call(f >= 0.0 and f <= 1.0, "%s の割合が0〜1: %f" % [row["label_key"], f])
