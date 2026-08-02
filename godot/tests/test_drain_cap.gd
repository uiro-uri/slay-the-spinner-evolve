extends RefCounted

## 1衝突の削りの天井(drain_cap_share / SpinnerPhysics.capped_spin_drain)のテスト。
##
## 素の削りは相手の硬さ(質量×半径²)に反比例するので、柔らかい相手には1撃で
## 回転ゲージ全部を超える削りが出ていた(ボット500戦でLv1戦の勝ちの99.2%が衝突1回、
## 決着中央値0.27秒)。天井は「1回の衝突で奪えるのは相手のゲージのcap_shareまで」。
## ここで固定するのは:
##  - 純関数の向き: 天井未満の削りはそのまま、超える削りは天井で切る
##  - 天井は受け手の**初期rps**基準(現在rpsだと減るほど天井も下がって永遠に倒せない)
##  - cap_share<=0 で天井なし=旧挙動と厳密一致(古い保存データの再現)
##  - リゾルバが実際に天井を使い、柔らかい相手が1衝突では死ななくなること
##  - **硬い相手には天井が届かない**(=Lv3以降の難易度を動かさない、が採用の前提)
##  - 天井は削り比例のspin_kick(弾き)にも効くこと(削りだけ切って弾きが素のままだと、
##    即死は消えても「1発で場外まで吹き飛ぶ」ほうが残る)
##  - シリアライズ往復と、キーの無い旧データの既定0(=旧挙動)
##  - 実UI(Battle.gd)が@exportの値をrequestへ実際に載せていること。既定値の一致は
##    test_battle_defaults.gdが見るが、「値は正しいのにrequestへ渡し忘れている」型の
##    配線漏れはそれでは通ってしまう(実UIだけ天井なしで遊ぶことになる)。

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_cap_function(check)
	_test_resolver_stops_one_hit_kill(check)
	_test_hard_opponent_untouched(check)
	_test_cap_reaches_spin_kick(check)
	_test_cap_still_allows_the_kill(check)
	_test_serialization(check)
	_test_battle_wires_the_knob(check)


func _test_cap_function(check: Callable) -> void:
	check.call(
		absf(SpinnerPhysics.capped_spin_drain(30.0, 20.0, 0.0) - 30.0) < EPS,
		"capped_spin_drain: cap_share=0は天井なしでそのまま(旧挙動)"
	)
	check.call(
		absf(SpinnerPhysics.capped_spin_drain(30.0, 20.0, -0.5) - 30.0) < EPS,
		"capped_spin_drain: 負のcap_shareも天井なし扱い"
	)
	check.call(
		absf(SpinnerPhysics.capped_spin_drain(30.0, 20.0, 0.5) - 10.0) < EPS,
		"capped_spin_drain: ゲージを超える削りは天井(max_rps×share)で切られる"
	)
	check.call(
		absf(SpinnerPhysics.capped_spin_drain(3.0, 20.0, 0.5) - 3.0) < EPS,
		"capped_spin_drain: 天井未満の削りはそのまま"
	)
	check.call(
		absf(SpinnerPhysics.capped_spin_drain(30.0, -5.0, 0.5)) < EPS,
		"capped_spin_drain: 負のmax_rpsは0扱い(天井0)"
	)


## 柔らかい相手(硬さが自分よりはるかに低い)に全力で当たる理想環境。
## 摩擦・傾斜・自然減衰を切り、壁は遠くへ置くので、rpsの増減は衝突削りだけ。
## 敵は静止していて、プレイヤーが1回だけ当たる。
func _soft_target_request(cap_share: float) -> BattleRequest:
	var req := BattleRequest.new()
	req.arena_bounds = Rect2(0, 0, 100, 100)
	req.stage_strength = 0.0
	req.natural_damping = 0.0
	req.drain_cap_share = cap_share
	req.max_duration = 0.6

	var pstats := SpinnerStats.new()
	pstats.mass = 1.5
	pstats.radius = 0.7
	pstats.friction = 0.0
	pstats.restitution = 1.0
	pstats.rps = 15.0
	# Lv1相当の柔らかさ(硬さ 0.7×0.41² ≈ 0.12。プレイヤーは 1.5×0.7² ≈ 0.74)。
	var estats := SpinnerStats.new()
	estats.mass = 0.7
	estats.radius = 0.41
	estats.friction = 0.0
	estats.restitution = 1.0
	estats.rps = 18.8

	req.player = BattleRequest.Launch.new(pstats, Vector2(46.0, 50.0), Vector2(12.0, 0.0))
	var launches: Array[BattleRequest.Launch] = []
	launches.append(BattleRequest.Launch.new(estats, Vector2(50.0, 50.0), Vector2.ZERO))
	req.enemies = launches
	return req


func _enemy_drain(result: BattleResult) -> float:
	return float(result.enemy_rps_loss[0].get("drain", 0.0))


func _test_resolver_stops_one_hit_kill(check: Callable) -> void:
	var bare := BattleResolver.resolve(_soft_target_request(0.0))
	var capped := BattleResolver.resolve(_soft_target_request(0.5))

	check.call(bare.impacts.size() == 1, "天井なし: 衝突がちょうど1回起きる")
	check.call(capped.impacts.size() == 1, "天井あり: 衝突がちょうど1回起きる")

	# 天井なしの素の削りは相手のゲージ(18.8)を超えている＝1撃で空になる、が前提。
	# ここが崩れたら以降の比較は「即死を止めた」ことの検証になっていない。
	var raw := SpinnerPhysics.spin_drain(
		1.5, 12.0, 0.7, 0.41, BattleRequest.new().violence
	)
	check.call(
		raw > 18.8,
		"検証環境: 天井なしの素の削り %.2f は相手のゲージ 18.8 を超えている" % raw
	)
	check.call(
		absf(_enemy_drain(bare) - 18.8) < EPS,
		"天井なし: 1衝突で敵のゲージが空になる (%.2f)" % _enemy_drain(bare)
	)
	check.call(
		absf(_enemy_drain(capped) - 18.8 * 0.5) < EPS,
		"天井あり: 1衝突の削りはゲージの半分ちょうどで止まる (%.2f)" % _enemy_drain(capped)
	)
	# 「最低2回噛み合う」の実体。ゲージが半分残っている＝この衝突では倒せていない。
	var track: Array = capped.enemy_tracks[0]
	check.call(
		track[track.size() - 1].rps > 18.8 * 0.5 - EPS,
		"天井あり: 1衝突を受けても敵は倒れず、ゲージが半分残る (%.2f)"
			% track[track.size() - 1].rps
	)


## 硬い相手(ボス相当)には天井が届かない＝Lv3以降の難易度は動かない。
## この不変が崩れると、序盤の即死対策のはずが終盤のバランスまで動かしてしまう。
func _test_hard_opponent_untouched(check: Callable) -> void:
	var bare_req := _soft_target_request(0.0)
	var capped_req := _soft_target_request(0.5)
	for req in [bare_req, capped_req]:
		# ボス相当の硬さ(4.2×1.74² ≈ 12.7)。ゲージも実物に合わせる。
		req.enemies[0].stats.mass = 4.2
		req.enemies[0].stats.radius = 1.74
		req.enemies[0].stats.rps = 38.6
		# 半径が増えたぶん接触が早まるので、当たる位置まで離す。
		req.enemies[0].position = Vector2(52.0, 50.0)
	var bare := BattleResolver.resolve(bare_req)
	var capped := BattleResolver.resolve(capped_req)

	check.call(bare.impacts.size() == 1, "硬い相手: 検証環境で衝突が1回起きる")
	check.call(
		_enemy_drain(bare) < 38.6 * 0.5,
		"検証環境: 硬い相手の1撃の削り %.2f は天井(19.3)に届いていない" % _enemy_drain(bare)
	)
	check.call(
		absf(_enemy_drain(capped) - _enemy_drain(bare)) < EPS,
		"硬い相手: 天井の有無で削りが1ptも変わらない (%.4f / %.4f)"
			% [_enemy_drain(capped), _enemy_drain(bare)]
	)
	check.call(
		absf(capped.player_rps_loss["drain"] - bare.player_rps_loss["drain"]) < EPS,
		"硬い相手: 自分が受ける削りも天井の有無で変わらない"
	)


## 天井の基準は受け手の**初期**rpsであって、その時の残りrpsではない。
## 残りrps基準にすると1撃で奪えるのが常に残りの半分になり、削りだけでは
## いつまでも倒しきれない(決着が壁と自然減衰に丸投げされる)。
## 実戦に近い土俵で何度も噛み合わせ、最後まで削り切れることで基準を固定する。
func _test_cap_still_allows_the_kill(check: Callable) -> void:
	var req := _soft_target_request(0.5)
	# 既定の10x10すり鉢へ戻す。弾かれても傾斜が中央へ戻すので何度も噛み合う。
	req.arena_bounds = Rect2(0, 0, 10, 10)
	req.stage_strength = BattleRequest.new().stage_strength
	req.max_duration = 30.0
	req.player.position = Vector2(1.5, 5.0)
	req.enemies[0].position = Vector2(5.0, 5.0)
	var result := BattleResolver.resolve(req)

	# 回数の**上界**まで見るのが要点。初期rps基準なら1撃はゲージの半分ちょうどなので
	# 満タンから2回で倒し切れる。現在rps基準だと毎回「残りの半分」に痩せて回数が
	# 跳ね上がる(実測6回)ため、下限だけの検査では両者を見分けられない。
	check.call(
		result.impacts.size() >= 2 and result.impacts.size() <= 3,
		"倒し切り: 天井0.5なら満タンから2〜3回で倒し切れる (%d回)" % result.impacts.size()
	)
	check.call(
		result.player_won() and result.loser_death_cause == "drain",
		"倒し切り: 天井があっても削りで倒し切れる (%s / %s)"
			% [str(result.outcome), result.loser_death_cause]
	)


## 天井は削り比例のspin_kick(弾き)にも効く。削りだけ切って弾きを素のままにすると、
## 即死は消えても「1発で吹き飛ばして壁で殺す」が残り、決着が壁へ倒れる。
func _test_cap_reaches_spin_kick(check: Callable) -> void:
	var bare := BattleResolver.resolve(_soft_target_request(0.0))
	var capped := BattleResolver.resolve(_soft_target_request(0.5))
	var bare_track: Array = bare.enemy_tracks[0]
	var capped_track: Array = capped.enemy_tracks[0]
	var bare_speed: float = bare_track[bare_track.size() - 1].velocity.length()
	var capped_speed: float = capped_track[capped_track.size() - 1].velocity.length()
	check.call(
		capped_speed < bare_speed - EPS,
		"天井あり: 弾き飛ばしも天井ぶん弱まる (%.2f < %.2f)" % [capped_speed, bare_speed]
	)


func _test_serialization(check: Callable) -> void:
	var req := _soft_target_request(0.5)
	var revived := BattleRequest.from_dict(req.to_dict())
	check.call(
		absf(revived.drain_cap_share - 0.5) < EPS,
		"往復: drain_cap_shareが保存される (%.2f)" % revived.drain_cap_share
	)
	check.call(
		absf(_enemy_drain(BattleResolver.resolve(revived)) - _enemy_drain(
			BattleResolver.resolve(req))) < EPS,
		"往復: 往復しても結果が変わらない"
	)

	var old_dict := req.to_dict()
	old_dict.erase("drain_cap_share")
	var old := BattleRequest.from_dict(old_dict)
	check.call(
		old.drain_cap_share == 0.0,
		"旧データ互換: キーが無ければ天井なし(0)で読む (%.2f)" % old.drain_cap_share
	)
	check.call(
		absf(_enemy_drain(BattleResolver.resolve(old)) - 18.8) < EPS,
		"旧データ互換: 当時どおり1衝突でゲージが空になる"
	)


## 実UIの配線。Battle.gdはautoload(GameState)を参照するのでヘッドレスの--scriptからは
## new()できないため、test_battle_defaults.gdと同じくソーステキストで確認する。
func _test_battle_wires_the_knob(check: Callable) -> void:
	var src := FileAccess.get_file_as_string("res://scenes/battle/Battle.gd")
	check.call(src != "", "配線: Battle.gd を読めた")
	check.call(
		src.contains("request.drain_cap_share = drain_cap_share"),
		"配線: Battle.gdが@exportの天井をBattleRequestへ載せている"
	)
