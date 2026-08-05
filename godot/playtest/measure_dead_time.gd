extends SceneTree

## 「空転」——コマ同士が触れていない時間——を数える計測器。
##
## 発射後は入力が無いので、外した罰は「何も起きない画面を見る時間」になる。
## それが実際どれくらいなのかを、初接触までの時間と、戦闘時間に占める無接触の
## 割合で出す。あわせて PlaybackPacing の自動早送り(idle_speed_at)を通したときの
## 実再生秒数と、**記録された接触時刻での最大速度**(必ず1.0であること＝接触を
## 飛ばしていないこと)を出す。パラメータを振れるので、lead_in/ramp/倍率の
## 決め方をここで見てから Battle.gd の既定値にする。
##
## 壁への衝突は接触に数えない(PlaybackPacing.contact_span と同じ理由)。
##
##   godot --headless --path godot --script res://playtest/measure_dead_time.gd -- \
##       --count=800 --mult=3.0 --lead-in=0.8 --ramp=1.6

const DEFAULT_COUNT := 800
const STEP := 1.0 / 60.0
const POLICIES: Array[int] = [
	LaunchPolicy.Kind.RANDOM, LaunchPolicy.Kind.AIM_SPAWN, LaunchPolicy.Kind.INTERCEPT
]


func _init() -> void:
	var count := DEFAULT_COUNT
	var mult := 3.0
	var lead_in := 0.8
	var ramp := 1.6
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):
			count = int(arg.split("=")[1])
		elif arg.begins_with("--mult="):
			mult = float(arg.split("=")[1])
		elif arg.begins_with("--lead-in="):
			lead_in = float(arg.split("=")[1])
		elif arg.begins_with("--ramp="):
			ramp = float(arg.split("=")[1])

	print("== 空転の計測 (1レベルあたり%d戦, 倍率%.1f lead_in%.2f ramp%.2f) ==" % [
		count, mult, lead_in, ramp
	])
	print("初接触=発射から最初にコマ同士が触れるまでの秒数 / 無接触率=接触の無い時間の割合")
	print("再生=自動早送りを通したときの実時間 / 接触時速度=接触の瞬間の最大速度(1.00であること)")
	print("")
	print("Lv 方針       戦数 初接触p50 初接触p90 無接触率p50 決着→再生(p90)     決着→再生(最悪)   接触時速度")

	var field := BattleSim.default_field()
	for level in [1, 2, 3, 4, 5]:
		for policy in POLICIES:
			_measure(level, policy, count, field, mult, lead_in, ramp)
	quit()


func _measure(
	level: int, policy: int, count: int, field: FieldData,
	mult: float, lead_in: float, ramp: float
) -> void:
	var firsts: Array[float] = []
	var idle_shares: Array[float] = []
	var finishes: Array[float] = []
	var played: Array[float] = []
	var worst_at_contact := 0.0
	var n := 0
	for i in count:
		var seed_value := 4_100_000 + i * 7 + level * 3137 + policy * 101
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var pool := EnemyRoster.of_level(level)
		var enemies: Array[EnemyData] = [pool[rng.randi_range(0, pool.size() - 1)]]
		var r: Variant = _solve(seed_value, enemies, policy, SpinnerStats.new(), field)
		if r == null:
			continue
		n += 1
		var solved: Dictionary = r
		var times: PackedFloat32Array = solved["times"]
		var finish: float = solved["finish"]
		firsts.append(times[0] if not times.is_empty() else finish)
		finishes.append(finish)
		idle_shares.append(_idle_share(times, finish))
		played.append(_playback_seconds(times, finish, mult, lead_in, ramp))
		worst_at_contact = maxf(
			worst_at_contact, _speed_at_contacts(times, finish, mult, lead_in, ramp)
		)

	# 中央値ではなく**裾**を見ること。痛いのは「たまに来る十数秒の空転」で、
	# 中央値の戦闘は元から短く、縮めても縮まなくても手触りは変わらない。
	var fin90 := _pct(finishes, 0.9)
	var play90 := _pct(played, 0.9)
	var fin_max := _pct(finishes, 1.0)
	var play_max := _pct(played, 1.0)
	print("%d  %-9s %4d  %8.2f  %8.2f  %9.2f  %6.2f→%-6.2f %3.0f%%  %6.2f→%-6.2f %3.0f%%  %.2f" % [
		level, LaunchPolicy.NAMES[policy], n,
		_pct(firsts, 0.5), _pct(firsts, 0.9),
		_pct(idle_shares, 0.5),
		fin90, play90, 100.0 * (1.0 - play90 / maxf(fin90, 0.001)),
		fin_max, play_max, 100.0 * (1.0 - play_max / maxf(fin_max, 0.001)),
		worst_at_contact
	])


## 接触の無い時間が戦闘時間に占める割合。区間の境界は発射(0)と決着(finish)。
## 「接触の間隔のうち、余韻(lead_in相当)を除いてもなお空いている時間」ではなく
## 素の合計を出す——早送りの効き目ではなく、退屈さの生の量を見るため。
func _idle_share(times: PackedFloat32Array, finish: float) -> float:
	if finish <= 0.0:
		return 0.0
	if times.is_empty():
		return 1.0
	# 接触は瞬間なので、無接触時間＝全体から「接触の直後〜次の接触」を引くのではなく、
	# 最初の接触までと、決着までの尻尾の合計にする(噛み合っている最中は退屈ではない)。
	return clampf((times[0] + (finish - times[times.size() - 1])) / finish, 0.0, 1.0)


## 自動早送りを通したときに、決着まで何秒かかるか(実時間)。
func _playback_seconds(
	times: PackedFloat32Array, finish: float, mult: float, lead_in: float, ramp: float
) -> float:
	var t := 0.0
	var frames := 0
	while t < finish and frames < 200000:
		var span := PlaybackPacing.contact_span(times, t, finish)
		t += STEP * PlaybackPacing.idle_speed_at(
			t, span.x, span.y, mult, lead_in, ramp, -1.0, 0.28
		)
		frames += 1
	return frames * STEP


## 記録された接触時刻での最大速度。1.00でなければ接触を早送りで飛ばしている。
func _speed_at_contacts(
	times: PackedFloat32Array, finish: float, mult: float, lead_in: float, ramp: float
) -> float:
	var worst := 0.0
	for x in times:
		var span := PlaybackPacing.contact_span(times, x, finish)
		worst = maxf(
			worst,
			PlaybackPacing.idle_speed_at(x, span.x, span.y, mult, lead_in, ramp, -1.0, 0.28)
		)
	return worst


## BattleSim.play_one と同じ手順で1戦を解き、接触時刻と決着時刻だけ返す
## (play_one の戻り値は集計用のレコードで、接触の時刻までは持たない)。
func _solve(
	seed_value: int, enemies: Array[EnemyData], policy: int,
	stats: SpinnerStats, field: FieldData
) -> Variant:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var request := BattleRequest.new()
	request.arena_bounds = field.arena_bounds
	request.wall_shape = field.wall_shape
	request.obstacles = field.obstacles
	request.stage_strength = field.stage_strength
	request.stage_shape = field.stage_shape

	var plans: Array[EnemySpawn.Plan] = []
	var radii := PackedFloat32Array()
	var launches: Array[BattleRequest.Launch] = []
	var group := EnemySpawn.Group.new()
	var swirl := EnemySpawn.group_swirl_deg(enemies.size(), BattleSim.SPAWN_SWIRL_DEG, rng)
	for enemy in enemies:
		var plan := EnemySpawn.plan(
			field.center(), BattleSim.SPAWN_RING, LaunchSpeed.random(rng, enemy.stats.radius),
			BattleSim.SPAWN_SPREAD_DEG, rng, enemy.stats.radius, field.inradius(),
			group.avoid(), group.min_gap(enemy.stats.radius), field.obstacles, swirl
		)
		group.add(plan.position, enemy.stats.radius)
		plans.append(plan)
		radii.append(enemy.stats.radius)
		launches.append(BattleRequest.Launch.new(enemy.stats, plan.position, plan.velocity))
	var launch := LaunchPolicy.decide(policy, field, stats.radius, plans, radii, rng, 1.0)
	request.player = BattleRequest.Launch.new(stats, launch.position, launch.velocity)
	request.enemies = launches

	var result := BattleResolver.resolve(request)
	if result.finish_time <= 0.0:
		return null
	var times := PackedFloat32Array()
	for imp in result.impacts:
		times.append(imp.time)
	return {"times": times, "finish": result.finish_time}


func _pct(values: Array[float], q: float) -> float:
	if values.is_empty():
		return -1.0
	values.sort()
	return values[clampi(int(q * (values.size() - 1)), 0, values.size() - 1)]
