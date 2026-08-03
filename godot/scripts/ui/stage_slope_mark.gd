class_name StageSlopeMark
extends RefCounted

## マップのノードの中に描く「この土俵の傾斜はどれくらい急か」の印(ハッチング)。
## Node にもシーンにも乱数にも依存しない純粋関数だけ(cf. scripts/ui/obstacle_marks.gd)。
##
## 動機はコールドプレイの一次証拠。マップのノードは既に**外周形状**(矩形/八角/円)と
## **柱**を描いているが、**傾斜だけは入場するまで見えない**。ところが土俵6種のうち
## FIELD_CLASSIC / FIELD_BOWL / FIELD_PLATE は外周が矩形・柱なしで**画面上まったく
## 同じ絵**になる。違うのは傾斜だけで、その傾斜が壁の代償を2倍動かす:
##
##   同じ敵・同じ発射方針(各400戦, intercept)。自機のrps喪失に占める壁の取り分と壁回数
##     Lv3: FIELD_BOWL(すり鉢8.0) 17% / 1.47回
##          FIELD_CLASSIC(すり鉢4.9) 21% / 1.69回
##          FIELD_PLATE(円錐3.0)  **33% / 2.69回**
##     Lv4: 20% / 23% / **32%**
##
## 傾斜が緩いほど端で粘る＝壁に何度も当たる。コールドプレイでも敗北の主因は一貫して
## 壁で(段8で壁13.4/27.1、決戦で壁13.4/28.5)、「この部屋は壁に持っていかれるのか」は
## 部屋を選ぶ時点で一番知りたい量だった。それが**選んだあとにしか分からない**。
##
## 見えない差は選択そのものを殺す。ランダムな進路を3000ラン歩かせて、実際に直面した
## 2択以上の分岐 20684 件を数えると、**11.3% が「全ての選択肢が画面上まったく同じ絵」**
## (レベル・敵数・外周形状・柱がすべて一致)で、**55.8% のランが最低1回それを踏む**。
## 傾斜を描くと、同じ絵になるのは土俵そのものが同一の 5.5% まで落ちる
## ——差があるのに見えていなかったぶんが、ちょうど半分。
##
## 印はハッチング(ケバ)。地図で窪地や法面の傾斜を描く在来の記法そのままで、
## **急なほど本数が多く・長い**。数値も作り事ではなく、壁のところでコマが中心へ
## 引き戻される加速度(SpinnerPhysics.stage_slope_accel)をそのまま目盛りにしている。
##
## 脅威メーターと違って**すべての戦闘ノードに出す**。取り分は「今のビルドとの比」
## なので遠いノードでは嘘になるが、傾斜は土俵の静的な事実で、育っても変わらない
## ——柱の印・外周形状を全ノードに描いているのと同じ理由。

## 目盛りの満杯。壁での引き戻し加速度がこの値でケバが最大になる。
##
## 今の土俵の最大(FIELD_BOWL: すり鉢8.0 × 内接半径5.0 = 40.0)がちょうど満杯に
## なるよう決め打ってある。ロスターの最大値から動的に決めないのは、土俵を1つ足す
## たびに**既存の全ノードの絵が変わる**ため(目盛りが動くと、覚えた読み方が壊れる)。
## これより急な土俵を足したら満杯で頭打ちになって差が出なくなるので、そのときは
## この定数を上げる——テスト(test_stage_slope_mark)がロスターと突き合わせて落ちる。
const PULL_FULL := 40.0

## ケバの本数。緩い土俵で MIN、満杯で MAX。
const TICK_MIN_COUNT := 4
const TICK_MAX_COUNT := 10

## ケバの長さ(ノード半径に対する比)。緩い土俵で MIN、満杯で MAX。
## 上限0.34はレベルの数字を避ける値: 半径18のノードでケバの内端が半径11.9に来て、
## 数字(20px、対角でおよそ半径9)に触れない。ホバーで膨らんでも縦画面で拡大されても
## 比なので一緒に動く(ObstacleMarks と同じ流儀)。
const TICK_MIN_LENGTH := 0.12
const TICK_MAX_LENGTH := 0.34

## ケバを並べ始める向き(ラジアン)。真上から時計回り。
const TICK_START_ANGLE := -PI * 0.5


## 壁のところで中心へ引き戻される加速度の大きさ。傾斜の「急さ」の実体。
##
## すり鉢(DISH)は変位に比例するので内接半径が効き、円錐(CONE)はどこでも一定なので
## 強さそのものになる——その場合分けは書かず、SpinnerPhysics.stage_slope_accel に
## 壁上の点を渡して測る。傾斜の定義が2箇所にあると、マップと実戦で違う土俵を出す
## ことになる(ThreatMeter が硬さを StatReadout から取るのと同じ理由)。
static func rim_pull(field: FieldData) -> float:
	if field == null:
		return 0.0
	var center := field.center()
	var rim := center + Vector2.RIGHT * field.inradius()
	return SpinnerPhysics.stage_slope_accel(
		rim, center, field.stage_strength, field.stage_shape
	).length()


## 目盛り上の位置(0〜1)。PULL_FULL で満杯、それ以上は頭打ち。
static func share(field: FieldData) -> float:
	if PULL_FULL <= 0.0:
		return 0.0
	return clampf(rim_pull(field) / PULL_FULL, 0.0, 1.0)


## この土俵に出すケバの本数。
static func tick_count(field: FieldData) -> int:
	if field == null:
		return 0
	return int(round(lerpf(float(TICK_MIN_COUNT), float(TICK_MAX_COUNT), share(field))))


## ケバの線分列。2点で1本(外端→内端)、外端はノードの縁に載る。
##
## center/node_radius は描画中のノードのもの(ホバーで膨らんだ半径や、縦画面の
## 拡大率が乗った半径をそのまま渡してよい。印も一緒に動く)。
##
## 外周が矩形・八角のノードでもケバは**円周上**に並べる。ノード本体の形は
## 「土俵の外周形状」という別の情報を既に担っていて、そこにケバの配置まで
## 乗せると2つの量が1つの絵に混ざる。中に描かれた円い窪みとして読ませる。
static func ticks(center: Vector2, node_radius: float, field: FieldData) -> PackedVector2Array:
	var out := PackedVector2Array()
	if field == null or node_radius <= 0.0:
		return out
	var count := tick_count(field)
	if count <= 0:
		return out
	var length := node_radius * lerpf(TICK_MIN_LENGTH, TICK_MAX_LENGTH, share(field))
	for i in count:
		var angle := TICK_START_ANGLE + TAU * float(i) / float(count)
		var dir := Vector2(cos(angle), sin(angle))
		out.append(center + dir * node_radius)
		out.append(center + dir * (node_radius - length))
	return out
