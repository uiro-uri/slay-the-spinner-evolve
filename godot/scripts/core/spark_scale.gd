class_name SparkScale
extends RefCounted

## 衝撃波(スパーク)の大きさを「その瞬間に失われたrps」でスケールする純粋関数。
##
## 壁の喪失は進入速度比例(impact_scaled_wall_damping)、削りは噛み合い床
## (bitten_speed)持ちで、同じ「接触」でも痛さは何倍も違う。だがスパークが
## 固定サイズだと、擦り接触と激突が画面上で同じに見え、決着時の内訳を見る
## まで「壁で2割失った」ことに気付けない(コールドプレイの一次証拠:
## ボス戦の敗因が壁6回20.4喪失なのに、再生中はただの点滅にしか見えない)。
##
## 倍率は失われたrpsの平方根に比例させる: スパークは面で見えるので、
## 「4倍痛い衝突は半径2倍(面積4倍)」が知覚上の比例になる。
## Nodeにもシーンにも依存せず、ヘッドレステストが直接叩く。


## strength(失われたrps)を、ref_loss を基準1.0とした表示倍率に変換する。
## - ref_loss <= 0 はスケール無効(常に1.0=従来の固定サイズ)。旧結果の再生や
##   Inspectorからの一時無効化に使う安全弁。
## - strength <= 0 (削りゼロの微衝突)は最小倍率へ。
## - 倍率は [min_scale, max_scale] にクランプ。ゼロサイズや画面を覆う波を防ぐ。
static func scale_for(
	strength: float, ref_loss: float, min_scale: float, max_scale: float
) -> float:
	if ref_loss <= 0.0:
		return 1.0
	if strength <= 0.0:
		return min_scale
	return clampf(sqrt(strength / ref_loss), min_scale, max_scale)
