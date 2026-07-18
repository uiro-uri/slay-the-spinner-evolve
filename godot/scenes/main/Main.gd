extends Node

## 画面切り替えのルート。Flask版のルーティング（/, /map, /simulation, /reward）に相当する。
## 各画面はScreenHolderの子として差し替える。
##
## 各画面は「何が起きたか」だけをsignalで知らせ、次にどこへ行くかはここが決める。

const TITLE_SCENE: PackedScene = preload("res://scenes/title/Title.tscn")
const MAP_SCENE: PackedScene = preload("res://scenes/map/MapScreen.tscn")
const BATTLE_SCENE: PackedScene = preload("res://scenes/battle/Battle.tscn")
const REWARD_SCENE: PackedScene = preload("res://scenes/reward/RewardScreen.tscn")
const GAMEOVER_SCENE: PackedScene = preload("res://scenes/gameover/GameOver.tscn")
const GAMECLEAR_SCENE: PackedScene = preload("res://scenes/gameclear/GameClear.tscn")
const SOUNDTEST_SCENE: PackedScene = preload("res://scenes/soundtest/SoundTest.tscn")

@onready var _screen_holder: Node = $ScreenHolder


func _ready() -> void:
	goto_title()


func goto_title() -> void:
	var title := _swap_screen(TITLE_SCENE)
	title.start_requested.connect(_on_start_requested)
	title.sound_test_requested.connect(goto_sound_test)


## タイトルから開くサウンドテスト。戻るでタイトルへ返す。
func goto_sound_test() -> void:
	var sound_test := _swap_screen(SOUNDTEST_SCENE)
	sound_test.back_requested.connect(goto_title)


func _on_start_requested() -> void:
	AudioManager.play("ui_confirm")
	GameState.reset_run()
	goto_map()


func goto_map() -> void:
	var map := _swap_screen(MAP_SCENE)
	map.node_chosen.connect(_on_map_node_chosen)
	map.setup(GameState.map_tree)


## 進む先を選んだら、そのノードに確定済みの敵グループ(1〜3体)と土俵を戦闘へ渡す。
## ここでは再抽選しない（マップ生成時に決めた遭遇をそのまま使う＝表示と実戦が一致）。
func _on_map_node_chosen(coord: Vector2i) -> void:
	if not GameState.map_tree.advance_to(coord):
		push_error("Main: 進めないノードが選ばれた: %s" % coord)
		return
	AudioManager.play("ui_select")
	var node: MapTree.MapNode = GameState.map_tree.nodes[GameState.map_tree.current_coord]
	GameState.pending_enemies = node.enemies
	GameState.pending_field = node.field
	goto_battle()


func goto_battle() -> void:
	var battle := _swap_screen(BATTLE_SCENE)
	battle.finished.connect(_on_battle_finished)


## 負けたらゲームオーバー画面へ。勝てば報酬を選んでマップへ戻る。
func _on_battle_finished(player_won: bool) -> void:
	if not player_won:
		goto_gameover()
		return
	if GameState.map_tree.is_goal():
		# ボスに勝ったらラン終了。クリア画面で締める。
		goto_gameclear()
		return
	goto_reward()


func goto_gameclear() -> void:
	var gameclear := _swap_screen(GAMECLEAR_SCENE)
	gameclear.to_title_requested.connect(_on_gameclear_to_title)
	gameclear.setup(GameState.acquired_part_ids, GameState.continues_left)
	# クリアの締めにファンファーレ。戦闘の勝利ジングルは決着後の余韻中に鳴り終えており、
	# クリア画面は決着から finish_delay 秒ほど後に出るので重ならない。
	AudioManager.play_clear_fanfare()


func _on_gameclear_to_title() -> void:
	AudioManager.play("ui_click")
	goto_title()


func goto_gameover() -> void:
	var gameover := _swap_screen(GAMEOVER_SCENE)
	gameover.continue_requested.connect(_on_continue_requested)
	gameover.give_up_requested.connect(_on_give_up_requested)
	gameover.setup(GameState.continues_left)


## コンティニュー: 回数を1消費し、同じ相手・同じマップ位置で戦闘へ戻る。
## pending_enemiesもcurrent_coordも触らないので、同じグループでそのまま再挑戦になる。
func _on_continue_requested() -> void:
	AudioManager.play("ui_confirm")
	if not GameState.use_continue():
		# 残0で来たら念のためタイトルへ（通常はボタンが隠れて起きない）。
		goto_title()
		return
	goto_battle()


func _on_give_up_requested() -> void:
	AudioManager.play("ui_back")
	goto_title()


func goto_reward() -> void:
	var reward := _swap_screen(REWARD_SCENE)
	reward.part_chosen.connect(_on_part_chosen)
	# 今倒した段のレベルほどレアが出やすい。current_step()は段選択時と同じ値。
	var level := EnemyRoster.level_for_step(GameState.map_tree.current_step())
	reward.setup(CustomPartCatalog.pick_choices(CustomPartCatalog.REWARD_CHOICES, null, level))


func _on_part_chosen(part: CustomPart) -> void:
	AudioManager.play("ui_confirm")
	GameState.apply_part(part)
	goto_map()


func _swap_screen(scene: PackedScene) -> Node:
	for child in _screen_holder.get_children():
		_screen_holder.remove_child(child)
		child.queue_free()
	var screen := scene.instantiate()
	_screen_holder.add_child(screen)
	return screen
