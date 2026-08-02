class_name StatReadout
extends RefCounted

## 対戦画面に出すプレイヤーのコマのステータス表示。
##
## 「どのステータスを・どの翻訳キーで・どれだけ埋まったバーで出すか」を、UIノード
## 生成から切り離してここ一箇所の純粋関数に集める(headlessでテストできるように
## する。cf. scripts/core/screen_layout.gd)。実際のバー生成は Battle.gd が行う。
##
## 数値の生表示は無粋なので、各ステータスは 0〜1 の割合(fraction)で返してバーで見せる。
## 表示レンジ(*_MAX)は初期ビルドがおおむね半分になるよう取ってある ―― パーツで
## 伸び縮みするのが一目で分かる。あくまで見た目用で、勝敗計算とは無関係。
##
## rps は「初期回転数」として出す。ライブに減っていく回転数は画面下のHPバーで
## 既に見えているので、こちらはビルドの基準値(＝開始時rps)を見せる。
##
## 先頭2行は勝敗をほぼ決める複合量の**硬さ**と**寿命**(PartPreviewと同じ定義を
## 共有する)。生の4本(重さ/大きさ/反発/初期回転)はその材料でしかなく、
## 「重さ×半径²」「rps÷(半径×回転減衰)」がどちらへ動いたかは4本を眺めても読めない。
## 報酬画面は2026-08-02のサイクルでこの2つを見せるようになったが、ビルド表示は
## 生の4本のままだったので、**カードで「硬さ 0.73 → 1.32」と約束された値が、
## 取った後どこにも出ない**という切れ方をしていた。11枚積んで硬さが初期値のまま
## だったことに最後まで気付かなかった、というコールドプレイが2サイクル続いている。
## StatPanelは動いた行を光らせるので、札の効きがそのまま目に入るようになる。
##
## なお、コールドプレイCLI(playtest/naive_play.gd)は最初からこの2つを毎回
## 印字していた=**自己改善サイクルのエージェントだけが実プレイヤーより多くの情報で
## 札を選んでいた**。ハーネスと実ゲームのズレ(発射初速1.67倍・出現間隔)を2度踏んだ
## 系譜と同型なので、実UI側を合わせて塞ぐ。

## バーが満タンになる値(下端は0)。初期ビルド(重さ1.5/大きさ0.7/反発0.75/回転15)が
## ほぼ中央に来るよう、既定値の約2倍を上端にしている。
const MASS_MAX := 3.0
const RADIUS_MAX := 1.4
const RESTITUTION_MAX := 1.5
const RPS_MAX := 30.0
## 硬さ・寿命も同じ規則。初期ビルドは硬さ 1.5×0.7²=0.735、寿命 15÷(0.7×1.0)≒21.4。
const TOUGHNESS_MAX := 1.5
const LIFETIME_MAX := 45.0
## 無敵時間の上端。ゴースト2枚(合計4秒)で満タン。
const GHOST_MAX := 4.0


## 表示する行(上から順)。ラベルの翻訳キーと、バーの埋まり具合(0〜1)。
##
## ghost_seconds はゴースト札で得た無敵時間の合計(枚数×1枚あたり秒)。取得している
## (0より大きい)ときだけ末尾に無敵時間の行を足す。未取得なら出さない。値は
## CustomPartCatalog.total_ghost_seconds が出したものを Battle が渡す。
static func rows(stats: SpinnerStats, ghost_seconds: float = 0.0) -> Array[Dictionary]:
	var r: Array[Dictionary] = [
		{
			"label_key": "STAT_TOUGHNESS",
			"fraction": _fraction(PartPreview.toughness(stats), TOUGHNESS_MAX),
		},
		{
			"label_key": "STAT_LIFETIME",
			"fraction": _fraction(PartPreview.lifetime(stats), LIFETIME_MAX),
		},
		{"label_key": "STAT_MASS", "fraction": _fraction(stats.mass, MASS_MAX)},
		{"label_key": "STAT_RADIUS", "fraction": _fraction(stats.radius, RADIUS_MAX)},
		{"label_key": "STAT_RESTITUTION", "fraction": _fraction(stats.restitution, RESTITUTION_MAX)},
		{"label_key": "STAT_RPS_INITIAL", "fraction": _fraction(stats.rps, RPS_MAX)},
	]
	if ghost_seconds > 0.0:
		r.append({"label_key": "STAT_GHOST", "fraction": _fraction(ghost_seconds, GHOST_MAX)})
	return r


## 値を 0〜max で 0〜1 に正規化する。範囲外は端で頭打ち(バーが溢れない/負にならない)。
static func _fraction(value: float, max_value: float) -> float:
	if max_value <= 0.0:
		return 0.0
	return clampf(value / max_value, 0.0, 1.0)
