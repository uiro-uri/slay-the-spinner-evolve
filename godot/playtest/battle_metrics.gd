class_name BattleMetrics
extends RefCounted

## 敗者がどう死んだかを、rpsの時系列だけから分類する。純粋な静的関数で、
## Nodeにもシーンにも依存しない(invariants.gd と同型)。
##
## 「衝突1回で終わる」がどのコマに・どれくらいの頻度で起きているかを測るための
## 計測。BattleResult.impacts は衝突回数を数えるが、誰同士かを区別しないうえ、
## impacts==1 でも「一撃死」か「衝突を1回挟んだだけの自然減衰死」かを区別できない。
## そこで敗者1体ぶんのrps系列を歩き、各フレームの減り方を署名で分類する。
##
## リゾルバは1ステップで rps を次の順に動かす(battle_resolver.gd):
##   1. 衝突削り     rps -= drain           (引き算、drainは任意)
##   2. 壁/障害物     rps *= wall_damping    (乗算、0.75)
##   3. 自然減衰     rps -= radius*rate*dt  (引き算、定数)
## いずれも maxf(., 0.0) でクランプされる。3つは署名が違うので、自然減衰ぶんを
## 差し引いた残りが「乗算に見えるか/任意の引き算か/ゼロか」で見分けられる。
## impacts/wall_impacts の共有リストは体を区別しないので使わない(相手の壁衝突が
## 混ざる)。体ごとに正しいのは、その体自身のrps系列だけ。


## 敗者の死因を1レコードにまとめて返す。決着が付いていない(引き分け/打ち切り)
## 場合は {"loser": "none"} を返す。
static func classify(request: BattleRequest, result: BattleResult) -> Dictionary:
	if result.outcome == BattleResult.Outcome.DRAW or result.timed_out:
		return {"loser": "none"}

	var frames: Array[BattleResult.Snapshot]
	var radius: float
	var who: String
	if result.outcome == BattleResult.Outcome.ENEMY_WIN:
		# プレイヤーが力尽きた。
		frames = result.player_frames
		radius = request.player.stats.radius
		who = "player"
	else:
		# プレイヤーの勝ち。最後に力尽きた敵(＝最終rpsが最小の敵)を敗者とする。
		var idx := _lowest_final_enemy(result)
		if idx < 0:
			return {"loser": "none"}
		frames = result.enemy_tracks[idx]
		radius = request.enemies[idx].stats.radius
		who = "enemy"

	return _classify_track(request, frames, radius, who)


static func _lowest_final_enemy(result: BattleResult) -> int:
	var best := -1
	var best_rps := INF
	for i in result.enemy_tracks.size():
		var track: Array = result.enemy_tracks[i]
		if track.is_empty():
			continue
		var final_rps: float = track[track.size() - 1].rps
		if final_rps < best_rps:
			best_rps = final_rps
			best = i
	return best


static func _classify_track(
	request: BattleRequest, frames: Array[BattleResult.Snapshot],
	radius: float, who: String
) -> Dictionary:
	var dt := request.time_step
	var decay_amt := radius * request.natural_damping * dt
	var wall_damping := request.wall_damping
	var threshold := request.lose_threshold

	# 死んだフレーム(初めて閾値以下になったところ)を探す。
	var fatal := -1
	for i in frames.size():
		if frames[i].rps <= threshold:
			fatal = i
			break
	if fatal <= 0:
		# 最初のフレームで既に死んでいる/見つからない。分類不能。
		return {"loser": who, "death_cause": "unknown"}

	# fatal-1 → fatal の間に何が起きたかを分類する。
	var hits_taken := 0            # これまでに受けた衝突(クラスタ)の数
	var wall_hits := 0
	var prev_was_hit := false      # 連続フレームの削りを1クラスタに統合するため
	var rps_at_first_hit := -1.0
	var fatal_hit_index := 0       # 何発目の衝突で死んだか(0=衝突死でない)
	var death_cause := "decay"
	var rps_before_fatal := frames[fatal - 1].rps
	var fatal_drain := 0.0

	for i in range(1, fatal + 1):
		var prev := frames[i - 1].rps
		var cur := frames[i].rps
		var kind := _event_kind(prev, cur, decay_amt, wall_damping)

		if kind == "wall":
			wall_hits += 1
			prev_was_hit = false
		elif kind == "drain":
			if not prev_was_hit:
				hits_taken += 1
				if rps_at_first_hit < 0.0:
					rps_at_first_hit = prev
			prev_was_hit = true
		else:
			prev_was_hit = false

		if i == fatal:
			# 死んだフレームの原因を確定する。
			var before_decay := cur + decay_amt
			fatal_drain = maxf(prev - before_decay, 0.0)
			if kind == "drain":
				death_cause = "drain"
				fatal_hit_index = hits_taken
			elif kind == "wall":
				death_cause = "wall"
			else:
				death_cause = "decay"

	return {
		"loser": who,
		"death_cause": death_cause,
		"hits_taken": hits_taken,
		"wall_hits": wall_hits,
		"fatal_hit_index": fatal_hit_index,
		"rps_before_fatal": rps_before_fatal,
		"fatal_drain": fatal_drain,
		"rps_at_first_hit": rps_at_first_hit,
	}


## 1フレームぶんのrps変化を分類する。自然減衰を差し引いた残りが
##  - ほぼゼロ            → "decay"(減衰のみ)
##  - prev*wall_damping^k → "wall"(壁/障害物、1〜2回)
##  - それ以外の引き算    → "drain"(衝突削り)
## 衝突と壁が同フレームで重なると "drain" に寄る(衝突が起きた事実を優先)。
static func _event_kind(
	prev: float, cur: float, decay_amt: float, wall_damping: float
) -> String:
	if prev <= 0.0:
		return "decay"
	# 自然減衰を戻した、衝突/壁だけが効いた後の値。クランプで cur=0 のときは
	# 過大に戻るが、その場合はもう死んでいるので分類の細部は問わない。
	var before_decay := cur + decay_amt
	var tol := maxf(1e-4, 1e-3 * prev)

	if absf(before_decay - prev) <= tol:
		return "decay"
	# 壁は乗算。1回または2回(同フレーム複数衝突)を許す。
	for k in [1, 2]:
		if absf(before_decay - prev * pow(wall_damping, k)) <= tol:
			return "wall"
	return "drain"
