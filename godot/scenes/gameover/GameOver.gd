extends Control

## 戦闘に負けたときのゲームオーバー画面。
## 遷移先はMainが決める。GameOverは「どちらが押されたか」だけ知らせる。
##
## コンティニューは2択にしてある。same_opponent=真なら負けた相手・負けた出現を
## そっくり据え置いて再戦し(＝狙いを変えた効果だけが結果に出る)、偽なら同レベルの
## 別個体へ替える(＝噛み合わない相手から降りる)。規則の実体はRetryPlan。
signal continue_requested(same_opponent: bool)
signal give_up_requested

@onready var _continues_label: Label = $CenterContainer/VBoxContainer/ContinuesLabel
@onready var _rematch_button: Button = $CenterContainer/VBoxContainer/RematchButton
@onready var _continue_button: Button = $CenterContainer/VBoxContainer/ContinueButton
@onready var _give_up_button: Button = $CenterContainer/VBoxContainer/GiveUpButton


func _ready() -> void:
	_rematch_button.pressed.connect(_on_rematch_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_give_up_button.pressed.connect(_on_give_up_pressed)


## 残りコンティニュー回数を受け取り、表示とボタンの活殺を決める。
## 残0ならコンティニューは選べず、あきらめるだけになる。
func setup(remaining: int) -> void:
	# 残数ラベルは{0}を差し込むので、キーの自動翻訳ではなく手で組み立てる。
	_continues_label.text = tr("GAMEOVER_CONTINUES_LEFT").format([remaining])
	var can_continue := remaining > 0
	_rematch_button.visible = can_continue
	_rematch_button.disabled = not can_continue
	_continue_button.visible = can_continue
	_continue_button.disabled = not can_continue


func _on_rematch_pressed() -> void:
	continue_requested.emit(true)


func _on_continue_pressed() -> void:
	continue_requested.emit(false)


func _on_give_up_pressed() -> void:
	give_up_requested.emit()
