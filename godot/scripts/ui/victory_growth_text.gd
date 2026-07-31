class_name VictoryGrowthText
extends RefCounted

## 決着後のリザルトに出す「勝利で回転がどれだけ育つか」の行を組み立てる共有ヘルパー。
##
## 勝利成長(SpinnerStats.grow_rps_by_victory)はこれまでStatPanelのゲージが黙って
## 動くだけで、実UIのプレイヤーは撃破ボーナス(接触で仕留めた勝ちは大きく育つ)の
## 存在を知り得なかった。CLI(naive_play.victory_text)では表示済みの事実を、
## 実UIにも同じ規則で出す。
##
## 静的関数からは tr() を呼べないので、TranslationServer で現在ロケールを引く
## (RpsLossText と同じ流儀)。


## 表示丸め(%.1f)で+0.0になる成長を「成長した」と言わないための閾値。
## naive_play.victory_text と同じ境界にして、出す数字と文言の食い違いを防ぐ。
const SHOWN_MIN := 0.05

## 余勢転化(spin_decayの低下)を「長持ちになった」と言うための閾値。
## 表示丸め(%.2f)で同じ値になる低下を成長と呼ばない(SHOWN_MINと同じ発想)。
## naive_play.victory_text と同じ境界。
const DECAY_SHOWN_MIN := 0.005


## 勝利成長の1行テキスト。gainedは実際に増える量(上限で頭打ちなら0)、
## rps_nowは成長後のrps、knockoutは接触で決着を付けた勝ち(撃破ボーナス)。
## 上限到達で丸め表示が+0.0になる成長は「頭打ち」と正直に言う。
## decay_before/decay_afterは成長適用の前後のspin_decay。撃破ボーナスの余勢が
## 寿命へ転化した(SpinnerStats.grow_rps_by_victoryの余勢転化)ときは頭打ちでなく
## 「勢い余って回転が長持ちに」を出す。省略時(-1.0)は従来どおり。
static func growth_line(
	knockout: bool, gained: float, rps_now: float,
	decay_before: float = -1.0, decay_after: float = -1.0
) -> String:
	var cap := "%.0f" % SpinnerStats.RPS_CAP
	if knockout and decay_before > 0.0 and decay_before - decay_after >= DECAY_SHOWN_MIN:
		return TranslationServer.translate("BATTLE_GROWTH_KNOCKOUT_OVERFLOW").format(
			["%.2f" % decay_before, "%.2f" % decay_after]
		)
	if gained < SHOWN_MIN:
		if knockout:
			return TranslationServer.translate("BATTLE_GROWTH_KNOCKOUT_CAPPED").format([cap])
		return TranslationServer.translate("BATTLE_GROWTH_CAPPED").format([cap])
	var values := ["%.1f" % gained, "%.1f" % rps_now]
	if knockout:
		return TranslationServer.translate("BATTLE_GROWTH_KNOCKOUT").format(values)
	return TranslationServer.translate("BATTLE_GROWTH_VICTORY").format(values)
