class_name VideoStill
extends Control
## 那 14 秒的偷拍视频。
##
## 全部是程序化绘制，没有一张贴图 —— 因为这里要的恰恰不是"一张漂亮的图"，
## 而是"一段被手机拍下来、又被压过好几手的画面"。这两件事的差别全在细节里：
## 偏斜的取景、四角的暗角、扫描线、飘动的跟踪噪点、压缩噪点、左上角闪的 REC、
## 运动物体边缘那几道糊掉的拖影，以及左下角那个挡住画面的人的后脑。
##
## 它还能"播"。点一下，画面里的人会动、时间码会走、噪点会变粗 —— 四秒钟。
## 这不是装饰：玩家盯着这段画面的时候，是在判断那 14 秒里到底发生了什么，
## 而"能看一点"和"只能看一帧"对判断的影响完全不同。
##
## 画面里只有一个问题：她抬起来的那只手，究竟有没有碰到他。
## 所以构图必须把这件事摆在正中间，又不能给出答案 ——
## 手停在离他的脸还有一小段的地方，剪影没有五官，噪点盖掉了接触的那一帧。
##
## 关于比例：所有人物尺寸都从"身高"推出来，按真人的比例算
## （头高约身高 13%、肩宽约 23%、胯宽约 19%、腿长约 47%）。
## 这几个常数决定剪影读起来是"人"还是"雪人"，比任何贴图都重要。
##
## 关于明暗：画面分三段打底 —— 天花板最暗、后墙居中、地面最亮，
## 因为灯管吊在顶上、光落在近处的地面上。人物用接近纯黑的墨色（亮度约 6/255），
## 地面在人物那一带是 64–86/255，也就是说剪影和背景差着十倍以上。
## 这一条比任何细节都关键：一开始地面只有 27/255、人 8/255，整幅画糊成一团深灰，
## 剪影立不住，读起来就像一张线框占位图。
##
## 关于开销：只在可见且需要动画时才 queue_redraw。案件界面打开时街区已经停渲染了
## （见 case_trigger.gd），这一屏有充足的预算。

## 播放一遍的时长（秒）。比真实的 14 秒快一些 —— 玩家不需要真的等。
const PLAY_SECONDS := 4.0

var playing := false
var _t := 0.0          ## 播放进度 0→1
var _clock := 0.0      ## 一直在走的时钟，驱动噪点与呼吸
var _hovered := false
var _redraw_accum := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(queue_redraw)
	mouse_entered.connect(func() -> void:
		_hovered = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hovered = false
		queue_redraw())
	set_process(true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if playing:
			playing = false
			_t = 0.0
		else:
			playing = true
			_t = 0.0
		queue_redraw()
		accept_event()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += delta
	if playing:
		_t += delta / PLAY_SECONDS
		if _t >= 1.0:
			_t = 1.0
			playing = false
		queue_redraw()
		return
	# 暂停状态不用每帧重画：只有噪点在慢慢挪，20fps 足够，
	# 而 20fps 的重画比 60fps 便宜三分之二。
	_redraw_accum += delta
	if _redraw_accum >= 0.05:
		_redraw_accum = 0.0
		queue_redraw()

# ─────────────────────────────────────────────────────────────
func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 8.0 or h < 8.0:
		return

	# ── 手机取景：整幅画面偏斜一点点，再放大一点点，让四角被切掉。
	# 这是"这不是官方影像"最省力的表达。
	draw_set_transform(Vector2(w * 0.5, h * 0.5), deg_to_rad(-1.15), Vector2(1.10, 1.10))
	var ox := -w * 0.5
	var oy := -h * 0.5

	_station(ox, oy, w, h)
	_figures(ox, oy, w, h)
	_foreground(ox, oy, w, h)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_overlays(w, h)

# ─────────────────────────────────────────────────────────────
#  站台本身
# ─────────────────────────────────────────────────────────────
func _station(x: float, y: float, w: float, h: float) -> void:
	# 分三段打底：天花板 → 后墙 → 地面。每段自己有一段纵向渐变，
	# 接缝处两段的颜色是对得上的，所以看起来是一整片光滑的空间，而不是三条色带。
	#
	# 三段之间的**亮度关系**才是重点：地面最亮，后墙居中，天花板最暗。
	# 灯管吊在顶上，光落在近处的地面上 —— 这个关系比任何细节都更能说明
	# "这是地铁站"。之前那版把地面压得太暗（地面 27、人 8），
	# 整幅画糊成一团深灰，剪影根本立不住，读起来就像线框占位图。
	var ceil_bot := Color(0.030, 0.040, 0.048)
	var wall_top := Color(0.078, 0.094, 0.102)
	var wall_bot := Color(0.186, 0.206, 0.208)
	var floor_bot := Color(0.362, 0.392, 0.382)
	_band(x, y + h * 0.000, w, h * 0.075, Color(0.018, 0.026, 0.032), ceil_bot, 8)
	_band(x, y + h * 0.075, w, h * 0.510, wall_top, wall_bot, 20)
	_band(x, y + h * 0.585, w, h * 0.293, wall_bot, floor_bot, 18)

	# 后墙的瓷砖竖缝 + 墙脚线。两条很轻的线，把墙和地面分开。
	var wall_y := y + h * 0.075
	var wall_h := h * 0.510
	for i in range(13):
		var tx := x + w * (0.015 + 0.081 * float(i))
		draw_line(Vector2(tx, wall_y), Vector2(tx, wall_y + wall_h * 0.94), Color(1, 1, 1, 0.022), 1.0)
	draw_line(Vector2(x, wall_y), Vector2(x + w, wall_y), Color(1, 1, 1, 0.045), 1.0)
	# 踢脚线：墙脚一道暗带。有了它，墙和地面在视觉上才"搭"在一起。
	draw_rect(Rect2(x, y + h * 0.556, w, h * 0.029), Color(0.086, 0.100, 0.106))
	draw_rect(Rect2(x, y + h * 0.556, w, 1.0), Color(1, 1, 1, 0.055))

	# 站名牌。远处一块亮着的小方牌，是画面里唯一交代"这是哪一站"的东西。
	var sign_w := w * 0.105
	var sign_x := x + w * 0.150
	var sign_y := y + h * 0.148
	draw_rect(Rect2(sign_x, sign_y, sign_w, h * 0.098), Color(0.052, 0.086, 0.098))
	draw_rect(Rect2(sign_x, sign_y, sign_w, h * 0.098), Color(0.45, 0.70, 0.76, 0.26))
	draw_rect(Rect2(sign_x + sign_w * 0.15, sign_y + h * 0.033, sign_w * 0.31, h * 0.026),
		Color(0.72, 0.92, 0.96, 0.55))
	draw_rect(Rect2(sign_x + sign_w * 0.53, sign_y + h * 0.033, sign_w * 0.28, h * 0.026),
		Color(0.72, 0.92, 0.96, 0.34))

	# 两根日光灯管 + 它们的晕。全场唯一的冷白光源，亮到过曝才对。
	for i in range(2):
		var lx := x + w * (0.112 + 0.455 * float(i))
		var ly := y + h * 0.078
		var lw := w * 0.185
		for k in range(9):
			var grow := float(k) * 3.4
			draw_rect(Rect2(lx - grow, ly - grow * 0.38, lw + grow * 2.0, 2.0 + grow * 0.80),
				Color(0.62, 0.79, 0.89, 0.075 * (1.0 - float(k) / 9.0)))
		draw_rect(Rect2(lx, ly, lw, 2.0), Color(0.96, 0.99, 1.00, 0.94))

	# 灯管在地面上的倒影。两道光斑，很弱，但把"地面是湿的"说清楚了。
	for i in range(2):
		var rx := x + w * (0.112 + 0.455 * float(i)) + w * 0.0925
		for k in range(11):
			var t := float(k) / 10.0
			draw_rect(Rect2(rx - w * 0.085, y + h * (0.615 + 0.212 * t), w * 0.17, h * 0.020),
				Color(0.70, 0.86, 0.94, 0.050 * (1.0 - t)))

	# 站台边缘与黄色安全线。这条线加上下面的轨道，"这里是地铁站"就成立了。
	# 它是画面里最亮的一条横线 —— 现实里它也确实是。
	var line_y := y + h * 0.866
	draw_rect(Rect2(x, line_y, w, h * 0.0080), Color(0.94, 0.78, 0.36, 0.62))
	draw_rect(Rect2(x, line_y + h * 0.0190, w, 1.0), Color(0.94, 0.78, 0.36, 0.20))
	# 站台唇口：一条被灯照亮的白边
	draw_rect(Rect2(x, y + h * 0.878, w, 1.8), Color(0.86, 0.91, 0.92, 0.42))
	# 轨道：画面最底下那一条几乎全黑的东西
	draw_rect(Rect2(x, y + h * 0.886, w, h * 0.114), Color(0.012, 0.017, 0.021))
	draw_rect(Rect2(x, y + h * 0.936, w, 1.2), Color(1, 1, 1, 0.09))

	# 右边缘一根立柱。窄，只在最边上：交代"镜头前面有东西"而不吃掉画面。
	draw_rect(Rect2(x + w * 0.968, y - h * 0.04, w * 0.032, h * 1.08), Color(0.014, 0.019, 0.023))

## 一块纵向渐变。分档而不是逐像素 —— 只要看不出台阶就够了。
## 每档高度多加 1 像素，避免相邻两档之间露出缝。
func _band(x: float, y0: float, w: float, height: float,
		c_top: Color, c_bot: Color, steps: int) -> void:
	for i in range(steps):
		var t := float(i) / float(steps - 1)
		draw_rect(Rect2(x, y0 + height * t, w, height / float(steps) + 1.0),
			c_top.lerp(c_bot, t))

# ─────────────────────────────────────────────────────────────
#  人
# ─────────────────────────────────────────────────────────────
func _figures(x: float, y: float, w: float, h: float) -> void:
	var ink := Color(0.024, 0.031, 0.038)
	var blur := 0.0
	if playing:
		# 播放时才有明显拖影。静止帧上不该有，否则像坏了。
		blur = 4.0
	elif _hovered:
		blur = 1.6   # 悬停时画面"活"一点点，非常轻

	# 播放时的动作编排：年轻女子向长者倾过去，长者轻微后仰。
	# 用一条先快后慢的曲线，免得像机械平移。
	var lean := 0.0
	var swing := 0.0
	var recoil := 0.0
	if _t > 0.0:
		var e := _ease(_t)
		lean = e * w * 0.013
		swing = e * w * 0.030
		recoil = e * w * 0.008

	# 远处候车的乘客。小、淡、没有细节 —— 只用来交代"站台上还有别人"。
	# 比近处的人亮一大截：空气和噪点把远处的对比度吃掉了，这就是"远"。
	# 注意别留太实 —— 一个又黑又窄的竖条会被读成柱子，而不是人。
	_figure(Vector2(x + w * 0.312, y + h * 0.788), h * 0.195, ink.lightened(0.145))

	# 长椅。坐着的长者靠它成立，否则他就是"悬在半空"。
	var bench_top := y + h * 0.742
	var bench := Color(0.078, 0.089, 0.096)
	draw_rect(Rect2(x + w * 0.598, bench_top, w * 0.312, h * 0.021), bench)
	draw_rect(Rect2(x + w * 0.598, bench_top, w * 0.312, 1.0), Color(1, 1, 1, 0.13))
	draw_rect(Rect2(x + w * 0.620, bench_top + h * 0.021, w * 0.012, h * 0.092),
		bench.darkened(0.35))
	draw_rect(Rect2(x + w * 0.876, bench_top + h * 0.021, w * 0.012, h * 0.092),
		bench.darkened(0.35))
	# 长椅落在地面上的一小片影子
	draw_rect(Rect2(x + w * 0.606, y + h * 0.845, w * 0.298, h * 0.014), Color(0, 0, 0, 0.16))

	# 老年乘客：坐姿，面朝左（也就是朝向镜头这一侧）
	_seated(Vector2(x + w * 0.650 + recoil, bench_top), h * 0.415, ink, blur)
	# 他身前斜着一根手杖
	draw_line(Vector2(x + w * 0.596 + recoil, bench_top - h * 0.132),
		Vector2(x + w * 0.556 + recoil, y + h * 0.852), Color(0.070, 0.084, 0.094), 1.8)

	# 年轻女子：站姿，更靠近镜头（所以更大），身体前倾
	var foot := Vector2(x + w * 0.560 + lean, y + h * 0.855)
	var shoulder := _figure(foot, h * 0.440, ink.darkened(0.06), blur, 1.0)

	# 她抬起的手臂。从肩出发，指向长者的头部方向 ——
	# 手掌停在离他的头还有一小段空隙的地方（约画面宽的 1%，缩到界面里大约是 8 像素）。
	# 整段画面最关键的误读点就在这里：这点空隙刚好够"碰到了"和"没碰到"两种读法
	# 都说得通，而剪影没有五官、画面又是低码率，谁也拿不出更多证据。
	var hand := Vector2(x + w * 0.618 + lean + swing, y + h * 0.546)
	var arm := ink.lightened(0.020)
	_limb(shoulder, hand, h * 0.440, arm)
	# 播放时手上拖一道极短的残影：有"动过"，但没有方向。
	if playing and swing > 0.5:
		draw_line(hand - Vector2(w * 0.028, 0), hand, Color(0.15, 0.18, 0.20, 0.30), 2.4)

## 站姿剪影。返回肩膀的位置，好让手臂接得上。
func _figure(foot: Vector2, height: float, color: Color, blur := 0.0, facing := 1.0) -> Vector2:
	# 拖影：同一个人画三遍，每遍偏一点点、更淡一点点。
	if blur > 0.1:
		for k in range(1, 4):
			var off := blur * float(k) * -facing
			_blob(foot + Vector2(off, 0), height, Color(0.15, 0.18, 0.20, 0.24 / float(k)))
	return _blob(foot, height, color)

func _blob(foot: Vector2, height: float, color: Color) -> Vector2:
	# 全部尺寸都由身高推出来，按真人比例：
	# 头半径 ≈ 身高 6.6%（即头高约 13%）、肩半宽 11.5%、胯半宽 9.5%、腿长 45.5%。
	# 之前那版头占了身高的四成，剪影读起来像雪人 —— 差别就在这几个常数上。
	var head_r := height * 0.066
	var head_c := Vector2(foot.x, foot.y - height + head_r)
	var shoulder_y := foot.y - height * 0.815
	var hip_y := foot.y - height * 0.455
	var sw := height * 0.115     # 肩半宽
	var hw := height * 0.095     # 胯半宽

	# 腿
	var leg_w := hw * 0.82
	var leg_top := hip_y - height * 0.015
	draw_rect(Rect2(foot.x - hw * 0.92, leg_top, leg_w, foot.y - leg_top), color)
	draw_rect(Rect2(foot.x + hw * 0.10, leg_top, leg_w, foot.y - leg_top), color)
	# 鞋
	draw_rect(Rect2(foot.x - hw * 1.02, foot.y - height * 0.022, hw * 0.98, height * 0.022), color)
	draw_rect(Rect2(foot.x + hw * 0.04, foot.y - height * 0.022, hw * 0.98, height * 0.022), color)

	# 躯干：肩比胯宽。这一笔决定它读起来是"人"还是"雪人"。
	var torso := PackedVector2Array([
		Vector2(foot.x - sw, shoulder_y),
		Vector2(foot.x + sw, shoulder_y),
		Vector2(foot.x + hw, hip_y + height * 0.010),
		Vector2(foot.x - hw, hip_y + height * 0.010),
	])
	draw_colored_polygon(torso, color)

	# 脖子
	draw_rect(Rect2(head_c.x - head_r * 0.36, head_c.y + head_r * 0.70,
		head_r * 0.72, shoulder_y - head_c.y - head_r * 0.70 + 1.0), color)
	# 头
	draw_circle(head_c, head_r, color)
	# 上缘一道极淡的轮廓光，把剪影从背景里分离出来
	draw_arc(head_c, head_r, PI * 1.10, PI * 1.90, 22, Color(1, 1, 1, 0.10), 1.0, true)
	draw_line(Vector2(foot.x - sw, shoulder_y), Vector2(foot.x + sw, shoulder_y),
		Color(1, 1, 1, 0.05), 1.0)

	return Vector2(foot.x + sw * 0.88, shoulder_y - height * 0.020)

## 坐姿剪影。stature 是"这个人站着会有多高" —— 所有部件都从它推出来，
## 于是坐着的那个自然比站着的矮一截，不需要另配一套数字。
func _seated(hip: Vector2, stature: float, color: Color, blur := 0.0) -> void:
	if blur > 0.1:
		for k in range(1, 4):
			_seated(hip + Vector2(blur * float(k), 0), stature,
				Color(0.15, 0.18, 0.20, 0.24 / float(k)))
		return

	var head_r := stature * 0.066
	var shoulder := Vector2(hip.x - stature * 0.030, hip.y - stature * 0.300)
	var head_c := Vector2(shoulder.x - stature * 0.012, shoulder.y - stature * 0.045 - head_r)
	var sw := stature * 0.115     # 肩半宽
	var hw := stature * 0.110     # 坐在椅子上，胯会比站着时宽一点

	# 大腿：从胯向前（朝左）伸出去。有了它，坐姿才坐得住。
	var knee := Vector2(hip.x - stature * 0.270, hip.y + stature * 0.010)
	draw_line(Vector2(hip.x, hip.y + stature * 0.024), knee, color, maxf(3.0, stature * 0.070))
	# 小腿：垂到地面
	var ankle := Vector2(knee.x + stature * 0.020, hip.y + stature * 0.256)
	draw_line(knee, ankle, color, maxf(2.4, stature * 0.058))
	draw_circle(knee, stature * 0.035, color)
	# 脚
	draw_rect(Rect2(ankle.x - stature * 0.055, ankle.y - stature * 0.010,
		stature * 0.080, stature * 0.018), color)

	# 躯干
	var torso := PackedVector2Array([
		Vector2(shoulder.x - sw, shoulder.y),
		Vector2(shoulder.x + sw, shoulder.y),
		Vector2(hip.x + hw, hip.y + stature * 0.030),
		Vector2(hip.x - hw, hip.y + stature * 0.030),
	])
	draw_colored_polygon(torso, color)

	# 脖子
	draw_rect(Rect2(head_c.x - head_r * 0.36, head_c.y + head_r * 0.70,
		head_r * 0.72, shoulder.y - head_c.y - head_r * 0.70 + 1.0), color)
	# 头
	draw_circle(head_c, head_r, color)
	draw_arc(head_c, head_r, PI * 1.10, PI * 1.90, 22, Color(1, 1, 1, 0.10), 1.0, true)
	draw_line(Vector2(shoulder.x - sw, shoulder.y), Vector2(shoulder.x + sw, shoulder.y),
		Color(1, 1, 1, 0.05), 1.0)

## 一条手臂。粗细也跟身高挂钩，免得粗成一根棍子。
func _limb(a: Vector2, b: Vector2, height: float, color: Color) -> void:
	var th := maxf(2.0, height * 0.055)
	draw_line(a, b, color, th)
	draw_circle(a, th * 0.56, color)
	draw_circle(b, th * 0.44, color)

# ─────────────────────────────────────────────────────────────
#  镜头前的那个人
# ─────────────────────────────────────────────────────────────
func _foreground(x: float, y: float, w: float, h: float) -> void:
	# 左下角：镜头前那个人的后脑与肩。虚、暗、不抢戏，
	# 但正是它让这段画面读起来像"随手拍的"而不是"摆好的"。
	# 顺便也把左下角那一大块空地填掉了。
	var dark := Color(0.006, 0.010, 0.014)
	var hc := Vector2(x + w * 0.050, y + h * 0.790)
	var hr := w * 0.033
	var shoulder := PackedVector2Array([
		Vector2(x - w * 0.070, y + h * 1.06),
		Vector2(x + w * 0.190, y + h * 1.06),
		Vector2(x + w * 0.152, y + h * 0.902),
		Vector2(x + w * 0.082, y + h * 0.842),
		Vector2(x - w * 0.025, y + h * 0.892),
	])
	draw_colored_polygon(shoulder, dark)
	draw_circle(hc, hr, dark)
	# 后脑上缘一道极淡的轮廓光。不画这一笔，它就只是一个黑球。
	draw_arc(hc, hr, PI * 1.15, PI * 1.95, 22, Color(0.72, 0.80, 0.84, 0.15), 1.2, true)

func _ease(t: float) -> float:
	# 先快后慢，收得干脆
	return 1.0 - pow(1.0 - clampf(t / 0.55, 0.0, 1.0), 3.0)

# ─────────────────────────────────────────────────────────────
#  手机取景的痕迹：扫描线、噪点、时间码、角落括线、暗角
# ─────────────────────────────────────────────────────────────
func _overlays(w: float, h: float) -> void:
	# 扫描线
	var sy := 0.0
	while sy < h:
		draw_rect(Rect2(0, sy, w, 1.0), Color(0, 0, 0, 0.075))
		sy += 3.0

	# 一条缓慢上下游走的跟踪噪点带。老录像带的味道，也提醒玩家"画面质量有限"。
	var band_y := fmod(_clock * 11.0, h + 90.0) - 45.0
	var amp := 1.0 + (_t * 1.4 if playing else 0.0)
	for k in range(9):
		var a := 0.075 * (1.0 - absf(float(k) - 4.0) / 4.0)
		# 噪点带播放时更粗：画面在动，压缩算法就跟不上了
		draw_rect(Rect2(0, band_y + float(k) * 2.4, w, 2.4), Color(1, 1, 1, a * amp))

	# 压缩噪点。位置固定、亮度随帧微变 —— 这就是"低码率"最直接的证据，
	# 比任何一句说明文字都有效。
	_grain(w, h)

	# 暗角。偷拍镜头的四角总是暗的。
	for k in range(10):
		var t := float(k) / 9.0
		var a := 0.10 * (1.0 - t)
		var inset := t * h * 0.16
		draw_rect(Rect2(0, inset, w, 2.5), Color(0, 0, 0, a))
		draw_rect(Rect2(0, h - inset - 2.5, w, 2.5), Color(0, 0, 0, a))
		var inset_x := t * w * 0.10
		draw_rect(Rect2(inset_x, 0, 2.5, h), Color(0, 0, 0, a * 0.7))
		draw_rect(Rect2(w - inset_x - 2.5, 0, 2.5, h), Color(0, 0, 0, a * 0.7))

	# 角落括线：取景框。极细，只在四角。
	var b := 14.0
	var line := Color(1, 1, 1, 0.20)
	var corners := [
		PackedVector2Array([Vector2(0, b), Vector2(0, 0), Vector2(b, 0)]),
		PackedVector2Array([Vector2(w - b, 0), Vector2(w, 0), Vector2(w, b)]),
		PackedVector2Array([Vector2(0, h - b), Vector2(0, h), Vector2(b, h)]),
		PackedVector2Array([Vector2(w - b, h), Vector2(w, h), Vector2(w, h - b)]),
	]
	for tri in corners:
		draw_polyline(tri, line, 1.0)

	# 上左：REC 与闪动的红点。只在真的在播的时候亮。
	if playing:
		var blink := 0.42 + 0.58 * absf(sin(_clock * 4.4))
		draw_circle(Vector2(15, 14), 4.0, Color(0.80, 0.22, 0.22, blink))
		draw_string(UIKit.font_mono(), Vector2(24, 18), "REC",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.52 * blink))

	# 下左：走的时间码。静止的那一帧取的是"中段"，所以停在 00:07；
	# 播放时才走针。这一格数字是画面里唯一可核对的东西。
	var secs := 7 if _t <= 0.0 else int(_t * 14.0)
	var clock_text := "00:%02d" % secs
	draw_string(UIKit.font_mono(), Vector2(14, h - 12), clock_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.62))
	var dur := "0:14"
	var dur_w := UIKit.font_mono().get_string_size(dur, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(UIKit.font_mono(), Vector2(w - 14 - dur_w, h - 12), dur,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.40))

	# 播放进度：贴着底边的一条细线。有它，玩家才知道这段只有四秒。
	if _t > 0.0:
		draw_rect(Rect2(0, h - 2.0, w * clampf(_t, 0.0, 1.0), 2.0), UIKit.LAMP)

	# 中央的播放钮。只在没播的时候出现。
	if not playing:
		var c := Vector2(w * 0.5, h * 0.5)
		var pulse := 1.0 + (0.05 if _hovered else 0.0)
		draw_circle(c, 27.0 * pulse, Color(0, 0, 0, 0.40))
		draw_arc(c, 27.0 * pulse, 0.0, TAU, 64, Color(1, 1, 1, 0.34 if _hovered else 0.24), 1.0, true)
		var tri := PackedVector2Array([
			c + Vector2(-6, -10), c + Vector2(-6, 10), c + Vector2(10, 0)])
		draw_colored_polygon(tri, Color(1, 1, 1, 0.80 if _hovered else 0.68))

## 一层很轻的压缩噪点。用自己的哈希而不是 RandomNumberGenerator：
## 这里要的是"稳定、便宜、够散"，不要序列、不要状态、不要内存分配。
func _grain(w: float, h: float) -> void:
	var salt := int(_clock * 20.0)
	for i in range(120):
		var r := _hash(i, salt)
		var a := 0.028 + 0.055 * r.z
		draw_rect(Rect2(r.x * w, r.y * h, 1.6, 1.6), Color(1, 1, 1, a))

func _hash(i: int, salt: int) -> Vector3:
	var v := float((i * 73856093) ^ (salt * 19349663))
	return Vector3(
		fmod(absf(sin(v * 0.0000100) * 43758.5453), 1.0),
		fmod(absf(sin(v * 0.0000131) * 24634.6345), 1.0),
		fmod(absf(sin(v * 0.0000167) * 56445.2341), 1.0))
