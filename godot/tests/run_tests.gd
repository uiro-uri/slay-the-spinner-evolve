extends SceneTree

## ヘッドレスで実行する簡易テストランナー。
##   godot --headless --path godot --script res://tests/run_tests.gd
## 失敗すると終了コード1で終わるのでCIやコミット前チェックに使える。
##
## 注意: GDScriptの実行時エラー（型不一致など）は例外として捕捉できず、
## その関数だけが中断される。取りこぼして「成功」と誤報告しないよう、
## 各テストは最後に_done()を呼び、全部が完走したかを最後に照合する。

var _failures: Array[String] = []
var _completed: Array[String] = []

const EXPECTED_TESTS: Array[String] = ["translations", "gamestate"]


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   - %s" % message)
	else:
		_failures.append(message)
		printerr("  FAIL - %s" % message)


func _done(test_name: String) -> void:
	_completed.append(test_name)


func _init() -> void:
	print("== translations ==")
	_test_translations()

	print("== gamestate ==")
	_test_gamestate_autoload()

	for test_name in EXPECTED_TESTS:
		if not test_name in _completed:
			_failures.append("%s が完走しなかった（実行時エラーの可能性）" % test_name)
			printerr("  FAIL - %s が完走しなかった（実行時エラーの可能性）" % test_name)

	print("")
	if _failures.is_empty():
		print("すべて成功 (%d/%d テスト完走)" % [_completed.size(), EXPECTED_TESTS.size()])
		quit(0)
	else:
		printerr("%d 件失敗" % _failures.size())
		quit(1)


func _test_translations() -> void:
	var locales := TranslationServer.get_loaded_locales()
	_check("en" in locales, "enの翻訳が読み込まれている (loaded: %s)" % [locales])
	_check("ja" in locales, "jaの翻訳が読み込まれている (loaded: %s)" % [locales])

	TranslationServer.set_locale("en")
	_check(tr("TITLE_START") == "Game Start", "en: TITLE_START -> '%s'" % tr("TITLE_START"))

	TranslationServer.set_locale("ja")
	_check(tr("TITLE_START") == "ゲームスタート", "ja: TITLE_START -> '%s'" % tr("TITLE_START"))

	# 未定義キーはキー自身が返る＝訳抜けを検出できる
	_check(tr("NO_SUCH_KEY") == "NO_SUCH_KEY", "未定義キーはそのまま返る")

	_done("translations")


func _test_gamestate_autoload() -> void:
	# autoloadはメインシーン実行時にツリーへ入るので、--script実行のこの時点では
	# まだ存在しない。ここでは「project.godotに登録されているか」と
	# 「スクリプト自体の挙動」を分けて確認する。
	_check(
		ProjectSettings.get_setting("autoload/GameState", "") == "*res://autoloads/GameState.gd",
		"GameStateがproject.godotにautoload登録されている"
	)

	var game_state: Node = load("res://autoloads/GameState.gd").new()
	var part_ids: Array[int] = [1, 2]
	game_state.current_node_id = 42
	game_state.acquired_part_ids = part_ids
	game_state.reset_run()
	_check(game_state.current_node_id == -1, "reset_run()でcurrent_node_idが初期化される")
	_check(game_state.acquired_part_ids.is_empty(), "reset_run()でacquired_part_idsが空になる")
	game_state.free()

	_done("gamestate")
