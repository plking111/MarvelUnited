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

## 需要选择一张故事情节中的卡牌
signal prompt_story_card(callback: Callable, title: String)

## 需要从牌库选择一张牌
signal prompt_deck_card(callback: Callable, title: String, hero_id: String)

## 显示一张反派行动牌（主计划牌）并要求确认（黑寡妇审讯用）
signal prompt_villain_card(callback: Callable, title: String, card_idx: int)

## 需要选择地点
signal prompt_location(callback: Callable, title: String, filter: Callable)

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
