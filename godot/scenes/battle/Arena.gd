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

## 床に描く等高線の半径。土俵ごとに一度だけ積んで持っておく(_drawは毎再描画で
## 走るが、傾斜はsetupの間ずっと動かない)。
var _contour_radii: PackedFloat32Array = PackedFloat32Array()

var walls: Array[ArenaWall] = ArenaWall.from_rect(BOUNDS)


## 土俵をフィールドに合わせて設定する。
##
## nullは FieldData の既定値(矩形10x10・すり鉢4.9・柱なし=Arena.BOUNDSと同じ土俵)で
## 代用する。既定値をここに書き写さないのは、傾斜まで描くようになった以上
## 「絵の既定」と「解決の既定」がずれると床が嘘をつくため。Battle は @export の
## 傾斜を載せた FieldData を渡してくるので、ここへ来る null はテスト等だけ。
func setup(field: FieldData) -> void:
	var resolved := field if field != null else FieldData.new()
	_bounds = resolved.arena_bounds
	_wall_shape = resolved.wall_shape
	_obstacles = resolved.obstacles
	walls = ArenaWall.build(_wall_shape, _bounds)
	_contour_radii = SlopeContour.radii(resolved)
	queue_redraw()


func center() -> Vector2:
	return _bounds.get_center()


func _draw() -> void:
	# 床。矩形はそのまま、非矩形は多角形で塗る。
	if _wall_shape == ArenaWall.WallShape.RECT:
		draw_rect(_bounds, FLOOR_COLOR, true)
	else:
		draw_colored_polygon(ArenaWall.outline_points(_wall_shape, _bounds), FLOOR_COLOR)

	# 中央が低いことを示す等高線。従来はどの土俵でも半径を4等分した同心円で、
	# 傾斜の急さも形も描いていなかった(すり鉢8.0と円錐3.0が同じ絵)。
	# SlopeContourは等しい高さで割るので、急な区間ほど輪が詰まる=線の混み方が
	# そのまま傾斜になり、本数はマップのノードのケバと一致する。
	for r in _contour_radii:
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
