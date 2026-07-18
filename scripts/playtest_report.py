#!/usr/bin/env python3
"""テストプレイのJSONLを集計してMarkdownレポートを出す。

usage: playtest_report.py <data_dir>

読み方はdocs/playtest.md参照。数字の解釈で大事なのは、ボットの腕は
人間と同じではないこと。方針ごとの幅(下手random〜上手intercept)で読む。
"""
import json
import sys
from collections import defaultdict
from pathlib import Path

POLICY_ORDER = ["random", "aim_center", "aim_spawn", "intercept"]
SHAPE_NAMES = {0: "すり鉢", 1: "円錐"}

## アラートの基準となる腕。ここを全勝/全敗するなら誰がやっても同じ。
ALERT_POLICY = "intercept"
ALERT_REWARD = "greedy"

## この試行数に満たない段は、全勝でも「たまたま」なので断定しない。
## 20戦全勝なら、真の勝率が85%以下である確率は5%未満(0.85^20≒0.039)。
MIN_SAMPLES = 20

## アラートを出す勝率の帯。上下で非対称なのは理由がある。
##
## 「ちょうど0%/100%」だけを見ると壊れた段を取り逃す。敵のrpsを3000
## (絶対に倒せない)にしても勝率は2%であって0%にならなかった。たまたま
## 当たらずに相手が自滅する試合が残るため。0%も2%も同じく遊びがないので、
## 下限は0ちょうどではなく帯で見る。
##
## 一方、上は100%の際まで許している。導入の段をほぼ自動勝利にするのは
## 正当な設計で(現に段1は96.7%、段2は97.9%ある)、そこを鳴らすと誤報になる。
## 「一度も負けない」なら選択がないが、たまに負けるなら緊張はある。
##
## 逆に「20回に1回しか勝てない段」が意図的なことはまずないので、下限は緩い。
ALERT_LOW = 5.0
ALERT_HIGH = 99.0


def load(data_dir: Path):
    battles, runs = [], []
    for path in sorted(data_dir.glob("*.jsonl")):
        for line in path.open():
            rec = json.loads(line)
            # どのセル由来か記録する。単独パーツ計測(exp_*)を標準集計から
            # 切り離すのに使う。
            rec["_src"] = path.stem
            (runs if "battles" in rec else battles).append(rec)
    return battles, runs


def pct(n, d):
    return f"{100.0 * n / d:5.1f}%" if d else "  n/a"


def median(xs):
    xs = sorted(xs)
    return xs[len(xs) // 2] if xs else 0.0


def step_win_rates(runs):
    """ラン中の段ごとの勝率。実際に起きる組み合わせ(段相応に育った状態)。

    戦闘単体の表は初期性能のままの数字なので、Lv5が0%でも実プレイでは起きない。
    アラートはこちらで判定する。
    """
    by_step = defaultdict(lambda: [0, 0])  # step -> [試行, 勝ち]
    for r in runs:
        if r["policy"] != ALERT_POLICY or r["reward_policy"] != ALERT_REWARD:
            continue
        for b in r["battles"]:
            by_step[b["step"]][0] += 1
            by_step[b["step"]][1] += b["win"]
    return by_step


def alerts(runs, out):
    """勝率が0%か100%の段を検出する。

    どちらも「遊びが成立していない」。全勝なら何をしても勝つので選択に意味がなく、
    全敗なら何をしても負けるので理不尽。プレイヤーの入力が結果を変えない段は、
    そこにゲームがない。
    """
    by_step = step_win_rates(runs)
    if not by_step:
        return False

    problems, unsure = [], []
    for step in sorted(by_step):
        n, wins = by_step[step]
        rate = 100.0 * wins / n
        if ALERT_LOW < rate < ALERT_HIGH:
            continue
        too_easy = rate >= ALERT_HIGH
        kind = "全勝" if wins == n else ("ほぼ全勝" if too_easy else
               ("全敗" if wins == 0 else "ほぼ全敗"))
        if n < MIN_SAMPLES:
            unsure.append(f"段{step}: {kind}({wins}/{n})だが試行が少なく断定できない")
        else:
            problems.append(
                f"**段{step}: 勝率 {rate:.1f}% ({wins}/{n})** — {kind}。"
                + ("何をしても勝つので、そこに選択がない"
                   if too_easy else "何をしても負けるので理不尽")
            )

    out.append("## アラート\n")
    if problems:
        out.append(f"⚠️ **遊びが成立していない段が {len(problems)} 件ある。**\n")
        for p in problems:
            out.append(f"- {p}")
        out.append("")
    else:
        out.append(f"遊びが成立していない段はなし。\n")
    out.append(f"判定: {ALERT_POLICY}+{ALERT_REWARD} の勝率が "
               f"{ALERT_LOW:.0f}%以下 か {ALERT_HIGH:.0f}%以上 の段 "
               f"(n≧{MIN_SAMPLES})。ちょうど0%/100%だけを見ると取り逃す —— "
               f"敵を絶対に倒せない値にしても、たまたま相手が自滅する試合が残って "
               f"勝率は2%であって0%にならなかった。\n")
    if unsure:
        out.append("試行が少なく判定を保留した段:\n")
        for u in unsure:
            out.append(f"- {u}")
        out.append("")

    out.append("### ラン中の段ごとの勝率\n")
    out.append(f"({ALERT_POLICY}+{ALERT_REWARD}。段相応に育った状態＝実際に起きる組み合わせ)\n")
    out.append("| 段 | 勝率 | 試行 |")
    out.append("|---|---|---|")
    for step in sorted(by_step):
        n, wins = by_step[step]
        rate = 100.0 * wins / n
        flag = ""
        if rate <= ALERT_LOW or rate >= ALERT_HIGH:
            flag = " ⚠️" if n >= MIN_SAMPLES else " (n少)"
        out.append(f"| {step} | {pct(wins, n)}{flag} | {n} |")
    out.append("")
    return bool(problems)


def battle_tables(battles, out):
    default = [b for b in battles if abs(b["violence"] - 0.08) < 1e-9 and b["shape"] == 0]

    out.append("## 戦闘単体 (現行設定)\n")
    out.append("レベル×発射方針の勝率。1セル = "
               f"{len(default) // 20 if default else 0}戦。\n")
    out.append("| Lv | " + " | ".join(POLICY_ORDER) + " | 決着中央値 |")
    out.append("|---|" + "---|" * (len(POLICY_ORDER) + 1))
    for level in range(1, 6):
        row = [f"| {level} "]
        durations = []
        for policy in POLICY_ORDER:
            cell = [b for b in default if b["level"] == level and b["policy"] == policy]
            row.append(f"| {pct(sum(b['win'] for b in cell), len(cell))} ")
            durations += [b["finish_time"] for b in cell]
        row.append(f"| {median(durations):.1f}s |")
        out.append("".join(row))
    out.append("")

    timeouts = [b for b in battles if b["timed_out"]]
    zero_impact = [b for b in default if b["impacts"] == 0]
    out.append(f"- timeout(決着せず打ち切り): {pct(len(timeouts), len(battles))}")
    out.append(f"- 一度もぶつからない戦闘: {pct(len(zero_impact), len(default))}"
               " (発射が当たらず自然減衰だけで決まる＝運ゲーの割合)")
    out.append("")


def sweep_tables(battles, out):
    sweep = [b for b in battles if not (abs(b["violence"] - 0.08) < 1e-9 and b["shape"] == 0)]
    if not sweep:
        return
    out.append("## スイープ (intercept固定)\n")
    combos = sorted({(b["shape"], b["violence"]) for b in sweep} |
                    {(0, 0.08)})  # 現行設定も比較列に含める
    header = " | ".join(f"{SHAPE_NAMES[s]} v={v}" for s, v in combos)
    out.append("| Lv | " + header + " |")
    out.append("|---|" + "---|" * len(combos))
    pool = battles  # 現行設定セルはdefaultデータから拾う
    for level in range(1, 6):
        row = [f"| {level} "]
        for shape, violence in combos:
            cell = [b for b in pool
                    if b["level"] == level and b["shape"] == shape
                    and abs(b["violence"] - violence) < 1e-9
                    and b["policy"] == "intercept"]
            row.append(f"| {pct(sum(b['win'] for b in cell), len(cell))} ")
        out.append("".join(row) + "|")
    out.append("")


def run_tables(runs, out):
    out.append("## ラン全体\n")
    out.append("| 発射方針 | 報酬方針 | クリア率 | 勝ち抜き数中央値 |")
    out.append("|---|---|---|---|")
    cells = defaultdict(list)
    for r in runs:
        cells[(r["policy"], r["reward_policy"])].append(r)
    for (policy, reward), rs in sorted(cells.items()):
        cleared = sum(r["cleared"] for r in rs)
        out.append(f"| {policy} | {reward} | {pct(cleared, len(rs))} "
                   f"| {median([r['battles_won'] for r in rs])} |")
    out.append("")

    out.append("### ボス戦 (段9に到達したランのうち)\n")
    out.append("戦闘単体の表のLv5は初期性能のままの数字で、実プレイでは起きない"
               "(ボスは必ずパーツを積んだ状態で会う)。こちらが実際の勝率。\n")
    out.append("| 発射方針 | 報酬方針 | 到達率 | **ボス勝率** |")
    out.append("|---|---|---|---|")
    for (policy, reward), rs in sorted(cells.items()):
        reached = [r for r in rs if r["cleared"] or r["died_at_step"] == 9]
        cleared = sum(r["cleared"] for r in reached)
        out.append(f"| {policy} | {reward} | {pct(len(reached), len(rs))} "
                   f"| **{pct(cleared, len(reached))}** |")
    out.append("")

    out.append("### どの段で死ぬか (interceptのみ)\n")
    deaths = defaultdict(int)
    pool = [r for r in runs if r["policy"] == "intercept"]
    for r in pool:
        deaths["クリア" if r["cleared"] else f"段{r['died_at_step']}"] += 1
    for key in sorted(deaths, key=lambda k: (k == "クリア", k)):
        out.append(f"- {key}: {pct(deaths[key], len(pool))}")
    out.append("")

    out.append("### 土俵別の勝率 (intercept+greedy)\n")
    out.append("土俵は段ごとに一様抽選なので、どれも同じくらいの勝率になるはず。"
               "突出した土俵は、その形が有利/不利になっている兆候。\n")
    out.append("| 土俵 | 勝率 | 試行 |")
    out.append("|---|---|---|")
    by_field = defaultdict(lambda: [0, 0])
    for r in runs:
        if r["policy"] != ALERT_POLICY or r["reward_policy"] != ALERT_REWARD:
            continue
        for b in r["battles"]:
            by_field[b.get("field", "?")][0] += 1
            by_field[b.get("field", "?")][1] += b["win"]
    for name in sorted(by_field):
        n, wins = by_field[name]
        out.append(f"| {name} | {pct(wins, n)} | {n} |")
    out.append("")

    out.append("### パーツ別: 取ったランのクリア率 vs 取らなかったラン\n")
    out.append("(相関であって因果ではない。強い正の差＝そのパーツを取ると"
               "勝ちやすい兆候)\n")
    out.append("| パーツID | 取った(クリア率/数) | 取らない(クリア率/数) | 差 |")
    out.append("|---|---|---|---|")
    part_ids = sorted({p for r in runs for p in r["parts"]})
    for pid in part_ids:
        with_p = [r for r in runs if pid in r["parts"]]
        without = [r for r in runs if pid not in r["parts"]]
        cw = 100.0 * sum(r["cleared"] for r in with_p) / len(with_p) if with_p else 0
        co = 100.0 * sum(r["cleared"] for r in without) / len(without) if without else 0
        out.append(f"| {pid} | {cw:.0f}% / {len(with_p)} | {co:.0f}% / {len(without)} "
                   f"| {cw - co:+.0f}pt |")
    out.append("")


def death_cause_table(runs, out):
    # ラン中の各戦闘のうち「敵が敗北した」もの(＝プレイヤーの勝ち)を、敵の死因で
    # 分ける。単体と乱戦(複数体)を分けるのは、乱戦メンバーがrps÷頭数で耐久を
    # 割られており、混ぜると下限が守れているか見えなくなるため。
    # これは情報提供。アラート(終了コード)には配線しない。Lv1は設計上ズタズタに
    # される側なので、一撃死メトリクスで鳴らすと誤報になる。
    rows = {}  # (level, is_swarm) -> counters
    for r in runs:
        for b in r.get("battles", []):
            if b.get("loser") != "enemy":
                continue
            key = (b["level"], b.get("count", 1) > 1)
            c = rows.setdefault(key, {"n": 0, "drain": 0, "wall": 0, "decay": 0,
                                      "oneshot": 0, "hits": []})
            c["n"] += 1
            cause = b.get("death_cause", "decay")
            if cause in ("drain", "wall", "decay"):
                c[cause] += 1
            if b.get("fatal_hit_index", 0) == 1:
                c["oneshot"] += 1
            if cause == "drain":
                c["hits"].append(b.get("hits_taken", 0))
    if not rows:
        return

    out.append("## 死因の内訳 (敵の敗北, レベル×編成)\n")
    out.append("敵がどう力尽きたか。**1衝突で決着**が「衝突1回で終わる」割合。"
               "乱戦メンバーはrps÷頭数で耐久が割れるので単体と分ける。\n")
    out.append("| Lv | 編成 | n | 削り / 壁 / 自然減衰 | 1衝突で決着 | 削り死のhits中央値 |")
    out.append("|---|---|---|---|---|---|")
    for level in range(1, 6):
        for is_swarm in (False, True):
            c = rows.get((level, is_swarm))
            if not c or c["n"] == 0:
                continue
            comp = "乱戦" if is_swarm else "単体"
            split = (f"{pct(c['drain'], c['n'])} / {pct(c['wall'], c['n'])} "
                     f"/ {pct(c['decay'], c['n'])}")
            out.append(f"| {level} | {comp} | {c['n']} | {split} "
                       f"| {pct(c['oneshot'], c['n'])} | {median(c['hits']):.0f} |")
    out.append("")


def violations_table(battles, runs, out):
    bad = [b for b in battles if "violations" in b]
    for r in runs:
        for b in r.get("battles", []):
            if "violations" in b:
                bad.append({"seed": r["seed"], "violations": b["violations"],
                            "policy": r["policy"], "level": b["level"]})
    out.append("## 不変条件違反\n")
    if not bad:
        out.append("なし。\n")
        return False
    out.append(f"⚠️ **{len(bad)}件。** シードで再現できる:\n")
    for b in bad[:20]:
        out.append(f"- seed={b['seed']} lv={b.get('level')} policy={b.get('policy')}: "
                   f"{'; '.join(b['violations'])}")
    out.append("")
    return True


## 単独パーツ計測(--parts)で使うidと名前の対応。GDScriptのカタログと合わせる。
PART_NAMES = {
    2: "GIANT_GROWTH (半径)", 3: "OVERENCUMBERED (質量)",
    5: "FULL_STEAM_AHEAD (摩擦)", 6: "RAGE_REFLECTION (反発)",
    7: "SPIN_ENGINE (RPS)", 8: "SPARE_CORE (残機)", 9: "GHOST (無敵)",
}


def _clear_and_boss(runs, boss_step):
    """runs集合の (クリア率, ボス段の1戦あたり勝率, ラン数) を出す。"""
    n = len(runs)
    cleared = sum(r["cleared"] for r in runs)
    b_att = b_win = 0
    for r in runs:
        for b in r["battles"]:
            if b["step"] == boss_step:
                b_att += 1
                b_win += b["win"]
    return cleared, n, b_win, b_att


def part_effect_table(exp_runs, out):
    """単独パーツ強化の因果効果。force-partセル(--parts)があるときだけ出す。

    同条件のbaseline(強制なしgreedy)に対し、その札だけ出るたび必ず取ったランの
    クリア率とボス段勝率がどれだけ動いたか。相関表(取った/取らない)と違い、
    札の取得自体を実験操作しているので因果に近い。greedyが構造的に選ばない
    SET_LIVES/GHOST(id8/9)もここで測れる。
    """
    if not exp_runs:
        return
    boss_step = max((b["step"] for r in exp_runs for b in r["battles"]), default=0)
    policies = [p for p in POLICY_ORDER
                if any(r["policy"] == p for r in exp_runs)]

    out.append("## 単独パーツ強化の因果効果 (force-part)\n")
    out.append(f"baseline=強制なしgreedy。各札を「出るたび必ず取る」ランと比較。"
               f"ボス段=step{boss_step}の1戦あたり勝率。差はbaseline比(pt)。\n")
    for policy in policies:
        pol = [r for r in exp_runs if r["policy"] == policy]
        base = [r for r in pol if r["reward_policy"] != "forced"]
        if not base:
            continue
        bc, bn, bbw, bba = _clear_and_boss(base, boss_step)
        base_clear = 100.0 * bc / bn if bn else 0.0
        base_boss = 100.0 * bbw / bba if bba else 0.0
        out.append(f"### 腕={policy}\n")
        out.append(f"baseline: クリア率 {base_clear:.1f}% (n={bn}) / "
                   f"ボス段勝率 {base_boss:.1f}% (n={bba})\n")
        out.append("| パーツ | クリア率 | Δクリア | ボス段勝率 | Δボス |")
        out.append("|---|---|---|---|---|")
        forced = defaultdict(list)
        for r in pol:
            if r["reward_policy"] == "forced":
                forced[r["force_part_id"]].append(r)
        for pid in sorted(forced):
            c, n, bw, ba = _clear_and_boss(forced[pid], boss_step)
            clear = 100.0 * c / n if n else 0.0
            boss = 100.0 * bw / ba if ba else 0.0
            name = PART_NAMES.get(pid, f"id{pid}")
            out.append(f"| {name} | {clear:.1f}% | {clear - base_clear:+.1f}pt "
                       f"| {boss:.1f}% | {boss - base_boss:+.1f}pt |")
        out.append("")


def main() -> int:
    data_dir = Path(sys.argv[1])
    battles, runs = load(data_dir)
    # 単独パーツ計測(exp_*)は2000ラン規模の実験なので、標準の集計・アラートには
    # 混ぜず切り離す。標準の数字を--partsの有無で揺らさないため。
    std_runs = [r for r in runs if not r["_src"].startswith("exp_")]
    exp_runs = [r for r in runs if r["_src"].startswith("exp_")]
    out = [f"# テストプレイレポート\n",
           f"戦闘 {len(battles)}件 / ラン {len(std_runs)}件"
           + (f" / 単独パーツ計測 {len(exp_runs)}件" if exp_runs else "") + "\n"]

    # アラートは先頭に置く。末尾だと読まれない。
    alerted = alerts(std_runs, out) if std_runs else False
    if battles:
        battle_tables(battles, out)
        sweep_tables(battles, out)
    if std_runs:
        run_tables(std_runs, out)
        death_cause_table(std_runs, out)
    part_effect_table(exp_runs, out)
    # 不変条件違反は全ラン(exp含む)から拾う。
    violated = violations_table(battles, runs, out)
    print("\n".join(out))
    # 呼び出し側(playtest.sh)が気づけるよう終了コードにも出す。
    return 1 if (alerted or violated) else 0


if __name__ == "__main__":
    sys.exit(main())
