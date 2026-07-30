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


## 勝利成長の1行テキスト。gainedは実際に増える量(上限で頭打ちなら0)、
## rps_nowは成長後のrps、knockoutは接触で決着を付けた勝ち(撃破ボーナス)。
## 上限到達で丸め表示が+0.0になる成長は「頭打ち」と正直に言う。
static func growth_line(knockout: bool, gained: float, rps_now: float) -> String:
	var cap := "%.0f" % SpinnerStats.RPS_CAP
	if gained < SHOWN_MIN:
		if knockout:
			return TranslationServer.translate("BATTLE_GROWTH_KNOCKOUT_CAPPED").format([cap])
		return TranslationServer.translate("BATTLE_GROWTH_CAPPED").format([cap])
	var values := ["%.1f" % gained, "%.1f" % rps_now]
	if knockout:
		return TranslationServer.translate("BATTLE_GROWTH_KNOCKOUT").format(values)
	return TranslationServer.translate("BATTLE_GROWTH_VICTORY").format(values)
