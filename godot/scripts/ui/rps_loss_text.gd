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

## 同士討ちの欄を出す下限。表示は小数1桁なので、これ未満は出しても「0.0」にしか
## ならず、単体戦の厳密な0と浮動小数の塵を同じ「出さない」に倒せる。
const _MUTUAL_EPS := 0.05


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


## 相手側の内訳行。自分の行(summary_line)の真下に同じ並びで出し、縦に読み比べれば
## 「もらった削り18.1 / 与えた削り12.6」「自分の壁13.5(9回) / 相手の壁8.2(3回)」の
## ように**非対称そのもの**が見えるようにする。自分の喪失だけを見せても多いのか
## 少ないのかの基準が無く、ボスに連敗しても何を変えればいいのか分からなかった
## (journal 筆頭候補「ボス連敗の手がかりの無さ」)。
##
## 削りだけは相手の総喪失でなく `drain_by_player`(プレイヤーが殴った分)を使う。
## 乱戦では敵同士の同士討ちも相手の lost_drain に入るので、総量を「与えた削り」と
## 呼ぶと自分の手柄を水増しする。壁・減衰は相手が自分で失った量そのものなので、
## 行の見出しも「与えた」ではなく「相手が失った回転」にして、削りの欄にだけ
## 「自分の」と断る(単体戦では両者一致する)。
##
## enemies は BattleResult.enemy_rps_loss(敵ごとの内訳Dictionary)。乱戦では和を取る
## ——片付けるべき部屋の総量が答えなので、頭数ぶん積むのが正しい集約
## (ThreatMeter の硬さが和なのと同じ理由)。
##
## 乱戦では **同士討ち**(lost_drain のうちプレイヤーが絡まない分 = drain − drain_by_player)
## を独立した欄として足す。以前は自分の手柄でないという理由でこの分を落としていたが、
## 落とすと相手の行の数字が相手の実際の喪失に**足りなくなる**。2026-08-04 の
## コールドプレイの実測では、段2(3体)で敵が削りで失った 50.4 のうち自分の寄与は
## 25.6 で、**残り 24.8(49%)がリザルトのどこにも出ていなかった**。段7(2体)でも
## 敵1体あたり 14.6 のうち 4.1(28%)が同士討ち。乱戦で一番効く手が「敵同士が
## ぶつかる位置へ置く」ことなのに、それが起きた事実が画面に一度も出ないので
## 学びようがない。手柄の水増しは「自分の削り」の欄を drain_by_player のまま
## 据え置くことで防ぎ、同士討ちは別欄にして混ぜない。
##
## 単体戦では同士討ちは厳密に0なので欄ごと出さない(「同士討ち0.0」は無意味な雑音)。
static func dealt_line(enemies: Array) -> String:
	if enemies.is_empty():
		return ""
	# 旧結果(drain_by_player を持たない)は0埋めすると「削り0.0」と嘘をつくので、
	# 1体も持っていなければ行ごと出さない(summary_line の空Dictionary扱いと同じ流儀)。
	var attributed := false
	var drain := 0.0
	var mutual := 0.0
	var wall := 0.0
	var decay := 0.0
	var wall_hits := 0
	for loss in enemies:
		if not (loss is Dictionary) or loss.is_empty():
			continue
		if loss.has("drain_by_player"):
			attributed = true
		var by_player := float(loss.get("drain_by_player", 0.0))
		drain += by_player
		# 総削りを持たない旧結果では by_player を総量とみなす=同士討ち0。
		mutual += maxf(float(loss.get("drain", by_player)) - by_player, 0.0)
		wall += float(loss.get("wall", 0.0))
		decay += float(loss.get("decay", 0.0))
		wall_hits += int(loss.get("wall_hits", 0))
	if not attributed:
		return ""
	if mutual < _MUTUAL_EPS:
		return TranslationServer.translate("BATTLE_RPS_DEALT_BREAKDOWN").format([
			_fmt(drain), _fmt(wall), wall_hits, _fmt(decay),
		])
	return TranslationServer.translate("BATTLE_RPS_DEALT_BREAKDOWN_MUTUAL").format([
		_fmt(drain), _fmt(mutual), _fmt(wall), wall_hits, _fmt(decay),
	])


## 割合の行に並べる機構の順。summary_line の並び(削り→壁→減衰)と同じにする
## ——同じ内訳を2つの画面で別の順に出すと、縦に読み比べる相手が入れ替わる。
const _SHARE_KEYS := ["drain", "wall", "decay"]


## 「自分の回転がどこへ消えたか」を**割合**にした3つ組 [削り%, 壁%, 減衰%]。
## 総量が0(または内訳なし)なら空配列を返し、呼び手は行ごと落とす。
##
## 絶対量ではなく割合なのが要。報酬の軽減札は**その機構の何%を減らすか**で効く
## (RAGE = 壁の喪失-17% / SHOCK_ABSORBER = 衝突削り-17%、上限も0.5で同じ)ので、
## 2枚のどちらが得かを決めるのは自分の喪失の**構成比**であって、戦いごとに変わる
## 絶対量ではない。絶対量はリザルト画面(summary_line)が既に言っている。
##
## 端数は最大剰余法で配る。単純な四捨五入だと合計が99%や101%になり、
## 「内訳の割合」を名乗る行として壊れて見える。
static func shares(loss: Dictionary) -> Array[int]:
	var out: Array[int] = []
	if loss.is_empty():
		return out
	var values: Array[float] = []
	var total := 0.0
	for key in _SHARE_KEYS:
		var v := maxf(float(loss.get(key, 0.0)), 0.0)
		values.append(v)
		total += v
	if total <= 0.0:
		return out
	var remainders: Array[float] = []
	var floored := 0
	for v in values:
		var exact := v / total * 100.0
		var f := int(floor(exact))
		out.append(f)
		remainders.append(exact - float(f))
		floored += f
	var left := 100 - floored
	while left > 0:
		var best := 0
		var best_remainder := -1.0
		for i in remainders.size():
			if remainders[i] > best_remainder:
				best_remainder = remainders[i]
				best = i
		out[best] += 1
		remainders[best] = -1.0
		left -= 1
	return out


## 報酬画面に出す「直前の戦いで自分の回転がどこへ消えたか」の1行。
##
## 動機はコールドプレイ(2026-08-09)の一次証拠。段5の報酬で
## PART_RAGE_REFLECTION(壁での喪失-17%)を取ったが、**自分の壁の取り分を知らないまま
## 取った**。直前の戦いは 削り7.1 / 壁7.6 とほぼ五分で、実際にはコイントスだった。
## 続く段8では鏡写しの PART_SHOCK_ABSORBER(衝突削り-17%)が出て、直前の戦いは
## 削り16.1 / 壁9.7 と削り優勢——**取るべき札が測定済みの数字で決まっていたのに、
## その数字は1画面前で消えていた**。リザルト画面には出ている(summary_line)が、
## 報酬を選ぶ画面に移った時点で見えなくなる。
##
## 出すのは**自分の喪失だけ**。相手の喪失(dealt_line)は「相手を倒せたか」の話で、
## 軽減札が効く先ではない。攻めの見積もりはカードの行(PartPreview)が既に言う。
##
## 内訳なし・総量0(旧結果、報酬画面が戦闘を経ずに開かれた場合)は空文字を返す。
static func share_line(loss: Dictionary) -> String:
	var s := shares(loss)
	if s.is_empty():
		return ""
	return TranslationServer.translate("REWARD_RECENT_LOSS").format([
		s[0], s[1], int(loss.get("wall_hits", 0)), s[2],
	])


## **次の戦いの発射前**に据え置きで出す「前の戦いで自分の回転がどこへ消えたか」の1行。
## 中身は share_line と同じ3つの割合で、違うのは訳文(「前の戦い」と断る)だけ。
##
## 動機はコールドプレイ(2026-08-09 昼, seed=48213)の一次証拠。段1で満引きして勝ったが、
## **自分の喪失の63%が壁**(削り2.5 / 壁5.9・4回 / 減衰1.0)で、残りrpsは37%まで削られていた。
## それを知ったのは戦いが終わって報酬画面に移った後で、そこで初めて
## PART_LOW_CENTER(中央へ引き戻す=壁が遠くなる)を選んだ。以後も段5で壁52%(3回)・
## 段6で壁47%(2回)と、**壁が自分の最大の出費である戦いが9戦中3戦**あったのに、
## 発射を決める画面ではその事実が毎回消えていた——「次はもう少し弱く引こう」を
## いちばん思い出したい瞬間に、思い出す材料が画面に無い。
##
## 発射前の見積もり(WallCostPreview)は**相手に届くまで**しか見ない。噛み合った後の
## もみ合いで払う壁は自由飛行の先読みでは出せないので、そこは実測の据え置きで補う
## ——この行が答えるのは「この狙いは何を払うか」ではなく「**自分のビルドは何で
## 死にかけているか**」で、土俵も相手も変わっても持ち越して意味のある問い。
##
## 前の戦いの内訳が無い(ランの1戦目・旧結果・総量0)なら空文字。呼び手は行ごと落とす。
static func carryover_line(loss: Dictionary) -> String:
	var s := shares(loss)
	if s.is_empty():
		return ""
	return TranslationServer.translate("BATTLE_LAST_LOSS_CARRYOVER").format([
		s[0], s[1], int(loss.get("wall_hits", 0)), s[2],
	])


## 表示用の数値。小数1桁固定(丸めで桁が揺れない)。負は0に潰す(蓄積は非負のはずだが表示の防衛)。
static func _fmt(value: float) -> String:
	return "%.1f" % maxf(value, 0.0)
