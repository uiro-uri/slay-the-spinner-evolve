class_name EnemySpawn
extends RefCounted

## 敵がどこに出て、どこへ飛ぶかを決める。
##
## プロトタイプでは全敵が中央(5,5)から一律に(3,4)で発射されていた。
## ENEMY_LISTにも位置と速度が入っていたが、app.pyはinitial_conditionsの
## 固定値を使っており一度も読まれていない死んだデータだった。毎回同じでは
## 戦いが単調なので、位置と向きをランダムにする。
##
## ただし完全なランダムでは対処のしようがないので、決まった内容は
## EnemyTelegraphが赤い三角形で予告する（プレイヤーの狙いと同じ意匠）。
## 「ランダムだが読める」状態にするのが狙い。
##
## Nodeに依存しない純粋な計算なので、ヘッドレスから直接テストできる。


## 決まった出現内容。
class Plan:
	extends RefCounted

	var position: Vector2
	var velocity: Vector2

	func _init(pos: Vector2, vel: Vector2) -> void:
		position = pos
		velocity = vel


## 乱戦(複数体)の出現を、重ならないように順に決めるための積み上げ器。
##
## plan()のavoid/min_gapに何を渡すかという「間隔の規則」は3経路
## (実プレイのBattle._spawn_enemy・ボットのBattleSim・CLIのnaive_play)が
## 踏むべきものなのに、それぞれが直接plan()を呼んでいて、実際に渡していたのは
## 実プレイだけだった。ボット/CLIでは敵同士が縁を食い込ませた状態で湧き、
## 発射前に勝手に潰し合う。measure_spawn_gap.gd で数えると乱戦の組の**13.1%**が
## 重なり(段7では21.8%、最大2.44ユニットめり込み)、実プレイ経路は0.0%だった。
## docs/playtest.md が「実プレイとずれると存在しない条件で測ることになって
## 数字だけが嘘になる」と警告しているまさにその状態で、乱戦は「報酬は頭数ぶん
## 増えるのに脅威は増えない部屋」として測られ続けていた(2026-08-02の
## コールドプレイでも、段2の3体戦で2体が0.25秒で自壊して報酬3枚が転がり込んだ)。
##
## 規則をここに1つだけ置いて、3経路が同じものを通るようにする。
class Group:
	extends RefCounted

	## 縁同士に空けたい距離。Battle.gdのspawn_clearance既定値と同じ。
	const DEFAULT_CLEARANCE := 0.6

	var clearance: float

	var _placed: Array[Vector2] = []
	var _widest := 0.0

	func _init(clearance_: float = DEFAULT_CLEARANCE) -> void:
		clearance = clearance_

	## 既に決まっている出現位置。plan()のavoidにそのまま渡す。
	func avoid() -> Array[Vector2]:
		return _placed

	## 半径radiusのコマを次に置くときのmin_gap。相手半径は既出の最大で見積もる
	## (どの相手とも縁がclearanceだけ空く)。まだ誰も居なければ制約なし＝0.0を返し、
	## plan()の速い道(1回引くだけ)がそのまま通る＝単体戦は従来と厳密に同じ。
	func min_gap(radius: float) -> float:
		if _placed.is_empty():
			return 0.0
		return _widest + radius + clearance

	## 決まった位置を控える。次の1体はここを避ける。
	## 敵だけでなく、発射前のプレイヤーの位置を先に入れてもよい(実プレイがそうする)。
	func add(position: Vector2, radius: float) -> void:
		_placed.append(position)
		_widest = maxf(_widest, radius)


## 中心からring_radiusだけ離れた円周上のランダムな一点に出現し、
## 中心方向 ± spread_deg の範囲へ speed で発射する。
##
## 中心を狙わせるのは、そうしないと敵がプレイヤーと出会わないまま
## 外周を回って終わることがあるため。spread_degで読みにくさを調整する。
##
## radiusはコマの半径。大きいコマがring_radiusのまま外周に出ると壁に
## めり込むので、アリーナに収まるところまで内側へ寄せる。ボスは半径3.0と
## アリーナ(10x10)に対してかなり大きく、寄せないと半分が壁の外に出る。
##
## avoid/min_gapは発射前の表示が重ならないための除け所。プレイヤーの初期位置や
## 既に決めた敵の位置をavoidに渡すと、そこからmin_gap以上離れたリング上の点を
## 選び直す(角度だけを棄却サンプリング、半径は変えない)。空なら初回の角度が
## そのまま通るので既存の挙動・決定性は不変。
##
## obstaclesは土俵の柱(FieldData.obstacles、xy=中心・z=半径)。コマ全体
## (radiusぶん)が柱に重ならない角度を選ぶ。大きいコマはリングが内側へ寄って
## (effective_ring)柱の真上を通ることがあり、めり込んで出現すると毎ステップ
## 柱に弾かれ続けて接触ゼロのまま自滅する(コールドプレイ2026-07-29で実測)。
static func plan(
	center: Vector2,
	ring_radius: float,
	speed: float,
	spread_deg: float,
	rng: RandomNumberGenerator,
	radius: float = 0.0,
	arena_half_size: float = 5.0,
	avoid: Array[Vector2] = [],
	min_gap: float = 0.0,
	obstacles: Array[Vector3] = []
) -> Plan:
	var max_ring := maxf(arena_half_size - radius, 0.0)
	var effective_ring := minf(ring_radius, max_ring)

	var angle := _pick_angle(rng, center, effective_ring, avoid, min_gap, radius, obstacles)
	var position := center + Vector2.RIGHT.rotated(angle) * effective_ring

	var toward_center := (center - position).normalized()
	var spread := deg_to_rad(rng.randf_range(-spread_deg, spread_deg))
	return Plan.new(position, toward_center.rotated(spread) * speed)


## リング上の角度を選ぶ。除け所も柱も無ければ1回引くだけ(従来どおり)。
## あるときは、全avoid点からmin_gap以上・全柱から(柱半径+コマ半径)以上離れた
## 角度が出るまで最大K回引き直す。どれも満たせなければ、試した中で「一番
## 食い込みが浅い」角度を返す(余白margin=距離-必要距離の最小値が最大の角度)。
## avoidだけの場合、marginは従来のclearanceからmin_gapを引いただけなので
## 採否・優先順位とも従来と厳密に一致する(後方互換)。
static func _pick_angle(
	rng: RandomNumberGenerator,
	center: Vector2,
	effective_ring: float,
	avoid: Array[Vector2],
	min_gap: float,
	radius: float,
	obstacles: Array[Vector3]
) -> float:
	var angle := rng.randf_range(0.0, TAU)
	if (avoid.is_empty() or min_gap <= 0.0) and obstacles.is_empty():
		return angle

	const K := 24
	var best_angle := angle
	var best_margin := -INF
	for i in K:
		var pos := center + Vector2.RIGHT.rotated(angle) * effective_ring
		var margin := INF
		if min_gap > 0.0:
			for p in avoid:
				margin = minf(margin, pos.distance_to(p) - min_gap)
		for o in obstacles:
			margin = minf(margin, pos.distance_to(Vector2(o.x, o.y)) - (o.z + radius))
		if margin >= 0.0:
			return angle
		if margin > best_margin:
			best_margin = margin
			best_angle = angle
		angle = rng.randf_range(0.0, TAU)
	return best_angle
