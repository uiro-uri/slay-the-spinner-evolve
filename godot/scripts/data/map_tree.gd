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

## この段以降の戦闘ノードへの進路には必ず「1体部屋」の逃げ道を保証する
## (_ensure_single_escape)。段5=敵Lv3から。それより前の乱戦は強制されても
## ほぼ無料の追加報酬なので保証しない(経済を痩せさせない)。
const SINGLE_ESCAPE_FROM_STEP := 5


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
		_widen_single_choices(step, rng)


## その段の「進める先が1本しかない」ノードへ、足せるなら2本目の矢印を足す。
##
## 1択のノードが続くと「選択肢のないまま詰み部屋へ強制される」体験になるため
## （分岐マップなのに分岐がない）、矢印の交差を作らない範囲で全ノード2択以上を
## 保証する。先のノードが無ければ作ってよい——この段の矢印確定直後
## （＝次の段の矢印確定前）に呼ばれるので、作られたノードは次の反復で
## 普通に矢印を貰い、行き止まりにならない。ただし段7だけはゴール手前の
## 3ノードへ着地する必要があるので、実在するノードにしか足せない。
## 幾何的に足せない場合（例: 右端の列で、左隣が右下へ出している）だけ
## 1本のまま残る。段0は3本固定、段8はゴールへ集約する設計なので触らない。
func _widen_single_choices(step: int, rng: RandomNumberGenerator) -> void:
	var columns: Array[int] = []
	for coord in nodes:
		if coord.x == step:
			columns.append(coord.y)
	columns.sort()

	for column in columns:
		var node: MapNode = nodes[Vector2i(step, column)]
		if node.arrows.size() >= 2:
			continue
		var candidates := _addable_arrows(step, column)
		if candidates.is_empty():
			continue
		# 右下を足すと右隣ノードの左下候補を潰す(交差になる)ので、
		# 後続を制約しない左下/真下を優先し、右下は他に無いときだけ。
		if candidates.size() > 1:
			candidates.erase(Arrow.RIGHT)
		var arrow: Arrow = candidates[rng.randi_range(0, candidates.size() - 1)]
		node.arrows.append(arrow)
		var target := node.target_of(arrow)
		if not nodes.has(target):
			nodes[target] = MapNode.new(target)


## (step, column) のノードにいま足せる矢印。持っていないもののうち、
## 盤面の内側に収まり、隣列の既存矢印と交差しないものだけ。
## 段7だけは着地先(ゴール手前の3ノード)が実在することも要求する。
func _addable_arrows(step: int, column: int) -> Array[Arrow]:
	var node: MapNode = nodes[Vector2i(step, column)]
	var result: Array[Arrow] = []
	for arrow in [Arrow.LEFT, Arrow.STRAIGHT, Arrow.RIGHT]:
		if arrow in node.arrows:
			continue
		var target := node.target_of(arrow)
		if target.y < 0 or target.y >= COLUMN_COUNT:
			continue
		if step == 7 and not nodes.has(target):
			continue
		if arrow == Arrow.LEFT and _neighbor_has(step, column - 1, Arrow.RIGHT):
			continue
		if arrow == Arrow.RIGHT and _neighbor_has(step, column + 1, Arrow.LEFT):
			continue
		result.append(arrow)
	return result


func _neighbor_has(step: int, column: int, arrow: Arrow) -> bool:
	var neighbor: MapNode = nodes.get(Vector2i(step, column))
	return neighbor != null and arrow in neighbor.arrows


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
	_ensure_single_escape(rng)


## 段SINGLE_ESCAPE_FROM_STEP以降のノードの進める先に「1体部屋」を最低1つ保証する。
##
## 遭遇はノードごとに独立抽選(2体30%/3体10%)なので、「進める先が全部複数体」が
## 選択局面の約2割・ラン全体では8割超で最低1回起きていた(段7→段8は3割)。複数体戦は
## 頭数ぶん報酬が増える「選べるリスク」の設計なのに、選択肢が全部複数体だと強制に
## なってしまう。ここでは強制になっているノードの進める先から1つを単体へ引き直し、
## **同じ段の別の単体ノードを同じ頭数へ昇格して複数体の総量を保存する**。
## 引き直すだけだと複数体ノードが4割減り、頭数ぶん報酬のパーツ経済が痩せて
## ラン全体が弱くなってしまう(bot計測でクリア率58%→46%)。交換なら強制だけが消える。
##
## 保証は段5以降(Lv3+)への進路だけ。序盤(Lv1-2)の乱戦は勝率92〜96%の
## 「ほぼ無料の追加報酬」で、強制されても害がなく、実際の強制詰みの不満は
## 全て段5以降の複数体部屋だった。全段に保証を張ると、ランダム進路が乱戦を
## 踏む率そのものが下がって(38%→24%)経済が痩せる副作用も出る。
##
## 昇格先は「昇格してもその親全員に1体部屋の逃げ道が残る」単体ノードに限る。
## 昇格は1件ずつ現在の盤面で判定するので、複数回の昇格が重なって逃げ道を
## 潰すことはない。候補が無ければ昇格を諦める(保証が優先)。
##
## 段の昇順・列の昇順で舐めるのは決定性のため(Dictionaryの挿入順に依存させない)。
## 先の段の引き直しを後続の親も見るので、同じ子が2度引き直されることはない。
func _ensure_single_escape(rng: RandomNumberGenerator) -> void:
	for step in range(SINGLE_ESCAPE_FROM_STEP - 1, STEP_GOAL):
		var columns: Array[int] = []
		for coord in nodes:
			if coord.x == step:
				columns.append(coord.y)
		columns.sort()

		for column in columns:
			var node: MapNode = nodes[Vector2i(step, column)]
			var targets := node.targets()
			if targets.is_empty():
				continue
			var all_multi := true
			for t in targets:
				var tn: MapNode = nodes.get(t)
				if tn == null or tn.enemy_count() <= 1:
					all_multi = false
					break
			if not all_multi:
				continue
			var chosen: Vector2i = targets[rng.randi_range(0, targets.size() - 1)]
			var chosen_node: MapNode = nodes[chosen]
			var demoted_count := chosen_node.enemy_count()
			chosen_node.enemies = [EnemyRoster.pick_for_step(chosen.x, rng)]
			_promote_compensation(chosen.x, chosen, demoted_count, rng)


## 引き直しの補償: child_step の単体ノードを1つ、count 体の乱戦へ昇格する。
## 「昇格しても、その全親に1体部屋の逃げ道が残る」ノードだけが候補。
## 候補が無ければ何もしない(1体部屋保証が複数体の総量保存より優先)。
func _promote_compensation(
	child_step: int, exclude: Vector2i, count: int, rng: RandomNumberGenerator
) -> void:
	var candidates: Array[Vector2i] = []
	for coord in nodes:
		if coord.x != child_step or coord == exclude:
			continue
		var node: MapNode = nodes[coord]
		if node.enemy_count() != 1 or coord == GOAL_COORD:
			continue
		if _parents_keep_escape_without(coord):
			candidates.append(coord)
	if candidates.is_empty():
		return
	candidates.sort()  # 決定性: Dictionaryの列挙順に依存しない
	var chosen: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
	var members := EnemyRoster.of_level(EnemyRoster.level_for_step(child_step))
	var group: Array[EnemyData] = []
	for _i in count:
		group.append(members[rng.randi_range(0, members.size() - 1)])
	nodes[chosen].enemies = group


## coord が複数体になっても、coord を進める先に持つ全ノードに
## 別の1体部屋が残るか。
func _parents_keep_escape_without(coord: Vector2i) -> bool:
	for parent_coord in nodes:
		if parent_coord.x != coord.x - 1:
			continue
		var parent: MapNode = nodes[parent_coord]
		if not coord in parent.targets():
			continue
		var has_other_single := false
		for t in parent.targets():
			if t == coord:
				continue
			var tn: MapNode = nodes.get(t)
			if tn != null and tn.enemy_count() <= 1:
				has_other_single = true
				break
		if not has_other_single:
			return false
	return true


func _assign_arrows_for_step(step: int, rng: RandomNumberGenerator) -> void:
	var columns: Array[int] = []
	for coord in nodes:
		if coord.x == step:
			columns.append(coord.y)
	columns.sort()

	# ひとつ左のノードが右下へ進んだ場合、このノードが左下へ進むと矢印が交差する。
	# 交差しうるのは隣接した列だけ——列の間に空きがあれば矢印は届かないので、
	# 制約を粘着させず「直前に処理した列が本当にひとつ左か」を見る。
	var last_column := -99
	var last_took_right := false
	var is_last := step == 7

	for column in columns:
		var cant_go_left := last_took_right and last_column == column - 1
		var node: MapNode = nodes[Vector2i(step, column)]
		node.arrows = _pick_arrows(step, column, cant_go_left, is_last, rng)

		if not is_last:
			for coord in node.targets():
				if not nodes.has(coord):
					nodes[coord] = MapNode.new(coord)

		last_column = column
		last_took_right = Arrow.RIGHT in node.arrows


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
