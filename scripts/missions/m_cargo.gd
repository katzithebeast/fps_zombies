extends "res://scripts/missions/mission.gd"
## Náklad z vrtulníku: ve vodě leží vrak, kolem plavou bedny se zelenými chemickými světly.
## Bednu jde nést jen jednu (zbraň je schovaná, jde se pomaleji) a nosí se k táboru u výsadku.

const COUNT := 3

var cases: Array = []
var delivered := 0
var wreck_pos := Vector3.ZERO
var _beacon: OmniLight3D
var _t := 0.0

func _init() -> void:
	title = "Vyzvedni náklad"
	brief = "Mi-8 s nákladem z laboratoře spadl do bažiny. Bedny plavou kolem vraku, poznáte je podle zelených světel. Doneste všechny tři k táboru."

func place() -> void:
	var th: Dictionary = main.mission_theme()
	var pts: Array = main.mission_points(1, {"where": "water", "min_spawn": 38.0, "clear": 6.0})
	if pts.is_empty(): pts = main.mission_points(1, {"where": "any", "min_spawn": 30.0, "clear": 4.0})
	wreck_pos = pts[0]
	var yaw: float = main.rng.randf() * TAU
	var wreck: Node3D = director.place_model(main, th.wreck, 13.5, wreck_pos + Vector3(0, -0.85, 0), yaw, Vector3(0.1, 0, 0.16))
	var sz: Vector3 = wreck.get_meta("size")
	director.collider(main, Vector3(sz.x * 0.45, 2.6, sz.z * 0.6), Transform3D(Basis(Vector3.UP, yaw), wreck_pos + Vector3(0, 0.4, 0)))
	# rozbitý, ale pořád blikající červený maják na ocasu
	_beacon = OmniLight3D.new()
	_beacon.light_color = Color(1.0, 0.12, 0.05)
	_beacon.omni_range = 10.0
	_beacon.light_volumetric_fog_energy = 2.0
	main.add_child(_beacon)
	_beacon.global_position = wreck_pos + Basis(Vector3.UP, yaw) * Vector3(0, 2.4, sz.z * 0.42)
	# bedny okolo vraku
	for i in COUNT:
		var p := Vector3.ZERO
		for attempt in 60:
			var a: float = main.rng.randf() * TAU
			var d: float = main.rng.randf_range(6.0, 17.0)
			p = wreck_pos + Vector3(cos(a) * d, 0, sin(a) * d)
			if absf(p.x) > main.R - main.WALL - 3.0 or absf(p.z) > main.R - main.WALL - 3.0: continue
			var ok := true
			for c in cases:
				if (c.pos as Vector3).distance_to(p) < 5.0: ok = false
			if ok and main.ground(p.x, p.z) > -0.95: break
		var n: Node3D = director.place_model(main, th.cargo, 0.95, Vector3.ZERO, main.rng.randf() * TAU)
		_chemlight(n)
		var c := {"node": n, "pos": p, "done": false, "ph": main.rng.randf() * TAU}
		c.act = director.add_action(p, "Vzít bednu", 0.8, _pick.bind(c), true, 2.6)
		cases.append(c)
		_settle(c, p)

func _chemlight(n: Node3D) -> void:
	var stick: MeshInstance3D = director.box(n, Vector3(0.03, 0.03, 0.16), Vector3(0.25, 0.5, 0.1), Color(0.35, 1.0, 0.3), 6.0)
	stick.rotation.y = 0.6
	var l := OmniLight3D.new()
	l.light_color = Color(0.35, 1.0, 0.35)
	l.light_energy = 0.9
	l.omni_range = 5.0
	l.light_volumetric_fog_energy = 1.5
	l.position = Vector3(0.25, 0.65, 0.1)
	n.add_child(l)

## Umístí bednu: na vodě plave, na souši leží.
func _settle(c: Dictionary, p: Vector3) -> void:
	c.pos = p
	c.act.pos = p
	c.act.on = true
	var g: float = main.ground(p.x, p.z)
	c.floating = g < main.WATER_Y - 0.15
	(c.node as Node3D).global_position = Vector3(p.x, (main.WATER_Y - 0.18) if c.floating else g, p.z)
	(c.node as Node3D).rotation = Vector3(0, (c.node as Node3D).rotation.y, 0)

func _pick(c: Dictionary) -> void:
	director.carry(c.node, func(_n: Node3D, p: Vector3): _settle(c, p))

func tick(dt: float) -> void:
	_t += dt
	if _beacon: _beacon.light_energy = 3.5 if fmod(_t, 1.6) < 0.15 else 0.0
	for c in cases:
		if c.done or director.carrying == c.node: continue
		if c.floating:
			var n: Node3D = c.node
			n.global_position.y = main.WATER_Y - 0.18 + sin(_t * 1.2 + c.ph) * 0.035
			n.rotation.x = sin(_t * 0.9 + c.ph) * 0.04
			n.rotation.z = cos(_t * 0.7 + c.ph) * 0.05
	# donesení k táboru
	var drop: Vector3 = main.cargo_drop
	if director.carrying and Vector2(director.player.global_position.x - drop.x, director.player.global_position.z - drop.z).length() < 4.5:
		for c in cases:
			if director.carrying == c.node:
				var n: Node3D = director.release()
				c.done = true
				var off := Vector3((delivered % 2) * 1.05 - 0.5, 0, 0)
				n.global_position = Vector3(drop.x + off.x, main.ground(drop.x, drop.z) + (0.58 if delivered >= 2 else 0.0), drop.z)
				n.rotation = Vector3.ZERO
				delivered += 1
				director.snd("res://audio/crate_close.wav", -2.0, 0.8)
				director.radio("Centrála: Bedna %d z %d. Pokračujte." % [delivered, COUNT] if delivered < COUNT else "Centrála: Máme všechny.", 4.0)
				if delivered == COUNT: complete()
				break

func lines() -> Array:
	var l := ["Bedny u tábora: %d/%d" % [delivered, COUNT]]
	if director.carrying: l.append("Neseš bednu – k táboru u výsadku")
	return l

func targets() -> Array:
	var out := []
	for c in cases:
		if not c.done: out.append(c.pos)
	return out
