extends RefCounted

## Battle.gd(実UI)の@export既定値と BattleRequest の既定値の一致を照合する。
##
## 戦闘の調整値は実UI(Battle.tscn→Battle.gd)・bot統計(battle_sim)・コールドプレイ
## CLI(naive_play)の3経路で使われるが、後2者はBattleRequest.new()の既定値を
## そのまま使う。片方だけ変えると「CLIと実ゲームが別のゲームになる」——
## naive_playの発射速度が実ゲームの1.67倍だったハーネスの嘘(2026-07-21)と
## 同型の事故がバランス定数でも起きうるので、ここで機械的に封じる。
##
## Battle.gdはautoload(GameState)を参照するためヘッドレスの--scriptモードでは
## コンパイルできず、new()して実値を読むことができない。そこでソーステキストから
## 「var <名前>: float = <数値>」を抽出して比較する。書式が変わったら抽出失敗が
## そのままFAILになる(黙って素通りはしない)。あわせてBattle.tscnが@exportを
## 上書きしていないことも確認する(上書きされるとスクリプト既定値の照合では
## 実ゲームの値を保証できなくなるため)。

const BATTLE_SRC := "res://scenes/battle/Battle.gd"
const REQUEST_SRC := "res://scripts/battle/battle_request.gd"
const SCENE_SRC := "res://scenes/battle/Battle.tscn"

## 3経路で共有する数値ノブ。ここに載せた名前だけ照合する。
const KNOBS: Array[String] = [
	"stage_strength",
	"violence",
	"spin_kick_scale",
	"natural_damping",
	"wall_damping",
	"wall_impact_ref_speed",
	"lose_threshold",
]


func run(check: Callable) -> void:
	_test_defaults_match(check)
	_test_scene_has_no_overrides(check)


## ソースから「var <名前>: float = <数値>」の右辺を抜く。見つからなければNAN。
static func default_of(source: String, knob: String) -> float:
	var pattern := "var %s: float = " % knob
	var at := source.find(pattern)
	if at < 0:
		return NAN
	var rest := source.substr(at + pattern.length())
	var line := rest.get_slice("\n", 0).strip_edges()
	if not line.is_valid_float():
		return NAN
	return line.to_float()


func _test_defaults_match(check: Callable) -> void:
	var battle_src := FileAccess.get_file_as_string(BATTLE_SRC)
	var request_src := FileAccess.get_file_as_string(REQUEST_SRC)
	check.call(battle_src != "", "Battle.gd を読めた")
	check.call(request_src != "", "battle_request.gd を読めた")

	for knob in KNOBS:
		var in_battle := default_of(battle_src, knob)
		var in_request := default_of(request_src, knob)
		check.call(
			is_finite(in_battle) and is_finite(in_request)
				and is_equal_approx(in_battle, in_request),
			"%s: Battle.gd(%s) と BattleRequest(%s) の既定値が一致" % [knob, in_battle, in_request]
		)


## Battle.tscnがノブを上書きしていないこと。上書きが必要になったら、
## BattleRequest側も揃えた上でこのテストをシーンの値を読む形に直すこと。
func _test_scene_has_no_overrides(check: Callable) -> void:
	var scene_src := FileAccess.get_file_as_string(SCENE_SRC)
	check.call(scene_src != "", "Battle.tscn を読めた")
	for knob in KNOBS:
		check.call(
			not scene_src.contains("%s = " % knob),
			"Battle.tscn が %s を上書きしていない" % knob
		)
