extends Node3D
## Rozhlas lázní: plechové reproduktory pod stropy a občasná hlášení.
## Hlášky se berou ze složky audio/pa podle názvu:
##   pa_*.wav          – běžná úřední hlášení (fáze 1)
##   pa_f2_*.wav       – „něco je špatně“ (fáze 2, od 4. kola nebo po přečtení 3 vzkazů)
##   pa_rozpad_*.wav   – rozpadlý rozhlas (fáze 3, od 8. kola nebo po přečtení 6 vzkazů)
## Hlášení hraje ze všech blízkých reproduktorů naráz se zpožděním podle vzdálenosti (ozvěna budovy).

const DIR := "res://audio/pa/"
const SOUND_SPEED := 343.0

var main: Node
var speakers: Array[Vector3] = []
var _lines := {1: [], 2: [], 3: []}
var _players: Array[AudioStreamPlayer3D] = []
var _timer := 22.0           # první hlášení krátce po začátku
var _last: AudioStream
var playing_until := 0.0

func setup(main_node: Node) -> void:
	main = main_node
	_load_lines()
	for i in 6:
		var p := AudioStreamPlayer3D.new()
		p.bus = "World"
		p.unit_size = 7.0
		p.max_distance = 45.0
		p.attenuation_filter_cutoff_hz = 9000.0
		add_child(p)
		_players.append(p)
	_place_speakers.call_deferred()

func _load_lines() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null: return
	var seen := {}
	for f in dir.get_files():
		var name := f.trim_suffix(".import")
		if not name.ends_with(".wav") or seen.has(name): continue
		seen[name] = true
		var phase := 3 if name.begins_with("pa_rozpad") else (2 if name.begins_with("pa_f2") else 1)
		var stream: AudioStream = load(DIR + name)
		if stream: _lines[phase].append(stream)

func _place_speakers() -> void:
	await get_tree().physics_frame
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.55, 0.57, 0.55)
	metal.metallic = 0.6
	metal.roughness = 0.5
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.05, 0.05)
	for rect in main.MAP_RECTS:
		var r: Rect2 = rect
		var c := r.get_center()
		var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(c.x, 2.5, c.y), Vector3(c.x, -5.0, c.y), 1))
		if floor_hit.is_empty(): continue
		var fy: float = maxf(floor_hit.position.y, main.WATER_Y)
		var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(c.x, fy + 1.5, c.y), Vector3(c.x, fy + 12.0, c.y), 1))
		if up.is_empty(): continue
		# Reproduktor na zdi pod stropem je věrohodnější než uprostřed stropu: najít nejbližší zeď.
		var at: Vector3 = up.position + Vector3.DOWN * 0.35
		var facing := Vector3.DOWN
		for k in 8:
			var d := Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 8.0)
			var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(at, at + d * 9.0, 1))
			if not wall.is_empty() and absf((wall.normal as Vector3).y) < 0.2:
				at = wall.position + (wall.normal as Vector3) * 0.18
				facing = (wall.normal as Vector3)
				break
		speakers.append(at)
		_build_speaker(at, facing, metal, dark)

func _build_speaker(at: Vector3, facing: Vector3, metal: Material, dark: Material) -> void:
	# Plechový tlakový reproduktor (trychtýř) na držáku, mírně skloněný dolů.
	var root := Node3D.new()
	add_child(root)
	var dir := (facing * 0.8 + Vector3.DOWN * 0.45).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	if side.length() < 0.1: side = Vector3.RIGHT
	var up := side.cross(dir).normalized()
	root.global_transform = Transform3D(Basis(side, up, -dir), at)
	var horn := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.035
	cone.bottom_radius = 0.15
	cone.height = 0.28
	cone.radial_segments = 14
	horn.mesh = cone
	horn.material_override = metal
	horn.rotation.x = PI / 2          # osa trychtýře míří ven (-Z kořene)
	horn.position = Vector3(0, 0, -0.1)
	root.add_child(horn)
	var mouth := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.14
	disc.bottom_radius = 0.14
	disc.height = 0.005
	mouth.mesh = disc
	mouth.material_override = dark
	mouth.rotation.x = PI / 2
	mouth.position = Vector3(0, 0, -0.24)
	root.add_child(mouth)
	var body := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.1, 0.1, 0.12)
	body.mesh = b
	body.material_override = metal
	body.position = Vector3(0, 0, 0.08)
	root.add_child(body)

func _unhandled_input(event: InputEvent) -> void:
	# F7: hlášení hned (na zkoušku).
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_F7:
		_timer = 0.0

func _phase() -> int:
	var reads: int = main.notes._read.size() if main.get("notes") else 0
	var r: int = main.mode.round_now if main.mode and main.mode.active else 0
	if (r >= 8 or reads >= 6) and not _lines[3].is_empty(): return 3
	if (r >= 4 or reads >= 3) and not _lines[2].is_empty(): return 2
	return 1

func _process(dt: float) -> void:
	if main == null or main.player == null or speakers.is_empty(): return
	if main.menu and main.menu.is_open: return
	if not main.player.control_enabled: return
	_timer -= dt
	if _timer > 0.0: return
	# V největší vřavě nehlásit – rozhlas má zaznít, když je chvíli klid.
	if main.sfx and main.sfx.tension > 0.6:
		_timer = 8.0
		return
	_timer = randf_range(75.0, 160.0)
	var phase := _phase()
	var pool: Array = _lines[phase]
	if phase == 3 and randf() < 0.35 and not _lines[1].is_empty(): pool = _lines[1]      # občas ještě „normální“ hlášení – o to divnější
	if pool.is_empty(): pool = _lines[1]
	if pool.is_empty(): return
	var stream: AudioStream = pool.pick_random()
	if pool.size() > 1:
		while stream == _last: stream = pool.pick_random()
	_last = stream
	announce(stream)

func announce(stream: AudioStream) -> void:
	# Nejbližší reproduktory zahrají naráz; zvuk dorazí s fyzikálním zpožděním → ozvěna budovy.
	var p: Vector3 = main.player.global_position
	var near := speakers.duplicate()
	near.sort_custom(func(a, b): return a.distance_to(p) < b.distance_to(p))
	near = near.slice(0, mini(_players.size(), near.size()))
	for i in near.size():
		var player := _players[i]
		var at: Vector3 = near[i]
		var d: float = at.distance_to(p)
		if d > 45.0: continue
		player.stream = stream
		player.global_position = at
		player.volume_db = -2.0 - i * 1.5
		var delay := d / SOUND_SPEED
		if delay < 0.005: player.play()
		else: get_tree().create_timer(delay).timeout.connect(player.play)
	playing_until = Time.get_ticks_msec() / 1000.0 + stream.get_length()
