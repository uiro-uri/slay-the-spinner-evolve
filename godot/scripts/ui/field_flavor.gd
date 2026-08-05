class_name FieldFlavor
extends RefCounted

## 土俵(FieldData)を「名前 — 性格」の1行にする純粋な静的関数。Nodeにもシーンにも
## 依存しない(RpsLossText/StageSlopeMark と同じ流儀)。
##
## 土俵には `title_key` があり `strings.csv` に和英の名前も入っているのに、
## **ゲーム内のどこにも出ていなかった**——出ていたのは playtest CLI とテストだけ。
## マップは外周の形(ノードの輪郭)・傾斜の急さ(ケバ)・柱(紫の印)を絵で描き分けて
## いるが、その絵に名前が付いていないので**符丁を覚えようがない**。
## 2026-08-06 のコールドプレイでは6つの土俵で戦ったのに、最後まで
## 「今どこで戦っているか」を言葉にできなかった(残機3のうち2つを落としたのが
## どちらも柱の土俵だったことに、リザルトの土俵名が無いので気付けない)。
##
## 名前だけでは足りない。**傾斜は絵で最も読みにくい性質**で、等高線の本数を数える
## までCLASSIC(4.9)とBOWL(8.0)の違いが分からない。そこで名前に「性格」を1つ添える。
##
## 性格は FieldData の数値から**導く**(手書きの固定文をフィールドごとに持たせない)。
## 傾斜や柱は手触りで調整する前提の@exportなので、固定文にすると調整した瞬間に
## 説明だけが古くなって嘘になる。導出なら数値を変えれば文も追従する。
##
## 静的関数からは tr() を呼べないので TranslationServer で引く(RpsLossText と同じ)。

## 「深いすり鉢」と呼ぶ傾斜の強さ。ロスターの標準(CLASSIC/ARENA=4.9)と
## 深いすり鉢(BOWL=8.0)の間に置く。ここを跨いだ土俵だけが STEEP を名乗る。
const STEEP_STRENGTH := 6.5

## 性格の訳キー。優先順は trait_key の順。
const TRAIT_PILLARS := "FIELD_TRAIT_PILLARS"
const TRAIT_CONE := "FIELD_TRAIT_CONE"
const TRAIT_OCTAGON := "FIELD_TRAIT_OCTAGON"
const TRAIT_ROUND := "FIELD_TRAIT_ROUND"
const TRAIT_STEEP := "FIELD_TRAIT_STEEP"
const TRAIT_PLAIN := "FIELD_TRAIT_PLAIN"


## この土俵を一番よく言い表す性格の訳キー。**1つだけ**選ぶ。
##
## 順番は「見えないもの・効くものが先」ではなく「その土俵をその土俵たらしめる
## ものが先」で並べる。柱は他のどの土俵にも無い唯一の中身なので最優先、
## 次が傾斜の形(すり鉢か一定か＝縁で粘れるかどうかが変わる)、次が外周の形、
## 最後に傾斜の強さ。外周が矩形で柱の無い土俵だけが強さで名乗り分けるので、
## ロスターの CLASSIC(4.9)と BOWL(8.0)がちょうど PLAIN と STEEP に割れる。
static func trait_key(field: FieldData) -> String:
	if field == null:
		return ""
	if not field.obstacles.is_empty():
		return TRAIT_PILLARS
	if field.stage_shape == SpinnerPhysics.StageShape.CONE:
		return TRAIT_CONE
	if field.wall_shape == ArenaWall.WallShape.OCTAGON:
		return TRAIT_OCTAGON
	if field.wall_shape == ArenaWall.WallShape.ROUND:
		return TRAIT_ROUND
	if field.stage_strength >= STEEP_STRENGTH:
		return TRAIT_STEEP
	return TRAIT_PLAIN


## 対戦画面に出す1行。土俵が無い/名前が無いときは空文字を返し、呼び手は非表示にする。
##
## 名前の無い土俵は Battle.tscn を単体で起動したとき(FieldData.make("", ...))に出る。
## そこで性格だけ出すと「名前の分からない土俵の説明」という読めない行になるので、
## 行ごと出さない(RpsLossText が旧結果で行ごと落とすのと同じ判断)。
static func line(field: FieldData) -> String:
	if field == null or field.title_key == "":
		return ""
	var trait_id := trait_key(field)
	if trait_id == "":
		return ""
	return TranslationServer.translate("BATTLE_FIELD_LINE").format([
		TranslationServer.translate(field.title_key),
		TranslationServer.translate(trait_id),
	])
