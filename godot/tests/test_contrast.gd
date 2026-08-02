extends RefCounted

## Palette のテキスト/ステージのコントラストが WCAG のしきい値を満たすか検証する。
##
## もともと戦闘メッセージ(既定のほぼ白文字)がほぼ白の床 f0f0f0 の上に乗っていて
## 読めなかった。色をいじる度に同じ罠を踏まないよう、ここで機械的に固定する。
##
## 判定は ColorContrast(WCAG 相対輝度→コントラスト比)で行う。通常テキストは
## 4.5:1、大きいテキスト・非テキスト図形は 3:1。戦闘メッセージは36pxで「大」だが、
## 縁取りに対しては通常テキスト基準(4.5)で押さえる(縁取りが読みの地になるため)。
##
## サボタージュ検証(CLAUDE.md「壊した実装を落とせて初めて完成」):
##   1. palette.gd の FLOOR を Color("f0f0f0")(旧の白床)に戻す
##      → 「明色文字 vs 床」「ネオン図形 vs 床」が赤くなる。
##   2. palette.gd の TEXT_PRIMARY を Palette.FLOOR にする
##      → 「明色文字 vs 縁取り/床」が赤くなる。
##   いずれも確認したら元に戻す。実際にこの手順で赤くなることを確認済み。

## Godot の既定 Theme が Label に与える font_color。エンジン内蔵の定数で、
## メニュー画面はこれを default_clear_color の上に描く。将来Godot側が変えたら
## ここも追随する(現行 4.x は 0.875 のグレー)。
const DEFAULT_LABEL_FONT_COLOR := Color(0.875, 0.875, 0.875)


func run(check: Callable) -> void:
	_test_battle_message(check)
	_test_reward_rare_card(check)
	_test_menu_text(check)
	_test_neon_actors_on_floor(check)
	_test_map_nodes(check)
	_test_threat_meter_colors(check)
	_test_obstacle_mark_colors(check)


## 元凶。戦闘メッセージ(明色文字＋暗色縁取り)が床の上でも縁取りの上でも読める。
func _test_battle_message(check: Callable) -> void:
	var vs_outline := ColorContrast.ratio(Palette.TEXT_PRIMARY, Palette.TEXT_OUTLINE)
	check.call(
		vs_outline >= ColorContrast.AA_NORMAL,
		"戦闘メッセージ: 明色文字 vs 縁取り = %.2f (>= %.1f)" % [vs_outline, ColorContrast.AA_NORMAL]
	)
	var vs_floor := ColorContrast.ratio(Palette.TEXT_PRIMARY, Palette.FLOOR)
	check.call(
		vs_floor >= ColorContrast.AA_NORMAL,
		"戦闘メッセージ: 明色文字 vs 床 = %.2f (>= %.1f)" % [vs_floor, ColorContrast.AA_NORMAL]
	)


## レア報酬カード。明るいまま残る唯一の面。暗色文字が金の地で読める。
func _test_reward_rare_card(check: Callable) -> void:
	var r := ColorContrast.ratio(Palette.TEXT_ON_LIGHT, Palette.GOLD_CARD)
	check.call(
		r >= ColorContrast.AA_NORMAL,
		"レアカード: 暗色文字 vs 金の地 = %.2f (>= %.1f)" % [r, ColorContrast.AA_NORMAL]
	)

	# 報酬カードの見積もり(硬さ・寿命の増減)の色。通常カードは暗い地(SURFACE)に
	# 直接乗り、レアカードは金の地なので暗色の縁取りを敷いて読ませる(戦闘メッセージ
	# と同じ手口)。どちらの地でも通常テキスト基準を満たすこと。
	for entry in [
		{"name": "良化", "color": Palette.STAT_UP},
		{"name": "悪化", "color": Palette.STAT_DOWN},
	]:
		var color: Color = entry["color"]
		var vs_surface := ColorContrast.ratio(color, Palette.SURFACE)
		check.call(
			vs_surface >= ColorContrast.AA_NORMAL,
			"見積もり(%s): 文字 vs カードの地 = %.2f (>= %.1f)" % [
				entry["name"], vs_surface, ColorContrast.AA_NORMAL]
		)
		var vs_outline := ColorContrast.ratio(color, Palette.TEXT_OUTLINE)
		check.call(
			vs_outline >= ColorContrast.AA_NORMAL,
			"見積もり(%s): 文字 vs レアカードでの縁取り = %.2f (>= %.1f)" % [
				entry["name"], vs_outline, ColorContrast.AA_NORMAL]
		)


## メニュー。既定の明るいラベル文字が、暗い既定クリア色の上で読める。
## クリア色は project.godot のリテラルなので Palette.BG と一致していることも確かめる
## (両者がずれるとテストは通るのに実画面のコントラストが崩れるため)。
func _test_menu_text(check: Callable) -> void:
	var clear: Color = ProjectSettings.get_setting(
		"rendering/environment/defaults/default_clear_color", Color.BLACK
	)
	check.call(
		clear.is_equal_approx(Palette.BG),
		"クリア色が Palette.BG と一致 (project.godot=%s, Palette.BG=%s)" % [clear, Palette.BG]
	)
	var r := ColorContrast.ratio(DEFAULT_LABEL_FONT_COLOR, Palette.BG)
	check.call(
		r >= ColorContrast.AA_NORMAL,
		"メニュー: 既定ラベル文字 vs 背景 = %.2f (>= %.1f)" % [r, ColorContrast.AA_NORMAL]
	)


## ネオンの主役たち(コマ・壁・照準)が床の上で図形として見分けられる(非テキスト 3:1)。
func _test_neon_actors_on_floor(check: Callable) -> void:
	var actors := {
		"プレイヤーのコマ": Palette.PLAYER,
		"敵のコマ": Palette.ENEMY,
		"壁": Palette.NEON_MAGENTA,
		"照準": Palette.AIM,
	}
	for name in actors:
		var r := ColorContrast.ratio(actors[name], Palette.FLOOR)
		check.call(
			r >= ColorContrast.AA_LARGE,
			"%s vs 床 = %.2f (>= %.1f)" % [name, r, ColorContrast.AA_LARGE]
		)


## マップの主役ノード(現在地・次に進める先)が暗い背景で見分けられる(非テキスト 3:1)。
func _test_map_nodes(check: Callable) -> void:
	var nodes := {
		"現在地ノード": Palette.MAP_CURRENT,
		"次のノード": Palette.MAP_NEXT,
	}
	for name in nodes:
		var r := ColorContrast.ratio(nodes[name], Palette.BG)
		check.call(
			r >= ColorContrast.AA_LARGE,
			"%s vs 背景 = %.2f (>= %.1f)" % [name, r, ColorContrast.AA_LARGE]
		)


## マップの脅威メーターが読めること。長さが主たる符号化で色は補助だが、
## 「どこまで埋まっているか」と「互角の目盛りがどこか」が見えないと長さも読めない。
## 埋まり(敵色)と空き(トラック)、目盛りと両者を、非テキスト図形の 3:1 で確かめる。
## トラック自体は背景に沈まなければよいので 3:1 は課さない(意図的に控えめな色)。
func _test_threat_meter_colors(check: Callable) -> void:
	var pairs := {
		"埋まり vs 空き": [Palette.ENEMY, Palette.MAP_THREAT_TRACK],
		"目盛り vs 空き": [Palette.MAP_THREAT_TICK, Palette.MAP_THREAT_TRACK],
		"目盛り vs 埋まり": [Palette.MAP_THREAT_TICK, Palette.ENEMY],
	}
	for name in pairs:
		var r := ColorContrast.ratio(pairs[name][0], pairs[name][1])
		check.call(
			r >= ColorContrast.AA_LARGE,
			"脅威メーター %s = %.2f (>= %.1f)" % [name, r, ColorContrast.AA_LARGE]
		)

	var vs_bg := ColorContrast.ratio(Palette.MAP_THREAT_TRACK, Palette.BG)
	check.call(vs_bg >= 1.5, "脅威メーターの空き vs 背景 = %.2f (>= 1.5)" % vs_bg)


## マップの柱の印が読めること。印は最大でもノード半径の12%(実測 直径4.3px)の小さな
## 円なので、地(ノード塗り)が明るい緑〜暗い灰と幅広い以上、色だけでは全部の地に
## 対して 3:1 を取れない。読めるかは**縁取り**が担うので、そこを確かめる:
## 縁 vs 印(紫)と、縁 vs 進める先のノード塗り——決断に関わるのは進める先だけ。
## 印の紫は対戦画面の柱と同じ色で、入場した先の土俵と見た目が一致する。
func _test_obstacle_mark_colors(check: Callable) -> void:
	var pairs := {
		"縁 vs 柱の印": [Palette.MAP_OUTLINE, Palette.NEON_VIOLET],
		"縁 vs 進める先のノード": [Palette.MAP_OUTLINE, Palette.MAP_NEXT],
	}
	for name in pairs:
		var r := ColorContrast.ratio(pairs[name][0], pairs[name][1])
		check.call(
			r >= ColorContrast.AA_LARGE,
			"柱の印 %s = %.2f (>= %.1f)" % [name, r, ColorContrast.AA_LARGE]
		)
