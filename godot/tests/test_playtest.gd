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
	_test_naive_play_stats_roundtrip(check)
	_test_naive_play_group_rewards(check)
	_test_naive_play_field_text(check)
	_test_naive_play_enemy_line(check)
	_test_naive_play_launch_lock(check)
	_test_naive_play_reward_guard(check)
	_test_naive_play_defeat_prompt(check)
	_test_naive_play_bseed_pin(check)


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


func _test_invariants_pass_healthy_result(check: Callable) -> void:
	var request := _request()
	var violations := PlaytestInvariants.check(request, _healthy_result(request))
	check.call(
		violations.is_empty(),
		"検査器: 健全な結果は素通しする (%s)" % [violations]
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
	var a := BattleSim.play_one(5, enemies, LaunchPolicy.Kind.INTERCEPT, stats, null, plate)
	var b := BattleSim.play_one(5, enemies, LaunchPolicy.Kind.INTERCEPT, stats, null, pillars)
	check.call(
		a["finish_time"] != b["finish_time"] or a["impacts"] != b["impacts"],
		"battle_sim: 土俵が変われば戦いも変わる"
	)


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
