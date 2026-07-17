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
