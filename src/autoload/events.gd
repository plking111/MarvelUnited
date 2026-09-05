extends Node
## Events: 全局信号总线。UI 监听这些信号刷新显示。

## 状态整体变化（任何重要修改后广播，UI 全量刷新）
signal state_changed

## 新日志行
signal log_line(text: String, color: Color)

## 需要玩家选择（弹出选择框）
signal prompt_choice(options: Array, title: String, callback: Callable)

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

## 显示一张反派行动牌（主计划牌）并要求确认（黑寡妇审讯用）
signal prompt_villain_card(callback: Callable, title: String, card_idx: int)

## 需要选择地点
signal prompt_location(callback: Callable, title: String, filter: Callable)

## 需要从可选英雄池中选择一个（灭霸淘汰替换英雄用）：弹出搜索/筛选面板
signal prompt_hero_pick(callback: Callable, title: String, options: Array)

## 游戏结束
signal game_over(victory: bool, reason: String)

## 切换场景
signal change_scene(scene_path: String)

## 需要选择地点中的指示物（民/暴）移动
signal prompt_move_tokens(callback: Callable, title: String)

func emit_log(text: String, color: Color = Color.WHITE) -> void:
	log_line.emit(text, color)

func emit_toast(text: String) -> void:
	toast.emit(text)

func emit_state_changed() -> void:
	state_changed.emit()
