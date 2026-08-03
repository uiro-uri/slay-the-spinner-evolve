extends RefCounted

## 決戦の土俵の広さ。
##
## ボスは全敵で最も大きい(半径1.91＝Lv4最大の1.5倍)のに、決戦の土俵だけは道中と
## 同じ10ユニット四方の八角形＝全土俵で最も内接半径が小さいままだった。
## 「中心の相手に触れずにいられる隙間」= 内接半径 − 相手の半径 − 自機の半径 は
## 道中の最悪ケースで2.63あるのに、決戦は2.01しかなく、発射直後から密着が切れない。
## テストプレイでも段別の被弾/秒(中央値)が段8=1.42に対し段9=2.34と跳ねていた。
##
## ここで縛るのは**幾何**であって強さではない。ボスの質量・rps・半径は
## test_enemy_roster.gd の不変条件が別に縛っており、数値の調整で隙間の invariant が
## 壊れないよう、この suite は「道中の最悪ケース以上の隙間が決戦にもある」という
## 比較だけを見る(絶対値を書かないので、土俵もボスも再調整して構わない)。

const EPS := 0.0001

## 表示上のアリーナの一辺(px)。Battle.ARENA_PX と対。
const ARENA_PX := 500.0


func run(check: Callable) -> void:
	_test_clearance(check)
	_test_boss_field_is_exclusive(check)
	_test_unit_scale(check)


## 中心の相手に触れずにいられる隙間。負なら「土俵のどこにいても接触している」。
func _clearance(field: FieldData, enemy_radius: float, player_radius: float) -> float:
	return field.inradius() - enemy_radius - player_radius


## そのレベルで最も大きい敵の半径。隙間の最悪ケースを作る。
func _widest_enemy(level: int) -> float:
	var widest := 0.0
	for enemy in EnemyRoster.of_level(level):
		widest = maxf(widest, enemy.stats.radius)
	return widest


func _test_clearance(check: Callable) -> void:
	var player_radius := SpinnerStats.default_player().radius

	# 道中(段1〜8)の最悪ケース: 一番大きい敵 × 一番狭い土俵。どの土俵が出るかは
	# 抽選なので、段ごとに全土俵を当てて最小を取る(シードに依存しない)。
	var worst_run := INF
	for step in range(1, MapTree.STEP_GOAL):
		var enemy_radius := _widest_enemy(EnemyRoster.level_for_step(step))
		for field in FieldRoster.all():
			worst_run = minf(worst_run, _clearance(field, enemy_radius, player_radius))

	var boss_field := FieldRoster.boss_field()
	var boss_clearance := _clearance(
		boss_field, _widest_enemy(EnemyRoster.level_for_step(MapTree.STEP_GOAL)), player_radius
	)
	check.call(
		boss_clearance >= worst_run - EPS,
		"決戦の隙間: 道中の最悪ケース以上 (決戦%.2f >= 道中%.2f)" % [boss_clearance, worst_run]
	)

	# 隙間が正でないと「土俵のどこにいても接触」になる。上の比較は道中側が
	# 一緒に潰れると通ってしまうので、絶対の床も別に踏む。
	check.call(boss_clearance > 0.0, "決戦の隙間: 正 (%.2f)" % boss_clearance)

	# 決戦の土俵は道中のどれよりも広い。形(八角形)は道中のFIELD_ARENAと同じなので、
	# 内接半径が同じままだと「広い決戦専用」ではなく単なる別名になる。
	var widest_run := 0.0
	for field in FieldRoster.all():
		widest_run = maxf(widest_run, field.inradius())
	check.call(
		boss_field.inradius() > widest_run + EPS,
		"決戦の土俵: 道中のどれよりも広い (%.2f > %.2f)" % [boss_field.inradius(), widest_run]
	)

	# 隙間は「自機がすり抜けられる帯の幅」なので、自機の直径を基準に読む。
	# 帯が直径より狭いと、ボスの脇を通ることすらできない。
	check.call(
		boss_clearance > player_radius * 2.0,
		"決戦の隙間: 自機の直径より広い (%.2f > %.2f)" % [boss_clearance, player_radius * 2.0]
	)


## 決戦の土俵は決戦にしか出ない。道中の抽選プールに混ざると専用ではなくなるし、
## 道中の土俵として広いものが出れば難易度がまるごと変わる。
func _test_boss_field_is_exclusive(check: Callable) -> void:
	var boss_key := FieldRoster.boss_field().title_key
	var in_pool := false
	for field in FieldRoster.all():
		if field.title_key == boss_key:
			in_pool = true
	check.call(not in_pool, "決戦の土俵: 道中の抽選プール(all)には入っていない")

	var rng := RandomNumberGenerator.new()
	var leaked := false
	var boss_always := true
	for i in range(120):
		rng.seed = i
		for step in range(1, MapTree.STEP_GOAL):
			if FieldRoster.pick_for_step(step, rng).title_key == boss_key:
				leaked = true
		if FieldRoster.pick_for_step(MapTree.STEP_GOAL, rng).title_key != boss_key:
			boss_always = false
	check.call(not leaked, "決戦の土俵: 段1〜8では引かれない")
	check.call(boss_always, "決戦の土俵: 段9では必ず引かれる")

	check.call(
		tr(boss_key) != boss_key,
		"決戦の土俵: 表示名が翻訳されている (%s)" % boss_key
	)


## 土俵が何ユニット四方でも、画面上のアリーナは同じ大きさの正方形に収まること。
## 以前は「1ユニット=50px」の決め打ちで、広い土俵を渡すと画面からはみ出した。
func _test_unit_scale(check: Callable) -> void:
	var fields := FieldRoster.all()
	fields.append(FieldRoster.boss_field())
	var constant_box := true
	var sizes := {}
	for field in fields:
		var size := field.arena_bounds.size
		sizes[size.x] = true
		var px: float = ScreenLayout.arena_unit_scale(size, ARENA_PX) * maxf(size.x, size.y)
		if absf(px - ARENA_PX) > EPS:
			constant_box = false
	check.call(constant_box, "表示縮尺: 土俵の広さによらず画面上の一辺はARENA_PXで一定")
	# 広さが1種類しかないと上のチェックは何も言っていない(縮尺が決め打ちでも通る)。
	check.call(sizes.size() > 1, "表示縮尺: 広さの違う土俵が実在する (%d種)" % sizes.size())

	# 広い土俵ほど1ユニットは小さく映る＝広さがそのまま絵に出る。
	check.call(
		ScreenLayout.arena_unit_scale(Vector2(12, 12), ARENA_PX)
			< ScreenLayout.arena_unit_scale(Vector2(10, 10), ARENA_PX),
		"表示縮尺: 広い土俵ほど1ユニットあたりのpxが小さい"
	)
	# 0除算は例外にならず INF を返すので、正であることだけを見ても素通りする。
	var degenerate := ScreenLayout.arena_unit_scale(Vector2.ZERO, ARENA_PX)
	check.call(
		degenerate > 0.0 and is_finite(degenerate),
		"表示縮尺: 広さ0でも有限の倍率を返す (%f)" % degenerate
	)
