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
## **MIN=0** は自機と同じ下限。自機は引き量0で速度0まで撃てるので、敵も同じ0まで撃てる。
## 低速だと EnemyTelegraph の予告(長さ sqrt(速度)×length_scale)がコマの下に隠れかねないが、
## それは予告側で「コマ半径＋余白」を下回らない最小可視長を張って対処する(EnemyTelegraphの
## readable_radius / min_length_margin)。速度そのものの下限は0でよい。
##
## Nodeに依存しない純粋な計算なので、ヘッドレスから直接テストできる。
const MIN := 0.0
const MAX := 12.0


## 敵の初速。出現位置・向きと同じく、出現ごとに[MIN, MAX]から一様抽選する。
## EnemyTelegraphが予告するので「ランダムだが読める」を維持できる(低速は予告側の
## 最小可視長で隠れないよう担保する)。
static func random(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(MIN, MAX)


## 自機の初速。引き量(0..max_pull)の比をMAXにマップする。full pullでMAX、無引きで0。
## 自機は下限MINを持たない(引き量に応じて0まで出せる。狙いの三角形は常時見える)。
static func from_pull(pull_len: float, max_pull: float) -> float:
	if max_pull <= 0.0:
		return 0.0
	return clampf(pull_len / max_pull, 0.0, 1.0) * MAX
