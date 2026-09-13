extends Node
## Events: 全局信号总线。UI 监听这些信号刷新显示。

## 状态整体变化（任何重要修改后广播，UI 全量刷新）
signal state_changed

## 新日志行
signal log_line(text: String, color: Color)

## 需要玩家选择（弹出选择框）
signal prompt_choice(options: Array, title: String, callback: Callable)

## 行动图形化选择（移动/攻击/英勇等）：rows 每项 {icon, arrow, text, img, ...}，PopupLayer 渲染图标+箭头+目标
signal prompt_action(rows: Array, title: String, callback: Callable)

## 需要玩家输入数字/确认
signal prompt_confirm(text: String, callback: Callable)

## 提示信息（短暂 toast）
signal toast(text: String)

## 需要选择手牌（可多选 count 张）
signal prompt_hand_card(callback: Callable, title: String, hero_id: String, count: int)

## 需要选择一张故事情节中的卡牌；filter_hero 非空时只显示该英雄的行动牌（如斯塔克实验室交换）
signal prompt_story_card(callback: Callable, title: String, filter_hero: String)

## 需要从牌库选择一张牌
signal prompt_deck_card(callback: Callable, title: String, hero_id: String)

## 完成一个任务时触发（用于弹出"任务完成"提示）；count 为第几个任务(1-3)，hero_id 为完成该任务的英雄
signal mission_completed(count: int, hero_id: String)

## 反派出牌展示用
signal prompt_villain_card(callback: Callable, title: String, card_idx: int)

## 联机：弹窗是否只读（不是本人在操作 → 只展示、点不动）
signal popup_readonly_changed(readonly: bool)

## 需要选择地点
signal prompt_location(callback: Callable, title: String, filter: Callable)

## 需要从可选英雄池中选择一个（灭霸淘汰替换英雄用）：弹出搜索/筛选面板
signal prompt_hero_pick(callback: Callable, title: String, options: Array)

## 需要拖拽调整顺序（术士亚当·量子魔法看牌堆顶 3 张）：
## cards = 反派行动卡索引数组（顺序 = 当前"牌堆顶 → 往下"的顺序），villain = 反派 id，
## callback 收到新顺序（Array[int]）。联机时只有"该答的玩家"能拖（readonly 时拖不动）。
signal prompt_reorder(cards: Array, villain: String, title: String, callback: Callable)

## 游戏结束
signal game_over(victory: bool, reason: String)

## 切换场景
signal change_scene(scene_path: String)

## 需要选择地点中的指示物（民/暴）移动
signal prompt_move_tokens(callback: Callable, title: String)

## 叛徒模式：某玩家已秘密查看并确认自己的身份牌（热座逐个发放用）
signal identity_confirmed(hero_id: String)

func emit_log(text: String, color: Color = Color.WHITE) -> void:
	log_line.emit(text, color)

func emit_toast(text: String) -> void:
	toast.emit(text)

func emit_state_changed() -> void:
	state_changed.emit()

## ================================================================ 测试兼容桥（结构优化第 4 步）
## 历史背景：早期弹窗只有"纯文字"的 prompt_choice，后来行动类弹窗改成了图形化的
## prompt_action（图标 + 箭头 + 目标）。仓库里有 13 个老测试只连 prompt_choice，于是它们
## 在被测流程改用新弹窗之后"答不上题"→ 要么卡死、要么断言失败，被误当成真 bug。
##
## 这里做一个**只在测试进程生效、且只在"没人接新弹窗"时才补发**的桥：
##   - 正式游戏：Board 的 PopupLayer 会连 prompt_action → 桥不动作（行为完全不变）
##   - 老测试（无 Board、只连 prompt_choice）：把 rows 摊平成纯文字后补发一份 prompt_choice
##   - 新测试（自己连了 prompt_action）：不补发 → 不会出现"两路都接、重复应答"
## 这样那 13 个老测试不用逐个改写就能继续覆盖它们负责的卡牌效果。
func _ready() -> void:
	if not _is_test_run():
		return
	prompt_action.connect(_bridge_action_to_choice)

func _is_test_run() -> bool:
	for a in OS.get_cmdline_args():
		if String(a).begins_with("res://tests/") or String(a).contains("tests/"):
			return true
	return false

func _bridge_action_to_choice(rows: Array, title: String, callback: Callable) -> void:
	# 有人接新弹窗（例如带了 Board 的测试）→ 不补发，避免同一个弹窗被答两次
	if prompt_action.get_connections().size() > 1:
		return
	if prompt_choice.get_connections().size() == 0:
		return
	var opts: Array = []
	for r in rows:
		opts.append(String((r as Dictionary).get("text", "")))
	prompt_choice.emit(opts, title, callback)
