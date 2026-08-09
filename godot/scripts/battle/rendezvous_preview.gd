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
## 打ち切りの敷居は**発射時のめり込みの深さ**に置く(_cut_gates)。発射位置は
## 柱の縁へ密着クランプされうるので「触れているか」だけで切ると柱際の狙いが
## 全部無言になり、逆に「離れるまで免除」だと**柱を貫いて「噛み合う」と嘘をつく**。
## 深さで見れば、沿って滑る狙いは残り、突っ込む狙いだけが切れる。
##
## 打ち切りは**どちら側が届いたのか**まで返す(cut_by)。ここが要る理由は
## コールドプレイ2026-08-06: 満引き(force=1.0)で段1〜6を勝ち上がったあと段7で
## 2連敗し、力を0.2へ落とした3回目で勝った。満引きの罰は「相手より先に壁へ着く」
## ことなのに、**打ち切りは実UIでは無言**で、輪は「惜しくも外した」ときと
## 見分けがつかない。「外れる」と「そもそも相手に届く前に壁だ」は打ち手が
## まったく違う(狙いを動かす/引きを弱める)ので、同じ絵にしてはいけない。
## journal に4サイクル連続で載っている「force を初見が逆に学習する」は、
## 引きを強くするほどこの打ち切りに入りやすくなる、の裏返しでもある。
##
## Nodeにもシーンにも依存しない純粋な静的関数なので、ヘッドレスから直接テストできる。


## 先読みを打ち切った側。PLAYER|ENEMY のビット和なので BOTH は両方の論理和。
enum CutBy { NONE = 0, PLAYER = 1, ENEMY = 2, BOTH = 3 }


## 先読みする既定の秒数。壁までの1本目の道のりを見るのに足りて、
## それ以上伸ばしても壁で打ち切られるだけの長さ。
const DEFAULT_HORIZON := 1.4

## 先読みの刻み幅。**BattleRequest.time_step と同じであること**——ずれると
## 先読みと本番のリゾルバが別の軌道を歩き、予告した交差時刻が本番とずれる。
## tests/test_rendezvous_preview.gd が両者の一致を照合する。
const DEFAULT_STEP := 1.0 / 60.0

## 打ち切りの敷居(_cut_gates)に足す遊び。発射位置は柱の縁へ _NUDGE(=0.02)ぶんの
## 余裕で寄せられるので、それより1桁細かく取れば「密着から沿って滑る」狙いを
## 誤って切らずに、突っ込む狙い(1刻みで0.2ユニット深くなる)は取れる。
const _GATE_EPS := 0.001


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
## walls は土俵の壁(ArenaWall.build と同じ半平面の列)、obstacles は柱
## (xy=中心・z=半径)。どちらかのコマの縁がそこへ届いたら打ち切って cut_short を
## 立てる。walls が空なら壁を、obstacles が空なら柱を見ない(調整・テスト用)。
##
## 壁を**内接円1本ではなく本番と同じ半平面の列**で受けるのが要
## (コールドプレイ 2026-08-09 の積み残し)。矩形の土俵で内接円を使うと、
## `clamp_inside` が合法と認める隅——10×10 なら中心から 5.0 を超えて 7.07 まで——が
## 丸ごと「壁の外」に見え、(a)隅に置いたコマが発射の瞬間から食い込み扱いになって
## 免除の敷居が立ち、(b)対角へ撃つと実際の辺より 1〜2 ユニット手前で打ち切る。
## どちらも先読みが嘘をつく形なので、壁は BattleResolver と同じ
## `SpinnerPhysics.wall_gap` で測る。
##
## 戻り値:
##   time          その瞬間の時刻(秒)。発射を0とする
##   player_point  その時刻の自分の中心
##   enemy_point   その時刻の相手の中心
##   gap           縁と縁の距離。負なら食い込み(=接触)
##   contact       本番と同じ述語(SpinnerPhysics.is_colliding)で噛み合ったか
##   cut_short     壁か柱へ届いて先読みを打ち切ったか
##   cut_by        打ち切った側(CutBy)。cut_shortがfalseなら必ずNONE
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
	walls: Array[ArenaWall],
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
		"cut_by": CutBy.NONE,
	}
	# 壁・柱は「めり込みが発射時より深くなった瞬間」で打ち切る(_cut_gates)。
	# 免除を「発射時の深さまで」に限るのが要。詳しくは _cut_gates の注釈。
	var p_gates := _cut_gates(
		_block_depths(pp, player_stats.radius, walls, obstacles))
	var e_gates := _cut_gates(
		_block_depths(ep, enemy_stats.radius, walls, obstacles))

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

		var p_now := _block_depths(pp, player_stats.radius, walls, obstacles)
		var e_now := _block_depths(ep, enemy_stats.radius, walls, obstacles)
		# 同じ刻みで両者が届くこともあるので、片方を見つけた時点では抜けない。
		var cut := int(CutBy.NONE)
		if _past_gates(p_now, p_gates):
			cut |= int(CutBy.PLAYER)
		if _past_gates(e_now, e_gates):
			cut |= int(CutBy.ENEMY)
		if cut != int(CutBy.NONE):
			best["cut_short"] = true
			best["cut_by"] = cut
			return best
		# 抜け出した相手の免除は取り消す(離れたなら次は普通に打ち切る相手)。
		p_gates = _tighten_gates(p_gates, p_now)
		e_gates = _tighten_gates(e_gates, e_now)

	return best


## コマの縁が壁1枚1枚・柱それぞれへ**どれだけ食い込んでいるか**。
## 正なら食い込み、0でちょうど接触、負なら離れている(その距離)。
## 並びは walls + obstacles と同順。wallsが空なら壁の要素そのものを置かず、
## obstaclesが空なら柱の要素が無い(調整・テスト用の「見ない」がそのまま出る)。
##
## 壁は本番のリゾルバと同じ `SpinnerPhysics.wall_gap`(半平面までの符号付き深さ)で
## 測る。以前は「中心からの距離＋半径－内接半径」＝**内接円1本**だったので、
## 矩形の土俵では隅が丸ごと壁の外に見えていた: 10×10 の (8.17, 8.17) に半径0.7 の
## コマを置くと、実際には右壁まで 1.13 ユニット空いているのに深さ +0.18 の
## 「食い込み」になる。壁を1枚に畳んでいたぶん、免除も全方向へ一括で効いていた。
##
## 「届いたか」のboolではなく深さを返すのは、_cut_gates が
## 「発射時より深くなったか」を問うため。boolでは同じ答えしか出せない。
static func _block_depths(
	pos: Vector2, radius: float, walls: Array[ArenaWall],
	obstacles: Array[Vector3]
) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for w in walls:
		out.append(SpinnerPhysics.wall_gap(w.point, w.normal, pos, radius))
	for o in obstacles:
		out.append(SpinnerPhysics.obstacle_gap(Vector2(o.x, o.y), o.z, pos, radius))
	return out


## 打ち切りの敷居。壁・柱ごとに「この深さを超えたら打ち切る」を持つ。
##
## 発射位置は柱の縁へ寄せてクランプされる(FieldData.clamp_placement)ので、
## 「触れているか」だけで切ると柱際からの狙いが1刻み目で全部無言になる。
## そこで**発射時に既に食い込んでいる相手は、その深さまで免除する**。
##
## 免除を「離れるまで」にしてはいけない(2026-08-09のコールドプレイ、段3・
## FIELD_PILLARS で1敗した形): 発射位置が柱(7,7)の縁へ密着クランプされたまま
## 中央を狙うと、免除が柱を**通り抜け終わるまで**続き、先読みは柱の芯
## (中心からの距離0.09ユニット)を素通りして「0.30秒で噛み合う」と予告した。
## 本番はもちろん1歩目で柱に弾かれ、敵に一度も触れないまま壁で削られて敗北。
## **「打ち切りが無言」ではなく「噛み合うと嘘をつく」**ので、輪の破線でも
## 1行の文言でも救えない——嘘の側を直すしかない。
##
## 敷居を「発射時の深さ」に置くと、密着から離れる/沿って滑る狙いは今までどおり
## 先読みが残り(深さは増えない)、突っ込む狙いだけが切れる。
static func _cut_gates(depths: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for d in depths:
		out.append(maxf(d, 0.0))
	return out


## どれか1つでも敷居より深く食い込んだか。
static func _past_gates(depths: PackedFloat32Array, gates: PackedFloat32Array) -> bool:
	for i in depths.size():
		if depths[i] > gates[i] + _GATE_EPS:
			return true
	return false


## 抜け出した(食い込みが消えた)相手の免除を取り消す。従来の実装が
## `p_blocked = p_now` で毎刻み更新していたのと同じ役目で、一度離れた柱へ
## 戻ってきたときは普通に打ち切る。敷居は下がるだけ＝免除は緩まない。
static func _tighten_gates(
	gates: PackedFloat32Array, depths: PackedFloat32Array
) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in gates.size():
		out.append(minf(gates[i], maxf(depths[i], 0.0)))
	return out


## closest_approach の結果が「自分が先に壁か柱へ届いた」ぶんで打ち切られたか。
## 描画側が輪を印付けるのに使う。噛み合う結果には打ち切りが立たないので、
## 触れる狙いに警告が出ることはない。
static func cut_player(lead: Dictionary) -> bool:
	return int(lead.get("cut_by", CutBy.NONE)) & int(CutBy.PLAYER) != 0


## 同じく「相手が先に届いた」ぶんか。
static func cut_enemy(lead: Dictionary) -> bool:
	return int(lead.get("cut_by", CutBy.NONE)) & int(CutBy.ENEMY) != 0


## 打ち切りを1行で言う訳キー。言うことが無ければ空文字＝呼び手は行ごと出さない。
##
## 「外す」と「打ち切り」を分けるのが目的なので、**噛み合う結果では必ず空**に
## なる。ここに contact の門は置かない: closest_approach は contact で先に返り
## cut_by を NONE のまま残すので、門を足しても答えが変わらない枝が1本増える
## だけになる(journal に何度も出る「防御的な既定値は書いた瞬間にテストへ映らない
## 枝になる」)。「噛み合う結果は必ず cut_by=NONE」の方をテストが名指しで縛る。
##
## 側で文言を分けるのは、打ち手が反対だから: 自分が先に届くなら引きを弱めるか
## 近くから撃つ、相手が先に届くなら跳ね返りを待つ(＝そのまま撃ってよい)。
static func hint_key(lead: Dictionary) -> String:
	var mine := cut_player(lead)
	var theirs := cut_enemy(lead)
	if mine and theirs:
		return "BATTLE_LEAD_CUT_BOTH"
	if mine:
		return "BATTLE_LEAD_CUT_PLAYER"
	if theirs:
		return "BATTLE_LEAD_CUT_ENEMY"
	return ""


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
