class_name PlaybackPacing
extends RefCounted

## 再生の早送り(押している間だけ倍速)の計算。Nodeにもシーンにも依存しない
## 純粋な静的関数だけを置く(FinishFocus/TelegraphWobbleと同じ流儀)。
##
## 戦いは発射時に全部決まっていて、再生は観るだけ。長い戦闘(実測で17〜20秒)の
## 後半は毎秒ほぼ同強度の微衝突が決着直前まで続く消耗戦で、間延びする。
## どこが退屈かの自動判定はしない——「最後のイベント以降」は実測で0.2〜1.0秒しか
## なく無力で、「敗者のrpsが低い」基準は残り数%の接戦のクライマックスまで
## 早送りしてしまう。退屈の判定はプレイヤーの指に委ねるのが一番正直。
##
## 勝敗・軌跡(BattleResult)には一切影響しない(再生時刻の進み方だけが変わる)。


## 再生速度(1.0=等速)。押している間だけmultiplier倍。
##
## 決着ズーム演出(FinishFocus)の最中だけは押していても等速へ戻す:
## 演出はEngine.time_scaleのスローで見せるので、倍速と重なると相殺されて
## 一番熱い瞬間が流れてしまう。演出なし(decisive_time<0)なら常に押した通り。
static func speed_at(
	held: bool, multiplier: float, t: float, decisive_time: float, lead: float
) -> float:
	if not held:
		return 1.0
	if FinishFocus.strength_at(t, decisive_time, lead) > 0.0:
		return 1.0
	return maxf(multiplier, 1.0)
