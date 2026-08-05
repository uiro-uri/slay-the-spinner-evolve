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


## 土俵1ユニットあたりの表示px。土俵の広さ(ユニット)が土俵ごとに違っても、
## 画面上の正方形は arena_px のまま動かないようにするための倍率。
##
## かつては「1ユニット=50px」の決め打ちで、10x10以外の土俵を渡すと画面から
## はみ出した(FieldData.arena_boundsは土俵ごとの値なのに、描画側だけが10x10を
## 前提にしていた)。広い土俵ほどコマが小さく映る＝広さがそのまま絵に出る。
static func arena_unit_scale(bounds_size: Vector2, arena_px: float) -> float:
	var span: float = maxf(bounds_size.x, bounds_size.y)
	if span <= 0.0:
		return 1.0
	return arena_px / span


## スケール後サイズ scaled を visible 内に置くときの左上座標。
## h_bias/v_bias は 0.5 で中央、0.7 で右/下寄り。負の余白は 0 に丸めて画面外へ出さない。
static func placement(scaled: Vector2, visible: Vector2, h_bias: float, v_bias: float) -> Vector2:
	var slack := Vector2(maxf(0.0, visible.x - scaled.x), maxf(0.0, visible.y - scaled.y))
	return Vector2(slack.x * h_bias, slack.y * v_bias)


## 高さ block_h の行の塊を、高さ span の領域の上端からの相対位置で置くときの
## 上端オフセット。基本は span の bias 倍の位置だが、塊の下端が span を越えるなら
## 越えない位置まで押し上げる(span より塊が高ければ 0＝上端に貼り付く)。
##
## 対戦画面のリザルトはメッセージ＋数行をアリーナの上に重ねるが、**行の高さは画面に
## 依らない固定px**なのに**アリーナは端末幅で縮む**ので、細い端末ほど塊が下へはみ出して
## 直下のバー帯へ食い込む。行を1本増やしたときに SP幅360 で 4行目がバーに重なる計算に
## なったのがこれを入れた理由(実測できない=Battle.gdは自動読み込みに依存していて
## ヘッドレスで実体化できないので、規則をここへ出して純粋関数として固定する)。
static func stack_top(span: float, block_h: float, bias: float) -> float:
	return minf(span * bias, maxf(span - block_h, 0.0))
