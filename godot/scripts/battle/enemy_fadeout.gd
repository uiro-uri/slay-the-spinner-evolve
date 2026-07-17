class_name EnemyFadeout
extends RefCounted

## 力尽きたコマを、一定時間後に描画ごと消す(フェードアウト)ための計算。
##
## 二つの場面で使う:
##   1. 乱戦の戦闘中: resolver は倒れた敵も統合・バウンド・記録を続ける(alive を落として
##      当たり判定から外すだけ)ので、再生中は倒れた敵が明るいまま漂い、HPバーも0%で残る。
##      誰がまだ生きているか読みにくいので、倒れた敵を時間差で消してすっきりさせる
##      (defeat_time + alpha_at。Battle.gd が敵の数で使い分ける)。
##   2. 決着の瞬間: バトル終了で力尽きたコマ(敗者、引き分けなら両者)を、即座にグレーアウト
##      させず最後の姿を一拍保持してからフェードで消す。どのコマを消すかは should_fade が返す。
##
## Nodeにもシーンにも乱数にも依存しない純粋関数。軌跡・時刻・状態を渡せば同じ値が返るので、
## telegraph_wobble.gd と同じくヘッドレスで直接テストできる。

## rps が尽きてから消え始めるまでの待機(秒)。この間は力尽きた姿のまま残す。
const DEFAULT_DELAY := 0.8

## フェードにかける秒数。
const DEFAULT_DURATION := 0.5

## この値以下の不透明度は「もう消えている」とみなす閾値。
const VISIBLE_EPS := 0.01


## 決着時、このコマをフェードアウトさせるべきか。
## 力尽きていて(rps <= lose_threshold)、かつまだ見えている(乱戦で戦闘中に既に消え切った敵は
## 除外する)コマだけを対象にする。勝者は rps が残っているので自動的に対象外になる。
static func should_fade(final_rps: float, lose_threshold: float, current_alpha: float) -> bool:
	return final_rps <= lose_threshold and current_alpha > VISIBLE_EPS


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
