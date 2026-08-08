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
## **なぜ2行目が寿命でなく打たれ強さなのか**(2026-08-06)
## 寿命は「殴られなくても力尽きるまでの秒数」＝**自然減衰**の軸だが、
## 自然減衰は実際にはほとんど決着に効いていない:
##  - `build/playtest/report.md` の死因内訳では、敵の敗因のうち自然減衰は
##    **全レベルで0.0%**(削り51〜84% / 壁16〜49%)。
##  - `playtest/measure_launch_force.gd` で見る自機のrps喪失内訳も、ランの行方を
##    決めるLv3〜5では 削り71〜80% / 壁15〜25% / **減衰3〜11%**。
## それでも寿命は2行のうち1行を占め、しかも**カード間で最も大きく動く行**だった。
## 結果として、硬さを1ミリも動かさない FULL_STEAM_AHEAD が寿命 +5.4 と
## 「いちばん得する札」に見え、硬さを1.8倍にする GIANT_GROWTH が寿命 −4.3 と
## 「損する札」に見えていた。`playtest/measure_parts.gd`(Lv3・3枚)の実測では
## 前者が **+0.5pt(全11札で最下位)**、後者が **+95.2pt(1位)** で、**見積もりの
## 2行目が札の価値と逆を向いていた**。
##
## 一次証拠(コールドプレイ 2026-08-06, seed=4821): 効果テキストと見積もりだけで
## 11枚選んだ結果、FULL_STEAM_AHEAD を2枚採り GIANT_GROWTH を2回見送って、
## 硬さ 0.73→0.96(1.3倍)のまま決戦(敵の硬さ12.1〜12.6)へ入り**7連敗**した。
##
## そこで2行目を、**削り(＝喪失の7〜8割)に何回耐えられるか**に比例する
## **打たれ強さ**へ差し替えた。寿命そのものは対戦画面の StatReadout に残る
## ——あちらは「相手と自分のどちらが先に自滅するか」を比べる場所で、
## 相手が分かっているぶん寿命に意味がある。カードの巨大化札は効果テキストが
## 「大きくなるぶん自然減衰が速まる」と言い続けるので、代償が消えるわけではない。
##
## **なぜ3行目に壁の軸が要るのか**(2026-08-06)
## 硬さも打たれ強さも**接触(コマ同士の削り)の量**で、壁は1ミリも入っていない。
## ところが壁は喪失の半分以上を占める:
##  - コールドプレイ(seed=4821・9戦全勝でクリア)の自機rps喪失は、ラン合計で
##    **壁61.1 対 削り52.5**。段6以降は毎戦で壁が削りを上回った
##    (段6 8.8対4.5 / 段7 10.7対7.6 / 段8 12.0対10.3 / 決戦 20.3対14.8)。
##  - `custom_part_catalog.gd` の LOW_CENTER の由来にも
##    「壁でのrps喪失はプレイヤーの敗因の約半分を占める」とある。
## それでも見積もりの2行はどちらも接触の量なので、**壁の代償を軽くする唯一の札**
## RAGE_REFLECTION(wall_keep)は、報酬画面で
## 「硬さ 2.76 / 打たれ強さ 106.0」と**2行とも変化なし**で出ていた。
## 同じカードの効果文は「終盤は壁での喪失が削りに並ぶ、後半ほど効く」と書いている
## ので、**カードが自分の数字と正反対のことを言っている**状態だった
## (上のコールドプレイはこの札を2枚とも、見積もりを無視して効果文だけで取っている)。
## 対戦画面の StatReadout には反発の行があるのでRAGEも多少は動いて見えるが、
## **選ぶ場所である報酬画面にだけ壁の軸が無い**という切れ方をしていた。
##
## 打たれ強さと壁強さは wall_keep も hit_guard も0のうちは**同じ値になる**が、
## それは「ラン開始時は接触にも壁にも同じ回数だけ耐えられる」という本当のことで、
## 片方の札を取った瞬間に恒久的に割れる。並べる意味はそこにある——
## 衝突軽減と怒りの反射を並べたとき、どちらがどちらの軸かが2行の対比で一目で読める。
##
## **なぜ攻めが2行なのか**(2026-08-08)
## 上の3行を足した時点で守り(硬さ・打たれ強さ・壁強さ)は接触と壁の両方を数えるように
## なったが、**攻めは削りしか数えていなかった**。敵の死因は Lv2以降で壁が1/4〜1/2以上
## (Lv3・Lv4の乱戦では壁が主因)で、押し込む強さは攻め力に1ミリも入っていない。
## そのため RAGE_REFLECTION(反発↑=弾性衝突で相手をより遠くへ飛ばす)は攻めの行が
## 据え置きで出て、SHARP_EDGE の「弾き飛ばしも強まる」という効果文にも数字が付かない。
## 詳細と一次証拠は `knockback` の doc。
##
## 硬さ・攻め力・弾き・打たれ強さ・壁強さは**変化しない札でも常に出す**。「この札では硬さが伸びない」
## こと自体が選択に必要な情報で、行が出たり消えたりするとカードの高さも揺れる
## (行を1本足してもカードは371→403px、画面全体で521/720pxに収まることを実測済み)。
## 残機・無敵時間の行は、その札が動かすときだけ足す(コマの性能ではないため)。

## 硬さ・寿命・打たれ強さがゼロ除算にならないための下限。半径や回転減衰は@export_rangeで
## 0.1以上に制限されているが、テストや将来の札が0を渡してもnan/infを出さない。
const _EPSILON := 0.0001


## 硬さ = 質量 × 半径²。1衝突で削られるrpsがこれに反比例する(spinner_physics.spin_drain)。
static func toughness(stats: SpinnerStats) -> float:
	return stats.mass * stats.radius * stats.radius


## 寿命(秒の目安) = rps ÷ (半径 × 回転減衰)。自然減衰(natural_spin_decay)が
## 半径×回転減衰に比例するので、殴られなくてもこの時間で回転が尽きる。
static func lifetime(stats: SpinnerStats) -> float:
	var rate := decay_rate(stats)
	if rate < _EPSILON:
		return 0.0
	return stats.rps / rate


## 自然減衰の速さ = 半径 × 回転減衰。寿命の分母そのもの
## (SpinnerPhysics.natural_spin_decay がこれに比例する)。
##
## **4行が1本も読まない唯一の軸**。硬さは 質量×半径²、打たれ強さ・壁強さは
## rps×硬さ÷軽減、攻め力は 質量・半径・edge・drill で、**回転減衰(spin_decay)は
## どの行にも入っていない**。半径の方も、4行では**得の側にしか出てこない**
## (硬さを押し上げる)。decay_note はこの片側だけ見えている軸を補う。
static func decay_rate(stats: SpinnerStats) -> float:
	return stats.radius * stats.spin_decay


## 打たれ強さ = rps × 硬さ ÷ (1 − 衝突軽減)。**接触に何回耐えられるか**に比例する。
##
## 1接触で削られるrpsは
##   (相手の質量 × 相手の速さ × violence) ÷ 硬さ × (1 − hit_guard)
## (spin_drain と guarded_spin_drain)。耐えられる回数は rps ÷ これなので、
## 相手と速さと violence を共通因子として括り出すと rps × 硬さ ÷ (1 − hit_guard)
## が残る。**相手にも速さにも依らない**ので、硬さと同じく相手を知らずに出せる。
##
## 硬さの行と重なるが、重ならない札がある: 回転を上げる札(EXTRA_WINDING /
## SPIN_ENGINE)と衝突軽減の札(SHOCK_ABSORBER)は硬さを1ミリも動かさないので、
## 硬さの行だけでは「何も起きない札」に見える。特にSHOCK_ABSORBERは
## 硬さ・寿命の両方が凍っていて、**見積もりが一言も語らない札**だった。
static func endurance(stats: SpinnerStats) -> float:
	# hit_guard=1(完全無効化)でのゼロ除算避け。カタログの上限はGUARD_HIT_MAX=0.5
	# なので実プレイでは届かないが、届いても inf を出さない。
	var taken := maxf(1.0 - clampf(stats.hit_guard, 0.0, 1.0), _EPSILON)
	return stats.rps * toughness(stats) / taken


## 壁強さ = rps × 硬さ ÷ (1 − 壁での軽減)。**壁に何回耐えられるか**に比例する。
## 打たれ強さ(接触版)と同じ形で、割る相手が hit_guard ではなく wall_keep になる。
##
## 壁1回の喪失は wall_absolute_share(既定0.6)で2つの式を混ぜたもの
## (BattleResolver._wall_damaged_rps)。**支配的な絶対量の側**は
##   absolute_wall_drain(進入速度, 質量, 半径, wall_violence) × (1 − wall_keep)
##   = wall_violence × 進入速度 ÷ 硬さ × (1 − wall_keep)
## なので、耐えられる回数は rps ÷ これ。**wall_violence と進入速度を共通因子として
## 括り出す**と rps × 硬さ ÷ (1 − wall_keep) が残る——打たれ強さで相手・速さ・
## violence を括り出したのと同じ手口で、**土俵にも速さにも依らない**量になる。
##
## 残り(比例の側)は rps × effective_wall_damping(base, wall_keep) の乗算なので、
## 耐えられる回数は硬さに依らず対数で効く。ただし **rps↑・wall_keep↑ で増える向きは
## 同じ**(effective_wall_damping は wall_keep 単調増加)なので、2つの式で符号が
## 食い違うことはない。硬さの寄与だけが比例側で薄まる、という控えめな見積もりになる。
static func wall_endurance(stats: SpinnerStats) -> float:
	# wall_keep=1(壁で無損失)でのゼロ除算避け。カタログの上限は RAGE_WALL_KEEP_MAX=0.5
	# なので実プレイでは届かないが、届いても inf を出さない(endurance と同じ扱い)。
	var taken := maxf(1.0 - clampf(stats.wall_keep, 0.0, 1.0), _EPSILON)
	return stats.rps * toughness(stats) / taken


## 攻め力 = 1接触で**相手から削れる**rps(共通因子の violence と相対速さを括り出した値)。
## 上の3行が全部「自分がどれだけ削られないか」なのに対し、これだけが攻めの軸。
##
## **なぜ相手の硬さを引数で受けるのか**
## 硬さ・打たれ強さ・壁強さは、相手・速さ・violence を共通因子として括り出せたので
## 相手を知らずに出せた。攻めは括り出せない——素の削りは相手の硬さに反比例する一方、
## edge/drill の上乗せの基準 pierce(相手が自分と同じ硬さだったときの削り)は
## **自分の**硬さで決まり、両者は maxf で繋がっている(SpinnerPhysics の
## sharpened_spin_drain / drilled_spin_drain)。max の内側で相手が生き残るので、
## 「相手が誰でも同じ」量にはならない。だから基準の相手を1体、外から渡してもらう。
##
## 式は BattleResolver._resolve_pair の与ダメージ側そのまま。a(自分)が b(相手)へ
## 与える削りは
##   素の削り  = violence × 自分の質量 × 相対速さ ÷ 相手の硬さ
##   pierce   = violence × 相対速さ ÷ 自分の半径²  (spin_drain に自分の質量・半径を渡した値)
##   合計      = 素の削り + edge × max(素の削り, pierce) + drill × pierce
## で、**violence と相対速さは自分の札では動かない**ので括り出す。残るのが
##   自分の質量/相手の硬さ + edge × max(自分の質量/相手の硬さ, 1/自分の半径²)
##   + drill / 自分の半径²
## 相手の hit_guard(受け手の軽減)は敵側の性能なので、相手・速さと同じく括り出す。
##
## 一次証拠(コールドプレイ 2026-08-06, seed=48123): 9戦全勝でクリアしたが、
## **報酬10枚のうち攻めの札は1枚も取らなかった**。EDGE・DRILL・MOMENTUM・LOW_CENTER は
## 見積もりの3行が**1つも動かない**ので、GIANT_GROWTH(硬さ 0.73→1.32)や
## OVERENCUMBERED(打たれ強さ 37.2→46.9)と並ぶと**空欄の札**に見える。
## 段1で DRILL_BIT を効果文だけで取ったときも「硬さ 0.73 / 打たれ強さ 11.8 /
## 壁強さ 11.8」と3行とも据え置きで出ていて、取った後も何が変わったのか分からなかった。
## 結果、質量と直径だけを積む1本道のビルドになった——`build/playtest/report.md` は
## 報酬方針の差を **greedy 53.3% 対 random 14.7%(38.6pt)** と出しており、
## このゲームでいちばん結果を動かすのは札選びなのに、その画面に攻めの軸が無かった。
##
## opponent_toughness <= 0 は「基準の相手が居ない」= 行を出さない合図(rows を参照)。
## 自分の半径は @export_range で 0.1 以上に制限されているが、0 を渡されても
## inf を出さないよう _EPSILON で床を張る(endurance / wall_endurance と同じ扱い)。
static func attack(stats: SpinnerStats, opponent_toughness: float) -> float:
	if opponent_toughness <= 0.0:
		return 0.0
	var raw := stats.mass / opponent_toughness
	var pierce := 1.0 / maxf(stats.radius * stats.radius, _EPSILON)
	return (
		raw
		+ maxf(stats.edge, 0.0) * maxf(raw, pierce)
		+ maxf(stats.drill, 0.0) * pierce
	)


## 弾き = 1接触で相手に渡す「自分から離れる向きの速さ」(共通因子の噛み合う速さを
## 括り出した値)。攻め力が**削って倒す**側の軸なのに対し、これは**壁へ押し込んで
## 倒す**側の軸。
##
## **なぜ攻め力の隣にもう1本要るのか**(2026-08-08)
## 敵は削りだけで死ぬのではない。`build/playtest/report.md` の死因内訳(1200ラン)は
##   Lv1 単体 削り95.2% / 壁 4.8%     Lv3 乱戦 削り47.5% / 壁 **52.5%**
##   Lv2 単体 削り60.7% / 壁 39.3%    Lv4 乱戦 削り44.7% / 壁 **55.3%**
##   Lv5 単体 削り71.0% / 壁 29.0%
## で、**Lv2以降は敵の死の1/4〜1/2以上が壁**、Lv3〜4の乱戦では壁が主因を上回る。
## 自然減衰(全レベル0.0%)を注記へ降ろしたのと正反対の重みを持つ軸なのに、
## 報酬画面の攻めの行は**削りしか数えていなかった**。
##
## 一次証拠(コールドプレイ 2026-08-08, seed=4471・9戦全勝でクリア): 段5以降の5戦の
## うち**4戦で決着死因が「壁」**、敵のrps喪失も壁が削りを上回った
## (段5 壁14.5対削り8.0 / 段7 壁15.2対15.1 / 段8 壁24.9対11.4 / 決戦 壁20.4対16.2)。
## 実際に勝たせていたのは「当ててから壁へ押し込む」ことなのに、選ぶ画面には
## 攻め力(削り)しか無く、押し込む強さが伸びたのか縮んだのかは最後まで分からなかった。
## しかもカード文面の方は既にそれを言っている——GIANT_GROWTH と OVERENCUMBERED は
## 「相手をより弾く」、SHARP_EDGE は「弾き飛ばしも強まる」、`SpinnerStats.edge` の
## 注釈も「相手を強く弾き飛ばす=壁へ押し込む攻め」と書いていた。
## **カードが言っていることが数字のどこにも出ていない**、壁強さを足す前と同じ切れ方。
##
## **式**(`BattleResolver._resolve_disc_collision` の相手側そのまま)
## 相手 b が自分 a から受け取る「離れる向きの速さ」は2つの和:
##   弾性衝突     (1 + 反発の積) × 自分の質量 ÷ (自分の質量 + 相手の質量) × 噛み合う速さ
##                (SpinnerPhysics.elastic_velocities の中心線方向の交換)
##   spin_kick   spin_kick_scale × 相手の半径 × 相手が受けた削り
##                (SpinnerPhysics.spin_kick。削り比例なので edge/drill もここで効く)
## 相手が受けた削りは violence × 自分の速さ × attack() × (1 − 相手の衝突軽減) なので、
## **噛み合う速さ**を共通因子として括り出すと(正面から止まっている相手に当てる=
## プレイヤーが実際に狙う発射の1撃では、自分の速さと噛み合う速さが一致する)
##   (1 + 反発の積) × 質量比 + spin_kick_scale × 相手の半径 × violence × attack × (1 − 軽減)
## が残る。硬さ・打たれ強さ・壁強さで相手・速さ・violence を括り出したのと同じ手口で、
## **速さに依らない**量になる。violence と spin_kick_scale は2つの項の重みが
## 単位ごと違うので括り出せず、BattleRequest の既定値を使う
## (Battle.gd の @export と一致することは test_battle_defaults.gd が見張っている)。
##
## 相手を引数で受けるのは攻め力と同じ理由に加えて、**質量比が相手の質量を含む**ため。
## 1接触で奪えるrpsの天井(`capped_spin_drain`)は掛けない——天井は相手の残りrpsに
## 依るので、札を選ぶ時点では相手の減り具合が分からない。天井に張り付いている
## 相手では spin_kick の側が実際より大きく出る、控えめでない向きの近似なので、
## そこは弾性衝突の側が支配的(実測: 素のコマ基準で弾性が Lv1 55% / Lv3 83% /
## Lv5 92%)であることで薄まっている。
static func knockback(
	stats: SpinnerStats, opponent: SpinnerStats,
	spin_kick_scale: float, violence: float
) -> float:
	if stats == null or opponent == null:
		return 0.0
	var total_mass := maxf(stats.mass + opponent.mass, _EPSILON)
	# 反発は積で、かつ壁と同じく[0,1]へクランプする(1超は発散するので
	# BattleResolver も同じクランプを掛けている。表示だけ発散させない)。
	var pair_restitution := clampf(stats.restitution * opponent.restitution, 0.0, 1.0)
	var exchange := (1.0 + pair_restitution) * stats.mass / total_mass
	# 受け手の衝突軽減(Shock Absorber)は削りを減らし、削り比例の spin_kick も一緒に
	# 減らす。敵は現状0だが、相手の性能として素直に読む。
	var taken := 1.0 - clampf(opponent.hit_guard, 0.0, 1.0)
	var kick := (
		maxf(spin_kick_scale, 0.0) * opponent.radius * maxf(violence, 0.0)
		* attack(stats, toughness(opponent)) * taken
	)
	return exchange + kick


## 弾きの行に**実際に出す**値。素のコマが同じ相手を弾く量で割った倍率で、
## 素のコマがちょうど 1.00 になる。
##
## 攻め力(`attack_index`)と揃える理由は2つ。生の弾きは質量比の項が
## **相手が重いほど縮む**ので、そのまま出すとラン中に自分が育つほど数字が小さくなる
## ——攻め力を倍率へ変えた 2026-08-07 とまったく同じ逆立ちが起きる。もう1つは、
## 攻めの2行が同じ「素のコマの何倍か」で並ぶと、削りと押し込みのどちらが伸びた札
## なのかが横並びで読めること(mass札は両方・EDGE/DRILL札は攻め力だけ・
## RAGE_REFLECTION は弾きだけを動かす)。
##
## violence / spin_kick_scale は分子・分母で共通なので、既定値から動いても
## 倍率の大小関係は保たれる。
static func knockback_index(stats: SpinnerStats, opponent: SpinnerStats) -> float:
	if stats == null or opponent == null:
		return 0.0
	var req := BattleRequest.new()
	var base := knockback(
		SpinnerStats.default_player(), opponent, req.spin_kick_scale, req.violence
	)
	if base < _EPSILON:
		return 0.0
	return knockback(stats, opponent, req.spin_kick_scale, req.violence) / base


## 攻め力の行に**実際に出す**値。`attack` を「出発時のコマが同じ相手へ与える削り」で
## 割った倍率で、素のコマがちょうど 1.00 になる。
##
## **なぜ生の attack をそのまま出さないのか**(2026-08-07)
## `attack` は「この相手へ1接触で削れる量」で、値としては正しい。ところが基準の相手は
## 段が進むごとに硬くなり(ThreatMeter 冒頭: Lv1 0.12 → Lv5 12.5 の100倍)、素の削りは
## その硬さに**反比例**する。結果、**自分は強くなり続けているのに行だけが縮む**。
##
## 一次証拠(コールドプレイ 2026-08-07, seed=4821・9戦全勝でクリア): 札を10枚積んで
## いく途中の攻め力が段ごとに
##   13.33 → 3.56 → 5.59 → 2.61 → 2.45 → 1.52 → 1.48 → 1.02
## と**下がり続けた**。隣の打たれ強さは 11.8 → 137.0 と伸びるので、同じ4行の中で
## この行だけが逆を向く。前サイクルが基準の相手の硬さを注記(`attack_basis_text`)で
## 併記して「なぜ縮むか」までは言えるようにしたが、**縮む数字そのもの**は残ったので、
## 「自分の攻めは育っているのか」には最後まで答えられなかった
## (前サイクルの journal も同じ現象を独立に実測して「次の候補」の筆頭に置いている)。
##
## 割る相手を**素のコマ**に固定すると、同じ実測が
##   1.00 → 1.17 → 1.54 → 2.64 → 2.86 → 3.71 → 3.83 → 8.55
## と**単調に伸びる**。守りの3行と同じ向きになり、「出発時の何倍削れるか」という
## 一言で読める。基準の相手は分母にも分子にも入るので消えはしない——最後の跳ね上がりは
## 「貫通削り(pierce)は相手の硬さに依らないので、硬い相手ほど素のコマとの差が開く」
## という本当のことで、DRILL/EDGE を積んだビルドが決戦で効く理由がそのまま出ている。
##
## 1画面の中でのカード同士の比較は**一切変わらない**。分母は3枚とも共通の正の数
## (素のコマ×同じ相手)なので、倍率は attack の正のスカラー倍——大小関係も
## 「伸びる/据え置き/縮む」の向きも保たれる。変わるのは**画面をまたいだ読み**だけ。
##
## 分母は `SpinnerStats.default_player()`(ランの出発点。GameState.default_player_stats が
## そのまま返すのと同じ実体)。素のコマは edge も drill も 0 なので
## 分母は 質量÷相手の硬さ で、相手の硬さが正なら必ず正になる。
static func attack_index(stats: SpinnerStats, opponent_toughness: float) -> float:
	if opponent_toughness <= 0.0:
		return 0.0
	var base := attack(SpinnerStats.default_player(), opponent_toughness)
	if base < _EPSILON:
		return 0.0
	return attack(stats, opponent_toughness) / base


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
##
## opponent は攻めの2行の基準にする相手1体(Main が
## ThreatMeter.reachable_hardest_stats で「次に踏みうる部屋のいちばん硬い1体」を
## 渡す)。null なら攻めの2行を出さない——基準の相手が居ないのは最終戦のあとと、
## ステータス無しで呼ばれる古い経路・テストだけで、そこで嘘の基準を捏造すると
## 「相手を知らずに出せる3行」との区別が消える。
##
## **硬さだけでなく相手のステータスそのものを受ける**(2026-08-08)。攻め力は相手の
## 硬さだけで足りるが、弾きは**質量比**も読む(knockback 参照)。スカラーを2つ別々に
## 受けると、片方だけ違う敵のものを渡す配線ミスが黙って通る。相手は1体として渡す。
##
## 攻め力・弾きを硬さの直後に置くのは、この3つが**同じ1接触の表と裏**だから
## (硬さ=1接触で削られない量 / 攻め力=1接触で削る量 / 弾き=1接触で押し出す速さ)。
## 残る2行は「何回耐えられるか」で単位が違うので、後ろにまとめる。
static func rows(
	stats: SpinnerStats, part: CustomPart,
	continues: int = -1, ghost_seconds: float = 0.0,
	opponent: SpinnerStats = null
) -> Array[Dictionary]:
	var after := preview_stats(stats, part)
	var result: Array[Dictionary] = [
		_row("STAT_TOUGHNESS", toughness(stats), toughness(after), 2),
	]
	var opponent_toughness := toughness(opponent) if opponent != null else 0.0
	if opponent_toughness > 0.0:
		# 出す値は生の attack ではなく素のコマ基準の倍率(attack_index 参照)。
		result.append(_row(
			"STAT_ATTACK",
			attack_index(stats, opponent_toughness),
			attack_index(after, opponent_toughness),
			2, "×"
		))
		# 削って倒す軸(攻め力)の隣に、壁へ押し込んで倒す軸。Lv2以降は敵の死の
		# 1/4〜1/2以上が壁なのに、この行が無いあいだ攻めの行は削りしか数えて
		# いなかった(knockback 参照)。こちらも素のコマ基準の倍率。
		result.append(_row(
			"STAT_KNOCKBACK",
			knockback_index(stats, opponent),
			knockback_index(after, opponent),
			2, "×"
		))
	result.append(_row("STAT_ENDURANCE", endurance(stats), endurance(after), 1))
	result.append(
		_row("STAT_WALL_ENDURANCE", wall_endurance(stats), wall_endurance(after), 1)
	)
	# 残機札(SPARE_CORE)はコマの性能を一切変えないので、硬さ・打たれ強さだけでは
	# 「何も起きない札」に見えてしまう。GameState側の効果をここで補う。
	if continues >= 0 and part.lives > 0:
		result.append(_row("STAT_LIVES", continues, maxi(continues, part.lives), 0))
	if part.effect == CustomPart.Effect.GHOST and part.ghost_seconds > 0.0:
		result.append(_row(
			"STAT_GHOST", ghost_seconds, ghost_seconds + part.ghost_seconds, 1
		))
	return result


## 攻めの行が**何を基準にした値なのか**を1行で言う注記。基準の相手が居なければ
## 空文字(攻めの行そのものが出ない)。
##
## **なぜ要るのか**(2026-08-07)
## 守りの3行(硬さ・打たれ強さ・壁強さ)は相手を括り出せているのでラン中は単調に伸びる。
## 攻めの行だけは基準の相手を1体受け取っていて(attack 参照)、その相手の硬さは
## レベルごとに3〜4倍動く(ThreatMeter 冒頭のコメント: Lv1 0.12 → Lv5 12.5)。
## 結果、**自分は強くなっているのに攻めの行だけがラン中に9割縮む**。
##
## 一次証拠(コールドプレイ 2026-08-07, seed=4711): 同じビルドが育っていく途中で
## 攻め力が 12.59(段1の報酬) → 4.31(段2) → 1.66(段3) → 1.09(段8) と落ちていき、
## 他の3行が 11.8 → 68.7 と伸びる隣で**この行だけ逆を向いている理由が読めなかった**。
## 1画面の中でカード同士を比べるぶんには正しいので嘘ではないが、行の名前も
## 見出しも基準を言っていないので、初見には「強くなるほど攻めが落ちる」に見える。
## (前サイクルの journal も同じ現象を実測して「行の名前が基準を語っていない」と
## 書き残している。)
##
## そこで**基準の相手の硬さを数字で出す**。カードの1行目が自分の硬さなので、
## 「自分 1.72 / 相手 12.64」が同じ画面で並び、攻めが縮んだ理由がその場で読める
## ——このゲームの中心にある非対称(自分の硬さは2倍しか動かないのに相手は16倍動く)
## が、部品を選ぶまさにその画面に出る。
##
## **2026-08-07 追記**: 行の値そのものを素のコマ基準の倍率へ変えた(`attack_index`)ので、
## この注記も「何倍か」を先に言う。基準の相手を出し続けるのは、倍率の分母にも分子にも
## その相手が入っている(硬い相手ほど貫通削りの差が開く)からで、どの相手を見た倍率かは
## 依然として読み手に要る情報。
##
## 行の中ではなくカードの外の1行に置くのは、3枚のカードで基準が共通だから
## (同じ文をカードごとに3回出しても情報は増えない)と、カード幅220pxの行に
## 長い項目名を足すと値と衝突するため。
static func attack_basis_text(opponent_toughness: float) -> String:
	if opponent_toughness <= 0.0:
		return ""
	return TranslationServer.translate("REWARD_ATTACK_BASIS").format(
		[String.num(opponent_toughness, 2)]
	)


## 自然減衰の軸が動く札にだけ付ける注記。動かなければ空の辞書を返し、呼び手は
## ラベルごと出さない(`CustomPart.capped_note` と同じ約束)。
## 返す辞書は {"text": 表示文, "better": +1/0/-1} で、better は**寿命**の向き。
##
## **なぜ行ではなく注記なのか**(2026-08-07)
## 寿命は 2026-08-06 に2行目から外した軸で、その判断は今も正しい——当時の2行構成では
## 寿命が**カード間で最も大きく動く行**になり、実測最下位の FULL_STEAM_AHEAD(+0.5pt)が
## いちばん得に見え、実測1位の GIANT_GROWTH(+95.2pt)に唯一のマイナスが付いていた。
## 揃った数値の列に peer として並べると、読み手は4本を横並びで数えるので、
## 決着にほとんど効かない軸(敵の敗因の自然減衰は全レベル0.0%)が1/5票を持ってしまう。
##
## それでも**代償と得が数字でどこにも出ない**のは別の欠陥だった。4行が読むのは
## 質量・半径・rps・hit_guard・wall_keep・edge・drill で、**回転減衰は1行も読まず**、
## **半径は硬さを押し上げる得の側にしか出てこない**。
##
## 一次証拠(コールドプレイ 2026-08-07 夜, seed=25458): 段5で GIANT_GROWTH を取ったら
## 4行が全部上がって見えた裏で寿命が 25.2→22.0 に落ちていて、そのまま2枚積んだ結果
## 段6・段7が **22.0秒/25衝突・25.0秒/23衝突**の消耗戦になり、自分のrps喪失のうち
## **自然減衰が6.9・7.9**(全体の24%・30%)を占めた。逆に段7で FULL_STEAM_AHEAD は
## 寿命を **28.9→38.0(+31%)** も伸ばすのに、4行では攻め力が ×2.56→×2.80 と
## 動くだけの地味な札に見えた——**その時いちばん大きかった喪失源を唯一直せる札**が、
## 画面上でいちばん小さく見えていた。
##
## そこで peer の行ではなく、**上限注記(capped_note)と同じ小さな1行**として出す。
## 揃った値の列の外に置くので4行を横並びで数える読みは変わらず、代償と得だけが
## 数字になる。色は行と同じ規則(良し悪しは色で見せる)。
##
## **なぜ寿命の変化ではなく減衰率の変化で出すのか**
## 寿命 = rps ÷ 減衰率 なので、回転を上げる札(EXTRA_WINDING / SPIN_ENGINE)でも
## 寿命は伸びる。しかし rps は打たれ強さ・壁強さの**2行が既に読んでいる**軸で、
## そこに3つ目の上向きを足しても情報は増えず、回転札を過大に見せるだけになる。
## 出す条件を**減衰率(半径×回転減衰)が動いたとき**に絞ると、カタログ12枚のうち
## GIANT_GROWTH(0.700→0.875)と FULL_STEAM_AHEAD(0.700→0.560)の**2枚だけ**が
## 該当する——上のコールドプレイで取り違えた2枚と正確に一致する。
## 直径が既に上限のビルドでは減衰率が動かないので注記も出ない(代償が無いのは本当で、
## 「もう直径は伸びない」は capped_note の側が言う)。
static func decay_note(stats: SpinnerStats, part: CustomPart) -> Dictionary:
	if stats == null or part == null:
		return {}
	var after := preview_stats(stats, part)
	# 見るのは減衰率そのものではなく**その2つの軸**。物差しは上限注記と共有する
	# (CustomPart.stat_moved)——別々に持つと、上限注記が「回転減衰はもう伸びない」と
	# 言う隣で減衰の注記だけが動いて見える(実測: 勢い維持4枚のビルドで
	# 回転減衰 0.41→下限0.40 が「寿命 76.7 → 78.6」として出た)。
	if not (
		CustomPart.stat_moved(stats.radius, after.radius)
		or CustomPart.stat_moved(stats.spin_decay, after.spin_decay)
	):
		return {}
	var before_life := lifetime(stats)
	var after_life := lifetime(after)
	var better := 0
	if not is_equal_approx(before_life, after_life):
		better = 1 if after_life > before_life else -1
	return {
		"text": TranslationServer.translate("REWARD_DECAY_NOTE").format(
			[String.num(before_life, 1), String.num(after_life, 1)]
		),
		"better": better,
	}


## prefix は値の前に付ける記号。攻め力だけが**倍率**(素のコマ=1.00)なので、
## 硬さ・打たれ強さのような絶対量と同じ見た目で並ぶと単位を取り違える。
static func _row(
	label_key: String, before: float, after: float, digits: int, prefix: String = ""
) -> Dictionary:
	var better := 0
	if not is_equal_approx(before, after):
		better = 1 if after > before else -1
	return {
		"label_key": label_key, "before": before, "after": after,
		"digits": digits, "better": better, "prefix": prefix,
	}


## 1行の表示文字列。変化しないときは今の値だけを出す(「0.73 → 0.73」は読み手に
## 変化があると誤読させる)。矢印は方向を持たない記号にして、良し悪しは色で見せる。
static func format_row(row: Dictionary) -> String:
	var digits: int = row["digits"]
	var prefix: String = row.get("prefix", "")
	var before := prefix + String.num(row["before"], digits)
	if row["better"] == 0:
		return before
	return "%s → %s" % [before, prefix + String.num(row["after"], digits)]
