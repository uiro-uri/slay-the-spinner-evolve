extends RefCounted

## DiscWeightVisual(質量→縁リムの太さ)のテスト。
##
## 質量はこれまで画面のどこにも出ておらず、「壁へ弾き飛ばして仕留める」戦法が
## 撃つまで分からない賭けだった(コールドプレイの一次証拠)。リムは相対比較で
## 読む表示なので、単調性・クランプ・「読める差が出る」ことを数値で押さえる。

const EPS := 1e-6


func run(check: Callable) -> void:
	_test_monotonic(check)
	_test_bounds(check)
	_test_readable_difference(check)
	_test_rim_width(check)
	_test_rim_color(check)
	_test_mass_full_matches_catalog(check)


## 質量が増えてリムが細くなることはない。写像域(0〜MASS_FULL)では厳密に太くなる。
func _test_monotonic(check: Callable) -> void:
	var prev := -1.0
	var monotonic := true
	for i in 101:
		var r := DiscWeightVisual.rim_ratio(i * 0.1)
		if r < prev - EPS:
			monotonic = false
		prev = r
	check.call(monotonic, "リム: 質量が増えて細くなることはない")

	var strictly := true
	for i in 79:
		var m := i * 0.1
		if DiscWeightVisual.rim_ratio(m + 0.1) <= DiscWeightVisual.rim_ratio(m) + EPS:
			strictly = false
	check.call(strictly, "リム: 写像域(0〜%.0f)では質量差が必ず太さの差になる" % DiscWeightVisual.MASS_FULL)


## 両端はクランプ。負や異常値でも壊れず、太さは常に[MIN, MAX]に収まる。
func _test_bounds(check: Callable) -> void:
	check.call(
		is_equal_approx(DiscWeightVisual.rim_ratio(-5.0), DiscWeightVisual.MIN_RATIO),
		"リム: 質量が負でも下限で止まる"
	)
	check.call(
		is_equal_approx(DiscWeightVisual.rim_ratio(999.0), DiscWeightVisual.MAX_RATIO),
		"リム: 天井超えの質量は上限で頭打ち"
	)
	var in_range := true
	for i in 201:
		var r := DiscWeightVisual.rim_ratio(i * 0.1 - 2.0)
		if r < DiscWeightVisual.MIN_RATIO - EPS or r > DiscWeightVisual.MAX_RATIO + EPS:
			in_range = false
	check.call(in_range, "リム: どんな質量でも太さは[%.2f, %.2f]" % [
		DiscWeightVisual.MIN_RATIO, DiscWeightVisual.MAX_RATIO])

	# 回転の尾(Disc.TAIL_WIDTH_RATIO)より細いこと。リムが尾を覆うと速度情報が消える。
	check.call(
		DiscWeightVisual.MAX_RATIO < Disc.TAIL_WIDTH_RATIO,
		"リム: 最大でも回転の尾(%.2f)より細い (%.2f)" % [
			Disc.TAIL_WIDTH_RATIO, DiscWeightVisual.MAX_RATIO]
	)


## 「読める差」が出ること。初期プレイヤー(質量1.5)とLv4/ボスの巨体の間に
## 見て分かる太さの差(割合で0.03以上)がないと、可視化した意味がない。
func _test_readable_difference(check: Callable) -> void:
	var player := SpinnerStats.default_player()
	var player_ratio := DiscWeightVisual.rim_ratio(player.mass)

	var heaviest_lv4 := 0.0
	for e in EnemyRoster.of_level(4):
		heaviest_lv4 = maxf(heaviest_lv4, e.stats.mass)
	var lv4_ratio := DiscWeightVisual.rim_ratio(heaviest_lv4)
	check.call(
		lv4_ratio - player_ratio >= 0.03,
		"リム: 初期プレイヤーとLv4最重量(質量%.2f)の差が読める (%.3f vs %.3f)" % [
			heaviest_lv4, player_ratio, lv4_ratio]
	)

	var heaviest_boss := 0.0
	for e in EnemyRoster.of_level(5):
		heaviest_boss = maxf(heaviest_boss, e.stats.mass)
	check.call(
		DiscWeightVisual.rim_ratio(heaviest_boss) > lv4_ratio + EPS,
		"リム: ボス帯はLv4よりさらに太い"
	)


## 実太さは半径に比例する。大きくて重いコマほど物理的にも分厚い縁になり、
## 硬さ=質量×半径²の直感と揃う。
func _test_rim_width(check: Callable) -> void:
	var w1 := DiscWeightVisual.rim_width(3.0, 1.0)
	var w2 := DiscWeightVisual.rim_width(3.0, 2.0)
	check.call(is_equal_approx(w2, w1 * 2.0), "リム: 実太さは半径に比例する")
	check.call(
		is_equal_approx(w1, DiscWeightVisual.rim_ratio(3.0)),
		"リム: 半径1ならratioがそのまま太さ"
	)


## リム色は基準色より暗く、アルファは保つ。明るい回転マークと取り違えないため。
func _test_rim_color(check: Callable) -> void:
	var base := Color(0.8, 0.3, 0.2, 0.9)
	var rim := DiscWeightVisual.rim_color(base)
	check.call(
		rim.get_luminance() < base.get_luminance(),
		"リム色: 基準色より暗い (%.3f < %.3f)" % [rim.get_luminance(), base.get_luminance()]
	)
	check.call(is_equal_approx(rim.a, base.a), "リム色: アルファは変えない")


## 写像の天井はパーツの質量上限と同じ値。coreからdata層への参照を作らないため
## 定数は重複で持つが、ズレたらここで割れる。
func _test_mass_full_matches_catalog(check: Callable) -> void:
	check.call(
		is_equal_approx(DiscWeightVisual.MASS_FULL, CustomPartCatalog.MASS_CAP),
		"リム: 写像の天井(%.1f)がパーツの質量上限(%.1f)と一致" % [
			DiscWeightVisual.MASS_FULL, CustomPartCatalog.MASS_CAP]
	)
