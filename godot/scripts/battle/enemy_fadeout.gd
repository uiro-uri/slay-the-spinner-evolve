class_name EnemyFadeout
extends RefCounted

## 乱戦で力尽きた敵を、一定時間後に描画ごと消す(フェードアウト)ための計算。
##
## resolver は倒れた敵も統合・バウンド・記録を続ける(alive を落として当たり判定から
## 外すだけ)ので、再生中は倒れた敵が明るいまま漂い、HPバーも0%で残り続ける。乱戦では
## これで「誰がまだ生きているか」が読みにくい。倒れた敵を時間差で消してすっきりさせる。
##
## **1体だけの戦闘には使わない。** そこは決着後に暗くして残す既存挙動のままにする。
## この判断は呼び出し側(Battle.gd)が敵の数で行う。
##
## Nodeにもシーンにも乱数にも依存しない純粋関数。軌跡と時刻を渡せば同じ値が返るので、
## telegraph_wobble.gd と同じくヘッドレスで直接テストできる。

## rps が尽きてから消え始めるまでの待機(秒)。この間は暗転した姿のまま残す。
const DEFAULT_DELAY := 0.8

## フェードにかける秒数。
const DEFAULT_DURATION := 0.5


## 軌跡を走査し、rps が lose_threshold 以下になる最初のフレームの時刻を返す。
## 一度も割らない(最後まで生存)なら -1.0。空の軌跡も -1.0。
## この -1.0 は「まだ倒れていない」の番兵で、alpha_at がフェードしないと解釈する。
static func defeat_time(track: Array, lose_threshold: float, time_step: float) -> float:
	for i in track.size():
		if track[i].rps <= lose_threshold:
			return i * time_step
	return -1.0


## 時刻 t での不透明度(0〜1)。
##
## defeat_time が負(未撃破)なら常に 1.0。撃破後 delay までは 1.0 のまま(暗転した姿を
## 見せる時間)、そこから duration かけて 0.0 へ抜け、以後は 0.0。
## 時間について単調非増加で、返り値は必ず [0,1] に収まる。
static func alpha_at(t: float, defeat_time_: float, delay: float, duration: float) -> float:
	if defeat_time_ < 0.0:
		return 1.0
	var elapsed := t - defeat_time_
	if elapsed < delay:
		return 1.0
	if duration <= 0.0:
		return 0.0
	if elapsed >= delay + duration:
		return 0.0
	return 1.0 - (elapsed - delay) / duration
