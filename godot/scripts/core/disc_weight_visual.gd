class_name DiscWeightVisual
extends RefCounted

## 質量(重さ)をコマの見た目へ写す純粋関数集。
##
## 敵の性能のうち、半径はコマの大きさ・rpsはゲージと回転の尾・速度は予告の
## 長さで見えるのに、質量だけは画面のどこにも出ていなかった。質量は衝突の
## 削り(硬さ=質量×半径²に反比例)と弾き(壁へ飛ばせるかどうか)の両方を支配する
## 主要な読み合い材料で、これが見えないと「壁へ弾き飛ばして仕留める」戦法が
## 撃つまで分からない賭けになる(コールドプレイでLv4/ボスの巨体相手に実際に
## そうなった)。
##
## そこで重いコマほど縁のリムを太く描く。「重い=分厚い縁」の比喩で、
## プレイヤーのコマにも同じ規則で描くため、質量パーツで自分が重くなるのも
## 見えるし、敵との相対比較(自分より分厚い=弾き合いで負ける)が一目でできる。
##
## Nodeに依存しない純粋関数なのでヘッドレスから直接テストできる。


## リム太さの写像の天井となる質量。パーツの質量上限(CustomPartCatalog.MASS_CAP)
## と同じ値で、敵の最重量(ボス帯)もこの中に収まる。値の一致はテストが照合する
## (coreからdata層への参照を作らないためhere重複で持つ)。
const MASS_FULL := 8.0

## リムの太さ(半径に対する割合)の下限と上限。
## 下限: 最軽量(Lv1の0.6前後)でも「縁がある」ことは見える。
## 上限: 回転の尾(Disc.TAIL_WIDTH_RATIO=0.28)より細く保ち、回転の情報を覆わない。
const MIN_RATIO := 0.05
const MAX_RATIO := 0.22

## リムの明度の落とし幅。本体より暗い縁にして、回転マーク(明るい)と取り違えない。
const RIM_DARKEN := 0.45


## 質量→リム太さ(半径に対する割合)。質量に対して単調増加で、両端はクランプ。
static func rim_ratio(mass: float) -> float:
	return lerpf(MIN_RATIO, MAX_RATIO, clampf(mass / MASS_FULL, 0.0, 1.0))


## リムの実太さ(ユニット)。半径に比例するので、大きくて重いコマほど
## 物理的にも分厚い縁になる(硬さ=質量×半径²の直感と揃う)。
static func rim_width(mass: float, radius: float) -> float:
	return rim_ratio(mass) * radius


## リムの色。本体の基準色(敗北時は暗転済みの色)から作るので、状態変化に追従する。
static func rim_color(base: Color) -> Color:
	return base.darkened(RIM_DARKEN)
