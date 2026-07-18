extends RefCounted

## サウンドテスト(SoundCatalog + AudioManager の全体音量)のテスト。
##
## 表示・再生そのものはヘッドレスでは評価できないので、崩れると実害が出る不変条件を突く:
##  - カタログの整合性(件数・キー重複・パスが実在してogg vorbisであること)。
##    パスの打ち間違いはここで捕まる(サボタージュ検証の主眼)。
##  - by_category() が期待カテゴリを漏れなく返し、合計件数が一致すること。
##  - 全体音量の set/get が往復すること・0でミュートになること。
##  - 未知キー/空パスで再生しても落ちないこと。
##  - サウンドテスト画面が使う翻訳キーが訳抜けしていないこと。

const EPS := 1e-3
const EXPECTED_CATEGORIES := ["launch", "impact", "wall", "result", "ui"]
const EXPECTED_COUNT := 17


func run(check: Callable) -> void:
	_test_catalog_integrity(check)
	_test_by_category(check)
	_test_path_for(check)
	_test_master_volume(check)
	_test_play_never_crashes(check)
	_test_clear_fanfare(check)
	_test_translations(check)


func _test_catalog_integrity(check: Callable) -> void:
	var entries := SoundCatalog.all()
	check.call(entries.size() == EXPECTED_COUNT, "カタログが%d件ある (実際: %d)" % [EXPECTED_COUNT, entries.size()])

	var seen: Dictionary = {}
	var duplicated := false
	var all_ogg := true
	var bad_paths: Array[String] = []
	for entry in entries:
		var key: String = entry["key"]
		if seen.has(key):
			duplicated = true
		seen[key] = true
		var stream := load(entry["path"]) as AudioStream
		if stream == null or not (stream is AudioStreamOggVorbis):
			all_ogg = false
			bad_paths.append(entry["path"])
	check.call(not duplicated, "キーが全て一意")
	check.call(all_ogg, "全SEのパスが読み込めてOggVorbisである (不正: %s)" % [bad_paths])


func _test_by_category(check: Callable) -> void:
	var grouped := SoundCatalog.by_category()
	var keys: Array = grouped.keys()
	check.call(keys == EXPECTED_CATEGORIES, "by_category()が期待カテゴリを順序通り返す (実際: %s)" % [keys])

	var total := 0
	var all_non_empty := true
	for category in grouped:
		var items: Array = grouped[category]
		if items.is_empty():
			all_non_empty = false
		total += items.size()
	check.call(all_non_empty, "各カテゴリが1件以上")
	check.call(total == EXPECTED_COUNT, "カテゴリ合計が全件と一致 (%d)" % total)
	check.call(SoundCatalog.categories() == EXPECTED_CATEGORIES, "categories()が期待通り")


func _test_path_for(check: Callable) -> void:
	var first := SoundCatalog.all()[0]
	check.call(SoundCatalog.path_for(first["key"]) == first["path"], "path_for()が既知キーのパスを返す")
	check.call(SoundCatalog.path_for("__no_such_key__") == "", "path_for()は未知キーで空文字")


func _test_master_volume(check: Callable) -> void:
	var am: Node = load("res://autoloads/AudioManager.gd").new()

	# project.godotに登録されていること(gamestateテストと同じ確認方法)。
	check.call(
		ProjectSettings.get_setting("autoload/AudioManager", "") == "*res://autoloads/AudioManager.gd",
		"AudioManagerがproject.godotにautoload登録されている"
	)

	var original: float = am.get_master_volume_linear()

	am.set_master_volume_linear(0.5)
	check.call(absf(am.get_master_volume_linear() - 0.5) < EPS, "全体音量0.5が往復する (%.3f)" % am.get_master_volume_linear())

	am.set_master_volume_linear(0.0)
	check.call(am.get_master_volume_linear() == 0.0, "全体音量0でミュート(0を返す)")

	am.set_master_volume_linear(1.0)
	check.call(absf(am.get_master_volume_linear() - 1.0) < EPS, "全体音量1.0が往復する (%.3f)" % am.get_master_volume_linear())

	# クランプ: 範囲外を入れても0〜1に収まる。
	am.set_master_volume_linear(2.0)
	check.call(am.get_master_volume_linear() <= 1.0 + EPS, "全体音量は1.0を超えない")

	am.set_master_volume_linear(original)
	am.free()


func _test_play_never_crashes(check: Callable) -> void:
	var am: Node = load("res://autoloads/AudioManager.gd").new()
	# _ready前(プール未構築)でも落ちないこと。ここを過ぎればガードが効いている。
	am.play("__no_such_key__")
	am.play_path("")
	am.play_path(SoundCatalog.all()[0]["path"])
	check.call(true, "未知キー/空パス/プール未構築でも play が落ちない")
	am.free()


func _test_clear_fanfare(check: Callable) -> void:
	var am: Node = load("res://autoloads/AudioManager.gd").new()

	# 5度=3/2、オクターブ=2。
	check.call(absf(am.CLEAR_FIFTH_RATIO - 1.5) < EPS, "5度は×1.5 (%.3f)" % am.CLEAR_FIFTH_RATIO)
	check.call(absf(am.CLEAR_OCTAVE - 2.0) < EPS, "オクターブは×2.0 (%.3f)" % am.CLEAR_OCTAVE)
	# 「一拍置いて」の間は三連打の間隔より広い(着地フレーズが分離して聞こえる)。
	check.call(am.CLEAR_REST > am.CLEAR_HIT_INTERVAL, "着地前の間が三連打の間隔より広い")
	check.call(am.CLEAR_HIT_INTERVAL > 0.0, "三連打の間隔が正")

	# 旋律: 頭は同音三連打、締めはオクターブで着地(=最後がドミナントより上に解決する)。
	var seq: Array = am.CLEAR_SEQUENCE
	check.call(seq.size() >= 5, "旋律が三連打+着地フレーズを含む長さ (%d音)" % seq.size())
	var opening_unison := true
	for i in 3:
		if not is_equal_approx(seq[i]["pitch"], am.CLEAR_UNISON):
			opening_unison = false
	check.call(opening_unison, "頭の三音が同音(主音)")
	var last_pitch: float = seq[seq.size() - 1]["pitch"]
	check.call(absf(last_pitch - am.CLEAR_OCTAVE) < EPS, "最後の音がオクターブ(主音)で着地する (%.3f)" % last_pitch)
	check.call(last_pitch > am.CLEAR_FIFTH_RATIO, "着地音が5度より高い(ドミナントで開放したまま終わらない)")
	check.call(seq[seq.size() - 1]["gap"] <= 0.0, "最後の音の後に間は無い")

	# 締めはオクターブの16分連打。連打は三連打の間隔より速く、末尾に複数連続する。
	check.call(am.CLEAR_ROLL_INTERVAL < am.CLEAR_HIT_INTERVAL, "連打(16分)が三連打の間隔より速い")
	var trailing_octaves := 0
	for i in range(seq.size() - 1, -1, -1):
		if is_equal_approx(seq[i]["pitch"], am.CLEAR_OCTAVE):
			trailing_octaves += 1
		else:
			break
	check.call(trailing_octaves >= 3, "締めがオクターブの連打(末尾に%d連続)" % trailing_octaves)
	# 連打内の音(最後を除く)は16分間隔で刻む。
	var roll_spacing_ok := true
	for i in range(seq.size() - trailing_octaves, seq.size() - 1):
		if not is_equal_approx(seq[i]["gap"], am.CLEAR_ROLL_INTERVAL):
			roll_spacing_ok = false
	check.call(roll_spacing_ok, "連打の間隔が16分(CLEAR_ROLL_INTERVAL)で揃う")
	# クリア音素材が読めてOggVorbisであること。
	var note := load(am.CLEAR_NOTE_PATH) as AudioStream
	check.call(note != null and note is AudioStreamOggVorbis, "クリア音がOggVorbisで読める (%s)" % am.CLEAR_NOTE_PATH)

	# ツリー外(get_tree()==null)でも最初の一打で戻り、落ちないこと。
	am.play_clear_fanfare()
	check.call(true, "ツリー外でも play_clear_fanfare が落ちない")
	am.free()


func _test_translations(check: Callable) -> void:
	TranslationServer.set_locale("ja")
	var chrome_keys := [
		"TITLE_SOUND_TEST", "SOUNDTEST_TITLE", "SOUNDTEST_VOLUME", "SOUNDTEST_BACK",
		"SOUNDTEST_CAT_FANFARE", "SOUNDTEST_CLEAR_FANFARE",
	]
	for category in EXPECTED_CATEGORIES:
		chrome_keys.append("SOUNDTEST_CAT_%s" % category.to_upper())
	var untranslated: Array[String] = []
	for key in chrome_keys:
		if TranslationServer.translate(key) == key:
			untranslated.append(key)
	check.call(untranslated.is_empty(), "サウンドテストの翻訳キーに訳がある (未訳: %s)" % [untranslated])
