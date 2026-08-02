class_name PlaytestInvariants
extends RefCounted

## どんな調整でも成り立つべき性質を、全戦闘結果に掛ける検査。
##
## バグ検出の本体。1戦を目で見ても分からない壊れ方(nan、アリーナ外への脱出、
## rpsの増加)を、大量試行の中から機械的に拾う。違反はシードとリクエストの
## JSONごと記録するので、BattleRequest.from_dict()でその場で再現できる。

## 壁は「内向きに進んでいる間は当たらない」判定なので、1ステップ分は
## 食い込みうる。それを超えた分だけを脱出とみなす余白。
const ESCAPE_MARGIN := 1.0


## 違反の一覧を返す。空なら健全。
static func check(request: BattleRequest, result: BattleResult) -> Array[String]:
	var violations: Array[String] = []

	_check_frames(request, result.player_frames, "player", violations)
	for i in result.enemy_tracks.size():
		_check_frames(request, result.enemy_tracks[i], "enemy[%d]" % i, violations)

	# 全トラックの長さがプレイヤーと揃っていること。1本でもずれると再生時に
	# フレームの引き当てが狂う。
	for i in result.enemy_tracks.size():
		if result.enemy_tracks[i].size() != result.player_frames.size():
			violations.append("フレーム数が揃っていない enemy[%d] (%d vs %d)" % [
				i, result.enemy_tracks[i].size(), result.player_frames.size()
			])

	if not is_finite(result.finish_time) or result.finish_time < 0.0:
		violations.append("決着時刻が壊れている (%s)" % result.finish_time)
	elif result.finish_time > request.max_duration + request.time_step:
		violations.append("決着時刻が上限を超えている (%.2f > %.2f)" % [
			result.finish_time, request.max_duration
		])

	_check_spawn_overlap(request, violations)

	for impact in result.impacts:
		if impact.time < 0.0 or impact.time > result.finish_time + request.time_step:
			violations.append("衝突時刻が戦闘の外 (%.3f / 決着 %.3f)" % [
				impact.time, result.finish_time
			])
			break

	return violations


## 出現の時点で敵同士が重なっていないこと。
##
## 出現の間隔規則(EnemySpawn.Group)を通していない経路があると、敵が縁を食い込ませた
## 状態で湧き、プレイヤーが着く前に勝手に潰し合う。実プレイ(Battle._spawn_enemy)は
## 通しているので、通していない経路で測ると**実プレイに存在しない乱戦**の数字が出る。
## 実際にBattleSimとnaive_playが渡しておらず、乱戦の組の13.1%(段7では21.8%、
## 最大2.44ユニット)が重なっていた。「乱戦は報酬が頭数ぶん増えるのに脅威は増えない」
## という所見が何サイクルも積み残されていた一因がこれ。
##
## 経路が増えても同じ穴が開かないよう、全戦闘に掛ける検査として常設する。
## プレイヤーは対象外: 発射位置は LaunchStandoff が全敵の間合い(半径和より広い)の
## 外へクランプしており、詰み配置での最後の手段(_best_effort)まで含めて
## 重なりゼロを保証してはいないので、ここで拾うと誤報になる。
static func _check_spawn_overlap(request: BattleRequest, violations: Array[String]) -> void:
	for a in request.enemies.size():
		for b in range(a + 1, request.enemies.size()):
			var ea := request.enemies[a]
			var eb := request.enemies[b]
			var gap := ea.position.distance_to(eb.position) - ea.stats.radius - eb.stats.radius
			if gap < 0.0:
				violations.append("敵が重なって出現 enemy[%d]/enemy[%d] (めり込み %.3f)" % [
					a, b, -gap
				])
				return


static func _check_frames(
	request: BattleRequest, frames: Array[BattleResult.Snapshot],
	who: String, violations: Array[String]
) -> void:
	if frames.is_empty():
		violations.append("%s: 軌跡が空" % who)
		return

	var lo := request.arena_bounds.position - Vector2.ONE * ESCAPE_MARGIN
	var hi := request.arena_bounds.end + Vector2.ONE * ESCAPE_MARGIN
	var prev_rps := INF

	for i in frames.size():
		var f := frames[i]

		if not (is_finite(f.position.x) and is_finite(f.position.y)
				and is_finite(f.velocity.x) and is_finite(f.velocity.y)
				and is_finite(f.rps)):
			violations.append("%s: 数値が壊れた (step %d: pos=%s rps=%s)" % [who, i, f.position, f.rps])
			return

		# 落ちたコマ(rps <= lose_threshold)は壁の当たり判定を失い、勢いのまま場外へ
		# 抜けるのが仕様。生きている間だけアリーナ内に収まっていることを確かめる。
		# rpsは増えないので、一度この閾値を割ればそのフレーム以降は全て素通しになる。
		if f.rps > request.lose_threshold:
			if f.position.x < lo.x or f.position.x > hi.x or f.position.y < lo.y or f.position.y > hi.y:
				violations.append("%s: アリーナから脱出 (step %d: %s)" % [who, i, f.position])
				return

		# rpsが増える経路はリゾルバに存在しないはず。増えたら計算が壊れている。
		if f.rps > prev_rps + 1e-4:
			violations.append("%s: rpsが増えた (step %d: %.4f -> %.4f)" % [who, i, prev_rps, f.rps])
			return
		prev_rps = f.rps

		if f.rps < 0.0:
			violations.append("%s: rpsが負 (step %d: %.4f)" % [who, i, f.rps])
			return
