class_name EnemyData
extends Resource

## 敵1体。archive/flask-prototype/enemy.py のEnemyに相当する。
##
## 数値はプロトタイプを出発点にしているだけで、手触りで調整する前提。

## 1〜5。大きいほど強い。5はボス。
@export_range(1, 5, 1) var level: int = 1

## 表示名。プロトタイプはenemy1-1のような開発用の名前だった。
@export var display_name: String = ""

## 発射の速さ(ユニット/秒)。出現位置と向きは毎回ランダムに決まるので、
## 敵ごとに固定なのは強さだけ。
##
## プロトタイプのENEMY_LISTには位置と速度ベクトルが入っていたが、app.pyは
## initial_conditionsの固定値(全敵が中央から(3,4))を使っており、一度も
## 読まれていない死んだデータだった。ただし値はレベルが上がるほど大きく
## (Lv1で2.2、Lv5で14.1)、強い敵ほど速く発射させる意図は読み取れるので、
## その大きさだけを引き継いでいる。
@export_range(0.5, 30.0, 0.1) var launch_speed: float = 2.0

@export var stats: SpinnerStats


static func make(
	level_: int, name_: String, launch_speed_: float, stats_: SpinnerStats
) -> EnemyData:
	var data := EnemyData.new()
	data.level = level_
	data.display_name = name_
	data.launch_speed = launch_speed_
	data.stats = stats_
	return data
