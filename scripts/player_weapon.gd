extends Node
## Zbraň hráče: střelba s rozptylem, zpětný ráz pohledu, přebíjení ze zásoby, sprint se sklopenou zbraní, úder pažbou.
signal fired(origin: Vector3, hit: Vector3)
signal melee_hit(origin: Vector3, direction: Vector3)
# Zbraně: zásobník, zásoba, kadence (s), automat, poškození, broky, rozptyl, ráz pohledu, zvuk (výška, hlasitost).
const STATS:={
	"ak":    {"name":"AK-47","mag":30,"reserve":210,"rate":0.1,"auto":true,"damage":50.0,"pellets":1,"spread":0.011,"pellet_spread":0.0,"kick":Vector2(0.009,0.022),"sound":"ak_fire.wav","pitch":1.0,"volume":6.0},
	"mp40":  {"name":"MP 40","mag":32,"reserve":224,"rate":0.11,"auto":true,"damage":38.0,"pellets":1,"spread":0.013,"pellet_spread":0.0,"kick":Vector2(0.007,0.016),"sound":"mp40_fire.wav","pitch":1.0,"volume":7.0},
	"izh54": {"name":"IŽ-54","mag":2,"reserve":36,"rate":0.28,"auto":false,"damage":32.0,"pellets":9,"spread":0.01,"pellet_spread":0.07,"kick":Vector2(0.02,0.085),"sound":"izh_fire.wav","pitch":1.0,"volume":2.0},
	"deagle":{"name":"Desert Eagle","mag":7,"reserve":70,"rate":0.24,"auto":false,"damage":130.0,"pellets":1,"spread":0.009,"pellet_spread":0.0,"kick":Vector2(0.016,0.07),"sound":"deagle_fire.wav","pitch":1.0,"volume":4.0},
}
const ORDER:=["ak","mp40","izh54","deagle"]
const MAG:=30            # AK; zachováno kvůli starším voláním
const RESERVE:=210
const MELEE:=0.55
var player: Player
var equipped:=false        # drží hráč nějakou zbraň
var current:="ak"
var owned:={}
var clips:={}              # zbraň -> [v zásobníku, v zásobě]
var damage:=50.0
var _switch_left:=0.0
const SWITCH_TIME:=0.68
var _switch_target:=""
var _switch_committed:=false
var _next_gun:=""
var _trigger_was:=false
var aiming:=false
var test_aim:=false        # jen pro testy
var aim_amount:=0.0
var ammo:=MAG
var reserve:=RESERVE
var infinite_reserve:=true      # mimo režim přežití se zásoba nepočítá
var reload_left:=0.0
var inspect:=0.0           # 0..1 kontrola zásobníku (držené R)
var examining:=false       # držené N: prohlídka zbraně
var test_examine:=false    # testy: prohlídka bez klávesy
var _steady:=0.0
var _was_floor:=true
var _fall_vel:=0.0
var _r_held:=0.0
var _tag: Control
var _tag_font: Font
var spread:=0.012               # poloviční úhel rozptylu (rad); čte ho zaměřovač
var sprint_amount:=0.0
var melee_left:=0.0
var _heat:=0.0
var _cooldown:=0.0
var _trigger_pending:=false
var _melee_pending:=false
var _shot_sound: AudioStreamPlayer
var _tail_sound: AudioStreamPlayer
var _ui_sound: AudioStreamPlayer
var _zap_sound: AudioStreamPlayer      # sci-fi vrstva výstřelu vylepšených zbraní
var _shimmer_sound: AudioStreamPlayer  # třpyt pokřtěné zbraně
var _zap_streams: Array=[]
var _shimmer_cd:=0.0
var _punch:=Vector2.ZERO
var _punch_target:=Vector2.ZERO

func _player(file: String, volume: float, voices: int) -> AudioStreamPlayer:
	var sound:=AudioStreamPlayer.new()
	if ResourceLoader.exists("res://audio/"+file): sound.stream=load("res://audio/"+file)
	sound.volume_db=volume
	sound.max_polyphony=voices
	sound.bus="World" if AudioServer.get_bus_index("World")>=0 else "Master"   # dozvuk podle místnosti
	add_child(sound)
	return sound

func _ready() -> void:
	_shot_sound=_player("ak_fire.wav",-1.0,5)
	if _shot_sound.stream==null:
		_shot_sound.stream=load("res://audio/ak_shot.wav")
		_shot_sound.volume_db=-9.0
	_tail_sound=_player("ak_tail.wav",-30.0,3)      # nahraný výstřel má vlastní dozvuk; tady jen jemně dokreslí halu
	_ui_sound=_player("dry_fire.wav",-8.0,2)
	_zap_sound=_player("pap_zap_1.wav",-12.0,6)
	_shimmer_sound=_player("pap_shimmer.wav",-14.0,2)
	for i in 3:
		if ResourceLoader.exists("res://audio/pap_zap_%d.wav" % (i+1)): _zap_streams.append(load("res://audio/pap_zap_%d.wav" % (i+1)))
	_make_tag()
	for key in STATS: clips[key]=[STATS[key].mag,STATS[key].reserve]

var upgraded:={}          # vylepšené zbraně z pracovního stolu
var wall_react:=true      # zbraň reaguje na zeď před sebou (vypíná jen test)
var debug_ammo:=false     # testování: zásobník se neprázdní
var baptizing:=""         # zbraň právě leží v andělově vodě (nedá se vytáhnout)
var item_held:=""         # předmět v ruce místo zbraně (injekce)
var _inject_t:=-1.0
var _inject_done:=false
var _item_lmb_was:=true
const INJECT_TIME:=1.75
const ITEM_TIME:={"syringe":1.75,"pumpkin":0.85}   # injekce / hod dýňovou bombou
const INJECT_HEAL:=60.0
const PAP_NAMES:={"ak":"Křtitel","mp40":"Vodník","izh54":"Dvě slzy","deagle":"Andělské oko"}

var reserve_scale:=1.0     # hororový režim: méně munice v záloze

func stats_of(gun: String) -> Dictionary:
	if not upgraded.has(gun) and reserve_scale==1.0: return STATS[gun]
	var s: Dictionary=STATS[gun].duplicate()
	s.reserve=maxi(int(s.mag),int(int(s.reserve)*reserve_scale))
	if not upgraded.has(gun): return s
	# Stupně z pracovního stolu (I–III) a křest v andělově vodě (IV).
	var t: int=tier(gun)
	var dmg: float=[1.0,1.25,1.6,2.1,3.2][t]
	s.damage=float(s.damage)*dmg
	s.mag=int(ceil(int(s.mag)*(2.0 if t>=4 else 1.5)))
	s.reserve=int(int(s.reserve)*[1.0,1.5,1.75,2.0,2.5][t])
	if t>=2: s.rate=float(s.rate)*(0.82 if t>=4 else 0.92)
	if t>=2: s.spread=float(s.spread)*(0.6 if t>=4 else 0.75)
	s.name=String(s.name)+["",""," I"," II"," III"," (pokřtěná)"][t+1]
	if t>=4: s.name=String(PAP_NAMES.get(gun,s.name))
	s.reload=[1.0,1.0,0.92,0.85,0.62][t]       # křest: o třetinu rychlejší přebíjení
	return s

const ZAP_PITCH:={"ak":1.0,"mp40":1.12,"izh54":0.72,"deagle":0.86}

func _play_zap() -> void:
	# Vylepšené zbraně: pod výstřelem laserový „zap“, s vyšším stupněm hlasitější a hlubší; po křtu i třpyt.
	var t:=tier(current) if upgraded.has(current) else 0
	if t<=0 or _zap_streams.is_empty() or _zap_sound==null: return
	_zap_sound.stream=_zap_streams[randi()%_zap_streams.size()]
	_zap_sound.pitch_scale=float(ZAP_PITCH.get(current,1.0))*[1.0,1.08,1.0,0.92,0.84][t]*randf_range(0.97,1.03)
	_zap_sound.volume_db=[-80.0,-17.0,-13.0,-9.5,-6.0][t]
	_zap_sound.play()
	if t>=4 and _shimmer_sound and _shimmer_cd<=0.0:
		_shimmer_cd=0.4
		_shimmer_sound.pitch_scale=randf_range(0.95,1.08)
		_shimmer_sound.play()

func _wall_ahead(rig: Node) -> float:
	# Jak blízko před zbraní je zeď: 0 = volno, 1 = hlaveň by byla celá ve zdi.
	var cam: Camera3D=player.camera
	if cam==null or not cam.is_inside_tree(): return 0.0
	var reach: float=absf(float(rig._gi().muzzle.z))+0.32      # od oka k ústí hlavně
	var fwd: Vector3=-cam.global_basis.z
	var right: Vector3=cam.global_basis.x
	var up: Vector3=cam.global_basis.y
	var space:=player.get_world_3d().direct_space_state
	var nearest:=reach
	# Střed pohledu + místo, kde zbraň skutečně je (vpravo dole), + mezi nimi.
	for o in [Vector3.ZERO, right*0.14-up*0.2, right*0.07-up*0.1]:
		var from: Vector3=cam.global_position+o*(1.0-aim_amount*0.8)
		var q:=PhysicsRayQueryParameters3D.create(from,from+fwd*reach,1)
		var hit:=space.intersect_ray(q)
		if not hit.is_empty(): nearest=minf(nearest,from.distance_to(hit.position))
	# Delší zbraň musí reagovat dřív; úplně u zdi (přes 1) se ještě víc stáhne.
	return clampf((reach-nearest)/(reach*0.42),0.0,2.0)

func _apply_look() -> void:
	# Pokřtěné zbraně: kamufláž a záře v rukou, rychlejší přebíjení.
	var rig: Node=player.body.weapon if player and player.body else null
	if rig==null or not rig.has_method("set_look"): return
	for key in STATS: rig.set_look(key,tier(key) if upgraded.has(key) else 0)
	rig.reload_mul=float(stats().get("reload",1.0))

func tier(gun: String) -> int:
	if not upgraded.has(gun): return 0
	var v=upgraded[gun]
	return clampi(int(v) if typeof(v)==TYPE_INT else 1,0,4)

func stats() -> Dictionary:
	return stats_of(current)

func display_name() -> String:
	return stats().name

func upgrade(gun: String) -> void:
	upgraded[gun]=mini(tier(gun)+1,4)
	if gun==current:
		_store()
		clips[gun]=[int(stats().mag),int(stats().reserve)]
		_load_current()
	else:
		clips[gun]=[int(stats_of(gun).mag),int(stats_of(gun).reserve)]
	_apply_look()

func _store() -> void:
	clips[current]=[ammo,reserve]

func _load_current() -> void:
	ammo=clips[current][0]
	reserve=clips[current][1]
	damage=stats().damage
	_apply_look()
	if _shot_sound:
		_shot_sound.stream=_gun_stream(String(STATS[current].sound))
		# Vlastní sběrnice zbraně (basy, ozvěna, hlasitost z nastavení „Zbraně“).
		if AudioServer.get_bus_index("Gun_"+current)>=0: _shot_sound.bus="Gun_"+current

var _gun_streams:={}

func _gun_stream(file: String) -> AudioStream:
	# Výstřely mají několik nahraných variant (ak_fire_1..4.wav); přehrávají se náhodně, nikdy dvakrát stejná po sobě.
	if _gun_streams.has(file): return _gun_streams[file]
	var base:=file.get_basename()
	var rnd:=AudioStreamRandomizer.new()
	rnd.playback_mode=AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	rnd.random_pitch=1.0
	rnd.random_volume_offset_db=0.0
	for i in range(1,9):
		var p:="res://audio/%s_%d.wav" % [base,i]
		if ResourceLoader.exists(p): rnd.add_stream(-1,load(p))
	var result: AudioStream=rnd
	if rnd.streams_count==0:
		result=load("res://audio/"+file) if ResourceLoader.exists("res://audio/"+file) else null
	_gun_streams[file]=result
	return result

func give(gun: String, select: bool=true) -> void:
	owned[gun]=true
	if select or not equipped: switch_to(gun,not equipped)

func refill() -> void:
	for key in STATS: clips[key]=[stats_of(key).mag,stats_of(key).reserve]
	_load_current()

func refill_reserve() -> void:
	_store()
	for key in STATS: clips[key][1]=stats_of(key).reserve
	_load_current()

func switch_to(gun: String, instant: bool=false) -> void:
	if not owned.has(gun) or gun==baptizing: return
	if item_held!="":
		if _inject_t>=0.0: return
		_drop_item_state()
		_commit_switch(gun,true)
		return
	if _switch_left>0.0 and not instant:
		# Kolečko může cíl měnit během schovávání; již vytaženou zbraň znovu neschovávat.
		if not _switch_committed: _switch_target=gun
		else: _next_gun=gun
		return
	if gun==current and equipped: return
	if equipped and not instant:
		_switch_target=gun
		_switch_committed=false
		_switch_left=SWITCH_TIME
		reload_left=0.0
		inspect=0.0
		_r_held=0.0
		_trigger_pending=false
		melee_left=0.0
		_melee_pending=false
		player.body.weapon.cancel_reload()
		return
	_switch_left=0.0
	_switch_target=""
	_next_gun=""
	_commit_switch(gun,true)
	player.body.weapon.holster=0.0

func _commit_switch(gun: String, draw: bool) -> void:
	if equipped: _store()
	reload_left=0.0
	current=gun
	equipped=true
	_load_current()
	player.body.weapon.set_gun(gun,draw)
	player.body.weapon.equipped=true

func _update_switch(dt: float) -> void:
	if _switch_left<=0.0: return
	_switch_left=maxf(0.0,_switch_left-dt)
	var phase:=1.0-_switch_left/SWITCH_TIME
	var rig: Node=player.body.weapon
	rig.holster=smoothstep(0.0,0.4,phase) if phase<0.46 else 1.0-smoothstep(0.52,1.0,phase)
	if phase>=0.46 and not _switch_committed:
		_switch_committed=true
		_commit_switch(_switch_target,false)
	if _switch_left<=0.0:
		rig.holster=0.0
		_switch_target=""
		var queued:=_next_gun
		_next_gun=""
		if queued!="" and queued!=current: switch_to(queued)

func cycle(step: int) -> void:
	var list:=ORDER.filter(func(key): return owned.has(key))
	if list.size()<2: return
	var from:=_next_gun if _next_gun!="" else (_switch_target if _switch_left>0.0 else current)
	switch_to(list[(list.find(from)+step+list.size())%list.size()])

func reset() -> void:
	equipped=false
	owned={}
	upgraded={}
	baptizing=""
	item_held=""
	_inject_t=-1.0
	player.body.weapon.inject=0.0
	current="ak"
	_apply_look()
	for key in STATS: clips[key]=[STATS[key].mag,STATS[key].reserve]
	_switch_left=0.0
	_switch_target=""
	_switch_committed=false
	_next_gun=""
	if player.body.weapon.has_method("set_gun"): player.body.weapon.set_gun("ak")
	aiming=false
	aim_amount=0
	ammo=MAG
	reserve=RESERVE
	reload_left=0
	melee_left=0
	sprint_amount=0
	_heat=0
	_trigger_pending=false
	_melee_pending=false
	_cooldown=0
	_punch=Vector2.ZERO
	_punch_target=Vector2.ZERO
	player.sprint_lock=false
	var rig: Node=player.body.weapon
	rig.equipped=false
	rig.weight=0
	rig.reload_left=0
	rig.recoil=0
	rig.aim=0
	rig.sprint=0
	rig.melee=0
	rig.holster=0.0
	rig.cancel_reload()

func hold_item(id: String) -> void:
	# Injekce do ruky: zbraň se schová, v ruce je injektor, levým tlačítkem si ji hráč vpíchne.
	if not ITEM_TIME.has(id) or _inject_t>=0.0: return
	if item_held==id:
		_finish_item()          # druhý stisk: injekci schovat, zpátky zbraň
		return
	if player.swimming: return
	if equipped:
		_store()
		equipped=false
	reload_left=0.0
	inspect=0.0
	aiming=false
	melee_left=0.0
	_switch_left=0.0
	_switch_target=""
	_next_gun=""
	item_held=id
	_item_lmb_was=true
	var rig: Node=player.body.weapon
	rig.cancel_reload()
	rig.holster=0.0
	rig.inject=0.0
	rig.set_gun(id,true)
	rig.equipped=true
	_click("item_pickup.wav",1.1)

func _drop_item_state() -> void:
	item_held=""
	_inject_t=-1.0
	_inject_done=false
	var rig: Node=player.body.weapon
	rig.inject=0.0
	rig.set_gun(current,false)
	rig.equipped=false

func put_away_item() -> void:
	if item_held=="" or _inject_t>=0.0: return
	_drop_item_state()

func _main() -> Node:
	return player.get_parent()

func _update_item(dt: float) -> void:
	var rig: Node=player.body.weapon
	var ok: bool=player.control_enabled and not player.input_suspended and not player.interaction_locked and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED
	var lmb: bool=ok and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var main_node: Node=_main()
	var inv: Node=main_node.get("inventory")
	if _inject_t<0.0:
		if player.swimming or (inv and not inv.has(item_held)):
			# Pod vodou nebo bez injekcí: injektor pryč, zpátky zbraň.
			_finish_item()
			return
		if lmb and not _item_lmb_was and rig._draw<=0.25:
			var mode: Node=main_node.get("mode")
			if item_held=="pumpkin":
				_inject_t=0.0
				_inject_done=false
				_click("item_pickup.wav",0.7)
			elif mode and mode.active and float(mode.health)>=99.0:
				mode._popup("Zdraví je plné",false)
			else:
				_inject_t=0.0
				_inject_done=false
				_click("syringe_inject.wav",1.0)
	else:
		_inject_t+=dt
		var p:=_inject_t/float(ITEM_TIME[item_held])
		if item_held=="pumpkin" and p>=0.47 and not _inject_done:
			_inject_done=true
			_throw_bomb()
			if inv: inv.remove(item_held,1)
		elif item_held=="syringe" and p>=0.6 and not _inject_done:
			_inject_done=true
			var mode: Node=main_node.get("mode")
			if mode:
				mode.health=minf(100.0,float(mode.health)+INJECT_HEAL)
				mode._regen_wait=0.0
				mode._popup("+%d zdraví" % int(INJECT_HEAL),true)
			if inv: inv.remove(item_held,1)
		if p>=1.0:
			_finish_item()
			return
	_item_lmb_was=lmb
	if item_held!="": rig.inject=clampf(_inject_t/float(ITEM_TIME[item_held]),0.0,1.0) if _inject_t>=0.0 else 0.0

func _throw_bomb() -> void:
	# Dýně letí z ruky po směru pohledu, s mírným obloukem a rychlostí hráče.
	var cam: Camera3D=player.camera
	var fwd: Vector3=-cam.global_basis.z
	var right: Vector3=cam.global_basis.x
	var from: Vector3=cam.global_position+fwd*0.45+right*0.18-cam.global_basis.y*0.08
	var space:=player.get_world_3d().direct_space_state
	var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(cam.global_position,from,1))
	if not hit.is_empty(): from=hit.position-fwd*0.12    # těsně u zdi nehodit skrz
	var vel: Vector3=fwd*11.0+Vector3.UP*2.6+player.velocity*0.6
	preload("res://scripts/pumpkin_bomb.gd").throw_from(_main(),from,vel)
	_click("melee.wav",1.25)

func _finish_item() -> void:
	# Po vpichu (nebo bez injekcí) se vrátí poslední zbraň s vytažením.
	_drop_item_state()
	if owned.has(current): _commit_switch(current,true)

func holster() -> void:
	# Zbraň do pouzdra / na záda (z inventáře: přetažením z rukou).
	if item_held!="":
		put_away_item()
		return
	if not equipped or _switch_left>0.0: return
	_store()
	equipped=false
	reload_left=0.0
	inspect=0.0
	aiming=false
	player.body.weapon.cancel_reload()
	player.body.weapon.equipped=false

func equip() -> void:
	# Sebrání AK-47.
	give("ak",true)

func can_reload() -> bool:
	return equipped and reload_left<=0 and _switch_left<=0 and ammo<int(stats().mag) and (infinite_reserve or reserve>0)

func reload() -> void:
	if not can_reload() or player.swimming or melee_left>0 or float(player.body.weapon.wipe)>0.0: return      # VISOR: ne při otírání
	inspect=0.0
	_r_held=0.0
	player.body.weapon.begin_reload(ammo==0)
	reload_left=player.body.weapon.reload_time
	player.body.action_started.emit("reload",[])

func melee() -> void:
	if not equipped or melee_left>0 or reload_left>0 or _switch_left>0.0 or player.swimming or not player.control_enabled or player.interaction_locked: return
	if float(player.body.weapon.wipe)>0.0: return      # VISOR (experiment): ruka je u hledí
	melee_left=MELEE
	_melee_pending=true
	if ResourceLoader.exists("res://audio/melee.wav"):
		_ui_sound.stream=load("res://audio/melee.wav")
		_ui_sound.pitch_scale=randf_range(0.92,1.08)
		_ui_sound.play()

func _unhandled_input(event: InputEvent) -> void:
	if player==null or player.input_suspended or Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED: return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_Q: if not player.third_person: melee()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_MIDDLE: melee()
			MOUSE_BUTTON_WHEEL_UP: cycle(-1)
			MOUSE_BUTTON_WHEEL_DOWN: cycle(1)

func update(dt: float) -> void:
	_update_switch(dt)
	var enabled:=equipped and _switch_left<=0.0 and player.control_enabled and not player.input_suspended and not player.swimming and not player.interaction_locked and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED
	# R: krátký stisk přebije, držení vytáhne zásobník a ukáže, kolik v něm zbývá.
	var r_down:=enabled and not player.third_person and Input.is_physical_key_pressed(KEY_R)
	var inspecting:=false
	if r_down:
		_r_held+=dt
		inspecting=_r_held>0.28 and reload_left<=0 and melee_left<=0 and _switch_left<=0
		if inspecting and inspect<=0.0: _click("ak_mag_out.wav",1.15)
	else:
		if _r_held>0.0 and _r_held<=0.28 and can_reload(): reload()
		elif _r_held>0.28 and inspect>0.5: _click("ak_mag_in.wav",1.15)
		_r_held=0.0
	inspect=move_toward(inspect,1.0 if inspecting else 0.0,dt*(3.2 if inspecting else 4.5))
	# N (držet): prohlídka zbraně – zvednout, otočit z obou stran (jako v Rustu / CoD).
	# Míření, střelba, přebíjení i úder ji přeruší.
	var lmb:=enabled and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var rmb:=enabled and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	examining=enabled and Input.is_physical_key_pressed(KEY_N) and not lmb and not rmb and reload_left<=0 and melee_left<=0 and inspect<0.05 and sprint_amount<0.3
	if _tag: _tag.queue_redraw()
	var wiping:=float(player.body.weapon.wipe)>0.0      # VISOR (experiment): levá ruka otírá hledí
	var trigger:=enabled and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and inspect<0.2 and float(player.body.weapon._ex_w)<0.35 and not wiping
	var sights:=((enabled and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)) or (test_aim and equipped)) and not wiping
	var s: Dictionary=stats()
	if reload_left>0:
		reload_left=maxf(0,reload_left-dt)
		if reload_left==0:
			var need: int=int(s.mag)-ammo
			var take:=need if infinite_reserve else mini(need,reserve)
			ammo+=take
			if not infinite_reserve: reserve-=take
	# Střelba, míření a úder ruší sprint; při sprintu je zbraň sklopená a nestřílí.
	player.sprint_lock=equipped and (trigger or sights or melee_left>0)
	var speed:=Vector2(player.velocity.x,player.velocity.z).length()
	var sprinting: bool=(equipped or item_held!="") and _inject_t<0.0 and player._sprint and speed>Player.WALK+0.4 and player.is_on_floor() and not player.crouching and not player.swimming
	sprint_amount=move_toward(sprint_amount,1.0 if sprinting else 0.0,dt*(4.5 if sprinting else 7.0))
	aiming=sights and reload_left<=0 and melee_left<=0
	aim_amount=lerpf(aim_amount,1.0 if aiming else 0.0,1.0-exp(-14.0*dt))
	_cooldown=maxf(0,_cooldown-dt)
	_shimmer_cd=maxf(0.0,_shimmer_cd-dt)
	if melee_left>0:
		melee_left=maxf(0,melee_left-dt)
		if _melee_pending and melee_left<MELEE-0.13:
			_melee_pending=false
			melee_hit.emit(player.camera.global_position,-player.camera.global_basis.z)
	# Rozptyl: stání < chůze < běh, dávka ho rozevírá, míření téměř ruší.
	_heat*=exp(-5.5*dt)
	var base: float=float(s.spread)+0.013*clampf(speed/Player.WALK,0.0,1.7)
	if player.crouching: base*=0.7
	if not player.is_on_floor() and not player.swimming: base+=0.03
	spread=lerpf(base+_heat,0.0012+_heat*0.2,aim_amount)+float(s.pellet_spread)*(1.0-aim_amount*0.4)
	var before:=_punch
	_punch_target*=exp(-(2.2 if _cooldown>0 else 7.0)*dt)
	_punch=_punch.lerp(_punch_target,1.0-exp(-38.0*dt))
	player.pitch=clampf(player.pitch+(_punch.y-before.y),-1.5,1.5)
	player.yaw+=_punch.x-before.x
	var rig: Node=player.body.weapon
	rig.equipped=equipped or item_held!=""
	rig.aim=aim_amount
	rig.pitch=player.pitch
	rig.sprint=sprint_amount
	rig.melee=1.0-melee_left/MELEE if melee_left>0 else 0.0
	rig.inspect=inspect
	rig.loaded=ammo
	rig.examine_hold=examining or test_examine
	rig.local_velocity=Basis(Vector3.UP,-player.yaw)*player.velocity
	rig.step_phase=player._bob_phase
	rig.crouch_now=player.crouching
	rig.air_vy=0.0 if (player.is_on_floor() or player.swimming) else player.velocity.y
	rig.obstruct=_wall_ahead(rig) if (equipped and wall_react and not player.swimming) else 0.0
	if item_held!="": _update_item(dt)
	# Dopad ze skoku/pádu: zbraň se propadne a hlaveň klesne.
	var on_floor_now: bool=player.is_on_floor()
	if on_floor_now and not _was_floor and _fall_vel<-2.5:
		var k:=clampf(-_fall_vel/8.0,0.0,1.0)
		rig.impulse(Vector3(0,-0.9*k,0),Vector3(-1.4*k,0,randf_range(-0.4,0.4)*k))
	elif not on_floor_now and _was_floor and player.velocity.y>1.0:
		rig.impulse(Vector3(0,-0.3,0),Vector3(-0.4,0,0))     # odraz při skoku
	_fall_vel=player.velocity.y if not on_floor_now else 0.0
	_was_floor=on_floor_now
	# Klidná zbraň: při míření, drženém R a přebíjení se tlumí houpání zbraně i pohledu.
	var steady_target:=maxf(maxf(aim_amount,float(rig._ex_w)*0.7),maxf(inspect,1.0 if reload_left>0 else 0.0))
	_steady=move_toward(_steady,steady_target,dt*5.0)
	rig.steady=_steady
	rig.steady_keep=player.aim_sway
	player.steady=_steady
	var pull: bool=trigger and (bool(s.auto) or not _trigger_was)
	_trigger_was=trigger
	if pull and reload_left<=0 and melee_left<=0 and _cooldown<=0 and _switch_left<=0 and sprint_amount<0.35:
		if ammo>0: _trigger_pending=true
		elif can_reload(): reload()
		else:
			# Prázdná zbraň bez zásoby: jen cvakne.
			_cooldown=0.28
			if ResourceLoader.exists("res://audio/dry_fire.wav"):
				_ui_sound.stream=load("res://audio/dry_fire.wav")
				_ui_sound.pitch_scale=1.0
				_ui_sound.play()

func _click(file: String, pitch: float) -> void:
	if ResourceLoader.exists("res://audio/"+file):
		_ui_sound.stream=load("res://audio/"+file)
		_ui_sound.pitch_scale=pitch
		_ui_sound.play()

func _make_tag() -> void:
	var layer:=CanvasLayer.new()
	layer.layer=5
	add_child(layer)
	_tag=Control.new()
	_tag.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tag.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_tag.draw.connect(_draw_tag)
	layer.add_child(_tag)
	var system:=SystemFont.new()
	system.font_names=PackedStringArray(["Bahnschrift","Segoe UI","Helvetica Neue","Arial","DejaVu Sans"])
	system.font_weight=600
	_tag_font=system

func _draw_tag() -> void:
	# Tečka na zásobníku (u dvojky na nábojích v hlavních), čára a počet nábojů.
	if inspect<0.75 or not equipped: return
	var rig: Node=player.body.weapon
	var camera: Camera3D=player.camera
	var anchor: Vector3=rig.inspect_point()
	if camera.is_position_behind(anchor): return
	var a:=clampf((inspect-0.75)/0.25,0.0,1.0)
	var dot:=camera.unproject_position(anchor)
	# Zásobník pistole bývá pod okrajem obrazu: tečka zůstane na okraji.
	var screen:=_tag.get_viewport_rect().size
	dot=dot.clamp(Vector2(30,30),screen-Vector2(260,40))
	var bend:=dot+Vector2(60,-70)
	var main_text:=str(ammo)
	var sub:="zásoba  "+("∞" if infinite_reserve else str(reserve))
	var size:=_tag_font.get_string_size(sub,HORIZONTAL_ALIGNMENT_LEFT,-1,18)
	var end:=bend+Vector2(maxf(size.x+30,150),0)
	for pass_i in 2:
		var c:=Color(0,0,0,0.6*a) if pass_i==0 else Color(1,1,1,0.95*a)
		var o:=Vector2(1.5,1.5) if pass_i==0 else Vector2.ZERO
		_tag.draw_circle(dot+o,5.5,c)
		_tag.draw_polyline(PackedVector2Array([dot+o,bend+o,end+o]),c,2.2,true)
		_tag.draw_string(_tag_font,bend+o+Vector2(14,-10),main_text,HORIZONTAL_ALIGNMENT_LEFT,-1,40,c)
		_tag.draw_string(_tag_font,bend+o+Vector2(14,24),sub,HORIZONTAL_ALIGNMENT_LEFT,-1,18,c if pass_i==0 else Color(1,0.85,0.5,0.95*a))

func finish_frame() -> void:
	if _trigger_pending:
		_trigger_pending=false
		shoot()

func shoot() -> void:
	if not equipped or ammo<=0 or reload_left>0 or _switch_left>0.0 or player.swimming: return
	var s: Dictionary=stats()
	if not debug_ammo: ammo-=1
	_cooldown=s.rate
	# Zpětný ráz pohledu: rychlý zdvih, při dávce stoupá a po puštění spouště se z větší části vrátí.
	var main_ref=player.get_parent()
	var rscale:=float(main_ref.settings.get("recoil",1.0)) if "settings" in main_ref else 1.0
	player.body.weapon.recoil_scale=rscale
	player.body.weapon.kick()
	var kick: Vector2=s.kick*rscale*(0.7 if aiming else 1.0)
	# Část rázu je trvalá: hlaveň v dávce stoupá a hráč ji musí strhávat myší dolů (jako v reálu).
	# Zbytek je rychlé škubnutí, které se samo vrátí. Vodorovně ráz bloudí, s mírnou tendencí doprava.
	var climb:=randf_range(kick.y*0.8,kick.y*1.2)
	player.pitch=clampf(player.pitch+climb*0.55,-1.5,1.5)
	player.yaw+=randf_range(-kick.x*0.8,kick.x*1.1)*0.6
	_punch_target+=Vector2(randf_range(-kick.x,kick.x),climb*0.45)
	_punch_target=_punch_target.clamp(Vector2(-0.05,0.0),Vector2(0.05,0.16))
	# Rána do mířidel: zbraň po výstřelu chvíli nemíří přesně tam, kam pohled (rozhodí další střelu).
	_heat=minf(_heat+kick.y*0.35,0.05)
	var camera:=player.camera
	var aim_xf: Transform3D=camera.global_transform
	if player.cam_fx and player.cam_fx.active(): aim_xf=player.cam_fx.aim_transform(player)   # BODYCAM: střela letí ve směru hlavně
	var origin:=aim_xf.origin
	damage=s.damage
	# Každý brok (nebo jediná střela) letí náhodně uvnitř kužele rozptylu.
	for pellet in int(s.pellets):
		var angle:=randf()*TAU
		var off:=tan(spread)*sqrt(randf())
		var forward: Vector3=(-aim_xf.basis.z+aim_xf.basis.x*cos(angle)*off+aim_xf.basis.y*sin(angle)*off).normalized()
		var query:=PhysicsRayQueryParameters3D.create(origin,origin+forward*100.0,1|32|64)
		query.collide_with_areas=true
		var hit:=player.get_world_3d().direct_space_state.intersect_ray(query)
		var point: Vector3=hit.position if hit else origin+forward*100.0
		fired.emit(origin,point)
		if pellet==0: player.body.action_started.emit("shot",[origin,point])
	_heat=minf(_heat+(0.0045 if s.auto else 0.009),0.03)
	var main_node=player.get_parent()
	var user_pitch:=float(main_node.settings.get("gun_%s_pitch" % current,1.0)) if "settings" in main_node else 1.0
	_shot_sound.pitch_scale=float(s.pitch)*user_pitch*randf_range(0.96,1.04)
	_shot_sound.volume_db=float(s.volume)
	_shot_sound.play()
	_play_zap()
	var sfx_node=player.get_parent().get("sfx")
	if sfx_node: sfx_node.duck()
	if _tail_sound.stream:
		_tail_sound.pitch_scale=float(s.pitch)*randf_range(0.92,1.06)
		_tail_sound.play()
