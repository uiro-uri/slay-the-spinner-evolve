extends Control

## ゲームクリア画面専用の「ゆっくり流れる虹」背景。
## シェーダーは使わず、この repo の流儀どおり _draw() で横帯を塗り、_process() で
## 色相の位相を進めて queue_redraw() することで、帯が縦にスクロールして見えるようにする。
##
## 色そのものの決定は純関数 hue_at() に切り出し、ヘッドレスでテストする
## (tests/test_rainbow_background.gd)。描画は hue_at() を引くだけにして、
## 「表示ロジックは純関数で検証」の流儀に乗せる。
##
## この背景は最背面(GameClear ルートの最初の子)に置き、テキストは手前に乗る。
## mouse_filter は IGNORE にして、背後にいる本ノードがボタン入力を奪わないようにする。

## 虹をスクロールさせる速さ(1秒あたりに進む位相。1.0 で一周)。「ゆっくり」= 約20秒で一周。
@export var scroll_speed: float = 0.05

## 帯の彩度・明度。縁取りで可読性を担保できるのでほどよく鮮やかに。
@export_range(0.0, 1.0) var saturation: float = 0.6
@export_range(0.0, 1.0) var value: float = 0.85

## 高さを何本の横帯に分けて塗るか。多いほど滑らかなグラデーションになる。
@export_range(2, 256) var band_count: int = 64

## 現在の色相位相。_process で 0..1 を巡回する。
var _phase: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 縦位置の割合 fraction(0=上, 1=下)と時間位相 phase から、その帯の色を返す。
## 色相を fraction+phase で回し、wrapf で 0..1 に畳む(phase が進むと帯がスクロールして見える)。
## value 非依存な純関数なので、彩度・明度を変えても性質(循環性・単調性)は保たれる。
static func hue_at(fraction: float, phase: float, sat: float, val: float) -> Color:
	return Color.from_hsv(wrapf(fraction + phase, 0.0, 1.0), sat, val)


func _process(delta: float) -> void:
	_phase = wrapf(_phase + delta * scroll_speed, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var band_h := h / float(band_count)
	for i in band_count:
		var fraction := i / float(band_count)
		var color := hue_at(fraction, _phase, saturation, value)
		# 帯どうしの継ぎ目に隙間が出ないよう、高さは切り上げ気味に少しだけ重ねる。
		draw_rect(Rect2(0.0, i * band_h, w, band_h + 1.0), color)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
