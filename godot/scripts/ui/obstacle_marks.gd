class_name ObstacleMarks
extends RefCounted

## マップのノードの中に描く「この部屋には柱が立っている」の印。
## Node にもシーンにも乱数にも依存しない純粋関数だけ(cf. scripts/ui/threat_meter.gd)。
##
## 動機はコールドプレイの一次証拠と、その裏を取ったボット統計。
## マップのノードは既に**土俵の外周形状**(矩形/八角/円)で描かれていて、円い土俵か
## 角のある土俵かは選ぶ前に分かる。ところが**土俵の中に立っている柱だけは、
## 入場して初めて見える**。そしてこの柱が、隠れている中で一番大きな難度の差になる:
##
##   同じ敵・同じ発射方針での勝率(各500戦, intercept)
##     Lv1: 柱なし 100% → FIELD_PILLARS **94.4%**
##     Lv2: 柱なし 94〜97% → FIELD_PILLARS **73.2%**
##     Lv3: 柱なし 0〜2% → FIELD_PILLARS **8.8%**(柱が敵も削るので逆に上がる)
##   自機のrps喪失のうち壁・柱の取り分  Lv2: 9〜28% → **55%**
##
## 傾斜の強さ(3.0〜8.0)も勝率を2〜3pt動かすが、柱は20pt以上動かす。
## コールドプレイでも、負けた2戦(段6の初黒星と段1の被弾4回)はどちらも
## FIELD_PILLARS で、1〜1.5秒で快勝した段3・段4は柱なしだった。
## **選ぶ時点で見えないと、勝率20ptぶんの情報が「入ってからのお楽しみ」になる。**
##
## 印は土俵の実座標をノードへそのまま縮めたもので、位置も大きさも作り事ではない。
## 「柱がある」だけでなく「どこに立っているか」まで同じ形で出るので、入場した先の
## 土俵と印が一致する(色も対戦画面の柱と同じ Palette.NEON_VIOLET を使う)。
##
## 脅威メーターと違って**すべての戦闘ノードに出す**。取り分は「今のビルドとの比」
## なので遠いノードでは嘘になるが、柱は土俵の静的な事実で、育っても変わらない
## ——ノードの外周形状を全ノードに描いているのと同じ理由。


## 土俵の柱を、ノード内に描く印(x, y, 半径)の列にして返す。
##
## center/node_radius は描画中のノードのもの(ホバーで膨らんだ半径や、縦画面の
## 拡大率が乗った半径をそのまま渡してよい。印も一緒に動く)。
##
## 縮尺は土俵の**長い方の半辺**を node_radius に合わせた一様倍率。x/y を別々に
## 合わせると正方形でない土俵で柱が楕円になり、円である柱の見た目が嘘になる。
## 今の土俵はすべて 10×10 の正方形なので、どちらでも同じ値になる。
static func marks(center: Vector2, node_radius: float, field: FieldData) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if field == null or field.obstacles.is_empty() or node_radius <= 0.0:
		return out
	var half := field.arena_bounds.size * 0.5
	var span := maxf(half.x, half.y)
	if span <= 0.0:
		return out
	var scale := node_radius / span
	var origin := field.center()
	for o in field.obstacles:
		var offset := (Vector2(o.x, o.y) - origin) * scale
		out.append(Vector3(center.x + offset.x, center.y + offset.y, o.z * scale))
	return out
