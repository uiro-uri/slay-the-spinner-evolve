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
##   1. 衝突削り     rps -= drain                                  (引き算、drainは任意)
##   2. 壁/障害物     rps *= effective_wall_damping(衝突の激しさでスケールした基準, wall_keep)
##   3. 自然減衰     rps -= radius*(rate*spin_decay)*dt            (引き算、定数)
## いずれも maxf(., 0.0) でクランプされる。自然減衰は定数なので値で照合できるが、
## 壁は損失が進入速度に比例するようになり(impact_scaled_wall_damping)、rps系列の
## 値照合では衝突削りと見分けられない。そこで壁だけは、リゾルバが記録した事実
## (wall_impacts の時刻と接触点)をその体のフレームと突き合わせて見分ける。接触点は
## 「その体の中心から壁法線方向へ半径ぶん」に置かれるため、該当フレームの自分の
## 中心との距離がちょうど自分の半径のものだけが自分の壁衝突になる。
## 照合に使う減衰量は**そのコマの実効値**でなければならない。土俵の素の値で照合
## すると、MOMENTUM(spin_decay) 札を持つコマの減衰が "drain"(衝突削り)に化け、
## 死因と被弾数が嘘になる。


## 敗者の死因を1レコードにまとめて返す。決着が付いていない(引き分け/打ち切り)
## 場合は {"loser": "none"} を返す。
static func classify(request: BattleRequest, result: BattleResult) -> Dictionary:
	if result.outcome == BattleResult.Outcome.DRAW or result.timed_out:
		return {"loser": "none"}

	var frames: Array[BattleResult.Snapshot]
	var stats: SpinnerStats
	var who: String
	if result.outcome == BattleResult.Outcome.ENEMY_WIN:
		# プレイヤーが力尽きた。
		frames = result.player_frames
		stats = request.player.stats
		who = "player"
	else:
		# プレイヤーの勝ち。最後に力尽きた敵(＝最終rpsが最小の敵)を敗者とする。
		var idx := _lowest_final_enemy(result)
		if idx < 0:
			return {"loser": "none"}
		frames = result.enemy_tracks[idx]
		stats = request.enemies[idx].stats
		who = "enemy"

	return _classify_track(request, frames, stats, who, result.wall_impacts)


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
	stats: SpinnerStats, who: String, wall_impacts: Array[BattleResult.Impact]
) -> Dictionary:
	var dt := request.time_step
	# リゾルバが実際に適用する式と同じ実効値で照合する(battle_resolver.gd参照)。
	var decay_amt := SpinnerPhysics.natural_spin_decay(
		stats.radius, request.natural_damping * stats.spin_decay, dt)
	# 壁損失は速度スケールで変動するが、この値より深くは削れない(損失の上限側)。
	# 壁だけでは説明できない喪失を衝突削りへ振り分けるのに使う。
	var wall_damping_floor := SpinnerPhysics.effective_wall_damping(
		request.wall_damping, stats.wall_keep)
	var own_walls := _own_wall_transitions(frames, stats.radius, wall_impacts, dt)
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
		var kind := _event_kind(
			prev, cur, decay_amt, own_walls.has(i), wall_damping_floor)

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
##  - ほぼゼロ                        → "decay"(減衰のみ)
##  - 自分の壁衝突が記録されたフレーム → "wall"(壁/障害物)
##  - それ以外の引き算                → "drain"(衝突削り)
## 壁損失は進入速度でスケールするため値では見分けず、リゾルバの記録(has_wall)で
## 見分ける。衝突と壁が同フレームで重なった場合、壁の下限係数(wall_damping_floor)
## でも説明できない大きさの喪失なら "drain" に寄せる(衝突が起きた事実を優先する
## 旧実装と同じ向き。壁だけの喪失は同フレーム2回でも prev*(1-floor²) を超えない)。
static func _event_kind(
	prev: float, cur: float, decay_amt: float,
	has_wall: bool, wall_damping_floor: float
) -> String:
	if prev <= 0.0:
		return "decay"
	# 自然減衰を戻した、衝突/壁だけが効いた後の値。クランプで cur=0 のときは
	# 過大に戻るが、その場合はもう死んでいるので分類の細部は問わない。
	var before_decay := cur + decay_amt
	var tol := maxf(1e-4, 1e-3 * prev)

	if absf(before_decay - prev) <= tol:
		return "decay"
	if has_wall:
		var max_wall_loss := prev * (1.0 - wall_damping_floor * wall_damping_floor)
		if prev - before_decay > max_wall_loss + tol:
			return "drain"
		return "wall"
	return "drain"


## そのコマ自身の壁/障害物衝突が映っているフレーム遷移(prev→cur の cur 側index)の
## 集合を返す。時刻tの壁衝突はステップ t/dt の積分後の状態に効くので、次の
## スナップショット(index = t/dt + 1)に映る。wall_impacts は全部の体で共有のため、
## 接触点とそのフレームの自分の中心との距離が自分の半径に一致するものだけを拾う
## (接触点は必ず「その体の中心から法線方向へ半径ぶん」に記録される)。
static func _own_wall_transitions(
	frames: Array[BattleResult.Snapshot], radius: float,
	wall_impacts: Array[BattleResult.Impact], dt: float
) -> Dictionary:
	var out := {}
	if dt <= 0.0:
		return out
	for imp in wall_impacts:
		var i := int(round(imp.time / dt)) + 1
		if i < 1 or i >= frames.size():
			continue
		if absf(imp.point.distance_to(frames[i].position) - radius) <= 1e-3:
			out[i] = true
	return out
