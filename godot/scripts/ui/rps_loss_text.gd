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


## 表示用の数値。小数1桁固定(丸めで桁が揺れない)。負は0に潰す(蓄積は非負のはずだが表示の防衛)。
static func _fmt(value: float) -> String:
	return "%.1f" % maxf(value, 0.0)
