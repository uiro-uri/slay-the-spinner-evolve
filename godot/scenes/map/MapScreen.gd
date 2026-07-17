extends Control

## 分岐マップの画面。今いるノードと、そこから進める先だけを押せる。
##
## プロトタイプはHTMLのtableとJinjaのforで矢印を1マスずつ組み立てていたが、
## ここは_draw()で線を引き、ノードだけをButtonとして置く。

## 進める先が選ばれた。遷移先の判断はMainがする。
signal node_chosen(coord: Vector2i)

const CELL := Vector2(64.0, 62.0)

## 中央列(2)が画面中央に来る位置。設計解像度1280x720に合わせている。
## 段0からゴールの段9までがCELL.y間隔で並ぶので、上端はタイトル表示の下に置く。
const ORIGIN := Vector2(640.0, 80.0)
const NODE_RADIUS := 18.0

const COLOR_LINE := Color(0.45, 0.45, 0.5, 0.55)
const COLOR_VISITED := Color(0.6, 0.75, 0.9)
const COLOR_CURRENT := Color(0.4, 0.7, 1.0)
const COLOR_NEXT := Color(0.45, 0.85, 0.5)
const COLOR_PLAIN := Color(0.75, 0.75, 0.78)

var _tree: MapTree
var _buttons: Dictionary = {}

@onready var _acquired_list: VBoxContainer = $AcquiredPanel/VBox/Scroll/List


func setup(tree: MapTree) -> void:
	_tree = tree
	_rebuild()
	_rebuild_acquired()


func _rebuild() -> void:
	for button in _buttons.values():
		button.queue_free()
	_buttons.clear()

	if _tree == null:
		return

	var reachable := _tree.next_coords()
	for coord in _tree.nodes:
		var button := Button.new()
		button.size = Vector2(NODE_RADIUS, NODE_RADIUS) * 2.0
		button.position = _to_pixel(coord) - button.size * 0.5
		button.flat = true
		# ノードIDはメタ情報なので出さない（プロトタイプも同じ判断をしている）。
		button.text = ""

		var is_next: bool = coord in reachable
		button.disabled = not is_next
		button.mouse_default_cursor_shape = (
			Control.CURSOR_POINTING_HAND if is_next else Control.CURSOR_ARROW
		)
		if is_next:
			button.pressed.connect(_on_node_pressed.bind(coord))
		add_child(button)
		_buttons[coord] = button

	queue_redraw()


func _on_node_pressed(coord: Vector2i) -> void:
	node_chosen.emit(coord)


## このランで取得済みのパーツ一覧を組み直す。集約はカタログの純関数に任せる。
func _rebuild_acquired() -> void:
	for child in _acquired_list.get_children():
		_acquired_list.remove_child(child)
		child.queue_free()

	var entries := CustomPartCatalog.aggregate_acquired(GameState.acquired_part_ids)
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "MAP_NO_UPGRADES"  # キー＝自動翻訳
		_acquired_list.add_child(empty)
		return

	for entry in entries:
		_acquired_list.add_child(_build_row(entry["part"], entry["count"]))


## 取得済みパーツ1件分の行。報酬カード(RewardScreen._build_card)の縮約版。
## 選択ボタンや明滅はなく、名前＋効果を静的に見せるだけ。
func _build_row(part: CustomPart, count: int) -> Control:
	var is_rare := part.rarity == CustomPart.Rarity.RARE

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_rare:
		panel.add_theme_stylebox_override("panel", CustomPart.rare_stylebox())

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var title := Label.new()
	# 個数がある時だけ「×2」を付ける。1個ならキーのまま渡して自動翻訳に任せる。
	if count > 1:
		title.text = tr(part.title_key) + tr("PART_COUNT_SUFFIX").format([count])
	else:
		title.text = part.title_key
	title.add_theme_font_size_override("font_size", 16)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)

	# 説明文はパーツの実データから生成される（custom_part.gd:describe）ので嘘にならない。
	var text := Label.new()
	text.text = part.describe()
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)

	if is_rare:
		# 金色の地は明るいので文字を暗くしないと読めない。報酬カードと同じ扱い。
		for label in [title, text]:
			label.add_theme_color_override("font_color", CustomPart.RARE_TEXT_COLOR)

	return panel


func _to_pixel(coord: Vector2i) -> Vector2:
	# 列は中央(2)を基準に左右へ振り分ける。
	return ORIGIN + Vector2((coord.y - 2) * CELL.x, coord.x * CELL.y)


func _draw() -> void:
	if _tree == null:
		return

	for coord in _tree.nodes:
		var node: MapTree.MapNode = _tree.nodes[coord]
		var from := _to_pixel(coord)
		for target in node.targets():
			if not _tree.nodes.has(target):
				continue
			var to := _to_pixel(target)
			# ノードの縁から縁へ引く。
			var dir := (to - from).normalized()
			draw_line(
				from + dir * NODE_RADIUS, to - dir * NODE_RADIUS, COLOR_LINE, 2.0, true
			)

	var reachable := _tree.next_coords()
	for coord in _tree.nodes:
		var center := _to_pixel(coord)
		var color := COLOR_PLAIN
		if coord == _tree.current_coord:
			color = COLOR_CURRENT
		elif coord in reachable:
			color = COLOR_NEXT
		elif coord.x < _tree.current_step():
			color = COLOR_VISITED
		draw_circle(center, NODE_RADIUS, color)
		draw_arc(center, NODE_RADIUS, 0, TAU, 32, Color(0.2, 0.2, 0.25, 0.8), 2.0, true)
