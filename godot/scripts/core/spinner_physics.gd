class_name SpinnerPhysics
extends RefCounted

## コマ同士のぶつかり合いの計算。すべて純粋な静的関数で、Nodeにもシーンにも
## 依存しないため、ヘッドレステストから直接呼べる。
##
## 式はプロトタイプ(archive/flask-prototype/simulation.py)を出発点にしているが、
## 数値は引き継がない。「コマらしく動くか」を基準に呼び出し側で調整する。
##
## これはゲームのための嘘物理であり、系全体としての保存則は成り立たない。
## 特にspin_kickは回転をエネルギー源にして運動を足すので、エネルギーは増える。
## 個々の関数のテストで保存を確認している箇所があるが、それはその関数単体の
## 性質（式が正しいか）を見ているだけで、ゲームの設計上の制約ではない。
## 手触りのために保存を破る変更は歓迎されるべきで、テストの方を直すこと。
##
## プロトタイプから意図的に変えた点:
##  - 衝突時の回転キックを、互いに引き寄せる向きから弾き合う向きに変えた。
##    プロトタイプは両者を近づける符号になっており、弾性衝突の反発を
##    打ち消していた。「角運動量→運動量」というコメントの意図と逆。
##  - 同キックで相手側にも自分の半径とRPS減少量を使っていたのを対称にした。


## ステージの形。ベイブレードのスタジアムのように中央へ向かって傾斜している。
enum StageShape {
	## 放物面のすり鉢。中心から離れるほど傾斜が急になる。実物のスタジアムに近い。
	## プロトタイプのコードが実際にやっていた挙動。
	DISH,
	## 一定傾斜の円錐。どこでも同じ角度で中心へ滑り落ちる。
	## プロトタイプの g = 9.81*sin(30°) という定数はこちらの意図を示唆する。
	CONE,
}


## ステージの傾斜でコマが中央へ滑り落ちる加速度。
##
## DISH: 変位に比例する（放物面のすり鉢＝バネと同じ式）。中心付近は緩やかで
##       外側ほど強く戻される。
## CONE: 大きさ一定で中心を向く（一定傾斜の斜面を滑る成分）。
static func stage_slope_accel(
	pos: Vector2, center: Vector2, strength: float, shape: StageShape = StageShape.DISH
) -> Vector2:
	var toward_center := center - pos
	if shape == StageShape.CONE:
		# normalized()はゼロベクトルにゼロを返すので、中心では力ゼロになる。
		return strength * toward_center.normalized()
	return strength * toward_center


## 土俵の傾斜の効き目を、コマ側の低重心(slope_grip)で強めた実効の強さ。
## grip=1.0で従来どおり、1.5なら中心へ引き戻す力が1.5倍になる。
##
## 傾斜は「土俵の性質」なので本来コマごとに違うのは嘘だが、この物理は
## 元から嘘物理(冒頭のコメント参照)で、低重心のコマほど斜面をよく捉える、
## という手触りの側を採る。壁対策の軸をここに置くのは、壁での喪失が
## 進入速度に比例する(impact_scaled_wall_damping)ため:
## 中心へ強く引かれるコマは壁へ届く距離も届いたときの速さも落ちる
## ——「当たっても軽くする」wall_keep(Rage Reflection)とは別の機構になる。
## 負のgripは中心から遠ざかる向きに反転してしまうので0でクランプする
## (デバフ札を置かないカタログの原則と同じ向き)。
static func gripped_slope_strength(base: float, slope_grip: float) -> float:
	return base * maxf(slope_grip, 0.0)


## 進行方向と逆向きの一定減速度。
## 停止時はゼロが返る。GodotのVector2.normalized()はゼロベクトルに対して
## ゼロを返すので、プロトタイプのnumpyのように0除算でnanにはならない。
static func friction_accel(vel: Vector2, decel: float) -> Vector2:
	return -decel * vel.normalized()


## 2体が接触していて、かつ近づいているか。離れていく最中の再衝突を防ぐ。
static func is_colliding(
	pos_a: Vector2, radius_a: float, vel_a: Vector2,
	pos_b: Vector2, radius_b: float, vel_b: Vector2
) -> bool:
	if pos_a.distance_squared_to(pos_b) > (radius_a + radius_b) ** 2:
		return false
	return (vel_a - vel_b).dot(pos_a - pos_b) < 0.0


## 反発係数付き衝突後の速度を [a, b] で返す。
##
## restitution=1.0 で完全弾性衝突（従来の挙動と厳密一致）。1未満で非弾性になり、
## 中心線方向の分離速度が e 倍に落ちる（e=0で法線方向に一体化）。一般化は
## 弾性の係数 2 を (1+e) に置き換えるだけ。壁のrestitutionと同じ意味の係数を
## コマ同士の衝突にも効かせるための引数（Rage Reflectionの想定）。
## e>1は壁と同様に衝突ごとに加速して発散するので、呼び出し側で[0,1]にクランプする。
static func elastic_velocities(
	pos_a: Vector2, vel_a: Vector2, mass_a: float,
	pos_b: Vector2, vel_b: Vector2, mass_b: float,
	restitution: float = 1.0
) -> Array[Vector2]:
	var delta := pos_a - pos_b
	var dist_sq := delta.length_squared()
	if dist_sq < 1e-12:
		# 完全に重なっていると向きが定まらない。何もしない方が安全。
		return [vel_a, vel_b]

	var total_mass := mass_a + mass_b
	# 中心線方向の相対速度成分だけを、質量比と反発係数に応じて交換する。
	var impulse := (vel_a - vel_b).dot(delta) / dist_sq * delta
	var factor := 1.0 + restitution
	var new_a := vel_a - (factor * mass_b / total_mass) * impulse
	var new_b := vel_b + (factor * mass_a / total_mass) * impulse
	return [new_a, new_b]


## 衝突で削られるRPS量。相手が重く速いほど大きく、自分が重く大きいほど小さい。
static func spin_drain(
	opponent_mass: float, opponent_speed: float,
	own_mass: float, own_radius: float, violence: float
) -> float:
	if own_mass <= 0.0 or own_radius <= 0.0:
		return 0.0
	return violence * (opponent_mass * opponent_speed) / (own_mass * own_radius * own_radius)


## 回転が並進運動に変わって弾き合う分の速度。相手から離れる向きに働く。
## 完全に重なっている時は向きが定まらないが、normalized()がゼロを返すので
## 結果もゼロになる。
static func spin_kick(
	pos_self: Vector2, pos_other: Vector2, own_radius: float, drain: float, scale: float
) -> Vector2:
	return scale * own_radius * drain * (pos_self - pos_other).normalized()


## 壁にめり込んでいて、かつ壁に向かって進んでいるか。
## normalはアリーナ内側を向いた単位ベクトル。
static func wall_hit(
	wall_point: Vector2, wall_normal: Vector2,
	pos: Vector2, vel: Vector2, radius: float
) -> bool:
	if wall_normal.dot(pos - wall_point) >= radius:
		return false
	return wall_normal.dot(vel) < 0.0


## 壁へめり込んでいる深さ。めり込んでいなければ0。
## 法線方向にこの量だけ戻すと、コマの縁がちょうど壁面に接する。
##
## 反射は速度しか変えないので、めり込んだ位置はそのまま次のステップへ持ち越される。
## それでも普通の跳ね返りは離れていくので問題にならないが、コマより狭い隙間
## (柱と壁の隅など)では「どちらの面からも出られない位置」に居座ることになり、
## すり鉢に押し戻されるたび衝突が再点火して毎フレームrpsを取られる。実測では
## 敵1体が柱(7,7)と右壁の間でxを8.75↔8.85と往復しながら0.27秒で27.2→15.7rpsを
## 失った(コールドプレイ2026-08-03: 段7で接触0回・壁54回の敗北)。
## 深さを解いておけば、隙間より大きいコマは両面から押されて隙間の外へ絞り出される。
static func wall_penetration(
	wall_point: Vector2, wall_normal: Vector2, pos: Vector2, radius: float
) -> float:
	return maxf(wall_gap(wall_point, wall_normal, pos, radius), 0.0)


## 壁との符号付きの深さ。正でめり込み、0でちょうど接触、負なら壁までその距離ある。
## wall_penetrationは押し出し量なので0で切るが、「接したままか」を見る側は
## 離れているのか乗っているのかを区別する必要があるので符号を落とさない版を使う。
static func wall_gap(
	wall_point: Vector2, wall_normal: Vector2, pos: Vector2, radius: float
) -> float:
	return radius - wall_normal.dot(pos - wall_point)


## 柱へめり込んでいる深さ。wall_penetrationの柱版で、法線は柱の中心からの放射方向。
static func obstacle_penetration(
	obstacle_center: Vector2, obstacle_radius: float, pos: Vector2, radius: float
) -> float:
	return maxf(obstacle_gap(obstacle_center, obstacle_radius, pos, radius), 0.0)


## 柱との符号付きの深さ。wall_gapの柱版。
static func obstacle_gap(
	obstacle_center: Vector2, obstacle_radius: float, pos: Vector2, radius: float
) -> float:
	return (obstacle_radius + radius) - pos.distance_to(obstacle_center)


## 壁で反射した後の速度。restitutionで勢いが変わる。
static func wall_bounce(vel: Vector2, wall_normal: Vector2, restitution: float) -> Vector2:
	return vel.bounce(wall_normal) * restitution


## 壁での実効rpsダンピング。wall_keep(0..1)のぶんだけ無損失(1.0)へ寄せる。
## wall_keep=0で従来のbase、1で1.0(壁でrpsを失わない)。Rage Reflectionが上げる。
static func effective_wall_damping(base: float, wall_keep: float) -> float:
	return base + (1.0 - base) * clampf(wall_keep, 0.0, 1.0)


## 壁ダンピングを衝突の激しさ(壁法線方向の進入速度)でスケールした値。
## 従来は壁に触れるだけで一律 base 倍(0.75なら25%喪失)で、そっと縁を擦った
## 接触と全力の激突が同じ代償だった。その理不尽さが「壁こそが真の敵」の手触りと
## 「当てにいかず低速で待つのが最適」という逆立ちした戦略の原因になっていたので、
## normal_speed が ref_speed 以上の激突でちょうど base(従来どおり)、それ未満は
## 無損失(1.0)へ線形に寄せる。ref_speed<=0 は速度スケール無効=常に base
## (旧挙動と厳密一致。古い保存データの再現用)。
static func impact_scaled_wall_damping(
	base: float, normal_speed: float, ref_speed: float
) -> float:
	if ref_speed <= 0.0:
		return base
	return lerpf(1.0, base, clampf(normal_speed / ref_speed, 0.0, 1.0))


## 衝突で受けるrps削りの実効値。hit_guard(0..1)のぶんだけ削りを打ち消す。
## 壁のeffective_wall_dampingと対になる、コマ同士の衝突版の防御(Shock Absorber)。
## 削りが減るぶんspin_kick(削り量に比例する弾き)も弱まる=回転を守る代わりに
## 逃げの弾きも小さくなる。
static func guarded_spin_drain(drain: float, hit_guard: float) -> float:
	return drain * (1.0 - clampf(hit_guard, 0.0, 1.0))


## 攻め手のedge(0..)のぶんだけ、相手に与えるrps削りを増やす。edge=0.2で+20%。
## guarded_spin_drain(受け手の軽減)と対になる攻め側の係数で、両方掛かるときは
## 乗算なので順序によらない。負のedgeは0でクランプ(削りを減らす方向には使わない。
## デバフ札を置かないカタログの原則と同じ向き)。
##
## pierce_drainは「相手が攻め手自身と同じ硬さだったときの素の削り」
## (spin_drainに自分の質量・半径を渡した値)。素の削りは相手の硬さ(質量×半径²)に
## 反比例するため、巨体相手ではedgeの乗算ボーナスがほぼゼロに消え、攻め札が
## 終盤に無価値になる非対称があった(edge=0.60でもLv4に約0.2/hit)。edgeのボーナス
## 基準を maxf(drain, pierce_drain) にすることで、刃の食い込みは相手の硬さで
## 無効化されない: 柔らかい相手には従来どおり(1+edge)倍、硬い相手には
## 自分基準の追加削りが下限になる。pierce_drain=0(既定)は従来の乗算と厳密一致。
static func sharpened_spin_drain(drain: float, edge: float, pierce_drain: float = 0.0) -> float:
	return drain + maxf(edge, 0.0) * maxf(drain, pierce_drain)


## 1回の衝突で奪えるrpsの天井。相手の回転ゲージ(=初期rps)に対する割合で切る。
##
## 素の削りは相手の硬さ(質量×半径²)に反比例するため、柔らかい相手には
## 1撃でゲージ全部を上回る削りが出る。実測(ボット500戦)でLv1戦の勝ちの
## **99.2%が衝突1回**で終わっており、レポートのアラートも段2を
## 「勝率99.7% ほぼ全勝。何をしても勝つので、そこに選択がない」と名指ししている。
## 導入が「ほぼ負けない」のは設計どおりだが、衝突1回では削り・弾き・壁という
## このゲームの噛み合いを1つも見せないまま終わる。
##
## cap_share=0.5 なら「ゲージ満タンの相手を倒すには最低2回噛み合う必要がある」
## が保証される。天井は割合なので、硬い相手(1撃の削りがゲージのごく一部)には
## 一切触れない=Lv3以降の難易度は動かさず、柔らかい相手の即死だけを消す。
##
## 天井は削り(とそれに比例するspin_kick)にだけ効き、弾性衝突の速度交換は素のまま。
## cap_share<=0 で天井なし=旧挙動と厳密一致(古い保存データの再現用)。
static func capped_spin_drain(drain: float, max_rps: float, cap_share: float) -> float:
	if cap_share <= 0.0:
		return drain
	return minf(drain, maxf(max_rps, 0.0) * cap_share)


## 1回の壁(・柱)当たりで失えるrpsの天井。capped_spin_drainの壁版で、式は同じく
## 「回転ゲージ(=初期rps)に対する割合」で切る。
##
## capped_spin_drainだけでは即死が消えない: 接触の削りに天井を置いても、その1撃の
## spin_kickで軽い相手は壁へ飛ばされ、壁の喪失は絶対量(absolute_wall_drain)で
## **自分の硬さに反比例**するため、柔らかい相手ほど1回の壁でゲージが大きく削れる。
## 結果、接触の天井を迂回して壁が即死を肩代わりする(drain_cap_shareの採用時にも
## 「0.34にするとLv1の死因が壁63.1%へ倒れた」として観測されている)。
##
## 天井は壁の喪失にだけ効き、反射(wall_bounce)の速度には触れない=押し込む手応えと
## 壁際の危険はそのまま。割合の天井なので硬い相手(1回の壁がゲージのごく一部)には
## 一切触れず、柔らかい相手の壁即死だけを消す。
## cap_share<=0 で天井なし=旧挙動と厳密一致(古い保存データの再現用)。
static func capped_wall_drain(drain: float, max_rps: float, cap_share: float) -> float:
	if cap_share <= 0.0:
		return drain
	return minf(drain, maxf(max_rps, 0.0) * cap_share)


## 壁・柱に1回ぶつかった後のrps。上の3本(effective_wall_damping /
## impact_scaled_wall_damping / absolute_wall_drain / capped_wall_drain)を
## 本番の順序どおりに組み上げた1本で、経緯は BattleResolver._wall_damaged_rps の注釈。
##
## ここへ出したのは、**発射前の見積もり(WallCostPreview)と本番(BattleResolver)が
## 同じ式を通ること**を構造で保証するため。見積もりが本番と1ミリでも違う式を持つと、
## それは「予告が嘘をつく」のと同じ罪になる(rendezvous_preview.gd の注釈と同じ約束)。
##
## gauge_rps は天井の基準になる回転ゲージ(=初期rps)で、道中で減った現在rpsではない。
static func wall_damaged_rps(
	rps: float, gauge_rps: float, mass: float, radius: float, wall_keep: float,
	normal_speed: float, damping: float, impact_ref_speed: float,
	absolute_share: float, violence: float, drain_cap_share: float
) -> float:
	var keep := clampf(wall_keep, 0.0, 1.0)
	var proportional := rps * effective_wall_damping(
		impact_scaled_wall_damping(damping, normal_speed, impact_ref_speed), keep
	)
	var share := clampf(absolute_share, 0.0, 1.0)
	var damaged := proportional
	if share > 0.0:
		var absolute := maxf(
			rps - absolute_wall_drain(normal_speed, mass, radius, violence) * (1.0 - keep),
			0.0
		)
		damaged = lerpf(proportional, absolute, share)
	return rps - capped_wall_drain(rps - damaged, gauge_rps, drain_cap_share)


## 攻め手のdrill(0..)のぶんだけ、相手の硬さに依存しない追加削りを上乗せする。
## 追加量は drill × pierce_drain(相手が攻め手自身と同じ硬さだったときの素の削り)。
##
## edgeのpierce下限は「edgeボーナスが巨体で消えない」ための床だが、素の削り自体が
## 硬さに反比例して痩せるため、edge上限0.60を積んでも巨体への合計削りは細いままで、
## 攻め特化ビルドがLv4〜ボス帯で構造的に詰む(コールドプレイでedge0.60がボスに
## 与0.6/hit vs 被1.5/hitで6連敗、が一次証拠)。drillは乗算でなく加算なので、
## 相手がどれだけ硬くても同じ量が食い込む=対巨体専用の攻め軸になる。
## 柔らかい相手には素の削りの方がはるかに大きく、相対的にほぼ効かない。
## drill=0(既定)で従来と厳密一致。負のdrillは0でクランプ(デバフ札を置かない原則)。
static func drilled_spin_drain(drain: float, drill: float, pierce_drain: float) -> float:
	return drain + maxf(drill, 0.0) * maxf(pierce_drain, 0.0)


## 壁で失うrpsを、現在rpsの割合でなく絶対量で出す版。式はspin_drainと同じ形で、
## 壁を「無限に重い相手」と見なして進入速度に比例させ、自分の硬さ(質量×半径²)で割る。
static func absolute_wall_drain(
	normal_speed: float, own_mass: float, own_radius: float, violence: float
) -> float:
	if own_mass <= 0.0 or own_radius <= 0.0:
		return 0.0
	return violence * maxf(normal_speed, 0.0) / (own_mass * own_radius * own_radius)


## 衝突削りの計算に使う速さの床。相手の速さがfloor_speed未満でも、floor_speed
## ぶんの削りが出る=遅い接触でも最低限「噛み合う」。
##
## 泥仕合対策(2026-07-23): 速度は摩擦・非弾性衝突・すり鉢の引き戻しで単調に沈む
## ため、長引いた戦いは相対速度1〜5の微衝突の応酬になり、削り(∝相手の速さ)が
## ゼロへ痩せて決着が壁と自然減衰任せになっていた(ボス戦16秒26衝突で削り計7、
## 死因の主成分が減衰、という一次証拠)。壁のimpact_scaled_wall_damping(速い激突
## ほど痛い)と対になる「遅い接触にも最低限の噛み合い」で、長引いた削り合いを
## 接触決着へ寄せる。床は削り量(とそれに比例するspin_kick)にだけ効き、
## 弾性衝突の速度交換そのものは実速度のまま。
## floor_speed<=0 で床なし=旧挙動と厳密一致(古い保存データの再現用)。
static func bitten_speed(speed: float, floor_speed: float) -> float:
	return maxf(speed, maxf(floor_speed, 0.0))


## 障害物(固定された円)にめり込んでいて、かつ障害物へ向かって進んでいるか。
## 壁のwall_hitと同じ構造で、法線が固定でなく中心からの放射方向になるだけ。
## 反射は wall_bounce(vel, (pos - obstacle_center).normalized(), restitution) を使う。
## 完全に中心が重なっている(delta=0)時はnormalized()がゼロを返し、
## Vector2.bounce(ゼロ)は元の速度をそのまま返すのでNaNにならない。
static func obstacle_hit(
	obstacle_center: Vector2, obstacle_radius: float,
	pos: Vector2, vel: Vector2, radius: float
) -> bool:
	var delta := pos - obstacle_center
	var sum := obstacle_radius + radius
	if delta.length_squared() >= sum * sum:
		return false
	return vel.dot(delta) < 0.0


## 何もしなくても回転は落ちていく。大きいコマほど速く落ちる。
static func natural_spin_decay(radius: float, rate: float, delta: float) -> float:
	return radius * rate * delta
