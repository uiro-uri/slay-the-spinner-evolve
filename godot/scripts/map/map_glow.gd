class_name MapGlow
extends RefCounted

## マップの見た目演出のための、時刻の純粋関数。
##
## Nodeにもシーンにも乱数にも依存しない。時刻を渡せば同じ値が返る
## (telegraph_wobble.gd と同じ設計)。_process/_draw に数式を埋めるとテスト
## できないので、明滅とフェードの計算だけをここに切り出してある。

## 明滅のゆっくりさ。低いほど周期が長い。
const DEFAULT_PULSE_SPEED := 2.4

## 入場フェードの長さ(秒)。
const DEFAULT_ENTRANCE_DURATION := 0.35


## 選択可能マスの明滅の素。0〜1をゆっくり滑らかに往復する。
##
## t=0で0(=最も淡い側)から始まるので、マップが出た瞬間に明るさが跳ねない
## (wobble の「t=0は休止」と同じ思想)。cosを使うと t=0 で確実に0になり、値域も
## [0,1]に収まる。呼び出し側は lerp(下限, 上限, pulse) でアルファや半径に通す。
static func pulse(t: float, speed: float = DEFAULT_PULSE_SPEED) -> float:
	return 0.5 - 0.5 * cos(t * speed)


## 入場フェードの進捗。0(出た瞬間)→1(表示完了)。
##
## smoothstepで緩急を付ける。単調非減少で、経過が長さを超えたら1.0に張り付く。
## duration<=0 の0除算は最初から1.0扱いにして防ぐ(CollisionSparkと同じ配慮)。
static func entrance(elapsed: float, duration: float = DEFAULT_ENTRANCE_DURATION) -> float:
	if duration <= 0.0:
		return 1.0
	var x := clampf(elapsed / duration, 0.0, 1.0)
	return smoothstep(0.0, 1.0, x)
