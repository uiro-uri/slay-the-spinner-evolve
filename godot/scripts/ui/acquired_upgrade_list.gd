class_name AcquiredUpgradeList
extends RefCounted

## このランで取得済みのアップグレード(カスタムパーツ)の一覧UIを組み立てる共有ヘルパー。
##
## マップ画面(サイドの「取得済み」パネル)とゲームクリア画面(締めのリザルト)で同じ行を
## 使いたいので、行ビルダーをここに集約する。もとは MapScreen が抱えていたが、
## クリア画面にも出すにあたり二重持ちを避けて切り出した。
##
## 集約(重複の畳み込み)は CustomPartCatalog.aggregate_acquired に任せ、ここは見た目だけを担う。


## listの中身を取得済みパーツの行で組み直す。既存の子は消してから積む。
static func populate(list: VBoxContainer, ids: Array[int]) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()

	var entries := CustomPartCatalog.aggregate_acquired(ids)
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "MAP_NO_UPGRADES"  # キー＝自動翻訳
		list.add_child(empty)
		return

	for entry in entries:
		list.add_child(build_row(entry["part"], entry["count"]))


## 取得済みパーツ1件分の行。報酬カード(RewardScreen._build_card)の縮約版。
## 選択ボタンや明滅はなく、名前＋効果を静的に見せるだけ。
static func build_row(part: CustomPart, count: int) -> Control:
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
	# 静的関数からは tr() を呼べないので、TranslationServer で現在ロケールを引く
	# (GameClear.format_* と同じ流儀。数個の連結には文脈がないので等価)。
	if count > 1:
		title.text = (
			TranslationServer.translate(part.title_key)
			+ TranslationServer.translate("PART_COUNT_SUFFIX").format([count])
		)
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
