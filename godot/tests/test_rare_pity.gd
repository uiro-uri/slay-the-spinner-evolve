extends RefCounted

## RAREの天井(CustomPartCatalog.RARE_PITY_OFFERS)のテスト。
##
## 押さえるのは3つ。
##   1. 空振りの数え方(offer_has_rare / next_rare_drought / pity_due)が規則どおり。
##   2. 天井が発動したら**必ず**RAREが1枚入り、枚数も重複も変わらない。
##   3. 天井が発動していない間は**従来と厳密に同じ抽選**。天井は下振れだけを切る
##      ものなので、平均が動いたらこの変更の意味が変わる。

const TRIALS := 400


func run(check: Callable) -> void:
	_test_offer_has_rare(check)
	_test_next_drought(check)
	_test_pity_due(check)
	_test_pity_guarantees_rare(check)
	_test_below_threshold_unchanged(check)
	_test_default_matches_legacy(check)
	_test_shape_preserved(check)
	_test_slot_not_fixed(check)
	_test_no_rare_in_pool(check)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _commons(n: int) -> Array[CustomPart]:
	var out: Array[CustomPart] = []
	for part in CustomPartCatalog.all():
		if part.rarity == CustomPart.Rarity.COMMON and out.size() < n:
			out.append(part)
	return out


func _one_rare() -> CustomPart:
	for part in CustomPartCatalog.all():
		if part.rarity == CustomPart.Rarity.RARE:
			return part
	return null


func _ids(parts: Array[CustomPart]) -> Array[int]:
	var out: Array[int] = []
	for part in parts:
		out.append(part.id)
	return out


func _test_offer_has_rare(check: Callable) -> void:
	var empty: Array[CustomPart] = []
	check.call(not CustomPartCatalog.offer_has_rare(empty), "天井: 空の提示はRARE無し")
	var commons := _commons(3)
	check.call(commons.size() == 3, "天井: COMMONが3枚以上ある(前提)")
	check.call(not CustomPartCatalog.offer_has_rare(commons), "天井: COMMONだけならRARE無し")
	var mixed := _commons(2)
	mixed.append(_one_rare())
	check.call(CustomPartCatalog.offer_has_rare(mixed), "天井: 1枚でもRAREがあれば有り")


func _test_next_drought(check: Callable) -> void:
	var commons := _commons(3)
	var mixed := _commons(2)
	mixed.append(_one_rare())
	check.call(CustomPartCatalog.next_rare_drought(0, commons) == 1, "天井: 空振りで+1")
	check.call(CustomPartCatalog.next_rare_drought(3, commons) == 4, "天井: 空振りは累積する")
	check.call(CustomPartCatalog.next_rare_drought(7, mixed) == 0, "天井: RAREが出たら0へ戻る")
	check.call(CustomPartCatalog.next_rare_drought(-5, commons) == 1, "天井: 負の空振りは0扱い")


func _test_pity_due(check: Callable) -> void:
	var t := CustomPartCatalog.RARE_PITY_OFFERS
	check.call(t > 0, "天井: 既定の閾値は正")
	check.call(not CustomPartCatalog.pity_due(0), "天井: 空振り0では発動しない")
	check.call(not CustomPartCatalog.pity_due(t - 1), "天井: 閾値の1つ手前では発動しない")
	check.call(CustomPartCatalog.pity_due(t), "天井: 閾値に達したら発動")
	check.call(CustomPartCatalog.pity_due(t + 3), "天井: 閾値を超えても発動")
	check.call(not CustomPartCatalog.pity_due(99, 0), "天井: 閾値0は天井そのものを無効にする")
	check.call(not CustomPartCatalog.pity_due(99, -1), "天井: 負の閾値も無効")


## 発動したら必ずRAREが1枚以上。レベル1(RAREが一番出にくい)で数を撃つ。
func _test_pity_guarantees_rare(check: Callable) -> void:
	var misses := 0
	for i in TRIALS:
		var offer := CustomPartCatalog.pick_choices(
			CustomPartCatalog.REWARD_CHOICES, _rng(i + 1), 1, null, -1, [], 1,
			CustomPartCatalog.RARE_PITY_OFFERS
		)
		if not CustomPartCatalog.offer_has_rare(offer):
			misses += 1
	check.call(misses == 0, "天井: 発動時はRAREが必ず1枚以上 (空振り%d/%d)" % [misses, TRIALS])


## 閾値未満では天井は効かない=COMMONだけの提示が普通に出る。
## (「常にRAREを混ぜる」実装になっていたらここが落ちる)
func _test_below_threshold_unchanged(check: Callable) -> void:
	var all_common := 0
	for i in TRIALS:
		var offer := CustomPartCatalog.pick_choices(
			CustomPartCatalog.REWARD_CHOICES, _rng(i + 1), 1, null, -1, [], 1,
			CustomPartCatalog.RARE_PITY_OFFERS - 1
		)
		if not CustomPartCatalog.offer_has_rare(offer):
			all_common += 1
	check.call(
		all_common > TRIALS / 2,
		"天井: 閾値未満ではCOMMONだけの提示が過半 (%d/%d)" % [all_common, TRIALS]
	)


## 引数を省略した従来の呼び方と、空振り0を明示した呼び方が同じ結果。
## 天井は「渡さなければ存在しない」ことの担保。
func _test_default_matches_legacy(check: Callable) -> void:
	var diffs := 0
	for i in TRIALS:
		var legacy := CustomPartCatalog.pick_choices(
			CustomPartCatalog.REWARD_CHOICES, _rng(i + 1), 1
		)
		var explicit := CustomPartCatalog.pick_choices(
			CustomPartCatalog.REWARD_CHOICES, _rng(i + 1), 1, null, -1, [], 1, 0
		)
		if _ids(legacy) != _ids(explicit):
			diffs += 1
	check.call(diffs == 0, "天井: 空振り0は従来の抽選と同一 (差分%d/%d)" % [diffs, TRIALS])


## 発動しても提示の枚数は変わらず、同じ札が2枚並ばない。
func _test_shape_preserved(check: Callable) -> void:
	var bad_size := 0
	var dupes := 0
	for i in TRIALS:
		var offer := CustomPartCatalog.pick_choices(
			CustomPartCatalog.REWARD_CHOICES, _rng(i + 1), 3, null, -1, [], 2,
			CustomPartCatalog.RARE_PITY_OFFERS
		)
		if offer.size() != CustomPartCatalog.REWARD_CHOICES:
			bad_size += 1
		var seen: Array[int] = []
		for part in offer:
			if seen.has(part.id):
				dupes += 1
			seen.append(part.id)
	check.call(bad_size == 0, "天井: 発動しても提示枚数は変わらない (異常%d)" % bad_size)
	check.call(dupes == 0, "天井: 発動しても同じ札は並ばない (重複%d)" % dupes)


## 差し替える枠が固定でない。1枠に固定すると、天井のときだけ並びに規則性が出る。
##
## 「RAREが出た枠の種類数」で見ると**落とせない**: 天井が発動しなかった提示
## (自然にRAREが出た回)の枠がばらけるので、差し替えを0番に固定しても3種そろう。
## 発動回と非発動回は外から区別できないので、**先頭にRAREが来る割合**で見る。
## 正しければ差し替え先も自然発生も一様=1/3付近、0番固定なら大半が先頭に寄る。
func _test_slot_not_fixed(check: Callable) -> void:
	var with_rare := 0
	var first_slot := 0
	for i in TRIALS:
		var offer := CustomPartCatalog.pick_choices(
			CustomPartCatalog.REWARD_CHOICES, _rng(i + 1), 1, null, -1, [], 1,
			CustomPartCatalog.RARE_PITY_OFFERS
		)
		if not CustomPartCatalog.offer_has_rare(offer):
			continue
		with_rare += 1
		if offer[0].rarity == CustomPart.Rarity.RARE:
			first_slot += 1
	var share := float(first_slot) / maxf(float(with_rare), 1.0)
	check.call(with_rare > TRIALS / 2, "天井: RAREを含む提示が十分ある(前提 %d)" % with_rare)
	check.call(
		share < 0.55,
		"天井: RAREの入る枠は固定でない (先頭に来た割合 %.2f, 一様なら約0.33)" % share
	)


## 母集団にRAREが1枚も残っていなければ、天井は何もしない(落ちない・枚数も変えない)。
## 見送り除外や死にカード除外でRAREが消える組み合わせがありうる。
func _test_no_rare_in_pool(check: Callable) -> void:
	var rare_ids: Array[int] = []
	for part in CustomPartCatalog.all():
		if part.rarity == CustomPart.Rarity.RARE:
			rare_ids.append(part.id)
	check.call(not rare_ids.is_empty(), "天井: カタログにRAREがある(前提)")
	var offer := CustomPartCatalog.pick_choices(
		CustomPartCatalog.REWARD_CHOICES, _rng(11), 1, null, -1, rare_ids, 1,
		CustomPartCatalog.RARE_PITY_OFFERS
	)
	check.call(
		offer.size() == CustomPartCatalog.REWARD_CHOICES,
		"天井: RAREが母集団に無くても枚数は満たす"
	)
	# ガードを外すと空配列から引こうとして null が提示に混ざる(GDScriptの範囲外
	# 参照は中断せず null を返す)。枚数だけ見ていると素通りするので、中身を見る。
	var holes := 0
	for part in offer:
		if part == null:
			holes += 1
	check.call(holes == 0, "天井: RAREが母集団に無くても提示に穴が空かない (null%d枚)" % holes)
	check.call(
		not CustomPartCatalog.offer_has_rare(offer),
		"天井: RAREが母集団に無ければ混ぜようがない"
	)
