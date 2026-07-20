# 進化ジャーナル

自己改善サイクル（EVOLVE.md）の記録。各サイクルが末尾に1エントリ追記する。
書式は EVOLVE.md の手順5を参照。

## 開始 2026-07-19
- uiro-uri/slay-the-spinner からこのリポジトリを分岐。ここから自動進化を開始する
- 次の候補: (まだなし。最初のサイクルがコールドプレイから見つける)

## サイクル 2026-07-19 11:34 UTC
- プレイ所感: seed=21357 で1ラン(段6で全滅)。段1〜5は狙いを工夫すれば勝てて手応えがあった。
  段5→6が1択の一本道で、その先が Lv3×3体 部屋。敵rps21〜22に対しこちら基礎rps15で、
  乱戦に入ると1発も当てられずに削り殺される(6連敗、被弾11〜17)。逃げ(force=0.15)も
  すり鉢が中央へ集めるので無意味だった。「選択肢のない段が続いた末に詰み部屋」が今回の
  一番の不満。ただし今回の敗因の半分はハーネスの嘘(下記)で自分のビルドを壊したことにある。
- 選んだ改善: コールドプレイ環境(naive_play)が嘘をつく問題の修正。プレイ中に3つ発見した:
  (1) RAGE/MOMENTUM 札の効果表記が STAT_MULTIPLY 用分岐に落ち、既定値の「質量×1.10」を
  表示(実効果は反発+壁rps保持)。効果テキストだけで報酬を選ぶ約束なので選択が腐る。
  実際 MOMENTUM 札を「質量ダウン」だと思って避け続けた。
  (2) 提示されていない札を pick できてしまい(id=2 を誤爆取得)、ビルドが壊れた。
  bseed を変えれば報酬の引き直しも効いてしまう。
  (3) 引き分け(DRAW)が「敗北 死因=? loser=none」と表示され、なぜ負けたか分からない
  (実UIは BATTLE_DRAW を出す。CLIだけの欠落)。
  コールドプレイは全サイクルの一次証拠なので、ゲーム本体より先にここを直すのが最優先と判断。
- 変更: godot/playtest/naive_play.gd — card_text を効果種別ごとに真実の表記へ(静的関数化)、
  reward の提示札を state["offered"] に保存して pick を提示札に限定+引き直しを封鎖、
  結果表示に result_label(引き分けを明示)、giveup の段表示を交戦中対応に。
  godot/tests/test_playtest.gd — 上記3点のテストを追加。
- 結果: 全テスト green。表記フォールスルー復元・pick ガード無効化の2種のサボタージュで
  テストが落ちることを確認済み。E2Eスモークで「同じ3枚の再掲」「提示外 pick 拒否」も確認。
- 次の候補: 3体部屋の難度検証(playtest.sh で敵数別勝率を before/after 測定してから調整)。
  マップ生成で1択の段が連続しない保証(段5→6→7で1択が続いた)。素の rps15 と Lv3敵 rps22 の
  差の妥当性検証。
- 環境メモ: この実行環境のプロキシは GitHub releases を403で弾き、EVOLVE.md 手順0の
  ダウンロードは失敗する。回避策: mirror.gcr.io(許可済み)の barichello/godot-ci:4.7.1 の
  1.37GB レイヤー(sha256:138b08b3...)から /usr/local/bin/godot をストリーミング抽出すると
  公式 4.7.1 バイナリが得られる(匿名トークン→manifest→blob を curl+tar で)。

## サイクル 2026-07-19 15:33 UTC
- プレイ所感: seed=20896 で1ラン(段9ボスで全滅)。段1〜4は全力ラムで秒殺できほぼ作業、
  段5(Lv3×2)で突然3連敗の壁、ボス(rps33.3)には正面・退避・迎撃の3戦略すべてで敗死。
  「敵rpsは15→33まで伸びるのに、自分のrpsを上げる札(SPIN_ENGINE)が報酬8回中1回しか
  出ない」理不尽感が最大の不満。退避戦術はすり鉢が中央へ集めるので機能しない(これは
  納得感がある)。リトライの敵再抽選が実質「良い出現を引くまでリトライ」になっている。
- 選んだ改善: コールドプレイCLI(naive_play)の嘘・第2弾。プレイ後の検分で、上の所感の
  一部がハーネスのバグ由来だと判明した:
  (1) statsのJSON往復で spin_decay / wall_keep が保存されず、MOMENTUM/RAGE札の主効果が
  次のコマンドで消えていた。MOMENTUM3枚(spin_decay 0.51相当)を取ったのに寿命が全く
  伸びなかったのはこれで、ボス戦の「詰み感」の一次証拠が壊れていた。
  (2) 実ゲーム(Main)は乱戦で倒した頭数ぶん報酬を選べるが、CLIは常に1枚。今回のランは
  実ゲームより3枚痩せたビルドで後半に入っていた。
  (3) ボス撃破後に、実ゲームには存在しない報酬pickを要求していた。
  前サイクルと同じ判断(コールドプレイは全サイクルの一次証拠。器の嘘を先に直す)。
- 変更: godot/playtest/naive_play.gd — stats_dict/stats_from を静的化して全フィールドを
  往復(旧stateはキー欠落を既定値で互換読み)、rewards_left で頭数ぶんの reward→pick 反復、
  ボス勝利は launch 時に即クリア確定、battle/status 表示に spin_decay・wall_keep を追加、
  寿命目安を rps/(radius*spin_decay) に修正。godot/tests/test_playtest.gd — 往復保存と
  頭数報酬のテストを追加。
- 結果: 全テストgreen。spin_decay欠落・頭数1固定の2種のサボタージュで新テストが落ちる
  ことを確認。E2Eスモークで「2体撃破→報酬2回→ノード確定」「spin_decay/wall_keepの
  コマンド跨ぎ保持(寿命目安15→26.8に反映)」「ボス勝利の即クリア」を実走確認。
  bot統計(run_sim)はこのバグの影響を受けないので勝率は不変のはずだが、ベースラインとして
  playtest.sh を計測済み(全段成立・不変条件違反なし。段5勝率20.3%が谷、死亡の66%が段3〜5)。
- 次の候補: 中盤の減衰レース緩和(勝利ごとの微小rps成長 か SPIN_ENGINEの出現率調整。
  段5の谷20.3%と段3〜5死亡集中が裏付け。ただし修正済みハーネスでのコールドプレイで
  再評価してから)。GIANT_GROWTHの効果文が寿命悪化(rps/radius)に触れない罠になっている件。
  naive_play の launch が敗北を保存しない(リトライせず撃ち直せる)抜け穴。

## サイクル 2026-07-19 18:50 UTC
- プレイ所感: seed=5546 で1ラン、初の全段突破。段1〜2は全力ラムで瞬殺、段5(Lv3)で
  全力の正面衝突が2連敗する壁。突破口は「弱発射で接触を避け敵の自然減衰を待つ」で、
  今回はSPIN_ENGINEが4回も引けたため寿命目安が敵の約4倍になり、以後ボスまで全部
  受け身戦法で勝ててしまった(ボス戦5秒、ほぼ何もせず勝利で気持ちよくない)。
  前サイクル(SPIN_ENGINE 8回中1回でボス全敗)と正反対で、成長がRARE札の引き運に
  全依存なのが両極端の根っこだと確信。他: 同じ札が何度も出て報酬プールが狭い、
  GIANT_GROWTHは効果文だけ見ると罠。
- 選んだ改善: journal筆頭候補の「勝利ごとの微小rps成長」。戦闘勝利のたびにrpsが
  +0.5だけ確実に成長する(上限RPS_CAP=40)。引けないランの詰みを緩め、引き運の
  振れ幅を狭める下支え。
- 変更: scripts/core/spinner_stats.gd に grow_rps_by_victory() と VICTORY_RPS_GROWTH。
  RPS_CAPをSpinnerStatsへ一本化(CustomPartCatalogは参照)。適用は Main._on_battle_finished
  (実プレイ)・RunSim.play_one(bot統計)・naive_play(コールドプレイCLI)の3経路、
  いずれも報酬選択より先(倍率札は成長込みに掛かる)。tests/test_victory_growth.gd 追加。
- 結果: 全テストgreen(31 suite)。成長無効化・上限クランプ除去の2種のサボタージュで
  落ちることを確認。playtest before→after(+0.5): 段5勝率 20.3%→25.2%(谷のまま緩和)、
  段3〜5死亡集中 66%→57%、intercept+greedyクリア率 7.7%→13.3%。+1.0も測ったが
  random+random botのクリア率が56%へ跳ねて過剰なので0.5を採用。敵の死因構成比
  (Lv3+は自然減衰が8割)はほぼ不変=減衰支配は悪化せず。
- 次の候補: 「弱発射で待つ」受け身戦法が引きが良いと支配的になる問題(Lv3+の敵死因の
  8割が自然減衰。接触で決まる勝負に寄せるには自然減衰と衝突削りの比の再設計が要る、
  大きいので分割)。勝利成長の画面演出(現状StatPanelの数字が黙って増えるだけ)。
  GIANT_GROWTHの罠テキスト。naive_playのlaunchが敗北を保存しない抜け穴。
  報酬プールの拡充。

## サイクル 2026-07-19 21:25 UTC
- プレイ所感: seed=17423 で1ラン、初の「全戦一発勝利」での全段突破(9戦9勝、残機3温存)。
  MASS_UP3枚+SPIN_ENGINE2枚と引きが良かったのもあるが、「反対側から全力ラム」と
  「進路へ迎撃」だけでどの戦闘も1発で終わり、狙いを工夫する動機が薄かった。
  最大の不満は報酬の顔ぶれ: 9回の提示でGHOSTが6回・FULL_STEAMが5回出て、7枚プールの
  狭さがそのまま選択の退屈につながっていた。防御の選択肢はGHOST(時間限定)だけで
  魅力がなく、一度も取らなかった。死因表示(drain/decay/wall)は良い。
- 選んだ改善: journal筆頭候補とも一致した報酬プールの拡充。コマ同士の衝突で受ける
  rps削りを軽減する純防御COMMON「ショックアブソーバー」(hit_guard、1枚+0.17・
  上限0.5=最大で削り半減)を追加。壁のwall_keep(RAGE)と対になる衝突版で、COMMONの
  防御軸の空白を埋める。削りが減るぶんspin_kick(削り量比例の弾き)も一緒に弱まる。
- 変更: scripts/core/spinner_stats.gd(hit_guard)、spinner_physics.gd
  (guarded_spin_drain)、battle_resolver.gd、battle_request.gd(dict往復・後方互換)、
  scripts/data/custom_part.gd(GUARD効果)・custom_part_catalog.gd(id=10)、
  translations/strings.csv、playtest/naive_play.gd(表示・state往復・card_text)、
  run_sim.gd(greedyの値踏みにhit_guardを織り込み)、measure_parts.gd。
  tests/test_hit_guard.gd 新設(EXPECTED_TESTS登録)。
- 結果: 全テストgreen(32 suite)。リゾルバのguard適用除去・上限クランプ除去の2種の
  サボタージュで落ちることを確認。単独計測(measure_parts): Lv3で+4.7pt/枚・3枚で
  +16.0ptとRAGE(+5.0)/FULL_STEAM(+7.5)同格の中堅COMMON。ラン統計(playtest.sh):
  死亡集中帯の段3勝率52.6%→57.2%、段5も25.2%→27.0%と谷が緩み、intercept+randomの
  クリア率は21.7%で不変。一方intercept+greedyは13.3%→8.3%に低下: greedyが後半も
  GUARDをmomentum系より優先して自然減衰レースで伸び悩むためで、値踏みを
  1/(1-g)→控えめな線形(1+g)に直しても傾向は変わらなかった(bot側の近視眼が主因、
  カード自体の単独効果は正)。要経過観察として次サイクルに引き継ぐ。
- 次の候補: greedy botの報酬価値関数の再設計(1戦の硬さでなくラン単位の複利を
  織り込む。GUARD追加で段6〜9のgreedy勝率が下がった件の切り分けを含む)。
  受け身戦法支配の本丸(Lv3+死因の8割が自然減衰)。勝利成長の画面演出。
  GIANT_GROWTHの罠テキスト(今回の単独計測でもLv3 -9.2pt/枚と唯一の負で、罠が数字でも
  裏付けられた)。naive_playのlaunchが敗北を保存しない抜け穴。

## サイクル 2026-07-20 00:30 UTC
- プレイ所感: seed=22325 で1ラン、全段突破(残機1消費のみ)。段7で全力ラムが drain 負け
  した直後、「force=0.3 で敵から離れた所に置いて自然減衰を待つ」に切り替えたら、段8は
  102発被弾しながら decay 勝ち、ボスも受け身のまま8.8秒で勝ててしまった。当てにいく
  プレイが罰され、退屈な待ちが最適解になる逆転が今回の最大の不満で、journal 筆頭候補
  「受け身戦法支配(Lv3+の敵死因の8割が自然減衰)」の生々しい再現だった。他: GHOST は
  提示されるたび一度も取る気にならず、報酬の顔ぶれの狭さも引き続き感じた。
- 選んだ改善: 受け身支配の本丸(減衰と削りの比の再設計)は大きいので、まず報酬側から
  斬り込む「撃破ボーナス」。敵を接触(衝突削り drain / 壁への弾き飛ばし wall)で仕留めた
  勝利は rps 成長 +1.0、自然減衰(decay)を待っただけの勝利は従来通り +0.5。受け身を
  弱体化せず、当てにいく勝ちだけをラン単位の複利で報いる。
- 変更: battle_resolver.gd が敗者の死因を解決時に記録(State.death_cause、rpsを減らす
  3機構の直後に _mark_if_dead で確定。乱戦は最後に力尽きた敵=決着を付けた1体で判定)し、
  battle_result.gd の loser_death_cause + finished_by_knockout() に載せる(dict往復・
  後方互換込み)。spinner_stats.gd に KNOCKOUT_RPS_GROWTH=1.0、grow_rps_by_victory(knockout)。
  適用3経路: Main(Battle.finishedシグナルにknockout追加)・run_sim(battle_simの
  record["knockout"])・naive_play(★撃破ボーナス★表示と決着死因の明示)。
  tests/test_death_cause.gd 新設(EXPECTED_TESTS登録)、test_victory_growth.gd 拡張。
- 結果: 全テストgreen(33 suite)。死因記録の無効化・knockout無視の2種のサボタージュで
  落ちることを確認。playtest before→after: intercept+greedy クリア率 8.3%→10.3%、
  intercept+random 21.7%→27.3%、後半の段勝率が改善(段8 46.5%→54.2%、段9 52.1%→57.4%)。
  無操作寄り random+random は 41.0%→46.7% で、一律+1.0で過剰とされた56%には遠い。
  段5の谷(27.0%→26.8%)は不変=谷はパーツ引き運の問題で、これは別テーマ。
  ボットは常に当てにいくので差分は上界寄り。人間の受け身プレイは+0.5のままなのが本旨。
- 次の候補: 撃破ボーナスの画面表示(現状、実UIでは+1.0と+0.5の区別が見えない。勝利成長の
  演出ごと未着手)。受け身戦法支配の本丸(自然減衰と衝突削りの比の再設計)。GIANT_GROWTHの
  罠テキスト。報酬プールの拡充(GHOSTの魅力不足も)。naive_playのlaunchが敗北を保存しない
  抜け穴。ベースライン計測は必ずclean worktreeで(編集と並行した計測が1809件のパースエラー
  で汚れ、取り直しになった)。
