class_name Disc
extends Node2D

## コマ1体。座標も半径もアリーナのユニット系で、表示上の拡大は親のArenaRootの
## scaleが担う（1ユニット = ARENA_PIXELS_PER_UNIT ピクセル）。
##
## 物理の計算そのものはSpinnerPhysicsの純粋関数が持ち、Battleが駆動する。
## このノードは状態の保持と描画だけを受け持つ。

## 破線リングの本数。回転が目で追える程度に。
const DASH_COUNT := 8

## リングの太さ（ユニット）。
const RING_WIDTH := 0.16

@export var stats: SpinnerStats
@export var body_color: Color = Color("3498db")

var velocity: Vector2 = Vector2.ZERO

## 現在の回転数。尽きた方が負け。stats.rpsは初期値としてだけ使う。
var rps: float = 0.0

## 決着後に色を落とすためのフラグ。
var defeated: bool = false


func _ready() -> void:
	if stats == null:
		stats = SpinnerStats.new()
	reset_spin()


## statsの初期値から回転をやり直す。
func reset_spin() -> void:
	rps = stats.rps
	defeated = false
	queue_redraw()


func _process(delta: float) -> void:
	# 実際のRPSで見た目も回す。速いほど目に見えて速く回る。
	rotation += rps * TAU * delta
	queue_redraw()


func _draw() -> void:
	var radius := stats.radius
	var fill := body_color
	if defeated:
		fill = fill.darkened(0.7)
	draw_circle(Vector2.ZERO, radius, fill)

	# 破線のリング。無地の円だと回転しているのか分からないため。
	var ring_color := Color(1, 1, 1, 0.7)
	if defeated:
		ring_color.a = 0.25
	var arc_span := TAU / (DASH_COUNT * 2)
	for i in DASH_COUNT:
		var start := arc_span * 2 * i
		draw_arc(Vector2.ZERO, radius, start, start + arc_span, 6, ring_color, RING_WIDTH)
