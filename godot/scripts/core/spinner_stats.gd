class_name SpinnerStats
extends Resource

## コマ1体の性能。プロトタイプのobject.pyのObjectに相当する。
##
## 単位はアリーナ内の「ユニット」。アリーナは10x10ユニットで中心が(5,5)、
## 表示時にArenaRootのscaleで拡大される（simulation.pyと同じ土俵にして
## おくと、プロトタイプの値を初期の目安として使えるため）。
##
## 数値はプロトタイプから引き継がず、手触りで調整する前提。すべて
## インスペクタからいじれる。

## 重いほど弾かれにくく、相手からRPSを削られにくい。
@export_range(0.1, 10.0, 0.1) var mass: float = 1.5

## 大きいほど当たりやすく削られにくいが、自然減衰でRPSを失いやすい。
@export_range(0.1, 3.0, 0.05) var radius: float = 0.5

## 進行方向と逆向きにかかる一定の減速度(ユニット/秒^2)。
## プロトタイプではdecayという名前だったが、実体は摩擦による減速。
@export_range(0.0, 5.0, 0.01) var friction: float = 0.98

## 壁での跳ね返り係数。1.0で速度を保ったまま反射する。
@export_range(0.0, 2.0, 0.05) var restitution: float = 1.0

## 回転数(rotations per second)。これが尽きた方が負け。
@export_range(0.0, 40.0, 0.5) var rps: float = 15.0

## 自然回転減衰(natural_spin_decay)にかかる自分ぶんの倍率。1.0で従来どおり。
## 1未満で回転を失いにくくなる＝長く回り続ける。Full Steam Aheadが下げる。
@export_range(0.1, 2.0, 0.01) var spin_decay: float = 1.0

## 壁・障害物にぶつかったときのrps喪失を減らす度合い。0で従来どおり、1で無損失。
## 実効ダンピングを1.0(無損失)へこの割合だけ寄せる。Rage Reflectionが上げる。
@export_range(0.0, 1.0, 0.01) var wall_keep: float = 0.0

## コマ同士の衝突で受けるrps削りを減らす度合い。0で従来どおり、1で削り無効。
## 壁のwall_keepと対になる衝突版の防御。Shock Absorberが上げる。
@export_range(0.0, 1.0, 0.01) var hit_guard: float = 0.0

## コマ同士の衝突で相手に与えるrps削りを増やす度合い。0で従来どおり、0.2で+20%。
## hit_guard(受け)と対になる攻めのステータス。Sharp Edgeが上げる。
## 相手のspin_kickは受けた削り量に比例するので、削りが増えるぶん相手を強く
## 弾き飛ばす=壁へ押し込む攻めとも噛み合う。
@export_range(0.0, 2.0, 0.01) var edge: float = 0.0

## 衝突ごとに相手の硬さ(質量×半径²)に依存しない追加削りを与える度合い。
## 0で従来どおり。追加量は pierce(自分と同じ硬さの相手への素の削り)×drill で、
## 相手がどれだけ硬くても減らない=対巨体の攻め軸。Drill Bitが上げる。
## edge(素の削りの乗算強化)は硬い相手ほどボーナスの絶対量が細るが、こちらは
## 相手の硬さと無関係に一定量が食い込む、という住み分け。
@export_range(0.0, 2.0, 0.01) var drill: float = 0.0

## 回転数の上限。「RPSの最大値を40にし、ゲージに反映」というコミットで決まった値。
## SPIN_ENGINE札の上限(CustomPartCatalog.RPS_CAP)も勝利成長もこれを参照する。
const RPS_CAP := 40.0

## 戦闘勝利1回ごとの回転成長量。敵rpsは段と共に15→33へ確実に上がるのに、
## プレイヤーの成長はRARE札(SPIN_ENGINE)の引き運に全依存で、引けないランは
## 段3〜5の減衰レースで詰む(計測: 段5勝率20.3%が谷、死亡の66%が段3〜5)。
## 勝つたびに小さく確実に育つ下支えを入れて、引き運の振れ幅を狭める。
## 値は計測(scripts/playtest.sh)で決めた: +1.0は谷を29.5%まで上げる一方、無操作寄りの
## random+random botのクリア率が56%へ跳ねて過剰。+0.5で谷25.2%・全体の締まりを両立。
const VICTORY_RPS_GROWTH := 0.5

## 敵を接触(衝突削り/壁への弾き飛ばし)で仕留めた勝利の成長量の下限。撃破ボーナス。
## 「弱発射で敵から離れて自然減衰を待つ」受け身戦法が支配的(Lv3+の敵死因の8割が
## 自然減衰)で、当てにいく楽しい方の遊びが報われない。そこで決着のつき方で成長に
## 差を付け、狙って当てた勝ちがラン単位で複利になるようにする。受け身の勝ちは
## 従来のVICTORY_RPS_GROWTHのまま(弱体化はしない)。
const KNOCKOUT_RPS_GROWTH := 1.0

## 撃破ボーナスの比例成長率。+1.0固定はrpsが育つほど相対的に空気になり
## (rps15では+6.7%、rps29では+3.4%)、後半ほど当てにいく理由が薄れていた。
## 現在rpsに比例させて「狙って当てた勝ちはラン後半でも複利で効く」を保つ。
## rps20以下ではKNOCKOUT_RPS_GROWTHの下限が働き、序盤の手触りは従来と同一。
## 受け身の勝ち(VICTORY_RPS_GROWTH)は比例させない: 逃げ切りが複利になると
## 撃破ボーナスの存在意義(当てにいく方が報われる)が崩れるため。
const KNOCKOUT_RPS_GROWTH_RATE := 0.05

## 撃破ボーナスの余勢転化でspin_decayを下げるときの下限。MOMENTUM札
## (CustomPartCatalog.FULL_STEAM_FLOOR)と同じ0.4で、勝ち続けても自然減衰は
## 通常の40%までしか軽くならない(無限に回るコマを作らないための床)。
## 同値であることはテストが照合する。
const OVERFLOW_DECAY_FLOOR := 0.4


## 戦闘に勝ったときに呼ぶ。回転を少しだけ成長させる(上限RPS_CAP)。
## knockout=真(接触で決着。BattleResult.finished_by_knockout)なら撃破ボーナスで
## 大きく育つ(現在rpsに比例、下限KNOCKOUT_RPS_GROWTH)。実プレイ(Main経由の
## GameState)とシミュレーション(RunSim)の両方がここを使う。
## 戻り値は実際に増えた量(上限で頭打ちした場合は要求より小さい)。表示用。
##
## 上限で堰き止められた撃破ボーナスの余りは寿命へ転化する(余勢)。強ビルドは
## 中盤に上限40へ到達し、以降の勝利で「当てにいく理由」を機構ごと失っていた
## (2026-07-30/31のコールドプレイで頭打ち表示が終盤の勝利に流れ続けた)。
## 寿命目安はrps/(radius×spin_decay)なので、spin_decayをRPS_CAP/(RPS_CAP+余り)倍
## することで、堰き止められたrpsが入っていた場合と厳密に同じだけ寿命が伸びる。
## 受け身の勝ち(knockout=偽)は転化しない: 上限後こそ差を付けたい場面だから。
func grow_rps_by_victory(knockout: bool = false) -> float:
	var growth := VICTORY_RPS_GROWTH
	if knockout:
		growth = maxf(KNOCKOUT_RPS_GROWTH, rps * KNOCKOUT_RPS_GROWTH_RATE)
	var before := rps
	rps = minf(rps + growth, RPS_CAP)
	var gained := rps - before
	if knockout:
		var overflow := growth - gained
		if overflow > 0.0:
			spin_decay = maxf(
				OVERFLOW_DECAY_FLOOR, spin_decay * RPS_CAP / (RPS_CAP + overflow)
			)
	return gained


func duplicate_stats() -> SpinnerStats:
	var copy := SpinnerStats.new()
	copy.mass = mass
	copy.radius = radius
	copy.friction = friction
	copy.restitution = restitution
	copy.rps = rps
	copy.spin_decay = spin_decay
	copy.wall_keep = wall_keep
	copy.hit_guard = hit_guard
	copy.edge = edge
	copy.drill = drill
	return copy


## プレイヤーの初期性能。プロトタイプの Object(1.5, 0.5, 0.98, 1.0, 15.0) 相当。
## GameState(実プレイ)とRunSim(シミュレーション)の両方がここを使う。
## autoloadのGameStateに置くと--script実行から参照できない(識別子が
## 解決できず、参照した側がコンパイルエラーになる)ため、こちらが持つ。
static func default_player() -> SpinnerStats:
	var stats := SpinnerStats.new()
	stats.mass = 1.5
	stats.radius = 0.7
	stats.friction = 0.98
	# 反発の上限が1.0(それを超えると壁で加速して発散する)なので、初期値を
	# 下げておかないとRage Reflectionが何も起こさない死に札になる。
	# 壁で少し勢いを失う代わりに、パーツで無損失まで持っていける。
	stats.restitution = 0.75
	stats.rps = 15.0
	return stats
