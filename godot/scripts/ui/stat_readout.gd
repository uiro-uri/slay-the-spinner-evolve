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
## 乱戦の集約は硬さと寿命で**別**にする。硬さは**頭数ぶんの和**、寿命は
## **いちばん粘る個体**。理由は問いが違うから: 硬さの行が答えるのは「この部屋を
## 片付けるのにどれだけの仕事が要るか/どれだけ殴られるか」で、どちらも敵ごとの
## 和になる(削り切るべき回転も、飛んでくる衝突も頭数ぶんある)。寿命の行が
## 答えるのは「待ったら何秒で自滅するか」で、これは最後の1体が力尽きるまで＝最大。
## 硬い個体と長生きな個体が同一とは限らないので、集約は別々に取る。
##
## 硬さを最大にしていた頃は、**同じレベルなら1体でも3体でもメーターが同じ値**を
## 出していた。実測(playtest/measure_group_size.gd, 中盤ビルド・各400戦)では
## Lv3の勝率が **1体91.2% → 2体24.8% → 3体8.2%** と動くのに、取り分は
## **0.63 / 0.64 / 0.64** で見分けが付かなかった。和にすると 0.63 / 0.78 / 0.84 に
## なり、12セル(Lv1〜4 × 1〜3体)を取り分の昇順に並べたとき勝率がほぼ単調に下がる
## (逆転はLv4×1体 5.2% と Lv3×3体 8.2% の1組・3pt差だけ)。単体の部屋では和＝最大
## なので値は1つも変わらない——変わるのは乱戦だけ。
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
	var longest := _longest_lifetime(enemies)
	if longest < 0.0:
		return []
	return [
		{"label_key": "STAT_ENEMY_TOUGHNESS", "fraction": toughness_share(stats, enemies)},
		{
			"label_key": "STAT_ENEMY_LIFETIME",
			"fraction": _share(longest, PartPreview.lifetime(stats)),
		},
	]


## 部屋ぜんぶの硬さ(頭数ぶんの和)と自分との、硬さの取り分。enemy_rows の1行目そのもの。
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
	var room := room_toughness(enemies)
	if room < 0.0:
		return PARITY
	return _share(room, PartPreview.toughness(stats))


## 部屋の硬さ＝有効な相手の硬さの**和**。有効な相手が1体も居なければ -1.0 を返す
## (硬さ0の相手と「相手が居ない」を取り違えないため)。
##
## 和にする理由は enemy_rows の説明のとおり。単体なら和は個体の硬さそのものなので、
## 乱戦以外では従来の「最大」と1つも値が変わらない。
static func room_toughness(enemies: Array[SpinnerStats]) -> float:
	var total := -1.0
	for enemy in enemies:
		if enemy == null:
			continue
		if total < 0.0:
			total = 0.0
		total += PartPreview.toughness(enemy)
	return total


## 群のうち最大の寿命。有効な相手が1体も居なければ -1.0 を返す(寿命0の相手と
## 「相手が居ない」を取り違えないため)。
##
## 寿命だけ最大なのは、部屋が自滅で終わるのは**最後の1体**が力尽きたときだから。
## 頭数が増えても「待ち時間」は伸びない(同時に回っている)ので、和にすると嘘になる。
static func _longest_lifetime(enemies: Array[SpinnerStats]) -> float:
	var peak := -1.0
	for enemy in enemies:
		if enemy == null:
			continue
		peak = maxf(peak, PartPreview.lifetime(enemy))
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
