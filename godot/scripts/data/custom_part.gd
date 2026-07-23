class_name CustomPart
extends Resource

## 戦闘に勝つと選べる強化パーツ。archive/flask-prototype/custom_part.py の移植。
##
## プロトタイプは効果ごとにupdate_massのようなメソッドを用意し、
## kwargsで生やした属性(mass_value/mass_calculation)の有無でディスパッチして
## いたが、実際の7個はすべて「あるステータスに定数を掛ける」だけなので、
## 対象ステータスと倍率のデータに畳んだ。
##
## 説明文は数値から自動生成する。プロトタイプでは説明文が手書きで、
## 実際の値と2回食い違っていた:
##  - Spin Engineは「10%上昇」と書いて実際は1.2倍(=20%)。しかも直前のコミットが
##    「パーツ説明が嘘だったので修正」で、修正したそばから再発している。
##  - 以前は「50%上昇 (最大20)」で、上限も実際の40と違っていた。
## 生成にすれば嘘のつきようがない。

enum Rarity { COMMON, RARE }

enum Stat { MASS, RADIUS, FRICTION, RESTITUTION, RPS }

## 効果の種類。既存の札は全部STAT_MULTIPLY（あるステータスに定数を掛ける）。
## STAT_MULTIPLY以外は非ステータス効果で、SpinnerStatsのどの値にも乗らない:
##  - SET_LIVES: コマの性能ではなくランの残機(GameState.continues_left)を触る。
##    適用はGameState.apply_partが担う（CustomPartは純ResourceのままGameStateを参照しない）。
##  - GHOST: 最初の衝突の直後から一定時間だけ敵との衝突を無効化する時間効果
##    (ヒット&ラン: 初撃は通り、直後の報復をすり抜けて離脱する)。すり抜け時間は
##    BattleがCustomPartCatalog.total_ghost_secondsで戦闘へ渡す。
## MOMENTUM: 摩擦(速度減衰)と回転減衰率の両方を multiplier 倍にする「勢い維持」効果。
## 単一ステータス倍率では摩擦しか触れず戦績がほぼ0だったので、回転減衰にも効かせる。
## cap は spin_decay の下限(これ以上は減らさない=青天井/無限HP化を防ぐ)。
##
## RAGE: 反発(restitution)を multiplier 倍(cap上限)にしつつ、壁でのrps喪失を
## 減らす(wall_keepを wall_keep_step ぶん加算、上限1.0)複合効果。反発upは相手を
## 壁へ押し込む攻撃用途として残しつつ、wall_keepで自分の壁ダメージを減らす。
##
## GUARD: コマ同士の衝突で受けるrps削りを減らす(hit_guardを hit_guard_step ぶん
## 加算、上限hit_guard_max)。壁のRAGE(wall_keep)と対になる衝突版の純防御。
##
## EDGE: コマ同士の衝突で相手に与えるrps削りを増やす(edgeを edge_step ぶん加算、
## 上限edge_max)。GUARD(受け)と対になる攻めの軸で、当てにいくプレイを装備側から
## 支える(撃破ボーナスと同じ狙い)。相手のspin_kickは受けた削り量に比例するので、
## 強く削るほど相手を強く弾き飛ばす=壁への押し込みとも噛み合う。
##
## GROWTH: 直径と質量の両方を倍にする「巨大化」。直径だけの倍率(旧GIANT_GROWTH)は
## 自然減衰(radius×spin_decayに比例)の悪化が上回り、単独計測でLv3 -6.4pt/枚と
## 唯一の純マイナス札だった=「報酬は全部プラス」の原則(CustomPartCatalog.all参照)に
## 実測で反していた。大きくなるなら重くもなる方が直感にも合い、質量が衝突耐性
## (削りは1/(質量×半径²))と弾き飛ばしを補って、寿命悪化と引き換えの本物の
## トレードオフになる。
## SPIN_UP: 回転数(rps)を定数だけ加算する(上限cap)。倍率のSPIN_ENGINE(RARE)と違い
## 引き運に依存しにくいCOMMONの確実な回転成長。敵のrpsはLv1→5で15→33まで伸びるのに、
## プレイヤーの回転成長は勝利成長(+0.5/+1.0)とRARE札だけで、SPIN_ENGINEを引けない
## ランはLv4帯(rps26)とのプール差が構造的に埋まらなかった(コールドプレイで報酬8画面
## 中rps札の提示0回・rps21vs26で全滅、が一次証拠)。
enum Effect { STAT_MULTIPLY, SET_LIVES, GHOST, MOMENTUM, RAGE, GUARD, GROWTH, EDGE, SPIN_UP }

## レアカードの見た目。報酬選択とマップの取得済み一覧で同じ強調を使うため、
## パーツ側に置いて共有する。地が明るい金色なので文字は暗くしないと読めない。
const RARE_TEXT_COLOR := Palette.TEXT_ON_LIGHT

## 効果の説明に使う翻訳キー。倍率と上限を埋め込む。
const _STAT_KEYS := {
	Stat.MASS: "PART_EFFECT_MASS",
	Stat.RADIUS: "PART_EFFECT_RADIUS",
	Stat.FRICTION: "PART_EFFECT_FRICTION",
	Stat.RESTITUTION: "PART_EFFECT_RESTITUTION",
	Stat.RPS: "PART_EFFECT_RPS",
}

## 倍率だけでは何が起きるか読み取れないので、実際の挙動を一言添える。
## キーは PART_NOTE_<ステータス>_<UP|DOWN> の形。上げ下げで効果が逆になる
## ステータス（特に半径は衝突減衰と自然減衰が逆に動く）ので方向で分ける。
## 未使用の方向でも、後でデバフ札を足したとき訳抜けが素で見えるよう両方置く。
const _STAT_NAMES := {
	Stat.MASS: "MASS",
	Stat.RADIUS: "RADIUS",
	Stat.FRICTION: "FRICTION",
	Stat.RESTITUTION: "RESTITUTION",
	Stat.RPS: "RPS",
}

@export var id: int = 0

## パーツ名の翻訳キー。
@export var title_key: String = ""

@export var rarity: Rarity = Rarity.COMMON

## 効果の種類。デフォルトはステータス倍率。
@export var effect: Effect = Effect.STAT_MULTIPLY

## どのステータスに掛けるか。effectがSTAT_MULTIPLYのときだけ意味を持つ。
@export var stat: Stat = Stat.MASS

## 掛ける倍率。1未満なら下げる効果。
@export var multiplier: float = 1.0

## 上限。0以下なら上限なし。
@export var cap: float = 0.0

## SET_LIVESで引き上げる残機。他の札では0（GameState.apply_partのmaxiが無害になる）。
@export var lives: int = 0

## ゴースト1枚あたりのすり抜け秒数(最初の衝突後に効く)。effectがGHOSTのときだけ意味を持つ。
## 合計時間(=枚数×これ)はCustomPartCatalog.total_ghost_secondsが出す。
@export var ghost_seconds: float = 0.0

## RAGE札が1枚あたり加算する壁rps保持量(wall_keepへ加算)。
@export var wall_keep_step: float = 0.0

## RAGE札のwall_keep上限。壁を完全無損失(1.0)にすると無敵化するので1未満で頭打ち。
@export var wall_keep_max: float = 1.0

## GUARD札が1枚あたり加算する衝突rps保持量(hit_guardへ加算)。
@export var hit_guard_step: float = 0.0

## GUARD札のhit_guard上限。1.0(衝突削り無効)まで許すと無敵化するので1未満で頭打ち。
@export var hit_guard_max: float = 1.0

## EDGE札が1枚あたり加算する与ダメ増強量(edgeへ加算)。0.2で与える削り+20%。
@export var edge_step: float = 0.0

## EDGE札のedge上限。重ねがけの複利で削りが青天井にならないよう頭打ちにする。
@export var edge_max: float = 1.0

## GROWTH札が質量に掛ける倍率。直径側の倍率は multiplier / 上限は cap を使う。
@export var mass_multiplier: float = 1.0

## GROWTH札の質量上限。0以下なら上限なし。
@export var mass_cap: float = 0.0

## SPIN_UP札が1枚あたり加算する回転数。上限は cap(SpinnerStats.RPS_CAPを渡す)。
@export var rps_step: float = 0.0


static func make(
	id_: int, title_key_: String, rarity_: Rarity, stat_: Stat,
	multiplier_: float, cap_: float = 0.0
) -> CustomPart:
	var part := CustomPart.new()
	part.id = id_
	part.title_key = title_key_
	part.rarity = rarity_
	part.stat = stat_
	part.multiplier = multiplier_
	part.cap = cap_
	return part


## 残機を引き上げる札を作る。ステータスには触らないので stat/multiplier/cap は既定のまま。
static func make_set_lives(
	id_: int, title_key_: String, rarity_: Rarity, lives_: int
) -> CustomPart:
	var part := CustomPart.new()
	part.id = id_
	part.title_key = title_key_
	part.rarity = rarity_
	part.effect = Effect.SET_LIVES
	part.lives = lives_
	return part


## ゴースト札を作る。ステータスは変えず、開始後seconds_秒だけ敵との衝突を消す。
static func make_ghost(
	id_: int, title_key_: String, rarity_: Rarity, seconds_: float
) -> CustomPart:
	var part := CustomPart.new()
	part.id = id_
	part.title_key = title_key_
	part.rarity = rarity_
	part.effect = Effect.GHOST
	part.ghost_seconds = seconds_
	return part


## 勢い維持札を作る。摩擦とspin_decayの両方を multiplier 倍にする。
## spin_decay_floor_ は spin_decay の下限（重ねても回転減衰をこれ以下にはしない）。
static func make_momentum(
	id_: int, title_key_: String, rarity_: Rarity,
	multiplier_: float, spin_decay_floor_: float = 0.0
) -> CustomPart:
	var part := CustomPart.new()
	part.id = id_
	part.title_key = title_key_
	part.rarity = rarity_
	part.effect = Effect.MOMENTUM
	part.multiplier = multiplier_
	part.cap = spin_decay_floor_
	return part


## 怒りの反射札を作る。反発を restitution_mult 倍(restitution_cap上限)にしつつ、
## 壁rps保持を wall_keep_step_ ぶん上げる複合札。
static func make_rage(
	id_: int, title_key_: String, rarity_: Rarity,
	restitution_mult_: float, restitution_cap_: float,
	wall_keep_step_: float, wall_keep_max_: float
) -> CustomPart:
	var part := CustomPart.new()
	part.id = id_
	part.title_key = title_key_
	part.rarity = rarity_
	part.effect = Effect.RAGE
	part.multiplier = restitution_mult_
	part.cap = restitution_cap_
	part.wall_keep_step = wall_keep_step_
	part.wall_keep_max = wall_keep_max_
	return part


## 巨大化札を作る。直径を radius_mult_ 倍(radius_cap_上限)、質量を mass_mult_ 倍
## (mass_cap_上限)にする複合。直径には自然減衰の悪化(radius×spin_decayに比例)が
## あるので、質量側の上乗せで純マイナスにならないようにする(効果注記で代償も謳う)。
static func make_growth(
	id_: int, title_key_: String, rarity_: Rarity,
	radius_mult_: float, radius_cap_: float,
	mass_mult_: float, mass_cap_: float
) -> CustomPart:
	var part := CustomPart.new()
	part.id = id_
	part.title_key = title_key_
	part.rarity = rarity_
	part.effect = Effect.GROWTH
	part.multiplier = radius_mult_
	part.cap = radius_cap_
	part.mass_multiplier = mass_mult_
	part.mass_cap = mass_cap_
	return part


## シャープエッジ札を作る。衝突で相手に与えるrps削りの増強(edge)を step_ ぶん上げる。
## max_ は重ねがけの上限(与ダメの複利が青天井にならないよう頭打ちにする)。
static func make_edge(
	id_: int, title_key_: String, rarity_: Rarity,
	step_: float, max_: float
) -> CustomPart:
	var part := CustomPart.new()
	part.id = id_
	part.title_key = title_key_
	part.rarity = rarity_
	part.effect = Effect.EDGE
	part.edge_step = step_
	part.edge_max = max_
	return part


## 衝撃吸収札を作る。衝突で受けるrps削りの軽減(hit_guard)を step_ ぶん上げる。
## max_ は重ねがけの上限(1.0=削り無効の無敵化を防ぐためRAGEと同様1未満)。
static func make_guard(
	id_: int, title_key_: String, rarity_: Rarity,
	step_: float, max_: float
) -> CustomPart:
	var part := CustomPart.new()
	part.id = id_
	part.title_key = title_key_
	part.rarity = rarity_
	part.effect = Effect.GUARD
	part.hit_guard_step = step_
	part.hit_guard_max = max_
	return part


## 回転加算札を作る。rpsを step_ だけ加算する(cap_上限)。
static func make_spin_up(
	id_: int, title_key_: String, rarity_: Rarity,
	step_: float, cap_: float
) -> CustomPart:
	var part := CustomPart.new()
	part.id = id_
	part.title_key = title_key_
	part.rarity = rarity_
	part.effect = Effect.SPIN_UP
	part.rps_step = step_
	part.cap = cap_
	return part


func apply_to(stats: SpinnerStats) -> void:
	# 勢い維持(MOMENTUM): 摩擦と回転減衰の両方を下げる。spin_decayはcapを下限に
	# クランプして、重ねても回転減衰がゼロ(=無限に回る)にならないようにする。
	if effect == Effect.MOMENTUM:
		stats.friction *= multiplier
		var decayed := stats.spin_decay * multiplier
		if cap > 0.0:
			decayed = maxf(decayed, cap)
		stats.spin_decay = decayed
		return
	# 衝撃吸収(GUARD): 衝突で受けるrps削りを減らす(hit_guard加算)。上限で頭打ちに
	# して、重ねがけで削り無効(=衝突無敵)にならないようにする。
	if effect == Effect.GUARD:
		stats.hit_guard = minf(stats.hit_guard + hit_guard_step, hit_guard_max)
		return
	# シャープエッジ(EDGE): 衝突で相手に与えるrps削りを増やす(edge加算)。上限で
	# 頭打ちにして、重ねがけの複利で削りが青天井にならないようにする。
	if effect == Effect.EDGE:
		stats.edge = minf(stats.edge + edge_step, edge_max)
		return
	# 巨大化(GROWTH): 直径と質量の両方を倍にする。それぞれ上限でクランプ
	# (直径はアリーナを埋め尽くさないよう、質量は青天井の複利を防ぐよう)。
	if effect == Effect.GROWTH:
		var grown_radius := stats.radius * multiplier
		if cap > 0.0:
			grown_radius = minf(grown_radius, cap)
		stats.radius = grown_radius
		var grown_mass := stats.mass * mass_multiplier
		if mass_cap > 0.0:
			grown_mass = minf(grown_mass, mass_cap)
		stats.mass = grown_mass
		return
	# 回転加算(SPIN_UP): rpsを定数だけ足す(上限cap)。勝利成長と同じ加算で、
	# 倍率札(SPIN_ENGINE)と違い現在値に依存しない確実な底上げ。
	if effect == Effect.SPIN_UP:
		var boosted := stats.rps + rps_step
		if cap > 0.0:
			boosted = minf(boosted, cap)
		stats.rps = boosted
		return
	# 怒りの反射(RAGE): 反発を上げつつ(cap上限)、壁rps喪失を減らす(wall_keep加算)。
	if effect == Effect.RAGE:
		var rest := stats.restitution * multiplier
		if cap > 0.0:
			rest = minf(rest, cap)
		stats.restitution = rest
		# 壁rps保持はwall_keep_maxで頭打ち。1.0(完全無損失)まで許すと重ねがけで
		# 壁ダメージ皆無＝ほぼ無敵になり、ラン単位で壊れる(計測で+59pt)ため。
		stats.wall_keep = minf(stats.wall_keep + wall_keep_step, wall_keep_max)
		return
	# 非ステータスの札(残機・ゴースト)はコマの性能を一切いじらない。残機はGameState.
	# apply_partが、ゴーストの無敵時間はBattleが処理する。
	if effect != Effect.STAT_MULTIPLY:
		return
	var value := _read(stats) * multiplier
	if cap > 0.0:
		value = minf(value, cap)
	_write(stats, value)


## 死にカード判定で「意味のある変化」とみなす相対閾値(1%)。
##
## 厳密比較(is_equal_approx、誤差~1e-5)だと、上限クランプ間際の微小な残りが
## 「変化あり」扱いになる: RAGE3枚で反発は0.75×1.1³=0.99825(表示は1.00)・
## wall_keepは上限0.5に達し、4枚目の効果は反発+0.00175だけ——小数2桁の表示にすら
## 現れない実質死に札が、上限到達後も提示され続けていた。値の1%未満しか動かない
## 変化は「何も変わらない」とみなして弾く。
const MEANINGFUL_CHANGE_RATIO := 0.01


## この札を今取って、何かが実際に変わるか（死にカード判定）。
##
## 上限に達したステータスしか触らない札（例: rps=40でのSPIN_ENGINE）は、取っても
## 文字どおり何も起きない。それでも抽選に出続けると「どれを選んでも意味がない」
## 報酬画面ができてしまうので、CustomPartCatalog.pick_choicesが提示前にこれで弾く。
## 判定は複製へ実際にapply_toして全フィールドを比較する——apply_toと別実装の
## 予測ロジックを持つと、効果を変えたときに判定だけが古い嘘になるため。
## 比較は厳密一致ではなくMEANINGFUL_CHANGE_RATIOの相対閾値(上のコメント参照)。
## livesは現在の残機。負なら「残機不明」としてSET_LIVES札は常に有効扱いにする。
func would_change_anything(stats: SpinnerStats, lives_now: int = -1) -> bool:
	# ゴーストは重ねるほどすり抜け時間が線形に伸びる(上限なし)ので常に意味がある。
	if effect == Effect.GHOST:
		return true
	# 残機札はステータスに触らない。maxi適用で残機が実際に増えるときだけ有効。
	if effect == Effect.SET_LIVES:
		return lives_now < 0 or lives_now < lives
	var probe := stats.duplicate_stats()
	apply_to(probe)
	return not _stats_equal(probe, stats)


## 全フィールドに「意味のある変化」が無いか。would_change_anything専用
## （apply_toが触りうる値を全部見る）。
static func _stats_equal(a: SpinnerStats, b: SpinnerStats) -> bool:
	return (
		_nearly_same(a.mass, b.mass)
		and _nearly_same(a.radius, b.radius)
		and _nearly_same(a.friction, b.friction)
		and _nearly_same(a.restitution, b.restitution)
		and _nearly_same(a.rps, b.rps)
		and _nearly_same(a.spin_decay, b.spin_decay)
		and _nearly_same(a.wall_keep, b.wall_keep)
		and _nearly_same(a.hit_guard, b.hit_guard)
		and _nearly_same(a.edge, b.edge)
	)


## 2値の差がMEANINGFUL_CHANGE_RATIO(相対1%)未満なら「同じ」とみなす。
## 基準は両値の大きい方。ただし0近傍のフィールド(wall_keep/edgeの初期0など)で
## 相対比較が過敏にならないよう、基準には1.0の下駄を敷く(=絶対0.01が最低ライン。
## 現行カタログの加算刻みは最小0.17なので本物の効果を誤爆で弾くことはない)。
static func _nearly_same(a: float, b: float) -> bool:
	var scale := maxf(maxf(absf(a), absf(b)), 1.0)
	return absf(a - b) <= MEANINGFUL_CHANGE_RATIO * scale


## レアカードの金色スタイルボックス。報酬選択とマップ一覧で共有する。
static func rare_stylebox() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.GOLD_CARD
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


## 実際の値から説明文を組み立てる。手書きしないので数値と食い違わない。
## 1行目は「質量 ×1.6（上限 8）」の生の倍率、2行目に実際の挙動を一言。
func describe() -> String:
	if effect == Effect.SET_LIVES:
		return tr("PART_EFFECT_SET_LIVES").format([lives])
	# ゴーストは倍率を持たないので、無敵秒数を埋めた専用の説明を返す。
	if effect == Effect.GHOST:
		return tr("PART_EFFECT_GHOST").format([_trim(ghost_seconds)])
	# 勢い維持は摩擦と回転減衰の両方に効く。倍率を埋めた専用の説明に、挙動の
	# 注記を添える——「摩擦×0.8」だけでは下がる=良いことが初見に伝わらない
	# (コールドプレイでは寿命目安の併記に救われて選べた、が実UIにその救いはない)。
	if effect == Effect.MOMENTUM:
		return tr("PART_EFFECT_MOMENTUM").format([_trim(multiplier)]) + "\n" + tr("PART_NOTE_MOMENTUM")
	# 怒りの反射は反発倍率と壁rps保持の複合。両方を埋めた専用の説明を返す。
	if effect == Effect.RAGE:
		return tr("PART_EFFECT_RAGE").format([_trim(multiplier), _trim(cap)])
	# 衝撃吸収は軽減率を%で見せる(0.17より17%の方が読める)。上限も%で併記する。
	if effect == Effect.GUARD:
		return tr("PART_EFFECT_GUARD").format(
			[_trim(hit_guard_step * 100.0), _trim(hit_guard_max * 100.0)]
		)
	# シャープエッジも増強率を%で見せる(GUARDと同じ読みやすさの判断)。
	if effect == Effect.EDGE:
		return tr("PART_EFFECT_EDGE").format(
			[_trim(edge_step * 100.0), _trim(edge_max * 100.0)]
		)
	# 回転加算は「+2（上限 40）」の加算表記。挙動注記はRPS上昇の既存文を使い回す
	# (倍率でも加算でも起きることは同じ: 開始回転が増え寿命が延びる)。
	if effect == Effect.SPIN_UP:
		return (
			tr("PART_EFFECT_SPIN_UP").format([_trim(rps_step), _trim(cap)])
			+ "\n" + tr("PART_NOTE_RPS_UP")
		)
	# 巨大化は直径と質量の複合。代償(自然減衰の悪化)を効果注記で必ず謳う——
	# 直径だけの旧版は代償が読めない罠札で、効果文だけで選ぶと損をする札だった。
	if effect == Effect.GROWTH:
		return (
			tr("PART_EFFECT_GROWTH").format(
				[_trim(multiplier), _trim(cap), _trim(mass_multiplier), _trim(mass_cap)]
			)
			+ "\n" + tr("PART_NOTE_GROWTH")
		)
	var text: String = tr(_STAT_KEYS[stat]).format([_trim(multiplier)])
	if cap > 0.0:
		text += tr("PART_EFFECT_CAP").format([_trim(cap)])
	var note := _effect_note()
	if note != "":
		text += "\n" + note
	return text


## 倍率の向きから実際の挙動の説明を引く。倍率が1（効果なし）なら空。
func _effect_note() -> String:
	if is_equal_approx(multiplier, 1.0):
		return ""
	var direction := "UP" if multiplier > 1.0 else "DOWN"
	return tr("PART_NOTE_%s_%s" % [_STAT_NAMES[stat], direction])


## 1.20 -> "1.2", 2.00 -> "2" のように余分な0を落とす。
static func _trim(value: float) -> String:
	var text := "%.2f" % value
	while text.ends_with("0"):
		text = text.substr(0, text.length() - 1)
	if text.ends_with("."):
		text = text.substr(0, text.length() - 1)
	return text


func _read(stats: SpinnerStats) -> float:
	match stat:
		Stat.MASS:
			return stats.mass
		Stat.RADIUS:
			return stats.radius
		Stat.FRICTION:
			return stats.friction
		Stat.RESTITUTION:
			return stats.restitution
		_:
			return stats.rps


func _write(stats: SpinnerStats, value: float) -> void:
	match stat:
		Stat.MASS:
			stats.mass = value
		Stat.RADIUS:
			stats.radius = value
		Stat.FRICTION:
			stats.friction = value
		Stat.RESTITUTION:
			stats.restitution = value
		_:
			stats.rps = value
