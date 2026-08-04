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
## strength はその瞬間に実際に失われたrps(コマ同士は両者の合計、壁・障害物は
## その1体の喪失)。壁の喪失は進入速度比例・削りは噛み合い床持ちなので、
## 「どれだけ痛かったか」は事実として記録しないと再生側から読めない。
## 衝撃波の大きさをこれでスケールし、擦り接触は小さく・激突は大きく見せる。
class Impact:
	extends RefCounted

	## owner の値。壁・障害物の衝撃波にだけ意味がある(コマ同士は両者のものなので
	## 持ち主が決まらず、常にUNKNOWNのまま)。
	const OWNER_PLAYER := -1
	const OWNER_UNKNOWN := -2

	var time: float
	var point: Vector2
	var strength: float

	## その喪失を負ったのは誰か。OWNER_PLAYER か、敵の0始まりindex。
	## 「壁で何回転持っていかれたか」を再生中にその場へ出す(WallDamageReadout)には
	## 色を分ける相手が要るが、軌跡との距離から当てる推定は乱戦で外れる。
	## リゾルバが課金した瞬間に知っている事実なので、そのまま記録する。
	var owner: int

	func _init(
		time_: float,
		point_: Vector2,
		strength_: float = 1.0,
		owner_: int = OWNER_UNKNOWN
	) -> void:
		time = time_
		point = point_
		strength = strength_
		owner = owner_


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
## "decay"(自然減衰)。その敗者から最も多くrpsを奪った機構で分類する(閾値を割らせた
## 最後の一滴で分類すると、壁で大半を失った死が最後の微小な減衰で"decay"に化ける)。
## 引き分け・時間切れは空文字。リゾルバが解決時に記録する事実で、軌跡からの推定
## (BattleMetrics)ではない。撃破ボーナスの判定に使う。
var loser_death_cause: String = ""

## 決着を付けた敵がプレイヤーと一度でも接触したか。撃破ボーナスの寄与判定に使う:
## 死因がwall/drainでも、プレイヤーに一度も触れないまま壁や同士討ちで勝手に果てた
## 敵は「接触で仕留めた」勝ちではない(受け身の「待てば自滅」まで撃破+1.0で
## 報われていた)。リゾルバが勝ち分岐で必ず記録する事実。既定はtrue=接触あり扱いで、
## この記録を持たない旧dict・手組みの結果は従来どおり死因だけで判定される。
var loser_hit_by_player: bool = true

## プレイヤーが機構ごとに失ったrpsの内訳:
## {"drain": 衝突削り, "wall": 壁/障害物, "decay": 自然減衰, "wall_hits": 壁回数}。
## 死因ラベルは支配的な1機構しか語らないため、敗因分析にはこちらの量を使う。
## drain+wall+decay = 初期rps - 最終rps。旧結果のdictには無いので空dictで互換。
var player_rps_loss: Dictionary = {}

## 敵ごとの同内訳。enemy_rps_loss[i] が i 番目の敵のDictionary。
var enemy_rps_loss: Array = []

## プレイヤーが力尽きた瞬間の事実: {"cause": "drain"/"wall"/"decay", "time": 秒}。
## 力尽きていなければ空Dictionary(=生存)。loser_death_causeは敗者1体の最後の一撃
## しか語らないため、乱戦や相打ち(敵全滅と同じステップで自分も力尽きる=勝ち)では
## 「誰がいつ何で止まったか」が結果から読めなかった。リゾルバが記録する事実で、
## 軌跡からの推定ではない。旧dictには無いので空で互換。
var player_death: Dictionary = {}

## 敵ごとの同事実。enemy_deaths[i] が i 番目の敵のDictionary(生存なら空)。
var enemy_deaths: Array = []


func player_won() -> bool:
	return outcome == Outcome.PLAYER_WIN


## 勝利が「接触(衝突削り/壁への弾き飛ばし)で決まった」なら真。敵の自然減衰を
## 待っただけの勝ち("decay")と、決着を付けた敵に一度も触れないまま敵が勝手に
## 果てた勝ち(壁自滅・同士討ち)を除き、当てにいった勝ちに撃破ボーナス
## (SpinnerStats.KNOCKOUT_RPS_GROWTH)を与えるための判定。
func finished_by_knockout() -> bool:
	return player_won() and loser_death_cause in ["drain", "wall"] and loser_hit_by_player


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
			return [x.time, x.point.x, x.point.y, x.strength]),
		# 壁だけ5要素目に持ち主を載せる。コマ同士(impacts)は両者のものなので
		# 持ち主が決まらず、載せても常にUNKNOWNの水増しにしかならない。
		"wall_impacts": wall_impacts.map(func(x: Impact) -> Array:
			return [x.time, x.point.x, x.point.y, x.strength, x.owner]),
		"outcome": int(outcome),
		"finish_time": finish_time,
		"time_step": time_step,
		"timed_out": timed_out,
		"ghost_duration": ghost_duration,
		"ghost_start": ghost_start,
		"loser_death_cause": loser_death_cause,
		"loser_hit_by_player": loser_hit_by_player,
		"player_rps_loss": player_rps_loss,
		"enemy_rps_loss": enemy_rps_loss,
		"player_death": player_death,
		"enemy_deaths": enemy_deaths,
	}


static func from_dict(d: Dictionary) -> BattleResult:
	var r := BattleResult.new()
	r.player_frames = _frames_from_array(d["player"])
	var tracks: Array = []
	for raw_track in d["enemies"]:
		tracks.append(_frames_from_array(raw_track))
	r.enemy_tracks = tracks
	# 旧dictの要素は[time, x, y]の3要素。強度は1.0(=既定サイズ)で読み、
	# 当時の結果を当時の見た目のまま再生できるようにする。
	var impacts_: Array[Impact] = []
	for x in d["impacts"]:
		impacts_.append(Impact.new(x[0], Vector2(x[1], x[2]), x[3] if x.size() > 3 else 1.0))
	r.impacts = impacts_
	var wall_impacts_: Array[Impact] = []
	for x in d["wall_impacts"]:
		# 持ち主(5要素目)を持たない旧dictはUNKNOWNで読む。再生側は持ち主不明の
		# 喪失表示を出さないので、当時の結果は当時の見た目のまま再生される。
		wall_impacts_.append(Impact.new(
			x[0],
			Vector2(x[1], x[2]),
			x[3] if x.size() > 3 else 1.0,
			x[4] if x.size() > 4 else Impact.OWNER_UNKNOWN
		))
	r.wall_impacts = wall_impacts_
	r.outcome = d["outcome"]
	r.finish_time = d["finish_time"]
	r.time_step = d["time_step"]
	r.timed_out = d["timed_out"]
	r.ghost_duration = d.get("ghost_duration", 0.0)
	r.ghost_start = d.get("ghost_start", -1.0)
	r.loser_death_cause = d.get("loser_death_cause", "")
	# 旧dictにこのキーは無い。true=接触あり扱いで読み、当時の結果の撃破判定を
	# 当時のまま(死因だけで決まる)再現する。
	r.loser_hit_by_player = d.get("loser_hit_by_player", true)
	r.player_rps_loss = d.get("player_rps_loss", {})
	r.enemy_rps_loss = d.get("enemy_rps_loss", [])
	r.player_death = d.get("player_death", {})
	r.enemy_deaths = d.get("enemy_deaths", [])
	return r


static func _frames_to_array(frames: Array[Snapshot]) -> Array:
	return frames.map(func(s: Snapshot) -> Array:
		return [s.position.x, s.position.y, s.velocity.x, s.velocity.y, s.rps])


static func _frames_from_array(raw: Array) -> Array[Snapshot]:
	var frames: Array[Snapshot] = []
	for x in raw:
		frames.append(Snapshot.new(Vector2(x[0], x[1]), Vector2(x[2], x[3]), x[4]))
	return frames
