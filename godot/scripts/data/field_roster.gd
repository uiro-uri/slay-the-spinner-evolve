class_name FieldRoster
extends RefCounted

## 土俵(フィールド)の一覧と抽選。EnemyRosterに倣う。
##
## どのフィールドもどの段でも成立するので、段によらず一様ランダムで選ぶ。
## nullを返さないので進行が止まらない（EnemyRosterのテストと同じ保証）。
##
## 数値は手触りで調整する前提。壁の形・傾斜・障害物を組み合わせて、
## 各戦闘の土俵に個性を出す。
##
## **柱の本数だけは段で変わる**(step_field)。表の設計値はそのまま残し、抽選時に
## 間引く——EnemyRoster の SIZE_SCALE / step_member と同じ方式。

const _BOUNDS := Rect2(0, 0, 10, 10)

## 決戦専用の土俵の一辺。道中の10より広い。
##
## ボスは全敵で最も大きい(半径1.91)のに、決戦の土俵は八角形＝全土俵で最も内接半径が
## 小さい(4.62)ままだった。「中心のボスに触れずにいられる隙間」
## (内接半径 − ボス半径 − 自機半径)は道中が段1〜8で3.01〜3.83あるのに、決戦だけ2.01と
## 3分の2に落ちる。結果、決戦は発射直後から密着が切れず、被弾/秒が道中の倍近くになって
## 「何が起きたか分からないうちに終わる」戦闘になっていた(段別の被弾/秒 中央値は
## 段8が1.42に対し段9が2.34)。
##
## 12にすると隙間が3.04＝道中の最小値(段7・段8の3.01)と並ぶ。ボスの数値は動かさない:
## 硬さ・寿命・接触トレードはtests/test_enemy_roster.gdの不変条件が縛っており、
## ここで直したいのは強さではなく間合いの方だから。
## 広さを変えたら scripts/playtest.sh と playtest/measure_boss_arena.gd で測り直すこと。
const BOSS_ARENA_SIDE := 12.0


static func all() -> Array[FieldData]:
	return [
		# 現状同等の安全な既定。すり鉢の標準的な土俵。
		FieldData.make(
			"FIELD_CLASSIC", _BOUNDS, ArenaWall.WallShape.RECT,
			SpinnerPhysics.StageShape.DISH, 4.9),
		# 急なすり鉢。中央へ素早く戻される。
		FieldData.make(
			"FIELD_BOWL", _BOUNDS, ArenaWall.WallShape.RECT,
			SpinnerPhysics.StageShape.DISH, 8.0),
		# 浅い一定傾斜の皿。端で粘りやすい。
		FieldData.make(
			"FIELD_PLATE", _BOUNDS, ArenaWall.WallShape.RECT,
			SpinnerPhysics.StageShape.CONE, 3.0),
		# 八角形の闘技場。
		FieldData.make(
			"FIELD_ARENA", _BOUNDS, ArenaWall.WallShape.OCTAGON,
			SpinnerPhysics.StageShape.DISH, 4.9),
		# 円形の土俵。
		FieldData.make(
			"FIELD_ROUND", _BOUNDS, ArenaWall.WallShape.ROUND,
			SpinnerPhysics.StageShape.DISH, 6.0),
		# 障害物あり。柱は中心・出現リングを避けて配置する。
		FieldData.make(
			"FIELD_PILLARS", _BOUNDS, ArenaWall.WallShape.RECT,
			SpinnerPhysics.StageShape.DISH, 4.9,
			[Vector3(3, 3, 0.6), Vector3(7, 7, 0.6)]),
	]


## 柱が**表の本数ぶん全部立つ**敵レベル。これ未満の段では1本だけになる。
##
## **動機: 柱の難度が段に対して無補正だった**。FIELD_PILLARS は形も傾斜も
## FIELD_CLASSIC と同一で、違いは柱2本だけ。その2本が全段で同じ強さのまま
## 一様抽選されるので、段1で引くと段7で引くのと同じ重さがそのまま乗る。
##
## 2026-08-10 のコールドプレイの一次証拠: 段1(FIELD_PILLARS, Lv2単体)がこのランで
## 唯一の道中の死だった。ボット計測(playtest/measure_obstacle_layout.gd)でも
## **柱2本は Lv1 で -2pt・Lv2 で -21pt**(94.8%→73.4%)動かす。他の土俵は
## 傾斜と形の違いで Lv2 85.8〜94.5% に収まっており、柱だけが帯の外に落ちている
## ——report.md が「土俵は一様抽選なのでどれも同じくらいの勝率になるはず」と
## 書いている不変条件の唯一の破れ。
##
## **効いているのは柱の太さではなく本数と位置**。同スクリプトの計測(各800戦、Lv2):
##
##   柱なし         94.8%   壁ヒット1.03回   自機の喪失に占める壁 18%
##   2本 半径0.12   77.4%   壁2.34回   36%   ← 半径を5分の1にしても4ptしか戻らない
##   2本 半径0.30   76.4%   壁2.42回   40%
##   2本 半径0.60   73.4%   壁2.97回   46%   ← 現行
##   1本 半径0.60   80.5%   壁2.03回   33%   ← 本数を半分にすると7pt戻る
##   1本 半径0.30   84.9%   壁1.71回   29%
##
## 半径をいくら細らせても「柱が有る／無い」の崖(21pt)はほとんど埋まらない。1接触の
## 喪失が柱の大きさに依らないうえ、当たり判定は自機半径0.7との和なので、半径0.6→0.12は
## 塞ぐ円を1.30→0.82にしか縮めないため。**位置**も強い軸(中心距離1.6で68.7%、4.0で85.3%)
## だが、外へ動かすと発射リング(素の自機で3.80)を柱が跨いで発射位置の退避が増えるので
## 採らない。残るつまみが本数。
##
## **段1〜4を1本にする**。柱の害はLv1・Lv2に集中していて、Lv3以降では逆に
## プレイヤーを助ける(Lv3 単体で 柱なし0.1% → 2本8.5%。敵の方が大きいので敵が柱に
## 激突する)。符号が変わる境目がちょうどLv3なので、そこを閾値にする。
## 段ではなくレベルで判定するのは EnemyRoster.is_band_second_step と同じ理由——
## level_for_step を触ったときにこちらが黙って嘘にならないようにするため。
##
## 0本にはしない。柱の無い「柱の土俵」は名前が嘘になるし、マップの柱の印
## (ObstacleMarks)も消えて FIELD_CLASSIC と見分けが付かなくなる。1本なら段1でも
## 「この土俵には柱が立つ」を安く学べる。いじったら scripts/playtest.sh の
## 土俵別勝率と playtest/measure_obstacle_layout.gd で測り直すこと。
const OBSTACLE_FULL_LEVEL := 3

## 全部は立たない段で立つ柱の本数。表の先頭からこの本数だけ残す。
const OBSTACLE_EARLY_COUNT := 1


## 段stepでその土俵に立つ柱の本数。表の本数がこれ以下なら表のまま。
static func obstacle_count_for_step(step: int, listed: int) -> int:
	if EnemyRoster.level_for_step(step) >= OBSTACLE_FULL_LEVEL:
		return listed
	return mini(listed, OBSTACLE_EARLY_COUNT)


## 土俵を、段stepに出るものとして**柱の本数だけ**間引いた複製にする。
## 間引くものが無い段(Lv3以上・柱の無い土俵)では複製せずそのまま返す
## ＝従来と厳密に一致。位置・半径・壁・傾斜には一切触れない。
##
## 残すのは表の**先頭から**。FIELD_PILLARS の (3,3) と (7,7) は中心対称なので
## どちらを残しても難度は同じで、順序で決め打つ方が抽選に乱数を1つ足さずに済む。
static func step_field(field: FieldData, step: int) -> FieldData:
	if field == null:
		return field
	var keep := obstacle_count_for_step(step, field.obstacles.size())
	if keep >= field.obstacles.size():
		return field
	var obstacles: Array[Vector3] = []
	for i in keep:
		obstacles.append(field.obstacles[i])
	return FieldData.make(
		field.title_key, field.arena_bounds, field.wall_shape,
		field.stage_shape, field.stage_strength, obstacles
	)


## その段の土俵を1つ選ぶ。ボス(レベル5)は決戦専用の大闘技場で固定、それ以外は
## all()から一様。決戦の土俵はall()に入れない(道中で引けてしまうと専用ではなくなる)。
static func pick_for_step(step: int, rng: RandomNumberGenerator = null) -> FieldData:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	# 決戦の舞台は広い八角形の闘技場で固定して特別感を出す。
	if EnemyRoster.level_for_step(step) >= 5:
		return boss_field()
	var candidates := all()
	if candidates.is_empty():
		push_error("FieldRoster: 出せる土俵がない")
		return null
	return step_field(candidates[rng.randi_range(0, candidates.size() - 1)], step)


## 決戦専用の八角形闘技場。形と傾斜は道中のFIELD_ARENAと同じで、広さだけが違う。
static func boss_field() -> FieldData:
	return FieldData.make(
		"FIELD_GRAND_ARENA", Rect2(0, 0, BOSS_ARENA_SIDE, BOSS_ARENA_SIDE),
		ArenaWall.WallShape.OCTAGON, SpinnerPhysics.StageShape.DISH, 4.9)
