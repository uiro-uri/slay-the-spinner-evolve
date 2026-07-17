class_name LaunchController
extends Node2D

## 引っ張って離すとコマが飛ぶ（スリングショット式）。
##
## プロトタイプはmousedown/mousemove/mouseupで初速を作り、フォームを
## サーバーへ送って全ステップを計算させていた。ここでは押している間に
## 狙いを描き、離した瞬間にその場で発射する。
##
## 座標はアリーナのユニット系。ArenaRootの子として置くこと。

## プロトタイプの velocityArrow と同じ lime 系。純緑は暗い床でも十分映えるが、
## Palette.AIM に寄せて予告(赤)と対の彩度に揃える。
const ARROW_COLOR := Palette.AIM

## 引いた距離(ユニット)を初速(ユニット/秒)に変換する倍率。
@export_range(0.1, 20.0, 0.1) var pull_to_speed: float = 5.0

## これ以上引いても速くならない上限(ユニット)。
@export_range(0.5, 10.0, 0.1) var max_pull: float = 4.0

## 発射位置と速度が決まった。
signal launched(pos: Vector2, velocity: Vector2)

## 発射地点(三角形の頂点)が動いた。コマをそこへ置くために使う。
## 押していない間もマウスを追うので、どこから飛ぶのかが常に見える。
signal aim_moved(origin: Vector2)

var _dragging: bool = false
var _origin: Vector2 = Vector2.ZERO
var _current: Vector2 = Vector2.ZERO
var _enabled: bool = true


func set_enabled(value: bool) -> void:
	_enabled = value
	if not value:
		if _dragging:
			# 引いている途中で無効化(発射で戦闘へ入るなど)されたらチャージ音を止める。
			AudioManager.stop_charge()
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
			aim_moved.emit(_origin)
			# 引き始め。引き量0から鳴らし始め、動かすほど高く・大きくする。
			AudioManager.start_charge()
			queue_redraw()
		elif _dragging:
			_dragging = false
			_release()
		get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		if _dragging:
			_current = get_local_mouse_position()
			AudioManager.update_charge(_effective_pull().length() / max_pull)
			queue_redraw()
		else:
			# 押す前もコマがマウスを追うので、どこから飛ぶのかが常に見える。
			_origin = get_local_mouse_position()
			aim_moved.emit(_origin)


## 引いた向きと逆に飛ぶ（パチンコと同じ）。max_pullで頭打ちにする。
func _effective_pull() -> Vector2:
	var pull := _origin - _current
	if pull.length() > max_pull:
		return pull.normalized() * max_pull
	return pull


func _release() -> void:
	# 離した瞬間にチャージ音を止める。発射音は launched の購読側(Battle)で鳴らす。
	AudioManager.stop_charge()
	queue_redraw()
	launched.emit(_origin, _effective_pull() * pull_to_speed)


## 塗り潰しの三角形で狙いを示す。頂点が発射地点で、そのまま飛んでいく向きを指す。
## 敵の予告(EnemyTelegraph)と同じ意匠を使う。
func _draw() -> void:
	if not _dragging:
		return

	# 上限まで引いたらそれ以上は伸びない。見た目と実際の初速をずらさないため、
	# 描画も頭打ちにした位置で行う（プロトタイプに上限はなかった）。
	var pull := _effective_pull()
	var points := AimTriangle.points(_origin, pull, pull.length())
	if points.is_empty():
		return
	draw_colored_polygon(points, ARROW_COLOR)
