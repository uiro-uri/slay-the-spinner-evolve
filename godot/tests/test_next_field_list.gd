extends RefCounted

## NextFieldList(マップの「進める先の土俵」パネル)の検査。
##
## 見るのは5つ:
## (1) 進める先の**全部**が行になり、画面と同じ左→右の順に並ぶこと。
##     1つでも欠けると「名前の無い選択肢」が残り、この機能の目的
##     (コイントスを判断に変える)が達成されない。
## (2) 向きが列の差から決まること。行がどのノードの話かは位置ではなく
##     この語だけが決めているので、ここが嘘だと全部が嘘になる。
## (3) 行に土俵の名前と性格が両方入り、生の訳キーが出ないこと。
## (4) 行が左パネルの幅に対して MAX_LINES 行以内に収まること。文言は和英とも
##     人が後から書き足せるので、目で決めると次に足した人が溢れさせる。
## (5) マップ画面が実際にこれを組み、行が0なら隠していること(配線)。
##
## 実UI(MapScreen)は @onready のノードパスを持つのでヘッドレスの--scriptモードでは
## 組み立てられない。配線はソーステキスト照合で見る(test_field_flavor と同じ手口。
## コメントを落としてから照合するのも同じ理由)。
##
## サボタージュ検証は journal に記録。

const MAP_SRC := "res://scenes/map/MapScreen.gd"
const MAP_SCENE := "res://scenes/map/MapScreen.tscn"


func run(check: Callable) -> void:
	var prev_locale := TranslationServer.get_locale()
	_test_direction_key(check)
	_test_every_reachable_gets_a_row(check)
	_test_order_is_left_to_right(check)
	_test_row_text(check)
	_test_no_field_no_row(check)
	_test_localization(check)
	_test_fits_the_panel(check)
	_test_populate(check)
	_test_wiring(check)
	TranslationServer.set_locale(prev_locale)


## コメント行を落としたソース。理由を書いたコメントが照合に自分でヒットするのを避ける。
static func _code(path: String) -> String:
	var out := ""
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out += line + "\n"
	return out


static func _tree_with_seed(seed_value: int) -> MapTree:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return MapTree.generate(rng)


func _test_direction_key(check: Callable) -> void:
	var here := Vector2i(3, 2)
	check.call(
		NextFieldList.direction_key(here, Vector2i(4, 1)) == NextFieldList.DIR_LEFT,
		"列-1は左下"
	)
	check.call(
		NextFieldList.direction_key(here, Vector2i(4, 2)) == NextFieldList.DIR_STRAIGHT,
		"同じ列は真下"
	)
	check.call(
		NextFieldList.direction_key(here, Vector2i(4, 3)) == NextFieldList.DIR_RIGHT,
		"列+1は右下"
	)
	# 隣接していない座標は想定外。黙って左下扱いにせず空を返す。
	check.call(
		NextFieldList.direction_key(here, Vector2i(4, 4)) == "",
		"隣接しない列は向きが決まらない"
	)


## 進める先の数と行の数が必ず一致すること。ランを実際に歩いて全段で見る。
func _test_every_reachable_gets_a_row(check: Callable) -> void:
	TranslationServer.set_locale("ja")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260807
	var mismatches: Array[String] = []
	var checked := 0
	var saw_multi := false
	for i in 40:
		var tree := _tree_with_seed(i * 977 + 5)
		if tree == null:
			continue
		while true:
			var targets := tree.next_coords()
			if targets.is_empty():
				break
			var list := NextFieldList.rows(tree)
			checked += 1
			if targets.size() >= 2:
				saw_multi = true
			if list.size() != targets.size():
				mismatches.append("段%d: 進める先%d 行%d" % [
					tree.current_step(), targets.size(), list.size()
				])
			tree.advance_to(targets[rng.randi() % targets.size()])
	check.call(checked > 0, "歩けた選択局面がある (%d)" % checked)
	check.call(saw_multi, "2択以上の局面を通っている")
	check.call(
		mismatches.is_empty(),
		"進める先は全部が行になる (欠け: %s)" % [mismatches.slice(0, 5)]
	)


## 行の順が画面の並び(左の列から右の列)と一致すること。
## MapScreen._to_pixel は列が大きいほど右に置くので、列の昇順が画面の左→右。
func _test_order_is_left_to_right(check: Callable) -> void:
	var out_of_order := 0
	var multi_seen := 0
	for i in 40:
		var tree := _tree_with_seed(i * 611 + 17)
		if tree == null:
			continue
		var list := NextFieldList.rows(tree)
		if list.size() < 2:
			continue
		multi_seen += 1
		for j in range(1, list.size()):
			var prev: Vector2i = list[j - 1]["coord"]
			var cur: Vector2i = list[j]["coord"]
			if prev.y >= cur.y:
				out_of_order += 1
	check.call(multi_seen > 0, "2行以上の局面を見ている (%d)" % multi_seen)
	check.call(out_of_order == 0, "行は左の列から順に並ぶ (逆順 %d件)" % out_of_order)


## 行に向き・名前・性格が全部入り、生の訳キーが出ないこと。
func _test_row_text(check: Callable) -> void:
	TranslationServer.set_locale("ja")
	var tree := _tree_with_seed(4242)
	check.call(tree != null, "マップを生成できた")
	if tree == null:
		return
	var list := NextFieldList.rows(tree)
	check.call(not list.is_empty(), "スタート地点に進める先がある")
	for row in list:
		var text := NextFieldList.row_text(row)
		var dir_ja := TranslationServer.translate(row["direction_key"])
		check.call(dir_ja in text, "行に向きが入る (%s)" % text)
		check.call(row["line"] in text, "行に土俵の名前と性格が入る (%s)" % text)
		check.call(not ("MAP_NEXT_" in text), "向きの訳キーが生で出ない (%s)" % text)
		check.call(not ("FIELD_" in text), "土俵の訳キーが生で出ない (%s)" % text)


## 土俵の無いノード(名前が引けない)は行にしない。名前の分からない土俵の説明だけを
## 出しても読めないので、FieldFlavor が空を返したら行ごと落とす。
func _test_no_field_no_row(check: Callable) -> void:
	check.call(NextFieldList.rows(null).is_empty(), "マップが無ければ行も無い")
	var tree := _tree_with_seed(31337)
	if tree == null:
		return
	var before := NextFieldList.rows(tree).size()
	check.call(before > 0, "土俵付きなら行が出る (%d)" % before)
	for coord in tree.next_coords():
		tree.nodes[coord].field = null
	check.call(
		NextFieldList.rows(tree).is_empty(),
		"土俵の無いノードは行にならない"
	)


func _test_localization(check: Callable) -> void:
	var keys := [
		NextFieldList.DIR_LEFT, NextFieldList.DIR_STRAIGHT, NextFieldList.DIR_RIGHT,
		NextFieldList.ROW_FORMAT, NextFieldList.HEADING,
	]
	for locale in ["ja", "en"]:
		TranslationServer.set_locale(locale)
		var untranslated: Array[String] = []
		for key in keys:
			if TranslationServer.translate(key) == key:
				untranslated.append(key)
		check.call(
			untranslated.is_empty(),
			"%s: 進める先パネルの訳がある (未訳: %s)" % [locale, untranslated]
		)

	# 和英で実際に別の文になること(片方を空欄にしてもキーは引ける)。
	var tree := _tree_with_seed(555)
	if tree == null:
		return
	var row := NextFieldList.rows(tree)[0]
	TranslationServer.set_locale("ja")
	var ja := NextFieldList.row_text(row)
	TranslationServer.set_locale("en")
	var en := NextFieldList.row_text(row)
	check.call(ja != en, "和英で行が違う (ja=%s / en=%s)" % [ja, en])


## 行が左パネルの幅に対して MAX_LINES 行以内に収まること。溢れると左の列が
## 下へ伸びて取得済み一覧を押し出す(横画面では画面内に収まってしまい気付けない)。
## 実際に出る全組み合わせ(道中6つ＋決戦の土俵 × 向き3種)を和英で測る。
func _test_fits_the_panel(check: Callable) -> void:
	var font_path: String = ProjectSettings.get_setting("gui/theme/custom_font", "")
	var font := load(font_path) as Font if font_path != "" else null
	check.call(font != null, "既定フォントを読み込める (%s)" % font_path)
	if font == null:
		return
	var fields := FieldRoster.all()
	fields.append(FieldRoster.boss_field())
	var budget := NextFieldList.ROW_WIDTH * float(NextFieldList.MAX_LINES)
	for locale in ["ja", "en"]:
		TranslationServer.set_locale(locale)
		for field in fields:
			for dir_key in [
				NextFieldList.DIR_LEFT, NextFieldList.DIR_STRAIGHT, NextFieldList.DIR_RIGHT
			]:
				var text := NextFieldList.row_text({
					"direction_key": dir_key, "line": FieldFlavor.line(field)
				})
				var width := font.get_string_size(
					text, HORIZONTAL_ALIGNMENT_LEFT, -1, NextFieldList.ROW_FONT_SIZE
				).x
				check.call(
					width <= budget,
					"%s/%s/%s: 行が%d行に収まる (%.0f <= %.0f px: %s)" % [
						locale, field.title_key, dir_key, NextFieldList.MAX_LINES,
						width, budget, text
					]
				)


## 器への積み方。行数ぶんのLabelができ、積み直しで前回の行が残らないこと。
## Controlを作るがSceneTreeへは入れない(AcquiredUpgradeList のテストと同じ)。
func _test_populate(check: Callable) -> void:
	TranslationServer.set_locale("ja")
	var container := VBoxContainer.new()

	check.call(NextFieldList.populate(container, null) == 0, "マップが無ければ0行")
	check.call(container.get_child_count() == 0, "マップが無ければ器も空")

	var tree := _tree_with_seed(909)
	if tree == null:
		container.free()
		return
	var expected := NextFieldList.rows(tree).size()
	var count := NextFieldList.populate(container, tree)
	check.call(count == expected, "行数を返す (%d == %d)" % [count, expected])
	check.call(
		container.get_child_count() == expected,
		"行数ぶんのLabelを積む (%d)" % container.get_child_count()
	)
	var first := container.get_child(0)
	check.call(first is Label, "積むのはLabel (%s)" % first.get_class())
	check.call(
		(first as Label).autowrap_mode != TextServer.AUTOWRAP_OFF,
		"長い行は折り返す"
	)

	# 積み直しても前回の行が残らない(進める先は段ごとに変わる)。
	NextFieldList.populate(container, tree)
	check.call(
		container.get_child_count() == expected,
		"積み直しで行が二重にならない (%d)" % container.get_child_count()
	)
	container.free()


## 配線。マップ画面がこれを組み、行が0ならパネルごと隠していること。
func _test_wiring(check: Callable) -> void:
	var map := _code(MAP_SRC)
	check.call(map != "", "MapScreen.gd を読めた")
	check.call(
		map.contains("NextFieldList.populate(_next_list, _tree)"),
		"MapScreen: 進める先の行を組む"
	)
	check.call(
		map.contains("_next_panel.visible = NextFieldList.populate("),
		"MapScreen: 行が0ならパネルを隠す"
	)
	# setup() から呼ばれること。_rebuild_acquired と同じく毎回組み直さないと
	# 前の段の進める先が残る。
	var at_setup := map.find("func setup(")
	var at_call := map.find("_rebuild_next_fields()", at_setup)
	var at_next_func := map.find("func _process(")
	check.call(
		at_setup >= 0 and at_call > at_setup and at_call < at_next_func,
		"MapScreen: setup() が毎回組み直す"
	)

	# シーン側にパネルとリストが実在すること(ノードパスが合っていないと
	# @onready が null になり、実行時に初めて落ちる)。
	var scene := FileAccess.get_file_as_string(MAP_SCENE)
	check.call(
		scene.contains('[node name="NextPanel" type="PanelContainer" parent="LeftColumn"]'),
		"MapScreen.tscn: NextPanel がある"
	)
	check.call(
		scene.contains('[node name="List" type="VBoxContainer" parent="LeftColumn/NextPanel/VBox"]'),
		"MapScreen.tscn: 行を積む List がある"
	)
	check.call(
		scene.contains('text = "MAP_NEXT_HEADING"'),
		"MapScreen.tscn: 見出しが訳キーで入っている"
	)
