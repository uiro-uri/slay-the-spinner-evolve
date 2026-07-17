class_name EnemyTelegraph
extends Node2D

## 敵がどこへ飛ぶかの予告。
##
## 出現位置と向きが毎回ランダムなので、そのままでは対処のしようがない。
## プレイヤーの狙い(緑の三角形)と同じ意匠で、色だけ赤にして見せる。
## 読み方が同じなら説明しなくても伝わる。
##
## ArenaRootの子として置くこと（座標はアリーナのユニット系）。

## プレイヤーの狙い(lime)と対になる赤。
@export var color: Color = Color(1, 0.2, 0.2, 0.85)

## 三角形の長さ。速い敵ほど長く出るので、強さが見た目で分かる。
##
## 速度に比例させると破綻する。敵の速度はLv1で2.2、ボスで14.1と6倍以上
## 開くので、Lv1が見える長さに合わせるとボスがアリーナを突き抜け、ボスに
## 合わせるとLv1はコマ(半径0.5)の下に隠れて何も見えない。平方根で圧縮すれば
## 1.8〜4.5に収まり、どの敵でもコマの外に出た上で速い方が長いままになる。
@export_range(0.2, 4.0, 0.1) var length_scale: float = 1.2

## 明滅の速さ。止まっている三角形より、脈打っている方が
## 「これから飛ぶ」ことが伝わる。
@export_range(0.0, 10.0, 0.5) var pulse_speed: float = 4.0

var _origin: Vector2 = Vector2.ZERO
var _velocity: Vector2 = Vector2.ZERO
var _showing: bool = false
var _pulse: float = 0.0


func show_plan(origin: Vector2, velocity: Vector2) -> void:
	_origin = origin
	_velocity = velocity
	_showing = true
	_pulse = 0.0
	queue_redraw()


func hide_plan() -> void:
	_showing = false
	queue_redraw()


func _process(delta: float) -> void:
	if not _showing:
		return
	_pulse += delta * pulse_speed
	queue_redraw()


func telegraph_length() -> float:
	return sqrt(_velocity.length()) * length_scale


func _draw() -> void:
	if not _showing:
		return
	var points := AimTriangle.points(_origin, _velocity, telegraph_length())
	if points.is_empty():
		return
	var shown := color
	shown.a *= 0.65 + 0.35 * (0.5 + 0.5 * sin(_pulse))
	draw_colored_polygon(points, shown)
