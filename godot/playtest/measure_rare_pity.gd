extends SceneTree

## RAREの天井(CustomPartCatalog.RARE_PITY_OFFERS)の効き目を測る診断。
##
##   godot --headless --path godot --script res://playtest/measure_rare_pity.gd -- [--count=600]
##
## 動機はコールドプレイ(2026-08-04)。段1〜4で5回の提示=15枚を見てRAREが0枚、
## 素の自機に近いまま段5(Lv3×2体)で4連敗してラン終了した。出現率は妥当でも
## **1枚も引けないランが存在すること**そのものが詰みになる、という仮説を測る。
##
## 天井 on/off を同じシードで並べる(RunSim.play_one の rare_pity)。読みたいのは2つ:
##   1. off での「RAREを1枚も見ないままのラン」の割合と、初RAREまでの提示回数
##      —— 天井の閾値を決める根拠になる分布。
##   2. on/off のクリア率の差 —— 天井は**下振れの深さを切る**だけで平均を上げない、
##      という設計意図が守れているか。上がり過ぎるなら閾値が緩すぎる。
##
## ボットは人間ではないので、勝率は方針の幅で読む(docs/playtest.md)。

const POLICIES := ["random", "intercept"]


func _init() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var eq := arg.find("=")
			args[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	var count := int(args.get("count", "600"))
	var reward := RunSim.reward_by_name(args.get("reward", "greedy"))

	print("# RAREの天井スイープ (報酬方針=%s, 各セル%dラン)" % [
		RunSim.REWARD_NAMES[reward], count
	])
	print("# 天井=CustomPartCatalog.RARE_PITY_OFFERS=%d。offは天井導入前と同じ抽選。"
		% CustomPartCatalog.RARE_PITY_OFFERS)
	print("# 同じシード範囲をon/offで並べるので、差は天井だけに由来する。")

	for policy_name in POLICIES:
		var policy := LaunchPolicy.by_name(policy_name)
		print("\n## 発射方針=%s" % policy_name)
		print("| 天井 | クリア率 | 提示/ラン | RARE入り提示 | 初RAREまでの提示 | RARE皆無のラン | 死亡段(中央値) |")
		print("|---|---|---|---|---|---|---|")
		_row(policy, reward, count, false)
		_row(policy, reward, count, true)
	quit(0)


func _row(policy: LaunchPolicy.Kind, reward: RunSim.RewardPolicy, count: int, pity: bool) -> void:
	var cleared := 0
	var offers := 0
	var rare_offers := 0
	var no_rare_runs := 0
	var first_sum := 0
	var first_n := 0
	var death_steps: Array[int] = []
	for i in count:
		var run := RunSim.play_one(i + 1, policy, reward, null, 0, pity)
		if run.get("error", "") != "":
			continue
		if bool(run["cleared"]):
			cleared += 1
		else:
			death_steps.append(int(run["died_at_step"]))
		offers += int(run["offers"])
		rare_offers += int(run["rare_offers"])
		var first := int(run["first_rare_offer"])
		if first < 0:
			no_rare_runs += 1
		else:
			first_sum += first
			first_n += 1
	print("| %s | %.1f%% | %.1f | %.1f%% | %.2f | %.1f%% | %s |" % [
		"on" if pity else "off",
		100.0 * float(cleared) / float(count),
		float(offers) / float(count),
		100.0 * float(rare_offers) / maxf(float(offers), 1.0),
		float(first_sum) / maxf(float(first_n), 1.0),
		100.0 * float(no_rare_runs) / float(count),
		_median(death_steps),
	])


func _median(values: Array[int]) -> String:
	if values.is_empty():
		return "-"
	values.sort()
	return str(values[values.size() / 2])
