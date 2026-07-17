class_name BattleResolver
extends RefCounted

## 1戦を最初から最後まで計算する。BattleRequestを受けてBattleResultを返すだけの
## 純粋関数で、Nodeにもシーンにも乱数にも依存しない。
##
## 今はBattle.gdがローカルで呼ぶが、この resolve() がそのままサーバー化の
## 差し替え点になる。将来はサーバーが同じコードで解決し、結果だけを返す。
##
## 元はBattle.gdの_physics_processがDiscノードを直接書き換えていた。
## シーンがないと動かず、フレームレートに縛られ、同じ戦いを二度再現できなかった。
## ここへ移したことで、ヘッドレスで即座に何百戦でも回せる。


## 計算中の1体。Discノードの代わり。
class State:
	extends RefCounted

	var stats: SpinnerStats
	var position: Vector2
	var velocity: Vector2
	var rps: float

	func _init(launch: BattleRequest.Launch) -> void:
		stats = launch.stats
		position = launch.position
		velocity = launch.velocity
		rps = launch.stats.rps


static func resolve(request: BattleRequest) -> BattleResult:
	var result := BattleResult.new()
	result.time_step = request.time_step

	var player := State.new(request.player)
	var enemy := State.new(request.enemy)
	var walls := ArenaWall.from_rect(request.arena_bounds)
	var center := request.arena_bounds.get_center()

	var dt := request.time_step
	var max_steps := int(request.max_duration / dt)
	var t := 0.0

	for step in max_steps:
		# 現在の状態を記録してから進める。1フレーム目が初期状態になる。
		result.player_frames.append(_snapshot(player))
		result.enemy_frames.append(_snapshot(enemy))

		_integrate(player, center, request, dt)
		_integrate(enemy, center, request, dt)
		_resolve_disc_collision(player, enemy, request, t, result)
		_resolve_walls(player, walls, request)
		_resolve_walls(enemy, walls, request)
		_apply_natural_decay(player, request, dt)
		_apply_natural_decay(enemy, request, dt)

		t += dt

		var player_out := player.rps <= request.lose_threshold
		var enemy_out := enemy.rps <= request.lose_threshold
		if player_out or enemy_out:
			result.player_frames.append(_snapshot(player))
			result.enemy_frames.append(_snapshot(enemy))
			result.finish_time = t
			if player_out and enemy_out:
				result.outcome = BattleResult.Outcome.DRAW
			elif enemy_out:
				result.outcome = BattleResult.Outcome.PLAYER_WIN
			else:
				result.outcome = BattleResult.Outcome.ENEMY_WIN
			return result

	# 上限に達した。自然減衰があるので普通は来ないが、調整次第では
	# ありうるので黙って無限に回さない。残っている回転で決める。
	result.finish_time = t
	result.timed_out = true
	if is_equal_approx(player.rps, enemy.rps):
		result.outcome = BattleResult.Outcome.DRAW
	elif player.rps > enemy.rps:
		result.outcome = BattleResult.Outcome.PLAYER_WIN
	else:
		result.outcome = BattleResult.Outcome.ENEMY_WIN
	return result


static func _snapshot(s: State) -> BattleResult.Snapshot:
	return BattleResult.Snapshot.new(s.position, s.velocity, s.rps)


static func _integrate(s: State, center: Vector2, req: BattleRequest, dt: float) -> void:
	s.position += s.velocity * dt
	var accel := SpinnerPhysics.friction_accel(s.velocity, s.stats.friction)
	accel += SpinnerPhysics.stage_slope_accel(
		s.position, center, req.stage_strength, req.stage_shape
	)
	s.velocity += accel * dt


static func _resolve_disc_collision(
	player: State, enemy: State, req: BattleRequest, t: float, result: BattleResult
) -> void:
	if not SpinnerPhysics.is_colliding(
		player.position, player.stats.radius, player.velocity,
		enemy.position, enemy.stats.radius, enemy.velocity
	):
		return

	# 接触点。半径で重み付けした中点＝実際に触れている場所。
	var contact := (
		player.position * enemy.stats.radius + enemy.position * player.stats.radius
	) / (player.stats.radius + enemy.stats.radius)
	result.impacts.append(BattleResult.Impact.new(t, contact))

	# 削り量は衝突前の速さで決める。弾性衝突で速度が変わる前に取っておく。
	var player_speed := player.velocity.length()
	var enemy_speed := enemy.velocity.length()

	var bounced := SpinnerPhysics.elastic_velocities(
		player.position, player.velocity, player.stats.mass,
		enemy.position, enemy.velocity, enemy.stats.mass
	)
	player.velocity = bounced[0]
	enemy.velocity = bounced[1]

	var player_drain := SpinnerPhysics.spin_drain(
		enemy.stats.mass, enemy_speed, player.stats.mass, player.stats.radius, req.violence
	)
	var enemy_drain := SpinnerPhysics.spin_drain(
		player.stats.mass, player_speed, enemy.stats.mass, enemy.stats.radius, req.violence
	)

	player.velocity += SpinnerPhysics.spin_kick(
		player.position, enemy.position, player.stats.radius, player_drain, req.spin_kick_scale
	)
	enemy.velocity += SpinnerPhysics.spin_kick(
		enemy.position, player.position, enemy.stats.radius, enemy_drain, req.spin_kick_scale
	)

	player.rps = maxf(player.rps - player_drain, 0.0)
	enemy.rps = maxf(enemy.rps - enemy_drain, 0.0)


static func _resolve_walls(s: State, walls: Array[ArenaWall], req: BattleRequest) -> void:
	for wall in walls:
		if not SpinnerPhysics.wall_hit(
			wall.point, wall.normal, s.position, s.velocity, s.stats.radius
		):
			continue
		s.velocity = SpinnerPhysics.wall_bounce(s.velocity, wall.normal, s.stats.restitution)
		s.rps *= req.wall_damping


static func _apply_natural_decay(s: State, req: BattleRequest, dt: float) -> void:
	s.rps = maxf(
		s.rps - SpinnerPhysics.natural_spin_decay(s.stats.radius, req.natural_damping, dt),
		0.0
	)
