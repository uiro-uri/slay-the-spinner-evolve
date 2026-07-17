extends Control

## 戦闘に勝った後の報酬選択。3枚から1枚選ぶ。
##
## プロトタイプはBootstrapのカードで、レアだけ金色に光らせていた。
## その演出は踏襲する。

## 選ばれた。適用と遷移はMainがやる。
signal part_chosen(part: CustomPart)

const CHOICE_COUNT := 3

@onready var _cards: HBoxContainer = $CenterContainer/VBoxContainer/Cards

var _shine := 0.0


func setup(parts: Array[CustomPart]) -> void:
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()

	for part in parts:
		_cards.add_child(_build_card(part))


func _build_card(part: CustomPart) -> Control:
	var is_rare := part.rarity == CustomPart.Rarity.RARE

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(220, 260)
	if is_rare:
		panel.add_theme_stylebox_override("panel", CustomPart.rare_stylebox())

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = part.title_key
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)

	# 説明文はパーツの実データから組み立てる。手書きしないので嘘にならない。
	var text := Label.new()
	text.text = part.describe()
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(text)

	if is_rare:
		var tag := Label.new()
		tag.text = "PART_RARITY_RARE"
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(tag)
		for label in [title, text, tag]:
			label.add_theme_color_override("font_color", CustomPart.RARE_TEXT_COLOR)

	var button := Button.new()
	button.text = "REWARD_SELECT"
	button.pressed.connect(func() -> void: part_chosen.emit(part))
	box.add_child(button)

	return panel


func _process(delta: float) -> void:
	# レアのカードを控えめに明滅させる。プロトタイプの光る演出に相当。
	_shine += delta * 2.0
	var pulse := 1.0 + sin(_shine) * 0.06
	for card in _cards.get_children():
		if card.has_theme_stylebox_override("panel"):
			card.modulate = Color(pulse, pulse, pulse)
