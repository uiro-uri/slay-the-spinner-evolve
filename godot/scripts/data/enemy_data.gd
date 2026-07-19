class_name EnemyData
extends Resource

## 敵1体。archive/flask-prototype/enemy.py のEnemyに相当する。
##
## 数値はプロトタイプを出発点にしているだけで、手触りで調整する前提。

## 1〜5。大きいほど強い。5はボス。
@export_range(1, 5, 1) var level: int = 1

## 表示名。プロトタイプはenemy1-1のような開発用の名前だった。
@export var display_name: String = ""

## 出現位置・向き・発射速度はすべて出現ごとにランダムで、敵ごとに固定なのは強さだけ。
## 発射速度はかつて敵ごとの固定値だったが、自機と共通のレンジ(LaunchSpeed)から
## 出現ごとに抽選する方式に変えたため、EnemyDataは速度を持たなくなった。
@export var stats: SpinnerStats


static func make(
	level_: int, name_: String, stats_: SpinnerStats
) -> EnemyData:
	var data := EnemyData.new()
	data.level = level_
	data.display_name = name_
	data.stats = stats_
	return data
