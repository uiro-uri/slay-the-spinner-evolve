class_name RewardQuality
extends RefCounted

## マップのノードに出す「この部屋の報酬は“質”も上がっているか」の表示。
## Node にもシーンにも乱数にも依存しない純粋関数だけ(cf. scripts/ui/threat_meter.gd)。
##
## 動機はコールドプレイ(2026-08-04)の一次証拠。段2の分岐は
## `Lv2[1体] → 報酬1枚` と `Lv1[1体] → 報酬1枚` の二択で、**格上の部屋を選ぶ
## 理由が画面のどこにも無かった**(硬さ取り分メーターは「格上」とだけ言う=損の側)。
## 実際には斥候(次レベルの単体エリート)を倒すと RARE の抽選重みが実レベル準拠で
## 上がる(CustomPartCatalog.rare_weight_for、段2の斥候なら2倍)。
## **見返りの半分が実装されているのに画面に出ていない**ので、斥候は設計意図
## (EnemyRoster.is_vanguard_step の「見て避けられる選べるリスク」)どおりに
## 機能しておらず、ただの罠部屋に見える。
##
## 乱戦(複数体)も同じ規則で質が上がる(重みが頭数倍)が、こちらは**枚数**が
## 報酬ピップの数で見えているぶんまだリターンが読めた。質の側はどちらも不可視。
##
## 統計の裏付け(scripts/playtest.sh、ラン1200): クリア率は発射方針の差(intercept
## 51.3% 対 random 40.3% ＝11pt)より**報酬方針の差(greedy 51.3% 対 random 16.0%
## ＝35pt)の方がはるかに大きい**。プレイヤーが一番判断したいのは報酬の中身で、
## 部屋選びはその入口にある。
##
## 表示するのは**重みの倍率**であって確率の倍率ではない。RARE の重みが2倍でも
## COMMON側の重みは動かないので、当選確率は2倍より小さくなる(逓減する)。
## それでも倍率で出すのは、比べたいのが「隣の部屋より濃いかどうか」だからで、
## 既に CLI が乱戦に出していた `レア出やすさ×頭数` と同じ流儀に揃えてある。

## 倍率の表示上限。現状の最大は3体乱戦の×3(頭数の上限 MELEE_RARE_COUNT_MAX が3)。
## 色の振り切りをここに合わせる。
const RATIO_FULL := 3.0

## 振り切ったピップが金からどれだけ白へ寄るか。1.0(純白)まで行くと金色の
## 語彙(レア報酬カードの地＝Palette.GOLD_CARD)から離れてしまうので途中で止める。
## 0.8は「一番多い×2の部屋(斥候・2体乱戦)でも隣の基準の部屋と並べて差が読める」
## ところ: ffcc00 が ×2 で ffe066、×3 で ffe9cc と、青成分だけが段階的に増える。
const HIGHLIGHT_MAX := 0.8


## この部屋の RARE 抽選重みが、同じ段の基準の部屋(その段のレベル・単体)の何倍か。
##
## 定義は CustomPartCatalog.rare_weight_for をそのまま割る。倍率の定義がここと
## カタログの2箇所にあると、表示と実際の抽選がずれる(テストが同値を照合する)。
##
## 0除算のガードは**置かない**。分母の rare_weight_for は
## rare_weight_for_level が RARE_WEIGHT_MIN(=1) でクランプしているので、
## どんな引数でも1以上になる(レベル0や負でも)。実際には落ちない防御を置くと
## テストで落とせない分岐が増えるだけ。
static func weight_ratio(level: int, enemy_count: int, base_level: int) -> float:
	var base := CustomPartCatalog.rare_weight_for(base_level, 1)
	return float(CustomPartCatalog.rare_weight_for(level, enemy_count)) / float(base)


## マップのノード1つぶんの倍率。段の基準レベルは EnemyRoster.level_for_step で、
## ノードの実レベル(斥候なら段より上)は MapNode.level で決まる。
##
## 報酬の無いノード(ゴール＝ボス)を弾く分岐は**置かない**。ボスは段9の基準レベル
## そのものの単体なので、素直に計算しても1.0になる(＝分岐しても戻り値が変わらず、
## テストで落とせない防御になる)。nullだけは実際に落ちるので弾く。
static func ratio_for_node(node: MapTree.MapNode) -> float:
	if node == null:
		return 1.0
	return weight_ratio(
		node.level(), node.enemy_count(), EnemyRoster.level_for_step(node.coord.x)
	)


## 報酬ピップの色。倍率1.0(＝その段の基準の部屋)では plain をそのまま返す
## ——既存のノードの見た目は1ドットも変えない。質が上がっているぶんだけ白へ寄せて
## 明るくする(暗いマップの上では輝度が上がるほど目立つので、SPでの視認性も
## 落ちない向き)。
static func pip_color(plain: Color, ratio: float) -> Color:
	return plain.lerp(Color.WHITE, HIGHLIGHT_MAX * highlight(ratio))


## 倍率 → 強調の度合い(0〜1)。基準で0、表示上限 RATIO_FULL で1。
## 範囲外(1未満・上限超え)は端で頭打ちにする。
static func highlight(ratio: float) -> float:
	return clampf((ratio - 1.0) / (RATIO_FULL - 1.0), 0.0, 1.0)
