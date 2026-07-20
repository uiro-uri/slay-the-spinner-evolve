extends SceneTree

## 事前知識ゼロの初見プレイを1手ずつ回すための対話ドライバ(テストプレイ専用・使い捨て)。
##
## 使い方(状態はJSONファイルに永続化する):
##   new    --seed=N --state=path            ラン開始。マップと開始位置を出す
##   status --state=path                      現在のステータス/所持パーツ/残機/進める先
##   enter  --state=path --col=C --bseed=B    次ノードへ入り、敵の予告(テレグラフ)を出す
##   launch --state=path --bseed=B --from-deg=D --target=center|enemyK|x,y --force=F
##                                            自分の発射を決めて1戦解決。勝敗を出す
##   reward --state=path --bseed=B            勝利後、報酬3枚の効果を出す
##                                            (最初の1回で確定。以後bseedを変えても同じ3枚)
##   pick   --state=path --id=ID              報酬を1枚取る。乱戦は倒した頭数ぶん
##                                            reward→pickを繰り返す(実ゲームと同じ)
##                                            (直前のrewardで提示された札しか取れない)
##   retry  --state=path --bseed=B            残機を1消費して同ノードを再抽選(新しい予告)
##   giveup --state=path                      あきらめてラン終了
##
## 予告(enter/retry)と解決(launch)は同じ --bseed を渡すこと(敵の出現が一致する)。

const MAX_SPEED := 20.0
const SPAWN_RING := 4.0
const SPAWN_SPREAD_DEG := 30.0


func _init() -> void:
	var a := _args()
	var cmd: String = a.get("cmd", "")
	var path: String = a.get("state", "")
	match cmd:
		"new": _new(int(a.get("seed", "0")), path)
		"status": _status(_load(path), path)
		"enter": _enter(_load(path), path, int(a["col"]), int(a["bseed"]))
		"launch": _launch(_load(path), path, int(a["bseed"]), float(a.get("from-deg","0")), a.get("target","enemy1"), float(a.get("force","1.0")))
		"reward": _reward(_load(path), path, int(a["bseed"]))
		"pick": _pick(_load(path), path, int(a["id"]))
		"retry": _retry(_load(path), path, int(a["bseed"]))
		"giveup": _giveup(_load(path), path)
		_: printerr("unknown cmd: ", cmd)
	quit(0)


# ---- 状態の入出力 ----

func _default_state(seed_value: int) -> Dictionary:
	var s := SpinnerStats.default_player()
	return {
		"seed": seed_value,
		"path": [],            # 突破済みノードの列 [[step,col],...]
		"pending": null,       # 交戦中ノードの col (未突破)
		"stats": stats_dict(s),
		"parts": [],
		"offered": null,       # 直前のrewardで提示した札id列 (pickの検証と再抽選防止)
		"rewards_left": null,  # この勝利で残っている報酬選択回数 (乱戦=頭数ぶん)
		"continues": 3,
		"cleared": false,
		"dead": false,
	}

## ステータスの保存/復元は全フィールドを往復させる。以前は spin_decay(MOMENTUM札)と
## wall_keep(RAGE札)が抜けており、札を取っても次のコマンドで主効果が消えていた
## (摩擦・反発は残るので気づきにくい)。旧stateのキー欠落は既定値で読む。
static func stats_dict(s: SpinnerStats) -> Dictionary:
	return {"mass": s.mass, "radius": s.radius, "friction": s.friction,
		"restitution": s.restitution, "rps": s.rps,
		"spin_decay": s.spin_decay, "wall_keep": s.wall_keep, "hit_guard": s.hit_guard}

static func stats_from(d: Dictionary) -> SpinnerStats:
	var s := SpinnerStats.new()
	s.mass = d["mass"]; s.radius = d["radius"]; s.friction = d["friction"]; s.restitution = d["restitution"]; s.rps = d["rps"]
	s.spin_decay = d.get("spin_decay", 1.0)
	s.wall_keep = d.get("wall_keep", 0.0)
	s.hit_guard = d.get("hit_guard", 0.0)
	return s

func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())

func _save(state: Dictionary, path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(state, "  "))
	f.close()

## seedからツリーを作り、突破済みpathに沿って現在ノードまで進める。
func _tree_at(state: Dictionary) -> MapTree:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(state["seed"])
	var tree := MapTree.generate(rng)
	for step_col in state["path"]:
		tree.advance_to(Vector2i(int(step_col[0]), int(step_col[1])))
	return tree


# ---- コマンド ----

func _new(seed_value: int, path: String) -> void:
	var state := _default_state(seed_value)
	_save(state, path)
	var tree := _tree_at(state)
	print("=== NEW RUN seed=%d 残機=%d ===" % [seed_value, state["continues"]])
	_print_tree(tree)
	_print_reachable(tree)

func _status(state: Dictionary, path: String) -> void:
	var tree := _tree_at(state)
	print("=== STATUS ===")
	print("残機=%d  クリア=%s  死亡=%s" % [state["continues"], state["cleared"], state["dead"]])
	_print_stats(state)
	_print_parts(state)
	print("現在段=%d 交戦中col=%s" % [tree.current_step(), str(state["pending"])])
	_print_tree(tree)
	_print_reachable(tree)

func _enter(state: Dictionary, path: String, col: int, bseed: int) -> void:
	var tree := _tree_at(state)
	var target := Vector2i(tree.current_step() + 1, col)
	if not target in tree.next_coords():
		printerr("そのノードへは進めない: ", target, " 進める先=", tree.next_coords()); return
	state["pending"] = col
	state["offered"] = null    # 古い提示札で新ノードをpickできないように
	state["rewards_left"] = null
	_save(state, path)
	# pathには勝ってから足す。ここでは表示のためadvanceした木を使う
	tree.advance_to(target)
	_reveal(state, tree, bseed)

func _retry(state: Dictionary, path: String, bseed: int) -> void:
	if int(state["continues"]) <= 0:
		print("残機なし。giveupへ。"); return
	state["continues"] = int(state["continues"]) - 1
	state["offered"] = null
	_save(state, path)
	var tree := _tree_at(state)
	tree.advance_to(Vector2i(tree.current_step() + 1, int(state["pending"])))
	print("=== RETRY 残機を1消費 (残り%d) 敵を再抽選 ===" % state["continues"])
	_reveal(state, tree, bseed)

## 交戦中ノードの敵予告と土俵を出す。プレイヤーが撃つ前に見える情報。
func _reveal(state: Dictionary, tree: MapTree, bseed: int) -> void:
	var node: MapTree.MapNode = tree.nodes[tree.current_coord]
	var field: FieldData = node.field
	print("=== BATTLE 段%d %s ===" % [tree.current_step(), field.title_key])
	print("土俵: 形状=%s 中心=%s 内接半径=%.2f 範囲=%s" % [
		_wall_name(field.wall_shape), str(field.center()), field.inradius(), str(field.arena_bounds)])
	print("自分: mass=%.2f radius=%.2f rps=%.1f friction=%.3f rest=%.2f spin_decay=%.2f wall_keep=%.2f hit_guard=%.2f  発射リング半径=%.2f" % [
		state["stats"]["mass"], state["stats"]["radius"], state["stats"]["rps"],
		state["stats"]["friction"], state["stats"]["restitution"],
		float(state["stats"].get("spin_decay", 1.0)), float(state["stats"].get("wall_keep", 0.0)),
		float(state["stats"].get("hit_guard", 0.0)),
		field.inradius() - float(state["stats"]["radius"]) - 0.5])
	print("ゴースト無敵: %.1fs" % CustomPartCatalog.total_ghost_seconds(_ids(state)))
	var plans := _enemy_plans(node.enemies, field, bseed)
	print("敵 %d体 (bseed=%d):" % [node.enemies.size(), bseed])
	for i in node.enemies.size():
		var e: EnemyData = node.enemies[i]
		var pl: EnemySpawn.Plan = plans[i]
		var dir := pl.velocity.normalized()
		print("  enemy%d Lv%d '%s': 出現=%s 速度=%.1f 向き=%.0f° radius=%.2f rps=%.1f" % [
			i + 1, e.level, e.display_name, str(pl.position), pl.velocity.length(),
			rad_to_deg(dir.angle()), e.stats.radius, e.stats.rps])
	print("→ launch --bseed=%d --from-deg=<0-360> --target=center|enemy1..|x,y --force=<0-1>" % bseed)

func _launch(state: Dictionary, path: String, bseed: int, from_deg: float, target: String, force: float) -> void:
	var tree := _tree_at(state)
	tree.advance_to(Vector2i(tree.current_step() + 1, int(state["pending"])))
	var node: MapTree.MapNode = tree.nodes[tree.current_coord]
	var field: FieldData = node.field
	var plans := _enemy_plans(node.enemies, field, bseed)
	var pstats := stats_from(state["stats"])

	var pos := _ring_pos(field, pstats.radius, from_deg)
	var tgt := _target_point(field, plans, target)
	var vel := (tgt - pos).normalized() * clampf(force, 0.0, 1.0) * MAX_SPEED

	var req := BattleRequest.new()
	req.arena_bounds = field.arena_bounds
	req.wall_shape = field.wall_shape
	req.obstacles = field.obstacles
	req.stage_strength = field.stage_strength
	req.stage_shape = field.stage_shape
	req.ghost_duration = CustomPartCatalog.total_ghost_seconds(_ids(state))
	req.player = BattleRequest.Launch.new(pstats, pos, vel)
	var elaunch: Array[BattleRequest.Launch] = []
	for i in node.enemies.size():
		elaunch.append(BattleRequest.Launch.new(node.enemies[i].stats, plans[i].position, plans[i].velocity))
	req.enemies = elaunch

	var result := BattleResolver.resolve(req)
	var metrics := BattleMetrics.classify(req, result)
	var won := result.player_won()
	print("=== 発射: pos=%s vel=%.1f@%.0f° target=%s force=%.2f ===" % [
		str(pos), vel.length(), rad_to_deg(vel.angle()), target, force])
	print("結果: %s  決着=%.2fs 衝突=%d timed_out=%s" % [
		result_label(result.outcome), result.finish_time, result.impacts.size(), result.timed_out])
	# 死因(BattleMetrics)は最終rpsが最小の敗者の推定。決着死因はリゾルバが記録した
	# 「最後に力尽きた体」の事実で、乱戦では別の敵になりうる(撃破ボーナスは後者で決まる)。
	print("  死因=%s loser=%s hits_taken=%s 決着死因=%s" % [
		metrics.get("death_cause","?"), metrics.get("loser","?"), str(metrics.get("hits_taken","?")),
		result.loser_death_cause])
	if won:
		if tree.is_goal():
			# 実ゲーム(Main._on_battle_finished)はボス撃破で即クリアし報酬はない。
			# 以前はボス後にも報酬pickを要求しており、実ゲームに存在しない1枚が増えていた。
			state["path"].append([tree.current_step(), int(state["pending"])])
			state["pending"] = null
			state["offered"] = null
			state["rewards_left"] = null
			state["cleared"] = true
			_save(state, path)
			print("！！！全段突破・ラン完了！！！")
		else:
			# 実ゲーム(Main._on_battle_finished)と同じく、勝利のたびに回転が少し成長する。
			# 接触で仕留めた勝ち(knockout)は撃破ボーナスで大きく育つ。
			# 報酬(倍率札)より先に適用して保存する。
			var knockout := result.finished_by_knockout()
			var grown := stats_from(state["stats"])
			grown.grow_rps_by_victory(knockout)
			state["stats"] = stats_dict(grown)
			_save(state, path)
			if knockout:
				print("★撃破ボーナス★ 接触で仕留めた勝利で回転が大きく成長 rps=%.1f (+%.1f, 上限%.0f)" % [
					grown.rps, SpinnerStats.KNOCKOUT_RPS_GROWTH, SpinnerStats.RPS_CAP])
			else:
				print("勝利の勢いで回転が成長 rps=%.1f (+%.1f, 上限%.0f)" % [
					grown.rps, SpinnerStats.VICTORY_RPS_GROWTH, SpinnerStats.RPS_CAP])
			print("→ reward --bseed=<R> で報酬を見る")
	else:
		print("→ retry --bseed=<新B> (残機%d) か giveup" % state["continues"])

func _reward(state: Dictionary, path: String, bseed: int) -> void:
	var tree := _tree_at(state)
	tree.advance_to(Vector2i(tree.current_step() + 1, int(state["pending"])))
	var node: MapTree.MapNode = tree.nodes[tree.current_coord]
	var level := EnemyRoster.level_for_step(tree.current_step())
	# 乱戦は倒した頭数ぶん報酬を選べる(Main._on_battle_finishedの_rewards_remainingと同じ)。
	# 以前は頭数によらず1枚で、実ゲームよりビルドが痩せていた。
	if state.get("rewards_left") == null:
		state["rewards_left"] = rewards_for_group(node.enemies.size())
	var left := int(state["rewards_left"])
	var choices: Array[CustomPart] = []
	if state.get("offered") != null:
		# 提示済み: bseedを変えて引き直せないよう、保存した札をそのまま再掲する。
		for v in state["offered"]:
			choices.append(CustomPartCatalog.by_id(int(v)))
		print("=== REWARD 段%d(Lv%d)撃破 3枚から1枚 (残り%d回, 提示済み・再掲) ===" % [tree.current_step(), level, left])
	else:
		var rng := RandomNumberGenerator.new(); rng.seed = bseed
		choices = CustomPartCatalog.pick_choices(CustomPartCatalog.REWARD_CHOICES, rng, level)
		var ids := []
		for c in choices: ids.append(c.id)
		state["offered"] = ids
		_save(state, path)
		print("=== REWARD 段%d(Lv%d)撃破 3枚から1枚 (残り%d回, bseed=%d) ===" % [tree.current_step(), level, left, bseed])
	for c in choices:
		print("  id=%d '%s' [%s] %s" % [c.id, c.title_key, _rarity(c.rarity), card_text(c)])
	print("→ pick --id=<ID>")

func _pick(state: Dictionary, path: String, id: int) -> void:
	var offered = state.get("offered")
	if offered == null:
		printerr("先に reward で提示を見ること"); return
	if not pick_allowed(offered, id):
		var ids := []
		for v in offered: ids.append(int(v))
		printerr("id=%d は提示されていない。提示中: %s" % [id, str(ids)]); return
	var tree := _tree_at(state)
	var col := int(state["pending"])
	tree.advance_to(Vector2i(tree.current_step() + 1, col))
	var part := CustomPartCatalog.by_id(id)
	if part == null: printerr("不明なパーツid ", id); return
	var stats := stats_from(state["stats"])
	part.apply_to(stats)
	state["stats"] = stats_dict(stats)
	state["continues"] = maxi(int(state["continues"]), part.lives)
	state["parts"].append(id)
	state["offered"] = null
	# 乱戦は倒した頭数ぶん報酬を選べる。まだ残っていれば次のrewardへ(ノードは未確定のまま)。
	var left: int = (int(state["rewards_left"]) if state.get("rewards_left") != null else 1) - 1
	if left > 0:
		state["rewards_left"] = left
		_save(state, path)
		print("取得: id=%d '%s' → %s" % [id, part.title_key, card_text(part)])
		_print_stats(state)
		print("乱戦の報酬があと%d回 → reward --bseed=<新R>" % left)
		return
	state["rewards_left"] = null
	# ノード突破を確定
	state["path"].append([tree.current_step(), col])
	state["pending"] = null
	if tree.is_goal():
		state["cleared"] = true
	_save(state, path)
	print("取得: id=%d '%s' → %s" % [id, part.title_key, card_text(part)])
	_print_stats(state)
	if state["cleared"]:
		print("！！！全段突破・ラン完了！！！")
	else:
		var t2 := _tree_at(state)
		_print_reachable(t2)

func _giveup(state: Dictionary, path: String) -> void:
	state["dead"] = true
	_save(state, path)
	# current_step()は突破済みの段。交戦中に散った場合はその次の段で終わっている。
	var step := _tree_at(state).current_step()
	var where := "段%d(交戦中)" % (step + 1) if state.get("pending") != null else "段%d" % step
	print("=== GIVE UP %s で終了 取得%d枚 残機%d ===" % [
		where, state["parts"].size(), state["continues"]])


# ---- 計算ヘルパ ----

func _enemy_plans(enemies: Array, field: FieldData, bseed: int) -> Array:
	var rng := RandomNumberGenerator.new(); rng.seed = bseed
	var plans := []
	for e in enemies:
		plans.append(EnemySpawn.plan(field.center(), SPAWN_RING, LaunchSpeed.random(rng), SPAWN_SPREAD_DEG, rng, e.stats.radius, field.inradius()))
	return plans

func _ring_pos(field: FieldData, prad: float, from_deg: float) -> Vector2:
	var ring := field.inradius() - prad - 0.5
	var p := field.center() + Vector2.RIGHT.rotated(deg_to_rad(from_deg)) * ring
	if field.wall_shape == ArenaWall.WallShape.RECT:
		return ArenaWall.clamp_inside(field.arena_bounds, p, prad)
	return ArenaWall.clamp_inside_circle(field.center(), field.inradius(), p, prad)

func _target_point(field: FieldData, plans: Array, target: String) -> Vector2:
	if target == "center":
		return field.center()
	if target.begins_with("enemy"):
		var idx := int(target.substr(5)) - 1
		return plans[clampi(idx, 0, plans.size() - 1)].position
	var parts := target.split(",")
	if parts.size() == 2:
		return Vector2(float(parts[0]), float(parts[1]))
	return field.center()

func _ids(state: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for v in state["parts"]: out.append(int(v))
	return out


# ---- 表示ヘルパ ----

func _print_stats(state: Dictionary) -> void:
	var s = state["stats"]
	var decay := float(s.get("spin_decay", 1.0))
	var keep := float(s.get("wall_keep", 0.0))
	var guard := float(s.get("hit_guard", 0.0))
	# 自然減衰は radius×spin_decay に比例する(BattleResolverのnatural_spin_decay)ので、
	# 寿命目安もspin_decayを織り込む。MOMENTUM札の効果がここに見える。
	print("ステータス: mass=%.2f radius=%.2f friction=%.3f rest=%.2f rps=%.1f spin_decay=%.2f wall_keep=%.2f hit_guard=%.2f  (寿命目安rps/(radius*spin_decay)=%.1f 硬さmass*r^2=%.2f)" % [
		s["mass"], s["radius"], s["friction"], s["restitution"], s["rps"], decay, keep, guard,
		float(s["rps"]) / (float(s["radius"]) * decay), float(s["mass"]) * float(s["radius"]) * float(s["radius"])])

func _print_parts(state: Dictionary) -> void:
	if state["parts"].is_empty(): print("所持パーツ: なし"); return
	var names := []
	for id in state["parts"]:
		var p := CustomPartCatalog.by_id(int(id))
		names.append("%s" % (p.title_key if p else str(id)))
	print("所持パーツ: ", ", ".join(names))

func _print_tree(tree: MapTree) -> void:
	print("--- MAP (段:col=Lv[体数,土俵])  ゴールは段9のボス ---")
	for step in range(1, 10):
		var row := []
		for col in range(-4, 6):
			var c := Vector2i(step, col)
			if tree.nodes.has(c):
				var n: MapTree.MapNode = tree.nodes[c]
				row.append("col%+d=Lv%d[%d体,%s]" % [col, n.level(), n.enemy_count(), n.field.title_key.replace("FIELD_","")])
		if not row.is_empty():
			print("  段%d: %s" % [step, "  ".join(row)])

func _print_reachable(tree: MapTree) -> void:
	print("進める先(段%d→):" % (tree.current_step() + 1))
	for c in tree.next_coords():
		var n: MapTree.MapNode = tree.nodes[c]
		print("  col%+d : Lv%d %d体 %s" % [c.y, n.level(), n.enemy_count(), n.field.title_key])

## カードの効果を実効果と一致する日本語で出す(CustomPart.describe()のCLI版)。
## 以前はRAGE/MOMENTUMもSTAT_MULTIPLY用の分岐に落ち、statの既定値MASSを読んで
## 「質量 ×1.10」と嘘を表示していた(実際は反発と壁rps保持の複合)。
## コールドプレイは効果テキストだけで報酬を選ぶので、ここが嘘だと工程が腐る。
static func card_text(c: CustomPart) -> String:
	match c.effect:
		CustomPart.Effect.SET_LIVES:
			return "残機を%dにする" % c.lives
		CustomPart.Effect.GHOST:
			return "開始%.0f秒間 敵をすり抜ける" % c.ghost_seconds
		CustomPart.Effect.MOMENTUM:
			return "摩擦と回転減衰 ×%.2f(回転減衰の下限%.2f) [MOMENTUM]" % [c.multiplier, c.cap]
		CustomPart.Effect.RAGE:
			return "反発 ×%.2f(上限%.2f)・壁でのrps喪失を軽減+%.2f(上限%.2f) [RAGE]" % [
				c.multiplier, c.cap, c.wall_keep_step, c.wall_keep_max]
		CustomPart.Effect.GUARD:
			return "衝突で削られる回転を軽減+%.2f(上限%.2f) [GUARD]" % [
				c.hit_guard_step, c.hit_guard_max]
		CustomPart.Effect.GROWTH:
			# 代償(自然減衰の悪化)も必ず書く。直径だけの旧版はCLIに代償が出ず、
			# 効果文だけで選ぶコールドプレイの罠になっていた(実UIの注記はCLIに
			# 出ないので、ここに書かないと嘘のままになる)。
			return "直径 ×%.2f(上限%.2f)・質量 ×%.2f(上限%.2f)・代わりに自然減衰が速まる [GROWTH]" % [
				c.multiplier, c.cap, c.mass_multiplier, c.mass_cap]
		_:
			var stat_name: String = ["質量","直径","摩擦","反発","回転"][c.stat]
			var cap_txt := "" if c.cap <= 0.0 else "(上限%.2f)" % c.cap
			var dir := "UP" if c.multiplier > 1.0 else "DOWN"
			var key: String = ["MASS","RADIUS","FRICTION","RESTITUTION","RPS"][c.stat]
			return "%s ×%.2f%s [%s_%s]" % [stat_name, c.multiplier, cap_txt, key, dir]


## 勝利1回で選べる報酬回数。乱戦は倒した頭数ぶん
## (Main._on_battle_finishedの `maxi(pending_enemies.size(), 1)` と同じ式)。
static func rewards_for_group(group_size: int) -> int:
	return maxi(group_size, 1)


## pickが取れるのは直前のrewardで提示された札だけ。JSON経由でidがfloatに
## なっていても数値で照合する。
static func pick_allowed(offered: Array, id: int) -> bool:
	for v in offered:
		if int(v) == id:
			return true
	return false


## 勝敗表示。引き分け(相打ち・時間切れ)は進行上は敗北扱いだが、
## 「敗北」とだけ出すと死因不明の負けに見えるため区別して出す。
static func result_label(outcome: int) -> String:
	match outcome:
		BattleResult.Outcome.PLAYER_WIN:
			return "★勝利★"
		BattleResult.Outcome.DRAW:
			return "引き分け(敗北扱い)"
		_:
			return "敗北"

func _rarity(r: int) -> String:
	return "RARE" if r == CustomPart.Rarity.RARE else "COMMON"

func _wall_name(w: int) -> String:
	var names := ["RECT","CIRCLE","OCT"]
	return names[w] if w >= 0 and w < names.size() else str(w)

func _args() -> Dictionary:
	var out := {"cmd": ""}
	var argv := OS.get_cmdline_user_args()
	if argv.size() > 0 and not argv[0].begins_with("--"):
		out["cmd"] = argv[0]
	for arg in argv:
		if arg.begins_with("--") and arg.contains("="):
			var eq := arg.find("=")
			out[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	return out
