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
## 「要求点に最も近い合法点」を選ぶときの円周サンプル数。フォールバック用の
## _FALLBACK_SAMPLES より細かいのは、あちらが「充足率が最大の一点」を探すのに対し
## こちらは距離を competing させるため、角度の粗さがそのまま退避距離の誤差になるから。
const _NEAREST_SAMPLES := 64
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
## 満たしていればそのまま。踏んでいたら「要求点に最も近い合法点」へ寄せる
## (_nearest_legal)。壁と間合いに挟まれて満たせない詰み配置(小さい土俵の乱戦など)
## では、間合い円上の候補から「最も間合いに近い」点を選ぶ(決定的。それ以上は
## 幾何的に不可能)。
##
## 退避先が「最も近い合法点」であることは手触りの要件でもある(2026-08-01):
## 以前は一番深く踏んでいる敵から順に押し出す反復で、乱戦だと敵Aの押し出し先が
## 敵Bを踏み→Bから押し出し…と玉突きして、要求点と無関係な場所へ収束していた。
## 実測(段1の2体配置)で、左上を狙ったのに土俵の反対側の右下へ5.5ユニット飛ばされ、
## 最近合法点より2.78ユニット余分に退避していた。狙い中はこの位置にコマが表示される
## ので(_on_aim_moved)、これは「1度動かしただけでコマが土俵を横断する」ワープとして
## 見える。最近点なら、狙いを少し動かした時の退避先も少ししか動かない。
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
	if _deepest_violation(p, spawn_points, spawn_radii, player_radius, inradius) < 0:
		return p
	var best: Variant = _nearest_legal(
		p, spawn_points, spawn_radii, player_radius, inradius, wall_clamp
	)
	# 従来の押し出し反復も候補に残す。_nearest_legalの候補は境界の離散サンプルなので、
	# 細い隙間しか合法でない配置を取りこぼしうる。反復が合法点を出せたなら、
	# 近い方を採る=「合法点を見つける力」は従来以上、そのうえで最も近い点になる。
	var pushed := _push_out(
		p, spawn_points, spawn_radii, player_radius, inradius, center, wall_clamp
	)
	if _clearance_score(pushed, spawn_points, spawn_radii, player_radius, inradius) >= 1.0 - _EPS:
		if best == null or pushed.distance_squared_to(p) < (best as Vector2).distance_squared_to(p) - _EPS:
			best = pushed
	if best != null:
		return best
	return _best_effort(p, spawn_points, spawn_radii, player_radius, inradius, wall_clamp)


## 一番深く踏み込んでいる敵から順に押し出し→壁寄せを繰り返す従来の解法。
## 合法点に着くとは限らない(乱戦では玉突きして収束しないことがある)。
static func _push_out(
	pos: Vector2,
	spawn_points: PackedVector2Array,
	spawn_radii: PackedFloat32Array,
	player_radius: float,
	inradius: float,
	center: Vector2,
	wall_clamp: Callable
) -> Vector2:
	var p := pos
	for i in _PUSH_ITERS:
		var worst := _deepest_violation(p, spawn_points, spawn_radii, player_radius, inradius)
		if worst < 0:
			return p
		var req := required_distance(player_radius, spawn_radii[worst], inradius)
		var away := p - spawn_points[worst]
		# 出現点に重なっている(向きが決められない)ときは中心側へ逃がす。
		var dir := (away.normalized() if away.length() > _EPS
			else _inward_dir(spawn_points[worst], center))
		p = wall_clamp.call(spawn_points[worst] + dir * (req + _NUDGE))
	return p


## 全ての間合いを満たす点のうち target に最も近いものを返す。無ければ null。
##
## 候補は「合法領域(円板の外側の共通部分∩壁の内側)の境界上で最近点になりうる点」を
## 決定的に並べる: (a)各間合い円へのtargetの放射投影(敵が1体ならこれが厳密な最近点)、
## (b)各円周の等間隔サンプル(他の敵や壁に(a)が潰された場合の受け皿)。
## いずれも壁クランプを通すとまた間合いを割ることがあるので、採用前に必ず再判定する。
static func _nearest_legal(
	target: Vector2,
	spawn_points: PackedVector2Array,
	spawn_radii: PackedFloat32Array,
	player_radius: float,
	inradius: float,
	wall_clamp: Callable
) -> Variant:
	var best: Variant = null
	var best_d := INF
	for c in _boundary_candidates(target, spawn_points, spawn_radii, player_radius, inradius):
		var p: Vector2 = wall_clamp.call(c)
		# 壁クランプで間合いへ押し戻された候補は不合格。
		if _clearance_score(p, spawn_points, spawn_radii, player_radius, inradius) < 1.0 - _EPS:
			continue
		var d := p.distance_squared_to(target)
		if d < best_d - _EPS:
			best_d = d
			best = p
	return best


## _nearest_legalが調べる候補点(壁クランプ前)。
static func _boundary_candidates(
	target: Vector2,
	spawn_points: PackedVector2Array,
	spawn_radii: PackedFloat32Array,
	player_radius: float,
	inradius: float
) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in spawn_points.size():
		var req := required_distance(player_radius, spawn_radii[i], inradius)
		if req <= _EPS:
			continue
		var reach := req + _NUDGE
		var away := target - spawn_points[i]
		if away.length() > _EPS:
			out.append(spawn_points[i] + away.normalized() * reach)
		for k in _NEAREST_SAMPLES:
			var dir := Vector2.RIGHT.rotated(float(k) / float(_NEAREST_SAMPLES) * TAU)
			out.append(spawn_points[i] + dir * reach)
	return out


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
