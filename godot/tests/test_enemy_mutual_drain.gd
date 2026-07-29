extends RefCounted

## 敵同士の削り係数 enemy_mutual_drain_scale のテスト。
##
## 「乱戦一択」の検証(2026-07-29)で、柔らかい序盤の敵は同士討ちで勝手に潰し合い、
## 乱戦の脅威が頭数ぶん増えないままの報酬ジャックポットだと分かった。この係数は
## 敵同士の衝突の削り(と削り比例のspin_kick)だけを弱める。ここで固定するのは:
##  - 敵同士の初回衝突の削り(impact強度)が係数どおりに縮むこと
##  - プレイヤーが絡む衝突は係数に一切影響されないこと(0でも従来どおり)
##  - 1.0でスケール無効=旧挙動と厳密一致
##  - シリアライズ往復と、キーの無い旧データの既定1.0(=旧挙動の再現)

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_mutual_drain_scales(check)
	_test_scale_one_is_legacy(check)
	_test_player_collisions_unaffected(check)
	_test_serialization(check)


## 敵2体が正面衝突する理想環境。自然減衰・傾斜を切り、プレイヤーは遠くに
## 静止させて接触させない。rpsの減少は敵同士の削りだけになる。
static func _enemy_pair_request(scale: float) -> BattleRequest:
	var pstats := SpinnerStats.default_player()
	var e1 := SpinnerStats.new()
	e1.radius = 0.5
	e1.rps = 20.0
	var e2 := SpinnerStats.new()
	e2.radius = 0.5
	e2.rps = 20.0

	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	r.enemy_mutual_drain_scale = scale
	r.max_duration = 0.5
	r.player = BattleRequest.Launch.new(pstats, Vector2(1, 9), Vector2.ZERO)
	r.enemies = [
		BattleRequest.Launch.new(e1, Vector2(4, 5), Vector2(6, 0)),
		BattleRequest.Launch.new(e2, Vector2(6, 5), Vector2(-6, 0)),
	]
	return r


func _test_mutual_drain_scales(check: Callable) -> void:
	var full := BattleResolver.resolve(_enemy_pair_request(1.0))
	var half := BattleResolver.resolve(_enemy_pair_request(0.5))
	var none := BattleResolver.resolve(_enemy_pair_request(0.0))
	check.call(
		not full.impacts.is_empty() and not half.impacts.is_empty(),
		"mutualdrain: 敵同士の正面衝突が起きた"
	)
	if full.impacts.is_empty() or half.impacts.is_empty() or none.impacts.is_empty():
		return
	var full_hit: float = full.impacts[0].strength
	var half_hit: float = half.impacts[0].strength
	var none_hit: float = none.impacts[0].strength
	check.call(full_hit > EPS, "mutualdrain: 係数1.0では同士討ちの削りが出る")
	check.call(
		absf(half_hit - full_hit * 0.5) < EPS,
		"mutualdrain: 係数0.5で初回衝突の削りが半分になる (%.4f vs %.4f)" % [half_hit, full_hit]
	)
	check.call(
		absf(none_hit) < EPS,
		"mutualdrain: 係数0で同士討ちの削りが消える"
	)


func _test_scale_one_is_legacy(check: Callable) -> void:
	# キーの無い旧dictから復元したリクエストは、既定(0.5)ではなく係数1.0=旧挙動を
	# 再現する: 全敵の結末が係数1.0の明示リクエストと厳密一致する。
	var legacy := BattleResolver.resolve(_enemy_pair_request(1.0))
	var old_dict := _enemy_pair_request(0.5).to_dict()
	old_dict.erase("enemy_mutual_drain_scale")
	var revived := BattleResolver.resolve(BattleRequest.from_dict(old_dict))
	for i in 2:
		var legacy_last: float = legacy.enemy_tracks[i][-1].rps
		var revived_last: float = revived.enemy_tracks[i][-1].rps
		check.call(
			absf(legacy_last - revived_last) < EPS,
			"mutualdrain: 旧dict(キー無し)の敵%dの結末が係数1.0の旧挙動と一致" % (i + 1)
		)


## プレイヤーと敵の正面衝突。係数を0にしても一切変わらないこと。
static func _player_hit_request(scale: float) -> BattleRequest:
	var pstats := SpinnerStats.default_player()
	var estats := SpinnerStats.new()
	estats.radius = 0.5
	estats.rps = 20.0

	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	r.enemy_mutual_drain_scale = scale
	r.max_duration = 0.5
	r.player = BattleRequest.Launch.new(pstats, Vector2(4, 5), Vector2(6, 0))
	r.enemies = [BattleRequest.Launch.new(estats, Vector2(6, 5), Vector2(-6, 0))]
	return r


func _test_player_collisions_unaffected(check: Callable) -> void:
	var full := BattleResolver.resolve(_player_hit_request(1.0))
	var none := BattleResolver.resolve(_player_hit_request(0.0))
	check.call(
		not full.impacts.is_empty() and not none.impacts.is_empty(),
		"mutualdrain: プレイヤー対敵の衝突が起きた"
	)
	if full.impacts.is_empty() or none.impacts.is_empty():
		return
	check.call(
		full.impacts[0].strength > EPS,
		"mutualdrain: プレイヤー対敵の削りが出る"
	)
	check.call(
		absf(full.impacts[0].strength - none.impacts[0].strength) < EPS,
		"mutualdrain: プレイヤー対敵の削りは係数に影響されない"
	)


func _test_serialization(check: Callable) -> void:
	var r := _enemy_pair_request(0.5)
	var revived := BattleRequest.from_dict(
		JSON.parse_string(JSON.stringify(r.to_dict()))
	)
	check.call(
		absf(revived.enemy_mutual_drain_scale - 0.5) < EPS,
		"mutualdrain: to_dict/from_dictの往復で係数が保たれる"
	)
	var old_dict := r.to_dict()
	old_dict.erase("enemy_mutual_drain_scale")
	check.call(
		absf(BattleRequest.from_dict(old_dict).enemy_mutual_drain_scale - 1.0) < EPS,
		"mutualdrain: キーの無い旧データは1.0(=旧挙動)で読む"
	)
