extends RefCounted

## 壁の回転喪失を絶対量へ寄せる仕組み(absolute_wall_drain / wall_absolute_share)のテスト。
##
## 従来、壁の喪失だけが「現在rpsへの乗算」だった。rpsを減らす3機構のうち乗算はここだけで、
## 報酬でrpsを積むほど壁1回の代償が比例して膨らむ=後半は壁だけが勝敗を決めていた
## (ランボット300で段9の敗者死因は 削り1 / 壁159 / 減衰160、段1は 削り244 / 壁8)。
##
## ここで固定するのは:
##  - 純関数の向き: 進入速度に比例し、硬さ(質量×半径²)に反比例する
##  - share=0 で従来の乗算と厳密一致(旧データの再現)
##  - share=1 で絶対量そのもの
##  - **rpsが増えても壁1回で失う量が増えない**(この変更の目的そのもの)
##  - wall_keep(RAGE札)が絶対量側にも効くこと
##  - シリアライズ往復と、キーの無い旧データの既定0(=旧挙動)

const EPS := 1e-4


func run(check: Callable) -> void:
	_test_absolute_function(check)
	_test_share_endpoints(check)
	_test_loss_stops_scaling_with_rps(check)
	_test_wall_keep_applies(check)
	_test_serialization(check)


func _test_absolute_function(check: Callable) -> void:
	var base := SpinnerPhysics.absolute_wall_drain(8.0, 1.5, 0.7, 0.35)
	check.call(base > 0.0, "absolute: 正の進入速度で正の喪失が出る (%.4f)" % base)
	check.call(
		absf(SpinnerPhysics.absolute_wall_drain(16.0, 1.5, 0.7, 0.35) - base * 2.0) < EPS,
		"absolute: 進入速度2倍で喪失2倍(比例)"
	)
	check.call(
		absf(SpinnerPhysics.absolute_wall_drain(8.0, 3.0, 0.7, 0.35) - base * 0.5) < EPS,
		"absolute: 質量2倍で喪失半分(硬さに反比例)"
	)
	check.call(
		absf(SpinnerPhysics.absolute_wall_drain(8.0, 1.5, 1.4, 0.35) - base * 0.25) < EPS,
		"absolute: 半径2倍で喪失1/4(半径は2乗で効く)"
	)
	check.call(
		absf(SpinnerPhysics.absolute_wall_drain(-5.0, 1.5, 0.7, 0.35)) < EPS,
		"absolute: 負の進入速度は0でクランプ"
	)
	check.call(
		absf(SpinnerPhysics.absolute_wall_drain(8.0, 0.0, 0.7, 0.35)) < EPS
		and absf(SpinnerPhysics.absolute_wall_drain(8.0, 1.5, 0.0, 0.35)) < EPS,
		"absolute: 質量・半径が0なら0(0除算しない)"
	)


## 壁へ1回だけぶつかる理想環境。自然減衰・傾斜を切るので、rpsの減少は壁だけ。
## 敵は遠くに静止させて接触させない。
func _one_wall_hit_request(rps: float, share: float, wall_keep: float) -> BattleRequest:
	var pstats := SpinnerStats.default_player()
	pstats.rps = rps
	pstats.wall_keep = wall_keep
	var estats := SpinnerStats.new()
	estats.radius = 0.5
	estats.rps = 1000.0

	var r := BattleRequest.new()
	r.natural_damping = 0.0
	r.stage_strength = 0.0
	r.wall_absolute_share = share
	# 1回あたりの天井も切る。ここで見たいのは乗算と絶対量のブレンドそのもので、
	# 天井が被さると端点(share=0の25%喪失)が頭打ちになって式が読めない。
	# 天井は test_wall_drain_cap.gd が受け持つ。
	r.wall_drain_cap_share = 0.0
	# 速度スケールを切って、進入速度によらず base/絶対量そのものを見る。
	r.wall_impact_ref_speed = 0.0
	r.max_duration = 0.5
	# 下の壁(y=0)へ一直線。半径0.7なので0.8進むと接触する。
	r.player = BattleRequest.Launch.new(pstats, Vector2(5, 1.5), Vector2(0, -12.0))
	r.enemies = [BattleRequest.Launch.new(estats, Vector2(8, 8), Vector2.ZERO)]
	return r


func _wall_loss(rps: float, share: float, wall_keep: float = 0.0) -> float:
	var result := BattleResolver.resolve(_one_wall_hit_request(rps, share, wall_keep))
	return result.player_rps_loss.get("wall", 0.0)


func _wall_loss_with_violence(rps: float, share: float, wall_violence: float) -> float:
	var r := _one_wall_hit_request(rps, share, 0.0)
	r.wall_violence = wall_violence
	return BattleResolver.resolve(r).player_rps_loss.get("wall", 0.0)


func _test_share_endpoints(check: Callable) -> void:
	var rps := 40.0
	var proportional := _wall_loss(rps, 0.0)
	check.call(
		absf(proportional - rps * 0.25) < EPS,
		"share=0: 従来の乗算どおり25%%喪失 (%.4f)" % proportional
	)
	var absolute := _wall_loss(rps, 1.0)
	# 発射速度12から壁に触れるまでに摩擦でわずかに落ちるので、進入速度12ちょうどの
	# 理論値とは端数がずれる。式そのものは「wall_violenceに比例する」で押さえる。
	var doubled := _wall_loss_with_violence(rps, 1.0, BattleRequest.new().wall_violence * 2.0)
	check.call(
		absf(doubled - absolute * 2.0) < EPS,
		"share=1: 喪失はwall_violenceに比例する (%.4f ≒ %.4f)" % [doubled, absolute * 2.0]
	)
	var ideal := SpinnerPhysics.absolute_wall_drain(
		12.0, 1.5, 0.7, BattleRequest.new().wall_violence
	)
	check.call(
		absf(absolute - ideal) < ideal * 0.05,
		"share=1: 絶対量の式どおりの大きさ (%.4f ≒ %.4f)" % [absolute, ideal]
	)
	var half := _wall_loss(rps, 0.5)
	check.call(
		absf(half - (proportional + absolute) * 0.5) < EPS,
		"share=0.5: 乗算と絶対量のちょうど中間 (%.4f)" % half
	)


## この変更の目的そのもの: 絶対量に寄せた壁は「今どれだけ回っているか」で
## 代償が変わらない。乗算のままだとrpsに比例して膨らむ。
func _test_loss_stops_scaling_with_rps(check: Callable) -> void:
	var low_prop := _wall_loss(10.0, 0.0)
	var high_prop := _wall_loss(40.0, 0.0)
	check.call(
		high_prop > low_prop * 3.5,
		"乗算(旧): rps4倍なら壁1回の喪失もほぼ4倍 (%.4f vs %.4f)" % [high_prop, low_prop]
	)
	var low_abs := _wall_loss(10.0, 1.0)
	var high_abs := _wall_loss(40.0, 1.0)
	check.call(
		absf(high_abs - low_abs) < EPS,
		"絶対量: rpsが4倍でも壁1回の喪失は変わらない (%.4f ≒ %.4f)" % [high_abs, low_abs]
	)
	# 既定(share>0)でも、rpsの伸びに対して喪失の伸びははっきり鈍る。
	var share: float = BattleRequest.new().wall_absolute_share
	check.call(share > 0.0, "既定: wall_absolute_shareが有効になっている (%.2f)" % share)
	var low_default := _wall_loss(10.0, share)
	var high_default := _wall_loss(40.0, share)
	check.call(
		high_default < low_default * 4.0 - EPS,
		"既定: rps4倍でも喪失は4倍未満に留まる (%.4f < %.4f)" % [high_default, low_default * 4.0]
	)


func _test_wall_keep_applies(check: Callable) -> void:
	var plain := _wall_loss(40.0, 1.0, 0.0)
	var kept := _wall_loss(40.0, 1.0, 0.5)
	check.call(
		absf(kept - plain * 0.5) < EPS,
		"wall_keep: 絶対量側も0.5で喪失半分 (%.4f ≒ %.4f)" % [kept, plain * 0.5]
	)
	var full := _wall_loss(40.0, 1.0, 1.0)
	check.call(full < EPS, "wall_keep=1: 絶対量側でも壁で失わない (%.4f)" % full)


func _test_serialization(check: Callable) -> void:
	var r := _one_wall_hit_request(40.0, 0.6, 0.0)
	r.wall_violence = 0.42
	var round_tripped := BattleRequest.from_dict(r.to_dict())
	check.call(
		absf(round_tripped.wall_absolute_share - 0.6) < EPS
		and absf(round_tripped.wall_violence - 0.42) < EPS,
		"往復: wall_absolute_share/wall_violenceが保たれる"
	)
	check.call(
		BattleResolver.resolve(round_tripped).player_rps_loss.get("wall", 0.0)
			== BattleResolver.resolve(r).player_rps_loss.get("wall", 0.0),
		"往復: 往復しても壁の喪失が変わらない"
	)
	var old := r.to_dict()
	old.erase("wall_absolute_share")
	old.erase("wall_violence")
	check.call(
		absf(BattleRequest.from_dict(old).wall_absolute_share) < EPS,
		"旧データ: キーが無ければ0(=従来の乗算のみ)で読む"
	)
