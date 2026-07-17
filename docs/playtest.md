# 並列テストプレイ

ボット群で戦闘とランを大量に回し、バランスの実態とバグを数字で出す仕組み。

## 回し方

```bash
scripts/playtest.sh           # 標準セット(戦闘2万5千 + ラン1200) 約10秒
scripts/playtest.sh --sweep   # すり鉢/円錐 × violence のスイープも追加
scripts/playtest.sh --quick   # 1/10の規模(動作確認用)
```

出力は `build/playtest/report.md`(所見)と `build/playtest/data/*.jsonl`(生データ)。
シード範囲が固定なので**同じコマンドは同じ結果になる**(決定的)。

UI配線の煙感知器(統計ではない)は別口:

```bash
scripts/playtest_ui.py --plays 2   # 要: build/web (verify.shが作る)
```

## 仕組み

`BattleResolver.resolve()`が純粋関数なので、シーンもリアルタイムも不要。
1戦ミリ秒で解ける(500戦1.8秒、実測)。`scripts/playtest.sh`がセルごとに
godotプロセスを起こしてnproc並列でばら撒く。

- `godot/playtest/launch_policy.gd` — ボットの腕。random(下手の下界)〜
  intercept(予告を読み切る上界寄り)。**ボットは人間ではない**ので、
  勝率は1点ではなく方針の幅で読むこと。
- `godot/playtest/invariants.gd` — 全戦闘に掛ける検査(nan、アリーナ脱出、
  rps増加、時刻の整合)。違反レコードには`request`のJSONが丸ごと入っていて、
  `BattleRequest.from_dict()`に食わせればその場で再現できる。
- `godot/playtest/battle_sim.gd` / `run_sim.gd` — 戦闘1回/ラン1本。
  Battle.gd・Main.gdと同じ手順を踏む(出現→発射→resolve、勝利→報酬3枚から
  1枚)。**本体側の進行を変えたらrun_sim.gdも見ること。**
- `godot/tests/test_playtest.gd` — 検査器が壊れた結果を本当に拾うかの常設テスト。

## レポートの読み方

- **戦闘単体の表**: 行=敵レベル、列=ボットの腕。上手いボットでも勝率が
  一桁のレベルは、人間でもほぼ勝てない崖。全列100%のレベルは負けようがない。
- **一度もぶつからない戦闘の率**: 高いと「発射が当たらず自然減衰の我慢比べ」
  になっている。
- **どの段で死ぬか**: ランの難易度曲線。特定の段に死が集中していたら
  そこが崖。
- **パーツ別クリア率差**: 相関であって因果ではない。ただし大きな正の差は
  「そのパーツがないと勝てない」兆候。
- **不変条件違反**: 0件であるべき。出たらシードとJSONで再現し、リゾルバか
  パーツの相互作用のバグを疑う。

## 違反シードの再現

レコードの`request`をそのまま使う:

```gdscript
var request := BattleRequest.from_dict(JSON.parse_string(json_text))
var result := BattleResolver.resolve(request)
```

ラン由来の違反はランのシードから: `RunSim.play_one(seed, ...)`。

## 既知の限界

- ボットの腕は人間と違う。特にinterceptの先読みは等速仮定で、傾斜の曲がりを
  読まない。方針の幅で読むこと。
- run_simの報酬GREEDYは固定の選好順で、人間の状況判断(「今は防御を厚く」)は
  再現しない。
- 経路選びは一様ランダム。現状マップは全ノード敵なので損はないが、
  ノード種別(休憩・宝箱等)を足したら経路方針も要る。
