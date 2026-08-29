extends Node
## DB: 加载并缓存全部卡牌/地点/任务 JSON 数据。

var heroes: Dictionary = {}
var villains: Dictionary = {}
var locations: Dictionary = {}
var missions: Array = []
var challenges: Array = []

func _ready() -> void:
	load_data()

func load_data() -> void:
	heroes = _load_json("res://data/heroes.json")
	villains = _load_json("res://data/villains.json")
	locations = _load_json("res://data/locations.json").get("locations", {})
	var m = _load_json("res://data/missions.json")
	missions = m.get("missions", [])
	challenges = m.get("challenges", [])
	assert(heroes.size() == 5, "英雄数据应有5位")
	assert(villains.size() == 3, "反派数据应有3个")
	assert(locations.size() == 8, "地点数据应有8张")
	assert(missions.size() == 3, "任务卡应有3张")

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "无法打开数据文件: " + path)
	var text := f.get_as_text()
	var parsed = JSON.parse_string(text)
	assert(parsed != null, "JSON 解析失败: " + path)
	return parsed

## 返回英雄的卡牌数组（12张）
func hero_cards(hero_id: String) -> Array:
	return heroes[hero_id]["cards"]

func hero_name(hero_id: String) -> String:
	return heroes[hero_id]["name"]

func hero_color(hero_id: String) -> Color:
	return Color(heroes[hero_id].get("color", "#888888"))

func hero_back(hero_id: String) -> String:
	return heroes[hero_id]["back"]

func villain(id: String) -> Dictionary:
	return villains[id]

func villain_name(id: String) -> String:
	return villains[id]["name"]

func villain_image(id: String) -> String:
	return villains[id]["image"]

func location(id: String) -> Dictionary:
	return locations[id]

func location_name(id: String) -> String:
	return locations[id]["name"]

func location_image(id: String) -> String:
	return locations[id]["image"]

## 符号中文名（UI 用）
func symbol_name(sym: String) -> String:
	match sym:
		"move": return "移动"
		"attack": return "攻击"
		"heroic": return "英勇"
		"wild": return "万能"
		_: return sym
