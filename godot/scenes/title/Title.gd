extends Control

## 遷移先はMainが決める。Titleは「押された」ことだけ知らせる。
signal start_requested
signal sound_test_requested

@onready var _start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var _language_button: Button = $CenterContainer/VBoxContainer/LanguageButton
@onready var _sound_test_button: Button = $SoundTestButton
## 自機のコマ(手続き描画のDisc)を回転表示する。位置は下のDiscAnchorに合わせる。
@onready var _player_preview: Node2D = $PlayerPreview
@onready var _disc_anchor: Control = $CenterContainer/VBoxContainer/DiscAnchor


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_language_button.pressed.connect(_on_language_pressed)
	_sound_test_button.pressed.connect(_on_sound_test_pressed)

	# コマの縦位置をVBoxの応答レイアウト(縦横で中央寄せ)に追従させる。
	# レイアウト確定はreadyの後なので、resizedで追従しつつ初回はdeferで合わせる。
	_disc_anchor.resized.connect(_reposition_disc)
	_reposition_disc.call_deferred()


## PlayerPreview(Node2D)をDiscAnchor(Control)の中心へ載せる。Titleルートは
## 全画面・原点なので、Anchorのグローバル中心がそのままルートローカル座標になる。
func _reposition_disc() -> void:
	_player_preview.position = _disc_anchor.get_global_rect().get_center()


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
