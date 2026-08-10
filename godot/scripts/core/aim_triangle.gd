class_name AimTriangle
extends RefCounted

## 「ここから、この向きへ、この強さで飛ぶ」を示す塗り潰しの三角形。
## プロトタイプのvelocityArrowと同じ意匠で、頂点が発射地点、底辺が反対側へ広がる。
##
## プレイヤーの狙い(緑)と敵の予告(赤)で同じ形を使う。色が違うだけで読み方が
## 同じなら、説明しなくても伝わるため。
##
## **長さの規則も同じでなければ意味が同じにならない**。形だけ揃えても、片方が
## 「引き量」で片方が「sqrt(速度)」なら、並べた三角形の長短が速度の大小と一致しない。
## length_for_speed() が両者の唯一の規則で、自機も敵もここを通る。

## 底辺の半幅は、頂点から底辺までの距離のこの割合。プロトタイプは1/4だった。
const BASE_RATIO := 0.25


## 初速→三角形の長さ。自機の狙いと敵の予告で共通の規則。
##
## full_speed_length は LaunchSpeed.MAX のときの長さ(ユニット)で、自機の
## LaunchController.max_pull がその実体。長さが語るのは**初速**なので、自機に下限
## (LaunchSpeed.PLAYER_MIN)が入った 2026-08-10 以降、底辺がカーソル位置に来るのは
## full pull のときだけになった。僅かな引きでも実際に速度 PLAYER_MIN は出るのだから、
## 三角形もその長さでなければ「見えているとおりに飛ぶ」が崩れる。
##
## 敵の予告はかつて sqrt(速度)×length_scale だった。速度レンジが自機[0,20]・
## 敵[2.2,14.1]とバラバラだった頃、「Lv1が見える長さに合わせるとボスが突き抜ける」
## を平方根の圧縮で凌いだ名残で、LaunchSpeed が両者を[0,12]へ一本化した時点で
## 前提が消えている。残っていた圧縮のせいで、同じ速度でも敵の三角形の方が長く
## 見えていた(速度3で敵2.08 vs 自機1.00＝2倍、速度6で2.94 vs 2.00)。つまり
## 「相手より強く撃てているか」を並べて読めなかった。
static func length_for_speed(speed: float, full_speed_length: float) -> float:
	if full_speed_length <= 0.0 or not is_finite(speed) or LaunchSpeed.MAX <= 0.0:
		return 0.0
	return clampf(speed / LaunchSpeed.MAX, 0.0, 1.0) * full_speed_length


## originから飛んでいく向きにvelocity_dirを取り、長さlengthの三角形を作る。
static func points(origin: Vector2, direction: Vector2, length: float) -> PackedVector2Array:
	if direction.length_squared() < 1e-12 or length <= 0.0:
		return PackedVector2Array()
	# 底辺は飛んでいく向きの反対側（引いた先に相当する位置）に置く。
	var back := origin - direction.normalized() * length
	var half_base := (back - origin).orthogonal() * BASE_RATIO
	return PackedVector2Array([origin, back - half_base, back + half_base])
