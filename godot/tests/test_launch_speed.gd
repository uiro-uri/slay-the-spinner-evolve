extends RefCounted

## launch_speed.gd のテスト。自機・敵で共通の発射速度レンジを数値で押さえる。
##
## 敵はrandom()で[ENEMY_MIN,MAX]から抽選し、自機はfrom_pull()で引き量比を
## [PLAYER_MIN,MAX]にマップする(引き量ちょうど0だけが0)。値域・境界・決定性を
## 固定する。実際の手触りはverify.shの実描画/playtestで人が見る(CLAUDE.mdの方針)。

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_constants(check)
	_test_max_for_radius(check)
	_test_random_in_range(check)
	_test_random_big_radius(check)
	_test_callers_pass_radius(check)
	_test_random_deterministic(check)
	_test_from_pull(check)
	_test_callers_use_from_pull(check)


## レンジの妥当性。MINは「速度なし」、ENEMY_MIN/PLAYER_MINは抽選・引きの下限、MAXが上限。
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


## 自機の引き量→初速マップ。引き量0だけが0で、少しでも引けば下限PLAYER_MIN以上、
## full pullでMAX、超過はMAXでクランプ。
func _test_from_pull(check: Callable) -> void:
	const MAX_PULL := 4.0
	check.call(
		absf(LaunchSpeed.from_pull(0.0, MAX_PULL)) < EPS,
		"from_pull: 引き量0は速度0(向きが決まっていない状態。三角形も出ない)"
	)
	check.call(
		absf(LaunchSpeed.from_pull(MAX_PULL, MAX_PULL) - LaunchSpeed.MAX) < EPS,
		"from_pull: full pullで速度MAX"
	)
	check.call(
		absf(LaunchSpeed.from_pull(MAX_PULL * 0.5, MAX_PULL)
			- (LaunchSpeed.PLAYER_MIN + LaunchSpeed.MAX) * 0.5) < EPS,
		"from_pull: 半分引きで[PLAYER_MIN,MAX]の中点(線形)"
	)
	check.call(
		absf(LaunchSpeed.from_pull(MAX_PULL * 3.0, MAX_PULL) - LaunchSpeed.MAX) < EPS,
		"from_pull: max_pull超はMAXでクランプ(見た目と初速がズレない)"
	)
	check.call(
		absf(LaunchSpeed.from_pull(2.0, 0.0)) < EPS,
		"from_pull: max_pull<=0は0(ゼロ除算しない)"
	)

	# 死に帯の封鎖そのもの。ごく僅かでも引いたら「置きコマ」の速度域には落ちない。
	# ここが破れると、弱撃ちが罰でしかないことを知らないプレイヤーが静かに損をする
	# (measure_launch_force: 成長3枚Lv3単体で勝率13.2% vs 満引き62.8%)。
	check.call(
		LaunchSpeed.PLAYER_MIN > 0.0,
		"PLAYER_MIN: 自機にも下限がある(置きコマを撃てない)"
	)
	check.call(
		is_equal_approx(LaunchSpeed.PLAYER_MIN, LaunchSpeed.ENEMY_MIN),
		"PLAYER_MIN: 敵の下限と同値(同じ理屈なので片方だけ動かない)"
	)
	for i in 20:
		var pull := MAX_PULL * (float(i) + 1.0) / 20.0
		var speed := LaunchSpeed.from_pull(pull, MAX_PULL)
		check.call(
			speed >= LaunchSpeed.PLAYER_MIN - EPS,
			"from_pull: 引き量%.2fでも下限を割らない(速度%.2f)" % [pull, speed]
		)

	# 単調増加は残す。下限を敷いても「強く引くほど速い」は壊れていないこと。
	var prev := LaunchSpeed.from_pull(0.0, MAX_PULL)
	for i in 20:
		var speed := LaunchSpeed.from_pull(MAX_PULL * (float(i) + 1.0) / 20.0, MAX_PULL)
		check.call(speed > prev - EPS, "from_pull: 引くほど速い(単調)")
		prev = speed


## 自機の初速を作る3経路(実UI・ボット・CLI)が全て from_pull を通っていること。
##
## 下限は from_pull の中にしかない。どれか1経路が `MAX * force` の素の掛け算へ
## 戻ると、そこだけ**実プレイでは選べない置きコマ速度**を出せてしまう——しかも
## 単体テストは from_pull を直に呼ぶので全部greenのまま気づけない。実際
## ボット(launch_policy)とCLI(naive_play)は 2026-08-10 まで両方とも素の掛け算で、
## 統計とコールドプレイが実UIより遅い発射を混ぜていた。
## 3経路とも**実際に呼んで**下限を割らないことを見る。最初はソース照合だけで
## 書いたが、迂回のサボタージュ2種(`MAX * clampf(...)` と `MAX * (pull/max_pull)`)を
## どちらも取り逃した——正規表現が掛け算の右側の書き方に依存し、`contains` は
## コメント中の `from_pull` にも当たっていた。**呼んで確かめる**方が短くて強い。
## ソース照合は「MAXを掛けている行が1つも無い」の形だけ残す(迂回の再発の早期警報)。
func _test_callers_use_from_pull(check: Callable) -> void:
	const FAINT := 0.01  # ほんの少しだけ引いた状態

	# 実UI: LaunchController._launch_velocity の中身(velocity_from_pull)。
	# LaunchControllerはNodeでAudioManager(autoload)にも依存するのでヘッドレスから
	# new()できない——だから発射の規則そのものを純粋関数へ出してある。
	const MAX_PULL := 4.0
	var faint_v := LaunchSpeed.velocity_from_pull(Vector2(MAX_PULL * FAINT, 0.0), MAX_PULL)
	check.call(
		faint_v.length() >= LaunchSpeed.PLAYER_MIN - EPS,
		"実UI: ごく僅かな引きでも下限を割らない (%.2f)" % faint_v.length()
	)
	var full_v := LaunchSpeed.velocity_from_pull(Vector2(MAX_PULL, 0.0), MAX_PULL)
	check.call(
		absf(full_v.length() - LaunchSpeed.MAX) < EPS,
		"実UI: full pullで速度MAX (%.2f)" % full_v.length()
	)
	check.call(
		full_v.normalized().dot(Vector2.RIGHT) > 1.0 - EPS,
		"実UI: 速度は引いた向きそのまま(向きの反転は呼び出し側の役目)"
	)
	check.call(
		LaunchSpeed.velocity_from_pull(Vector2.ZERO, MAX_PULL) == Vector2.ZERO,
		"実UI: 引き量0はゼロベクトル(下限を勝手に生やさない)"
	)

	# ボット: LaunchPolicy.decide。force_scaleは引き量比なので同じ下限が要る。
	var field := BattleSim.default_field()
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var plans: Array[EnemySpawn.Plan] = [
		EnemySpawn.Plan.new(field.center() + Vector2(3.0, 0.0), Vector2(-4.0, 0.0))
	]
	var radii := PackedFloat32Array([0.5])
	for kind in [LaunchPolicy.Kind.AIM_CENTER, LaunchPolicy.Kind.AIM_SPAWN,
			LaunchPolicy.Kind.INTERCEPT]:
		var launch := LaunchPolicy.decide(kind, field, 0.7, plans, radii, rng, FAINT)
		check.call(
			launch.velocity.length() >= LaunchSpeed.PLAYER_MIN - EPS,
			"ボット(%s): 引き量%.2fでも下限を割らない (%.2f)" % [
				LaunchPolicy.NAMES[kind], FAINT, launch.velocity.length()]
		)

	# CLI: naive_play.launch_velocity は test_playtest 側でも見ているが、
	# 「3経路が揃っている」ことはここで一望できるべきなので並べておく。
	var NaivePlay := load("res://playtest/naive_play.gd")
	var cli := NaivePlay.launch_velocity(Vector2(8.0, 2.0), Vector2(5.0, 5.0), FAINT) as Vector2
	check.call(
		cli.length() >= LaunchSpeed.PLAYER_MIN - EPS,
		"CLI: 引き量%.2fでも下限を割らない (%.2f)" % [FAINT, cli.length()]
	)

	# 早期警報: この3ファイルに LaunchSpeed.MAX を掛けている箇所は本来1つも無い。
	var bypass := RegEx.new()
	bypass.compile("LaunchSpeed\\.MAX\\s*\\*")
	for path in ["res://scenes/battle/LaunchController.gd", "res://playtest/launch_policy.gd",
			"res://playtest/naive_play.gd"]:
		check.call(
			bypass.search(FileAccess.get_file_as_string(path)) == null,
			"%s: MAXを直接掛ける行が無い(from_pullを迂回していない)" % path
		)
	# 実UIが規則を自前で書き直していないこと(純粋関数を通しているから検査が効く)。
	check.call(
		FileAccess.get_file_as_string("res://scenes/battle/LaunchController.gd").contains(
			"LaunchSpeed.velocity_from_pull("),
		"LaunchController: 発射速度は velocity_from_pull(=テストが触れる純粋関数)で作る"
	)
