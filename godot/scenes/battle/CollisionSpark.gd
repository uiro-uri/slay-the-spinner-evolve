class_name CollisionSpark
extends Node2D

## コマ同士がぶつかった接触点から広がる衝撃波。
## プロトタイプ(templates/simulation.html)の .spark と @keyframes spark の移植。
##
## プロトタイプはサーバーが全ステップを先に計算して衝突時刻の一覧を返し、
## それをCSSの animation-delay で再生していた。こちらはリアルタイムなので
## ぶつかった瞬間にその場で生やす。移植したのは見た目であって仕組みではない。
##
## 座標はアリーナのユニット系。ArenaRootの子として足すこと。

## 広がりきって消えるまでの秒数。プロトタイプは1秒だった。
@export_range(0.05, 3.0, 0.05) var duration: float = 0.45

## 最終的な半径(ユニット)。アリーナは10x10、コマの半径は0.5。
##
## プロトタイプは1pxの円を scale(1000) ＝直径1000pxまで広げていた。アリーナが
## 500pxなので画面を覆い尽くす大きさで、肝心のコマが見えなくなる。当たった
## 場所と勢いが分かれば足りるので、コマの数倍に留めてある。派手にしたければ
## ここを上げる。
@export_range(0.2, 20.0, 0.1) var max_radius: float = 2.4

## 出た瞬間の色。プロトタイプの rgba(255, 0, 255, 0.8)。
@export var start_color: Color = Color(1.0, 0.0, 1.0, 0.8)

## 消える時の色。プロトタイプの rgba(255, 255, 125, 0.0)。
@export var end_color: Color = Color(1.0, 1.0, 0.49, 0.0)

var _elapsed: float = 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	# durationが0でも0除算しない。
	var t := 1.0 if duration <= 0.0 else clampf(_elapsed / duration, 0.0, 1.0)
	draw_circle(Vector2.ZERO, max_radius * t, start_color.lerp(end_color, t))
