class_name Sfx
extends Node
## Zvuk: ambientní smyčky, prostorové jednorázové zvuky a dozvuk, který se mění podle místnosti.
## Všechny soubory jsou ve složce res://audio a dají se nahradit vlastními nahrávkami se stejným názvem.

const GROUPS := {
	"step_tile": 6, "step_water": 6, "swim": 4, "splash_big": 2,
	"zombie_groan": 10, "zombie_attack": 8, "zombie_death": 7, "gib": 2,
	"hit_flesh": 4, "zombie_bang": 4, "wall_scratch": 3, "zombie_gurgle": 2,
	"thunder": 3, "creak": 6, "music_box": 3, "ghost_crowd": 3, "cry": 1, "laugh": 1,
	"chain": 5, "water_plop": 3, "breather": 3, "scare": 4, "drip": 6,
	"body_fall": 4, "stinger": 4, "lamp_spark": 2,
}
const ZONES := {
	# room_size, wet, damping, lowpass Hz, [room, water, vent, tunnel, déšť na střeše, šplouchání u okraje, temná plocha] dB
	"start":    [0.75, 0.38, 0.35, 20000.0, [-13.0, -30.0, -16.0, -60.0, -27.0, -38.0, -30.0]],
	"hall":     [0.99, 0.72, 0.15, 20000.0, [-15.0, -11.0, -24.0, -60.0, -21.0, -15.0, -27.0]],
	"corridor": [0.82, 0.5, 0.3, 20000.0, [-13.0, -19.0, -20.0, -30.0, -26.0, -30.0, -26.0]],
	"tunnel":   [0.45, 0.28, 0.6, 1500.0,  [-18.0, -30.0, -40.0, -9.0, -46.0, -50.0, -24.0]],
}

var _streams := {}
var _last_pick := {}
var _occlusion_clock := 0.0
var _occlusion_index := 0
var _atmosphere_clock := 0.0
var _amb := {}
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _i3 := 0
var _i2 := 0
var _reverb: AudioEffectReverb
var _lowpass: AudioEffectLowPassFilter
var _zone := "start"
var _bus := 0
var muted := false
var fade := 1.0            # celková hlasitost (fade na konci úrovně)
var music: AudioStreamPlayer
var music_volume := 0.35   # nastavení „Hudba“
var music_duck := 0.0      # 0..1 ztišení hudby (boj, konec hry)
var _music_db := -80.0
var tension := 0.0         # 0..1 nastavuje zombie režim (blízkost a počet zombie)
var _tension_s := 0.0
var _shot_duck := 0.0
var _amb_base := {}

const GUN_KEYS := ["ak", "mp40", "izh54", "deagle"]

func apply_gun_settings(s: Dictionary) -> void:
	for g in GUN_KEYS:
		var b := AudioServer.get_bus_index("Gun_" + g)
		if b < 0:
			continue
		AudioServer.set_bus_volume_db(b, float(s.get("gun_master", 0.0)) + float(s.get("gun_%s_vol" % g, 0.0)))
		var shelf := AudioServer.get_bus_effect(b, 0) as AudioEffectLowShelfFilter
		var bass_db := float(s.get("gun_bass", 0.0)) + float(s.get("gun_%s_bass" % g, 0.0))
		shelf.gain = db_to_linear(bass_db)
		var echo := AudioServer.get_bus_effect(b, 1) as AudioEffectDelay
		var amount := clampf(float(s.get("gun_%s_echo" % g, 0.35)) * float(s.get("gun_echo", 1.0)), 0.0, 2.0)
		AudioServer.set_bus_effect_enabled(b, 1, amount > 0.01)
		var lvl := linear_to_db(maxf(amount, 0.001))
		echo.tap1_level_db = -8.0 + lvl
		echo.tap2_level_db = -12.0 + lvl
		echo.feedback_level_db = -16.0 + lvl

func duck() -> void:
	_shot_duck = 1.0

func _ready() -> void:
	AudioServer.add_bus()
	_bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(_bus, "World")
	AudioServer.set_bus_send(_bus, "Master")
	_reverb = AudioEffectReverb.new()
	_reverb.predelay_msec = 60.0
	_reverb.predelay_feedback = 0.35
	_reverb.spread = 1.0
	_reverb.hipass = 0.12
	_reverb.dry = 0.9
	AudioServer.add_bus_effect(_bus, _reverb)
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(_bus, _lowpass)
	# Každá zbraň má vlastní sběrnici: basy (low shelf), ozvěna od obkladů (delay) a hlasitost z nastavení.
	for g in GUN_KEYS:
		AudioServer.add_bus()
		var b := AudioServer.bus_count - 1
		AudioServer.set_bus_name(b, "Gun_" + g)
		AudioServer.set_bus_send(b, "World")
		var shelf := AudioEffectLowShelfFilter.new()
		shelf.cutoff_hz = 140.0
		shelf.gain = 1.0
		AudioServer.add_bus_effect(b, shelf)
		var echo := AudioEffectDelay.new()
		echo.dry = 1.0
		echo.tap1_active = true
		echo.tap1_delay_ms = 70.0
		echo.tap1_level_db = -14.0
		echo.tap1_pan = -0.35
		echo.tap2_active = true
		echo.tap2_delay_ms = 135.0
		echo.tap2_level_db = -18.0
		echo.tap2_pan = 0.35
		echo.feedback_active = true
		echo.feedback_delay_ms = 210.0
		echo.feedback_level_db = -22.0
		echo.feedback_lowpass = 2500.0
		AudioServer.add_bus_effect(b, echo)
	# Limiter na výstupu: hlasité výstřely se nepřebudí do praskání, jen zhutní.
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	lim.pre_gain_db = 0.0
	lim.release = 0.12
	AudioServer.add_bus_effect(0, lim)

	for g in GROUPS:
		var arr: Array[AudioStream] = []
		for i in GROUPS[g]:
			var s := _load("%s_%d" % [g, i + 1], false)
			if s:
				arr.append(s)
		_streams[g] = arr
	for n in ["tick", "whoomp", "ak_shot", "ak_fire", "round_start", "round_end", "game_over", "player_hurt", "powerup", "powerup_spawn", "melee", "float_pop", "ball_hit",
			"locker_open", "crate_open", "crate_close", "gate_open", "item_pickup", "sleeper_wake", "music_box_wind", "gore_smash", "lamp_click"]:
		var arr2: Array[AudioStream] = []
		var s2 := _load(n, false)
		if s2:
			arr2.append(s2)
		# Varianty name_1, name_2... se střídají, ať stejný zvuk nezní pořád stejně.
		var variants: Array[AudioStream] = []
		for i in range(1, 9):
			if ResourceLoader.exists("res://audio/%s_%d.wav" % [n, i]):
				variants.append(load("res://audio/%s_%d.wav" % [n, i]))
		# Výstřely: jsou-li nahrané varianty, starý jednotlivý soubor se už nepoužije.
		if n == "ak_fire" and not variants.is_empty():
			arr2.clear()
		arr2.append_array(variants)
		_streams[n] = arr2
	_streams["ak"]=_streams["ak_fire"] if not _streams["ak_fire"].is_empty() else _streams["ak_shot"]

	for n in ["room", "water", "vent", "tunnel", "rain", "lap", "drone"]:
		var p := AudioStreamPlayer.new()
		p.stream = _load("amb_" + n, true)
		p.bus = "World"
		p.volume_db = -60.0
		add_child(p)
		p.play()
		_amb[n] = p
	# Temná hudba na pozadí: 30min smyčka, plynule najede a hraje i v menu.
	if ResourceLoader.exists("res://audio/music/dark_ambience.ogg"):
		var ms: AudioStream = load("res://audio/music/dark_ambience.ogg")
		if ms is AudioStreamOggVorbis: ms.loop = true
		music = AudioStreamPlayer.new()
		music.stream = ms
		music.volume_db = -80.0
		add_child(music)
		music.play(randf() * 1500.0)     # pokaždé jinde, ať se začátek neohraje
	for i in 26:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "World"
		p3.unit_size = 5.0
		p3.max_distance = 45.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.attenuation_filter_cutoff_hz = 9000.0
		p3.attenuation_filter_db = -18.0
		add_child(p3)
		_pool3d.append(p3)
	for i in 8:
		var p2 := AudioStreamPlayer.new()
		p2.bus = "World"
		add_child(p2)
		_pool2d.append(p2)

func _load(name: String, looped: bool) -> AudioStream:
	var path := "res://audio/%s.wav" % name
	if not ResourceLoader.exists(path):
		push_warning("Chybí zvuk: " + path)
		return null
	var s: AudioStream = load(path)
	if looped and s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	return s

func make_loop_3d(name: String, pos: Vector3, vol_db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _load(name, true)
	p.bus = "World"
	p.unit_size = 2.5
	p.max_distance = 22.0
	p.volume_db = vol_db
	add_child(p)
	p.global_position = pos
	p.play()
	return p

func _pick(group: String) -> AudioStream:
	var arr: Array = _streams.get(group, [])
	if arr.is_empty(): return null
	var index := randi() % arr.size()
	if arr.size() > 1 and index == int(_last_pick.get(group, -1)):
		index = (index + 1 + randi() % (arr.size() - 1)) % arr.size()
	_last_pick[group] = index
	return arr[index]

func play_at(group: String, pos: Vector3, vol_db := 0.0, pitch := 1.0) -> void:
	var s := _pick(group)
	if s == null:
		return
	# Neusekávat rozehranou blízkou stopu, dokud je volný hlas.
	for offset in _pool3d.size():
		var candidate := (_i3 + offset) % _pool3d.size()
		if not _pool3d[candidate].playing:
			_i3 = candidate
			break
	var p := _pool3d[_i3]
	_i3 = (_i3 + 1) % _pool3d.size()
	p.set_meta("base_db", vol_db)
	p.set_meta("occluded", false)
	p.attenuation_filter_cutoff_hz = 9000.0
	p.stream = s
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()

func play(group: String, vol_db := 0.0, pitch := 1.0) -> void:
	var s := _pick(group)
	if s == null:
		return
	var p := _pool2d[_i2]
	_i2 = (_i2 + 1) % _pool2d.size()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch * randf_range(0.93, 1.07)
	p.play()

func set_zone(z: String) -> void:
	if ZONES.has(z):
		_zone = z

func _process(dt: float) -> void:
	var _perf_t0:=Time.get_ticks_usec()
	_process_timed(dt)
	PerfMon.add("Zvuky",Time.get_ticks_usec()-_perf_t0)

func _process_timed(dt: float) -> void:
	_atmosphere_clock += dt
	var z: Array = ZONES[_zone]
	var a := 1.0 - exp(-1.6 * dt)
	_reverb.room_size = lerpf(_reverb.room_size, z[0], a)
	_reverb.wet = lerpf(_reverb.wet, z[1], a)
	_reverb.damping = lerpf(_reverb.damping, z[2], a)
	var cut: float = z[3] if fade > 0.99 else 350.0
	_lowpass.cutoff_hz = exp(lerpf(log(_lowpass.cutoff_hz), log(cut), 1.0 - exp(-3.0 * dt)))
	var vols: Array = z[4]
	var names := ["room", "water", "vent", "tunnel", "rain", "lap", "drone"]
	# Po výstřelu se okolí na zlomek vteřiny ztiší – rána tak vynikne a má sílu.
	_shot_duck = move_toward(_shot_duck, 0.0, dt * 2.2)
	_tension_s = lerpf(_tension_s, tension, 1.0 - exp(-0.5 * dt))
	for i in 7:
		var p: AudioStreamPlayer = _amb[names[i]]
		var target: float = vols[i]
		if names[i] == "drone":
			target = lerpf(target - 3.0 * (0.5 + 0.5 * sin(_atmosphere_clock * 0.095)), -15.0, _tension_s)       # napětí: plocha sílí, když jsou zombie blízko
		_amb_base[i] = lerpf(float(_amb_base.get(i, -60.0)), target, a)
		p.volume_db = _amb_base[i] - 9.0 * _shot_duck
	if music:
		var lin := minf(music_volume * 1.6, 1.4) * fade * (1.0 - 0.45 * music_duck) * (1.0 - 0.6 * _shot_duck) * (0.0 if muted else 1.0)
		_music_db = lerpf(_music_db, linear_to_db(maxf(lin, 0.0001)), 1.0 - exp(-(0.6 if lin > db_to_linear(_music_db) else 3.0) * dt))
		music.volume_db = _music_db
	var target_db := -80.0 if muted else linear_to_db(maxf(fade, 0.0001))
	AudioServer.set_bus_volume_db(_bus, lerpf(AudioServer.get_bus_volume_db(_bus), target_db, 1.0 - exp(-6.0 * dt)))

# Rozložený rozpočet: nejvýš tři raycasty za 80 ms, i v plné hordě.
func _physics_process(dt: float) -> void:
	var _perf_t0 := Time.get_ticks_usec()
	_occlusion(dt)
	PerfMon.add("Zvuky zakrytí", Time.get_ticks_usec() - _perf_t0)

func _occlusion(dt: float) -> void:
	_occlusion_clock -= dt
	if _occlusion_clock > 0.0: return
	_occlusion_clock = 0.08
	var camera := get_viewport().get_camera_3d()
	if camera == null or _pool3d.is_empty(): return
	var space := camera.get_world_3d().direct_space_state
	for i in 3:
		var voice := _pool3d[_occlusion_index % _pool3d.size()]
		_occlusion_index += 1
		if not voice.playing: continue
		var q := PhysicsRayQueryParameters3D.create(camera.global_position, voice.global_position, 1)
		var blocked := not space.intersect_ray(q).is_empty()
		voice.set_meta("occluded", blocked)
	for voice in _pool3d:
		if not voice.playing: continue
		var blocked: bool = voice.get_meta("occluded", false)
		voice.volume_db = lerpf(voice.volume_db, float(voice.get_meta("base_db", 0.0)) - (7.0 if blocked else 0.0), 0.4)
		voice.attenuation_filter_cutoff_hz = lerpf(voice.attenuation_filter_cutoff_hz, 1500.0 if blocked else 9000.0, 0.4)
