class_name ColorContrast
extends RefCounted

## WCAG 2.x のコントラスト比を計算する純粋な静的関数群。Node にも scene にも
## 依存しないので、ヘッドレステストから直接呼べる。
##
## Godot の Color.get_luminance() は使わない。あれは Rec.709 の知覚輝度(sRGB値の
## まま重み付き平均)であって、WCAG が要求する「線形化してから重み付けした相対輝度」
## ではない。ここでは 0.04045 のピースワイズ定義で明示的に線形化する。
##
## 判定のしきい値: 通常テキストは 4.5:1(AA)、大きいテキスト(24px以上、または
## 18.66px以上の太字)と非テキスト図形(SC 1.4.11)は 3:1。

## 通常テキストの AA しきい値。
const AA_NORMAL := 4.5

## 大きいテキスト・非テキスト図形の AA しきい値。
const AA_LARGE := 3.0


## sRGB の 1 チャンネル(0〜1)を線形値へ。WCAG の定義そのまま。
static func _linearize(channel: float) -> float:
	if channel <= 0.04045:
		return channel / 12.92
	return pow((channel + 0.055) / 1.055, 2.4)


## WCAG 相対輝度(0〜1)。α は無視する(地に完全に乗る前提)。
static func relative_luminance(c: Color) -> float:
	return (
		0.2126 * _linearize(c.r)
		+ 0.7152 * _linearize(c.g)
		+ 0.0722 * _linearize(c.b)
	)


## 2色のコントラスト比(1.0〜21.0)。順序に依存しない。
static func ratio(a: Color, b: Color) -> float:
	var la := relative_luminance(a)
	var lb := relative_luminance(b)
	var hi := maxf(la, lb)
	var lo := minf(la, lb)
	return (hi + 0.05) / (lo + 0.05)


## fg と bg のコントラストが threshold 以上か。
static func meets(fg: Color, bg: Color, threshold: float = AA_NORMAL) -> bool:
	return ratio(fg, bg) >= threshold
