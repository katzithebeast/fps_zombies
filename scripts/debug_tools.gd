extends Node
## Záložka „Testování“ v nastavení: rozdat si cokoli, spawnout zombie a power-upy,
## přeskočit kroky secretů a teleportovat se. Všechno jen pro ladění.

const ZombieScript := preload("res://scripts/zombie.gd")
const ZOMBIE_KINDS := [["classic", "Klasik"], ["cop", "Policajt"], ["girl", "Dívka"], ["ch10", "CH10"],
	["kid", "Dítě"], ["parasite", "Parazit"], ["alpha", "Alfa"]]
const AREA_POINTS := {6: Vector3(33.5, 0.6, -10.5), 4: Vector3(-22.0, -1.0, -21.3)}

var main: Node
var _status: Label
var _close_after: CheckBox
var _god_btn: Button
var _ammo_btn: Button
var _hold_btn: Button
var _freeze_btn: Button
var _frozen := false

# ------------------------------------------------------------------ stavba záložky
func build(tab: VBoxContainer) -> void:
	var intro := Label.new()
	intro.text = "Všechno tady funguje jen při rozehrané hře. Po akci se menu samo zavře (dá se vypnout)."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	tab.add_child(intro)
	_close_after = CheckBox.new()
	_close_after.text = "Po akci zavřít menu"
	_close_after.button_pressed = true
	tab.add_child(_close_after)
	_status = Label.new()
	_status.text = " "
	_status.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	tab.add_child(_status)

	_section(tab, "Hráč")
	var row := _flow(tab)
	_god_btn = _btn(row, "Nesmrtelnost: vyp", func(): _toggle_god(), false)
	_ammo_btn = _btn(row, "Nekonečná munice: vyp", func(): _toggle_ammo(), false)
	_btn(row, "Plné zdraví", func(): _mode_set("health", 100.0, "Zdraví 100"), false)
	_btn(row, "Ubrat 50 zdraví", func(): _hurt(), true)
	_btn(row, "+5000 bodů", func(): _points(5000), false)
	_btn(row, "Doplnit munici", func(): _refill(), false)

	_section(tab, "Zbraně")
	row = _flow(tab)
	for g in [["ak", "AK-47"], ["mp40", "MP 40"], ["izh54", "IŽ-54"], ["deagle", "Desert Eagle"]]:
		var gun: String = g[0]
		_btn(row, "Dát " + String(g[1]), func(): _give_gun(gun), true)
	_btn(row, "Všechny zbraně", func(): _give_all_guns(), true)
	row = _flow(tab)
	_label(row, "Stupeň zbraně v ruce:")
	for t in [[0, "základ"], [1, "I"], [2, "II"], [3, "III"], [4, "křest"]]:
		var tier: int = t[0]
		_btn(row, String(t[1]), func(): _set_tier(tier), true)

	_section(tab, "Do inventáře")
	row = _flow(tab)
	var inv_script: Script = load("res://scripts/inventory.gd")
	var items: Dictionary = inv_script.ITEMS
	for id in items:
		if String(items[id].kind) == "weapon": continue
		var item_id: String = id
		var n: int = 10 if String(items[id].kind) == "mat" else int(items[id].stack)
		_btn(row, "%s ×%d" % [items[id].name, n], func(): _give_item(item_id, n), false)
	_btn(row, "Materiály ×20 (vše)", func():
		for k in ["scrap", "parts", "chlor", "gears"]: _give_item(k, 20)
		_say("Materiály ×20"), false)

	_section(tab, "Na zem před sebe")
	row = _flow(tab)
	for id in ["syringe", "pumpkin", "ammo", "gears", "scrap"]:
		var item_id: String = id
		_btn(row, String(items[id].name), func(): _drop_item(item_id), true)
	_btn(row, "Ozubené kolo (jako ze zombíka)", func(): _drop_gear(), true)
	_btn(row, "Hodit dýňovou bombu", func(): _throw_bomb(), true)

	_section(tab, "Power-upy (před tebe)")
	row = _flow(tab)
	for p in [["ammo", "MAX AMMO"], ["insta", "INSTA-KILL"], ["heal", "ZDRAVOTNÍK"], ["kaboom", "KABOOM"]]:
		var kind: String = p[0]
		_btn(row, String(p[1]), func(): _powerup(kind), true)

	_section(tab, "Zombíci (6 m před tebou)")
	row = _flow(tab)
	for k in ZOMBIE_KINDS:
		var kind: String = k[0]
		_btn(row, String(k[1]), func(): _spawn(kind, 1), true)
	_btn(row, "Horda ×10", func(): _spawn("", 10), true)
	row = _flow(tab)
	_btn(row, "Zabít všechny", func(): _kill_all(), true)
	_freeze_btn = _btn(row, "Zombíci stojí: vyp", func(): _toggle_freeze(), false)
	_hold_btn = _btn(row, "Zastavit kola: vyp", func(): _toggle_hold(), false)
	row = _flow(tab)
	_label(row, "Skok na kolo:")
	for r in [1, 3, 5, 10, 15, 20]:
		var round_n: int = r
		_btn(row, str(r), func(): _jump_round(round_n), true)

	_section(tab, "Secrety (přeskočit krok)")
	row = _flow(tab)
	_btn(row, "Nahodit proud", func(): _q_power(), true)
	_btn(row, "Vyřešit hodiny (vypadne kolo)", func(): _q_clock(), true)
	_btn(row, "Vyřešit ventily (vypadne klíč)", func(): _q_valves(), true)
	_btn(row, "Vypustit Síň anděla", func(): _q_drain(), true)
	row = _flow(tab)
	_btn(row, "Teleport k Andělovi + boss", func(): _q_boss(), true)
	_btn(row, "Zabít Anděla", func(): _q_boss_kill(), true)
	_btn(row, "Spustit konec", func(): _q_end(), true)
	_btn(row, "UV lampa + náramek", func():
		_give_item("uv", 1)
		_give_item("band", 1)
		if main.quest:
			main.quest.has_uv = true
			main.quest.has_band = true
		_say("UV lampa a náramek v inventáři"), false)

	_section(tab, "Teleport")
	row = _flow(tab)
	var areas: Dictionary = load("res://scripts/area_identity.gd").AREAS
	for i in main.MAP_RECTS.size():
		var idx: int = i
		var name: String = String(areas[i].name) if areas.has(i) else "Místnost %d" % i
		_btn(row, name, func(): _teleport_area(idx), true)
	_btn(row, "Nádrž (dno)", func(): _teleport(Vector3(34.0, -14.0, -51.0)), true)
	_btn(row, "Start", func(): _teleport(main.SPAWN), true)

func _section(tab: VBoxContainer, title: String) -> void:
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
	tab.add_child(l)

func _flow(tab: VBoxContainer) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 8)
	f.add_theme_constant_override("v_separation", 8)
	tab.add_child(f)
	return f

func _label(row: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(0, 40)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)

func _btn(row: Control, text: String, cb: Callable, closes: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(func():
		if not _ready_to_test():
			_say("Nejdřív spusť hru (Enter the baths).", true)
			return
		cb.call()
		if closes and _close_after.button_pressed and main.menu.is_open: main._on_resume())
	row.add_child(b)
	return b

func _say(text: String, bad := false) -> void:
	if _status:
		_status.text = text
		_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45) if bad else Color(0.6, 1.0, 0.7))
	if main and main.get("mode") and main.mode.has_method("_popup"): main.mode._popup(text, not bad)

func _ready_to_test() -> bool:
	return main != null and main.player != null and main.menu != null and main.menu.in_game

func _ensure_mode() -> void:
	# Většina věcí potřebuje rozjetý režim přežití (body, kola, inventář).
	if not main.mode.active:
		if not main.player.weapon.owned.has("ak"): main.player.weapon.give("ak", true)
		main.mode.begin()

func _front(dist: float) -> Vector3:
	var p: Node3D = main.player
	var cam: Camera3D = p.camera
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var at: Vector3 = p.global_position + fwd * dist
	var space := p.get_world_3d().direct_space_state
	var block := space.intersect_ray(PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP, at + Vector3.UP, 1))
	if not block.is_empty(): at = block.position - fwd * 0.6 - Vector3.UP
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at + Vector3.DOWN * 6.0, 1))
	if not hit.is_empty(): at = hit.position
	return at

# ------------------------------------------------------------------ hráč
func _toggle_god() -> void:
	main.mode.debug_god = not main.mode.debug_god
	_god_btn.text = "Nesmrtelnost: " + ("ZAP" if main.mode.debug_god else "vyp")
	_say("Nesmrtelnost " + ("zapnuta" if main.mode.debug_god else "vypnuta"))

func _toggle_ammo() -> void:
	var w: Node = main.player.weapon
	w.debug_ammo = not w.debug_ammo
	_ammo_btn.text = "Nekonečná munice: " + ("ZAP" if w.debug_ammo else "vyp")
	_say("Nekonečná munice " + ("zapnuta" if w.debug_ammo else "vypnuta"))

func _mode_set(key: String, value: Variant, msg: String) -> void:
	main.mode.set(key, value)
	_say(msg)

func _hurt() -> void:
	_ensure_mode()
	main.mode.health = maxf(1.0, float(main.mode.health) - 50.0)
	_say("Zdraví %d" % int(main.mode.health))

func _points(n: int) -> void:
	_ensure_mode()
	main.mode.points += n
	_say("+%d bodů" % n)

func _refill() -> void:
	main.player.weapon.refill()
	_say("Munice doplněna")

# ------------------------------------------------------------------ zbraně
func _give_gun(gun: String) -> void:
	main.player.weapon.give(gun, true)
	_ensure_mode()
	_say("Zbraň: " + String(main.player.weapon.STATS[gun].name))

func _give_all_guns() -> void:
	for g in ["ak", "mp40", "izh54", "deagle"]: main.player.weapon.give(g, g == "ak")
	_ensure_mode()
	_say("Všechny zbraně")

func _set_tier(t: int) -> void:
	var w: Node = main.player.weapon
	if not w.equipped:
		_say("Vezmi zbraň do ruky", true)
		return
	var g: String = w.current
	if t <= 0: w.upgraded.erase(g)
	else: w.upgraded[g] = t
	w._store()
	w.clips[g] = [int(w.stats_of(g).mag), int(w.stats_of(g).reserve)]
	w._load_current()
	_say("%s" % w.display_name())

# ------------------------------------------------------------------ předměty
func _give_item(id: String, n: int) -> void:
	_ensure_mode()
	var inv: Node = main.inventory
	if inv == null: return
	var left: int = inv.add(id, n)
	if left > 0: inv.drop_to_ground(id, left)
	if main.quest:
		match id:
			"uv": main.quest.has_uv = true
			"band": main.quest.has_band = true
			"wheel": main.quest.has_wheel = true
			"pumpkey": main.quest.has_key = true
			"fuse": main.quest.fuses = int(main.quest.fuses) + n
	_say("%s ×%d%s" % [inv.ITEMS[id].name, n, "  (část na zemi – plno)" if left > 0 else ""])

func _drop_item(id: String) -> void:
	_ensure_mode()
	var inv: Node = main.inventory
	inv.drop_to_ground(id, 1)
	var entry: Dictionary = inv.ground[-1]
	var at := _front(1.6)
	(entry.node as Node3D).global_position = at
	if entry.item: entry.item.pos = at + Vector3(0, 0.3, 0) - Vector3(0, 0.6, 0)
	_say("%s leží před tebou" % inv.ITEMS[id].name)

func _drop_gear() -> void:
	_ensure_mode()
	main.quest._drop_gear(_front(2.0))
	_say("Ozubené kolo")

func _throw_bomb() -> void:
	_ensure_mode()
	var cam: Camera3D = main.player.camera
	load("res://scripts/pumpkin_bomb.gd").throw_from(main, cam.global_position - cam.global_basis.z * 0.6, -cam.global_basis.z * 10.0 + Vector3.UP * 2.5)
	_say("Dýňová bomba letí")

func _powerup(kind: String) -> void:
	_ensure_mode()
	var at := _front(3.0)
	main.mode._drop(kind, at)
	_say("Power-up " + kind)

# ------------------------------------------------------------------ zombie
func _spawn(kind: String, n: int) -> void:
	_ensure_mode()
	var mode: Node = main.mode
	var base := _front(6.0)
	for i in n:
		var z: Node3D = mode._make(maxi(int(mode.round_now), 1), kind)
		var a := TAU * float(i) / float(maxi(n, 1))
		z.position = base + (Vector3(cos(a), 0, sin(a)) * (0.0 if n == 1 else 2.2))
		z.rotation.y = randf() * TAU
		main.add_child(z)
		if _frozen: z.ai = false
	_say("Zombie: %s ×%d" % [kind if kind != "" else "mix", n])

func _kill_all() -> void:
	var n := 0
	for z in ZombieScript.crowd.duplicate():
		if not is_instance_valid(z) or z.dead: continue
		if z.has_meta("quest_boss"): continue
		z.hit(randi() % 8, z.global_position + Vector3.UP, Vector3.UP, 1.5, 99999.0)
		n += 1
	_say("Zabito %d" % n)

func _toggle_freeze() -> void:
	_frozen = not _frozen
	for z in ZombieScript.crowd:
		if is_instance_valid(z) and not z.dead: z.ai = not _frozen
	_freeze_btn.text = "Zombíci stojí: " + ("ZAP" if _frozen else "vyp")
	_say("Zombíci " + ("stojí" if _frozen else "zase chodí"))

func _toggle_hold() -> void:
	main.mode.debug_hold = not main.mode.debug_hold
	_hold_btn.text = "Zastavit kola: " + ("ZAP" if main.mode.debug_hold else "vyp")
	_say("Kola " + ("stojí (nic nespawnuje)" if main.mode.debug_hold else "zase běží"))

func _jump_round(r: int) -> void:
	_ensure_mode()
	_kill_all()
	var mode: Node = main.mode
	mode.round_now = r - 1
	mode._start_round()
	_say("Kolo %d" % r)

# ------------------------------------------------------------------ secrety
func _q_power() -> void:
	_ensure_mode()
	var q: Node = main.quest
	if q.power:
		_say("Proud už běží", true)
		return
	q.fuses_in = 3
	for i in 3:
		if q.has_method("_show_fuse"): q._show_fuse(i, true)
	q._power_on()
	_say("Proud nahozen")

func _q_clock() -> void:
	_ensure_mode()
	var q: Node = main.quest
	if q.clock_done:
		_say("Hodiny už jsou vyřešené", true)
		return
	q._clock_solved()
	_say("Hodiny vyřešené – u hodin leží ventilové kolo")

func _q_valves() -> void:
	_ensure_mode()
	var q: Node = main.quest
	if q.valves_done:
		_say("Ventily už jsou vyřešené", true)
		return
	for v in q._valves:
		v.value = int(q.valve_code[int(v.index)])
		if v.has("gauge") and is_instance_valid(v.gauge): v.gauge.text = str(v.value)
	if q._valves.size() >= 3: (q._valves[2].wheel as Node3D).visible = true
	q.has_wheel = true
	q._check_valves()
	_say("Ventily vyřešené – u ventilu II leží klíč" if q.valves_done else "Ventily se nepovedly", not q.valves_done)

func _q_drain() -> void:
	_ensure_mode()
	var q: Node = main.quest
	if q.drained:
		_say("Síň anděla už je vypuštěná", true)
		return
	q.drain_stage = 3
	q._drain_done()
	_say("Síň anděla vypuštěná (mříž se otevře za 4 s)")

func _q_boss() -> void:
	_ensure_mode()
	var q: Node = main.quest
	if not q.drained: _q_drain()
	_teleport(Vector3(q.CISTERN.get_center().x, -14.0, q.CISTERN.get_center().y + 7.0))
	if q.boss_state == "none": q._boss_rise()
	_say("Anděl se probouzí")

func _q_boss_kill() -> void:
	var q: Node = main.quest
	if q.boss_state != "fight" and q.boss_state != "rising":
		_say("Anděl ještě není vzhůru", true)
		return
	q._boss_dead()
	_say("Anděl padl")

func _q_end() -> void:
	_ensure_mode()
	main.quest._ending()
	_say("Konec")

# ------------------------------------------------------------------ teleport
func _teleport_area(i: int) -> void:
	if AREA_POINTS.has(i):
		_teleport(AREA_POINTS[i])
		return
	var r: Rect2 = main.MAP_RECTS[i]
	var c := r.get_center()
	var y: float = 0.5
	if main.quest:
		var fy: float = main.quest._floor_at(c)
		if fy != INF: y = fy + 0.05
	_teleport(Vector3(c.x, y, c.y))

func _teleport(at: Vector3) -> void:
	var p: Node = main.player
	p.teleport(at, p.yaw, p.pitch)
	_say("Teleport %s" % str(at.snapped(Vector3.ONE * 0.1)))
