class_name EnemyData
extends Resource

## 敵1体。archive/flask-prototype/enemy.py のEnemyに相当する。
##
## 数値はプロトタイプを出発点にしているだけで、手触りで調整する前提。

## 1〜5。大きいほど強い。5はボス。
@export_range(1, 5, 1) var level: int = 1

## 表示名。プロトタイプはenemy1-1のような開発用の名前だった。
@export var display_name: String = ""

@export var start_pos: Vector2 = Vector2(0, 0)
@export var start_vel: Vector2 = Vector2(0, 0)
@export var stats: SpinnerStats


static func make(
	level_: int, name_: String, pos: Vector2, vel: Vector2, stats_: SpinnerStats
) -> EnemyData:
	var data := EnemyData.new()
	data.level = level_
	data.display_name = name_
	data.start_pos = pos
	data.start_vel = vel
	data.stats = stats_
	return data
