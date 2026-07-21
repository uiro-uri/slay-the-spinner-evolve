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
## **MIN=0** は自機の下限。自機は引き量0で速度0まで撃てる(from_pull)。
## 低速だと EnemyTelegraph の予告(長さ sqrt(速度)×length_scale)がコマの下に隠れかねないが、
## それは予告側で「コマ半径＋余白」を下回らない最小可視長を張って対処する(EnemyTelegraphの
## readable_radius / min_length_margin)。
##
## **ENEMY_MIN=3** は敵の抽選だけに敷く下限。かつて敵も下限0だったが、ほぼ静止した敵は
## 全力ラムの無料キルで、リトライの敵再抽選が「当たり(低速)を引くまで引き直す」作業に
## なっていた(journal 2026-07-21、観測は速度0.1〜2.2の敵が全て置物)。MAXの1/4を下限に
## して置物を消しつつ、低速帯(3〜6)の「先回りして待ち構える」読み合いは残す。
##
## Nodeに依存しない純粋な計算なので、ヘッドレスから直接テストできる。
const MIN := 0.0
const ENEMY_MIN := 3.0
const MAX := 12.0


## 敵の初速。出現位置・向きと同じく、出現ごとに[ENEMY_MIN, MAX]から一様抽選する。
## EnemyTelegraphが予告するので「ランダムだが読める」を維持できる(低速は予告側の
## 最小可視長で隠れないよう担保する)。
static func random(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(ENEMY_MIN, MAX)


## 自機の初速。引き量(0..max_pull)の比をMAXにマップする。full pullでMAX、無引きで0。
## 自機は下限MINを持たない(引き量に応じて0まで出せる。狙いの三角形は常時見える)。
static func from_pull(pull_len: float, max_pull: float) -> float:
	if max_pull <= 0.0:
		return 0.0
	return clampf(pull_len / max_pull, 0.0, 1.0) * MAX
