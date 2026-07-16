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

## ディレクトリ構成

- `godot/` — Godotプロジェクト本体（このディレクトリを開く）
- `archive/flask-prototype/` — 検証済みゲームデザインの参考実装（凍結、
  機能追加はしない）。ローカル起動方法は同ディレクトリのREADME参照。

## ビルド/書き出し

書き出しプリセット（`godot/export_presets.cfg`）はM1でエディタから
Web（ブラウザ）とネイティブ（Windows/Mac/Linux, 将来的にSteam向け）を
設定し、以後はコミットして共有します。

```bash
# ヘッドレスでの書き出し例（要 Godot 4.x, export templates, プリセット設定後）
godot --headless --path godot --export-release "Web" build/web/index.html
```

## 実装の進め方

`docs/` はまだありませんが、実装ロードマップはマイルストーン単位
(M0〜M5)で進めています。詳細はプロジェクトの計画ドキュメントを参照して
ください。
