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

## 勝った戦闘で倒した頭数ぶん、報酬選択を繰り返す残り回数。
var _rewards_remaining: int = 0

## いま報酬画面に提示している札。選択時に見送り札(選ばなかった残り)を割り出し、
## 次の報酬抽選から除外する(GameState.last_rejected_ids)ために覚えておく。
var _reward_offer: Array[CustomPart] = []

## ランを通して出しっぱなしにするビルド表示HUD。ScreenHolderの外(Main直下)に置いて
## 画面差し替えで消えないようにし、_swap_screenのたびに現在のGameStateへ追従させる。
var _stat_panel: StatPanel


func _ready() -> void:
	_stat_panel = StatPanel.new()
	add_child(_stat_panel)
	goto_title()


func goto_title() -> void:
	# タイトルはランの外なのでビルド表示は出さない。
	var title := _swap_screen(TITLE_SCENE, false)
	title.start_requested.connect(_on_start_requested)
	title.sound_test_requested.connect(goto_sound_test)


## タイトルから開くサウンドテスト。戻るでタイトルへ返す。
func goto_sound_test() -> void:
	# サウンドテストもランの外なのでビルド表示は出さない。
	var sound_test := _swap_screen(SOUNDTEST_SCENE, false)
	sound_test.back_requested.connect(goto_title)


func _on_start_requested() -> void:
	AudioManager.play("ui_confirm")
	GameState.reset_run()
	goto_map()


func goto_map() -> void:
	var map := _swap_screen(MAP_SCENE)
	map.node_chosen.connect(_on_map_node_chosen)
	# 画面には状態を渡す(画面がGameStateを直接見ない)。マップは今のビルドを
	# 進める先の「相手の硬さの取り分」メーターと取得一覧の両方に使う。
	map.setup(GameState.map_tree, GameState.player_stats, GameState.acquired_part_ids)


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
	# 出現(位置・向き・速度)はここで引き直す。以後この種が据え置かれる限り
	# 同じ予告が出るので、負けたあとの「同じ相手に挑む」が本当の再戦になる。
	GameState.roll_spawn_seed()
	goto_battle()


func goto_battle() -> void:
	# ビルド表示に「この部屋の相手はどれだけ硬いか」を出すため、相手のstatsを渡す。
	# 戦闘画面へ入るときだけ渡すこと(pending_enemiesは次の戦闘まで消えないので、
	# StatPanelがGameStateを直接見るとマップ画面に前の相手が残る)。
	var battle := _swap_screen(BATTLE_SCENE, true, _pending_enemy_stats())
	battle.finished.connect(_on_battle_finished)


## これから戦う相手のステータス一覧。StatPanelの取り分バーに渡す。
func _pending_enemy_stats() -> Array[SpinnerStats]:
	var out: Array[SpinnerStats] = []
	for enemy in GameState.pending_enemies:
		if enemy != null and enemy.stats != null:
			out.append(enemy.stats)
	return out


## 負けたらゲームオーバー画面へ。勝てば報酬を選んでマップへ戻る。
func _on_battle_finished(
	player_won: bool, knockout: bool, enemy_tracks: Array
) -> void:
	if not player_won:
		# 相手の軌跡を持って行く。ゲームオーバー画面の3択のうち2つは「相手をどう
		# 扱うか」なのに、Battleごと差し替わるせいで相手の情報が画面から消えていた。
		goto_gameover(enemy_tracks)
		return
	if GameState.map_tree.is_goal():
		# ボスに勝ったらラン終了。クリア画面で締める。
		goto_gameclear()
		return
	# 勝利の勢いで回転が少し成長する。接触で仕留めた勝ち(knockout)は撃破ボーナスで
	# 大きく育つ。報酬選択より先(倍率札は成長込みに掛かる)。
	GameState.grow_after_victory(knockout)
	# 倒した頭数だけ報酬を選ぶ。乱戦はrps据え置きで手強いぶん、見返りも頭数ぶん。
	_rewards_remaining = maxi(GameState.pending_enemies.size(), 1)
	goto_reward()


func goto_gameclear() -> void:
	# 勝ち切ったので連続クリア記録を伸ばす。setupの前に加算し、加算後の値を画面へ渡す。
	GameState.record_clear()
	var gameclear := _swap_screen(GAMECLEAR_SCENE)
	gameclear.to_title_requested.connect(_on_gameclear_to_title)
	gameclear.setup(GameState.acquired_part_ids, GameState.continues_left, GameState.clear_streak)
	# クリアの締めにファンファーレ。戦闘の勝利ジングルは決着後の余韻中に鳴り終えており、
	# クリア画面は決着から finish_delay 秒ほど後に出るので重ならない。
	AudioManager.play_clear_fanfare()


func _on_gameclear_to_title() -> void:
	AudioManager.play("ui_click")
	goto_title()


## enemy_tracksは負けた相手の軌跡(Battle.finished が渡す)。
## 既定の空配列は「軌跡が無い＝行を出さない」。
func goto_gameover(enemy_tracks: Array = []) -> void:
	var gameover := _swap_screen(GAMEOVER_SCENE)
	gameover.continue_requested.connect(_on_continue_requested)
	gameover.give_up_requested.connect(_on_give_up_requested)
	gameover.setup(GameState.continues_left, enemy_tracks)


## コンティニュー: 回数を1消費し、同じマップ位置で戦闘へ戻る。相手を据え置くか
## 引き直すかはプレイヤーが選ぶ(same_opponent。規則はRetryPlanに1つだけ置き、
## コールドプレイCLIも同じものを通る)。
##
## 「同じ相手に挑む」は個体も出現の種も据え置くので、負けた立ち合いがそっくり
## 再現される＝狙いを変えた効果だけが結果に出る。「相手を替えて挑む」は同レベルの
## 別個体へ入れ替え、出現も引き直す(従来の挙動＝噛み合わない相手から降りる逃げ道)。
## どちらもレベル・頭数は保たれるので、マップ表示も報酬(node.level())も嘘にならない。
## ノード自体(node.enemies)は触らず、この戦闘のpending_enemiesだけを差し替える。
## current_coordも触らない。
func _on_continue_requested(same_opponent: bool) -> void:
	AudioManager.play("ui_confirm")
	if not GameState.use_continue():
		# 残0で来たら念のためタイトルへ（通常はボタンが隠れて起きない）。
		goto_title()
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	GameState.pending_enemies = RetryPlan.next_enemies(
		GameState.pending_enemies, same_opponent, rng)
	GameState.pending_spawn_seed = RetryPlan.next_spawn_seed(
		GameState.pending_spawn_seed, same_opponent, rng)
	goto_battle()


func _on_give_up_requested() -> void:
	# ランを勝ち切れずに終えたので連続クリア記録は途切れる。
	GameState.break_streak()
	AudioManager.play("ui_back")
	goto_title()


func goto_reward() -> void:
	var reward := _swap_screen(REWARD_SCENE)
	reward.part_chosen.connect(_on_part_chosen)
	# 今倒した敵のレベルほどレアが出やすい。段の名目レベルでなくノードの実レベル
	# (MapNode.level)を使う: 斥候(次レベルの単体エリート)を倒したときの見返りを
	# 実レベル準拠にするため。RunSimも同じく実レベルで抽選している(record["level"])。
	# 現在のステータスと残機を渡し、上限到達で効果ゼロの死にカードは提示しない。
	# 直前の画面で見送った札も除外し、同じ顔ぶれの連続を防ぐ。
	# 乱戦(複数体ノード)は報酬枚数だけでなく質も上がる: RAREの重みが頭数倍
	# (CustomPartCatalog.rare_weight_for)。危険な部屋の見返りを質でも釣り合わせる。
	# RAREの空振りが続いていれば天井が発動して1枚保証される(GameState.rare_drought)。
	var node: MapTree.MapNode = GameState.map_tree.nodes[GameState.map_tree.current_coord]
	var level := node.level()
	_reward_offer = CustomPartCatalog.pick_choices(
		CustomPartCatalog.REWARD_CHOICES, null, level,
		GameState.player_stats, GameState.continues_left,
		GameState.last_rejected_ids, node.enemy_count(), GameState.rare_drought
	)
	# 空振りの数え直しは「提示した時点」で確定する。選んだかどうかは関係ない
	# (天井が保証するのは提示であって取得ではない)。
	GameState.rare_drought = CustomPartCatalog.next_rare_drought(
		GameState.rare_drought, _reward_offer
	)
	# 今のビルドを渡す。カードごとの「取ると硬さ・寿命がどう動くか」(PartPreview)の
	# 基準になる。残機とゴーストの合計秒は、コマの性能を変えない札(残機・無敵)でも
	# 見積もりが空にならないよう添える。
	# 最後の1つは攻めの行の基準になる相手——**次に踏みうる部屋のいちばん硬い1体**。
	# 守りの3行(硬さ・打たれ強さ・壁強さ)は相手を括り出せるが攻めは括り出せず、
	# 相手を渡さないと EDGE/DRILL が「1行も動かない札」になる(PartPreview.attack)。
	# ここで渡せるのは、報酬を選ぶ時点で map_tree が既に今のノードまで進んでいて
	# next_coords() が次の分岐を返すため。決戦のあとは進める先が無く -1 が返り、
	# 攻めの行は出ない。
	reward.setup(
		_reward_offer, GameState.player_stats, GameState.continues_left,
		CustomPartCatalog.total_ghost_seconds(GameState.acquired_part_ids),
		ThreatMeter.reachable_hardest_toughness(GameState.map_tree)
	)


func _on_part_chosen(part: CustomPart) -> void:
	AudioManager.play("ui_confirm")
	GameState.last_rejected_ids = CustomPartCatalog.rejected_ids(_reward_offer, part.id)
	GameState.apply_part(part)
	# まだ倒した頭数ぶんの報酬が残っていれば、次の報酬選択へ。無ければマップへ戻る。
	_rewards_remaining -= 1
	if _rewards_remaining > 0:
		goto_reward()
		return
	goto_map()


## 画面を差し替える。show_stats=true(既定)のときはビルド表示HUDを今のGameStateへ
## 更新して見せ、ランの外の画面(タイトル/サウンドテスト)はfalseで隠す。
## enemy_stats を渡すと、その相手との硬さ・寿命の取り分もHUDに並ぶ(戦闘画面だけ)。
func _swap_screen(
	scene: PackedScene, show_stats: bool = true, enemy_stats: Array[SpinnerStats] = []
) -> Node:
	for child in _screen_holder.get_children():
		_screen_holder.remove_child(child)
		child.queue_free()
	var screen := scene.instantiate()
	_screen_holder.add_child(screen)
	if show_stats:
		_stat_panel.refresh(enemy_stats)
	else:
		_stat_panel.hide_panel()
	return screen
