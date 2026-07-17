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
