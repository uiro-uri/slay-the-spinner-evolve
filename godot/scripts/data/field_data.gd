class_name FieldData
extends Resource

## 1戦を戦う土俵(フィールド)。壁の位置・形状、傾斜、障害物をまとめる。
## EnemyDataと同じく、マップでノードを選んだ瞬間に FieldRosterが1つ選び、
## GameState.pending_field 経由でBattleへ渡す。
##
## 数値は手触りで調整する前提。すべて@exportでInspectorから触れる。

## フィールド名の翻訳キー。
@export var title_key: String = ""

## アリーナの矩形。中心と壁・傾斜の基準はここから決まる。
## 小さくすると狭い土俵、位置をずらすと非対称な土俵になる。
@export var arena_bounds: Rect2 = Rect2(0, 0, 10, 10)

## 外周の形。矩形/八角形/円形。
@export var wall_shape: ArenaWall.WallShape = ArenaWall.WallShape.RECT

## 傾斜の形。すり鉢(外側ほど急)か円錐(一定傾斜)か。
@export var stage_shape: SpinnerPhysics.StageShape = SpinnerPhysics.StageShape.DISH

## 傾斜の強さ。大きいほど中央へ強く戻される。
@export var stage_strength: float = 4.9

## 障害物。xy=中心(アリーナ座標)、z=半径。固定された円柱としてコマを弾く。
@export var obstacles: Array[Vector3] = []


static func make(
	title_key_: String, arena_bounds_: Rect2, wall_shape_: ArenaWall.WallShape,
	stage_shape_: SpinnerPhysics.StageShape, stage_strength_: float,
	obstacles_: Array[Vector3] = []
) -> FieldData:
	var data := FieldData.new()
	data.title_key = title_key_
	data.arena_bounds = arena_bounds_
	data.wall_shape = wall_shape_
	data.stage_shape = stage_shape_
	data.stage_strength = stage_strength_
	data.obstacles = obstacles_
	return data


## 壁の内接円半径。非矩形フィールドの発射クランプと敵の出現境界に使う。
func inradius() -> float:
	return ArenaWall.inradius_for(wall_shape, arena_bounds)


## アリーナの中心。
func center() -> Vector2:
	return arena_bounds.get_center()


## コマ全体が壁の内側に収まる位置へ寄せる。矩形は矩形クランプ、非矩形は内接円。
## Battle._clamp_launch と同じ寄せ方の一本化(bot・CLIはこちらを使う)。
func clamp_inside(pos: Vector2, radius: float) -> Vector2:
	if wall_shape == ArenaWall.WallShape.RECT:
		return ArenaWall.clamp_inside(arena_bounds, pos, radius)
	return ArenaWall.clamp_inside_circle(center(), inradius(), pos, radius)


## コマ全体が「壁の内側 かつ 障害物(柱)の外」に収まる位置へ寄せる。
## 柱に重なった位置から始まると毎ステップ柱に弾かれ続ける見えない拘束になるため、
## 初期配置(発射・狙い中の表示)はこちらを通す。柱が壁際にあって両立できない
## 詰み配置では壁を優先する(土俵の外にはみ出す方が重い嘘なので)。
func clamp_placement(pos: Vector2, radius: float) -> Vector2:
	var p := clamp_inside(pos, radius)
	for i in 4:
		# 柱の真上で向きが決められないときは中心へ逃がす(柱は中心を外して置かれる)。
		var pushed := ArenaWall.push_out_of_obstacles(
			p, obstacles, radius, _inward_or_right(p))
		if pushed.is_equal_approx(p):
			return p
		p = clamp_inside(pushed, radius)
	return p


func _inward_or_right(pos: Vector2) -> Vector2:
	var d := center() - pos
	return d.normalized() if d.length() > 0.001 else Vector2.RIGHT


## 発射位置のクランプ: 壁の内側 かつ 障害物の外 かつ 全ての敵予告から
## 間合い(LaunchStandoff)以上。spawn_points/spawn_radii は予告済みの敵の
## 出現中心と半径(同indexで対応)。
func clamp_launch(
	pos: Vector2,
	spawn_points: PackedVector2Array,
	spawn_radii: PackedFloat32Array,
	player_radius: float
) -> Vector2:
	return LaunchStandoff.clamp_away(
		pos, spawn_points, spawn_radii, player_radius, inradius(), center(),
		func(p: Vector2) -> Vector2: return clamp_placement(p, player_radius)
	)
