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
## intercept(予告を読み切るボット)がパーツを積んで挑んだときの勝率:
## Lv1 95% / Lv2 90% / Lv3 84% / Lv4 74%。
## ボスは段9に到達したラン(生き残って育った個体)のうち 30.5% ±1.6 (n=847)。
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
