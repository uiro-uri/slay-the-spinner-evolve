class_name CustomPartCatalog
extends RefCounted

## パーツの一覧と抽選。archive/flask-prototype/custom_part.py の
## CUSTOM_PARTS_DICT と get_random_keys に相当する。
##
## 数値はプロトタイプを出発点にしているだけで、手触りで調整する前提。

## レアリティごとの当たりやすさ。commonはrareの5倍出る(レベル1時)。
## COMMONの重みは固定で、RAREの重みだけ敵レベルで上げる(rare_weight_for_level)。
const WEIGHTS := {
	CustomPart.Rarity.COMMON: 5,
	CustomPart.Rarity.RARE: 1,
}

## RAREの重みを敵レベル(1..5)で増やす。深く進むほどレアが出やすい王道の設計。
## レベル1は現行どおり重み1(COMMON 5 : RARE 1)。以降レベルごとに+1し、MAXで頭打ち。
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

## 回転数の上限。プロトタイプの min(40.0, ...) に相当。
## 「RPSの最大値を40にし、ゲージに反映」というコミットで決まった値。
const RPS_CAP := 40.0

## Rage Reflectionが1枚あたり上げる壁rps保持量。0.34なら3枚で壁ほぼ無損失。
## 反発up単独は計測で正になりにくいので、こちら側で確実に正へ持っていく。
const RAGE_WALL_KEEP_STEP := 0.34

## Full Steam Aheadのspin_decay下限。重ねてもこれ以下には回転減衰を下げない。
## 0.4なら自然減衰は最大でも通常の40%まで（無限に回るのを防ぐ）。
const FULL_STEAM_FLOOR := 0.4

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
		CustomPart.make(2, "PART_GIANT_GROWTH", CustomPart.Rarity.COMMON,
			CustomPart.Stat.RADIUS, 1.25, RADIUS_CAP),
		# 最強札だったので×1.6→×1.5に微減(ボスは削りで倒す設計は維持)。
		CustomPart.make(3, "PART_OVERENCUMBERED", CustomPart.Rarity.RARE,
			CustomPart.Stat.MASS, 1.5, MASS_CAP),
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
			1.1, RESTITUTION_CAP, RAGE_WALL_KEEP_STEP),
		CustomPart.make(7, "PART_SPIN_ENGINE", CustomPart.Rarity.RARE,
			CustomPart.Stat.RPS, 1.25, RPS_CAP),
		# 残機を5へ引き上げるレア札。コマの性能ではなくコンティニュー回数
		# (GameState.continues_left、初期3)を底上げする。下げはしない(apply_partのmaxi)。
		CustomPart.make_set_lives(8, "PART_SPARE_CORE", CustomPart.Rarity.RARE, 5),
		# ゴースト: 開始後GHOST_SECONDS_PER_STACK秒だけ敵との衝突を無効化する。
		# ステータスは変えず、重ねて取るほど無敵時間が伸びる(線形)。
		CustomPart.make_ghost(9, "PART_GHOST", CustomPart.Rarity.COMMON,
			GHOST_SECONDS_PER_STACK),
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
static func pick_choices(count: int, rng: RandomNumberGenerator = null, level: int = 1) -> Array[CustomPart]:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var pool := all()
	var chosen: Array[CustomPart] = []
	for i in mini(count, pool.size()):
		var index := _weighted_index(pool, rng, level)
		chosen.append(pool[index])
		pool.remove_at(index)
	return chosen


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
