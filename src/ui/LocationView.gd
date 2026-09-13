class_name LocationView
extends Control
## 地点视图模块：一张地点卡的全部内容（卡面、名称、民/暴槽位、危机、
## 威胁卡 + 英勇槽 + 爪牙生命、威胁指示物、反派所在地高亮）。
##
## 新增地图：加 data/locations.json 条目 + 卡图即可；若新卡槽位布局不同，
## 在本文件 SLOT_TEMPLATES 中按格数追加模板（比例相对卡片左上角）。

const LOC_CARD_SIZE := 230.0

# 地点槽位位置模板（按格数，比例相对卡片左上角）。
# 校准方式：对 assets/cards/locations/*.png 上部的白色圆角方块做多阈值连通域检测
# （x 中心相差 <2% 卡宽的元件先合并成一列，再要求列数 == 该地点 slots、且同一行），
# 逐卡取检测值后按格数取中位数：
#   2格 n=2（milano / odins_vault）；3格 n=9；4格 n=16；5格 n=7。
# 未命中的地点（avengers_mansion / central_park / helicarrier / quantum_tunnel /
# royal_palace / shuris_lab / stark_lab / throne_room / valhalla / warrior_falls）
# 沿用同格数模板；其中 shuris_lab 卡面槽位列整体右移约 0.05，与该模板偏差最大。
const SLOT_TEMPLATES := {
	2: {"y": 0.192, "x": [0.420, 0.570]},
	3: {"y": 0.198, "x": [0.353, 0.500, 0.646]},
	4: {"y": 0.198, "x": [0.276, 0.425, 0.575, 0.724]},
	5: {"y": 0.197, "x": [0.201, 0.350, 0.499, 0.648, 0.794]},
}

# 威胁卡下半部分英勇槽的兜底位置（比例，相对威胁卡左上角）。
# 取 ThreatSlots.TABLE 全部 62 张非爪牙威胁卡逐卡坐标的中位数；逐卡精确值见 ThreatSlots.gd。
const THREAT_HEROIC_SLOTS := {"xs": [0.192, 0.504, 0.815], "y": 0.815}

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
var _last_threat_pos := Vector2.ZERO    # 危机指示物锚点：上一次威胁卡的位置/尺寸（威胁卡被化解后位置不变）
var _last_threat_size := Vector2.ZERO
var threat_slot: ColorRect
var threat_marker: TextureRect
var heroic_slots: Array = []
var _endangered_icon: TextureRect   # 濒危地点：守卫指示物（地点左上角）
var _threat_key: String = ""        # 当前威胁卡在 ThreatSlots.TABLE 中的键 "<vid>/<两位序号>"

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
	# 被摧毁地点（章鱼博士）：整卡压暗、隐藏全部指示物/威胁/槽位，仅保留名称
	if l.get("destroyed", false):
		card.modulate = Color(0.22, 0.22, 0.22)
		name_label.text = "💀 %s（已摧毁）" % DB.location_name(l["id"])
		name_label.add_theme_color_override("font_color", Color(0.75, 0.6, 0.6))
		for s in slots:
			s["icon"].visible = false
			s["empty"].visible = false
		for sr in heroic_slots:
			sr.visible = false
		threat.visible = false
		threat_label.visible = false
		threat_hp_icon.visible = false
		threat_marker.visible = false
		crisis_icon.visible = false
		crisis_label.visible = false
		_endangered_icon.visible = false
		return
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
		# 背面朝上（神秘客）：显示威胁卡背面，不显示生命/英勇槽，需花费任意行动翻开
		var face_down: bool = t.get("_face_down", false)
		var img: Texture2D = load("res://assets/cards/villains/%s/threat_back.png" % state["villain"]) if face_down else load(_threat_image_path(state, t))
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
		if face_down:
			# 背面朝上：生命值与英勇槽都不显示
			threat_label.visible = false
			threat_hp_icon.visible = false
			_threat_key = ""
			for sr in heroic_slots:
				sr.visible = false
		else:
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
			# 非爪牙威胁卡：下半部分 3 个英勇槽（卡面印刷的符号贴纸）+ 英勇指示物进度
			_threat_key = "%s/%02d" % [state["villain"], _threat_index(state, t) + 1]
			_update_threat_heroic_slots(t)
	else:
		_threat_key = ""
		threat.visible = false
		threat_label.visible = false
		threat_hp_icon.visible = false
	# 左下角威胁指示物：有威胁卡时显示，清除威胁后隐藏
	threat_marker.visible = l["threat"] != null
	# 危机指示物定位：固定在**威胁卡右侧**（图标左缘 = 威胁卡右缘 +6，纵向对齐威胁卡中线，数量标签在其下方）。
	# 威胁卡被化解/移走后**位置保持不变**（沿用上一次威胁卡的几何），不再跳回卡片中间。
	if crisis_icon.visible:
		if threat.visible:
			_last_threat_pos = threat.position
			_last_threat_size = threat.custom_minimum_size
		elif _last_threat_size == Vector2.ZERO:
			# 该地点从没渲染过威胁卡：按标准横版威胁卡（1198×853）算一次锚点
			_last_threat_size = Vector2(96.0 * 1198.0 / 853.0, 96.0)
			_last_threat_pos = _pos + Vector2(-_last_threat_size.x / 2.0, LOC_CARD_SIZE / 2.0 - _last_threat_size.y * 0.6)
		var cpos: Vector2 = _last_threat_pos + Vector2(_last_threat_size.x + 6.0, _last_threat_size.y * 0.5 - 13.0)
		crisis_icon.position = cpos
		crisis_label.position = cpos + Vector2(2, 24)
	# 反派所在地高亮
	card.modulate = Color(1.25, 1.05, 1.05) if state["villain_pos"] == i else Color.WHITE

## 非爪牙威胁卡：更新 3 个英勇槽（空槽偏白半透明，已放指示物全亮）
## 坐标优先取 ThreatSlots.TABLE 中该卡的逐卡值（key = "<vid>/<两位序号>"，与卡图序号一致），
## 查不到时回退到 THREAT_HEROIC_SLOTS（所有非爪牙威胁卡的中位数模板）。
## 罗南"符号清除"威胁卡：clear 数组决定每个槽的符号图标（移动/英勇/攻击），按 clear_progress 判断填充。
func _update_threat_heroic_slots(t: Dictionary) -> void:
	var tw: float = threat.custom_minimum_size.x
	var th: float = threat.custom_minimum_size.y
	var coords: Dictionary = ThreatSlots.TABLE.get(_threat_key, THREAT_HEROIC_SLOTS)
	var xs: Array = coords["xs"]
	var sy: float = coords["y"]
	# 指示物尺寸：接近槽间距（横版卡 38px、竖版卡 27px）
	var size: float = 38.0 if tw > 100.0 else 27.0
	if t.has("clear"):
		var clear: Array = t["clear"]
		var filled: Array = t.get("clear_progress", [])
		var sym_icons := {
			"move": load("res://assets/tokens/token_move.png"),
			"attack": load("res://assets/tokens/token_attack.png"),
			"heroic": load("res://assets/tokens/token_heroic.png"),
		}
		# 统计各符号已填次数
		var filled_count := {}
		for sym in filled:
			filled_count[sym] = int(filled_count.get(sym, 0)) + 1
		# 当前槽之前该符号已出现的次数（决定该槽是否已填）
		var seen := {}
		for si in range(3):
			var sr: TextureRect = heroic_slots[si]
			if t["hp"] > 0:
				sr.visible = false
				continue
			sr.visible = true
			sr.custom_minimum_size = Vector2(size, size)
			sr.position = Vector2(float(xs[si]) * tw - size / 2.0, sy * th - size / 2.0)
			if si < clear.size():
				var need_sym: String = clear[si]
				sr.texture = sym_icons.get(need_sym, _icon_heroic)
				var filled_before: int = int(seen.get(need_sym, 0))
				var filled_total: int = int(filled_count.get(need_sym, 0))
				# 该槽已填：在它之前的同符号槽都已填完，且总填入数 > 之前已计数
				sr.modulate = Color(1, 1, 1, 1.0) if filled_total > filled_before else Color(1, 1, 1, 0.3)
				seen[need_sym] = filled_before + 1
			else:
				sr.modulate = Color(1, 1, 1, 0.25)  # 无符号位置：弱显示
		return
	var tokens: int = int(t.get("heroic_tokens", 0))
	for si in range(3):
		var sr: TextureRect = heroic_slots[si]
		if t["hp"] > 0:
			sr.visible = false
			continue
		sr.texture = _icon_heroic
		sr.visible = true
		sr.custom_minimum_size = Vector2(size, size)
		sr.position = Vector2(float(xs[si]) * tw - size / 2.0, sy * th - size / 2.0)
		sr.modulate = Color(1, 1, 1, 1.0) if si < tokens else Color(1, 1, 1, 0.3)

## 本张威胁卡在 villains.json threats 数组中的序号（与 _threat_image_path 的取图口径一致）
## 优先用发牌时记录的原始序号 _tidx：神秘客有两张同名卡（破碎幻像/镜花水月/战斗无人机），
## 按名字查找会把它们全部指向同名第一张 → 显示错误的正面图与槽位坐标。
func _threat_index(state: Dictionary, t: Dictionary) -> int:
	if t.has("_tidx"):
		return int(t["_tidx"])
	var vid: String = state["villain"]
	var threats: Array = DB.villain(vid)["threats"]
	for i in range(threats.size()):
		if threats[i]["name"] == t["name"]:
			return i
	return 0

func _threat_image_path(state: Dictionary, t: Dictionary) -> String:
	return "res://assets/cards/villains/%s/threat_%02d.png" % [state["villain"], _threat_index(state, t) + 1]
