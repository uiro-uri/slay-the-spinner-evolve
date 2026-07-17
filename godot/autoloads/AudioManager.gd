extends Node

## 効果音(SE)の唯一の窓口。呼び出し側は生の stream を持たず、キーで鳴らす:
## AudioManager.play("impact") のように。ブラウザ・ネイティブ・ヘッドレステストを
## 同じコードベースで走らせるので、キーの存在確認や再生失敗の握りつぶしはここへ
## 閉じ込める(呼び出し側は落ちない)。詳しくは docs/se.md。
##
## 音は3系統ある:
##  - ワンショット(操作音・衝突音・発射音・勝敗音): 素材(ogg)をキーで鳴らす。
##    同時発音できるよう AudioStreamPlayer をプールし、ラウンドロビンで回す。
##  - 回転音: バトル中ずっと鳴る連続音。専用素材が無いので ToneSynth が合成する。
##    rps に応じて周波数・振幅が変わる(AudioLevels)。
##  - チャージ音: 引っ張っている間の連続音。引き量に応じて変わる。
##
## GameState.gd と同じく project.godot の [autoload] に登録する。

## 同時に鳴らせるワンショットの数。衝突音が連続で重なっても切れないよう少し多め。
const POOL_SIZE := 8

## SE/BGM のオーディオバス名。将来 BGM を入れるとき音量を別管理できるよう最初から分ける。
const SE_BUS := "SE"
const BGM_BUS := "BGM"

## キー→素材。配列のときは鳴らすたびランダムに1つ選び、単調な繰り返しを避ける。
## パスは import 済みの ogg。存在しないキーで play() しても握りつぶす。
const CLIPS := {
	"ui_click": ["res://assets/audio/se/ui/click_001.ogg"],
	"ui_select": ["res://assets/audio/se/ui/select_001.ogg"],
	"ui_confirm": ["res://assets/audio/se/ui/confirmation_001.ogg"],
	"ui_back": ["res://assets/audio/se/ui/back_001.ogg"],
	"launch": ["res://assets/audio/se/launch/scratch_001.ogg"],
	"impact": [
		"res://assets/audio/se/impact/impactMetal_medium_000.ogg",
		"res://assets/audio/se/impact/impactMetal_heavy_000.ogg",
		"res://assets/audio/se/impact/impactPlate_heavy_000.ogg",
	],
	"wall": [
		"res://assets/audio/se/wall/impactWood_medium_000.ogg",
		"res://assets/audio/se/wall/impactSoft_medium_000.ogg",
	],
	"win": ["res://assets/audio/se/result/jingles_NES01.ogg"],
	"lose": ["res://assets/audio/se/result/jingles_NES00.ogg"],
}

## キー→読み込んだ AudioStream 配列。_ready で CLIPS から作る。読めなかったものは飛ばす。
var _streams: Dictionary = {}

var _pool: Array[AudioStreamPlayer] = []
var _pool_next := 0

var _rotation: ToneSynth = null
var _charge: ToneSynth = null

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_ensure_buses()
	_load_streams()
	_build_pool()
	_rotation = _make_tone()
	_charge = _make_tone()


## SE/BGM バスが無ければ作って Master へ流す。default_bus_layout を置かずコードで
## 用意するので、リソースファイルを増やさずに済む。既にあれば触らない。
func _ensure_buses() -> void:
	for bus_name in [SE_BUS, BGM_BUS]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func _load_streams() -> void:
	for key in CLIPS:
		var loaded: Array[AudioStream] = []
		for path in CLIPS[key]:
			var stream := load(path) as AudioStream
			if stream != null:
				loaded.append(stream)
			else:
				push_warning("AudioManager: 素材を読めなかった: %s" % path)
		if not loaded.is_empty():
			_streams[key] = loaded


func _build_pool() -> void:
	for _i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = SE_BUS
		add_child(player)
		_pool.append(player)


func _make_tone() -> ToneSynth:
	var tone := ToneSynth.new()
	tone.bus = SE_BUS
	add_child(tone)
	return tone


## キーの素材を1回鳴らす。複数あればランダムに選ぶ。未知のキーは握りつぶす。
func play(key: String) -> void:
	if not _streams.has(key):
		push_warning("AudioManager: 未知のSEキー: %s" % key)
		return
	var choices: Array = _streams[key]
	var stream: AudioStream = choices[_rng.randi_range(0, choices.size() - 1)]
	var player := _pool[_pool_next]
	_pool_next = (_pool_next + 1) % _pool.size()
	player.stream = stream
	player.play()


## --- 回転音 ---

func start_rotation() -> void:
	if _rotation != null:
		_rotation.set_target(AudioLevels.ROT_FREQ_MIN, 0.0)


## その瞬間の rps に合わせて回転音を鳴らす。ref_rps はその戦闘の最大rps、
## lose_threshold 以下では無音になる。
func update_rotation(rps: float, ref_rps: float, lose_threshold: float) -> void:
	if _rotation == null:
		return
	var freq := AudioLevels.rotation_freq(rps, ref_rps)
	var amp := AudioLevels.rotation_amplitude(rps, ref_rps, lose_threshold)
	_rotation.set_target(freq, amp)


func stop_rotation() -> void:
	if _rotation != null:
		_rotation.stop_tone()


## --- チャージ音 ---

func start_charge() -> void:
	if _charge != null:
		_charge.set_target(AudioLevels.charge_freq(0.0), 0.0)


## 引き量 ratio(0〜1)に合わせてチャージ音を鳴らす。引くほど高く・大きく。
func update_charge(ratio: float) -> void:
	if _charge == null:
		return
	_charge.set_target(AudioLevels.charge_freq(ratio), AudioLevels.charge_amplitude(ratio))


func stop_charge() -> void:
	if _charge != null:
		_charge.stop_tone()
