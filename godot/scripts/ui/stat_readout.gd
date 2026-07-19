class_name StatReadout
extends RefCounted

## 対戦画面に出すプレイヤーのコマの数値ステータス表示。
##
## 「どのステータスを・どの翻訳キーで・どんな書式で出すか」を、UIノード生成から
## 切り離してここ一箇所の純粋関数に集める(headlessでテストできるようにする。
## cf. scripts/core/screen_layout.gd)。実際のラベル生成は Battle.gd が行う。
##
## rps は「初期回転数」として出す。ライブに減っていく回転数は画面下のHPバーで
## 既に見えているので、こちらはビルドの基準値(＝開始時rps)を静的に見せる。

## 表示する行(上から順)。ラベルの翻訳キーと、整形済みの数値文字列。
##
## ghost_seconds はゴースト札で得た無敵時間の合計(枚数×1枚あたり秒)。取得している
## (0より大きい)ときだけ末尾に無敵時間の行を足す。未取得なら出さない。値は
## CustomPartCatalog.total_ghost_seconds が出したものを Battle が渡す。
static func rows(stats: SpinnerStats, ghost_seconds: float = 0.0) -> Array[Dictionary]:
	var r: Array[Dictionary] = [
		{"label_key": "STAT_MASS", "value": _format(stats.mass)},
		{"label_key": "STAT_RADIUS", "value": _format(stats.radius)},
		{"label_key": "STAT_RESTITUTION", "value": _format(stats.restitution)},
		{"label_key": "STAT_RPS_INITIAL", "value": _format(stats.rps)},
	]
	if ghost_seconds > 0.0:
		r.append({"label_key": "STAT_GHOST", "value": _format_seconds(ghost_seconds)})
	return r


## 秒数に単位を付けて整形する("2秒" / "2s")。単位は現在ロケールで引く
## (GameClear.format_* と同じ流儀。静的関数からは tr() を呼べない)。
static func _format_seconds(v: float) -> String:
	return TranslationServer.translate("STAT_SECONDS").format([_format(v)])


## 数値を見やすく整形する。小数第2位まで出してから末尾の余分な0と小数点を落とす
## (1.50→"1.5"、0.75→"0.75"、15.0→"15")。CustomPart._trim() と同趣旨だが、
## あちらは private なのでここに小さく持つ。
static func _format(v: float) -> String:
	var s := "%.2f" % v
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	return s
