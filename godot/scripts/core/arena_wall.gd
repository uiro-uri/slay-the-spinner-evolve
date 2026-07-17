class_name ArenaWall
extends RefCounted

## アリーナの壁1枚。物理的な当たり判定ノードは持たず、位置と法線だけのデータ。
## 描画はArenaがLine2Dで別途行う。
##
## プロトタイプはこれをSVGポリゴンとして描いていた。1枚が「辺の全長を底辺、
## 中心方向へ1ユニット入った点を頂点とする平たい三角形」で、4枚で縁を成す。
## ここでは矩形の枠線として描いており、意味は同じだが縁の太さが一定になる。
##
## 補足: 以前ここに「4枚が重なって中央が塗り潰されるバグがあった」と書いて
## いたが誤りだった。頂点を計算すると各三角形は縁から1ユニット(50px)しか
## 入っておらず、500pxのアリーナの中央には届かない。プレイ中に見えた中央を
## 覆うマゼンタの塊は、衝突エフェクト(1pxの円をscale(1000)=直径1000pxまで
## 広げていた)の方だった。

## アリーナの外周の形。矩形のほか、正多角形で非矩形の土俵を作れる。
## ROUNDは辺の多い正多角形で円を近似する（ArenaWallは点＋法線の半平面なので
## 曲面そのものは表せない。辺を増やせば円に見え、壁の当たり判定は無改造で通る）。
enum WallShape { RECT, OCTAGON, ROUND }

const _OCTAGON_SIDES := 8
const _ROUND_SIDES := 32

## 壁上の任意の1点。
var point: Vector2

## アリーナ内側を向いた単位ベクトル。
var normal: Vector2


func _init(wall_point: Vector2, wall_normal: Vector2) -> void:
	point = wall_point
	normal = wall_normal.normalized()


## コマ全体がアリーナに収まる位置へ寄せる。
##
## 発射地点をマウス位置のまま使っていたので、アリーナの外どこからでも
## 発射できた。外から内向きに撃つと、壁の反射判定(内向きに進んでいる間は
## 当たらない)をすり抜けて助走をつけられてしまう。見た目にもコマが枠の外に浮く。
static func clamp_inside(bounds: Rect2, pos: Vector2, radius: float) -> Vector2:
	var lo := bounds.position + Vector2.ONE * radius
	var hi := bounds.end - Vector2.ONE * radius
	# コマがアリーナより大きいと範囲が反転する。その時は中心に置く。
	if lo.x > hi.x or lo.y > hi.y:
		return bounds.get_center()
	return Vector2(clampf(pos.x, lo.x, hi.x), clampf(pos.y, lo.y, hi.y))


## 矩形アリーナの4辺を内向き法線付きで返す。
static func from_rect(bounds: Rect2) -> Array[ArenaWall]:
	var center := bounds.get_center()
	return [
		ArenaWall.new(Vector2(bounds.position.x, center.y), Vector2.RIGHT),
		ArenaWall.new(Vector2(bounds.end.x, center.y), Vector2.LEFT),
		ArenaWall.new(Vector2(center.x, bounds.position.y), Vector2.DOWN),
		ArenaWall.new(Vector2(center.x, bounds.end.y), Vector2.UP),
	]


## 正多角形の各辺を「辺の中点 + 内向き法線」の半平面として返す。
## 頂点は角度 i*TAU/sides、辺の中点はその半区画ずれた (i+0.5)*TAU/sides の向き。
## 中心から辺までの距離(apothem) = circumradius * cos(PI/sides)。
static func from_polygon(center: Vector2, circumradius: float, sides: int) -> Array[ArenaWall]:
	var walls: Array[ArenaWall] = []
	var apothem := circumradius * cos(PI / float(sides))
	for i in sides:
		var outward := Vector2.RIGHT.rotated((float(i) + 0.5) / float(sides) * TAU)
		walls.append(ArenaWall.new(center + outward * apothem, -outward))
	return walls


## wall_shape に応じて壁を組む。RECTは既存のfrom_rect、それ以外は正多角形。
static func build(shape: WallShape, bounds: Rect2) -> Array[ArenaWall]:
	match shape:
		WallShape.OCTAGON:
			return from_polygon(bounds.get_center(), _circumradius(bounds), _OCTAGON_SIDES)
		WallShape.ROUND:
			return from_polygon(bounds.get_center(), _circumradius(bounds), _ROUND_SIDES)
		_:
			return from_rect(bounds)


## 描画用の外周頂点列。閉じた輪郭や床の塗りに使う。RECTはboundsの四隅。
static func outline_points(shape: WallShape, bounds: Rect2) -> PackedVector2Array:
	if shape == WallShape.RECT:
		return PackedVector2Array([
			bounds.position,
			Vector2(bounds.end.x, bounds.position.y),
			bounds.end,
			Vector2(bounds.position.x, bounds.end.y),
		])
	var center := bounds.get_center()
	var r := _circumradius(bounds)
	var sides := _sides_for(shape)
	var pts := PackedVector2Array()
	for i in sides:
		pts.append(center + Vector2.RIGHT.rotated(float(i) / float(sides) * TAU) * r)
	return pts


## 壁の内接円半径。非矩形の発射クランプと敵の出現境界に使う。
static func inradius_for(shape: WallShape, bounds: Rect2) -> float:
	match shape:
		WallShape.OCTAGON:
			return _circumradius(bounds) * cos(PI / float(_OCTAGON_SIDES))
		WallShape.ROUND:
			return _circumradius(bounds) * cos(PI / float(_ROUND_SIDES))
		_:
			return _circumradius(bounds)


## 円/多角形アリーナ用の保守的クランプ。内接円までしか許さない。
## 八角形の角は使わないが、どの壁の内側にも必ず収まり最も簡単。
static func clamp_inside_circle(
	center: Vector2, inradius: float, pos: Vector2, radius: float
) -> Vector2:
	var max_dist := maxf(inradius - radius, 0.0)
	var delta := pos - center
	if delta.length() <= max_dist:
		return pos
	return center + delta.normalized() * max_dist


## 点が壁の内側(凸領域内)にあるか。どれか1枚でも法線の外側ならfalse。
## リングアウト判定に使う（壁で弾かず、外側へ出たら場外とみなす）。
static func point_inside(walls: Array[ArenaWall], pos: Vector2) -> bool:
	for wall in walls:
		if wall.normal.dot(pos - wall.point) < 0.0:
			return false
	return true


## 矩形の短辺の半分＝多角形の外接円半径。土俵が縦横で違っても内側に収まる。
static func _circumradius(bounds: Rect2) -> float:
	return minf(bounds.size.x, bounds.size.y) * 0.5


static func _sides_for(shape: WallShape) -> int:
	match shape:
		WallShape.OCTAGON:
			return _OCTAGON_SIDES
		WallShape.ROUND:
			return _ROUND_SIDES
		_:
			return 4
