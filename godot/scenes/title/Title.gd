extends Control

@onready var _start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var _language_button: Button = $CenterContainer/VBoxContainer/LanguageButton


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_language_button.pressed.connect(_on_language_pressed)


func _on_start_pressed() -> void:
	# M3でマップ画面へ遷移させる。
	GameState.reset_run()


func _on_language_pressed() -> void:
	# 切り替え先の言語をボタンに表示する（英語表示中は「日本語」と出る）ため、
	# LANGUAGE_TOGGLEの訳語は意図的に反転させてある。
	var next_locale := "en" if TranslationServer.get_locale().begins_with("ja") else "ja"
	TranslationServer.set_locale(next_locale)
