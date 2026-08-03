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
	_test_enemy_rows(check)
	_test_enemy_rows_wiring(check)


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


## 敵の硬さ・寿命を「自分との取り分」で見せる行(StatReadout.enemy_rows)。
##
## 動機は「マップは Lv3 2体 としか言わず、その部屋が自分より硬いかが発射前に
## 分からない」。要点は**上端を決め打たないこと**——敵の硬さはLv1 0.12→Lv5 12.5と
## 100倍動くので、自分用の絶対レンジ(TOUGHNESS_MAX=1.5)で並べるとLv3以上が全部
## 満タンに張り付いて情報が消える。ここでは互角=PARITY・単調性・代表個体の取り方と、
## 「絶対レンジで頭打ちにならない」ことを固定する。
func _test_enemy_rows(check: Callable) -> void:
	var player := SpinnerStats.default_player()

	# 相手が居ない画面では行を出さない(StatPanelが何も足さない)。
	check.call(
		StatReadout.enemy_rows(player, []).is_empty(),
		"敵が空なら行を出さない"
	)
	var only_null: Array[SpinnerStats] = [null]
	check.call(
		StatReadout.enemy_rows(player, only_null).is_empty(),
		"中身がnullだけでも行を出さない"
	)

	# 行はちょうど2行、キーと並びを固定する。
	var even := SpinnerStats.default_player()
	var evens: Array[SpinnerStats] = [even]
	var rows := StatReadout.enemy_rows(player, evens)
	check.call(rows.size() == 2, "敵の行は2行(硬さ/寿命): %d" % rows.size())
	check.call(
		rows[0]["label_key"] == "STAT_ENEMY_TOUGHNESS",
		"1行目は敵の硬さ -> %s" % rows[0]["label_key"]
	)
	check.call(
		rows[1]["label_key"] == "STAT_ENEMY_LIFETIME",
		"2行目は敵の寿命 -> %s" % rows[1]["label_key"]
	)

	# 同じ性能の相手はちょうど互角(PARITY)。目盛りの位置と一致する。
	check.call(
		absf(rows[0]["fraction"] - StatReadout.PARITY) < EPS,
		"同性能の相手は硬さが互角(PARITY=%f): %f" % [StatReadout.PARITY, rows[0]["fraction"]]
	)
	check.call(
		absf(rows[1]["fraction"] - StatReadout.PARITY) < EPS,
		"同性能の相手は寿命が互角: %f" % rows[1]["fraction"]
	)

	# 相手が硬いほど取り分が伸び、必ず互角の目盛りを越える(=越えたら格上と読める)。
	var hard := SpinnerStats.default_player()
	hard.mass = player.mass * 4.0
	var hards: Array[SpinnerStats] = [hard]
	var hard_f: float = StatReadout.enemy_rows(player, hards)[0]["fraction"]
	check.call(
		hard_f > StatReadout.PARITY,
		"自分より硬い相手は目盛りを越える: %f" % hard_f
	)
	var soft := SpinnerStats.default_player()
	soft.mass = player.mass * 0.25
	var softs: Array[SpinnerStats] = [soft]
	var soft_f: float = StatReadout.enemy_rows(player, softs)[0]["fraction"]
	check.call(
		soft_f < StatReadout.PARITY,
		"自分より柔らかい相手は目盛りに届かない: %f" % soft_f
	)
	check.call(hard_f > soft_f, "硬い相手ほど取り分が大きい(単調)")

	# **上端を決め打っていないこと**。自分の絶対レンジを大きく超える相手(実測の
	# ボス硬さ12.5相当)でも満タンに張り付かず、さらに硬い相手とちゃんと区別が付く。
	# ここが絶対バーとの本質的な差で、落ちたら情報が消えている。
	var boss := SpinnerStats.default_player()
	boss.mass = StatReadout.TOUGHNESS_MAX * 20.0
	var bosses: Array[SpinnerStats] = [boss]
	var boss_f: float = StatReadout.enemy_rows(player, bosses)[0]["fraction"]
	var bigger_boss := SpinnerStats.default_player()
	bigger_boss.mass = StatReadout.TOUGHNESS_MAX * 60.0
	var bigger_bosses: Array[SpinnerStats] = [bigger_boss]
	var bigger_f: float = StatReadout.enemy_rows(player, bigger_bosses)[0]["fraction"]
	check.call(boss_f < 1.0, "自分のレンジを超える相手でも満タンに張り付かない: %f" % boss_f)
	check.call(
		bigger_f > boss_f,
		"レンジ外どうしでも硬さの差が残る: %f -> %f" % [boss_f, bigger_f]
	)

	# 自分が育てば同じ相手の取り分は下がる(札の効きが敵の行にも出る)。
	var grown := SpinnerStats.default_player()
	grown.mass = player.mass * 4.0
	check.call(
		StatReadout.enemy_rows(grown, hards)[0]["fraction"]
			< StatReadout.enemy_rows(player, hards)[0]["fraction"],
		"自分が硬くなると同じ相手の取り分は下がる"
	)

	# 乱戦の集約は硬さと寿命で**別**。硬さは頭数ぶんの和(部屋を片付ける仕事も、
	# 飛んでくる衝突も頭数ぶんある)、寿命は最大(自滅で終わるのは最後の1体)。
	var tough_one := SpinnerStats.default_player()
	tough_one.mass = player.mass * 4.0
	var lasting_one := SpinnerStats.default_player()
	lasting_one.rps = player.rps * 4.0
	var tough_only: Array[SpinnerStats] = [tough_one]
	var lasting_only: Array[SpinnerStats] = [lasting_one]

	# 硬さ: 和なので、同じ個体を並べるほど取り分が上がる。ここが「1体でも3体でも
	# 同じ長さのメーター」を潰している検査。
	var two_tough: Array[SpinnerStats] = [tough_one, tough_one]
	var three_tough: Array[SpinnerStats] = [tough_one, tough_one, tough_one]
	var f1: float = StatReadout.enemy_rows(player, tough_only)[0]["fraction"]
	var f2: float = StatReadout.enemy_rows(player, two_tough)[0]["fraction"]
	var f3: float = StatReadout.enemy_rows(player, three_tough)[0]["fraction"]
	check.call(f1 < f2 and f2 < f3, "硬さの取り分は頭数で単調に上がる: %f/%f/%f" % [f1, f2, f3])
	# 単体の部屋は和＝その個体の硬さ。乱戦以外で値が動いていないことの錨。
	check.call(
		absf(StatReadout.room_toughness(tough_only) - PartPreview.toughness(tough_one)) < EPS,
		"単体の部屋の硬さはその個体の硬さそのもの"
	)
	check.call(
		absf(StatReadout.room_toughness(two_tough)
			- 2.0 * PartPreview.toughness(tough_one)) < EPS,
		"2体の部屋の硬さは和"
	)
	# 弱い個体でも足せば脅威は上がる(頭数はそれ自体が脅威)。以前は最大だったので
	# ここは「変わらない」だった。
	var padded: Array[SpinnerStats] = [tough_one, soft, soft, soft]
	check.call(
		StatReadout.enemy_rows(player, padded)[0]["fraction"] > f1,
		"弱い個体でも足せば取り分は上がる(頭数は薄めない)"
	)
	# 寿命だけは最大のまま。頭数が増えても待ち時間は伸びない(同時に回っている)。
	var mixed: Array[SpinnerStats] = [soft, tough_one, lasting_one]
	var mixed_rows := StatReadout.enemy_rows(player, mixed)
	check.call(
		absf(mixed_rows[1]["fraction"]
			- StatReadout.enemy_rows(player, lasting_only)[1]["fraction"]) < EPS,
		"乱戦の寿命はいちばん寿命が長い個体を代表にする: %f" % mixed_rows[1]["fraction"]
	)
	var two_lasting: Array[SpinnerStats] = [lasting_one, lasting_one]
	check.call(
		absf(StatReadout.enemy_rows(player, two_lasting)[1]["fraction"]
			- StatReadout.enemy_rows(player, lasting_only)[1]["fraction"]) < EPS,
		"寿命の取り分は頭数では増えない(和にしていない)"
	)
	# nullが混じっても生きている個体で決まる(落ちない)。
	var with_null: Array[SpinnerStats] = [null, tough_one]
	check.call(
		absf(StatReadout.enemy_rows(player, with_null)[0]["fraction"] - f1) < EPS,
		"nullが混じっても生きている個体で決まる"
	)

	# 定義の共有: 報酬カード/自分のビルド表示と同じ PartPreview を通していること。
	# 別実装になって片方だけ直されると、カードの予告と敵の行が食い違う。
	var expected := PartPreview.toughness(tough_one) / (
		PartPreview.toughness(tough_one) + PartPreview.toughness(player)
	)
	check.call(
		absf(StatReadout.enemy_rows(player, tough_only)[0]["fraction"] - expected) < EPS,
		"敵の硬さは PartPreview.toughness と同じ定義: %f" % expected
	)
	var expected_life := PartPreview.lifetime(lasting_one) / (
		PartPreview.lifetime(lasting_one) + PartPreview.lifetime(player)
	)
	check.call(
		absf(StatReadout.enemy_rows(player, lasting_only)[1]["fraction"] - expected_life) < EPS,
		"敵の寿命は PartPreview.lifetime と同じ定義: %f" % expected_life
	)

	# どの行も 0〜1 に収まる(バーが溢れない)。極端な相手でも。
	for row in StatReadout.enemy_rows(player, bigger_bosses):
		var f: float = row["fraction"]
		check.call(f >= 0.0 and f <= 1.0, "%s の取り分が0〜1: %f" % [row["label_key"], f])


## 敵の行の配線。純粋関数が正しくても、呼ばれていなければ画面には何も出ない。
##
## StatPanelはCanvasLayerで@onreadyとレイアウトのフレームを要求するので、この
## ランナー(SceneTreeの_init中)では実体化して中身を見られない。test_part_preview.gd
## と同じくスクリプトの形を読んで押さえる。**呼び出しの存在だけを見ると、条件を殺して
## 到達しなくしたサボタージュを素通しする**(前サイクルが `if false:` で踏んだ穴)ので、
## 受け取り・呼び出し(引数ごと)・見た目の3点を揃って見る。
func _test_enemy_rows_wiring(check: Callable) -> void:
	var panel := FileAccess.get_file_as_string("res://scripts/ui/stat_panel.gd")
	check.call(
		panel.contains("func refresh(enemy_stats: Array[SpinnerStats] = []) -> void:"),
		"StatPanel.refresh()が相手のstatsを受け取る"
	)
	# 受け取った引数をそのまま渡していること。GameStateを直接見る実装だと、
	# マップ画面に前の戦闘の相手が残る(pending_enemiesは次の戦闘まで消えない)。
	check.call(
		panel.contains("StatReadout.enemy_rows(GameState.player_stats, enemy_stats)"),
		"StatPanelが受け取った相手で enemy_rows を呼ぶ"
	)
	check.call(
		panel.contains("_bar(fraction, Palette.ENEMY)"),
		"敵の行のバーは敵色で描く(自分の行と見分けが付く)"
	)
	check.call(
		panel.contains("_parity_tick()"),
		"敵の行に互角の目盛りを立てる(越えたら格上と読める)"
	)
	check.call(
		panel.contains("_flash(bar, Palette.ENEMY)"),
		"敵の行のフラッシュは敵色へ戻す(自分の色に化けない)"
	)
	# 目盛りの位置は取り分の定義(PARITY)から引くこと。0.5をベタ書きすると、
	# 取り分の定義を変えたときに目盛りだけ置き去りになって嘘の基準線になる。
	check.call(
		panel.contains("StatReadout.PARITY"),
		"目盛りの位置は StatReadout.PARITY から引く(ベタ書きしない)"
	)

	var main := FileAccess.get_file_as_string("res://scenes/main/Main.gd")
	check.call(
		main.contains("_swap_screen(BATTLE_SCENE, true, _pending_enemy_stats())"),
		"Mainが戦闘画面へ入るときに相手のstatsを渡す"
	)
	check.call(
		main.contains("_stat_panel.refresh(enemy_stats)"),
		"_swap_screenが受け取った相手をStatPanelへ素通しする"
	)
	check.call(
		main.contains("GameState.pending_enemies") and main.contains("enemy.stats"),
		"Mainが相手のstatsを pending_enemies から集める"
	)
	# 戦闘画面**だけ**に出すこと。ほかの画面にも渡すと、マップに前の相手が残る。
	# 呼び出し側だけを数える(定義 `func _pending_enemy_stats()` は末尾が `:` なので
	# `, ...())` の形には一致しない)。
	var call_sites := main.count(", _pending_enemy_stats())")
	check.call(
		call_sites == 1,
		"相手を渡すのは戦闘画面へ入るときだけ: %d 箇所" % call_sites
	)

	# 翻訳(キーがそのまま出る=訳の抜けはこれで気付く)。
	for key in ["STAT_ENEMY_TOUGHNESS", "STAT_ENEMY_LIFETIME"]:
		for locale in ["en", "ja"]:
			TranslationServer.set_locale(locale)
			var text := tr(key)
			check.call(text != key and text != "", "%s: %s の訳がある (%s)" % [locale, key, text])
	TranslationServer.set_locale("ja")
