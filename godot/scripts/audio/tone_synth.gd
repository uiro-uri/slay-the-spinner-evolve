class_name ToneSynth
extends AudioStreamPlayer

## 実行時に正弦波を合成する連続音の音源。回転音・チャージ音のように、専用素材が無く
## パラメータ(周波数・振幅)に連続追従させたい音に使う。
##
## AudioStreamGenerator へ毎フレーム波形を書き込む。目標周波数・振幅は set_target() で
## 与え、実値はそこへ平滑化して寄せる(急変でプツッと鳴らないように)。位相は連続に
## 保つので周波数を変えても途切れない。
##
## ヘッドレス(音声出力の無いテスト環境)では get_stream_playback() が使えないことが
## あるが、その場合でも push をスキップするだけで落ちない。そもそも AudioManager は
## テスト中にトーンを開始しないので、通常この _process は回らない。

## 合成のサンプリングレート。扱う周波数(〜430Hz程度)には十分で、低いほど1フレームで
## 埋めるフレーム数が減り軽い。
const MIX_RATE := 22050.0

## ジェネレータのバッファ長(秒)。短いほど遅延が少ないが、フレーム落ちに弱くなる。
const BUFFER_LENGTH := 0.1

## 目標へ寄せる速さ(毎秒)。大きいほど追従が速いが急変でクリックが出やすい。
const SMOOTH_RATE := 14.0

## これ以下の振幅になったら無音とみなし、停止要求時に実際に停止する。
const SILENCE := 0.001

var _target_freq := 0.0
var _target_amp := 0.0
var _freq := 0.0
var _amp := 0.0
var _phase := 0.0
var _stopping := false
var _playback: AudioStreamGeneratorPlayback = null


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = BUFFER_LENGTH
	stream = gen
	set_process(false)


## 目標の周波数(Hz)と振幅(0〜1)を与える。振幅>0なら再生を開始する。
## 停止フェード中に再び呼ばれたらフェードを取り消して鳴らし続ける。
func set_target(freq: float, amplitude: float) -> void:
	_target_freq = freq
	_target_amp = maxf(amplitude, 0.0)
	if _target_amp > 0.0:
		_stopping = false
		_ensure_playing()


## 音を止める。プツッと切れないよう振幅を0へ落とし、消えてから実際に停止する。
func stop_tone() -> void:
	_target_amp = 0.0
	_stopping = true


func _ensure_playing() -> void:
	if not playing:
		_phase = 0.0
		_freq = _target_freq
		play()
	# get_stream_playback() は playing 中でないと取れない。ヘッドレス(ダミー音声
	# ドライバ)では play() しても playing にならないので、ここで問い合わせず null の
	# まま進む(_process 側で波形を書かないだけ。エンジンのエラー出力も避けられる)。
	if playing and _playback == null:
		_playback = get_stream_playback()
	set_process(true)


func _process(delta: float) -> void:
	var k := minf(1.0, SMOOTH_RATE * delta)
	_freq += (_target_freq - _freq) * k
	_amp += (_target_amp - _amp) * k

	if _playback != null:
		_fill(_playback)

	# フェードし切ったら実際に止める。音声出力が無い環境でも同じ条件で止まる。
	if _stopping and _amp <= SILENCE:
		_do_stop()


## ジェネレータの空きフレームを正弦波で埋める。周波数はこのブロック内では一定。
func _fill(playback: AudioStreamGeneratorPlayback) -> void:
	var frames := playback.get_frames_available()
	if frames <= 0:
		return
	var incr := TAU * _freq / MIX_RATE
	for _i in frames:
		var s := sin(_phase) * _amp
		playback.push_frame(Vector2(s, s))
		_phase += incr
		if _phase > TAU:
			_phase -= TAU


func _do_stop() -> void:
	if playing:
		stop()
	_playback = null
	_amp = 0.0
	_phase = 0.0
	_stopping = false
	set_process(false)
