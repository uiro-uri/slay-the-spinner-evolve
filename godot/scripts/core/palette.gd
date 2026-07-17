class_name Palette
extends RefCounted

## ゲーム全体の配色の唯一の出所。ネオン・オン・深藍の現代的なテーマ。
##
## 色はもともと各シーンの const にばら撒かれていて、テキストとステージが
## 低コントラストで衝突していた(白文字がほぼ白の床の上に乗る等)。ここへ集約し、
## テキストは常に地に対してコントラストの取れる色＋縁取りで読ませる。
##
## Godotの .theme リソースは Control ノードしかスタイルできず、_draw() の手描き色
## には届かない。だから唯一の出所は Theme ではなくこの GDScript の const にする。
## 各描画スクリプトは `const XXX := Palette.YYY` で参照する(グローバル class_name の
## const は解析時に畳み込まれるので有効)。
##
## 色の妥当性は ColorContrast と tests/test_contrast.gd が WCAG 比で担保する。
## 値をいじったらテストが低コントラストを弾く。決して new() しない定数置き場。

# --- 構造色(暗い土台) ---

## 既定クリア色・メニュー背景。最も暗い藍。
const BG := Color("0e0b1a")

## パネル/バーなどの面。BGより一段明るい。
const SURFACE := Color("191433")

## 土俵の床。旧 f0f0f0(ほぼ白)を置換。ネオンが映える暗紫。
const FLOOR := Color("201a3d")

## すり鉢の底を示す同心円。暗い床の上なので白を薄く乗せる(旧は黒0.08)。
const FLOOR_MARK := Color(1, 1, 1, 0.06)

# --- ネオン差し色 ---

## 壁の輪郭・壁スパーク。旧 d98cd9。
const NEON_MAGENTA := Color("ff2e9a")

## 障害物。旧 b58cd9。
const NEON_VIOLET := Color("b26bff")

## 障害物の内側ハイライト。旧 d9c4f0。
const NEON_VIOLET_HI := Color("dab6ff")

## プレイヤーのコマ。旧 3498db。
const PLAYER := Color("21e6ff")

## 敵のコマ・敵の予告三角形。旧 e74c3c 系。
const ENEMY := Color("ff3b5c")

## プレイヤーの狙い/照準の緑。敵の予告(赤)と対。旧 純緑(0,1,0)は白床で沈んでいた。
const AIM := Color("3bff88")

## レア報酬カードの地。意図的に明るいまま据え置く。上の文字は TEXT_ON_LIGHT。
const GOLD_CARD := Color("ffcc00")

## コマ衝突スパークの開始色。旧 (1,0,1)。
const SPARK_START := Color("ff39c3")

## コマ衝突スパークが抜ける先。透明。旧 (1,1,0.49,0) 据え置き。
const SPARK_END := Color(1, 1, 0.49, 0)

## コマ上の回転マーク。コマ本体(明色)の上に乗るので白。α は呼び出し側で付ける。
const SPIN_MARK := Color(1, 1, 1)

# --- 文字色 ---

## 明るい文字。メニュー既定色に近く、戦闘メッセージにも使う。
const TEXT_PRIMARY := Color("f3f0ff")

## 明色文字の背後の縁取り。ほぼ黒。どんな地の上でも文字を浮かせる。
const TEXT_OUTLINE := Color("0b0818")

## 金/明るい地の上に置く暗色文字。旧 RewardScreen の (0.15,0.12,0) 相当。
const TEXT_ON_LIGHT := Color("241a00")

## 戦闘メッセージの縁取りの太さ(px)。
const MESSAGE_OUTLINE_SIZE := 6

# --- マップ(暗い背景の上のネオン) ---

const MAP_LINE := Color("6e6aa8", 0.55)
const MAP_VISITED := Color("6e7bc8")
const MAP_CURRENT := Color("3bb0ff")
const MAP_NEXT := Color("3bff88")
const MAP_PLAIN := Color("5a5a78")
const MAP_PATH := Color("5bff9a", 0.9)
const MAP_GLOW := Color("3bff88")
const MAP_HOVER_RING := Color("cfffe0")
const MAP_CURRENT_RING := Color("6ed8ff", 0.9)
const MAP_OUTLINE := Color("0b0818", 0.85)
