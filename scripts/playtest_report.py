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


def main() -> int:
    data_dir = Path(sys.argv[1])
    battles, runs = load(data_dir)
    out = [f"# テストプレイレポート\n",
           f"戦闘 {len(battles)}件 / ラン {len(runs)}件\n"]

    # アラートは先頭に置く。末尾だと読まれない。
    alerted = alerts(runs, out) if runs else False
    if battles:
        battle_tables(battles, out)
        sweep_tables(battles, out)
    if runs:
        run_tables(runs, out)
    violated = violations_table(battles, runs, out)
    print("\n".join(out))
    # 呼び出し側(playtest.sh)が気づけるよう終了コードにも出す。
    return 1 if (alerted or violated) else 0


if __name__ == "__main__":
    sys.exit(main())
