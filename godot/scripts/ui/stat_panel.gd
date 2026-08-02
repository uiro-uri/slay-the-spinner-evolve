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

## 敵の行(取り分バー)の「互角」目盛りの幅(px)と色。バーの中央に縦線を1本立てて、
## そこを越えたら相手の方が上、と読ませる。細いので明色＋半透明で十分目立つ。
const PARITY_TICK_WIDTH := 2.0
const PARITY_TICK_COLOR := Color(1, 1, 1, 0.55)

## 値が変わった行のバーを一瞬明るくして気付かせる。塗りをこの明るい色にしてから
## プレイヤー色へ戻す(cyanはG/Bが既に最大でmodulate倍率だと明度が上がらないため、
## 色そのものを白側へ寄せる)。戻るまでの秒数と、変化とみなす割合の下限も。
const FLASH_COLOR := Color(1, 1, 1)
const FLASH_DURATION := 0.45
const FLASH_EPS := 0.0001

var _grid: GridContainer

## 直前に見せた各行の埋まり具合(label_key -> fraction)。次のrefreshで差分を出しフラッシュに使う。
var _prev_fractions: Dictionary = {}

## 直前に見たプレイヤーstatsの実体。reset_run()で別ランになると実体が変わるので、
## それを新ラン(＝基準取り直し、フラッシュしない)の合図に使う。パーツ取得はstatsを
## その場で書き換える(実体は同じ)ので、ラン中の変化は差分として拾える。
var _run_stats: SpinnerStats = null


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
## 前回から埋まり具合が変わった行のバーは、組み直した直後に一瞬明るくして目立たせる。
##
## enemy_stats はこれから戦う相手のステータス。渡されたときだけ、自分のビルドの下に
## 「硬さ 相手 / 寿命 相手」の取り分バーを敵色で足す(StatReadout.enemy_rows)。
## Mainは戦闘画面へ差し替えるときだけ渡す——GameState.pending_enemies は次の戦闘まで
## 消えないので、それを直接見るとマップ画面に前の相手が出たままになる。
func refresh(enemy_stats: Array[SpinnerStats] = []) -> void:
	if GameState.player_stats == null:
		visible = false
		return
	visible = true

	# 別ラン(stats実体が変わった)なら基準を取り直し、初回なので差分フラッシュはしない。
	var fresh := GameState.player_stats != _run_stats
	_run_stats = GameState.player_stats
	if fresh:
		_prev_fractions.clear()

	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()

	# ゴースト札を取得していれば無敵時間の行も付く(StatReadout側で判断)。
	var ghost_seconds := CustomPartCatalog.total_ghost_seconds(GameState.acquired_part_ids)
	var current: Dictionary = {}
	for row in StatReadout.rows(GameState.player_stats, ghost_seconds):
		var key: String = row["label_key"]
		var fraction: float = row["fraction"]
		current[key] = fraction
		_grid.add_child(_name_label(key))
		var bar := _bar(fraction)
		_grid.add_child(bar)
		# 前回に無かった行(新登場)か、埋まり具合が動いた行だけ光らせる。
		if not fresh and (not _prev_fractions.has(key) or absf(fraction - _prev_fractions[key]) > FLASH_EPS):
			_flash(bar, Palette.PLAYER)

	# これから戦う相手が渡されていれば、自分との取り分を敵色のバーで続ける。
	# 互角の位置に目盛りが立つので、越えていれば「相手の方が硬い/長生き」と読める。
	for row in StatReadout.enemy_rows(GameState.player_stats, enemy_stats):
		var key: String = row["label_key"]
		var fraction: float = row["fraction"]
		current[key] = fraction
		_grid.add_child(_name_label(key))
		var bar := _bar(fraction, Palette.ENEMY)
		bar.add_child(_parity_tick())
		_grid.add_child(bar)
		if not fresh and (not _prev_fractions.has(key) or absf(fraction - _prev_fractions[key]) > FLASH_EPS):
			_flash(bar, Palette.ENEMY)

	# 残機を◯アイコンで。ランの残機(GameState.continues_left)ぶん並べる。
	_grid.add_child(_name_label("STAT_LIVES"))
	_grid.add_child(_life_pips(GameState.continues_left))

	_prev_fractions = current


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
## 見た目はHPバーに寄せる。塗りは既定でプレイヤー色、敵の取り分バーだけ敵色を渡す。
func _bar(fraction: float, color: Color = Palette.PLAYER) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = STAT_BAR_SIZE
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.value = fraction
	bar.add_theme_stylebox_override("background", _bar_bg_style())
	bar.add_theme_stylebox_override("fill", _fill_style(color))
	return bar


## 敵の取り分バーに立てる「互角」の目盛り。アンカーで幅の中央に置くので、
## バーの実寸がレイアウト後に決まっても勝手に追従する(生成時に幅を知らなくてよい)。
## 位置は StatReadout.PARITY をそのまま使う——取り分の定義が変われば目盛りも動く。
func _parity_tick() -> Panel:
	var tick := Panel.new()
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tick.anchor_left = StatReadout.PARITY
	tick.anchor_right = StatReadout.PARITY
	tick.anchor_top = 0.0
	tick.anchor_bottom = 1.0
	tick.offset_left = -PARITY_TICK_WIDTH * 0.5
	tick.offset_right = PARITY_TICK_WIDTH * 0.5
	tick.offset_top = 0.0
	tick.offset_bottom = 0.0
	var style := StyleBoxFlat.new()
	style.bg_color = PARITY_TICK_COLOR
	tick.add_theme_stylebox_override("panel", style)
	return tick


## 値が変わったバーを一瞬明るくして素へ戻す。塗り(fill)の色を白へ飛ばしてから
## 素の色へ引き戻すので、埋まった部分がぱっと光って落ち着く。バーごとに
## fillスタイルボックスは別実体(_fill_styleが都度new)なので、他のバーには波及しない。
## tweenはバーに束ねるので、次のrefreshでバーが消えても勝手に片付く。
## restは戻り先の色。敵の取り分バーはプレイヤー色へ戻すと色が入れ替わってしまう。
func _flash(bar: ProgressBar, rest: Color) -> void:
	var fill := bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill == null:
		return
	fill.bg_color = FLASH_COLOR
	var tween := bar.create_tween()
	tween.tween_property(fill, "bg_color", rest, FLASH_DURATION).set_ease(Tween.EASE_OUT)


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
