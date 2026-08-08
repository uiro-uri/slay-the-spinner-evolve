extends SceneTree

## ラン終了時点の**攻めの倍率**(攻め力・弾き)の到達分布を測る計測スクリプト。
##
##   godot --headless --path godot --script res://playtest/measure_offense_index.gd -- [--runs=1200] [--reward=greedy]
##
## 動機: 対戦画面のビルド表示(StatReadout)に攻めの2行を足すにあたって、
## バーの上端(ATTACK_INDEX_MAX / KNOCKBACK_INDEX_MAX)を決め打ちたくない。
## 倍率は出発点が必ず 1.00 なので、他の行の「初期ビルドが中央に来るよう約2倍」という
## 規則が使えない(伸びる一方の軸)。実際のランがどこまで伸びるかを測って、
## 上位1割が振り切れる位置に上端を置く。
##
## 測り方: RunSim.play_one を回して**取った札のid列**を拾い、素のコマへ順に適用して
## 最終ビルドを組み直す。攻め力・弾きはどちらも rps を読まない(PartPreview.attack /
## knockback の式を参照)ので、勝利成長ぶんのrpsを持たないこの再構成で厳密に一致する。
## 死んだランも「そのランが積めた枚数」として数える(HUDはラン中ずっと出ているので、
## 途中の値こそが実際に見られる値)。

const DEFAULT_RUNS := 1200


func _init() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var eq := arg.find("=")
			args[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	var runs := int(args.get("runs", str(DEFAULT_RUNS)))
	var reward := RunSim.reward_by_name(args.get("reward", "greedy"))
	var launch := LaunchPolicy.by_name(args.get("launch", "intercept"))

	var base := SpinnerStats.default_player()
	print("# ラン終了時点の攻めの倍率 (報酬=%s, 発射=%s, runs=%d)" % [
		RunSim.REWARD_NAMES[reward], LaunchPolicy.NAMES[launch], runs])
	print("# 素のコマ基準(=1.00)。基準の相手も素のコマ。")

	var attacks: Array[float] = []
	var knockbacks: Array[float] = []
	var cards: Array[float] = []
	for i in runs:
		var result := RunSim.play_one(i + 1, launch, reward)
		if result.has("error"):
			continue
		var stats := base.duplicate_stats()
		for id in result["parts"]:
			var part := CustomPartCatalog.by_id(int(id))
			if part != null:
				part.apply_to(stats)
		attacks.append(StatReadout.attack_index(stats))
		knockbacks.append(StatReadout.knockback_index(stats))
		cards.append(float((result["parts"] as Array).size()))

	_report("攻め力", attacks)
	_report("弾き", knockbacks)
	_report("積んだ枚数", cards)
	quit()


func _report(label: String, values: Array[float]) -> void:
	if values.is_empty():
		print("%s: サンプル無し" % label)
		return
	values.sort()
	print("%s: n=%d 最小%.2f p50 %.2f p75 %.2f p90 %.2f p99 %.2f 最大%.2f" % [
		label, values.size(), values[0],
		_percentile(values, 0.50), _percentile(values, 0.75),
		_percentile(values, 0.90), _percentile(values, 0.99),
		values[values.size() - 1]])


## 昇順に並んだ values の分位点。index は最近傍で取る(分布の形しか見ないので補間は不要)。
func _percentile(values: Array[float], q: float) -> float:
	var idx := int(round(q * (values.size() - 1)))
	return values[clampi(idx, 0, values.size() - 1)]
