class_name RetryPlan
extends RefCounted

## 敗北後の再挑戦で「何を据え置き、何を引き直すか」の規則。
##
## これまでリトライは相手を必ず同レベルの別個体へ入れ替えていた
## (EnemyRoster.reroll_group)。位置しか変わらない同型再戦の徒労感への対策だったが、
## 今度は逆の穴が空いた——**負けた相手にもう一度挑めない**。2026-08-05 の
## コールドプレイでは決戦で2連敗し3回目に勝ったが、3回とも別個体
## (硬さ 12.56 / 12.53 / 12.07)で、勝ったのが自分の判断の成果なのか引き直しの
## 成果なのか最後まで分からなかった。反省が効かないので、負けが学びにならない。
##
## そこで「据え置く/引き直す」をプレイヤーの選択にする。
##
## same_opponent=true(同じ相手に挑む): 個体も出現の種も据え置く。予告が1ドットも
##   変わらないので、負けた立ち合いをそっくりやり直せる＝狙いを変えた効果だけが
##   結果に出る。統計的には「自分が負けた相手」なので引き直しより手強いはずで、
##   そのぶん勝てば自分の手柄だと分かる。
## same_opponent=false(相手を替えて挑む): 同レベルの別個体へ入れ替え、出現の種も
##   引き直す。どうしても噛み合わない相手から降りるための逃げ道。従来の挙動。
##
## 実UI(Main._on_continue_requested)とコールドプレイCLI(naive_play retry)の2経路が
## ここを通る。片方だけ変えると「CLIと実ゲームが別のゲームになる」ので、規則は
## ここに1つだけ置く(EnemySpawn.Group と同じ方針)。


## 再挑戦する相手。据え置きならそのまま、替えるなら同レベルの別個体へ。
static func next_enemies(
	current: Array[EnemyData], same_opponent: bool, rng: RandomNumberGenerator
) -> Array[EnemyData]:
	if same_opponent:
		return current
	return EnemyRoster.reroll_group(current, rng)


## 再挑戦の出現(位置・向き・速度・乱戦の回り込み)を決める種。
## 据え置きなら同じ種＝同じ予告。
static func next_spawn_seed(
	current_seed: int, same_opponent: bool, rng: RandomNumberGenerator
) -> int:
	if same_opponent:
		return current_seed
	# 引き直したのに同じ種を引くと、予告が1ドットも変わらないまま「相手を替えた」と
	# 名乗ることになる。別の値が出るまで引く(reroll_groupが必ず別個体を返すのと
	# 同じ約束を、出現の側でも守る)。
	var next := rng.randi()
	while next == current_seed:
		next = rng.randi()
	return next
