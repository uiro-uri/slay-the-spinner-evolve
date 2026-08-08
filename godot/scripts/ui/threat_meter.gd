class_name ThreatMeter
extends RefCounted

## マップのノードに出す「この部屋は自分より硬いか」のメーター。
## Node にもシーンにも乱数にも依存しない純粋関数だけ(cf. scripts/core/map_glow.gd)。
##
## 動機はコールドプレイの一次証拠。マップは「Lv3 2体」としか言わない。段1〜4を
## 残りrps 50%前後で快勝した直後、段5(Lv3×2体)で4連敗して残機を使い切ったが、
## **負けて初めて**相手の硬さが 1.5〜1.8(自分は 0.735)だと知った。レベルの数字は
## 1つ上がっただけに見えるのに、実測の硬さは Lv1 0.12 → Lv2 0.47 → Lv3 1.7 →
## Lv4 3.9 → Lv5 12.5 とレベルごとに3〜4倍動く。自分の硬さはラン全体でも
## 0.735 → 1.7 しか動かないので、**この非対称が可視化されないと部屋を選べない**。
##
## 2026-08-02 のサイクルが同じ穴を対戦画面のビルド表示(StatReadout.enemy_rows)で
## 塞いだが、**部屋を選ぶ決断はその1画面手前のマップで起きる**。戦闘画面で
## 「格上だ」と分かっても、そのときにはもう引き返せない。
##
## 値は StatReadout.endurance_share をそのまま呼ぶ。部屋の脅威の定義が2箇所に
## あると、マップと対戦画面で違う脅威を出すことになる(対戦画面の enemy_rows も
## 1行目がこれ)。取り分 敵/(自分+敵) なので上端を決め打たずに済み(打たれ強さは
## 1000倍動くので絶対レンジのバーでは Lv3 以上が全部満タンに張り付く)、
## 互角でちょうど StatReadout.PARITY。
##
## **軸は硬さから打たれ強さへ移した**(2026-08-08 深夜)。硬さ(質量×半径²)は
## 1接触で削られる rps の分母でしかなく、**rps を一切読まない**。先に回転が尽きた方が
## 負けるゲームなので、それだけでは部屋を抜けられるかを答えられない。実測では
## 硬さを固定して自機の rps だけを振ると Lv2×2体の勝率が 34%→99% と動くのに、
## 硬さ取り分は 0.51 で不動だった(playtest/measure_threat_axis.gd)。
## 理由と一次証拠の全文は StatReadout.endurance_share の doc に置いてある。
##
## **部屋の硬さは頭数ぶんの和**(2026-08-03 のサイクル)。それ以前は群の最大だったので、
## **同じレベルなら1体でも3体でもメーターが同じ長さ**になっていた。頭数はピップで
## 別に描かれてはいたが、「格上か格下か」を言い切っているのはこのメーターの側で、
## そこに頭数が一切入っていなかった。コールドプレイで段5の「Lv3 2体(0.65)」を
## 隣の「Lv3 1体(0.63)」と同程度の危険度だと読んで選び、残機5を全部溶かしている
## (実測の勝率は 91.2% と 24.8%)。頭数と硬さは別の軸ではなく、同じ「部屋の脅威」の
## 成分なので、1本のメーターに合算する。単体の部屋では値は1つも変わらない。
##
## **進める先のノードにだけ出す**。遠いノードの取り分は「今のビルド」との比なので、
## そこへ着く頃には嘘になっている(段9のボスは今の自分なら 0.88 で「絶望」と
## 読めるが、育ってから戦う相手だ)。決断に関係するのは進める先だけ。
##
## テレグラフの揺らぎは損なわない。揺らして隠しているのは出現位置と向き=この一戦の
## 計画で、硬さは個体の静的な性能。どこへ飛ぶかは相変わらず読み切れない。

## メーターをノード下辺からどれだけ下に置くか(中心のy。敵数ピップのさらに外側)。
## ノード半径18・ピップが半径+6 なので、ピップの下端(+8.6)と次の段のノードの
## 報酬ピップの上端(+35.4)の隙間の真ん中あたりに来る。
const TRACK_OFFSET := 13.0
## メーターの高さ(px)。幅はノードの直径そのもの(どのノードの話かを迷わせない)。
const TRACK_HEIGHT := 3.0
## 互角の目盛りがメーターの上下へはみ出す量(px)。埋まりの先端と見間違えないよう、
## 目盛りだけ縦に長くする。
const TICK_EXTRA := 1.5
## 互角の目盛りの太さ(px)。
const TICK_WIDTH := 1.5


## 敵グループ(EnemyData)から stats を取り出す。null は捨てる。
## Main._pending_enemy_stats と同じ変換だが、あちらは GameState.pending_enemies
## (=入場が確定した相手)、こちらはマップ上のまだ選んでいないノードが相手。
static func stats_of(enemies: Array[EnemyData]) -> Array[SpinnerStats]:
	var out: Array[SpinnerStats] = []
	for enemy in enemies:
		if enemy != null and enemy.stats != null:
			out.append(enemy.stats)
	return out


## この部屋の脅威(相手の打たれ強さの取り分)。
## 定義は対戦画面の「打たれ強さ 相手」の行と共有する。
static func share(player: SpinnerStats, enemies: Array[EnemyData]) -> float:
	return StatReadout.endurance_share(player, stats_of(enemies))


## 進める先のうち**戦闘ノードだけ**の脅威。座標 → 取り分。
##
## 描画とテストがこの1本を通るようにしてある。「どのノードに出すか」は見た目では
## なく判断の規則なので、_draw() に埋めるとテストできない。
static func reachable_shares(tree: MapTree, player: SpinnerStats) -> Dictionary:
	var out: Dictionary = {}
	if tree == null:
		return out
	for coord in tree.next_coords():
		if not tree.nodes.has(coord):
			continue
		var node: MapTree.MapNode = tree.nodes[coord]
		if not node.has_encounter():
			continue
		out[coord] = share(player, node.enemies)
	return out


## 進める先の部屋に居る**いちばん硬い1体のステータス**。相手が居なければ null。
##
## 報酬画面の攻めの2行(PartPreview.attack / knockback)の基準にする相手。攻め力は
## 「1接触で相手から削れるrps」なので、基準も**1体**でなければならない
## ——部屋の脅威(room_toughness)が頭数ぶんの和なのは「この部屋を抜けられるか」の
## 話だからで、1回の噛み合いの相手はそのうちの1体でしかない。和を渡すと
## 3体の部屋で攻め力が1/3に見え、乱戦ほど攻め札が無価値だという逆の嘘になる。
##
## 進める先ぜんぶのうち**いちばん硬い1体**を採るのは、どのノードへ進むかが
## まだ決まっていないから(報酬はマップへ戻る手前で選ぶ)。最も硬い相手を基準に
## すれば見積もりは控えめに出る——攻め札を過大評価して「通るはずが通らない」
## という外し方をしない向きに倒す。
##
## reachable_shares と同じく**進める先の戦闘ノードだけ**を見る。遠いノードを
## 混ぜないのはあちらと同じ理由で、そこへ着く頃には今のビルドとの比が嘘になる。
##
## **硬さだけでなく1体まるごと返す**(2026-08-08)。弾きの行(PartPreview.knockback)は
## 相手の質量・半径・反発・衝突軽減も読むので、硬さのスカラーでは足りない。
## 攻めの2行が**同じ1体**を見ていることを型で保証するために、選んだ相手をそのまま返す。
static func reachable_hardest_stats(tree: MapTree) -> SpinnerStats:
	var hardest: SpinnerStats = null
	var hardest_toughness := -1.0
	if tree == null:
		return hardest
	for coord in tree.next_coords():
		if not tree.nodes.has(coord):
			continue
		var node: MapTree.MapNode = tree.nodes[coord]
		if not node.has_encounter():
			continue
		for stats in stats_of(node.enemies):
			var t := PartPreview.toughness(stats)
			if t > hardest_toughness:
				hardest_toughness = t
				hardest = stats
	return hardest


## 上の1体の硬さ。相手が居なければ -1.0。硬さしか要らない呼び手のための薄い包み。
static func reachable_hardest_toughness(tree: MapTree) -> float:
	var hardest := reachable_hardest_stats(tree)
	if hardest == null:
		return -1.0
	return PartPreview.toughness(hardest)


## メーターの外枠。ノード中心と(ホバーで膨らんだあとの)半径から決まる。
## node_radius と center は既に縦画面の拡大率が掛かった実効値、draw_scale は
## 装飾px(オフセットや太さ)に掛けるぶん —— MapScreen の PIP_OFFSET と同じ流儀。
static func track_rect(center: Vector2, node_radius: float, draw_scale: float) -> Rect2:
	var h := TRACK_HEIGHT * draw_scale
	var w := node_radius * 2.0
	var mid_y := center.y + node_radius + TRACK_OFFSET * draw_scale
	return Rect2(center.x - w * 0.5, mid_y - h * 0.5, w, h)


## 埋まっている部分。左詰めで、取り分に比例する。範囲外は端で頭打ち。
static func fill_rect(track: Rect2, share_value: float) -> Rect2:
	var w := track.size.x * clampf(share_value, 0.0, 1.0)
	return Rect2(track.position, Vector2(w, track.size.y))


## 互角の目盛り(縦線)。取り分なので必ず幅のちょうど中央に立つ。
static func parity_rect(track: Rect2, draw_scale: float) -> Rect2:
	var extra := TICK_EXTRA * draw_scale
	var w := TICK_WIDTH * draw_scale
	var x := track.position.x + track.size.x * StatReadout.PARITY
	return Rect2(x - w * 0.5, track.position.y - extra, w, track.size.y + extra * 2.0)
