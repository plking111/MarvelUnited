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
	return b

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
