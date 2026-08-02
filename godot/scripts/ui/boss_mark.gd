class_name BossMark
extends RefCounted

## 「ここが決戦(段9のボス)だ」の印と、その言い回し。
## Node にもシーンにも乱数にも依存しない純粋関数だけ(cf. scripts/ui/obstacle_marks.gd)。
##
## 動機はコールドプレイの一次証拠。段9まで辿り着いてボスを倒したのに、
## **最後まで「これが決戦だ」と分かる瞬間が一度も無かった**:
##
##   - マップのゴールのノードは、他の戦闘ノードと同じ大きさ・同じ色・同じ輪郭で、
##     レベルの数字が5なだけ。むしろ**報酬ピップが無い唯一のノード**なので、
##     情報量では他より少ない。分岐マップの終着点が、道中のどの部屋よりも地味だった。
##   - 対戦画面も同じで、出る文字は道中と同じ「引っ張って発射!」。1.18秒で決着した
##     ボス戦が、直前の段8の1体戦と見分けが付かなかった。
##
## FieldRoster には既に「決戦の舞台は八角形の闘技場で固定して特別感を出す」という
## 意図が書かれている。ところが同じ八角形は道中の段でも普通に抽選されるので、
## **特別感を出す当てが外れている**。ここはその意図を、抽選ではなく表示で果たす。
##
## 印は星。ノード半径に比例するので、ホバーで膨らんでも縦画面で拡大されても
## 一緒に動く。ノード本体(八角形)の内側に必ず収まるので、既存の表示
## (レベルの数字・敵数ピップ・脅威メーター)と場所を取り合わない。

## 星の先端の数。
const SPIKES := 5

## 先端/谷の半径がノード半径に占める割合。
## 外側は八角形ノードの内接率 cos(PI/8)=0.924 より内側に取る(輪郭を突き破らない)。
const OUTER_SHARE := 0.78
const INNER_SHARE := 0.40


## 段の座標が決戦(ボス)か。段9のゴールだけが真。
static func is_boss(coord: Vector2i) -> bool:
	return coord.x == MapTree.STEP_GOAL


## 星の輪郭の頂点列。先端と谷を交互に並べた 2*SPIKES 個。
## 最初の頂点は真上(-90度)で、以降は時計回りに PI/SPIKES ずつ。
## center/node_radius は描画中のノードのもの(膨らんだ半径をそのまま渡してよい)。
static func points(center: Vector2, node_radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if node_radius <= 0.0:
		return pts
	var outer := node_radius * OUTER_SHARE
	var inner := node_radius * INNER_SHARE
	for i in SPIKES * 2:
		var radius := outer if i % 2 == 0 else inner
		var angle := -PI * 0.5 + PI * float(i) / float(SPIKES)
		pts.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return pts


## 発射前に対戦画面へ出す一言の翻訳キー。決戦だけ言い回しを変える。
## 「今どの部屋に居るか」はマップを閉じた瞬間に消えるので、対戦画面が自分で言う。
static func prompt_key(is_goal_battle: bool) -> String:
	return "BATTLE_FINAL_DRAG_TO_SHOOT" if is_goal_battle else "BATTLE_DRAG_TO_SHOOT"
