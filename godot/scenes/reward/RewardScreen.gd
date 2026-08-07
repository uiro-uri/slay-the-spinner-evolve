extends Control

## 戦闘に勝った後の報酬選択。3枚から1枚選ぶ。
##
## プロトタイプはBootstrapのカードで、レアだけ金色に光らせていた。
## その演出は踏襲する。

## 選ばれた。適用と遷移はMainがやる。
signal part_chosen(part: CustomPart)

const CHOICE_COUNT := 3

@onready var _cards: HBoxContainer = $CenterContainer/VBoxContainer/Cards
## 攻めの行の基準(相手1体の硬さ)を言う注記。3枚のカードで基準は共通なので、
## カードの中ではなくカードの外に1行だけ置く(PartPreview.attack_basis_text)。
## 基準の相手が居ない決戦のあとは行ごと隠す。
@onready var _attack_basis: Label = $CenterContainer/VBoxContainer/AttackBasis

var _shine := 0.0

## 見積もりの基準になる今のビルド。setup()で受け取る。nullなら見積もりを出さない
## (ステータス無しで呼ばれる古い経路・テストのため)。
var _stats: SpinnerStats = null
var _continues := -1
var _ghost_seconds := 0.0

## 攻め力(PartPreview.attack)の基準にする相手1体の硬さ。0以下ならその行を出さない。
## Mainが「次に踏みうる部屋のいちばん硬い1体」を渡す(ThreatMeter参照)。
var _opponent_toughness := 0.0


## 選択肢を並べる。stats/continues/ghost_secondsは各カードの「取るとどうなるか」
## (PartPreview)の基準で、Mainが今のGameStateから渡す。
func setup(
	parts: Array[CustomPart], stats: SpinnerStats = null,
	continues: int = -1, ghost_seconds: float = 0.0,
	opponent_toughness: float = 0.0
) -> void:
	_stats = stats
	_continues = continues
	_ghost_seconds = ghost_seconds
	_opponent_toughness = opponent_toughness

	# 攻めの行の基準。翻訳済みの文に数字を差し込むので、このラベルだけ
	# 自動翻訳を切ってある(tscn の auto_translate_mode)。
	var basis := PartPreview.attack_basis_text(_opponent_toughness)
	_attack_basis.text = basis
	_attack_basis.visible = basis != ""

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

	# 上限に達して動かなくなった軸の注記。効果文は上限に達した後も
	# 「直径 ×1.25（上限 2）＆質量 ×1.15（上限 8）」と両方を謳い続けるが、
	# 既に直径が上限のビルドでは半分が死んでいる。止まっている軸が無ければ
	# 何も足さない。詳細は CustomPart.capped_axes の冒頭コメント。
	var capped_label: Label = null
	if _stats != null:
		var capped_text := part.capped_note(_stats)
		if capped_text != "":
			capped_label = Label.new()
			capped_label.text = capped_text
			capped_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			capped_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			capped_label.add_theme_font_size_override("font_size", 12)
			# 見積もりの「下がった値」と同じ色。良し悪しは色で見せる約束
			# (_build_preview_row と同じ手口)なので、レアの明るい地では
			# 暗色の縁取りを足して読ませる。dark(暗色文字)には入れない
			# ——自前の色を持つ行は見積もりの値と同じ扱いにする。
			capped_label.add_theme_color_override("font_color", Palette.STAT_DOWN)
			if is_rare:
				capped_label.add_theme_color_override(
					"font_outline_color", Palette.TEXT_OUTLINE
				)
				capped_label.add_theme_constant_override("outline_size", 3)
			box.add_child(capped_label)

	# 「取るとどうなるか」の見積もり。効果テキストは倍率までしか言わないので、
	# 勝敗を決める複合量(硬さ・打たれ強さ)がどちらへ動くかをここで見せる。詳細は
	# scripts/ui/part_preview.gd の冒頭コメント。
	var preview_labels: Array[Label] = []
	if _stats != null:
		var heading := Label.new()
		heading.text = "REWARD_PREVIEW_HEADING"
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heading.add_theme_font_size_override("font_size", 12)
		box.add_child(heading)
		preview_labels.append(heading)
		for row in PartPreview.rows(
			_stats, part, _continues, _ghost_seconds, _opponent_toughness
		):
			var line := _build_preview_row(row, is_rare)
			box.add_child(line)
			preview_labels.append(line.get_child(0) as Label)

	if is_rare:
		var tag := Label.new()
		tag.text = "PART_RARITY_RARE"
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(tag)
		# 金の地は明るいまま残る唯一の面なので、暗色文字＋明色縁取りで読ませる
		# (戦闘メッセージの明色文字＋暗色縁取りと対の関係)。文字色はCustomPartが出所。
		var dark: Array[Label] = [title, text, tag]
		dark.append_array(preview_labels)
		for label in dark:
			label.add_theme_color_override("font_color", CustomPart.RARE_TEXT_COLOR)
			label.add_theme_color_override("font_outline_color", Palette.TEXT_PRIMARY)
			label.add_theme_constant_override("outline_size", 3)

	var button := Button.new()
	button.text = "REWARD_SELECT"
	button.pressed.connect(func() -> void: part_chosen.emit(part))
	box.add_child(button)

	return panel


## 見積もり1行。左に項目名、右に「今の値 → 取った後の値」。
## 良し悪しは値の色で見せる(変化なしは既定色のまま)。
##
## レアカードは地が明るい金なので、明色の値には暗色の縁取りを付けて読ませる
## (戦闘メッセージと同じ手口。項目名の方は呼び出し側が暗色文字にする)。
func _build_preview_row(row: Dictionary, is_rare: bool) -> HBoxContainer:
	var line := HBoxContainer.new()

	var name_label := Label.new()
	name_label.text = row["label_key"]
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)

	var value := Label.new()
	value.text = PartPreview.format_row(row)
	value.add_theme_font_size_override("font_size", 13)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if row["better"] != 0:
		value.add_theme_color_override(
			"font_color", Palette.STAT_UP if row["better"] > 0 else Palette.STAT_DOWN
		)
		if is_rare:
			value.add_theme_color_override("font_outline_color", Palette.TEXT_OUTLINE)
			value.add_theme_constant_override("outline_size", 3)
	elif is_rare:
		value.add_theme_color_override("font_color", CustomPart.RARE_TEXT_COLOR)
		value.add_theme_color_override("font_outline_color", Palette.TEXT_PRIMARY)
		value.add_theme_constant_override("outline_size", 3)
	line.add_child(value)

	return line


func _process(delta: float) -> void:
	# レアのカードを控えめに明滅させる。プロトタイプの光る演出に相当。
	_shine += delta * 2.0
	var pulse := 1.0 + sin(_shine) * 0.06
	for card in _cards.get_children():
		if card.has_theme_stylebox_override("panel"):
			card.modulate = Color(pulse, pulse, pulse)
