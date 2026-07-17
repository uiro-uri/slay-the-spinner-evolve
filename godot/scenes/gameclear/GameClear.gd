extends Control

## ボス(ゴール)に勝ってランを勝ち切ったときのゲームクリア画面。
## 締めに簡単なリザルトサマリ(取得パーツ数・コンティニュー残数)を出す。
## 遷移先はMainが決める。GameClearは「タイトルへ押された」ことだけ知らせる。
signal to_title_requested

@onready var _parts_label: Label = $CenterContainer/VBoxContainer/PartsLabel
@onready var _continues_label: Label = $CenterContainer/VBoxContainer/ContinuesLabel
@onready var _to_title_button: Button = $CenterContainer/VBoxContainer/ToTitleButton


func _ready() -> void:
	_to_title_button.pressed.connect(_on_to_title_pressed)


## ランの結果を受け取り、サマリ2行を組み立てる。
## {0}を差し込むラベルはキーの自動翻訳ではなく手で組み立てる(GameOverと同じ流儀)。
func setup(parts_count: int, continues_left: int) -> void:
	_parts_label.text = format_parts(parts_count)
	_continues_label.text = format_continues(continues_left)


## 表示ロジックはヘッドレスで検証できるよう純関数に切り出す。
## (この repo は表示文言も純関数でテストする流儀)
## tr()はインスタンスメソッドで静的から呼べないため、現在ロケールを引く
## TranslationServer.translate()で解決する(このキーに文脈はないので等価)。
static func format_parts(parts_count: int) -> String:
	return TranslationServer.translate("GAMECLEAR_PARTS").format([parts_count])


static func format_continues(continues_left: int) -> String:
	return TranslationServer.translate("GAMECLEAR_CONTINUES_LEFT").format([continues_left])


func _on_to_title_pressed() -> void:
	to_title_requested.emit()
