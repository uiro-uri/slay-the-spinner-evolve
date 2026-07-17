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

const EXPECTED_TESTS: Array[String] = [
	"translations", "gamestate", "font", "physics", "map", "enemies", "parts", "spawn"
]


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

	print("== font ==")
	_test_font_covers_japanese()

	print("== physics ==")
	_test_physics()

	print("== map ==")
	_test_map()

	print("== enemies ==")
	_test_enemies()

	print("== parts ==")
	_test_parts()

	print("== spawn ==")
	_test_spawn()

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
	game_state.acquired_part_ids = part_ids
	game_state.pending_enemy = EnemyRoster.all()[0]
	game_state.reset_run()

	_check(game_state.acquired_part_ids.is_empty(), "reset_run()でacquired_part_idsが空になる")
	_check(game_state.pending_enemy == null, "reset_run()でpending_enemyが消える")
	_check(game_state.player_stats != null, "reset_run()でプレイヤーの性能が用意される")
	_check(game_state.map_tree != null, "reset_run()でマップが生成される")
	if game_state.map_tree != null:
		_check(
			game_state.map_tree.current_coord == MapTree.START_COORD,
			"reset_run()でマップがスタート地点から始まる"
		)
	game_state.free()

	_done("gamestate")


func _test_font_covers_japanese() -> void:
	# Godot標準フォントはCJKグリフを持たず、日本語が豆腐(□)になる。
	# 実ブラウザで見るまで気付けなかったので、ここで機械的に検出する。
	# pckサイズでは捕まらない: フォントファイルはall_resourcesで同梱される
	# ため、custom_fontの指定を外しても容量は変わらない。
	var font_path: String = ProjectSettings.get_setting("gui/theme/custom_font", "")
	_check(font_path != "", "既定フォントがproject.godotに設定されている")
	if font_path == "":
		_done("font")
		return

	var font := load(font_path) as Font
	_check(font != null, "既定フォントを読み込める (%s)" % font_path)
	if font == null:
		_done("font")
		return

	for sample in ["あ", "日", "ア", "A"]:
		_check(
			font.has_char(sample.unicode_at(0)),
			"既定フォントが '%s' のグリフを持つ" % sample
		)

	_done("font")


func _test_physics() -> void:
	var suite = load("res://tests/test_spinner_physics.gd").new()
	suite.run(_check)
	_done("physics")


func _test_map() -> void:
	var suite = load("res://tests/test_map_tree.gd").new()
	suite.run(_check)
	_done("map")


func _test_parts() -> void:
	var suite = load("res://tests/test_custom_part.gd").new()
	suite.run(_check)
	_done("parts")


func _test_spawn() -> void:
	var suite = load("res://tests/test_enemy_spawn.gd").new()
	suite.run(_check)
	_done("spawn")


func _test_enemies() -> void:
	# どの段にも出せる敵がいること。1体でも欠けるとその段で進行不能になる。
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for step in range(1, MapTree.STEP_GOAL + 1):
		var enemy: EnemyData = EnemyRoster.pick_for_step(step, rng)
		_check(
			enemy != null and enemy.stats != null,
			"段%d に出せる敵がいる (レベル%d)" % [step, EnemyRoster.level_for_step(step)]
		)

	# ゴールがボス(レベル5)になること。プロトタイプが修正コミットで狙った挙動。
	_check(
		EnemyRoster.level_for_step(MapTree.STEP_GOAL) == 5,
		"ゴール(段%d)がレベル5のボスになる" % MapTree.STEP_GOAL
	)
	# 段が進むほど強くなること(下がらない)
	var monotonic := true
	for step in range(1, MapTree.STEP_GOAL):
		if EnemyRoster.level_for_step(step + 1) < EnemyRoster.level_for_step(step):
			monotonic = false
	_check(monotonic, "段が進んでも敵レベルが下がらない")

	# 名前が翻訳されること(訳抜けはキーがそのまま出るので分かる)
	TranslationServer.set_locale("ja")
	var untranslated: Array[String] = []
	for enemy in EnemyRoster.all():
		if tr(enemy.display_name) == enemy.display_name:
			untranslated.append(enemy.display_name)
	_check(untranslated.is_empty(), "敵の名前に訳がある (未訳: %s)" % [untranslated])

	_done("enemies")
