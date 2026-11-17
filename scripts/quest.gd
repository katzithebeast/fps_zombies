extends Node3D
## Hlavní linka secretů (jako easter egg v CoD Zombies). Bez ní se hra nedá dohrát.
## Proud (3 pojistky) → plovoucí tělo s náramkem → skříňka 37 (UV lampa) → UV nápisy
## → sprchy a zrcadlo (čas) → hodiny ve vstupní hale (ventilové kolo) → ventily v kotelně (klíč)
## → vypuštění Síně anděla (obrana čerpadla) → mříž → Nádrž → Anděl → lístek „Lantern“ → konec.
## Vedle toho materiály (šrot, součástky, chlór) na stupně zbraní u pracovního stolu a křest zbraně.

const Props := preload("res://scripts/props.gd")
const ZombieScript := preload("res://scripts/zombie.gd")

const TIER_COST := [
	{},
	{"points": 1000, "scrap": 4, "gears": 1},
	{"points": 2500, "scrap": 8, "parts": 3, "gears": 2},
	{"points": 4000, "scrap": 8, "parts": 2, "chlor": 4, "gears": 3},
]
const BAPTISM_COST := 5000
const MAT_NAMES := {"scrap": "šrot", "parts": "součástky", "chlor": "chlór", "gears": "ozub. kola"}

# Místa na zemi, kde může ležet pojistka (vybírají se 3 náhodně).
const FUSE_SPOTS := [Vector2(41.4, 21.0), Vector2(-3.0, -53.0), Vector2(-6.0, -36.0), Vector2(38.0, 6.0),
	Vector2(47.5, 37.5), Vector2(-28.0, -40.0)]
const CHLOR_SPOTS := [Vector2(-11.6, -25.6), Vector2(2.5, -57.8), Vector2(25.0, 0.0)]
const PARTS_AREAS := [10, 13, 15, 8, 0]
const BODY_SPOTS := [Vector3(8.6, -0.35, -17.0), Vector3(-8.6, -0.35, -11.0), Vector3(8.6, -0.35, -10.5), Vector3(-8.6, -0.35, -17.5)]
const CISTERN := Rect2(22.0, -62.0, 24.0, 22.0)
const CISTERN_FLOOR := -14.4
const ANGEL_FLOOR := -14.4

var main: Node
var mode: Node
var st: Node

# --- stav jedné hry
var mats := {"scrap": 0, "parts": 0, "chlor": 0, "gears": 0}
var fuses := 0
var fuses_in := 0
var power := false
var has_band := false
var has_uv := false
var uv_on := false
var mirror_seen := false
var has_wheel := false
var clock_done := false
var valves_done := false
var has_key := false
var drain_stage := -1           # -1 nic, 0..2 vypouštění, 3 hotovo
var drained := false
var boss_state := "none"        # none, rising, fight, dead
var ended := false
var valve_code := [1, 1, 1]
var clock_target := 0           # v minutách 0..719
var clock_now := 0

var _rng := RandomNumberGenerator.new()
var _pickups: Array = []        # quest položky ve stations.items, které se při resetu mažou
var _body: Node3D
var _uv_labels: Array = []      # [Label3D]
var _fuse_box: Dictionary
var _fuse_slots: Array = []
var _valves: Array = []         # {item, value, wheel(Node3D), gauge(Label3D)}
var _taps: Array = []           # {item, on, stream(GPUParticles3D)}
var _steam: FogVolume
var _mirror_text: Label3D
var _clock_hands: Array = []    # [hodinová, minutová]
var _clock_panel: Node3D
var _pump: Dictionary
var _pump_light: OmniLight3D
var _pump_jam := false
var _pump_fix := 0.0
var _jam_at := 0.5
var _stage_t := 0.0
var _gate: Dictionary
var _angel_water: Node3D
var _angel_zone: Dictionary
var _boss: Node3D
var _weak: Array = []           # {body, mesh, hp}
var _boss_t := 0.0
var _ambush_t := 40.0
var _last_round := 0
var _chlor_items: Array = []
var _hud: Label
var _layer: CanvasLayer
var _end_layer: CanvasLayer
var _font: Font

func setup(main_node: Node) -> void:
	main = main_node
	mode = main.mode
	_font = SystemFont.new()
	(_font as SystemFont).font_names = PackedStringArray(["Ink Free", "Segoe Print", "Comic Sans MS", "DejaVu Sans"])
	_build_ui()

# Volá zombie režim hned po vytvoření stanic (ještě před pečením navigace).
func stations_ready(stations: Node) -> void:
	st = stations
	# Mříž ze dna Síně anděla do Nádrže: zarezlá, otevře ji až vypuštění.
	st._add_gate(Vector3(33.5, ANGEL_FLOOR, -27.3), 0.0, [0, 2.0, 2.6])
	_gate = st.items[st.items.size() - 1]
	_gate["locked"] = true
	_build_world.call_deferred()

# ------------------------------------------------------------------ stavba
func _build_world() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	_rng.seed = 7731
	# Skříňka č. 37 v šatnách (ta nejvíc vpravo).
	var best: Dictionary = {}
	for item in st.items:
		if item.kind == "locker" and (best.is_empty() or (item.pos as Vector3).distance_to(Vector3(9.0, 0.5, 8.7)) < (best.pos as Vector3).distance_to(Vector3(9.0, 0.5, 8.7))):
			best = item
	if not best.is_empty():
		best["lock37"] = true
		for side in [1.0, -1.0]:
			var num := _label3d("37", 64, Color(0.95, 0.92, 0.8))
			best.node.add_child(num)
			num.position = Vector3(0, 1.62, 0.33 * side)
			num.rotation.y = 0.0 if side > 0.0 else PI
			num.font = null
	_build_fuse_box(space)
	_build_parts(space)
	_build_showers()
	_build_clock(space)
	_build_valves(space)
	_build_pump()
	_build_baptism()
	_build_lab()
	_build_uv_texts(space)
	_angel_water = main.water_mesh_for(Vector2(33.5, -18.0))
	_angel_zone = main.add_water_zone(Rect2(20.6, -34.0, 26.0, 32.0), main.WATER_Y)

const QA := "res://assets/quest/"

func _inst(name: String, fit: float, axis := -1) -> Node3D:
	# Model z assets/quest zmenšený na danou velikost; počátek držáku = střed podstavy.
	var holder := Node3D.new()
	var pivot := Node3D.new()
	holder.add_child(pivot)
	var m: Node3D = (load(name if name.begins_with("res://") else QA + name + ".glb") as PackedScene).instantiate()
	pivot.add_child(m)
	var b: AABB = Props._bounds(pivot)
	var size: float = maxf(b.size.x, maxf(b.size.y, b.size.z)) if axis < 0 else b.size[axis]
	var k := fit / maxf(size, 0.0001)
	pivot.scale = Vector3.ONE * k
	pivot.position = -Vector3(b.get_center().x, b.position.y, b.get_center().z) * k
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return holder

func _label3d(text: String, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = _font
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	return l

func _mat(color: Color, emission := 0.0, metal := 0.0, rough := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m

func _boxmesh(size: Vector3, m: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	return mi

func _cylmesh(r: float, h: float, m: Material) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 16
	cm.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	return mi

func _wall(space: PhysicsDirectSpaceState3D, area: int, w: float, h: float) -> Dictionary:
	return st._find_wall(space, main.MAP_RECTS[area], w, h, _rng)

func _floor_at(xz: Vector2) -> float:
	# Nejnižší podlaha nad hlubokou vodou v daném bodě (stejně jako u zbraní na zdi).
	var space := get_world_3d().direct_space_state
	var top := 8.0
	var fy := INF
	for i in 6:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(xz.x, top, xz.y), Vector3(xz.x, -6.0, xz.y), 1))
		if hit.is_empty(): break
		var hy: float = hit.position.y
		if (hit.normal as Vector3).y > 0.85 and hy >= -0.6 and hy < 2.6 and top - hy > 2.0: fy = hy
		top = hy - 0.05
	return fy

func _wall_basis(n: Vector3) -> Basis:
	return Basis.looking_at(-n, Vector3.UP)

# Obecná položka pro systém stanic (popisek, zvýraznění, E).
func _item(node: Node3D, at: Vector3, label: Callable, use: Callable, temp := false) -> Dictionary:
	var item := {"kind": "quest", "node": node, "pos": at - Vector3(0, 0.6, 0), "top": 0.0, "state": "idle", "t": 0.0,
		"gun": "", "prize": "", "show": null, "open": 0.0, "lbl": label, "use": use}
	st.items.append(item)
	if temp: _pickups.append(item)
	return item

func _remove_node(node: Node) -> void:
	for item in st.items:
		if item.kind == "quest" and item.node == node:
			_remove(item)
			return

func _remove(item: Dictionary) -> void:
	st.items.erase(item)
	_pickups.erase(item)
	if is_instance_valid(item.node): item.node.queue_free()

func _glow(parent: Node3D, color: Color, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	parent.add_child(l)
	return l

# --- proud
func _build_fuse_box(space: PhysicsDirectSpaceState3D) -> void:
	var spot := _wall(space, 3, 1.2, 1.4)
	if spot.is_empty(): return
	var n: Vector3 = spot.normal
	var root := Node3D.new()
	add_child(root)
	root.global_transform = Transform3D(_wall_basis(n), spot.pos - Vector3.UP * 1.4 + n * 0.26)
	var cab := _inst("electrical_box", 2.0, 1)
	root.add_child(cab)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.93, 2.0, 0.48)
	cs.shape = bs
	cs.position.y = 1.0
	body.add_child(cs)
	root.add_child(body)
	var plate := _label3d("R-3   POJISTKY", 28, Color(0.95, 0.88, 0.25))
	plate.font = null
	root.add_child(plate)
	plate.position = Vector3(0, 1.62, 0.26)
	# Vložené pojistky jsou vidět na čele skříně.
	for i in 3:
		var f := _inst("fuse", 0.16, 0)
		root.add_child(f)
		f.position = Vector3(-0.2 + i * 0.2, 1.42, 0.27)
		f.visible = false
		_fuse_slots.append(f)
	var lever := _boxmesh(Vector3(0.05, 0.3, 0.05), _mat(Color(0.7, 0.1, 0.08), 0.0, 0.3, 0.4))
	root.add_child(lever)
	lever.position = Vector3(0.52, 1.1, 0.05)
	lever.rotation.x = 0.6
	root.set_meta("lever", lever)
	_fuse_box = _item(root, root.global_position + Vector3.UP * 1.0 + n * 0.55, func():
		if power: return ["Rozvaděč", "proud běží"]
		if fuses_in < 3:
			if fuses > 0: return ["Rozvaděč", "E  vložit pojistku   (%d/3)" % fuses_in]
			return ["Rozvaděč", "chybí pojistky   (%d/3)" % fuses_in]
		return ["Rozvaděč", "E  nahodit proud"]
	, func():
		if power: return
		if fuses_in < 3 and fuses > 0:
			fuses -= 1
			_inv_remove("fuse")
			fuses_in += 1
			_show_fuse(fuses_in - 1, true)
			main.sfx.play_at("lamp_click", root.global_position + Vector3.UP * 1.4, -2.0, 0.8)
		elif fuses_in >= 3:
			_power_on())

func _show_fuse(i: int, on: bool) -> void:
	if i < 0 or i >= _fuse_slots.size(): return
	(_fuse_slots[i] as Node3D).visible = on

func _power_on() -> void:
	power = true
	var lever: Node3D = _fuse_box.node.get_meta("lever")
	create_tween().tween_property(lever, "rotation:x", -0.6, 0.25)
	main.sfx.play_at("gate_open", _fuse_box.node.global_position, -4.0, 0.7)
	main.sfx.play("whoomp", -6.0)
	# Všechna světla na okamžik zhasnou a pak nahodí – lázně se probouzí.
	for L in main.lamps:
		var light: Light3D = L.light
		if not is_instance_valid(light): continue
		var e: float = light.light_energy
		light.light_energy = 0.0
		get_tree().create_timer(randf_range(0.6, 1.6)).timeout.connect(func():
			if is_instance_valid(light): light.light_energy = e
			main.sfx.play_at("lamp_spark", light.global_position, -14.0, randf_range(0.9, 1.1)))
	mode._show_banner("", "Proud obnoven", 2.4)
	_radio("Control", "Vidíme odběr proudu ze strojovny. Lantern, co jsi to tam nahodil?")

func _place_fuses() -> void:
	var spots := FUSE_SPOTS.duplicate()
	spots.shuffle()
	var placed := 0
	for xz in spots:
		if placed >= 3: break
		var fy := _floor_at(xz)
		if fy == INF: continue
		placed += 1
		var root := Node3D.new()
		add_child(root)
		root.global_position = Vector3(xz.x, fy + 0.04, xz.y)
		var f := _inst("fuse", 0.15, 0)
		root.add_child(f)
		f.rotation.y = randf() * TAU
		_glow(root, Color(1.0, 0.6, 0.3), 0.25, 1.4).position.y = 0.25
		_item(root, root.global_position, func(): return ["Pojistka", "E  sebrat"], func():
			fuses += 1
			_inv_add("fuse")
			main.sfx.play("item_pickup", -4.0)
			mode._popup("Pojistka  %d/3" % (fuses + fuses_in), true)
			_remove_node(root), true)

# --- součástky a chlór
func _build_parts(space: PhysicsDirectSpaceState3D) -> void:
	for area in PARTS_AREAS:
		var spot := _wall(space, area, 0.8, 0.9)
		if spot.is_empty(): continue
		var n: Vector3 = spot.normal
		var root := Node3D.new()
		add_child(root)
		root.global_transform = Transform3D(_wall_basis(n), spot.pos + n * 0.1)
		var box := _inst("electrical_box", 0.7, 1)
		root.add_child(box)
		box.position = Vector3(0, -0.35, -0.02)
		# Vyrvané kabely visí z dvířek – dokud je hráč nevytáhne.
		var wires := Node3D.new()
		root.add_child(wires)
		for i in 4:
			var w := _cylmesh(0.008, randf_range(0.18, 0.32), _mat([Color(0.7, 0.1, 0.05), Color(0.1, 0.25, 0.7), Color(0.85, 0.75, 0.1), Color(0.15, 0.15, 0.15)][i]))
			wires.add_child(w)
			w.position = Vector3(-0.08 + i * 0.05, -0.05, 0.11)
			w.rotation.z = randf_range(-0.4, 0.4)
		var spark := _glow(wires, Color(0.6, 0.8, 1.0), 0.25, 1.2)
		spark.position = Vector3(0, 0.0, 0.2)
		root.set_meta("full", true)
		root.set_meta("wires", wires)
		_item(root, root.global_position + n * 0.3, func():
			return ["Rozbitá elektroskříň", "E  vytáhnout součástky" if root.get_meta("full") else "vybraná"]
		, func():
			if not root.get_meta("full"): return
			root.set_meta("full", false)
			(root.get_meta("wires") as Node3D).visible = false
			main.sfx.play_at("lamp_spark", root.global_position, -6.0)
			add_mat("parts", 2))

func _place_chlor() -> void:
	_chlor_items.clear()
	for xz in CHLOR_SPOTS:
		var fy := _floor_at(xz)
		if fy == INF: continue
		var root := Node3D.new()
		add_child(root)
		root.global_position = Vector3(xz.x, fy, xz.y)
		var bucket := _cylmesh(0.16, 0.34, _mat(Color(0.15, 0.4, 0.75), 0.0, 0.0, 0.5))
		root.add_child(bucket)
		bucket.position.y = 0.17
		var lid := _cylmesh(0.165, 0.03, _mat(Color(0.9, 0.9, 0.85)))
		root.add_child(lid)
		lid.position.y = 0.35
		var tag := _label3d("CHLOR", 26, Color(0.1, 0.1, 0.1))
		tag.font = null
		root.add_child(tag)
		tag.position = Vector3(0, 0.2, 0.165)
		root.set_meta("full", true)
		_item(root, root.global_position + Vector3(0, 0.4, 0), func():
			return ["Chlórové tablety", "E  vzít" if root.get_meta("full") else "prázdný kbelík"]
		, func():
			if not root.get_meta("full"): return
			root.set_meta("full", false)
			lid.visible = false
			main.sfx.play("item_pickup", -4.0)
			add_mat("chlor", 2), true)
		_chlor_items.append(root)

func add_mat(kind: String, n: int) -> void:
	if main.inventory: main.inventory.add(kind, n)
	else: mats[kind] = int(mats[kind]) + n
	mode._popup("+%d %s" % [n, MAT_NAMES[kind]], false)

func bench_cost(tier: int) -> Dictionary:
	return TIER_COST[tier] if tier > 0 and tier < TIER_COST.size() else {}

func cost_text(cost: Dictionary, with_points: bool) -> String:
	var parts := []
	if with_points and cost.has("points"): parts.append("%d" % int(cost.points))
	for k in ["scrap", "parts", "chlor", "gears"]:
		if cost.has(k): parts.append("%s %d" % [MAT_NAMES[k], int(cost[k])])
	return "  ·  ".join(parts)

func mat(k: String) -> int:
	return main.inventory.count(k) if main.inventory else int(mats[k])

func can_afford(cost: Dictionary) -> bool:
	for k in ["scrap", "parts", "chlor", "gears"]:
		if mat(k) < int(cost.get(k, 0)): return false
	return true

func spend(cost: Dictionary) -> void:
	for k in ["scrap", "parts", "chlor", "gears"]:
		if int(cost.get(k, 0)) <= 0: continue
		if main.inventory: main.inventory.remove(k, int(cost.get(k, 0)))
		else: mats[k] = int(mats[k]) - int(cost.get(k, 0))

# --- sprchy a zrcadlo
func _build_showers() -> void:
	var spots := []
	for sz in [14.5, 17.0, 19.0]:
		spots.append([Vector3(sz, 1.1, -14.91), Vector3(sz, 2.05, -14.64), Vector3(0, 0, 1)])
		spots.append([Vector3(sz - 1.2, 1.1, -13.09), Vector3(sz - 1.2, 2.05, -13.36), Vector3(0, 0, -1)])
	for s in spots:
		var marker := Node3D.new()
		add_child(marker)
		marker.global_position = s[0]
		var p := GPUParticles3D.new()
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, -1, 0)
		pm.spread = 8.0
		pm.initial_velocity_min = 1.2
		pm.initial_velocity_max = 1.8
		pm.gravity = Vector3(0, -9.8, 0)
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.06
		p.process_material = pm
		var drop := QuadMesh.new()
		drop.size = Vector2(0.012, 0.09)
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.8, 0.9, 1.0, 0.45)
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		drop.material = dm
		p.draw_pass_1 = drop
		p.amount = 90
		p.lifetime = 0.9
		p.emitting = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		p.global_position = s[1]
		var tap := {"on": false, "stream": p, "loop": null}
		tap["item"] = _item(marker, s[0] + (s[2] as Vector3) * 0.3, func():
			if not power: return ["Kohoutek", "nic neteče"]
			return ["Kohoutek", "E  zavřít" if tap.on else "E  pustit vodu"]
		, func():
			if not power:
				main.sfx.play_at("lamp_click", marker.global_position, -6.0, 1.4)
				return
			tap.on = not tap.on
			p.emitting = tap.on
			main.sfx.play_at("lamp_click", marker.global_position, -6.0, 0.7)
			if tap.on:
				var loop: AudioStreamPlayer3D = main.sfx.make_loop_3d("amb_water", s[1], -14.0)
				loop.pitch_scale = 1.4
				tap.loop = loop
			elif tap.loop:
				(tap.loop as Node).queue_free()
				tap.loop = null
			_check_showers())
		_taps.append(tap)
	_steam = FogVolume.new()
	_steam.size = Vector3(7.4, 3.2, 2.6)
	var fm := FogMaterial.new()
	fm.density = 0.0
	fm.albedo = Color(0.9, 0.92, 0.95)
	_steam.material = fm
	add_child(_steam)
	_steam.global_position = Vector3(16.3, 1.4, -14.0)
	# Zrcadlo mezi sprchami: ve páře se na něm objeví čas napsaný prstem.
	var mirror := _boxmesh(Vector3(0.8, 0.6, 0.02), _mat(Color(0.75, 0.8, 0.82), 0.0, 1.0, 0.04))
	add_child(mirror)
	mirror.global_position = Vector3(15.75, 1.65, -14.98)
	_mirror_text = _label3d("", 72, Color(0.95, 0.97, 1.0, 0.0))
	add_child(_mirror_text)
	_mirror_text.global_position = Vector3(15.75, 1.65, -14.965)

func _check_showers() -> void:
	var all_on := true
	for t in _taps: all_on = all_on and bool(t.on)
	var fm: FogMaterial = _steam.material
	var tw := create_tween()
	tw.tween_property(fm, "density", 0.35 if all_on else 0.0, 6.0 if all_on else 3.0)
	if all_on and not mirror_seen:
		mirror_seen = true
		_mirror_text.text = "%d:%02d" % [_clock_h(clock_target), clock_target % 60]
		tw.parallel().tween_property(_mirror_text, "modulate:a", 0.75, 7.0).set_delay(2.5)
		get_tree().create_timer(5.0).timeout.connect(func(): main.sfx.play_at("scare", _mirror_text.global_position, -16.0, 0.8))

func _clock_h(minutes: int) -> int:
	var h := int(minutes / 60) % 12
	return 12 if h == 0 else h

# --- hodiny ve vstupní hale
func _build_clock(space: PhysicsDirectSpaceState3D) -> void:
	var spot := _wall(space, 0, 1.4, 1.2)
	if spot.is_empty(): return
	var n: Vector3 = spot.normal
	var root := Node3D.new()
	add_child(root)
	root.global_transform = Transform3D(_wall_basis(n), spot.pos + n * 0.005 + Vector3.UP * 0.75)
	# Model leží ciferníkem nahoru (12 k −Z): otočit čelem do místnosti.
	var clock := _inst("clock", 0.65, 0)
	root.add_child(clock)
	clock.rotation.x = PI / 2
	for nm in ["hour empty", "minute empty", "second empty"]:
		var h: Node = clock.find_child(nm, true, false)
		if h: _clock_hands.append(h)
	# Technická dvířka pod hodinami.
	_clock_panel = Node3D.new()
	root.add_child(_clock_panel)
	_clock_panel.position = Vector3(-0.25, -0.95, 0.0)
	var door := _boxmesh(Vector3(0.5, 0.5, 0.04), _mat(Color(0.55, 0.58, 0.55), 0.0, 0.4, 0.6))
	_clock_panel.add_child(door)
	door.position = Vector3(0.25, 0, 0.02)
	_item(root, root.global_position + n * 0.35 - Vector3.UP * 0.4, func():
		if clock_done: return ["Hodiny", "stojí"]
		if not power: return ["Hodiny", "stojí – bez proudu"]
		return ["Hodiny  %d:%02d" % [_clock_h(clock_now), clock_now % 60], "E  posunout ručičky"]
	, func():
		if clock_done or not power: return
		clock_now = (clock_now + 15) % 720
		_pose_clock()
		main.sfx.play_at("lamp_click", root.global_position, -8.0, 1.6)
		if clock_now == clock_target and mirror_seen:
			_clock_solved())

func _pose_clock() -> void:
	# Ručičky se točí kolem osy Y modelu, záporně = po směru hodin; 0 = dvanáctka.
	if _clock_hands.size() < 2: return
	(_clock_hands[0] as Node3D).rotation.y = -TAU * float(clock_now % 720) / 720.0
	(_clock_hands[1] as Node3D).rotation.y = -TAU * float(clock_now % 60) / 60.0

func _clock_solved() -> void:
	clock_done = true
	await get_tree().create_timer(1.2).timeout
	# Ručičky se roztočí pozpátku a dvířka pod hodinami odskočí.
	var tw := create_tween()
	tw.tween_method(func(v: float):
		(_clock_hands[0] as Node3D).rotation.y = v * 0.08
		(_clock_hands[1] as Node3D).rotation.y = v, 0.0, TAU * 6.0, 3.0)
	main.sfx.play_at("scare", _clock_panel.global_position, -8.0, 0.6)
	await tw.finished
	main.sfx.play_at("locker_open", _clock_panel.global_position, -2.0, 0.8)
	create_tween().tween_property(_clock_panel, "rotation:y", -1.7, 0.5)
	var root := Node3D.new()
	add_child(root)
	root.global_position = _clock_panel.global_position + _clock_panel.global_basis.z * 0.12 + Vector3.UP * 0.0
	var wheel := _wheel_mesh()
	root.add_child(wheel)
	_glow(root, Color(1.0, 0.85, 0.5), 0.3, 1.2)
	_item(root, root.global_position + _clock_panel.global_basis.z * 0.3 + Vector3.UP * 0.3, func(): return ["Ventilové kolo", "E  vzít"], func():
		has_wheel = true
		_inv_add("wheel")
		main.sfx.play("item_pickup", -3.0)
		mode._popup("Ventilové kolo", true)
		_remove_node(root), true)

func _wheel_mesh() -> Node3D:
	# Ruční kolo z modelu ventilu (zbytek ventilu se skryje).
	var v := _inst("valve", 0.75, 1)
	var parts := _valve_split(v)
	for m in parts.body: (m as Node3D).visible = false
	var holder := Node3D.new()
	holder.add_child(v)
	v.position = -parts.center
	return holder

func _valve_split(v: Node3D) -> Dictionary:
	# Rozdělí sítě ventilu na ruční kolo (nahoře) a tělo; vrací i střed kola v souřadnicích držáku.
	var wheel := []
	var body := []
	var b: AABB = Props._bounds(v)
	var top := b.end.y
	var wb := AABB()
	var first := true
	for m in v.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = Props._xf(m, v) * (m as MeshInstance3D).get_aabb()
		if a.get_center().y > top - b.size.y * 0.14:
			wheel.append(m)
			wb = a if first else wb.merge(a)
			first = false
		else:
			body.append(m)
	return {"wheel": wheel, "body": body, "center": wb.get_center() if not first else Vector3(0, top, 0)}

# --- ventily v kotelně
func _build_valves(space: PhysicsDirectSpaceState3D) -> void:
	var spot := _wall(space, 10, 2.8, 1.3)
	if spot.is_empty(): return
	var n: Vector3 = spot.normal
	var basis := _wall_basis(n)
	var tangent: Vector3 = basis.x
	var floor_at: Vector3 = spot.pos - Vector3.UP * 1.4
	for i in 3:
		var at: Vector3 = floor_at + tangent * (float(i) - 1.0) * 0.95 + n * 0.38
		var root := Node3D.new()
		add_child(root)
		root.global_transform = Transform3D(basis, at)
		var valve := _inst("valve", 0.75, 1)
		root.add_child(valve)
		var parts := _valve_split(valve)
		var pivot := Node3D.new()
		valve.add_child(pivot)
		pivot.position = parts.center
		for m in parts.wheel: (m as Node3D).reparent(pivot, true)
		pivot.visible = i != 2           # třetímu chybí kolo
		var gauge := _label3d("0", 30, Color(0.95, 0.92, 0.8))
		gauge.font = null
		root.add_child(gauge)
		gauge.position = Vector3(0, 0.98, -0.02)
		var dial := _cylmesh(0.065, 0.025, _mat(Color(0.12, 0.12, 0.12), 0.0, 0.6, 0.4))
		root.add_child(dial)
		dial.rotation.x = PI / 2
		dial.position = Vector3(0, 0.98, -0.045)
		var stand := _cylmesh(0.012, 0.25, _mat(Color(0.3, 0.3, 0.3), 0.0, 0.8, 0.4))
		root.add_child(stand)
		stand.position = Vector3(0, 0.83, -0.045)
		var roman := _label3d(["I", "II", "III"][i], 30, Color(0.9, 0.85, 0.6))
		roman.font = null
		root.add_child(roman)
		roman.position = Vector3(0, 0.2, 0.3)
		var v := {"value": 0, "wheel": pivot, "gauge": gauge, "index": i}
		v["item"] = _item(root, at + n * 0.45 + Vector3.UP * 0.9, func():
			if valves_done: return ["Ventil " + ["I", "II", "III"][i], "tlak drží"]
			if i == 2 and not pivot.visible:
				return ["Ventil III", "E  nasadit kolo" if has_wheel else "chybí kolo"]
			return ["Ventil %s   tlak %d" % [["I", "II", "III"][i], int(v.value)], "E  otočit"]
		, func():
			if valves_done: return
			if i == 2 and not pivot.visible:
				if has_wheel:
					has_wheel = false
					_inv_remove("wheel")
					pivot.visible = true
					main.sfx.play_at("lamp_click", root.global_position, -4.0, 0.6)
				return
			v.value = (int(v.value) + 1) % 6
			gauge.text = str(v.value)
			create_tween().tween_property(pivot, "rotation:y", pivot.rotation.y - TAU / 6.0, 0.35)
			main.sfx.play_at("chain", root.global_position, -12.0, 1.3)
			_check_valves())
		_valves.append(v)

func _check_valves() -> void:
	for v in _valves:
		if int(v.value) != int(valve_code[int(v.index)]): return
	if _valves.size() < 3 or not (_valves[2].wheel as Node3D).visible: return
	valves_done = true
	var at: Vector3 = (_valves[1].item.node as Node3D).global_position
	main.sfx.play_at("boiler_hum", at, 2.0, 0.6)
	main.sfx.play_at("whoomp", at, -2.0, 0.7)
	# Z trubky vypadne klíč od čerpadel.
	var root := Node3D.new()
	add_child(root)
	var fy := _floor_at(Vector2(at.x, at.z) + Vector2((_valves[1].item.node as Node3D).global_basis.z.x, (_valves[1].item.node as Node3D).global_basis.z.z) * 0.6)
	root.global_position = Vector3(at.x, (fy if fy != INF else at.y - 1.4) + 0.03, at.z) + (_valves[1].item.node as Node3D).global_basis.z * 0.6
	var key := _boxmesh(Vector3(0.05, 0.015, 0.16), _mat(Color(0.8, 0.65, 0.3), 0.0, 0.9, 0.3))
	root.add_child(key)
	var tag := _boxmesh(Vector3(0.06, 0.01, 0.04), _mat(Color(0.85, 0.1, 0.08)))
	root.add_child(tag)
	tag.position.z = 0.1
	_glow(root, Color(1.0, 0.8, 0.4), 0.3, 1.3).position.y = 0.2
	_item(root, root.global_position + Vector3(0, 0.3, 0), func(): return ["Klíč od čerpadel", "E  vzít"], func():
		has_key = true
		_inv_add("pumpkey")
		main.sfx.play("item_pickup", -3.0)
		mode._popup("Klíč od čerpadel", true)
		_radio("Control", "Čerpadla Síně anděla? Lantern, jestli tu vodu vypustíš, nevíme, co je pod ní.")
		_remove_node(root), true)

# --- čerpadlo a vypouštění Síně anděla
func _build_pump() -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = Vector3(44.6, -0.35, -24.0)
	root.rotation.y = -PI / 2
	var pump := _inst("pump", 2.6, 1)
	root.add_child(pump)
	var ap: AnimationPlayer = pump.find_children("*", "AnimationPlayer", true, false)[0] if not pump.find_children("*", "AnimationPlayer", true, false).is_empty() else null
	if ap:
		var anim: Animation = ap.get_animation(ap.get_animation_list()[0])
		anim.loop_mode = Animation.LOOP_LINEAR
		root.set_meta("anim", ap)
	# Ovládací pult vedle čerpadla.
	var panel := _boxmesh(Vector3(0.6, 1.1, 0.4), _mat(Color(0.2, 0.32, 0.45), 0.0, 0.5, 0.5))
	root.add_child(panel)
	panel.position = Vector3(1.35, 0.55, 0.35)
	var sign := _label3d("ČERPADLO Č. 2", 26, Color(0.95, 0.9, 0.3))
	sign.font = null
	root.add_child(sign)
	sign.position = Vector3(1.35, 0.9, 0.56)
	var collider := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.2, 2.6, 0.95)
	cs.shape = bs
	cs.position = Vector3(0.2, 1.3, 0)
	collider.add_child(cs)
	root.add_child(collider)
	_pump_light = _glow(root, Color(0.3, 1.0, 0.4), 0.0, 3.0)
	_pump_light.position = Vector3(1.35, 1.4, 0.4)
	_pump = _item(root, root.global_transform * Vector3(1.35, 0.3, 1.0), func():
		if drained: return ["Čerpadlo", "nádrž je prázdná"]
		if drain_stage >= 0:
			if _pump_jam: return ["Čerpadlo – ZASEKLÉ", "drž E  opravit   %d %%" % int(_pump_fix * 100.0)]
			return ["Čerpadlo", "vypouští se…  %d %%" % int(_drain_progress() * 100.0)]
		if not power: return ["Čerpadlo", "bez proudu"]
		if not has_key: return ["Čerpadlo", "zamčené – chybí klíč"]
		return ["Čerpadlo", "E  spustit vypouštění"]
	, func():
		if drain_stage < 0 and power and has_key and not drained:
			_start_drain())

func _drain_progress() -> float:
	return clampf((float(maxi(drain_stage, 0)) + _stage_t / 40.0) / 3.0, 0.0, 1.0)

func _inv_add(id: String, n := 1) -> void:
	if main.inventory: main.inventory.add(id, n)

func _inv_remove(id: String, n := 1) -> void:
	if main.inventory: main.inventory.remove(id, n)

func _start_drain() -> void:
	_inv_remove("pumpkey")
	drain_stage = 0
	_stage_t = 0.0
	_jam_at = randf_range(0.3, 0.7)
	_pump_light.light_energy = 1.2
	main.sfx.play_at("boiler_hum", _pump.node.global_position, 0.0, 0.8)
	if (_pump.node as Node3D).has_meta("anim"): ((_pump.node as Node3D).get_meta("anim") as AnimationPlayer).play(((_pump.node as Node3D).get_meta("anim") as AnimationPlayer).get_animation_list()[0])
	main.sfx.play_at("gate_open", _pump.node.global_position, -2.0, 0.5)
	var loop: AudioStreamPlayer3D = main.sfx.make_loop_3d("boiler_hum", (_pump.node as Node3D).global_position + Vector3.UP, -6.0)
	loop.pitch_scale = 0.7
	(_pump.node as Node3D).set_meta("loop", loop)
	_horde(10)

func _horde(n: int) -> void:
	# Vypouštění přitáhne hordu: když je klid mezi koly, kolo začne hned.
	if mode.state == "wait": mode._timer = minf(float(mode._timer), 1.0)
	elif mode.state == "round": mode._to_spawn = int(mode._to_spawn) + n

func _drain_tick(dt: float) -> void:
	if drain_stage < 0 or drained: return
	if (_pump.node as Node3D).has_meta("anim"):
		var ap: AnimationPlayer = (_pump.node as Node3D).get_meta("anim")
		ap.speed_scale = 0.0 if _pump_jam else 1.0
	if _pump_jam:
		var focus: Dictionary = st._focus
		if focus == _pump and Input.is_physical_key_pressed(KEY_E):
			_pump_fix += dt / 1.6
			if _pump_fix >= 1.0:
				_pump_jam = false
				_pump_light.light_color = Color(0.3, 1.0, 0.4)
				main.sfx.play_at("lamp_click", _pump.node.global_position, -2.0, 0.7)
		return
	_stage_t += dt
	if _stage_t / 40.0 > _jam_at and _jam_at > 0.0:
		_jam_at = -1.0
		_pump_jam = true
		_pump_fix = 0.0
		_pump_light.light_color = Color(1.0, 0.15, 0.1)
		main.sfx.play_at("zombie_bang", _pump.node.global_position + Vector3.UP, 0.0, 0.6)
		main.sfx.play_at("lamp_spark", _pump.node.global_position + Vector3.UP, -2.0)
	var level := lerpf(main.WATER_Y, ANGEL_FLOOR + 0.15, _drain_progress())
	_set_angel_level(level)
	if _stage_t >= 40.0:
		drain_stage += 1
		_stage_t = 0.0
		_jam_at = randf_range(0.25, 0.75)
		if drain_stage >= 3:
			_drain_done()
		else:
			_horde(8)
			main.sfx.play_at("splash_big", Vector3(33.5, level, -18.0), 0.0, 0.5)

func _set_angel_level(level: float) -> void:
	if _angel_water: _angel_water.position.y = level - main.WATER_Y
	if not _angel_zone.is_empty(): _angel_zone.level = level
	if _angel_water: _angel_water.visible = level > ANGEL_FLOOR + 0.2

func _drain_done() -> void:
	drained = true
	_set_angel_level(ANGEL_FLOOR + 0.1)
	_pump_light.light_energy = 0.3
	if (_pump.node as Node3D).has_meta("anim"): ((_pump.node as Node3D).get_meta("anim") as AnimationPlayer).pause()
	if (_pump.node as Node3D).has_meta("loop"):
		var loop: Node = (_pump.node as Node3D).get_meta("loop")
		if is_instance_valid(loop): loop.queue_free()
	main.sfx.play("whoomp", -2.0, 0.6)
	mode._show_banner("", "Síň anděla je vypuštěná", 2.6)
	# Zarezlá mříž na dně povolí.
	get_tree().create_timer(4.0).timeout.connect(func():
		_gate.locked = false
		_gate.state = "opening"
		_gate.t = 0.0
		(_gate.body.get_child(0) as CollisionShape3D).disabled = true
		main.sfx.play_at("gate_open", _gate.pos + Vector3(0, 1.5, 0), 2.0, 0.6)
		_radio("Control", "Lantern… na dně je průchod. Na plánech není. Buď opatrný."))

# --- křest zbraně (andělova voda u paty sochy, jen po vypuštění)
func _build_baptism() -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = Vector3(30.2, ANGEL_FLOOR, -24.5)
	var basin := _cylmesh(0.55, 0.5, _mat(Color(0.5, 0.5, 0.48), 0.0, 0.0, 0.9))
	root.add_child(basin)
	basin.position.y = 0.25
	var water := _cylmesh(0.48, 0.02, _mat(Color(0.35, 0.95, 0.9), 2.2))
	root.add_child(water)
	water.position.y = 0.5
	var glow := _glow(root, Color(0.35, 0.95, 0.9), 0.0, 4.0)
	glow.position.y = 1.0
	root.set_meta("glow", glow)
	_bap_root = root
	_item(root, root.global_position + Vector3(0, 0.9, 0.6), func():
		if not drained: return []
		var w: Node = main.player.weapon
		if _bap_state == "sink" or _bap_state == "bless": return ["Andělova voda", "voda si bere %s…" % w.STATS[_bap_gun].name]
		if _bap_state == "ready": return ["Andělova voda", "E  vzít %s" % w.stats_of(_bap_gun).name]
		if not w.equipped: return ["Andělova voda", "vezmi zbraň do ruky"]
		var tier: int = w.tier(w.current)
		if tier >= 4: return ["Andělova voda", "%s je pokřtěná" % w.display_name()]
		if tier < 3: return ["Andělova voda", "zbraň musí mít stupeň III"]
		return ["Andělova voda", "E  pokřtít %s" % w.display_name() + ("   %d" % BAPTISM_COST if not mode.horror() else "")]
	, func():
		if not drained: return
		var w: Node = main.player.weapon
		if _bap_state == "ready":
			_bap_take()
			return
		if _bap_state != "" or not w.equipped: return
		if w.tier(w.current) != 3: return
		if not st._pay(BAPTISM_COST): return
		_bap_begin())

var _bap_root: Node3D
var _bap_state := ""          # "" → sink (zbraň klesá) → bless (voda září) → ready (vznáší se, vzít E)
var _bap_gun := ""
var _bap_t := 0.0
var _bap_model: Node3D

func _bap_begin() -> void:
	var w: Node = main.player.weapon
	_bap_gun = String(w.current)
	w.holster()
	w.baptizing = _bap_gun
	var rig: Node = main.player.body.weapon
	_bap_model = _inst(String(rig.GUNS[_bap_gun].scene), 0.62 if _bap_gun != "deagle" else 0.3, -1)
	_bap_root.add_child(_bap_model)
	_bap_model.position = Vector3(0, 1.35, 0)
	_bap_model.rotation = Vector3(0, 0.6, PI / 2)       # hlavní dolů do vody
	_bap_state = "sink"
	_bap_t = 0.0
	main.sfx.play_at("splash_big", _bap_root.global_position + Vector3(0, 0.6, 0), -6.0)
	main.sfx.play("whoomp", -6.0, 0.6)

func _bap_tick(dt: float) -> void:
	if _bap_root == null: return
	var glow: OmniLight3D = _bap_root.get_meta("glow")
	if _bap_state == "" or _bap_model == null or not is_instance_valid(_bap_model):
		# Klidná křtitelnice po vypuštění jemně dýchá světlem.
		_bap_t += dt
		glow.light_energy = (3.2 + 0.5 * sin(_bap_t * 1.3)) if drained else 0.0
		return
	_bap_t += dt
	if _bap_state == "sink":
		var k: float = smoothstep(0.0, 1.0, _bap_t / 1.4)
		_bap_model.position.y = lerpf(1.35, 0.3, k)
		glow.light_energy = lerpf(4.0, 7.0, k)
		if _bap_t >= 1.4:
			_bap_state = "bless"
			_bap_t = 0.0
			main.sfx.play_at("powerup_spawn", _bap_root.global_position, -4.0, 0.7)
	elif _bap_state == "bless":
		glow.light_energy = 7.0 + 6.0 * absf(sin(_bap_t * 5.0)) + _bap_t * 3.0
		if _bap_t >= 2.6:
			var w: Node = main.player.weapon
			w.upgrade(_bap_gun)
			main.player.body.weapon.set_pap(_bap_gun, true)
			main.player.body.weapon.apply_pap_overlay(_bap_model)
			_bap_state = "ready"
			_bap_t = 0.0
			main.sfx.play("powerup", -2.0, 0.7)
			main.sfx.play_at("splash_big", _bap_root.global_position + Vector3(0, 0.6, 0), -4.0)
			mode._show_banner(w.stats_of(_bap_gun).name, "Pokřtěná ve vodě anděla", 2.6)
	elif _bap_state == "ready":
		var k: float = smoothstep(0.0, 1.0, minf(_bap_t / 1.1, 1.0))
		_bap_model.position.y = lerpf(0.3, 1.25, k) + sin(_bap_t * 1.7) * 0.03 * k
		_bap_model.rotation.z = lerpf(PI / 2, 0.0, k)
		_bap_model.rotation.y += dt * 0.7
		glow.light_energy = lerpf(glow.light_energy, 5.0 + sin(_bap_t * 2.0), 1.0 - exp(-3.0 * dt))

func _bap_take() -> void:
	var w: Node = main.player.weapon
	var gun := _bap_gun
	_bap_clear()
	w.switch_to(gun)
	main.sfx.play("powerup", -8.0, 1.2)

func _bap_clear() -> void:
	if _bap_model and is_instance_valid(_bap_model): _bap_model.queue_free()
	_bap_model = null
	if main and main.player and main.player.weapon: main.player.weapon.baptizing = ""
	_bap_state = ""
	_bap_gun = ""
	if _bap_root and _bap_root.has_meta("glow"): (_bap_root.get_meta("glow") as OmniLight3D).light_energy = 4.0 if drained else 0.0

# --- laboratoř v Nádrži
var _note_spot := Vector3(25.2, CISTERN_FLOOR + 0.92, -43.0)

func _build_lab() -> void:
	var lab := _inst("autopsy_lab", 3.1, -1)
	add_child(lab)
	lab.global_position = Vector3(23.8, CISTERN_FLOOR, -42.9)
	lab.rotation.y = PI / 2
	# Pitevní stůl: kolize a místo pro poslední lístek.
	var table: Node = lab.find_child("DissectionTable_Main*", true, false)
	if table:
		var b: AABB = Props._bounds_of(table, self)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b.size
		cs.shape = bs
		body.add_child(cs)
		add_child(body)
		body.global_position = b.get_center()
		_note_spot = Vector3(b.get_center().x, b.end.y + 0.01, b.get_center().z)
	# Dvě kapsle se vzorky u západní stěny.
	for z in [-53.0, -56.4]:
		var cap := _inst("capsule", 2.6, 1)
		add_child(cap)
		cap.global_position = Vector3(23.2, CISTERN_FLOOR, z)
		cap.rotation.y = PI / 2
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.55
		cyl.height = 2.6
		cs.shape = cyl
		cs.position.y = 1.3
		body.add_child(cs)
		cap.add_child(body)
		_glow(cap, Color(0.3, 0.9, 1.0), 0.9, 4.0).position = Vector3(0.6, 1.4, 0)

# --- UV nápisy
func _build_uv_texts(space: PhysicsDirectSpaceState3D) -> void:
	for l in _uv_labels:
		if is_instance_valid(l): l.queue_free()
	_uv_labels.clear()
	var texts := [
		[2, "PUSŤ VŠECHNY\nSPRCHY NAJEDNOU"],
		[12, "VENTIL I = %d" % valve_code[0]],
		[8, "VENTIL II = %d" % valve_code[1]],
		[15, "VENTIL III = %d" % valve_code[2]],
		[0, "ČAS SE VRACÍ\nPOZPÁTKU"],
		[6, "ONA ČEKÁ DOLE"],
		[3, "NEVĚŘ VELITELI"],
		[1, "Lantern  ·  2017"],
		[13, "kolik nás poslali před tebou?"],
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng.seed + 99
	for t in texts:
		var spot: Dictionary = st._find_wall(space, main.MAP_RECTS[int(t[0])], 1.8, 0.8, rng)
		if spot.is_empty(): continue
		var n: Vector3 = spot.normal
		var l := _label3d(String(t[1]), 96, Color(0.72, 0.5, 1.0, 0.0))
		l.pixel_size = 0.0045
		l.no_depth_test = false
		add_child(l)
		l.global_transform = Transform3D(_wall_basis(n).rotated(n, rng.randf_range(-0.12, 0.12)), spot.pos + n * 0.02 + Vector3.UP * rng.randf_range(-0.2, 0.4))
		_uv_labels.append(l)

func _update_uv() -> void:
	var cam: Camera3D = main.player.camera
	if cam == null: return
	var from := cam.global_position
	var fwd := -cam.global_basis.z
	for l in _uv_labels:
		if not is_instance_valid(l): continue
		var a := 0.0
		if uv_on and main.flashlight and main.flashlight.visible:
			var to: Vector3 = (l as Node3D).global_position - from
			var d := to.length()
			if d < 9.0:
				var cosang := fwd.dot(to / d)
				a = smoothstep(0.86, 0.95, cosang) * (1.0 - smoothstep(6.5, 9.0, d))
		var c: Color = (l as Label3D).modulate
		c.a = move_toward(c.a, a * 0.95, 0.15)
		(l as Label3D).modulate = c
		(l as Label3D).visible = c.a > 0.01

func toggle_flash() -> bool:
	# F: s UV lampou se cyklí vypnuto → bílé světlo → UV → vypnuto. Vrací true, když to vyřídila.
	if not has_uv or main.flashlight == null: return false
	var f: SpotLight3D = main.flashlight
	if not f.visible:
		f.visible = true
		uv_on = false
	elif not uv_on:
		uv_on = true
	else:
		f.visible = false
		uv_on = false
	f.light_color = Color(0.5, 0.25, 1.0) if uv_on else Color(1.0, 0.86, 0.62)
	if main._flash_spill: main._flash_spill.light_color = f.light_color
	main.sfx.play("tick", -6.0, 1.8 if uv_on else (1.5 if f.visible else 1.1))
	return true

# --- plovoucí tělo s náramkem
func _spawn_body() -> void:
	if is_instance_valid(_body): _body.queue_free()
	var spot: Vector3 = BODY_SPOTS[0]
	for s in BODY_SPOTS:
		var fy := _floor_at(Vector2(s.x, s.z))
		if fy != INF and fy < -0.15:
			spot = Vector3(s.x, fy, s.z)
			break
	var z: Node3D = mode._make(1, "classic")
	mode._zombies.erase(z)
	z.position = spot
	z.rotation.y = randf() * TAU
	z.target = main.player
	z.set_meta("quest", true)
	z.set_meta("quest_band", true)
	main.add_child(z)
	z.lie_down.call_deferred()
	_body = z

# --- kufry s lootem (zbraň, munice, injekce, materiál) rozházené po mapě
const CASE_SPOTS := [Vector2(-11.0, -3.0), Vector2(11.0, -24.6), Vector2(-17.5, -12.8), Vector2(40.0, 20.5), Vector2(-8.0, -49.0),
	Vector2(20.0, -50.0), Vector2(8.0, -30.0), Vector2(40.0, 1.0), Vector2(13.0, 6.6), Vector2(-3.6, 1.6), Vector2(47.0, 14.0),
	Vector2(60.0, 38.0), Vector2(-26.0, -45.0), Vector2(-9.0, 8.4)]

func _place_cases() -> void:
	var spots := CASE_SPOTS.duplicate()
	spots.shuffle()
	var made := 0
	var free_spots := []
	for xz in spots:
		if made >= 7:
			free_spots.append(xz)
			continue
		var fy := _floor_at(xz)
		if fy == INF: continue
		made += 1
		var root := Node3D.new()
		add_child(root)
		root.global_position = Vector3(xz.x, fy, xz.y)
		root.rotation.y = randf() * TAU
		var case_model := _inst("res://assets/props2/weapon_case.glb", 1.0, 0)
		root.add_child(case_model)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.0, 0.18, 0.45)
		cs.shape = bs
		cs.position.y = 0.09
		body.add_child(cs)
		root.add_child(body)
		var roll := randf()
		var w: Node = main.player.weapon
		var guns := ["ak", "mp40", "izh54", "deagle"]
		var loot: String = "gun" if roll < 0.3 else ("ammo" if roll < 0.55 else ("heal" if roll < 0.7 else ("parts" if roll < 0.76 else ("gears" if roll < 0.85 else ("pumpkin" if roll < 0.93 else "chlor")))))
		var gun: String = guns.pick_random() if loot == "gun" else ""
		var shown: Node3D
		match loot:
			"gun":
				shown = st._gun_scenes[gun].instantiate()
				shown.basis = Basis(Vector3.RIGHT, PI / 2) * Basis(Vector3.UP, PI / 2)
				shown.scale = Vector3.ONE * 0.85
			"ammo":
				shown = Props.make("ammo")
				shown.scale = Vector3.ONE * 0.6
			"heal":
				shown = Props.make("syringe")
			"parts":
				shown = _inst("fuse", 0.18, 0)
			"chlor":
				shown = _boxmesh(Vector3(0.22, 0.08, 0.14), _mat(Color(0.88, 0.9, 0.92)))
			"pumpkin":
				shown = Props.make("pumpkin")
				shown.scale = Vector3.ONE * 0.45
			"gears":
				shown = Node3D.new()
				for gi in 2:
					var g := _gear_mesh(randi() % 5, 0.15 - gi * 0.03)
					shown.add_child(g)
					g.position = Vector3(gi * 0.06 - 0.03, gi * 0.012, gi * 0.03)
					g.rotation.y = randf() * TAU
		root.add_child(shown)
		shown.position.y += 0.12
		var label: String = {"gun": "", "ammo": "Munice", "heal": "Injekce", "parts": "Součástky", "chlor": "Chlórové tablety", "gears": "Ozubená kola", "pumpkin": "Dýňová bomba"}[loot]
		if loot == "gun": label = w.STATS[gun].name
		_item(root, root.global_position + Vector3(0, 0.3, 0), func():
			if not is_instance_valid(shown): return ["Kufr", "prázdný"]
			return ["Kufr  ·  " + label, "E  vzít"]
		, func():
			if not is_instance_valid(shown): return
			shown.queue_free()
			_take_case(loot, gun), true)
	_place_bombs(free_spots)

func _place_bombs(spots: Array) -> void:
	# Dvě dýňové bomby leží volně na místech, kde nejsou kufry.
	var placed := 0
	for xz in spots:
		if placed >= 2: break
		var fy := _floor_at(xz)
		if fy == INF: continue
		placed += 1
		var root := Node3D.new()
		add_child(root)
		root.global_position = Vector3(xz.x + randf_range(-0.4, 0.4), fy, xz.y + randf_range(-0.4, 0.4))
		var pk := Props.make("pumpkin")
		pk.scale = Vector3.ONE * 0.45
		pk.rotation.y = randf() * TAU
		root.add_child(pk)
		_glow(root, Color(1.0, 0.5, 0.1), 0.3, 1.4).position.y = 0.25
		_item(root, root.global_position + Vector3(0, 0.3, 0), func(): return ["Dýňová bomba", "E  vzít"], func():
			if main.inventory and main.inventory.add("pumpkin", 1) > 0: return
			main.sfx.play("item_pickup", -3.0, 0.9)
			mode._popup("Dýňová bomba – vezmi do ruky v inventáři (I)", true)
			_remove_node(root), true)

func _take_case(loot: String, gun: String) -> void:
	var w: Node = main.player.weapon
	main.sfx.play("item_pickup", -3.0)
	match loot:
		"gun":
			if w.owned.has(gun):
				# Zbraň už má: vezme si z kufru aspoň plnou munici do ní.
				w._store()
				w.clips[gun] = [w.stats_of(gun).mag, w.stats_of(gun).reserve]
				w._load_current()
				mode._show_banner("", "Munice doplněna", 1.2)
			else:
				w.give(gun, true)
				main.sfx.play("powerup", -8.0)
		"ammo": _inv_add("ammo")
		"heal": _inv_add("syringe")
		"parts": add_mat("parts", 2)
		"chlor": add_mat("chlor", 2)
		"gears": add_mat("gears", 2)
		"pumpkin": _inv_add("pumpkin")

var _kid: Node3D
var _knock_t := 8.0

func _spawn_kid() -> void:
	# Dítě schované v poslední kabince na toaletách – vstane, až hráč nakoukne dovnitř.
	if is_instance_valid(_kid): _kid.queue_free()
	var z: Node3D = mode._make(1, "kid")
	mode._zombies.erase(z)
	z.position = Vector3(18.9, 0.5, 7.25)
	z.rotation.y = randf() * TAU
	z.target = main.player
	z.set_meta("quest", true)
	main.add_child(z)
	z.lie_down.call_deferred()
	_kid = z

func _knock_tick(dt: float) -> void:
	# Ze zamčené kabinky se občas ozve bouchání.
	_knock_t -= dt
	if _knock_t > 0.0: return
	_knock_t = randf_range(9.0, 22.0)
	var at := Vector3(18.8, 1.4, 4.25)
	if main.player.global_position.distance_to(at) < 9.0:
		for i in randi_range(2, 4):
			get_tree().create_timer(i * randf_range(0.3, 0.55)).timeout.connect(func(): main.sfx.play_at("zombie_bang", at, -6.0, randf_range(1.05, 1.25)))

func zombie_died(z: Node3D, spot: Vector3) -> void:
	if z.has_meta("quest_band"):
		_drop_band(spot)
	if randf() < 0.3: add_mat("scrap", 1)
	# Ozubená kola na vylepšení zbraní: vzácně vypadnou na zem, v pozdějších kolech o něco častěji.
	var chance: float = minf(0.06 + float(mode.round_now) * 0.004, 0.14)
	if randf() < chance and _gears.size() < 5: _drop_gear(spot)

# --- ozubená kola
var _gears: Array = []          # {root, t}
const GEAR_LIFE := 45.0

func _gear_mesh(idx: int, size: float) -> Node3D:
	# Jedno kolo ze sady (5 různých), položené naplocho a zmenšené na danou velikost.
	var holder := Node3D.new()
	var pivot := Node3D.new()
	holder.add_child(pivot)
	var m: Node3D = (load(QA + "gears.glb") as PackedScene).instantiate()
	pivot.add_child(m)
	var names := ["gear1", "gear2", "gear4", "gear5", "gear7"]
	var keep: Node3D = null
	for n in names:
		var g := m.find_child(n, true, false) as Node3D
		if g == null: continue
		if n == names[idx % names.size()]: keep = g
		else: g.get_parent().remove_child(g); g.queue_free()
	var b: AABB = Props._bounds(pivot)
	var k := size / maxf(maxf(b.size.x, b.size.z), 0.0001)
	pivot.scale = Vector3.ONE * k
	b = Props._bounds(holder)
	pivot.position = -Vector3(b.get_center().x, b.position.y, b.get_center().z)
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return holder

func _drop_gear(spot: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	var fy := _floor_at(Vector2(spot.x, spot.z))
	var wl: float = main.water_level_at(spot)
	var y: float = fy if fy != INF else spot.y
	if wl > y: y = wl + 0.02          # ve vodě plave na hladině
	root.global_position = Vector3(spot.x + randf_range(-0.3, 0.3), y + 0.01, spot.z + randf_range(-0.3, 0.3))
	var gear := _gear_mesh(randi() % 5, 0.17)
	root.add_child(gear)
	gear.rotation = Vector3(randf_range(-0.08, 0.08), randf() * TAU, randf_range(-0.08, 0.08))
	var light := _glow(root, Color(1.0, 0.78, 0.45), 0.35, 1.6)
	light.position.y = 0.25
	var entry := {"root": root, "t": 0.0, "light": light, "gear": gear}
	_gears.append(entry)
	main.sfx.play_at("ball_hit", root.global_position, -10.0, 1.8)   # cinknutí kovu o dlaždice
	_item(root, root.global_position + Vector3(0, 0.25, 0), func(): return ["Ozubené kolo", "E  vzít"], func():
		_gears.erase(entry)
		add_mat("gears", 1)
		main.sfx.play("item_pickup", -3.0, 1.15)
		_remove_node(root), true)

func _gear_tick(dt: float) -> void:
	for i in range(_gears.size() - 1, -1, -1):
		var e: Dictionary = _gears[i]
		if not is_instance_valid(e.root):
			_gears.remove_at(i)
			continue
		e.t = float(e.t) + dt
		var t: float = e.t
		# Jemný záblesk, ať je kolo v šeru vidět; posledních 8 s bliká a pak zmizí.
		var pulse := 0.28 + 0.12 * sin(t * 2.6)
		if t > GEAR_LIFE - 8.0: pulse *= 1.0 if fmod(t * (2.0 + (t - GEAR_LIFE + 8.0)), 1.0) < 0.6 else 0.0
		(e.light as OmniLight3D).light_energy = pulse
		(e.gear as Node3D).visible = pulse > 0.0 or t <= GEAR_LIFE - 8.0
		if t >= GEAR_LIFE:
			_gears.remove_at(i)
			_remove_node(e.root)

func _drop_band(spot: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	var fy := _floor_at(Vector2(spot.x, spot.z))
	root.global_position = Vector3(spot.x, (fy if fy != INF else spot.y) + 0.03, spot.z)
	var band := _inst("wristband", 0.12, 0)
	root.add_child(band)
	var tag := _label3d("37", 40, Color(1, 1, 1))
	tag.font = null
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(tag)
	tag.position.y = 0.12
	_glow(root, Color(1.0, 0.4, 0.3), 0.35, 1.5).position.y = 0.3
	_item(root, root.global_position + Vector3(0, 0.3, 0), func(): return ["Gumový náramek č. 37", "E  vzít"], func():
		has_band = true
		_inv_add("band")
		main.sfx.play("item_pickup", -3.0)
		mode._popup("Náramek od skříňky 37", true)
		_remove_node(root), true)

func took_uv() -> void:
	has_uv = true
	_inv_add("uv")
	main.sfx.play("powerup", -6.0, 0.8)
	mode._show_banner("UV lampa", "F přepíná: světlo → UV → vypnuto", 3.0)
	main.notes.open_text("Lístek ve skříňce 37", "Kdo tohle najde – sviť UV na zdi.\nPsal jsem všude, kam jsem došel.\n\nVoda není to nejhorší.\nTo nejhorší je, co ji drží\nna dně Síně anděla.\n\nVelitel ví, kolik nás bylo.\n\n— L.")

# --- přepadení z vody
func _ambush_tick(dt: float) -> void:
	if mode.state != "round" or int(mode._to_spawn) <= 0: return
	_ambush_t -= dt
	if _ambush_t > 0.0: return
	_ambush_t = randf_range(35.0, 70.0)
	var p: Node3D = main.player
	var back: Vector3 = p.camera.global_basis.z
	back.y = 0.0
	back = back.normalized()
	var space := get_world_3d().direct_space_state
	for attempt in 10:
		var dir: Vector3 = back.rotated(Vector3.UP, randf_range(-0.9, 0.9))
		var at: Vector3 = p.global_position + dir * randf_range(3.2, 6.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, 1.5, at.z), Vector3(at.x, -20.0, at.z), 1))
		if hit.is_empty(): continue
		var level: float = main.water_level_at(at)
		if (hit.position as Vector3).y > level - 1.0: continue
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(p.camera.global_position, Vector3(at.x, level + 0.5, at.z), 1)).is_empty(): continue
		var z: Node3D = mode._make(int(mode.round_now))
		z.position = Vector3(at.x, level, at.z)
		main.add_child(z)
		z.emerge()
		mode._to_spawn = int(mode._to_spawn) - 1
		return

# --- Nádrž a Anděl
func _boss_tick(dt: float) -> void:
	var p: Vector3 = main.player.global_position
	if boss_state == "none":
		if drained and CISTERN.has_point(Vector2(p.x, p.z)) and p.y < -10.0 and Vector2(p.x, p.z).distance_to(CISTERN.get_center()) < 9.0:
			_boss_rise()
		return
	if boss_state != "fight" and boss_state != "rising": return
	# Srdce sledují kosti animovaného Anděla.
	if is_instance_valid(_boss) and _boss.has_meta("skel"):
		var sk: Skeleton3D = _boss.get_meta("skel")
		for w in _weak:
			if not is_instance_valid(w.body): continue
			var bi := sk.find_bone(String(w.bone))
			if bi < 0: continue
			var t: Transform3D = sk.global_transform * sk.get_bone_global_pose(bi)
			(w.body as Node3D).global_position = t.origin + t.basis.z.normalized() * 0.35
	if boss_state != "fight": return
	_boss_t -= dt
	for w in _weak:
		var m: MeshInstance3D = w.mesh
		if is_instance_valid(m): m.scale = Vector3.ONE * (1.0 + 0.12 * sin(Time.get_ticks_msec() / 160.0 + float(w.hp)))
	if _boss_t <= 0.0:
		_boss_t = randf_range(9.0, 14.0)
		main.sfx.play_at("stinger", _boss.global_position + Vector3.UP * 4.0, 2.0, 0.55)
		# Anděl volá utopence: vynoří se z vody kolem něj.
		for i in 3:
			var a := randf() * TAU
			var at := Vector3(CISTERN.get_center().x + cos(a) * randf_range(5.0, 9.0), main.water_level_at(Vector3(CISTERN.get_center().x, 0, CISTERN.get_center().y)), CISTERN.get_center().y + sin(a) * randf_range(5.0, 8.0))
			var z: Node3D = mode._make(maxi(int(mode.round_now), 6))
			z.position = at
			main.add_child(z)
			z.emerge()

func _boss_rise() -> void:
	boss_state = "rising"
	_horde(12)
	for L in main.lamps:
		var light: Light3D = L.light
		if is_instance_valid(light) and light.global_position.y < -5.0: light.light_energy *= 0.4
	main.sfx.play("whoomp", 0.0, 0.5)
	_radio("Control", "Lantern, co se tam děje? Signál… Lantern!")
	var c := CISTERN.get_center()
	# Anděl: kostlivec s deseti pažemi a svatozáří (model angel_boss, ~6 m).
	_boss = Node3D.new()
	add_child(_boss)
	var model: Node3D = (load(QA + "angel_boss.glb") as PackedScene).instantiate()
	_boss.add_child(model)
	model.scale = Vector3.ONE * 200.0
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).extra_cull_margin = 8.0
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		var ap: AnimationPlayer = aps[0]
		var anim_name: StringName = ap.get_animation_list()[0]
		ap.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		ap.play(anim_name)
	for sk in model.find_children("*", "Skeleton3D", true, false):
		if (sk as Skeleton3D).find_bone("skeleton_chest_06") >= 0: _boss.set_meta("skel", sk)
	var light := _glow(_boss, Color(0.9, 0.85, 1.0), 2.0, 12.0)
	light.position = Vector3(0, 7.0, 1.5)
	_boss.global_position = Vector3(c.x, CISTERN_FLOOR - 6.8, c.y)
	var tw := create_tween()
	tw.tween_property(_boss, "global_position:y", CISTERN_FLOOR + 0.2, 6.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	main.sfx.play_at("splash_big", Vector3(c.x, CISTERN_FLOOR + 0.5, c.y), 4.0, 0.4)
	main.sfx.play_at("stinger", Vector3(c.x, CISTERN_FLOOR + 3.0, c.y), 4.0, 0.5)
	var hp := 2500.0 + 300.0 * float(mode.round_now)
	for bone_name in ["skeleton_chest_06", "skeleton_head_09", "skeleton_root_pelvis_03"]:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.42
		cs.shape = sph
		body.add_child(cs)
		add_child(body)
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.4
		sm.height = 0.8
		sm.material = _mat(Color(0.85, 0.05, 0.05), 3.0, 0.0, 0.3)
		m.mesh = sm
		body.add_child(m)
		_glow(body, Color(1.0, 0.1, 0.05), 1.2, 4.0)
		var w := {"body": body, "mesh": m, "hp": hp, "bone": bone_name}
		body.set_meta("shootable", self)
		body.set_meta("weak", w)
		_weak.append(w)
	await tw.finished
	boss_state = "fight"
	_boss_t = 4.0
	mode._show_banner("ANDĚL", "Zasáhni tři rudá srdce", 3.0)

func shot(collider: Object, point: Vector3, _direction: Vector3) -> void:
	# Zásah do srdce Anděla (volá střelba přes meta „shootable“).
	if boss_state != "fight" or not collider.has_meta("weak"): return
	var w: Dictionary = collider.get_meta("weak")
	if float(w.hp) <= 0.0: return
	var dmg: float = float(main.player.weapon.damage)
	w.hp = float(w.hp) - dmg
	main.sfx.play_at("gore_smash", point, -6.0, randf_range(0.7, 0.9))
	if float(w.hp) <= 0.0:
		main.sfx.play_at("gib", point, 0.0, 0.6)
		main.sfx.play_at("stinger", point, 2.0, 0.6)
		(w.body as Node3D).queue_free()
		var left := 0
		for x in _weak:
			if float(x.hp) > 0.0: left += 1
		if left == 0: _boss_dead()
		else: mode._popup("Srdce: zbývá %d" % left, true)

func _boss_dead() -> void:
	boss_state = "dead"
	main.sfx.play("whoomp", 2.0, 0.4)
	var tw := create_tween()
	tw.tween_property(_boss, "global_position:y", CISTERN_FLOOR - 8.0, 7.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(_boss.queue_free)
	for w in _weak:
		if is_instance_valid(w.body): (w.body as Node).queue_free()
	# Všechno živé v lázních padne.
	for z in ZombieScript.crowd.duplicate():
		if is_instance_valid(z) and not z.dead and z.ai:
			z.hit(randi() % 8, z.global_position + Vector3.UP, Vector3.UP, 1.5, 99999.0)
	mode._to_spawn = 0
	mode._show_banner("", "Anděl padl", 3.0)
	# Na stole v laboratoři zůstane poslední lístek.
	var root := Node3D.new()
	add_child(root)
	root.global_position = _note_spot
	var paper := _boxmesh(Vector3(0.21, 0.004, 0.28), _mat(Color(0.92, 0.88, 0.75), 0.4))
	root.add_child(paper)
	_glow(root, Color(1.0, 0.9, 0.7), 0.6, 2.5).position.y = 0.5
	_item(root, root.global_position + Vector3(0, -0.3, 0), func(): return ["Lístek", "E  číst"], func():
		main.notes.open_text("Hlášení – Lantern", "Control, tady Lantern.\nNašel jsem zdroj. Je pod Síní anděla.\nPosílám vzorky, jak jste chtěli.\n\nJestli tohle čte další z nás:\nnikdo pro tebe nepřijde.\nMy jsme ta zkouška.\n\n— Lantern, 14. 3. 2017", _ending), true)

# ------------------------------------------------------------------ konec
func _ending() -> void:
	if ended: return
	ended = true
	_radio("Control", "Lantern… vzorky máme. Dobrá práce.")
	_radio("Control", "Zůstaň na místě. Pošleme dalšího.")
	await get_tree().create_timer(9.0).timeout
	main.player.control_enabled = false
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_layer.add_child(fade)
	var text := Label.new()
	text.set_anchors_preset(Control.PRESET_FULL_RECT)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", 34)
	text.modulate.a = 0.0
	text.text = "H L A D I N A\n\n\nPřežil jsi %d kol.\nZabití: %d\n\nNejsi první Lantern.\nA nebudeš poslední." % [int(mode.round_now), int(mode.kills)]
	_end_layer.add_child(text)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 3.0)
	tw.parallel().tween_property(main.sfx, "fade", 0.0, 3.5)
	tw.tween_property(text, "modulate:a", 1.0, 1.5)
	tw.tween_interval(7.0)
	tw.tween_property(text, "modulate:a", 0.0, 1.2)
	tw.tween_callback(func():
		fade.queue_free()
		text.queue_free()
		main.sfx.fade = 1.0
		mode.reset()
		main._open_main_menu())

func _radio(speaker: String, text: String) -> void:
	if main.voice and main.voice.has_method("say_text"): main.voice.say_text(speaker, text)

# ------------------------------------------------------------------ hra
func reset() -> void:
	# Nová hra: všechno zpět, secrety se zamíchají.
	_bap_clear()
	for e in _gears:
		if is_instance_valid(e.root): _remove_node(e.root)
	_gears.clear()
	mats = {"scrap": 0, "parts": 0, "chlor": 0, "gears": 0}
	if main.inventory: main.inventory.reset()
	fuses = 0
	fuses_in = 0
	power = false
	has_band = false
	has_uv = false
	uv_on = false
	mirror_seen = false
	has_wheel = false
	clock_done = false
	valves_done = false
	has_key = false
	drain_stage = -1
	drained = false
	boss_state = "none"
	ended = false
	_pump_jam = false
	_stage_t = 0.0
	_last_round = 0
	_ambush_t = randf_range(30.0, 60.0)
	if st == null: return
	for item in _pickups.duplicate(): _remove(item)
	_chlor_items.clear()
	valve_code = [randi_range(1, 5), randi_range(1, 5), randi_range(1, 5)]
	clock_target = randi_range(0, 47) * 15
	clock_now = (clock_target + randi_range(8, 40) * 15) % 720
	_pose_clock()
	for i in 3: _show_fuse(i, false)
	if _fuse_box.has("node"):
		var lever: Node3D = _fuse_box.node.get_meta("lever")
		lever.rotation.x = 0.6
	for t in _taps:
		t.on = false
		(t.stream as GPUParticles3D).emitting = false
		if t.loop: (t.loop as Node).queue_free()
		t.loop = null
	if _steam: (_steam.material as FogMaterial).density = 0.0
	if _mirror_text:
		_mirror_text.text = ""
		_mirror_text.modulate.a = 0.0
	if _clock_panel: _clock_panel.rotation.y = 0.0
	for v in _valves:
		v.value = 0
		(v.gauge as Label3D).text = "0"
		(v.wheel as Node3D).visible = int(v.index) != 2
	if _pump_light:
		_pump_light.light_energy = 0.0
		_pump_light.light_color = Color(0.3, 1.0, 0.4)
	if not _pump.is_empty():
		if (_pump.node as Node3D).has_meta("loop"):
			var loop: Node = (_pump.node as Node3D).get_meta("loop")
			if is_instance_valid(loop): loop.queue_free()
			(_pump.node as Node3D).remove_meta("loop")
	_set_angel_level(main.WATER_Y)
	if not _gate.is_empty(): _gate.locked = true
	if is_instance_valid(_boss): _boss.queue_free()
	for w in _weak:
		if is_instance_valid(w.body): (w.body as Node).queue_free()
	_weak.clear()
	for item in st.items:
		if item.kind == "quest" and item.node.has_meta("full"): item.node.set_meta("full", true)
		if item.kind == "quest" and item.node.has_meta("wires"): (item.node.get_meta("wires") as Node3D).visible = true
		if item.kind == "locker" and item.get("lock37", false): item["opened37"] = false
	if main.flashlight:
		main.flashlight.light_color = Color(1.0, 0.86, 0.62)
	var space := get_world_3d().direct_space_state
	_build_uv_texts(space)
	_place_fuses()
	_place_chlor()
	_spawn_body()
	_spawn_kid()
	_place_cases()

func _process(dt: float) -> void:
	if main == null or st == null or mode == null: return
	var playing: bool = mode.active and mode.state != "dead"
	_hud.visible = false           # materiály a předměty ukazuje inventář (Tab)
	if not playing: return
	_update_uv()
	_knock_tick(dt)
	_drain_tick(dt)
	_bap_tick(dt)
	_gear_tick(dt)
	_ambush_tick(dt)
	_boss_tick(dt)
	# Kbelíky s chlórem se doplní každé 3 kola.
	if int(mode.round_now) != _last_round:
		_last_round = int(mode.round_now)
		if _last_round > 1 and _last_round % 3 == 1:
			for root in _chlor_items:
				if is_instance_valid(root): root.set_meta("full", true)
	_hud.text = _hud_text()

func _hud_text() -> String:
	var lines := ["Šrot %d     Součástky %d     Chlór %d" % [int(mats.scrap), int(mats.parts), int(mats.chlor)]]
	var items := []
	if fuses > 0: items.append("Pojistky %d" % fuses)
	if has_band: items.append("Náramek 37")
	if has_uv: items.append("UV lampa" + (" ●" if uv_on else ""))
	if has_wheel: items.append("Ventilové kolo")
	if has_key: items.append("Klíč od čerpadel")
	if not items.is_empty(): lines.append("   ·   ".join(items))
	return "\n".join(lines)

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 6
	add_child(_layer)
	_hud = Label.new()
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.add_theme_font_size_override("font_size", 19)
	_hud.add_theme_constant_override("outline_size", 6)
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hud.add_theme_color_override("font_color", Color(0.92, 0.9, 0.82, 0.9))
	_hud.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hud.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hud.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hud.offset_right = -40
	_hud.offset_bottom = -185
	_layer.add_child(_hud)
	_end_layer = CanvasLayer.new()
	_end_layer.layer = 55
	add_child(_end_layer)
