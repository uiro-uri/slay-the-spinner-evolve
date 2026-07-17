class_name AimTriangle
extends RefCounted

## 「ここから、この向きへ、この強さで飛ぶ」を示す塗り潰しの三角形。
## プロトタイプのvelocityArrowと同じ意匠で、頂点が発射地点、底辺が反対側へ広がる。
##
## プレイヤーの狙い(緑)と敵の予告(赤)で同じ形を使う。色が違うだけで読み方が
## 同じなら、説明しなくても伝わるため。

## 底辺の半幅は、頂点から底辺までの距離のこの割合。プロトタイプは1/4だった。
const BASE_RATIO := 0.25


## originから飛んでいく向きにvelocity_dirを取り、長さlengthの三角形を作る。
static func points(origin: Vector2, direction: Vector2, length: float) -> PackedVector2Array:
	if direction.length_squared() < 1e-12 or length <= 0.0:
		return PackedVector2Array()
	# 底辺は飛んでいく向きの反対側（引いた先に相当する位置）に置く。
	var back := origin - direction.normalized() * length
	var half_base := (back - origin).orthogonal() * BASE_RATIO
	return PackedVector2Array([origin, back - half_base, back + half_base])
