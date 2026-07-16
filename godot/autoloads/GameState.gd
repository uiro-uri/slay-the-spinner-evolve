extends Node

## 1回のラン（プレイ）の状態を保持するシングルトン。
## Flaskプロトタイプのセッションに相当する。
##
## MVPでは永続化しない（メモリ上のみ）。プロトタイプがサーバー再起動で
## セッションを失っていたのと同じ挙動。セーブ/再開は将来の課題。

## プレイヤーのコマの性能（mass, radius, decay, restitution, rps）。M2で導入。
var player_stats: Resource = null

## 分岐マップとその現在位置。M3で導入。
var map_tree: Variant = null
var current_node_id: int = -1

## 次の戦闘の相手。M3で導入。
var pending_enemy: Variant = null

## このランで獲得したカスタムパーツのID。M4で導入。
var acquired_part_ids: Array[int] = []


func reset_run() -> void:
	player_stats = null
	map_tree = null
	current_node_id = -1
	pending_enemy = null
	acquired_part_ids = []
