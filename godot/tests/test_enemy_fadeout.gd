extends RefCounted

## enemy_fadeout.gd のテスト。乱戦で倒れた敵を時間差で消す計算を固定する。
##
## 見た目のフェード自体は Battle.gd がノードへ流し込む部分で、ここでは値の出所である
## 純粋関数(被撃破時刻の割り出しと不透明度カーブ)を突く。単調性・境界・番兵の扱いなど、
## 秒数を後で調整しても壊れない性質で押さえる。

const EPS := 1e-4

const THRESHOLD := 0.03
const STEP := 1.0 / 60.0
const DELAY := 0.8
const DURATION := 0.5


func run(check: Callable) -> void:
	_test_defeat_time(check)
	_test_alpha_not_defeated(check)
	_test_alpha_shape(check)
	_test_alpha_monotonic_and_bounded(check)
	_test_alpha_zero_duration(check)


## rps がしきい値以下になる最初のフレームの時刻を返すこと。
func _test_defeat_time(check: Callable) -> void:
	# 5フレーム目(index 5)で初めてしきい値を割るトラック。
	var track: Array = []
	for i in 10:
		var rps := 1.0 if i < 5 else 0.0
		track.append(BattleResult.Snapshot.new(Vector2.ZERO, Vector2.ZERO, rps))
	var t_defeat := EnemyFadeout.defeat_time(track, THRESHOLD, STEP)
	check.call(
		is_equal_approx(t_defeat, 5 * STEP),
		"被撃破時刻: 最初に閾値を割ったフレームの時刻を返す (%.4f)" % t_defeat
	)

	# しきい値ちょうども撃破とみなす(<=)。
	var edge: Array = [BattleResult.Snapshot.new(Vector2.ZERO, Vector2.ZERO, THRESHOLD)]
	check.call(
		is_equal_approx(EnemyFadeout.defeat_time(edge, THRESHOLD, STEP), 0.0),
		"被撃破時刻: しきい値ちょうども撃破とみなす"
	)

	# 一度も割らない(最後まで生存)なら -1。
	var alive: Array = []
	for i in 10:
		alive.append(BattleResult.Snapshot.new(Vector2.ZERO, Vector2.ZERO, 1.0))
	check.call(
		EnemyFadeout.defeat_time(alive, THRESHOLD, STEP) < 0.0,
		"被撃破時刻: 最後まで生き残ったら -1 (未撃破の番兵)"
	)

	# 空トラックも -1。
	check.call(
		EnemyFadeout.defeat_time([], THRESHOLD, STEP) < 0.0,
		"被撃破時刻: 空の軌跡は -1"
	)


## 未撃破(-1)は常に不透明。ここが崩れると生存敵まで消える。
func _test_alpha_not_defeated(check: Callable) -> void:
	var opaque := true
	for i in 200:
		var t := i * 0.05
		if not is_equal_approx(EnemyFadeout.alpha_at(t, -1.0, DELAY, DURATION), 1.0):
			opaque = false
	check.call(opaque, "不透明度: 未撃破の敵はどの時刻でも消えない(常に1.0)")


## 撃破後、delayまでは1.0、delay+durationで0.0、中点で0.5。
func _test_alpha_shape(check: Callable) -> void:
	var td := 1.0

	check.call(
		is_equal_approx(EnemyFadeout.alpha_at(td, td, DELAY, DURATION), 1.0),
		"不透明度: 撃破直後はまだ消えない(暗転した姿を見せる)"
	)
	check.call(
		is_equal_approx(EnemyFadeout.alpha_at(td + DELAY - EPS, td, DELAY, DURATION), 1.0),
		"不透明度: delay直前まで1.0のまま"
	)
	var mid := EnemyFadeout.alpha_at(td + DELAY + DURATION * 0.5, td, DELAY, DURATION)
	check.call(
		is_equal_approx(mid, 0.5),
		"不透明度: フェード中点で0.5 (%.3f)" % mid
	)
	check.call(
		is_equal_approx(EnemyFadeout.alpha_at(td + DELAY + DURATION, td, DELAY, DURATION), 0.0),
		"不透明度: delay+durationで完全に消える"
	)
	check.call(
		is_equal_approx(EnemyFadeout.alpha_at(td + 100.0, td, DELAY, DURATION), 0.0),
		"不透明度: 消えたあとは0.0のまま"
	)


## 時間について単調非増加で、常に [0,1] に収まること。
func _test_alpha_monotonic_and_bounded(check: Callable) -> void:
	var td := 1.0
	var prev := 2.0
	var monotonic := true
	var bounded := true
	for i in 400:
		var t := i * 0.01
		var a := EnemyFadeout.alpha_at(t, td, DELAY, DURATION)
		if a > prev + EPS:
			monotonic = false
		if a < -EPS or a > 1.0 + EPS:
			bounded = false
		prev = a
	check.call(monotonic, "不透明度: 時間が進んで濃くなることはない(単調非増加)")
	check.call(bounded, "不透明度: 常に0〜1に収まる")


## duration=0 でも 0除算やNaNにならず、delay経過で0へ落ちること。
func _test_alpha_zero_duration(check: Callable) -> void:
	var td := 1.0
	check.call(
		is_equal_approx(EnemyFadeout.alpha_at(td + DELAY - EPS, td, DELAY, 0.0), 1.0),
		"不透明度: duration=0 でもdelay前は1.0"
	)
	var a := EnemyFadeout.alpha_at(td + DELAY, td, DELAY, 0.0)
	check.call(
		is_equal_approx(a, 0.0) and not is_nan(a),
		"不透明度: duration=0 でもNaNにならずdelayで0へ落ちる"
	)
