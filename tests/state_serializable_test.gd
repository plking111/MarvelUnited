extends Node
## 联机可行性前提验证：Game.state 必须是"纯数据"（可 JSON 序列化 → 能整体广播给客户端）。
## 主机权威方案的同步方式就是把 state 序列化后发给客户端，因此这里逐个模式/反派做断言。

var _fail := 0

func _check(n: String, ok: bool, d: String = "") -> void:
	if ok:
		print("PASS: " + n)
	else:
		_fail += 1
		print("FAIL: " + n + " — " + d)

func _ready() -> void:
	Game.autopilot = true
	var cases := [
		{"name": "基础盒红骷髅", "v": "redskull", "h": ["cap", "ironman"], "c": "none", "m": "base", "e": []},
		{"name": "邪恶六人组", "v": "docock", "h": ["spiderman", "miles", "wasp"], "c": "none", "m": "s6", "e": []},
		{"name": "秘密身份", "v": "mysterio", "h": ["cap", "widow", "hulk"], "c": "secretid", "m": "base", "e": []},
		{"name": "叛徒", "v": "kraven", "h": ["cap", "widow", "hulk"], "c": "traitor", "m": "base", "e": []},
		{"name": "濒危地点", "v": "goblin", "h": ["spiderman", "spiderpig"], "c": "endangered", "m": "base", "e": []},
		{"name": "无限战争", "v": "thanos", "h": ["cap", "ironman"], "c": "none", "m": "iw", "e": ["无限战争"]},
		{"name": "第一季众筹英雄", "v": "corvus", "h": ["vision", "hawkeye", "nickfury"], "c": "none", "m": "base", "e": []},
	]
	for cs in cases:
		var heroes: Array = []
		for hh in cs["h"]:
			if DB.heroes.has(hh):
				heroes.append(hh)
		if heroes.is_empty():
			continue
		Game.pending_campaign = {}
		Game.setup(String(cs["v"]), heroes, String(cs["c"]), String(cs["m"]), cs["e"])
		var json := JSON.stringify(Game.state)
		var ok_parse := false
		var back: Variant = JSON.parse_string(json)
		ok_parse = back is Dictionary and (back as Dictionary).has("heroes")
		_check("【%s】state 可 JSON 序列化并回读（%d 字节）" % [cs["name"], json.length()], ok_parse, "序列化/回读失败")
		if ok_parse:
			var bd: Dictionary = back
			_check("【%s】回读后关键字段一致（hero_ids / villain / locations）" % cs["name"],
				str(bd.get("hero_ids", [])) == str(Game.state.get("hero_ids", []))
				and str(bd.get("villain", "")) == str(Game.state.get("villain", ""))
				and (bd.get("locations", []) as Array).size() == (Game.state["locations"] as Array).size(),
				"hero_ids/villain/locations 不一致")
			# 手牌裁剪可行性：客户端只该拿到自己的手牌
			var vis: Dictionary = back
			for hid in (vis.get("heroes", {}) as Dictionary).keys():
				var hh2: Dictionary = vis["heroes"][hid]
				hh2["hand_count"] = (hh2.get("hand", []) as Array).size()
				hh2["hand"] = []
				hh2["deck_count"] = (hh2.get("deck", []) as Array).size()
				hh2["deck"] = []
			_check("【%s】裁剪他人手牌/牌库后仍可正常回读（只留数量）" % cs["name"],
				JSON.parse_string(JSON.stringify(vis)) != null, "裁剪后序列化失败")
	# 是否存在非 JSON 类型（Color/Vector2/Callable 等会在 stringify 时被转成字符串或报错）
	Game.setup("redskull", ["cap", "ironman"], "none", "base")
	print("state 顶层键数量 = %d" % (Game.state as Dictionary).size())
	if _fail == 0:
		print("=== STATE SERIALIZABLE TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		print("=== STATE SERIALIZABLE TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)
