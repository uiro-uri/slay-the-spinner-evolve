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


## 戦闘に勝ったときに呼ぶ。回転を少しだけ成長させる(上限RPS_CAP)。
## 実プレイ(Main経由のGameState)とシミュレーション(RunSim)の両方がここを使う。
func grow_rps_by_victory() -> void:
	rps = minf(rps + VICTORY_RPS_GROWTH, RPS_CAP)


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
