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
@onready var _margin_label: Label = $CenterContainer/VBoxContainer/MarginLabel
@onready var _rematch_button: Button = $CenterContainer/VBoxContainer/RematchButton
@onready var _continue_button: Button = $CenterContainer/VBoxContainer/ContinueButton
@onready var _give_up_button: Button = $CenterContainer/VBoxContainer/GiveUpButton


func _ready() -> void:
	_rematch_button.pressed.connect(_on_rematch_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_give_up_button.pressed.connect(_on_give_up_pressed)


## 残りコンティニュー回数と、負けた相手が残していた回転を受け取る。
## 残0ならコンティニューは選べず、あきらめるだけになる。
##
## enemy_tracks を出すのは、この画面の3択のうち2つ(同じ相手にもう一度／
## 相手を替えて挑む)が**相手をどう扱うか**の選択だから。相手にどこまで届いて
## いたかは戦闘画面のリザルトにしか出ておらず、Mainが画面を差し替えた瞬間に
## 消えていた=残機の数だけを見て3択させていた。空配列(軌跡なし)なら
## 行ごと隠す(RemainingRpsText.opponent_margin_line が空文字を返す)。
func setup(remaining: int, enemy_tracks: Array = []) -> void:
	# 残数ラベルは{0}を差し込むので、キーの自動翻訳ではなく手で組み立てる。
	_continues_label.text = tr("GAMEOVER_CONTINUES_LEFT").format([remaining])
	_margin_label.text = RemainingRpsText.opponent_margin_line(enemy_tracks)
	_margin_label.visible = not _margin_label.text.is_empty()
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
