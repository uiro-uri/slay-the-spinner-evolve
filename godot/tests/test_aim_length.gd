extends RefCounted

## 自機の狙いと敵の予告で、三角形の長さの規則が同じであることのテスト。
##
## AimTriangle のコメントは最初から「色が違うだけで読み方が同じ」を謳っていたが、
## 長さの規則だけが揃っていなかった(自機=引き量に比例、敵=sqrt(速度)×1.2)。
## 形が同じで長さの意味が違うと、並べた三角形の長短が速度の大小と一致しない
## ——「相手より速く撃てているか」が読めない。ここが縛るのは**両者が同じ関数を
## 通ること**と、その帰結として**同じ速度なら同じ長さになること**。
##
## 長さの絶対値は縛らない(full_speed_length は @export で手触り調整の対象)。
## 縛るのは自機と敵の**一致**と単調性——値を動かしても生き残る性質。

const EPS := 1e-4

## 自機の full pull 長の既定(LaunchController.max_pull)。
const FULL := 4.0


func run(check: Callable) -> void:
	_test_rule_shape(check)
	_test_player_base_stays_at_cursor(check)
	_test_player_and_enemy_agree(check)
	_test_enemy_speed_order_matches_length_order(check)
	_test_battle_wires_full_speed_length(check)


## 規則そのもの: 0で0、MAXでfull、その間は単調増加、MAX超はクランプ。
func _test_rule_shape(check: Callable) -> void:
	check.call(
		absf(AimTriangle.length_for_speed(0.0, FULL)) < EPS,
		"length_for_speed: 速度0は長さ0"
	)
	check.call(
		absf(AimTriangle.length_for_speed(LaunchSpeed.MAX, FULL) - FULL) < EPS,
		"length_for_speed: MAXでfull長(%.2f)" % FULL
	)
	check.call(
		absf(AimTriangle.length_for_speed(LaunchSpeed.MAX * 3.0, FULL) - FULL) < EPS,
		"length_for_speed: MAX超はクランプ(予告が伸び続けない)"
	)
	var prev := -1.0
	for i in 13:
		var length := AimTriangle.length_for_speed(float(i), FULL)
		check.call(length > prev, "length_for_speed: 速度%dで単調に伸びる (%.3f)" % [i, length])
		prev = length
	# 基準長が壊れていても負の長さを返さない。0は掛け算で自然に0になるので、
	# ガードが本当に効いているかは**負**を渡さないと分からない(0だけ見る検査は
	# ガードを外しても素通りする)。
	check.call(
		absf(AimTriangle.length_for_speed(6.0, 0.0)) < EPS,
		"length_for_speed: full長0は0"
	)
	check.call(
		AimTriangle.length_for_speed(6.0, -4.0) >= 0.0,
		"length_for_speed: full長が負でも負の長さを返さない (%.3f)"
			% AimTriangle.length_for_speed(6.0, -4.0)
	)
	check.call(
		absf(AimTriangle.length_for_speed(NAN, FULL)) < EPS,
		"length_for_speed: 非有限の速度は0(NaN長を描かない)"
	)


## 自機側: 三角形の長さは**初速**を語る。だから自機に下限(LaunchSpeed.PLAYER_MIN)が
## 入った 2026-08-10 以降、底辺はもうカーソル位置には来ない——僅かに引いただけでも
## 実際に速度 PLAYER_MIN が出るので、三角形もその長さでなければ嘘になる。
## 縛るのは「full pull で底辺がカーソル」「少しでも引けば下限ぶんの長さがある」
## 「引くほど伸びる」。長さの絶対値そのものは縛らない(@exportの調整対象)。
func _test_player_base_stays_at_cursor(check: Callable) -> void:
	var floor_length := AimTriangle.length_for_speed(LaunchSpeed.PLAYER_MIN, FULL)
	check.call(
		absf(AimTriangle.length_for_speed(LaunchSpeed.from_pull(FULL, FULL), FULL) - FULL) < EPS,
		"自機: full pullで底辺がカーソル位置"
	)
	check.call(
		absf(AimTriangle.length_for_speed(LaunchSpeed.from_pull(0.0, FULL), FULL)) < EPS,
		"自機: 引き量0は長さ0(向きが決まっていないので三角形を出さない)"
	)
	var prev := 0.0
	for pull in [0.01, 0.5, 1.3, 2.0, 3.7, FULL]:
		var length := AimTriangle.length_for_speed(LaunchSpeed.from_pull(pull, FULL), FULL)
		check.call(
			length >= floor_length - EPS,
			"自機: 引き量%.2f → 長さ%.2f (下限%.2fを割らない)" % [pull, length, floor_length]
		)
		check.call(length > prev - EPS, "自機: 引き量%.2fで伸びている(単調)" % pull)
		prev = length
	# 上限を超えて引いても伸びない(既存の頭打ちが生きている)。
	var over := AimTriangle.length_for_speed(LaunchSpeed.from_pull(FULL * 2.0, FULL), FULL)
	check.call(absf(over - FULL) < EPS, "自機: max_pull超は伸びない (%.2f)" % over)


## この変更の本体: 同じ速度なら自機と敵の三角形が同じ長さになること。
## 敵は最小可視長を無効化して生の規則だけを見る(下限は別の約束で、
## test_enemy_spawn が縛っている)。
func _test_player_and_enemy_agree(check: Callable) -> void:
	var telegraph := EnemyTelegraph.new()
	telegraph.full_speed_length = FULL
	telegraph.readable_radius = 0.0
	telegraph.min_length_margin = 0.0
	# 揺らぎは表示専用で長さも揺らすので、突き合わせの間だけ止める。
	telegraph.wobble_position = 0.0
	telegraph.wobble_angle_deg = 0.0
	telegraph.wobble_length = 0.0

	for speed in [LaunchSpeed.ENEMY_MIN, 4.0, 6.0, 8.5, LaunchSpeed.MAX]:
		telegraph.show_plan(Vector2(5, 5), Vector2.DOWN * speed)
		var enemy_length := telegraph.telegraph_length()
		# 自機が同じ初速を出すのに要る引き量。マップが[PLAYER_MIN,MAX]になったので
		# 逆写像も下限ぶんをずらす(素の speed/MAX ではもう同じ速度にならない)。
		var span: float = LaunchSpeed.MAX - LaunchSpeed.PLAYER_MIN
		var pull: float = (speed - LaunchSpeed.PLAYER_MIN) / span * FULL
		# 下限ちょうどは引き量0(=速度0の「向き未定」)へ落ちるので、僅かに引いた扱いにする。
		var player_length := AimTriangle.length_for_speed(
			LaunchSpeed.from_pull(maxf(pull, 1e-6), FULL), FULL
		)
		check.call(
			absf(enemy_length - player_length) < EPS,
			"速度%.1f: 敵の予告%.3f == 自機の狙い%.3f" % [speed, enemy_length, player_length]
		)
	telegraph.free()


## 帰結: 敵同士でも「長い三角形＝速い」が厳密に成り立つ。sqrt でも成り立って
## いた性質だが、規則を差し替えたので改めて縛る。ENEMY_MIN〜MAX の全域で見る。
func _test_enemy_speed_order_matches_length_order(check: Callable) -> void:
	var telegraph := EnemyTelegraph.new()
	telegraph.full_speed_length = FULL
	telegraph.readable_radius = 0.0
	telegraph.min_length_margin = 0.0
	telegraph.wobble_position = 0.0
	telegraph.wobble_angle_deg = 0.0
	telegraph.wobble_length = 0.0

	var prev := -1.0
	var steps := 10
	for i in steps + 1:
		var speed: float = lerpf(LaunchSpeed.ENEMY_MIN, LaunchSpeed.MAX, float(i) / float(steps))
		telegraph.show_plan(Vector2(5, 5), Vector2.RIGHT * speed)
		var length := telegraph.telegraph_length()
		check.call(length > prev, "敵の予告: 速度%.1f で長さ%.3f が伸び続ける" % [speed, length])
		prev = length
	telegraph.free()


## 配線の回帰: 基準長を定数で2箇所に置くと片方の調整で黙ってズレる。Battleが
## 自機の max_pull を予告へ流し込んでいることを、ソースの形で押さえる
## (Battle は autoload とシーンに依存するのでヘッドレスから立てられない)。
func _test_battle_wires_full_speed_length(check: Callable) -> void:
	var source := FileAccess.get_file_as_string("res://scenes/battle/Battle.gd")
	check.call(
		source.contains("telegraph.full_speed_length = _launcher.max_pull"),
		"Battle: 予告の基準長に自機の max_pull を流し込んでいる"
	)
	var launcher := FileAccess.get_file_as_string("res://scenes/battle/LaunchController.gd")
	check.call(
		launcher.contains("AimTriangle.length_for_speed"),
		"LaunchController: 狙いの長さも共通の規則を通っている"
	)
