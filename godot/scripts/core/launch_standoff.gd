class_name LaunchStandoff
extends RefCounted

## 発射位置と敵の出現予告の「立ち合いの間合い」。
##
## 発射位置は土俵の中で自由に選べるが、予告された敵の真横にコマを置いて
## 全力で殴る「至近スポーン殴り」は、敵が1ユニットも動かないうちに初撃が
## 確定するため、予告の進路・速度を読んで狙う工程がまるごと不要になる
## (2026-07-22のコールドプレイで9戦中7戦がこれで決まり、ボスも初見6.5秒)。
##
## そこで発射位置は各敵の出現予告から最小距離(間合い)以上離す。間合いの
## 外から出現点や進路の先を狙うのは今までどおり自由で、当てにいくプレイ
## 自体は罰しない。相撲の立ち合いと同じで、離れて向き合ってから始める。
##
## 純粋な静的関数のみ。実UI(Battle)・CLI(naive_play)・bot(LaunchPolicy)の
## 3経路が同じ関数を通る(発射速度のLaunchSpeedと同じ扱い)。

## 縁と縁の間の最低自由距離(ユニット)。全力発射(速度12)でこの距離を詰める
## 約0.17秒の間に、敵は自分の直径ほど動く=出現点をなぞるだけでは掠り、
## 進路を先読みした点を狙う必要が生まれる、を狙った値。
const GAP := 2.0

const _EPS := 0.001
const _PUSH_ITERS := 8
const _FALLBACK_SAMPLES := 32
## 押し出し先に足す微小マージン。間合いちょうどに置くと、後段の壁クランプの
## わずかな寄せで間合いを浮動小数分だけ割ることがある。
const _NUDGE := 0.02


## 間合い: プレイヤー中心と敵出現中心の必要距離。縁の自由距離GAPは一定なので、
## コマが大きいほど中心距離は伸びる。上限は inradius - player_radius:
## 「出現点の反対側の壁際」には必ず置ける距離で、巨体同士では間合いが
## 接触距離を割って実質無効になる(巨体はどのみち接触を避けられない)。
static func required_distance(player_radius: float, enemy_radius: float, inradius: float) -> float:
	return maxf(minf(player_radius + enemy_radius + GAP, inradius - player_radius), 0.0)


## posを「壁の内側 かつ 全ての敵予告から間合い以上」へ寄せる。
## wall_clampは土俵の内側クランプ(Vector2->Vector2)。呼び出し側の壁形状
## (矩形/内接円)をそのまま使うため、関数で受け取る。
##
## 一番深く踏み込んでいる敵から順に押し出し→壁寄せを繰り返す。壁と間合いに
## 挟まれて満たせない詰み配置(小さい土俵の乱戦など)では、間合い円上の候補から
## 「最も間合いに近い」点を選ぶ(決定的。それ以上は幾何的に不可能)。
static func clamp_away(
	pos: Vector2,
	spawn_points: PackedVector2Array,
	spawn_radii: PackedFloat32Array,
	player_radius: float,
	inradius: float,
	center: Vector2,
	wall_clamp: Callable
) -> Vector2:
	var p: Vector2 = wall_clamp.call(pos)
	if spawn_points.is_empty():
		return p
	for i in _PUSH_ITERS:
		var worst := _deepest_violation(p, spawn_points, spawn_radii, player_radius, inradius)
		if worst < 0:
			return p
		var req := required_distance(player_radius, spawn_radii[worst], inradius)
		var away := p - spawn_points[worst]
		# 出現点に重なっている(向きが決められない)ときは中心側へ逃がす。
		var dir := away.normalized() if away.length() > _EPS else _inward_dir(spawn_points[worst], center)
		p = wall_clamp.call(spawn_points[worst] + dir * (req + _NUDGE))
	return _best_effort(p, spawn_points, spawn_radii, player_radius, inradius, wall_clamp)


## 間合いを一番深く割っている敵のindex。どの敵も満たしていれば-1。
static func _deepest_violation(
	p: Vector2,
	spawn_points: PackedVector2Array,
	spawn_radii: PackedFloat32Array,
	player_radius: float,
	inradius: float
) -> int:
	var worst := -1
	var worst_ratio := 1.0
	for i in spawn_points.size():
		var req := required_distance(player_radius, spawn_radii[i], inradius)
		if req <= _EPS:
			continue
		var ratio := (p.distance_to(spawn_points[i]) + _EPS) / req
		if ratio < worst_ratio:
			worst_ratio = ratio
			worst = i
	return worst


## 全敵に対する間合いの充足率(最小の 距離/間合い)。1.0以上なら全て満たしている。
static func _clearance_score(
	p: Vector2,
	spawn_points: PackedVector2Array,
	spawn_radii: PackedFloat32Array,
	player_radius: float,
	inradius: float
) -> float:
	var score := INF
	for i in spawn_points.size():
		var req := required_distance(player_radius, spawn_radii[i], inradius)
		if req <= _EPS:
			continue
		score = minf(score, p.distance_to(spawn_points[i]) / req)
	return score


## 押し出しの反復で満たせなかったときの決定的フォールバック。各敵の間合い円上を
## 等間隔にサンプルして壁へ寄せ、充足率が最大の候補を返す。幾何的に満たせる点が
## あれば(サンプル密度の範囲で)見つかり、真の詰みでは一番マシな点になる。
static func _best_effort(
	current: Vector2,
	spawn_points: PackedVector2Array,
	spawn_radii: PackedFloat32Array,
	player_radius: float,
	inradius: float,
	wall_clamp: Callable
) -> Vector2:
	var best := current
	var best_score := _clearance_score(current, spawn_points, spawn_radii, player_radius, inradius)
	for i in spawn_points.size():
		var req := required_distance(player_radius, spawn_radii[i], inradius)
		if req <= _EPS:
			continue
		for k in _FALLBACK_SAMPLES:
			var dir := Vector2.RIGHT.rotated(float(k) / float(_FALLBACK_SAMPLES) * TAU)
			var candidate: Vector2 = wall_clamp.call(spawn_points[i] + dir * (req + _NUDGE))
			var score := _clearance_score(candidate, spawn_points, spawn_radii, player_radius, inradius)
			if score > best_score + _EPS:
				best_score = score
				best = candidate
	return best


static func _inward_dir(from: Vector2, center: Vector2) -> Vector2:
	var d := center - from
	return d.normalized() if d.length() > _EPS else Vector2.RIGHT
