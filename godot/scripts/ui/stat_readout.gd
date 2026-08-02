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

## 敵の行(enemy_rows)で「互角」になる埋まり具合。取り分なので必ずちょうど半分。
## StatPanelがこの位置に目盛りを描く。
const PARITY := 0.5


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


## これから戦う相手の硬さ・寿命を、**自分と比べた取り分**で出す行。
##
## 動機: マップは「Lv3 2体」としか言わないので、その部屋が自分より硬いのかどうかが
## 発射前にどこにも出ていない。実測で敵の硬さは Lv1 0.12 → Lv5 12.5 と100倍動くのに、
## 自分の硬さはラン全体でも 0.73 → 1.7 しか動かない。**同じ絶対レンジのバーで並べても
## 意味を成さない**(TOUGHNESS_MAX=1.5 では Lv3 以上が全部満タンに張り付く)ので、
## 上端を決め打たずに済む取り分 敵/(自分+敵) にする。ちょうど互角で PARITY、
## 目盛りを越えていれば「相手の方が硬い/長生き」と読める。
##
## 乱戦は**いちばん硬い個体・いちばん寿命が長い個体**を代表にする(部屋の難度は
## 一番きつい相手で決まる。平均だと弱い個体が数で薄めてしまう)。硬さと寿命は
## 別々に最大を取る——硬い個体と長生きな個体が同一とは限らず、部屋の脅威は
## 「いちばん硬い奴」と「いちばん粘る奴」の両方だから。
##
## これは**予告(EnemyTelegraph)の揺らぎを損なわない**。揺らして隠しているのは
## 出現位置と向き=この一戦の計画で、硬さ・寿命は個体の静的な性能。どこへ飛ぶかは
## 相変わらず読み切れない。
##
## なお、コールドプレイCLI(playtest/naive_play.gd)は敵1体ごとに硬さ・寿命を
## 最初から印字していた。自分のビルド側は 2026-08-02 のサイクルで塞いだが、
## 敵側は残っていた=**エージェントだけが「この部屋は硬い」を知って札を選べる**
## 状態だった。同型のズレ(発射初速1.67倍・出現間隔・自分の硬さ表示)に続く4件目。
##
## enemies が空(相手が居ない画面)なら行を出さない。StatPanelはそのまま何も足さない。
static func enemy_rows(stats: SpinnerStats, enemies: Array[SpinnerStats]) -> Array[Dictionary]:
	if stats == null or enemies.is_empty():
		return []
	var longest := _peak(enemies, false)
	if longest < 0.0:
		return []
	return [
		{"label_key": "STAT_ENEMY_TOUGHNESS", "fraction": toughness_share(stats, enemies)},
		{
			"label_key": "STAT_ENEMY_LIFETIME",
			"fraction": _share(longest, PartPreview.lifetime(stats)),
		},
	]


## 相手のいちばん硬い個体と自分との、硬さの取り分。enemy_rows の1行目そのもの。
##
## 公開してあるのは、**マップのノードに出す脅威メーター(ThreatMeter)がこれを呼ぶ**
## から。部屋の硬さの定義が2箇所にあると、マップと対戦画面で違う脅威を出すことになる
## (片方だけ直されたときに食い違う。硬さ・寿命の定義を PartPreview から借りているのと
## 同じ理由)。
##
## 相手が居ない・値が取れないときは互角(PARITY)を返す。0埋めにすると
## 「相手が居ないので安全」ではなく「相手が弱い」という別の嘘になる。
static func toughness_share(stats: SpinnerStats, enemies: Array[SpinnerStats]) -> float:
	if stats == null:
		return PARITY
	var toughest := _peak(enemies, true)
	if toughest < 0.0:
		return PARITY
	return _share(toughest, PartPreview.toughness(stats))


## 群のうち最大の硬さ(use_toughness=true)または最大の寿命。有効な相手が1体も
## 居なければ -1.0 を返す(硬さ0の相手と「相手が居ない」を取り違えないため)。
##
## 乱戦の代表を最大にするのは、部屋の難度がいちばんきつい相手で決まるから
## (平均だと弱い個体が数で薄めてしまう)。硬さと寿命で別々に最大を取るのは、
## 硬い個体と長生きな個体が同一とは限らないから。
static func _peak(enemies: Array[SpinnerStats], use_toughness: bool) -> float:
	var peak := -1.0
	for enemy in enemies:
		if enemy == null:
			continue
		var value := PartPreview.toughness(enemy) if use_toughness else PartPreview.lifetime(enemy)
		peak = maxf(peak, value)
	return peak


## 相手の取り分。互角(両者が同じ値)でちょうど PARITY、相手が上回るほど1へ寄る。
## 上端を決め打たずに済むので、100倍のレンジ差があっても頭打ちにならない。
## 両方0(値が取れない)なら互角扱いにする——0埋めだと「相手が弱い」という嘘になる。
static func _share(enemy_value: float, player_value: float) -> float:
	var total := enemy_value + player_value
	if total <= 0.0:
		return PARITY
	return clampf(enemy_value / total, 0.0, 1.0)


## 値を 0〜max で 0〜1 に正規化する。範囲外は端で頭打ち(バーが溢れない/負にならない)。
static func _fraction(value: float, max_value: float) -> float:
	if max_value <= 0.0:
		return 0.0
	return clampf(value / max_value, 0.0, 1.0)
