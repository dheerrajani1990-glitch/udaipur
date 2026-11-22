extends Node2D
# INUKI - The Tale of a Ninja (Godot 4 port)
# Everything is drawn in code: backgrounds are generated pixel images, characters are skeletal rigs.

const W := 480
const H := 270
const GY := 210
const LW := 960
const DASH_T := 10.0

var font: Font
var LV: Array = []
var st := "title"
var lv := 0
var P: Dictionary = {}
var en: Array = []
var ar: Array = []
var fx: Array = []
var plats: Array = []
var LEN := 1700
var cam := 0.0
var combo := 0
var ct := 0.0
var raijin := 0.0
var shake := 0.0
var hs := 0
var kf := 0
var zm := 1.0
var msg := ""
var mt := 0
var boss = null
var score := 0
var lv_score := 0
var best := 0
var clear := 0
var aiming := false
var aim_src := ""
var ts := 1.0
var acc := 0.0
var tnow := 0.0
var NS := Vector2.ZERO
var xf := Transform2D.IDENTITY
var prev_aim_held := false
var prev_rai := false
var prev_any := false
var sfx := {}
var players: Array = []
var pidx := 0

var POSES := {
	"idle": {"lean": .06, "fa": .22, "fk": -.3, "ba": -.18, "bk": -.12, "sf": .55, "ef": 1.25, "sb": -.15, "eb": .9},
	"hold": {"lean": .15, "fa": .3, "fk": -.4, "ba": -.25, "bk": -.2, "sf": 1.0, "ef": .5, "sb": -.2, "eb": .8},
	"aim": {"lean": .5, "fa": .95, "fk": -1.45, "ba": -.75, "bk": -.7, "sf": 1.0, "ef": 1.35, "sb": .35, "eb": 1.4},
	"air": {"lean": .15, "fa": 1.1, "fk": -1.8, "ba": .45, "bk": -1.5, "sf": .9, "ef": .9, "sb": -.9, "eb": .6},
	"dash": {"lean": .9, "fa": -.25, "fk": -.6, "ba": -.8, "bk": -.5, "sf": 1.57, "ef": 0.0, "sb": -1.8, "eb": .3},
	"throw": {"lean": -.1, "fa": .3, "fk": -.4, "ba": -.25, "bk": -.2, "sf": -2.4, "ef": -.4, "sb": -.2, "eb": .8},
	"thrown": {"lean": .3, "fa": .3, "fk": -.4, "ba": -.25, "bk": -.2, "sf": 1.6, "ef": 0.0, "sb": -.2, "eb": .8},
}

# ------------------------------------------------------------ setup
func _ready() -> void:
	randomize()
	font = ThemeDB.fallback_font
	_load_best()
	_setup_audio()
	_build_levels()
	_load_level(0)
	st = "title"

func _load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://inuki.cfg") == OK:
		best = int(cf.get_value("save", "best", 0))

func _save_best() -> void:
	if score > best:
		best = score
		var cf := ConfigFile.new()
		cf.set_value("save", "best", best)
		cf.save("user://inuki.cfg")

# ------------------------------------------------------------ audio (synthesized)
func _setup_audio() -> void:
	sfx["slash"] = _synth("slash", 0.2)
	sfx["hit"] = _synth("hit", 0.3)
	sfx["kill"] = _synth("kill", 0.45)
	sfx["thunder"] = _synth("thunder", 1.4)
	sfx["click"] = _synth("click", 0.08)
	sfx["hurt"] = _synth("hurt", 0.3)
	sfx["throw"] = _synth("throw", 0.14)
	sfx["slam"] = _synth("slam", 0.6)
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)

func _synth(kind: String, dur: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		var k := t / dur
		var nz := randf() * 2.0 - 1.0
		var s := 0.0
		match kind:
			"slash":
				lp += (nz - lp) * (0.9 - k * 0.7)
				s = (nz - lp * 0.6) * pow(1.0 - k, 2.0) * 0.8
			"hit":
				ph += TAU * lerpf(160.0, 45.0, k) / rate
				lp += (nz - lp) * 0.2
				s = (sin(ph) * 0.8 + lp * 0.5) * pow(1.0 - k, 2.5)
			"kill":
				ph += TAU * lerpf(220.0, 40.0, k) / rate
				lp += (nz - lp) * 0.35
				s = (sin(ph) * 0.6 + lp * 0.7) * pow(1.0 - k, 1.8)
			"thunder":
				lp += (nz - lp) * 0.06
				s = lp * 3.0 * pow(1.0 - k, 1.3) * (0.6 + 0.4 * sin(t * 37.0))
			"click":
				ph += TAU * 2400.0 / rate
				s = signf(sin(ph)) * 0.4 * (1.0 - k)
			"hurt":
				ph += TAU * lerpf(300.0, 90.0, k) / rate
				s = signf(sin(ph)) * 0.35 * (1.0 - k)
			"throw":
				lp += (nz - lp) * 0.5
				s = lp * sin(k * PI) * 0.5
			"slam":
				ph += TAU * lerpf(90.0, 30.0, k) / rate
				lp += (nz - lp) * 0.08
				s = (sin(ph) + lp * 2.0) * pow(1.0 - k, 2.0) * 0.7
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w

func play(snd: String, pitch := 1.0, vol := 0.0) -> void:
	var p: AudioStreamPlayer = players[pidx]
	pidx = (pidx + 1) % players.size()
	p.stream = sfx[snd]
	p.pitch_scale = pitch * randf_range(0.92, 1.08)
	p.volume_db = vol
	p.play()

# ------------------------------------------------------------ background generation
var _rng := RandomNumberGenerator.new()
func R() -> float:
	return _rng.randf()

func _img(w: int) -> Image:
	var im := Image.create(w, H, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 0))
	return im

func fr(im: Image, x: float, y: float, w: float, h: float, c: Color) -> void:
	var r := Rect2i(int(round(x)), int(round(y)), max(1, int(round(w))), max(1, int(round(h))))
	r = r.intersection(Rect2i(0, 0, im.get_width(), im.get_height()))
	if r.size.x > 0 and r.size.y > 0:
		im.fill_rect(r, c)

const BY := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
func dither(im: Image, cols: Array, y0: int, y1: int) -> void:
	var n: int = cols.size() - 1
	for y in range(y0, y1):
		var t := float(y - y0) / float(y1 - y0) * n
		for x in im.get_width():
			var i := int(floor(t))
			var f := t - i
			if f * 16.0 > BY[(y % 4) * 4 + x % 4]:
				i += 1
			im.set_pixel(x, y, Color(cols[min(n, i)]))

func ridge(im: Image, w: int, base: float, amp: float, col: Color, stp := 1.0) -> void:
	var v := 0.0
	for x in w:
		v += (R() - .5) * stp
		v *= .97
		var hh := base - amp * (.5 + .5 * sin(float(x) / w * TAU * 3.0 + 1.0)) + v * 9.0 + sin(x * .7) * .8
		fr(im, x, hh, 1, H - hh, col)

func pine(im: Image, X: float, Y: float, sz: float, col: Color, rim) -> void:
	fr(im, X, Y - sz * 3, max(2, sz / 3), sz * 3, col)
	for i in 4:
		var ww := sz * (3 - i * .5) * (.8 + R() * .4)
		var yy := Y - sz * 3 - i * sz * .9
		var ox := (R() - .5) * sz
		fr(im, X + ox - ww / 2, yy - sz * .5, ww, ceil(sz * .7), col)
		if rim != null:
			var p := 0.0
			while p < ww:
				if R() < .5:
					fr(im, X + ox - ww / 2 + p, yy - sz * .5, 2 if R() < .5 else 1, 1, rim)
				p += 2 + int(R() * 4)

func torii(im: Image, X: float, Y: float, s: float, col: Color, rim: Color) -> void:
	fr(im, X - s * 4, Y - s * 9, s * 8, s, col)
	fr(im, X - s * 4 - 2, Y - s * 9 - 2, 3, 2, col)
	fr(im, X + s * 4 - 1, Y - s * 9 - 2, 3, 2, col)
	fr(im, X - s * 3.5, Y - s * 7.5, s * 7, s * .6, col)
	fr(im, X - s * 3, Y - s * 9, s * .8, s * 9, col)
	fr(im, X + s * 2.2, Y - s * 9, s * .8, s * 9, col)
	fr(im, X - s * 4, Y - s * 9 - 1, s * 3, 1, rim)
	fr(im, X + s, Y - s * 9 - 1, s * 2.5, 1, rim)
	fr(im, X - s * 2, Y - s * 7.5 - 1, s * 2, 1, rim)

func pagoda(im: Image, X: float, Y: float, w: float, fl: int, col: Color, win: Color) -> void:
	for f in fl:
		var yy := Y - f * 20
		var ww := w - f * 10
		fr(im, X - ww / 2, yy - 16, ww, 16, col)
		fr(im, X - ww / 2 - 8, yy - 20, ww + 16, 5, col)
		fr(im, X - ww / 2 - 11, yy - 22, 4, 3, col)
		fr(im, X + ww / 2 + 7, yy - 22, 4, 3, col)
		var p := -ww / 2 + 4
		while p < ww / 2 - 4:
			if R() < .6:
				fr(im, X + p, yy - 11, 3, 5, win)
				fr(im, X + p - 1, yy - 12, 5, 7, Color(win, .15))
			p += 8
	fr(im, X - 1, Y - fl * 20 - 10, 3, 10, col)

func dead_tree(im: Image, X: float, Y: float, col: Color) -> void:
	fr(im, X, Y - 70, 6, 70, col)
	var bx := X + 3
	var by := Y - 70
	for i in 16:
		var dx := (R() - .5) * 50
		var dy := -R() * 22
		var t := 0.0
		while t < 1.0:
			fr(im, bx + dx * t, by + dy * t, 3 if t < .5 else 2, 2, col)
			t += .05
		fr(im, bx + dx - 5, by + dy - 3, 8 + R() * 10, 3, col)
		if R() < .5:
			bx += dx * .5
			by += dy * .5

func disc(im: Image, cx: float, cy: float, r: float, c1: Color, c2 = null) -> void:
	for yy in range(-int(r), int(r) + 1):
		for xx in range(-int(r), int(r) + 1):
			if xx * xx + yy * yy < r * r:
				var c := c1
				if c2 != null and sin(xx * .35) * cos(yy * .4) > .4:
					c = c2
				fr(im, cx + xx, cy + yy, 1, 1, c)

func _build_levels() -> void:
	var defs := [
		{"n": "I. Moonlit Torii", "tr": .25, "fl": 0.0, "col": {"s": "#0b0914", "m": "#2e2448", "r": "#ff9ac1"},
		 "en": {"s": "#120e1e", "m": "#2a2040", "r": "#ff9ac1", "e": "#ff4d8d"}, "ground": "#0b0914"},
		{"n": "II. Lantern Village", "tr": .35, "fl": 1.0, "col": {"s": "#0d0a14", "m": "#33202e", "r": "#ff8a8a"},
		 "en": {"s": "#140e1c", "m": "#2c1a2a", "r": "#ff8a8a", "e": "#ff5050"}, "ground": "#120c1a", "water": "#2a1d3d"},
		{"n": "III. Misty Cliffs", "tr": .4, "fl": 1.5, "col": {"s": "#1b1c1b", "m": "#4a4c4a", "r": "#ffffff"},
		 "en": {"s": "#2a2b2a", "m": "#4a4b48", "r": "#eeeeea", "e": "#cc3333"}, "ground": "#3a3b38", "fog": true},
		{"n": "IV. The Burning Camp", "tr": .5, "fl": 0.0, "col": {"s": "#070c0f", "m": "#18303a", "r": "#9ff6ff"},
		 "en": {"s": "#0b1418", "m": "#1a2a30", "r": "#ff9a40", "e": "#ff4020"}, "ground": "#060b0e", "rain": true, "boss": true},
	]
	for i in defs.size():
		var d: Dictionary = defs[i]
		var L := {"n": d.n, "tr": d.tr, "fl": d.fl, "fog": d.get("fog", false), "rain": d.get("rain", false), "boss": d.get("boss", false)}
		for key in ["col", "en"]:
			var c := {}
			for kk in d[key]:
				c[kk] = Color(d[key][kk])
			L[key] = c
		L["ground"] = Color(d.ground)
		_rng.seed = 1000 + i
		var sky := _img(W)
		var far := _img(LW)
		var mid := _img(LW)
		var near := _img(LW)
		var gnd := _img(LW)
		match i:
			0:
				dither(sky, ["#1c1a33", "#252342", "#2e2850", "#3d2c5c", "#4a2f63"], 0, H)
				for s in 80:
					fr(sky, R() * W, R() * 140, 1, 1, Color("#cfc8ff", .5 + R() * .5))
				for cl in [[90, 45, 90], [350, 95, 70], [220, 30, 60]]:
					for k in 6:
						fr(sky, cl[0] - cl[2] / 2.0 + k * 6, cl[1] + (k % 2) * 3, cl[2] - k * 10, 4, Color("#17152a"))
				disc(sky, 380, 60, 18, Color("#f4e8ff"), Color("#d8c8f0"))
				ridge(far, LW, 185, 34, Color("#3a2a5a"), .5)
				ridge(mid, LW, 205, 14, Color("#241a3a"), .4)
				var X := 80.0
				while X < LW:
					torii(mid, X, GY + 2, 7, Color("#07060c"), Color("#ff9ac1"))
					X += 230 + R() * 140
				X = 30.0
				while X < LW:
					pine(near, X, GY + 6, 10 + R() * 6, Color("#050409"), Color("#ff9ac1"))
					X += 120 + R() * 140
			1:
				dither(sky, ["#2a1d45", "#3e2758", "#6a3a6e", "#a35a7e", "#c8788a", "#7a4a78"], 0, 180)
				dither(sky, ["#3a2850", "#2a1d3d"], 180, H)
				disc(sky, 130, 90, 42, Color("#f2b8b0"), Color("#e09aa0"))
				for s in 14:
					fr(sky, (s * 83) % W, 30 + s * 11, 90 + (s * 13) % 60, 2, Color("#5a3466"))
				ridge(far, LW, 172, 26, Color("#5a3e74"), .6)
				ridge(mid, LW, 190, 9, Color("#3a2852"), .4)
				var X := 60.0
				while X < LW:
					pagoda(mid, X, GY - 6, 50 + R() * 26, 2 + int(R() * 2), Color("#140e1e"), Color("#ff6a5a"))
					X += 170 + R() * 130
				X = 120.0
				while X < LW:
					dead_tree(near, X, GY + 4, Color("#08060d"))
					X += 300 + R() * 160
				X = 0.0
				while X < LW:
					fr(near, X, GY - 10, 3, 14, Color("#08060d"))
					X += 22
			2:
				dither(sky, ["#cfcfca", "#dcdcd7", "#e9e9e4", "#efefea"], 0, H)
				disc(sky, 90, 60, 16, Color("#f6f6e8"))
				var X := 0.0
				while X < LW:
					var hh := 60 + R() * 85
					var ww := 18 + R() * 30
					fr(far, X, 185 - hh, ww, H, Color("#c2c3bf"))
					fr(far, X + 3, 178 - hh, ww - 8, 8, Color("#c2c3bf"))
					X += 30 + R() * 45
				X = 0.0
				while X < LW:
					var hh := 24 + R() * 55
					var i2 := 0.0
					while i2 < hh:
						fr(mid, X - i2 * .2, GY - hh + i2, 28 + i2 * .6, 4, Color("#9a9c97"))
						i2 += 4
					X += 50 + R() * 70
				ridge(mid, LW, GY + 3, 6, Color("#8a8c87"), .3)
				X = 90.0
				while X < LW:
					pine(near, X, GY + 6, 8 + R() * 5, Color("#2c2e2b"), Color("#5a5c58"))
					X += 240 + R() * 160
			3:
				dither(sky, ["#0a141a", "#0f1e26", "#15303a", "#1a3a44", "#14262e"], 0, H)
				for r in range(36, 16, -4):
					disc(sky, 380, 50, r, Color(.63, .94, 1.0, .06))
				disc(sky, 380, 50, 16, Color("#e8ffff"))
				var X := 0.0
				while X < LW:
					fr(far, X, 130 + sin(X * .05) * 10 + R() * 10, 3, H, Color("#0e1d23"))
					X += 3
				X = 0.0
				while X < LW:
					fr(mid, X, 165 + sin(X * .03) * 5, 2, H, Color("#0a161b"))
					X += 2
				X = 50.0
				while X < LW:
					fr(mid, X, GY - 46, 54, 24, Color("#d8c8a0"))
					fr(mid, X + 20, GY - 41, 12, 12, Color("#0a161b"))
					fr(mid, X + 23, GY - 38, 6, 6, Color("#d8c8a0"))
					for b in 3:
						fr(mid, X + b * 25, GY - 78, 2, 58, Color("#0a161b"))
						fr(mid, X + b * 25 + 2, GY - 78, 7, 20, Color("#c9bfa0"))
					for f in 3:
						var fx2 := X + R() * 70
						fr(mid, fx2, GY - 14, 7, 11, Color("#ff6a10"))
						fr(mid, fx2 + 2, GY - 10, 3, 7, Color("#ffcc40"))
					X += 190 + R() * 100
				X = 70.0
				while X < LW:
					dead_tree(near, X, GY + 4, Color("#030608"))
					X += 300 + R() * 140
		# ground strip
		fr(gnd, 0, GY, LW, H - GY, L.ground)
		var gx := 0.0
		while gx < LW:
			fr(gnd, gx, GY, 1, 2 if R() < .3 else 1, Color(L.col.r, .5))
			gx += 3 + int(R() * 6)
		if d.has("water"):
			fr(gnd, 0, GY + 22, LW, H, Color(d.water))
			for s in 60:
				fr(gnd, R() * LW, GY + 26 + R() * 34, 6 + R() * 18, 1, Color("#c8788a", .7))
		L["sky"] = ImageTexture.create_from_image(sky)
		L["far"] = ImageTexture.create_from_image(far)
		L["mid"] = ImageTexture.create_from_image(mid)
		L["near"] = ImageTexture.create_from_image(near)
		L["gnd"] = ImageTexture.create_from_image(gnd)
		LV.append(L)

# ------------------------------------------------------------ level / entities
func pose(n: String) -> Dictionary:
	return POSES[n].duplicate()

func mk(type: String, X: float, Y: float, pl) -> Dictionary:
	return {"type": type, "x": X, "y": Y, "pl": pl, "t": randf() * 80, "wind": 0.0, "strike": 0.0, "cd": 0.0, "dir": 1.0, "f": true,
		"an": 0.0, "vy": 0.0, "vx": 0.0, "gr": true, "hp": 2 if type == "m" else 1, "inv": 0.0, "thr": 0.0, "pose": pose("idle")}

func _load_level(i: int) -> void:
	lv = i
	lv_score = score
	var L: Dictionary = LV[i]
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + i
	P = {"x": 50.0, "y": float(GY), "vx": 0.0, "vy": 0.0, "f": false, "hp": 5, "inv": 0.0, "dash": 0.0, "dx": 1.0, "dy": 0.0, "ch": 2,
		"gr": true, "an": 0.0, "slash": 0.0, "fo": 100.0, "lt": 0, "pose": pose("idle"), "sw": "in", "swt": 0.0}
	en = []; ar = []; fx = []; plats = []
	cam = 0.0; combo = 0; ct = 0.0; hs = 0; boss = null; clear = 0; msg = L.n; mt = 150; aiming = false
	if L.boss:
		LEN = 640
		plats = [{"x": 50.0, "y": GY - 42.0, "w": 96.0}, {"x": 272.0, "y": GY - 80.0, "w": 96.0}, {"x": 494.0, "y": GY - 42.0, "w": 96.0}]
		boss = {"x": 500.0, "y": float(GY), "vx": 0.0, "vy": 0.0, "hp": 12, "mhp": 12, "t": 0.0, "inv": 0.0, "f": true, "gr": true, "an": 0.0, "pose": pose("hold")}
		en.append(mk("t", 98, GY - 42, plats[0]))
		en.append(mk("t", 542, GY - 42, plats[2]))
	else:
		LEN = 1700 + i * 380
		var X := 220.0
		while X < LEN - 180:
			var w := 54.0 + rng.randf() * 76
			var tier := 1 + int(rng.randf() * 3)
			plats.append({"x": X, "y": GY - tier * 34.0, "w": w})
			X += w + 40 + rng.randf() * 90
		for p in plats:
			if rng.randf() < .7:
				en.append(mk("t" if rng.randf() < L.tr else "m", p.x + p.w / 2, p.y, p))
		X = 360.0
		while X < LEN - 90:
			en.append(mk("m", X, GY, null))
			X += 250 + rng.randf() * 200
		if L.fl > 0:
			X = 480.0
			while X < LEN - 90:
				en.append(mk("f", X, GY, null))
				X += 420 / L.fl + rng.randf() * 240

func start_game() -> void:
	if st == "title" or st == "win":
		score = 0; raijin = 0.0
		_load_level(0)
	elif st == "over":
		score = lv_score; raijin = 0.0
		_load_level(lv)
	st = "play"

# ------------------------------------------------------------ input
func move_axis() -> float:
	var a := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): a -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): a += 1
	var j := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	if abs(j) > .25: a = j
	return clampf(a, -1, 1)

func aim_held() -> bool:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): aim_src = "mouse"; return true
	if Input.is_key_pressed(KEY_K) or Input.is_key_pressed(KEY_J): aim_src = "key"; return true
	if Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > .5 or Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER): aim_src = "pad"; return true
	return false

func aim_dir() -> Vector2:
	var v := Vector2.ZERO
	if aim_src == "mouse":
		var m := get_viewport().get_mouse_position()
		var ps := xf * Vector2(P.x, P.y - 18)
		v = m - ps
		if v.length() < 6: v = Vector2.ZERO
	elif aim_src == "pad":
		v = Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
		if v.length() < .3: v = Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
		if v.length() < .3: v = Vector2.ZERO
	else:
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): v.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): v.x += 1
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): v.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): v.y += 1
	if v == Vector2.ZERO:
		return Vector2(-1 if P.f else 1, 0)
	return v.normalized()

func raijin_pressed() -> bool:
	return Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_joy_button_pressed(0, JOY_BUTTON_Y)

func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_F:
		var m := DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if m == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE and st == "play":
		get_tree().paused = false
	if st != "play" and ((ev is InputEventKey and ev.pressed and not ev.echo) or (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventJoypadButton and ev.pressed)):
		start_game()
		prev_aim_held = true

func release() -> void:
	if P.ch <= 0: return
	var d := aim_dir()
	P.ch -= 1
	P.dash = DASH_T
	P.dx = d.x; P.dy = d.y
	if d.x != 0: P.f = d.x < 0
	P.slash = 14.0
	P.gr = false
	shake = max(shake, 2.0)
	fx.append({"k": "streak", "x0": P.x, "y0": P.y - 18, "x1": P.x, "y1": P.y - 18, "l": 16.0, "live": true})
	play("slash", 1.1 if P.lt > 0 else 1.0)

# ------------------------------------------------------------ main loop
func _process(delta: float) -> void:
	acc += min(delta, 0.1)
	tnow += delta
	while acc >= 1.0 / 60.0:
		acc -= 1.0 / 60.0
		if st == "play":
			var held := aim_held()
			if held and not prev_aim_held and P.ch > 0 and not clear:
				aiming = true
			if aiming and not held:
				aiming = false
				release()
			prev_aim_held = held
			var rp := raijin_pressed()
			if rp and not prev_rai and raijin >= 100 and P.lt <= 0:
				activate_raijin()
			prev_rai = rp
			ts = 0.12 if aiming else (0.25 if hs > 0 else 1.0)
			if hs > 0: hs -= 1
			if kf > 0: kf -= 1
			step(ts)
			shake = shake * .85 if shake > .3 else 0.0
	queue_redraw()

func PC() -> Vector2:
	return Vector2(P.x, P.y - 18)

func EC(e: Dictionary) -> Vector2:
	return Vector2(e.x, e.y - 18)

func part(X: float, Y: float, col: Color, n: int, sp := 3.0) -> void:
	for i in n:
		fx.append({"k": "p", "x": X, "y": Y, "vx": (randf() - .5) * sp * 2, "vy": -randf() * sp * 1.5, "l": 20 + randf() * 25, "c": col, "sz": 2})

func blood(X: float, Y: float, n: int) -> void:
	for i in n:
		fx.append({"k": "blood", "x": X, "y": Y, "vx": (randf() - .5) * 6 + P.dx * 3, "vy": (randf() - .8) * 4.5 + P.dy * 1.5,
			"l": 40 + randf() * 30, "c": Color("#d0102a") if randf() < .5 else Color("#7a0018"), "sz": 1 + int(randf() * 3)})

func bolt(x0: float, y0: float, x1: float, y1: float) -> void:
	var pts := [Vector2(x0, y0)]
	for i in range(1, 6):
		pts.append(Vector2(x0 + (x1 - x0) * i / 6.0 + (randf() - .5) * 12, y0 + (y1 - y0) * i / 6.0 + (randf() - .5) * 12))
	pts.append(Vector2(x1, y1))
	fx.append({"k": "bolt", "pts": pts, "l": 10.0})

func activate_raijin() -> void:
	raijin = 0.0
	P.lt = 540
	P.ch = 2
	shake = 14.0
	hs = 20
	fx.append({"k": "flash", "l": 16.0, "blue": true})
	for i in 7:
		bolt(P.x + (randf() - .5) * 90, P.y - 160, P.x + (randf() - .5) * 30, P.y - 18)
	play("thunder")

func kill(e: Dictionary) -> void:
	var c := EC(e)
	var L: Dictionary = LV[lv]
	fx.append({"k": "corpse", "x": e.x, "y": e.y, "pose": e.pose.duplicate(), "f": e.f, "vx": P.dx * 3.5, "vy": -3 + P.dy * 3, "rot": 0.0,
		"vr": (1 if P.dx > 0 else -1) * .12, "l": 60.0, "sc": 1.0})
	if P.lt > 0:
		bolt(c.x, c.y - 45, c.x, c.y)
		bolt(c.x - 30, c.y - 15, c.x + 30, c.y + 8)
	part(c.x, c.y, L.en.s, 10)
	part(c.x, c.y, L.col.r, 8, 4.5)
	combo += 1
	ct = 150.0
	score += 10 * combo
	if P.lt <= 0: raijin = min(100.0, raijin + 12)
	shake = max(shake, 5.0)
	hs = 10
	kf = 24
	blood(c.x, c.y, 26)
	P.ch = min(2, P.ch + 1)
	P.vy = min(P.vy, -1.8)
	fx.append({"k": "text", "x": c.x, "y": c.y - 22, "t": (str(combo) + "x") if combo > 1 else "+10", "l": 40.0, "vy": -.6})
	play("kill")

func hit(e: Dictionary) -> bool:
	var dmg := 2 if P.lt > 0 else 1
	e.hp -= dmg
	if e.hp <= 0: return true
	e.inv = 18.0; e.vx = P.dx * 4.5; e.wind = 0.0; e.strike = 0.0
	hs = 5; shake = max(shake, 3.0)
	var c := EC(e)
	part(c.x, c.y, Color("#d0102a"), 8)
	part(c.x, c.y, LV[lv].col.r, 5)
	P.ch = min(2, P.ch + 1)
	P.vy = min(P.vy, -1.8)
	play("hit")
	return false

func hurt(from: float) -> void:
	if P.inv > 0 or P.dash > 0 or clear: return
	P.hp -= 1
	P.inv = 70.0
	shake = 9.0; hs = 6; combo = 0
	P.vx = -3.8 if P.x < from else 3.8
	P.vy = -3.0
	part(P.x, P.y - 18, Color.WHITE, 8)
	play("hurt")
	if P.hp <= 0:
		st = "over"
		aiming = false
		_save_best()

func lerp_pose(cur: Dictionary, tp: Dictionary, r: float) -> void:
	for q in tp:
		cur[q] += (tp[q] - cur[q]) * r

func run_pose(an: float, out: bool) -> Dictionary:
	var s := sin(an)
	var c := cos(an)
	return {"lean": .3, "fa": .75 * s, "fk": -.25 - .9 * max(0.0, c), "ba": -.75 * s, "bk": -.25 - .9 * max(0.0, -c),
		"sf": 1.2 if out else .6, "ef": .4 if out else 1.2, "sb": -.6 * s, "eb": .6}

func step(dt: float) -> void:
	var L: Dictionary = LV[lv]
	if mt > 0: mt -= 1
	# focus
	if aiming:
		P.fo -= .5
		if P.fo <= 0:
			P.fo = 0.0
			aiming = false
			release()
	else:
		P.fo = min(100.0, P.fo + .45)
	# player
	if P.dash > 0:
		P.dash -= dt
		var sp := 12.0 if P.lt > 0 else 9.75
		P.vx = P.dx * sp; P.vy = P.dy * sp
		if P.lt > 0 and randf() < .5:
			bolt(P.x, P.y - 18, P.x - P.dx * 20 + (randf() - .5) * 14, P.y - 18 - P.dy * 20 + (randf() - .5) * 14)
		fx.append({"k": "ghost", "x": P.x, "y": P.y, "l": 10.0, "f": P.f, "pose": P.pose.duplicate()})
		for f in fx:
			if f.k == "streak" and f.live:
				f.x1 = P.x; f.y1 = P.y - 18
		if P.dash <= 0:
			P.vx *= .7
			P.vy = P.vy * .3 - .9
			for f in fx:
				if f.k == "streak": f.live = false
	else:
		var tg := 0.0 if (aiming and aim_src == "key") else move_axis() * 2.7
		if tg != 0:
			P.vx += (tg - P.vx) * (.25 if P.gr else .07) * dt
			P.f = tg < 0
		elif P.gr:
			P.vx *= pow(.75, dt)
		P.vy = min(3.9, P.vy + (.165 if P.vy < 0 else .13) * dt)
	var oy: float = P.y
	P.x += P.vx * dt
	P.y += P.vy * dt
	P.gr = false
	if P.y >= GY:
		P.y = float(GY)
		if P.vy > 0: P.vy = 0.0
		P.gr = true
	elif P.vy >= 0:
		for p in plats:
			if oy <= p.y + .5 and P.y >= p.y and abs(P.x - (p.x + p.w / 2)) < p.w / 2 + 3:
				P.y = p.y; P.vy = 0.0; P.gr = true
				if P.dash > 0 and P.dy > .4: P.dash = 0.0
				break
	if P.gr and P.dash <= 0: P.ch = 2
	if P.y < 40:
		P.y = 40.0
		P.vy = max(0.0, P.vy)
	P.x = clampf(P.x, 10, LEN - 10)
	P.inv -= dt
	if P.slash > 0: P.slash -= dt
	if abs(P.vx) > .4 and P.gr: P.an += .2 * dt
	# sword: draw / hold / sheathe
	if P.dash > 0:
		P.sw = "out"; P.swt = 0.0
	elif P.sw == "out":
		P.swt += 3.0 if aiming else dt
		if P.swt > 16 or aiming:
			P.sw = "sh"; P.swt = 0.0
	elif P.sw == "sh":
		P.swt += 2.0 if aiming else dt
		if P.swt > 16:
			P.sw = "in"
			part(P.x + 3, P.y - 18, L.col.r, 4, 1.2)
			play("click", 1.0, -6)
	var tp: Dictionary
	if P.dash > 0:
		var a := atan2(abs(P.dx), P.dy)
		tp = pose("dash"); tp.lean = clampf(a - .7, -.3, 1.1); tp.sf = a; tp.ef = 0.0
	elif aiming:
		tp = POSES.aim
	elif not P.gr:
		tp = pose("air")
		if P.sw != "in": tp.sf = 1.4; tp.ef = .3
	elif abs(P.vx) > .4:
		tp = run_pose(P.an * 1.1, P.sw == "out")
	else:
		tp = POSES.hold if P.sw == "out" else POSES.idle
	lerp_pose(P.pose, tp, .6 if P.dash > 0 else .3)
	if ct > 0: ct -= dt
	else: combo = 0
	# enemies
	var pc := PC()
	var atk: bool = P.dash > 0 or P.slash > 8
	var i := en.size() - 1
	while i >= 0:
		var e: Dictionary = en[i]
		i -= 1
		var ec := EC(e)
		var d := pc.x - ec.x
		if abs(d) > W * .8: continue
		e.t += dt; e.cd -= dt; e.inv -= dt
		if atk and e.inv <= 0 and pc.distance_to(ec) < 24:
			if hit(e):
				kill(e)
				en.erase(e)
				continue
		var mn: float = (e.pl.x + 6) if e.pl != null else 6.0
		var mx: float = (e.pl.x + e.pl.w - 6) if e.pl != null else LEN - 6.0
		var same: bool = abs(P.y - e.y) < 24
		var etp: Dictionary = POSES.hold
		if e.inv > 0:
			e.x += e.vx * dt; e.vx *= .85; etp = POSES.air
		elif e.type == "m":
			if e.wind > 0:
				e.wind -= dt; etp = POSES.aim
				if e.wind <= 0:
					e.strike = 14.0; e.vx = (-1 if e.f else 1) * 4.2
					play("slash", .8, -4)
			elif e.strike > 0:
				e.strike -= dt; e.x += e.vx * dt
				etp = pose("dash"); etp.sf = 1.57; etp.ef = 0.0; etp.lean = .5
				if pc.distance_to(ec) < 21: hurt(e.x)
			elif same and abs(d) < 48 and e.cd <= 0:
				e.wind = 30.0; e.f = d < 0; e.cd = 80.0
			else:
				var v: float = (signf(d) * 1.2) if same else (e.dir * .6)
				e.x += v * dt; e.an += .2 * dt
				if not same and (e.x <= mn or e.x >= mx): e.dir *= -1
				e.f = v < 0
				etp = run_pose(e.an * 1.1, true)
		elif e.type == "t":
			e.f = d < 0
			if e.wind > 0:
				e.wind -= dt; etp = POSES.throw
				if e.wind <= 0:
					var v := (pc - (ec + Vector2(0, -6))).normalized() * 2.7
					ar.append({"x": ec.x, "y": ec.y - 6, "vx": v.x, "vy": v.y, "r": 0.0, "l": 260.0})
					e.thr = 10.0
					play("throw", 1.0, -6)
			elif abs(d) < 260 and e.t > 110:
				e.t = 0.0; e.wind = 26.0
			if e.thr > 0:
				e.thr -= dt; etp = POSES.thrown
		else:
			if not e.gr:
				e.vy += .24 * dt; e.x += e.vx * dt; e.y += e.vy * dt; etp = POSES.air
				if pc.distance_to(EC(e)) < 21: hurt(e.x)
				if e.y >= GY:
					e.y = float(GY); e.gr = true; e.cd = 90.0
			elif e.wind > 0:
				e.wind -= dt; etp = POSES.aim
				if e.wind <= 0:
					e.gr = false; e.vy = -6.0; e.vx = clampf((pc.x - ec.x) / 38.0, -3.9, 3.9)
			elif abs(d) < 200 and e.cd <= 0:
				e.wind = 24.0; e.f = d < 0
			else:
				e.f = d < 0
		if e.type != "f" or e.gr: e.x = clampf(e.x, mn, mx)
		lerp_pose(e.pose, etp, .3)
	# shuriken
	i = ar.size() - 1
	while i >= 0:
		var a: Dictionary = ar[i]
		i -= 1
		a.x += a.vx * dt; a.y += a.vy * dt; a.r += .4 * dt; a.l -= dt
		var dd := pc.distance_to(Vector2(a.x, a.y))
		if atk and dd < 24:
			part(a.x, a.y, L.col.r, 6)
			ar.erase(a)
			score += 5
			P.ch = min(2, P.ch + 1)
			hs = 3
			play("click", 1.4, -4)
			continue
		if dd < 11:
			hurt(a.x); ar.erase(a); continue
		if a.l <= 0 or a.y > GY + 6: ar.erase(a)
	# boss
	if boss != null:
		var b: Dictionary = boss
		var bc := Vector2(b.x, b.y - 36)
		var d := pc.x - bc.x
		b.t += dt; b.inv -= dt
		var btp: Dictionary = POSES.hold
		if b.gr:
			b.f = d < 0
			var ph := fmod(b.t, 240.0)
			if ph < 110:
				b.x += signf(d) * .9 * dt; b.an += .15 * dt
				btp = run_pose(b.an, true)
			elif ph < 140:
				btp = POSES.throw
			if ph >= 140 and ph - dt < 140:
				for j in range(-2, 3):
					var ang := atan2(pc.y - bc.y, d) + j * .3
					ar.append({"x": bc.x, "y": bc.y, "vx": cos(ang) * 2.5, "vy": sin(ang) * 2.5, "r": 0.0, "l": 300.0})
				play("throw", .7)
			if ph >= 170 and ph < 190: btp = POSES.aim
			if ph >= 190 and ph - dt < 190:
				b.vy = -6.9; b.vx = clampf(d / 45.0, -3.9, 3.9); b.gr = false
		else:
			btp = POSES.air
			b.vy += .225 * dt; b.x += b.vx * dt; b.y += b.vy * dt
			if b.y >= GY:
				b.y = float(GY); b.gr = true; shake = 10.0
				part(bc.x, GY, L.en.r, 20, 4.5)
				play("slam")
				if P.gr and P.y >= GY and abs(d) < 70: hurt(b.x)
		b.x = clampf(b.x, 30, LEN - 30)
		lerp_pose(b.pose, btp, .25)
		var hd := pc.distance_to(bc)
		if atk and hd < 45:
			if b.inv <= 0:
				var dm := 2 if P.lt > 0 else 1
				b.hp -= dm; b.inv = 16.0; hs = 8; shake = 7.0; kf = 10
				part(bc.x, bc.y, Color("#d0102a"), 14); part(bc.x, bc.y, L.col.r, 10)
				blood(bc.x, bc.y, 12)
				if P.lt > 0: bolt(bc.x, bc.y - 45, bc.x, bc.y + 15)
				score += 25 * dm
				raijin = min(100.0, raijin + 8)
				P.ch = 2; P.vy = -3.3
				play("hit", .8)
		elif hd < 30 and P.dash <= 0:
			hurt(b.x)
		if b.hp <= 0:
			part(bc.x, bc.y, Color("#d0102a"), 60, 6); part(bc.x, bc.y, Color.BLACK, 40, 6)
			fx.append({"k": "corpse", "x": b.x, "y": b.y, "pose": b.pose.duplicate(), "f": b.f, "vx": P.dx * 3, "vy": -4.5, "rot": 0.0, "vr": .08, "l": 90.0, "sc": 2.0})
			boss = null
			shake = 20.0; hs = 40; kf = 30; score += 500; ar.clear()
			play("thunder", .7)
			for e2 in en: kill(e2)
			en.clear()
	# raijin
	if P.lt > 0:
		P.lt -= 1
		if randf() < .15: bolt(P.x + (randf() - .5) * 20, P.y - 38, P.x + (randf() - .5) * 20, P.y)
	# fx
	i = fx.size() - 1
	while i >= 0:
		var f: Dictionary = fx[i]
		i -= 1
		var slow: bool = f.k in ["ghost", "corpse", "p", "blood", "text"]
		f.l -= dt if slow else 1.0
		match f.k:
			"corpse":
				f.x += f.vx * dt; f.y = min(float(GY), f.y + f.vy * dt); f.vy += .27 * dt; f.rot += f.vr * dt
				if f.y >= GY: f.vr *= .5; f.vx *= .8
			"p", "blood":
				f.x += f.vx * dt; f.y += f.vy * dt; f.vy += .22 * dt
			"text":
				f.y += f.vy * dt
		if f.l <= 0: fx.erase(f)
	cam += (clampf(P.x - W * .42, 0, LEN - W) - cam) * .12
	if en.is_empty() and boss == null and not clear:
		clear = 1; mt = 100; hs = 20
		msg = "THE DEMON LORD FALLS" if lv == 3 else "PATH CLEARED"
	if clear:
		clear += 1
		if clear > 110:
			if lv == 3:
				st = "win"; _save_best()
			else:
				var hp: int = 5
				_load_level(lv + 1)
				P.hp = hp

# ------------------------------------------------------------ drawing helpers
func px(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(round(x), round(y), w, h), c)

func ln(x0: float, y0: float, x1: float, y1: float, c: Color, w := 1.0) -> void:
	var n: int = max(1, int(Vector2(x1 - x0, y1 - y0).length()))
	for i in n + 1:
		var t := float(i) / n
		draw_rect(Rect2(round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t), w, w), c)

func txt(t: String, X: float, Y: float, c: Color, size := 10, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var wdt := -1.0
	var x0 := X
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		wdt = W; x0 = X - W / 2.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		wdt = X; x0 = 0
	draw_string(font, Vector2(x0 + 1, Y + 1), t, align, wdt, size, Color(0, 0, 0, c.a))
	draw_string(font, Vector2(x0, Y), t, align, wdt, size, c)

# Skeletal ninja. X0,Y0 = feet. col: {s,m,r}. opt: horns, eye, dash, mono, rot
func ninja(X0: float, Y0: float, f: bool, po: Dictionary, col: Dictionary, sw: String, swt: float, opt := {}) -> void:
	var sc: float = opt.get("sc", 1.0)
	var rot: float = opt.get("rot", 0.0)
	draw_set_transform_matrix(xf * Transform2D(rot, Vector2(sc, sc), 0.0, Vector2(round(X0), round(Y0))))
	var d := -1.0 if f else 1.0
	var TH := 9.0; var SH := 9.0; var UA := 6.0; var FA := 6.0; var TOR := 12.0
	var mono: bool = opt.get("mono", false)
	var cs: Color = col.s; var cm: Color = col.get("m", col.s); var cr: Color = col.r
	if mono:
		cs = col.r; cm = col.r
	var legH := func(a: float, k: float) -> float: return cos(a) * TH + cos(a + k) * SH
	var hx := 0.0
	var hy: float = -maxf(legH.call(po.fa, po.fk), legH.call(po.ba, po.bk))
	var sx := hx + d * sin(po.lean) * TOR
	var sy := hy - cos(po.lean) * TOR
	var nx := sx + d * sin(po.lean) * 4.5
	var ny := sy - cos(po.lean) * 4.5
	if opt.get("player", false):
		NS = xf * Vector2(X0 + sx * sc, Y0 + sy * sc)
	var t := tnow * 8.0
	var P2 := func(px0: float, py0: float, a: float, l: float) -> Vector2: return Vector2(px0 + d * sin(a) * l, py0 + cos(a) * l)
	# scarf
	for i in range(1, 10):
		px(sx - d * (i * 2.2), sy - 2 + i * .5 + sin(t + i * .7) * 1.2, 3 if i < 4 else 2, 1 if i > 6 else 2, cr)
	# back arm, back leg
	_arm(P2, sx, sy, po.sb, po.eb, cm, UA, FA)
	_leg(P2, hx, hy, po.ba, po.bk, cm, TH, SH, d)
	# scabbard
	var mx := hx + d * 3; var my := hy - 1.5
	var sa: float = -1.15 + po.lean * .4
	var se: Vector2 = P2.call(mx, my, sa, 18.0)
	ln(mx, my, se.x, se.y, cm, 2)
	px(se.x, se.y, 2, 1, cr)
	# torso
	ln(hx, hy, sx, sy, cs, 4)
	ln(hx + d * 1.5, hy - 3, sx + d * 1.5, sy + 3, cs, 3)
	# sash + knot tails
	px(hx - 3, hy - 1.5, 7, 2, cr)
	px(hx - d * 4.5, hy, 1, 3, cr)
	px(hx - d * 6, hy + 1 + sin(t) * .8, 1, 3, cr)
	# front leg
	_leg(P2, hx, hy, po.fa, po.fk, cs, TH, SH, d)
	# head
	px(nx - 2, ny - 2, 5, 6, cs)
	px(nx - 3, ny, 7, 3, cs)
	if opt.get("horns", false):
		px(nx - 3, ny - 3, 7, 3, cs)
		px(nx - 3, ny - 1, 7, 1, cr)
		px(nx - d * 5, ny - 1 + sin(t) * .8, 2, 1, cr)
		px(nx - d * 6, ny + sin(t + 1), 1, 2, cr)
		px(nx - d * 3, ny - 6, 1, 3, cr); px(nx - d * 4, ny - 7, 1, 1, cr)
		px(nx + d * 3, ny - 6, 1, 3, cr); px(nx + d * 4, ny - 7, 1, 1, cr)
	else:
		px(nx - 8, ny - 3, 17, 1, cs)
		px(nx - 5, ny - 4, 11, 1, cs)
		px(nx - 3, ny - 5, 7, 1, cs)
		px(nx - 1, ny - 6, 3, 1, cs)
		px(nx - 1, ny - 6, 3, 1, cr); px(nx - 5, ny - 4, 3, 1, cr)
		px(nx - 8, ny - 3, 1, 1, cr); px(nx + 8, ny - 3, 1, 1, cr)
	px(nx + d * 1.5, ny, 2 if not f else 1, 1, opt.get("eye", cr))
	# front arm + sword
	var hd: Vector2 = _arm(P2, sx, sy, po.sf, po.ef, cs, UA, FA)
	if sw == "in":
		ln(mx, my, mx + d * 4, my - 3, cs, 2)
		px(mx, my - 1, 1, 3, cr)
	elif sw == "sh":
		var p := minf(1.0, swt / 16.0)
		var L := 20.0 * (1.0 - p)
		var u := Vector2(-d * sin(sa), -cos(sa))
		var tip := Vector2(mx, my) + u * L
		ln(mx, my, tip.x, tip.y, Color.WHITE if not mono else cr)
		ln(tip.x, tip.y, tip.x + u.x * 4, tip.y + u.y * 4, cs, 2)
		px(tip.x, tip.y, 1, 1, cr)
	else:
		var a: float = po.sf + po.ef + (.3 if not opt.get("dash", false) else 0.0)
		var bx := hd.x + d * sin(a) * 21
		var by := hd.y + cos(a) * 21
		ln(hd.x - d * sin(a) * 4, hd.y - cos(a) * 4, hd.x, hd.y, cs, 2)
		ln(hd.x, hd.y, bx, by, Color.WHITE if not mono else cr)
		ln(hd.x, hd.y + 1, bx, by + 1, cr)
	draw_set_transform_matrix(xf)

func _leg(P2: Callable, hx: float, hy: float, a: float, k: float, c: Color, TH: float, SH: float, d: float) -> void:
	var kn: Vector2 = P2.call(hx, hy, a, TH)
	var ft: Vector2 = P2.call(kn.x, kn.y, a + k, SH)
	ln(hx, hy, kn.x, kn.y, c, 3)
	ln(kn.x, kn.y, ft.x, ft.y, c, 2)
	px(ft.x - (2 if d < 0 else 0), ft.y + 1, 4, 1, c)

func _arm(P2: Callable, sx: float, sy: float, a: float, e: float, c: Color, UA: float, FA: float) -> Vector2:
	var el: Vector2 = P2.call(sx, sy + 1, a, UA)
	var hd: Vector2 = P2.call(el.x, el.y, a + e, FA)
	ln(sx, sy + 1, el.x, el.y, c, 2)
	ln(el.x, el.y, hd.x, hd.y, c, 2)
	return hd

func para(tex: Texture2D, p: float) -> void:
	var o := fposmod(cam * p, LW)
	draw_texture(tex, Vector2(-round(o), 0))
	draw_texture(tex, Vector2(LW - round(o), 0))

# ------------------------------------------------------------ render
func _draw() -> void:
	var L: Dictionary = LV[lv]
	var shk := Vector2((randf() - .5) * shake, (randf() - .5) * shake) if shake > 0 else Vector2.ZERO
	zm += ((1.22 if aiming else (1.08 if kf > 0 else 1.0)) - zm) * .15
	var z := Vector2(clampf(P.x - cam, 60, W - 60), P.y - 18)
	var zoom := Transform2D(0.0, Vector2(zm, zm), 0.0, z + shk.round()) * Transform2D(0.0, Vector2.ONE, 0.0, -z)
	xf = Transform2D.IDENTITY
	draw_set_transform_matrix(xf)
	draw_texture(L.sky, Vector2.ZERO)
	draw_set_transform_matrix(zoom)
	para(L.far, .15)
	if L.fog: draw_rect(Rect2(-40, -40, W + 80, H + 80), Color("#e6e6e1", .4))
	para(L.mid, .4)
	if L.fog: draw_rect(Rect2(-40, 110, W + 80, H), Color("#dcdcd7", .27))
	para(L.near, .7)
	para(L.gnd, 1.0)
	if st == "title":
		xf = zoom * Transform2D(0.0, Vector2.ONE, 0.0, Vector2(-cam, 0))
		ninja(W / 2.0, GY, false, POSES.idle, L.col, "in", 0.0)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		draw_rect(Rect2(0, 40, W, 74), Color(0, 0, 0, .45))
		txt("INUKI", W / 2.0, 82, L.col.r, 36)
		txt("the tale of a ninja", W / 2.0, 102, Color("#dddddd"), 12)
		txt("A/D move  -  hold MOUSE to aim, release to strike  -  E / SPACE: Raijin  -  F fullscreen", W / 2.0, 140, Color("#cccccc"), 8)
		txt("press any key", W / 2.0, 250, Color.WHITE if int(tnow * 2.5) % 2 else L.col.r, 12)
		return
	if aiming: draw_rect(Rect2(-40, -40, W + 80, H + 80), Color(0, 0, 0, .3))
	xf = zoom * Transform2D(0.0, Vector2.ONE, 0.0, Vector2(-round(cam), 0))
	draw_set_transform_matrix(xf)
	# platforms
	for p in plats:
		if p.x > cam + W or p.x + p.w < cam: continue
		draw_rect(Rect2(p.x, p.y, p.w, 5), L.ground)
		draw_rect(Rect2(p.x + 4, p.y + 5, 3, GY - p.y - 5), Color(L.ground, .8))
		draw_rect(Rect2(p.x + p.w - 7, p.y + 5, 3, GY - p.y - 5), Color(L.ground, .8))
		draw_rect(Rect2(p.x + 1, p.y + 5, p.w - 2, 1), Color(L.ground, .8))
		draw_rect(Rect2(p.x, p.y, p.w, 1), Color(L.col.r, .6))
	# ghosts
	for f in fx:
		if f.k == "ghost":
			ninja(f.x, f.y, f.f, f.pose, {"s": Color(L.col.r, f.l / 22.0), "r": Color(L.col.r, f.l / 22.0)}, "out", 0.0, {"mono": true})
	# corpses
	for f in fx:
		if f.k == "corpse":
			var a := minf(1.0, f.l / 20.0)
			ninja(f.x, f.y, f.f, f.pose, {"s": Color(L.en.s, a), "m": Color(L.en.m, a), "r": Color(L.en.r, a)}, "in", 0.0, {"horns": true, "eye": Color("#400000", a), "sc": f.sc, "rot": f.rot})
	# enemies
	for e in en:
		var warn: bool = (e.wind > 0 and int(tnow * 16) % 2 == 0) or (e.inv > 0 and int(tnow * 25) % 2 == 0)
		var col: Dictionary = {"s": L.en.s, "m": L.en.s, "r": Color.WHITE} if warn else L.en
		ninja(e.x, e.y, e.f, e.pose, col, "in" if e.type == "t" else "out", 0.0, {"horns": true, "eye": Color.WHITE if warn else L.en.e, "dash": e.strike > 0})
		if e.type == "m" and e.hp > 1:
			px(e.x - 4, e.y - 48, 3, 1, L.en.e); px(e.x + 1, e.y - 48, 3, 1, L.en.e)
	# shuriken
	for a in ar:
		for j in 4:
			var an: float = a.r + j * 1.571
			px(a.x + cos(an) * 3, a.y + sin(an) * 3, 1, 1, Color("#dddddd"))
			px(a.x + cos(an) * 4.8, a.y + sin(an) * 4.8, 1, 1, Color("#dddddd"))
		px(a.x, a.y, 2, 2, L.en.e)
	# boss
	if boss != null and not (boss.inv > 0 and int(tnow * 20) % 2 == 0):
		ninja(boss.x, boss.y, boss.f, boss.pose, {"s": Color("#050203"), "m": Color("#1a0a0e"), "r": Color("#ff3040")}, "out", 0.0, {"horns": true, "eye": Color("#ffee55"), "sc": 2.0})
	# lightning bolts
	for f in fx:
		if f.k == "bolt":
			var a: float = f.l / 10.0
			for j in range(1, f.pts.size()):
				ln(f.pts[j - 1].x, f.pts[j - 1].y, f.pts[j].x, f.pts[j].y, Color("#bbffff", a), 2)
				ln(f.pts[j - 1].x, f.pts[j - 1].y, f.pts[j].x, f.pts[j].y, Color(1, 1, 1, a))
	# dash streaks
	for f in fx:
		if f.k == "streak":
			var a := minf(1.0, f.l / 10.0)
			ln(f.x0, f.y0, f.x1, f.y1, Color(Color("#99ffff") if P.lt > 0 else L.col.r, a), 3)
			ln(f.x0, f.y0 + 1, f.x1, f.y1 + 1, Color(1, 1, 1, a))
	# player
	if not (P.inv > 0 and int(P.inv) % 6 < 3):
		var lc: Dictionary = L.col
		if P.lt > 0:
			lc = {"s": Color("#05080f"), "m": Color("#1a2a40"), "r": Color("#99ffff") if int(tnow * 20) % 3 else Color.WHITE}
		var mv: bool = abs(P.vx) > .4 and P.gr
		var bob := .8 if (not mv and P.gr and not aiming and int(tnow * 1.6) % 2) else 0.0
		ninja(P.x, P.y + bob, P.f, P.pose, lc, P.sw, P.swt, {"dash": P.dash > 0, "player": true})
		if P.slash > 0:
			var d := -1.0 if P.f else 1.0
			var t: float = 1.0 - P.slash / 14.0
			var sw0 := xf.affine_inverse() * NS
			var hx := sw0.x; var hy := sw0.y + 3
			var a := -1.9 + minf(1.0, t * 1.6) * 3.2
			var aa := maxf(-1.9, a - 1.6)
			while aa <= a:
				var al := 1.0 - (a - aa) / 1.6
				var c: Color = Color.WHITE if al > .7 else (Color("#99ffff") if P.lt > 0 else L.col.r)
				c.a = al * (1.0 - t * .6)
				for rr in [22.0, 25.0, 28.0]:
					px(hx + d * cos(aa) * rr, hy + sin(aa) * rr, 1, 1, c)
				aa += .05
			ln(hx, hy, hx + d * cos(a) * 29, hy + sin(a) * 29, Color.WHITE)
	for j in P.ch:
		px(P.x - 4 + j * 6, P.y - 46, 3, 3, L.col.r)
	# aim guide
	if aiming:
		var ad := aim_dir()
		var pc := PC()
		var i := 9
		while i < 96:
			var c: Color = Color.WHITE if i % 12 == 9 else L.col.r
			c.a = 1.0 - i / 120.0
			px(pc.x + ad.x * i, pc.y + ad.y * i, 2, 2, c)
			i += 6
		var e := pc + ad * 99
		var nrm := Vector2(-ad.y, ad.x)
		ln(e.x - ad.x * 5 + nrm.x * 5, e.y - ad.y * 5 + nrm.y * 5, e.x, e.y, Color.WHITE)
		ln(e.x - ad.x * 5 - nrm.x * 5, e.y - ad.y * 5 - nrm.y * 5, e.x, e.y, Color.WHITE)
	# particles & text
	for f in fx:
		if f.k == "p":
			px(f.x, f.y, 2, 2, f.c)
		elif f.k == "text":
			draw_set_transform_matrix(xf)
			draw_string(font, Vector2(f.x - 20, f.y), f.t, HORIZONTAL_ALIGNMENT_CENTER, 40, 10, L.col.r)
	# kill flash: white wash, then blood on top
	if kf > 0:
		draw_set_transform_matrix(Transform2D.IDENTITY)
		draw_rect(Rect2(0, 0, W, H), Color(1, .98, .96, minf(.75, kf / 24.0 * .9)))
		draw_set_transform_matrix(xf)
	for f in fx:
		if f.k == "blood":
			px(f.x, f.y, f.sz, f.sz, f.c)
	# weather
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if L.rain:
		for j in 120:
			var rx := fposmod(j * 53 + tnow * 240 * ts, W)
			var ry := fposmod(j * 97 + tnow * 450 * ts, H)
			draw_rect(Rect2(int(rx), int(ry), 1, 6), Color(.62, .84, .88, .5))
		for j in 16:
			px(fposmod(j * 71 + tnow * 30, W), H - fposmod(j * 37 + tnow * 60, H), 1, 1, Color("#ff9a40"))
	if L.fog:
		for j in 8:
			draw_rect(Rect2(int(fposmod(j * 110 - tnow * 20, W + 200)) - 100, 130 + j * 9, 200, 12), Color(1, 1, 1, .08))
	if lv < 2:
		for j in 20:
			px(fposmod(j * 41 + tnow * 25 + sin(tnow * 2 + j) * 14, W), fposmod(j * 29 + tnow * 40, H), 1, 1, Color(L.col.r, .7))
	if P.lt > 0:
		draw_rect(Rect2(0, 0, W, H), Color(.47, .78, 1, .06 + randf() * .04))
	for f in fx:
		if f.k == "flash":
			draw_rect(Rect2(0, 0, W, H), Color(.75, .94, 1, f.l / 16.0) if f.get("blue", false) else Color(1, 1, 1, f.l / 24.0))
	# HUD
	for j in 5:
		draw_rect(Rect2(6 + j * 10, 6, 7, 7), L.col.r if j < P.hp else Color(1, 1, 1, .13))
	draw_rect(Rect2(6, 17, 62, 5), Color(0, 0, 0, .55))
	var rv: float = (P.lt / 540.0 * 100.0) if P.lt > 0 else raijin
	var rc := Color("#99ffff") if P.lt > 0 else (Color.WHITE if (raijin >= 100 and int(tnow * 10) % 2) else Color("#66ccff"))
	draw_rect(Rect2(7, 18, rv * .6, 3), rc)
	txt("RAIJIN x2" if P.lt > 0 else ("RAIJIN READY  [E]" if raijin >= 100 else "RAIJIN"), 74, 23, Color("#99ffff"), 9, HORIZONTAL_ALIGNMENT_LEFT)
	draw_rect(Rect2(6, 25, 62, 3), Color(0, 0, 0, .55))
	draw_rect(Rect2(7, 26, P.fo * .6, 1), Color("#bbddff"))
	txt(str(score), W - 6, 14, Color.WHITE, 12, HORIZONTAL_ALIGNMENT_RIGHT)
	if boss == null:
		txt("ninjas " + str(en.size()), W - 6, 27, Color("#bbbbbb"), 9, HORIZONTAL_ALIGNMENT_RIGHT)
	if combo > 1:
		txt(str(combo) + " CHAIN", W / 2.0, 30, L.col.r, 12 if combo < 8 else 18)
	if boss != null:
		draw_rect(Rect2(W - 216, 22, 210, 6), Color(0, 0, 0, .55))
		draw_rect(Rect2(W - 215, 23, max(0.0, 208.0 * boss.hp / boss.mhp), 4), Color("#ff3040"))
		txt("KAGE, THE DEMON LORD", W - 6, 40, Color("#ff3040"), 9, HORIZONTAL_ALIGNMENT_RIGHT)
	if mt > 0:
		var a := minf(1.0, mt / 30.0)
		draw_rect(Rect2(0, 80, W, 34), Color(0, 0, 0, .45 * a))
		txt(msg, W / 2.0, 104, Color(1, 1, 1, a), 18)
	if st == "over" or st == "win":
		draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, .72))
		txt("THE DEMON LORD FALLS" if st == "win" else "YOU HAVE FALLEN", W / 2.0, 110, L.col.r, 24)
		txt("score " + str(score) + "    best " + str(best), W / 2.0, 140, Color.WHITE, 12)
		txt("press any key to play again" if st == "win" else "press any key to retry this level", W / 2.0, 170, Color("#aaaaaa"), 10)
