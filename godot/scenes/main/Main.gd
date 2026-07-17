extends Node

## 画面切り替えのルート。Flask版のルーティング（/, /map, /simulation, /reward）に相当する。
## 各画面はScreenHolderの子として差し替える。

const TITLE_SCENE: PackedScene = preload("res://scenes/title/Title.tscn")

@onready var _screen_holder: Node = $ScreenHolder


func _ready() -> void:
	goto_screen(TITLE_SCENE)


func goto_screen(scene: PackedScene) -> void:
	for child in _screen_holder.get_children():
		_screen_holder.remove_child(child)
		child.queue_free()
	_screen_holder.add_child(scene.instantiate())
