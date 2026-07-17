class_name ToneSynth
extends AudioStreamPlayer

## 実行時に波形を合成する連続音の音源。回転音・チャージ音のように、専用素材が無く
## パラメータ(周波数・振幅)に連続追従させたい音に使う。
##
## AudioStreamGenerator へ毎フレーム波形を書き込む。目標周波数・振幅は set_target() で
## 与え、実値はそこへ平滑化して寄せる(急変でプツッと鳴らないように)。位相は連続に
## 保つので周波数を変えても途切れない。波形は正弦波か三角波を選べる。
##
## ヘッドレス(音声出力の無いテスト環境)では get_stream_playback() が使えないことが
## あるが、その場合でも push をスキップするだけで落ちない。そもそも AudioManager は
## テスト中にトーンを開始しないので、通常この _process は回らない。

enum Waveform { SINE, TRIANGLE }

## 合成のサンプリングレート。扱う周波数には十分で、低いほど1フレームで埋める
## フレーム数が減り軽い。
const MIX_RATE := 22050.0

## ジェネレータのバッファ長(秒)。短いほど遅延が少ないが、フレーム落ちに弱くなる。
const BUFFER_LENGTH := 0.1

## 目標へ寄せる速さ(毎秒)。大きいほど追従が速いが急変でクリックが出やすい。
## 引き量に機敏に追従させたいので少し速め。
const SMOOTH_RATE := 24.0

## 停止時に振幅を0へ落とす速さ(毎秒)。SMOOTH_RATE よりずっと速くして、離した瞬間に
## だらだら尾を引かず、ほぼ即座に切る(ごく短いフェードでプツッというクリックだけ防ぐ)。
const STOP_SMOOTH_RATE := 90.0

## これ以下の振幅になったら無音とみなし、停止要求時に実際に停止する。
const SILENCE := 0.001

## 波形。AudioManager が音源ごとに設定する(チャージ音は三角波など)。
var waveform: Waveform = Waveform.SINE

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


## 音を止める。だらだら下降させず素早く切る(STOP_SMOOTH_RATE の高速フェード)。
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
	# 停止中は振幅だけを高速フェードで落とし、離した瞬間に尾を引かせない。
	var amp_rate := STOP_SMOOTH_RATE if _stopping else SMOOTH_RATE
	_freq += (_target_freq - _freq) * minf(1.0, SMOOTH_RATE * delta)
	_amp += (_target_amp - _amp) * minf(1.0, amp_rate * delta)

	if _playback != null:
		_fill(_playback)

	# フェードし切ったら実際に止める。音声出力が無い環境でも同じ条件で止まる。
	if _stopping and _amp <= SILENCE:
		_do_stop()


## ジェネレータの空きフレームを波形で埋める。周波数はこのブロック内では一定。
func _fill(playback: AudioStreamGeneratorPlayback) -> void:
	var frames := playback.get_frames_available()
	if frames <= 0:
		return
	var incr := TAU * _freq / MIX_RATE
	for _i in frames:
		var s := _sample(_phase) * _amp
		playback.push_frame(Vector2(s, s))
		_phase += incr
		if _phase > TAU:
			_phase -= TAU


## 位相(0〜TAU)から -1〜1 の波形値を返す。三角波は倍音を含むぶん明るく硬い音になる。
func _sample(phase: float) -> float:
	match waveform:
		Waveform.TRIANGLE:
			# asin(sin) が素直な三角波(位相0で0から始まりクリックが出にくい)。
			return (2.0 / PI) * asin(sin(phase))
		_:
			return sin(phase)


func _do_stop() -> void:
	if playing:
		stop()
	_playback = null
	_amp = 0.0
	_phase = 0.0
	_stopping = false
	set_process(false)
