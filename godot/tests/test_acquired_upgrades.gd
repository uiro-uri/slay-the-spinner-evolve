extends RefCounted

## 取得済みアップグレードの集約ロジック (CustomPartCatalog.aggregate_acquired) のテスト。
##
## UI (MapScreen の一覧) はツリーが要るのでここでは触らず、純関数の集約だけを
## ヘッドレスで確かめる。初出順・個数・レアリティが正しく畳まれるかを見る。


func run(check: Callable) -> void:
	_test_empty(check)
	_test_single(check)
	_test_aggregates_and_order(check)
	_test_rare_count(check)


func _test_empty(check: Callable) -> void:
	var ids: Array[int] = []
	var result := CustomPartCatalog.aggregate_acquired(ids)
	check.call(result.is_empty(), "集約: 空の取得IDは空の結果になる")


func _test_single(check: Callable) -> void:
	var ids: Array[int] = [7]
	var result := CustomPartCatalog.aggregate_acquired(ids)
	check.call(result.size() == 1, "集約: 1件は1エントリ (%d)" % result.size())
	if result.size() == 1:
		var part: CustomPart = result[0]["part"]
		check.call(
			part.title_key == "PART_SPIN_ENGINE",
			"集約: id7 が Spin Engine に解決される (%s)" % part.title_key
		)
		check.call(result[0]["count"] == 1, "集約: 1件のcountは1 (%d)" % result[0]["count"])


func _test_aggregates_and_order(check: Callable) -> void:
	# id2 を2回、id5 を1回。初出順は 2 -> 5。
	var ids: Array[int] = [2, 2, 5]
	var result := CustomPartCatalog.aggregate_acquired(ids)
	check.call(result.size() == 2, "集約: 重複は畳んで2エントリ (%d)" % result.size())
	if result.size() == 2:
		var first: CustomPart = result[0]["part"]
		var second: CustomPart = result[1]["part"]
		check.call(first.id == 2, "集約: 初出順で id2 が先頭 (%d)" % first.id)
		check.call(result[0]["count"] == 2, "集約: id2 のcountは2 (%d)" % result[0]["count"])
		check.call(second.id == 5, "集約: id5 が2番目 (%d)" % second.id)
		check.call(result[1]["count"] == 1, "集約: id5 のcountは1 (%d)" % result[1]["count"])


func _test_rare_count(check: Callable) -> void:
	# id3 (Overencumbered) はレア。2回取得で count 2 かつ RARE のまま。
	var ids: Array[int] = [3, 3]
	var result := CustomPartCatalog.aggregate_acquired(ids)
	check.call(result.size() == 1, "集約: レアの重複も畳んで1エントリ (%d)" % result.size())
	if result.size() == 1:
		var part: CustomPart = result[0]["part"]
		check.call(result[0]["count"] == 2, "集約: レアのcountは2 (%d)" % result[0]["count"])
		check.call(
			part.rarity == CustomPart.Rarity.RARE,
			"集約: id3 はレアと判定される"
		)
