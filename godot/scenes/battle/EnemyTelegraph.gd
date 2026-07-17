class_name EnemyTelegraph
extends Node2D

## 敵がどこへ飛ぶかの予告。
##
## 出現位置と向きが毎回ランダムなので、そのままでは対処のしようがない。
## プレイヤーの狙い(緑の三角形)と同じ意匠で、色だけ赤にして見せる。
## 読み方が同じなら説明しなくても伝わる。
##
## ただし確定値をそのまま見せると読み切れてしまうので、確定値の周りで
## 揺らして見せる(TelegraphWobble)。**揺れるのは見た目だけで、実際の発射は
## show_plan()で渡された確定値のまま。** 揺らぎは確定値を中心に振れるので、
## 長く見ていれば平均は真の値に寄る。「読めなくする」のではなく
## 「一瞬では読み切れなくする」もの。
##
## 発射する側(Battle)は必ず確定値を使うこと。表示値で撃つと予告が本当に
## 嘘になる。
##
## ArenaRootの子として置くこと（座標はアリーナのユニット系）。

## プレイヤーの狙い(lime)と対になる赤。
@export var color: Color = Color(Palette.ENEMY, 0.85)

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

@export_group("揺らぎ")

## 位置の揺れ幅(ユニット)。0で揺らさない。
@export_range(0.0, 1.0, 0.01) var wobble_position: float = TelegraphWobble.DEFAULT_POSITION_AMPLITUDE

## 向きの揺れ幅(度)。0で揺らさない。
@export_range(0.0, 45.0, 0.5) var wobble_angle_deg: float = TelegraphWobble.DEFAULT_ANGLE_AMPLITUDE

## 長さの揺れ幅(割合)。0.15なら±15%。0で揺らさない。
@export_range(0.0, 0.5, 0.01) var wobble_length: float = TelegraphWobble.DEFAULT_LENGTH_AMPLITUDE

## 揺れの速さ。
@export_range(0.1, 10.0, 0.1) var wobble_speed: float = TelegraphWobble.DEFAULT_SPEED

## 発射で撃たれる確定値。揺らさない。
var _origin: Vector2 = Vector2.ZERO
var _velocity: Vector2 = Vector2.ZERO

var _showing: bool = false
var _pulse: float = 0.0

## 揺らぎ用の経過時間。
var _wobble_time: float = 0.0


func show_plan(origin: Vector2, velocity: Vector2) -> void:
	_origin = origin
	_velocity = velocity
	_showing = true
	_pulse = 0.0
	_wobble_time = 0.0
	queue_redraw()


func hide_plan() -> void:
	_showing = false
	queue_redraw()


func _process(delta: float) -> void:
	if not _showing:
		return
	_pulse += delta * pulse_speed
	_wobble_time += delta
	queue_redraw()


## 今この瞬間に見せている位置。確定値の周りを漂う。
## コマもここへ置くので、三角形の頂点とコマがずれない。
func display_position() -> Vector2:
	return TelegraphWobble.position_at(_origin, _wobble_time, wobble_position, wobble_speed)


## 今この瞬間に見せている速度。向きと大きさが揺れる。
func display_velocity() -> Vector2:
	return TelegraphWobble.velocity_at(
		_velocity, _wobble_time, wobble_angle_deg, wobble_length, wobble_speed
	)


## 長さは表示用の速度から決める。揺れ幅の分だけ伸び縮みする。
func telegraph_length() -> float:
	return sqrt(display_velocity().length()) * length_scale


func _draw() -> void:
	if not _showing:
		return
	# 確定値ではなく表示値で描く。ここが揺れる。
	var points := AimTriangle.points(
		display_position(), display_velocity(), telegraph_length()
	)
	if points.is_empty():
		return
	var shown := color
	shown.a *= 0.65 + 0.35 * (0.5 + 0.5 * sin(_pulse))
	draw_colored_polygon(points, shown)
