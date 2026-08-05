class_name PlaybackPacing
extends RefCounted

## 再生の早送りの計算。Nodeにもシーンにも依存しない純粋な静的関数だけを置く
## (FinishFocus/TelegraphWobbleと同じ流儀)。手動(speed_at)と自動(idle_speed_at)の
## 2本立てで、Battle側はその速い方を採る。
##
## 戦いは発射時に全部決まっていて、再生は観るだけ。長い戦闘(実測で17〜20秒)の
## 後半は毎秒ほぼ同強度の微衝突が決着直前まで続く消耗戦で、間延びする。
## 手動の早送りはそこを縮めるために入った。
##
## 自動判定を退けた経緯もここに書いてあった——「最後のイベント以降」は実測で
## 0.2〜1.0秒しかなく無力で、「敗者のrpsが低い」基準は残り数%の接戦の
## クライマックスまで早送りしてしまう、と。**この2つはどちらも後ろ向きの基準で、
## 前向きの「次に噛み合うまで」は測っていなかった**(2026-08-05に撤回。詳細は
## idle_speed_at)。
##
## 勝敗・軌跡(BattleResult)には一切影響しない(再生時刻の進み方だけが変わる)。


## 再生速度(1.0=等速)。押している間だけmultiplier倍。
##
## 決着ズーム演出(FinishFocus)の最中だけは押していても等速へ戻す:
## 演出はEngine.time_scaleのスローで見せるので、倍速と重なると相殺されて
## 一番熱い瞬間が流れてしまう。演出なし(decisive_time<0)なら常に押した通り。
static func speed_at(
	held: bool, multiplier: float, t: float, decisive_time: float, lead: float
) -> float:
	if not held:
		return 1.0
	if FinishFocus.strength_at(t, decisive_time, lead) > 0.0:
		return 1.0
	return maxf(multiplier, 1.0)


## 時刻tを挟む「コマ同士の接触」の区間 [直前, 次] をVector2で返す。
## timesは昇順の接触時刻(BattleResult.impactsの時刻)。直前が無ければ0.0(発射の
## 瞬間)、次が無ければfinish(決着)。接触が1つも無い戦いは常に [0.0, finish] で、
## それは「戦闘まるごとが空転」という事実そのものになる。
##
## 壁への衝突は境界に数えない。プレイヤーが待っているのは相手と噛み合う瞬間で、
## 壁の跳ね返りは倍速でも読める(スパークは_emit_due_wall_impactsがwhileで
## 出すので、圧縮されても1つも落ちない)。壁を境界に数えると、空転中も1〜2秒おきに
## 壁が入るせいでこの早送りはほぼ発動しなくなる。
static func contact_span(times: PackedFloat32Array, t: float, finish: float) -> Vector2:
	var prev := 0.0
	var next := maxf(finish, 0.0)
	for x in times:
		if x <= t:
			prev = maxf(prev, x)
		else:
			# 昇順なので、最初に見つかった未来の接触が最も近い。
			next = minf(next, x)
			break
	return Vector2(prev, maxf(next, prev))


## 接触の無い区間を自動で早送りする速度(1.0=等速)。
##
## 戦いは発射時に全部決まっているので、次にコマ同士が触れる時刻は**再生を始める前から
## 分かっている**。この関数はそれだけを見る。上で退けた自動判定は「最後のイベント
## 以降の経過」と「敗者のrpsが低い」——どちらも**後ろ向き**の基準で、前者は無力、
## 後者はクライマックスを飛ばした。前向きの「次の接触までの残り」はその2つとは
## 別物で、**定義から接触の瞬間を飛ばせない**(接触時刻でちょうど等速に戻る)。
##
## 直したいのは後半の消耗戦ではなく**初弾を外したときの空白**。実測(2026-08-05、
## measure_dead_time.gd)では素の自機で出現点を狙うと、Lv1の26.5%の戦闘が初接触まで
## 3秒以上かかり、p90は15.07秒だった。発射後に入力が無いゲームで、外した罰が
## 「15秒なにも起きない画面を見る」になっていた。
##
## 形: 直前の接触から lead_in 秒は等速(命中の余韻と発射直後の助走を潰さない)、
## そこから ramp 秒かけて multiplier まで上げ、次の接触へ向けて ramp 秒かけて
## 等速へ戻す。短い区間は山が立つ前に下り坂へ入るので自動的にほとんど加速しない
## ——「何秒から空転とみなすか」の閾値を別に置かなくてよい(調整点が1つ減る)。
##
## 決着ズーム演出の最中は手動と同じく等速へ戻す。
static func idle_speed_at(
	t: float,
	prev_contact: float,
	next_contact: float,
	multiplier: float,
	lead_in: float,
	ramp: float,
	decisive_time: float,
	lead: float
) -> float:
	if multiplier <= 1.0 or ramp <= 0.0:
		return 1.0
	if FinishFocus.strength_at(t, decisive_time, lead) > 0.0:
		return 1.0
	# 直前の接触からの経過(余韻ぶんを引く)と、次の接触までの残り。小さい方が
	# 「等速に戻すべき理由の強さ」で、両端でちょうど0になる。
	var since := t - (prev_contact + maxf(lead_in, 0.0))
	var until := next_contact - t
	var gap := minf(since, until)
	# 両端の外(gapが負)はclampfの下限0が等速へ畳む。ここに `if gap <= 0.0: return 1.0`
	# を書きたくなるが、それはclampfと同じ答えを返す**テストに映らない枝**になる
	# (サボタージュで外しても1件も落ちなかった)。下限0そのものは検査してある。
	return lerpf(1.0, multiplier, clampf(gap / ramp, 0.0, 1.0))
