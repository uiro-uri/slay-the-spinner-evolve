extends Control

## 遷移先はMainが決める。Titleは「押された」ことだけ知らせる。
signal start_requested
signal sound_test_requested

@onready var _start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var _language_button: Button = $CenterContainer/VBoxContainer/LanguageButton
@onready var _sound_test_button: Button = $SoundTestButton


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_language_button.pressed.connect(_on_language_pressed)
	_sound_test_button.pressed.connect(_on_sound_test_pressed)


func _on_start_pressed() -> void:
	# ランの初期化はMainがやる。Titleは押されたことだけ伝える。
	start_requested.emit()


func _on_sound_test_pressed() -> void:
	# 遷移はMainが決める。押されたことだけ伝える。
	sound_test_requested.emit()


func _on_language_pressed() -> void:
	# 切り替え先の言語をボタンに表示する（英語表示中は「日本語」と出る）ため、
	# LANGUAGE_TOGGLEの訳語は意図的に反転させてある。
	var next_locale := "en" if TranslationServer.get_locale().begins_with("ja") else "ja"
	TranslationServer.set_locale(next_locale)
