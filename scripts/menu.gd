class_name GameMenu
extends CanvasLayer
## Hlavní menu, pauza a nastavení. Celé UI se staví v kódu.
## Hodnoty drží slovník `s` (sdílený s main.gd), změna vyvolá signál `changed`.

signal changed(key: String)
signal play_pressed
signal resume_pressed
signal quit_pressed
signal host_pressed(display_name: String, port: int, automatic_port: bool)
signal join_pressed(display_name: String, address: String, port: int)
signal disconnect_pressed
signal copy_connection_pressed

const PRESETS := {
	0: {"upscale": 3, "gi": false, "ssr": false, "volumetric": false, "planar": 0, "ao": true, "dof": false, "shadows": 1, "dust": false},
	1: {"upscale": 2, "gi": true, "ssr": false, "volumetric": true, "planar": 1, "ao": true, "dof": true, "shadows": 2, "dust": true},
	2: {"upscale": 0, "gi": true, "ssr": true, "volumetric": true, "planar": 1, "ao": true, "dof": true, "shadows": 3, "dust": true},
	3: {"upscale": 1, "gi": true, "ssr": true, "volumetric": true, "planar": 2, "ao": true, "dof": true, "shadows": 4, "dust": true},
}

var s: Dictionary
var is_open := false
var in_game := false

var _root: Control
var _dim: ColorRect
var _main_box: VBoxContainer
var _settings_box: Control
var _play_btn: Button
var _title: Label
var _sub: Label
var _refresh: Array[Callable] = []
var _muting := false
var _multiplayer_box: PanelContainer
var _network_status: Label
var _host_btn: Button
var _join_btn: Button
var _disconnect_btn: Button
var _copy_btn: Button
var _network_active := false
var _intro: Tween
var _footer: Label
var _tabs: TabContainer
const CustomizeScript := preload("res://scripts/customize_panel.gd")
var _customize: Control

func add_tab(title: String) -> VBoxContainer:
	# Další záložka nastavení zvenku (testování).
	return _tab(_tabs, title)

func _init(settings: Dictionary) -> void:
	s = settings
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	_root = Control.new()
	_root.theme = _make_theme()
	add_child(_root)
	_dim = ColorRect.new()
	_dim.color = Color.WHITE
	var atmosphere := ShaderMaterial.new()
	atmosphere.shader = load("res://shaders/menu_atmosphere.gdshader")
	_dim.material = atmosphere
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_dim)

	# --- hlavní sloupec
	_main_box = VBoxContainer.new()
	_main_box.position = Vector2(140, 220)
	_main_box.custom_minimum_size = Vector2(480, 0)
	_main_box.add_theme_constant_override("separation", 14)
	_root.add_child(_main_box)
	_title = Label.new()
	_title.text = "HLADINA"
	_title.add_theme_font_size_override("font_size", 96)
	_main_box.add_child(_title)
	_sub = Label.new()
	_sub.text = "Y O U   A R E   N O T   A L O N E   D O W N   H E R E"
	_sub.add_theme_color_override("font_color", Color(0.75, 0.9, 0.92, 0.75))
	_main_box.add_child(_sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 50)
	_main_box.add_child(gap)
	_play_btn = _button(_main_box, "Enter the baths", func():
		if in_game:
			resume_pressed.emit()
		else:
			play_pressed.emit())
	_button(_main_box, "Settings", func(): _show_settings(true))
	_button(_main_box, "Customize", func(): _show_customize(true))
	_button(_main_box, "Multiplayer", func(): _show_multiplayer(true))
	_button(_main_box, "Quit", func(): quit_pressed.emit())
	_footer = Label.new()
	_footer.text = ""
	_footer.position = Vector2(140, 910)
	_footer.add_theme_font_size_override("font_size", 18)
	_footer.modulate = Color(0.58, 0.69, 0.67, 0.85)
	_root.add_child(_footer)
	_build_multiplayer()
	_customize = CustomizeScript.new(s)
	_customize.visible = false
	_customize.changed.connect(func(key: String, value: Variant): _change(key, value))
	_customize.closed.connect(func(): _show_customize(false))
	_root.add_child(_customize)

	# --- nastavení
	_settings_box = PanelContainer.new()
	_settings_box.position = Vector2(150, 110)
	_settings_box.custom_minimum_size = Vector2(980, 820)
	_settings_box.visible = false
	_root.add_child(_settings_box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_settings_box.add_child(vb)
	var head := Label.new()
	head.text = "Nastavení"
	head.add_theme_font_size_override("font_size", 40)
	vb.add_child(head)
	var tabs := TabContainer.new()
	_tabs = tabs
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(tabs)

	var t := _tab(tabs, "Obraz")
	_opt(t, "Režim okna", "window", [["Celá obrazovka", 0], ["Okno", 1]])
	_check(t, "Vertikální synchronizace", "vsync")
	_opt(t, "Vykreslování / upscaling", "upscale", [["Nativní rozlišení + TAA", 0], ["FSR 2.2 nativní (nejostřejší)", 1],
		["FSR 2.2 kvalita (77 %)", 2], ["FSR 2.2 vyvážený (67 %)", 3], ["FSR 2.2 výkon (50 %)", 4], ["Vlastní měřítko + TAA", 5]])
	_slider(t, "Měřítko rozlišení (50–200 %)", "resolution_scale", 50.0, 200.0, 5.0, "%d %%")
	_opt(t, "Limit FPS", "fps_limit", [["Neomezeně", 0], ["30 FPS", 30], ["60 FPS", 60], ["75 FPS", 75], ["90 FPS", 90], ["120 FPS", 120], ["144 FPS", 144], ["165 FPS", 165], ["180 FPS", 180], ["240 FPS", 240], ["360 FPS", 360]])
	_slider(t, "Doostření", "sharpen", 0.0, 1.0, 0.05)
	_slider(t, "Jas", "brightness", 0.5, 2.0, 0.05)
	_slider(t, "Kontrast", "contrast", 0.6, 1.6, 0.02)
	_slider(t, "Gama (nižší = tmavší střední tóny)", "gamma", 0.6, 1.6, 0.02)
	_slider(t, "Zorné pole", "fov", 60.0, 100.0, 1.0, "%d°")
	_check(t, "Zobrazit FPS", "show_fps")

	t = _tab(tabs, "Grafika")
	_opt(t, "Celková kvalita", "preset", [["Nízká", 0], ["Střední", 1], ["Vysoká", 2], ["Ultra", 3], ["Vlastní", 4]])
	_check(t, "Globální osvětlení (SDFGI)", "gi")
	_check(t, "Odrazy na dlaždicích (SSR)", "ssr")
	_opt(t, "Odrazy na vodě", "planar", [["Vypnuto", 0], ["Poloviční rozlišení", 1], ["Plné rozlišení", 2]])
	_check(t, "Světelné paprsky (volumetrika)", "volumetric")
	_slider(t, "Síla světelných paprsků", "rays_strength", 0.0, 2.0, 0.05)
	_check(t, "Prach ve světle", "dust")
	_check(t, "Odlesky vody na stěnách", "water_glow")
	_opt(t, "Stíny", "shadows", [["Tvrdé", 0], ["Nízké", 1], ["Střední", 2], ["Vysoké", 3], ["Ultra", 4]])
	_check(t, "Ambient occlusion + SSIL", "ao")
	_slider(t, "Bloom", "bloom", 0.0, 1.0, 0.05)
	_check(t, "Hloubka ostrosti", "dof")
	_slider(t, "Zrno", "grain", 0.0, 1.0, 0.05)
	_slider(t, "Vinětace", "vignette", 0.0, 1.0, 0.05)

	t = _tab(tabs, "Kamera")
	_opt(t, "Perspektiva (klávesa P)", "perspective", [["První osoba", 0], ["Třetí osoba přes rameno", 1]])
	_slider(t, "Citlivost myši", "mouse", 0.2, 3.0, 0.05, "%.2f")
	_slider(t, "Filmový pohyb kamery (0 = vypnuto)", "camera_motion", 0.0, 1.5, 0.05)
	_slider(t, "Houpání při chůzi", "bob", 0.0, 1.5, 0.05)
	_slider(t, "Kývání a váha zbraně (bez míření)", "gun_sway", 0.0, 2.0, 0.05)
	_slider(t, "Houpání zbraně při míření a držení R (0 = vypnuto)", "aim_sway", 0.0, 1.0, 0.05)
	_slider(t, "Třes ruční kamery", "shake", 0.0, 2.0, 0.05)
	_check(t, "VHS kamera  (klávesa V)", "vhs")
	_check(t, "Rybí oko  (klávesa G)", "fisheye")
	_check(t, "Zaměřovač", "crosshair_on")
	_check(t, "Hitmarker při zásahu (křížek)", "hitmarker")
	_check(t, "Zvuk zásahu", "hit_sound")
	_slider(t, "Velikost světla baterky", "flash_size", 15.0, 70.0, 1.0, "%d°")
	_check(t, "Baterka občas problikne", "flash_flicker")
	_slider(t, "Síla rybího oka", "fisheye_strength", 0.0, 1.0, 0.05)
	_section(t, "Minimapa  (drž M nebo Tab)")
	_slider(t, "Přiblížení (kolik metrů kolem tebe)", "mini_range", 8.0, 60.0, 1.0, "%d m")
	_slider(t, "Velikost", "mini_size", 160.0, 560.0, 10.0, "%d px")
	_opt(t, "Pozice", "mini_pos", [["Vpravo nahoře", 0], ["Nahoře uprostřed", 4], ["Vlevo nahoře", 1], ["Vlevo uprostřed", 5],
		["Vlevo dole", 2], ["Dole uprostřed", 6], ["Vpravo dole", 3], ["Vpravo uprostřed", 7]])
	_slider(t, "Tloušťka čar", "mini_line", 1.0, 5.0, 1.0, "%d")
	_slider(t, "Odsazení od okraje", "mini_margin", 0.0, 300.0, 5.0, "%d px")

	t = _tab(tabs, "3. osoba")
	_slider(t, "Vzdálenost kamery", "tp_distance", 1.2, 5.0, 0.1, "%.1f m")
	_slider(t, "Odsazení od ramene", "tp_offset", 0.0, 1.0, 0.05, "%.2f m")
	_slider(t, "Výška kamery", "tp_height", 0.9, 1.9, 0.05, "%.2f m")
	_opt(t, "Rameno (klávesa Q)", "tp_side", [["Pravé", 0], ["Levé", 1]])
	_slider(t, "Zorné pole třetí osoby", "tp_fov", 55.0, 95.0, 1.0, "%d°")
	_slider(t, "Plynulost návratu kamery", "tp_smoothing", 0.0, 1.0, 0.05)

	t = _tab(tabs, "Zvuk")
	_slider(t, "Hlasitost", "volume", 0.0, 1.0, 0.02)
	_slider(t, "Hudba", "music", 0.0, 1.0, 0.02)

	t = _tab(tabs, "Hra")
	_section(t, "Herní režim")
	_check(t, "Hororový režim (bez bodů, málo munice, rány se samy nezahojí, méně ale silnějších zombie)", "horror")
	_check(t, "Úvodní briefing při spuštění hry", "intro")
	t = _tab(tabs, "Zbraně")
	_slider(t, "Zpětný ráz", "recoil", 0.0, 2.0, 0.05, "%.2f×")
	_slider(t, "Všechny zbraně – hlasitost", "gun_master", -12.0, 12.0, 0.5, "%+.1f dB")
	_slider(t, "Všechny zbraně – basy", "gun_bass", -6.0, 12.0, 0.5, "%+.1f dB")
	_slider(t, "Všechny zbraně – ozvěna", "gun_echo", 0.0, 2.0, 0.05, "%.2f×")
	_section(t, "AK-47")
	_slider(t, "  Hlasitost", "gun_ak_vol", -12.0, 12.0, 0.5, "%+.1f dB")
	_slider(t, "  Basy", "gun_ak_bass", -6.0, 12.0, 0.5, "%+.1f dB")
	_slider(t, "  Ozvěna", "gun_ak_echo", 0.0, 1.0, 0.05)
	_slider(t, "  Výška tónu", "gun_ak_pitch", 0.8, 1.2, 0.01, "%.2f×")
	_section(t, "MP 40")
	_slider(t, "  Hlasitost", "gun_mp40_vol", -12.0, 12.0, 0.5, "%+.1f dB")
	_slider(t, "  Basy", "gun_mp40_bass", -6.0, 12.0, 0.5, "%+.1f dB")
	_slider(t, "  Ozvěna", "gun_mp40_echo", 0.0, 1.0, 0.05)
	_slider(t, "  Výška tónu", "gun_mp40_pitch", 0.8, 1.2, 0.01, "%.2f×")
	_section(t, "IŽ-54")
	_slider(t, "  Hlasitost", "gun_izh54_vol", -12.0, 12.0, 0.5, "%+.1f dB")
	_slider(t, "  Basy", "gun_izh54_bass", -6.0, 12.0, 0.5, "%+.1f dB")
	_slider(t, "  Ozvěna", "gun_izh54_echo", 0.0, 1.0, 0.05)
	_slider(t, "  Výška tónu", "gun_izh54_pitch", 0.8, 1.2, 0.01, "%.2f×")
	_section(t, "Desert Eagle")
	_slider(t, "  Hlasitost", "gun_deagle_vol", -12.0, 12.0, 0.5, "%+.1f dB")
	_slider(t, "  Basy", "gun_deagle_bass", -6.0, 12.0, 0.5, "%+.1f dB")
	_slider(t, "  Ozvěna", "gun_deagle_echo", 0.0, 1.0, 0.05)
	_slider(t, "  Výška tónu", "gun_deagle_pitch", 0.8, 1.2, 0.01, "%.2f×")

	var back := _button(vb, "Zpět", func(): _show_settings(false))
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.custom_minimum_size = Vector2(220, 52)
	_root.visible = false

func _build_multiplayer() -> void:
	_multiplayer_box = PanelContainer.new()
	_multiplayer_box.position = Vector2(150, 100)
	_multiplayer_box.custom_minimum_size = Vector2(1080, 850)
	_multiplayer_box.visible = false
	_root.add_child(_multiplayer_box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	_multiplayer_box.add_child(vb)
	var heading := Label.new()
	heading.text = "Multiplayer · až 4 hráči"
	heading.add_theme_font_size_override("font_size", 38)
	vb.add_child(heading)
	var row := _row(vb, "Tvoje jméno")
	var nick := LineEdit.new()
	nick.max_length = 24
	nick.text = str(s.get("player_name", "Hráč"))
	nick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nick.text_changed.connect(func(value: String): _change("player_name", value))
	row.add_child(nick)
	row = _row(vb, "UDP port (stejný u obou)")
	var port := SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = int(s.get("server_port", 24567))
	port.value_changed.connect(func(value: float): _change("server_port", int(value)))
	row.add_child(port)
	var automatic := CheckBox.new()
	automatic.text = "Zkusit automaticky otevřít port routeru (UPnP)"
	automatic.button_pressed = bool(s.get("automatic_port", true))
	automatic.toggled.connect(func(value: bool): _change("automatic_port", value))
	vb.add_child(automatic)
	_host_btn = _button(vb, "Hostovat novou hru", func(): host_pressed.emit(nick.text, int(port.value), automatic.button_pressed))
	row = _row(vb, "Adresa hostitele (IP / VPN)")
	var address := LineEdit.new()
	address.placeholder_text = "např. 192.168.1.10"
	address.text = str(s.get("server_address", ""))
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address.text_changed.connect(func(value: String): _change("server_address", value))
	row.add_child(address)
	_join_btn = _button(vb, "Připojit se", func(): join_pressed.emit(nick.text, address.text, int(port.value)))
	_network_status = Label.new()
	_network_status.custom_minimum_size = Vector2(980, 135)
	_network_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_network_status.add_theme_color_override("font_color", Color(0.65, 0.94, 0.95))
	_network_status.text = "Host založí hru. Druhý hráč zadá jeho adresu a stejný port."
	_network_status.add_theme_font_size_override("font_size", 22)
	vb.add_child(_network_status)
	var hint := Label.new()
	hint.text = "Stejná Wi-Fi / LAN: použij místní IP hostitele.\nInternet: UPnP nebo přesměrování UDP portu na routeru; případně společná VPN.\nWindows může při prvním hostování požádat o povolení hry ve firewallu."
	hint.add_theme_font_size_override("font_size", 20)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hint)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	vb.add_child(buttons)
	_copy_btn = _button(buttons, "Kopírovat adresy", func(): copy_connection_pressed.emit())
	_disconnect_btn = _button(buttons, "Odpojit / zrušit", func(): disconnect_pressed.emit())
	_button(buttons, "Zpět", func(): _show_multiplayer(false))
	_copy_btn.visible = false
	_disconnect_btn.visible = false

func set_network_state(text: String, active: bool, busy: bool) -> void:
	_network_active = active
	if not text.is_empty(): _network_status.text = text
	_host_btn.disabled = active or busy
	_join_btn.disabled = active or busy
	_disconnect_btn.visible = active or busy
	_copy_btn.visible = active

func _show_multiplayer(value: bool) -> void:
	_multiplayer_box.visible = value
	_main_box.visible = not value
	_settings_box.visible = false
	if _customize: _customize.visible = false

func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 24
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.025, 0.045, 0.045, 0.45)
	normal.border_color = Color(0.85, 0.95, 0.97, 0.35)
	normal.border_width_left = 2
	normal.border_width_bottom = 1
	normal.set_corner_radius_all(0)
	normal.set_content_margin_all(12)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color(0.66, 0.75, 0.66, 0.95)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Color(0.6, 0.85, 0.9, 0.9)
	for cls in ["Button", "OptionButton"]:
		th.set_stylebox("normal", cls, normal)
		th.set_stylebox("hover", cls, hover)
		th.set_stylebox("pressed", cls, pressed)
		var focus := StyleBoxFlat.new()
		focus.bg_color = Color.TRANSPARENT
		focus.border_color = Color(0.8, 0.85, 0.65)
		focus.set_border_width_all(2)
		th.set_stylebox("focus", cls, focus)
		th.set_color("font_color", cls, Color(0.92, 0.97, 0.98))
		th.set_color("font_hover_color", cls, Color(0.04, 0.1, 0.12))
		th.set_color("font_pressed_color", cls, Color(0.04, 0.1, 0.12))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.03, 0.07, 0.08, 0.88)
	panel.border_color = Color(0.85, 0.95, 0.97, 0.2)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(4)
	panel.set_content_margin_all(28)
	th.set_stylebox("panel", "PanelContainer", panel)
	var tabp := StyleBoxFlat.new()
	tabp.bg_color = Color(1, 1, 1, 0.03)
	tabp.set_content_margin_all(18)
	th.set_stylebox("panel", "TabContainer", tabp)
	return th

func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 58)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title.replace(".", "")
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)
	tabs.set_tab_title(tabs.get_tab_count()-1, title)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 10)
	sc.add_child(vb)
	return vb

func _section(tab: VBoxContainer, title: String) -> void:
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
	tab.add_child(l)

func _row(tab: VBoxContainer, label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.custom_minimum_size = Vector2(0, 46)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(430, 0)
	h.add_child(l)
	tab.add_child(h)
	return h

var mini_preview_until := 0     # do kdy ukazovat minimapu nad menu (živý náhled při úpravě)

func _change(key: String, value: Variant) -> void:
	if _muting:
		return
	s[key] = value
	if key.begins_with("mini_"):
		mini_preview_until = Time.get_ticks_msec() + 5000
	if key == "resolution_scale":
		s["upscale"] = 5
		s["preset"] = 4
		changed.emit("upscale")
		refresh()
	elif key == "upscale" and int(value) < 5:
		s["resolution_scale"] = [100.0, 100.0, 77.0, 67.0, 50.0][int(value)]
		refresh()
	if key == "preset" and PRESETS.has(int(value)):
		s["resolution_scale"] = [100.0, 100.0, 77.0, 67.0, 50.0][int(PRESETS[int(value)]["upscale"])]
		for k in PRESETS[int(value)]:
			s[k] = PRESETS[int(value)][k]
			changed.emit(k)
		refresh()
	elif PRESETS[0].has(key) and int(s.get("preset", 4)) != 4:
		s["preset"] = 4
		refresh()
	changed.emit(key)

func _opt(tab: VBoxContainer, label: String, key: String, items: Array) -> void:
	var h := _row(tab, label)
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it in items:
		o.add_item(it[0], int(it[1]))
	o.item_selected.connect(func(i: int): _change(key, o.get_item_id(i)))
	h.add_child(o)
	_refresh.append(func(): o.select(o.get_item_index(int(s[key]))))

func _check(tab: VBoxContainer, label: String, key: String) -> void:
	var h := _row(tab, label)
	var c := CheckButton.new()
	c.toggled.connect(func(v: bool): _change(key, v))
	h.add_child(c)
	_refresh.append(func(): c.set_pressed_no_signal(bool(s[key])))

func _slider(tab: VBoxContainer, label: String, key: String, lo: float, hi: float, step: float, fmt := "%.2f") -> void:
	var h := _row(tab, label)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := Label.new()
	val.custom_minimum_size = Vector2(90, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sl.value_changed.connect(func(v: float):
		val.text = fmt % v
		_change(key, v))
	h.add_child(sl)
	h.add_child(val)
	_refresh.append(func():
		sl.set_value_no_signal(float(s[key]))
		val.text = fmt % float(s[key]))

func refresh() -> void:
	_muting = true
	for r in _refresh:
		r.call()
	_muting = false

func _show_settings(v: bool) -> void:
	_settings_box.visible = v
	_multiplayer_box.visible = false
	if _customize: _customize.visible = false
	_main_box.visible = not v

## Customize: vzhled obleku s živým náhledem postavy.
func _show_customize(v: bool) -> void:
	_customize.visible = v
	_settings_box.visible = false
	_multiplayer_box.visible = false
	_main_box.visible = not v
	if v:
		if _customize._selected != "": _customize._select("")
		_customize.refresh()

func open(game_running: bool) -> void:
	in_game = game_running
	is_open = true
	_play_btn.text = "Resume" if game_running else "Enter the baths"
	_sub.text = ("P A U S E D   ·   S E S S I O N   R U N N I N G" if _network_active else "P A U S E D") if game_running else "Y O U   A R E   N O T   A L O N E   D O W N   H E R E"
	(_dim.material as ShaderMaterial).set_shader_parameter("paused", game_running)
	if _intro: _intro.kill()
	_main_box.modulate.a = 0.0
	_intro = create_tween()
	_intro.tween_property(_main_box, "modulate:a", 1.0, 0.45)
	_show_settings(false)
	refresh()
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	is_open = false
	_root.visible = false

## Esc: z nastavení zpět, jinak (ve hře) pokračovat.
func back() -> void:
	if _settings_box.visible:
		_show_settings(false)
	elif _customize.visible:
		_customize.back()
	elif _multiplayer_box.visible:
		_show_multiplayer(false)
	elif in_game:
		resume_pressed.emit()

func _process(_dt: float) -> void:
	var _perf_t0:=Time.get_ticks_usec()
	_process_timed(_dt)
	PerfMon.add("Menu",Time.get_ticks_usec()-_perf_t0)

func _process_timed(_dt: float) -> void:
	if not is_open:
		return
	var vs := get_viewport().get_visible_rect().size
	var sc := minf(vs.y / 1080.0, vs.x / 1440.0)
	_root.scale = Vector2(sc, sc)
	_root.size = vs / sc
	_footer.visible = _main_box.visible

func _unhandled_input(event: InputEvent) -> void:
	if is_open and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		back()
