extends RefCounted

## ゲームクリア画面のリザルトサマリ文言 (GameClear.format_parts / format_continues) の
## テスト。UI (Control のインスタンス化) は要らず、純静的関数だけをヘッドレスで確かめる。
##
## サボタージュ検証 (CLAUDE.md「壊した実装を落とせて初めて完成」):
##   1. format_parts の {0} 差し込みを外して素の tr("GAMECLEAR_PARTS") にする
##      → 数字が入らず「取得パーツ数が文言に入る」が赤くなる。
##   2. format_parts と format_continues の中身(キー)を入れ替える
##      → en/ja の期待文字列がずれて赤くなる。
##   いずれも確認済み。

const GameClearScript := preload("res://scenes/gameclear/GameClear.gd")


func run(check: Callable) -> void:
	var prev_locale := TranslationServer.get_locale()

	TranslationServer.set_locale("ja")
	check.call(
		GameClearScript.format_parts(5) == "取得パーツ: 5",
		"ja: 取得パーツ数が文言に入る -> '%s'" % GameClearScript.format_parts(5)
	)
	check.call(
		GameClearScript.format_parts(0) == "取得パーツ: 0",
		"ja: 0個も表示できる -> '%s'" % GameClearScript.format_parts(0)
	)
	check.call(
		GameClearScript.format_continues(2) == "コンティニュー残: 2",
		"ja: コンティニュー残数が文言に入る -> '%s'" % GameClearScript.format_continues(2)
	)

	TranslationServer.set_locale("en")
	check.call(
		GameClearScript.format_parts(5) == "Parts acquired: 5",
		"en: 取得パーツ数が文言に入る -> '%s'" % GameClearScript.format_parts(5)
	)
	check.call(
		GameClearScript.format_continues(3) == "Continues left: 3",
		"en: コンティニュー残数が文言に入る -> '%s'" % GameClearScript.format_continues(3)
	)

	TranslationServer.set_locale(prev_locale)
