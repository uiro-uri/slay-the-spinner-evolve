#!/usr/bin/env bash
#
# 並列テストプレイの親。ボット群で戦闘とランを大量に回し、レポートを出す。
#
#   scripts/playtest.sh                 標準セット(戦闘＋ラン)
#   scripts/playtest.sh --sweep         スイープ(すり鉢/円錐 × violence)も回す
#   scripts/playtest.sh --quick         セル当たりの試行を1/10に(動作確認用)
#
# セルごとに1つのgodotプロセスを起こし、nproc並列でばら撒く。シード範囲が
# 同じなら結果も同じ(決定的)。出力: build/playtest/report.md と生JSONL。
#
# 環境変数:
#   GODOT_BIN   godotバイナリ (既定: PATHのgodot4/godot, なければ ~/bin/godot4)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/build/playtest"
VENV="$HOME/.cache/slay-the-spinner/venv"

BATTLES_PER_CELL=500
RUNS_PER_CELL=300
SWEEP=0
for arg in "$@"; do
  case "$arg" in
    --sweep) SWEEP=1 ;;
    --quick) BATTLES_PER_CELL=50; RUNS_PER_CELL=30 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

if [[ -z "${GODOT_BIN:-}" ]]; then
  if command -v godot4 >/dev/null 2>&1; then GODOT_BIN="$(command -v godot4)"
  elif command -v godot >/dev/null 2>&1; then GODOT_BIN="$(command -v godot)"
  else GODOT_BIN="$HOME/bin/godot4"; fi
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/data"

# インポート済みでないと class_name が解決しない
"$GODOT_BIN" --headless --path "$REPO_ROOT/godot" --import >/dev/null 2>&1 || true

# ジョブ一覧を組み立てる。1行 = 1プロセス。シードはセルごとに固定の
# オフセットから振る(同じコマンドは常に同じ結果になる)。
jobs_file="$(mktemp)"
seed_base=0

add_battle_jobs() {
  local shape="$1" violence="$2" tag="$3"
  for policy in random aim_center aim_spawn intercept; do
    for level in 1 2 3 4 5; do
      local out="$OUT_DIR/data/battle_${tag}_${policy}_lv${level}.jsonl"
      local extra=""
      [[ "$shape" != "-" ]] && extra+=" --shape=$shape"
      [[ "$violence" != "-" ]] && extra+=" --violence=$violence"
      echo "$GODOT_BIN --headless --path $REPO_ROOT/godot --script res://playtest/playtest_main.gd -- --mode=battle --seed-start=$seed_base --count=$BATTLES_PER_CELL --policy=$policy --level=$level$extra --out=$out" >>"$jobs_file"
      seed_base=$((seed_base + 100000))
    done
  done
}

# 標準セット: 現行設定
add_battle_jobs "-" "-" "default"

# ラン: 発射方針 × 報酬方針
for policy in random intercept; do
  for reward in random greedy; do
    out="$OUT_DIR/data/run_${policy}_${reward}.jsonl"
    echo "$GODOT_BIN --headless --path $REPO_ROOT/godot --script res://playtest/playtest_main.gd -- --mode=run --seed-start=$seed_base --count=$RUNS_PER_CELL --policy=$policy --reward=$reward --out=$out" >>"$jobs_file"
    seed_base=$((seed_base + 100000))
  done
done

# スイープ: 形状 × violence (発射はintercept固定で条件だけ比較する)
if [[ $SWEEP -eq 1 ]]; then
  for shape in 0 1; do
    for violence in 0.04 0.08 0.16; do
      for level in 1 2 3 4 5; do
        out="$OUT_DIR/data/sweep_s${shape}_v${violence}_lv${level}.jsonl"
        echo "$GODOT_BIN --headless --path $REPO_ROOT/godot --script res://playtest/playtest_main.gd -- --mode=battle --seed-start=$seed_base --count=$BATTLES_PER_CELL --policy=intercept --level=$level --shape=$shape --violence=$violence --out=$out" >>"$jobs_file"
        seed_base=$((seed_base + 100000))
      done
    done
  done
fi

total_jobs="$(wc -l <"$jobs_file")"
para="$(nproc)"
echo "ジョブ ${total_jobs}件を ${para}並列で実行..."
t0=$(date +%s)

# 1行1コマンドをxargsでばら撒く。どれかが失敗したら止まらず最後に報告。
xargs -P "$para" -I{} bash -c '{}' <"$jobs_file" >"$OUT_DIR/jobs.log" 2>&1
rc=$?

t1=$(date +%s)
echo "完了 ($((t1 - t0))秒)。failures=$(grep -c 'SCRIPT ERROR' "$OUT_DIR/jobs.log" || true)"
rm -f "$jobs_file"

if [[ $rc -ne 0 ]]; then
  echo "一部のジョブが失敗。$OUT_DIR/jobs.log を確認" >&2
fi

"$VENV/bin/python" "$REPO_ROOT/scripts/playtest_report.py" "$OUT_DIR/data" >"$OUT_DIR/report.md"
report_rc=$?
echo "レポート: $OUT_DIR/report.md"
echo

# アラート(勝率0%/100%の段、不変条件違反)はレポートの先頭に出る。
# 埋もれないようここにも出し、終了コードにも乗せる。
sed -n '/^## アラート/,/^### ラン中の段ごとの勝率/p' "$OUT_DIR/report.md" | sed '$d'
grep -A6 '^## 不変条件違反' "$OUT_DIR/report.md"

if [[ $report_rc -ne 0 ]]; then
  echo
  echo "⚠️  遊びが成立していない段か、不変条件違反がある。上記とレポートを確認すること。"
  exit 1
fi
