extends Control

## 戦闘に負けたときのゲームオーバー画面。
## 遷移先はMainが決める。GameOverは「どちらが押されたか」だけ知らせる。
signal continue_requested
signal give_up_requested

@onready var _continues_label: Label = $CenterContainer/VBoxContainer/ContinuesLabel
@onready var _continue_button: Button = $CenterContainer/VBoxContainer/ContinueButton
@onready var _give_up_button: Button = $CenterContainer/VBoxContainer/GiveUpButton


func _ready() -> void:
	_continue_button.pressed.connect(_on_continue_pressed)
	_give_up_button.pressed.connect(_on_give_up_pressed)


## 残りコンティニュー回数を受け取り、表示とボタンの活殺を決める。
## 残0ならコンティニューは選べず、あきらめるだけになる。
func setup(remaining: int) -> void:
	# 残数ラベルは{0}を差し込むので、キーの自動翻訳ではなく手で組み立てる。
	_continues_label.text = tr("GAMEOVER_CONTINUES_LEFT").format([remaining])
	var can_continue := remaining > 0
	_continue_button.visible = can_continue
	_continue_button.disabled = not can_continue


func _on_continue_pressed() -> void:
	continue_requested.emit()


func _on_give_up_pressed() -> void:
	give_up_requested.emit()
