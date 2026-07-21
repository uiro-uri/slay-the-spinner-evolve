extends RefCounted

## launch_speed.gd のテスト。自機・敵で共通の発射速度レンジを数値で押さえる。
##
## 敵はrandom()で[MIN,MAX]から抽選し、自機はfrom_pull()で引き量比を[0,MAX]に
## マップする。値域・境界・決定性を固定する。実際の手触りはverify.shの実描画/
## playtestで人が見る(CLAUDE.mdの方針)。

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_constants(check)
	_test_random_in_range(check)
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
