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

    out.append("### どの段で死ぬか (interceptのみ)\n")
    deaths = defaultdict(int)
    pool = [r for r in runs if r["policy"] == "intercept"]
    for r in pool:
        deaths["クリア" if r["cleared"] else f"段{r['died_at_step']}"] += 1
    for key in sorted(deaths, key=lambda k: (k == "クリア", k)):
        out.append(f"- {key}: {pct(deaths[key], len(pool))}")
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
        return
    out.append(f"**{len(bad)}件。** シードで再現できる:\n")
    for b in bad[:20]:
        out.append(f"- seed={b['seed']} lv={b.get('level')} policy={b.get('policy')}: "
                   f"{'; '.join(b['violations'])}")
    out.append("")


def main():
    data_dir = Path(sys.argv[1])
    battles, runs = load(data_dir)
    out = [f"# テストプレイレポート\n",
           f"戦闘 {len(battles)}件 / ラン {len(runs)}件\n"]
    if battles:
        battle_tables(battles, out)
        sweep_tables(battles, out)
    if runs:
        run_tables(runs, out)
    violations_table(battles, runs, out)
    print("\n".join(out))


if __name__ == "__main__":
    main()
