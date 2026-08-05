extends RefCounted

## playback_pacing.gd(早送り)のテスト。純粋関数と配線を検証する。
##
## 手動(speed_at)で大事なのは (1) 押していないときは必ず等速、(2) 決着ズーム
## 演出の最中は押していても等速(スロー演出と倍速が相殺して一番熱い瞬間が流れる
## 事故の防止)、(3) 無効化(multiplier=1)が効くこと、(4) Battle側の配線。
##
## 自動(idle_speed_at)は2026-08-05に足した。**「押していなければ必ず等速」という
## 画面全体の約束はここで撤回されている**——手動の関数は今も等速を返すが、Battleは
## 自動と速い方を採るので、押さなくても速くなる区間がある。代わりに守るべき約束が
## 「**接触の瞬間は必ず等速**」に置き換わったので、そちらを名指しで検査する:
## 実リゾルバの結果に対して、記録された全接触時刻で速度が1.0であること。


func run(check: Callable) -> void:
	_test_not_held_is_realtime(check)
	_test_held_is_fast(check)
	_test_climax_guard(check)
	_test_disabled(check)
	_test_battle_wires_pacing(check)
	_test_fast_forward_string(check)
	_test_contact_span(check)
	_test_idle_contacts_stay_realtime(check)
	_test_idle_long_gap_speeds_up(check)
	_test_idle_short_gap_barely_moves(check)
	_test_idle_bounds_and_continuity(check)
	_test_idle_climax_guard(check)
	_test_idle_disabled(check)
	_test_idle_on_real_battle(check)


## 押していなければ、speed_at自体はどんな時刻・演出状態でも等速1.0を返す
## (自動早送りは別関数で、Battleが速い方を採る)。
func _test_not_held_is_realtime(check: Callable) -> void:
	var worst := 0.0
	for i in 100:
		var t := i * 0.2
		worst = maxf(worst, PlaybackPacing.speed_at(false, 3.0, t, 8.0, 0.28))
		worst = maxf(worst, PlaybackPacing.speed_at(false, 3.0, t, -1.0, 0.28))
	check.call(is_equal_approx(worst, 1.0), "速度: 押していなければ常に等速 (最大 %.2f)" % worst)


## 押している間はmultiplier倍。演出なし(decisive=-1)なら決着までずっと効く。
func _test_held_is_fast(check: Callable) -> void:
	check.call(
		is_equal_approx(PlaybackPacing.speed_at(true, 3.0, 5.0, -1.0, 0.28), 3.0),
		"速度: 押していれば倍速(演出なしの戦い)"
	)
	check.call(
		is_equal_approx(PlaybackPacing.speed_at(true, 3.0, 2.0, 10.0, 0.28), 3.0),
		"速度: 決着演出のずっと手前では押せば倍速"
	)
	# 1.0未満の倍率を渡されても遅回しにはしない(早送りの道具であって巻き戻しではない)。
	check.call(
		PlaybackPacing.speed_at(true, 0.5, 5.0, -1.0, 0.28) >= 1.0,
		"速度: 倍率が1未満でも等速を下回らない"
	)


## 決着ズーム演出(lead区間〜決着後)の間は、押していても等速へ戻す。
func _test_climax_guard(check: Callable) -> void:
	var dt := 8.0
	var lead := 0.28
	check.call(
		is_equal_approx(PlaybackPacing.speed_at(true, 3.0, dt - lead * 0.5, dt, lead), 1.0),
		"演出ガード: lead区間内は押していても等速"
	)
	check.call(
		is_equal_approx(PlaybackPacing.speed_at(true, 3.0, dt, dt, lead), 1.0),
		"演出ガード: 決着時刻ちょうども等速"
	)
	check.call(
		is_equal_approx(PlaybackPacing.speed_at(true, 3.0, dt + 0.3, dt, lead), 1.0),
		"演出ガード: 決着後(強さ1に張り付く区間)も等速"
	)
	check.call(
		is_equal_approx(PlaybackPacing.speed_at(true, 3.0, dt - lead - 0.01, dt, lead), 3.0),
		"演出ガード: lead開始の手前までは倍速のまま"
	)


## multiplier=1.0で無効(押しても等速)。Inspectorから早送りを切れること。
func _test_disabled(check: Callable) -> void:
	check.call(
		is_equal_approx(PlaybackPacing.speed_at(true, 1.0, 5.0, -1.0, 0.28), 1.0),
		"速度: multiplier=1.0は押しても等速"
	)


## Battle.gdが早送りをPlaybackPacingで配線している(退行検知)。
func _test_battle_wires_pacing(check: Callable) -> void:
	var source := FileAccess.get_file_as_string("res://scenes/battle/Battle.gd")
	check.call(
		source.contains("PlaybackPacing.speed_at("),
		"Battle.gdが再生速度をPlaybackPacingから得る"
	)
	check.call(
		source.contains("delta * pace"),
		"Battle.gdが再生時刻の進みに速度を掛ける"
	)
	check.call(
		source.contains("_fast_forward_held()"),
		"Battle.gdが押下状態を速度計算へ渡す"
	)
	check.call(
		source.contains("finish_zoom_lead\n\t)") or source.contains("finish_zoom_lead)"),
		"Battle.gdが決着演出の窓(lead)を速度計算へ渡す(演出ガードの配線)"
	)
	check.call(
		source.contains("BATTLE_FAST_FORWARD"),
		"Battle.gdが早送り中の表示を出す"
	)
	check.call(
		source.contains("PlaybackPacing.idle_speed_at("),
		"Battle.gdが自動早送りをPlaybackPacingから得る"
	)
	check.call(
		source.contains("PlaybackPacing.contact_span("),
		"Battle.gdが次の接触の時刻をcontact_spanで引く"
	)
	check.call(
		source.contains("var pace := maxf("),
		"Battle.gdが手動と自動の速い方を採る"
	)
	check.call(
		source.contains("for imp in _result.impacts:"),
		"Battle.gdが接触時刻の一覧を軌跡から作る"
	)
	check.call(
		source.contains("BATTLE_AUTO_FAST_FORWARD"),
		"Battle.gdが自動早送りを別の文言で見せる"
	)


## 早送り表示の訳が両localeにあり、記号▶のグリフを既定フォントが持つ(豆腐防止)。
func _test_fast_forward_string(check: Callable) -> void:
	var saved_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var en := TranslationServer.translate("BATTLE_FAST_FORWARD")
	check.call(en != "BATTLE_FAST_FORWARD", "en: BATTLE_FAST_FORWARDの訳がある (%s)" % en)
	TranslationServer.set_locale("ja")
	var ja := TranslationServer.translate("BATTLE_FAST_FORWARD")
	check.call(ja != "BATTLE_FAST_FORWARD", "ja: BATTLE_FAST_FORWARDの訳がある (%s)" % ja)
	check.call(ja.contains("早送り"), "ja: 早送りだと分かる (%s)" % ja)
	TranslationServer.set_locale(saved_locale)

	var font_path: String = ProjectSettings.get_setting("gui/theme/custom_font", "")
	var font := load(font_path) as Font
	if font != null and en.contains("▶"):
		check.call(font.has_char("▶".unicode_at(0)), "既定フォントが▶のグリフを持つ")

	# 自動早送りの文言。押していないのに速くなる以上、理由が読めないと不具合に見える。
	TranslationServer.set_locale("en")
	var auto_en := TranslationServer.translate("BATTLE_AUTO_FAST_FORWARD")
	check.call(
		auto_en != "BATTLE_AUTO_FAST_FORWARD", "en: BATTLE_AUTO_FAST_FORWARDの訳がある (%s)" % auto_en
	)
	TranslationServer.set_locale("ja")
	var auto_ja := TranslationServer.translate("BATTLE_AUTO_FAST_FORWARD")
	check.call(
		auto_ja != "BATTLE_AUTO_FAST_FORWARD", "ja: BATTLE_AUTO_FAST_FORWARDの訳がある (%s)" % auto_ja
	)
	check.call(auto_ja != ja, "ja: 自動早送りの文言が手動と区別できる (%s / %s)" % [auto_ja, ja])
	TranslationServer.set_locale(saved_locale)


const IDLE_MULT := 3.0
const IDLE_LEAD_IN := 0.8
const IDLE_RAMP := 2.4


## 演出ガード無し(decisive=-1)の既定パラメータで自動速度を引く。
func _idle(t: float, prev_contact: float, next_contact: float) -> float:
	return PlaybackPacing.idle_speed_at(
		t, prev_contact, next_contact, IDLE_MULT, IDLE_LEAD_IN, IDLE_RAMP, -1.0, 0.28
	)


## contact_span: 時刻を挟む接触の組。端は発射(0.0)と決着(finish)で閉じる。
func _test_contact_span(check: Callable) -> void:
	var times := PackedFloat32Array([2.0, 5.0, 9.0])
	check.call(
		PlaybackPacing.contact_span(times, 3.0, 12.0).is_equal_approx(Vector2(2.0, 5.0)),
		"接触区間: 接触の間では前後の接触で挟む"
	)
	check.call(
		PlaybackPacing.contact_span(times, 0.5, 12.0).is_equal_approx(Vector2(0.0, 2.0)),
		"接触区間: 初接触より前は発射(0.0)から初接触まで"
	)
	check.call(
		PlaybackPacing.contact_span(times, 10.0, 12.0).is_equal_approx(Vector2(9.0, 12.0)),
		"接触区間: 最後の接触より後は決着まで"
	)
	check.call(
		PlaybackPacing.contact_span(PackedFloat32Array(), 4.0, 12.0).is_equal_approx(
			Vector2(0.0, 12.0)
		),
		"接触区間: 接触が1つも無い戦いは戦闘まるごとが1区間"
	)
	# 接触時刻ちょうどは「直前」に数える(そこで等速へ戻り、そこから余韻が始まる)。
	check.call(
		PlaybackPacing.contact_span(times, 5.0, 12.0).is_equal_approx(Vector2(5.0, 9.0)),
		"接触区間: 接触時刻ちょうどはその接触を直前として扱う"
	)


## 一番大事な約束: 接触の瞬間とその直後(余韻)は等速。ここを飛ばしたら
## 「早送りが試合を食った」ことになる。
func _test_idle_contacts_stay_realtime(check: Callable) -> void:
	check.call(is_equal_approx(_idle(20.0, 2.0, 20.0), 1.0), "自動: 次の接触の瞬間は等速")
	check.call(is_equal_approx(_idle(2.0, 2.0, 20.0), 1.0), "自動: 直前の接触の瞬間は等速")
	check.call(
		is_equal_approx(_idle(2.0 + IDLE_LEAD_IN, 2.0, 20.0), 1.0),
		"自動: 命中の余韻(lead_in)の終わりまで等速"
	)
	# 接触の直前は「ちょうど等速」まで戻り切っていること(1フレーム手前で見る)。
	check.call(_idle(20.0 - 1.0 / 60.0, 2.0, 20.0) < 1.05, "自動: 接触の1フレーム前にはほぼ等速")


## 長い空転(初弾を外した15秒)は上限倍率まで上がる。ここが上がらないと今回の
## 改善そのものが効いていない。
func _test_idle_long_gap_speeds_up(check: Callable) -> void:
	var peak := 0.0
	for i in 900:
		peak = maxf(peak, _idle(i * 15.0 / 900.0, 0.0, 15.0))
	check.call(is_equal_approx(peak, IDLE_MULT), "自動: 15秒の空転は上限倍率まで上がる (%.2f)" % peak)


## 短い区間(噛み合っている最中の0.5秒)はほとんど加速しない。閾値を別に置かず、
## ramp の幾何だけでそうなることを固定する。
func _test_idle_short_gap_barely_moves(check: Callable) -> void:
	var peak := 0.0
	for i in 200:
		peak = maxf(peak, _idle(5.0 + i * 0.5 / 200.0, 5.0, 5.5))
	check.call(peak <= 1.05, "自動: 0.5秒の間隔はほぼ等速のまま (%.2f)" % peak)
	var peak2 := 0.0
	for i in 200:
		peak2 = maxf(peak2, _idle(5.0 + i * 2.0 / 200.0, 5.0, 7.0))
	check.call(peak2 < 2.0, "自動: 2秒の間隔は控えめにしか上がらない (%.2f)" % peak2)


## 速度は常に [1.0, multiplier] に収まり、1フレームで飛ばない(段差はワープに見える)。
func _test_idle_bounds_and_continuity(check: Callable) -> void:
	var lo := INF
	var hi := 0.0
	var jump := 0.0
	var step := 1.0 / 60.0
	var prev := _idle(0.0, 0.0, 15.0)
	for i in range(1, 900):
		var s := _idle(i * step, 0.0, 15.0)
		lo = minf(lo, s)
		hi = maxf(hi, s)
		jump = maxf(jump, absf(s - prev))
		prev = s
	check.call(lo >= 1.0 - 1e-5, "自動: 等速を下回らない (最小 %.3f)" % lo)
	check.call(hi <= IDLE_MULT + 1e-5, "自動: 上限倍率を超えない (最大 %.3f)" % hi)
	# 1フレームぶんの変化は (multiplier-1)/ramp * step = 2/2.4/60 ≈ 0.014 が理論値。
	check.call(jump <= 0.02, "自動: 1フレームで速度が飛ばない (最大 %.3f)" % jump)


## 決着ズーム演出の最中は自動でも等速へ戻す(手動と同じ理由)。
func _test_idle_climax_guard(check: Callable) -> void:
	var dt := 12.0
	var lead := 0.28
	check.call(
		is_equal_approx(
			PlaybackPacing.idle_speed_at(
				dt - lead * 0.5, 0.0, 20.0, IDLE_MULT, IDLE_LEAD_IN, IDLE_RAMP, dt, lead
			),
			1.0
		),
		"自動: 決着演出のlead区間内は等速"
	)


## multiplier=1.0(またはramp=0)で自動早送りを完全に切れる。
func _test_idle_disabled(check: Callable) -> void:
	var worst := 0.0
	for i in 300:
		var t := i * 0.05
		worst = maxf(
			worst,
			PlaybackPacing.idle_speed_at(t, 0.0, 15.0, 1.0, IDLE_LEAD_IN, IDLE_RAMP, -1.0, 0.28)
		)
		worst = maxf(
			worst,
			PlaybackPacing.idle_speed_at(t, 0.0, 15.0, IDLE_MULT, IDLE_LEAD_IN, 0.0, -1.0, 0.28)
		)
	check.call(is_equal_approx(worst, 1.0), "自動: multiplier=1.0 / ramp=0 で無効 (最大 %.2f)" % worst)


## 実リゾルバの結果に対する検査。Battleと同じ手順(接触時刻を集める→毎フレーム
## contact_span→idle_speed_at)で再生を回し、
##   (a) 記録された全ての接触時刻で速度が1.0(接触は必ず等速で見せる)
##   (b) それでも全体の再生時間は縮む(この改善が効いている)
## を確かめる。純粋関数の単体検査だけだと、Battleの引き方(壁を混ぜる等)を
## 間違えても気付けない。
func _test_idle_on_real_battle(check: Callable) -> void:
	var request := BattleRequest.new()
	var ps := SpinnerStats.new()
	ps.rps = 15.0
	var es := SpinnerStats.new()
	es.rps = 15.0
	# わざと外す発射: 相手の反対側へ、すれ違う向きに撃つ。噛み合うまで間が空く。
	request.player = BattleRequest.Launch.new(ps, Vector2(1.5, 1.5), Vector2(0.5, 8.0))
	request.enemies = [BattleRequest.Launch.new(es, Vector2(8.5, 8.5), Vector2(8.0, 0.5))]
	var result := BattleResolver.resolve(request)

	var times := PackedFloat32Array()
	for imp in result.impacts:
		times.append(imp.time)

	var worst_at_contact := 0.0
	for imp in result.impacts:
		var span := PlaybackPacing.contact_span(times, imp.time, result.finish_time)
		worst_at_contact = maxf(
			worst_at_contact,
			PlaybackPacing.idle_speed_at(
				imp.time, span.x, span.y, IDLE_MULT, IDLE_LEAD_IN, IDLE_RAMP, -1.0, 0.28
			)
		)
	check.call(
		result.impacts.size() > 0,
		"実戦: 接触が起きる配置になっている (%d回)" % result.impacts.size()
	)
	check.call(
		is_equal_approx(worst_at_contact, 1.0),
		"実戦: 記録された全ての接触時刻で等速 (最大 %.2f)" % worst_at_contact
	)

	# 再生を回して、かかる秒数を比べる。
	var step := 1.0 / 60.0
	var frames_plain := 0
	var t := 0.0
	while t < result.finish_time and frames_plain < 100000:
		t += step
		frames_plain += 1
	var frames_auto := 0
	t = 0.0
	while t < result.finish_time and frames_auto < 100000:
		var span := PlaybackPacing.contact_span(times, t, result.finish_time)
		t += step * PlaybackPacing.idle_speed_at(
			t, span.x, span.y, IDLE_MULT, IDLE_LEAD_IN, IDLE_RAMP, -1.0, 0.28
		)
		frames_auto += 1
	check.call(
		frames_auto < frames_plain,
		"実戦: 自動早送りで再生時間が縮む (%.2f秒 → %.2f秒)" % [
			frames_plain * step, frames_auto * step
		]
	)
