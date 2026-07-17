extends Node

## 1回のラン（プレイ）の状態を保持するシングルトン。
## Flaskプロトタイプのセッションに相当する。
##
## MVPでは永続化しない（メモリ上のみ）。プロトタイプがサーバー再起動で
## セッションを失っていたのと同じ挙動。セーブ/再開は将来の課題。

## プレイヤーのコマの性能。パーツを取ると書き換わっていく。
var player_stats: SpinnerStats = null

## 分岐マップと現在位置。現在位置はMapTreeが持つ。
var map_tree: MapTree = null

## 次の戦闘の相手。マップでノードを選んだときに決まる。
var pending_enemy: EnemyData = null

## このランで獲得したカスタムパーツのID。M4で導入。
var acquired_part_ids: Array[int] = []


func reset_run() -> void:
	player_stats = default_player_stats()
	map_tree = MapTree.generate()
	pending_enemy = null
	acquired_part_ids = []


## 初期性能の実体はSpinnerStats.default_player()にある(シミュレーションと共有)。
static func default_player_stats() -> SpinnerStats:
	return SpinnerStats.default_player()
