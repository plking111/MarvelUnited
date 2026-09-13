extends Node
## 审计工具：把原始拼版图里 12 张摩多克行动卡的「移动/BAM 区」和「指示物区」裁出来拼成联络表，
## 方便人眼逐张核对移动数、BAM、以及每个白框里的指示物种类与数量。
## 纯图像运算，headless 也能跑（不需要显示服务器）。
const SRC := "F:/桌游相关/漫威联合/电子游戏/素材和相关信息/反派/7.4康/康行动卡.png"
const OUT_DIR := "F:/桌游相关/漫威联合/电子游戏/devtools"

func _ready() -> void:
	var src: Image = Image.load_from_file(SRC)
	if src == null:
		print("!! 载入失败：%s" % SRC)
		get_tree().quit(1)
		return
	print("拼版尺寸 = %dx%d" % [src.get_width(), src.get_height()])
	var cw: int = int(src.get_width() / 6)
	var ch: int = int(src.get_height() / 2)
	print("单卡尺寸推定 = %dx%d" % [cw, ch])

	# ① 移动/BAM 区：卡内右上（箭头数字 + BAM 图），分两张（1-6、7-12）各 3 列 × 2 行
	_sheet(src, "shot_kang_movebam_A.png", cw, ch, 380, 60, cw, 760, 3, range(0, 6))
	_sheet(src, "shot_kang_movebam_B.png", cw, ch, 380, 60, cw, 760, 3, range(6, 12))
	# ② 指示物/文本框区：卡内下半，分两张（1-6、7-12），各 2 列 × 3 行 → 分辨率足够看清指示物种类
	_sheet(src, "shot_kang_tokens_A.png", cw, ch, 0, 760, cw, ch, 2, range(0, 6))
	_sheet(src, "shot_kang_tokens_B.png", cw, ch, 0, 760, cw, ch, 2, range(6, 12))
	# ③ 威胁卡拼版 → 只裁文本带（去掉周边美术），2 列 × 3 行，保证文字可读
	var tsrc: Image = Image.load_from_file("F:/桌游相关/漫威联合/电子游戏/素材和相关信息/反派/7.4康/康威胁卡.png")
	if tsrc != null:
		print("威胁卡拼版 = %dx%d" % [tsrc.get_width(), tsrc.get_height()])
		var cols_t: int = 3
		var rows_t: int = 2
		var cw1: float = float(tsrc.get_width()) / 3.0 / (float(tsrc.get_height()) / 2.0)
		if absf(cw1 - 1.404) > absf(float(tsrc.get_width()) / 2.0 / (float(tsrc.get_height()) / 3.0) - 1.404):
			cols_t = 2
			rows_t = 3
		var tw: int = int(tsrc.get_width() / cols_t)
		var th: int = int(tsrc.get_height() / rows_t)
		print("威胁卡单卡推定 = %dx%d（网格 %d 列 × %d 行）" % [tw, th, cols_t, rows_t])
		var tx: int = int(tw * 0.06)
		var ty: int = int(th * 0.20)
		_sheet(tsrc, "shot_kang_threats_sheet.png", tw, th, tx, ty, int(tw * 0.94), int(th * 0.80), 2, range(0, 6), 2)
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
