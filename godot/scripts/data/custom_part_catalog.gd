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


## 敵レベル(1..5)→RAREの抽選重み。範囲外はクランプする。
static func rare_weight_for_level(level: int) -> int:
	return clampi(RARE_WEIGHT_MIN + (level - 1), RARE_WEIGHT_MIN, RARE_WEIGHT_MAX)

## 報酬として一度に見せる枚数。画面(Main)もシミュレーション(RunSim)も
## これを参照する。別々に持つと乖離するため。
const REWARD_CHOICES := 3

## 反発の上限。
##
## プロトタイプは2.0だったが、1.0を超えると壁で跳ねるたびに速度が増える。
## 何度も跳ねると幾何級数的に加速し、1ステップで壁の判定(内向きに進んで
## いる間は当たらない)を飛び越えてアリーナの外へ出る。テストプレイの
## 25,000戦で出た脱出は全て反発>1のランだった。1.0なら跳ね返っても
## 速度は増えない。
const RESTITUTION_CAP := 1.0

## 半径の上限。アリーナは10x10でボスの半径が3.0。これ以上大きいと
## 避ける余地がなくなる。
const RADIUS_CAP := 2.0

## 質量の上限。
const MASS_CAP := 8.0

## Overencumbered(質量アップ)の倍率。質量は与える削り(×倍率)と受ける削り(÷倍率)の
## 両側に効くため、接触トレードは倍率の2乗で動く: ×1.5では1枚でスイング2.25倍になり、
## 単独計測でLv3 +45.9pt/枚(次点RAREのSPIN_ENGINE +13.5の3.4倍)・2枚で勝率6.6%→92.6%の
## 実質勝ち確定札だった。コールドプレイでも「2枚引いたら全戦一発勝利で緊張感ゼロ」を再現。
## ×1.3(スイング1.69倍)でRARE帯(SPIN_ENGINE同格)に収める。値の照合はテストの
## 質量倍率天井(倍率²≦2.0)を参照。
const OVERENCUMBERED_MASS_MULT := 1.3

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
		# 緩和)し、札の突出を抑える方を採った(×1.6→×1.5→今回)。
		CustomPart.make(3, "PART_OVERENCUMBERED", CustomPart.Rarity.RARE,
			CustomPart.Stat.MASS, OVERENCUMBERED_MASS_MULT, MASS_CAP),
		# Full Steam Ahead: 勢いを保つ札。摩擦(速度減衰)だけを下げていた頃は
		# 戦績がほぼ0の死に札だった(摩擦は勝敗にほとんど効かない)。名前どおり
		# 「勢いを保つ」よう、摩擦と回転減衰率(自然にRPSが落ちる速さ)の両方を
		# 下げるMOMENTUM効果にした。spin_decayの下限FULL_STEAM_FLOORで、重ねても
		# 回転減衰がゼロ(無限に回る)にならないようにする。倍率は計測で調整。
		CustomPart.make_momentum(5, "PART_FULL_STEAM_AHEAD", CustomPart.Rarity.COMMON,
			0.8, FULL_STEAM_FLOOR),
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
## lives_nowは現在の残機（SET_LIVES札の死に判定に使う。負=不明なら常に有効扱い）。
## 省略時(null)は従来どおり全札から引く。
## rejected_idsは直前の報酬画面で見送った札のID（rejected_ids()で作る）。
## 渡すとその札を今回の提示から外し、同じ顔ぶれが画面をまたいで続くのを防ぐ。
## 取った札はここに入らないので、同じ札を重ねて取る戦略は妨げない。
static func pick_choices(
	count: int, rng: RandomNumberGenerator = null, level: int = 1,
	stats: SpinnerStats = null, lives_now: int = -1,
	rejected_ids: Array[int] = []
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
		var index := _weighted_index(pool, rng, level)
		chosen.append(pool[index])
		pool.remove_at(index)
	return chosen


## 提示(offered)からプレイヤーが選ばなかった札のID＝見送り札を返す。
## 次の報酬画面のpick_choicesにrejected_idsとして渡すと、連続提示を防げる。
static func rejected_ids(offered: Array[CustomPart], picked_id: int) -> Array[int]:
	var out: Array[int] = []
	for part in offered:
		if part.id != picked_id:
			out.append(part.id)
	return out


static func _weight_for(part: CustomPart, level: int) -> int:
	if part.rarity == CustomPart.Rarity.RARE:
		return rare_weight_for_level(level)
	return WEIGHTS[part.rarity]


static func _weighted_index(pool: Array[CustomPart], rng: RandomNumberGenerator, level: int = 1) -> int:
	var total := 0
	for part in pool:
		total += _weight_for(part, level)
	var roll := rng.randi_range(0, total - 1)
	for i in pool.size():
		roll -= _weight_for(pool[i], level)
		if roll < 0:
			return i
	return pool.size() - 1
