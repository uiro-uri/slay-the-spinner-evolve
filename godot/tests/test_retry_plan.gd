extends RefCounted

## 敗北後の再挑戦の2択(RetryPlan)を検査する。
##
## 守りたい約束は1つ:「同じ相手に挑む」を選んだら、**立ち合いが1ドットも変わらない**。
## 相手の個体も出現(位置・向き・速度・乱戦の回り込み)も据え置かれるから、
## 結果の差は自分が狙いを変えたぶんだけになる——負けが学びになる、の実体がこれ。
## 逆に「相手を替えて挑む」は個体も出現も必ず変わる(替えたと名乗って何も変わらない、
## という嘘をつかない)。
##
## Battle.gd/Main.gd/GameOver.gd はautoload(GameState)やシーンツリーに依存していて
## ヘッドレスの--scriptモードではnew()できないので、配線はソーステキストで照合する
## (test_battle_defaults.gd と同じ手口。書式が変わったら抽出失敗がそのままFAILになる)。

const BATTLE_SRC := "res://scenes/battle/Battle.gd"
const MAIN_SRC := "res://scenes/main/Main.gd"
const GAMEOVER_SRC := "res://scenes/gameover/GameOver.gd"
const GAMEOVER_SCENE := "res://scenes/gameover/GameOver.tscn"
const GAMESTATE_SRC := "res://autoloads/GameState.gd"

## 出現の再現性を見るときの土俵。値そのものに意味は無い(同じ値を2回使うだけ)。
const CENTER := Vector2(5.0, 5.0)
const RING := 3.5
const INRADIUS := 5.0
const SPREAD_DEG := 25.0


func run(check: Callable) -> void:
	_test_same_opponent_keeps_everything(check)
	_test_new_opponent_changes_everything(check)
	_test_seed_reroll_never_repeats(check)
	_test_seed_determines_the_telegraph(check)
	_test_wiring(check)


static func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


## コメント行を落としたソース。「その呼び出しを使っていないこと」を見るとき、
## 使わない理由を書いたコメントが自分でヒットしてしまうのを避ける。
static func _code(path: String) -> String:
	var out := ""
	for line in _read(path).split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out += line + "\n"
	return out


static func _names(group: Array[EnemyData]) -> Array[String]:
	var out: Array[String] = []
	for enemy in group:
		out.append(enemy.display_name)
	return out


## 段3あたりの乱戦(2体)を借りてくる。個体の中身は問わないので先頭2枚でよい。
static func _sample_group() -> Array[EnemyData]:
	var pool := EnemyRoster.of_level(2)
	var out: Array[EnemyData] = []
	out.append(pool[0])
	out.append(pool[1 % pool.size()])
	return out


## Battle._ready()の出現手順を最小限で写したもの。同じ種から同じ予告が出ることを
## 見るためだけに使う(実UIの値ではなく、2回とも同じ値を渡すことが要点)。
static func _plans_for_seed(seed_value: int, datas: Array[EnemyData]) -> Array[Vector4]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var swirl := EnemySpawn.group_swirl_deg(
		datas.size(), EnemySpawn.DEFAULT_SWIRL_DEG, rng)
	var group := EnemySpawn.Group.new()
	var out: Array[Vector4] = []
	for data in datas:
		var radius: float = data.stats.radius
		var speed := LaunchSpeed.random(rng, radius)
		var plan := EnemySpawn.plan(
			CENTER, RING, speed, SPREAD_DEG, rng, radius, INRADIUS,
			group.avoid(), group.min_gap(radius), [], swirl)
		group.add(plan.position, radius)
		# 位置と速度をまとめて1点にする(比較しやすくするためだけの入れ物)。
		out.append(Vector4(plan.position.x, plan.position.y, plan.velocity.x, plan.velocity.y))
	return out


func _test_same_opponent_keeps_everything(check: Callable) -> void:
	var group := _sample_group()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var kept := RetryPlan.next_enemies(group, true, rng)
	check.call(
		_names(kept) == _names(group),
		"同じ相手に挑む: 個体が据え置かれる(名前が一致)"
	)
	var stats_kept := true
	for i in group.size():
		if not is_equal_approx(kept[i].stats.mass, group[i].stats.mass):
			stats_kept = false
		if not is_equal_approx(kept[i].stats.rps, group[i].stats.rps):
			stats_kept = false
	check.call(stats_kept, "同じ相手に挑む: 質量も回転も据え置かれる(乱戦の倍率が掛け直らない)")

	var seed_value := 987654
	check.call(
		RetryPlan.next_spawn_seed(seed_value, true, rng) == seed_value,
		"同じ相手に挑む: 出現の種が据え置かれる"
	)
	# 据え置きは乱数を1つも消費しない。消費すると「据え置きを選んだかどうか」で
	# この後の抽選がずれ、据え置きが据え置きでなくなる。
	var probe_a := RandomNumberGenerator.new()
	probe_a.seed = 42
	var probe_b := RandomNumberGenerator.new()
	probe_b.seed = 42
	RetryPlan.next_spawn_seed(seed_value, true, probe_a)
	RetryPlan.next_enemies(group, true, probe_a)
	check.call(
		probe_a.randi() == probe_b.randi(),
		"同じ相手に挑む: 乱数を1つも消費しない"
	)


func _test_new_opponent_changes_everything(check: Callable) -> void:
	var group := _sample_group()
	var rng := RandomNumberGenerator.new()
	rng.seed = 24680
	var swapped := RetryPlan.next_enemies(group, false, rng)
	var all_changed := swapped.size() == group.size()
	var level_kept := true
	for i in group.size():
		if swapped[i].display_name == group[i].display_name:
			all_changed = false
		if swapped[i].level != group[i].level:
			level_kept = false
	check.call(all_changed, "相手を替えて挑む: どの枠も必ず別個体になる")
	check.call(level_kept, "相手を替えて挑む: レベルは保たれる(マップ表示と報酬が嘘にならない)")

	# 種は引き直され、しかも呼ぶたびに散る(同じ値を返し続けたら替えたことにならない)。
	var seeds := {}
	for i in 32:
		seeds[RetryPlan.next_spawn_seed(555, false, rng)] = true
	check.call(seeds.size() > 1, "相手を替えて挑む: 出現の種が引き直される(32回で複数の値)")
	check.call(not seeds.has(555), "相手を替えて挑む: 元の種は返らない")


## 引き直したのに同じ種を引いてしまう場合。乱数の順番を先読みして、
## 1発目がちょうど元の種と同じになる状況を作って踏ませる。
func _test_seed_reroll_never_repeats(check: Callable) -> void:
	var peek := RandomNumberGenerator.new()
	peek.seed = 777
	var collides: int = peek.randi()

	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var got := RetryPlan.next_spawn_seed(collides, false, rng)
	check.call(
		got != collides,
		"相手を替えて挑む: 1発目が元の種と同値でも引き直す(got=%d)" % got
	)


## 種が予告を決めきっていること。同じ種なら位置も速度も完全一致し、
## 別の種なら変わる——これが「同じ相手に挑む＝同じ立ち合い」の土台。
func _test_seed_determines_the_telegraph(check: Callable) -> void:
	var datas := _sample_group()
	var a := _plans_for_seed(31415, datas)
	var b := _plans_for_seed(31415, datas)
	var c := _plans_for_seed(31416, datas)

	var same := a.size() == b.size() and a.size() > 0
	for i in a.size():
		if a[i] != b[i]:
			same = false
	check.call(same, "同じ種なら出現(位置・速度)が完全に一致する")

	var differs := false
	for i in mini(a.size(), c.size()):
		if a[i] != c[i]:
			differs = true
	check.call(differs, "別の種なら出現が変わる(据え置きが効いていることの対照)")


## 2択が実際に配線されているか。ここが外れると規則だけ正しくて game には出ない。
func _test_wiring(check: Callable) -> void:
	var battle := _code(BATTLE_SRC)
	check.call(
		battle.contains("rng.seed = GameState.pending_spawn_seed"),
		"Battle: 出現の乱数をGameStateの種から起こす"
	)
	check.call(
		not battle.contains("rng.randomize()"),
		"Battle: randomize()を使わない(使うと据え置いた種が無視されて再戦にならない)"
	)

	var main := _code(MAIN_SRC)
	check.call(
		main.contains("func _on_continue_requested(same_opponent: bool)"),
		"Main: コンティニューが2択を受け取る"
	)
	check.call(
		main.contains("RetryPlan.next_enemies(") and main.contains("RetryPlan.next_spawn_seed("),
		"Main: 相手も種もRetryPlanの規則を通す"
	)
	check.call(
		not main.contains("EnemyRoster.reroll_group("),
		"Main: 入れ替えを直接呼ばない(規則はRetryPlanに1つだけ)"
	)
	check.call(
		main.contains("GameState.roll_spawn_seed()"),
		"Main: マップでノードを選ぶたびに出現を引き直す"
	)

	var gameover := _code(GAMEOVER_SRC)
	check.call(
		gameover.contains("continue_requested.emit(true)")
		and gameover.contains("continue_requested.emit(false)"),
		"GameOver: 据え置きと入れ替えの両方を通知できる"
	)
	check.call(
		_read(GAMEOVER_SCENE).contains("RematchButton"),
		"GameOver.tscn: 「同じ相手にもう一度」のボタンが居る"
	)

	var game_state := _read(GAMESTATE_SRC)
	check.call(
		game_state.contains("var pending_spawn_seed"),
		"GameState: 出現の種を持つ(戦闘をまたいで据え置ける)"
	)

	# コールドプレイCLIも同じ規則を通る(CLIと実ゲームを別のゲームにしない)。
	var cli := _code("res://playtest/naive_play.gd")
	check.call(
		cli.contains("RetryPlan.next_enemies("),
		"naive_play: retryが実UIと同じ規則を通る"
	)
	check.call(
		not cli.contains("EnemyRoster.reroll_group("),
		"naive_play: 入れ替えを直接呼ばない"
	)
