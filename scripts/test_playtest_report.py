#!/usr/bin/env python3
"""playtest_report.py の集計のテスト。

    python3 scripts/test_playtest_report.py

verify.sh(CI)には乗っていない——あちらはゲーム本体の門番で、ここは
テストプレイの集計ツール。バランスを触るサイクルで playtest.sh を
回す前に手で走らせること。

守りたいのは1点だけ: **「現行設定」のセルを値の決め打ちで探さない。**
かつては `violence == 0.08` という決め打ちで、既定が 0.16 に変わった
時点で「戦闘単体(現行設定)」の表が全セル n/a のまま数サイクル出続けた。
データは消えておらず、条件に一致しなくなっただけだった。
"""
import importlib.util
import sys
import unittest
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location(
    "playtest_report", Path(__file__).with_name("playtest_report.py")
)
report = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(report)


# 現行の既定(BattleRequest.violence)。ここを変えてもテストは通らねばならない
# ——それが「決め打ちしていない」ことの検査になる。
CURRENT_VIOLENCE = 0.16


def battle(src, level, policy, win, violence=CURRENT_VIOLENCE, shape=0):
    return {
        "_src": src, "level": level, "policy": policy, "win": win,
        "violence": violence, "shape": shape,
        "finish_time": 3.0, "timed_out": False, "impacts": 2,
    }


def default_cells(violence=CURRENT_VIOLENCE):
    """playtest.sh の標準セット相当。4方針×5レベル、各1戦。"""
    out = []
    for policy in report.POLICY_ORDER:
        for level in range(1, 6):
            out.append(battle(f"battle_default_{policy}_lv{level}",
                              level, policy, win=1, violence=violence))
    return out


class DefaultSetting(unittest.TestCase):
    def test_reads_setting_from_data_not_a_constant(self):
        # 既定値が何であれ、由来がdefaultなら現行設定として読めること。
        for violence in (0.04, 0.08, CURRENT_VIOLENCE, 0.99):
            with self.subTest(violence=violence):
                self.assertEqual(
                    report.default_setting(default_cells(violence)),
                    (0, violence),
                )

    def test_sweep_cells_do_not_define_the_setting(self):
        # スイープが同居していても、現行設定はdefault由来だけで決まる。
        battles = default_cells() + [
            battle("sweep_s1_v0.04_lv3", 3, "intercept", win=0,
                   violence=0.04, shape=1)
            for _ in range(50)
        ]
        self.assertEqual(report.default_setting(battles), (0, CURRENT_VIOLENCE))

    def test_no_default_cells(self):
        sweep = [battle("sweep_s0_v0.04_lv1", 1, "intercept", win=1, violence=0.04)]
        self.assertIsNone(report.default_setting(sweep))


class BattleTable(unittest.TestCase):
    def test_cells_are_populated(self):
        out = []
        alerted = report.battle_tables(default_cells(), out)
        text = "\n".join(out)
        self.assertFalse(alerted)
        # 決め打ちに戻すとここが全部 n/a になる(表が空のまま出続けた状態)。
        self.assertNotIn("n/a", text)
        self.assertIn("100.0%", text)
        self.assertIn("1セル = 1戦", text)

    def test_heading_names_the_actual_setting(self):
        out = []
        report.battle_tables(default_cells(), out)
        self.assertIn(f"現行設定: すり鉢 v={CURRENT_VIOLENCE}", "\n".join(out))

    def test_missing_default_data_is_an_alert(self):
        # 集計と playtest.sh のファイル名がずれたら黙って n/a を並べない。
        sweep = [battle("sweep_s0_v0.04_lv1", 1, "intercept", win=1, violence=0.04)]
        out = []
        alerted = report.battle_tables(sweep, out)
        self.assertTrue(alerted)
        self.assertIn("⚠️", "\n".join(out))


class SweepTable(unittest.TestCase):
    def test_current_setting_column_carries_default_data(self):
        battles = default_cells() + [
            battle("sweep_s1_v0.04_lv1", 1, "intercept", win=0,
                   violence=0.04, shape=1)
        ]
        out = []
        report.sweep_tables(battles, out)
        text = "\n".join(out)
        # 現行設定の列が見出しにあり、かつ中身が n/a でない。
        self.assertIn(f"すり鉢 v={CURRENT_VIOLENCE}", text)
        self.assertIn("円錐 v=0.04", text)
        self.assertIn("100.0%", text)

    def test_no_phantom_column_for_a_setting_nobody_ran(self):
        battles = default_cells() + [
            battle("sweep_s1_v0.04_lv1", 1, "intercept", win=0,
                   violence=0.04, shape=1)
        ]
        out = []
        report.sweep_tables(battles, out)
        self.assertNotIn("すり鉢 v=0.08", "\n".join(out))

    def test_skipped_without_sweep_data(self):
        out = []
        report.sweep_tables(default_cells(), out)
        self.assertEqual(out, [])

    def test_unknown_source_is_not_folded_into_the_sweep(self):
        # スイープも現行設定も、由来で名指しして拾う。「defaultでないもの」で
        # 拾うと、将来 add_battle_jobs に3つ目のタグが増えた日に、その計測が
        # 黙ってスイープの列として混ざる(見出しは v=... としか言わないので
        # 別物だと気づけない)。
        battles = default_cells() + [
            battle("battle_cone_intercept_lv1", 1, "intercept", win=0,
                   violence=0.30, shape=1)
        ]
        out = []
        report.sweep_tables(battles, out)
        self.assertEqual(out, [])


if __name__ == "__main__":
    sys.exit(0 if unittest.main(exit=False).result.wasSuccessful() else 1)
