extends Control

## 遷移先はMainが決める。Titleは「押された」ことだけ知らせる。
signal start_requested
signal sound_test_requested

@onready var _streak_label: Label = $CenterContainer/VBoxContainer/StreakLabel
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

	# 現在の連続クリア記録。まだ1回も勝ち切っていない(0)ならラベルごと隠して
	# タイトルをすっきりさせる。1以上のときだけ「連続クリア: N」を出す。
	_refresh_streak()

	# コマの縦位置をVBoxの応答レイアウト(縦横で中央寄せ)に追従させる。
	# レイアウト確定はreadyの後なので、resizedで追従しつつ初回はdeferで合わせる。
	_disc_anchor.resized.connect(_reposition_disc)
	_reposition_disc.call_deferred()


## PlayerPreview(Node2D)をDiscAnchor(Control)の中心へ載せる。Titleルートは
## 全画面・原点なので、Anchorのグローバル中心がそのままルートローカル座標になる。
func _reposition_disc() -> void:
	_player_preview.position = _disc_anchor.get_global_rect().get_center()


## 連続クリア記録ラベルを現在値で更新する。0なら非表示、1以上なら文言を入れて表示。
func _refresh_streak() -> void:
	var streak: int = GameState.clear_streak
	_streak_label.visible = streak > 0
	if _streak_label.visible:
		_streak_label.text = format_streak(streak)


## 表示ロジックはヘッドレスで検証できるよう純関数に切り出す（GameClearと同じ流儀）。
## クリア画面と共通のSTREAKキーを引く。
static func format_streak(clear_streak: int) -> String:
	return TranslationServer.translate("STREAK").format([clear_streak])


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
