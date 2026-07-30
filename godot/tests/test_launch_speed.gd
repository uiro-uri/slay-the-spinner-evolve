extends RefCounted

## launch_speed.gd のテスト。自機・敵で共通の発射速度レンジを数値で押さえる。
##
## 敵はrandom()で[MIN,MAX]から抽選し、自機はfrom_pull()で引き量比を[0,MAX]に
## マップする。値域・境界・決定性を固定する。実際の手触りはverify.shの実描画/
## playtestで人が見る(CLAUDE.mdの方針)。

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_constants(check)
	_test_max_for_radius(check)
	_test_random_in_range(check)
	_test_random_big_radius(check)
	_test_callers_pass_radius(check)
	_test_random_deterministic(check)
	_test_from_pull(check)


## レンジの妥当性。MINは自機の下限(0)、ENEMY_MINは敵の抽選下限、MAXが上限。
func _test_constants(check: Callable) -> void:
	check.call(LaunchSpeed.MIN < LaunchSpeed.MAX, "MIN(%.1f) < MAX(%.1f)" % [LaunchSpeed.MIN, LaunchSpeed.MAX])
	check.call(LaunchSpeed.MIN >= 0.0, "MIN(%.1f) は0以上(負の速度は無い)" % LaunchSpeed.MIN)
	check.call(
		LaunchSpeed.ENEMY_MIN > LaunchSpeed.MIN,
		"ENEMY_MIN(%.1f) > MIN(%.1f) (置物スポーンを許さない)" % [LaunchSpeed.ENEMY_MIN, LaunchSpeed.MIN]
	)
	check.call(
		LaunchSpeed.ENEMY_MIN < LaunchSpeed.MAX * 0.5,
		"ENEMY_MIN(%.1f) はMAXの半分未満(低速帯の読み合いを残す)" % LaunchSpeed.ENEMY_MIN
	)


## 大型敵の抽選上限の体格スケール。値そのものでなく、チューニングで生き残る
## 性質(単調・境界・値域)を固定する(CLAUDE.mdの方針)。
func _test_max_for_radius(check: Callable) -> void:
	# 中小型(CAP_FREE_RADIUS以下)は完全に従来どおり=上限MAX。
	check.call(
		absf(LaunchSpeed.max_for_radius(0.0) - LaunchSpeed.MAX) < EPS,
		"max_for_radius: 半径0(省略時)は上限MAX(旧挙動と厳密一致)"
	)
	check.call(
		absf(LaunchSpeed.max_for_radius(LaunchSpeed.CAP_FREE_RADIUS) - LaunchSpeed.MAX) < EPS,
		"max_for_radius: CAP_FREE_RADIUS以下は上限MAX(中小型のレンジを削らない)"
	)
	# ボス級(CAP_FULL_RADIUS以上)はCAP_BIGで頭打ち(それ以上大きくても下がり続けない)。
	check.call(
		absf(LaunchSpeed.max_for_radius(LaunchSpeed.CAP_FULL_RADIUS) - LaunchSpeed.CAP_BIG) < EPS,
		"max_for_radius: CAP_FULL_RADIUSでCAP_BIG"
	)
	check.call(
		absf(LaunchSpeed.max_for_radius(10.0) - LaunchSpeed.CAP_BIG) < EPS,
		"max_for_radius: 超大型でもCAP_BIGで頭打ち(抽選レンジが潰れない)"
	)
	# 半径について単調非増加(大きいほど速くはならない)。
	var monotone := true
	var prev := LaunchSpeed.max_for_radius(0.0)
	for i in 200:
		var cap := LaunchSpeed.max_for_radius(0.02 * (i + 1))
		if cap > prev + EPS:
			monotone = false
		prev = cap
	check.call(monotone, "max_for_radius: 半径について単調非増加")
	# 上限が下限を割らない=抽選レンジが常に成立する。
	check.call(
		LaunchSpeed.CAP_BIG > LaunchSpeed.ENEMY_MIN,
		"CAP_BIG(%.1f) > ENEMY_MIN(%.1f) (大型でも抽選レンジが残る)" % [LaunchSpeed.CAP_BIG, LaunchSpeed.ENEMY_MIN]
	)


## 敵の抽選は必ず[ENEMY_MIN,MAX]に収まること。多数サンプルで両端も踏む。
## 下限がENEMY_MINなのが本質: 下限0に戻すと「ほぼ静止の無料キル」が復活する。
func _test_random_in_range(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var lo := INF
	var hi := -INF
	var all_in := true
	for i in 5000:
		var s := LaunchSpeed.random(rng)
		if s < LaunchSpeed.ENEMY_MIN - EPS or s > LaunchSpeed.MAX + EPS:
			all_in = false
		lo = minf(lo, s)
		hi = maxf(hi, s)
	check.call(all_in, "random(): 全サンプルが[ENEMY_MIN,MAX]に収まる (観測 %.2f〜%.2f)" % [lo, hi])
	# レンジをちゃんと使い切っている(両端近くまで出る)ことも確認。
	check.call(
		lo < LaunchSpeed.ENEMY_MIN + 0.5 and hi > LaunchSpeed.MAX - 0.5,
		"random(): レンジの両端近くまで抽選される (%.2f〜%.2f)" % [lo, hi]
	)


## 大型半径を渡した抽選は縮んだレンジ[ENEMY_MIN, max_for_radius]に収まり、
## かつそのレンジを使い切ること。radius省略と半径0が同じ列を返す後方互換も固定する。
func _test_random_big_radius(check: Callable) -> void:
	const BOSS_RADIUS := 1.91  # 実ゲームのボス実半径の上端相当
	var cap := LaunchSpeed.max_for_radius(BOSS_RADIUS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var lo := INF
	var hi := -INF
	var all_in := true
	for i in 5000:
		var s := LaunchSpeed.random(rng, BOSS_RADIUS)
		if s < LaunchSpeed.ENEMY_MIN - EPS or s > cap + EPS:
			all_in = false
		lo = minf(lo, s)
		hi = maxf(hi, s)
	check.call(all_in, "random(大型): 全サンプルが[ENEMY_MIN, cap=%.2f]に収まる (観測 %.2f〜%.2f)" % [cap, lo, hi])
	check.call(
		hi > cap - 0.5 and lo < LaunchSpeed.ENEMY_MIN + 0.5,
		"random(大型): 縮んだレンジを使い切る (%.2f〜%.2f)" % [lo, hi]
	)
	# radius省略はradius=0.0と同じ列(既存呼び出しの挙動を変えない)。
	var a := RandomNumberGenerator.new(); a.seed = 99
	var b := RandomNumberGenerator.new(); b.seed = 99
	var same := true
	for i in 100:
		if not is_equal_approx(LaunchSpeed.random(a), LaunchSpeed.random(b, 0.0)):
			same = false
	check.call(same, "random(): radius省略とradius=0.0は同一列")


## 敵の初速を引く3経路(実UI・battle_sim・naive_play)が全て半径を渡していること。
## radius省略は旧挙動(上限MAX)へ静かに退行するので、渡し忘れを源泉で捕まえる
## (test_battle_defaultsと同じソース照合の流儀)。
func _test_callers_pass_radius(check: Callable) -> void:
	const CALLERS: Array[String] = [
		"res://scenes/battle/Battle.gd",
		"res://playtest/battle_sim.gd",
		"res://playtest/naive_play.gd",
	]
	var bare := RegEx.new()
	bare.compile("LaunchSpeed\\.random\\(\\s*\\w+\\s*\\)")
	for path in CALLERS:
		var src := FileAccess.get_file_as_string(path)
		check.call(
			src.contains("LaunchSpeed.random("),
			"%s: LaunchSpeed.randomを使っている(経路が消えたら本テストの守備範囲を見直す)" % path
		)
		check.call(
			bare.search(src) == null,
			"%s: LaunchSpeed.random に半径を渡している(引数1つの素の呼び出しが無い)" % path
		)


## 同じseedなら同じ列。playbackとplaytestの決定性の土台。
func _test_random_deterministic(check: Callable) -> void:
	var a := RandomNumberGenerator.new(); a.seed = 777
	var b := RandomNumberGenerator.new(); b.seed = 777
	var same := true
	for i in 100:
		if not is_equal_approx(LaunchSpeed.random(a), LaunchSpeed.random(b)):
			same = false
	check.call(same, "random(): 同一seedは同一列を返す")


## 自機の引き量→初速マップ。0でMIN無しの0、full pullでMAX、超過はMAXでクランプ。
func _test_from_pull(check: Callable) -> void:
	const MAX_PULL := 4.0
	check.call(
		absf(LaunchSpeed.from_pull(0.0, MAX_PULL)) < EPS,
		"from_pull: 引き量0は速度0(自機は下限MINを持たない)"
	)
	check.call(
		absf(LaunchSpeed.from_pull(MAX_PULL, MAX_PULL) - LaunchSpeed.MAX) < EPS,
		"from_pull: full pullで速度MAX"
	)
	check.call(
		absf(LaunchSpeed.from_pull(MAX_PULL * 0.5, MAX_PULL) - LaunchSpeed.MAX * 0.5) < EPS,
		"from_pull: 半分引きで速度MAX/2(線形)"
	)
	check.call(
		absf(LaunchSpeed.from_pull(MAX_PULL * 3.0, MAX_PULL) - LaunchSpeed.MAX) < EPS,
		"from_pull: max_pull超はMAXでクランプ(見た目と初速がズレない)"
	)
	check.call(
		absf(LaunchSpeed.from_pull(2.0, 0.0)) < EPS,
		"from_pull: max_pull<=0は0(ゼロ除算しない)"
	)
