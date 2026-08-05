class_name RendezvousPreview
extends RefCounted

## 発射前の先読み: 自分と相手が**同じ時刻にどこに居るか**を出す。
##
## 動機(コールドプレイ 2026-08-05): 段1で敵の予告のど真ん中を狙って撃ったのに、
## 接触0回のまま両者が壁で削れ合って勝ってしまった。狙った相手に一度も触れずに
## 勝つ試合が初戦だったので、このゲームの核である「噛み合わせ」がまだ一度も
## 起きていないまま報酬画面へ進んだことになる。前サイクルの計測でも、素の自機で
## 敵の**出現点**を狙うボット(aim_spawn)はLv1の無接触率の中央値が1.00
## ——半分の戦闘が一度も噛み合わない——一方で先読みして撃つボット(intercept)は
## 初接触までのp90が0.95秒だった。つまりこれは腕前ではなく**情報**の差で、
## 予告は「敵の今の位置と速度」しか語らないのに、当てるのに要るのは
## 「自分が着いた頃に敵がどこに居るか」だった。
##
## そこで、狙っている間だけ、両者を**衝突なしで自由飛行**させて先読みし、
## 一番近づく瞬間の2点を返す。プレイヤーはその2点を見て置き撃ちできる。
##
## 表示専用であることが要:
##  - **敵側の入力は予告の表示値(揺れたもの)を渡すこと**。確定値を渡すと予告の
##    揺れ(TelegraphWobble = 読み切らせないための設計)を素通りして先読みが
##    確定情報になる。揺れた値で先読みすれば、先読みもその幅ぶん揺れる
##    ——「だいたい噛み合う/だいたい外す」までは分かり、それ以上は分からない。
##  - 発射は今までどおり確定値で解決される。ここの結果は一切使われない。
##
## 跳ね返りは追わない。代わりに**どちらかが壁か柱へ届いた時点で打ち切る**
## (cut_short)。跳ね返った先まで先読みすると当たらない未来まで描くことになり、
## 「跳ね返る前に噛み合うか」という読みやすい問いから外れる。柱を壁と同じに
## 扱うのが要で、コールドプレイ2026-08-05の段1(FIELD_PILLARS)はまさに、
## 柱の縁で敵が弾かれて予告した交差が起きなかった形だった。
##
## Nodeにもシーンにも依存しない純粋な静的関数なので、ヘッドレスから直接テストできる。


## 先読みする既定の秒数。壁までの1本目の道のりを見るのに足りて、
## それ以上伸ばしても壁で打ち切られるだけの長さ。
const DEFAULT_HORIZON := 1.4

## 先読みの刻み幅。**BattleRequest.time_step と同じであること**——ずれると
## 先読みと本番のリゾルバが別の軌道を歩き、予告した交差時刻が本番とずれる。
## tests/test_rendezvous_preview.gd が両者の一致を照合する。
const DEFAULT_STEP := 1.0 / 60.0


## 自由飛行の1ステップ。**BattleResolver._integrate と同じ順序・同じ式**
## (位置を先に進めてから加速度を足す)。順序を変えると本番とずれる。
## 戻り値は [位置, 速度]。
static func advance(
	pos: Vector2,
	vel: Vector2,
	stats: SpinnerStats,
	center: Vector2,
	stage_strength: float,
	stage_shape: SpinnerPhysics.StageShape,
	dt: float
) -> Array[Vector2]:
	var next_pos := pos + vel * dt
	var accel := SpinnerPhysics.friction_accel(vel, stats.friction)
	accel += SpinnerPhysics.stage_slope_accel(
		next_pos, center,
		SpinnerPhysics.gripped_slope_strength(stage_strength, stats.slope_grip),
		stage_shape
	)
	return [next_pos, vel + accel * dt] as Array[Vector2]


## 発射前の2体を自由飛行させ、**一番近づく瞬間**を返す。触れるならその瞬間で
## 打ち切る(触れた後の未来は衝突を無視した嘘になるため)。
##
## inradius は土俵の内接半径、obstacles は柱(xy=中心・z=半径)。どちらかのコマの
## 縁がそこへ届いたら打ち切って cut_short を立てる。inradius が0以下なら壁を、
## obstacles が空なら柱を見ない(調整・テスト用)。
##
## 戻り値:
##   time          その瞬間の時刻(秒)。発射を0とする
##   player_point  その時刻の自分の中心
##   enemy_point   その時刻の相手の中心
##   gap           縁と縁の距離。負なら食い込み(=接触)
##   contact       本番と同じ述語(SpinnerPhysics.is_colliding)で噛み合ったか
##   cut_short     壁か柱へ届いて先読みを打ち切ったか
static func closest_approach(
	player_pos: Vector2,
	player_vel: Vector2,
	player_stats: SpinnerStats,
	enemy_pos: Vector2,
	enemy_vel: Vector2,
	enemy_stats: SpinnerStats,
	center: Vector2,
	stage_strength: float,
	stage_shape: SpinnerPhysics.StageShape,
	inradius: float,
	obstacles: Array[Vector3] = [],
	horizon: float = DEFAULT_HORIZON,
	dt: float = DEFAULT_STEP
) -> Dictionary:
	# 刻み数。dtが0以下でも門は要らない: horizon/0.0 は INF で、int(INF) は負の
	# 巨大値になり for が0回で回る=発射の瞬間だけを見て返る。門を別に置くと
	# テストに映らない枝が1本増えるだけなので置かない(dt=0はテストが名指しで検査する)。
	var steps := int(horizon / dt)

	var pp := player_pos
	var pv := player_vel
	var ep := enemy_pos
	var ev := enemy_vel
	var touch := player_stats.radius + enemy_stats.radius

	var best := {
		"time": 0.0,
		"player_point": pp,
		"enemy_point": ep,
		"gap": pp.distance_to(ep) - touch,
		"contact": false,
		"cut_short": false,
	}
	# 壁・柱は「入った瞬間」で打ち切る=**発射時に既に接しているものは数えない**。
	# 発射位置は柱の縁へ寄せてクランプされる(FieldData.clamp_placement)ので、
	# 素直に「触れているか」で切ると、柱際から撃った瞬間に先読みが消える。
	var p_blocked := _blocked(pp, player_stats.radius, center, inradius, obstacles)
	var e_blocked := _blocked(ep, enemy_stats.radius, center, inradius, obstacles)

	# 発射の瞬間から噛み合っている場合(本番も1歩目で衝突する)。判定は下の刻みと
	# 同じ述語で採る。
	if SpinnerPhysics.is_colliding(
		pp, player_stats.radius, pv, ep, enemy_stats.radius, ev
	):
		best["contact"] = true
		return best

	for i in steps:
		var t := (i + 1) * dt
		var pn := advance(pp, pv, player_stats, center, stage_strength, stage_shape, dt)
		var en := advance(ep, ev, enemy_stats, center, stage_strength, stage_shape, dt)
		pp = pn[0]
		pv = pn[1]
		ep = en[0]
		ev = en[1]

		var gap := pp.distance_to(ep) - touch
		if gap < float(best["gap"]):
			best["time"] = t
			best["player_point"] = pp
			best["enemy_point"] = ep
			best["gap"] = gap
		# 噛み合いの判定は**本番と同じ述語**(SpinnerPhysics.is_colliding)で採る。
		# 「縁が重なった」だけでは足りない: 最接近の瞬間は相対速度が横向きなので、
		# 掠めただけの重なりはリゾルバ側で「離れていく最中」と見なされて衝突に
		# ならない。gap<=0 で噛み合うと言ってしまうと、その掠めを「当たる」と
		# 予告して本番で当たらない——先読みが嘘をつく唯一の道がこれだった
		# (コールドプレイ2026-08-05の段1がまさにこの掠めで、接触0回だった)。
		if SpinnerPhysics.is_colliding(
			pp, player_stats.radius, pv, ep, enemy_stats.radius, ev
		):
			best["time"] = t
			best["player_point"] = pp
			best["enemy_point"] = ep
			best["gap"] = gap
			best["contact"] = true
			return best

		var p_now := _blocked(pp, player_stats.radius, center, inradius, obstacles)
		var e_now := _blocked(ep, enemy_stats.radius, center, inradius, obstacles)
		if (p_now and not p_blocked) or (e_now and not e_blocked):
			best["cut_short"] = true
			return best
		p_blocked = p_now
		e_blocked = e_now

	return best


## コマの縁が壁(内接円)か柱へ届いたか。inradiusが0以下なら壁を、obstaclesが
## 空なら柱を見ない。
static func _blocked(
	pos: Vector2, radius: float, center: Vector2, inradius: float,
	obstacles: Array[Vector3]
) -> bool:
	if inradius > 0.0 and pos.distance_to(center) + radius >= inradius:
		return true
	for o in obstacles:
		if pos.distance_to(Vector2(o.x, o.y)) <= o.z + radius:
			return true
	return false


## 乱戦で先読みを1つだけ見せるための選び方。**触れるものがあれば一番早く
## 触れるもの**、無ければ**一番近づくもの**を選ぶ。返すのはresultsの添字で、
## 空なら-1(呼び手は非表示にする)。
##
## 全員ぶんの円を出すと、時刻の違う「自分」が頭数ぶん並んで何を見ればいいのか
## 分からなくなる。最初に噛み合う相手だけが置き撃ちの対象なので、1つに絞る。
static func primary_index(results: Array[Dictionary]) -> int:
	var best := -1
	for i in results.size():
		if best < 0:
			best = i
			continue
		var a: Dictionary = results[i]
		var b: Dictionary = results[best]
		if bool(a["contact"]) != bool(b["contact"]):
			if bool(a["contact"]):
				best = i
			continue
		if bool(a["contact"]):
			if float(a["time"]) < float(b["time"]):
				best = i
		elif float(a["gap"]) < float(b["gap"]):
			best = i
	return best
