# EVOLVE.md — 自己改善サイクルのプロトコル

このリポジトリは **uiro-uri/slay-the-spinner の自動進化実験 fork** です。定期実行される
Claude が「テストプレイ → 改善を1つ実装 → PR → CI green で自動マージ」を繰り返します。
このファイルはそのサイクルの手順書です。定期実行エージェントは毎回まっさらな環境で起動し、
このファイルだけを頼りに1サイクルを完遂します。

ミッション: **このゲームを、実際に遊んでみて感じた根拠に基づいて、少しずつ面白くすること。**
バランス・UX・演出・新機能、何でも対象。ただし1サイクルにつき改善は1テーマ。

## 0. 環境ブートストラップ

クラウド環境には Godot が無いので、まずエディタバイナリ（headless CLI 兼用）を用意する:

```bash
curl -fsSL -o /tmp/godot.zip \
  https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64.zip
unzip -o /tmp/godot.zip -d /tmp/godot-bin
export GODOT_BIN=/tmp/godot-bin/Godot_v4.7.1-stable_linux.x86_64
chmod +x "$GODOT_BIN"
# インポート(1回目は .translation とフォント未生成のエラーが出るのが正常。2回目が無エラーであること)
"$GODOT_BIN" --headless --path godot --import || true
"$GODOT_BIN" --headless --path godot --import
```

export templates（2GB）と Chromium は**不要**。完全な `scripts/verify.sh` は CI（PR の
`build` ジョブ）が担当する。ローカルで走らせるのはインポート・テスト・playtest だけでよい。

**ブートストラップに失敗したら**（ダウンロード不可など）、作業を続けず
`gh issue create` で障害内容を issue にして終了すること。沈黙で死なない。

## 1. 前回の尻拭いを最優先

`gh pr list --state open` で自分の過去サイクルの PR が残っていないか確認する。
残っていたら（= CI が落ちて auto-merge されなかった）、**新しい改善を始めずに**
その PR の CI を green にすることだけをこのサイクルの仕事にする。
CI ログは `gh run list` / `gh run view --log-failed` で読める。

## 2. コールドプレイ（コードを読む前に！）

**journal・ソースコード・過去 PR を読む前に**、初見の目で1ラン遊ぶ。順序を守ること。
先にコードや journal を読むと「事前知識ゼロの手触り」が消えて、この工程の価値がなくなる。

```bash
S=/tmp/run.json
"$GODOT_BIN" --headless --path godot --script res://playtest/naive_play.gd -- new --seed=$RANDOM --state=$S
"$GODOT_BIN" --headless --path godot --script res://playtest/naive_play.gd -- status --state=$S
# 以後1手ずつ: enter → launch → (勝てば reward → pick / 負ければ retry か giveup)
# enter/retry と launch には同じ --bseed を渡すこと(敵の出現が一致する)
```

- 予告（テレグラフ）を見て**自分で**狙いを決める。攻略済みの定石をコードから逆引きしない
- 報酬はカードの効果テキストだけで選ぶ
- 遊びながら「詰まった・退屈だった・気持ちよかった・分かりにくかった」を具体的にメモする

## 3. 文脈を読む

コールドプレイが終わってから:
- `docs/evolve/journal.md` — 過去サイクルの知見と「次の候補」
- `scripts/playtest.sh` — ボット統計（25k 戦、`build/playtest/report.md` に出力）。
  バランスに触るサイクルでは実行し、勝率への影響を before/after で見る
- 必要に応じて `CLAUDE.md`（アーキテクチャと検証の約束事）と関連ソース

## 4. 改善を1つ選んで実装する

- **1サイクル1テーマ**。小さく確実に。大きな構想は journal の「次の候補」に書き残して分割する
- コールドプレイで自分が感じたことを一次証拠にする。統計は裏付け
- テストの約束事は CLAUDE.md の通り（headless で走る、suite を `EXPECTED_TESTS` に登録、
  新テストは実装をわざと壊して落ちることを確認してから完成とする）
- ローカル検証（フル verify は CI に任せる）:

```bash
"$GODOT_BIN" --headless --path godot --import
"$GODOT_BIN" --headless --path godot --script res://tests/run_tests.gd
"$GODOT_BIN" --headless --path godot --quit-after 60
```

## 5. journal を書いて PR

`docs/evolve/journal.md` の末尾にこのサイクルのエントリを追記し、**同じ PR に含める**:

```markdown
## サイクル YYYY-MM-DD HH:MM UTC
- プレイ所感: (コールドプレイで感じたこと。クリア可否、詰まり、気持ちよさ)
- 選んだ改善: (何を・なぜ)
- 変更: (要点と主要ファイル)
- 結果: (テスト/統計での裏付け)
- 次の候補: (今回見送ったこと)
```

コミット・PR 作成・auto-merge 予約:

```bash
git checkout -b evolve/<短い英語スラッグ>
git add -A && git commit -m "<日本語で変更内容>"
git push -u origin HEAD
gh pr create --title "<日本語タイトル>" --body "<プレイ所感と変更内容。日本語>"
gh pr merge --auto --merge
```

CI（`scripts/verify.sh`）が green なら自動でマージされ、GitHub Pages に自動デプロイされる。
このサイクル内でマージ完了を待つ必要はない（落ちていたら次サイクルの手順1が拾う）。

## ガードレール

- **`.github/`・`scripts/verify.sh`・このファイルは変更しない**（CODEOWNERS により
  変更 PR は人間のレビュー待ちになり、auto-merge されない）。検証の門番と手順書を
  自分で緩めないため。変えたい場合は提案 PR を別に立てて人間の判断に委ねるのは可
- 1サイクル1PR。マージ済みの main にだけ積む（他ブランチへの依存を作らない)
- コミットメッセージ・コメント・journal は日本語（リポジトリの既存慣習）
- 物理・バランスの考え方は CLAUDE.md の「Physics: it is deliberately fake」節に従う
