extends RefCounted

## 1回の壁当たりで失えるrpsの天井(wall_drain_cap_share / SpinnerPhysics.capped_wall_drain)
## のテスト。接触側の天井(drain_cap_share / test_drain_cap.gd)と対になる。
##
## 接触に天井を置いても序盤の即死は消えていなかった。その1撃のspin_kickで軽い相手が
## 壁へ飛び、壁の喪失は絶対量(absolute_wall_drain)で**自分の硬さに反比例**するため、
## 柔らかい相手ほど1回の壁でゲージが大きく削れて、接触の天井を壁が迂回していた
## (コールドプレイの一次証拠: 段2のLv1が1.33秒で 削り0.6 / 壁17.4＝**3回**の壁で
## ゲージ18.1を使い切っている。ボット統計でもLv2単体の敗因は壁52.0%)。
##
## ここで固定するのは:
##  - 純関数の向き: 天井未満の喪失はそのまま、超える喪失は天井で切る
##  - 天井は**初期rps**基準(現在rps基準だと減るほど天井も痩せて壁で死ななくなる)
##  - cap_share<=0 で天井なし=旧挙動と厳密一致(古い保存データの再現)
##  - リゾルバが実際に天井を使い、**柔らかいコマが数回の壁で即死しなくなる**こと
##  - **硬いコマには天井が届かない**(=後半の難易度を動かさない、が採用の前提)
##  - **反射(wall_bounce)には触れない**。天井は喪失にだけ効き、跳ね返りの速さも
##    壁に当たる時刻も動かない=「壁へ押し込む」手応えはそのまま
##  - 喪失の内訳の恒等式(削り+壁+減衰 = 初期rps - 最終rps)が壊れないこと
##  - シリアライズ往復と、キーの無い旧データの既定0(=旧挙動)
##  - 実UI(Battle.gd)が@exportの値をrequestへ実際に載せていること。既定値の一致は
##    test_battle_defaults.gdが見るが、「値は正しいのにrequestへ渡し忘れている」型の
##    配線漏れはそれでは通ってしまう(実UIだけ天井なしで遊ぶことになる)。

const EPS := 1e-4

## 検証環境の柔らかいコマ。Lv1の敵に近い形(硬さ 0.7×0.41² ≈ 0.12)。
const SOFT_MASS := 0.7
const SOFT_RADIUS := 0.41
const SOFT_RPS := 18.8


func run(check: Callable) -> void:
	_test_cap_function(check)
	_test_resolver_caps_a_single_wall_hit(check)
	_test_hard_body_untouched(check)
	_test_bounce_is_untouched(check)
	_test_cap_is_based_on_the_full_gauge(check)
	_test_loss_breakdown_still_adds_up(check)
	_test_serialization(check)
	_test_battle_wires_the_knob(check)


func _test_cap_function(check: Callable) -> void:
	check.call(
		absf(SpinnerPhysics.capped_wall_drain(30.0, 20.0, 0.0) - 30.0) < EPS,
		"capped_wall_drain: cap_share=0は天井なしでそのまま(旧挙動)"
	)
	check.call(
		absf(SpinnerPhysics.capped_wall_drain(30.0, 20.0, -0.5) - 30.0) < EPS,
		"capped_wall_drain: 負のcap_shareも天井なし扱い"
	)
	check.call(
		absf(SpinnerPhysics.capped_wall_drain(30.0, 20.0, 0.15) - 3.0) < EPS,
		"capped_wall_drain: ゲージを超える喪失は天井(max_rps×share)で切られる"
	)
	check.call(
		absf(SpinnerPhysics.capped_wall_drain(1.0, 20.0, 0.15) - 1.0) < EPS,
		"capped_wall_drain: 天井未満の喪失はそのまま"
	)
	check.call(
		absf(SpinnerPhysics.capped_wall_drain(30.0, -5.0, 0.15)) < EPS,
		"capped_wall_drain: 負のmax_rpsは0扱い(天井0)"
	)


## 壁へ1回だけぶつかる理想環境。摩擦・傾斜・自然減衰を切るので、rpsの減少は壁だけ。
## 敵は遠くに静止させて接触させない。massとradiusでコマの硬さ(=壁の痛さ)を振る。
func _one_wall_hit_request(
	cap_share: float, mass: float, radius: float, rps: float
) -> BattleRequest:
	var pstats := SpinnerStats.new()
	pstats.mass = mass
	pstats.radius = radius
	pstats.friction = 0.0
	pstats.restitution = 0.75
	pstats.rps = rps
	var estats := SpinnerStats.new()
	estats.radius = 0.5
	estats.rps = 1000.0

	var req := BattleRequest.new()
	req.natural_damping = 0.0
	req.stage_strength = 0.0
	req.wall_drain_cap_share = cap_share
	# 速度スケールを切って、進入速度によらず激突ぶんの喪失そのものを見る。
	req.wall_impact_ref_speed = 0.0
	req.max_duration = 0.5
	# 下の壁(y=0)へ一直線。半径ぶん進むと接触する。
	req.player = BattleRequest.Launch.new(
		pstats, Vector2(5.0, radius + 0.8), Vector2(0.0, -12.0)
	)
	req.enemies = [BattleRequest.Launch.new(estats, Vector2(8.0, 8.0), Vector2.ZERO)]
	return req


func _wall_loss(cap_share: float, mass: float, radius: float, rps: float) -> float:
	var result := BattleResolver.resolve(
		_one_wall_hit_request(cap_share, mass, radius, rps)
	)
	return float(result.player_rps_loss.get("wall", 0.0))


## この変更の目的そのもの: 柔らかいコマが1回の壁でゲージを大きく持っていかれない。
func _test_resolver_caps_a_single_wall_hit(check: Callable) -> void:
	var bare := _wall_loss(0.0, SOFT_MASS, SOFT_RADIUS, SOFT_RPS)
	var capped := _wall_loss(0.15, SOFT_MASS, SOFT_RADIUS, SOFT_RPS)

	# 天井なしの素の喪失がゲージの15%を超えている＝天井が意味を持つ、が前提。
	# ここが崩れたら以降の比較は「即死を止めた」ことの検証になっていない。
	check.call(
		bare > SOFT_RPS * 0.15,
		"検証環境: 天井なしの壁1回の喪失 %.2f はゲージの15%%(%.2f)を超えている"
			% [bare, SOFT_RPS * 0.15]
	)
	check.call(
		absf(capped - SOFT_RPS * 0.15) < EPS,
		"天井あり: 壁1回の喪失はゲージの15%%ちょうどで止まる (%.4f)" % capped
	)
	# 「壁だけで死ぬには最低7回」の実体。天井なしだと同じコマが何回で尽きるか。
	var bare_hits := ceili(SOFT_RPS / maxf(bare, EPS))
	var capped_hits := ceili(SOFT_RPS / maxf(capped, EPS))
	check.call(
		capped_hits >= 7 and capped_hits > bare_hits,
		"天井あり: 壁だけで尽きるのに要る回数が %d回 → %d回 へ増える"
			% [bare_hits, capped_hits]
	)


## 硬いコマ(ボス相当)には天井が届かない＝後半の難易度は動かない。
## この不変が崩れると、序盤の壁即死対策のはずが終盤のバランスまで動かしてしまう。
func _test_hard_body_untouched(check: Callable) -> void:
	# ボス相当の硬さ(4.2×1.74² ≈ 12.7)。ゲージも実物に合わせる。
	var bare := _wall_loss(0.0, 4.2, 1.74, 38.6)
	var capped := _wall_loss(0.15, 4.2, 1.74, 38.6)
	check.call(
		bare < 38.6 * 0.15,
		"検証環境: 硬いコマの壁1回の喪失 %.2f は天井(%.2f)に届いていない"
			% [bare, 38.6 * 0.15]
	)
	check.call(
		absf(capped - bare) < EPS,
		"硬いコマ: 天井の有無で壁の喪失が1ptも変わらない (%.4f / %.4f)" % [capped, bare]
	)


## 天井は喪失にだけ効き、反射には触れない。跳ね返りの速さも壁に当たる時刻も
## 変わらないので、「相手を壁へ押し込む」手応えはそのまま残る。
func _test_bounce_is_untouched(check: Callable) -> void:
	var bare := BattleResolver.resolve(
		_one_wall_hit_request(0.0, SOFT_MASS, SOFT_RADIUS, SOFT_RPS)
	)
	var capped := BattleResolver.resolve(
		_one_wall_hit_request(0.15, SOFT_MASS, SOFT_RADIUS, SOFT_RPS)
	)
	check.call(
		bare.wall_impacts.size() == 1 and capped.wall_impacts.size() == 1,
		"検証環境: どちらも壁に1回だけ当たる (%d / %d)"
			% [bare.wall_impacts.size(), capped.wall_impacts.size()]
	)
	check.call(
		absf(bare.wall_impacts[0].time - capped.wall_impacts[0].time) < EPS,
		"反射: 壁に当たる時刻は天井の有無で変わらない (%.4f / %.4f)"
			% [bare.wall_impacts[0].time, capped.wall_impacts[0].time]
	)
	var bare_track: Array = bare.player_frames
	var capped_track: Array = capped.player_frames
	var bare_v: Vector2 = bare_track[bare_track.size() - 1].velocity
	var capped_v: Vector2 = capped_track[capped_track.size() - 1].velocity
	check.call(
		bare_v.distance_to(capped_v) < EPS,
		"反射: 跳ね返った後の速度も変わらない (%s / %s)" % [str(bare_v), str(capped_v)]
	)
	# 天井が効いていること自体は残rpsの側に出る(上の2つが「何も起きていない」で
	# 通ってしまわないための対)。
	check.call(
		capped_track[capped_track.size() - 1].rps
			> bare_track[bare_track.size() - 1].rps + EPS,
		"反射: 速度は同じでも残りrpsは天井ぶん多い (%.2f > %.2f)" % [
			capped_track[capped_track.size() - 1].rps,
			bare_track[bare_track.size() - 1].rps,
		]
	)


## 天井の基準は**初期**rpsであって、その時の残りrpsではない。
## 残りrps基準にすると壁の喪失が残りに比例して痩せ、いくら壁に叩き付けても
## 死ななくなる=壁が脅威でなくなる(接触側 test_drain_cap.gd の裏返し)。
func _test_cap_is_based_on_the_full_gauge(check: Callable) -> void:
	# 同じ形・同じ進入速度で、残りrpsだけを半分にしたコマ。初期rps基準なら
	# 天井は「そのランのゲージ」に対して決まるので、素の喪失(rpsに依らない絶対量)が
	# 天井未満に収まる側では喪失が一致する。
	var full := _wall_loss(0.15, SOFT_MASS, SOFT_RADIUS, SOFT_RPS)
	var half := _wall_loss(0.15, SOFT_MASS, SOFT_RADIUS, SOFT_RPS * 0.5)
	check.call(
		half < full - EPS,
		"ゲージ基準: ゲージが小さいコマは天井も小さい (%.4f < %.4f)" % [half, full]
	)
	# 壁に何度も当てて、天井があっても最後まで壁で倒し切れること。現在rps基準だと
	# 残りに比例して天井が痩せ、いつまでも尽きない。
	var req := _one_wall_hit_request(0.15, SOFT_MASS, SOFT_RADIUS, SOFT_RPS)
	req.max_duration = 60.0
	# 左右の壁を往復させる。反発0.75でも十分な回数当たる。
	req.player = BattleRequest.Launch.new(
		req.player.stats, Vector2(5.0, 5.0), Vector2(12.0, 0.0)
	)
	var result := BattleResolver.resolve(req)
	check.call(
		not result.player_won() and result.loser_death_cause == "wall",
		"ゲージ基準: 天井があっても壁で尽きる (%s / %s)"
			% [str(result.outcome), result.loser_death_cause]
	)


## 内訳の恒等式。天井は「喪失を切って残りrpsへ戻す」ので、切ったぶんが
## lost_wallから漏れると 削り+壁+減衰 が実際の減少と合わなくなる。
func _test_loss_breakdown_still_adds_up(check: Callable) -> void:
	var req := _one_wall_hit_request(0.15, SOFT_MASS, SOFT_RADIUS, SOFT_RPS)
	req.max_duration = 60.0
	req.natural_damping = BattleRequest.new().natural_damping
	req.stage_strength = BattleRequest.new().stage_strength
	req.player = BattleRequest.Launch.new(
		req.player.stats, Vector2(5.0, 5.0), Vector2(12.0, 0.0)
	)
	var result := BattleResolver.resolve(req)
	var loss: Dictionary = result.player_rps_loss
	var sum: float = (
		float(loss.get("drain", 0.0))
		+ float(loss.get("wall", 0.0))
		+ float(loss.get("decay", 0.0))
	)
	var track: Array = result.player_frames
	var actual: float = SOFT_RPS - float(track[track.size() - 1].rps)
	check.call(
		float(loss.get("wall", 0.0)) > 0.0,
		"内訳: 検証環境で壁の喪失が実際に出ている (%.2f)" % float(loss.get("wall", 0.0))
	)
	check.call(
		absf(sum - actual) < 1e-3,
		"内訳: 削り+壁+減衰 が実際の減少と一致する (%.4f ≒ %.4f)" % [sum, actual]
	)


func _test_serialization(check: Callable) -> void:
	var req := _one_wall_hit_request(0.15, SOFT_MASS, SOFT_RADIUS, SOFT_RPS)
	var revived := BattleRequest.from_dict(req.to_dict())
	check.call(
		absf(revived.wall_drain_cap_share - 0.15) < EPS,
		"往復: wall_drain_cap_shareが保存される (%.2f)" % revived.wall_drain_cap_share
	)
	check.call(
		absf(
			float(BattleResolver.resolve(revived).player_rps_loss.get("wall", 0.0))
			- float(BattleResolver.resolve(req).player_rps_loss.get("wall", 0.0))
		) < EPS,
		"往復: 往復しても結果が変わらない"
	)

	var old_dict := req.to_dict()
	old_dict.erase("wall_drain_cap_share")
	var old := BattleRequest.from_dict(old_dict)
	check.call(
		old.wall_drain_cap_share == 0.0,
		"旧データ互換: キーが無ければ天井なし(0)で読む (%.2f)" % old.wall_drain_cap_share
	)
	check.call(
		absf(
			float(BattleResolver.resolve(old).player_rps_loss.get("wall", 0.0))
			- _wall_loss(0.0, SOFT_MASS, SOFT_RADIUS, SOFT_RPS)
		) < EPS,
		"旧データ互換: 当時どおり天井なしの喪失になる"
	)


## 実UIの配線。Battle.gdはautoload(GameState)を参照するのでヘッドレスの--scriptからは
## new()できないため、test_battle_defaults.gdと同じくソーステキストで確認する。
func _test_battle_wires_the_knob(check: Callable) -> void:
	var src := FileAccess.get_file_as_string("res://scenes/battle/Battle.gd")
	check.call(src != "", "配線: Battle.gd を読めた")
	check.call(
		src.contains("request.wall_drain_cap_share = wall_drain_cap_share"),
		"配線: Battle.gdが@exportの天井をrequestへ載せている"
	)
