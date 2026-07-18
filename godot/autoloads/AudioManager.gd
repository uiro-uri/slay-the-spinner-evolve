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

## 全体音量の対象バス(Master)。SEも将来のBGMもまとめて効かせるため Master をいじる。
const MASTER_BUS_INDEX := 0

## スライダー0付近を無音とみなすしきい値。これ未満はミュート扱い(linear_to_db が
## 0で-infに落ちるのを避ける)。
const MUTE_THRESHOLD := 0.0001

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
	# 回転音は柔らかい正弦波、チャージ音は硬く目立つ三角波。
	_rotation = _make_tone(ToneSynth.Waveform.SINE)
	_charge = _make_tone(ToneSynth.Waveform.TRIANGLE)


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
		# ワンショットSEは SAMPLE 再生にする。Web版の既定は STREAM(Godot内部ミキサで
		# 実時間Vorbisデコード)だが、これが Web でデコード結果を返さず無音になる。
		# SAMPLE は素材をWeb Audioのバッファへ焼いてから鳴らす、SFX向けの確実な経路
		# (Godot 4.3+ がまさにこの用途に用意したもの)。ネイティブでも問題なく鳴る。
		player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE
		add_child(player)
		_pool.append(player)


func _make_tone(waveform: ToneSynth.Waveform) -> ToneSynth:
	var tone := ToneSynth.new()
	tone.bus = SE_BUS
	tone.waveform = waveform
	add_child(tone)
	return tone


## キーの素材を1回鳴らす。複数あればランダムに選ぶ。未知のキーは握りつぶす。
func play(key: String) -> void:
	if not _streams.has(key):
		push_warning("AudioManager: 未知のSEキー: %s" % key)
		return
	var choices: Array = _streams[key]
	var stream: AudioStream = choices[_rng.randi_range(0, choices.size() - 1)]
	_play_stream(stream)


## 音源パスを直接1回鳴らす。サウンドテストが素材を1つずつ試聴するのに使う
## (ゲーム側は必ずキー参照の play() を通すこと)。読めなければ握りつぶす。
func play_path(path: String) -> void:
	if path == "":
		return
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("AudioManager: SEを読み込めない: %s" % path)
		return
	_play_stream(stream)


## プールから次のプレイヤーを取り、stream を鳴らす。play()/play_path() 共通。
## _ready 前(プール未構築)に呼ばれても落ちないよう保険。
func _play_stream(stream: AudioStream) -> void:
	if _pool.is_empty():
		return
	var player := _pool[_pool_next]
	_pool_next = (_pool_next + 1) % _pool.size()
	player.stream = stream
	player.play()


## --- 全体音量 ---
##
## Master バスを直接いじるので SE も将来の BGM もまとめて効く。autoload なので
## 設定は1ラン中ずっと保たれる(セーブはしない=GameStateと同じ流儀)。

## 全体音量をセットする。value は 0.0(無音)〜1.0(原音)の線形値。
## しきい値未満はミュート、それ以外は線形→dB変換して Master バスへ。
func set_master_volume_linear(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if clamped < MUTE_THRESHOLD:
		AudioServer.set_bus_mute(MASTER_BUS_INDEX, true)
	else:
		AudioServer.set_bus_mute(MASTER_BUS_INDEX, false)
		AudioServer.set_bus_volume_db(MASTER_BUS_INDEX, linear_to_db(clamped))


## 現在の全体音量を線形値(0.0〜1.0)で返す。ミュート中は0。
func get_master_volume_linear() -> float:
	if AudioServer.is_bus_mute(MASTER_BUS_INDEX):
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(MASTER_BUS_INDEX)), 0.0, 1.0)


## --- 回転音 ---
##
## 一旦オフにしている(連続音が短いワンショットSEを覆い隠すため)。フックは Battle 側に
## 残したまま、ここを true にすれば復活する。
const ROTATION_ENABLED := false


func start_rotation() -> void:
	if ROTATION_ENABLED and _rotation != null:
		_rotation.set_target(AudioLevels.ROT_FREQ_MIN, 0.0)


## その瞬間の rps に合わせて回転音を鳴らす。ref_rps はその戦闘の最大rps、
## lose_threshold 以下では無音になる。
func update_rotation(rps: float, ref_rps: float, lose_threshold: float) -> void:
	if not ROTATION_ENABLED or _rotation == null:
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
