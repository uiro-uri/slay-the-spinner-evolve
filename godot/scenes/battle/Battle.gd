extends Node2D

## 1戦分の進行。物理ステップを駆動し、勝敗を決める。
##
## 計算式はSpinnerPhysicsの純粋関数が持つ。ここは「毎フレーム何をどの順で
## 呼ぶか」と、その結果としての勝敗だけを見る。
##
## プロトタイプ(simulation.py)はサーバー側で全ステップを先に計算し、
## その履歴をCSSアニメーションで再生していた。ここではリアルタイムに回す。
##
## 数値はすべて手触りで調整する前提。プロトタイプの値は出発点でしかない。

signal finished(player_won: bool)

const COLLISION_SPARK: PackedScene = preload("res://scenes/battle/CollisionSpark.tscn")

## ステージの傾斜の強さ。
@export_range(0.0, 20.0, 0.1) var stage_strength: float = 4.9

## すり鉢(外側ほど急)か円錐(一定傾斜)か。どちらが気持ちいいかは動かして決める。
@export var stage_shape: SpinnerPhysics.StageShape = SpinnerPhysics.StageShape.DISH

## ぶつかり合いの激しさ。大きいほど1回の衝突で削れるRPSが増える。
@export_range(0.0, 1.0, 0.01) var violence: float = 0.08

## 削れたRPSがどれだけ弾き飛ばしに変わるか。
@export_range(0.0, 5.0, 0.05) var spin_kick_scale: float = 1.0

## 何もしなくても失われる回転(毎秒、半径に比例)。
@export_range(0.0, 5.0, 0.05) var natural_damping: float = 1.0

## 壁にぶつかった時に残る回転の割合。
@export_range(0.0, 1.0, 0.01) var wall_damping: float = 0.75

## これを下回ったら負け。
@export_range(0.0, 1.0, 0.01) var lose_threshold: float = 0.03

## 決着後、余韻を見せてから次へ進むまでの秒数。
@export_range(0.0, 5.0, 0.1) var finish_delay: float = 2.0

## 敵の初期状態。M3でマップから選ばれた敵に差し替える。
@export var enemy_start_pos: Vector2 = Vector2(8, 2)
@export var enemy_start_vel: Vector2 = Vector2(-3, 4)

@export_group("調整用")

## ドラッグを待たずに即開始する。このシーンだけをF5で走らせて挙動を見る用。
## 本編ではMainがドラッグ発射で始めるので false のままにしておくこと。
@export var auto_start: bool = false

## auto_start時のプレイヤーの初期位置と初速。
@export var auto_start_pos: Vector2 = Vector2(2, 8)
@export var auto_start_vel: Vector2 = Vector2(6, -6)

@onready var _arena: Arena = $ArenaRoot/Arena
@onready var _player: Disc = $ArenaRoot/PlayerDisc
@onready var _enemy: Disc = $ArenaRoot/EnemyDisc
@onready var _launcher: LaunchController = $ArenaRoot/LaunchController
@onready var _message: Label = $UI/Message
@onready var _player_bar: ProgressBar = $UI/Bars/PlayerBar
@onready var _enemy_bar: ProgressBar = $UI/Bars/EnemyBar

var _running: bool = false
var _resolved: bool = false
var _max_rps: float = 1.0


func _ready() -> void:
	set_physics_process(false)
	_launcher.launched.connect(_on_launched)
	_message.text = "BATTLE_DRAG_TO_SHOOT"
	_apply_run_state()
	# 発射前は待機位置に置いておく。
	_enemy.position = enemy_start_pos
	_enemy.velocity = Vector2.ZERO
	_player.reset_spin()
	_enemy.reset_spin()
	_max_rps = maxf(_player.stats.rps, _enemy.stats.rps)
	_update_bars()

	if auto_start:
		_launcher.set_enabled(false)
		_message.text = ""
		start(auto_start_pos, auto_start_vel, enemy_start_pos, enemy_start_vel)


## ランの状態があればそれを使う。Battle.tscn単体で走らせたときは
## シーンに置いてある値のままにして、単体で調整できるようにしておく。
func _apply_run_state() -> void:
	if GameState.player_stats != null:
		_player.stats = GameState.player_stats
	var enemy: EnemyData = GameState.pending_enemy
	if enemy != null and enemy.stats != null:
		_enemy.stats = enemy.stats
		enemy_start_pos = enemy.start_pos
		enemy_start_vel = enemy.start_vel


func _on_launched(pos: Vector2, velocity: Vector2) -> void:
	_launcher.set_enabled(false)
	_message.text = ""
	start(pos, velocity, enemy_start_pos, enemy_start_vel)


## 初期位置と初速を与えて開始する。座標はアリーナのユニット系。
func start(
	player_pos: Vector2, player_vel: Vector2,
	enemy_pos: Vector2, enemy_vel: Vector2
) -> void:
	_player.position = player_pos
	_player.velocity = player_vel
	_player.reset_spin()

	_enemy.position = enemy_pos
	_enemy.velocity = enemy_vel
	_enemy.reset_spin()

	_max_rps = maxf(_player.stats.rps, _enemy.stats.rps)
	_running = true
	_resolved = false
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not _running:
		return

	_integrate(_player, delta)
	_integrate(_enemy, delta)
	_resolve_disc_collision()
	_resolve_walls(_player)
	_resolve_walls(_enemy)
	_apply_natural_decay(_player, delta)
	_apply_natural_decay(_enemy, delta)
	_update_bars()
	_check_finish()


func _update_bars() -> void:
	_player_bar.max_value = _max_rps
	_enemy_bar.max_value = _max_rps
	_player_bar.value = _player.rps
	_enemy_bar.value = _enemy.rps


## 位置と速度を1ステップ進める。
func _integrate(disc: Disc, delta: float) -> void:
	disc.position += disc.velocity * delta

	var accel := SpinnerPhysics.friction_accel(disc.velocity, disc.stats.friction)
	accel += SpinnerPhysics.stage_slope_accel(
		disc.position, _arena.center(), stage_strength, stage_shape
	)
	disc.velocity += accel * delta


## コマ同士がぶつかったら、弾き合いとRPSの削り合いを起こす。
func _resolve_disc_collision() -> void:
	if not SpinnerPhysics.is_colliding(
		_player.position, _player.stats.radius, _player.velocity,
		_enemy.position, _enemy.stats.radius, _enemy.velocity
	):
		return

	# 接触点から衝撃波を出す。半径で重み付けした中点＝実際に触れている場所で、
	# プロトタイプ(simulation.py:54)の collision_points と同じ式。
	_spawn_spark(
		(_player.position * _enemy.stats.radius + _enemy.position * _player.stats.radius)
		/ (_player.stats.radius + _enemy.stats.radius)
	)

	# 削り量は衝突前の速さで決める。弾性衝突で速度が変わる前に取っておく。
	var player_speed := _player.velocity.length()
	var enemy_speed := _enemy.velocity.length()

	var bounced := SpinnerPhysics.elastic_velocities(
		_player.position, _player.velocity, _player.stats.mass,
		_enemy.position, _enemy.velocity, _enemy.stats.mass
	)
	_player.velocity = bounced[0]
	_enemy.velocity = bounced[1]

	var player_drain := SpinnerPhysics.spin_drain(
		_enemy.stats.mass, enemy_speed,
		_player.stats.mass, _player.stats.radius, violence
	)
	var enemy_drain := SpinnerPhysics.spin_drain(
		_player.stats.mass, player_speed,
		_enemy.stats.mass, _enemy.stats.radius, violence
	)

	# 失った回転の分だけ弾き飛ばされる。
	_player.velocity += SpinnerPhysics.spin_kick(
		_player.position, _enemy.position, _player.stats.radius, player_drain, spin_kick_scale
	)
	_enemy.velocity += SpinnerPhysics.spin_kick(
		_enemy.position, _player.position, _enemy.stats.radius, enemy_drain, spin_kick_scale
	)

	_player.rps = maxf(_player.rps - player_drain, 0.0)
	_enemy.rps = maxf(_enemy.rps - enemy_drain, 0.0)


## 衝撃波をアリーナのユニット系に生やす。自分で消えるので後始末は要らない。
func _spawn_spark(at: Vector2) -> void:
	var spark := COLLISION_SPARK.instantiate()
	spark.position = at
	$ArenaRoot.add_child(spark)


func _resolve_walls(disc: Disc) -> void:
	for wall in _arena.walls:
		if not SpinnerPhysics.wall_hit(
			wall.point, wall.normal, disc.position, disc.velocity, disc.stats.radius
		):
			continue
		disc.velocity = SpinnerPhysics.wall_bounce(
			disc.velocity, wall.normal, disc.stats.restitution
		)
		disc.rps *= wall_damping


func _apply_natural_decay(disc: Disc, delta: float) -> void:
	disc.rps = maxf(
		disc.rps - SpinnerPhysics.natural_spin_decay(disc.stats.radius, natural_damping, delta),
		0.0
	)


## 先に回転が尽きた方が負け。両方尽きていたら引き分け扱いで敗北とする。
func _check_finish() -> void:
	if _resolved:
		return
	var player_out := _player.rps <= lose_threshold
	var enemy_out := _enemy.rps <= lose_threshold
	if not player_out and not enemy_out:
		return

	_resolved = true
	_running = false
	set_physics_process(false)

	var player_won := enemy_out and not player_out
	_player.defeated = player_out
	_enemy.defeated = enemy_out

	if player_out and enemy_out:
		_message.text = "BATTLE_DRAW"
	elif player_won:
		_message.text = "BATTLE_WIN"
	else:
		_message.text = "BATTLE_LOSE"

	await get_tree().create_timer(finish_delay).timeout
	finished.emit(player_won)
