class_name DamageNumber
extends Node2D

## 壁・柱で失った回転を、当たった場所に浮かせて見せる数字。
## 自分で消えるので、生やしたら後始末は要らない(CollisionSparkと同じ流儀)。
##
## 値の決め方(出す/出さない・文字・色・退場)は WallDamageReadout の純粋関数が
## 持っていて、ここは描くだけ。大きさの基準は衝撃波と同じ SparkScale なので、
## 「大きい波＝大きい数字」が必ず揃う。
##
## 座標はアリーナのユニット系(ArenaRootの子として足すこと)。ただし文字だけは
## ユニットで測ると読めない大きさになる(1ユニット≒コマの直径)ので、
## unit_scale に ArenaRoot のスケールを渡して自前で打ち消し、
## font_size をそのままpxとして扱う。

## 消えるまでの秒数。
@export_range(0.05, 3.0, 0.05) var duration: float = 0.7

## 満タンの不透明度を保つ割合。ここを過ぎてから線形に薄くなる。
@export_range(0.0, 1.0, 0.05) var hold_share: float = 0.35

## 消えるまでに上へ逃げる距離(ユニット)。
@export_range(0.0, 4.0, 0.1) var rise: float = 0.9

## 文字の大きさ(px)。ArenaRootのスケールを打ち消したうえで使うので、
## 土俵の広さや縦画面の拡大に関わらず同じ大きさで出る。
@export_range(4.0, 96.0, 1.0) var font_size: float = 22.0

## 縁取りの太さ(px)。暗い床の上でも明るいコマの上でも読めるように必ず付ける。
@export_range(0.0, 12.0, 1.0) var outline_size: float = 5.0

@export var text: String = ""
@export var color: Color = Palette.TEXT_PRIMARY

## ArenaRootのスケール(px/ユニット)。1で等倍(=親が素のNode2D)。
var unit_scale: Vector2 = Vector2.ONE

var _elapsed: float = 0.0


func _ready() -> void:
	# 親のユニット系を打ち消して、この中だけpxで描けるようにする。
	# 0除算とゼロスケールを避ける(縦画面の計算が潰れた時の保険)。
	scale = Vector2(
		1.0 / unit_scale.x if absf(unit_scale.x) > 0.0001 else 1.0,
		1.0 / unit_scale.y if absf(unit_scale.y) > 0.0001 else 1.0
	)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if text.is_empty():
		return
	var font := ThemeDB.fallback_font
	var fs := maxi(1, int(round(font_size)))
	var a := WallDamageReadout.alpha_at(_elapsed, duration, hold_share)
	# 上への逃げはユニットで決まっているので、px系のこの中では打ち消し分を掛け戻す。
	var up := WallDamageReadout.rise_at(_elapsed, duration, rise) * unit_scale.y
	var ssize := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	# draw_stringはベースライン基準。当たった点を文字の中央に持ってくる。
	var pos := Vector2(
		-ssize.x * 0.5,
		(font.get_ascent(fs) - font.get_descent(fs)) * 0.5 - up
	)
	if outline_size > 0.0:
		draw_string_outline(
			font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			maxi(1, int(round(outline_size))),
			Color(Palette.TEXT_OUTLINE, a)
		)
	draw_string(
		font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(color, a)
	)
