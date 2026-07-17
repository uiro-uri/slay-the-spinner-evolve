class_name EnemyRoster
extends RefCounted

## 敵の一覧と、どの段でどのレベルが出るか。
## archive/flask-prototype/enemy.py の ENEMY_LIST と get_random_enemy に相当する。
##
## 数値はプロトタイプを出発点にしているだけで、手触りで調整する前提。


## 段(1..9)に対する敵レベル(1..5)。ゴール(段9)がレベル5のボスになる。
## プロトタイプに「エネミーが強くなる周期が変だったので修正（ボスがレベル5に
## なるようにしたい）」というコミットがあり、この式に落ち着いている。
static func level_for_step(step: int) -> int:
	return clampi((step + 1) / 2, 1, 5)


## 数値はテストプレイ(scripts/playtest.sh)で当てたもの。プロトタイプの表は
## 使っていない。あちらは段9のボスが 質量5.0/半径3.0/rps60 で、パーツを8枚
## 積んだプレイヤーでも勝率0%だった(25,000戦で勝利ゼロ)。
##
## この2つが勝敗をほぼ決めるので、そこを見て決めている:
##  - **寿命 = rps ÷ 半径**。自然減衰が半径に比例するため。殴られなくても
##    ここで力尽きる。プロトタイプの敵は寿命20〜30秒で、プレイヤー(強化後で
##    9秒前後)が待つだけで負けていた。
##  - **硬さ = 質量 × 半径²**。1衝突で削られるRPSがこれに反比例する。
##    プロトタイプのボスは45、プレイヤーは0.4しかなく、接触即死だった。
##
## 質量と半径は見た目の個性(小さくて素早い/大きくて重い)として先に決め、
## rpsを難易度のつまみにしている。段9に着くまで8戦あるので、序盤を緩くしないと
## 誰もボスに辿り着かない。同レベルの2体は同じ強さで、形だけ違う。
##
## intercept(予告を読み切るボット)がパーツを積んで挑んだときの、段ごとの勝率:
## 段1〜8は85〜91%、ボス(段9)は到達したラン(生き残って育った個体)のうち
## 34.4% ±2.8 (n=1072)。
##
## この数字は乱戦(pick_group_for_step)とフィールド変化(FieldRoster)が入った後の
## 再実測。調整当時は単体・矩形すり鉢だけで30.5%だったが、土俵が変わるだけで
## 数pt動く。敵の値をいじったら scripts/playtest.sh で測り直すこと。
static func all() -> Array[EnemyData]:
	return [
		# 小さくて素早い。ほぼ負けない導入。
		_enemy(1, "ENEMY_1_1", 6.0, 0.8, 0.5, 0.97, 1.0, 32.0),
		_enemy(1, "ENEMY_1_2", 6.5, 0.7, 0.55, 0.98, 1.0, 30.0),
		_enemy(2, "ENEMY_2_1", 7.0, 1.2, 0.8, 0.97, 1.0, 18.5),
		_enemy(2, "ENEMY_2_2", 7.5, 1.1, 0.85, 0.98, 1.0, 18.0),
		_enemy(3, "ENEMY_3_1", 8.0, 2.0, 1.2, 0.98, 1.0, 10.5),
		_enemy(3, "ENEMY_3_2", 8.5, 1.8, 1.25, 0.985, 1.0, 10.5),
		_enemy(4, "ENEMY_4_1", 9.0, 3.0, 1.6, 0.98, 1.0, 10.5),
		_enemy(4, "ENEMY_4_2", 9.5, 2.8, 1.7, 0.985, 1.0, 10.5),
		# ボス。大きく重く、寿命も硬さもプレイヤーを上回る。
		_enemy(5, "ENEMY_5_1", 11.0, 4.5, 2.4, 0.98, 1.0, 26.0),
	]


static func of_level(level: int) -> Array[EnemyData]:
	var result: Array[EnemyData] = []
	for enemy in all():
		if enemy.level == level:
			result.append(enemy)
	return result


## その段にふさわしい敵を1体選ぶ。
static func pick_for_step(step: int, rng: RandomNumberGenerator = null) -> EnemyData:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var candidates := of_level(level_for_step(step))
	if candidates.is_empty():
		push_error("EnemyRoster: 段%dに出せる敵がいない" % step)
		return null
	return candidates[rng.randi_range(0, candidates.size() - 1)]


## その段の出現グループ(1〜3体)を選ぶ。乱戦パターンの入り口。
##
## ほとんどは1体。たまに2〜3体の乱戦になる。複数体のときは1段下のレベルから
## 選び、各体のrpsを頭数で割って弱める(総回転量を一定に保ち、雑に公平にする)。
## ボス(レベル5)は演出上つねに単体。
##
## rpsを割るのは共有Resourceの複製に対して行う。all()/of_level()は同じ
## EnemyData/SpinnerStatsの実体を返すので、直接書き換えると後続の抽選や
## 他の戦闘まで巻き添えで壊れる。_scaled()が必ず複製を作る。
static func pick_group_for_step(step: int, rng: RandomNumberGenerator = null) -> Array[EnemyData]:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	# ボスは単体固定。
	if level_for_step(step) >= 5:
		return [pick_for_step(step, rng)]

	# 頭数を重み付きで決める。大半は1体、たまに2〜3体。
	var roll := rng.randf()
	var count := 1
	if roll > 0.9:
		count = 3
	elif roll > 0.6:
		count = 2

	if count == 1:
		return [pick_for_step(step, rng)]

	# 複数体は1段下から選び、各体を頭数ぶん弱める。
	var member_level := maxi(level_for_step(step) - 1, 1)
	var candidates := of_level(member_level)
	if candidates.is_empty():
		return [pick_for_step(step, rng)]
	var group: Array[EnemyData] = []
	for _i in count:
		var base := candidates[rng.randi_range(0, candidates.size() - 1)]
		group.append(_scaled(base, 1.0 / float(count)))
	return group


## 元のEnemyDataを、rpsだけを factor 倍にした複製にする。共有Resourceを
## 壊さないよう stats を複製してから書き換える。
static func _scaled(enemy: EnemyData, factor: float) -> EnemyData:
	var stats := enemy.stats.duplicate_stats()
	stats.rps *= factor
	return EnemyData.make(enemy.level, enemy.display_name, enemy.launch_speed, stats)


static func _enemy(
	level: int, name_: String, launch_speed: float,
	mass: float, radius: float, friction: float, restitution: float, rps: float
) -> EnemyData:
	var stats := SpinnerStats.new()
	stats.mass = mass
	stats.radius = radius
	stats.friction = friction
	stats.restitution = restitution
	stats.rps = rps
	return EnemyData.make(level, name_, launch_speed, stats)
