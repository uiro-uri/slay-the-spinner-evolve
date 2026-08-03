class_name SlopeContour
extends RefCounted

## 対戦画面の床に描く「この土俵はどう窪んでいるか」の等高線。
## Node にもシーンにも乱数にも依存しない純粋関数だけ(cf. scripts/ui/stage_slope_mark.gd)。
##
## **なぜ要るのか**
## 前サイクルでマップのノードに傾斜のケバを描いたが、そのとき自分で残した宿題が
## 「ケバには現物との対が無い」だった。柱の印は入場すれば柱の絵があり、外周形状は
## 外周の絵がある。ところが**傾斜だけは、入場しても答え合わせができない**——
## 対戦画面の床は今まで**どの土俵でも同じ4本の同心円**で、すり鉢の急さも円錐との
## 違いも一切描いていなかったからである(Arena._draw の `for i in range(1, 5)`)。
##
## 一次証拠(コールドプレイ 2026-08-03, seed=4821)。1ランで6つの土俵に入ったが、
## FIELD_PLATE(段1・段4・段8) と FIELD_BOWL(段3) と FIELD_CLASSIC(段5・段7) は
## 入場後の画面まで一字一句同じ(矩形・内接半径5.0・柱なし・同心円4本)で、
## **遊び終わるまでこの3つの違いが分からなかった**。実際には壁の代償が2倍違う
## (前サイクルの実測: 自機のrps喪失に占める壁の取り分が BOWL 17% ↔ PLATE 33%)。
##
## **記法**
## 等高線。ケバと同じく地図の在来記法で、**線が混んでいるところほど急**。
## すり鉢(DISH)は外へ行くほど急なので縁に寄って混み、円錐(CONE)はどこでも一定
## 傾斜なので等間隔に並ぶ——形の違いがそのまま線の詰まり方に出る。
##
## 本数はマップのケバと**同数**(StageSlopeMark.tick_count)にする。目盛りを別に
## 作ると2つの絵が別々の嘘をつくし、何より「ノードのケバが7本 → 入ったら床の輪も
## 7本」という対応が取れることがこの変更の目的そのものなので、本数は借りてくる。

## 高さを数値積分するときの刻み数。中点則なので、すり鉢(1次)・円錐(定数)の
## どちらもこの刻みで厳密に積める(誤差は逆引きの線形補間ぶんだけ)。
const SAMPLES := 512


## この土俵の等高線の本数。マップのケバと同数。
static func ring_count(field: FieldData) -> int:
	return StageSlopeMark.tick_count(field)


## 中心から radius までの「登り」(単位質量あたりの位置エネルギー)。
##
## すり鉢と円錐で式が違うが、その場合分けはここに書き写さない。
## SpinnerPhysics.stage_slope_accel に道中の点を渡して積む
## (傾斜の定義が2箇所にあると、床の絵と実際の解決で違う土俵を出すことになる。
## StageSlopeMark.rim_pull が同じ理由で物理に測らせているのと同じ流儀)。
static func height(field: FieldData, radius: float) -> float:
	return _cumulative(field, radius)[SAMPLES]


## 等高線の半径列(内→外)。等しい高さの刻みで割るので、急な区間ほど輪が詰まる。
## 最外周はちょうど内接半径＝壁の上に載る。
static func radii(field: FieldData) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if field == null:
		return out
	var count := ring_count(field)
	var rim := field.inradius()
	if count <= 0 or rim <= 0.0:
		return out

	var cumulative := _cumulative(field, rim)
	var total := cumulative[SAMPLES]
	if total <= 0.0:
		# 傾斜が無い土俵(強さ0)。高さで割れないので半径を等分する
		# ——平らな床の目盛りとして読ませる(従来の同心円と同じ絵)。
		for k in range(1, count + 1):
			out.append(rim * float(k) / float(count))
		return out

	# 累積は単調増加なので、刻みを1本ずつ上げながら表を舐めれば1周で逆に引ける。
	var step := rim / float(SAMPLES)
	var idx := 1
	for k in range(1, count + 1):
		var target := total * float(k) / float(count)
		while idx < SAMPLES and cumulative[idx] < target:
			idx += 1
		var lo := cumulative[idx - 1]
		var hi := cumulative[idx]
		var t := 0.0 if hi <= lo else clampf((target - lo) / (hi - lo), 0.0, 1.0)
		out.append(step * (float(idx - 1) + t))
	# 最外周は積分の丸めに関わらず壁の上へ。中途半端に内側へ落ちると
	# 「壁の手前にもう1本ある」ように見えるし、外へ出れば土俵をはみ出す。
	out[count - 1] = rim
	return out


## 中心から radius までの高さの累積表。index i は中心から step*i までの登り
## (先頭は必ず0で、長さは SAMPLES+1)。土俵が無い・半径が0なら全て0。
static func _cumulative(field: FieldData, radius: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(SAMPLES + 1)
	if field == null or radius <= 0.0:
		return out
	var center := field.center()
	var step := radius / float(SAMPLES)
	var running := 0.0
	for i in SAMPLES:
		# 中点則。円錐は normalized() が中心でだけ0を返すので、区間の端でなく
		# 中点を測ることで「中心の1点だけ傾斜0」という数値上の穴を踏まない。
		var s := (float(i) + 0.5) * step
		running += SpinnerPhysics.stage_slope_accel(
			center + Vector2.RIGHT * s, center, field.stage_strength, field.stage_shape
		).length() * step
		out[i + 1] = running
	return out
