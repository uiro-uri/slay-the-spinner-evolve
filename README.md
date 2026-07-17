# Slay the Spinner

ベイブレード風の回転数(RPS)減衰バトル × Slay the Spire風の分岐マップ ×
レアリティ付きロ―グライク強化パーツ、を組み合わせたゲームです。

ゲームデザインはFlaskで作った初期プロトタイプ（`archive/flask-prototype/`）
で検証済みです。ブラウザとSteam配信を最終目標に、実装を Godot で作り直して
います。本体は `godot/` 以下にあります。

## 開発環境

- [Godot 4.x](https://godotengine.org/download) をインストールしてください。
  同じバイナリがエディタ（GUI）とヘッドレスCLI（`godot --headless ...`）を
  兼ねています。
- `godot/project.godot` をGodotエディタで開いてください。
- **エディタをsudo（root）で起動しないでください。** インポートキャッシュ
  `godot/.godot/` がroot所有になり、以後は通常ユーザーでのインポート・
  書き出しが権限エラーで失敗するようになります（`.import`が`valid=false`に
  書き換わり、フォントや翻訳が焼き込まれない壊れたビルドができます）。
  そうなった場合は `sudo rm -rf godot/.godot` で消せば再生成されます。

## ディレクトリ構成

- `godot/` — Godotプロジェクト本体（このディレクトリを開く）
- `archive/flask-prototype/` — 検証済みゲームデザインの参考実装（凍結、
  機能追加はしない）。ローカル起動方法は同ディレクトリのREADME参照。

## ビルド/書き出し

書き出しプリセット（`godot/export_presets.cfg`）にWeb（ブラウザ）と
ネイティブ（Windows/Linux, 将来的にSteam向け）を定義しています。
成果物はリポジトリ直下の `build/` に出ます（gitignore済み）。

```bash
# 事前に一度インポートしておく（.translation等の生成物を作るため）
godot --headless --path godot --import

# 書き出し（出力先はexport_presets.cfgのexport_pathに従う）
mkdir -p build/web
godot --headless --path godot --export-release "Web"

# ローカルで確認
(cd build/web && python3 -m http.server 8099)
# -> http://localhost:8099/index.html
```

## 検証

```bash
scripts/verify.sh           # 全段階
scripts/verify.sh --quick   # 描画確認を省略して速く回す
```

終了コードは当てにならない（フォントと翻訳が抜けた壊れたビルドがexit 0で
通った実績がある）ため、各段階に実質的な判定基準を置いている:

| 段階 | 判定 |
|---|---|
| 0. preflight | `.godot`が自分の所有か（sudoでエディタを起動する事故の検出） |
| 1. import ×2 | **2回目**にエラーが無いこと（1回目は生成物が未作成で正当にエラーになる） |
| 2. テスト | 終了コード＋完走したテスト数 |
| 3. ヘッドレス起動 | `ERROR`が出ないこと |
| 4. 書き出し ×3 | 終了コード＋pckサイズ下限 |
| 5. ネイティブ描画 | 実際に起動して描画したフレームが単色でないこと |
| 6. Web描画 | ブラウザでGodotが起動し、JSエラー0、canvasが単色でないこと |

5と6は `build/verify/native.png` と `build/verify/web.png` を残すので、
見た目は画像を見て確認する。

個別に回す場合:

```bash
godot --headless --path godot --script res://tests/run_tests.gd
```

## 実装の進め方

`docs/` はまだありませんが、実装ロードマップはマイルストーン単位
(M0〜M5)で進めています。詳細はプロジェクトの計画ドキュメントを参照して
ください。
