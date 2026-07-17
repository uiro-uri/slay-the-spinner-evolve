class_name CustomPartCatalog
extends RefCounted

## パーツの一覧と抽選。archive/flask-prototype/custom_part.py の
## CUSTOM_PARTS_DICT と get_random_keys に相当する。
##
## 数値はプロトタイプを出発点にしているだけで、手触りで調整する前提。

## レアリティごとの当たりやすさ。commonはrareの5倍出る。
const WEIGHTS := {
	CustomPart.Rarity.COMMON: 5,
	CustomPart.Rarity.RARE: 1,
}

## 報酬として一度に見せる枚数。画面(Main)もシミュレーション(RunSim)も
## これを参照する。別々に持つと乖離するため。
const REWARD_CHOICES := 3

## 反発の上限。プロトタイプの min(2.0, ...) に相当。
const RESTITUTION_CAP := 2.0

## 回転数の上限。プロトタイプの min(40.0, ...) に相当。
## 「RPSの最大値を40にし、ゲージに反映」というコミットで決まった値。
const RPS_CAP := 40.0


static func all() -> Array[CustomPart]:
	return [
		CustomPart.make(1, "PART_GRAVITY_NEGATOR", CustomPart.Rarity.COMMON,
			CustomPart.Stat.MASS, 0.5),
		CustomPart.make(2, "PART_GIANT_GROWTH", CustomPart.Rarity.COMMON,
			CustomPart.Stat.RADIUS, 2.0),
		CustomPart.make(3, "PART_OVERENCUMBERED", CustomPart.Rarity.RARE,
			CustomPart.Stat.MASS, 2.0),
		CustomPart.make(4, "PART_SHRINK", CustomPart.Rarity.COMMON,
			CustomPart.Stat.RADIUS, 0.5),
		# プロトタイプはdecayを1へ近づけていたが、simulation.pyのdecayは
		# 「進行方向と逆にかかる減速度」なので、1へ近づけるほど遅くなる。
		# 「Full Steam Ahead(速度減衰を改善)」という名前と逆の効果だった。
		# 使われていないrun_simulationのdecay=0.99引数から見て、昔は
		# vel *= decay (大きいほど良い)で、定数減速に変えた際にパーツ側の
		# 意味が取り残されたと思われる。名前どおり速くなるよう摩擦を減らす。
		CustomPart.make(5, "PART_FULL_STEAM_AHEAD", CustomPart.Rarity.COMMON,
			CustomPart.Stat.FRICTION, 0.9),
		CustomPart.make(6, "PART_RAGE_REFLECTION", CustomPart.Rarity.COMMON,
			CustomPart.Stat.RESTITUTION, 1.1, RESTITUTION_CAP),
		CustomPart.make(7, "PART_SPIN_ENGINE", CustomPart.Rarity.RARE,
			CustomPart.Stat.RPS, 1.2, RPS_CAP),
	]


static func by_id(id: int) -> CustomPart:
	for part in all():
		if part.id == id:
			return part
	return null


## 報酬として見せる候補を重複なしで選ぶ。
##
## プロトタイプはk=3で引き直しては重複が消えるまでやり直していた(しかも
## 引数nを無視して常に3個)。ここは選んだものを母集団から取り除きながら
## 順に引くので、引き直しが要らず個数も指定どおりになる。
static func pick_choices(count: int, rng: RandomNumberGenerator = null) -> Array[CustomPart]:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var pool := all()
	var chosen: Array[CustomPart] = []
	for i in mini(count, pool.size()):
		var index := _weighted_index(pool, rng)
		chosen.append(pool[index])
		pool.remove_at(index)
	return chosen


static func _weighted_index(pool: Array[CustomPart], rng: RandomNumberGenerator) -> int:
	var total := 0
	for part in pool:
		total += WEIGHTS[part.rarity]
	var roll := rng.randi_range(0, total - 1)
	for i in pool.size():
		roll -= WEIGHTS[pool[i].rarity]
		if roll < 0:
			return i
	return pool.size() - 1
