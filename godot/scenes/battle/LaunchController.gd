class_name LaunchController
extends Node2D

## 引っ張って離すとコマが飛ぶ（スリングショット式）。
##
## プロトタイプはmousedown/mousemove/mouseupで初速を作り、フォームを
## サーバーへ送って全ステップを計算させていた。ここでは押している間に
## 狙いを描き、離した瞬間にその場で発射する。
##
## 座標はアリーナのユニット系。ArenaRootの子として置くこと。

## プロトタイプの velocityArrow と同じ lime。
const ARROW_COLOR := Color(0, 1, 0)

## 引いた距離(ユニット)を初速(ユニット/秒)に変換する倍率。
@export_range(0.1, 20.0, 0.1) var pull_to_speed: float = 5.0

## これ以上引いても速くならない上限(ユニット)。
@export_range(0.5, 10.0, 0.1) var max_pull: float = 4.0

## 発射位置と速度が決まった。
signal launched(pos: Vector2, velocity: Vector2)

var _dragging: bool = false
var _origin: Vector2 = Vector2.ZERO
var _current: Vector2 = Vector2.ZERO
var _enabled: bool = true


func set_enabled(value: bool) -> void:
	_enabled = value
	if not value:
		_dragging = false
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_origin = get_local_mouse_position()
			_current = _origin
			queue_redraw()
		elif _dragging:
			_dragging = false
			_release()
		get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _dragging:
		_current = get_local_mouse_position()
		queue_redraw()


## 引いた向きと逆に飛ぶ（パチンコと同じ）。max_pullで頭打ちにする。
func _effective_pull() -> Vector2:
	var pull := _origin - _current
	if pull.length() > max_pull:
		return pull.normalized() * max_pull
	return pull


func _release() -> void:
	queue_redraw()
	launched.emit(_origin, _effective_pull() * pull_to_speed)


## プロトタイプと同じ塗り潰しの三角形で狙いを示す。
## 頂点が発射地点、底辺が引いた先に広がる。発射は引いた向きと逆なので、
## 頂点はそのまま飛んでいく向きを指す。底辺の半幅は引いた距離の1/4。
func _draw() -> void:
	if not _dragging:
		return

	# 上限まで引いたらそれ以上は伸びない。見た目と実際の初速をずらさないため、
	# 描画も頭打ちにした位置で行う（プロトタイプに上限はなかった）。
	var pull := _effective_pull()
	var pulled_to := _origin - pull
	var diff := pulled_to - _origin
	var half_base := diff.orthogonal() / 4.0

	draw_colored_polygon(
		[_origin, pulled_to - half_base, pulled_to + half_base], ARROW_COLOR
	)
