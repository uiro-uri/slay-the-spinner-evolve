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

	## 実際に戦う敵のレベル。斥候(次レベルの単体エリート)が混ざるので、
	## 名目段レベルではなく実レベル(最大値)を返して表示を嘘にしない。
	## 報酬のレア重み(Main.goto_reward)もこの実レベルを使う。
	func level() -> int:
		var highest := 0
		for enemy in enemies:
			highest = maxi(highest, enemy.level)
		return highest

	## 斥候(その段の基準レベルより強い敵)のノードか。マップの進路保証
	## (_ensure_vanguard_choice)と乱戦昇格の除外(_promote_compensation)が使う。
	func is_vanguard() -> bool:
		return level() > EnemyRoster.level_for_step(coord.x)

	## 勝てば選べる報酬の枚数(倒した頭数ぶん。Main._on_battle_finishedと同じ規則)。
	## ゴール(ボス)は撃破で即クリアになり報酬選択が無いので0。
	## マップ表示が使う: 敵数ピップ(脅威)しか出さないと乱戦が「リスクだけの部屋」に
	## 見えて選択が歪むため、リターン側もノード選択の時点で見せる。
	func reward_count() -> int:
		if not has_encounter() or coord.x == MapTree.STEP_GOAL:
			return 0
		return enemy_count()

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

	# prev_pivot: 直前の段で1択を押し込んだ列。次の段では避けて、1択ノードが
	# 縦に連なるレール(一本道回廊)を作らない。
	var prev_pivot := -1
	for step in range(1, 8):
		prev_pivot = _assign_arrows_for_step(step, rng, prev_pivot)
		_widen_single_choices(step, rng)


## その段の「進める先が1本しかない」ノードへ、足せるなら2本目の矢印を足す。
##
## 1択のノードが続くと「選択肢のないまま詰み部屋へ強制される」体験になるため
## （分岐マップなのに分岐がない）、矢印の交差を作らない範囲で全ノード2択以上を
## 保証する。先のノードが無ければ作ってよい——この段の矢印確定直後
## （＝次の段の矢印確定前）に呼ばれるので、作られたノードは次の反復で
## 普通に矢印を貰い、行き止まりにならない。ただし段7だけはゴール手前の
## 3ノードへ着地する必要があるので、実在するノードにしか足せない。
## 幾何的に足せない場合（ピボット列と段7の両端。_assign_arrows_for_step参照）
## だけ1本のまま残る。段0は3本固定、段8はゴールへ集約する設計なので触らない。
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
	_ensure_vanguard_choice(rng)
	_ensure_distinct_choice(rng)
	_ensure_distinct_field(rng)


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
		# 斥候は昇格させない(次レベル敵の乱戦は脅威が読めない上、斥候が黙って消える)。
		if node.is_vanguard():
			continue
		if _parents_keep_escape_without(coord):
			candidates.append(coord)
	if candidates.is_empty():
		return
	candidates.sort()  # 決定性: Dictionaryの列挙順に依存しない
	var chosen: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
	# 乱戦の組み方は EnemyRoster.group_of に一本化してある(頭数ぶんの質量倍率も
	# そこで掛かる)。ここで素の表から組むと、昇格した部屋だけ規則から外れる。
	nodes[chosen].enemies = EnemyRoster.group_of(
		EnemyRoster.level_for_step(child_step), count, rng, child_step
	)


## 全ノードの進める先に「斥候でないノード」を最低1つ保証する。
##
## 斥候(次レベルの単体エリート)は見て避けられる「選べるリスク」の設計なので、
## 進める先が全部斥候だと強制になってしまう(乱戦の_ensure_single_escapeと同じ理屈)。
## 強制になっているノードの進める先から1つを、同段の通常単体へ引き直す。
## 単体へ引き直すのは_ensure_single_escapeの保証(1体部屋)を後から壊さないため
## (斥候はもともと単体なので、頭数の総量も変わらない)。
## 段の昇順・列の昇順で舐めるのは決定性のため(Dictionaryの挿入順に依存させない)。
##
## 舐める段が**段0(スタート)から**なのは、段1が斥候段になったため(2026-08-07)。
## 段1は必ず3ノードしかないので「3つとも斥候」が0.8%で起き、そのときラン最初の
## 選択が「Lv2を踏むか、Lv2を踏むか、Lv2を踏むか」になる。段0自身は戦闘ノードでは
## ないが矢印は持つので、他の段とまったく同じ判定でよい(200生成のテストが
## seed=19 で実際に踏んだ)。
func _ensure_vanguard_choice(rng: RandomNumberGenerator) -> void:
	for step in range(0, STEP_GOAL):
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
			var all_vanguard := true
			for t in targets:
				var tn: MapNode = nodes.get(t)
				if tn == null or not tn.is_vanguard():
					all_vanguard = false
					break
			if not all_vanguard:
				continue
			var chosen: Vector2i = targets[rng.randi_range(0, targets.size() - 1)]
			var chosen_node: MapNode = nodes[chosen]
			chosen_node.enemies = [EnemyRoster.pick_for_step(chosen.x, rng)]


## 「見分けの付かない2択」を潰す: 進める先が**全部**同じレベルの単体部屋なら、
## そのうち1つを2体の乱戦へ昇格し、**同じ段の別の乱戦から頭数を1つもらって
## 帳尻を合わせる**。
##
## 動機はコールドプレイの一次証拠(2026-08-08, seed=48213)。段4・段5・段7の3回、
## 進める先の2つが
##   `col+3 : Lv4 1体(硬さ取り分0.55 格上)→報酬1枚` と
##   `col+4 : Lv4 1体(硬さ取り分0.55 格上)→報酬1枚`
## のように**表示されている数字が1つ残らず同じ**だった(段8は1択)。危険(レベル・
## 頭数・脅威メーター)も見返り(報酬枚数・レア倍率)も一致するので、選ぶ根拠が
## どこにも無く、3回とも指の赴くままに押した。段1〜3は 1体/2体/3体 が並んで
## 「安全に1枚か、賭けて2〜3枚か」の賭けになっていたのに、**後半はマップが
## ただの通路になる**。
##
## 差が付いていない軸は頭数だけではないが、頭数以外は動かさない:
## - **レベル**は斥候(`_ensure_vanguard_choice`)が既に持っている軸で、
##   斥候が混ざった段(段6)は実際に見分けが付いていた=足す必要がない。
## - **土俵**はマップに外周形状・等高線・柱として描かれてはいるが、難易度が
##   どこにも数字で出ない(脅威メーターは土俵に無補正)。実測
##   (`playtest/measure_field.gd`, Lv2各400戦)でも勝率は
##   CLASSIC 93.8% / BOWL 91.8% / PLATE 91.2% / ARENA 87.5% / ROUND 87.0% と
##   6pt に収まり、大きく外れるのは PILLARS 73.2% の1つだけ。つまり土俵違いは
##   **賭けの内容を変えていない**ので、ここでは同一として扱う。
##
## 昇格する側の条件は `_promote_compensation` と同じ理屈で揃える:
## - ゴール(ボス)は演出上つねに単体なので触らない。
## - 斥候は昇格させない(次レベルの乱戦は脅威が読めず、斥候も黙って消える)。
## - `_parents_keep_escape_without` を通ったノードだけ。**他の親から見た
##   1体部屋の逃げ道**(`_ensure_single_escape`)を後から壊さないため。この保証は
##   段5以降にしか要らないが、全段で掛けても失うのは昇格の機会だけなので、
##   ここでは段を分けずに常に守る側へ倒す。
## 昇格しても自分自身の進める先には昇格しなかった単体部屋が必ず残る(前提が
## 「全部1体」なので2つ以上ある)ので、この段の逃げ道は定義から保たれる。
## 斥候の集合も動かさない(素の段レベルの乱戦を作るだけ)ので
## `_ensure_vanguard_choice` の保証も保たれる=**この関数は最後に走ってよい**。
##
## 頭数は2体で固定する。3体まで振ると「同一の2択」を消すためだけに部屋の危険度が
## 大きく動いてしまう(Lv3の勝率は 1体91% → 2体54% → 3体41%)。対比を作るのに
## 必要な最小の1歩が2体。
##
## **昇格だけでは経済が太る**。交換にせず「1体を2体へ」だけやった版をボットで
## 測ると、頭数ぶん報酬が増えるぶんクリア率が **54.7% → 65.3%**、決戦の勝率が
## **37.4% → 46.4%** と大きく跳ねた(intercept+greedy, 各300ラン)。ここで直したいのは
## 「選ぶ根拠が無い」ことであって難易度ではないので、`_ensure_single_escape` が
## 引き直しを昇格で相殺しているのと同じ理屈で、**同じ段の別の乱戦から頭数を1つ
## もらう**(`_demote_donor`。3体→2体 か 2体→1体)。段の頭数の総和は1つも動かない。
## 渡し手が見つからなければ昇格もしない——経済を動かさない方を優先する。
##
## **1周で足りる**。交換は「渡し手のいる分岐点」を1つ潰すだけで新しい渡し手を
## 生まないので、2周目に回しても取り分は1つも増えない(500生成で総数が1つも
## 動かないことを measure_map_choice で確認済み)。掃引は1回だけにしてある。
##
## 段の昇順・列の昇順で舐めるのは決定性のため(Dictionaryの挿入順に依存させない)。
func _ensure_distinct_choice(rng: RandomNumberGenerator) -> void:
	for step in range(0, STEP_GOAL):
		var columns: Array[int] = []
		for coord in nodes:
			if coord.x == step:
				columns.append(coord.y)
		columns.sort()

		for column in columns:
			var node: MapNode = nodes[Vector2i(step, column)]
			var targets := node.targets()
			if targets.size() < 2:
				continue
			if not _targets_are_alike(targets):
				continue
			var candidates: Array[Vector2i] = []
			for t in targets:
				var tn: MapNode = nodes.get(t)
				if tn == null or t == GOAL_COORD or tn.is_vanguard():
					continue
				if _parents_keep_escape_without(t):
					candidates.append(t)
			if candidates.is_empty():
				continue
			candidates.sort()  # 決定性: targets の並び順に依存しない
			var chosen: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
			var donor := _demote_donor(chosen, targets, rng)
			if donor == GOAL_COORD:
				continue  # 割に合う交換相手が居ない=経済を太らせないために何もしない
			# 型付きのローカルへ受けてから代入する。`nodes[...]`(Variant)へ直接
			# 代入すると Array[EnemyData] への変換が働かず、実行時に
			# 「Invalid assignment ... value of type 'Array'」で**この関数だけが
			# 黙って中断**する(呼び手は続行するので生成は成功したように見える)。
			var donor_node: MapNode = nodes[donor]
			donor_node.enemies = EnemyRoster.group_of(
				EnemyRoster.level_for_step(donor.x),
				donor_node.enemy_count() - 1,
				rng,
				donor.x
			)
			# 乱戦の組み方は EnemyRoster.group_of に一本化してある(頭数ぶんの質量倍率も
			# 段のrpsランプもそこで掛かる)。_promote_compensation と同じ入り口。
			var chosen_node: MapNode = nodes[chosen]
			chosen_node.enemies = EnemyRoster.group_of(
				EnemyRoster.level_for_step(chosen.x), 2, rng, chosen.x
			)



## 昇格の交換相手: step の乱戦ノードを1つ選んで返す。割に合う相手が居なければ
## GOAL_COORD(ボスは常に単体＝乱戦ノードになりえないので「該当なし」の番兵に使える)。
##
## `exclude` はいま見ている分岐点の進める先。ここから落とすと、せっかく作った対比を
## 自分で潰す(2択の片方を上げて片方を下げるだけ)ので除く。
##
## 渡す/貰う頭数は**1つだけ**。donor は頭数を1つ減らし(3体→2体 か 2体→1体)、
## `chosen` は 1体→2体 になるので、段の頭数の総和はきっかり保たれる。
##
## **3体の donor が最優先になる**。3体→2体 ではそのノードは乱戦のままなので、
## そこを目印にしていた親の2択は1つも平らにならない(損=0)。2体→1体 は目印が
## 消えるので損が立つ。下の「損の少ない順」がそれを自動的に選ぶ。
##
## **交換は移動元を潰しうる**。乱戦ノードはこのマップで「見分け」を作っている
## 主な実体なので、2体を動かすと移動元の親が平らになる。だから「潰さない相手」を
## 探すのではなく、**差し引きで得になる交換だけ**を通す:
##   得 = `chosen` を2体にすると平らでなくなる親の数
##   損 = `donor` の頭数を1つ減らすと新しく平らになる親の数
## で 得 > 損 のときだけ交換する。親を多く抱えた2体(＝多くの2択を1つで支えている)は
## 損が大きくて選ばれず、3体や、親が既に別の乱戦を持っている冗長な2体から動く。
## 同点は動かさない(意味のない揺らぎを入れない)。
##
## `chosen` と `donor` の両方を進める先に持つ親は損の側だけで数える(その親は昇格前も
## 昇格後も平らではないので、実際には損でも得でもない)。多めに見積もる方向なので、
## 経済を太らせる側へは倒れない。
func _demote_donor(
	chosen: Vector2i, exclude: Array[Vector2i], rng: RandomNumberGenerator
) -> Vector2i:
	var gain := _alike_parent_count(chosen, Vector2i(-1, -1))
	if gain <= 0:
		return GOAL_COORD
	var best_loss := gain - 1  # 損が得に並んだ時点で「割に合わない」＝上限は得−1
	var candidates: Array[Vector2i] = []
	for coord in nodes:
		if coord.x != chosen.x or coord in exclude or coord == GOAL_COORD:
			continue
		var node: MapNode = nodes[coord]
		if node.enemy_count() < 2:
			continue
		# 損 = いま平らでない親のうち、coord の頭数が1つ減ると平らになる数。
		# 3体→2体 は乱戦のままなので、定義から1つも平らにならない=損0。
		var loss := 0
		if node.enemy_count() == 2:
			loss = (
				_alike_parent_count(coord, coord)
				- _alike_parent_count(coord, Vector2i(-1, -1))
			)
		if loss > best_loss:
			continue
		if loss < best_loss:
			best_loss = loss
			candidates.clear()
		candidates.append(coord)
	if candidates.is_empty():
		return GOAL_COORD
	candidates.sort()  # 決定性: Dictionaryの列挙順に依存しない
	return candidates[rng.randi_range(0, candidates.size() - 1)]


## coord を進める先に持つ親のうち、2択以上を持ち、かつ進める先が見分けの付かない
## ものの数。`as_single` は `_targets_are_alike` へそのまま渡す仮定(coord を渡せば
## 「coord が1体へ落ちたら」の数になる)。
func _alike_parent_count(coord: Vector2i, as_single: Vector2i) -> int:
	var total := 0
	for parent_coord in nodes:
		if parent_coord.x != coord.x - 1:
			continue
		var parent: MapNode = nodes[parent_coord]
		var targets := parent.targets()
		if targets.size() < 2 or not coord in targets:
			continue
		if _targets_are_alike(targets, as_single):
			total += 1
	return total


## 進める先が全部「同じレベルの1体部屋」か＝マップ上で見分けが付かないか。
##
## マップのノードが出す判断材料は レベル・頭数・報酬枚数・レア倍率・脅威メーター で、
## このうち独立に動くのは実レベルと頭数の2つだけ(報酬枚数は頭数そのもの、レア倍率と
## 脅威メーターはレベルと頭数の関数)。だから両方一致＝表示が全一致になる。
##
## 頭数が2以上で揃っている場合は昇格の出番が無い(2体を3体にすると危険度が
## 跳ねる)ので、ここで false を返して手を出さない。
##
## `as_single` に座標を渡すと、そのノードだけ「1体へ落ちたら」と仮定して判定する
## (交換相手の下見。`_parents_keep_distinct_without` が使う)。落としてもレベルは
## 段相応のまま変わらないので、仮定するのは頭数だけでよい。
func _targets_are_alike(
	targets: Array[Vector2i], as_single: Vector2i = Vector2i(-1, -1)
) -> bool:
	var level := -1
	for t in targets:
		var tn: MapNode = nodes.get(t)
		if tn == null or not tn.has_encounter():
			return false
		if tn.enemy_count() != 1 and t != as_single:
			return false
		if level < 0:
			level = tn.level()
		elif tn.level() != level:
			return false
	return level > 0


## 進める先が「数字も土俵も全部おなじ」＝ノードの絵が1ピクセルも違わない分岐を無くす。
##
## 動機はコールドプレイの一次証拠。9段のランで、段1→2 が
## 「Lv1 1体 FIELD_BOWL」対「Lv1 1体 FIELD_BOWL」、段3→4 が
## 「Lv2 2体 FIELD_BOWL」対「Lv2 2体 FIELD_BOWL」で、**どちらも完全な同一物の2択**
## だった。選べる2つが同じなら、それは選択ではなく確認ボタンが2つ並んでいるだけ。
##
## `_ensure_distinct_choice` は既に「数字が全一致」を頭数の交換で崩しているが、
## 手が出せる範囲が狭い: (a) 全部1体のときだけ(全部2体は「2体を3体にすると
## 危険度が跳ねる」ので意図的に見送っている)、(b) 経済を太らせない交換相手
## (`_demote_donor`)が見つかったときだけ。上のコールドプレイの2件は
## ちょうど (a) と (b) の穴に落ちている。
##
## **土俵は経済に触れずに対比を作れる唯一の軸**。報酬枚数は頭数そのもの、レア倍率と
## 脅威メーターはレベルと頭数の関数——つまり数字を動かすものは全部、報酬の総量を
## 動かす。土俵はどれも同じ枚数・同じレア倍率なので、引き直しても
## 「マップに置かれた報酬の総量」(measure_map_choice の頭数の総和)は1つも動かない。
## しかも絵は確実に変わる: 土俵6種はノード上で外周形状・傾斜のケバ・柱の印の
## いずれかが必ず違う(`StageSlopeMark` を入れたサイクルが作った差)。
##
## 手を出すのは**数字も土俵も全一致**のときだけ。数字が違えば(1体対2体など)報酬枚数と
## 脅威メーターで既に見分けが付くので、そこで土俵まで違えるのは余計な作り込みになる。
##
## 引き直す先は「**その子の全ての親から見た兄弟**が使っていない土俵」に限る。
## 子は複数の親を持ちうるので、目の前の2択を直すために別の親の2択を平らにしたら
## 差し引きゼロになる。候補が無ければ次の的へ移り、どれも駄目なら諦める
## (悪化させないことを最優先にする)。
##
## 決戦(ボス)の土俵は専用の大闘技場で固定なので触らない。そもそも段8→9 は
## 進める先が1つしかないのでここへ来ない。
##
## 段の昇順・列の昇順で舐めるのは決定性のため(Dictionaryの挿入順に依存させない)。
func _ensure_distinct_field(rng: RandomNumberGenerator) -> void:
	for step in range(0, STEP_GOAL):
		var columns: Array[int] = []
		for coord in nodes:
			if coord.x == step:
				columns.append(coord.y)
		columns.sort()

		for column in columns:
			var node: MapNode = nodes[Vector2i(step, column)]
			var targets := node.targets()
			if targets.size() < 2:
				continue
			if not _targets_look_identical(targets):
				continue
			var order := targets.duplicate()
			order.sort()  # 決定性: targets の並び順(矢印の順)に依存しない
			for t in order:
				if _reassign_field(t, rng):
					break


## 進める先が「実レベルも頭数も土俵も」全部おなじか＝ノードの絵が完全に同じか。
##
## `_targets_are_alike` とは別実装にしてある。あちらは**昇格の下見**なので
## 「全部1体」でなければ false を返す(2体を3体にはしない)が、こちらは
## **遊ぶ側から見た同一性**で、全部2体の2択も等しく見分けが付かない。
func _targets_look_identical(targets: Array[Vector2i]) -> bool:
	var level := -1
	var count := -1
	var field_key := ""
	for t in targets:
		var tn: MapNode = nodes.get(t)
		if tn == null or not tn.has_encounter() or tn.field == null:
			return false
		if level < 0:
			level = tn.level()
			count = tn.enemy_count()
			field_key = tn.field.title_key
		elif (
			tn.level() != level
			or tn.enemy_count() != count
			or tn.field.title_key != field_key
		):
			return false
	return level > 0


## coord の土俵を、その全ての親から見た兄弟が使っていないものへ引き直す。
## 引き直せたら true。ボスの土俵は固定なので触らず、候補が無ければ何もしない。
func _reassign_field(coord: Vector2i, rng: RandomNumberGenerator) -> bool:
	var node: MapNode = nodes.get(coord)
	if node == null or not node.has_encounter() or node.field == null:
		return false
	# 決戦の土俵は専用の大闘技場で固定(FieldRoster.pick_for_step と同じ判定)。
	if coord == GOAL_COORD or EnemyRoster.level_for_step(coord.x) >= 5:
		return false

	var taken := {node.field.title_key: true}
	for sibling in _siblings_of(coord):
		var sn: MapNode = nodes.get(sibling)
		if sn != null and sn.field != null:
			taken[sn.field.title_key] = true

	var candidates: Array[FieldData] = []
	for field in FieldRoster.all():
		if not taken.has(field.title_key):
			candidates.append(field)
	if candidates.is_empty():
		return false
	node.field = candidates[rng.randi_range(0, candidates.size() - 1)]
	return true


## coord と親を共有するノード(coord 自身は除く)。同じノードが複数の親から
## 兄弟として見えることがあるので座標で重複を潰す。
func _siblings_of(coord: Vector2i) -> Array[Vector2i]:
	var seen := {}
	var result: Array[Vector2i] = []
	for parent_coord in nodes:
		if parent_coord.x != coord.x - 1:
			continue
		var parent: MapNode = nodes[parent_coord]
		var targets := parent.targets()
		if not coord in targets:
			continue
		for t in targets:
			if t == coord or seen.has(t):
				continue
			seen[t] = true
			result.append(t)
	result.sort()  # 決定性: Dictionaryの列挙順に依存しない
	return result


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


## この段の全ノードへ矢印を割り当てる。戻り値はこの段の「ピボット列」(下記)。
##
## 交差禁止は隣へ連鎖する: 端の列は矢印2種しか持てないので、全5列が埋まった
## 段では「どこか1列が1択になる」のが幾何的に避けられない(例: 左端が2本
## 持つには必ず右下が要り、それが列1の左下を塞ぎ、列1も右下頼み……と続いて
## 右端は真下しか残らない)。かつては常に左から確定していたため、この
## しわ寄せが毎段右端に溜まり、右端を縦に貫く多段の一本道回廊ができていた。
##
## そこで、しわ寄せを受ける「ピボット列」を段ごとに抽選し、両端からピボットへ
## 向かって確定していく。ピボットは直前の段のピボット列(prev_pivot)を避ける
## ので、1択ノードが1択ノードへ縦に連なるレールにはならない。盤の端まで
## 埋まっていない段は端に向かって普通に掃引すれば、しわ寄せは盤の空きに
## 逃げて消える(その場合ピボットは無し=-1を返す)。
func _assign_arrows_for_step(step: int, rng: RandomNumberGenerator, prev_pivot: int) -> int:
	var columns: Array[int] = []
	for coord in nodes:
		if coord.x == step:
			columns.append(coord.y)
	columns.sort()

	var is_last := step == 7
	var pivot := _pick_pivot(step, columns, prev_pivot, rng)

	# 処理順: ピボットの左側を左から、右側を右から、最後にピボット。
	# ピボットが無い段は、盤の端に接している側から遠い側へ掃引する
	# (端の列を先に確定すれば2本持てて、しわ寄せが端に溜まらない)。
	var order: Array[int] = []
	if pivot >= 0:
		for c in columns:
			if c < pivot:
				order.append(c)
		var right_side: Array[int] = []
		for c in columns:
			if c > pivot:
				right_side.append(c)
		right_side.reverse()
		order.append_array(right_side)
		order.append(pivot)
	else:
		order = columns.duplicate()
		if columns[0] != 0:
			order.reverse()

	for column in order:
		var node: MapNode = nodes[Vector2i(step, column)]
		# 先に確定した隣がこちら側へ斜めを出していたら、こちらの対向斜めは
		# 交差になるので出せない。未確定の隣は矢印が空なので自然に無視される。
		node.arrows = _pick_arrows(
			step, column,
			_neighbor_has(step, column - 1, Arrow.RIGHT),
			_neighbor_has(step, column + 1, Arrow.LEFT),
			is_last, rng
		)

		if not is_last:
			for coord in node.targets():
				if not nodes.has(coord):
					nodes[coord] = MapNode.new(coord)

	return pivot


## しわ寄せ(1択)を受けるピボット列を選ぶ。両端まで埋まった段だけが対象で、
## それ以外は -1(しわ寄せ自体が発生しない)。直前の段のピボットは避ける。
## 段6と段7は端の列を避ける: 段7の両端(7,0)/(7,4)は着地先が1つしかない
## 構造的1択なので、その親まで1択にすると2段連続の一本道になってしまう。
func _pick_pivot(step: int, columns: Array[int], prev_pivot: int, rng: RandomNumberGenerator) -> int:
	if columns[0] != 0 or columns[columns.size() - 1] != COLUMN_COUNT - 1:
		return -1
	var candidates: Array[int] = []
	for c in columns:
		if c == prev_pivot:
			continue
		if step >= 6 and (c == 0 or c == COLUMN_COUNT - 1):
			continue
		candidates.append(c)
	if candidates.is_empty():
		return prev_pivot
	return candidates[rng.randi_range(0, candidates.size() - 1)]


## cant_left / cant_right には交差禁止で出せない斜めを渡す。
func _pick_arrows(
	_step: int, column: int, cant_left: bool, cant_right: bool,
	is_last: bool, rng: RandomNumberGenerator
) -> Array[Arrow]:
	# 段7だけは、ゴール手前の3ノード(列1..3)に必ず着地させる必要がある。
	# 端の列の唯一の斜めは着地先(8,1)/(8,3)を隣が指せない(列1の左下・列3の
	# 右下は盤外行きで確定時に消される)ので、交差禁止と衝突しない。
	# 矢印を2種しか持てないノード(端の列や、交差禁止で1方向を失った列)は
	# 2本とも持つ。1本に絞ると後段の交差禁止と重なって1択ノードが量産され、
	# 「全ノード2択以上」の保証(_widen_single_choices)が幾何的に成立しなくなる。
	if column == 0:
		if is_last:
			return [Arrow.RIGHT]
		if cant_right:
			return [Arrow.STRAIGHT]
		return [Arrow.STRAIGHT, Arrow.RIGHT]

	if column == COLUMN_COUNT - 1:
		if is_last:
			return [Arrow.LEFT]
		if cant_left:
			return [Arrow.STRAIGHT]
		return [Arrow.LEFT, Arrow.STRAIGHT]

	var pool: Array[Arrow] = [Arrow.LEFT, Arrow.STRAIGHT, Arrow.RIGHT]
	var weights := [1, 1, 1, 2, 2, 2, 3]
	if cant_left:
		pool.erase(Arrow.LEFT)
	if cant_right:
		pool.erase(Arrow.RIGHT)
	if pool.size() == 2:
		weights = [2, 2, 2]
	elif pool.size() == 1:
		return pool
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
