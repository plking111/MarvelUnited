extends Node
## 审计工具（犀牛人 Rhino）：把原始拼版图里 12 张行动卡的「移动数字/BAM 区」和「指示物放置区」裁出来拼成
## 放大联络表，方便人眼逐张核对移动步数、BAM! 有无、以及每个白框里的指示物种类与数量；
## 威胁卡只裁「卡名条 + 文本带 + 英勇槽」，保证文字与槽位可读。
## 纯图像运算，headless 也能跑（不需要显示服务器）。
##
## ⚠️ 已知坑：_sheet() 必须显式传"源拼版的网格列数"（行动卡 6 列 × 2 行、威胁卡 2 列 × 3 行），
##    否则按 i % 6 去取威胁卡会读到图外、拼出白图。
const SRC_DIR := "F:/桌游相关/漫威联合/电子游戏/素材和相关信息/反派/7.5犀牛人"
const ACTION_SHEET := SRC_DIR + "/犀牛人行动卡.png"
const THREAT_SHEET := SRC_DIR + "/犀牛人威胁卡.png"
const OUT_DIR := "F:/桌游相关/漫威联合/电子游戏/devtools"

func _ready() -> void:
	var src: Image = Image.load_from_file(ACTION_SHEET)
	if src == null:
		print("!! 载入失败：%s" % ACTION_SHEET)
		get_tree().quit(1)
		return
	print("行动卡拼版尺寸 = %dx%d" % [src.get_width(), src.get_height()])
	var cw: int = int(src.get_width() / 6)
	var ch: int = int(src.get_height() / 2)
	print("行动卡单卡推定 = %dx%d（网格 6 列 × 2 行，行优先 = action_01..12）" % [cw, ch])
	# ① 移动数字 + BAM! 区：卡内右上（顺时针箭头数字 + BAM 星爆），分两批各 6 张、3 列 × 2 行
	_sheet(src, "shot_rhino_movebam_A.png", cw, ch, 440, 230, 830, 790, 3, range(0, 6), 6)
	_sheet(src, "shot_rhino_movebam_B.png", cw, ch, 440, 230, 830, 790, 3, range(6, 12), 6)
	_sheet(src, "shot_rhino_movebam_sheet.png", cw, ch, 440, 230, 830, 790, 4, range(0, 12), 6)
	# ② 指示物放置区：卡内下半（三个白框），分两批各 6 张、2 列 × 3 行 → 分辨率足够看清种类
	_sheet(src, "shot_rhino_tokens_A.png", cw, ch, 0, 760, cw, ch, 2, range(0, 6), 6)
	_sheet(src, "shot_rhino_tokens_B.png", cw, ch, 0, 760, cw, ch, 2, range(6, 12), 6)
	_sheet(src, "shot_rhino_tokens_sheet.png", cw, ch, 0, 760, cw, ch, 3, range(0, 12), 6)
	# ③ 威胁卡拼版（2 列 × 3 行）→ 卡名条 + 文本带 + 英勇槽
	var tsrc: Image = Image.load_from_file(THREAT_SHEET)
	if tsrc != null:
		print("威胁卡拼版尺寸 = %dx%d" % [tsrc.get_width(), tsrc.get_height()])
		var cols_t: int = 2
		var rows_t: int = 3
		var tw: int = int(tsrc.get_width() / cols_t)
		var th: int = int(tsrc.get_height() / rows_t)
		print("威胁卡单卡推定 = %dx%d（网格 %d 列 × %d 行，行优先 = threat_01..06）" % [tw, th, cols_t, rows_t])
		_sheet(tsrc, "shot_rhino_threats_sheet.png", tw, th, 0, 40, tw, th, 2, range(0, 6), 2)
	else:
		print("!! 威胁卡拼版载入失败：%s" % THREAT_SHEET)
	get_tree().quit(0)

func _sheet(src: Image, out_name: String, cw: int, ch: int, sx: int, sy: int, ex: int, ey: int, cols: int, idxs: Array, src_cols: int = 6) -> void:
	var w: int = ex - sx
	var h: int = ey - sy
	var rows: int = int(ceil(float(idxs.size()) / float(cols)))
	var dst := Image.create(w * cols, h * rows, false, src.get_format())
	for n in range(idxs.size()):
		var i: int = int(idxs[n])
		var r: int = int(n / cols)
		var c: int = n % cols
		var card_x: int = cw * (i % src_cols)
		var card_y: int = ch * int(i / src_cols)
		var rect := Rect2i(card_x + sx, card_y + sy, w, h)
		var crop: Image = src.get_region(rect)
		if crop == null:
			print("!! 卡 %d 裁剪失败 %s" % [i + 1, str(rect)])
			continue
		dst.blit_rect(crop, Rect2i(0, 0, w, h), Vector2i(w * c, h * r))
		for x in range(w * c, w * c + w):
			dst.set_pixel(x, h * r, Color(1, 0, 1))
	var path: String = "%s/%s" % [OUT_DIR, out_name]
	var err: int = dst.save_png(path)
	print("已保存 %s  尺寸=%dx%d  布局=%d 列 × %d 行  卡片顺序=%s  err=%d" % [out_name, dst.get_width(), dst.get_height(), cols, rows, str(idxs), err])
