extends RefCounted

## ゲームオーバー画面(GameOver.tscn)を実体化して、3択の画面に**相手の情報が
## 載っていること**を確かめる。
##
## このリポジトリのテストは基本的に純関数を突くが、この1本だけは実体化する。
## 理由: 文言の組み立て(RemainingRpsText.opponent_margin_line)は
## test_remaining_rps_text が押さえているので、ここで壊れうるのは
## **文言と画面の間の配線**しかない——tscnからラベルを消す/setupで代入し忘れる。
## 純関数テストはそのどちらも赤にしない。
##
## 画面を出す理由そのもの: 敗北画面の3択のうち2つ(同じ相手にもう一度／
## 相手を替えて挑む)は**相手をどう扱うか**の選択なのに、Battleごと差し替わる
## せいで相手に届いていた度合いが画面から消え、残機の数だけで選ばされていた。

const _BASE := "CenterContainer/VBoxContainer/"
const _MARGIN := _BASE + "MarginLabel"


func run(check: Callable) -> void:
	var saved_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("ja")
	_test_margin_shown(check)
	_test_margin_hidden_without_tracks(check)
	_test_buttons_follow_continues(check)
	TranslationServer.set_locale(saved_locale)


## 相手の残量を渡すと、その数字が画面のラベルに載って見える状態になる。
func _test_margin_shown(check: Callable) -> void:
	var panel := _make(check, 3, [_frames([38.6, 1.9])])
	if panel == null:
		return
	var label: Label = panel.get_node(_MARGIN)
	check.call(label.visible, "相手の残量があるとラベルが見える")
	check.call(label.text.contains("1.9"), "実数がラベルに載る: %s" % label.text)
	check.call(label.text.contains("5"), "割合(5%)がラベルに載る: %s" % label.text)
	# キーが素通りしていたら、tscnの初期値がそのまま残っている(setupが代入していない)。
	check.call(
		not label.text.contains("GAMEOVER_MARGIN"),
		"tscnの初期値のままになっていない: %s" % label.text
	)
	# 残機ラベルも同時に見る: 片方だけ配線されている状態を通さない。
	var continues: Label = panel.get_node(_BASE + "ContinuesLabel")
	check.call(continues.text.contains("3"), "残機がラベルに載る: %s" % continues.text)
	_dispose(panel)


## 軌跡を持たない結果(空配列)ではラベルごと隠れる。
## 空文字のラベルを見せたままだと、VBoxの隙間だけが空いて画面が間延びする。
func _test_margin_hidden_without_tracks(check: Callable) -> void:
	var panel := _make(check, 2, [])
	if panel == null:
		return
	var label: Label = panel.get_node(_MARGIN)
	check.call(label.text == "", "軌跡なしなら空文字")
	check.call(not label.visible, "軌跡なしならラベルごと隠れる")
	_dispose(panel)


## 既存の約束(残0ならコンティニューを選べない)を、行を1本足しても壊していない。
func _test_buttons_follow_continues(check: Callable) -> void:
	var alive := _make(check, 1, [_frames([40.0, 4.0])])
	if alive == null:
		return
	check.call(
		alive.get_node(_BASE + "RematchButton").visible,
		"残機があれば「同じ相手にもう一度」が押せる"
	)
	_dispose(alive)

	var spent := _make(check, 0, [_frames([40.0, 4.0])])
	if spent == null:
		return
	check.call(
		not spent.get_node(_BASE + "RematchButton").visible,
		"残機0なら「同じ相手にもう一度」は出ない"
	)
	check.call(
		not spent.get_node(_BASE + "ContinueButton").visible,
		"残機0なら「相手を替えて挑む」も出ない"
	)
	# 惜しい負けでも残機0なら挑めない。行が増えても案内だけが浮かない。
	check.call(
		spent.get_node(_BASE + "GiveUpButton").visible,
		"残機0でもあきらめるは押せる"
	)
	_dispose(spent)


## 画面を実体化してsetupまで通す。行が無ければ null を返す(呼び手は打ち切る)。
##
## @onready の代入は NOTIFICATION_READY で走るので、ツリーへ入れる代わりに
## その通知だけを直に送る。ツリーへ add_child すると、テストランナーは
## 1フレームも回さずに quit() するため解放が最後まで走り切らず、実行のたびに
## 「CanvasItem RIDs were leaked / ObjectDB instances were leaked」が出る
## (実測: 1テストにつき画面1枚ぶん)。テストのログにエラー行を常駐させると
## **本物のエラーがそこに紛れる**ので、ツリーに入れない形にしてある。
##
## setup の前に行の存在を名指しで確かめるのは、行が消えたサボタージュで
## setup 側が null への代入で落ち、GDScriptの実行時エラーが**その先の検査を
## 黙って飛ばす**ため(journal 2026-08-06 で同じ踏み方をしている)。
## 先に1件の素直な失敗にしておけば、行が消えたことがログの先頭で読める。
func _make(check: Callable, continues: int, enemy_tracks: Array) -> Control:
	var panel: Control = load("res://scenes/gameover/GameOver.tscn").instantiate()
	panel.notification(Node.NOTIFICATION_READY)
	if panel.get_node_or_null(_MARGIN) == null:
		check.call(false, "ゲームオーバー画面に相手の残量の行(MarginLabel)がある")
		panel.free()
		return null
	panel.setup(continues, enemy_tracks)
	return panel


func _dispose(panel: Control) -> void:
	panel.free()


## rpsの並びから軌跡(Snapshotの配列)を作る。位置・速度はこの行が読まないので固定値。
func _frames(rps_values: Array) -> Array:
	var frames: Array = []
	for rps in rps_values:
		frames.append(BattleResult.Snapshot.new(Vector2.ZERO, Vector2.ZERO, float(rps)))
	return frames
