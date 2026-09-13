class_name MissionView
extends Control
## 任务视图模块：一张任务卡（卡图 + 指示物格子 + 进度标签）。
##
## 新增任务类型：加 data/missions.json 条目 + 卡图即可；
## 若新卡图的指示物槽位布局不同，在本文件 MISSION_SLOTS 中按任务 id 追加。

# 任务卡图上的槽位格中心（比例，相对卡图左上角；由任务卡原图亮度分析+连通域分析得出）
# 营救/击败：3x3 共 9 格；清除：2x2 共 4 格（2026 重新校准：脚本分析 mission_*.png 卡面）
const MISSION_SLOTS := {
	"rescue": {"xs": [0.217, 0.500, 0.782], "ys": [0.344, 0.555, 0.761]},
	"defeat": {"xs": [0.219, 0.501, 0.782], "ys": [0.353, 0.561, 0.769]},
	"clear": {"xs": [0.326, 0.674], "ys": [0.430, 0.667]},
}

var _holder: Control
var _img: TextureRect
var _icon_tex: Texture2D
var _slot_l: Label

func setup(m: Dictionary, mission_textures: Dictionary, icon_tex: Texture2D) -> void:
	# 任务视图是普通 Control：必须显式设置最小尺寸，
	# 否则对 HBoxContainer 宽度为 0，三张任务卡会重叠在同一位置
	custom_minimum_size = Vector2(100, 166)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	_holder = Control.new()
	_holder.custom_minimum_size = Vector2(100, 140)
	v.add_child(_holder)
	_img = TextureRect.new()
	_img.custom_minimum_size = Vector2(100, 140)
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_img.texture = load(m["img"]) if m.get("img", "") != "" else mission_textures.get(m["id"])
	_holder.add_child(_img)
	_icon_tex = icon_tex
	_slot_l = UiKit.label("", 15, Color(1, 0.9, 0.3))
	_slot_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_slot_l)
	refresh(m)

## 刷新进度指示物与标签（指示物随任务状态增减）
func refresh(m: Dictionary) -> void:
	# 清除旧的指示物（保留卡图）
	for c in _holder.get_children():
		if c != _img:
			_holder.remove_child(c)
			c.queue_free()
	# 槽位模板：任务卡自带 xs/ys（如 B计划专属卡）优先，否则按任务 id 查表
	var tpl: Dictionary = MISSION_SLOTS.get(m["id"], MISSION_SLOTS["clear"])
	if m.has("xs") and m.has("ys"):
		tpl = {"xs": m["xs"], "ys": m["ys"]}
	var xs: Array = tpl["xs"]
	var ys: Array = tpl["ys"]
	var idx := 0
	for row in range(ys.size()):
		for col in range(xs.size()):
			var ic := TextureRect.new()
			ic.custom_minimum_size = Vector2(20, 20)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.texture = _icon_tex
			ic.position = Vector2(float(xs[col]) * 100.0 - 10.0, float(ys[row]) * 140.0 - 10.0)
			ic.modulate = Color(1, 1, 1, 1.0) if idx < int(m["tokens"]) else Color(1, 1, 1, 0.15)
			_holder.add_child(ic)
			idx += 1
	if m.get("done", false):
		_slot_l.text = "✅ 已完成"
		_slot_l.add_theme_color_override("font_color", Color(0.5, 1, 0.5))
	else:
		_slot_l.text = "%d / %d" % [m["tokens"], m["slots"]]
		_slot_l.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
