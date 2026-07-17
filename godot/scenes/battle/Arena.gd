class_name Arena
extends Node2D

## 戦うすり鉢。10x10ユニットの矩形で、中心は(5,5)。
##
## 壁は物理ボディではなくデータ(ArenaWall)として持ち、当たり判定は
## SpinnerPhysicsが行う。ここは見た目だけを描く。

const BOUNDS := Rect2(0.0, 0.0, 10.0, 10.0)

const WALL_WIDTH := 0.2
const WALL_COLOR := Color("d98cd9")
const FLOOR_COLOR := Color("f0f0f0")
const CENTER_MARK_COLOR := Color(0, 0, 0, 0.08)

var walls: Array[ArenaWall] = ArenaWall.from_rect(BOUNDS)


func center() -> Vector2:
	return BOUNDS.get_center()


func _draw() -> void:
	draw_rect(BOUNDS, FLOOR_COLOR, true)

	# 中央が低いことを示す同心円。すり鉢の底が見た目で分かるように。
	for i in range(1, 5):
		var r := BOUNDS.size.x * 0.5 * (float(i) / 4.0)
		draw_arc(center(), r, 0, TAU, 64, CENTER_MARK_COLOR, 0.03)

	# 壁は矩形の枠線として描く。プロトタイプは辺ごとに平たい三角形を置いて
	# 縁を作っていた（詳細はarena_wall.gd）。枠線なら太さが一定になる。
	draw_rect(BOUNDS, WALL_COLOR, false, WALL_WIDTH)
