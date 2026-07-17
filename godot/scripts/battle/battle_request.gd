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
		return Launch.new(
			stats_,
			Vector2(d["pos"][0], d["pos"][1]),
			Vector2(d["vel"][0], d["vel"][1])
		)


var player: Launch
var enemy: Launch

## アリーナ。中心と壁はここから決まる。
var arena_bounds: Rect2 = Rect2(0, 0, 10, 10)

## ステージの傾斜と、ぶつかり合いの調整値。Battle.tscnの@exportから来る。
var stage_strength: float = 4.9
var stage_shape: SpinnerPhysics.StageShape = SpinnerPhysics.StageShape.DISH
var violence: float = 0.08
var spin_kick_scale: float = 1.0
var natural_damping: float = 1.0
var wall_damping: float = 0.75
var lose_threshold: float = 0.03

## 計算の刻み幅(秒)。描画のfpsとは独立。
var time_step: float = 1.0 / 60.0

## この時間を超えたら打ち切る。自然減衰があるので必ず決着するはずだが、
## 純粋関数で無限ループは許容できない。
var max_duration: float = 120.0


func to_dict() -> Dictionary:
	return {
		"player": player.to_dict(),
		"enemy": enemy.to_dict(),
		"arena": [arena_bounds.position.x, arena_bounds.position.y,
			arena_bounds.size.x, arena_bounds.size.y],
		"stage_strength": stage_strength,
		"stage_shape": int(stage_shape),
		"violence": violence,
		"spin_kick_scale": spin_kick_scale,
		"natural_damping": natural_damping,
		"wall_damping": wall_damping,
		"lose_threshold": lose_threshold,
		"time_step": time_step,
		"max_duration": max_duration,
	}


static func from_dict(d: Dictionary) -> BattleRequest:
	var r := BattleRequest.new()
	r.player = Launch.from_dict(d["player"])
	r.enemy = Launch.from_dict(d["enemy"])
	r.arena_bounds = Rect2(d["arena"][0], d["arena"][1], d["arena"][2], d["arena"][3])
	r.stage_strength = d["stage_strength"]
	r.stage_shape = d["stage_shape"]
	r.violence = d["violence"]
	r.spin_kick_scale = d["spin_kick_scale"]
	r.natural_damping = d["natural_damping"]
	r.wall_damping = d["wall_damping"]
	r.lose_threshold = d["lose_threshold"]
	r.time_step = d["time_step"]
	r.max_duration = d["max_duration"]
	return r
