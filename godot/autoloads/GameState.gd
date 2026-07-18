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

## このランで獲得したカスタムパーツのID。M4で導入。
var acquired_part_ids: Array[int] = []

## このランで残っているコンティニュー回数。0で打ち止め。
var continues_left: int = MAX_CONTINUES


func reset_run() -> void:
	player_stats = default_player_stats()
	map_tree = MapTree.generate()
	pending_enemies = []
	pending_field = null
	acquired_part_ids = []
	continues_left = MAX_CONTINUES


## 選んだパーツをランに適用する。ステータス強化と残機の引き上げ、取得記録をまとめる。
## 残機はmaxiで底上げのみ（既に多ければ下げない＝報酬は全部プラス）。ステータス札は
## lives=0なのでmaxiは無害。
func apply_part(part: CustomPart) -> void:
	part.apply_to(player_stats)
	continues_left = maxi(continues_left, part.lives)
	acquired_part_ids.append(part.id)


## コンティニューを1回消費する。残0なら何もせずfalse。
func use_continue() -> bool:
	if continues_left <= 0:
		return false
	continues_left -= 1
	return true


## 初期性能の実体はSpinnerStats.default_player()にある(シミュレーションと共有)。
static func default_player_stats() -> SpinnerStats:
	return SpinnerStats.default_player()
