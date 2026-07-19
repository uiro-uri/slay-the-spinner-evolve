extends Control

## ボス(ゴール)に勝ってランを勝ち切ったときのゲームクリア画面。
## 締めに簡単なリザルトサマリ(コンティニュー残数)＋取得パーツ一覧を出す。
## 遷移先はMainが決める。GameClearは「タイトルへ押された」ことだけ知らせる。
signal to_title_requested

@onready var _continues_label: Label = $CenterContainer/VBoxContainer/ContinuesLabel
@onready var _streak_label: Label = $CenterContainer/VBoxContainer/StreakLabel
@onready var _acquired_list: GridContainer = $CenterContainer/VBoxContainer/List
@onready var _to_title_button: Button = $CenterContainer/VBoxContainer/ToTitleButton


func _ready() -> void:
	_to_title_button.pressed.connect(_on_to_title_pressed)


## 取得パーツは2列で並べる。パーツは最大5種なのでスクロールさせず全部見せられる。
const COLUMNS := 2


## ランの結果を受け取り、サマリ(コンティニュー残数)＋取得アップグレード一覧を組み立てる。
## {0}を差し込むラベルはキーの自動翻訳ではなく手で組み立てる(GameOverと同じ流儀)。
## 一覧はマップの「取得済み」パネルと同じ AcquiredUpgradeList を使う。
func setup(acquired_ids: Array[int], continues_left: int, clear_streak: int) -> void:
	_continues_label.text = format_continues(continues_left)
	_streak_label.text = format_streak(clear_streak)
	# 締めのサマリなので効果説明は省き、名前だけを詰めて並べる(show_description=false)。
	AcquiredUpgradeList.populate(_acquired_list, acquired_ids, false)
	_acquired_list.columns = COLUMNS


## 表示ロジックはヘッドレスで検証できるよう純関数に切り出す。
## (この repo は表示文言も純関数でテストする流儀)
## tr()はインスタンスメソッドで静的から呼べないため、現在ロケールを引く
## TranslationServer.translate()で解決する(このキーに文脈はないので等価)。
static func format_continues(continues_left: int) -> String:
	return TranslationServer.translate("GAMECLEAR_CONTINUES_LEFT").format([continues_left])


## 連続クリア記録の文言。タイトル画面と共通のSTREAKキーを引く（同じ概念を2画面で見せる）。
static func format_streak(clear_streak: int) -> String:
	return TranslationServer.translate("STREAK").format([clear_streak])


func _on_to_title_pressed() -> void:
	to_title_requested.emit()
