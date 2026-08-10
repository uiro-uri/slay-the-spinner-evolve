class_name LaunchSpeed
extends RefCounted

## 自機・敵で共有する発射速度レンジ(ユニット/秒)。
##
## かつては自機が引き量×pull_to_speedで0〜20、敵はEnemyDataの固定値(6.0〜9.8/ボス8.5)と
## レンジがバラバラだった。位置と向きは出現ごとにランダムなのに速度だけ固定という半端な
## 状態でもあった。ここに一本化する。
##
## **MAX=12** は自機・敵で共通の上限。自機は full pull でMAX、敵は抽選の上限。20だとボスが
## 壁に突撃して無敵中にrpsを大量に失い自滅する(=待つだけで倒せた。enemy_roster.gdの
## 発射速度11.0→8.5の経緯参照)。上限12でその暴発を抑える。
##
## **MIN=0** は「速度なし」を表す値。引き量0(＝向きが決まっていない)だけがここへ落ちる。
## 低速だと EnemyTelegraph の予告(長さは自機と共通の AimTriangle.length_for_speed)が
## コマの下に隠れかねないが、
## それは予告側で「コマ半径＋余白」を下回らない最小可視長を張って対処する(EnemyTelegraphの
## readable_radius / min_length_margin)。
##
## **ENEMY_MIN=3** は敵の抽選に敷く下限。かつて敵も下限0だったが、ほぼ静止した敵は
## 全力ラムの無料キルで、リトライの敵再抽選が「当たり(低速)を引くまで引き直す」作業に
## なっていた(journal 2026-07-21、観測は速度0.1〜2.2の敵が全て置物)。MAXの1/4を下限に
## して置物を消しつつ、低速帯(3〜6)の「先回りして待ち構える」読み合いは残す。
##
## **PLAYER_MIN は同じ下限を自機にも敷く**(2026-08-10)。「ほぼ静止したコマは的でしかない」
## のは撃つのが敵でも自分でも同じなのに、この対策は敵側にしか無く、自機は引き量0まで
## 撃てた——そして自分で選べるぶん、罠は自機側の方が深かった。
##
## `measure_launch_force` を GROWTH 0〜3枚 × Lv1〜5 × 1体/3体 で取り直すと、
## **弱く撃って得になるセルが1つも無い**。効きが最も大きい 成長3枚のLv3単体で
## フォース0.15が勝率13.2%、満引きが62.8%(各400戦)。弱撃ちは壁の取り分こそ
## 16%→3%に減るが、決着が10.1s→14.5sに延びて自然減衰に食われ、
## 差し引きで一方的に負ける。つまり引き量の下側は「慎重な選択肢」ではなく、
## **選ぶと静かに罰されるだけの死に帯**だった。
##
## 下限を敷いても引き量の比は 0→PLAYER_MIN、full→MAX へ線形に写るだけなので、
## 「弱く撃って先回りを待つ」読み合い(敵側で意図的に残した低速帯と同じもの)は残る。
## 消えるのは置きコマだけ。
##
## Nodeに依存しない純粋な計算なので、ヘッドレスから直接テストできる。
const MIN := 0.0
const ENEMY_MIN := 3.0
## 自機の下限。敵と同じ理屈・同じ値なので定数を共有する(片方だけ動かせないように)。
const PLAYER_MIN := ENEMY_MIN
const MAX := 12.0

## 大型の敵に敷く抽選上限の体格スケール。半径 CAP_FREE_RADIUS 以下は従来どおり
## MAX、そこから CAP_FULL_RADIUS へ向けて線形に下がり、以遠は CAP_BIG で頭打ち。
##
## 経緯: かつてボスの初速を11.0→8.5に落とした(速いと壁に突撃し、rpsの6割超を
## 壁で失って勝手に死ぬ=待つだけで倒せた。enemy_roster.gd参照)。その後の
## レンジ一本化で全敵が[3,12]抽選になり、この対策が大型敵に対して退行していた
## (コールドプレイ2026-07-30: 初速10.6のボス(半径1.91)が3.9秒で壁に20.8/34.6を
## 失い自滅、低フォースの待ちが最適だった)。壁の喪失は進入速度比例
## (impact_scaled_wall_damping)なので、体格ぶん壁に届きやすい大型だけ上限を
## 下げれば、小型の速度レンジ(読み合いの幅)を削らずに暴発だけを抑えられる。
##
## CAP_FREE_RADIUS=1.0 はLv1〜3の実半径(〜0.95)のすぐ上=中小型は完全に従来どおり。
## CAP_FULL_RADIUS=1.9 はボス級の実半径(1.69〜1.91)の上端。CAP_BIG=8.5 は
## かつてボス固定値として実証済みの速度。
const CAP_FREE_RADIUS := 1.0
const CAP_FULL_RADIUS := 1.9
const CAP_BIG := 8.5


## 半径に応じた敵の抽選上限。CAP_FREE_RADIUS以下はMAX(従来どおり)、
## CAP_FULL_RADIUS以上はCAP_BIG、その間は線形。
static func max_for_radius(radius: float) -> float:
	var t := clampf(
		(radius - CAP_FREE_RADIUS) / (CAP_FULL_RADIUS - CAP_FREE_RADIUS), 0.0, 1.0
	)
	return lerpf(MAX, CAP_BIG, t)


## 敵の初速。出現位置・向きと同じく、出現ごとに[ENEMY_MIN, max_for_radius(radius)]
## から一様抽選する。radius省略(0.0)は上限MAX=旧挙動と厳密一致。
## EnemyTelegraphが予告するので「ランダムだが読める」を維持できる(低速は予告側の
## 最小可視長で隠れないよう担保する)。
static func random(rng: RandomNumberGenerator, radius: float = 0.0) -> float:
	return rng.randf_range(ENEMY_MIN, max_for_radius(radius))


## 自機の初速。引き量(0..max_pull)の比を[PLAYER_MIN, MAX]にマップする。
## full pullでMAX、少しでも引けばPLAYER_MIN以上(死に帯を踏めない)。
##
## **引き量ちょうど0だけは0**を返す。あそこは「弱く撃つ」ではなく「まだ向きが
## 決まっていない」状態で、LaunchControllerも pull.normalized() がゼロベクトルに
## なるので速度は出ない。ここで PLAYER_MIN を返すと、狙いの三角形(長さは
## AimTriangle.length_for_speed(speed))だけが実際には出ない初速で描かれてしまう。
static func from_pull(pull_len: float, max_pull: float) -> float:
	if max_pull <= 0.0 or pull_len <= 0.0:
		return 0.0
	return lerpf(PLAYER_MIN, MAX, clampf(pull_len / max_pull, 0.0, 1.0))


## 引きベクトル(向き＋量)から自機の初速ベクトル。向きは引いた方向そのまま
## (逆向きにするのは呼び出し側の役目。LaunchControllerが `_origin - _current` を作る)。
##
## LaunchController が `pull.normalized() * from_pull(...)` を自前で書いていたのを
## ここへ引き上げた。あちらは Node で AudioManager 依存もあるためヘッドレスから
## `new()` できず、**自機の発射の本体だけがテストから触れなかった**——下限を敷いた
## 2026-08-10 に、ボットとCLIは検査できるのに実UIだけ検査できないと気づいた。
## 純粋関数にすればCLAUDE.mdの方針どおり直接呼べる。
static func velocity_from_pull(pull: Vector2, max_pull: float) -> Vector2:
	var speed := from_pull(pull.length(), max_pull)
	if speed <= 0.0:
		return Vector2.ZERO
	return pull.normalized() * speed
