class_name RpsLossText
extends RefCounted

## 決着後のリザルトに出す「回転をどこで失ったか」の内訳行を組み立てる共有ヘルパー。
##
## BattleResolver が機構別に数えた実測 ({"drain": 衝突削り, "wall": 壁/障害物,
## "decay": 自然減衰, "wall_hits": 壁回数}) を1行のテキストにする。
## 壁1回で現在rpsの2割超を失うことは初見には見えないので、勝敗の下に事実として出す。
## 死因ラベル(閾値を割った最後の一滴)と違い、これは喪失の全量の内訳なので嘘をつかない。
##
## 静的関数からは tr() を呼べないので、TranslationServer で現在ロケールを引く
## (AcquiredUpgradeList と同じ流儀)。


## 内訳の1行テキスト。内訳が無い(旧結果や未解決)なら空文字を返し、呼び手は非表示にする。
static func summary_line(loss: Dictionary) -> String:
	if loss.is_empty():
		return ""
	return TranslationServer.translate("BATTLE_RPS_LOSS_BREAKDOWN").format([
		_fmt(float(loss.get("drain", 0.0))),
		_fmt(float(loss.get("wall", 0.0))),
		int(loss.get("wall_hits", 0)),
		_fmt(float(loss.get("decay", 0.0))),
	])


## 表示用の数値。小数1桁固定(丸めで桁が揺れない)。負は0に潰す(蓄積は非負のはずだが表示の防衛)。
static func _fmt(value: float) -> String:
	return "%.1f" % maxf(value, 0.0)
