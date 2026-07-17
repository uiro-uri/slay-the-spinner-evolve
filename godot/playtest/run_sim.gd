class_name RunSim
extends RefCounted

## 1ラン(タイトル→マップ→戦闘→報酬→…→ボスorゲームオーバー)を丸ごと回す。
##
## ローグライクのバランス(パーツの強弱、どの段で死ぬか、RPSのインフレ)は
## ラン全体でしか測れない。Main.gdの進行(段→敵、勝利→報酬3枚から1枚)を
## 最小限に写しているので、Main.gd側の進行を変えたらここも見ること。
## 報酬の枚数はCustomPartCatalog.REWARD_CHOICES(画面と共有)を参照する。

enum RewardPolicy {
	## 3枚から一様ランダム。何も考えない人。
	RANDOM,
	## 雑な強さ順で選ぶ。回転>縮小>摩擦>反発>他。人間の柔軟さには届かないが、
	## 「考えて選ぶ人」の近似として。
	GREEDY,
}

const REWARD_NAMES := {
	RewardPolicy.RANDOM: "random",
	RewardPolicy.GREEDY: "greedy",
}

## GREEDYの選好。パーツの対象ステータスへの雑なスコア。
const GREEDY_SCORE := {
	CustomPart.Stat.RPS: 5,
	CustomPart.Stat.RADIUS: 3,   # 縮小前提(倍率<1で加点を反転する)
	CustomPart.Stat.FRICTION: 2,
	CustomPart.Stat.RESTITUTION: 1,
	CustomPart.Stat.MASS: 1,
}


static func reward_by_name(name: String) -> RewardPolicy:
	for kind in REWARD_NAMES:
		if REWARD_NAMES[kind] == name:
			return kind
	push_error("RunSim: 未知の報酬方針 '%s'" % name)
	return RewardPolicy.RANDOM


## 1ラン。シードが同じなら結果も同じ。
static func play_one(
	seed_value: int,
	launch_policy: LaunchPolicy.Kind,
	reward_policy: RewardPolicy,
	overrides: BattleSim.Overrides = null
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var stats := SpinnerStats.default_player()
	var tree := MapTree.generate(rng)
	if tree == null:
		return {"seed": seed_value, "error": "map_generation_failed"}

	var battles: Array = []
	var parts: Array = []
	var won_all := false

	while true:
		# 経路はランダムに選ぶ(人間の経路選びは今のマップでは差がつかない:
		# ノード種別が全部敵なので、どこを通っても戦闘数は同じ)
		var nexts := tree.next_coords()
		if nexts.is_empty():
			break
		tree.advance_to(nexts[rng.randi_range(0, nexts.size() - 1)])

		var enemy := EnemyRoster.pick_for_step(tree.current_step(), rng)
		var record := BattleSim.play_one(
			rng.randi(), enemy, launch_policy, stats, overrides
		)
		battles.append({
			"step": tree.current_step(),
			"level": record["level"],
			"win": record["win"],
			"finish_time": record["finish_time"],
			"rps_before": stats.rps,
		})
		if record.has("violations"):
			battles[battles.size() - 1]["violations"] = record["violations"]

		if not record["win"]:
			break

		if tree.is_goal():
			won_all = true
			break

		# 勝利報酬。Main._on_part_chosenと同じ適用。
		var choices := CustomPartCatalog.pick_choices(CustomPartCatalog.REWARD_CHOICES, rng)
		var part := _choose_part(choices, reward_policy, rng)
		part.apply_to(stats)
		parts.append(part.id)

	return {
		"seed": seed_value,
		"policy": LaunchPolicy.NAMES[launch_policy],
		"reward_policy": REWARD_NAMES[reward_policy],
		"cleared": won_all,
		"died_at_step": -1 if won_all else tree.current_step(),
		"battles_won": battles.filter(func(b): return b["win"]).size(),
		"parts": parts,
		"final_rps": stats.rps,
		"final_radius": stats.radius,
		"final_mass": stats.mass,
		"battles": battles,
	}


static func _choose_part(
	choices: Array[CustomPart], policy: RewardPolicy, rng: RandomNumberGenerator
) -> CustomPart:
	if policy == RewardPolicy.RANDOM:
		return choices[rng.randi_range(0, choices.size() - 1)]

	var best: CustomPart = choices[0]
	var best_score := -INF
	for part in choices:
		var score := float(GREEDY_SCORE.get(part.stat, 0))
		# 「下げる」パーツは、下げて嬉しいステータス(半径・摩擦)なら加点のまま、
		# 上げて嬉しいステータスなら減点に反転する。
		var wants_lower := part.stat == CustomPart.Stat.RADIUS or part.stat == CustomPart.Stat.FRICTION
		if part.multiplier < 1.0 and not wants_lower:
			score = -score
		if part.multiplier > 1.0 and wants_lower:
			score = -score
		if score > best_score:
			best_score = score
			best = part
	return best
