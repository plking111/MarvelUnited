extends Node
## 审计工具：把已切好的 6 张摩多克威胁卡拼成一张联络表（2 列 × 3 行，原始分辨率），
## 用来逐张核对名称/生命值/英勇槽/到达效果/开始回合效果/BAM 文本与数据是否一致。
const DIR := "F:/桌游相关/漫威联合/电子游戏/MarvelUnitedGame/assets/cards/villains/modok"
const OUT := "F:/桌游相关/漫威联合/电子游戏/devtools/shot_modok_threats_full.png"

func _ready() -> void:
	var imgs: Array = []
	for i in range(1, 7):
		var p := "%s/threat_%02d.png" % [DIR, i]
		var im: Image = Image.load_from_file(p)
		if im == null:
			print("!! 载入失败 %s" % p)
			get_tree().quit(1)
			return
		imgs.append(im)
		print("  threat_%02d = %dx%d" % [i, im.get_width(), im.get_height()])
	var w: int = (imgs[0] as Image).get_width()
	var h: int = (imgs[0] as Image).get_height()
	var dst := Image.create(w * 2, h * 3, false, (imgs[0] as Image).get_format())
	for n in range(6):
		var c: int = n % 2
		var r: int = int(n / 2)
		dst.blit_rect((imgs[n] as Image), Rect2i(0, 0, w, h), Vector2i(w * c, h * r))
		for x in range(w * c, w * c + w):
			dst.set_pixel(x, h * r, Color(1, 0, 1))
	var err: int = dst.save_png(OUT)
	print("已保存 shot_modok_threats_full.png 尺寸=%dx%d 布局=2 列 × 3 行 顺序=威胁1..6（行优先） err=%d" % [dst.get_width(), dst.get_height(), err])
	get_tree().quit(0)
