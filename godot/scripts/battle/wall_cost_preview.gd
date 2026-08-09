class_name WallCostPreview
extends RefCounted

## 発射前の見積もり その2: **相手に届くまでに、自分が壁でいくら回転を失うか**。
##
## 動機(コールドプレイ 2026-08-09 深夜): 段9のボスに5回撃って、残った相手の回転が
## 1% / 21% / 33% / 24% とばらけた。狙いを 250°→245°(5度)動かしただけで
## 「あと0.2rpsで勝ち」が「相手が9.3rps残して圧勝」へ裏返る。打ち手には
## **どちらへ動かせば良くなるのかが一切見えない**ので、引き直しは上達ではなく
## サイコロの振り直しになっていた。内訳を見ると裏返りの正体は壁で、同じボスに
## 対して自分の壁喪失が 11.6(5回) / 13.9(5回) / 15.8(7回) と揺れている。
## 段1〜3でも自分の喪失の 40% / 72% / 24% が壁だった。
##
## ところが発射前に見えるのは RendezvousPreview の「触れるか」だけで、
## **触れるまでに自分が何回壁を舐めるか**は誰も言わない。journal に5サイクル
## 連続で載っている「発射フォースが効くのに読めない」「発射の腕が効かない」は、
## 引きを強めた罰の半分がこの見えない側にある、ということだった
## (前サイクルの「次の候補」筆頭・案①)。
##
## そこで、狙っている間だけ**自分だけを衝突なしで自由飛行**させ、壁・柱に当たる
## たびに本番と同じ式で回転を引き、合計を返す。相手は見ない: 見積もりの寿命は
## 「相手に触れるまで」で、触れた後の未来は RendezvousPreview と同じ理由で嘘になる。
##
## 表示専用であること・本番と同じ式を通すことが要:
##  - 1回の喪失は **SpinnerPhysics.wall_damaged_rps**(BattleResolver が本番で
##    通すのと同じ1本)で出す。ここに式を書き写すと、調整のたび静かにずれて
##    「見積もりが嘘をつく」——予告が嘘をつくのと同じ罪になる。
##  - 積分は **RendezvousPreview.advance**(= BattleResolver._integrate と同順)。
##  - 課金の可否(billable)も本番と同じ「面から離れずに続く接触は1回」の規則で
##    数える。これが無いと壁に沿って滑る狙いが毎刻み課金され、見積もりが跳ね上がる。
##
## Nodeにもシーンにも依存しない純粋な静的関数なので、ヘッドレスから直接テストできる。


## 「言うに値する」敷居。回転ゲージのこの割合を超えて壁で失う見込みのときだけ
## 文言を出す。掠り1回(ゲージの1%未満)まで毎フレーム喋ると、本当に痛い狙いの
## ときの1行が埋もれる。
const DEFAULT_NOTABLE_SHARE := 0.05

## 面に接しているかの遊び。**BattleResolver.SURFACE_CONTACT_SKIN と同じ値**で
## あること——ずれると「続きの接触」の切れ目が本番と変わり、課金回数がずれる。
const _SURFACE_CONTACT_SKIN := 1e-3


## 発射から until 秒までのあいだに、自分が壁・柱で失う回転を見積もる。
##
## until には RendezvousPreview が返した噛み合いの時刻を渡すのが本筋
## (＝「相手に届くまでの通行料」)。噛み合わないなら先読みの地平をそのまま渡す。
##
## walls は土俵の壁(ArenaWall.build と同じ半平面の列)、obstacles は柱
## (xy=中心・z=半径)。req からは壁の調整値だけを読む(相手は一切見ない)。
##
## 戻り値:
##   hits        課金された壁・柱当たりの回数(本番の wall_hits と同じ数え方)
##   rps_loss    そのぶんで失う回転の合計
##   loss_share  rps_loss が回転ゲージ(stats.rps)に占める割合
##   first_time  最初に課金された当たりの時刻(秒)。hits=0 なら 0.0
##   first_speed その当たりの進入速度(壁の法線方向)。hits=0 なら 0.0
static func approach_cost(
	pos: Vector2,
	vel: Vector2,
	stats: SpinnerStats,
	center: Vector2,
	stage_strength: float,
	stage_shape: SpinnerPhysics.StageShape,
	walls: Array[ArenaWall],
	obstacles: Array[Vector3],
	req: BattleRequest,
	until: float = RendezvousPreview.DEFAULT_HORIZON,
	dt: float = RendezvousPreview.DEFAULT_STEP
) -> Dictionary:
	var out := {
		"hits": 0,
		"rps_loss": 0.0,
		"loss_share": 0.0,
		"first_time": 0.0,
		"first_speed": 0.0,
	}
	# 刻み数。dt<=0 は INF→int で負になり for が0回=発射の瞬間だけ見て返る
	# (RendezvousPreview.closest_approach と同じ理由で門を置かない)。
	var steps := int(until / dt)

	var p := pos
	var v := vel
	var rps := stats.rps
	# **本番(BattleResolver.State)は発射位置によらず false で始まる**ので、ここも
	# false で始める。「発射位置が柱の縁へ密着クランプされている(FieldData.
	# clamp_placement)なら接触中として始めるべきでは」と一度そう書いたが、それだと
	# 密着から柱へ突っ込む狙い——いちばん痛い狙い——で1回目の課金が消え、実測で
	# 見積もり1回/2.25rps に対し本番2回/4.50rps と**半分に過少申告**した。
	# 見積もりが本番より軽く出るのは、この機能でいちばんやってはいけない嘘なので、
	# 「もっともらしい」より「本番と同じ」を採る。
	var touching := false

	for i in steps:
		var t := (i + 1) * dt
		var next := RendezvousPreview.advance(
			p, v, stats, center, stage_strength, stage_shape, dt
		)
		p = next[0]
		v = next[1]

		# 課金の可否はステップの頭で固定する(本番 _resolve_body_field と同じ)。
		# 同じステップで壁と柱を両方踏んだときに二重取りにしないため。
		var billable := not touching
		var hit := false

		for w in walls:
			if not SpinnerPhysics.wall_hit(w.point, w.normal, p, v, stats.radius):
				continue
			# 進入速度は反射前に測る(本番と同じ)。
			var normal_speed := -w.normal.dot(v)
			v = SpinnerPhysics.wall_bounce(v, w.normal, stats.restitution)
			p += w.normal * SpinnerPhysics.wall_penetration(
				w.point, w.normal, p, stats.radius
			)
			hit = true
			if billable:
				rps = _charge(out, rps, normal_speed, stats, req, t)

		for o in obstacles:
			var obstacle_center := Vector2(o.x, o.y)
			if not SpinnerPhysics.obstacle_hit(
				obstacle_center, o.z, p, v, stats.radius
			):
				continue
			var normal := (p - obstacle_center).normalized()
			var normal_speed := -normal.dot(v)
			v = SpinnerPhysics.wall_bounce(v, normal, stats.restitution)
			p += normal * SpinnerPhysics.obstacle_penetration(
				obstacle_center, o.z, p, stats.radius
			)
			hit = true
			if billable:
				rps = _charge(out, rps, normal_speed, stats, req, t)

		if hit:
			touching = true
		elif not _touching_any_surface(p, stats.radius, walls, obstacles):
			touching = false

		# 自然減衰も本番どおり進める。見積もりに載せるのは壁のぶんだけだが、
		# 壁の喪失は現在rpsに比例する成分を持つので、rps自体は正しく減らす。
		rps = maxf(
			rps - SpinnerPhysics.natural_spin_decay(
				stats.radius, req.natural_damping * stats.spin_decay, dt
			),
			0.0
		)
		if rps <= 0.0:
			break

	if stats.rps > 0.0:
		out["loss_share"] = float(out["rps_loss"]) / stats.rps
	return out


## 1回ぶんの課金。失う量は本番と同じ SpinnerPhysics.wall_damaged_rps から出す。
## 戻り値は当たった後のrps。
static func _charge(
	out: Dictionary, rps: float, normal_speed: float,
	stats: SpinnerStats, req: BattleRequest, t: float
) -> float:
	var after := SpinnerPhysics.wall_damaged_rps(
		rps, stats.rps, stats.mass, stats.radius, stats.wall_keep, normal_speed,
		req.wall_damping, req.wall_impact_ref_speed, req.wall_absolute_share,
		req.wall_violence, req.wall_drain_cap_share
	)
	if int(out["hits"]) == 0:
		out["first_time"] = t
		out["first_speed"] = normal_speed
	out["hits"] = int(out["hits"]) + 1
	out["rps_loss"] = float(out["rps_loss"]) + (rps - after)
	return after


## 壁・柱のどれか1つにでも接しているか。向きは問わない。
## BattleResolver._touching_any_surface と同じ述語・同じ遊び。
static func _touching_any_surface(
	pos: Vector2, radius: float, walls: Array[ArenaWall], obstacles: Array[Vector3]
) -> bool:
	for w in walls:
		if SpinnerPhysics.wall_gap(w.point, w.normal, pos, radius) > -_SURFACE_CONTACT_SKIN:
			return true
	for o in obstacles:
		if SpinnerPhysics.obstacle_gap(
			Vector2(o.x, o.y), o.z, pos, radius
		) > -_SURFACE_CONTACT_SKIN:
			return true
	return false


## 見積もりが「言うに値する」か。掠り1回で毎フレーム喋らないための敷居。
static func is_notable(cost: Dictionary, threshold: float = DEFAULT_NOTABLE_SHARE) -> bool:
	return (
		int(cost.get("hits", 0)) > 0
		and float(cost.get("loss_share", 0.0)) >= threshold
	)


## 見積もりを1行にする。言うことが無ければ空文字＝呼び手は行ごと出さない。
##
## 文言の組み立てをここへ置くのは、実UI(Battle.gd)とCLI(naive_play)が
## **同じ数字を同じ言い方で**出すため。ハーネスと実UIの情報量を対等に保つ、が
## journal で何度も破れている約束なので、分かれ道自体を作らない。
static func hint_text(
	cost: Dictionary, threshold: float = DEFAULT_NOTABLE_SHARE
) -> String:
	if not is_notable(cost, threshold):
		return ""
	return TranslationServer.translate("BATTLE_LEAD_WALL_COST").format({
		"pct": int(round(float(cost["loss_share"]) * 100.0)),
		"hits": int(cost["hits"]),
	})
