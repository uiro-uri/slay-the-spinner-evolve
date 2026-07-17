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
				CENTER, RING, enemy.launch_speed, 30.0, rng, radius, 5.0
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
func _test_telegraph_visible(check: Callable) -> void:
	# 三角形の頂点はコマの中心にあるので、コマの縁より外へこれだけ出ていないと
	# 見えたことにならない。ボスは半径3.0とアリーナに対してかなり大きいので、
	# 「半径の何倍」ではなく「縁からの実距離」で見る。
	const MIN_MARGIN := 0.5
	var telegraph := EnemyTelegraph.new()
	var worst := INF
	var worst_name := ""

	for enemy in EnemyRoster.all():
		telegraph.show_plan(Vector2(5, 1), Vector2.DOWN * enemy.launch_speed)
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

	# 速い敵ほど長い（強さが見た目で分かる）
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
