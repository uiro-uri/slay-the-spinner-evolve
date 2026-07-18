extends RefCounted

## map_tree.gd のテスト。
##
## ランダム生成なので特定の形を期待できない。代わりに「何度生成しても
## 必ず成り立つべき不変条件」を多数回まわして確かめる。シードを渡せる
## ようにしてあるので、失敗したら同じマップを再現できる。

## 不変条件を確かめる回数。生成は速いので多めに回す。
const TRIALS := 200


func run(check: Callable) -> void:
	_test_invariants(check)
	_test_deterministic_with_seed(check)
	_test_navigation(check)
	_test_encounters(check)
	_test_encounters_deterministic(check)


func _test_invariants(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	var failures: Array[String] = []

	for trial in TRIALS:
		rng.seed = trial
		var tree := MapTree.generate(rng)
		if tree == null:
			failures.append("seed=%d: 生成に失敗" % trial)
			continue
		var problem := _find_problem(tree)
		if problem != "":
			failures.append("seed=%d: %s" % [trial, problem])

	check.call(
		failures.is_empty(),
		"マップ生成: %d回すべて不変条件を満たす%s" % [
			TRIALS,
			"" if failures.is_empty() else " / 例: " + failures[0]
		]
	)


## 壊れている点を1つ返す。問題なければ空文字。
func _find_problem(tree: MapTree) -> String:
	# スタートとゴールが定位置にあること
	if not tree.nodes.has(MapTree.START_COORD):
		return "スタートがない"
	if not tree.nodes.has(MapTree.GOAL_COORD):
		return "ゴールがない"

	# ゴール手前は必ず3ノード
	var penultimate := 0
	for coord in tree.nodes:
		if coord.x == 8:
			penultimate += 1
	if penultimate != 3:
		return "段8のノードが%d個(3個であるべき)" % penultimate

	# 段1も必ず3ノード
	var first := 0
	for coord in tree.nodes:
		if coord.x == 1:
			first += 1
	if first != 3:
		return "段1のノードが%d個(3個であるべき)" % first

	for coord in tree.nodes:
		var node: MapTree.MapNode = tree.nodes[coord]

		# 列は範囲内
		if coord.y < 0 or coord.y >= MapTree.COLUMN_COUNT:
			return "列が範囲外: %s" % coord

		# ゴール以外は必ず次へ進める(行き止まりを作らない)
		if coord != MapTree.GOAL_COORD and node.arrows.is_empty():
			return "行き止まり: %s" % coord
		if coord == MapTree.GOAL_COORD and not node.arrows.is_empty():
			return "ゴールから先へ矢印が出ている"

		# 矢印の先が実在すること(宙に浮いた矢印を出さない)
		for target in node.targets():
			if not tree.nodes.has(target):
				return "矢印の先が存在しない: %s -> %s" % [coord, target]

		# 同じ矢印が重複しない
		if node.arrows.size() != _unique_count(node.arrows):
			return "矢印が重複: %s" % coord

	# すべてのノードがスタートから到達可能(浮いたノードがない)
	var reached := _reachable_from_start(tree)
	for coord in tree.nodes:
		if not reached.has(coord):
			return "スタートから到達できないノード: %s" % coord

	# 矢印が交差しない: 列cが右下へ出しているなら、列c+1は左下へ出せない
	for step in range(0, 9):
		for column in range(0, MapTree.COLUMN_COUNT - 1):
			var left_node: MapTree.MapNode = tree.nodes.get(Vector2i(step, column))
			var right_node: MapTree.MapNode = tree.nodes.get(Vector2i(step, column + 1))
			if left_node == null or right_node == null:
				continue
			if MapTree.Arrow.RIGHT in left_node.arrows and MapTree.Arrow.LEFT in right_node.arrows:
				return "矢印が交差: 段%d 列%d と 列%d" % [step, column, column + 1]

	return ""


func _unique_count(arrows: Array) -> int:
	var seen := {}
	for a in arrows:
		seen[a] = true
	return seen.size()


func _reachable_from_start(tree: MapTree) -> Dictionary:
	var reached := {}
	var frontier: Array[Vector2i] = [MapTree.START_COORD]
	while not frontier.is_empty():
		var coord: Vector2i = frontier.pop_back()
		if reached.has(coord):
			continue
		reached[coord] = true
		var node: MapTree.MapNode = tree.nodes.get(coord)
		if node == null:
			continue
		for target in node.targets():
			if tree.nodes.has(target) and not reached.has(target):
				frontier.append(target)
	return reached


func _test_deterministic_with_seed(check: Callable) -> void:
	# 同じシードなら同じマップ。失敗したマップを再現できないと調べようがない。
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 12345
	var tree_a := MapTree.generate(rng_a)

	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 12345
	var tree_b := MapTree.generate(rng_b)

	check.call(
		tree_a != null and tree_b != null and _same_shape(tree_a, tree_b),
		"マップ生成: 同じシードなら同じマップになる"
	)


func _same_shape(a: MapTree, b: MapTree) -> bool:
	if a.nodes.size() != b.nodes.size():
		return false
	for coord in a.nodes:
		if not b.nodes.has(coord):
			return false
		var arrows_a: Array = a.nodes[coord].arrows.duplicate()
		var arrows_b: Array = b.nodes[coord].arrows.duplicate()
		arrows_a.sort()
		arrows_b.sort()
		if arrows_a != arrows_b:
			return false
	return true


func _test_navigation(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tree := MapTree.generate(rng)
	if tree == null:
		check.call(false, "マップ移動: 生成に失敗")
		return

	check.call(tree.current_coord == MapTree.START_COORD, "マップ移動: スタート地点から始まる")
	check.call(tree.current_step() == 0, "マップ移動: 最初は段0")
	check.call(not tree.is_goal(), "マップ移動: 最初はゴールではない")

	# 進める先以外へは動けない
	check.call(not tree.advance_to(Vector2i(5, 5)), "マップ移動: 繋がっていない先へは進めない")
	check.call(tree.current_coord == MapTree.START_COORD, "マップ移動: 失敗しても現在地は動かない")

	# ゴールまで辿り着けること
	var steps := 0
	while not tree.is_goal() and steps < 20:
		var candidates := tree.next_coords()
		if candidates.is_empty():
			break
		check.call(tree.advance_to(candidates[0]), "マップ移動: 繋がった先へ進める (段%d)" % tree.current_step())
		steps += 1

	check.call(tree.is_goal(), "マップ移動: 辿っていくとゴールに着く (%d手)" % steps)
	check.call(tree.next_coords().is_empty(), "マップ移動: ゴールから先はない")


## 各ノードに遭遇（敵グループ＋土俵）が確定して持たされていること。盤面と敵は
## クリック時に再抽選せず、ここから生成する（Main._on_map_node_chosen）。
##  - スタート(段0)は戦闘なし → 敵空・土俵null
##  - 段1以降は敵が1体以上、土俵が有効（名前つき）
##  - ゴール(段9)はレベル5のボス単体
## _assign_encounters を消す/段0にも付ける等の破壊でここが落ちる。
func _test_encounters(check: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	var failures: Array[String] = []

	for trial in TRIALS:
		rng.seed = trial
		var tree := MapTree.generate(rng)
		if tree == null:
			failures.append("seed=%d: 生成に失敗" % trial)
			continue
		for coord in tree.nodes:
			var node: MapTree.MapNode = tree.nodes[coord]
			if coord.x == 0:
				if node.has_encounter() or node.field != null:
					failures.append("seed=%d: スタート%sに遭遇が付いている" % [trial, coord])
			else:
				if not node.has_encounter():
					failures.append("seed=%d: 戦闘ノード%sに敵がいない" % [trial, coord])
				elif node.field == null or node.field.title_key == "":
					failures.append("seed=%d: 戦闘ノード%sの土俵が無効" % [trial, coord])

		# ゴールはレベル5のボス単体。
		var goal: MapTree.MapNode = tree.nodes[MapTree.GOAL_COORD]
		if goal.enemy_count() != 1 or goal.level() != 5:
			failures.append(
				"seed=%d: ゴールがボス単体Lv5でない (数%d/Lv%d)" % [
					trial, goal.enemy_count(), goal.level()
				]
			)

	check.call(
		failures.is_empty(),
		"マップ遭遇: %d回すべて全ノードに正しい遭遇が付く%s" % [
			TRIALS, "" if failures.is_empty() else " / 例: " + failures[0]
		]
	)


## 同じシードなら遭遇まで一致すること。ノードごとに敵数・実レベル・土俵名を照合する。
## 遭遇を非シードのRNGで引くとここが落ちる（表示と実戦の再現性が崩れる）。
func _test_encounters_deterministic(check: Callable) -> void:
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 999
	var tree_a := MapTree.generate(rng_a)

	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 999
	var tree_b := MapTree.generate(rng_b)

	var same := tree_a != null and tree_b != null
	if same:
		for coord in tree_a.nodes:
			var a: MapTree.MapNode = tree_a.nodes[coord]
			var b: MapTree.MapNode = tree_b.nodes[coord]
			if a.enemy_count() != b.enemy_count() or a.level() != b.level():
				same = false
				break
			var a_field: String = a.field.title_key if a.field != null else ""
			var b_field: String = b.field.title_key if b.field != null else ""
			if a_field != b_field:
				same = false
				break

	check.call(same, "マップ遭遇: 同じシードなら遭遇（敵数・レベル・土俵）も一致する")
