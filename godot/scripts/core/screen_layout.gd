class_name ScreenLayout
extends RefCounted

## 画面レイアウトの純粋関数。Node非依存なのでヘッドレステストから直接呼べる。
##
## ゲームは1280x720の横画面設計 + stretch=canvas_items/expand。スマホ縦画面では
## 視野が下へ拡張され(base単位で概ね1280x2770)、上端固定のコンテンツが上に貼り付き
## 左右が大きく空く。縦画面のときだけコンテンツを幅いっぱいへ拡大し、中央やや下へ
## 置き直すために、この判定と当てはめ計算をここへ集約する。
##
## 横画面(設計比16:9)では is_portrait が false になり、各画面はシーン既定へ戻す。
## つまり縦画面専用の変換で、横の見た目は一切変えない。

## 設計解像度。判定と当てはめの基準。
const DESIGN := Vector2(1280.0, 720.0)


## 設計比(16:9)より縦長か。visible は get_viewport().get_visible_rect().size
## (canvas_items stretch では base 単位)を渡す。ちょうど16:9は横画面扱い(false)。
## 除算を避けて交差積で比べる(visible.x>0 前提)。
static func is_portrait(visible: Vector2) -> bool:
	return visible.y * DESIGN.x > visible.x * DESIGN.y


## content(設計時のbbox)を target 領域へ、アスペクト比を保ったまま収める倍率。
## 幅と高さのうち厳しい方に合わせるので、拡大してもはみ出さない。
static func fit_scale(content: Vector2, target: Vector2) -> float:
	if content.x <= 0.0 or content.y <= 0.0:
		return 1.0
	return minf(target.x / content.x, target.y / content.y)


## スケール後サイズ scaled を visible 内に置くときの左上座標。
## h_bias/v_bias は 0.5 で中央、0.7 で右/下寄り。負の余白は 0 に丸めて画面外へ出さない。
static func placement(scaled: Vector2, visible: Vector2, h_bias: float, v_bias: float) -> Vector2:
	var slack := Vector2(maxf(0.0, visible.x - scaled.x), maxf(0.0, visible.y - scaled.y))
	return Vector2(slack.x * h_bias, slack.y * v_bias)
