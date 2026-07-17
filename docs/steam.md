# Steamへの配信

このリポジトリでできているところと、大島さんにしかできないところの切り分け。

## 現状

ネイティブ書き出しは動いていて、書き出したバイナリが実際に起動して描画する
ところまで `scripts/verify.sh` の段階5で毎回確認している（pckを外すと落ちる
ことも確認済み）。

なおブラウザ版は既にGitHub Pagesで公開済み（README参照）。Steamはネイティブ版の
話で、こちらはまだApp ID待ち。

| ターゲット | 状態 |
|---|---|
| Linux (x86_64) | 書き出し・起動確認済み |
| Windows (x86_64) | 書き出し済み。**実機での起動は未確認**（Linux上のWSLgからは確認できない） |
| macOS | プリセットなし。必要になってから |

Steamに載せるだけなら、この時点の `build/windows/` の中身
（`slay-the-spinner.exe` と `slay-the-spinner.pck`）をそのままアップロードできる。
GodotSteamは実績やクラウドセーブを使う段になって初めて要る（後述）。

## 大島さんにしかできないこと

私（AI）は実行できない。実世界の手続きとお金が絡むため。

1. **Steamworksパートナー登録** — 事業者情報・税務情報・銀行口座の登録が要る。
   審査に日数がかかる。
2. **App IDの購入** — Steam Direct の登録料 $100/作品。返金条件あり
   （売上が一定額に達すると返ってくる）。
3. **ストアページの作成** — 説明文、スクリーンショット、トレーラー、
   ジャンル/タグ、価格設定。公開の30日前までにストアページを出す必要がある。
4. **コンテンツ審査への提出** — ビルドをアップロードしてValveの審査を通す。

App IDが取れたら教えてほしい。以降のビルド設定とアップロード手順は私が組める。

## App IDが取れた後の手順

### 1. ビルド設定を埋める

`godot/export_presets.cfg` のWindowsプリセットに、今は空欄のものがある。
Windowsのファイルプロパティに出るので埋めておく（値が分からないので放置してある）:

- `application/product_name` — 製品名
- `application/company_name` — 会社名・サークル名
- `application/file_version` / `application/product_version` — バージョン
- `application/copyright` — 著作権表示
- `application/icon` — **`.ico` 形式が要る**。`godot/icon.svg` はそのままでは使えない

### 2. ローカルでSteam連携を試す

`steam_appid.txt` に App ID だけを書いて実行ファイルと同じ場所に置くと、
Steamクライアント経由でなくてもSteam APIが初期化できる。
**これは開発用。配布物には含めないこと。**

### 3. アップロード

SteamworksのSDKに含まれる `steamcmd` / ContentBuilder を使う。
`app_build_<AppID>.vdf` と `depot_build_<DepotID>.vdf` を書いて、

```
steamcmd +login <account> +run_app_build ../scripts/app_build_<AppID>.vdf +quit
```

アップロード対象は `build/windows/` の中身。

### 4. GodotSteam（実績・クラウドセーブ等が要るなら）

[GodotSteam](https://godotsteam.com/) をGDExtensionとして `godot/addons/` に置く。

**まだ入れていない。** App IDがないと初期化すらできず、動作確認のしようがない
ものを50MB超のバイナリごとリポジトリに入れることになるため。実績を作る段で
入れる。

入れる時は、Steamが無い環境（ブラウザ版、Steam経由でないネイティブ実行、
ヘッドレスのテスト）で落ちないよう、必ずガードを通して呼ぶこと:

```gdscript
# 悪い例: ブラウザ版とテストが壊れる
Steam.setAchievement("FIRST_WIN")

# 良い例
if SteamService.is_available():
    SteamService.unlock_achievement("FIRST_WIN")
```

ブラウザ版とネイティブ版を同じコードベースで出す以上、Steam APIの有無は
実行時に分岐するしかない。

## ブラウザ版との違いで気をつけること

| | ブラウザ | ネイティブ(Steam) |
|---|---|---|
| セーブ先 | `user://` はIndexedDB。ブラウザのサイトデータ削除で消える | `user://` はOSのアプリデータ。永続 |
| Steam API | 使えない | 使える |
| 初回ロード | wasm 38MB + pck 11MB のダウンロード待ちがある | なし |

現状MVPではセーブしない（1プレイ限りでランが終わる）ので、この差は表面化
していない。セーブを入れる時に効いてくる。
