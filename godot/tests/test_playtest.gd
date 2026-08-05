extends RefCounted

## テストプレイハーネス自体のテスト。
##
## 検査器(PlaytestInvariants)が本当に壊れた結果を拾えるかを、壊れた結果を
## 手で作って確かめる。ここが節穴だと大量試行の意味がなくなる。
## リゾルバへの細工(sabotage)は開発時に手でやったが、これは常設の裏付け。

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_invariants_catch_bad_results(check)
	_test_invariants_pass_healthy_result(check)
	_test_battle_sim_deterministic(check)
	_test_battle_sim_spaces_group(check)
	_test_policies_stay_legal(check)
	_test_field_reaches_battle(check)
	_test_overrides_beat_field(check)
	_test_run_sim_consistent(check)
	_test_run_sim_forced_pick(check)
	_test_run_sim_continues(check)
	_test_run_sim_spare_core(check)
	_test_naive_play_card_text(check)
	_test_naive_play_launch_speed(check)
	_test_naive_play_pick_guard(check)
	_test_naive_play_result_label(check)
	_test_naive_play_remaining_text(check)
	_test_naive_play_death_cause_text(check)
	_test_naive_play_stop_text(check)
	_test_naive_play_ghost_text(check)
	_test_naive_play_victory_text(check)
	_test_naive_play_no_contact_note(check)
	_test_naive_play_stats_roundtrip(check)
	_test_naive_play_group_rewards(check)
	_test_naive_play_field_text(check)
	_test_naive_play_slope_text(check)
	_test_naive_play_card_preview(check)
	_test_naive_play_route_text(check)
	_test_naive_play_enemy_line(check)
	_test_naive_play_launch_lock(check)
	_test_naive_play_enter_guard(check)
	_test_naive_play_reward_guard(check)
	_test_naive_play_defeat_prompt(check)
	_test_naive_play_bseed_pin(check)
	_test_naive_play_group_persistence(check)
	_test_naive_play_spaces_group(check)


func _request() -> BattleRequest:
	var r := BattleRequest.new()
	r.player = BattleRequest.Launch.new(SpinnerStats.default_player(), Vector2(2, 8), Vector2(6, -6))
	var enemy := EnemyRoster.of_level(1)[0]
	r.enemies = [BattleRequest.Launch.new(enemy.stats, Vector2(8, 2), Vector2(-3, 4))]
	return r


func _healthy_result(request: BattleRequest) -> BattleResult:
	return BattleResolver.resolve(request)


func _test_invariants_catch_bad_results(check: Callable) -> void:
	var request := _request()

	# nan
	var bad := _healthy_result(request)
	bad.player_frames[3] = BattleResult.Snapshot.new(Vector2(NAN, 1.0), Vector2.ZERO, 5.0)
	check.call(
		not PlaytestInvariants.check(request, bad).is_empty(),
		"検査器: nanを拾う"
	)

	# アリーナ脱出
	bad = _healthy_result(request)
	bad.enemy_tracks[0][2] = BattleResult.Snapshot.new(Vector2(30.0, 5.0), Vector2.ZERO, 5.0)
	check.call(
		not PlaytestInvariants.check(request, bad).is_empty(),
		"検査器: アリーナ脱出を拾う"
	)

	# rpsの増加
	bad = _healthy_result(request)
	var f := bad.player_frames[5]
	bad.player_frames[5] = BattleResult.Snapshot.new(f.position, f.velocity, 999.0)
	check.call(
		not PlaytestInvariants.check(request, bad).is_empty(),
		"検査器: rpsの増加を拾う"
	)

	# 落ちたコマ(rps <= lose_threshold)は壁を抜けて場外へ出るのが仕様なので、
	# アリーナ外にいても脱出違反にはしない。生きているコマ(上の脱出テスト)とは扱いを分ける。
	# 以降のフレームもrpsを下げて閾値以下に揃える(rps増加違反を誘発しないため)。
	var dead := _healthy_result(request)
	for i in range(2, dead.enemy_tracks[0].size()):
		dead.enemy_tracks[0][i] = BattleResult.Snapshot.new(Vector2(30.0, 5.0), Vector2.ZERO, 0.0)
	check.call(
		PlaytestInvariants.check(request, dead).is_empty(),
		"検査器: 落ちたコマの場外脱出は見逃す (%s)" % [PlaytestInvariants.check(request, dead)]
	)

	# 戦闘の外の衝突時刻
	bad = _healthy_result(request)
	bad.impacts.append(BattleResult.Impact.new(bad.finish_time + 10.0, Vector2(5, 5)))
	check.call(
		not PlaytestInvariants.check(request, bad).is_empty(),
		"検査器: 範囲外の衝突時刻を拾う"
	)

	# フレーム数の不一致
	bad = _healthy_result(request)
	bad.enemy_tracks[0].pop_back()
	check.call(
		not PlaytestInvariants.check(request, bad).is_empty(),
		"検査器: フレーム数の不一致を拾う"
	)

	# 敵同士が重なった出現。EnemySpawn.Group を通し忘れた経路の症状そのもの。
	var overlapped := _request()
	var second := EnemyRoster.of_level(1)[1]
	var near := overlapped.enemies[0].position + Vector2(0.1, 0.0)
	overlapped.enemies.append(BattleRequest.Launch.new(second.stats, near, Vector2(2, -2)))
	check.call(
		not PlaytestInvariants.check(overlapped, _healthy_result(overlapped)).is_empty(),
		"検査器: 敵が重なった出現を拾う"
	)


func _test_invariants_pass_healthy_result(check: Callable) -> void:
	var request := _request()
	var violations := PlaytestInvariants.check(request, _healthy_result(request))
	check.call(
		violations.is_empty(),
		"検査器: 健全な結果は素通しする (%s)" % [violations]
	)


## ボットの乱戦が、実プレイと同じ間隔規則(EnemySpawn.Group)を通っていること。
##
## BattleSim は Battle._spawn_enemy と同じ手順を踏むと謳いながら avoid/min_gap だけを
## 渡しておらず、乱戦の組の13.1%が重なって湧いていた。統計の土台が実プレイと違う
## 条件になるので、検査器の常設違反(敵が重なって出現)を全戦闘に掛けたうえで、
## ここでも実ロスターの乱戦を回して0件であることを直接確かめる。
func _test_battle_sim_spaces_group(check: Callable) -> void:
	var stats := SpinnerStats.default_player()
	var violations := 0
	var battles := 0
	for i in 120:
		var rng := RandomNumberGenerator.new()
		rng.seed = 5000 + i
		var step := 1 + (i % 8)
		var enemies := EnemyRoster.pick_group_for_step(step, rng)
		if enemies.size() < 2:
			continue
		battles += 1
		var record := BattleSim.play_one(
			9000 + i, enemies, LaunchPolicy.Kind.INTERCEPT, stats,
			null, FieldRoster.pick_for_step(step, rng)
		)
		if record.has("violations"):
			violations += 1
	check.call(
		battles > 0 and violations == 0,
		"ボットの乱戦: 出現が重ならない (%d戦中 違反%d件)" % [battles, violations]
	)


func _test_battle_sim_deterministic(check: Callable) -> void:
	var enemy := EnemyRoster.of_level(2)[0]
	var enemies: Array[EnemyData] = [enemy]
	var stats := SpinnerStats.default_player()

	var a := BattleSim.play_one(42, enemies, LaunchPolicy.Kind.INTERCEPT, stats)
	var b := BattleSim.play_one(42, enemies, LaunchPolicy.Kind.INTERCEPT, stats)
	check.call(
		JSON.stringify(a) == JSON.stringify(b),
		"battle_sim: 同じシードなら同じレコード"
	)

	for key in ["seed", "level", "count", "policy", "win", "finish_time", "impacts"]:
		check.call(a.has(key), "battle_sim: レコードに %s がある" % key)

	var c := BattleSim.play_one(43, enemies, LaunchPolicy.Kind.INTERCEPT, stats)
	check.call(
		JSON.stringify(a) != JSON.stringify(c),
		"battle_sim: シードが違えば別の戦いになる"
	)


## どの土俵でも、ボットの発射が壁の内側から上限速度以下で出ること。
##
## 円形・八角形は矩形より内接円のぶん狭い。矩形クランプで済ませると角の方向で
## 壁の外から撃ててしまい、「外から助走をつける」ズルになる(実プレイでは
## Battle._clamp_launchが塞いでいる穴)。全フィールドを回して確かめる。
func _test_policies_stay_legal(check: Callable) -> void:
	var radius := 0.5
	var rng := RandomNumberGenerator.new()
	var worst_speed := 0.0

	for field in FieldRoster.all():
		var out_of_bounds := 0
		var limit := field.inradius() - radius
		for kind in LaunchPolicy.NAMES:
			for i in 50:
				rng.seed = i
				var plan := EnemySpawn.plan(
					field.center(), 4.0, 5.0, 30.0, rng, 0.5, field.inradius()
				)
				var plans: Array[EnemySpawn.Plan] = [plan]
				var launch := LaunchPolicy.decide(
					kind, field, radius, plans, PackedFloat32Array([0.5]), rng
				)
				worst_speed = maxf(worst_speed, launch.velocity.length())
				if field.wall_shape == ArenaWall.WallShape.RECT:
					var b := field.arena_bounds
					if (launch.position.x < b.position.x + radius - EPS
							or launch.position.x > b.end.x - radius + EPS
							or launch.position.y < b.position.y + radius - EPS
							or launch.position.y > b.end.y - radius + EPS):
						out_of_bounds += 1
				elif launch.position.distance_to(field.center()) > limit + EPS:
					out_of_bounds += 1
		check.call(
			out_of_bounds == 0,
			"発射方針: %s の内側から撃つ (%d件はみ出し)" % [field.title_key, out_of_bounds]
		)

	check.call(
		worst_speed <= LaunchPolicy.MAX_SPEED + EPS,
		"発射方針: 初速が上限以下 (最大 %.2f / 上限 %.0f)" % [worst_speed, LaunchPolicy.MAX_SPEED]
	)


## 土俵がリゾルバまで届くこと。ここが切れていると、計測だけが実プレイに存在
## しない土俵(既定の矩形すり鉢)で回り、数字が実態とずれる。
func _test_field_reaches_battle(check: Callable) -> void:
	var enemies: Array[EnemyData] = [EnemyRoster.of_level(1)[0]]
	var stats := SpinnerStats.default_player()

	for field in FieldRoster.all():
		var record := BattleSim.play_one(
			5, enemies, LaunchPolicy.Kind.INTERCEPT, stats, null, field
		)
		check.call(
			record["field"] == field.title_key,
			"battle_sim: 土俵がレコードに載る (%s)" % field.title_key
		)
		check.call(
			record["shape"] == int(field.stage_shape),
			"battle_sim: 土俵の傾斜がリクエストへ届く (%s)" % field.title_key
		)

	# 土俵が違えば戦いも違う。同じ結果になるなら、どこかで捨てられている。
	var plate: FieldData = null
	var pillars: FieldData = null
	for field in FieldRoster.all():
		if field.title_key == "FIELD_PLATE":
			plate = field
		elif field.title_key == "FIELD_PILLARS":
			pillars = field
	# 単一シードだと「柱に触れる前に決着した」だけで落ちうる(決着が速くなると起きる)。
	# 複数シードを見て、1本でも違えば土俵は届いている。
	var differs := false
	for seed_value in range(5, 25):
		var a := BattleSim.play_one(
			seed_value, enemies, LaunchPolicy.Kind.INTERCEPT, stats, null, plate)
		var b := BattleSim.play_one(
			seed_value, enemies, LaunchPolicy.Kind.INTERCEPT, stats, null, pillars)
		if a["finish_time"] != b["finish_time"] or a["impacts"] != b["impacts"]:
			differs = true
			break
	check.call(differs, "battle_sim: 土俵が変われば戦いも変わる")


## スイープの上書きは土俵より後に載ること。逆だとフィールドが上書きを潰して、
## スイープ表が全部同じ数字になる。
func _test_overrides_beat_field(check: Callable) -> void:
	var enemies: Array[EnemyData] = [EnemyRoster.of_level(1)[0]]
	var stats := SpinnerStats.default_player()
	var bowl: FieldData = null
	for field in FieldRoster.all():
		if field.title_key == "FIELD_BOWL":  # DISH固定の土俵
			bowl = field
	var overrides := BattleSim.Overrides.new()
	overrides.stage_shape = int(SpinnerPhysics.StageShape.CONE)

	var record := BattleSim.play_one(
		5, enemies, LaunchPolicy.Kind.INTERCEPT, stats, overrides, bowl
	)
	check.call(
		record["shape"] == int(SpinnerPhysics.StageShape.CONE),
		"battle_sim: スイープの上書きが土俵に勝つ"
	)


func _test_run_sim_consistent(check: Callable) -> void:
	for seed_value in [7, 8, 9]:
		var r := RunSim.play_one(seed_value, LaunchPolicy.Kind.INTERCEPT, RunSim.RewardPolicy.GREEDY)
		check.call(not r.has("error"), "run_sim: ランが完走する (seed %d)" % seed_value)
		check.call(r["battles"].size() > 0, "run_sim: 戦闘が記録される (seed %d)" % seed_value)

		# パーツはボス以外の勝利ごとに「倒した頭数」枚(乱戦は頭数ぶん報酬)。
		# クリアなら最後の勝利(ボス=単体)には付かないので1枚ぶん差し引く。
		var expected_parts := 0
		for b in r["battles"]:
			if b["win"]:
				expected_parts += int(b["count"])
		if r["cleared"]:
			expected_parts -= 1
		check.call(
			r["parts"].size() == expected_parts,
			"run_sim: パーツ数が倒した頭数と整合 (seed %d: %d枚 / 期待 %d)" % [
				seed_value, r["parts"].size(), expected_parts
			]
		)

		if r["cleared"]:
			check.call(r["died_at_step"] == -1, "run_sim: クリアなら死亡段がない")
		else:
			check.call(r["died_at_step"] >= 1, "run_sim: 死亡段が記録される")


## FORCED方針: 対象idが3択にあれば必ずそれを取る。ステータスを変えないSET_LIVES
## (greedyのtoughness選好では絶対選ばれない)を強制できることが肝。
func _test_run_sim_forced_pick(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	var stats := SpinnerStats.default_player()

	# 3択にSPARE_CORE(id8)を混ぜる。greedyなら硬さの上がるGiant Growth(id2)を選ぶが、
	# FORCEDならid8を選ぶ。
	var with_target: Array[CustomPart] = [
		CustomPartCatalog.by_id(2), CustomPartCatalog.by_id(8), CustomPartCatalog.by_id(5)
	]
	var picked := RunSim._choose_part(
		with_target, RunSim.RewardPolicy.FORCED, rng, stats, 8
	)
	check.call(picked.id == 8, "run_sim: FORCEDは対象id(残機札)を必ず取る (実際 %d)" % picked.id)

	# 対象が3択に無い回はgreedyに委譲する(3択の中から選ぶ)。
	var without_target: Array[CustomPart] = [
		CustomPartCatalog.by_id(2), CustomPartCatalog.by_id(5), CustomPartCatalog.by_id(6)
	]
	var fallback := RunSim._choose_part(
		without_target, RunSim.RewardPolicy.FORCED, rng, stats, 8
	)
	var ids := without_target.map(func(p): return p.id)
	check.call(
		ids.has(fallback.id),
		"run_sim: FORCEDは対象不在ならgreedyに委譲 (実際 %d)" % fallback.id
	)


## 残機(コンティニュー)の模擬。敗北しても残機がある限り再挑戦し、残機が尽きて
## 初めて力尽きる。実プレイのGameStateと同じ。SPARE_COREを取らないFORCED(質量)で
## 回すので残機の底上げは起きず、初期3から消費した分だけ減る。
func _test_run_sim_continues(check: Callable) -> void:
	var died_checked := false
	for seed_value in range(0, 30):
		var r := RunSim.play_one(
			seed_value, LaunchPolicy.Kind.INTERCEPT, RunSim.RewardPolicy.FORCED, null, 3
		)
		# SPARE_COREを取らないので残機は増えない: 消費+残 == 初期。
		check.call(
			r["continues_used"] + r["final_continues"] == RunSim.START_CONTINUES,
			"run_sim: 残機の収支が初期値と整合 (seed %d)" % seed_value
		)
		check.call(
			r["continues_used"] <= RunSim.START_CONTINUES,
			"run_sim: 消費残機が初期値以下 (seed %d)" % seed_value
		)
		# 肝: 残機がある限り死なない。死んだなら残機は必ず0。
		if not r["cleared"]:
			died_checked = true
			check.call(
				r["final_continues"] == 0,
				"run_sim: 残機がある限り死なない(死亡時は残0) (seed %d, 残%d)" % [
					seed_value, r["final_continues"]
				]
			)
	check.call(died_checked, "run_sim: 残機の死亡分岐を少なくとも1回検証した")


## SPARE_CORE(id8)を取ると残機が5へ底上げされる(GameState.apply_partのmaxiと同じ)。
## 取得後に一度も敗北しなければ残機は5のまま。固定シード集合なので決定的。
func _test_run_sim_spare_core(check: Callable) -> void:
	var acquired_any := false
	var max_continues := 0
	for seed_value in range(0, 60):
		var r := RunSim.play_one(
			seed_value, LaunchPolicy.Kind.INTERCEPT, RunSim.RewardPolicy.FORCED, null, 8
		)
		if r["parts"].has(8):
			acquired_any = true
			max_continues = maxi(max_continues, r["final_continues"])
	check.call(acquired_any, "run_sim: SPARE_COREを取得したランがある")
	check.call(
		max_continues > RunSim.START_CONTINUES,
		"run_sim: SPARE_COREで残機が初期(%d)を超える (最大 %d)" % [
			RunSim.START_CONTINUES, max_continues
		]
	)


## naive_play(コールドプレイCLI)のカード表記が実効果と一致することを固定する。
## 発見の経緯: RAGE/MOMENTUMがSTAT_MULTIPLY用の分岐に落ち、statの既定値MASSを
## 読んで「質量 ×1.10」と表示していた。コールドプレイは効果テキストだけで
## 報酬を選ぶ約束なので、表記が嘘だと選択の一次証拠が腐る。
func _test_naive_play_card_text(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	var rage := CustomPartCatalog.by_id(6)    # RAGE(反発+壁rps保持)
	var rage_text: String = NaivePlay.card_text(rage)
	check.call("反発" in rage_text, "naive_play: RAGE札は反発を謳う (%s)" % rage_text)
	check.call(not ("質量" in rage_text), "naive_play: RAGE札の表記に質量が混ざらない")
	# 壁rps保持(割合)はGUARD/EDGE/DRILLと同じ%表記で出すこと。生の「+0.17」は
	# 加算札の「回転+3.0」と並ぶと誤差にしか見えず読み違える(GUARDの一次証拠と同型)。
	check.call("17%" in rage_text and "50%" in rage_text,
		"naive_play: RAGE札の壁軽減は%%表記 (%s)" % rage_text)
	check.call(not ("0.17" in rage_text), "naive_play: RAGE札に生の小数を出さない (%s)" % rage_text)
	# 価値逆転(いつ効くか)も謳うこと。発見の経緯: 壁被弾ほぼゼロの序盤に効果文だけ
	# 読んで2回見送り、段5以降は壁喪失11〜17が支配的になって僅差負けした
	# (終盤はボス戦で壁20.0 vs 削り12.0と、壁が削りを上回ることさえある)。
	check.call("終盤" in rage_text and "壁" in rage_text,
		"naive_play: RAGE札は価値逆転(終盤は壁喪失が膨らむ)も謳う (%s)" % rage_text)
	var momentum := CustomPartCatalog.by_id(5)    # MOMENTUM(摩擦+回転減衰)
	var momentum_text: String = NaivePlay.card_text(momentum)
	check.call("回転減衰" in momentum_text, "naive_play: MOMENTUM札は回転減衰を謳う (%s)" % momentum_text)
	check.call(not ("質量" in momentum_text), "naive_play: MOMENTUM札の表記に質量が混ざらない")
	check.call("長持ち" in momentum_text, "naive_play: MOMENTUM札は挙動(回転が長持ち)も謳う (%s)" % momentum_text)
	# STAT_MULTIPLY札も実UI(describe)と同じ挙動注記をCLIに出すこと。
	# 発見の経緯: 「質量 ×1.30」だけでは対巨体の削り耐性だと読めず、実UIの
	# 報酬画面には見えている注記がCLIにだけ出ないまま質量札を見送って、
	# 段7のLv4(自分の2倍の質量)に削り交換で詰んだ。
	var mass := CustomPartCatalog.by_id(3)    # OVERENCUMBERED(質量UP)
	var mass_text: String = NaivePlay.card_text(mass)
	check.call(
		"削られにくく" in mass_text and "弾く" in mass_text,
		"naive_play: 質量UP札は挙動(削り耐性と弾き)を謳う (%s)" % mass_text
	)
	var spin := CustomPartCatalog.by_id(7)    # SPIN_ENGINE(回転UP)
	var spin_text: String = NaivePlay.card_text(spin)
	check.call("寿命" in spin_text, "naive_play: 回転UP札は挙動(寿命)を謳う (%s)" % spin_text)
	# GHOST(すり抜け)は利点(初撃は当たってから発動・反撃を受けない)まで謳うこと。
	# 発見の経緯: 「敵をすり抜ける」だけでは攻めが止まるデメリットに読め、性能は
	# COMMON上位(ラン相関+29pt)なのにコールドプレイで5提示5見送りだった。
	var ghost := CustomPartCatalog.by_id(9)
	var ghost_text: String = NaivePlay.card_text(ghost)
	check.call("すり抜ける" in ghost_text, "naive_play: ゴースト札はすり抜けを謳う (%s)" % ghost_text)
	check.call(
		"初撃" in ghost_text and "反撃" in ghost_text,
		"naive_play: ゴースト札は利点(初撃が当たる・反撃を受けない)も謳う (%s)" % ghost_text
	)
	# 注記は倍率の向きに追従すること(デバフ方向の札を仮に作って逆向きを確認)。
	var shrink := CustomPart.make(0, "T", CustomPart.Rarity.COMMON, CustomPart.Stat.MASS, 0.5)
	var shrink_text: String = NaivePlay.card_text(shrink)
	check.call("弾きにくい" in shrink_text, "naive_play: 質量DOWNは逆向きの注記になる (%s)" % shrink_text)
	# GROWTH(直径+質量の複合)は両方の効果と、代償(自然減衰の悪化)まで謳うこと。
	# 旧版(直径のみ)はCLIに代償が出ず、効果文だけで選ぶコールドプレイの罠だった。
	var growth := CustomPartCatalog.by_id(2)
	var growth_text: String = NaivePlay.card_text(growth)
	check.call("直径" in growth_text, "naive_play: 巨大化札は直径を謳う (%s)" % growth_text)
	check.call("質量" in growth_text, "naive_play: 巨大化札は質量も謳う (%s)" % growth_text)
	check.call("減衰" in growth_text, "naive_play: 巨大化札は代償(自然減衰)も謳う (%s)" % growth_text)
	# 利点(衝突耐性と弾き)も実UIの注記と同様に謳うこと。発見の経緯: 代償だけの表記を
	# 読んで、タンク型(硬さ1.76)に5連敗している最中に唯一の対抗札を2回見送った。
	check.call(
		"衝突に強く" in growth_text and "弾く" in growth_text,
		"naive_play: 巨大化札は利点(衝突耐性と弾き)も謳う (%s)" % growth_text
	)
	# 代償は「大きくなるぶん」と機構を明示すること(自然減衰は半径経由で悪化するので、
	# ステータス行のspin_decay=1.00と食い違って見える混乱があった)。
	check.call(
		"大きくなる" in growth_text,
		"naive_play: 巨大化札の代償は大きさ由来だと分かる (%s)" % growth_text
	)
	var lives := CustomPartCatalog.by_id(8)
	check.call("残機" in NaivePlay.card_text(lives), "naive_play: 残機札は残機を謳う")
	# SPIN_UP(回転加算)は加算量と上限、挙動(寿命)まで謳うこと。STAT_MULTIPLYの
	# 汎用分岐に落ちると既定のstat=MASSを読んで「質量 ×1.00」と嘘の表示になる。
	var winding := CustomPartCatalog.by_id(12)
	var winding_text: String = NaivePlay.card_text(winding)
	check.call(
		"回転 +3" in winding_text and "40" in winding_text,
		"naive_play: 回転加算札は加算量と上限を謳う (%s)" % winding_text
	)
	check.call("寿命" in winding_text, "naive_play: 回転加算札は挙動(寿命)も謳う (%s)" % winding_text)
	check.call(not ("質量" in winding_text), "naive_play: 回転加算札の表記に質量が混ざらない")


## naive_play(コールドプレイCLI)の発射速度が実ゲームと同じレンジであることを固定する。
## 実ゲーム(LaunchController)は full pull で LaunchSpeed.MAX を出す。発見の経緯:
## CLIに旧仕様(0〜20)の上限20.0が残り、実ゲームでは出せない1.67倍速の発射で全戦を
## 戦えていた(bot統計は正しく12で走っており、コールドプレイの実感だけが緩く汚れる)。
## CLI(naive_play)の乱戦も、実プレイと同じ間隔規則を通っていること。
##
## 自己改善サイクルのコールドプレイはこのCLIが唯一の遊ぶ手段なので、ここが実プレイと
## ずれると「一次証拠」そのものが嘘になる。実際2026-08-02のコールドプレイでは、
## 段2の3体戦で2体が0.25〜0.27秒で自壊して報酬3枚が転がり込んだ。
func _test_naive_play_spaces_group(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	var worst := INF
	var pairs := 0
	for i in 200:
		var rng := RandomNumberGenerator.new()
		rng.seed = 3300 + i
		var step := 1 + (i % 8)
		var enemies := EnemyRoster.pick_group_for_step(step, rng)
		if enemies.size() < 2:
			continue
		var field := FieldRoster.pick_for_step(step, rng)
		var plans: Array = NaivePlay._enemy_plans(enemies, field, 4400 + i)
		for a in plans.size():
			for b in range(a + 1, plans.size()):
				worst = minf(worst, plans[a].position.distance_to(plans[b].position)
					- enemies[a].stats.radius - enemies[b].stats.radius)
				pairs += 1
	check.call(
		pairs > 0 and worst >= 0.0,
		"naive_play: 乱戦の出現が重ならない (%d組の最小すきま %.3f)" % [pairs, worst]
	)


func _test_naive_play_launch_speed(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	var pos := Vector2(8.0, 2.0)
	var tgt := Vector2(5.0, 5.0)
	var full: Vector2 = NaivePlay.launch_velocity(pos, tgt, 1.0)
	check.call(
		absf(full.length() - LaunchSpeed.MAX) < EPS,
		"naive_play: force=1の発射速度が実ゲームの上限(%.1f)と一致 (%.1f)" % [LaunchSpeed.MAX, full.length()]
	)
	check.call(
		full.normalized().dot((tgt - pos).normalized()) > 1.0 - EPS,
		"naive_play: 発射は狙い点へ向く"
	)
	var over: Vector2 = NaivePlay.launch_velocity(pos, tgt, 5.0)
	check.call(
		absf(over.length() - LaunchSpeed.MAX) < EPS,
		"naive_play: force>1でも実ゲームの上限を超えない"
	)
	var half: Vector2 = NaivePlay.launch_velocity(pos, tgt, 0.5)
	check.call(
		absf(half.length() - LaunchSpeed.MAX * 0.5) < EPS,
		"naive_play: forceは速度に線形(0.5で半分)"
	)


## pickは直前のrewardで提示された札しか取れない。発見の経緯: 提示されていない
## id=2 を pick したら通ってしまい、ラン後半の一次証拠が壊れた。
func _test_naive_play_pick_guard(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	check.call(NaivePlay.pick_allowed([5, 7, 9], 7), "naive_play: 提示された札は取れる")
	check.call(not NaivePlay.pick_allowed([5, 7, 9], 2), "naive_play: 提示外の札は取れない")
	check.call(not NaivePlay.pick_allowed([], 2), "naive_play: 提示ゼロでは何も取れない")
	check.call(NaivePlay.pick_allowed([5.0, 7.0], 5), "naive_play: JSON経由のfloat idも照合できる")


## MOMENTUM/RAGE札の主効果(spin_decay/wall_keep)が状態JSONの往復で消えていた。
## 発見の経緯: コールドプレイでMOMENTUM札を3枚取っても寿命が全く伸びず、
## ボス戦の一次証拠が壊れた(摩擦・反発は残るので気づきにくい)。
func _test_naive_play_stats_roundtrip(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	var stats := SpinnerStats.default_player()
	CustomPartCatalog.by_id(5).apply_to(stats)    # MOMENTUM: spin_decayが下がる
	CustomPartCatalog.by_id(6).apply_to(stats)    # RAGE: wall_keepが上がる
	check.call(stats.spin_decay < 1.0 - EPS, "前提: MOMENTUM札でspin_decayが下がっている")
	check.call(stats.wall_keep > EPS, "前提: RAGE札でwall_keepが上がっている")
	var back: SpinnerStats = NaivePlay.stats_from(NaivePlay.stats_dict(stats))
	check.call(
		absf(back.spin_decay - stats.spin_decay) < EPS,
		"naive_play: spin_decay(MOMENTUM)が状態の往復で保存される")
	check.call(
		absf(back.wall_keep - stats.wall_keep) < EPS,
		"naive_play: wall_keep(RAGE)が状態の往復で保存される")
	check.call(
		absf(back.mass - stats.mass) < EPS and absf(back.rps - stats.rps) < EPS
			and absf(back.friction - stats.friction) < EPS
			and absf(back.restitution - stats.restitution) < EPS
			and absf(back.radius - stats.radius) < EPS,
		"naive_play: 既存フィールドも往復で保存される")
	# 旧stateファイル(キー欠落)は既定値で読めること(後方互換)。
	var legacy: SpinnerStats = NaivePlay.stats_from(
		{"mass": 1.5, "radius": 0.7, "friction": 0.98, "restitution": 0.75, "rps": 15.0})
	check.call(
		absf(legacy.spin_decay - 1.0) < EPS and absf(legacy.wall_keep) < EPS,
		"naive_play: 旧state(キー欠落)は既定値で読める")


## 実ゲーム(Main)は乱戦で倒した頭数ぶん報酬を選べるが、CLIは頭数によらず1枚だった。
## 発見の経緯: コールドプレイで2体戦に勝っても報酬が1枚しか出ず、実ゲームより
## ビルドが痩せたまま後半へ進んでいた。
func _test_naive_play_group_rewards(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	check.call(NaivePlay.rewards_for_group(1) == 1, "naive_play: 単体撃破は報酬1回")
	check.call(NaivePlay.rewards_for_group(2) == 2, "naive_play: 2体乱戦は報酬2回")
	check.call(NaivePlay.rewards_for_group(3) == 3, "naive_play: 3体乱戦は報酬3回")
	check.call(NaivePlay.rewards_for_group(0) == 1, "naive_play: 0体でも最低1回(Mainのmaxiと同じ)")


## 土俵表示に柱(障害物)が出ること。発見の経緯: 実ゲームではArenaが柱を描いて
## プレイヤーに見えているのに、CLIの土俵行には出ておらず、PILLARS土俵で見えない
## 柱に向かって盲目で狙いを決めていた(コールドプレイの一次証拠の欠落)。
func _test_naive_play_field_text(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	var pillars: FieldData = null
	var classic: FieldData = null
	for field in FieldRoster.all():
		if field.title_key == "FIELD_PILLARS":
			pillars = field
		elif field.title_key == "FIELD_CLASSIC":
			classic = field
	var text: String = NaivePlay.field_text(pillars)
	check.call("柱" in text, "naive_play: PILLARS土俵は柱を表示する (%s)" % text)
	check.call(
		pillars.obstacles.size() > 0,
		"前提: PILLARS土俵に障害物がある")
	for o in pillars.obstacles:
		check.call(
			("(%.1f,%.1f)r%.1f" % [o.x, o.y, o.z]) in text,
			"naive_play: 柱の位置と半径が表示に載る (%.1f,%.1f)r%.1f" % [o.x, o.y, o.z])
	var plain: String = NaivePlay.field_text(classic)
	check.call(not ("柱" in plain), "naive_play: 柱の無い土俵に柱表記は出ない (%s)" % plain)
	check.call("形状=RECT" in plain, "naive_play: 従来の土俵情報(壁形状)も出る")


## 土俵の傾斜がCLIに出ること。実UIはマップのノードにケバ(StageSlopeMark)を、
## 対戦画面の床に等高線(SlopeContour)を描いているのに、CLIには名前しか無かった。
##
## 発見の経緯(コールドプレイ 2026-08-05, seed=48231): 矩形・柱なしの3土俵
## FIELD_CLASSIC / FIELD_BOWL / FIELD_PLATE は、この行が無いと土俵表示が
## 一字一句同じで区別が付かない。実際には縁の引き戻しが3倍違う。
func _test_naive_play_slope_text(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	var by_key := {}
	for field in FieldRoster.all():
		by_key[field.title_key] = field
	var classic: FieldData = by_key["FIELD_CLASSIC"]
	var bowl: FieldData = by_key["FIELD_BOWL"]
	var plate: FieldData = by_key["FIELD_PLATE"]

	# 前提: この3つは壁形状・範囲・柱がすべて同じ(=傾斜以外に区別が無い)。
	check.call(
		classic.wall_shape == bowl.wall_shape and classic.wall_shape == plate.wall_shape
		and classic.arena_bounds == bowl.arena_bounds
		and classic.arena_bounds == plate.arena_bounds
		and classic.obstacles.is_empty() and bowl.obstacles.is_empty()
		and plate.obstacles.is_empty(),
		"前提: CLASSIC/BOWL/PLATEは傾斜以外の土俵情報が同一")

	# 傾斜の形。すり鉢(DISH)と円錐(CONE)が呼び分けられること。
	check.call(
		NaivePlay.slope_shape_name(classic) == "すり鉢",
		"naive_play: DISH土俵はすり鉢と呼ぶ (%s)" % NaivePlay.slope_shape_name(classic))
	check.call(
		NaivePlay.slope_shape_name(plate) == "円錐",
		"naive_play: CONE土俵は円錐と呼ぶ (%s)" % NaivePlay.slope_shape_name(plate))

	# 3つの土俵行がすべて互いに異なること(この変更の目的そのもの)。
	var t_classic: String = NaivePlay.field_text(classic)
	var t_bowl: String = NaivePlay.field_text(bowl)
	var t_plate: String = NaivePlay.field_text(plate)
	check.call(t_classic != t_bowl, "naive_play: CLASSICとBOWLの土俵行が区別できる")
	check.call(t_classic != t_plate, "naive_play: CLASSICとPLATEの土俵行が区別できる")
	check.call(t_bowl != t_plate, "naive_play: BOWLとPLATEの土俵行が区別できる")

	# 値は実UIと同じ関数から借りること(2箇所に式を書くと絵と数字が食い違う)。
	for field in [classic, bowl, plate]:
		var text: String = NaivePlay.field_text(field)
		check.call(
			("縁の引き戻し=%.1f" % StageSlopeMark.rim_pull(field)) in text,
			"naive_play: 縁の引き戻しはStageSlopeMark.rim_pullの値 (%s)" % text)
		check.call(
			("等高線=%d本" % SlopeContour.ring_count(field)) in text,
			"naive_play: 等高線の本数はSlopeContour.ring_countの値 (%s)" % text)
		check.call(
			("強さ=%.1f" % field.stage_strength) in text,
			"naive_play: 傾斜の強さが出る (%s)" % text)

	# 急な土俵ほどケバが多い(印としての向きが正しいこと)。
	check.call(
		StageSlopeMark.rim_pull(bowl) > StageSlopeMark.rim_pull(plate),
		"前提: BOWL(すり鉢8.0)はPLATE(円錐3.0)より縁の引き戻しが強い")
	check.call(
		StageSlopeMark.tick_count(bowl) > StageSlopeMark.tick_count(plate),
		"naive_play: 急な土俵ほどケバが多い")

	# 部屋を選ぶ時点(=進める先/盤面)でも読めること。実UIのマップは全戦闘ノードに
	# ケバを描いているので、選択の1画面手前に無いと意味がない。
	var mark_bowl: String = NaivePlay.slope_mark(bowl)
	var mark_plate: String = NaivePlay.slope_mark(plate)
	check.call(mark_bowl != mark_plate, "naive_play: 選択時点の傾斜の印が土俵で違う")
	check.call(
		("%d本" % StageSlopeMark.tick_count(bowl)) in mark_bowl,
		"naive_play: 印のケバ本数はStageSlopeMark.tick_countの値 (%s)" % mark_bowl)

	# nullの土俵で落ちない(旧stateや手組みのノードから呼ばれても壊れない)。
	check.call(NaivePlay.slope_mark(null) == "", "naive_play: 土俵nullで印は空文字")
	check.call(NaivePlay.slope_text(null) == "", "naive_play: 土俵nullで傾斜行は空文字")

	# 進める先の行にも印が載ること(選択の1画面手前)。
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tree := MapTree.generate(rng)
	var checked := 0
	for coord in tree.nodes:
		var n: MapTree.MapNode = tree.nodes[coord]
		if not n.has_encounter():
			continue
		var line: String = NaivePlay.route_text(coord.y, n, null)
		check.call(
			NaivePlay.slope_mark(n.field) in line,
			"naive_play: 進める先の行に傾斜の印が載る (%s)" % line)
		var cell: String = NaivePlay.map_cell_text(coord.y, n)
		check.call(
			("%s%d" % [
				NaivePlay.slope_shape_name(n.field),
				StageSlopeMark.tick_count(n.field)]) in cell,
			"naive_play: 盤面の俯瞰にも傾斜が載る (%s)" % cell)
		checked += 1
	check.call(checked > 0, "前提: 傾斜の印を検査した戦闘ノードがある")


## 報酬カードに実UIと同じ「取るとどう変わるか」(硬さ/寿命)が出ること。
##
## 発見の経緯(コールドプレイ 2026-08-05, seed=48231): 実UIのRewardScreenは
## 2026-08-02から PartPreview.rows をカードに出しているのに、CLIには効果文しか
## 無かった。結果、段1でGIANT_GROWTHを「自然減衰が速まる」がデメリットに読めて
## 見送った——PartPreviewのdocが「この死に方を潰すために作った」と名指ししている
## 見送り方そのもので、直したはずの穴をCLIだけが踏み続けていた。
func _test_naive_play_card_preview(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	var stats := SpinnerStats.default_player()

	# 硬さと寿命は、動かさない札でも常に出す(実UIと同じ規則。「この札では硬さが
	# 伸びない」ことも選択に必要な情報)。
	var edge := CustomPartCatalog.by_id(11)    # SHARP_EDGE(硬さも寿命も動かさない)
	var edge_text: String = NaivePlay.card_preview_text(stats, edge)
	check.call("硬さ" in edge_text, "naive_play: 硬さの行は変化しない札でも出る (%s)" % edge_text)
	check.call("寿命" in edge_text, "naive_play: 寿命の行は変化しない札でも出る (%s)" % edge_text)
	check.call(
		not ("→" in edge_text),
		"naive_play: 動かさない札に矢印を出さない(誤読を招く) (%s)" % edge_text)

	# 巨大化は硬さを上げ寿命を下げる。両方が数字で見えること。
	var growth := CustomPartCatalog.by_id(2)    # GIANT_GROWTH
	var after := PartPreview.preview_stats(stats, growth)
	check.call(
		PartPreview.toughness(after) > PartPreview.toughness(stats)
		and PartPreview.lifetime(after) < PartPreview.lifetime(stats),
		"前提: 巨大化は硬さを上げ寿命を下げる")
	var growth_text: String = NaivePlay.card_preview_text(stats, growth)
	check.call(
		("%s → %s" % [
			String.num(PartPreview.toughness(stats), 2),
			String.num(PartPreview.toughness(after), 2)]) in growth_text,
		"naive_play: 硬さの変化が実UIと同じ桁で出る (%s)" % growth_text)
	check.call(
		("%s → %s" % [
			String.num(PartPreview.lifetime(stats), 1),
			String.num(PartPreview.lifetime(after), 1)]) in growth_text,
		"naive_play: 寿命の変化が実UIと同じ桁で出る (%s)" % growth_text)

	# 値は PartPreview から借りること(2箇所に式を書くと実UIとCLIが別の数字を出す)。
	for id in [2, 3, 5, 7, 11, 12, 14]:
		var part := CustomPartCatalog.by_id(id)
		var text: String = NaivePlay.card_preview_text(stats, part)
		for row in PartPreview.rows(stats, part):
			check.call(
				PartPreview.format_row(row) in text,
				"naive_play: id=%d の行が PartPreview と一致する (%s)" % [id, text])

	# コマの性能を変えない札(残機・ゴースト)は、ラン側の効果を行として補う
	# ——硬さ/寿命だけだと「何も起きない札」に見える(実UIと同じ規則)。
	var spare := CustomPartCatalog.by_id(8)    # SPARE_CORE(残機を5にする)
	var spare_text: String = NaivePlay.card_preview_text(stats, spare, 2)
	check.call("残機 2 → 5" in spare_text, "naive_play: 残機札は残機の行を出す (%s)" % spare_text)
	check.call(
		not ("残機" in NaivePlay.card_preview_text(stats, edge, 2)),
		"naive_play: 残機を動かさない札に残機の行は出ない")
	var ghost := CustomPartCatalog.by_id(9)    # GHOST
	var ghost_text: String = NaivePlay.card_preview_text(stats, ghost, 2, 0.0)
	check.call("無敵時間" in ghost_text, "naive_play: ゴースト札は無敵時間の行を出す (%s)" % ghost_text)

	# ラベルは翻訳キーのままにしない(STAT_TOUGHNESS/STAT_LIFETIMEでは区別が付かない)。
	check.call(
		not ("STAT_" in growth_text),
		"naive_play: 生の翻訳キーを出さない (%s)" % growth_text)

	# プレビューは元のステータスを壊さない(表示のたびにコマが育ってはならない)。
	var before_mass := stats.mass
	var before_radius := stats.radius
	NaivePlay.card_preview_text(stats, growth, 2)
	check.call(
		is_equal_approx(stats.mass, before_mass) and is_equal_approx(stats.radius, before_radius),
		"naive_play: プレビューが元のステータスを書き換えない")

	# 欠けた引数で落ちない。
	check.call(NaivePlay.card_preview_text(null, growth) == "", "naive_play: stats nullで空文字")
	check.call(NaivePlay.card_preview_text(stats, null) == "", "naive_play: part nullで空文字")


## 進める先の行に、敵数(リスク)と対で報酬枚数(リターン=倒した頭数ぶん)が出ること。
## 以前は敵数しか出ておらず、頭数ぶん報酬のルールを知らない初見プレイヤーには乱戦が
## 「リスクだけの部屋」に読めて全戦で最少体数ノードを選んでいた(コールドプレイの
## 一次証拠)。実UIのマップも同じ情報を金ピップで見せる(reward_count()が共通の出所)。
## ゴール(ボス)は報酬選択が無いので報酬枚数の代わりに「撃破でクリア」を出す。
func _test_naive_play_route_text(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	var rng := RandomNumberGenerator.new()
	var single: MapTree.MapNode = null
	var group: MapTree.MapNode = null
	var goal: MapTree.MapNode = null
	for trial in 30:
		rng.seed = trial
		var tree := MapTree.generate(rng)
		goal = tree.nodes[MapTree.GOAL_COORD]
		for coord in tree.nodes:
			var n: MapTree.MapNode = tree.nodes[coord]
			if not n.has_encounter() or coord == MapTree.GOAL_COORD:
				continue
			if n.enemy_count() >= 2 and group == null:
				group = n
			elif n.enemy_count() == 1 and not n.is_vanguard() and single == null:
				# 斥候(格上の単体)はレア倍率が出る側なので、素の単体ノードだけを拾う。
				single = n
		if single != null and group != null:
			break
	check.call(single != null and group != null, "前提: 単体ノードと乱戦ノードが見つかる")

	var single_text: String = NaivePlay.route_text(1, single)
	check.call(
		"1体→報酬1枚" in single_text,
		"naive_play: 単体ノードは報酬1枚が読める (%s)" % single_text)
	check.call(
		not ("レア" in single_text),
		"naive_play: 単体ノードにレア倍率は出ない(単体は従来抽選のまま) (%s)" % single_text)
	var group_text: String = NaivePlay.route_text(-2, group)
	check.call(
		("%d体→報酬%d枚" % [group.enemy_count(), group.enemy_count()]) in group_text,
		"naive_play: 乱戦ノードは頭数ぶんの報酬枚数が読める (%s)" % group_text)
	check.call(
		("レア出やすさ×%.2f" % RewardQuality.ratio_for_node(group)) in group_text,
		"naive_play: 乱戦ノードはレアの出やすさ(頭数倍)が読める (%s)" % group_text)
	check.call(group_text.begins_with("col-2"), "naive_play: 列表記は従来どおり (%s)" % group_text)

	# 斥候(格上の単体)の見返り。実UIは報酬ピップの色で出しており(RewardQuality)、
	# CLIに無いままだとコールドプレイのエージェントだけが「格上を選ぶ理由」を
	# 一言も知らずに部屋を選ぶ。ハーネスと実ゲームの情報量は対等に保つ約束。
	var vanguard: MapTree.MapNode = MapTree.MapNode.new(Vector2i(2, 2))
	vanguard.enemies = [EnemyRoster.of_level(EnemyRoster.level_for_step(2) + 1)[0]]
	vanguard.field = single.field
	var vanguard_text: String = NaivePlay.route_text(1, vanguard)
	check.call(
		("レア出やすさ×%.2f" % RewardQuality.ratio_for_node(vanguard)) in vanguard_text,
		"naive_play: 斥候(格上の単体)もレアの出やすさが読める (%s)" % vanguard_text)
	check.call(
		RewardQuality.ratio_for_node(vanguard) > 1.0,
		"naive_play: 斥候の倍率は基準より大きい (%s)" % vanguard_text)

	# 相手の硬さの取り分。実UIのマップに載ったメーターのCLI版で、**値も判定も
	# ThreatMeter と一致していなければならない**——ここがずれると、コールドプレイの
	# エージェントと実プレイヤーが違う情報で部屋を選ぶ(過去4回踏んだ型のズレ)。
	var player := SpinnerStats.default_player()
	var lv1: MapTree.MapNode = MapTree.MapNode.new(Vector2i(1, 2))
	lv1.enemies = EnemyRoster.of_level(1)
	lv1.field = single.field
	var lv3: MapTree.MapNode = MapTree.MapNode.new(Vector2i(5, 2))
	lv3.enemies = EnemyRoster.of_level(3)
	lv3.field = single.field

	var lv1_text: String = NaivePlay.route_text(1, lv1, player)
	var lv3_text: String = NaivePlay.route_text(1, lv3, player)
	check.call(
		("%.2f" % ThreatMeter.share(player, lv1.enemies)) in lv1_text,
		"naive_play: 取り分の値がThreatMeterと一致 (%s)" % lv1_text)
	check.call(
		"格下" in lv1_text and not ("格上" in lv1_text),
		"naive_play: 初期ビルドから見てLv1は格下と出る (%s)" % lv1_text)
	check.call(
		"格上" in lv3_text,
		"naive_play: 初期ビルドから見てLv3は格上と出る (%s)" % lv3_text)
	check.call(
		not ("取り分" in NaivePlay.route_text(1, lv3)),
		"naive_play: 自分のビルドを渡さなければ従来どおり何も足さない")

	var goal_text: String = NaivePlay.route_text(2, goal)
	check.call(
		"撃破でクリア" in goal_text,
		"naive_play: ボスは報酬でなくクリアを謳う (%s)" % goal_text)
	check.call(
		not ("→報酬" in goal_text),
		"naive_play: ボスに報酬枚数は出ない(勝てば即クリアで報酬選択が無い) (%s)" % goal_text)


## 敵の予告行に質量と硬さ(質量×半径²)が出ること。壁へ弾き飛ばせる相手か
## どうかの読み合い材料で、実UIのリム表示(DiscWeightVisual)と対になる。
## 発見の経緯: 質量がCLI・実UIのどこにも出ておらず、Lv4/ボスの巨体への
## 壁弾きが撃つまで分からない賭けになっていた(コールドプレイの一次証拠)。
func _test_naive_play_enemy_line(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	var e := EnemyRoster.of_level(4)[2]  # ENEMY_4_3: Lv4最重量級
	var pl := EnemySpawn.Plan.new(Vector2(8, 2), Vector2(-3, 4))
	var line: String = NaivePlay.enemy_line(0, e, pl, 0.7, 5.0)
	check.call(
		("質量=%.1f" % e.stats.mass) in line,
		"naive_play: 敵行に質量が出る (%s)" % line)
	check.call(
		("硬さ=%.2f" % (e.stats.mass * e.stats.radius * e.stats.radius)) in line,
		"naive_play: 敵行に硬さ(質量×半径²)が出る")
	check.call(
		"enemy1" in line and "寿命目安=" in line and "間合い=" in line and "rps=" in line,
		"naive_play: 従来の敵情報(寿命目安・間合い・rps)も残る")


## launchの結果(勝敗)が状態に保存され、確定後の撃ち直しを受け付けないこと。
## 発見の経緯: 敗北が状態に残らず、残機を消費せずに同じノードを何度でも
## 撃ち直せた(勝利側も撃ち直すたびに勝利成長rpsを二重取りできた)。
func _test_naive_play_launch_lock(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	var state := {"pending": 2, "must_retry": false, "won": false}
	check.call(NaivePlay.launch_block_reason(state) == "", "naive_play: 交戦中は撃てる")
	NaivePlay.mark_defeat(state)
	check.call(
		NaivePlay.launch_block_reason(state) != "",
		"naive_play: 敗北後はretry/giveup以外を受け付けない")
	var won_state := {"pending": 2, "must_retry": false, "won": true}
	check.call(
		NaivePlay.launch_block_reason(won_state) != "",
		"naive_play: 勝利後の撃ち直し(勝利成長の二重取り)を受け付けない")
	check.call(
		NaivePlay.launch_block_reason({"pending": null}) != "",
		"naive_play: 交戦外では撃てない")
	check.call(
		NaivePlay.launch_block_reason({"pending": 1}) == "",
		"naive_play: 旧state(キー欠落)は従来どおり撃てる(後方互換)")


## enterは交戦が解決するまで受け付けないこと。発見の経緯: enterだけがノーガードで、
## (1)乱戦の報酬が残ったままenterすると黙って放棄になり(案内1行の見落としで実害)、
## (2)敗北後にenterで別ノードへ移ると残機を消費せず負けを消せ、(3)発射前でもbseedを
## 変えてenterし直すと敵の出現を無料で再抽選できた。実ゲームはノード選択→戦闘が
## 一方通行で、どの経路も存在しない。
func _test_naive_play_enter_guard(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	check.call(
		NaivePlay.enter_block_reason({"pending": null}) == "",
		"naive_play: 交戦外はenterできる")
	var won_rewards := {"pending": 2, "must_retry": false, "won": true, "rewards_left": 2}
	var r1: String = NaivePlay.enter_block_reason(won_rewards)
	check.call(r1 != "", "naive_play: 乱戦報酬が残ったままのenterは拒否(黙った放棄の防止)")
	check.call("2" in r1 and "reward" in r1, "naive_play: 拒否理由に残り回数と受け取り方を出す")
	var won_state := {"pending": 2, "must_retry": false, "won": true, "rewards_left": null}
	check.call(
		NaivePlay.enter_block_reason(won_state) != "",
		"naive_play: 勝利未確定(reward前)のenterは拒否")
	var defeated := {"pending": 2, "must_retry": true, "won": false}
	var r2: String = NaivePlay.enter_block_reason(defeated)
	check.call(r2 != "", "naive_play: 敗北後のenterは拒否(残機を消費しない逃亡の防止)")
	check.call("retry" in r2 and "giveup" in r2, "naive_play: 敗北後の拒否理由は出口(retry/giveup)を案内する")
	check.call(
		NaivePlay.enter_block_reason({"pending": 2, "must_retry": false, "won": false}) != "",
		"naive_play: 発射前のenterし直しは拒否(予告の無料再抽選の防止)")
	check.call(
		NaivePlay.enter_block_reason({"pending": 1}) != "",
		"naive_play: 旧state(キー欠落)もpendingが残っていれば拒否")
	check.call(
		NaivePlay.enter_block_reason({"pending": null, "dead": true}) != "",
		"naive_play: giveup済みのランではenterできない(死んだランの蘇生防止)")
	check.call(
		NaivePlay.enter_block_reason({"pending": null, "cleared": true}) != "",
		"naive_play: クリア済みのランではenterできない")


## rewardとpickは勝利済みの戦闘でしか受け付けないこと。発見の経緯: launch側の
## ロックだけで、敗北後(must_retry)や発射前(won=false)でも reward→pick が通り、
## 負けた/戦っていないノードを残機を減らさず突破確定できる裏口があった。
func _test_naive_play_reward_guard(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	var won_state := {"pending": 2, "must_retry": false, "won": true}
	check.call(
		NaivePlay.reward_block_reason(won_state) == "",
		"naive_play: 勝利後はrewardを受け付ける")
	var defeated := {"pending": 2, "must_retry": true, "won": false}
	check.call(
		NaivePlay.reward_block_reason(defeated) != "",
		"naive_play: 敗北後のreward/pickは拒否(負けたノードの突破の裏口)")
	var before_launch := {"pending": 2, "must_retry": false, "won": false}
	check.call(
		NaivePlay.reward_block_reason(before_launch) != "",
		"naive_play: 発射前のreward/pickは拒否(戦闘スキップの裏口)")
	check.call(
		NaivePlay.reward_block_reason({"pending": null}) != "",
		"naive_play: 交戦外のreward/pickは拒否")
	check.call(
		NaivePlay.reward_block_reason({"pending": 1}) == "",
		"naive_play: 旧state(キー欠落)は従来どおり(後方互換)")


## 敗北直後の案内は「retryで1消費して残る数」まで出すこと。発見の経緯: 消費前の
## 所持数だけが出ており、「(残機3)」表示→retryすると「残り2」と数字が食い違って
## 見えた。残機0はretryできないのでgiveupだけを案内する。
func _test_naive_play_defeat_prompt(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	var p: String = NaivePlay.defeat_prompt(3)
	check.call(
		"retry" in p and "残り2" in p,
		"naive_play: 敗北案内は消費後に残る残機を明示する")
	check.call("giveup" in p, "naive_play: 敗北案内はgiveupも常に出す")
	var zero: String = NaivePlay.defeat_prompt(0)
	check.call(
		not "retry" in zero and "giveup" in zero,
		"naive_play: 残機0の敗北案内はgiveupのみ")


## launchは予告(enter/retry)時のbseedで解決すること。発見の経緯: 引数のbseedを
## そのまま使っており、予告と違う敵で戦える=テレグラフを読む工程が嘘になる穴。
func _test_naive_play_bseed_pin(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	check.call(
		NaivePlay.launch_bseed({"bseed": 1111}, 9999) == 1111,
		"naive_play: 保存済みbseedを優先する(予告と同じ敵で解決)")
	check.call(
		NaivePlay.launch_bseed({"bseed": 1111.0}, 9999) == 1111,
		"naive_play: JSON経由のfloat bseedも整数で読める")
	check.call(
		NaivePlay.launch_bseed({"bseed": null}, 9999) == 9999,
		"naive_play: bseed未保存(旧state)は引数を使う")
	check.call(
		NaivePlay.launch_bseed({}, 7) == 7,
		"naive_play: キー欠落(旧state)も引数を使う")


## 引き分けは進行上は敗北扱いだが、表示では区別する。発見の経緯: DRAWが
## 「敗北 死因=? loser=none」と出て、なぜ負けたのか分からなかった。
func _test_naive_play_result_label(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	check.call(
		"勝利" in NaivePlay.result_label(BattleResult.Outcome.PLAYER_WIN),
		"naive_play: PLAYER_WINは勝利表示")
	check.call(
		"引き分け" in NaivePlay.result_label(BattleResult.Outcome.DRAW),
		"naive_play: DRAWは引き分けと明示")
	check.call(
		NaivePlay.result_label(BattleResult.Outcome.ENEMY_WIN) == "敗北",
		"naive_play: ENEMY_WINは敗北表示")


## 終了時の残りrps表示。発見の経緯: 喪失内訳(削り14.6 壁11.6 減衰1.5)を手で
## 合算しないと「28.0中27.7を失う残り0.3の辛勝」が読めず、コールドプレイが
## ボス戦を楽勝と誤読していた(実UIなら再生中のrpsバーで見えている情報)。
func _test_naive_play_remaining_text(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	var frames: Array[BattleResult.Snapshot] = [
		BattleResult.Snapshot.new(Vector2.ZERO, Vector2.ZERO, 28.0),
		BattleResult.Snapshot.new(Vector2.ZERO, Vector2.ZERO, 14.0),
		BattleResult.Snapshot.new(Vector2.ZERO, Vector2.ZERO, 0.3),
	]
	check.call(
		NaivePlay.remaining_text("自分", frames) == "自分 0.3/28.0(1%)",
		"naive_play: 残りrpsは最終値/開始値と残存率で出す")
	var alive: Array[BattleResult.Snapshot] = [
		BattleResult.Snapshot.new(Vector2.ZERO, Vector2.ZERO, 20.0),
		BattleResult.Snapshot.new(Vector2.ZERO, Vector2.ZERO, 15.0),
	]
	check.call(
		NaivePlay.remaining_text("enemy1", alive) == "enemy1 15.0/20.0(75%)",
		"naive_play: 生き残り側の残量も同じ形式で読める")
	check.call(
		NaivePlay.remaining_text("自分", []) == "",
		"naive_play: フレーム欠落(旧結果)は空文字で行ごと省く")
	# 実リゾルバの結果とも整合すること(開始値=発射時rps、最終値=最終フレーム)。
	var request := _request()
	var result := _healthy_result(request)
	var text: String = NaivePlay.remaining_text("自分", result.player_frames)
	check.call(
		"/%.1f" % request.player.stats.rps in text,
		"naive_play: 開始値は発射時のrpsと一致する")
	check.call(
		text.begins_with("自分 %.1f/" % result.player_frames[result.player_frames.size() - 1].rps),
		"naive_play: 最終値は最終フレームのrpsと一致する")


## 死因トークンの表示。発見の経緯: 「死因=drain ... 決着死因=drain」の生トークンが
## 初見で読めず、喪失内訳行の「削り/壁/減衰」と同じ現象なのに語彙が繋がらなかった
## (2026-07-28のコールドプレイ)。内訳と同じ日本語を主にしてトークンを併記する。
func _test_naive_play_death_cause_text(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	check.call(
		"削り" in NaivePlay.death_cause_text("drain"),
		"naive_play: 死因drainは内訳と同じ「削り」で読める")
	check.call(
		"drain" in NaivePlay.death_cause_text("drain"),
		"naive_play: 死因drainは元トークンも併記する")
	check.call(
		"減衰" in NaivePlay.death_cause_text("decay"),
		"naive_play: 死因decayは内訳と同じ「減衰」で読める")
	check.call(
		"壁" in NaivePlay.death_cause_text("wall"),
		"naive_play: 死因wallは内訳と同じ「壁」で読める")
	check.call(
		"分類不能" in NaivePlay.death_cause_text("unknown"),
		"naive_play: unknownは分類不能と読める")
	check.call(
		NaivePlay.death_cause_text("?") == "?",
		"naive_play: 未知トークンはそのまま通す(引き分けの死因=?を壊さない)")


## 停止行(誰が・いつ・何で力尽きたか)と相打ち注記。発見の経緯: 双方残り0%なのに
## ★勝利★と出る相打ちが2回あり、なぜ勝ったのか読めなかった(2026-07-29の
## コールドプレイ)。リゾルバは相打ちをプレイヤーの勝ちと定めているが、その規則が
## CLIのどこにも出ていなかった。
func _test_naive_play_stop_text(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	# 生存は「生存」、停止は時刻と死因(内訳と同じ語彙)で読める。
	check.call(
		NaivePlay.stop_text("自分", {}) == "自分 生存",
		"naive_play: 力尽きていない体は「生存」と読める")
	var dead_text: String = NaivePlay.stop_text("enemy1", {"cause": "drain", "time": 5.25})
	check.call(
		"5.25s" in dead_text and "削り" in dead_text and dead_text.begins_with("enemy1"),
		"naive_play: 停止した体は時刻と死因で読める (%s)" % dead_text)
	# 相打ち注記: 勝ちなのに自分の停止が記録されているときだけ出る。
	var mutual := BattleResult.new()
	mutual.outcome = BattleResult.Outcome.PLAYER_WIN
	mutual.player_death = {"cause": "drain", "time": 6.0}
	check.call(
		"相打ち" in NaivePlay.mutual_ko_text(mutual),
		"naive_play: 相打ち勝利には規則の注記が出る")
	var clean_win := BattleResult.new()
	clean_win.outcome = BattleResult.Outcome.PLAYER_WIN
	check.call(
		NaivePlay.mutual_ko_text(clean_win) == "",
		"naive_play: 自分が生き残った勝利に相打ち注記は出ない")
	var loss := BattleResult.new()
	loss.outcome = BattleResult.Outcome.ENEMY_WIN
	loss.player_death = {"cause": "drain", "time": 3.0}
	check.call(
		NaivePlay.mutual_ko_text(loss) == "",
		"naive_play: 敗北に相打ち注記は出ない")
	# 実リゾルバの結果とも整合: 勝った戦いでは敵の停止行に決着死因と同じ死因が出る。
	var request := _request()
	var result := _healthy_result(request)
	if result.player_won() and result.enemy_deaths.size() == 1:
		var enemy_text: String = NaivePlay.stop_text("enemy1", result.enemy_deaths[0])
		check.call(
			NaivePlay.death_cause_text(result.loser_death_cause) in enemy_text,
			"naive_play: 実結果の敵停止行が決着死因と整合する (%s)" % enemy_text)


## ゴースト発動行: 実UIの半透明表示に相当する事実がCLIにも出ること。
## 札なし(duration=0)は行なし・不発(start<0)はその旨・発動は時刻と長さが読める。
func _test_naive_play_ghost_text(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	var no_ghost := BattleResult.new()
	check.call(
		NaivePlay.ghost_text(no_ghost) == "",
		"naive_play: ゴースト札なしの戦いに発動行は出ない")
	var unfired := BattleResult.new()
	unfired.ghost_duration = 2.0
	unfired.ghost_start = -1.0
	check.call(
		"発動せず" in NaivePlay.ghost_text(unfired),
		"naive_play: 衝突ゼロの戦いは不発と読める")
	var fired := BattleResult.new()
	fired.ghost_duration = 2.0
	fired.ghost_start = 1.25
	var fired_text: String = NaivePlay.ghost_text(fired)
	check.call(
		"1.25s" in fired_text and "2.0s" in fired_text and "すり抜け" in fired_text,
		"naive_play: 発動行は初衝突時刻と窓の長さで読める (%s)" % fired_text)
	# 実リゾルバとも整合: ゴースト付きで衝突が起きた戦いでは発動行が出る。
	var request := _request()
	request.ghost_duration = 1.5
	var result := _healthy_result(request)
	if not result.impacts.is_empty():
		check.call(
			"ゴースト発動" in NaivePlay.ghost_text(result),
			"naive_play: 実結果でも初衝突があれば発動行が出る")


## 接触ゼロ勝利の注記。死因が接触系(wall/drain)なのに撃破ボーナスが付かない勝ちで
## 「なぜ+0.5なのか」が読めるように、自滅の事実を1行で明文化する。
func _test_naive_play_no_contact_note(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	# 接触ゼロの壁自滅勝ち: 注記が出る。
	var self_destruct := BattleResult.new()
	self_destruct.outcome = BattleResult.Outcome.PLAYER_WIN
	self_destruct.loser_death_cause = "wall"
	self_destruct.loser_hit_by_player = false
	var note: String = NaivePlay.no_contact_note(self_destruct)
	check.call(
		"接触ゼロ" in note and "撃破ボーナス対象外" in note,
		"naive_play: 接触ゼロの壁自滅勝ちに自滅の注記が出る (%s)" % note)
	# 同士討ちのdrain死も同様に出る。
	self_destruct.loser_death_cause = "drain"
	check.call(
		NaivePlay.no_contact_note(self_destruct) != "",
		"naive_play: 接触ゼロの同士討ち勝ちにも注記が出る")
	# 接触して仕留めた勝ちには出ない。
	var knockout := BattleResult.new()
	knockout.outcome = BattleResult.Outcome.PLAYER_WIN
	knockout.loser_death_cause = "wall"
	knockout.loser_hit_by_player = true
	check.call(
		NaivePlay.no_contact_note(knockout) == "",
		"naive_play: 接触で仕留めた勝ちに注記は出ない")
	# 乱戦で自分が1体でも落としていれば、決着を付けたのが自滅した敵でも出ない
	# (撃破ボーナスは付くので、「対象外」と書いたら嘘になる)。
	var melee := BattleResult.new()
	melee.outcome = BattleResult.Outcome.PLAYER_WIN
	melee.loser_death_cause = "wall"
	melee.loser_hit_by_player = false
	melee.enemy_deaths = [
		{"cause": "drain", "time": 0.5, "by_player": true},
		{"cause": "wall", "time": 2.0, "by_player": false},
	]
	check.call(
		NaivePlay.no_contact_note(melee) == "",
		"naive_play: 乱戦で1体でも落としていれば注記は出ない (%s)"
		% NaivePlay.no_contact_note(melee))
	# 逆に、1体も落としていない乱戦(全員が自滅・同士討ち)には出る。
	melee.enemy_deaths = [
		{"cause": "drain", "time": 0.5, "by_player": false},
		{"cause": "wall", "time": 2.0, "by_player": false},
	]
	check.call(
		NaivePlay.no_contact_note(melee) != "",
		"naive_play: 1体も落としていない乱戦の勝ちには注記が出る")
	# 減衰待ちの勝ち(そもそも撃破対象外)と敗北にも出ない。
	var decay_win := BattleResult.new()
	decay_win.outcome = BattleResult.Outcome.PLAYER_WIN
	decay_win.loser_death_cause = "decay"
	decay_win.loser_hit_by_player = false
	check.call(
		NaivePlay.no_contact_note(decay_win) == "",
		"naive_play: 減衰待ちの勝ちに注記は出ない")
	var loss := BattleResult.new()
	loss.outcome = BattleResult.Outcome.ENEMY_WIN
	loss.loser_death_cause = "wall"
	loss.loser_hit_by_player = false
	check.call(
		NaivePlay.no_contact_note(loss) == "",
		"naive_play: 敗北に注記は出ない")


## 勝利成長の表示。上限到達で+0.0なのに「大きく成長」と祝う矛盾
## (2026-07-30コールドプレイ、段5以降の全勝利で再現)を防ぐ。
func _test_naive_play_victory_text(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	# 上限到達(成長0)は頭打ちと正直に言い、成長の祝辞を出さない。
	var capped_ko: String = NaivePlay.victory_text(true, 0.0, SpinnerStats.RPS_CAP)
	check.call(
		"頭打ち" in capped_ko and "大きく成長" not in capped_ko,
		"naive_play: 上限到達の撃破ボーナスは頭打ちと読める (%s)" % capped_ko)
	check.call(
		"★撃破ボーナス★" in capped_ko,
		"naive_play: 頭打ちでも接触で仕留めた事実は残す")
	var capped_passive: String = NaivePlay.victory_text(false, 0.0, SpinnerStats.RPS_CAP)
	check.call(
		"頭打ち" in capped_passive and "+0.0" not in capped_passive,
		"naive_play: 上限到達の受け身勝利も頭打ちと読める (%s)" % capped_passive)
	# 表示丸めで+0.0になる微小成長も頭打ち扱い(数字と文言の食い違い防止)。
	check.call(
		"頭打ち" in String(NaivePlay.victory_text(true, 0.04, SpinnerStats.RPS_CAP)),
		"naive_play: 丸めて+0.0になる成長は頭打ちと言う")
	# 通常の成長は従来どおり増加量つきで祝う。
	var normal_ko: String = NaivePlay.victory_text(true, 1.2, 25.0)
	check.call(
		"大きく成長" in normal_ko and "+1.2" in normal_ko,
		"naive_play: 通常の撃破ボーナスは増加量つきで祝う (%s)" % normal_ko)
	var normal_passive: String = NaivePlay.victory_text(false, 0.5, 20.0)
	check.call(
		"勝利の勢い" in normal_passive and "+0.5" in normal_passive and "頭打ち" not in normal_passive,
		"naive_play: 通常の受け身勝利は従来表示 (%s)" % normal_passive)
	# 余勢転化: 上限で堰き止められた撃破ボーナスは前後のspin_decayが渡され、
	# 頭打ちでなく「長持ち」と実値つきで読める。
	var overflow_ko: String = NaivePlay.victory_text(true, 0.0, SpinnerStats.RPS_CAP, 0.80, 0.76)
	check.call(
		"長持ち" in overflow_ko and "0.80" in overflow_ko and "0.76" in overflow_ko,
		"naive_play: 余勢転化は減衰の前後値つきで長持ちと読める (%s)" % overflow_ko)
	check.call(
		"★撃破ボーナス★" in overflow_ko and "頭打ち" not in overflow_ko,
		"naive_play: 余勢転化は撃破ボーナスとして祝い頭打ちと矛盾しない")
	# 表示丸め(%.2f)で見えない低下は従来どおり頭打ち(数字と文言の食い違い防止)。
	check.call(
		"頭打ち" in String(NaivePlay.victory_text(true, 0.0, SpinnerStats.RPS_CAP, 0.402, 0.400)),
		"naive_play: 丸めで見えない転化は頭打ちのまま")
	# 実装(grow_rps_by_victory)とも整合: 上限のコマの撃破勝利は余勢転化の表示、
	# spin_decayが床のコマは転化できず頭打ち表示に落ちる。
	var s := SpinnerStats.new()
	s.rps = SpinnerStats.RPS_CAP
	var decay_before := s.spin_decay
	var gained := s.grow_rps_by_victory(true)
	check.call(
		"長持ち" in String(NaivePlay.victory_text(true, gained, s.rps, decay_before, s.spin_decay)),
		"naive_play: 実成長関数の余勢転化が長持ち表示に繋がる")
	var floored := SpinnerStats.new()
	floored.rps = SpinnerStats.RPS_CAP
	floored.spin_decay = SpinnerStats.OVERFLOW_DECAY_FLOOR
	var floored_before := floored.spin_decay
	var floored_gain := floored.grow_rps_by_victory(true)
	check.call(
		"頭打ち" in String(NaivePlay.victory_text(
			true, floored_gain, floored.rps, floored_before, floored.spin_decay)),
		"naive_play: 床に達したコマは頭打ち表示に戻る")


## retryの個体入れ替えは名前でstateに保存され、launchが同じ相手を復元すること
## (group_names/group_from_namesの往復)。名前で持つのはstateがJSONだから。
## 復元できない名前が混ざったら部分的に混ぜず、丸ごとノード生成時の個体へ戻す。
func _test_naive_play_group_persistence(check: Callable) -> void:
	var NaivePlay = load("res://playtest/naive_play.gd")
	var fallback := EnemyRoster.of_level(4)
	var group := EnemyRoster.of_level(3)
	var names: Array = NaivePlay.group_names(group)
	var restored: Array[EnemyData] = NaivePlay.group_from_names(names, fallback)
	var roundtrip := restored.size() == group.size()
	if roundtrip:
		for i in restored.size():
			if restored[i].display_name != group[i].display_name:
				roundtrip = false
	check.call(roundtrip, "naive_play: 個体入れ替えは名前で往復できる(予告と同じ相手で解決)")
	check.call(
		NaivePlay.group_from_names(null, fallback) == fallback,
		"naive_play: 名前未保存(旧state/enter直後)はノード生成時の個体を使う")
	check.call(
		NaivePlay.group_from_names([], fallback) == fallback,
		"naive_play: 空の名前列はノード生成時の個体を使う")
	check.call(
		NaivePlay.group_from_names(["ENEMY_9_9"], fallback) == fallback,
		"naive_play: 知らない名前が混ざったら丸ごとノード生成時の個体へ戻す")
