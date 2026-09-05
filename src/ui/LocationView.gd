class_name LocationView
extends Control
## 地点视图模块：一张地点卡的全部内容（卡面、名称、民/暴槽位、危机、
## 威胁卡 + 英勇槽 + 爪牙生命、威胁指示物、反派所在地高亮）。
##
## 新增地图：加 data/locations.json 条目 + 卡图即可；若新卡槽位布局不同，
## 在本文件 SLOT_TEMPLATES 中按格数追加模板（比例相对卡片左上角）。

const LOC_CARD_SIZE := 230.0

# 地点槽位位置模板（按格数，比例相对卡片左上角，来自用户实测）
# 2格 y=0.199 x=[0.42,0.58]；3格 y=0.199 x=[0.340,0.504,0.657]；4格 y=0.192 x=[0.290,0.418,0.580,0.724]；5格 y=0.192 x=[0.199,0.351,0.498,0.660,0.788]
const SLOT_TEMPLATES := {
	2: {"y": 0.199, "x": [0.42, 0.58]},
	3: {"y": 0.199, "x": [0.340, 0.504, 0.657]},
	4: {"y": 0.192, "x": [0.290, 0.418, 0.580, 0.724]},
	5: {"y": 0.192, "x": [0.199, 0.351, 0.498, 0.660, 0.788]},
}

# 威胁卡下半部分的英勇槽位置（比例，相对威胁卡左上角；三个反派布局一致）
const THREAT_HEROIC_SLOTS := {"xs": [0.188, 0.506, 0.827], "y": 0.802}

var i: int
var _pos: Vector2
var card: TextureRect
var name_label: Label
var threat: TextureRect
var threat_label: Label
var threat_hp_icon: TextureRect
var slots: Array = []          # [{"icon": TextureRect, "empty": ColorRect}]
var crisis_icon: TextureRect
var crisis_label: Label
var threat_slot: ColorRect
var threat_marker: TextureRect
var heroic_slots: Array = []
var _endangered_icon: TextureRect   # 濒危地点：守卫指示物（地点左上角）

var _icon_civ: Texture2D
var _icon_thug: Texture2D
var _icon_crisis: Texture2D
var _icon_threat: Texture2D
var _icon_heroic: Texture2D

## on_clicked: Callable(event) —— 由 Board 绑定好地点序号后传入
func setup(idx: int, pos: Vector2, bank: Dictionary, on_clicked: Callable) -> void:
	i = idx
	_pos = pos
	_icon_civ = bank.get("civ")
	_icon_thug = bank.get("thug")
	_icon_crisis = bank.get("crisis")
	_icon_threat = bank.get("threat")
	_icon_heroic = bank.get("heroic")
	# 地点卡（可点击查看详情）
	card = TextureRect.new()
	card.position = _pos - Vector2(LOC_CARD_SIZE / 2, LOC_CARD_SIZE / 2)
	card.custom_minimum_size = Vector2(LOC_CARD_SIZE, LOC_CARD_SIZE)
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.gui_input.connect(on_clicked)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(card)
	# 地点中文名（卡片上边缘外侧，不遮挡卡面）
	name_label = UiKit.label("", 17, Color(1, 0.95, 0.8))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	name_label.add_theme_constant_override("outline_size", 5)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = _pos + Vector2(-LOC_CARD_SIZE / 2, -LOC_CARD_SIZE / 2 - 24)
	name_label.custom_minimum_size = Vector2(LOC_CARD_SIZE, 24)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_label)
	# 左下角：白色方块（常驻，放置威胁指示物）
	threat_slot = ColorRect.new()
	threat_slot.color = Color(1, 1, 1, 0.92)
	threat_slot.position = _pos + Vector2(-LOC_CARD_SIZE / 2 + 8, LOC_CARD_SIZE / 2 - 48)
	threat_slot.custom_minimum_size = Vector2(40, 40)
	threat_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(threat_slot)
	# 威胁指示物（有威胁卡时显示，清除后隐藏）
	threat_marker = TextureRect.new()
	threat_marker.custom_minimum_size = Vector2(28, 28)
	threat_marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	threat_marker.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	threat_marker.texture = _icon_threat
	threat_marker.position = _pos + Vector2(-LOC_CARD_SIZE / 2 + 14, LOC_CARD_SIZE / 2 - 42)
	threat_marker.visible = false
	threat_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(threat_marker)
	# 威胁卡：完整小卡，上部 3/5 覆盖地点卡底部白色效果框，下部 2/5 伸出卡片边缘
	threat = TextureRect.new()
	threat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	threat.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	threat.visible = false
	threat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(threat)
	# 非爪牙威胁卡的英勇槽（3 个，威胁卡子节点相对定位）
	for si in range(3):
		var sr := TextureRect.new()
		sr.custom_minimum_size = Vector2(30, 30)
		sr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sr.texture = _icon_heroic
		sr.visible = false
		sr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		threat.add_child(sr)
		heroic_slots.append(sr)
	# 爪牙生命值（威胁卡左下角；图标 + 数字；普通威胁不显示）
	threat_hp_icon = TextureRect.new()
	threat_hp_icon.texture = load("res://assets/tokens/hp_icon.png")
	threat_hp_icon.custom_minimum_size = Vector2(20, 20)
	threat_hp_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	threat_hp_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	threat_hp_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	threat_hp_icon.visible = false
	add_child(threat_hp_icon)
	threat_label = Label.new()
	threat_label.add_theme_font_size_override("font_size", 15)
	threat_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	threat_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	threat_label.add_theme_constant_override("outline_size", 5)
	threat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	threat_label.position = _pos + Vector2(-40, 40)
	threat_label.custom_minimum_size = Vector2(60, 20)
	add_child(threat_label)
	# 槽位：最多 5 个（在威胁卡上层显示）
	for si in range(5):
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(26, 26)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.visible = false
		add_child(icon)
		var empty := ColorRect.new()
		empty.color = Color(1, 1, 1, 0.28)
		empty.custom_minimum_size = Vector2(24, 24)
		empty.visible = false
		add_child(empty)
		slots.append({"icon": icon, "empty": empty})
	# 危机指示物（卡片右下角：图标 + 数量）
	crisis_icon = TextureRect.new()
	crisis_icon.custom_minimum_size = Vector2(26, 26)
	crisis_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crisis_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crisis_icon.visible = false
	add_child(crisis_icon)
	# 濒危地点守卫指示物（地点卡左上角）
	_endangered_icon = TextureRect.new()
	_endangered_icon.custom_minimum_size = Vector2(40, 40)
	_endangered_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_endangered_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_endangered_icon.visible = false
	add_child(_endangered_icon)
	crisis_label = Label.new()
	crisis_label.add_theme_font_size_override("font_size", 15)
	crisis_label.add_theme_color_override("font_color", Color(0.85, 0.85, 1))
	crisis_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	crisis_label.add_theme_constant_override("outline_size", 5)
	crisis_label.position = _pos + Vector2(34, 44)
	add_child(crisis_label)

## 根据最新游戏状态刷新本地点全部内容
func refresh(state: Dictionary) -> void:
	var l: Dictionary = state["locations"][i]
	card.texture = load(DB.location_image(l["id"]))
	name_label.text = DB.location_name(l["id"])
	# 槽位填充：先平民后暴徒；基尔格蒙时危机也占槽位
	var slots_total: int = int(DB.location(l["id"])["slots"])
	var fill: Array = []
	for ci in range(l["civ"]):
		fill.append("civ")
	for ti in range(l["thug"]):
		fill.append("thug")
	var km: bool = state.get("villain", "") == "kilmonger"
	if km:
		for ki in range(l["crisis"]):
			fill.append("crisis")
	# 槽位按格数模板定位（对齐卡面白色方块）
	var tpl: Dictionary = SLOT_TEMPLATES[slots_total]
	var ratios: Array = tpl["x"]
	var sy_ratio: float = tpl["y"]
	for si in range(5):
		var icon: TextureRect = slots[si]["icon"]
		var empty: ColorRect = slots[si]["empty"]
		if si < slots_total:
			var sx: float = _pos.x - LOC_CARD_SIZE / 2 + LOC_CARD_SIZE * ratios[si]
			var sy: float = _pos.y - LOC_CARD_SIZE / 2 + LOC_CARD_SIZE * sy_ratio
			icon.position = Vector2(sx - 13, sy - 13)
			empty.position = Vector2(sx - 12, sy - 12)
			if si < fill.size():
				var kind: String = fill[si]
				icon.texture = _icon_civ if kind == "civ" else (_icon_thug if kind == "thug" else _icon_crisis)
				icon.visible = true
				empty.visible = false
			else:
				icon.visible = false
				empty.visible = true
		else:
			icon.visible = false
			empty.visible = false
	# 危机：基尔格蒙时已填充到槽位（不再右下角）；否则单独显示右下角
	if km:
		crisis_icon.visible = false
		crisis_label.visible = false
	elif l["crisis"] > 0:
		crisis_icon.texture = _icon_crisis
		crisis_icon.position = crisis_label.position + Vector2(-30, 2)
		crisis_icon.visible = true
		crisis_label.text = "x%d" % l["crisis"]
		crisis_label.visible = true
	else:
		crisis_icon.visible = false
		crisis_label.visible = false
	# 濒危地点：守卫指示物（地点卡左上角；按守护玩家的序号显示对应数字指示物）
	_endangered_icon.visible = false
	if state.get("challenge", "") == "endangered":
		var end: Dictionary = state.get("endangered", {})
		if end.has("setup_done"):
			for hid in state["hero_ids"]:
				if int(end.get(hid, -1)) == i:
					var idx: int = state["hero_ids"].find(hid)   # 玩家序号0-based
					var num: int = idx + 1                        # 指示物数字 1-4
					var tex: Texture2D = load("res://assets/tokens/endangered_%d.png" % num)
					_endangered_icon.texture = tex
					# 地点卡右上角、超出边缘少许
					var tl: Vector2 = _pos - Vector2(LOC_CARD_SIZE / 2, LOC_CARD_SIZE / 2)
					_endangered_icon.position = tl + Vector2(LOC_CARD_SIZE - 20, -14)
					_endangered_icon.visible = true
					break
	# 威胁卡：完整小卡，上部 3/5 覆盖底部效果框，下部 2/5 伸出卡片边缘
	if l["threat"] != null:
		var t: Dictionary = l["threat"]
		var img: Texture2D = load(_threat_image_path(state, t))
		threat.texture = img
		# 按图像比例填满一侧宽度（不留白不变形；竖版固定宽 96，横版固定高 96）
		var is_portrait: bool = img.get_width() < img.get_height()
		var tw: float
		var th: float
		if is_portrait:
			tw = 96.0
			th = 96.0 * img.get_height() / float(img.get_width())
		else:
			th = 96.0
			tw = 96.0 * img.get_width() / float(img.get_height())
		threat.custom_minimum_size = Vector2(tw, th)
		# 上缘 = 卡底 - 0.6*高（3/5 在地点卡内），下缘伸出卡底 0.4*高（2/5 超出）
		threat.position = _pos + Vector2(-tw / 2, LOC_CARD_SIZE / 2 - th * 0.6)
		threat.visible = true
		# 爪牙生命值显示在威胁卡左下角（普通威胁无生命不显示）
		if t["hp"] > 0:
			threat_label.text = "%d" % t["hp"]
			var hp_pos: Vector2 = _pos + Vector2(-tw / 2 + 2, LOC_CARD_SIZE / 2 - th * 0.6 + th - 18)
			threat_label.position = hp_pos + Vector2(22, 0)
			threat_label.visible = true
			threat_hp_icon.position = hp_pos
			threat_hp_icon.visible = true
		else:
			threat_label.visible = false
			threat_hp_icon.visible = false
		# 非爪牙威胁卡：下半部分 3 个英勇槽（偏白圆环）+ 英勇指示物进度
		_update_threat_heroic_slots(t)
	else:
		threat.visible = false
		threat_label.visible = false
		threat_hp_icon.visible = false
	# 左下角威胁指示物：有威胁卡时显示，清除威胁后隐藏
	threat_marker.visible = l["threat"] != null
	# 反派所在地高亮
	card.modulate = Color(1.25, 1.05, 1.05) if state["villain_pos"] == i else Color.WHITE

## 非爪牙威胁卡：更新 3 个英勇槽（空槽偏白半透明，已放指示物全亮）
func _update_threat_heroic_slots(t: Dictionary) -> void:
	var tw: float = threat.custom_minimum_size.x
	var th: float = threat.custom_minimum_size.y
	var xs: Array = THREAT_HEROIC_SLOTS["xs"]
	var sy: float = THREAT_HEROIC_SLOTS["y"]
	var tokens: int = int(t.get("heroic_tokens", 0))
	# 指示物尺寸：接近槽间距（横版卡 38px、竖版卡 27px）
	var size: float = 38.0 if tw > 100.0 else 27.0
	for si in range(3):
		var sr: TextureRect = heroic_slots[si]
		if t["hp"] > 0:
			sr.visible = false
			continue
		sr.visible = true
		sr.custom_minimum_size = Vector2(size, size)
		sr.position = Vector2(float(xs[si]) * tw - size / 2.0, sy * th - size / 2.0 + 4.0)
		sr.modulate = Color(1, 1, 1, 1.0) if si < tokens else Color(1, 1, 1, 0.3)

func _threat_image_path(state: Dictionary, t: Dictionary) -> String:
	var vid: String = state["villain"]
	var threats: Array = DB.villain(vid)["threats"]
	var idx := 0
	for i in range(threats.size()):
		if threats[i]["name"] == t["name"]:
			idx = i
			break
	return "res://assets/cards/villains/%s/threat_%02d.png" % [vid, idx + 1]
