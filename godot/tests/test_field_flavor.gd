extends RefCounted

## FieldFlavor(土俵の「名前 — 性格」1行)の検査。
##
## 見るのは3つ:
## (1) ロスターの全土俵が**それぞれ違う**行になること。同じ絵に見える2択が
##     出たときに、行まで同じだとこの機能の意味が無い。
## (2) 性格が FieldData の数値から導かれていること(固定文でないこと)。
##     傾斜も柱も手触り調整前提の@exportなので、値を動かしたら文も動くのが条件。
## (3) 対戦画面が実際にこの行を出し、発射の瞬間に消していること(配線)。
##
## 実UI(Battle.gd)は autoload を参照するのでヘッドレスの--scriptモードでは
## new()できない。配線はソーステキスト照合で見る(test_retry_plan と同じ手口。
## コメントを落としてから照合するのも同じ理由——「借りる」と書いた自分の
## コメントに照合がヒットしてしまう)。

const BATTLE_SRC := "res://scenes/battle/Battle.gd"

## 借りている行(LAND_LOSS_RECT)の幅と字の大きさ。Battle.gd の実値と揃える。
## 行はセンター寄せなので、はみ出すと左右へ均等に溢れる——横画面では画面内に
## 収まってしまい気付けないが、縦画面(SP幅390)では画面外へ出る。
const ROW_WIDTH := 500.0
const ROW_FONT_SIZE := 20


func run(check: Callable) -> void:
	var prev_locale := TranslationServer.get_locale()
	_test_every_field_has_a_distinct_line(check)
	_test_trait_is_derived(check)
	_test_priority(check)
	_test_line_contains_name_and_trait(check)
	_test_no_field_no_line(check)
	_test_localization(check)
	_test_fits_the_row(check)
	_test_wiring(check)
	TranslationServer.set_locale(prev_locale)


## 道中6つ＋決戦の全土俵。決戦の土俵は all() に入っていない(段9専用)ので明示的に足す。
static func _all_fields() -> Array[FieldData]:
	var fields := FieldRoster.all()
	fields.append(FieldRoster.boss_field())
	return fields


## コメント行を落としたソース。「その文字列を使っていること/いないこと」を
## 見るとき、理由を書いたコメントが自分でヒットするのを避ける。
static func _code(path: String) -> String:
	var out := ""
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out += line + "\n"
	return out


func _test_every_field_has_a_distinct_line(check: Callable) -> void:
	TranslationServer.set_locale("ja")
	var lines := {}
	var collisions: Array[String] = []
	for field in _all_fields():
		var text := FieldFlavor.line(field)
		check.call(text != "", "%s: 行が出る (%s)" % [field.title_key, text])
		if lines.has(text):
			collisions.append("%s と %s" % [lines[text], field.title_key])
		lines[text] = field.title_key
	check.call(
		collisions.is_empty(),
		"土俵ごとに違う行になる (重複: %s)" % [collisions]
	)


## 性格が数値から導かれていること。ロスターの実物がどの性格を名乗るかを名指しで
## 押さえたうえで、**同じ土俵の数値だけを動かすと性格が変わる**ことまで見る。
## 名指しだけだと「title_key で分岐する固定文」の実装が素通りしてしまう。
func _test_trait_is_derived(check: Callable) -> void:
	var expected := {
		"FIELD_CLASSIC": FieldFlavor.TRAIT_PLAIN,
		"FIELD_BOWL": FieldFlavor.TRAIT_STEEP,
		"FIELD_PLATE": FieldFlavor.TRAIT_CONE,
		"FIELD_ARENA": FieldFlavor.TRAIT_OCTAGON,
		"FIELD_ROUND": FieldFlavor.TRAIT_ROUND,
		"FIELD_PILLARS": FieldFlavor.TRAIT_PILLARS,
		"FIELD_GRAND_ARENA": FieldFlavor.TRAIT_OCTAGON,
	}
	for field in _all_fields():
		if not expected.has(field.title_key):
			check.call(false, "土俵 %s の期待値がテストに無い" % field.title_key)
			continue
		check.call(
			FieldFlavor.trait_key(field) == expected[field.title_key],
			"%s の性格は %s (実際 %s)" % [
				field.title_key, expected[field.title_key], FieldFlavor.trait_key(field)
			]
		)

	# 名前を据え置いたまま数値だけ動かす。固定文だとここで落ちる。
	var flat := FieldData.make(
		"FIELD_CLASSIC", Rect2(0, 0, 10, 10), ArenaWall.WallShape.RECT,
		SpinnerPhysics.StageShape.DISH, FieldFlavor.STEEP_STRENGTH - 0.1)
	var steep := FieldData.make(
		"FIELD_CLASSIC", Rect2(0, 0, 10, 10), ArenaWall.WallShape.RECT,
		SpinnerPhysics.StageShape.DISH, FieldFlavor.STEEP_STRENGTH)
	check.call(
		FieldFlavor.trait_key(flat) == FieldFlavor.TRAIT_PLAIN,
		"閾値のすぐ下は標準の傾斜 (実際 %s)" % FieldFlavor.trait_key(flat)
	)
	check.call(
		FieldFlavor.trait_key(steep) == FieldFlavor.TRAIT_STEEP,
		"閾値ちょうどから深いすり鉢 (実際 %s)" % FieldFlavor.trait_key(steep)
	)
	check.call(
		FieldFlavor.line(flat) != FieldFlavor.line(steep),
		"同名でも傾斜が違えば行が変わる"
	)

	# 閾値がロスターを実際に割っていること。どちらかへ寄り切っていたら
	# 「閾値がある」だけで名乗り分けが起きておらず、この判定は空回りしている。
	var plain := 0
	var steep_count := 0
	for field in _all_fields():
		match FieldFlavor.trait_key(field):
			FieldFlavor.TRAIT_PLAIN: plain += 1
			FieldFlavor.TRAIT_STEEP: steep_count += 1
	check.call(
		plain > 0 and steep_count > 0,
		"傾斜の閾値がロスターを割っている (標準%d/深い%d)" % [plain, steep_count]
	)


## 優先順。1つの土俵が複数の特徴を持つとき、どれを名乗るかが決まっていること。
func _test_priority(check: Callable) -> void:
	var bounds := Rect2(0, 0, 10, 10)
	var pillars := [Vector3(3, 3, 0.6)] as Array[Vector3]

	# 柱は他のどの土俵にも無い唯一の中身なので、何と重なっても柱が勝つ。
	var cone_pillars := FieldData.make(
		"FIELD_PILLARS", bounds, ArenaWall.WallShape.ROUND,
		SpinnerPhysics.StageShape.CONE, 9.0, pillars)
	check.call(
		FieldFlavor.trait_key(cone_pillars) == FieldFlavor.TRAIT_PILLARS,
		"柱は傾斜にも外周にも優先する (実際 %s)" % FieldFlavor.trait_key(cone_pillars)
	)

	# 傾斜の形(縁で粘れるかどうかが変わる)は外周の形より先。
	var cone_octagon := FieldData.make(
		"FIELD_PLATE", bounds, ArenaWall.WallShape.OCTAGON,
		SpinnerPhysics.StageShape.CONE, 9.0)
	check.call(
		FieldFlavor.trait_key(cone_octagon) == FieldFlavor.TRAIT_CONE,
		"一定傾斜は外周の形に優先する (実際 %s)" % FieldFlavor.trait_key(cone_octagon)
	)

	# 外周が矩形でない土俵は、傾斜の強さではなく外周で名乗る。
	var steep_round := FieldData.make(
		"FIELD_ROUND", bounds, ArenaWall.WallShape.ROUND,
		SpinnerPhysics.StageShape.DISH, 9.0)
	check.call(
		FieldFlavor.trait_key(steep_round) == FieldFlavor.TRAIT_ROUND,
		"外周の形は傾斜の強さに優先する (実際 %s)" % FieldFlavor.trait_key(steep_round)
	)


func _test_line_contains_name_and_trait(check: Callable) -> void:
	TranslationServer.set_locale("ja")
	for field in _all_fields():
		var text := FieldFlavor.line(field)
		var name_ja := TranslationServer.translate(field.title_key)
		var trait_ja := TranslationServer.translate(FieldFlavor.trait_key(field))
		check.call(
			name_ja in text and trait_ja in text,
			"%s: 行に名前と性格が両方入る (%s)" % [field.title_key, text]
		)
		check.call(
			not ("FIELD_" in text),
			"%s: 訳キーが生で出ない (%s)" % [field.title_key, text]
		)


## 土俵が無いとき(Battle.tscn単体起動)は行ごと出さない。名前の分からない土俵の
## 説明だけを出しても読めないので、性格が決まることと出すことは別に扱う。
func _test_no_field_no_line(check: Callable) -> void:
	check.call(FieldFlavor.line(null) == "", "土俵が無ければ行は空")
	check.call(FieldFlavor.trait_key(null) == "", "土俵が無ければ性格も空")
	var nameless := FieldData.make(
		"", Rect2(0, 0, 10, 10), ArenaWall.WallShape.RECT,
		SpinnerPhysics.StageShape.DISH, 4.9)
	check.call(FieldFlavor.line(nameless) == "", "名前の無い土俵の行は空")
	check.call(
		FieldFlavor.trait_key(nameless) != "",
		"名前が無くても性格そのものは決まる"
	)


func _test_localization(check: Callable) -> void:
	var keys := [
		FieldFlavor.TRAIT_PILLARS, FieldFlavor.TRAIT_CONE, FieldFlavor.TRAIT_OCTAGON,
		FieldFlavor.TRAIT_ROUND, FieldFlavor.TRAIT_STEEP, FieldFlavor.TRAIT_PLAIN,
		"BATTLE_FIELD_LINE",
	]
	for locale in ["ja", "en"]:
		TranslationServer.set_locale(locale)
		var untranslated: Array[String] = []
		for key in keys:
			if TranslationServer.translate(key) == key:
				untranslated.append(key)
		check.call(
			untranslated.is_empty(),
			"%s: 性格の訳がある (未訳: %s)" % [locale, untranslated]
		)

	# 和英で実際に別の文になること(片方を空欄にしてもキーは引けてしまう)。
	var field := FieldRoster.all()[0]
	TranslationServer.set_locale("ja")
	var ja := FieldFlavor.line(field)
	TranslationServer.set_locale("en")
	var en := FieldFlavor.line(field)
	check.call(ja != en, "和英で行が違う (ja=%s / en=%s)" % [ja, en])


## 行が借りている枠に収まること。文言は和英どちらも人が書き足せるので、
## 「読める長さ」を目で決めると次に足した人が知らずに溢れさせる。既定フォントの
## 実測幅で機械的に止める(既定フォントが日本語グリフを持つことは font スイートが見ている)。
func _test_fits_the_row(check: Callable) -> void:
	var font_path: String = ProjectSettings.get_setting("gui/theme/custom_font", "")
	var font := load(font_path) as Font if font_path != "" else null
	check.call(font != null, "既定フォントを読み込める (%s)" % font_path)
	if font == null:
		return
	for locale in ["ja", "en"]:
		TranslationServer.set_locale(locale)
		for field in _all_fields():
			var text := FieldFlavor.line(field)
			var width := font.get_string_size(
				text, HORIZONTAL_ALIGNMENT_LEFT, -1, ROW_FONT_SIZE
			).x
			check.call(
				width <= ROW_WIDTH,
				"%s/%s: 行が枠に収まる (%.0f <= %.0f px: %s)" % [
					locale, field.title_key, width, ROW_WIDTH, text
				]
			)


## 配線。対戦画面がこの行を出し、発射で消していること。
func _test_wiring(check: Callable) -> void:
	var battle := _code(BATTLE_SRC)
	check.call(battle != "", "Battle.gd を読めた")
	check.call(
		battle.contains("_loss_label.text = FieldFlavor.line(_field)"),
		"Battle: 狙い中に土俵の行を出す"
	)
	# 出すのは土俵が決まった後でなければ、単体起動でない本編でも常に空になる。
	var at_apply := battle.find("_apply_run_state()")
	var at_line := battle.find("_loss_label.text = FieldFlavor.line(_field)")
	check.call(
		at_apply >= 0 and at_line > at_apply,
		"Battle: 土俵を確定させてから行を組む"
	)
	# 発射で消えること。_begin() が内訳行を空にするのがその経路。
	var at_begin := battle.find("func _begin(")
	check.call(
		at_begin >= 0 and battle.find('_loss_label.text = ""', at_begin) > at_begin,
		"Battle: 発射の瞬間に行が消える"
	)
	# 決着後は内訳が同じ行へ入る＝2つの文が同時に出ない。
	check.call(
		battle.contains("_loss_label.text = RpsLossText.summary_line("),
		"Battle: 決着後は同じ行へ内訳が入る"
	)
