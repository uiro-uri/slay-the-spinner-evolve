class_name NextFieldList
extends RefCounted

## マップの「進める先」パネル。**今いるノードから進める先の土俵**を、
## 向き(左下/真下/右下)付きで並べる。行の中身は対戦画面と同じ FieldFlavor.line。
##
## 動機はコールドプレイの一次証拠。2026-08-06 のサイクルで土俵の名前と性格を
## **対戦画面に**出したが、そのサイクル自身が「マップ側にはまだ名前が出ない。
## **決めるのは進む先を選ぶ瞬間なので、本当はそこに要る**」を宿題に残していた。
## 2026-08-07 の初見プレイで正面から踏んだ:
## 段3の2択が Lv2・2体・報酬2枚・レア×2 と**表示されるすべての軸で同値**で、
## 違いは土俵(PILLARS と BOWL)だけだった。ところがマップに名前が無いので
## 「柱がある」と分かるのは**入場して戦闘画面に出てから**——つまり引き返せなく
## なってから。journal の実測では PILLARS の Lv2 勝率は 73.5%、他の土俵は 95〜97%。
## 20ポイントの決断がコイントスとして提示されていたことになる。
##
## マップは既に外周の形・ケバ・柱の紫を絵で描き分けている。足りないのは
## **その絵の呼び名**なので、絵を増やすのではなく名前を添える。
##
## ノードの脇には置けない。列の間隔は CELL.x=64px しかなく、上下は報酬ピップ・
## 敵数ピップ・脅威メーターで既に埋まっている(「八角形の闘技場」は font 10 でも
## 70px ある)。ホバーの吹き出しにもできない——縦画面(スマホ)にホバーが無く、
## タップは即入場なので、SPだけ名前が出ないことになる。そこで**左の列に
## 常設のパネル**として置く: 向きで各行がどのノードの話か決まるので位置に
## 頼らず、ホバーもタップも要らず、縦横どちらのレイアウトでも同じに出る。
##
## Node にもシーンにも autoload にも依存しない(MapScreen 自身が
## GameState を見ないのと同じ理由。ヘッドレステストから直接呼べる)。

## 向きの訳キー。左下/真下/右下＝画面上の左下/真下/右下そのもの
## (MapScreen._to_pixel は列が大きいほど右へ置くので、列-1 が画面の左)。
const DIR_LEFT := "MAP_NEXT_LEFT"
const DIR_STRAIGHT := "MAP_NEXT_STRAIGHT"
const DIR_RIGHT := "MAP_NEXT_RIGHT"

## 1行の書式キーと見出しキー。
const ROW_FORMAT := "MAP_NEXT_ROW"
const HEADING := "MAP_NEXT_HEADING"

## 行のフォントサイズ。実UIとテストで同じ値を使う(テストだけ別の大きさで
## 測ると、枠に収まるかの検査が実物と無関係になる)。
const ROW_FONT_SIZE := 13

## 行に使える幅(px)。左パネルは tscn で幅300、PanelContainer の既定余白ぶんを引く。
const ROW_WIDTH := 280.0

## 折り返して許す行数。3件×この行数がパネルの高さの上限になる。
## 超える文言を足すと左の列が下へ溢れるので、テストがここで止める。
const MAX_LINES := 2


## 向きの訳キー。current から target への列の差で決まる。
## 隣接していない座標(想定外)は空文字を返し、呼び手は行ごと落とす。
static func direction_key(current: Vector2i, target: Vector2i) -> String:
	match target.y - current.y:
		-1:
			return DIR_LEFT
		0:
			return DIR_STRAIGHT
		1:
			return DIR_RIGHT
		_:
			return ""


## 進める先の一覧。左の列から右の列の順＝画面に並ぶ順。
## 各要素は {coord, direction_key, line}。土俵の無いノードは行にしない
## (FieldFlavor.line が空を返す＝名前の分からない土俵の説明になってしまう)。
static func rows(tree: MapTree) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if tree == null:
		return out
	var coords := tree.next_coords()
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y)
	for coord in coords:
		if not tree.nodes.has(coord):
			continue
		var node: MapTree.MapNode = tree.nodes[coord]
		var line := FieldFlavor.line(node.field)
		if line == "":
			continue
		var dir := direction_key(tree.current_coord, coord)
		if dir == "":
			continue
		out.append({"coord": coord, "direction_key": dir, "line": line})
	return out


## 1行の表示テキスト。静的関数からは tr() を呼べないので TranslationServer で引く
## (FieldFlavor と同じ)。line は既に訳済みなのでそのまま差し込む。
static func row_text(row: Dictionary) -> String:
	return TranslationServer.translate(ROW_FORMAT).format([
		TranslationServer.translate(row.get("direction_key", "")),
		row.get("line", ""),
	])


## container に行を積み直して、積んだ行数を返す。0 なら呼び手はパネルごと隠す。
## 組み立てを MapScreen の中に書かないのは AcquiredUpgradeList と同じ理由で、
## ヘッドレステストから「何行できるか・何が書いてあるか」を直接見るため。
static func populate(container: VBoxContainer, tree: MapTree) -> int:
	if container == null:
		return 0
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

	var list := rows(tree)
	for row in list:
		var label := Label.new()
		label.text = row_text(row)
		label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
		# 幅は固定で、長い文言は折り返す(横へ溢れて左パネルの外に出ない)。
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(ROW_WIDTH, 0)
		container.add_child(label)
	return list.size()
