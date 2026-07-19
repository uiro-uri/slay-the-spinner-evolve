extends RefCounted

## ゲームクリア画面のリザルトサマリ文言 (GameClear.format_continues) のテスト。
## UI (Control のインスタンス化) は要らず、純静的関数だけをヘッドレスで確かめる。
##
## サボタージュ検証 (CLAUDE.md「壊した実装を落とせて初めて完成」):
##   1. format_continues の {0} 差し込みを外して素の tr("GAMECLEAR_CONTINUES_LEFT") にする
##      → 数字が入らず「コンティニュー残数が文言に入る」が赤くなる。
##   2. format_continues のキーを別キーに差し替える
##      → en/ja の期待文字列がずれて赤くなる。
##   いずれも確認済み。

const GameClearScript := preload("res://scenes/gameclear/GameClear.gd")


func run(check: Callable) -> void:
	var prev_locale := TranslationServer.get_locale()

	TranslationServer.set_locale("ja")
	check.call(
		GameClearScript.format_continues(2) == "コンティニュー残: 2",
		"ja: コンティニュー残数が文言に入る -> '%s'" % GameClearScript.format_continues(2)
	)
	check.call(
		GameClearScript.format_streak(3) == "連続クリア: 3",
		"ja: 連続クリア記録が文言に入る -> '%s'" % GameClearScript.format_streak(3)
	)

	TranslationServer.set_locale("en")
	check.call(
		GameClearScript.format_continues(3) == "Continues left: 3",
		"en: コンティニュー残数が文言に入る -> '%s'" % GameClearScript.format_continues(3)
	)
	check.call(
		GameClearScript.format_streak(3) == "Win streak: 3",
		"en: 連続クリア記録が文言に入る -> '%s'" % GameClearScript.format_streak(3)
	)

	TranslationServer.set_locale(prev_locale)
