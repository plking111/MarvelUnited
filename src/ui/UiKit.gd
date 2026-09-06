class_name UiKit
## 共享 UI 工厂：所有界面模块统一从这里创建标签/按钮/面板样式，保证视觉一致。
## 新增通用控件样式时改这里，全局生效。

static func label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, 44)
	b.add_theme_font_size_override("font_size", 19)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	b.add_theme_stylebox_override("normal", sb)
	attach_jelly(b)
	return b

## 带黑色描边的按钮（菜单/导航用；已含白色文字与黑描边字）
static func button_bordered(text: String, color: Color) -> Button:
	var b := button(text, color)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	b.add_theme_constant_override("outline_size", 3)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		if state == "hover":
			sb.bg_color = color.lightened(0.12)
		elif state == "pressed":
			sb.bg_color = color.darkened(0.2)
		elif state == "disabled":
			sb.bg_color = Color(0.3, 0.3, 0.35)
		sb.border_color = Color(0, 0, 0, 0.95)
		sb.set_border_width_all(3)
		sb.corner_radius_top_left = 8
		sb.corner_radius_top_right = 8
		sb.corner_radius_bottom_left = 8
		sb.corner_radius_bottom_right = 8
		b.add_theme_stylebox_override(state, sb)
	return b

## 用图片作背景的按钮（自动叠加文字）。img_path 为透明 PNG。
## 图片为满幅横幅样式；本类按钮无九宫格（texture_margin=0），整图等比缩放，
## 避免中心区图案被九宫格不对称拉伸产生畸变。
## 文字用嵌入的卡通字体（方正舒体）+ 加粗黑描边，做卡通感。
static func image_button(text: String, img_path: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 34)
	# 卡通字体（方正舒体，已嵌入工程）；找不到则用默认系统字体
	var cf: Font = load("res://assets/fonts/FZShuTXSJF.ttf")
	if cf != null:
		b.add_theme_font_override("font", cf)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	b.add_theme_constant_override("outline_size", 8)
	var tex: Texture2D = load(img_path)
	if tex != null:
		var mk := func(mod: Color) -> StyleBoxTexture:
			var sb := StyleBoxTexture.new()
			sb.texture = tex
			# 无九宫格：整图等比重放，图案不畸变
			sb.texture_margin_left = 0
			sb.texture_margin_right = 0
			sb.texture_margin_top = 0
			sb.texture_margin_bottom = 0
			# 左内边距把文字整体右移，更靠按钮图案中央偏右
			sb.content_margin_left = 40
			sb.content_margin_right = 0
			sb.content_margin_top = 0
			sb.content_margin_bottom = 0
			sb.modulate_color = mod
			return sb
		b.add_theme_stylebox_override("normal", mk.call(Color(1, 1, 1, 1)))
		b.add_theme_stylebox_override("hover", mk.call(Color(1.15, 1.15, 1.15, 1)))
		b.add_theme_stylebox_override("pressed", mk.call(Color(0.85, 0.85, 0.85, 1)))
		b.add_theme_stylebox_override("disabled", mk.call(Color(0.55, 0.55, 0.55, 1)))
	attach_jelly(b)
	return b

## 载入入场动画：让一个按钮从下方往上滑入到目标位置（快），带轻微依次延迟。
## offset 为从下方抬升的像素；delay 为相对该按钮开始前等待的秒数。
static func slide_in(btn: Control, offset: float, delay: float = 0.0, dur: float = 0.28) -> void:
	var target := btn.position
	btn.position = Vector2(target.x, target.y + offset)
	var tw := btn.create_tween()
	tw.set_trans(Tween.TRANS_BACK)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "position", target, dur).set_delay(delay)
	btn.set_meta("slide_tween", tw)

## 场景缓存：同一场景只从磁盘 load 一次，之后 change_scene_to_packed 只实例化，
## 避免 change_scene_to_file 每次切换都同步重载场景文件导致的卡顿。
static var _scene_cache: Dictionary = {}

static func goto_scene(path: String) -> void:
	var packed: PackedScene = _scene_cache.get(path)
	if packed == null:
		packed = load(path)
		_scene_cache[path] = packed
	if packed != null:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.change_scene_to_packed(packed)

## 预加载场景，让首次点击切换到该场景时无需现场读取（可放在 _ready 调用）
static func preload_scene(path: String) -> void:
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path)

## 异步后台预加载棋盘常用资源（load_threaded_* 在子线程解码，不阻塞当前场景进入）。
## 在设置页 _ready 调用，等到进入棋盘时资源已就绪，避免点击"确定"卡顿。
static var _precache_requested: Dictionary = {}
static func precache_async() -> void:
	var paths: Array = []
	paths.append("res://src/ui/Board.tscn")
	var tokens := ["civ_token", "thug_token", "crisis_token", "threat_token",
			"token_move", "token_attack", "token_heroic", "token_wild",
			"mission_rescue", "mission_defeat", "mission_clear", "hp_icon"]
	for t in tokens:
		paths.append("res://assets/tokens/%s.png" % t)
	# 英雄/反派卡背
	for hid in ["cap", "ironman", "cmarvel", "hulk", "widow", "winter", "shuri", "blackpanther", "korg", "valkyrie", "betaray", "thor", "starlord", "rocket", "gamora", "groot", "spiderman", "miles", "gwenspider", "spiderpig"]:
		paths.append(DB.hero_back(hid))
	for vid in ["redskull", "ultron", "taskmaster", "thanos", "proxima", "cull", "ebony", "kilmonger", "loki", "ronan", "goblin"]:
		paths.append(DB.villain(vid)["back"])
	for p in paths:
		if _precache_requested.has(p):
			continue
		_precache_requested[p] = true
		if ResourceLoader.exists(p):
			ResourceLoader.load_threaded_request(p)

## 果冻效果：悬停放大、按下缩小、松开/移出弹性回弹（TRANS_BACK 过冲曲线）
static func attach_jelly(btn: Button) -> void:
	# 幂等：已有果冻说明已连接信号，避免重复连接
	if btn.has_meta("jelly_attached"):
		return
	btn.set_meta("jelly_attached", true)
	# 缩放以按钮中心为基准
	var hovering := false
	btn.mouse_entered.connect(func() -> void:
		hovering = true
		_animate(btn, 1.06, 0.22))
	btn.mouse_exited.connect(func() -> void:
		hovering = false
		if not btn.is_pressed():
			_animate(btn, 1.0, 0.22))
	btn.button_down.connect(func() -> void:
		_animate(btn, 0.94, 0.18))
	btn.button_up.connect(func() -> void:
		_animate(btn, 1.06 if hovering else 1.0, 0.24))

static func _animate(btn: Button, target: float, dur: float) -> void:
	# 停掉上一次动画（存在 meta 中），避免连点抖动
	var tw: Tween = null
	if btn.has_meta("jelly_tween"):
		var old: Tween = btn.get_meta("jelly_tween")
		if old != null and old.is_valid():
			old.kill()
	# 以中心为锚缩放：pivot_offset 需在尺寸确定后设置
	if btn.pivot_offset == Vector2.ZERO:
		btn.pivot_offset = btn.size / 2.0
		btn.resized.connect(func(): btn.pivot_offset = btn.size / 2.0)
	tw = btn.create_tween()
	tw.set_trans(Tween.TRANS_BACK)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "scale", Vector2(target, target), dur)
	btn.set_meta("jelly_tween", tw)

static func panel_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	return sb

## 带边框的方框样式（用于区域背景）
static func box_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	return sb

## 英雄卡图片路径
static func hero_card_image(hid: String, idx: int) -> String:
	return "res://assets/cards/heroes/%s/card_%02d.png" % [hid, idx + 1]

## 反派行动牌图片路径
static func villain_action_image(vid: String, idx: int) -> String:
	return "res://assets/cards/villains/%s/action_%02d.png" % [vid, idx + 1]
