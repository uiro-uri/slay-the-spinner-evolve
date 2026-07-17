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

@export var id: int = 0

## パーツ名の翻訳キー。
@export var title_key: String = ""

@export var rarity: Rarity = Rarity.COMMON

## どのステータスに掛けるか。
@export var stat: Stat = Stat.MASS

## 掛ける倍率。1未満なら下げる効果。
@export var multiplier: float = 1.0

## 上限。0以下なら上限なし。
@export var cap: float = 0.0


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


func apply_to(stats: SpinnerStats) -> void:
	var value := _read(stats) * multiplier
	if cap > 0.0:
		value = minf(value, cap)
	_write(stats, value)


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
func describe() -> String:
	var text: String = tr(_STAT_KEYS[stat]).format([_trim(multiplier)])
	if cap > 0.0:
		text += tr("PART_EFFECT_CAP").format([_trim(cap)])
	return text


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
