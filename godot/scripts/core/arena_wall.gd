class_name ArenaWall
extends RefCounted

## アリーナの壁1枚。物理的な当たり判定ノードは持たず、位置と法線だけのデータ。
## 描画はArenaがLine2Dで別途行う。
##
## プロトタイプはこれをSVGポリゴンとして描いていたが、内側の頂点が中心方向へ
## 1ユニットしかオフセットされていない一方で両端はアリーナ全幅に広がる座標に
## なっており、4枚が重なって中央が塗り潰されて見えるバグがあった。
## ここでは矩形の枠線として素直に描くので、その計算は引き継がない。

## 壁上の任意の1点。
var point: Vector2

## アリーナ内側を向いた単位ベクトル。
var normal: Vector2


func _init(wall_point: Vector2, wall_normal: Vector2) -> void:
	point = wall_point
	normal = wall_normal.normalized()


## 矩形アリーナの4辺を内向き法線付きで返す。
static func from_rect(bounds: Rect2) -> Array[ArenaWall]:
	var center := bounds.get_center()
	return [
		ArenaWall.new(Vector2(bounds.position.x, center.y), Vector2.RIGHT),
		ArenaWall.new(Vector2(bounds.end.x, center.y), Vector2.LEFT),
		ArenaWall.new(Vector2(center.x, bounds.position.y), Vector2.DOWN),
		ArenaWall.new(Vector2(center.x, bounds.end.y), Vector2.UP),
	]
