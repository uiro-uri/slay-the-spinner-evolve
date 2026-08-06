class_name RemainingRpsText
extends RefCounted

## 決着後のリザルトに出す「どちらがどれだけ回転を残して立っていたか」の行を組み立てる。
##
## RpsLossText の2行(自分/相手の喪失内訳)は**何で失ったか**を語るが、
## **どれだけ残して決着したか**は3項を手で合算し、しかも相手の開始rps(画面のどこにも
## 出ない)で割らないと出ない。つまり実UIでは事実上読めない。
##
## この1行が無いと、連敗が「近づいているのか」まったく分からない。2026-08-05 の
## コールドプレイでは決戦(段9)に6連敗し、敵の残りは順に 25% / 22% / 12% / 25% /
## 16% / **0.5%**(0.2/40.1)だった。最後の1敗は**あと一撃**だったのに、画面には
## 「敗北...」と喪失内訳しか出ないので、6敗が全部同じ「歯が立たない」に見えていた。
## しかもリトライは毎回**別個体**を出す(開始rps 38.6〜40.1、硬さ 12.07〜12.56)ので、
## 内訳の素の合計を並べても試行間で比較できない——**個体差で割った割合**でないと
## 「前より近づいた」が読めない。
##
## CLI(playtest/naive_play.gd の remaining_text)には 2026-07 のサイクルで同じ行が
## 入っていて、そちらの docstring は「実UIなら再生中のrpsバーで見えている情報」と
## 書いている。実際には**バーは全員同じ _max_rps 目盛りで、個体の満タンに対する割合を
## 出さない**し、決着の瞬間に消える。前サイクルが CLI を実UIの情報量へ揃えたのの逆で、
## 今回は**実UIを CLI の情報量へ揃える**(「ハーネスと実ゲームの情報量は対等に保つ」)。
##
## 静的関数からは tr() を呼べないので、TranslationServer で現在ロケールを引く
## (RpsLossText と同じ流儀)。

## 割合を出す下限の開始rps。これ以下は「そもそも回っていなかった」として0%に倒す。
## 単なる0除算避けではない: 0近傍で割ると 5.0/0.0005 = 1000000% が頭打ちで100%になり、
## **満タンで生き残った**と正反対の嘘になる。
const _START_EPS := 0.001


## frames(BattleResult.Snapshot の配列。先頭=開始時、末尾=決着時)から
## {"start": 開始rps, "final": 残りrps} を取り出す。フレームを持たない結果
## (to_dict/from_dict の旧データ)は空Dictionary＝呼び手が行ごと出さない。
static func margin(frames: Array) -> Dictionary:
	if frames.is_empty():
		return {}
	return {
		"start": maxf(float(frames[0].rps), 0.0),
		"final": maxf(float(frames[frames.size() - 1].rps), 0.0),
	}


## 敵の頭数ぶんを1つに畳んだ残量。tracks は BattleResult.enemy_tracks。
##
## 和を取るのは、答えるべき問いが「この部屋はあとどれだけ残っていたか」だから
## (RpsLossText.dealt_line が喪失を足すのと、ThreatMeter が硬さを足すのと同じ理由)。
## 落ちた敵は末尾フレームが lose_threshold 以下なので、和にはほぼ0しか足さない。
##
## 1体でもフレームを持たない結果が混ざったら空Dictionary＝行ごと出さない。
## 一部だけ足すと「相手の満タン」が実際より小さく出て、割合が水増しされる。
static func totals(tracks: Array) -> Dictionary:
	if tracks.is_empty():
		return {}
	var start := 0.0
	var final := 0.0
	for track in tracks:
		if not (track is Array):
			return {}
		var m := margin(track)
		if m.is_empty():
			return {}
		start += float(m["start"])
		final += float(m["final"])
	return {"start": start, "final": final}


## 残量の百分率(0〜100の整数)。開始rpsが無い/0なら0%。
## 四捨五入なので 0.2/40.1 は「0%」になるが、行には実数(0.2)も併記するので
## 「0%だがまだ0.2残っていた＝あと一撃」が読める。割合だけ・実数だけでは
## どちらも足りない(実数は個体差で比較できず、割合は最後の一滴を潰す)。
static func percent(m: Dictionary) -> int:
	if m.is_empty():
		return 0
	var start := float(m.get("start", 0.0))
	if start < _START_EPS:
		return 0
	return clampi(int(round(float(m.get("final", 0.0)) / start * 100.0)), 0, 100)


## 決着時の残り回転の1行。自分と相手を同じ書式で横に並べる。
##
## 勝てば相手が0、負ければ自分が0になるので片側は必ず0付近になるが、それは
## 雑音ではなく「片方が拭き取られた」という事実で、並べるからこそ生き残った側の
## 数字が基準を持つ(RpsLossText.dealt_line が両側を縦に並べるのと同じ考え)。
##
## player_frames は BattleResult.player_frames、enemy_tracks は同 enemy_tracks。
## どちらかがフレームを持たなければ空文字＝ラベルは見えないまま。
static func remaining_line(player_frames: Array, enemy_tracks: Array) -> String:
	var mine := margin(player_frames)
	var theirs := totals(enemy_tracks)
	if mine.is_empty() or theirs.is_empty():
		return ""
	return TranslationServer.translate("BATTLE_RPS_REMAINING").format([
		_fmt(float(mine["final"])), percent(mine),
		_fmt(float(theirs["final"])), percent(theirs),
	])


## 敗北画面に出す「相手はどれだけ残して立っていたか」の1行。
##
## remaining_line は決着リザルト(戦闘画面)の行で、**負けた瞬間に一緒に消える**。
## Main は goto_gameover() で画面ごと差し替えるので、プレイヤーが
## 「同じ相手にもう一度／相手を替えて挑む／あきらめる」を選ぶ画面には
## 残機の数しか出ていない。3択のうち2つは**相手をどう扱うか**の選択なのに、
## その相手にどこまで届いていたかが画面から消えている。
##
## 2026-08-06 のコールドプレイでは決戦で敗北し、相手の残りは 1.9/38.6(5%)だった。
## あきらめずに残機を払ったのは**この数字を見たから**で、CLIには出ていたが
## 実UIでは戦闘画面を離れた時点で失われる情報だった。
##
## 自分の側は出さない。負けた側なので必ず0付近で、3択の判断材料にならない
## (remaining_line が両側を並べるのは「勝ったときも出す」行だからで、
## こちらは敗北専用)。頭数は totals と同じく畳む＝答えるべき問いは
## 「この部屋はあとどれだけ残っていたか」。
##
## 受け取るのは BattleResult.enemy_tracks そのもの。畳むのは**ここ**で、
## 呼び手(Battle→Main→GameOver)は軌跡を素通しするだけにしてある。畳んだ後の
## Dictionaryを渡す形にすると、頭数の畳み方がテストの無い層(Battle)へ漏れて、
## そこを壊してもテストが赤くならない(実際にサボタージュで素通りした)。
##
## 軌跡を持たない結果(totalsが空)なら空文字＝ラベルは見えないまま。
## 値の取り出しに get(既定0.0)を使うのは防御ではなく**この門を可視にするため**で、
## 門を外すと空文字ではなく「0.0(0%)」が出てテストが落ちる。角括弧で引くと
## 門を外した瞬間に実行時エラーになり、GDScriptは関数を中断して既定値("")を
## 返す＝門があるときと**同じ結果**になり、門がテストに映らない枝になる。
static func opponent_margin_line(enemy_tracks: Array) -> String:
	var theirs := totals(enemy_tracks)
	if theirs.is_empty():
		return ""
	return TranslationServer.translate("GAMEOVER_MARGIN").format([
		_fmt(float(theirs.get("final", 0.0))), percent(theirs),
	])


## 表示用の数値。RpsLossText と同じ小数1桁固定にして、リザルトの縦並びで桁が揃う。
static func _fmt(value: float) -> String:
	return "%.1f" % maxf(value, 0.0)
