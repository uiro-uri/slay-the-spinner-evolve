class_name RunSim
extends RefCounted

## 1ラン(タイトル→マップ→戦闘→報酬→…→ボスorゲームオーバー)を丸ごと回す。
##
## ローグライクのバランス(パーツの強弱、どの段で死ぬか、RPSのインフレ)は
## ラン全体でしか測れない。Main.gdの進行(段→敵と土俵、勝利→報酬3枚から1枚)を
## 最小限に写しているので、Main.gd側の進行を変えたらここも見ること。
## 報酬の枚数はCustomPartCatalog.REWARD_CHOICES(画面と共有)を参照する。

enum RewardPolicy {
	## 3枚から一様ランダム。何も考えない人。
	RANDOM,
	## 一番硬くなる札を取る。人間の柔軟さには届かないが「考えて選ぶ人」の近似。
	GREEDY,
}

const REWARD_NAMES := {
	RewardPolicy.RANDOM: "random",
	RewardPolicy.GREEDY: "greedy",
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

		# Main._on_map_node_chosen と同じく、進んだノードに確定済みの遭遇を使う
		# （マップ生成時に決まっている。実戦とシミュレーションの遭遇を一致させる）。
		var node: MapTree.MapNode = tree.nodes[tree.current_coord]
		var group := node.enemies
		var field := node.field
		var record := BattleSim.play_one(
			rng.randi(), group, launch_policy, stats, overrides, field
		)
		battles.append({
			"step": tree.current_step(),
			"level": record["level"],
			"count": record["count"],
			"field": record["field"],
			"win": record["win"],
			"finish_time": record["finish_time"],
			"rps_before": stats.rps,
			"mass_before": stats.mass,
			"radius_before": stats.radius,
			"death_cause": record.get("death_cause", "none"),
			"loser": record.get("loser", "none"),
			"fatal_hit_index": record.get("fatal_hit_index", 0),
			"hits_taken": record.get("hits_taken", 0),
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
		var part := _choose_part(choices, reward_policy, rng, stats)
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


## 「耐えられる衝突回数」の目安。
##
## 1衝突で失うRPSは violence×(相手質量×相手速さ)÷(自分質量×自分半径²) なので、
## 何発耐えられるかは rps×自分質量×自分半径² に比例する。この式が
## 勝敗をほぼ決めているので、これを最大化する札を取るのが「考えて選ぶ人」。
##
## 最初はステータスごとの好みを手で並べていたが、それだと半径が2乗で効くことを
## 見落として Shrink(半径×0.5) を良い札として選んでしまい、「上手い人」のはずが
## 耐久を1/4にしていた。式から出す方が間違えない。
static func toughness(stats: SpinnerStats) -> float:
	return stats.rps * stats.mass * stats.radius * stats.radius


static func _choose_part(
	choices: Array[CustomPart], policy: RewardPolicy, rng: RandomNumberGenerator,
	stats: SpinnerStats
) -> CustomPart:
	if policy == RewardPolicy.RANDOM:
		return choices[rng.randi_range(0, choices.size() - 1)]

	var best: CustomPart = choices[0]
	var best_score := -INF
	for part in choices:
		# 実際に適用してみて測る。上限に当たって効かない札もここで分かる。
		var probe := stats.duplicate_stats()
		part.apply_to(probe)
		var score := toughness(probe)
		# 硬さが変わらない札(摩擦・反発)は速さで比べる。摩擦が低いほど、
		# 反発が高いほど、当たったときに削れる量が増える。
		score += (2.0 - probe.friction) * 0.01 + probe.restitution * 0.01
		if score > best_score:
			best_score = score
			best = part
	return best
