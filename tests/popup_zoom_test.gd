extends Node
## 弹窗内英雄牌"鼠标悬停放大"验证：
## ① 英雄牌（含英雄卡背）悬停 → 放大图出现，尺寸按卡面比例（高 620）
## ② 非英雄牌图片（暴徒指示物/威胁卡/地点缩略）不放大
## ③ 跟随鼠标 + 贴边自动翻转，且永不超出 1920×1080
## ④ 自愈：宿主隐藏/鼠标离开宿主（例如点了卡片使弹窗关闭）→ 立刻收起，不留残影
## ⑤ 放大图 mouse_filter=IGNORE（不能挡住点击）；层号高于弹窗自身

var _fail := 0

func _check(n: String, ok: bool, d: String = "") -> void:
	if ok:
		print("PASS: " + n)
	else:
		_fail += 1
		print("FAIL: " + n + " — " + d)

func _ready() -> void:
	var popup: CanvasLayer = load("res://src/ui/PopupLayer.gd").new()
	add_child(popup)

	# 容器默认 mouse_filter（0=STOP 1=PASS 2=IGNORE）：决定"整行悬停"能不能收到鼠标
	print("默认 mouse_filter: PanelContainer=%d MarginContainer=%d VBox=%d HBox=%d Label=%d"
		% [PanelContainer.new().mouse_filter, MarginContainer.new().mouse_filter,
			VBoxContainer.new().mouse_filter, HBoxContainer.new().mouse_filter, Label.new().mouse_filter])

	_check("放大图层号高于弹窗自身（保证盖在弹窗之上）",
		int(popup._zoom_layer.layer) > int(popup.layer),
		"zoom=%d popup=%d" % [int(popup._zoom_layer.layer), int(popup.layer)])
	_check("放大图 mouse_filter=IGNORE（不挡点击）",
		popup._zoom_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "")
	_check("初始不可见", not popup._zoom_panel.visible, "")

	# ① 英雄牌行：整行悬停即放大（不用精确指到 60px 小图）
	var hero_card := UiKit.hero_card_image("wasp", 3)
	var row: Control = popup._make_action_row({"img": hero_card, "text": "能量投射", "hide_text": true}, 0)
	row.mouse_entered.emit()
	_check("① 英雄牌行悬停 → 放大图显示", popup._zoom_panel.visible and popup._zoom_panel.texture != null, "")
	var zs: Vector2 = popup._zoom_panel.size
	_check("① 放大尺寸按卡面比例、高 620",
		absf(zs.y - popup.ZOOM_MAX_H) < 1.0 and absf(zs.x / zs.y - 853.0 / 1198.0) < 0.01,
		"size=%s 期望高 620、宽高比 0.712" % str(zs))
	row.mouse_exited.emit()
	_check("① 鼠标移出 → 放大图收起", not popup._zoom_panel.visible and popup._zoom_panel.texture == null, "")

	# ①b 英雄卡背（英雄选择弹窗用的就是卡背）同样支持
	var row_back: Control = popup._make_action_row({"img": DB.hero_back("okoye"), "text": "okoye", "hide_text": true}, 1)
	row_back.mouse_entered.emit()
	_check("①b 英雄卡背悬停 → 放大图显示", popup._zoom_panel.visible and popup._zoom_panel.texture != null, "")
	row_back.mouse_exited.emit()

	# ② 非英雄牌不放大
	var row_thug: Control = popup._make_action_row({"img": "res://assets/tokens/thug_token.png", "text": "暴徒", "hide_text": true}, 2)
	row_thug.mouse_entered.emit()
	_check("② 暴徒指示物行悬停 → 不放大", not popup._zoom_panel.visible, "")
	var row_loc: Control = popup._make_action_row({"icon": "move", "text": "中央公园", "bottom": "res://assets/cards/locations/central_park.png"}, 3)
	row_loc.mouse_entered.emit()
	_check("② 地点缩略图行悬停 → 不放大", not popup._zoom_panel.visible, "")

	# ③④ 用一个普通宿主控件验证跟随/翻转/自愈
	var host := TextureRect.new()
	host.position = Vector2(100, 100)
	host.size = Vector2(80, 110)
	host.custom_minimum_size = Vector2(80, 110)
	popup.add_child(host)
	popup.bind_card_zoom(host, hero_card)
	popup.bind_card_zoom(host, "res://assets/tokens/thug_token.png")   # 非英雄牌：不应重复绑定
	popup._zoom_mouse_override = Vector2(140, 150)   # 落在宿主体内
	host.mouse_entered.emit()
	popup._process(0.0)
	_check("③ 鼠标在宿主体内 → 保持放大", popup._zoom_panel.visible, "")
	_check("③ 放大图跟随鼠标（右下方 +24）", popup._zoom_panel.position == Vector2(164, 174),
		"pos=%s" % str(popup._zoom_panel.position))

	# 贴右下角 → 翻到鼠标左上，且不溢出屏幕
	popup._zoom_mouse_override = Vector2(140, 150)
	popup._update_zoom_position()
	popup._zoom_mouse_override = Vector2(1890, 1070)
	popup._update_zoom_position()
	var p: Vector2 = popup._zoom_panel.position
	_check("③ 贴右下角 → 翻到鼠标左上", p.x < 1890.0 and p.y < 1070.0, "pos=%s" % str(p))
	_check("③ 放大图永不超出屏幕",
		p.x >= 0.0 and p.y >= 0.0 and p.x + zs.x <= 1920.0 and p.y + zs.y <= 1080.0, "pos=%s size=%s" % [str(p), str(zs)])

	# ④ 自愈：鼠标已不在宿主上（点了卡片 → 弹窗关闭，mouse_exited 不一定触发）
	popup._zoom_mouse_override = Vector2(1500, 900)
	popup._process(0.0)
	_check("④ 鼠标离开宿主 → 自动收起（无残影）", not popup._zoom_panel.visible, "")

	# ④b 宿主被隐藏 → 自动收起
	popup._zoom_mouse_override = Vector2(140, 150)
	host.mouse_entered.emit()
	popup._process(0.0)
	_check("④b 宿主可见时保持放大", popup._zoom_panel.visible, "")
	host.visible = false
	popup._process(0.0)
	_check("④b 宿主被隐藏 → 自动收起", not popup._zoom_panel.visible, "")
	host.visible = true

	if _fail == 0:
		print("=== POPUP ZOOM TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		print("=== POPUP ZOOM TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)
