class_name MapTree
extends RefCounted

## Slay the Spire風の分岐マップ。archive/flask-prototype/maptree.py の移植。
##
## 縦10段(0=スタート, 9=ゴール)、横5列。各ノードは次の段の左下/真下/右下へ
## 1〜3本の矢印を持つ。スタート直後(段1)とゴール手前(段8)は必ず3ノード。
##
## プロトタイプはノードIDを step*10 + 列 の数値1つで表していたが、
## 段が10以上になると破綻する上に //10 や %10 が読みにくいので、
## ここでは Vector2i(段, 列) で持つ。IDは元々メタ情報で画面には出さない
## （プロトタイプにも「ノードIDはメタ情報なので表示しない」というコミットがある）。

enum Arrow { LEFT, STRAIGHT, RIGHT }

const STEP_GOAL := 9
const COLUMN_COUNT := 5
const START_COORD := Vector2i(0, 2)
const GOAL_COORD := Vector2i(STEP_GOAL, 2)

## 妥当なマップができるまで作り直す。無限ループを避けるための上限。
const MAX_ATTEMPTS := 200


class MapNode:
	extends RefCounted

	var coord: Vector2i
	var arrows: Array[Arrow] = []

	## このノードで戦う敵グループと土俵。マップ生成時に確定して持たせておく
	## （盤面と敵はここから生成する。Mainはクリック時に再抽選しない）。
	## スタート(段0)は戦闘が無いので空/null のまま。
	var enemies: Array[EnemyData] = []
	var field: FieldData = null

	func _init(node_coord: Vector2i) -> void:
		coord = node_coord

	## 戦闘ノードか（スタートだけ false）。
	func has_encounter() -> bool:
		return not enemies.is_empty()

	## このノードで戦う敵の数（乱戦なら2〜3）。
	func enemy_count() -> int:
		return enemies.size()

	## 実際に戦う敵のレベル。乱戦は1段下のメンバーレベルになるので、
	## 名目段レベルではなく実レベルを返して表示を嘘にしない。
	func level() -> int:
		if enemies.is_empty():
			return 0
		return enemies[0].level

	## 土俵の外周形状。描画でノードの輪郭に使う。土俵未設定なら矩形扱い。
	func wall_shape() -> ArenaWall.WallShape:
		if field == null:
			return ArenaWall.WallShape.RECT
		return field.wall_shape

	## この矢印を辿った先の座標。
	func target_of(arrow: Arrow) -> Vector2i:
		match arrow:
			Arrow.LEFT:
				return coord + Vector2i(1, -1)
			Arrow.RIGHT:
				return coord + Vector2i(1, 1)
			_:
				return coord + Vector2i(1, 0)

	func targets() -> Array[Vector2i]:
		var result: Array[Vector2i] = []
		for arrow in arrows:
			result.append(target_of(arrow))
		return result


## Vector2i(段, 列) -> MapNode
var nodes: Dictionary = {}

var current_coord: Vector2i = START_COORD


func current_step() -> int:
	return current_coord.x


## 今いるノードから進める先。ここ以外はクリックさせない。
func next_coords() -> Array[Vector2i]:
	var node: MapNode = nodes.get(current_coord)
	if node == null:
		return []
	return node.targets()


func advance_to(coord: Vector2i) -> bool:
	if not coord in next_coords():
		return false
	current_coord = coord
	return true


func is_goal() -> bool:
	return current_coord == GOAL_COORD


static func generate(rng: RandomNumberGenerator = null) -> MapTree:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	for attempt in MAX_ATTEMPTS:
		var tree := MapTree.new()
		tree._build(rng)
		if tree._all_penultimate_reachable():
			# 採用が確定した木にだけ遭遇を割り当てる（作り直した分は無駄に引かない）。
			tree._assign_encounters(rng)
			return tree

	# ここに来るなら生成条件が壊れている。黙って壊れたマップを返さない。
	push_error("MapTree: %d回試しても妥当なマップができなかった" % MAX_ATTEMPTS)
	return null


func _build(rng: RandomNumberGenerator) -> void:
	nodes.clear()
	current_coord = START_COORD

	# スタートは3方向へ分岐する。
	var start := MapNode.new(START_COORD)
	start.arrows = [Arrow.LEFT, Arrow.STRAIGHT, Arrow.RIGHT]
	nodes[START_COORD] = start
	for coord in start.targets():
		nodes[coord] = MapNode.new(coord)

	# ゴール手前の段は必ず3ノードで、すべてゴールへ集まる。
	# 先に置いておき、段7からここへ到達できるかを後で検証する。
	for column in [1, 2, 3]:
		var coord := Vector2i(8, column)
		var node := MapNode.new(coord)
		# 1->右下, 2->真下, 3->左下 でいずれも(9,2)へ。
		node.arrows = [[Arrow.RIGHT, Arrow.STRAIGHT, Arrow.LEFT][column - 1]]
		nodes[coord] = node
	nodes[GOAL_COORD] = MapNode.new(GOAL_COORD)

	for step in range(1, 8):
		_assign_arrows_for_step(step, rng)


## 全戦闘ノード（段1以降）に敵グループと土俵を確定して持たせる。段ごとの抽選は
## 既存の EnemyRoster / FieldRoster をそのまま使い、渡す rng は生成と同じものなので
## 「同じシード＝同じ遭遇」が保たれる（盤面表示と実戦が必ず一致する）。
## スタート(段0)は戦闘が無いので触らない。ゴール(段9)は EnemyRoster 側で単体ボスになる。
func _assign_encounters(rng: RandomNumberGenerator) -> void:
	for coord in nodes:
		if coord.x == 0:
			continue
		var node: MapNode = nodes[coord]
		node.enemies = EnemyRoster.pick_group_for_step(coord.x, rng)
		node.field = FieldRoster.pick_for_step(coord.x, rng)


func _assign_arrows_for_step(step: int, rng: RandomNumberGenerator) -> void:
	var columns: Array[int] = []
	for coord in nodes:
		if coord.x == step:
			columns.append(coord.y)
	columns.sort()

	# ひとつ左のノードが右下へ進んだ場合、このノードが左下へ進むと矢印が交差する。
	var cant_go_left := false
	var is_last := step == 7

	for column in columns:
		var node: MapNode = nodes[Vector2i(step, column)]
		node.arrows = _pick_arrows(step, column, cant_go_left, is_last, rng)

		if not is_last:
			for coord in node.targets():
				if not nodes.has(coord):
					nodes[coord] = MapNode.new(coord)

		if Arrow.RIGHT in node.arrows:
			cant_go_left = true


func _pick_arrows(
	_step: int, column: int, cant_go_left: bool, is_last: bool, rng: RandomNumberGenerator
) -> Array[Arrow]:
	# 段7だけは、ゴール手前の3ノード(列1..3)に必ず着地させる必要がある。
	if column == 0:
		if is_last:
			return [Arrow.RIGHT]
		return _sample([Arrow.STRAIGHT, Arrow.RIGHT], _pick_count([1, 1, 2], rng), rng)

	if column == COLUMN_COUNT - 1:
		if is_last:
			return [Arrow.LEFT]
		if cant_go_left:
			return [Arrow.STRAIGHT]
		return _sample([Arrow.LEFT, Arrow.STRAIGHT], _pick_count([1, 1, 2], rng), rng)

	var pool: Array[Arrow] = [Arrow.LEFT, Arrow.STRAIGHT, Arrow.RIGHT]
	var weights := [1, 1, 1, 2, 2, 2, 3]
	if cant_go_left:
		pool = [Arrow.STRAIGHT, Arrow.RIGHT]
		weights = [1, 1, 2]
	var arrows := _sample(pool, _pick_count(weights, rng), rng)

	if is_last:
		# 列1から左下は(8,0)、列3から右下は(8,4)で、どちらも存在しない。
		if column == 1:
			arrows.erase(Arrow.LEFT)
		elif column == COLUMN_COUNT - 2:
			arrows.erase(Arrow.RIGHT)
		if arrows.is_empty():
			arrows = [Arrow.STRAIGHT]
	return arrows


## 選択肢の重み付き個数。[1,1,2]なら2/3の確率で1本、1/3で2本。
func _pick_count(weights: Array, rng: RandomNumberGenerator) -> int:
	return weights[rng.randi_range(0, weights.size() - 1)]


func _sample(pool: Array[Arrow], count: int, rng: RandomNumberGenerator) -> Array[Arrow]:
	var shuffled := pool.duplicate()
	# Array.shuffle()はグローバルRNGを使いシードを渡せないので自前で混ぜる。
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Arrow = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	var result: Array[Arrow] = []
	for i in mini(count, shuffled.size()):
		result.append(shuffled[i])
	return result


## ゴール手前の3ノードすべてにスタートから到達できるか。
##
## 途中の段のノードは矢印が指したときにだけ作られるので構造上必ず到達できる。
## 先に置いてあるゴール手前の3ノードだけが浮く可能性がある。
##
## プロトタイプはここを条件式の羅列で書いていたが、82へ到達する判定に
## node_73のrightを見ていた(正しくはleft、rightは範囲外の84)。しかも73のrightは
## 構築時に必ず除去されるのでこの節は常に真になり、73の寄与が無視されていた。
## 結果、73だけが82に届くマップが誤って棄却されていた。ここでは実際に
## 辿って確かめるので、その手の取り違えが起きない。
func _all_penultimate_reachable() -> bool:
	var reached := {}
	var frontier: Array[Vector2i] = [START_COORD]
	while not frontier.is_empty():
		var coord: Vector2i = frontier.pop_back()
		if reached.has(coord):
			continue
		reached[coord] = true
		var node: MapNode = nodes.get(coord)
		if node == null:
			continue
		for target in node.targets():
			if nodes.has(target) and not reached.has(target):
				frontier.append(target)

	for column in [1, 2, 3]:
		if not reached.has(Vector2i(8, column)):
			return false
	return reached.has(GOAL_COORD)
