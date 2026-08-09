extends Node

## 1回のラン（プレイ）の状態を保持するシングルトン。
## Flaskプロトタイプのセッションに相当する。
##
## MVPでは永続化しない（メモリ上のみ）。プロトタイプがサーバー再起動で
## セッションを失っていたのと同じ挙動。セーブ/再開は将来の課題。

## 1ランで使えるコンティニュー回数。0になると「あきらめる」だけになる。
const MAX_CONTINUES := 3

## プレイヤーのコマの性能。パーツを取ると書き換わっていく。
var player_stats: SpinnerStats = null

## 分岐マップと現在位置。現在位置はMapTreeが持つ。
var map_tree: MapTree = null

## 次の戦闘の相手。マップでノードを選んだときに決まる。複数体の乱戦もありうる。
var pending_enemies: Array[EnemyData] = []

## 次の戦闘の土俵。相手と同じくマップでノードを選んだときに決まる。
var pending_field: FieldData = null

## 次の戦闘で敵の出現(位置・向き・速度・乱戦の回り込み)を決める種。Battleは乱数の
## 種にこれを使うので、**種が同じなら立ち合いはそっくり同じ**になる。マップで
## ノードを選ぶたびに引き直し、負けたあと「同じ相手に挑む」を選んだときだけ
## 据え置く(RetryPlan)。据え置きが要るのは、リトライで相手も出現も入れ替わると
## 勝てたときに「自分が上手くなったのか引きが良かったのか」が分からないため。
var pending_spawn_seed: int = 0

## このランで獲得したカスタムパーツのID。M4で導入。
var acquired_part_ids: Array[int] = []

## このランで残っているコンティニュー回数。0で打ち止め。
var continues_left: int = MAX_CONTINUES

## 直前の報酬画面で見送った(提示されたが選ばなかった)札のID。
## 次の報酬抽選(CustomPartCatalog.pick_choices)がこれを除外して、同じ顔ぶれが
## 画面をまたいで続くのを防ぐ。取った札は入らない=重ね取り戦略は妨げない。
var last_rejected_ids: Array[int] = []

## RAREを1枚も含まなかった報酬提示が続いた回数。天井
## (CustomPartCatalog.RARE_PITY_OFFERS)に達すると次の提示でRAREが1枚保証される。
## 提示のたびにCustomPartCatalog.next_rare_droughtで更新する。ランの状態なので
## reset_run()で0へ戻る。
var rare_drought: int = 0

## 直前に終えた戦いで、自分の回転がどこへ消えたかの機構別内訳
## (BattleResult.player_rps_loss)。報酬画面が軽減札の選択材料として割合で出し
## (RpsLossText.share_line)、**次の戦いの発射前**にも据え置きで出す
## (RpsLossText.carryover_line)。1戦も終えていないうちは空＝どちらの行も出ない。
##
## Mainのローカル変数ではなくここに置くのは、報酬画面だけでなく**画面を2つまたいだ
## 次の戦闘**が読むため。Battleは_ready()の時点でこれを読むので、Mainが
## instantiate後に差し込む形では間に合わない。
var last_battle_rps_loss: Dictionary = {}

## 連続クリア記録（連勝数）。ランをまたいで持ち越すので reset_run() では消さない。
## クリアで +1、ギブアップ（ランを勝ち切れず終了）で 0 に戻る。メモリ上のみ＝
## アプリを閉じると消えるのは、このプロジェクトのセーブなし方針に合わせている。
var clear_streak: int = 0


func _ready() -> void:
	# ランの外から戦闘に入る場合(Battle.tscn単体起動など)でも出現が毎回変わるように、
	# 起動時に1回引いておく。ランに入れば reset_run()/マップ選択が引き直す。
	roll_spawn_seed()


func reset_run() -> void:
	player_stats = default_player_stats()
	map_tree = MapTree.generate()
	pending_enemies = []
	pending_field = null
	acquired_part_ids = []
	continues_left = MAX_CONTINUES
	last_rejected_ids = []
	rare_drought = 0
	last_battle_rps_loss = {}
	roll_spawn_seed()


## 次の立ち合いの出現を引き直す。マップでノードを選んだときに呼ぶ。
## リトライ時の引き直しは RetryPlan.next_spawn_seed が受け持つ(据え置きと対になる)。
func roll_spawn_seed() -> void:
	pending_spawn_seed = randi()


## 選んだパーツをランに適用する。ステータス強化と残機の引き上げ、取得記録をまとめる。
## 残機はmaxiで底上げのみ（既に多ければ下げない＝報酬は全部プラス）。ステータス札は
## lives=0なのでmaxiは無害。
func apply_part(part: CustomPart) -> void:
	part.apply_to(player_stats)
	continues_left = maxi(continues_left, part.lives)
	acquired_part_ids.append(part.id)


## 戦闘に勝つたびに呼ぶ。回転が少しだけ確実に成長する(SpinnerStats.grow_rps_by_victory)。
## knockout=真(接触で決着)なら撃破ボーナスで成長が大きい。
## 報酬札より先に適用する(倍率札はこの成長込みのrpsに掛かる)。
func grow_after_victory(knockout: bool = false) -> void:
	player_stats.grow_rps_by_victory(knockout)


## ボスを倒してランを勝ち切ったときに呼ぶ。連続クリア記録を1伸ばす。
func record_clear() -> void:
	clear_streak += 1


## ランを勝ち切れずに終えたとき（あきらめ）に呼ぶ。連続クリア記録が途切れて0に戻る。
func break_streak() -> void:
	clear_streak = 0


## コンティニューを1回消費する。残0なら何もせずfalse。
func use_continue() -> bool:
	if continues_left <= 0:
		return false
	continues_left -= 1
	return true


## 初期性能の実体はSpinnerStats.default_player()にある(シミュレーションと共有)。
static func default_player_stats() -> SpinnerStats:
	return SpinnerStats.default_player()
