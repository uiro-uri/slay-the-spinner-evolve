extends RefCounted

## enemy_spawn.gd / aim_triangle.gd のテスト。
##
## ランダムなので特定の値は期待できない。何度まわしても成り立つべき性質だけ見る。

const TRIALS := 300
const EPS := 1e-4

const CENTER := Vector2(5, 5)
const RING := 4.0
const SPEED := 6.0


func run(check: Callable) -> void:
	_test_spawn_on_ring(check)
	_test_aims_near_center(check)
	_test_spread_zero_aims_exactly_center(check)
	_test_varies(check)
	_test_deterministic_with_seed(check)
	_test_aim_triangle(check)
	_test_telegraph_visible(check)
	_test_fits_inside_arena(check)
	_test_avoids_keepout(check)
	_test_avoids_obstacles(check)
	_test_group_spacing(check)
	_test_battle_wires_group(check)


## 発射前の初期表示が重ならないよう、avoidに渡した点からmin_gap以上離れて出ること。
##
## プレイヤーが出現リングのすぐ上に静止していると、ランダムな角度次第で敵がその上に
## 出て見た目が重なる。avoid/min_gapを渡すと、そこを避けた角度を選び直す。
func _test_avoids_keepout(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()

	# リング上のある一点を避け所にする。そこからmin_gap以内には出ないこと。
	var keepout := CENTER + Vector2.RIGHT.rotated(2.3) * RING
	var min_gap := 1.5
	var avoid: Array[Vector2] = [keepout]
	var worst := INF
	for trial in TRIALS:
		rng.seed = trial
		var plan := EnemySpawn.plan(CENTER, RING, SPEED, 30.0, rng, 0.0, 5.0, avoid, min_gap)
		worst = minf(worst, plan.position.distance_to(keepout))
	check.call(
		worst >= min_gap - EPS,
		"敵の出現: 除け所からmin_gap以上離れて出る (最小距離 %.3f >= %.2f)" % [worst, min_gap]
	)

	# avoidが空なら従来どおり初回の角度が出る(後方互換で決定性が変わらない)。
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 7
	var plain := EnemySpawn.plan(CENTER, RING, SPEED, 30.0, rng_a)
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 7
	var empty := EnemySpawn.plan(CENTER, RING, SPEED, 30.0, rng_b, 0.0, 5.0, [], 1.5)
	check.call(
		plain.position.is_equal_approx(empty.position),
		"敵の出現: 除け所が無ければ従来と同じ結果(後方互換)"
	)


## EnemySpawn.Group を通して湧かせた乱戦は、敵同士が重ならないこと。
##
## 間隔の規則を3経路(Battle・BattleSim・naive_play)で1つにまとめた本体。
## かつてはボット/CLIがavoid/min_gapを渡しておらず、乱戦の組の13.1%が縁を
## 食い込ませて湧いて、発射前に勝手に潰し合っていた。
##
## 実ロスターの実寸(Lv1〜4の半径・最大3体)で回して、縁がclearanceぶん空くことを見る。
func _test_group_spacing(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	var clearance := EnemySpawn.Group.DEFAULT_CLEARANCE
	var worst := INF
	var trials := 0
	for trial in TRIALS:
		rng.seed = 1000 + trial
		var level := 1 + (trial % 4)
		var pool := EnemyRoster.of_level(level)
		var count := 2 + (trial % 2)
		var group := EnemySpawn.Group.new(clearance)
		var placed: Array[Vector2] = []
		var radii: Array[float] = []
		for i in count:
			var enemy: EnemyData = pool[rng.randi_range(0, pool.size() - 1)]
			var r: float = enemy.stats.radius
			var plan := EnemySpawn.plan(
				CENTER, RING, SPEED, 30.0, rng, r, 5.0,
				group.avoid(), group.min_gap(r), []
			)
			group.add(plan.position, r)
			placed.append(plan.position)
			radii.append(r)
		for a in placed.size():
			for b in range(a + 1, placed.size()):
				worst = minf(worst, placed[a].distance_to(placed[b]) - radii[a] - radii[b])
				trials += 1
	check.call(
		worst >= clearance - EPS,
		"乱戦の出現: 敵同士の縁が%.2f以上空く (%d組の最小 %.3f)" % [clearance, trials, worst]
	)

	# 1体目には制約が無い＝単体戦はplan()の速い道(1回引くだけ)を従来どおり通る。
	var solo := EnemySpawn.Group.new(clearance)
	check.call(
		solo.min_gap(1.0) == 0.0 and solo.avoid().is_empty(),
		"乱戦の出現: 1体目は無制約(単体戦の決定性が変わらない)"
	)


## 実プレイ(Battle.gd)が出現を EnemySpawn.Group で配線していること(退行検知)。
##
## Battle.gd はシーンスクリプトでヘッドレスから直接は回せないので、ボット/CLIのように
## 出現を回して確かめられない。実際に間隔規則を渡し忘れて何サイクルも気づかれなかった
## のがボット/CLI側だったので、**3経路のうち唯一テストの目が届かない実プレイ側**にも
## 同じ穴が開かないよう、ソースの配線を見る。
func _test_battle_wires_group(check: Callable) -> void:
	var source := FileAccess.get_file_as_string("res://scenes/battle/Battle.gd")
	check.call(
		source.contains("EnemySpawn.Group.new("),
		"Battle.gdが出現の間隔をEnemySpawn.Groupで組む"
	)
	check.call(
		source.contains("group.avoid()") and source.contains("group.min_gap("),
		"Battle.gdが間隔をEnemySpawn.plan()へ渡す"
	)


## 柱(障害物)に重なった出現をしないこと。大きいコマはリングが内側へ寄って
## (effective_ring)柱の真上を通ることがあり、めり込んで出現すると毎ステップ
## 柱に弾かれて接触ゼロのまま自滅する(2026-07-29のコールドプレイで実測:
## ENEMY_3_3が柱(3,3)に0.32めり込んで出現し、13回弾かれて接触0回で死んだ)。
func _test_avoids_obstacles(check: Callable) -> void:
	# PILLARS土俵と同じ柱。半径0.89の敵はリング上の対角付近で柱に重なる。
	var obstacles: Array[Vector3] = [Vector3(3, 3, 0.6), Vector3(7, 7, 0.6)]
	var radius := 0.89
	var rng := RandomNumberGenerator.new()
	var worst := INF
	for trial in TRIALS:
		rng.seed = trial
		var plan := EnemySpawn.plan(
			CENTER, RING, SPEED, 30.0, rng, radius, 5.0, [], 0.0, obstacles)
		for o in obstacles:
			worst = minf(worst, plan.position.distance_to(Vector2(o.x, o.y)) - (o.z + radius))
	check.call(
		worst >= -EPS,
		"敵の出現: 柱に重ならない (最小余白 %.3f)" % worst
	)

	# 再現バグの実例: bseed=10103のENEMY_3_3は柱(3,3)にめり込んで出ていた。
	var rng_bug := RandomNumberGenerator.new()
	rng_bug.seed = 10103
	LaunchSpeed.random(rng_bug)  # naive_playと同じ消費順(速度→角度)
	var fixed := EnemySpawn.plan(
		CENTER, RING, SPEED, 30.0, rng_bug, radius, 5.0, [], 0.0, obstacles)
	var bug_clear := true
	for o in obstacles:
		if fixed.position.distance_to(Vector2(o.x, o.y)) < o.z + radius - EPS:
			bug_clear = false
	check.call(bug_clear, "敵の出現: 2026-07-29の再現ケースが柱を避ける")

	# 柱を渡しても、最初の角度が柱を避けているなら結果は柱なしと同じ
	# (余計なRNG消費をしない=既存bseedの出現をむやみに変えない)。
	var seed_clear := -1
	for trial in TRIALS:
		var rng_a := RandomNumberGenerator.new()
		rng_a.seed = trial
		var plain := EnemySpawn.plan(CENTER, RING, SPEED, 30.0, rng_a, radius, 5.0)
		var ok := true
		for o in obstacles:
			if plain.position.distance_to(Vector2(o.x, o.y)) < o.z + radius:
				ok = false
		if ok:
			seed_clear = trial
			break
	if seed_clear >= 0:
		var rng_b := RandomNumberGenerator.new()
		rng_b.seed = seed_clear
		var plain_again := EnemySpawn.plan(CENTER, RING, SPEED, 30.0, rng_b, radius, 5.0)
		var rng_c := RandomNumberGenerator.new()
		rng_c.seed = seed_clear
		var with_obs := EnemySpawn.plan(
			CENTER, RING, SPEED, 30.0, rng_c, radius, 5.0, [], 0.0, obstacles)
		check.call(
			plain_again.position.is_equal_approx(with_obs.position)
				and plain_again.velocity.is_equal_approx(with_obs.velocity),
			"敵の出現: 柱を避けた初回角度は柱なしと同じ結果(後方互換)"
		)

	# 同じシード+同じ柱なら同じ結果(決定性)
	var rng_d := RandomNumberGenerator.new()
	rng_d.seed = 42
	var a := EnemySpawn.plan(CENTER, RING, SPEED, 30.0, rng_d, radius, 5.0, [], 0.0, obstacles)
	var rng_e := RandomNumberGenerator.new()
	rng_e.seed = 42
	var b := EnemySpawn.plan(CENTER, RING, SPEED, 30.0, rng_e, radius, 5.0, [], 0.0, obstacles)
	check.call(
		a.position.is_equal_approx(b.position) and a.velocity.is_equal_approx(b.velocity),
		"敵の出現: 柱つきでも同じシードなら同じ結果"
	)


## どの敵もコマ全体がアリーナに収まった状態で出ること。
##
## ボスは半径3.0でアリーナ(10x10)に対してかなり大きい。出現半径をそのまま
## 使うと壁にめり込んだ状態で始まる。速度が中心向きなので壁の反射判定には
## 引っかからず、半分外に出たまま始まる絵になる。
func _test_fits_inside_arena(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	var worst := INF
	var worst_name := ""

	for enemy in EnemyRoster.all():
		var radius: float = enemy.stats.radius
		for trial in 50:
			rng.seed = trial
			var plan := EnemySpawn.plan(
				CENTER, RING, LaunchSpeed.MAX, 30.0, rng, radius, 5.0
			)
			# 一番壁に近い縁が、アリーナ(0..10)の内側にあること
			var margin := minf(
				minf(plan.position.x - radius, plan.position.y - radius),
				minf(10.0 - plan.position.x - radius, 10.0 - plan.position.y - radius)
			)
			if margin < worst:
				worst = margin
				worst_name = "%s(半径%.1f)" % [enemy.display_name, radius]

	check.call(
		worst >= -EPS,
		"敵の出現: どの敵もコマ全体がアリーナに収まる (最小余裕 %.2f: %s)" % [worst, worst_name]
	)


## 予告の三角形が敵のコマの下に隠れないこと。
##
## 三角形の頂点はコマの中心にあるので、長さがコマの半径以下だと全部隠れて
## 何も見えない。最初に速度比例で書いたときは長さ1.0に対しコマの半径0.5で、
## 実際に半分が隠れて画面上で87pxしか出ていなかった。スクショを目で見ても
## 気づけなかったので、数値で押さえる。
##
## 発射速度は自機と共通のレンジ(LaunchSpeed)から出現ごとに抽選し、下限は0まで下がる。
## 予告長は初速に比例する(AimTriangle.length_for_speed)ので**速度0**が最悪ケース。そこでも
## 隠れないよう、EnemyTelegraphは readable_radius+min_length_margin を最小可視長にする。
## Battleが出現時に readable_radius=disc.stats.radius を入れるのと同じ状態で、速度0でも
## どの敵の予告もコマの縁より外に出ることを確かめる。min_length_marginを削るとここが落ちる。
func _test_telegraph_visible(check: Callable) -> void:
	# 三角形の頂点はコマの中心にあるので、コマの縁より外へこれだけ出ていないと
	# 見えたことにならない。ボスは半径3.0とアリーナに対してかなり大きいので、
	# 「半径の何倍」ではなく「縁からの実距離」で見る。
	const MIN_MARGIN := 0.5
	var telegraph := EnemyTelegraph.new()
	var worst := INF
	var worst_name := ""

	for enemy in EnemyRoster.all():
		# Battle._spawn_enemyと同じく、このコマの半径を最小可視長の基準に渡す。
		telegraph.readable_radius = enemy.stats.radius
		# 最悪ケース=速度0(予告長が生の式では0になる)でも隠れないこと。
		telegraph.show_plan(Vector2(5, 1), Vector2.DOWN * LaunchSpeed.MIN)
		var length := telegraph.telegraph_length()
		var margin: float = length - enemy.stats.radius
		if margin < worst:
			worst = margin
			worst_name = "%s(Lv%d, 半径%.1f, 長さ%.2f)" % [
				enemy.display_name, enemy.level, enemy.stats.radius, length
			]
		# アリーナ(10x10)を突き抜けない
		check.call(
			length < MapTree.COLUMN_COUNT + 1,
			"敵の予告: %s がアリーナを突き抜けない (長さ %.2f)" % [enemy.display_name, length]
		)

	check.call(
		worst > MIN_MARGIN,
		"敵の予告: どの敵でもコマの縁より外に出る (最小 %.2f: %s)" % [worst, worst_name]
	)

	# 速い敵ほど長い（強さが見た目で分かる）。生の長さを見たいので最小可視長は無効化。
	telegraph.readable_radius = 0.0
	telegraph.min_length_margin = 0.0
	telegraph.show_plan(Vector2.ZERO, Vector2.DOWN * 2.2)
	var slow := telegraph.telegraph_length()
	telegraph.show_plan(Vector2.ZERO, Vector2.DOWN * 14.1)
	var fast := telegraph.telegraph_length()
	check.call(fast > slow, "敵の予告: 速い敵ほど長い (%.2f > %.2f)" % [fast, slow])
	telegraph.free()


func _test_spawn_on_ring(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	var worst := 0.0
	for trial in TRIALS:
		rng.seed = trial
		var plan := EnemySpawn.plan(CENTER, RING, SPEED, 30.0, rng)
		worst = maxf(worst, absf(plan.position.distance_to(CENTER) - RING))
	check.call(worst < EPS, "敵の出現: 常に中心から%.1fの円周上 (最大ずれ %.5f)" % [RING, worst])


func _test_aims_near_center(check: Callable) -> void:
	# 中心方向±spread以内を向くこと。外周を回るだけで終わらないための条件。
	var rng := RandomNumberGenerator.new()
	var spread := 30.0
	var worst := 0.0
	for trial in TRIALS:
		rng.seed = trial
		var plan := EnemySpawn.plan(CENTER, RING, SPEED, spread, rng)
		var toward_center := (CENTER - plan.position).normalized()
		var off := rad_to_deg(absf(toward_center.angle_to(plan.velocity.normalized())))
		worst = maxf(worst, off)
	check.call(
		worst <= spread + 0.01,
		"敵の狙い: 中心方向から±%.0f度以内 (最大 %.2f度)" % [spread, worst]
	)


func _test_spread_zero_aims_exactly_center(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var plan := EnemySpawn.plan(CENTER, RING, SPEED, 0.0, rng)
	var toward_center := (CENTER - plan.position).normalized()
	check.call(
		toward_center.distance_to(plan.velocity.normalized()) < EPS,
		"敵の狙い: ぶれ0なら真っ直ぐ中心へ"
	)
	check.call(
		absf(plan.velocity.length() - SPEED) < EPS,
		"敵の速度: 指定した速さになる (%.3f)" % plan.velocity.length()
	)


func _test_varies(check: Callable) -> void:
	# 毎回同じ場所に出たら意味がない
	var rng := RandomNumberGenerator.new()
	var seen := {}
	for trial in TRIALS:
		rng.seed = trial
		var plan := EnemySpawn.plan(CENTER, RING, SPEED, 30.0, rng)
		seen["%.1f,%.1f" % [plan.position.x, plan.position.y]] = true
	check.call(seen.size() > TRIALS / 4, "敵の出現: 毎回ばらける (%d通り/%d回)" % [seen.size(), TRIALS])


func _test_deterministic_with_seed(check: Callable) -> void:
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 42
	var a := EnemySpawn.plan(CENTER, RING, SPEED, 30.0, rng_a)
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 42
	var b := EnemySpawn.plan(CENTER, RING, SPEED, 30.0, rng_b)
	check.call(
		a.position.is_equal_approx(b.position) and a.velocity.is_equal_approx(b.velocity),
		"敵の出現: 同じシードなら同じ結果(再現できる)"
	)


func _test_aim_triangle(check: Callable) -> void:
	# 頂点が発射地点にあること。ここにコマを置くので、ずれると嘘になる。
	var origin := Vector2(2, 8)
	var points := AimTriangle.points(origin, Vector2(1, -1), 3.0)
	check.call(points.size() == 3, "狙いの三角形: 3頂点 (%d)" % points.size())
	check.call(points[0].is_equal_approx(origin), "狙いの三角形: 頂点が発射地点 (%s)" % points[0])

	# 底辺は飛んでいく向きの反対側にある
	var direction := Vector2(1, -1).normalized()
	var base_mid: Vector2 = (points[1] + points[2]) * 0.5
	check.call(
		(base_mid - origin).normalized().dot(direction) < -0.99,
		"狙いの三角形: 底辺は飛ぶ向きの反対側 (%s)" % base_mid
	)
	check.call(
		absf(base_mid.distance_to(origin) - 3.0) < EPS,
		"狙いの三角形: 長さが指定どおり (%.3f)" % base_mid.distance_to(origin)
	)

	# 向きがゼロなら描かない(0除算しない)
	check.call(
		AimTriangle.points(origin, Vector2.ZERO, 3.0).is_empty(),
		"狙いの三角形: 向きがゼロなら空"
	)
	check.call(
		AimTriangle.points(origin, Vector2(1, 0), 0.0).is_empty(),
		"狙いの三角形: 長さがゼロなら空"
	)
