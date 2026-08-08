extends RefCounted

## 報酬カードの「取るとどうなるか」見積もり(scripts/ui/part_preview.gd)のテスト。
##
## 大事なのは (1) 硬さ・寿命・打たれ強さが物理と同じ式であること(表示だけ別式だと
## 嘘になる)、(2) プレビューが元のステータスを壊さないこと、(3) 変化の向き(better)が
## 実際の増減と一致すること、(4) 硬さ・打たれ強さの行は変化しない札でも必ず出ること、
## (5) コマの性能を変えない札(残機・ゴースト)でも見積もりが空にならないこと、
## (6) RewardScreen/Mainの配線と訳の存在。
##
## (8) **3行目が壁の軸であること**。硬さ・打たれ強さはどちらも接触の量なので、
## 壁へ効く唯一の札(RAGE_REFLECTION)が2行とも「変化なし」で出ていた——効果文が
## 「終盤は壁での喪失が削りに並ぶ」と書いている札が、数字では何も起きない札に
## 見えていた。壁はラン合計で削りを上回る(コールドプレイ seed=4821 で
## 壁61.1 対 削り52.5)ので、壁の札と接触の札が**別々の行を動かす**ことを見る。
##
## (9) **攻めの行が素のコマ基準の倍率であること**。生の攻め力は基準の相手の硬さに
## 反比例するので、ラン中は自分が強くなるほど数字が縮んでいた(コールドプレイ
## seed=4821 の実測で 13.64 → 1.02)。守りの3行が伸びる隣でこの行だけが逆を向くと、
## 「自分の攻めは育っているのか」に画面のどこも答えられない。素のコマで割った倍率は
## 同じ実測で 1.00 → 8.56 と伸びる。1画面の中でのカード同士の比較は変わらない
## (分母が3枚に共通なので順位が保たれる)ことも併せて見る。
##
## (7) **2行目が寿命でないこと**。寿命は自然減衰の軸で、実測では決着にほぼ効かない
## (敵の敗因の自然減衰は全レベル0.0%)のに、カード間で最も大きく動く行だった。
## 結果として最下位の札(FULL_STEAM_AHEAD)が最も得に見え、1位の札(GIANT_GROWTH)が
## 損に見えていた——その逆立ちを戻さないための検査。経緯は part_preview.gd の
## 冒頭コメントと docs/evolve/journal.md の当該サイクル。
##
## サボタージュ検証(CLAUDE.md「壊した実装を落とせて初めて完成」)は
## docs/evolve/journal.md の当該サイクルに記録。


func run(check: Callable) -> void:
	_test_derived_matches_physics(check)
	_test_preview_does_not_mutate(check)
	_test_growth_shows_both_gains(check)
	_test_second_row_tracks_drain_not_decay(check)
	_test_wall_row_tracks_wall_loss(check)
	_test_attack_row_matches_physics(check)
	_test_attack_row_needs_an_opponent(check)
	_test_attack_row_is_the_only_home_of_the_offence_cards(check)
	_test_attack_index_is_a_multiple_of_the_stock_spinner(check)
	_test_attack_row_reads_as_build_growth(check)
	_test_knockback_row_matches_physics(check)
	_test_knockback_row_is_the_offence_the_attack_row_misses(check)
	_test_knockback_index_is_a_multiple_of_the_stock_spinner(check)
	_test_attack_basis_names_the_reference_opponent(check)
	_test_rows_always_show_the_deciding_pair(check)
	_test_decay_note_covers_the_axis_no_row_reads(check)
	_test_non_stat_parts_still_show_something(check)
	_test_format_hides_unchanged(check)
	_test_screen_wiring(check)
	_test_translations(check)


func _player() -> SpinnerStats:
	return SpinnerStats.default_player()


## 攻めの2行の基準にする相手1体。硬さ(質量×半径²)を指定した値ちょうどにして返す。
## 相手をスカラーではなく1体として渡すようになった(2026-08-08。弾きが質量比も
## 読むため)ので、テストも1体を組み立てる。反発は敵ロスターと同じ 1.0。
func _opponent(target_toughness: float, mass: float = 2.0) -> SpinnerStats:
	var o := SpinnerStats.new()
	o.mass = mass
	o.radius = sqrt(target_toughness / mass)
	o.restitution = 1.0
	return o


## 硬さ・寿命は「表示用の別式」ではなく物理そのもの。
## 硬さ: 1衝突の削りが 質量×半径² に反比例する(SpinnerPhysics.spin_drain)。
## 寿命: 自然減衰が 半径×spin_decay に比例する(SpinnerPhysics.natural_spin_decay)。
func _test_derived_matches_physics(check: Callable) -> void:
	var stats := _player()
	stats.mass = 2.0
	stats.radius = 0.8
	stats.rps = 24.0
	stats.spin_decay = 0.8

	# 硬さ: 素の削りは violence*(相手質量*相手速さ)/硬さ。硬さを2倍にすれば削りは半分。
	var drain_1 := SpinnerPhysics.spin_drain(1.0, 5.0, stats.mass, stats.radius, 0.16)
	var drain_2 := SpinnerPhysics.spin_drain(1.0, 5.0, stats.mass * 2.0, stats.radius, 0.16)
	check.call(
		is_equal_approx(PartPreview.toughness(stats), 2.0 * 0.8 * 0.8),
		"硬さ = 質量×半径² (%.4f)" % PartPreview.toughness(stats)
	)
	check.call(
		is_equal_approx(drain_1 / drain_2, 2.0),
		"硬さ2倍で素の削りが半分 (比 %.4f)" % (drain_1 / drain_2)
	)

	# 寿命: rpsを1秒あたりの自然減衰量で割った秒数。
	var per_second := SpinnerPhysics.natural_spin_decay(stats.radius, stats.spin_decay, 1.0)
	check.call(
		is_equal_approx(PartPreview.lifetime(stats), stats.rps / per_second),
		"寿命 = rps ÷ 1秒あたりの自然減衰 (%.2f秒)" % PartPreview.lifetime(stats)
	)

	# ゼロ除算でinf/nanを出さない(将来の札が半径や減衰を0にしても壊れない)。
	var degenerate := _player()
	degenerate.radius = 0.0
	check.call(
		PartPreview.lifetime(degenerate) == 0.0,
		"寿命: 半径0でもinf/nanにならない"
	)


## プレビューは見積もりなので、渡されたステータスを絶対に変えてはいけない。
## (ここが壊れると、報酬画面を開くだけでビルドが勝手に強くなる)
func _test_preview_does_not_mutate(check: Callable) -> void:
	var stats := _player()
	var before_mass := stats.mass
	var before_radius := stats.radius
	var before_rps := stats.rps
	for part in CustomPartCatalog.all():
		PartPreview.rows(stats, part, 3, 0.0)
	check.call(
		is_equal_approx(stats.mass, before_mass)
		and is_equal_approx(stats.radius, before_radius)
		and is_equal_approx(stats.rps, before_rps),
		"見積もりは元のステータスを変えない (質量 %.3f / 直径 %.3f / rps %.2f)" % [
			stats.mass, stats.radius, stats.rps]
	)


## 巨大化(GROWTH)は硬さも打たれ強さも上がる、実測1位(measure_parts Lv3・3枚で
## +95.2pt)の札。効果テキストは「直径×1.25・質量×1.15・自然減衰が速まる」までしか
## 言わないので、**得の側が数字で出ること**が今回の眼目。
##
## 以前の2行目(寿命)では、この札だけが唯一「悪くなる側」を表示する札で、
## コールドプレイが2度とも見送る原因になっていた。
func _test_growth_shows_both_gains(check: Callable) -> void:
	var stats := _player()
	var growth := _find_effect(CustomPart.Effect.GROWTH)
	check.call(growth != null, "カタログに巨大化札がある")
	if growth == null:
		return
	var rows := PartPreview.rows(stats, growth, 3, 0.0)
	var tough := _row_of(rows, "STAT_TOUGHNESS")
	var endure := _row_of(rows, "STAT_ENDURANCE")
	check.call(tough["better"] == 1, "巨大化: 硬さは良くなる側 (%.2f→%.2f)" % [
		tough["before"], tough["after"]])
	check.call(endure["better"] == 1, "巨大化: 打たれ強さも良くなる側 (%.1f→%.1f)" % [
		endure["before"], endure["after"]])
	# 寿命の行はもう出さない。出すと「最も大きく動く行」が実測1位の札に
	# 唯一のマイナスを付ける状態へ戻る。
	check.call(
		_row_of(rows, "STAT_LIFETIME").is_empty(),
		"報酬カードに寿命の行を出さない(自然減衰は決着にほぼ効かない)"
	)
	# ただし代償は**注記として**出る。行に戻さないまま「巨大化は寿命を削る」を
	# 数字にするのが decay_note の役目(2026-08-07)。
	var growth_note := PartPreview.decay_note(stats, growth)
	check.call(
		not growth_note.is_empty() and growth_note["better"] == -1,
		"巨大化: 寿命が縮む注記が悪くなる側で出る (%s)" % growth_note.get("text", "なし")
	)

	# betterの符号は実際の増減と一致していること(全札・全行で確認する)。
	var mismatched := 0
	for part in CustomPartCatalog.all():
		for row in PartPreview.rows(stats, part, 3, 0.0):
			var delta: float = row["after"] - row["before"]
			var sign_of := 0
			if not is_equal_approx(row["before"], row["after"]):
				sign_of = 1 if delta > 0.0 else -1
			if row["better"] != sign_of:
				mismatched += 1
	check.call(mismatched == 0, "betterの符号が実際の増減と一致 (不一致 %d 件)" % mismatched)

	# カタログには現在「下がる行」を出す札が無いので、-1の枝は合成の値で押さえる
	# (将来デメリット札が入ったときに向きを取り違えないため)。
	var worse := PartPreview._row("STAT_ENDURANCE", 20.0, 12.0, 1)
	check.call(worse["better"] == -1, "下がる行は悪くなる側として出る (%d)" % worse["better"])


## 2行目が「削られる側」を測っていること。打たれ強さは
## **1接触で削られるrpsに何回耐えられるか**に比例していなければならない。
##
## 物理側(spin_drain × guarded_spin_drain)から耐久回数を実際に組み立て、
## 打たれ強さの比と一致することを見る。式を2箇所に書くと表示だけが嘘になるので、
## ここでは PartPreview を信用せず物理から作り直して突き合わせる。
func _test_second_row_tracks_drain_not_decay(check: Callable) -> void:
	var a := _player()
	var b := _player()
	b.mass = 2.4
	b.radius = 0.9
	b.rps = 21.0
	b.hit_guard = 0.34
	# 相手・速さ・violence は任意でよい(打たれ強さの定義から約分されるため、
	# ここで違う値を入れても比が変わらないことが主張そのもの)。
	var hits_a := _hits_survived(a, 3.1, 6.0, 0.16)
	var hits_b := _hits_survived(b, 3.1, 6.0, 0.16)
	var by_physics := hits_b / hits_a
	var by_preview := PartPreview.endurance(b) / PartPreview.endurance(a)
	check.call(
		is_equal_approx(by_physics, by_preview),
		"打たれ強さの比 = 耐えられる接触回数の比 (物理 %.4f / 表示 %.4f)" % [
			by_physics, by_preview]
	)
	# 相手も速さも変えて同じ比になる(＝相手を知らずに出してよい量である証拠)。
	var other := _hits_survived(b, 0.7, 12.0, 0.5) / _hits_survived(a, 0.7, 12.0, 0.5)
	check.call(
		is_equal_approx(other, by_preview),
		"打たれ強さの比は相手・速さ・violenceに依らない (%.4f / %.4f)" % [other, by_preview]
	)

	# 衝突軽減(SHOCK_ABSORBER)が効くこと。以前は硬さも寿命も凍っていて、
	# **見積もりが一言も語らない札**だった。
	var guarded := _player()
	guarded.hit_guard = 0.5
	check.call(
		PartPreview.endurance(guarded) > PartPreview.endurance(_player()) * 1.5,
		"衝突軽減0.5で打たれ強さが1.5倍超 (%.1f → %.1f)" % [
			PartPreview.endurance(_player()), PartPreview.endurance(guarded)]
	)
	var absorber := _find_effect(CustomPart.Effect.GUARD)
	check.call(absorber != null, "カタログに衝突軽減札がある")
	if absorber != null:
		var row := _row_of(PartPreview.rows(_player(), absorber, 3, 0.0), "STAT_ENDURANCE")
		check.call(
			row["better"] == 1,
			"衝突軽減札: 打たれ強さの行が伸びる側で出る (%.1f→%.1f)" % [
				row["before"], row["after"]]
		)

	# 勢い維持(MOMENTUM)は守りの3行(硬さ・打たれ強さ・壁強さ)をどれも動かさない。
	# 触るのは摩擦・自然減衰・与ダメ増強で、守りの軸を1本も持たないため。
	# 以前は寿命が2行目に居たせいで、measure_parts(Lv3・3枚)で最下位の札が
	# 「最も大きく得をする札」に見えていた。
	var momentum := _find_effect(CustomPart.Effect.MOMENTUM)
	check.call(momentum != null, "カタログに勢い維持札がある")
	if momentum != null:
		var rows := PartPreview.rows(_player(), momentum, 3, 0.0)
		check.call(
			_row_of(rows, "STAT_TOUGHNESS")["better"] == 0
			and _row_of(rows, "STAT_ENDURANCE")["better"] == 0,
			"勢い維持札: 硬さも打たれ強さも動かない(守りの軸を持たないため)"
		)
		# ただし**攻めの行は動く**。複合化(MOMENTUM_EDGE_STEP)で削りの軸を得たので、
		# 基準の相手を渡した画面では見積もりが必ず何かを語る——4行とも据え置きの
		# 「白紙の札」ではなくなったことがこの札の改修の要点(死に札 +0.4pt の一次証拠は
		# CustomPartCatalog.MOMENTUM_EDGE_STEP のコメント)。
		var attack_rows := PartPreview.rows(_player(), momentum, 3, 0.0, _opponent(1.5))
		var attack_row := _row_of(attack_rows, "STAT_ATTACK")
		check.call(
			attack_row["better"] == 1,
			"勢い維持札: 攻め力の行が伸びる側で出る (%.2f→%.2f)" % [
				attack_row["before"], attack_row["after"]]
		)

	# 低重心(GRIP)も同じ穴に落ちていた札。傾斜(slope_grip)は見積もりの4行が
	# どれも読まない軸なので、改修前は**4行が1桁まで据え置き**の白紙の札に見えた
	# (コールドプレイ2026-08-03・08-07・08-07夜と3サイクル連続で見送られている)。
	# 複合化(GRIP_HIT_GUARD_STEP)で削り軽減の軸を得たので、打たれ強さの行が動く。
	var grip := _find_effect(CustomPart.Effect.GRIP)
	check.call(grip != null, "カタログに低重心札がある")
	if grip != null:
		var grip_rows := PartPreview.rows(_player(), grip, 3, 0.0)
		var endurance_row := _row_of(grip_rows, "STAT_ENDURANCE")
		check.call(
			endurance_row["better"] == 1,
			"低重心札: 打たれ強さの行が伸びる側で出る (%.1f→%.1f)" % [
				endurance_row["before"], endurance_row["after"]]
		)

	# ゼロ除算でinf/nanを出さない(将来の札が軽減を1.0にしても壊れない)。
	var immune := _player()
	immune.hit_guard = 1.0
	check.call(
		is_finite(PartPreview.endurance(immune))
		and PartPreview.endurance(immune) > PartPreview.endurance(guarded),
		"打たれ強さ: 軽減1.0でもinf/nanにならない (%.1f)" % PartPreview.endurance(immune)
	)


## 3行目が「壁で削られる側」を測っていること。壁強さは
## **壁1回で削られるrpsに何回耐えられるか**に比例していなければならない。
##
## 打たれ強さ(接触)と同じく、物理側(absolute_wall_drain × (1−wall_keep))から
## 耐久回数を組み直して比を突き合わせる。表示だけ別式にすると嘘になる。
##
## 動機は part_preview.gd の冒頭コメント: 壁は喪失の半分以上(コールドプレイ
## seed=4821 でラン合計 壁61.1 対 削り52.5)なのに、壁へ効く唯一の札
## RAGE_REFLECTION が2行とも「変化なし」で出ていた。
func _test_wall_row_tracks_wall_loss(check: Callable) -> void:
	var a := _player()
	var b := _player()
	b.mass = 2.4
	b.radius = 0.9
	b.rps = 21.0
	b.wall_keep = 0.34
	# 進入速度と wall_violence は任意でよい(壁強さの定義から約分されるため、
	# ここで違う値を入れても比が変わらないことが主張そのもの)。
	var by_physics := _wall_hits_survived(b, 7.0, 0.35) / _wall_hits_survived(a, 7.0, 0.35)
	var by_preview := PartPreview.wall_endurance(b) / PartPreview.wall_endurance(a)
	check.call(
		is_equal_approx(by_physics, by_preview),
		"壁強さの比 = 耐えられる壁の回数の比 (物理 %.4f / 表示 %.4f)" % [by_physics, by_preview]
	)
	var other := _wall_hits_survived(b, 2.5, 0.9) / _wall_hits_survived(a, 2.5, 0.9)
	check.call(
		is_equal_approx(other, by_preview),
		"壁強さの比は進入速度・wall_violenceに依らない (%.4f / %.4f)" % [other, by_preview]
	)

	# 混ざるもう片方(比例の側)とも向きが食い違わないこと。effective_wall_damping は
	# wall_keep 単調増加＝1回の壁で残るrpsが増える。ここが逆を向いていると、
	# 壁強さの行は「支配的な側だけ正しい見積もり」ですらなくなる。
	var kept_more := SpinnerPhysics.effective_wall_damping(0.75, 0.34)
	var kept_less := SpinnerPhysics.effective_wall_damping(0.75, 0.0)
	check.call(
		kept_more > kept_less,
		"比例の側も壁での軽減で残りrpsが増える向き (%.4f > %.4f)" % [kept_more, kept_less]
	)

	# 壁の札(RAGE)と接触の札(GUARD)が**別々の行を動かす**こと。ここが眼目で、
	# 以前はRAGEが硬さ・打たれ強さの両方を凍らせたまま「何も起きない札」に見えていた。
	# 行が消えたサボタージュで「'better' が無い」のスクリプトエラーになると、関数が
	# そこで中断してこの先の検査が黙って飛ぶ。行の存在ごと1つのcheckで見る
	# (_better は行が無ければ 99 を返し、どの期待値とも一致しない)。
	var rage := _find_effect(CustomPart.Effect.RAGE)
	check.call(rage != null, "カタログに怒りの反射札がある")
	if rage != null:
		var rows := PartPreview.rows(_player(), rage, 3, 0.0)
		var wall_row := _row_of(rows, "STAT_WALL_ENDURANCE")
		check.call(
			_better(rows, "STAT_WALL_ENDURANCE") == 1,
			"怒りの反射: 壁強さの行が伸びる側で出る (%s)" % (
				"行が無い" if wall_row.is_empty()
				else "%.1f→%.1f" % [wall_row["before"], wall_row["after"]])
		)
		check.call(
			_better(rows, "STAT_ENDURANCE") == 0,
			"怒りの反射: 打たれ強さ(接触)は動かない＝2つの行が別の軸を測っている"
		)
	var absorber := _find_effect(CustomPart.Effect.GUARD)
	if absorber != null:
		var rows := PartPreview.rows(_player(), absorber, 3, 0.0)
		check.call(
			_better(rows, "STAT_WALL_ENDURANCE") == 0
			and _better(rows, "STAT_ENDURANCE") == 1,
			"衝突軽減: 打たれ強さだけが伸びて壁強さは動かない(壁には効かない札)"
		)

	# ゼロ除算でinf/nanを出さない(将来の札がwall_keepを1.0にしても壊れない)。
	var immune := _player()
	immune.wall_keep = 1.0
	check.call(
		is_finite(PartPreview.wall_endurance(immune))
		and PartPreview.wall_endurance(immune) > PartPreview.wall_endurance(_player()),
		"壁強さ: 軽減1.0でもinf/nanにならない (%.1f)" % PartPreview.wall_endurance(immune)
	)


## 壁1回で削られるrpsから逆算した「耐えられる壁の回数」。物理の関数だけで組む。
## 混合(wall_absolute_share)のうち支配的な絶対量の側を使う——BattleResolver の
## _wall_damaged_rps が absolute へ寄せている式そのもの。
func _wall_hits_survived(stats: SpinnerStats, normal_speed: float, violence: float) -> float:
	var drain := SpinnerPhysics.absolute_wall_drain(
		normal_speed, stats.mass, stats.radius, violence
	) * (1.0 - stats.wall_keep)
	return stats.rps / drain


## 1回の接触で削られるrpsから逆算した「耐えられる接触回数」。物理の関数だけで組む。
func _hits_survived(
	stats: SpinnerStats, foe_mass: float, foe_speed: float, violence: float
) -> float:
	var drain := SpinnerPhysics.guarded_spin_drain(
		SpinnerPhysics.spin_drain(foe_mass, foe_speed, stats.mass, stats.radius, violence),
		stats.hit_guard
	)
	return stats.rps / drain


## 硬さ・打たれ強さは「この札では伸びない」ことも情報なので、動かない札でも必ず出す。
## (行が出たり消えたりするとカードの高さも揺れる)
func _test_rows_always_show_the_deciding_pair(check: Callable) -> void:
	var stats := _player()
	var missing: Array[String] = []
	var stale: Array[String] = []
	for part in CustomPartCatalog.all():
		var rows := PartPreview.rows(stats, part, 3, 0.0)
		if (_row_of(rows, "STAT_TOUGHNESS").is_empty()
				or _row_of(rows, "STAT_ENDURANCE").is_empty()
				or _row_of(rows, "STAT_WALL_ENDURANCE").is_empty()):
			missing.append(part.title_key)
		if not _row_of(rows, "STAT_LIFETIME").is_empty():
			stale.append(part.title_key)
	check.call(
		missing.is_empty(),
		"全ての札で硬さ・打たれ強さ・壁強さの行が出る (欠け: %s)" % ", ".join(missing)
	)
	check.call(
		stale.is_empty(),
		"どの札にも寿命の行を出さない (残り: %s)" % ", ".join(stale)
	)

	# 攻めの札(EDGE)は硬さも打たれ強さも動かさない。それが見えることが選択の材料になる。
	var edge := _find_effect(CustomPart.Effect.EDGE)
	if edge != null:
		var rows := PartPreview.rows(stats, edge, 3, 0.0)
		check.call(
			_row_of(rows, "STAT_TOUGHNESS")["better"] == 0
			and _row_of(rows, "STAT_ENDURANCE")["better"] == 0,
			"シャープエッジ: 硬さも打たれ強さも動かない(変化なしとして出る)"
		)


## **自然減衰の注記(decay_note)**。4行が1本も読まない軸を補う小さな注記で、
## 行には戻さない(戻すと 2026-08-06 に外した「最も大きく動く行」が復活する)。
##
## 見るのは4つ:
##  (1) 出す条件が**減衰率(半径×回転減衰)の変化**であること。寿命の変化で出すと
##      回転札(EXTRA_WINDING / SPIN_ENGINE)にも付くが、rpsは打たれ強さ・壁強さの
##      2行が既に読んでいるので、3つ目の上向きは情報を増やさず回転札を過大に見せる。
##  (2) **両方向に出る**こと。巨大化の代償だけ出して勢い維持の得を出さないのは
##      片側だけの開示になる(コールドプレイ 2026-08-07夜 で取り違えたのは両方)。
##  (3) 表示する数字が `lifetime` そのものであること(2箇所に式を書くと表示だけ嘘になる)。
##  (4) 行の列は**一切増えていない**こと。
##
## 一次証拠は part_preview.gd の decay_note 冒頭コメント。
## サボタージュ検証は docs/evolve/journal.md の当該サイクル。
func _test_decay_note_covers_the_axis_no_row_reads(check: Callable) -> void:
	var stats := _player()

	# (1)(2) カタログ全体で、注記が出る札 = 減衰率が動く札 と一致する。
	var noted: Array[String] = []
	var rate_moved: Array[String] = []
	var mismatched: Array[String] = []
	for part in CustomPartCatalog.all():
		var after := PartPreview.preview_stats(stats, part)
		var moves_rate := (
			CustomPart.stat_moved(stats.radius, after.radius)
			or CustomPart.stat_moved(stats.spin_decay, after.spin_decay)
		)
		var note := PartPreview.decay_note(stats, part)
		if moves_rate:
			rate_moved.append(part.title_key)
		if not note.is_empty():
			noted.append(part.title_key)
		if moves_rate != (not note.is_empty()):
			mismatched.append(part.title_key)
	check.call(
		mismatched.is_empty(),
		"注記は減衰率が動く札にだけ出る (食い違い: %s)" % ", ".join(mismatched)
	)
	check.call(
		noted.size() >= 2,
		"注記が出る札が両方向ぶん存在する (%s)" % ", ".join(noted)
	)

	# 回転だけ動かす札(EXTRA_WINDING / SPIN_ENGINE)は寿命が伸びるのに注記を出さない
	# ——rpsは打たれ強さ・壁強さの2行が既に読んでいる軸だから。カードを名指しせず
	# 「rpsを上げるが減衰率は動かさない札」として全カタログから拾う。
	var spin_cards: Array[String] = []
	var leaked: Array[String] = []
	for part in CustomPartCatalog.all():
		var after := PartPreview.preview_stats(stats, part)
		if after.rps <= stats.rps:
			continue
		if CustomPart.stat_moved(stats.radius, after.radius) or CustomPart.stat_moved(stats.spin_decay, after.spin_decay):
			continue
		spin_cards.append(part.title_key)
		if PartPreview.lifetime(after) <= PartPreview.lifetime(stats):
			leaked.append("%s(寿命が伸びていない)" % part.title_key)
		elif not PartPreview.decay_note(stats, part).is_empty():
			leaked.append("%s(注記が出た)" % part.title_key)
	check.call(spin_cards.size() >= 2, "回転を上げる札が2枚以上ある (%s)" % ", ".join(spin_cards))
	check.call(
		leaked.is_empty(),
		"回転札は寿命が伸びるが注記は出ない (%s)" % ", ".join(leaked)
	)

	# (2) 勢い維持は**得の側**で出る。この札は4行では攻め力が少し動くだけで、
	# コールドプレイ 2026-08-07夜 の段7では寿命 28.9→38.0 を伸ばしながら
	# 「いちばん地味な札」に見えていた。
	var momentum := _find_effect(CustomPart.Effect.MOMENTUM)
	check.call(momentum != null, "カタログに勢い維持札がある")
	if momentum != null:
		var note := PartPreview.decay_note(stats, momentum)
		check.call(
			not note.is_empty() and note["better"] == 1,
			"勢い維持: 寿命が伸びる注記が良くなる側で出る (%s)" % note.get("text", "なし")
		)

		# **上限注記と物差しを共有していること**(CustomPart.stat_moved)。
		# 勢い維持を4枚積んだビルド(摩擦0.40・回転減衰0.41、どちらも下限0.40)では
		# capped_axes が「もう伸びない」と言う。ここだけ厳密一致で見ていると、
		# 同じカードが「回転減衰はすでに上限」と「寿命 76.7 → 78.6」を**同時に言う**
		# (下限クランプで 0.41→0.40 と1目盛だけ動くため。報酬画面で実測した)。
		# おまけに注記が2本になってカードが伸び、1280x720 で 721/720 と溢れていた。
		var stacked := _player()
		stacked.friction = 0.40
		stacked.spin_decay = 0.41
		check.call(
			momentum.capped_note(stacked) != "",
			"勢い維持4枚のビルドでは上限注記が出る (%s)" % momentum.capped_note(stacked)
		)
		check.call(
			PartPreview.decay_note(stacked, momentum).is_empty(),
			"上限に達した軸では減衰の注記を出さない(上限注記と同じ物差し) (%s)"
				% PartPreview.decay_note(stacked, momentum).get("text", "なし")
		)

	# (3) 注記の数字は lifetime そのもの。実UIと同じ桁(小数1桁)で両端が入る。
	var growth := _find_effect(CustomPart.Effect.GROWTH)
	check.call(growth != null, "カタログに巨大化札がある")
	if growth != null:
		var after_growth := PartPreview.preview_stats(stats, growth)
		var text: String = PartPreview.decay_note(stats, growth)["text"]
		check.call(
			String.num(PartPreview.lifetime(stats), 1) in text
			and String.num(PartPreview.lifetime(after_growth), 1) in text,
			"注記の数字が lifetime と一致する (%s / %.1f→%.1f)" % [
				text, PartPreview.lifetime(stats), PartPreview.lifetime(after_growth)]
		)
		check.call(
			not ("REWARD_DECAY_NOTE" in text),
			"注記が生の翻訳キーのままになっていない (%s)" % text
		)

		# 直径が上限のビルドでは減衰率が動かない=代償が無いので注記も出ない
		# (「もう直径は伸びない」は capped_note の側が言う)。
		var maxed := _player()
		maxed.radius = 1.05
		check.call(
			PartPreview.decay_note(maxed, growth).is_empty(),
			"直径が上限なら巨大化の注記は出ない (寿命 %.1f→%.1f)" % [
				PartPreview.lifetime(maxed),
				PartPreview.lifetime(PartPreview.preview_stats(maxed, growth))]
		)

	# (4) 注記を足しても行の列は増えていない(peer の行に戻していない)。
	for part in CustomPartCatalog.all():
		check.call(
			_row_of(PartPreview.rows(stats, part, 3, 0.0, _opponent(1.5)), "STAT_LIFETIME").is_empty(),
			"%s: 寿命は行ではなく注記のまま" % part.title_key
		)

	# 引数が null でも落ちない(古い経路・ステータス無しの呼び出し)。
	check.call(
		PartPreview.decay_note(null, growth).is_empty()
		and PartPreview.decay_note(stats, null).is_empty(),
		"nullを渡しても空の注記を返す"
	)


## 残機札・ゴースト札はSpinnerStatsを一切変えない。硬さ・打たれ強さだけだと
## 「何も起きない札」に見えるので、ラン側の効果を行として補う。
func _test_non_stat_parts_still_show_something(check: Callable) -> void:
	var stats := _player()
	var lives := _find_effect(CustomPart.Effect.SET_LIVES)
	check.call(lives != null, "カタログに残機札がある")
	if lives != null:
		var rows := PartPreview.rows(stats, lives, 2, 0.0)
		var row := _row_of(rows, "STAT_LIVES")
		check.call(
			row["better"] == 1 and int(row["after"]) == lives.lives,
			"残機札: 残機の行が伸びる側で出る (%d→%d)" % [int(row["before"]), int(row["after"])]
		)
		# 既に多いときは下げない(GameState.apply_partのmaxiと同じ)。
		var already := _row_of(PartPreview.rows(stats, lives, 9, 0.0), "STAT_LIVES")
		check.call(
			already["better"] == 0,
			"残機札: 既に残機が多ければ変化なし (%d→%d)" % [
				int(already["before"]), int(already["after"])]
		)
		# 残機を渡さない呼び出し(continues<0)では行を出さない。
		check.call(
			_row_of(PartPreview.rows(stats, lives), "STAT_LIVES").is_empty(),
			"残機札: 残機が未指定なら残機の行は出さない"
		)

	var ghost := _find_effect(CustomPart.Effect.GHOST)
	check.call(ghost != null, "カタログにゴースト札がある")
	if ghost != null:
		var row := _row_of(PartPreview.rows(stats, ghost, 3, 2.0), "STAT_GHOST")
		check.call(
			row["better"] == 1 and is_equal_approx(row["after"], 2.0 + ghost.ghost_seconds),
			"ゴースト札: 無敵時間が累積して伸びる (%.1f→%.1f)" % [row["before"], row["after"]]
		)


## 変化しない行に「0.73 → 0.73」と出すと、変化があると誤読させる。
func _test_format_hides_unchanged(check: Callable) -> void:
	var same := {"label_key": "STAT_TOUGHNESS", "before": 0.735, "after": 0.735,
		"digits": 2, "better": 0}
	var moved := {"label_key": "STAT_TOUGHNESS", "before": 0.735, "after": 0.97,
		"digits": 2, "better": 1}
	check.call(
		not PartPreview.format_row(same).contains("→"),
		"変化なしの行に矢印を出さない (%s)" % PartPreview.format_row(same)
	)
	check.call(
		PartPreview.format_row(moved).contains("→"),
		"変化する行は 今の値 → 取った後の値 (%s)" % PartPreview.format_row(moved)
	)


## 画面側の配線。純粋関数が正しくても、呼ばれていなければ何も出ない。
##
## 報酬画面は@onreadyとレイアウトのフレームを要求するので、このランナー
## (SceneTreeの_init中)では実体化して中身を見られない。そこでBattle.gdに対する
## test_playback_pacing.gdと同じく、スクリプトの形を読んで配線を押さえる。
## **呼び出しの存在だけを見ると、条件を殺して到達しなくしたサボタージュを素通しする**
## (実際に `if _stats != null:` を `if false:` にして1件も落ちなかった)。
## 受け取り・条件・呼び出しの3点を揃って見ること。
func _test_screen_wiring(check: Callable) -> void:
	var screen := FileAccess.get_file_as_string("res://scenes/reward/RewardScreen.gd")
	check.call(
		screen.contains("_stats = stats"),
		"RewardScreen.gdがsetup()で今のビルドを受け取る"
	)
	check.call(
		screen.contains("if _stats != null:"),
		"RewardScreen.gdがビルドを受け取っているときに見積もりを出す(到達可能な条件)"
	)
	check.call(
		screen.contains("_stats, part, _continues, _ghost_seconds, _opponent"),
		"RewardScreen.gdが見積もりをPartPreviewから得る(受け取った値をそのまま渡す)"
	)
	check.call(
		screen.contains("_opponent = opponent"),
		"RewardScreen.gdがsetup()で攻めの基準になる相手を受け取る"
	)
	check.call(
		screen.contains("PartPreview.format_row("),
		"RewardScreen.gdが見積もりの表示文字列をPartPreviewから得る"
	)
	check.call(
		screen.contains("Palette.STAT_UP") and screen.contains("Palette.STAT_DOWN"),
		"RewardScreen.gdが良し悪しを色で見せる"
	)
	# 攻めの基準の注記。文字列を作るだけで画面に出していない配線を落とすため、
	# 生成・代入・出し隠しの3点を揃って見る(この関数の冒頭コメントと同じ理由)。
	check.call(
		screen.contains("PartPreview.attack_basis_text(")
		and screen.contains("PartPreview.toughness(_opponent) if _opponent != null else 0.0")
		and screen.contains("_attack_basis.text = basis")
		and screen.contains("_attack_basis.visible = basis != \"\""),
		"RewardScreen.gdが攻めの基準の注記を作り、画面に出し、基準が無ければ隠す"
	)
	# 自然減衰の注記。文字列を作るだけで画面に足していない配線を落とすため、
	# 生成・本文の代入・カードへの追加の3点を揃って見る(攻めの基準の注記と同じ理由)。
	check.call(
		screen.contains("PartPreview.decay_note(_stats, part)")
		and screen.contains("decay_label.text = decay[\"text\"]")
		and screen.contains("box.add_child(decay_label)"),
		"RewardScreen.gdが自然減衰の注記を作り、カードに足す"
	)
	check.call(
		screen.contains("if not decay.is_empty():"),
		"RewardScreen.gdは減衰率が動かない札に注記を出さない(空なら足さない)"
	)

	var main := FileAccess.get_file_as_string("res://scenes/main/Main.gd")
	check.call(
		main.contains("GameState.player_stats") and main.contains("GameState.continues_left")
		and main.contains("total_ghost_seconds(GameState.acquired_part_ids)"),
		"Main.gdが今のビルド(ステータス・残機・無敵時間)を報酬画面へ渡す"
	)
	check.call(
		main.contains("ThreatMeter.reachable_hardest_stats(GameState.map_tree)"),
		"Main.gdが攻めの基準になる相手(次に踏みうる部屋のいちばん硬い1体)を渡す"
	)
	# ハーネスと実UIの情報量は対等に保つ約束(naive_play.card_preview_text の冒頭)。
	# 実UIにだけ攻めの行があると、コールドプレイのエージェントだけが攻め札を
	# 「1行も動かない空欄の札」として見送り続けることになる。
	var cli := FileAccess.get_file_as_string("res://playtest/naive_play.gd")
	# 攻めの2行**とも**CLIに読める名前が要る。`_PREVIEW_LABELS` は未知のキーを
	# そのまま出す作りなので、片方だけ足し忘れると `STAT_KNOCKBACK ×1.09` という
	# 生キーがコールドプレイの画面に出る(実際にサボタージュで素通りした穴)。
	check.call(
		cli.contains("ThreatMeter.reachable_hardest_stats(tree)")
		and cli.contains("\"STAT_ATTACK\": \"攻め力\"")
		and cli.contains("\"STAT_KNOCKBACK\": \"弾き\""),
		"naive_play.gdも同じ基準で攻めの2行を出す(ハーネスと実UIの情報量は対等)"
	)
	check.call(
		cli.contains("PartPreview.toughness(opponent) if opponent != null else 0.0")
		and cli.contains("TranslationServer.set_locale(\"ja\")"),
		"naive_play.gdも攻めの基準の注記を、CLIの他の出力と同じ日本語で出す"
	)
	var scene := FileAccess.get_file_as_string("res://scenes/reward/RewardScreen.tscn")
	check.call(
		scene.contains("REWARD_PREVIEW_HINT"),
		"報酬画面に硬さ・打たれ強さの意味の注記がある"
	)
	check.call(
		scene.contains("name=\"AttackBasis\"") and scene.contains("auto_translate_mode = 2"),
		"報酬画面に攻めの基準の行があり、自動翻訳を切ってある(訳文へ数字を差し込むため)"
	)


## 新しい表示キーの訳が両localeにある。欠けるとキーが素で画面に出る。
func _test_translations(check: Callable) -> void:
	var saved := TranslationServer.get_locale()
	for locale in ["en", "ja"]:
		TranslationServer.set_locale(locale)
		for key in ["STAT_TOUGHNESS", "STAT_ATTACK", "STAT_KNOCKBACK", "STAT_ENDURANCE",
				"STAT_WALL_ENDURANCE", "REWARD_PREVIEW_HEADING", "REWARD_PREVIEW_HINT",
				"REWARD_DECAY_NOTE"]:
			var got := TranslationServer.translate(key)
			check.call(got != key, "%s: %s の訳がある (%s)" % [locale, key, got])
	# 注記は5つの行を全部説明していること。行だけ増えて説明が据え置きだと、
	# 「壁強さ」や「弾き」が何の量なのか画面のどこにも出ない。
	TranslationServer.set_locale("ja")
	var hint_ja := TranslationServer.translate("REWARD_PREVIEW_HINT")
	check.call(
		hint_ja.contains("硬さ") and hint_ja.contains("攻め力") and hint_ja.contains("弾き")
		and hint_ja.contains("打たれ強さ") and hint_ja.contains("壁強さ"),
		"注記が5つの行を全部説明している (%s)" % hint_ja
	)
	TranslationServer.set_locale(saved)


## 攻め力の行は「表示用の別式」ではなく、BattleResolver が与ダメージに使う
## SpinnerPhysics の合成そのもの。括り出したのは violence と相対速さだけなので、
## その2つを掛け戻せば実際の削りと**厳密に一致**しなければならない。
##
## 相手が自分より柔らかい場合と硬い場合の両方を見る。edge のボーナス基準は
## maxf(素の削り, pierce) なので、片方だけでは max の中身が入れ替わる境目を
## 押さえられない(max を落として素の削りだけにするサボタージュが素通りする)。
func _test_attack_row_matches_physics(check: Callable) -> void:
	var violence := 0.16
	var speed := 5.0
	var stats := _player()
	stats.mass = 2.0
	stats.radius = 0.8
	stats.edge = 0.2
	stats.drill = 0.25

	# 相手の硬さ = 質量×半径²。柔らかい相手(素の削り > pierce)と
	# 硬い相手(pierce > 素の削り)の2つ。
	for opponent in [[0.6, 0.4], [3.9, 1.8]]:
		var opp_mass: float = opponent[0]
		var opp_radius: float = opponent[1]
		var opp_toughness := opp_mass * opp_radius * opp_radius
		# BattleResolver._resolve_pair の与ダメージ側と同じ組み立て。
		var pierce := SpinnerPhysics.spin_drain(
			stats.mass, speed, stats.mass, stats.radius, violence)
		var raw := SpinnerPhysics.spin_drain(
			stats.mass, speed, opp_mass, opp_radius, violence)
		var dealt := SpinnerPhysics.drilled_spin_drain(
			SpinnerPhysics.sharpened_spin_drain(raw, stats.edge, pierce),
			stats.drill, pierce
		)
		var shown := PartPreview.attack(stats, opp_toughness)
		check.call(
			is_equal_approx(shown * violence * speed, dealt),
			"攻め力×violence×速さ = 実際の削り (硬さ%.2fの相手: %.4f 対 %.4f)"
				% [opp_toughness, shown * violence * speed, dealt]
		)


## **弾きの行が物理そのものであること**。表示だけ別式にすると嘘になるのは攻め力と同じ。
##
## 弾きは「1接触で相手が自分から離れる向きに受け取る速さ」から**噛み合う速さだけ**を
## 括り出した値なので、掛け戻せば BattleResolver が相手に与える速度変化と
## **厳密に一致**しなければならない。突き合わせるのは
## `SpinnerPhysics.elastic_velocities`(弾性衝突の交換)と `SpinnerPhysics.spin_kick`
## (削り比例の弾き)の和——この2つが弾きの2つの項の出どころそのもの。
##
## 正面衝突(相手は静止)で見るのは、そこが**プレイヤーが実際に狙う発射の1撃**であり、
## かつ自分の速さと噛み合う速さが一致する場面だから(knockback の doc 参照)。
## 速さを2つ試すのは、括り出した速さが本当に約分されていることを見るため
## ——片方の項だけ速さの掛け方を間違えると、この2本で値が食い違う。
func _test_knockback_row_matches_physics(check: Callable) -> void:
	var violence := 0.16
	var kick_scale := 1.15
	var stats := _player()
	stats.mass = 2.0
	stats.radius = 0.8
	stats.edge = 0.2
	stats.drill = 0.25
	stats.restitution = 0.85

	for opponent_spec in [[0.6, 0.4], [3.9, 1.8]]:
		var opp := SpinnerStats.new()
		opp.mass = opponent_spec[0]
		opp.radius = opponent_spec[1]
		opp.restitution = 1.0
		var shown := PartPreview.knockback(stats, opp, kick_scale, violence)
		for speed in [4.0, 11.0]:
			# 正面衝突: 自分は原点から+x へ speed、相手は +x 側で静止。
			var pos_a := Vector2.ZERO
			var pos_b := Vector2(stats.radius + opp.radius, 0.0)
			var vel_a := Vector2(speed, 0.0)
			var pair := clampf(stats.restitution * opp.restitution, 0.0, 1.0)
			var bounced := SpinnerPhysics.elastic_velocities(
				pos_a, vel_a, stats.mass, pos_b, Vector2.ZERO, opp.mass, pair
			)
			# 相手が受ける削り(BattleResolver._resolve_disc_collision の b_drain と同じ組み立て)。
			var pierce := SpinnerPhysics.spin_drain(
				stats.mass, speed, stats.mass, stats.radius, violence)
			var drain := SpinnerPhysics.guarded_spin_drain(
				SpinnerPhysics.drilled_spin_drain(
					SpinnerPhysics.sharpened_spin_drain(
						SpinnerPhysics.spin_drain(
							stats.mass, speed, opp.mass, opp.radius, violence),
						stats.edge, pierce
					),
					stats.drill, pierce
				),
				opp.hit_guard
			)
			var kicked: Vector2 = bounced[1] + SpinnerPhysics.spin_kick(
				pos_b, pos_a, opp.radius, drain, kick_scale)
			check.call(
				is_equal_approx(shown * speed, kicked.x),
				"弾き×噛み合う速さ = 実際に相手が受け取る速さ (相手 質量%.2f/半径%.2f, 速さ%.1f: %.4f 対 %.4f)"
					% [opp.mass, opp.radius, speed, shown * speed, kicked.x]
			)

	# 相手の衝突軽減は削り比例の側だけを削る(弾性衝突は軽減を通らない)。
	var guarded_opp := SpinnerStats.new()
	guarded_opp.mass = 2.0
	guarded_opp.radius = 0.9
	guarded_opp.restitution = 1.0
	guarded_opp.hit_guard = 0.5
	var plain_opp := SpinnerStats.new()
	plain_opp.mass = 2.0
	plain_opp.radius = 0.9
	plain_opp.restitution = 1.0
	check.call(
		PartPreview.knockback(stats, guarded_opp, kick_scale, violence)
			< PartPreview.knockback(stats, plain_opp, kick_scale, violence),
		"相手の衝突軽減で弾きが減る(削り比例の側だけ)"
	)

	# 質量比の項は相手が重いほど縮み、自分が重いほど伸びる。反発も上げれば伸びる。
	var heavy := _player()
	heavy.mass = _player().mass * 2.0
	var bouncy := _player()
	bouncy.restitution = minf(_player().restitution * 1.1, 1.0)
	check.call(
		PartPreview.knockback(heavy, plain_opp, kick_scale, violence)
			> PartPreview.knockback(_player(), plain_opp, kick_scale, violence)
		and PartPreview.knockback(bouncy, plain_opp, kick_scale, violence)
			> PartPreview.knockback(_player(), plain_opp, kick_scale, violence),
		"質量でも反発でも弾きが伸びる"
	)

	# null / 縮退した相手でも inf・nan を出さない(古い経路・将来の札)。
	var zero_opp := SpinnerStats.new()
	zero_opp.mass = 0.0
	zero_opp.radius = 0.0
	check.call(
		PartPreview.knockback(stats, null, kick_scale, violence) == 0.0
		and PartPreview.knockback(null, plain_opp, kick_scale, violence) == 0.0
		and is_finite(PartPreview.knockback(stats, zero_opp, kick_scale, violence)),
		"nullや縮退した相手でもinf/nanにならない"
	)


## **この変更の証拠**。攻め力は削りしか数えないので、壁へ押し込む攻めの札が
## 攻めの行で1ミリも動かなかった。敵の死因は Lv2以降で壁が1/4〜1/2以上
## (Lv3・Lv4の乱戦では壁が主因。build/playtest/report.md の死因内訳)なのに、
## RAGE_REFLECTION(反発↑)は攻めの行が据え置き、SHARP_EDGE の効果文が言う
## 「弾き飛ばしも強まる」にも数字が付いていなかった。
##
## 見るのは3つ:
##  (1) **反発の札は弾きだけを動かす**(攻め力は据え置き)。ここが眼目で、
##      壁強さを足したときの「RAGEが2行とも変化なし」と同じ切れ方の攻め版。
##  (2) **削り増強・貫通削りの札は両方を動かす**。spin_kick は削り比例なので、
##      効果文の「弾き飛ばしも強まる」が本当であることが数字になる。
##  (3) **攻めの2行は必ず一緒に出る**(片方だけ出る状態を作らない)。順番は
##      硬さ → 攻め力 → 弾き。
func _test_knockback_row_is_the_offence_the_attack_row_misses(check: Callable) -> void:
	var stats := _player()
	var opp := _opponent(1.52)

	# (1) 反発の札(RAGE)は攻め力を1ミリも動かさず、弾きだけを動かす。
	var rage := _find_effect(CustomPart.Effect.RAGE)
	check.call(rage != null, "カタログに怒りの反射札がある")
	if rage != null:
		var rows := PartPreview.rows(stats, rage, -1, 0.0, opp)
		check.call(
			_better(rows, "STAT_KNOCKBACK") == 1 and _better(rows, "STAT_ATTACK") == 0,
			"怒りの反射: 弾きだけが伸びる＝攻めの2行が別の軸を測っている (弾き %s)"
				% _row_text(rows, "STAT_KNOCKBACK")
		)

	# (2) 削りの札(EDGE/DRILL)は spin_kick 経由で弾きも伸ばす。効果文の
	#     「弾き飛ばしも強まる」に初めて数字が付く。
	for effect in [CustomPart.Effect.EDGE, CustomPart.Effect.DRILL]:
		var part := _find_effect(effect)
		var rows := PartPreview.rows(stats, part, -1, 0.0, opp)
		check.call(
			_better(rows, "STAT_ATTACK") == 1 and _better(rows, "STAT_KNOCKBACK") == 1,
			"%s: 攻め力と弾きの両方が伸びる (弾き %s)"
				% [part.title_key, _row_text(rows, "STAT_KNOCKBACK")]
		)

	# 質量・反発を上げる札は**例外なく**弾きが伸びる(弾性衝突の側)。カード名で
	# 名指しせず「質量か反発を上げる札」としてカタログ全体から拾う——札が増えたときも
	# 検査が付いてくるし、`_find_effect` の効果IDに依存しない。
	var heavy_cards: Array[String] = []
	var flat: Array[String] = []
	for part in CustomPartCatalog.all():
		var after := PartPreview.preview_stats(stats, part)
		if after.mass <= stats.mass and after.restitution <= stats.restitution:
			continue
		heavy_cards.append(part.title_key)
		if _better(PartPreview.rows(stats, part, -1, 0.0, opp), "STAT_KNOCKBACK") != 1:
			flat.append(part.title_key)
	check.call(heavy_cards.size() >= 2, "質量か反発を上げる札が2枚以上ある (%s)" % ", ".join(heavy_cards))
	check.call(
		flat.is_empty(),
		"質量・反発を上げる札は弾きが伸びる(弾性衝突の側) (伸びなかった: %s)" % ", ".join(flat)
	)

	# 守りの札(GUARD)は攻めの2行を動かさない——ここが動き始めたら、行が
	# 「何でも伸びる欄」になっていて選択の材料にならない。
	var absorber := _find_effect(CustomPart.Effect.GUARD)
	if absorber != null:
		var rows := PartPreview.rows(stats, absorber, -1, 0.0, opp)
		check.call(
			_better(rows, "STAT_KNOCKBACK") == 0 and _better(rows, "STAT_ATTACK") == 0,
			"衝突軽減: 攻めの2行はどちらも動かない(守りの札)"
		)

	# (3) 攻めの2行は必ず一緒に出て、硬さ → 攻め力 → 弾き の順に並ぶ。
	var missing: Array[String] = []
	var order_broken: Array[String] = []
	for part in CustomPartCatalog.all():
		var without := PartPreview.rows(stats, part, -1, 0.0)
		if not (_row_of(without, "STAT_ATTACK").is_empty()
				and _row_of(without, "STAT_KNOCKBACK").is_empty()):
			missing.append("%s(相手なしで出た)" % part.title_key)
		var rows := PartPreview.rows(stats, part, -1, 0.0, opp)
		if _row_of(rows, "STAT_ATTACK").is_empty() or _row_of(rows, "STAT_KNOCKBACK").is_empty():
			missing.append("%s(相手ありで欠けた)" % part.title_key)
			continue
		var keys := PackedStringArray()
		for row in rows:
			keys.append(row["label_key"])
		if not (keys[0] == "STAT_TOUGHNESS" and keys[1] == "STAT_ATTACK"
				and keys[2] == "STAT_KNOCKBACK"):
			order_broken.append("%s(%s)" % [part.title_key, ", ".join(keys)])
	check.call(
		missing.is_empty(),
		"攻めの2行は基準の相手と一緒に出入りする (%s)" % ", ".join(missing)
	)
	check.call(
		order_broken.is_empty(),
		"並びは 硬さ → 攻め力 → 弾き (%s)" % ", ".join(order_broken)
	)


## 倍率(PartPreview.knockback_index)の素性。攻め力の倍率と同じ3点:
## 素のコマがちょうど 1.00、相手が居なければ 0、そして**カード同士の順位を
## 変えない**(分母が全札に共通の正の数)。
##
## 倍率にする理由は attack_index と同じで、生の弾きは質量比の項が相手の質量に
## 反比例して縮むため、そのまま出すとラン中に自分が育つほど数字が小さくなる。
## **相手を重くしても素のコマが1.00のまま**であることが、その逆立ちを潰した証拠。
func _test_knockback_index_is_a_multiple_of_the_stock_spinner(check: Callable) -> void:
	var opponents: Array[SpinnerStats] = [
		_opponent(0.12, 0.8), _opponent(1.52, 2.0), _opponent(12.56, 3.8)
	]
	for opp in opponents:
		check.call(
			is_equal_approx(PartPreview.knockback_index(_player(), opp), 1.0),
			"素のコマは倍率1.00 (相手の硬さ%.2f: %.4f)" % [
				PartPreview.toughness(opp), PartPreview.knockback_index(_player(), opp)]
		)
	check.call(
		PartPreview.knockback_index(_player(), null) == 0.0
		and PartPreview.knockback_index(null, opponents[0]) == 0.0,
		"基準の相手が無ければ倍率も0(弾きの行を出さない合図)"
	)

	# 分母が全札に共通＝倍率と生の弾きで大小関係が同じ。
	var req := BattleRequest.new()
	for opp in [opponents[0], opponents[2]]:
		var ratios: Array[float] = []
		for part in CustomPartCatalog.all():
			var after := PartPreview.preview_stats(_player(), part)
			var raw := PartPreview.knockback(after, opp, req.spin_kick_scale, req.violence)
			var indexed := PartPreview.knockback_index(after, opp)
			check.call(raw > 0.0 and indexed > 0.0, "%s: 弾きは正" % part.title_key)
			ratios.append(indexed / raw)
		for i in range(1, ratios.size()):
			check.call(
				is_equal_approx(ratios[0], ratios[i]),
				"相手の硬さ%.2f: 全札で同じ分母＝順位が変わらない (%.6f 対 %.6f)"
					% [PartPreview.toughness(opp), ratios[0], ratios[i]]
			)


## 基準の相手が居なければ行を出さない。守りの3行と違って攻めは相手を括り出せない
## ので、相手が無いときに0や適当な既定値で行を出すと**嘘の見積もり**になる。
## 決戦のあと(進める先が無い)と、ステータス無しで呼ばれる古い経路がここを通る。
func _test_attack_row_needs_an_opponent(check: Callable) -> void:
	var stats := _player()
	var part := _find_effect(CustomPart.Effect.EDGE)
	check.call(
		_row_of(PartPreview.rows(stats, part), "STAT_ATTACK").is_empty(),
		"基準の相手が無ければ攻めの行は出ない"
	)
	var rows := PartPreview.rows(stats, part, -1, 0.0, _opponent(1.5))
	check.call(
		not _row_of(rows, "STAT_ATTACK").is_empty(),
		"基準の相手があれば攻めの行が出る"
	)
	# 硬さの直後。この2つは同じ1接触の表と裏(削られない量と削る量)で、
	# 残る2行は「何回耐えられるか」と単位が違う。
	var keys := PackedStringArray()
	for row in rows:
		keys.append(row["label_key"])
	check.call(
		keys.size() >= 2 and keys[0] == "STAT_TOUGHNESS" and keys[1] == "STAT_ATTACK",
		"攻めの行は硬さの直後に並ぶ (%s)" % ", ".join(keys)
	)


## **この変更の証拠**。EDGE(削り増強)と DRILL(貫通削り)は、攻めの行が入る前は
## 硬さ・打たれ強さ・壁強さの3行とも1ミリも動かず、報酬画面で**空欄の札**だった
## (一次証拠はコールドプレイ 2026-08-06 seed=48123。part_preview.gd の attack 参照)。
## 攻めの行だけが動き、守りの3行は据え置きのままであることを両方見る
## ——攻めの札が守りの行を動かし始めたらそれは別のバグ。
func _test_attack_row_is_the_only_home_of_the_offence_cards(check: Callable) -> void:
	var stats := _player()
	for effect in [CustomPart.Effect.EDGE, CustomPart.Effect.DRILL]:
		var part := _find_effect(effect)
		var rows := PartPreview.rows(stats, part, -1, 0.0, _opponent(1.5))
		check.call(
			_better(rows, "STAT_ATTACK") == 1,
			"%s: 攻め力が伸びる" % part.title_key
		)
		check.call(
			_better(rows, "STAT_TOUGHNESS") == 0
			and _better(rows, "STAT_ENDURANCE") == 0
			and _better(rows, "STAT_WALL_ENDURANCE") == 0,
			"%s: 守りの3行は据え置き(＝攻めの行が無ければ空欄の札だった)" % part.title_key
		)


## 倍率(PartPreview.attack_index)の素性。素のコマがちょうど 1.00 になること、
## 基準の相手が無ければ 0(＝行そのものが出ない合図)であること、そして
## **1画面の中でのカード同士の比較を一切変えない**こと——分母は3枚とも共通の正の数
## なので、倍率は attack の正のスカラー倍でなければならない。ここが崩れると
## 「見た目のために順位が入れ替わる」ことになり、見積もりが嘘になる。
func _test_attack_index_is_a_multiple_of_the_stock_spinner(check: Callable) -> void:
	for opponent in [0.12, 1.52, 12.56]:
		check.call(
			is_equal_approx(PartPreview.attack_index(_player(), opponent), 1.0),
			"素のコマは倍率1.00 (相手の硬さ%.2f: %.4f)"
				% [opponent, PartPreview.attack_index(_player(), opponent)]
		)
	check.call(
		PartPreview.attack_index(_player(), 0.0) == 0.0
		and PartPreview.attack_index(_player(), -1.0) == 0.0,
		"基準の相手が無ければ倍率も0(攻めの行を出さない合図)"
	)

	# 分母が3枚に共通＝倍率と生の攻め力で大小関係が同じ。全札×2つの硬さで見る。
	for opponent in [0.12, 12.56]:
		var ratios: Array[float] = []
		for part in CustomPartCatalog.all():
			var after := PartPreview.preview_stats(_player(), part)
			var raw := PartPreview.attack(after, opponent)
			var indexed := PartPreview.attack_index(after, opponent)
			check.call(raw > 0.0 and indexed > 0.0, "%s: 攻めは正" % part.title_key)
			ratios.append(indexed / raw)
		for i in range(1, ratios.size()):
			check.call(
				is_equal_approx(ratios[0], ratios[i]),
				"相手の硬さ%.2f: 全札で同じ分母＝順位が変わらない (%.6f 対 %.6f)"
					% [opponent, ratios[0], ratios[i]]
			)


## **この変更の証拠**(2026-08-07)。攻めの行に出す値を素のコマ基準の倍率へ変えた理由は
## 「ランを通して読むと、育っているのに数字が縮む」だった。コールドプレイ
## (seed=4821・9戦全勝でクリア)で実際に踏んだ8画面ぶんのビルドと基準の相手を並べ、
##  - **倍率は段が進むごとに必ず伸びる**(＝守りの3行と同じ向き)
##  - **生の攻め力はそうならない**(縮む段がある。それがこの変更の動機)
## の両方を見る。後半だけでは足りない——前半は相手が柔らかく素の削りが支配的、
## 後半は相手が硬く貫通削りが支配的で、max の中身が入れ替わるからで、
## 片側だけ切り出すと「たまたま単調だった」で通ってしまう。
func _test_attack_row_reads_as_build_growth(check: Callable) -> void:
	# [基準の相手の硬さ, 質量, 半径, 削り増強, 貫通削り] を段1の報酬画面から順に。
	var run := [
		[0.11, 1.50, 0.70, 0.00, 0.00],
		[0.49, 1.50, 0.70, 0.00, 0.25],
		[0.41, 1.50, 0.70, 0.40, 0.25],
		[1.52, 1.95, 0.70, 0.40, 0.25],
		[1.76, 2.24, 0.88, 0.40, 0.50],
		[3.66, 2.58, 1.05, 0.40, 0.50],
		[3.88, 2.58, 1.05, 0.40, 0.50],
		[12.56, 2.58, 1.05, 0.40, 0.50],
	]
	var shown: Array[float] = []
	var raw: Array[float] = []
	# 表示の値は rows() から取る。attack_index を直に呼ぶと「関数はあるが
	# 行に繋がっていない」サボタージュが素通りする。
	var wiring := _find_effect(CustomPart.Effect.DRILL)
	for entry in run:
		var stats := _player()
		stats.mass = entry[1]
		stats.radius = entry[2]
		stats.edge = entry[3]
		stats.drill = entry[4]
		var row := _row_of(
			PartPreview.rows(stats, wiring, -1, 0.0, _opponent(entry[0])), "STAT_ATTACK")
		check.call(not row.is_empty(), "攻めの行が出る(相手の硬さ%.2f)" % entry[0])
		shown.append(row["before"])
		raw.append(PartPreview.attack(stats, entry[0]))

	var shown_falls := false
	var raw_falls := false
	for i in range(1, shown.size()):
		if shown[i] <= shown[i - 1]:
			shown_falls = true
		if raw[i] <= raw[i - 1]:
			raw_falls = true
	check.call(
		not shown_falls,
		"攻めの行はラン中ずっと伸びる(実測のビルド8画面: %s)" % str(shown)
	)
	check.call(
		raw_falls,
		"生の攻め力はそうならない＝この変更の動機がまだ現実であること (%s)" % str(raw)
	)
	# 倍率だと分かる印。絶対量の行(硬さ・打たれ強さ)には付かない。
	var rows := PartPreview.rows(_player(), wiring, -1, 0.0, _opponent(12.56, 3.8))
	check.call(
		PartPreview.format_row(_row_of(rows, "STAT_ATTACK")).begins_with("×"),
		"攻めの行は倍率と分かる印が付く (%s)"
			% PartPreview.format_row(_row_of(rows, "STAT_ATTACK"))
	)
	for key in ["STAT_TOUGHNESS", "STAT_ENDURANCE", "STAT_WALL_ENDURANCE"]:
		check.call(
			not PartPreview.format_row(_row_of(rows, key)).begins_with("×"),
			"%s は絶対量なので倍率の印を付けない" % key
		)


## 攻めの行だけが基準の相手を持っていて、その相手の
## 硬さはラン中に十数倍になる。だから自分が強くなっていても攻めの行は縮む
## (コールドプレイ seed=4711 の実測で 12.59 → 1.09)。注記が**基準の相手の硬さを
## その場の数字で**言わなければ、他の3行が伸びる隣でこの行だけ逆を向く理由が
## 画面のどこにも無い。
##
## 見るのは3点: (1)基準が無ければ注記も出ない(攻めの行が出ないのと揃う)、
## (2)基準の相手が変われば注記の数字も変わる(定型文を出すだけのサボタージュを落とす)、
## (3)その数字が実際に渡された硬さである。
func _test_attack_basis_names_the_reference_opponent(check: Callable) -> void:
	var saved := TranslationServer.get_locale()
	TranslationServer.set_locale("ja")

	check.call(
		PartPreview.attack_basis_text(0.0) == "",
		"基準の相手が無ければ注記も出ない(攻めの行が出ないのと揃う)"
	)
	check.call(
		PartPreview.attack_basis_text(-1.0) == "",
		"決戦のあと(reachable_hardest_toughness が -1)も注記を出さない"
	)

	# 段1の相手(Lv1)と決戦の相手(Lv5)。硬さは実ロスターのおおよその両端。
	var early := PartPreview.attack_basis_text(0.12)
	var late := PartPreview.attack_basis_text(12.64)
	check.call(early != "" and late != "", "基準の相手があれば注記が出る")
	check.call(
		early != late,
		"基準の相手が変われば注記も変わる(定型文ではない: %s / %s)" % [early, late]
	)
	check.call(
		early.contains("0.12") and late.contains("12.64"),
		"注記が基準の相手の硬さそのものを出す (%s / %s)" % [early, late]
	)

	# 両localeに訳があること。欠けるとキーが素のまま画面に出る。
	# 行の値が倍率になった(2026-08-07)ので、注記は**何を1.00とした倍率か**まで言う
	# ——基準の相手だけを言って倍率だと言わないと、「×3.83」が絶対量に読める。
	for locale in ["en", "ja"]:
		TranslationServer.set_locale(locale)
		var text := PartPreview.attack_basis_text(12.64)
		check.call(
			not text.begins_with("REWARD_ATTACK_BASIS") and text.contains("12.64"),
			"%s: 注記の訳がある (%s)" % [locale, text]
		)
		check.call(
			text.contains("素のコマ") if locale == "ja" else text.contains("stock spinner"),
			"%s: 注記が倍率の基準(素のコマ)を名指しする (%s)" % [locale, text]
		)
	TranslationServer.set_locale(saved)


## 良し悪しの色が実際に読めるかは test_contrast.gd が見る(色はPaletteの持ち物)。
func _find_effect(effect: CustomPart.Effect) -> CustomPart:
	for part in CustomPartCatalog.all():
		if part.effect == effect:
			return part
	return null


## 行の変化の向き。行そのものが無ければ 99(どの期待値とも一致しない値)を返す。
## 「行が消えた」を「向きが違う」と同じ1つの失敗として出すための踏み台。
func _better(rows: Array[Dictionary], label_key: String) -> int:
	var row := _row_of(rows, label_key)
	return 99 if row.is_empty() else int(row["better"])


## 失敗メッセージ用の「1.00→1.09」。行が無ければそう言う。
func _row_text(rows: Array[Dictionary], label_key: String) -> String:
	var row := _row_of(rows, label_key)
	if row.is_empty():
		return "行が無い"
	return "%.2f→%.2f" % [row["before"], row["after"]]


func _row_of(rows: Array[Dictionary], label_key: String) -> Dictionary:
	for row in rows:
		if row["label_key"] == label_key:
			return row
	return {}
