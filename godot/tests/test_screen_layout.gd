extends RefCounted

## screen_layout.gd のテスト。縦画面レイアウトの純粋関数を数値で確かめる。
##
## 見た目そのものは静止画では確かめられない(CLAUDE.mdの方針)。ここでは
## 「横画面(設計比16:9)では一切変換しない」不変条件と、当てはめ・配置の
## 値域・単調性・境界を固定する。実描画の当否は verify.sh のSPスクショで人が見る。

const EPS := 1e-3


func run(check: Callable) -> void:
	_test_is_portrait(check)
	_test_fit_scale(check)
	_test_placement(check)
	_test_stack_top(check)


## 一番大事な不変条件: 設計解像度(1280x720, 16:9)は横画面扱い=変換しない。
## ここが true になると横画面の見た目が動いてしまう。
func _test_is_portrait(check: Callable) -> void:
	check.call(
		not ScreenLayout.is_portrait(ScreenLayout.DESIGN),
		"設計解像度(1280x720)は横画面扱い(変換しない)"
	)
	check.call(
		not ScreenLayout.is_portrait(Vector2(1920.0, 720.0)),
		"16:9より横長も横画面扱い"
	)
	# expandで縦長ウィンドウは base が縦に伸びる(例 1280x2770)。
	check.call(
		ScreenLayout.is_portrait(Vector2(1280.0, 2770.0)),
		"16:9より縦長は縦画面扱い"
	)
	# デバイス寸法(スケール前)でも比で判定できる。
	check.call(ScreenLayout.is_portrait(Vector2(390.0, 844.0)), "スマホ縦(390x844)は縦画面")
	# 4:3 も16:9より縦長。
	check.call(ScreenLayout.is_portrait(Vector2(1280.0, 960.0)), "4:3は縦画面扱い")


## アスペクト維持で target へ収める倍率。厳しい方に合わせ、はみ出さない。
func _test_fit_scale(check: Callable) -> void:
	# 幅が厳しい: min(200/100, 400/100)=2
	check.call(
		absf(ScreenLayout.fit_scale(Vector2(100.0, 100.0), Vector2(200.0, 400.0)) - 2.0) < EPS,
		"fit_scale: 厳しい軸(幅)に合わせる"
	)
	# 収めた結果が両軸とも target 以内。
	var content := Vector2(292.0, 594.0)
	var target := Vector2(1152.0, 2770.0)
	var k := ScreenLayout.fit_scale(content, target)
	var scaled := content * k
	check.call(
		scaled.x <= target.x + EPS and scaled.y <= target.y + EPS,
		"fit_scale: 収めた結果が target 内 (%.1fx%.1f)" % [scaled.x, scaled.y]
	)
	# 少なくとも片方の軸は target にぴったり届く(無駄に小さくしない)。
	check.call(
		absf(scaled.x - target.x) < EPS or absf(scaled.y - target.y) < EPS,
		"fit_scale: 片軸は target にぴったり"
	)
	# 0除算しない。
	check.call(
		ScreenLayout.fit_scale(Vector2.ZERO, target) == 1.0,
		"fit_scale: content 0 でも壊れない"
	)


## スケール後サイズを visible 内に置く左上座標。bias=0.5で中央、0.7で下寄り。
func _test_placement(check: Callable) -> void:
	var scaled := Vector2(100.0, 100.0)
	var visible := Vector2(500.0, 500.0)

	var centered := ScreenLayout.placement(scaled, visible, 0.5, 0.5)
	check.call(centered.is_equal_approx(Vector2(200.0, 200.0)), "placement: 0.5で中央")

	var lower := ScreenLayout.placement(scaled, visible, 0.5, 0.7)
	check.call(lower.y > centered.y + EPS, "placement: v_bias0.7は中央より下")
	check.call(absf(lower.x - centered.x) < EPS, "placement: 横は中央のまま")
	# (500-100)*0.7 = 280
	check.call(absf(lower.y - 280.0) < EPS, "placement: v_bias0.7の値 (%.1f)" % lower.y)

	# 余白が負(コンテンツが画面より大きい)なら0に丸め、画面外へ出さない。
	var overflow := ScreenLayout.placement(Vector2(800.0, 800.0), visible, 0.5, 0.7)
	check.call(overflow == Vector2.ZERO, "placement: 余白が負なら0")

	# 横画面相当(scaled==visible)なら shift 0。
	var same := ScreenLayout.placement(visible, visible, 0.5, 0.7)
	check.call(same == Vector2.ZERO, "placement: ぴったりなら移動なし")


## リザルト行の塊の置き所。対戦画面はメッセージ(60px)＋固定高の行を
## アリーナの上に重ねるが、行は画面に依らない固定pxでアリーナだけが端末幅で縮むので、
## 細い端末では塊が下のバー帯へ食い込む。span を越えない範囲まで押し上げる規則を固定する。
func _test_stack_top(check: Callable) -> void:
	const EPS := 0.001
	# 余裕がある(広い縦画面・タブレット相当)なら bias のまま動かない。
	# arena_px=691, 塊=60+40*4=220 → 691*0.4=276.4 が 691-220=471 より小さいので素通り。
	check.call(
		absf(ScreenLayout.stack_top(691.0, 220.0, 0.4) - 276.4) < EPS,
		"stack_top: 余裕があれば bias のまま (%.1f)" % ScreenLayout.stack_top(691.0, 220.0, 0.4)
	)

	# SP幅390 (arena_px=351): bias位置140.4だと下端が360.4でアリーナ(351)を越える。
	# 押し上げて 351-220=131。この端末が押し上げの要る側の代表。
	check.call(
		absf(ScreenLayout.stack_top(351.0, 220.0, 0.4) - 131.0) < EPS,
		"stack_top: SP390は押し上げる (%.1f)" % ScreenLayout.stack_top(351.0, 220.0, 0.4)
	)

	# どの端末でも下端が span を越えない、が守るべき性質そのもの。
	# 行が3本だった頃(180px)は押し上げ不要だった幅でも、4本(220px)なら要る。
	for arena_px in [324.0, 351.0, 400.0, 500.0, 691.0]:
		var top := ScreenLayout.stack_top(arena_px, 220.0, 0.4)
		check.call(
			top + 220.0 <= arena_px + EPS,
			"stack_top: arena %.0f で塊がはみ出さない (下端 %.1f)" % [arena_px, top + 220.0]
		)
		check.call(top >= -EPS, "stack_top: arena %.0f で負にならない (%.1f)" % [arena_px, top])

	# 塊が領域より高ければ上端へ貼り付く(負にして画面外へ出さない)。
	check.call(
		absf(ScreenLayout.stack_top(100.0, 220.0, 0.4)) < EPS, "stack_top: 入り切らなければ0"
	)
