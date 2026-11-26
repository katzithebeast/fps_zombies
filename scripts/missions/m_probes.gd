extends "res://scripts/missions/mission.gd"
## Měřicí sondy: na 3 místech označených kolíkem s blikajícím světlem postav sondu.
## Sonda měří 40 s, jen když je hráč do 14 m (jinak měření stojí). Každá sonda přiláká zombie.

const COUNT := 3
const MEASURE := 40.0
const NEAR := 14.0

var probes: Array = []
var _t := 0.0

func _init() -> void:
	title = "Měřicí sondy"
	brief = "Potřebujeme data z bažiny. Na třech místech jsou kolíky s majáčkem, postavte u každého sondu a hlídejte ji, dokud neodměří. Měření je přiláká."
	ambient_cap = 5

func place() -> void:
	var pts: Array = main.mission_points(COUNT, {"where": "any", "min_spawn": 26.0, "sep": 30.0, "clear": 2.0})
	for i in pts.size():
		var p: Vector3 = pts[i]
		var root := Node3D.new()
		main.add_child(root)
		root.global_position = Vector3(p.x, maxf(p.y, main.WATER_Y - 0.6), p.z)
		# kolík s červenobílými pruhy a žlutý majáček
		for s in 6:
			director.box(root, Vector3(0.06, 0.28, 0.06), Vector3(0, 0.14 + s * 0.28, 0), Color(0.75, 0.08, 0.05) if s % 2 == 0 else Color(0.85, 0.85, 0.8))
		director.box(root, Vector3(0.1, 0.08, 0.1), Vector3(0, 1.74, 0), Color(1.0, 0.7, 0.1), 3.0)
		var bl := OmniLight3D.new()
		bl.light_color = Color(1.0, 0.65, 0.15)
		bl.omni_range = 7.0
		bl.light_volumetric_fog_energy = 1.5
		bl.position = Vector3(0, 1.85, 0)
		root.add_child(bl)
		var pr := {"pos": Vector3(p.x, root.global_position.y, p.z), "root": root, "blink": bl, "state": "wait", "k": 0.0, "led": null, "tick": 0.0, "n": i + 1}
		pr.act = director.add_action(pr.pos, "Postavit sondu", 3.0, _deploy.bind(pr))
		probes.append(pr)

func _deploy(pr: Dictionary) -> void:
	var root: Node3D = pr.root
	var dark := Color(0.12, 0.14, 0.1)
	# trojnožka, skříňka, anténa
	for i in 3:
		var a := TAU * i / 3.0
		var leg: MeshInstance3D = director.box(root, Vector3(0.03, 1.0, 0.03), Vector3(0.55 + cos(a) * 0.22, 0.48, sin(a) * 0.22), Color(0.3, 0.3, 0.28))
		leg.rotation = Vector3(sin(a) * 0.35, 0, -cos(a) * 0.35)
	director.box(root, Vector3(0.36, 0.26, 0.28), Vector3(0.55, 1.02, 0), dark)
	director.box(root, Vector3(0.015, 0.7, 0.015), Vector3(0.68, 1.5, 0.08), Color(0.08, 0.08, 0.08))
	pr.led = director.box(root, Vector3(0.05, 0.05, 0.02), Vector3(0.55, 1.08, 0.15), Color(1.0, 0.1, 0.05), 5.0)
	pr.state = "measure"
	director.snd("res://audio/gun_handle_2.wav", -4.0, 0.8)
	director.waves.surge(4)
	director.radio("Centrála: Sonda %d měří. Zůstaňte u ní, signál přiláká, co je okolo." % pr.n, 5.0)

func tick(dt: float) -> void:
	_t += dt
	var pp: Vector3 = director.player.global_position
	for pr in probes:
		match pr.state:
			"wait":
				(pr.blink as OmniLight3D).light_energy = 2.2 if fmod(_t + pr.n * 0.4, 1.4) < 0.2 else 0.0
			"measure":
				(pr.blink as OmniLight3D).light_energy = 0.0
				var near := Vector2(pp.x - pr.pos.x, pp.z - pr.pos.z).length() < NEAR
				if near: pr.k = minf(1.0, pr.k + dt / MEASURE)
				pr.tick -= dt
				if pr.tick <= 0.0 and near:
					pr.tick = 1.0
					var a := AudioStreamPlayer3D.new()
					a.stream = load("res://audio/tick.wav")
					a.unit_size = 3.0
					a.volume_db = -4.0
					main.add_child(a)
					a.global_position = pr.pos + Vector3(0, 1.0, 0)
					a.play()
					a.finished.connect(a.queue_free)
				var led: MeshInstance3D = pr.led
				led.visible = fmod(_t, 0.8) < 0.4 if near else fmod(_t, 2.0) < 0.1
				if pr.k >= 1.0:
					pr.state = "done"
					var m := StandardMaterial3D.new()
					m.albedo_color = Color(0.2, 1.0, 0.25)
					m.emission_enabled = true
					m.emission = Color(0.2, 1.0, 0.25)
					m.emission_energy_multiplier = 5.0
					led.material_override = m
					led.visible = true
					director.snd("res://audio/powerup.wav", -8.0, 1.3)
					var done := 0
					for q in probes: done += 1 if q.state == "done" else 0
					if done == probes.size(): complete()
					else: director.radio("Centrála: Data ze sondy %d máme. Zbývá %d." % [pr.n, probes.size() - done], 4.0)

func lines() -> Array:
	var out := []
	for pr in probes:
		var s := "čeká na postavení"
		if pr.state == "measure":
			var far := Vector2(director.player.global_position.x - pr.pos.x, director.player.global_position.z - pr.pos.z).length() >= NEAR
			s = "měří %d %%%s" % [int(pr.k * 100.0), " – jsi moc daleko!" if far else ""]
		elif pr.state == "done": s = "hotovo"
		out.append("Sonda %d: %s" % [pr.n, s])
	return out

func targets() -> Array:
	var out := []
	for pr in probes:
		if pr.state != "done": out.append(pr.pos)
	return out
