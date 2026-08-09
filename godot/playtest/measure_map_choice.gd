extends SceneTree

## マップの分岐が「選択になっているか」を測る診断。
##
##   godot --headless --path godot --script res://playtest/measure_map_choice.gd -- [--count=500]
##
## 動機: マップのノードが出す判断材料は **レベル・頭数・報酬枚数・レア倍率・
## 脅威メーター** で、このうち独立に動くのは実レベルと頭数の2つだけ(報酬枚数は
## 頭数そのもの、レア倍率と脅威メーターはレベルと頭数の関数)。進める先が全部
## 同じ(レベル, 頭数)なら、**表示されている数字が1つ残らず一致する2択**——
## つまり選ぶ根拠が無い分岐になる。コールドプレイでは段4・段5・段7の3回これを
## 踏んだが、n=1 では「たまたま運が悪かった」と区別できないので数える。
##
## 出力は段別の「分岐点の数 / 見分けの付かない分岐点の数と割合」。
## 分岐点＝進める先を2つ以上持つノード(1択のノードはそもそも選択が無いので別勘定)。

const DEFAULT_COUNT := 500


func _init() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var eq := arg.find("=")
			args[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	var count := int(args.get("count", str(DEFAULT_COUNT)))

	# 段(親の段) -> [分岐点の数, 見分けの付かない数, 1択ノードの数]
	var per_step := {}
	# 全戦闘ノードの頭数の総和。報酬枚数は頭数そのものなので、これが「マップに
	# 置かれた報酬の総量」＝経済の大きさになる。分岐を作り直す改変が経済まで
	# 動かしていないかは、この1つの数で見張れる。
	var heads := 0
	var rng := RandomNumberGenerator.new()
	for seed_value in count:
		rng.seed = seed_value
		var tree := MapTree.generate(rng)
		if tree == null:
			continue
		for coord in tree.nodes:
			var node: MapTree.MapNode = tree.nodes[coord]
			heads += node.enemy_count()
			var targets := node.targets()
			if targets.is_empty():
				continue
			var row: Array = per_step.get(coord.x, [0, 0, 0, 0])
			if targets.size() < 2:
				row[2] += 1
			else:
				row[0] += 1
				if _alike(tree, targets):
					row[1] += 1
					# 数字が全一致でも、土俵が違えば外周形状/傾斜のケバ/柱の印が
					# 違う絵になる。土俵まで同じものだけが「本当に見分けが付かない」。
					if _same_field(tree, targets):
						row[3] += 1
			per_step[coord.x] = row

	print("# マップの分岐の中身 (%d回の生成, シード0..%d)" % [count, count - 1])
	print("# 数字が全一致＝進める先が全部おなじ(実レベル, 頭数)＝表示される数字が同じ。")
	print("# 土俵まで一致＝そのうえ土俵も同一＝ノードの絵(外周形状・傾斜のケバ・柱)まで同じ。")
	print("")
	print("| 親の段 | 分岐点(2択以上) | 数字が全一致 | 割合 | 土俵まで一致 | 割合 | 1択ノード |")
	print("|---|---|---|---|---|---|---|")
	var steps := per_step.keys()
	steps.sort()
	var total_branch := 0
	var total_alike := 0
	var total_single := 0
	var total_same_field := 0
	for step in steps:
		var row: Array = per_step[step]
		total_branch += row[0]
		total_alike += row[1]
		total_single += row[2]
		total_same_field += row[3]
		print("| 段%d | %d | %d | %s | %d | %s | %d |" % [
			step, row[0], row[1], _pct(row[1], row[0]),
			row[3], _pct(row[3], row[0]), row[2]
		])
	print("| **合計** | %d | %d | %s | %d | %s | %d |" % [
		total_branch, total_alike, _pct(total_alike, total_branch),
		total_same_field, _pct(total_same_field, total_branch), total_single
	])
	print("")
	print("全戦闘ノードの頭数の総和(=報酬の総量): **%d**" % heads)
	quit(0)


## 進める先が全部おなじ(実レベル, 頭数)か。MapTree._targets_are_alike とは別実装で、
## こちらは頭数が2以上で揃っている場合も「見分けが付かない」と数える
## (生成器が手を出さない場合も、遊ぶ側から見れば同じ2択であることに変わりはない)。
func _alike(tree: MapTree, targets: Array[Vector2i]) -> bool:
	var level := -1
	var count := -1
	for t in targets:
		var node: MapTree.MapNode = tree.nodes.get(t)
		if node == null or not node.has_encounter():
			return false
		if level < 0:
			level = node.level()
			count = node.enemy_count()
		elif node.level() != level or node.enemy_count() != count:
			return false
	return level > 0


## 進める先の土俵が全部同一か。土俵が違えばノードの絵(外周形状・傾斜のケバの
## 本数と長さ・柱の印)が違うので、数字が全一致でも見分けは付く。
func _same_field(tree: MapTree, targets: Array[Vector2i]) -> bool:
	var key := ""
	for t in targets:
		var node: MapTree.MapNode = tree.nodes.get(t)
		if node == null or node.field == null:
			return false
		if key.is_empty():
			key = node.field.title_key
		elif node.field.title_key != key:
			return false
	return not key.is_empty()


func _pct(part: int, whole: int) -> String:
	if whole <= 0:
		return "-"
	return "%.1f%%" % (100.0 * float(part) / float(whole))
