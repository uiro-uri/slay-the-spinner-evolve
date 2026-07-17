# 効果音 (SE) の実装方針

このドキュメントの対象は効果音（SE）のみ。BGMは扱わない。

## 現状

SEインフラ（`AudioManager` + `SE` バス）を実装済み。素材は Kenney のCC0効果音を
`godot/assets/audio/se/` に配置している（ライセンスは `godot/assets/audio/LICENSE-Kenney.txt`）。

| 項目 | 状態 |
|---|---|
| オーディオバス | `SE`・`BGM` を `AudioManager._ready` でコード生成し Master へ流す |
| 音の窓口 | `autoloads/AudioManager.gd`（autoload登録済み） |
| ワンショット素材 | `se/ui`・`se/impact`・`se/wall`・`se/launch`・`se/result` の ogg |
| 回転音・チャージ音 | 専用素材が無いので `ToneSynth` が正弦波を実行時合成 |

## 音の系統

3系統ある。詳細は `autoloads/AudioManager.gd` のコメントを参照。

1. **ワンショット** — 素材(ogg)をキーで鳴らす。同時発音のため `AudioStreamPlayer` を
   `POOL_SIZE` 個プールし、ラウンドロビンで回す。1キーに複数素材を持たせ、鳴らすたび
   ランダムに選んで単調な繰り返しを避ける。
2. **回転音** — バトル中ずっと鳴る連続音。専用素材が無く、rps に連続追従させたいので、
   `ToneSynth`（`scripts/audio/tone_synth.gd`）が `AudioStreamGenerator` で正弦波を合成する。
   周波数・振幅は `AudioLevels`（`scripts/audio/audio_levels.gd`, 純粋関数）が rps から決める。
3. **チャージ音** — 引っ張っている間の連続音。引き量(0〜1)に連続追従。同じく `ToneSynth`。

回転音・チャージ音を素材ではなく合成にした理由: どちらも rps／引き量に**連続追従**する音で、
ワンショットの ogg では表現できない。素材が用意できたら `AudioManager` の該当メソッドを
差し替えればよい（呼び出し側は触らずに済む）。

## 呼び出し方（キー参照）

呼び出し側は生の stream を持たず、必ず `AudioManager` 経由で鳴らす。キーの存在確認や再生失敗の
握りつぶしは `AudioManager` に閉じ込めてあるので、ブラウザ・ネイティブ・ヘッドレステストの
どれでも落ちない。

```gdscript
AudioManager.play("impact")          # ワンショット
AudioManager.start_rotation()        # 回転音の開始
AudioManager.update_rotation(rps, ref_rps, lose_threshold)
AudioManager.stop_rotation()
AudioManager.start_charge() / update_charge(ratio) / stop_charge()
```

## 実装済みのフック

| SE | キー / API | 発生源 |
|---|---|---|
| 操作音(開始) | `ui_confirm` | `Main._on_start_requested` |
| 操作音(マップ選択) | `ui_select` | `Main._on_map_node_chosen` |
| 操作音(報酬選択) | `ui_confirm` | `Main._on_part_chosen` |
| 操作音(コンティニュー/断念) | `ui_confirm` / `ui_back` | `Main._on_continue_requested` / `_on_give_up_requested` |
| 操作音(クリアからタイトル) | `ui_click` | `Main._on_gameclear_to_title` |
| 発射音 | `launch` | `Battle._on_launched` |
| 衝突音(ディスク) | `impact` | `Battle._emit_due_impacts`（`BattleResult.impacts` に同期） |
| 衝突音(壁) | `wall` | `Battle._emit_due_wall_impacts` |
| 勝敗音 | `win` / `lose` | `Battle._finish` の `outcome` 分岐 |
| 回転音 | `start/update/stop_rotation` | `Battle.play`／`_physics_process`／`_finish`・`_exit_tree` |
| チャージ音 | `start/update/stop_charge` | `LaunchController` の押下／ドラッグ／離す・無効化 |

衝突音は再生と同じ `BattleResult.impacts`／`wall_impacts` に同期させている（物理ステップ
ではない）。回転音・チャージ音の音量・ピッチは `AudioLevels` の `const` で調整できる。

## テスト

`AudioLevels` の純粋関数を `godot/tests/test_audio_levels.gd` で検証する（`EXPECTED_TESTS` に
`audio` を登録済み）。数値そのものではなく、調整で崩れない性質だけを見る: rps／引き量での
単調性、`lose_threshold` 以下・`ratio=0` での無音、範囲クランプ、reference=0 での安全性。

`ToneSynth` と `AudioManager` の再生自体は音声出力の無いヘッドレスでは評価できないので
テストしない。代わりにトーンは開始要求があるまで再生しない作りにし、テスト中は音源が
アイドルのまま＝落ちないことだけを保証する。実際の鳴りは `verify.sh` 段階5〜7（実機/ブラウザ
起動）で「エラーが出ないこと」を、フィーリングは人間の耳で確認する。

## 多言語対応について

SEはテキストを持たないため、`translations/strings.csv` によるJA/EN翻訳の対象外。

## 大島さんにしかできないこと

1. **音のフィーリング判断** — 実際に鳴らして「合っているか」を判断するのは人間の耳。
   素材の当たり外れ、音量・ピッチ、回転音／チャージ音の合成トーンが心地よいかは
   `AudioLevels` の `const` と各 `@export` を触りながら詰める。
2. **追加素材の選定・購入/収録** — 回転音・チャージ音に合成トーンではなく実素材を使いたく
   なった場合や、勝敗音・操作音を差し替えたい場合、`.wav`/`.ogg` の用意とライセンス確認
   （商用利用可否、クレジット表記の要否）は人間の作業。
3. **ライセンス表記の更新** — 新しい素材を足したら `godot/assets/audio/` に
   `LICENSE-<name>.txt` を置く（既存の `LICENSE-Kenney.txt` と同じ形式）。

## 環境ごとの違いで気をつけること

| | ブラウザ | ネイティブ | ヘッドレステスト |
|---|---|---|---|
| 音声出力 | Web Audio API経由。初回のユーザー操作までは再生がブロックされることがある（エラーではない） | OSの音声デバイスに直接出力 | `AudioServer` はあるが出力先が無い。呼び出しても落ちないことだけが要件 |
| 対応フォーマット | `.ogg`（配置済み素材はすべて ogg） | wav/ogg どちらでも問題ない | 再生自体は評価されない |
| 合成トーン | `AudioStreamGenerator` はWebでも動作する | 問題なし | トーンは開始要求まで鳴らさないので影響なし |
