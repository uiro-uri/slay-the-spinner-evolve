class_name DiscGradient
extends RefCounted

## コマ本体を単色ではなく直線グラデーションで塗るための純粋関数。
##
## 本体を単色で塗ると、回転の手がかりは白マーク・尾・オーラだけで、本体そのものは
## 回っている情報を持たない。そこで本体へ**一方向(直線)のグラデーション**を乗せ、
## コマのローカル座標系(rotationが乗る系)に描くことで、コマと一緒にグラデーションが
## 回り、本体からも回転が読めるようにする。方向は放射状ではなく直線。
##
## 明度の振れ方は陣営で固定する:
##  - プレイヤー(toward_light=true) : 基準色 → 明るい基準色(明度を上げる)
##  - 敵      (toward_light=false): 基準色 → 暗い基準色(明度を下げる)
##
## 片端は必ず基準色(Palette.PLAYER / ENEMY)なので、コマの識別色は保たれる。
##
## **Nodeにもシーンにも乱数にも依存しない純粋関数。** spin_aura.gd /
## telegraph_wobble.gd と同じ設計。_draw() に数式を埋めるとテストできないので、
## 端点と補間だけをここへ切り出す。tests/test_disc_gradient.gd が固定する。

## プレイヤー側の遠端の明るさ上げ量(Color.lightenedの引数)。
const BRIGHTEN := 0.5

## 敵側の遠端の暗さ下げ量(Color.darkenedの引数)。
const DARKEN := 0.5


## グラデーションの2端点。near は必ず基準色そのまま、far は陣営に応じて明側/暗側。
## alpha は base のものを保つ(lightened/darkened は alpha を触らない)。
static func endpoints(base: Color, toward_light: bool) -> Dictionary:
	var far := base.lightened(BRIGHTEN) if toward_light else base.darkened(DARKEN)
	return {"near": base, "far": far}


## 端点間を t(0=near=基準色, 1=far)で線形補間した色。t は [0,1] にクランプする。
## Disc 側はリム各頂点でこれを呼び、直線グラデーションの頂点色を作る。
static func sample(base: Color, toward_light: bool, t: float) -> Color:
	var e := endpoints(base, toward_light)
	return (e.near as Color).lerp(e.far as Color, clampf(t, 0.0, 1.0))
