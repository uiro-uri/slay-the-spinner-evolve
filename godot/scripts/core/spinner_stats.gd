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


func duplicate_stats() -> SpinnerStats:
	var copy := SpinnerStats.new()
	copy.mass = mass
	copy.radius = radius
	copy.friction = friction
	copy.restitution = restitution
	copy.rps = rps
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
