extends RefCounted

## 取得済みアップグレード一覧UI (AcquiredUpgradeList) の組み立てテスト。
##
## 集約ロジック自体は test_acquired_upgrades.gd が純関数として確かめているので、
## ここは「集約結果が正しい数・種類のUI行になるか」だけを見る。Controlを生成するが
## SceneTreeへ入れない(ツリー不要)。生成したノードは最後にfreeしてリークを避ける。
##
## サボタージュ検証 (CLAUDE.md「壊した実装を落とせて初めて完成」):
##   1. build_row を追加せず空のまま return する → 「2件は2行」が赤くなる。
##   2. 空チェックを消して空リストで何も積まない → 「空は1行(なし表示)」が赤くなる。
##   3. rare_stylebox の付与を common にも付ける/レアに付けない → レア強調のチェックが赤くなる。
##   いずれも確認済み。


func run(check: Callable) -> void:
	_test_empty_shows_placeholder(check)
	_test_aggregates_into_rows(check)
	_test_rare_row_is_highlighted(check)
	_test_common_row_is_plain(check)


func _test_empty_shows_placeholder(check: Callable) -> void:
	var list := VBoxContainer.new()
	var ids: Array[int] = []
	AcquiredUpgradeList.populate(list, ids)
	check.call(
		list.get_child_count() == 1,
		"空の取得IDは「なし」表示1件だけになる (%d)" % list.get_child_count()
	)
	if list.get_child_count() == 1:
		var only := list.get_child(0)
		check.call(only is Label, "空表示はLabel (%s)" % only.get_class())
	list.free()


func _test_aggregates_into_rows(check: Callable) -> void:
	# id2 を2回、id5 を1回。集約で2行になる。
	var list := VBoxContainer.new()
	var ids: Array[int] = [2, 2, 5]
	AcquiredUpgradeList.populate(list, ids)
	check.call(
		list.get_child_count() == 2,
		"重複を畳んで2行になる (%d)" % list.get_child_count()
	)
	list.free()


func _test_rare_row_is_highlighted(check: Callable) -> void:
	# id3 (Overencumbered) はレア。行のパネルに金色スタイルボックスが付く。
	var list := VBoxContainer.new()
	var ids: Array[int] = [3]
	AcquiredUpgradeList.populate(list, ids)
	check.call(list.get_child_count() == 1, "レア1件は1行 (%d)" % list.get_child_count())
	if list.get_child_count() == 1:
		var row := list.get_child(0)
		check.call(
			row.has_theme_stylebox_override("panel"),
			"レア行はパネルに金色スタイルボックスが付く"
		)
	list.free()


func _test_common_row_is_plain(check: Callable) -> void:
	# id2 (Giant Growth) はコモン。レア強調は付かない。
	var list := VBoxContainer.new()
	var ids: Array[int] = [2]
	AcquiredUpgradeList.populate(list, ids)
	if list.get_child_count() == 1:
		var row := list.get_child(0)
		check.call(
			not row.has_theme_stylebox_override("panel"),
			"コモン行にはレアの金色スタイルボックスが付かない"
		)
	list.free()
