class_name FinishFocus
extends RefCounted

## 決着を付けたコマ同士の衝突に合わせて、カメラを衝突点へ寄せてスローにする
## 「フィニッシュ演出」の計算。Nodeにもシーンにも依存しない純粋な静的関数だけを
## 置く（TelegraphWobbleと同じ流儀）。Battle.gdはこれを呼んで表示に反映するだけで、
## BattleResolver/BattleResultの計算やシリアライズには一切触れない。
##
## resolverは決着が立つステップで即returnするので、impactsの末尾が最後のコマ衝突。
## 決着はdrainの1ステップ後にfinish_timeが確定するため、決着衝突は概ねfinish_time
## 直前にある。末尾衝突がfinish_timeから十分近いときだけ「決着衝突」と見なす。


## 演出の起点にする決着衝突の時刻を返す。該当しなければ -1（＝演出なし）。
##
## 末尾のコマ衝突がfinish_timeからwindow秒以内にあり、かつ時間切れで終わって
## いないときだけ採用する。消耗戦(最後の衝突がずっと前)や時間切れでは -1 を返し、
## 素の再生に任せる。
static func decisive_impact_time(result: BattleResult, window: float) -> float:
	if result == null or result.timed_out or result.impacts.is_empty():
		return -1.0
	var last_time: float = result.impacts[result.impacts.size() - 1].time
	if result.finish_time - last_time > window:
		return -1.0
	return last_time


## 決着衝突の接触点(アリーナのユニット系)。impactsが空なら原点。
static func decisive_impact_point(result: BattleResult) -> Vector2:
	if result == null or result.impacts.is_empty():
		return Vector2.ZERO
	return result.impacts[result.impacts.size() - 1].point


## 時刻tでの演出の強さ(0〜1)。decisive_time-lead で 0、decisive_time で 1 に達し、
## 以後は 1 に張り付く。区間内はsmoothstepで滑らかにイーズインする。
## decisive_time が負(演出なし)なら常に 0。
static func strength_at(t: float, decisive_time: float, lead: float) -> float:
	if decisive_time < 0.0:
		return 0.0
	if lead <= 0.0:
		return 1.0 if t >= decisive_time else 0.0
	return smoothstep(decisive_time - lead, decisive_time, t)


## 強さstrengthに応じたArenaRootの変換(position/scale)を返す。
##
## strength=0 で base変換そのまま(恒等)。strength=1 で focus_world がビューポート
## 中心に来て base_scale*zoom 倍になる。途中は focus_world のスクリーン位置を
## base位置→中心へ、倍率を 1→zoom へ補間する。UIは別CanvasLayerなので影響しない。
##
## base_scale/zoom は成分ごとに掛ける。写像は screen = position + scale*world。
static func arena_transform(
	base_pos: Vector2,
	base_scale: Vector2,
	focus_world: Vector2,
	viewport_size: Vector2,
	zoom: float,
	strength: float
) -> Dictionary:
	var z := lerpf(1.0, zoom, strength)
	var scale := base_scale * z
	var focus_at_base := base_pos + base_scale * focus_world
	var viewport_center := viewport_size * 0.5
	var focus_screen := focus_at_base.lerp(viewport_center, strength)
	var position := focus_screen - scale * focus_world
	return {"position": position, "scale": scale}
