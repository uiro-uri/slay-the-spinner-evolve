class_name StatPanel
extends CanvasLayer

## ランを通して画面左上に出しっぱなしにする、プレイヤーのビルド表示HUD。
##
## Mainが1枚だけ持ち、画面を差し替えるたびに refresh() する(画面をまたいで
## 生き残るよう ScreenHolder ではなく Main 直下に置く)。中身は GameState から
## 引くので、報酬取得やコンティニュー消費で変わっても切替時に追従する。
##
## 数値の生表示は無粋なので、各ステータスは埋まり具合をバーで見せる(割合は
## StatReadout が出す)。末尾に残機を◯アイコンで並べる。ランが始まる前
## (player_stats が無い=タイトル等)は丸ごと隠す。Mainが show_stats=false で呼ぶ。

## バー1本の幅・高さ、残機アイコンの直径(px)。見た目の詰めなので定数で持つ。
const STAT_BAR_SIZE := Vector2(120.0, 10.0)
const LIFE_PIP_DIAMETER := 12.0

var _grid: GridContainer


func _ready() -> void:
	# 各画面(Battleの$UIは既定layer)より確実に手前へ。
	layer = 128
	_build_shell()
	visible = false


## 器(パネル・余白・グリッド)を一度だけ作る。中身の行は refresh() が積み直す。
func _build_shell() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(12, 12)
	panel.add_theme_stylebox_override("panel", _panel_style())

	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 5)
	panel.add_child(_grid)
	add_child(panel)


## いまの GameState からビルド表示を組み直す。ランが無ければ隠す。
func refresh() -> void:
	if GameState.player_stats == null:
		visible = false
		return
	visible = true

	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()

	# ゴースト札を取得していれば無敵時間の行も付く(StatReadout側で判断)。
	var ghost_seconds := CustomPartCatalog.total_ghost_seconds(GameState.acquired_part_ids)
	for row in StatReadout.rows(GameState.player_stats, ghost_seconds):
		_grid.add_child(_name_label(row["label_key"]))
		_grid.add_child(_bar(row["fraction"]))

	# 残機を◯アイコンで。ランの残機(GameState.continues_left)ぶん並べる。
	_grid.add_child(_name_label("STAT_LIVES"))
	_grid.add_child(_life_pips(GameState.continues_left))


## 画面切替でランがまだ無い/終わった画面(タイトル等)から呼ぶ。中身は消さず隠すだけ。
func hide_panel() -> void:
	visible = false


## ステータス名ラベル。キーを入れてControlの自動翻訳に任せる。床やコマの上でも
## 読めるよう、メッセージ表示と同じ明色文字＋暗色縁取り。
func _name_label(key: String) -> Label:
	var label := Label.new()
	label.text = key
	label.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
	label.add_theme_color_override("font_outline_color", Palette.TEXT_OUTLINE)
	label.add_theme_constant_override("outline_size", Palette.MESSAGE_OUTLINE_SIZE)
	return label


## ステータス1本ぶんのバー。max_value=1、value=fraction(0〜1)で埋まり具合にする。
## 見た目はHPバーに寄せ、塗りはプレイヤー色。
func _bar(fraction: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = STAT_BAR_SIZE
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.value = fraction
	bar.add_theme_stylebox_override("background", _bar_bg_style())
	bar.add_theme_stylebox_override("fill", _fill_style(Palette.PLAYER))
	return bar


## 残機を◯アイコンで横並びに。残機ぶんだけプレイヤー色の小円を置く。0個ならHBoxが空。
## 円はフォント依存の記号ではなく、角丸を直径の半分にしたPanelで確実に描く。
func _life_pips(count: int) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in maxi(0, count):
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(LIFE_PIP_DIAMETER, LIFE_PIP_DIAMETER)
		pip.add_theme_stylebox_override("panel", _circle_style(Palette.PLAYER))
		box.add_child(pip)
	return box


## パネル背景(暗紫・半透明)。内側に余白を持たせて中身と縁の間を空ける。
func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(Palette.FLOOR, 0.72)
	s.set_corner_radius_all(6)
	for m in ["left", "right", "top", "bottom"]:
		s.set("content_margin_" + m, 8.0)
	return s


func _bar_bg_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(Palette.BG, 0.6)
	s.set_corner_radius_all(4)
	return s


func _fill_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(4)
	return s


func _circle_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(int(LIFE_PIP_DIAMETER / 2.0))
	return s
