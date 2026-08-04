extends RefCounted

## 壁の喪失をその場に出す表示のテスト。
##
## (1) WallDamageReadout の純粋関数: 足切り(ゲージ比)・持ち主不明の除外・文字・
##     色分け・退場カーブ(保持してから抜ける/上へ逃げる)。
## (2) リゾルバが Impact.owner に「誰が壁で失ったか」を事実として記録すること。
##     乱戦で敵ごとに別のindexが付き、プレイヤーのものは OWNER_PLAYER になる。
## (3) dict往復で持ち主が保存され、持ち主を持たない旧4要素dictは UNKNOWN
##     ＝表示しない側へ落ちる後方互換。

const EPS := 1e-3


func run(check: Callable) -> void:
	_test_should_show(check)
	_test_text_and_color(check)
	_test_exit_curves(check)
	_test_owner_recorded(check)
	_test_owner_serialization(check)


func _test_should_show(check: Callable) -> void:
	const P := BattleResult.Impact.OWNER_PLAYER
	check.call(
		WallDamageReadout.should_show(1.5, 40.0, 0.03, P),
		"walldamage: ゲージの3%以上の喪失は出す"
	)
	check.call(
		not WallDamageReadout.should_show(1.0, 40.0, 0.03, P),
		"walldamage: ゲージの3%未満の擦り接触は出さない"
	)
	# 同じ絶対量でも、ゲージが小さければ「痛い」。割合で切っている証拠。
	check.call(
		WallDamageReadout.should_show(1.0, 15.0, 0.03, P),
		"walldamage: 同じ1.0でもゲージ15なら痛いので出す"
	)
	check.call(
		not WallDamageReadout.should_show(0.0, 40.0, 0.03, P)
			and not WallDamageReadout.should_show(-1.0, 40.0, 0.03, P),
		"walldamage: 喪失0以下は出さない"
	)
	check.call(
		not WallDamageReadout.should_show(5.0, 0.0, 0.03, P),
		"walldamage: ゲージが取れない(0)なら割合が決まらないので出さない"
	)
	check.call(
		WallDamageReadout.should_show(0.01, 40.0, 0.0, P),
		"walldamage: 足切り0は無効化＝正の喪失を全部出す"
	)
	check.call(
		not WallDamageReadout.should_show(
			9.9, 40.0, 0.03, BattleResult.Impact.OWNER_UNKNOWN
		),
		"walldamage: 持ち主不明(旧結果)は色を分けられないので出さない"
	)


func _test_text_and_color(check: Callable) -> void:
	check.call(
		WallDamageReadout.text(9.74) == "-9.7",
		"walldamage: 文字は減少符号つき小数1桁 (%s)" % WallDamageReadout.text(9.74)
	)
	check.call(
		WallDamageReadout.text(-3.0) == "-0.0",
		"walldamage: 負の喪失は0扱い(二重のマイナスを出さない)"
	)
	var player_col := Color(0.1, 0.9, 1.0)
	var enemy_col := Color(1.0, 0.2, 0.3)
	check.call(
		WallDamageReadout.color(
			BattleResult.Impact.OWNER_PLAYER, player_col, enemy_col
		) == player_col,
		"walldamage: 自分の喪失は自分のコマの色"
	)
	check.call(
		WallDamageReadout.color(0, player_col, enemy_col) == enemy_col
			and WallDamageReadout.color(2, player_col, enemy_col) == enemy_col,
		"walldamage: 敵の喪失は敵の色(indexが幾つでも)"
	)


func _test_exit_curves(check: Callable) -> void:
	check.call(
		absf(WallDamageReadout.alpha_at(0.0, 0.7, 0.35) - 1.0) < EPS
			and absf(WallDamageReadout.alpha_at(0.24, 0.7, 0.35) - 1.0) < EPS,
		"walldamage: 保持区間は不透明度が満タンのまま"
	)
	# 同じ時刻でも保持を切れば薄くなる＝hold_shareが本当に効いている。
	# (保持区間の1.0はクランプでも作れてしまうので、比較でしか固定できない)
	check.call(
		WallDamageReadout.alpha_at(0.24, 0.7, 0.0) < 1.0 - EPS,
		"walldamage: 保持0なら同じ時刻でもう薄れている (%.3f)"
			% WallDamageReadout.alpha_at(0.24, 0.7, 0.0)
	)
	check.call(
		absf(WallDamageReadout.alpha_at(0.35, 0.7, 0.5) - 1.0) < EPS
			and WallDamageReadout.alpha_at(0.35, 0.7, 0.2) < 1.0 - EPS,
		"walldamage: 保持を伸ばすとその時刻がまだ満タン側に入る"
	)
	check.call(
		absf(WallDamageReadout.alpha_at(0.7, 0.7, 0.35)) < EPS,
		"walldamage: 終わりで不透明度0"
	)
	var prev := 2.0
	var decreasing := true
	for k in 10:
		var a := WallDamageReadout.alpha_at(0.35 + 0.035 * k, 0.7, 0.35)
		if a > prev + EPS:
			decreasing = false
		prev = a
	check.call(decreasing, "walldamage: 保持のあとは単調に薄くなる")
	check.call(
		absf(WallDamageReadout.alpha_at(0.1, 0.0, 0.35)) < EPS,
		"walldamage: duration=0は進み具合1.0＝即消滅(0除算しない)"
	)

	check.call(
		absf(WallDamageReadout.rise_at(0.0, 0.7, 0.9)) < EPS
			and absf(WallDamageReadout.rise_at(0.7, 0.7, 0.9) - 0.9) < EPS,
		"walldamage: 逃げる距離は0から満額まで"
	)
	# 1-(1-p)^2 は前半で半分以上を稼ぐ。出た瞬間にコマから離れる証拠。
	check.call(
		WallDamageReadout.rise_at(0.35, 0.7, 0.9) > 0.9 * 0.5 + EPS,
		"walldamage: 前半で半分より多く上がる(速く出て緩く止まる)"
	)


## リゾルバが壁の喪失の持ち主を記録している事実。
## 壁だけの状況を作るため、プレイヤーと敵を離して置き、それぞれ別の壁へ撃つ。
func _test_owner_recorded(check: Callable) -> void:
	var result := BattleResolver.resolve(_wall_only_request(2))

	var owners := {}
	for imp in result.wall_impacts:
		owners[imp.owner] = true
	check.call(
		result.wall_impacts.size() > 0, "walldamage: 壁の衝撃波が記録された"
	)
	check.call(
		owners.has(BattleResult.Impact.OWNER_PLAYER),
		"walldamage: 自分の壁ヒットは OWNER_PLAYER で記録される"
	)
	check.call(
		owners.has(0) and owners.has(1),
		"walldamage: 乱戦では敵ごとに別のindexで記録される (%s)" % str(owners.keys())
	)
	var unknown := false
	for imp in result.wall_impacts:
		if imp.owner == BattleResult.Impact.OWNER_UNKNOWN:
			unknown = true
	check.call(not unknown, "walldamage: リゾルバは持ち主不明を残さない")

	# 記録された持ち主が「その体の内訳」と量で一致すること。取り違えていたら
	# 合計がずれる(indexを1つずらすサボタージュがここで落ちる)。
	var by_owner := {}
	for imp in result.wall_impacts:
		by_owner[imp.owner] = float(by_owner.get(imp.owner, 0.0)) + imp.strength
	var player_wall := float(result.player_rps_loss.get("wall", 0.0))
	check.call(
		absf(float(by_owner.get(BattleResult.Impact.OWNER_PLAYER, 0.0)) - player_wall) < EPS,
		"walldamage: OWNER_PLAYERの強度の和が自分の壁喪失と一致 (%.3f vs %.3f)"
			% [float(by_owner.get(BattleResult.Impact.OWNER_PLAYER, 0.0)), player_wall]
	)
	for i in result.enemy_rps_loss.size():
		var want := float((result.enemy_rps_loss[i] as Dictionary).get("wall", 0.0))
		check.call(
			absf(float(by_owner.get(i, 0.0)) - want) < EPS,
			"walldamage: 敵%dの強度の和がその敵の壁喪失と一致 (%.3f vs %.3f)"
				% [i + 1, float(by_owner.get(i, 0.0)), want]
		)


func _test_owner_serialization(check: Callable) -> void:
	var result := BattleResolver.resolve(_wall_only_request(1))
	check.call(result.wall_impacts.size() > 0, "walldamage: 往復用の壁ヒットがある")

	var d := result.to_dict()
	var back := BattleResult.from_dict(JSON.parse_string(JSON.stringify(d)))
	var same := back.wall_impacts.size() == result.wall_impacts.size()
	if same:
		for i in result.wall_impacts.size():
			if back.wall_impacts[i].owner != result.wall_impacts[i].owner:
				same = false
	check.call(same, "walldamage: JSON往復で持ち主が保存される")

	# 旧dict(4要素)は持ち主を持たない。UNKNOWNで読めて、表示側が黙って落とす。
	var old_d := result.to_dict()
	var trimmed: Array = []
	for x in old_d["wall_impacts"]:
		trimmed.append([x[0], x[1], x[2], x[3]])
	old_d["wall_impacts"] = trimmed
	var old_back := BattleResult.from_dict(old_d)
	var all_unknown := old_back.wall_impacts.size() == result.wall_impacts.size()
	for imp in old_back.wall_impacts:
		if imp.owner != BattleResult.Impact.OWNER_UNKNOWN:
			all_unknown = false
	check.call(all_unknown, "walldamage: 旧4要素dictは持ち主UNKNOWNで読める")
	check.call(
		not WallDamageReadout.should_show(
			99.0, 40.0, 0.03, old_back.wall_impacts[0].owner
		),
		"walldamage: 旧結果の壁ヒットは数字を出さない(当時の見た目のまま再生)"
	)


## 全員がそれぞれ別の壁へ真っ直ぐ突っ込むだけの状況。互いに離して置き、
## 傾斜も切ってあるので、rpsが減る機構は壁と自然減衰だけ＝壁の衝撃波の持ち主が
## 一意に決まる。enemy_count 体の敵を土俵の別々の辺へ向ける。
static func _wall_only_request(enemy_count: int) -> BattleRequest:
	var r := BattleRequest.new()
	r.stage_strength = 0.0
	r.max_duration = 1.0
	var p := SpinnerStats.new()
	p.radius = 0.5
	p.rps = 20.0
	r.player = BattleRequest.Launch.new(p, Vector2(5, 2), Vector2(0, -12))
	# 上辺(プレイヤー)・左辺・右辺と、別々の壁へ散らす。
	var spawns := [
		[Vector2(2, 8), Vector2(-12, 0)],
		[Vector2(8, 8), Vector2(12, 0)],
		[Vector2(5, 8), Vector2(0, 12)],
	]
	var list: Array[BattleRequest.Launch] = []
	for i in mini(enemy_count, spawns.size()):
		var e := SpinnerStats.new()
		e.radius = 0.5
		e.rps = 20.0
		list.append(BattleRequest.Launch.new(e, spawns[i][0], spawns[i][1]))
	r.enemies = list
	return r
