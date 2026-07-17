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

@onready var _screen_holder: Node = $ScreenHolder


func _ready() -> void:
	goto_title()


func goto_title() -> void:
	var title := _swap_screen(TITLE_SCENE)
	title.start_requested.connect(_on_start_requested)


func _on_start_requested() -> void:
	GameState.reset_run()
	goto_map()


func goto_map() -> void:
	var map := _swap_screen(MAP_SCENE)
	map.node_chosen.connect(_on_map_node_chosen)
	map.setup(GameState.map_tree)


## 進む先を選んだら、その段にふさわしい敵と土俵を決めて戦闘へ。
func _on_map_node_chosen(coord: Vector2i) -> void:
	if not GameState.map_tree.advance_to(coord):
		push_error("Main: 進めないノードが選ばれた: %s" % coord)
		return
	var step := GameState.map_tree.current_step()
	GameState.pending_enemy = EnemyRoster.pick_for_step(step)
	GameState.pending_field = FieldRoster.pick_for_step(step)
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
		# ボスに勝ったらラン終了。TODO: クリア画面。
		goto_title()
		return
	goto_reward()


func goto_gameover() -> void:
	var gameover := _swap_screen(GAMEOVER_SCENE)
	gameover.continue_requested.connect(_on_continue_requested)
	gameover.give_up_requested.connect(_on_give_up_requested)
	gameover.setup(GameState.continues_left)


## コンティニュー: 回数を1消費し、同じ相手・同じマップ位置で戦闘へ戻る。
## pending_enemyもcurrent_coordも触らないので、そのまま再挑戦になる。
func _on_continue_requested() -> void:
	if not GameState.use_continue():
		# 残0で来たら念のためタイトルへ（通常はボタンが隠れて起きない）。
		goto_title()
		return
	goto_battle()


func _on_give_up_requested() -> void:
	goto_title()


func goto_reward() -> void:
	var reward := _swap_screen(REWARD_SCENE)
	reward.part_chosen.connect(_on_part_chosen)
	reward.setup(CustomPartCatalog.pick_choices(CustomPartCatalog.REWARD_CHOICES))


func _on_part_chosen(part: CustomPart) -> void:
	part.apply_to(GameState.player_stats)
	GameState.acquired_part_ids.append(part.id)
	goto_map()


func _swap_screen(scene: PackedScene) -> Node:
	for child in _screen_holder.get_children():
		_screen_holder.remove_child(child)
		child.queue_free()
	var screen := scene.instantiate()
	_screen_holder.add_child(screen)
	return screen
