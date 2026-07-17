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

### WSLで作業する場合、Windows版のGodotで開かないでください

Windows側から `\\wsl.localhost\` 経由でWSLのファイルを書くと、**sudoを使わなくても
root所有になります**（WSLの9Pファイルサーバーがroot権限で動くため）。つまり
**Windows版のGodotでこのプロジェクトを開くだけ**で `project.godot` も `.godot/` も
root所有になり、こうなります:

- インポートが権限エラーで失敗し、`.import` が `valid=false` に書き換わる。
  **フォントや翻訳が焼き込まれない壊れたビルドが黙ってできる**（exit 0で通る）。
- **gitがブランチを切り替えられなくなる**（`project.godot` を上書きできず `Aborting`）。
- Godotがシェーダキャッシュを書けず `shader_gles3.cpp` のエラーを吐き続ける。

WSL側のGodotで開けばこれは起きません。WSLgでWindowsの画面に窓が出ます:

```bash
~/bin/godot4 --path godot -e     # インストール場所は適宜
```

9Pを経由しないのでインポートも速くなります。

すでにroot所有になってしまった場合、**親ディレクトリが自分の所有ならsudoは要りません**:

```bash
rm -rf godot/.godot                      # 消えなければ sudo rm -rf godot/.godot
git checkout -- godot/project.godot
```

`verify.sh` の段階0がこの状態を検出します。

## ディレクトリ構成

- `godot/` — Godotプロジェクト本体（このディレクトリを開く）
- `docs/steam.md` — Steam配信の手順と、どこまでが済んでいるか
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

## 配信（GitHub Pages）

Web版は **https://uiro-uri.github.io/slay-the-spinner/** で公開しています。
`main` に push すると `.github/workflows/pages.yml` がビルドし、**`scripts/verify.sh`
が緑のときだけ**デプロイします（同じスクリプトをそのままゲートに使っており、CI用の
別実装は持ちません）。pull request ではビルドと検証だけを走らせ、公開はしません。

書き出し成果物はgitに入れません。CIが毎回ビルドして直接配信します。

### `variant/thread_support` を有効にしないでください

有効にするとGodotはSharedArrayBufferを要求し、その利用には COOP/COEP ヘッダが
必要になります。**GitHub Pagesは独自ヘッダを付けられないため、本番でだけゲームが
起動しなくなります。** しかも書き出しは成功し、ローカルの `python3 -m http.server`
経由の確認も通ってしまうので、気づけません。この事故を防ぐため、verify.sh の段階4で
`export_presets.cfg` を検査して落とすようにしてあります。

（`export_presets.cfg` はGodotが書き戻すためコメントを残せません。ここに書いています。）

## 検証

```bash
scripts/verify.sh           # 全段階
scripts/verify.sh --quick   # 描画確認を省略して速く回す
```

終了コードは当てにならない（フォントと翻訳が抜けた壊れたビルドがexit 0で
通った実績がある）ため、各段階に実質的な判定基準を置いている:

| 段階 | 判定 |
|---|---|
| 0. preflight | `godot/`配下が全部自分の所有か（Windows版Godotで開く事故の検出） |
| 1. import ×2 | **2回目**にエラーが無いこと（1回目は生成物が未作成で正当にエラーになる） |
| 2. テスト | 終了コード＋完走したテスト数 |
| 3. ヘッドレス起動 | `ERROR`が出ないこと |
| 4. 書き出し ×3 | 終了コード＋pckサイズ下限＋`thread_support`が無効なこと |
| 5. ネイティブ描画 | **書き出したバイナリ**を起動し、描画したフレームが単色でないこと |
| 6. Web描画 | 横(1280x720)と縦(SP=スマホ縦画面)の両方で、ブラウザでGodotが起動し、JSエラー0、canvasが単色でないこと |
| 7. SP画面遷移描画 | 縦画面でTitle→Map→Battleと遷移させ、各画面が起動・エラー0・単色でないこと |

段階5はプロジェクト（`--path godot`）ではなく `build/linux/` の書き出し済み
バイナリを起動する。プロジェクトを動かしてもエディタがソースから再生できる
ことしか分からず、バイナリとpckの組み合わせが壊れていても素通りする。
実際に配布されるのは書き出した方なので、そちらを起動する。

5〜7は `build/verify/` に絵を残すので、見た目は画像を見て確認する:
`native.png`・`web.png`（横）・`sp.png`（スマホ縦Title）・`sp_map.png`・`sp_battle.png`
（スマホ縦のMap/Battle）。SP縦の寸法は `SP_W`/`SP_H`（既定 390x844）、縦画面での
縦寄せは `SP_BIAS`（既定 0.7、Godot側 `portrait_vertical_bias` と合わせる）で変えられる。

Map/Battleは縦画面のときだけ、コンテンツを幅いっぱいへ拡大し中央やや下へ寄せる
レスポンシブ配置になる（横画面の見た目は変えない）。各画面の `portrait_fill` /
`portrait_vertical_bias` はInspectorから手触りで調整できる。

個別に回す場合:

```bash
godot --headless --path godot --script res://tests/run_tests.gd
```

## 実装の進め方

`docs/` はまだありませんが、実装ロードマップはマイルストーン単位
(M0〜M5)で進めています。詳細はプロジェクトの計画ドキュメントを参照して
ください。
