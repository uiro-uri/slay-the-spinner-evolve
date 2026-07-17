class_name Arena
extends Node2D

## 戦うすり鉢。既定は10x10ユニットの矩形で中心は(5,5)だが、setup()で土俵
## (フィールド)に合わせて壁の位置・形状・障害物を差し替えられる。
##
## 壁は物理ボディではなくデータ(ArenaWall)として持ち、当たり判定は
## SpinnerPhysics/BattleResolverが行う。ここは見た目だけを描く。

## Battle.tscn単体起動時とテストの既定値。フィールドが無いときのフォールバック。
const BOUNDS := Rect2(0.0, 0.0, 10.0, 10.0)

const WALL_WIDTH := 0.2
const WALL_COLOR := Palette.NEON_MAGENTA
const FLOOR_COLOR := Palette.FLOOR
const CENTER_MARK_COLOR := Palette.FLOOR_MARK
const OBSTACLE_COLOR := Palette.NEON_VIOLET
const OBSTACLE_HIGHLIGHT := Palette.NEON_VIOLET_HI

var _bounds: Rect2 = BOUNDS
var _wall_shape: ArenaWall.WallShape = ArenaWall.WallShape.RECT
var _obstacles: Array[Vector3] = []

var walls: Array[ArenaWall] = ArenaWall.from_rect(BOUNDS)


## 土俵をフィールドに合わせて設定する。nullなら既定(矩形10x10)のまま。
func setup(field: FieldData) -> void:
	if field != null:
		_bounds = field.arena_bounds
		_wall_shape = field.wall_shape
		_obstacles = field.obstacles
	else:
		_bounds = BOUNDS
		_wall_shape = ArenaWall.WallShape.RECT
		_obstacles = []
	walls = ArenaWall.build(_wall_shape, _bounds)
	queue_redraw()


func center() -> Vector2:
	return _bounds.get_center()


func _draw() -> void:
	# 床。矩形はそのまま、非矩形は多角形で塗る。
	if _wall_shape == ArenaWall.WallShape.RECT:
		draw_rect(_bounds, FLOOR_COLOR, true)
	else:
		draw_colored_polygon(ArenaWall.outline_points(_wall_shape, _bounds), FLOOR_COLOR)

	# 中央が低いことを示す同心円。すり鉢の底が見た目で分かるように。
	# 内接円半径に合わせるので、土俵の大きさ・形が変わっても縁からはみ出ない。
	var max_r := ArenaWall.inradius_for(_wall_shape, _bounds)
	for i in range(1, 5):
		var r := max_r * (float(i) / 4.0)
		draw_arc(center(), r, 0, TAU, 64, CENTER_MARK_COLOR, 0.03)

	# 壁の輪郭。矩形は枠線、非矩形は閉じた多角形。
	if _wall_shape == ArenaWall.WallShape.RECT:
		draw_rect(_bounds, WALL_COLOR, false, WALL_WIDTH)
	else:
		var pts := ArenaWall.outline_points(_wall_shape, _bounds)
		var loop := pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, WALL_COLOR, WALL_WIDTH)

	# 障害物は塗り円＋内側ハイライトで、盛り上がった柱に見せる。
	for o in _obstacles:
		var obstacle_center := Vector2(o.x, o.y)
		draw_circle(obstacle_center, o.z, OBSTACLE_COLOR)
		draw_circle(obstacle_center, o.z * 0.55, OBSTACLE_HIGHLIGHT)
