class_name SoundCatalog
extends RefCounted

## SE(効果音)のカタログ。キー→音源パスの対応表を1か所に集約する。
## Node非依存の静的関数だけで構成し、ヘッドレステストから直接検証できる
## (ScreenLayout / SpinnerPhysics と同じ流儀)。
##
## 呼び出し側(AudioManager)はここで解決したパス経由でのみ再生する。生パスを
## あちこちに散らさないための単一の出所。
##
## 素材は Kenney の CC0 効果音(godot/assets/audio/se/<category>/<key>.ogg)。
## key はファイル名の語幹、category はサブフォルダ名。サウンドテストの
## ボタンラベルにも key をそのまま使う。

## SE1件分の定義。
## - key:      再生キー兼サウンドテストの表示名(ファイル名の語幹)
## - category: 分類(サブフォルダ名)。サウンドテストの見出しに使う
## - path:     res:// の音源パス

## カテゴリの並び順。発射→衝突→壁→決着→UI(ゲームの流れ順)。
const CATEGORY_ORDER: Array[String] = ["launch", "impact", "wall", "result", "ui"]

## 全SE。カテゴリごとにまとめ、CATEGORY_ORDER の順で並べておく。
const ENTRIES: Array[Dictionary] = [
	{"key": "scratch_001", "category": "launch", "path": "res://assets/audio/se/launch/scratch_001.ogg"},
	{"key": "switch_001", "category": "launch", "path": "res://assets/audio/se/launch/switch_001.ogg"},

	{"key": "impactMetal_heavy_000", "category": "impact", "path": "res://assets/audio/se/impact/impactMetal_heavy_000.ogg"},
	{"key": "impactMetal_medium_000", "category": "impact", "path": "res://assets/audio/se/impact/impactMetal_medium_000.ogg"},
	{"key": "impactPlate_heavy_000", "category": "impact", "path": "res://assets/audio/se/impact/impactPlate_heavy_000.ogg"},

	{"key": "impactSoft_medium_000", "category": "wall", "path": "res://assets/audio/se/wall/impactSoft_medium_000.ogg"},
	{"key": "impactWood_medium_000", "category": "wall", "path": "res://assets/audio/se/wall/impactWood_medium_000.ogg"},

	{"key": "jingles_HIT00", "category": "result", "path": "res://assets/audio/se/result/jingles_HIT00.ogg"},
	{"key": "jingles_NES00", "category": "result", "path": "res://assets/audio/se/result/jingles_NES00.ogg"},
	{"key": "jingles_NES01", "category": "result", "path": "res://assets/audio/se/result/jingles_NES01.ogg"},
	{"key": "jingles_NES02", "category": "result", "path": "res://assets/audio/se/result/jingles_NES02.ogg"},
	{"key": "jingles_PIZZI00", "category": "result", "path": "res://assets/audio/se/result/jingles_PIZZI00.ogg"},
	{"key": "jingles_PIZZI01", "category": "result", "path": "res://assets/audio/se/result/jingles_PIZZI01.ogg"},

	{"key": "back_001", "category": "ui", "path": "res://assets/audio/se/ui/back_001.ogg"},
	{"key": "click_001", "category": "ui", "path": "res://assets/audio/se/ui/click_001.ogg"},
	{"key": "confirmation_001", "category": "ui", "path": "res://assets/audio/se/ui/confirmation_001.ogg"},
	{"key": "select_001", "category": "ui", "path": "res://assets/audio/se/ui/select_001.ogg"},
]


## 全SEを定義順で返す。
static func all() -> Array[Dictionary]:
	return ENTRIES


## キーから音源パスを引く。無ければ ""(呼び出し側で握りつぶす)。
static func path_for(key: String) -> String:
	for entry in ENTRIES:
		if entry["key"] == key:
			return entry["path"]
	return ""


## カテゴリ名→そのカテゴリのentry配列。CATEGORY_ORDER の順で、空カテゴリは含めない。
## (サウンドテスト画面がこれを回して見出し+ボタンを組む)
static func by_category() -> Dictionary:
	var grouped: Dictionary = {}
	for category in CATEGORY_ORDER:
		var items: Array[Dictionary] = []
		for entry in ENTRIES:
			if entry["category"] == category:
				items.append(entry)
		if not items.is_empty():
			grouped[category] = items
	return grouped


## 出現順のカテゴリ名一覧(実際にentryを持つものだけ)。
static func categories() -> Array[String]:
	var result: Array[String] = []
	for category in CATEGORY_ORDER:
		for entry in ENTRIES:
			if entry["category"] == category:
				result.append(category)
				break
	return result
