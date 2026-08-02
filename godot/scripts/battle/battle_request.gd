class_name BattleRequest
extends RefCounted

## 1戦を計算するのに必要な入力の全部。
##
## 「発射内容を渡す → 全部計算 → 結果を再生」という形にするための入り口。
## 今はローカルのBattleResolverが受け取るが、将来オンライン対戦をやるときは
## そのままサーバーへ送るものになる。だからNodeにもシーンにも依存させず、
## to_dict()で丸ごと送れるようにしてある。
##
## 敵の出現内容(位置・初速)が結果ではなく入力なのは、発射前に決まって
## EnemyTelegraphが予告しているため。そうでないと予告が嘘になる。
## 本物のサーバーでは「開始時にサーバーが出現内容を配る → プレイヤーが発射を
## 送る → サーバーが解決」になるが、決める主体が変わるだけでこの形は変わらない。


class Launch:
	extends RefCounted

	var stats: SpinnerStats
	var position: Vector2
	var velocity: Vector2

	func _init(stats_: SpinnerStats, position_: Vector2, velocity_: Vector2) -> void:
		stats = stats_
		position = position_
		velocity = velocity_

	func to_dict() -> Dictionary:
		return {
			"mass": stats.mass,
			"radius": stats.radius,
			"friction": stats.friction,
			"restitution": stats.restitution,
			"rps": stats.rps,
			"spin_decay": stats.spin_decay,
			"wall_keep": stats.wall_keep,
			"hit_guard": stats.hit_guard,
			"edge": stats.edge,
			"drill": stats.drill,
			"pos": [position.x, position.y],
			"vel": [velocity.x, velocity.y],
		}

	static func from_dict(d: Dictionary) -> Launch:
		var stats_ := SpinnerStats.new()
		stats_.mass = d["mass"]
		stats_.radius = d["radius"]
		stats_.friction = d["friction"]
		stats_.restitution = d["restitution"]
		stats_.rps = d["rps"]
		# 旧いJSONにはspin_decay/wall_keep/hit_guard/edge/drillが無いので、既定で読む（往復の後方互換）。
		stats_.spin_decay = d.get("spin_decay", 1.0)
		stats_.wall_keep = d.get("wall_keep", 0.0)
		stats_.hit_guard = d.get("hit_guard", 0.0)
		stats_.edge = d.get("edge", 0.0)
		stats_.drill = d.get("drill", 0.0)
		return Launch.new(
			stats_,
			Vector2(d["pos"][0], d["pos"][1]),
			Vector2(d["vel"][0], d["vel"][1])
		)


var player: Launch

## 敵は複数出うる（乱戦）。1体なら要素1の配列。順序はシリアライズ往復でも
## 保たれ、決定性のある衝突解決順(=index順)の土台になるので崩さないこと。
var enemies: Array[Launch] = []

## アリーナ。中心と壁はここから決まる。
var arena_bounds: Rect2 = Rect2(0, 0, 10, 10)

## 壁の形。矩形/八角形/円形。
var wall_shape: ArenaWall.WallShape = ArenaWall.WallShape.RECT

## 障害物。xy=中心、z=半径の固定円。
var obstacles: Array[Vector3] = []

## ステージの傾斜と、ぶつかり合いの調整値。Battle.tscnの@exportから来る。
## 既定値はBattle.gdの@export既定値と一致していること(tests/test_battle_defaults.gd
## が照合する)。ズレると実UI・bot統計・コールドプレイCLIが別のゲームを遊ぶことになる。
##
## violence/natural_damping/spin_kick_scaleの現行値は「減衰と削りの比」の再設計
## (2026-07-21): 旧比(violence=0.04, damping=1.0)ではLv4-5の敵死因の8割が自然減衰で、
## 当てにいかず低速で待つ受け身が最適解だった。削りを1.5倍・自然減衰を0.75倍にして
## 決着を接触寄りに。第2弾(2026-07-22)はLv3+の敵spin_decay<1(寿命の逆転解消)と対で
## violence 0.06→0.07。spin_kick_scaleは削り比例なので反比例(1.35→1.15)で勢いを維持。
##
## 第3弾(2026-08-01)「壁支配の是正」: 壁の喪失を絶対量へ寄せた(wall_absolute_share)
## だけでは決着が自然減衰待ちに倒れる(段9の死因が減衰350/366)ので、減衰を薄くして
## (0.75→0.30)接触の取り分を空け、そのぶん削りを強めて(0.07→0.16)決着の速さを保つ。
## 3つは一体で、どれか1つだけ動かすと必ずどれか別の機構が支配する(計測はjournal参照)。
## spin_kick_scaleは今回あえて据え置き=弾き飛ばしは強くなる(当てた手応えを上げる方向)。
var stage_strength: float = 4.9
var stage_shape: SpinnerPhysics.StageShape = SpinnerPhysics.StageShape.DISH
var violence: float = 0.16
var spin_kick_scale: float = 1.15
var natural_damping: float = 0.30
var wall_damping: float = 0.75

## 壁ダンピングを衝突の激しさに比例させる基準速度。壁法線方向の進入速度が
## この値以上でwall_dampingそのまま(激突=従来の代償)、遅い接触ほど無損失に近づく。
## 0以下でスケール無効=常にwall_damping(旧挙動)。詳細はSpinnerPhysics.
## impact_scaled_wall_damping。
var wall_impact_ref_speed: float = 8.0

## 衝突削りの計算に使う速さの床。相手の速さがこれ未満でも、この速さぶんの削りが
## 出る=遅い接触でも最低限噛み合う。壁のwall_impact_ref_speed(速い激突ほど痛い)と
## 対の泥仕合対策で、低速の微衝突の応酬が何も生まず決着が壁・減衰任せになるのを
## 防ぐ。0以下で床なし(旧挙動)。詳細はSpinnerPhysics.bitten_speed。
var bite_floor_speed: float = 4.0

## 壁の喪失を「現在rpsへの乗算」から「絶対量」へ寄せる度合いと、その威力。
## 1.0で完全に絶対量、0で従来の乗算のみ(旧挙動)。詳細はBattleResolver._wall_damaged_rps。
var wall_absolute_share: float = 0.6
var wall_violence: float = 0.35

## 敵同士の衝突で互いに与える削り(と削り比例のspin_kick)の倍率。1.0で対等
## (プレイヤーと同じ扱い)。「乱戦一択」の検証(2026-07-29)で、Lv1-2の乱戦は
## 勝率が単体と同等(98〜100%)のまま報酬だけ頭数倍のジャックポットだと判明した。
## 正体は同士討ち: 柔らかい序盤の敵ほど衝突のたび互いを大きく削り、頭数が
## 増えるほど勝手に潰し合って脅威が頭数ぶん増えない。この係数で同士討ちを
## 弱めると、柔らかい敵の乱戦ほど選択的に手強くなる(硬い後半の敵は元々
## ほぼ削り合えないので影響が小さい)。プレイヤーが与える・受ける削りには
## 一切効かない。1.0でスケール無効=旧挙動。
## 0.5の採用(2026-07-29): ランボット統計(300ラン×4方針)で単体戦は全Lvノイズ範囲の
## まま、乱戦だけ勝率が下がり(Lv2 3体 86.8→73.7% / Lv3 3体 44.0→29.9%)、Lv1乱戦は
## 98%残で導入の優しさを保った。0.25も測ったがLv3 3体が16.4%まで落ちて
## 「選べる賭け」でなく死の部屋になるため見送り。
var enemy_mutual_drain_scale: float = 0.5

## 1回の衝突で奪えるrpsの天井を、受け手の回転ゲージ(初期rps)に対する割合で決める。
## 0.5なら「満タンの相手を倒すには最低2回噛み合う」。0以下で天井なし(旧挙動)。
## 詳細はSpinnerPhysics.capped_spin_drain。
##
## 採用の経緯(2026-08-02): 削りは相手の硬さに反比例するので、柔らかいLv1相手には
## 1撃でゲージ全部を超える削りが出ていた(ボット500戦でLv1の勝ちの99.2%が衝突1回、
## コールドプレイでも段1が0.42秒・衝突1回。レポートのアラートも段2を
## 「勝率99.7% 何をしても勝つので、そこに選択がない」と名指ししていた)。
##
## 0.5の採用: 0.34(最低3回)も測ったが、敵が2回目の弾きを生き延びるぶん壁で死ぬ
## ようになり、Lv1の死因が 削り82.5%/壁17.5% → 36.9%/63.1% と壁へ倒れた
## (「壁支配の是正」2026-08-01 で削りを主死因に戻した方向への逆行)。0.5なら
## Lv1の即死だけが消えて(1衝突決着 72.4%→13.2%)死因の内訳はほぼ据え置き、
## Lv2〜5は決着中央値まで完全に不変、クリア率も48.0%のまま動かない。
var drain_cap_share: float = 0.5
var lose_threshold: float = 0.03

## ゴーストの無敵時間(秒)。開始からこの時刻までプレイヤーと敵の衝突判定を切る。
## 0なら無効(従来どおり最初から当たる)。ゴースト札の枚数で決まる
## (CustomPartCatalog.total_ghost_seconds)。壁・障害物・敵同士の衝突には効かない。
var ghost_duration: float = 0.0

## 計算の刻み幅(秒)。描画のfpsとは独立。
var time_step: float = 1.0 / 60.0

## この時間を超えたら打ち切る。自然減衰があるので必ず決着するはずだが、
## 純粋関数で無限ループは許容できない。
var max_duration: float = 120.0


func to_dict() -> Dictionary:
	return {
		"player": player.to_dict(),
		"enemies": enemies.map(func(e: Launch) -> Dictionary: return e.to_dict()),
		"arena": [arena_bounds.position.x, arena_bounds.position.y,
			arena_bounds.size.x, arena_bounds.size.y],
		"wall_shape": int(wall_shape),
		"obstacles": obstacles.map(func(o: Vector3) -> Array:
			return [o.x, o.y, o.z]),
		"stage_strength": stage_strength,
		"stage_shape": int(stage_shape),
		"violence": violence,
		"spin_kick_scale": spin_kick_scale,
		"natural_damping": natural_damping,
		"wall_damping": wall_damping,
		"wall_impact_ref_speed": wall_impact_ref_speed,
		"bite_floor_speed": bite_floor_speed,
		"wall_absolute_share": wall_absolute_share,
		"wall_violence": wall_violence,
		"enemy_mutual_drain_scale": enemy_mutual_drain_scale,
		"drain_cap_share": drain_cap_share,
		"lose_threshold": lose_threshold,
		"ghost_duration": ghost_duration,
		"time_step": time_step,
		"max_duration": max_duration,
	}


static func from_dict(d: Dictionary) -> BattleRequest:
	var r := BattleRequest.new()
	r.player = Launch.from_dict(d["player"])
	var enemies_: Array[Launch] = []
	for ed in d["enemies"]:
		enemies_.append(Launch.from_dict(ed))
	r.enemies = enemies_
	r.arena_bounds = Rect2(d["arena"][0], d["arena"][1], d["arena"][2], d["arena"][3])
	r.wall_shape = d["wall_shape"]
	var obstacles_: Array[Vector3] = []
	for o in d["obstacles"]:
		obstacles_.append(Vector3(o[0], o[1], o[2]))
	r.obstacles = obstacles_
	r.stage_strength = d["stage_strength"]
	r.stage_shape = d["stage_shape"]
	r.violence = d["violence"]
	r.spin_kick_scale = d["spin_kick_scale"]
	r.natural_damping = d["natural_damping"]
	r.wall_damping = d["wall_damping"]
	# 旧い保存データにキーが無いときは0(スケール無効=旧挙動)で補い、当時の
	# 結果をそのまま再現できるようにする(ghost_durationの既定0と同じ向き)。
	r.wall_impact_ref_speed = d.get("wall_impact_ref_speed", 0.0)
	# 同上: 旧い保存データは床なし(0)で補い、当時の結果をそのまま再現する。
	r.bite_floor_speed = d.get("bite_floor_speed", 0.0)
	# 旧データは0=無効(従来の乗算のみ)で読む。記録当時の挙動をそのまま再現するため。
	r.wall_absolute_share = d.get("wall_absolute_share", 0.0)
	r.wall_violence = d.get("wall_violence", 0.0)
	# 同上: 旧い保存データはスケール無効(1.0=対等)で補い、当時の結果を再現する。
	r.enemy_mutual_drain_scale = d.get("enemy_mutual_drain_scale", 1.0)
	# 同上: 旧い保存データは天井なし(0)で補い、当時の結果をそのまま再現する。
	r.drain_cap_share = d.get("drain_cap_share", 0.0)
	r.lose_threshold = d["lose_threshold"]
	# 旧い保存データにキーが無くても壊れないよう既定0で補う。
	r.ghost_duration = d.get("ghost_duration", 0.0)
	r.time_step = d["time_step"]
	r.max_duration = d["max_duration"]
	return r
