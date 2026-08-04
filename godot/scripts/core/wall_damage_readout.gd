class_name WallDamageReadout
extends RefCounted

## 壁・柱にぶつかった瞬間に「いま何回転ぶん持っていかれたか」をその場へ出す、
## 浮かぶ数字の純粋な計算部分。
##
## 動機(コールドプレイ 2026-08-04): **壁がこのゲームで一番人を殺している機構なのに、
## 戦闘中はそれが一度も言葉になっていない**。決戦3挑戦の自分の内訳は
## 削り22.4/壁16.6(9回)、削り23.1/壁15.8(7回)、削り26.3/壁10.5(6回)——
## rps40のうち3〜4割が壁である。敵側はもっと極端で、段3の2体戦は
## **1回の壁で23.4rpsのうち9.7(41%)** が飛んでいた(だから乱戦は1.2秒で終わる)。
## それでも再生中に見えるのは、HPバーが減ることと控えめな衝撃波だけで、
## 「いま減ったぶんは壁のせいだ」という結び付けがどこにも無い。
## 決着後の内訳(RpsLossText)には出るが、それは終わった後の答え合わせで、
## **戦っている間に学べる形になっていない**。前サイクルは同じことを
## 「壁対策の唯一の札(RAGE_REFLECTION)を3回提示されて3回とも見送った。
## カード文は正しいのに戦闘中にその実感が無いので文を信じられない」と記録している。
##
## そこで、痛い壁ヒットだけその場に喪失量を出す。擦り接触まで出すと画面が
## 数字で埋まって逆に読めなくなるので、**ゲージに対する割合**で足切りする
## (絶対量で切ると、rps15の序盤とrps40の終盤で「痛い」の意味が変わる)。
##
## Nodeにもシーンにも依存しない。大きさ(痛さ→サイズ)はスパークと同じ
## SparkScale を使い回すので、ここには持たない——対応をチャンネルごとに
## 変えると読みが壊れる。


## 出すか出さないか。gauge_rps はその体の初期rps(ゲージの満タン)。
##
## - gauge_rps <= 0 (ゲージが取れない)は出さない。割合が決められないため。
## - min_share <= 0 は足切り無効＝正の喪失を全部出す(Inspectorからの一時無効化)。
## - 持ち主不明(旧dictの結果)は出さない。色を分けられないので、
##   「誰の喪失か分からない数字」を土俵に置くことになる。
static func should_show(strength: float, gauge_rps: float, min_share: float, owner: int) -> bool:
	if owner == BattleResult.Impact.OWNER_UNKNOWN:
		return false
	if strength <= 0.0 or gauge_rps <= 0.0:
		return false
	if min_share <= 0.0:
		return true
	return strength >= gauge_rps * min_share


## 表示文字列。減った量なので必ずマイナス符号を付ける。小数1桁は
## 決着後の内訳(RpsLossText)と同じ粒度——同じ量を2箇所で違う丸め方で
## 見せると、足し合わせが合わないように見える。
static func text(strength: float) -> String:
	return "-%.1f" % maxf(strength, 0.0)


## 数字の色。喪失を負った側のコマの色をそのまま使う(自分=水色・敵=赤)。
## HPバーもコマも同じ色分けなので、「青い-9.0は自分が9.0失った」と
## 一目で読める。壁色(マゼンタ)で統一する案もあるが、それだと乱戦で
## 誰の喪失か分からなくなる。
static func color(owner: int, player_color: Color, enemy_color: Color) -> Color:
	return player_color if owner == BattleResult.Impact.OWNER_PLAYER else enemy_color


## 出てから消えるまでの進み具合(0〜1)。duration <= 0 は即消滅(1.0)。
static func progress(elapsed: float, duration: float) -> float:
	if duration <= 0.0:
		return 1.0
	return clampf(elapsed / duration, 0.0, 1.0)


## 不透明度。hold_share のあいだは満タンのまま読ませ、そこから線形に抜く。
## 出た瞬間から薄れ始めると、一番読ませたい激突の数字が一番読めない。
##
## hold区間で1.0に張り付くのは下のクランプが担う(p<hold では式が1を超える)ので、
## 早期returnは置かない——同じことを2箇所に書くと、消しても何も変わらない枝＝
## テストに映らないコードになる(サボタージュで実際にそうなった)。
## hold >= 1.0 だけは分母が0以下になるので別に畳む。
static func alpha_at(elapsed: float, duration: float, hold_share: float) -> float:
	var p := progress(elapsed, duration)
	var hold := clampf(hold_share, 0.0, 1.0)
	if hold >= 1.0:
		return 1.0 if p < 1.0 else 0.0
	return clampf(1.0 - (p - hold) / (1.0 - hold), 0.0, 1.0)


## 上へ逃げる距離(アリーナのユニット)。速く出て緩く止まる(1-(1-p)^2)ので、
## 出た瞬間にコマから離れて重ならない。
static func rise_at(elapsed: float, duration: float, rise: float) -> float:
	var p := progress(elapsed, duration)
	var inv := 1.0 - p
	return rise * (1.0 - inv * inv)
