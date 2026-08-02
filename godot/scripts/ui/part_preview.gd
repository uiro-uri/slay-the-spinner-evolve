class_name PartPreview
extends RefCounted

## 報酬カードに出す「この札を取ると自分のコマがどう変わるか」の見積もり。
##
## StatReadout(対戦画面のビルド表示)と同じく、UIノード生成から切り離した純粋関数に
## して headless でテストできるようにする。実際のラベル生成は RewardScreen.gd が行う。
##
## **なぜ生ステータスでなく複合量を出すのか**
## 敵の表(scripts/data/enemy_roster.gd)は「この2つが勝敗をほぼ決める」として
## **硬さ = 質量 × 半径²**(1衝突で削られるrpsがこれに反比例する)と
## **寿命 = rps ÷ (半径 × 回転減衰)**(自然減衰が半径比例)の2つで組んである。
## ところがプレイヤーに見えるのは 重さ/大きさ/反発/初期回転数 の生の4本だけで、
## 実際に勝敗を決めている2つはどこにも出ていなかった。
##
## 一次証拠(コールドプレイ 2026-08-02): カードの効果テキストだけで11枚選んだ結果、
## 硬さが初期値0.735のまま1度も伸びずに段8(敵の硬さ3.67〜3.88)で残機切れ。
## 直前サイクルのコールドプレイも同じ死に方(「段7で硬さの壁。EDGE/DRILLを積んでも
## 急に何も通らなくなった」)をしている。カード文面は「直径×1.25・質量×1.15」までは
## 言うが、それが硬さと寿命をどちらへどれだけ動かすかは言わない。
##
## 硬さと寿命は**変化しない札でも常に出す**。「この札では硬さが伸びない」こと自体が
## 選択に必要な情報で、行が出たり消えたりするとカードの高さも揺れる。
## 残機・無敵時間の行は、その札が動かすときだけ足す(コマの性能ではないため)。

## 硬さ・寿命がゼロ除算にならないための下限。半径や回転減衰は@export_rangeで
## 0.1以上に制限されているが、テストや将来の札が0を渡してもnan/infを出さない。
const _EPSILON := 0.0001


## 硬さ = 質量 × 半径²。1衝突で削られるrpsがこれに反比例する(spinner_physics.spin_drain)。
static func toughness(stats: SpinnerStats) -> float:
	return stats.mass * stats.radius * stats.radius


## 寿命(秒の目安) = rps ÷ (半径 × 回転減衰)。自然減衰(natural_spin_decay)が
## 半径×回転減衰に比例するので、殴られなくてもこの時間で回転が尽きる。
static func lifetime(stats: SpinnerStats) -> float:
	var rate := stats.radius * stats.spin_decay
	if rate < _EPSILON:
		return 0.0
	return stats.rps / rate


## この札を取った後のステータス。元のstatsは変えない(プレビューなので破壊しない)。
static func preview_stats(stats: SpinnerStats, part: CustomPart) -> SpinnerStats:
	var after := stats.duplicate_stats()
	part.apply_to(after)
	return after


## カードに出す行(上から順)。
##
## 各行は {"label_key": 翻訳キー, "before": 今の値, "after": 取った後の値,
##         "digits": 小数点以下の桁数, "better": +1/0/-1} 。
## better は「afterがbeforeより良い方向か」で、変化なしは0。色や矢印の向きに使う。
##
## continues は今の残機(GameState.continues_left)。0未満を渡すと残機の行を出さない。
## ghost_seconds は取得済みゴースト札の合計秒(CustomPartCatalog.total_ghost_seconds)。
static func rows(
	stats: SpinnerStats, part: CustomPart,
	continues: int = -1, ghost_seconds: float = 0.0
) -> Array[Dictionary]:
	var after := preview_stats(stats, part)
	var result: Array[Dictionary] = [
		_row("STAT_TOUGHNESS", toughness(stats), toughness(after), 2),
		_row("STAT_LIFETIME", lifetime(stats), lifetime(after), 1),
	]
	# 残機札(SPARE_CORE)はコマの性能を一切変えないので、硬さ・寿命だけでは
	# 「何も起きない札」に見えてしまう。GameState側の効果をここで補う。
	if continues >= 0 and part.lives > 0:
		result.append(_row("STAT_LIVES", continues, maxi(continues, part.lives), 0))
	if part.effect == CustomPart.Effect.GHOST and part.ghost_seconds > 0.0:
		result.append(_row(
			"STAT_GHOST", ghost_seconds, ghost_seconds + part.ghost_seconds, 1
		))
	return result


static func _row(label_key: String, before: float, after: float, digits: int) -> Dictionary:
	var better := 0
	if not is_equal_approx(before, after):
		better = 1 if after > before else -1
	return {
		"label_key": label_key, "before": before, "after": after,
		"digits": digits, "better": better,
	}


## 1行の表示文字列。変化しないときは今の値だけを出す(「0.73 → 0.73」は読み手に
## 変化があると誤読させる)。矢印は方向を持たない記号にして、良し悪しは色で見せる。
static func format_row(row: Dictionary) -> String:
	var digits: int = row["digits"]
	var before := String.num(row["before"], digits)
	if row["better"] == 0:
		return before
	return "%s → %s" % [before, String.num(row["after"], digits)]
