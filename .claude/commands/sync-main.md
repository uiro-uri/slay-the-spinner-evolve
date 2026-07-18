---
description: 現在のブランチに最新 origin/main を取り込み、衝突を解消して verify 後に push する
argument-hint: "[WEB_PORT]"
allowed-tools: Bash(git branch:*), Bash(git status:*), Bash(git fetch:*), Bash(git merge:*), Bash(git merge-base:*), Bash(git rev-list:*), Bash(git diff:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(scripts/verify.sh:*)
---

現在のフィーチャーブランチに最新の `origin/main` を取り込み、衝突があれば解消し、
`scripts/verify.sh` が緑になってから push する。**下の手順を上から順に実行すること。**
取り込み戦略は **merge**（rebase は使わない。push 済みブランチの force-push を避ける）。

## 前提

- `$ARGUMENTS` に値があればそれを `WEB_PORT` として `scripts/verify.sh` に渡す
  （並行セッションでポート 8099 が衝突しうるため。CLAUDE.md の検証ガード参照）。

## 手順

1. **前提チェック**
   - `git branch --show-current` で現在ブランチを取得。`main` または `master` なら
     **中止**（このコマンドはフィーチャーブランチ専用。main に直接触らない）。
   - `git status --porcelain` を確認。**追跡ファイルに未コミット変更（`M`/`A`/`D` 等）が
     あれば中止**し、先にコミットするようユーザーへ促す。`.uid`/`.import` などの
     未追跡（`??`）は無視してよい。dirty なまま merge しない。

2. **最新化**: `git fetch origin main`。

3. **要否判定**: `git merge-base --is-ancestor origin/main HEAD` を実行。
   - 真（終了コード 0）なら「既に最新 main を含んでいる。やることなし」と報告して**終了**。
   - 偽なら次へ。参考までに `git rev-list --count HEAD..origin/main` で遅れコミット数を把握。

4. **マージ**: `git merge origin/main` を実行。
   - **衝突なし** → 通常のマージコミット（または fast-forward）が自動で作られる。手順5へ。
   - **衝突あり** → `git diff --name-only --diff-filter=U` で衝突ファイルを列挙し、
     ユーザーに提示する。各ファイルを**両側の変更意図を理解した上で**解消する
     （どちらかを機械的に採用せず、両方の変更が生きるようマージする）。
     解消できたら `git add <解消したファイル>` → `git commit`（既定の
     "Merge remote-tracking branch 'origin/main' into <branch>" メッセージのままでよい）。
     **どのファイルをどう解消したかを必ずユーザーに報告する。**

5. **検証**: `scripts/verify.sh` を実行する（`$ARGUMENTS` があれば
   `WEB_PORT=$ARGUMENTS scripts/verify.sh` の形で渡す）。
   **失敗したら push せず停止**し、失敗した段階と原因を報告する。
   マージ解消の巻き添えで壊れていないかをここで担保する。

6. **push**: verify が緑なら `git push` する。

7. **要約**: 取り込んだ main の範囲（コミット数）・衝突の有無と解消ファイル・
   verify 結果・push 先ブランチを 1 行で報告する。
