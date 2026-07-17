class_name AudioLevels
extends RefCounted

## 回転音・チャージ音の音響パラメータを、ゲーム状態から決める純粋関数群。
##
## 回転音とチャージ音には専用の音声素材が無く、rps や引き量に連続追従する必要が
## あるので、ToneSynth が実行時に正弦波を合成する。その周波数(Hz)と振幅(0〜1)を
## ここで決める。Node にも AudioServer にも依存しないので、ヘッドレスでテストできる。
##
## 数値は手触りで詰める前提(CLAUDE.md)。ここの const は出発点でしかなく、テストは
## 値そのものではなく「rps が増えれば高く・大きくなる」「力尽きれば無音」といった
## 調整で崩れない性質(単調性・境界・上限)だけを検証する。

## --- 回転音 ---

## 回転音の下限・上限の周波数(Hz)。rps=0付近で下限、reference rps で上限へ近づく。
const ROT_FREQ_MIN := 70.0
const ROT_FREQ_MAX := 190.0

## 回転音の最大振幅。連続音なので衝突音より控えめにする。短い衝突音・発射音を
## 覆い隠さないよう、低めに抑える(手触りで調整可)。
const ROT_AMP_MAX := 0.12

## --- チャージ音 ---

## チャージ音の下限・上限の周波数(Hz)。引くほど高い「溜め」の唸り。三角波は倍音を
## 多く含んで明るく聞こえるので、基音は低めに置く。
const CHARGE_FREQ_MIN := 55.0
const CHARGE_FREQ_MAX := 160.0

## チャージ音の最大振幅。引き切ったところで最大。連続音なので控えめに。
const CHARGE_AMP_MAX := 0.20


## 回転音の周波数。rps が大きいほど高い。reference rps(その戦闘の最大rps)で頭打ち。
## reference が 0 以下でも落ちないよう素の下限を返す。
static func rotation_freq(rps: float, ref_rps: float) -> float:
	var t := _ratio(rps, ref_rps)
	return lerpf(ROT_FREQ_MIN, ROT_FREQ_MAX, t)


## 回転音の振幅(0〜1)。lose_threshold 以下は無音、そこから rps に応じて立ち上がる。
## 力尽きたコマ(rps≒0)で確実に消える境界が肝。
static func rotation_amplitude(rps: float, ref_rps: float, lose_threshold: float) -> float:
	if rps <= lose_threshold:
		return 0.0
	return ROT_AMP_MAX * _ratio(rps, ref_rps)


## チャージ音の周波数。引き量 ratio(0〜1)が大きいほど高い。
static func charge_freq(ratio: float) -> float:
	return lerpf(CHARGE_FREQ_MIN, CHARGE_FREQ_MAX, clampf(ratio, 0.0, 1.0))


## チャージ音の振幅(0〜1)。ratio=0 で無音、引くほど大きく、引き切りで最大。
static func charge_amplitude(ratio: float) -> float:
	return CHARGE_AMP_MAX * clampf(ratio, 0.0, 1.0)


## rps を reference で正規化して 0〜1 に収める。reference が 0 以下なら 0 扱い
## (ゼロ除算・負値を避ける)。
static func _ratio(rps: float, ref_rps: float) -> float:
	if ref_rps <= 0.0:
		return 0.0
	return clampf(rps / ref_rps, 0.0, 1.0)
