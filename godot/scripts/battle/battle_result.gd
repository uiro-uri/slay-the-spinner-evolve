class_name BattleResult
extends RefCounted

## 1戦の計算結果。軌跡・衝突・勝敗の全部。Battle.gdはこれを再生するだけ。
##
## 入力とシードだけを持って再生側で計算し直す形にはしていない。通信量では
## その方が有利だが、Godotは浮動小数の再現性をプラットフォーム間で保証せず
## (しかもVector2の成分は32bit)、同じ入力から別マシンで別の勝者が出うる。
## 軌跡を丸ごと持てばその問題自体が消える。60Hz・60秒・2体で約86KBなので、
## 1回発射して見るだけのこのゲームには十分小さい。
##
## 後から入力＋シード方式へ移ることはできるが、逆は難しい。


## あるステップでの1体の状態。
class Snapshot:
	extends RefCounted

	var position: Vector2
	var velocity: Vector2
	var rps: float

	func _init(position_: Vector2, velocity_: Vector2, rps_: float) -> void:
		position = position_
		velocity = velocity_
		rps = rps_


## 衝突が起きた瞬間。再生時にここで衝撃波を出す。
class Impact:
	extends RefCounted

	var time: float
	var point: Vector2

	func _init(time_: float, point_: Vector2) -> void:
		time = time_
		point = point_


## 何もなければ引き分け。
enum Outcome { DRAW, PLAYER_WIN, ENEMY_WIN }

## 各ステップの状態。index * time_step が時刻。
var player_frames: Array[Snapshot] = []

## 敵ごとの軌跡。enemy_tracks[i] が i 番目の敵の Array[Snapshot]。
## GDScriptはネスト型付き配列(Array[Array[Snapshot]])を扱えないので素のArrayにする。
## 各トラックの長さは player_frames と揃う(PlaytestInvariantsが検査する)。
var enemy_tracks: Array = []

var impacts: Array[Impact] = []

## 壁にぶつかった瞬間。コマ同士より控えめな衝撃波を再生時に出す。
var wall_impacts: Array[Impact] = []

var outcome: Outcome = Outcome.DRAW

## 決着した時刻(秒)。再生はここで止める。
var finish_time: float = 0.0

## 計算に使った刻み幅。再生側が時刻からフレームを引くのに要る。
var time_step: float = 1.0 / 60.0

## 上限に達して打ち切ったか。真なら決着が付かないまま終わっている。
var timed_out: bool = false

## ゴーストのすり抜け時間(秒)。窓は最初の衝突(ghost_start)の直後から
## この秒数だけ続く。入力(BattleRequest.ghost_duration)の写しだが、
## 再生はResultだけで完結する(サーバーが返すのもこれ)ので結果側にも持たせる。
var ghost_duration: float = 0.0

## ゴースト窓が開いた時刻(=最初のプレイヤー対敵の衝突時刻)。リゾルバが記録し、
## 再生側は(ghost_start, ghost_start+ghost_duration)の間プレイヤーのコマを
## 半透明シマーで描いて「すり抜け中」を見せる。窓が開かなかったら-1。
var ghost_start: float = -1.0

## 敗者(決着を付けられた側)がどう力尽きたか: "drain"(衝突削り)・"wall"(壁/障害物)・
## "decay"(自然減衰)。引き分け・時間切れは空文字。リゾルバが解決時に記録する
## 事実で、軌跡からの推定(BattleMetrics)ではない。撃破ボーナスの判定に使う。
var loser_death_cause: String = ""

## プレイヤーが機構ごとに失ったrpsの内訳:
## {"drain": 衝突削り, "wall": 壁/障害物, "decay": 自然減衰, "wall_hits": 壁回数}。
## loser_death_causeは「閾値を割った最後の一撃」しか語らない(壁で大半を失っても
## 最後の一滴が減衰なら"decay"になる)ため、敗因分析にはこちらの事実を使う。
## drain+wall+decay = 初期rps - 最終rps。旧結果のdictには無いので空dictで互換。
var player_rps_loss: Dictionary = {}

## 敵ごとの同内訳。enemy_rps_loss[i] が i 番目の敵のDictionary。
var enemy_rps_loss: Array = []


func player_won() -> bool:
	return outcome == Outcome.PLAYER_WIN


## 勝利が「接触(衝突削り/壁への弾き飛ばし)で決まった」なら真。敵の自然減衰を
## 待っただけの勝ち("decay")と区別し、当てにいった勝ちに撃破ボーナス
## (SpinnerStats.KNOCKOUT_RPS_GROWTH)を与えるための判定。
func finished_by_knockout() -> bool:
	return player_won() and loser_death_cause in ["drain", "wall"]


func duration() -> float:
	return finish_time


## 時刻tでの状態を返す。フレーム間は線形補間するので、描画のfpsが
## 計算の刻み幅と違っていても滑らかに動く。
func sample(frames: Array[Snapshot], t: float) -> Snapshot:
	if frames.is_empty():
		return Snapshot.new(Vector2.ZERO, Vector2.ZERO, 0.0)

	var raw := t / time_step
	var i := int(floor(raw))
	if i < 0:
		return frames[0]
	if i >= frames.size() - 1:
		return frames[frames.size() - 1]

	var a := frames[i]
	var b := frames[i + 1]
	var f := raw - i
	return Snapshot.new(
		a.position.lerp(b.position, f),
		a.velocity.lerp(b.velocity, f),
		lerpf(a.rps, b.rps, f)
	)


func to_dict() -> Dictionary:
	# 敵トラックはlambdaから静的関数を呼ばず、明示ループで直列化する。
	var enemies_out: Array = []
	for track in enemy_tracks:
		enemies_out.append(_frames_to_array(track))
	return {
		"player": _frames_to_array(player_frames),
		"enemies": enemies_out,
		"impacts": impacts.map(func(x: Impact) -> Array:
			return [x.time, x.point.x, x.point.y]),
		"wall_impacts": wall_impacts.map(func(x: Impact) -> Array:
			return [x.time, x.point.x, x.point.y]),
		"outcome": int(outcome),
		"finish_time": finish_time,
		"time_step": time_step,
		"timed_out": timed_out,
		"ghost_duration": ghost_duration,
		"ghost_start": ghost_start,
		"loser_death_cause": loser_death_cause,
		"player_rps_loss": player_rps_loss,
		"enemy_rps_loss": enemy_rps_loss,
	}


static func from_dict(d: Dictionary) -> BattleResult:
	var r := BattleResult.new()
	r.player_frames = _frames_from_array(d["player"])
	var tracks: Array = []
	for raw_track in d["enemies"]:
		tracks.append(_frames_from_array(raw_track))
	r.enemy_tracks = tracks
	var impacts_: Array[Impact] = []
	for x in d["impacts"]:
		impacts_.append(Impact.new(x[0], Vector2(x[1], x[2])))
	r.impacts = impacts_
	var wall_impacts_: Array[Impact] = []
	for x in d["wall_impacts"]:
		wall_impacts_.append(Impact.new(x[0], Vector2(x[1], x[2])))
	r.wall_impacts = wall_impacts_
	r.outcome = d["outcome"]
	r.finish_time = d["finish_time"]
	r.time_step = d["time_step"]
	r.timed_out = d["timed_out"]
	r.ghost_duration = d.get("ghost_duration", 0.0)
	r.ghost_start = d.get("ghost_start", -1.0)
	r.loser_death_cause = d.get("loser_death_cause", "")
	r.player_rps_loss = d.get("player_rps_loss", {})
	r.enemy_rps_loss = d.get("enemy_rps_loss", [])
	return r


static func _frames_to_array(frames: Array[Snapshot]) -> Array:
	return frames.map(func(s: Snapshot) -> Array:
		return [s.position.x, s.position.y, s.velocity.x, s.velocity.y, s.rps])


static func _frames_from_array(raw: Array) -> Array[Snapshot]:
	var frames: Array[Snapshot] = []
	for x in raw:
		frames.append(Snapshot.new(Vector2(x[0], x[1]), Vector2(x[2], x[3]), x[4]))
	return frames
