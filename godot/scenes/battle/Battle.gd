extends Node2D

## 1戦分の進行。ここは計算せず、BattleResolverが返した結果を再生するだけ。
##
## 発射された瞬間に戦いは全部決まっている(発射は1回きりで、以後入力がない)ので、
## その場で最後まで計算してしまい、あとは時刻を進めながら軌跡をなぞる。
## 将来オンライン対戦をやるときは、この resolve() の呼び先がサーバーになる。
##
## プロトタイプ(simulation.py)もサーバーで全ステップを先に計算していた。
## あれが駄目だったのは結果をCSSキーフレームで再生していたからで、権威を
## サーバーに置く構造自体は正しかった。ここでは同じ構造をGodotの描画で再生する。
##
## 数値はすべて手触りで調整する前提。プロトタイプの値は出発点でしかない。

signal finished(player_won: bool)

const COLLISION_SPARK: PackedScene = preload("res://scenes/battle/CollisionSpark.tscn")
const DISC: PackedScene = preload("res://scenes/battle/Disc.tscn")

## 敵ディスクの色。プレイヤー(青)と対になる赤。元はBattle.tscnのEnemyDiscに
## 直接置いていたが、敵を動的に生成するようになったのでここへ移した。
const ENEMY_COLOR := Color(0.906, 0.298, 0.235)

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
## 敵が出現する円周の、中心からの距離。壁とコマの半径より内側に取ること。
@export_range(1.0, 5.0, 0.1) var enemy_spawn_radius: float = 4.0

## 敵の狙いが中心からどれだけ外れうるか(度)。0なら必ず中心へ、
## 大きいほど読みにくくなる。
@export_range(0.0, 90.0, 5.0) var enemy_spread_deg: float = 30.0

## Battle.tscn単体で走らせたときの敵の発射速度。本編ではEnemyDataから来る。
@export_range(0.5, 30.0, 0.1) var fallback_enemy_speed: float = 4.0

## Battle.tscn単体で走らせたときの敵の性能。本編ではEnemyDataから来る。
## GameState.pending_enemiesが空のときだけ使う。
@export var fallback_enemy_stats: SpinnerStats

@export_group("壁エフェクト")

## 壁に当たった時の衝撃波。コマ同士(CollisionSpark既定)より小さく・短く・薄くして
## 控えめにする。色は壁(Arena.WALL_COLOR)に寄せ、当たった感を壁と結びつける。
## 手触りで詰める前提なので値はInspectorから触れるようにしてある。

## 広がりきる半径(ユニット)。コマ同士は2.4。
@export_range(0.2, 20.0, 0.1) var wall_spark_radius: float = 0.9

## 消えるまでの秒数。コマ同士は0.45。
@export_range(0.05, 3.0, 0.05) var wall_spark_duration: float = 0.3

## 出た瞬間の色。壁色を薄くしたもの。消える時は同色のままalpha 0へ抜ける。
@export var wall_spark_color: Color = Color("d98cd9", 0.5)

@export_group("調整用")

## ドラッグを待たずに即開始する。このシーンだけをF5で走らせて挙動を見る用。
## 本編ではMainがドラッグ発射で始めるので false のままにしておくこと。
@export var auto_start: bool = false

## auto_start時のプレイヤーの初期位置と初速。
@export var auto_start_pos: Vector2 = Vector2(2, 8)
@export var auto_start_vel: Vector2 = Vector2(6, -6)

@onready var _arena: Arena = $ArenaRoot/Arena
@onready var _player: Disc = $ArenaRoot/PlayerDisc
@onready var _enemy_discs_root: Node2D = $ArenaRoot/EnemyDiscs
@onready var _enemy_telegraphs_root: Node2D = $ArenaRoot/EnemyTelegraphs
@onready var _launcher: LaunchController = $ArenaRoot/LaunchController
@onready var _message: Label = $UI/Message
@onready var _bars: VBoxContainer = $UI/Bars
@onready var _player_bar: ProgressBar = $UI/Bars/PlayerBar

var _max_rps: float = 1.0

## この戦闘の土俵。ランから来る。null ならシーンの@export値とArena.BOUNDSを使う
## （Battle.tscn単体で調整するとき用）。
var _field: FieldData = null

## この戦闘での敵たち。1体でも複数体(乱戦)でも同じ配列で扱う。
## 4つの配列は同じindexで対応する(_enemies[i]の予告が_telegraphs[i])。
var _enemies: Array[Disc] = []
var _telegraphs: Array[EnemyTelegraph] = []
var _enemy_bars: Array[ProgressBar] = []

## 各敵の出現内容。発射前に決めて予告しておく。
var _enemy_plans: Array[EnemySpawn.Plan] = []

## 再生中の結果と、その中での現在時刻。
var _result: BattleResult = null
var _playback_time: float = 0.0

## まだ出していない衝突イベントの位置。時刻が来たら順に衝撃波を出す。
var _next_impact: int = 0

## 壁への衝突も同様に、時刻が追いついた順に控えめな衝撃波を出す。
var _next_wall_impact: int = 0


func _ready() -> void:
	set_physics_process(false)
	_launcher.launched.connect(_on_launched)
	_launcher.aim_moved.connect(_on_aim_moved)
	_message.text = "BATTLE_DRAG_TO_SHOOT"
	_apply_run_state()

	# 敵の出現をここで決めてしまい、発射前から予告しておく。毎回変わるが、
	# プレイヤーは狙う前に相手の軌道を読める。
	#
	# 予告は確定値の周りで揺らして見せる(読み切らせないため)が、揺れるのは
	# 見た目だけ。撃つときは必ず_enemy_plansの確定値を使う。
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_max_rps = _player.stats.rps
	for data in _enemy_datas():
		_spawn_enemy(data, rng)
	set_process(true)

	_player.reset_spin()
	for enemy in _enemies:
		enemy.reset_spin()
	_update_bars()

	if auto_start:
		_begin(auto_start_pos, auto_start_vel)


## この戦闘に出す敵の一覧。ランの状態があればそれを、なければ(Battle.tscn単体で
## 走らせたとき)フォールバックの1体を返す。
func _enemy_datas() -> Array[EnemyData]:
	if not GameState.pending_enemies.is_empty():
		return GameState.pending_enemies
	var stats := fallback_enemy_stats if fallback_enemy_stats != null else SpinnerStats.new()
	return [EnemyData.make(1, "ENEMY_1_1", fallback_enemy_speed, stats)]


## 敵を1体ぶん生成する。ディスク・予告・HPバーを作り、出現内容を決めて予告する。
## 4つの配列(_enemies/_telegraphs/_enemy_bars/_enemy_plans)へindexを揃えて積む。
func _spawn_enemy(data: EnemyData, rng: RandomNumberGenerator) -> void:
	var disc := DISC.instantiate() as Disc
	disc.stats = data.stats
	disc.body_color = ENEMY_COLOR
	_enemy_discs_root.add_child(disc)

	var telegraph := EnemyTelegraph.new()
	_enemy_telegraphs_root.add_child(telegraph)

	# HPバーの見た目はプレイヤーバー(Battle.tscnで設定)に合わせる。背景は共有し、
	# 塗りだけ敵色で作る。動的生成なのでtscnのサブリソースは使えず、コードで組む。
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 22)
	bar.show_percentage = false
	var bg := _player_bar.get_theme_stylebox("background")
	if bg != null:
		bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ENEMY_COLOR
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	_bars.add_child(bar)

	var speed := data.launch_speed if data != null else fallback_enemy_speed
	var plan := EnemySpawn.plan(
		_center(), enemy_spawn_radius, speed, enemy_spread_deg, rng,
		disc.stats.radius, _inradius()
	)
	disc.position = plan.position
	disc.velocity = Vector2.ZERO
	telegraph.show_plan(plan.position, plan.velocity)

	_enemies.append(disc)
	_telegraphs.append(telegraph)
	_enemy_bars.append(bar)
	_enemy_plans.append(plan)
	_max_rps = maxf(_max_rps, data.stats.rps)


## 発射前は、各コマを自分の予告の三角形の頂点に合わせて漂わせる。
## 揺らすのは見た目だけなので、ここで_enemy_plansは書き換えない。
func _process(_delta: float) -> void:
	if _result != null:
		set_process(false)
		return
	for i in _enemies.size():
		_enemies[i].position = _telegraphs[i].display_position()


## ランの状態があればプレイヤーの性能と土俵に使う。Battle.tscn単体で走らせたときは
## シーンに置いてある値のままにして、単体で調整できるようにしておく。
## 敵の性能は_spawn_enemyがEnemyDataから直接ディスクへ入れる。
func _apply_run_state() -> void:
	if GameState.player_stats != null:
		_player.stats = GameState.player_stats
	_field = GameState.pending_field
	# 土俵の見た目(壁の位置・形状・障害物)を反映してから最初の描画に入る。
	_arena.setup(_field)


## 土俵の矩形。フィールドがあればそれ、なければシーン既定のArena.BOUNDS。
func _bounds() -> Rect2:
	return _field.arena_bounds if _field != null else Arena.BOUNDS


func _center() -> Vector2:
	return _bounds().get_center()


func _wall_shape() -> ArenaWall.WallShape:
	return _field.wall_shape if _field != null else ArenaWall.WallShape.RECT


func _inradius() -> float:
	if _field != null:
		return _field.inradius()
	return ArenaWall.inradius_for(ArenaWall.WallShape.RECT, Arena.BOUNDS)


## 発射地点を土俵の内側へ寄せる。矩形は矩形クランプ、非矩形は内接円クランプ。
func _clamp_launch(pos: Vector2) -> Vector2:
	if _wall_shape() == ArenaWall.WallShape.RECT:
		return ArenaWall.clamp_inside(_bounds(), pos, _player.stats.radius)
	return ArenaWall.clamp_inside_circle(_center(), _inradius(), pos, _player.stats.radius)


## 狙っている間、コマを三角形の頂点(＝発射地点)へ置く。ここから飛ぶ、が
## 見たままになる。以前はどこをクリックしても発射の瞬間にコマが飛んでいた。
func _on_aim_moved(origin: Vector2) -> void:
	if _result != null:
		return
	_player.position = _clamp_launch(origin)


func _on_launched(pos: Vector2, velocity: Vector2) -> void:
	_begin(_clamp_launch(pos), velocity)


## 発射して戦闘へ入る。auto_startもここを通す。
##
## 以前はauto_startが独自に組み立てていて hide_plan() を呼び忘れており、
## 予告の三角形が戦闘中ずっと画面に残っていた。調整用の経路とはいえ、
## 挙動を見るために使う経路が本編と違う絵を出すのは困る。
func _begin(player_pos: Vector2, player_vel: Vector2) -> void:
	_launcher.set_enabled(false)
	for telegraph in _telegraphs:
		telegraph.hide_plan()
	_message.text = ""
	start(player_pos, player_vel)


## 初期位置と初速を与えて開始する。座標はアリーナのユニット系。敵の発射内容は
## _enemy_plansの確定値を使う(予告の揺れは見た目だけなので混ぜない)。
##
## ここで戦いを最後まで計算してしまい、以降は再生するだけ。
func start(player_pos: Vector2, player_vel: Vector2) -> void:
	var request := build_request(player_pos, player_vel)
	play(BattleResolver.resolve(request))


## 今の調整値で、この発射内容のリクエストを組み立てる。
## 将来サーバーへ送るのはこれ。
func build_request(player_pos: Vector2, player_vel: Vector2) -> BattleRequest:
	var request := BattleRequest.new()
	request.player = BattleRequest.Launch.new(_player.stats, player_pos, player_vel)
	var enemies: Array[BattleRequest.Launch] = []
	for i in _enemies.size():
		enemies.append(BattleRequest.Launch.new(
			_enemies[i].stats, _enemy_plans[i].position, _enemy_plans[i].velocity
		))
	request.enemies = enemies
	# 土俵(壁の位置・形状、傾斜、障害物)はフィールドから。
	# フィールドが無い単体調整時はシーンの@export値とArena.BOUNDSを使う。
	if _field != null:
		request.arena_bounds = _field.arena_bounds
		request.wall_shape = _field.wall_shape
		request.obstacles = _field.obstacles
		request.stage_strength = _field.stage_strength
		request.stage_shape = _field.stage_shape
	else:
		request.arena_bounds = Arena.BOUNDS
		request.wall_shape = ArenaWall.WallShape.RECT
		request.stage_strength = stage_strength
		request.stage_shape = stage_shape
	request.violence = violence
	request.spin_kick_scale = spin_kick_scale
	request.natural_damping = natural_damping
	request.wall_damping = wall_damping
	request.lose_threshold = lose_threshold
	return request


## 計算済みの結果を再生する。ローカルで解いた結果でも、将来サーバーから
## 返ってきた結果でも、ここから先は同じ。
func play(result: BattleResult) -> void:
	_result = result
	_playback_time = 0.0
	_next_impact = 0
	_next_wall_impact = 0

	_player.reset_spin()
	for enemy in _enemies:
		enemy.reset_spin()
	_apply_frame(0.0)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _result == null:
		return

	_playback_time += delta
	_apply_frame(_playback_time)
	_emit_due_impacts(_playback_time)
	_emit_due_wall_impacts(_playback_time)

	if _playback_time >= _result.finish_time:
		_finish()


## 時刻に応じた状態をコマへ反映する。フレーム間はBattleResultが補間するので、
## 描画のfpsが計算の刻み幅と違っていても滑らかに動く。
func _apply_frame(t: float) -> void:
	var p := _result.sample(_result.player_frames, t)
	_player.position = p.position
	_player.velocity = p.velocity
	_player.rps = p.rps

	for i in _enemies.size():
		var e := _result.sample(_result.enemy_tracks[i], t)
		_enemies[i].position = e.position
		_enemies[i].velocity = e.velocity
		_enemies[i].rps = e.rps

	_update_bars()


## 衝突は計算中に起きているので、再生時刻が追いついたところで衝撃波を出す。
func _emit_due_impacts(t: float) -> void:
	while _next_impact < _result.impacts.size() and _result.impacts[_next_impact].time <= t:
		_spawn_spark(_result.impacts[_next_impact].point)
		_next_impact += 1


## 壁への衝突も同じ要領で、時刻が来たところで控えめな衝撃波を出す。
## コマ同士とは別のカーソルで独立に進むだけで、互いに干渉しない。
func _emit_due_wall_impacts(t: float) -> void:
	while (
		_next_wall_impact < _result.wall_impacts.size()
		and _result.wall_impacts[_next_wall_impact].time <= t
	):
		_spawn_wall_spark(_result.wall_impacts[_next_wall_impact].point)
		_next_wall_impact += 1


func _update_bars() -> void:
	_player_bar.max_value = _max_rps
	_player_bar.value = _player.rps
	for i in _enemy_bars.size():
		_enemy_bars[i].max_value = _max_rps
		_enemy_bars[i].value = _enemies[i].rps


## 衝撃波をアリーナのユニット系に生やす。自分で消えるので後始末は要らない。
func _spawn_spark(at: Vector2) -> void:
	var spark := COLLISION_SPARK.instantiate()
	spark.position = at
	$ArenaRoot.add_child(spark)


## 壁用の控えめな衝撃波。同じCollisionSparkを、小さく・短く・壁色に寄せた値で使い回す。
func _spawn_wall_spark(at: Vector2) -> void:
	var spark := COLLISION_SPARK.instantiate()
	spark.position = at
	spark.max_radius = wall_spark_radius
	spark.duration = wall_spark_duration
	spark.start_color = wall_spark_color
	# 終わりは同じ色のまま透明へ抜ける。コマ同士のような色相の変化はさせない。
	spark.end_color = Color(wall_spark_color.r, wall_spark_color.g, wall_spark_color.b, 0.0)
	$ArenaRoot.add_child(spark)


## 再生が結果の終わりまで来た。勝敗はもう決まっているので、見せるだけ。
func _finish() -> void:
	set_physics_process(false)

	# 最後のフレームをそのまま残す。補間の途中で止まると中途半端な絵になる。
	_apply_frame(_result.finish_time)

	var player_won := _result.player_won()
	_player.defeated = not player_won
	# 敵は最終フレームの回転で個別に判定する。負け戦でも生き残った敵は
	# 光ったまま残り、乱戦で誰が倒れたかが絵で分かる。
	for enemy in _enemies:
		enemy.defeated = enemy.rps <= lose_threshold

	match _result.outcome:
		BattleResult.Outcome.DRAW:
			_message.text = "BATTLE_DRAW"
			# 引き分けは全員力尽きている。
			_player.defeated = true
			for enemy in _enemies:
				enemy.defeated = true
		BattleResult.Outcome.PLAYER_WIN:
			_message.text = "BATTLE_WIN"
		_:
			_message.text = "BATTLE_LOSE"

	await get_tree().create_timer(finish_delay).timeout
	finished.emit(player_won)
