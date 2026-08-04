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
	_test_group_swirl(check)
	_test_swirl_turns_the_aim(check)
	_test_swirl_aligns_the_group(check)
	_test_battle_wires_swirl(check)


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


## 乱戦の回り込み角(group_swirl_deg)の決まり方。
##
## 一番大事なのは**単体戦では0を返し、rngを1つも引かない**こと。引いてしまうと
## 以後の出現(速度→角度)が全部ずれて、単体戦の既存シードの再現が壊れる。
func _test_group_swirl(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()

	# 単体戦は0。しかも乱数を消費しない(消費すると単体戦の出現が変わってしまう)。
	rng.seed = 7
	var before := rng.randi()
	rng.seed = 7
	check.call(
		EnemySpawn.group_swirl_deg(1, 25.0, rng) == 0.0 and rng.randi() == before,
		"回り込み: 単体戦は0で、乱数も引かない"
	)

	# 0度指定(＝機構オフ)も同じく無消費。
	rng.seed = 7
	check.call(
		EnemySpawn.group_swirl_deg(3, 0.0, rng) == 0.0 and rng.randi() == before,
		"回り込み: 0度指定は乱数も引かない(導入前と厳密に同じ)"
	)

	# 乱戦は ±swirl_deg のどちらか。両方の符号が出ること(片側に固定されていない)。
	var plus := 0
	var minus := 0
	var off_value := 0
	for trial in TRIALS:
		rng.seed = trial
		var swirl := EnemySpawn.group_swirl_deg(2, 25.0, rng)
		if absf(absf(swirl) - 25.0) >= EPS:
			off_value += 1
		elif swirl > 0.0:
			plus += 1
		else:
			minus += 1
	check.call(off_value == 0, "回り込み: 乱戦は必ず±指定値ちょうど (%d件はずれ)" % off_value)
	check.call(
		plus > 0 and minus > 0,
		"回り込み: 向きは両方出る (+%d / -%d)" % [plus, minus]
	)


## plan() の swirl_deg が狙いをその角度ぶんだけ回すこと。
## 0なら乱数列も結果も導入前と厳密に一致すること(単体戦の後方互換の要)。
func _test_swirl_turns_the_aim(check: Callable) -> void:
	var worst := 0.0
	var same := true
	for trial in TRIALS:
		var rng_a := RandomNumberGenerator.new()
		rng_a.seed = trial
		var plain := EnemySpawn.plan(CENTER, RING, SPEED, 30.0, rng_a)
		var rng_b := RandomNumberGenerator.new()
		rng_b.seed = trial
		var zero := EnemySpawn.plan(CENTER, RING, SPEED, 30.0, rng_b, 0.0, 5.0, [], 0.0, [], 0.0)
		if not (plain.position.is_equal_approx(zero.position)
				and plain.velocity.is_equal_approx(zero.velocity)):
			same = false
		var rng_c := RandomNumberGenerator.new()
		rng_c.seed = trial
		var turned := EnemySpawn.plan(CENTER, RING, SPEED, 30.0, rng_c, 0.0, 5.0, [], 0.0, [], 25.0)
		# 位置は変わらず(角度の抽選は同じ)、速度だけがちょうど25度回っている。
		if not turned.position.is_equal_approx(plain.position):
			same = false
		worst = maxf(worst, absf(rad_to_deg(plain.velocity.angle_to(turned.velocity)) - 25.0))
	check.call(same, "回り込み: 0度は導入前と同じ結果・位置は回り込みで動かない")
	check.call(
		worst < 1e-2,
		"回り込み: 狙いがちょうど指定角ぶん回る (最大ずれ %.4f度)" % worst
	)


## この変更の目的そのもの: 群で符号を揃えると、全員が中心のまわりを**同じ向きに**
## 回る。回転の向きは (出現位置-中心) × 速度 の符号で読める。
##
## 導入前(swirl=0)は狙いが中心±spreadなので符号はほぼ半々に散らばり、
## 逆向き同士＝正面衝突の組が生まれる。共通の回り込みを入れると全員同符号になり、
## 交差しても追い越しになるので開幕の潰し合いが減る
## (measure_melee_selfkill.gd: 敵同士の初衝突の中央値が全乱戦セルで後ろへ動いた)。
func _test_swirl_aligns_the_group(check: Callable) -> void:
	var sign_of := func(plan: EnemySpawn.Plan) -> float:
		return signf((plan.position - CENTER).cross(plan.velocity))

	var aligned_plain := 0
	var aligned_swirl := 0
	var pairs := 0
	for trial in TRIALS:
		# 同じ群の2体ぶん(同じrngから続けて引く=実プレイと同じ)。
		var rng_a := RandomNumberGenerator.new()
		rng_a.seed = trial
		var a1 := EnemySpawn.plan(CENTER, RING, SPEED, 30.0, rng_a)
		var a2 := EnemySpawn.plan(CENTER, RING, SPEED, 30.0, rng_a)
		var rng_b := RandomNumberGenerator.new()
		rng_b.seed = trial
		var b1 := EnemySpawn.plan(CENTER, RING, SPEED, 30.0, rng_b, 0.0, 5.0, [], 0.0, [], 25.0)
		var b2 := EnemySpawn.plan(CENTER, RING, SPEED, 30.0, rng_b, 0.0, 5.0, [], 0.0, [], 25.0)
		pairs += 1
		if sign_of.call(a1) == sign_of.call(a2):
			aligned_plain += 1
		if sign_of.call(b1) == sign_of.call(b2):
			aligned_swirl += 1

	# 回り込み25度 > 散らし30度 ではないので全部は揃わないが、揃う割合は明確に上がる。
	check.call(
		aligned_swirl > aligned_plain,
		"回り込み: 群の回る向きが揃いやすくなる (%d/%d → %d/%d組)" % [
			aligned_plain, pairs, aligned_swirl, pairs
		]
	)
	check.call(
		aligned_swirl * 10 >= pairs * 8,
		"回り込み: 8割以上の組で向きが揃う (%d/%d組)" % [aligned_swirl, pairs]
	)


## 実プレイ(Battle.gd)が回り込みを**群で1回だけ**決めてplan()へ渡していること。
## _test_battle_wires_group と同じ理由(実プレイ側だけテストの目が届かない)で、
## ソースの配線を見る。体ごとに引き直すと符号が揃わず、機構の意味が消える。
func _test_battle_wires_swirl(check: Callable) -> void:
	var source := FileAccess.get_file_as_string("res://scenes/battle/Battle.gd")
	check.call(
		source.contains("EnemySpawn.group_swirl_deg("),
		"Battle.gdが回り込みをEnemySpawn.group_swirl_degで決める"
	)
	# 体ごとに引き直すと符号が揃わない＝機構がまるごと無意味になる。出現を組む
	# _spawn_enemy の中で引いていないこと(＝ループの外で1回)を見る。
	var spawn_body := source.substr(source.find("func _spawn_enemy"))
	# 代入の形で数える(コメント中の言及を巻き込まないため)。
	var assign := "_group_swirl_deg = EnemySpawn.group_swirl_deg("
	check.call(
		source.count(assign) == 1 and not spawn_body.contains(assign),
		"Battle.gdが回り込みを群で1回だけ決める(体ごとに引き直さない)"
	)
	check.call(
		spawn_body.contains("_group_swirl_deg"),
		"Battle.gdが決めた回り込みを各敵のplan()へ渡す"
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
