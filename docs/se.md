# 効果音 (SE) の実装方針

このドキュメントの対象は効果音（SE）のみ。BGMは扱わない。

## 現状

効果音まわりのコードは一切無い。

| 項目 | 状態 |
|---|---|
| オーディオバス | 未設定（`project.godot` に `[audio]` 系の設定なし） |
| `AudioStreamPlayer` | 未配置（`godot/` 全体に1つも無い） |
| `godot/assets/audio/` | 未作成 |
| 素材 (wav/ogg) | 未取得 |

## まだ全部入れない理由

1. **素材が無い。** 実際の `.wav`/`.ogg` ファイルがまだ無く、鳴らすものが
   何も無い状態でAPIだけ先に組んでも当てずっぽうになる。
2. **当たり判定まわりの調整がまだ固まっていない。** `spinner_physics.gd` の
   衝突・壁バウンドはCLAUDE.mdにある通り「Tuning is judged by feel」の段階で、
   まだ動きが変わりうる。どの瞬間に何を鳴らすかを今固定するのは早い。

**まだSEの実装には早い。**

## フック候補と優先度

既存コードを洗った結果、SEを足せそうな箇所は以下。それぞれ実装時の優先度を
つけておく。

| フック | 発生源 | 判定 | 理由 |
|---|---|---|---|
| 発射音 | `LaunchController.launched(pos, velocity)`（`godot/scenes/battle/LaunchController.gd`） | 優先候補 | 既にsignalがあり、フック追加のための改造が要らない |
| 勝敗音 | `Battle.finished(player_won)`（`godot/scenes/battle/Battle.gd`） | 優先候補 | 既存signal。`Main.gd` が既に購読しているので鳴らす場所もそのまま使える |
| ディスク衝突音 | `Battle._resolve_disc_collision()` | 保留 | 現状signalが無く、`_physics_process` からのポーリングのみ（後述） |
| 壁バウンド音 | `Battle._resolve_walls()` | 保留 | 同上 |
| パーツ選択音 | `RewardScreen.gd` のカードボタン（ハンドラ名の無いinline lambdaでemit） | 保留 | `Main.gd` の `_on_part_chosen` 側で鳴らせば `RewardScreen.gd` 自体の改造は不要 |
| 画面遷移音 | `Main._swap_screen()`（全遷移が通る一箇所） | 保留 | 実装コストは低いが、ゲームプレイ音より優先度は下 |
| UIクリック音 | Title/MapScreenの各ボタン | 保留 | 素材が無い段階でボタンごとに割り振るのは時期尚早 |

signalが既にあってコード改造無しで鳴らせるもの（発射音・勝敗音）が最優先。
それ以外はBattle.gdへの構造変更やRewardScreen側の変更を伴うため、素材が揃って
実装に着手するタイミングでまとめて判断する。

## Battle.gdへのsignal追加について

**今回はドキュメントのみ。`Battle.gd` には手を入れない。**

`_resolve_disc_collision()` と `_resolve_walls()` にsignalを足せばポーリングせずに
済むが、それを購読する `AudioManager` 自体がまだ存在しない状態でsignalだけ足すのは
死んだコードになる。また `spin_drain`/`spin_kick` の戻り値（衝突の大きさ）を
音量・ピッチに使うかどうかも、signalの形（値を積んで渡すか、素で鳴らすだけか）に
関わってくる。これは実際の再生コードと一緒に決めた方がよく、先回りして決め打ちしない。

## 想定するAudioManagerの形

実装するときはこう作る想定（今は作らない）。

- `godot/autoloads/AudioManager.gd`。`extends Node`、`GameState.gd` と同じ登録方式で
  `project.godot` の `[autoload]` に1行追加する
  （`AudioManager="*res://autoloads/AudioManager.gd"`）。
- 呼び出し側には生のstreamパスを持たせず、キー参照で鳴らす: `AudioManager.play("launch")`
  のような形。
- オーディオバスは `SE` を用意する。将来BGMを入れる時にバス名を後から分けなくて
  済むよう、`BGM` バスとは最初から分けておく方針だけここに書いておく。
- ヘッドレステスト（`scripts/verify.sh` 段階2、GDScriptテストは表示も実際の音声出力も
  無い状態で走る）で落ちないよう、呼び出し側は必ずAudioManager経由にすること。

```gdscript
# 悪い例: ヘッドレステストでstreamが無い/読み込めない場合に落ちる可能性がある
$SFXPlayer.stream = preload("res://assets/audio/launch.ogg")
$SFXPlayer.play()

# 良い例
AudioManager.play("launch")
```

ブラウザ版・ネイティブ版・ヘッドレステストを同じコードベースで走らせる以上、
SEの呼び出しは常にAudioManager経由にして、内部でキーの存在確認や失敗時の
握りつぶしをそこに閉じ込めること。

## 音量・ピッチのばらつき（発展）

衝突の大きさ（`spin_drain`/`spin_kick` の戻り値）に応じてSEの音量・ピッチを
変える案がある。ただしこれは発展的なアイデアであり、MVPの対象ではない。
そもそも衝突音自体が保留（上記）なので、その判断が付いてから考える。

## 多言語対応について

SEはテキストを持たないため、`translations/strings.csv` によるJA/EN翻訳の対象外。

## 大島さんにしかできないこと

1. **効果音素材の選定・購入/収録** — 実際の `.wav`/`.ogg` ファイルを用意すること
   自体が人間の作業。ライセンス確認（商用利用可否、クレジット表記の要否）も含む。
2. **ライセンス表記の作成** — `godot/assets/fonts/LICENSE-NotoSansJP.txt` と同じ形式で
   `godot/assets/audio/` にも `LICENSE-<name>.txt` を置く想定だが、素材ごとの
   ライセンス文面は人間が確認・転記する必要がある。
3. **音のフィーリング判断** — 実装後、実際に鳴らして「合っているか」を判断するのは
   人間の耳。

素材が揃ったら教えてほしい。AudioManagerの実装とフックの追加はその後に着手する。

## 環境ごとの違いで気をつけること

| | ブラウザ | ネイティブ | ヘッドレステスト |
|---|---|---|---|
| 音声出力 | Web Audio API経由。初回のユーザー操作までは再生がブロックされることがある | OSの音声デバイスに直接出力 | `AudioServer` はあるが出力先が無い。呼び出しても落ちないことだけが要件 |
| 対応フォーマット | `.ogg` 推奨（wasmビルドの制約） | wav/ogg どちらでも問題ない | 再生自体は評価されないため影響なし |
| 初回ロード | 音声アセットもwasm/pckの初回ダウンロードに乗る | なし | 対象外 |

現状SEは何も鳴っていないため、この差は表面化していない。実装時に効いてくる。
