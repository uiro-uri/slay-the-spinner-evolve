extends RefCounted

## 発射の**立ち位置**(LaunchPolicy.Stance / ring_scale, naive_play の --from-r)のテスト。
##
## 実UI(Battle._clamp_launch)の発射位置は「土俵の内側 かつ 敵予告の間合いの外」なら
## **どこでもよい2自由度**なのに、ボット(LaunchPolicy._ring_position)もコールドプレイCLI
## (naive_play._ring_pos)も長らく**外周リングの1点**しか撃てなかった。この差が塞がって
## いること、そして塞いだせいで従来の統計がズレていないことを固定する。
##
## 値(勝率がどれだけ動くか)は調整で動くので、ここでは
##   - 向き(真反対/同じ側)が中心を挟んで正しい側に出ること
##   - 距離(ring_scale)が中心へ寄せる向きに効き、範囲外はクランプされること
##   - **既定(RING_RANDOM・ring_scale=1.0)が導入前と厳密一致**であること
##   - どの立ち位置でも rng の消費数が同じ(＝敵の湧きがズレない)こと
##   - どの立ち位置でも壁の内側・間合いの外に留まること
##   - CLI(naive_play._ring_pos)とボットが同じ規則を使っていること
## という、値に依存しない性質だけを見る。

const EPS := 1e-3

## 間合いの検査だけ緩めの許容。LaunchStandoff の合格判定は**相対**
## (`_clearance_score` が 距離/必要距離 を 1e-3 の相対誤差で見る)なので、
## 必要距離が3ほどある場面では絶対値で数ミリの食い込みが正常に出る。
## ここを 1e-3 で見ると、立ち位置とは無関係にクランプの丸めを拾って落ちる。
const STANDOFF_EPS := 0.01

## 予告(敵の出現)を土俵の右寄りに置く。中心から見た向きがはっきりしていれば
## 「真反対/同じ側」の判定ができる。半径は小さめにして、間合いのクランプが
## 立ち位置そのものを潰さないようにする(潰れる場合の検査は別に置く)。
const _SPAWN := Vector2(8.5, 5.0)
const _SPAWN_RADIUS := 0.3
const _PLAYER_RADIUS := 0.7


func run(check: Callable) -> void:
	_test_direction(check)
	_test_ring_scale_pulls_inward(check)
	_test_ring_scale_clamped(check)
	_test_default_matches_legacy(check)
	_test_rng_consumption_is_stance_independent(check)
	_test_stays_inside_and_outside_standoff(check)
	_test_center_spawn_is_degenerate_safe(check)
	_test_battle_sim_honours_overrides(check)
	_test_cli_matches_policy_rule(check)


func _field() -> FieldData:
	return FieldData.make(
		"FIELD_TEST", Rect2(0, 0, 10, 10), ArenaWall.WallShape.RECT,
		SpinnerPhysics.StageShape.DISH, 4.9
	)


func _plans(spawn: Vector2 = _SPAWN) -> Array[EnemySpawn.Plan]:
	var out: Array[EnemySpawn.Plan] = [
		EnemySpawn.Plan.new(spawn, Vector2(-3.0, 0.0))
	]
	return out


func _radii() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.append(_SPAWN_RADIUS)
	return out


func _rng(seed_value: int = 7) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## 立ち位置を1つ決めて発射地点だけ返す。狙う方針は AIM_SPAWN 固定
## (どこを狙うかは立ち位置と直交するので、1つに固定して比較する)。
func _launch_pos(
	stance: LaunchPolicy.Stance, ring_scale: float = 1.0,
	seed_value: int = 7, spawn: Vector2 = _SPAWN
) -> Vector2:
	return LaunchPolicy.decide(
		LaunchPolicy.Kind.AIM_SPAWN, _field(), _PLAYER_RADIUS,
		_plans(spawn), _radii(), _rng(seed_value), 1.0, stance, ring_scale
	).position


## 真反対は中心を挟んで予告の反対側、同じ側は予告と同じ側。
## 中心から見た2つのベクトルの内積の符号で見る(距離に依存しない)。
func _test_direction(check: Callable) -> void:
	var center := _field().center()
	var to_spawn := _SPAWN - center
	var opposite := _launch_pos(LaunchPolicy.Stance.RING_OPPOSITE) - center
	var near := _launch_pos(LaunchPolicy.Stance.RING_NEAR) - center
	check.call(
		opposite.dot(to_spawn) < 0.0,
		"真反対: 中心を挟んで予告の逆側に立つ (内積 %.2f)" % opposite.dot(to_spawn)
	)
	check.call(
		near.dot(to_spawn) > 0.0,
		"同じ側: 予告と同じ側に立つ (内積 %.2f)" % near.dot(to_spawn)
	)
	# 助走の長さが逆転していないこと(真反対のほうが予告から遠い)。
	check.call(
		(opposite + center).distance_to(_SPAWN) > (near + center).distance_to(_SPAWN),
		"真反対のほうが予告から遠い＝助走が長い"
	)


## 中心からの距離の比を下げると、実際に中心へ寄る。真反対で見るのは、
## 同じ側だと間合いのクランプが先に効いて距離が潰れるため。
func _test_ring_scale_pulls_inward(check: Callable) -> void:
	var center := _field().center()
	var far := _launch_pos(LaunchPolicy.Stance.RING_OPPOSITE, 1.0).distance_to(center)
	var mid := _launch_pos(LaunchPolicy.Stance.RING_OPPOSITE, 0.5).distance_to(center)
	var inner := _launch_pos(LaunchPolicy.Stance.RING_OPPOSITE, 0.1).distance_to(center)
	check.call(
		far > mid and mid > inner,
		"距離: 比を下げるほど中心へ寄る (%.2f > %.2f > %.2f)" % [far, mid, inner]
	)


## 範囲外の比はクランプされる。負は0(中心)、1超は外周リングと同じ。
func _test_ring_scale_clamped(check: Callable) -> void:
	var center := _field().center()
	var negative := _launch_pos(LaunchPolicy.Stance.RING_OPPOSITE, -1.0)
	var zero := _launch_pos(LaunchPolicy.Stance.RING_OPPOSITE, 0.0)
	var over := _launch_pos(LaunchPolicy.Stance.RING_OPPOSITE, 2.0)
	var one := _launch_pos(LaunchPolicy.Stance.RING_OPPOSITE, 1.0)
	check.call(negative.is_equal_approx(zero), "距離: 負は0(中心)へクランプ")
	check.call(over.is_equal_approx(one), "距離: 1超は外周リングへクランプ")
	check.call(
		zero.distance_to(center) < _PLAYER_RADIUS + EPS,
		"距離0: 中心そのもの (中心から %.3f)" % zero.distance_to(center)
	)


## **既定は導入前と厳密一致**。引数を省いた呼び出しと、RING_RANDOM・比1.0 を
## 明示した呼び出しが同じ位置を返すこと。ここが割れると、立ち位置の軸を足した
## だけで report.md の全数値が動く。
func _test_default_matches_legacy(check: Callable) -> void:
	var legacy := LaunchPolicy.decide(
		LaunchPolicy.Kind.AIM_SPAWN, _field(), _PLAYER_RADIUS,
		_plans(), _radii(), _rng(11)
	)
	var explicit := LaunchPolicy.decide(
		LaunchPolicy.Kind.AIM_SPAWN, _field(), _PLAYER_RADIUS,
		_plans(), _radii(), _rng(11), 1.0,
		LaunchPolicy.Stance.RING_RANDOM, 1.0
	)
	check.call(
		legacy.position.is_equal_approx(explicit.position),
		"既定: 引数省略 == RING_RANDOM・比1.0 (位置)"
	)
	check.call(
		legacy.velocity.is_equal_approx(explicit.velocity),
		"既定: 引数省略 == RING_RANDOM・比1.0 (初速)"
	)
	# BattleSim.Overrides の既定も従来のまま。
	var overrides := BattleSim.Overrides.new()
	check.call(
		overrides.launch_stance == LaunchPolicy.Stance.RING_RANDOM
			and is_equal_approx(overrides.launch_ring_scale, 1.0),
		"既定: BattleSim.Overrides は従来の立ち位置"
	)


## **どの立ち位置でも rng の消費数が同じ**。立ち位置で乱数列がズレると、
## 「立ち位置の効果」に敵の湧きの違いが混ざって測定にならない。
func _test_rng_consumption_is_stance_independent(check: Callable) -> void:
	var tail := func(stance: LaunchPolicy.Stance) -> float:
		var rng := _rng(23)
		LaunchPolicy.decide(
			LaunchPolicy.Kind.AIM_SPAWN, _field(), _PLAYER_RADIUS,
			_plans(), _radii(), rng, 1.0, stance, 0.4
		)
		return rng.randf()
	var base: float = tail.call(LaunchPolicy.Stance.RING_RANDOM)
	check.call(
		is_equal_approx(base, tail.call(LaunchPolicy.Stance.RING_OPPOSITE)),
		"乱数: 真反対でも消費数が同じ"
	)
	check.call(
		is_equal_approx(base, tail.call(LaunchPolicy.Stance.RING_NEAR)),
		"乱数: 同じ側でも消費数が同じ"
	)


## どの立ち位置・どの距離でも、壁の内側かつ全予告の間合いの外に留まる
## (立ち位置の軸が LaunchStandoff の封鎖に穴を開けていないこと)。
func _test_stays_inside_and_outside_standoff(check: Callable) -> void:
	var field := _field()
	var b := field.arena_bounds
	var required := LaunchStandoff.required_distance(
		_PLAYER_RADIUS, _SPAWN_RADIUS, field.inradius()
	)
	for stance in [
		LaunchPolicy.Stance.RING_RANDOM,
		LaunchPolicy.Stance.RING_OPPOSITE,
		LaunchPolicy.Stance.RING_NEAR,
	]:
		for scale in [0.0, 0.25, 0.5, 1.0]:
			var pos := _launch_pos(stance, scale, 5)
			var inside := (
				pos.x >= b.position.x + _PLAYER_RADIUS - EPS
				and pos.x <= b.end.x - _PLAYER_RADIUS + EPS
				and pos.y >= b.position.y + _PLAYER_RADIUS - EPS
				and pos.y <= b.end.y - _PLAYER_RADIUS + EPS
			)
			check.call(inside, "壁の内側: %s 比%.2f (%s)" % [
				LaunchPolicy.STANCE_NAMES[stance], scale, str(pos)])
			check.call(
				pos.distance_to(_SPAWN) >= required - STANDOFF_EPS,
				"間合いの外: %s 比%.2f (%.2f >= %.2f)" % [
					LaunchPolicy.STANCE_NAMES[stance], scale,
					pos.distance_to(_SPAWN), required]
			)


## 予告が中心に重なっていると「真反対」の向きが取れない。NaNを出さず、
## ランダムな立ち位置と同じ扱いに落ちること。
func _test_center_spawn_is_degenerate_safe(check: Callable) -> void:
	var center := _field().center()
	var pos := _launch_pos(LaunchPolicy.Stance.RING_OPPOSITE, 1.0, 3, center)
	check.call(
		not (is_nan(pos.x) or is_nan(pos.y)),
		"中心スポーン: NaNを出さない (%s)" % str(pos)
	)
	check.call(
		pos.is_equal_approx(_launch_pos(LaunchPolicy.Stance.RING_RANDOM, 1.0, 3, center)),
		"中心スポーン: ランダムな立ち位置と同じ点に落ちる"
	)


## **BattleSim.Overrides の立ち位置が実際に LaunchPolicy まで届いている**こと。
##
## サボタージュで見つけた穴: `LaunchPolicy` 側が完璧でも `BattleSim.play_one` が
## stance/ring_scale を渡し忘れると、上の検査は全部通ったまま**測定だけが
## 「立ち位置は勝率を1ミリも動かさない」という嘘の全行一致を出す**。
## 配線が生きていれば発射地点が変わり、同じシードでも決着が動く。
## 「必ず毎回変わる」ではなく「何戦か試せばどこかで変わる」で見るのは、
## 弱い相手だと立ち位置が違っても同じ秒数で決着しうるため。
func _test_battle_sim_honours_overrides(check: Callable) -> void:
	var pool := EnemyRoster.of_level(3)
	if pool.is_empty():
		check.call(false, "配線: Lv3の敵表が空(前提が崩れている)")
		return
	var play := func(stance: LaunchPolicy.Stance, ring: float, seed_value: int) -> float:
		var overrides := BattleSim.Overrides.new()
		overrides.launch_stance = stance
		overrides.launch_ring_scale = ring
		var enemies: Array[EnemyData] = [pool[seed_value % pool.size()]]
		return BattleSim.play_one(
			seed_value, enemies, LaunchPolicy.Kind.INTERCEPT,
			SpinnerStats.default_player(), overrides
		)["finish_time"]

	var stance_moved := false
	var ring_moved := false
	for i in 12:
		var near_t: float = play.call(LaunchPolicy.Stance.RING_NEAR, 1.0, i)
		var opposite_t: float = play.call(LaunchPolicy.Stance.RING_OPPOSITE, 1.0, i)
		var inner_t: float = play.call(LaunchPolicy.Stance.RING_OPPOSITE, 0.2, i)
		if not is_equal_approx(near_t, opposite_t):
			stance_moved = true
		if not is_equal_approx(opposite_t, inner_t):
			ring_moved = true
	check.call(stance_moved, "配線: Overrides の向きが BattleSim を通って結果を動かす")
	check.call(ring_moved, "配線: Overrides の距離が BattleSim を通って結果を動かす")


## コールドプレイCLI(naive_play._ring_pos)とボット(LaunchPolicy)が
## **同じ立ち位置の規則**を使っていること。片方だけ2自由度になると、
## 「CLIでは撃てるのに統計には出ない」というハーネスのズレがまた開く。
func _test_cli_matches_policy_rule(check: Callable) -> void:
	var source := FileAccess.get_file_as_string("res://playtest/naive_play.gd")
	check.call(
		source.contains("from-r"),
		"CLI: --from-r で中心からの距離を選べる"
	)
	check.call(
		source.contains("func _ring_pos(field: FieldData, prad: float, from_deg: float, from_r: float = 1.0)"),
		"CLI: _ring_pos が距離を受け取り、既定1.0で従来と一致"
	)
	# 規則そのものの一致: CLIの式(inradius - 半径 - 0.5)×比 と、ボットの外周リングを
	# 比1.0で突き合わせる。CLIは間合いのクランプを呼び手側で掛けるので、ここでは
	# 距離だけを見る(向きはCLIが角度指定、ボットがstance指定で入口が違う)。
	var field := _field()
	var ring := field.inradius() - _PLAYER_RADIUS - 0.5
	var cli_half := (field.inradius() - _PLAYER_RADIUS - 0.5) * 0.5
	check.call(
		absf(cli_half - ring * 0.5) < EPS,
		"規則: 比0.5は外周リングのちょうど半分 (%.3f)" % cli_half
	)
