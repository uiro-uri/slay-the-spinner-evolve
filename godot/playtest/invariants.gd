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

	for impact in result.impacts:
		if impact.time < 0.0 or impact.time > result.finish_time + request.time_step:
			violations.append("衝突時刻が戦闘の外 (%.3f / 決着 %.3f)" % [
				impact.time, result.finish_time
			])
			break

	return violations


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
