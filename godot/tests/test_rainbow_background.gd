extends RefCounted

## ゲームクリア画面の虹背景 (RainbowBackground.hue_at) のテスト。
## UI (Control のインスタンス化) は要らず、純静的関数だけをヘッドレスで確かめる。
## この repo の流儀どおり、値そのものではなく「向き・単調性・周期性」など
## チューニングで変わらない性質を検証する。
##
## サボタージュ検証 (CLAUDE.md「壊した実装を落とせて初めて完成」):
##   1. hue_at の `fraction + phase` を `fraction - phase` にする
##      → 「phase を進めるのは fraction を進めるのと同じ」が崩れて赤くなる
##      (符号だけの反転は wrapf があるため単純な大小比較では捕まらない。等価性で捕まえる)。
##   2. `fraction + phase` から `+ phase` を落として fraction だけにする
##      → 「phase を変えると色が変わる」が同色になり赤くなる。
##   3. fraction の寄与を落として定数にする
##      → 「fraction 0→1 で色相が単調に進む」が赤くなる。
##   いずれも確認済み。

const Rainbow := preload("res://scenes/gameclear/RainbowBackground.gd")

const SAT := 0.6
const VAL := 0.85


func run(check: Callable) -> void:
	# phase を変えると色が変わる = 帯がスクロールしている証拠。
	var still := Rainbow.hue_at(0.0, 0.0, SAT, VAL)
	var moved := Rainbow.hue_at(0.0, 0.3, SAT, VAL)
	check.call(
		not is_equal_approx(still.h, moved.h),
		"phase を進めると色相が変わる (%.3f -> %.3f)" % [still.h, moved.h]
	)

	# phase を進めるのは fraction を進めるのと同じ = 帯が上へスクロールしていく向き。
	# 単純な大小比較は wrapf の巻き戻りで符号反転を見逃すので、等価性で向きを固定する:
	#   hue_at(0, d) == hue_at(d, 0)  ⇔  fraction+phase(＝正しい向き)。
	# `-` にすると hue_at(0, d)=wrap(-d) と hue_at(d, 0)=d がずれて落ちる。
	var by_phase := Rainbow.hue_at(0.0, 0.3, SAT, VAL)
	var by_fraction := Rainbow.hue_at(0.3, 0.0, SAT, VAL)
	check.call(
		by_phase.is_equal_approx(by_fraction),
		"phase を進めるのは fraction を進めるのと同じ (h %.3f == %.3f)" % [by_phase.h, by_fraction.h]
	)

	# fraction を 0→1 に動かすと色相が単調に増える(ラップ手前の 3 点で確認)。
	var lo := Rainbow.hue_at(0.1, 0.0, SAT, VAL)
	var mid := Rainbow.hue_at(0.4, 0.0, SAT, VAL)
	var hi := Rainbow.hue_at(0.7, 0.0, SAT, VAL)
	check.call(
		lo.h < mid.h and mid.h < hi.h,
		"fraction 0→1 で色相が単調に増える (%.3f < %.3f < %.3f)" % [lo.h, mid.h, hi.h]
	)

	# 位相を 1.0 進めると一周して同じ色に戻る(周期性)。
	var base := Rainbow.hue_at(0.2, 0.0, SAT, VAL)
	var looped := Rainbow.hue_at(0.2, 1.0, SAT, VAL)
	check.call(
		base.is_equal_approx(looped),
		"位相を 1.0 進めると同じ色に戻る (h %.3f -> %.3f)" % [base.h, looped.h]
	)

	# 彩度・明度は引数どおり反映される(色が有効な虹色になっている)。
	var c := Rainbow.hue_at(0.3, 0.0, SAT, VAL)
	check.call(
		is_equal_approx(c.s, SAT) and is_equal_approx(c.v, VAL),
		"彩度・明度が引数どおり (s=%.3f, v=%.3f)" % [c.s, c.v]
	)
