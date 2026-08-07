class_name CustomPartCatalog
extends RefCounted

## パーツの一覧と抽選。archive/flask-prototype/custom_part.py の
## CUSTOM_PARTS_DICT と get_random_keys に相当する。
##
## 数値はプロトタイプを出発点にしているだけで、手触りで調整する前提。

## レアリティごとの当たりやすさ。commonはrareの7倍出る(レベル1時)。
## COMMONの重みは固定で、RAREの重みだけ敵レベルで上げる(rare_weight_for_level)。
## レア(強札)が出過ぎる手触りだったのでCOMMON側を重くして全レベルで出現率を下げた。
const WEIGHTS := {
	CustomPart.Rarity.COMMON: 7,
	CustomPart.Rarity.RARE: 1,
}

## RAREの重みを敵レベル(1..5)で増やす。深く進むほどレアが出やすい王道の設計。
## レベル1は重み1(COMMON 7 : RARE 1 ≒ 12.5%)。以降レベルごとに+1し、MAXで頭打ち。
const RARE_WEIGHT_MIN := 1
const RARE_WEIGHT_MAX := 4

## 乱戦(複数体ノード)のRARE重みに掛ける頭数の上限。ロスター最大の3で頭打ち。
## 乱戦は報酬「枚数」が頭数倍になる(MapNode.reward_count)一方で「質」は単体と
## 同じだったため、後半(Lv3+)の乱戦は報酬EVが高くても残機の期待損失が上回る
## 「見えない罠」だった(コールドプレイとjournalの積み残し)。枚数と同じ規則
## 「頭数倍」をレアの出やすさにも掛け、危険な部屋の見返りを質でも釣り合わせる。
const MELEE_RARE_COUNT_MAX := 3


## 敵レベル(1..5)→RAREの抽選重み。範囲外はクランプする。
static func rare_weight_for_level(level: int) -> int:
	return clampi(RARE_WEIGHT_MIN + (level - 1), RARE_WEIGHT_MIN, RARE_WEIGHT_MAX)


## 敵レベルと倒した頭数→RAREの抽選重み。乱戦は頭数を掛けてレアが出やすくなる
## (経緯はMELEE_RARE_COUNT_MAXのコメント参照)。頭数1(単体・省略時)は
## rare_weight_for_levelと厳密に同じ。
static func rare_weight_for(level: int, enemy_count: int = 1) -> int:
	return rare_weight_for_level(level) * clampi(enemy_count, 1, MELEE_RARE_COUNT_MAX)

## 報酬として一度に見せる枚数。画面(Main)もシミュレーション(RunSim)も
## これを参照する。別々に持つと乖離するため。
const REWARD_CHOICES := 3

## RAREを1枚も含まない報酬提示がこの回数だけ続いたら、次の提示でRAREを1枚保証する
## (天井)。
##
## 動機はコールドプレイ(2026-08-04)の一次証拠。段1〜4を勝ち抜いて**5回の提示=15枚**を
## 見たが、RAREは1枚も出ず、素の自機に近いまま段5(Lv3×2体)へ入って4連敗しラン終了。
## 敵の硬さはレベルごとに3〜4倍動く(ThreatMeter参照)のに、こちらの伸びは
## 撃破ボーナス(+1.0/勝)とCOMMON札の小刻みな加算しかなく、**RAREを1枚も引けない
## ランは段3〜5で機構的に詰む**——これはjournalが VICTORY_RPS_GROWTH を入れたときの
## 「引けないランは段3〜5の減衰レースで詰む(段5勝率20.3%が谷)」と同じ穴で、
## あのときは成長の下支えで塞いだが、**札の引き運そのものの分散**は手付かずだった。
##
## 出現率(WEIGHTS/rare_weight_for)は変えない。変えると当たり運の良いランまで
## 一緒に強くなる。天井が狙うのは**下振れの深さ**で、「1枚も見ないままランが
## 終わる」を無くすこと。
##
## 値は計測で決めた(playtest/measure_rare_pity.gd)。連続空振りの分布では初RAREまで
## 平均3.2回なので、4は「大半のランでは一度も発動しない」位置。
##
## **実測では平均も少し上がる**(1500ラン、同一シードのon/off対照): RARE皆無のランは
## 4.0%→1.2% / 2.9%→0.9% と3分の1以下になる一方、クリア率も +2.9pt / +3.6pt 動く。
## 導入時は「平均は上げない」と書いたが、600ランでは差が標準誤差に紛れていただけの
## 誤りだった(journal 2026-08-04 07:06 の訂正)。救済された皆無ランだけでは
## この幅に足りず、道中で空振りが4回続いたラン全般にも1枚ずつ配っているぶんが乗る
## (RARE入り提示は1ランあたり約+0.29回)。目的は達しているので4のまま置くが、
## 平均の押し上げを絞るなら閾値を5〜6へ上げる。
const RARE_PITY_OFFERS := 4


## 提示にRARE(レア)が1枚以上含まれているか。天井の空振り判定の唯一の定義。
##
## nullを弾く防御は**入れない**。提示はpick_choicesが組み立てるので実際にnullは
## 来ないうえ、GDScriptのnullプロパティ参照は関数を中断せずエラーを出して
## nullを返すだけなので、**弾いても弾かなくても戻り値が変わらない**=テストで
## 落とせない分岐になる(サボタージュ検査で素通りした)。落とせない防御は置かない。
static func offer_has_rare(offered: Array[CustomPart]) -> bool:
	for part in offered:
		if part.rarity == CustomPart.Rarity.RARE:
			return true
	return false


## 提示のあとの連続空振り数。RAREが出ていれば0へ戻り、出ていなければ+1。
## 実プレイ(GameState)・シミュレーション(RunSim)・CLI(naive_play)がこの1本を通る。
static func next_rare_drought(drought: int, offered: Array[CustomPart]) -> int:
	if offer_has_rare(offered):
		return 0
	return maxi(drought, 0) + 1


## 天井が発動する空振り数か。thresholdが0以下なら天井そのものを無効にする
## (計測でon/offを並べるため。既定は RARE_PITY_OFFERS)。
static func pity_due(drought: int, threshold: int = RARE_PITY_OFFERS) -> bool:
	return threshold > 0 and drought >= threshold

## 残機が満タン(ランの初期値以上)のときのSET_LIVES札(SPARE_CORE)の抽選重み。
## 保険の価値は残機を失って初めて生まれるのに、無敗のランでも通常のRARE重み
## (レベル・頭数で最大12)で提示枠を占有していた(コールドプレイ: 無敗ランで
## 6回提示・6回見送りが一次証拠。journalでも「無敗ランでは死に枠」が再発)。
## 単純除外はしない——満タンでも5への引き上げは効くので、保険として先取りする
## 自由は最小重みで残す。残機を失った後は通常のRARE重みに戻り、「残機1での
## SPARE_CORE vs SPIN_ENGINE」(journal 2026-07-21)のような選択はそのまま生きる。
const SET_LIVES_FULL_WEIGHT := 1

## SET_LIVES札の「満タン」判定に使うランの初期残機。GameState.MAX_CONTINUESの
## 写し(データ層はGameStateを参照しない約束のため。ズレはテストが照合する)。
const RUN_STARTING_LIVES := 3


## SET_LIVES札(SPARE_CORE)のRARE重み。残機を失っていれば(または負=不明なら)
## 通常のRARE重み(レベル・頭数倍)で、満タンなら最小のSET_LIVES_FULL_WEIGHTへ
## 落とす(経緯はSET_LIVES_FULL_WEIGHTのコメント参照)。
static func set_lives_weight(level: int, enemy_count: int = 1, lives_now: int = -1) -> int:
	if lives_now >= RUN_STARTING_LIVES:
		return SET_LIVES_FULL_WEIGHT
	return rare_weight_for(level, enemy_count)

## 反発の上限。
##
## プロトタイプは2.0だったが、1.0を超えると壁で跳ねるたびに速度が増える。
## 何度も跳ねると幾何級数的に加速し、1ステップで壁の判定(内向きに進んで
## いる間は当たらない)を飛び越えてアリーナの外へ出る。テストプレイの
## 25,000戦で出た脱出は全て反発>1のランだった。1.0なら跳ね返っても
## 速度は増えない。
const RESTITUTION_CAP := 1.0

## 半径の上限。半径を動かす札はGIANT_GROWTHだけなので、実質そちらの重ね上限。
##
## 元は2.0(「アリーナ10x10でこれ以上大きいと避ける余地がない」)で、基礎0.7から
## 5枚ぶん重ねられた。GROWTH_MASS_MULTの調整は**1枚あたりの限界効果**だけを見て
## ×1.15を「中堅COMMON帯」と判定していたが、硬さ(質量×半径²)は半径の2乗で効くので
## 重ねると超線形に伸びる: 1枚で硬さ×1.80、3枚で×5.80、5枚で×16.4。
## measure_parts(Lv3)の実測がそのまま出ている——Δ+1枚は+1.4ptで中堅だが、
## **Δ+3枚は+96.0ptで、次点のOVERENCUMBERED(RARE, +32.5pt)の3倍・
## 3位のDRILL_BIT(+14.0pt)の7倍**。他のCOMMONは+0.4〜+8.6ptに収まる。
## コールドプレイ(2026-08-06 seed=48213)でも、提示された6回すべてで見積もりの
## 伸びが最大でそのまま4枚積み、9戦全勝・残機3を1つも使わずクリアした。
##
## 上限を2枚ぶん(0.7×1.25²=1.094)の直前で止める。OVERENCUMBERED_MASS_CAPが
## 「1〜2枚の最強RAREは維持し、そこから先の複利だけを止める」で決めたのと同じ形で、
## 1枚(直径0.875)の魅力はそのまま、2枚目で頭打ち、3枚目以降は質量ぶんしか伸びない。
## 3枚目からは前サイクルの上限注記(CustomPart.capped_note)が「直径はもう伸びない」を
## 出すので、重ね続ける理由が画面に出た状態で消える。
const RADIUS_CAP := 1.05

## 質量の上限。
const MASS_CAP := 8.0

## Overencumbered(質量アップ)の倍率。質量は与える削り(×倍率)と受ける削り(÷倍率)の
## 両側に効くため、接触トレードは倍率の2乗で動く: ×1.5では1枚でスイング2.25倍になり、
## 単独計測でLv3 +45.9pt/枚(次点RAREのSPIN_ENGINE +13.5の3.4倍)・2枚で勝率6.6%→92.6%の
## 実質勝ち確定札だった。コールドプレイでも「2枚引いたら全戦一発勝利で緊張感ゼロ」を再現。
## ×1.3(スイング1.69倍)に下げた後の単独計測はLv3 +21.5pt/枚・2枚71.0%で、最強RAREの
## 地位は保ちつつ次点(+13.5)と地続きになり、ボス単体を質量だけで溶かす性質
## (Lv5 3枚 +7.6pt)も消えた。1枚のスイング天井(²≦2.0)はテストが照合する。
const OVERENCUMBERED_MASS_MULT := 1.3

## Overencumbered固有の質量上限。全体上限MASS_CAP(8.0)を共有していた頃は6枚まで
## 意味を持ち、質量スタックが支配戦略になっていた: ラン相関で+38ptと次点RARE
## (SPARE_CORE +20pt)の2倍近く、単独計測でも3枚+86pt(journal 2026-07-29)。
## 単発〜2枚の「最強RAREだが地続き」(上の×1.3の経緯)は維持し、基礎質量1.5から
## 2枚分(1.5×1.3²=2.535)でほぼ頭打ちになる2.5で止める。3枚目からは死にカード判定
## (CustomPart.would_change_anything)が自動で提示から外す。GROWTHの質量上限は
## MASS_CAPのまま(あちらは半径経由で寿命に代償を払う複合札で、スタックの主犯では
## ない。ラン相関+0pt)。
const OVERENCUMBERED_MASS_CAP := 2.5

## Giant Growthの倍率。直径だけ(×1.25)だった頃は自然減衰(radius×spin_decay比例)の
## 悪化が上回り、単独計測でLv3 -6.4pt/枚・3枚で-26.9ptと唯一の純マイナス札=罠だった。
## 「大きくなるなら重くもなる」の複合にして、質量の衝突耐性(削りは1/(質量×半径²))で
## 代償を釣り合わせる。質量倍率は計測で決めた: ×1.25は単独でLv3 +15.6pt/枚と
## RARE級の初動になり、ラン全体でもintercept+greedyクリア率76%・random+randomでも
## 64%(勝利成長+1.0が「過剰」と却下された56%超え)までゲームが緩んだ。×1.15で
## 中堅COMMON帯(FULL_STEAM +8.2/RAGE +6.5と同格)に収める。
const GROWTH_RADIUS_MULT := 1.25
const GROWTH_MASS_MULT := 1.15

## 回転数の上限。プロトタイプの min(40.0, ...) に相当。
## 実体は勝利成長と共有するSpinnerStats.RPS_CAP(値の由来もあちらのコメント参照)。
const RPS_CAP := SpinnerStats.RPS_CAP

## Rage Reflectionが1枚あたり上げる壁rps保持量と、その上限。
## wall_keepは非線形で、1.0(完全無損失)付近で無敵化する(計測で+59ptクリア率)。
## 上限0.3では効果が薄く(単発+1pt)、0.5で明確に正になりつつ無敵化は避けられる。
## step0.17・上限0.5で、3枚で壁rps喪失を半減する。
const RAGE_WALL_KEEP_STEP := 0.17
const RAGE_WALL_KEEP_MAX := 0.5

## Full Steam Aheadのspin_decay下限。重ねてもこれ以下には回転減衰を下げない。
## 0.4なら自然減衰は最大でも通常の40%まで（無限に回るのを防ぐ）。
const FULL_STEAM_FLOOR := 0.4

## Full Steam Aheadが1枚あたり上げる与ダメ増強量(edgeへ加算)。上限はEDGE_MAXを
## SHARP_EDGEと共有する。
##
## 摩擦と回転減衰だけの札だった頃、単独計測(measure_parts, intercept, Lv3, 800戦/セル)
## で **3枚積んで+0.4pt** と全11札で最下位だった(次点のLOW_CENTER +0.8pt、
## 中堅のSHARP_EDGE +8.6pt、首位のGIANT_GROWTH +62.9pt)。倍率不足ではなく
## **軸が痩せている**のが理由で、自機のrps喪失は削り71〜83%/壁16〜23%/自然減衰4〜8%
## (playtest/measure_slope_grip)——この札が触る2軸は合わせても喪失の1割に届かない。
## 一次証拠(コールドプレイ 2026-08-07, seed=4821): 段4の報酬が
## LOW_CENTER / SHOCK_ABSORBER / FULL_STEAM の3枚で、**見積もりの4行が動くのは
## SHOCK_ABSORBERだけ**——3択の形をした1択だった。前サイクルのコールドプレイも
## 同じ2枚を「5回提示されて5回とも見送った」と書き残している。
##
## 0.10/枚はSHARP_EDGE(0.20/枚)の半分。攻めの専任札の上位互換にはせず、
## 3枚で+30%と器(EDGE_MAX=0.6)の半分までしか埋めない。器を共有するので
## 「勢い維持＋シャープエッジ」を同時に積んでも与ダメの複利は青天井にならず、
## 上限に達した側は死にカード判定(CustomPart.would_change_anything)と
## 上限到達の注記(PART_CAPPED_NOTE)が自動で拾う。
const MOMENTUM_EDGE_STEP := 0.1

## Shock Absorberが1枚あたり上げる衝突rps保持量(hit_guard)と、その上限。
## 数値は壁版のRAGE(wall_keep 0.17/0.5)に合わせた: 1枚で衝突削り-17%、
## 3枚の上限0.5で削り半減。1.0(削り無効)まで許すと衝突無敵になるので頭打ちにする。
const GUARD_HIT_STEP := 0.17
const GUARD_HIT_MAX := 0.5

## Sharp Edgeが1枚あたり上げる与ダメ増強量(edge)と、その上限。
## 受け側のGUARD(0.17/0.5)と対になる攻め版。+20%/枚・3枚の上限+60%。
## 単独計測(measure_parts, intercept)でLv3 Δ+1が+4.5pt/枚と、SHOCK_ABSORBERが
## 採用された時の+4.7pt/枚と同格の中堅COMMON。上限+60%(3枚+9.8pt)で
## 与ダメの複利が青天井にならないよう頭打ちにする。
const EDGE_STEP := 0.2
const EDGE_MAX := 0.6

## Drill Bit(ドリルビット)が1枚あたり上げる貫通削り量(drill)と、その上限。
## drillは衝突ごとに pierce(自分と同じ硬さの相手への素の削り)×drill を、相手の
## 硬さ(質量×半径²)に関係なく上乗せする。EDGE(乗算強化)は素の削りごと硬さ反比例で
## 痩せるため、edge上限0.60を積んでも巨体への合計削りは細いままで、攻め特化ビルドが
## Lv4〜ボス帯で構造的に詰んでいた(コールドプレイでedge0.60がボスに与0.6/hit vs
## 被1.5/hitで6連敗・戦法4種が同じ内訳に収束、が一次証拠)。柔らかい相手には素の
## 削りが支配的で相対的にほぼ効かないので、序盤の一撃キル速度は歪めない。
## 数値は単独計測(measure_parts)で決めた: 0.5/枚はLv3 +20.5pt/枚・3枚+68.8ptと
## COMMONの枠を大きく超えた(勝ち確定級)ため半分の0.25/枚に下げた。
const DRILL_STEP := 0.25
const DRILL_MAX := 0.75

## Low Center(低重心)が1枚あたり上げる傾斜の効き(slope_grip)と、その上限。
## 壁でのrps喪失はプレイヤーの敗因の約半分を占めるのに(コールドプレイ2026-08-03の
## 決戦4連敗: 壁9.6/15.1/18.5/19.1 対 削り20.5〜30.2、勝った段8でも壁19.6>削り17.1)、
## 壁へ効く札はRAGE(wall_keep)1枚だけで、14回の提示中2回しか出なかった。
## RAGEが「当たった時の代償を軽くする」のに対し、こちらは中心へ引き戻す力を強めて
## 「壁まで届く距離と届いたときの速さ」を削る——壁喪失は進入速度に比例する
## (impact_scaled_wall_damping)ので、同じ壁の軸でも機構が違う。
## 引き換えに縁へ張り付けなくなる(狙った軌道が中央へ引かれる)ので純粋な上位互換に
## ならない。上限は1.9(3枚で頭打ち)。青天井にすると中心に貼り付いて壁に一切
## 触れなくなり、wall_keep=1.0と同じ壊れ方をする。
const GRIP_STEP := 0.4
const GRIP_MAX := 2.2

## Extra Winding(追い巻き)が1枚あたり加算する回転数。上限はRPS_CAP。
## 敵rpsはLv1→5で15→33まで伸びるのに、プレイヤーの回転成長は勝利成長
## (+0.5/+1.0)とRARE札(SPIN_ENGINE ×1.25)の引き運だけで、引けないランは
## Lv4帯(rps26前後)とのプール差が構造的に埋まらない(コールドプレイ2回連続で
## ENEMY_4_3に全戦法敗北・報酬にrps札の提示0回が一次証拠)。COMMONの加算札で
## 確実な底上げの道を作る。+3.0はSPIN_ENGINE(rps20で+5)より弱くRAREの上位互換には
## しない。+2.0で始めたが単独計測Lv3 +4.6pt/枚のCOMMON中堅でも、10枚目の希釈で
## ラン統計が全方針-8pt締まった(random+randomは基準56%を大きく下回る21.3%が出発点で、
## これ以上締める余地がない)ため+3.0(単独計測Lv3 +7.9pt/枚・3枚+26.4pt)に引き上げて
## 相殺した。SPIN_ENGINE(同+9.9pt/枚)未満は維持している。
const SPIN_UP_STEP := 3.0

## ゴースト1枚あたりの無敵秒数。基準は開始後2秒間で、複数取得で線形に延長する
## (2枚=4秒、3枚=6秒…)。無敵時間の知識をここに閉じ込め、画面(Battle)も
## シミュ(RunSim)も同じ値を参照する。
const GHOST_SECONDS_PER_STACK := 2.0


## 報酬は全部プラスにする。マイナスのパーツは置かない。
##
## プロトタイプには Gravity Negator(質量×0.5) と Shrink(直径×0.5) があったが、
## どちらも純粋なデバフだった。衝突で削られるRPSは
## violence×(相手質量×相手速さ)÷(自分質量×自分半径²) なので、質量や半径を
## 下げると被害が増える。特に半径は2乗で効き、Shrinkは耐えられる衝突回数を
## 1/4にする。勝った報酬として3枚見せて、その中に自分を弱くする札が混じって
## いるのは罠でしかないので外した。
##
## 半径と質量には上限がある。デバフを外した以上どのパーツも取るほど強くなる
## 一方なので、上限がないとアリーナ(10x10)をコマが埋め尽くす。
static func all() -> Array[CustomPart]:
	return [
		# Giant Growth: 直径と質量の複合(倍率の経緯はGROWTH_*_MULTのコメント参照)。
		CustomPart.make_growth(2, "PART_GIANT_GROWTH", CustomPart.Rarity.COMMON,
			GROWTH_RADIUS_MULT, RADIUS_CAP, GROWTH_MASS_MULT, MASS_CAP),
		# 質量アップ。倍率の経緯と根拠はOVERENCUMBERED_MASS_MULTのコメント参照。
		# ボスは自滅(spin_decay=0.65)を抑えたぶん削りで倒す設計になっており、greedyの
		# 主火力である質量を削るとボスは硬くなる。uiroの判断でボス難化を許容(残機で
		# 緩和)し、札の突出を抑える方を採った(×1.6→×1.5→×1.3)。
		CustomPart.make(3, "PART_OVERENCUMBERED", CustomPart.Rarity.RARE,
			CustomPart.Stat.MASS, OVERENCUMBERED_MASS_MULT, OVERENCUMBERED_MASS_CAP),
		# Full Steam Ahead: 勢いを保つ札。摩擦(速度減衰)だけを下げていた頃は
		# 戦績がほぼ0の死に札だった(摩擦は勝敗にほとんど効かない)。名前どおり
		# 「勢いを保つ」よう、摩擦と回転減衰率(自然にRPSが落ちる速さ)の両方を
		# 下げるMOMENTUM効果にした。spin_decayの下限FULL_STEAM_FLOORで、重ねても
		# 回転減衰がゼロ(無限に回る)にならないようにする。倍率は計測で調整。
		# それでも最下位の死に札のままだったので、GROWTH(直径→質量)・RAGE(反発→
		# 壁軽減)と同じ複合化で削りの軸(MOMENTUM_EDGE_STEP)を足した——速いまま
		# 当たれば深く削る、という札の見立てそのままの向き。
		CustomPart.make_momentum(5, "PART_FULL_STEAM_AHEAD", CustomPart.Rarity.COMMON,
			0.8, FULL_STEAM_FLOOR, MOMENTUM_EDGE_STEP, EDGE_MAX),
		# Rage Reflection: 反発up(相手を壁へ押し込む攻撃用途・スキル天井)に加え、
		# 自分の壁rps喪失を減らす複合札。反発upだけでは計測で負(跳ね回って壁で
		# rpsを失う)だったので、wall_keepで壁ダメージを減らして確実に正にする。
		CustomPart.make_rage(6, "PART_RAGE_REFLECTION", CustomPart.Rarity.COMMON,
			1.1, RESTITUTION_CAP, RAGE_WALL_KEEP_STEP, RAGE_WALL_KEEP_MAX),
		CustomPart.make(7, "PART_SPIN_ENGINE", CustomPart.Rarity.RARE,
			CustomPart.Stat.RPS, 1.25, RPS_CAP),
		# 残機を5へ引き上げるレア札。コマの性能ではなくコンティニュー回数
		# (GameState.continues_left、初期3)を底上げする。下げはしない(apply_partのmaxi)。
		CustomPart.make_set_lives(8, "PART_SPARE_CORE", CustomPart.Rarity.RARE, 5),
		# ゴースト: 最初の衝突の直後からGHOST_SECONDS_PER_STACK秒だけ敵との衝突を
		# 無効化する(ヒット&ラン)。開始直後を無敵にする旧仕様は自分の初撃まで
		# 消していて、単独計測でLv1 -54.5pt/枚の自傷札だった。
		# ステータスは変えず、重ねて取るほどすり抜け時間が伸びる(線形)。
		CustomPart.make_ghost(9, "PART_GHOST", CustomPart.Rarity.COMMON,
			GHOST_SECONDS_PER_STACK),
		# Shock Absorber: 衝突で受けるrps削りを軽減する純防御札。防御の選択肢が
		# GHOST(時間限定)と質量(RARE)しかなくCOMMONの防御軸が空いていたのと、
		# 7枚プールでは3枚提示の顔ぶれが毎回同じになるため追加(報酬プール拡充)。
		CustomPart.make_guard(10, "PART_SHOCK_ABSORBER", CustomPart.Rarity.COMMON,
			GUARD_HIT_STEP, GUARD_HIT_MAX),
		# Sharp Edge: 衝突で相手に与えるrps削りを増やす攻めのCOMMON札。既存プールは
		# 防御(GUARD/RAGE)・寿命(MOMENTUM)・基礎値(質量/RPS)ばかりで「与える削り」の
		# 軸が空白だった。撃破ボーナス(接触で仕留めた勝利は成長+1.0)と同じ、
		# 当てにいくプレイを装備側から支える札。相手のspin_kickは受けた削り量に
		# 比例するので、壁への弾き飛ばしも強くなる。
		CustomPart.make_edge(11, "PART_SHARP_EDGE", CustomPart.Rarity.COMMON,
			EDGE_STEP, EDGE_MAX),
		# Extra Winding: 回転を+2.0する加算のCOMMON札(経緯はSPIN_UP_STEPのコメント
		# 参照)。回転成長の軸がRARE(SPIN_ENGINE)の引き運に全依存だったのを、
		# COMMONの確実な積み上げで下支えする。
		CustomPart.make_spin_up(12, "PART_EXTRA_WINDING", CustomPart.Rarity.COMMON,
			SPIN_UP_STEP, RPS_CAP),
		# Drill Bit: 相手の硬さに依存しない貫通削りの攻めCOMMON札(経緯はDRILL_STEPの
		# コメント参照)。EDGE(乗算)が巨体で細るのに対し、加算の貫通で対巨体の攻め軸を
		# 埋める。撃破ボーナス・SHARP_EDGE・GHOSTヒット&ランと同じ
		# 「当てにいくプレイを報いる」向き。
		CustomPart.make_drill(13, "PART_DRILL_BIT", CustomPart.Rarity.COMMON,
			DRILL_STEP, DRILL_MAX),
		# Low Center: 土俵の傾斜の効きを上げて中心へ強く引き戻される守りのCOMMON札
		# (経緯はGRIP_STEPのコメント参照)。壁の軸がRAGE1枚しかなく、敗因の半分が
		# 壁なのに対策が引き運任せだったのを、機構の違う2枚目で埋める。
		CustomPart.make_grip(14, "PART_LOW_CENTER", CustomPart.Rarity.COMMON,
			GRIP_STEP, GRIP_MAX),
	]


static func by_id(id: int) -> CustomPart:
	for part in all():
		if part.id == id:
			return part
	return null


## 取得済みIDから、ゴーストの合計無敵秒数(=枚数×1枚あたり秒数)を出す。
## 戦闘のghost_durationはこれで決まる。ゴースト以外のIDは無視する。
static func total_ghost_seconds(ids: Array[int]) -> float:
	var total := 0.0
	for id in ids:
		var part := by_id(id)
		if part != null and part.effect == CustomPart.Effect.GHOST:
			total += part.ghost_seconds
	return total


## 取得済みIDの配列を初出順に集約する。{"part": CustomPart, "count": int} の配列を返す。
## 同じパーツを複数回取っても1エントリにまとめ、countで個数を持たせる。
## UIから切り離した純関数にして、ツリー不要でヘッドレステストできるようにする。
static func aggregate_acquired(ids: Array[int]) -> Array[Dictionary]:
	var order: Array[int] = []          # 初出順を保つ
	var counts: Dictionary = {}          # id -> count
	for id in ids:
		if not counts.has(id):
			order.append(id)
			counts[id] = 0
		counts[id] += 1

	var result: Array[Dictionary] = []
	for id in order:
		var part := by_id(id)
		# 未知IDは無視する（通常起きないが防御的に）。
		if part != null:
			result.append({"part": part, "count": counts[id]})
	return result


## 報酬として見せる候補を重複なしで選ぶ。
##
## プロトタイプはk=3で引き直しては重複が消えるまでやり直していた(しかも
## 引数nを無視して常に3個)。ここは選んだものを母集団から取り除きながら
## 順に引くので、引き直しが要らず個数も指定どおりになる。
## levelは倒した敵のレベル(1..5)。高いほどRAREが出やすい。省略時はレベル1相当
## (現行の重み)で、既存の呼び出し・テストの挙動を保つ。
##
## statsを渡すと死にカード（取っても何も変わらない札。rps上限40での
## SPIN_ENGINEなど。CustomPart.would_change_anything参照）を抽選から外す。
## lives_nowは現在の残機（SET_LIVES札の死に判定と抽選重みに使う。負=不明なら
## 常に有効扱い・通常重み。満タンならSET_LIVES札の重みが最小へ落ちる）。
## 省略時(null)は従来どおり全札から引く。
## rejected_idsは直前の報酬画面で見送った札のID（rejected_ids()で作る）。
## 渡すとその札を今回の提示から外し、同じ顔ぶれが画面をまたいで続くのを防ぐ。
## 取った札はここに入らないので、同じ札を重ねて取る戦略は妨げない。
## enemy_countは倒したノードの頭数。乱戦(2体以上)はRAREの重みが頭数倍になる
## (rare_weight_for参照)。省略時1=単体で従来の抽選と厳密に同じ。
## rare_droughtはRAREを1枚も含まなかった提示が続いた回数(next_rare_droughtで作る)。
## 天井(RARE_PITY_OFFERS)に達していると、抽選結果にRAREが無かった場合だけ1枚を
## 差し替えて保証する。省略時0=天井は発動せず、従来の抽選と厳密に同じ。
static func pick_choices(
	count: int, rng: RandomNumberGenerator = null, level: int = 1,
	stats: SpinnerStats = null, lives_now: int = -1,
	rejected_ids: Array[int] = [], enemy_count: int = 1,
	rare_drought: int = 0
) -> Array[CustomPart]:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var pool := all()
	if stats != null:
		var alive: Array[CustomPart] = []
		for part in pool:
			if part.would_change_anything(stats, lives_now):
				alive.append(part)
		# 全札が死んでいたら安全側で全札に戻す（現行カタログではGHOSTが常に有効
		# なので起きないが、カタログ改変で空提示＝進行不能になるのを防ぐ）。
		if not alive.is_empty():
			pool = alive
	if not rejected_ids.is_empty():
		var fresh: Array[CustomPart] = []
		for part in pool:
			if not rejected_ids.has(part.id):
				fresh.append(part)
		# 見送り札は死にカードと違い、取れば効く。除外すると提示枚数を満たせない
		# ときは枚数を痩せさせず、除外を諦めて再掲する方を取る。
		if fresh.size() >= count:
			pool = fresh
	var chosen: Array[CustomPart] = []
	for i in mini(count, pool.size()):
		var index := _weighted_index(pool, rng, level, enemy_count, lives_now)
		chosen.append(pool[index])
		pool.remove_at(index)
	if pity_due(rare_drought) and not offer_has_rare(chosen):
		_swap_in_rare(chosen, pool, rng, level, enemy_count, lives_now)
	return chosen


## 天井の差し替え。chosenのCOMMON1枚を、母集団の残り(pool)のRARE1枚と入れ替える。
##
## 「1枚足す」ではなく「入れ替える」のは、提示枚数(REWARD_CHOICES)を天井の有無で
## 変えないため。枚数が増えると天井が発動したことが見え、しかも選択肢の広さまで
## 変わってしまう。差し替えなら、見えるのは「レアが1枚混じっている」だけ。
##
## 入れる側は通常の重み(_weight_for)で引く。天井は**RAREが出るかどうか**だけを
## 保証するもので、どのRAREが出るかまで歪めない(満タン時のSPARE_CORE札が
## 最小重みのまま=天井で保険札を掴まされにくい、も保たれる)。
## 抜く側は一様に選ぶ。特定の枠を固定すると、天井のときだけ並びに規則性が出る。
## poolにRAREが1枚も残っていなければ何もしない(死にカード除外で全RAREが消えた等)。
static func _swap_in_rare(
	chosen: Array[CustomPart], pool: Array[CustomPart], rng: RandomNumberGenerator,
	level: int, enemy_count: int, lives_now: int
) -> void:
	var rares: Array[CustomPart] = []
	for part in pool:
		if part.rarity == CustomPart.Rarity.RARE:
			rares.append(part)
	if rares.is_empty() or chosen.is_empty():
		return
	var incoming := rares[_weighted_index(rares, rng, level, enemy_count, lives_now)]
	chosen[rng.randi_range(0, chosen.size() - 1)] = incoming


## 提示(offered)からプレイヤーが選ばなかった札のID＝見送り札を返す。
## 次の報酬画面のpick_choicesにrejected_idsとして渡すと、連続提示を防げる。
static func rejected_ids(offered: Array[CustomPart], picked_id: int) -> Array[int]:
	var out: Array[int] = []
	for part in offered:
		if part.id != picked_id:
			out.append(part.id)
	return out


static func _weight_for(
	part: CustomPart, level: int, enemy_count: int = 1, lives_now: int = -1
) -> int:
	# 残機札だけは現在の残機で重みが変わる(set_lives_weight参照)。
	if part.effect == CustomPart.Effect.SET_LIVES:
		return set_lives_weight(level, enemy_count, lives_now)
	if part.rarity == CustomPart.Rarity.RARE:
		return rare_weight_for(level, enemy_count)
	return WEIGHTS[part.rarity]


static func _weighted_index(
	pool: Array[CustomPart], rng: RandomNumberGenerator, level: int = 1,
	enemy_count: int = 1, lives_now: int = -1
) -> int:
	var total := 0
	for part in pool:
		total += _weight_for(part, level, enemy_count, lives_now)
	var roll := rng.randi_range(0, total - 1)
	for i in pool.size():
		roll -= _weight_for(pool[i], level, enemy_count, lives_now)
		if roll < 0:
			return i
	return pool.size() - 1
