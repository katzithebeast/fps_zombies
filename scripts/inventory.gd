extends Node
## Inventář jako v DayZ: I otevře obrazovku s postavou (otáčí se tažením myši), sloty na zbraně
## a malý inventář. Věci se přetahují myší, pravým tlačítkem se použijí, puštěním mimo sloty
## se zahodí na zem. Slot „V rukou“ funguje jako v DayZ: zbraň do něj přetáhneš (vezmeš do ruky)
## a z něj zpět (schováš). Rychlý panel 1–5 se nastavuje v inventáři, klávesy fungují i při hraní.

const Props := preload("res://scripts/props.gd")
const SLOT := 62
const HOT := 5
const ITEMS := {
	"ak":      {"name": "AK-47", "kind": "weapon", "stack": 1},
	"mp40":    {"name": "MP 40", "kind": "weapon", "stack": 1},
	"izh54":   {"name": "IŽ-54", "kind": "weapon", "stack": 1},
	"deagle":  {"name": "Desert Eagle", "kind": "weapon", "stack": 1},
	"syringe": {"name": "Injekce", "kind": "use", "stack": 3, "desc": "Do ruky · levé tlačítko vpíchne · +60 zdraví"},
	"pumpkin": {"name": "Dýňová bomba", "kind": "use", "stack": 2, "desc": "Do ruky · levé tlačítko hodí · láká zombie, pak bouchne"},
	"ammo":    {"name": "Krabice nábojů", "kind": "use", "stack": 2, "desc": "Doplní zásobu všech zbraní"},
	"scrap":   {"name": "Šrot", "kind": "mat", "stack": 30, "desc": "Na pracovní stůl"},
	"parts":   {"name": "Součástky", "kind": "mat", "stack": 15, "desc": "Na pracovní stůl"},
	"chlor":   {"name": "Chlórové tablety", "kind": "mat", "stack": 12, "desc": "Na chlórové náboje"},
	"gears":   {"name": "Ozubené kolo", "kind": "mat", "stack": 20, "desc": "Na vylepšení zbraní u stolu"},
	"fuse":    {"name": "Pojistka", "kind": "quest", "stack": 3, "desc": "Do rozvaděče ve strojovně"},
	"band":    {"name": "Gumový náramek č. 37", "kind": "quest", "stack": 1, "desc": "Klíč od skříňky 37"},
	"uv":      {"name": "UV lampa", "kind": "quest", "stack": 1, "desc": "F přepíná světlo → UV → vypnuto"},
	"wheel":   {"name": "Ventilové kolo", "kind": "quest", "stack": 1, "desc": "Chybí na jednom ventilu"},
	"pumpkey": {"name": "Klíč od čerpadel", "kind": "quest", "stack": 1, "desc": "Síň anděla"},
}
const CONTAINERS := [["weapons", "ZBRANĚ", 4], ["bag", "INVENTÁŘ", 10]]

var main: Node
var slots := {}                 # kontejner -> Array (null nebo {id, count})
var hotbar: Array = []          # 9 × id nebo ""
var ground: Array = []          # zahozené věci: {id, count, node, item}
var is_open := false
var icons := {}

var _layer: CanvasLayer
var _root: Control
var _boxes := {}                # kontejner -> {panel, title, grid}
var _ground_grid: GridContainer
var _hot_box: HBoxContainer
var _hands: Label
var _hands_slot: Slot
var _info: Label
var _preview: SubViewport
var _preview_model: Node3D
var _icon_vp: SubViewport
var _icon_queue: Array = []
var _dirty := true
var _hud_hot: HBoxContainer

func setup(main_node: Node) -> void:
	main = main_node
	for c in CONTAINERS:
		var arr := []
		arr.resize(int(c[2]))
		slots[c[0]] = arr
	hotbar.resize(HOT)
	hotbar.fill("")
	_build_ui()
	_build_icon_baker()
	for id in ITEMS: _icon_queue.append(id)
	_bake_loop.call_deferred()

# ------------------------------------------------------------------ data
func reset() -> void:
	for c in slots: (slots[c] as Array).fill(null)
	hotbar.fill("")
	for g in ground:
		if main.quest and g.item: main.quest._remove(g.item)
	ground.clear()
	_dirty = true

func count(id: String) -> int:
	var n := 0
	for c in slots:
		for s in slots[c]:
			if s != null and s.id == id: n += int(s.count)
	return n

func has(id: String) -> bool:
	return count(id) > 0

func add(id: String, n: int = 1) -> int:
	# Vrátí, kolik se nevešlo (to spadne na zem k hráči).
	if not ITEMS.has(id): return n
	var stack: int = ITEMS[id].stack
	var order := ["weapons"] if ITEMS[id].kind == "weapon" else ["bag"]
	for c in order:
		for s in slots[c]:
			if n <= 0: break
			if s != null and s.id == id and int(s.count) < stack:
				var put := mini(n, stack - int(s.count))
				s.count = int(s.count) + put
				n -= put
	for c in order:
		var arr: Array = slots[c]
		for i in arr.size():
			if n <= 0: break
			if arr[i] == null:
				var put := mini(n, stack)
				arr[i] = {"id": id, "count": put}
				n -= put
	if n > 0 and ITEMS[id].kind != "weapon":
		drop_to_ground(id, n)
		n = 0
	if ITEMS[id].kind in ["weapon", "use"] and not hotbar.has(id):
		var free := hotbar.find("")
		if free >= 0: hotbar[free] = id
	_dirty = true
	return n

func remove(id: String, n: int = 1) -> bool:
	if count(id) < n: return false
	for c in ["bag", "weapons"]:
		var arr: Array = slots[c]
		for i in arr.size():
			if n <= 0: break
			var s = arr[i]
			if s != null and s.id == id:
				var take := mini(n, int(s.count))
				s.count = int(s.count) - take
				n -= take
				if int(s.count) <= 0: arr[i] = null
	_dirty = true
	return true

func _sync_weapons() -> void:
	var w: Node = main.player.weapon
	for gun in ["ak", "mp40", "izh54", "deagle"]:
		var owned: bool = w.owned.has(gun)
		if owned and count(gun) == 0: add(gun)
		elif not owned and count(gun) > 0: remove(gun, count(gun))
		if not owned:
			var h := hotbar.find(gun)
			if h >= 0:
				hotbar[h] = ""
				_dirty = true

# ------------------------------------------------------------------ použití
func use(id: String) -> void:
	if id == "" or not has(id): return
	var mode: Node = main.mode
	match ITEMS[id].kind:
		"weapon":
			main.player.weapon.switch_to(id)
		"use":
			match id:
				"syringe", "pumpkin":
					# Injekce / dýňová bomba se bere do ruky; levým tlačítkem vpich / hod (odebere se až potom).
					main.player.weapon.hold_item(id)
					return
				"ammo":
					main.player.weapon.refill_reserve()
					main.sfx.play("powerup", -6.0)
					mode._popup("Munice doplněna", true)
			remove(id, 1)
		"quest":
			if id == "uv" and main.quest: main.quest.toggle_flash()

func drop_to_ground(id: String, n: int) -> void:
	# Věc leží u nohou hráče; dá se zvednout E nebo přetažením z Okolí.
	if main.quest == null: return
	var p: Vector3 = main.player.global_position
	var at := p + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
	var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP, at + Vector3.DOWN * 3.0, 1))
	if not hit.is_empty(): at = hit.position
	var root := Node3D.new()
	main.quest.add_child(root)
	root.global_position = at
	var model := _model_for(id)
	if model: root.add_child(model)
	var entry := {"id": id, "count": n, "node": root, "item": null}
	entry.item = main.quest._item(root, at + Vector3(0, 0.3, 0), func():
		return [ITEMS[id].name + (" ×%d" % int(entry.count) if int(entry.count) > 1 else ""), "E  sebrat"]
	, func(): pick_from_ground(entry), true)
	ground.append(entry)
	_dirty = true

func drop_held() -> void:
	# T / přetažení z rukou na zem: zahodí, co je v ruce (zbraň, injekci, dýni).
	var w: Node = main.player.weapon
	if w.item_held != "":
		if w._inject_t >= 0.0: return
		var id: String = w.item_held
		w._finish_item()
		if remove(id, 1): drop_to_ground(id, 1)
		_clear_hot(id)
		main.sfx.play("item_pickup", -10.0, 0.6)
		return
	if w.equipped: drop_weapon(w.current)

func drop_weapon(gun: String) -> void:
	var w: Node = main.player.weapon
	if not w.owned.has(gun) or gun == w.baptizing: return
	if w.current == gun and w.equipped:
		w.holster()
	w._store()
	w.owned.erase(gun)
	remove(gun, count(gun))
	_clear_hot(gun)
	drop_to_ground(gun, 1)
	main.sfx.play("item_pickup", -10.0, 0.6)
	mode_popup("%s na zemi" % ITEMS[gun].name)

func drop_from_slot(where: String, i: int, all: bool) -> void:
	var s = get_slot(where, i)
	if s == null or where == "ground": return
	if where == "hands":
		drop_held()
		return
	if ITEMS[s.id].kind == "quest":
		main.mode._popup("Tohle nezahazuj", false)
		return
	if ITEMS[s.id].kind == "weapon":
		drop_weapon(s.id)
		return
	var n: int = int(s.count) if all else 1
	if where == "hot":
		remove(s.id, n)
	else:
		s.count = int(s.count) - n
		if int(s.count) <= 0: slots[where][i] = null
	drop_to_ground(s.id, n)
	_clear_hot(s.id)
	main.sfx.play("item_pickup", -10.0, 0.6)
	_dirty = true

func _clear_hot(id: String) -> void:
	if count(id) > 0: return
	var h := hotbar.find(id)
	if h >= 0: hotbar[h] = ""
	_dirty = true

func mode_popup(text: String) -> void:
	if main.mode: main.mode._popup(text, false)

func pick_from_ground(entry: Dictionary) -> void:
	var left := 0
	ground.erase(entry)
	if main.quest and entry.item: main.quest._remove(entry.item)
	if ITEMS[entry.id].kind == "weapon":
		# Zbraň ze země: zpátky do výzbroje (stupeň vylepšení si pamatuje).
		main.player.weapon.give(entry.id, not main.player.weapon.equipped and main.player.weapon.item_held == "")
		_sync_weapons()
		main.sfx.play("item_pickup", -4.0)
		_dirty = true
		return
	left = add(entry.id, int(entry.count))
	main.sfx.play("item_pickup", -4.0)
	_dirty = true

# ------------------------------------------------------------------ přesuny (táhni a pusť)
func get_slot(where: String, i: int):
	if where == "ground": return ground[i] if i < ground.size() else null
	if where == "hands":
		var w: Node = main.player.weapon
		if w.item_held != "": return {"id": w.item_held, "count": count(w.item_held)}
		return {"id": w.current, "count": 1} if w.equipped else null
	if where == "hot": return {"id": hotbar[i], "count": count(hotbar[i])} if hotbar[i] != "" else null
	return slots[where][i]

func move(from_where: String, from_i: int, to_where: String, to_i: int) -> void:
	if from_where == to_where and from_i == to_i: return
	var src = get_slot(from_where, from_i)
	if src == null: return
	var w: Node = main.player.weapon
	# Ruce: přetažením do nich zbraň vezmeš (věc použiješ), z nich zbraň schováš.
	if to_where == "hands":
		if from_where == "hands": return
		match String(ITEMS[src.id].kind):
			"weapon": w.switch_to(src.id)
			"use": use(src.id)
		_dirty = true
		return
	if from_where == "hands":
		if to_where == "ground":
			drop_held()
			return
		if to_where == "hot":
			var old_h := hotbar.find(src.id)
			if old_h >= 0: hotbar[old_h] = hotbar[to_i]
			hotbar[to_i] = src.id
		elif to_where != "ground":
			w.holster()
			main.sfx.play("item_pickup", -10.0, 0.7)
		_dirty = true
		return
	if to_where == "hot":
		if ITEMS[src.id].kind in ["mat"]: return
		var old := hotbar.find(src.id)
		if old >= 0: hotbar[old] = hotbar[to_i]
		hotbar[to_i] = src.id
		_dirty = true
		return
	if from_where == "hot":
		if to_where == "ground" or to_where != "hot": hotbar[from_i] = ""
		_dirty = true
		return
	if from_where == "ground":
		if to_where == "ground": return
		pick_from_ground(src)
		return
	if to_where == "ground":
		if ITEMS[src.id].kind == "quest":
			main.mode._popup("Tohle nezahazuj", false)
			return
		if ITEMS[src.id].kind == "weapon":
			drop_weapon(src.id)
			return
		slots[from_where][from_i] = null
		drop_to_ground(src.id, int(src.count))
		if count(src.id) == 0:
			var h := hotbar.find(src.id)
			if h >= 0: hotbar[h] = ""
		return
	var weapon_src: bool = ITEMS[src.id].kind == "weapon"
	if (to_where == "weapons") != weapon_src: return
	var dst = slots[to_where][to_i]
	if dst != null and dst.id == src.id and int(ITEMS[src.id].stack) > 1:
		var room: int = int(ITEMS[src.id].stack) - int(dst.count)
		var put := mini(room, int(src.count))
		dst.count = int(dst.count) + put
		src.count = int(src.count) - put
		if int(src.count) <= 0: slots[from_where][from_i] = null
	else:
		slots[to_where][to_i] = src
		slots[from_where][from_i] = dst
	_dirty = true

# ------------------------------------------------------------------ vstup
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo: return
	var key: Key = (event as InputEventKey).physical_keycode
	if key == KEY_I:
		if main.menu and main.menu.is_open: return
		if main.notes and main.notes.is_open(): return
		if not main.player.control_enabled and not is_open: return
		toggle()
		get_viewport().set_input_as_handled()
		return
	if key == KEY_T:
		if main.menu and main.menu.is_open: return
		if not main.player.control_enabled or main.player.input_suspended: return
		drop_held()
		get_viewport().set_input_as_handled()
		return
	if key >= KEY_1 and key <= KEY_1 + HOT - 1:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not is_open: return
		if main.player.input_suspended and not is_open: return
		use(hotbar[int(key - KEY_1)])
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if is_open and event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	is_open = not is_open
	_root.visible = is_open
	main.player.input_suspended = is_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_open else Input.MOUSE_MODE_CAPTURED
	main.sfx.play("item_pickup", -14.0, 0.7 if is_open else 0.9)
	_preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_open else SubViewport.UPDATE_DISABLED
	_dirty = true

# ------------------------------------------------------------------ UI
class Slot extends Panel:
	var inv: Node
	var where := ""
	var index := 0
	var icon: TextureRect
	var amount: Label

	func _init(owner_inv: Node, w: String, i: int, size_px: int) -> void:
		inv = owner_inv
		where = w
		index = i
		custom_minimum_size = Vector2(size_px, size_px)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.0, 0.0, 0.0, 0.35)
		sb.border_color = Color(1, 1, 1, 0.12)
		sb.set_border_width_all(1)
		add_theme_stylebox_override("panel", sb)
		icon = TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 3
		icon.offset_top = 3
		icon.offset_right = -3
		icon.offset_bottom = -3
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(icon)
		amount = Label.new()
		amount.add_theme_font_size_override("font_size", 13)
		amount.add_theme_constant_override("outline_size", 4)
		amount.add_theme_color_override("font_outline_color", Color.BLACK)
		amount.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		amount.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		amount.grow_vertical = Control.GROW_DIRECTION_BEGIN
		amount.offset_right = -3
		amount.offset_bottom = -1
		amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(amount)

	func show_item(s) -> void:
		if s == null:
			icon.texture = null
			amount.text = ""
			tooltip_text = ""
			return
		icon.texture = inv.icons.get(s.id)
		amount.text = str(int(s.count)) if int(s.count) > 1 else ""
		var info: Dictionary = inv.ITEMS[s.id]
		tooltip_text = String(info.name) + ("\n" + String(info.desc) if info.has("desc") else "")

	func _get_drag_data(_at: Vector2) -> Variant:
		var s = inv.get_slot(where, index)
		if s == null: return null
		# Ikona drží pod kurzorem (uprostřed), ve stejné velikosti jako ve slotu.
		var k: float = get_global_transform_with_canvas().get_scale().y
		var px: float = 62.0 * k
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var p := TextureRect.new()
		p.texture = icon.texture
		p.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		p.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		p.custom_minimum_size = Vector2(px, px)
		p.size = Vector2(px, px)
		p.position = -Vector2(px, px) * 0.5
		p.modulate.a = 0.9
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(p)
		set_drag_preview(holder)
		return {"where": where, "index": index}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("where")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		inv.move(data.where, data.index, where, index)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			var s = inv.get_slot(where, index)
			if s == null: return
			if where == "ground": inv.pick_from_ground(s)
			elif event.shift_pressed: inv.drop_from_slot(where, index, event.ctrl_pressed)   # Shift = zahodit 1, Ctrl+Shift = celý stoh
			else: inv.use(s.id)
		elif event is InputEventMouseButton and event.pressed and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
			var s = inv.get_slot(where, index)
			if s != null and where == "ground": inv.pick_from_ground(s)

class DropZone extends Panel:
	# Celá plocha Okolí: puštěním se věc zahodí.
	var inv: Node
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("where") and data.where != "ground"
	func _drop_data(_at: Vector2, data: Variant) -> void:
		inv.move(data.where, data.index, "ground", 0)

func _panel(title: String) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var head := Label.new()
	head.text = title
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 17)
	var hb := StyleBoxFlat.new()
	hb.bg_color = Color(0.55, 0.55, 0.55, 0.85)
	hb.content_margin_top = 5
	hb.content_margin_bottom = 5
	head.add_theme_stylebox_override("normal", hb)
	box.add_child(head)
	var body := PanelContainer.new()
	var bb := StyleBoxFlat.new()
	bb.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	bb.set_content_margin_all(6)
	body.add_theme_stylebox_override("panel", bb)
	box.add_child(body)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	body.add_child(grid)
	return {"panel": box, "title": head, "grid": grid, "body": body}

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 30
	add_child(_layer)
	_root = Control.new()
	_root.visible = false
	_layer.add_child(_root)
	# Ztmavené pozadí je zároveň „země“: věc puštěná mimo sloty se zahodí.
	var dim := DropZone.new()
	dim.inv = self
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0.02, 0.02, 0.03, 0.62)
	dim.add_theme_stylebox_override("panel", ds)
	_root.add_child(dim)
	# postava uprostřed
	var tex := TextureRect.new()
	tex.name = "Preview"
	tex.size = Vector2(520, 780)
	tex.mouse_filter = Control.MOUSE_FILTER_PASS
	tex.mouse_default_cursor_shape = Control.CURSOR_DRAG
	tex.gui_input.connect(func(ev: InputEvent):
		# Postavu si hráč otočí tažením myši.
		if ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) and _preview_model:
			_preview_model.rotation.y += (ev as InputEventMouseMotion).relative.x * 0.012)
	_root.add_child(tex)
	_preview = SubViewport.new()
	_preview.size = Vector2i(520, 780)
	_preview.transparent_bg = true
	_preview.own_world_3d = true
	_preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_preview)
	tex.texture = _preview.get_texture()
	_build_preview()
	# v rukou
	var hands := _panel("V RUKOU")
	hands.panel.custom_minimum_size = Vector2(340, 0)
	hands.panel.name = "Hands"
	_root.add_child(hands.panel)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 14)
	hands.body.remove_child(hands.grid)
	hands.body.add_child(hrow)
	_hands_slot = Slot.new(self, "hands", 0, SLOT)
	_hands_slot.custom_minimum_size = Vector2(150, 72)
	hrow.add_child(_hands_slot)
	_hands = Label.new()
	_hands.add_theme_font_size_override("font_size", 18)
	_hands.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hrow.add_child(_hands)
	# kontejnery vpravo
	var right := VBoxContainer.new()
	right.name = "Right"
	right.add_theme_constant_override("separation", 10)
	_root.add_child(right)
	for c in CONTAINERS:
		var p := _panel(String(c[1]))
		p.panel.custom_minimum_size = Vector2(5 * (SLOT + 4) + 12, 0)
		right.add_child(p.panel)
		for i in int(c[2]):
			p.grid.add_child(Slot.new(self, String(c[0]), i, SLOT))
		_boxes[c[0]] = p
	# rychlý panel (v inventáři)
	_hot_box = _hotbar_row(true)

	_root.add_child(_hot_box)
	_info = Label.new()
	_info.text = "Táhni myší · pravé tlačítko = použít · pustit mimo sloty = zahodit · na rychlý panel = klávesy 1–5 · zbraň do „V rukou“ = vzít, zpět = schovat · postavu otočíš tažením · I zavřít"

	_info.add_theme_font_size_override("font_size", 15)
	_info.modulate = Color(1, 1, 1, 0.6)
	_root.add_child(_info)
	# rychlý panel při hraní
	var hud := CanvasLayer.new()
	hud.layer = 6
	add_child(hud)
	_hud_hot = _hotbar_row(false)

	_hud_hot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_hud_hot)

func _hotbar_row(interactive: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6 if interactive else 4)
	for i in HOT:
		var s := Slot.new(self, "hot", i, SLOT if interactive else 44)
		if not interactive:
			s.mouse_filter = Control.MOUSE_FILTER_IGNORE
			s.modulate.a = 0.75
		var num := Label.new()
		num.text = str(i + 1)
		num.add_theme_font_size_override("font_size", 12)
		num.position = Vector2(3, 0)
		num.modulate = Color(1, 1, 1, 0.6)
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.add_child(num)
		row.add_child(s)
	return row

func _build_preview() -> void:
	var w := Node3D.new()
	_preview.add_child(w)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	e.ambient_light_energy = 0.7
	env.environment = e
	w.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-25, 35, 0)
	key.light_energy = 1.3
	w.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 200, 0)
	rim.light_energy = 0.8
	rim.light_color = Color(0.7, 0.8, 1.0)
	w.add_child(rim)
	_preview_model = (load("res://assets/hazmat/hazmat_player.tscn") as PackedScene).instantiate()
	w.add_child(_preview_model)
	var ap := AnimationPlayer.new()
	_preview_model.add_child(ap)
	ap.add_animation_library("", load("res://assets/hazmat/locomotion.res"))
	var idle: Animation = ap.get_animation("idle")
	if idle: idle.loop_mode = Animation.LOOP_LINEAR
	ap.play("idle")
	var cam := Camera3D.new()
	cam.name = "PreviewCam"
	w.add_child(cam)
	cam.fov = 30.0
	cam.current = true
	_frame_preview.call_deferred(cam)

func _frame_preview(cam: Camera3D) -> void:
	# Výška postavy podle kostry (rozměry sítě z FBX bývají v jiném měřítku).
	await get_tree().process_frame
	var top := 1.8
	var bottom := 0.0
	for sk in _preview_model.find_children("*", "Skeleton3D", true, false):
		var k: Skeleton3D = sk
		top = -INF
		bottom = INF
		for b in k.get_bone_count():
			var y: float = (k.global_transform * k.get_bone_global_pose(b)).origin.y
			top = maxf(top, y)
			bottom = minf(bottom, y)
	var h := maxf(top - bottom, 0.5) * 1.1
	var mid := bottom + h * 0.47
	cam.look_at_from_position(Vector3(0, mid + h * 0.05, h * 2.15), Vector3(0, mid, 0), Vector3.UP)

# ------------------------------------------------------------------ ikony (vyrenderované modely)
func _build_icon_baker() -> void:
	_icon_vp = SubViewport.new()
	_icon_vp.size = Vector2i(128, 128)
	_icon_vp.transparent_bg = true
	_icon_vp.own_world_3d = true
	_icon_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_icon_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.85, 0.85)
	e.ambient_light_energy = 1.3
	env.environment = e
	_icon_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 2.0
	_icon_vp.add_child(sun)
	var cam := Camera3D.new()
	cam.name = "Cam"
	_icon_vp.add_child(cam)
	cam.current = true

func _model_for(id: String) -> Node3D:
	var q: Node = main.quest
	match id:
		"ak", "mp40", "izh54", "deagle":
			return (load(main.player.body.weapon.GUNS[id].scene) as PackedScene).instantiate()
		"syringe": return Props.make("syringe")
		"pumpkin": return Props.make("pumpkin")
		"ammo": return Props.make("ammo")
		"fuse": return q._inst("fuse", 0.2, 0) if q else null
		"band": return q._inst("wristband", 0.12, 0) if q else null
		"uv": return q._inst("uv_flashlight", 0.22, 2) if q else null
		"wheel": return q._wheel_mesh() if q else null
		"pumpkey":
			var k := Node3D.new()
			var a := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.05, 0.015, 0.16)
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.8, 0.65, 0.3)
			m.metallic = 0.9
			m.roughness = 0.3
			bm.material = m
			a.mesh = bm
			k.add_child(a)
			return k
		"gears": return q._gear_mesh(0, 0.16) if q else null
		"scrap", "parts", "chlor":
			var n := Node3D.new()
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(id)
			var col: Color = {"scrap": Color(0.45, 0.28, 0.16), "parts": Color(0.15, 0.45, 0.2), "chlor": Color(0.9, 0.92, 0.95)}[id]
			for i in (4 if id == "scrap" else 3):
				var mi := MeshInstance3D.new()
				var mesh: PrimitiveMesh
				if id == "chlor":
					var cm := CylinderMesh.new()
					cm.top_radius = 0.03
					cm.bottom_radius = 0.03
					cm.height = 0.015
					mesh = cm
				else:
					var bm := BoxMesh.new()
					bm.size = Vector3(rng.randf_range(0.04, 0.09), 0.01 if id == "parts" else rng.randf_range(0.02, 0.05), rng.randf_range(0.04, 0.08))
					mesh = bm
				var m := StandardMaterial3D.new()
				m.albedo_color = col.darkened(rng.randf() * 0.3)
				m.metallic = 0.6 if id == "scrap" else 0.1
				m.roughness = 0.7
				mesh.material = m
				mi.mesh = mesh
				mi.position = Vector3(rng.randf_range(-0.04, 0.04), i * 0.02, rng.randf_range(-0.04, 0.04))
				mi.rotation = Vector3(rng.randf() * 0.5, rng.randf() * TAU, rng.randf() * 0.5)
				n.add_child(mi)
			return n
	return null

func _bake_loop() -> void:
	for f in 30: await get_tree().process_frame
	while not _icon_queue.is_empty():
		await _bake_next()

func _bake_next() -> void:
	if _icon_queue.is_empty() or main.quest == null: return
	var id: String = _icon_queue.pop_front()
	var model := _model_for(id)
	if model == null: return
	_icon_vp.add_child(model)
	var b := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if not (mi as MeshInstance3D).is_visible_in_tree(): continue
		var a: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		b = a if first else b.merge(a)
		first = false
	var c := b.get_center()
	var r: float = maxf(b.size.length() * 0.62, 0.02)
	var cam: Camera3D = _icon_vp.get_node("Cam")
	cam.fov = 40.0
	var dir := Vector3(0.35, 0.55, 1.0).normalized() if ITEMS[id].kind != "weapon" else Vector3(1.0, 0.25, 0.05).normalized()
	cam.look_at_from_position(c + dir * r * (2.25 if ITEMS[id].kind == "weapon" else 2.1), c, Vector3.UP)
	cam.near = r * 0.05
	cam.far = r * 10.0
	_icon_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _icon_vp.get_texture().get_image()
	if img: icons[id] = ImageTexture.create_from_image(img)
	model.queue_free()
	_dirty = true

# ------------------------------------------------------------------ smyčka
func _process(dt: float) -> void:
	if main == null or main.player == null: return
	_layout()
	_sync_weapons()
	var playing: bool = main.player.control_enabled and not (main.menu and main.menu.is_open)
	_hud_hot.visible = false          # rychlý panel je vidět jen v inventáři
	if not _dirty and not is_open: return
	_dirty = false
	_refresh()

func _layout() -> void:
	if _root.get_child_count() == 0: return
	# Návrh je pro 1080p; vše se zmenší/zvětší podle výšky okna.
	var vs := get_viewport().get_visible_rect().size
	var k := vs.y / 1080.0
	var w := vs.x / k
	_root.scale = Vector2(k, k)
	_root.size = Vector2(w, 1080)
	(_root.get_child(0) as Control).size = Vector2(w, 1080)
	var prev: Control = _root.get_node("Preview")
	prev.position = Vector2(w * 0.5 - 260, 60)
	var hands: Control = _root.get_node("Hands")
	hands.position = Vector2(w * 0.5 - 170, 1080 - 290)
	var right: Control = _root.get_node("Right")
	right.position = Vector2(w - (5 * (SLOT + 4) + 12) - 70, 540.0 - right.get_combined_minimum_size().y * 0.5)
	_hot_box.position = Vector2(w * 0.5 - HOT * (SLOT + 6) * 0.5, 1080 - 150)
	_info.position = Vector2(w * 0.5 - _info.size.x * 0.5, 1080 - 60)
	var hud_parent: Control = _hud_hot
	hud_parent.scale = Vector2(k, k)
	hud_parent.position = Vector2(vs.x * 0.5 - HOT * 48 * 0.5 * k, vs.y - 70 * k)

func _refresh() -> void:
	for c in CONTAINERS:
		var p: Dictionary = _boxes[c[0]]
		var arr: Array = slots[c[0]]
		var used := 0
		for i in arr.size():
			(p.grid.get_child(i) as Slot).show_item(arr[i])
			if arr[i] != null: used += 1
		(p.title as Label).text = "%s  (%d/%d)" % [c[1], used, arr.size()]
	# rychlý panel
	var w: Node = main.player.weapon
	for row in [_hot_box, _hud_hot]:
		for i in HOT:
			var s: Slot = row.get_child(i)
			var id: String = hotbar[i]
			s.show_item({"id": id, "count": count(id)} if id != "" and has(id) else null)
			var sb: StyleBoxFlat = s.get_theme_stylebox("panel")
			var active: bool = id != "" and id == w.current and w.equipped
			sb.border_color = Color(1.0, 0.8, 0.35, 0.9) if active else Color(1, 1, 1, 0.12)
	var cur: String = w.current if w.equipped else ""
	_hands_slot.show_item({"id": cur, "count": 1} if cur != "" else null)
	_hands.text = String(w.display_name()) if cur != "" else "prázdné ruce\n(přetáhni sem zbraň)"
