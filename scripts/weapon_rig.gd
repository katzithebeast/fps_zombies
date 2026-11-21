extends Node
## Procedurální obouruční držení; řešení dvou kostí zachovává délky paží.
# Všechny zbraně jsou převedené do stejné podoby (tools/build_guns.gd): hlaveň -Z, počátek v úchopu pravé ruky.
# muzzle = ústí, left = úchop levé ruky, handle = závěr / natahovač, mag_hand = kde levá ruka bere zásobník,
# hip = poloha od boku, aim_y = výška při míření (mířidla v ose oka), reload = styl přebíjení.
const GUNS:={
	"ak":{"rsnd":"","scene":"res://assets/ak47/ak47.tscn","muzzle":Vector3(0,0.09,-0.66),"left":Vector3(-0.025,0.025,-0.26),
		"handle":Vector3(0.045,0.075,-0.02),"mag_hand":Vector3(0,-0.15,-0.13),"hip":Vector3(-0.20,-0.21,0.24),"aim_y":-0.116,
		"reload":"mag","reload_time":2.2,"shell":Vector3(0.035,0.075,-0.06),"flash":1.0},
	"mp40":{"rsnd":"mp40_reload.wav","scene":"res://assets/mp40/mp40.tscn","muzzle":Vector3(0,0.055,-0.62),"left":Vector3(-0.02,-0.06,-0.31),
		"handle":Vector3(-0.035,0.045,-0.1),"mag_hand":Vector3(0,-0.17,-0.31),"hip":Vector3(-0.20,-0.20,0.24),"aim_y":-0.074,
		"reload":"mag","reload_time":2.4,"shell":Vector3(0.03,0.05,-0.08),"flash":0.85},
	"deagle":{"rsnd":"deagle_reload.wav","scene":"res://assets/deagle/deagle.tscn","muzzle":Vector3(0,0.08,-0.275),"left":Vector3(-0.035,-0.025,0.01),
		"handle":Vector3(0,0.1,0.03),"mag_hand":Vector3(0,-0.07,0.02),"hip":Vector3(-0.11,-0.085,0.22),"aim_y":-0.061,
		"reload":"pistol","reload_time":1.8,"shell":Vector3(0.02,0.09,-0.02),"flash":1.2},
	"izh54":{"rsnd":"izh_reload.wav","scene":"res://assets/izh54/izh54.tscn","muzzle":Vector3(0,0.07,-0.9),"left":Vector3(-0.025,0.03,-0.33),
		"handle":Vector3(0,0.06,-0.15),"mag_hand":Vector3(-0.02,0.02,-0.12),"hip":Vector3(-0.20,-0.20,0.26),"aim_y":-0.053,
		"reload":"break","reload_time":2.6,"ads_pull":0.012,"shell":Vector3.ZERO,"flash":1.6},
}
# Předměty, které se drží v ruce místo zbraně (stejný systém úchopu, houpání a IK).
const ITEM_POSES:={
	"syringe":{"rsnd":"","scene":"","muzzle":Vector3(0,0,-0.2),"left":Vector3(0,0,0),"handle":Vector3(0,0.05,0),
		"mag_hand":Vector3.ZERO,"hip":Vector3(-0.12,-0.17,0.3),"aim_y":-0.08,"reload":"pistol","reload_time":1.0,
		"shell":Vector3.ZERO,"flash":0.0},
	"pumpkin":{"rsnd":"","scene":"","muzzle":Vector3(0,0.06,-0.15),"left":Vector3(0,0,0),"handle":Vector3(0,0.05,0),
		"mag_hand":Vector3.ZERO,"hip":Vector3(-0.13,-0.19,0.3),"aim_y":-0.08,"reload":"pistol","reload_time":1.0,
		"shell":Vector3.ZERO,"flash":0.0},
}
var inject:=0.0             # 0..1 průběh vpichu injekce (0 = jen drží)
const HandGrip:=preload("res://scripts/hand_grip.gd")
var grip_solver: RefCounted          # úchop zbraní: ruce na úchopových bodech, prsty na povrchu (hand_grip.gd)
var _socket_mode:=false
var _trigger_pull:=0.0               # stisk spouště při výstřelu (1 → 0)
var _discipline:=0.0                 # 1 = ukazovák mimo spoušť podél pouzdra (přebíjení, sprint)
var _rf_cache:={}                    # zbraň → {kost: rotace} pravé ruky (prsty, ukazovák na spoušti / podél pouzdra)
var _lf_cache:={}                    # zbraň → {kost: rotace} levé ruky v úchopu
var _left_support:={}                # zbraň → zápěstí levé ruky (souřadnice zbraně) vč. prstů pravé ruky
var _lf_live:={}
var _grip_debug:=OS.get_environment("GRIP_DEBUG")   # ladicí výpisy úchopů (tools/bake_grips.gd)
var _lpush:=Vector3.ZERO               # vytlačení levé ruky ze zbraně (souřadnice zbraně)
var _lf_tick:=0

func _gi() -> Dictionary:
	return ITEM_POSES[gun] if ITEM_POSES.has(gun) else GUNS[gun]

func _gi_of(name: String) -> Dictionary:
	return ITEM_POSES[name] if ITEM_POSES.has(name) else GUNS[name]

var avatar: Node3D
var equipped := false
var aim := 0.0
var pitch := 0.0
var recoil := 0.0
var reload_left := 0.0
var weight := 0.0
var full: Node3D
var first: Node3D
var _time := 0.0
var _flash_time := 0.0
const FLASH_TIME:=0.04
const FLASH_BASE:=Color(1.35,1.15,0.95)
const SMOKE_POOL:=6
var _smoke_next:=0
var _flashes: Array[Node3D] = []
var right_error := 0.0
var left_error := 0.0
var _pose_skeleton: Skeleton3D
var _left_grip:=Vector3.ZERO
var _right_grip:=Vector3.ZERO
var _left_basis:=Basis.IDENTITY
var _right_basis:=Basis.IDENTITY
var _left_free:=0.0
var first_right_error:=0.0
var first_left_error:=0.0
var gun:="ak"
var inspect:=0.0          # 0..1 kontrola zásobníku
var examine_hold:=false   # držené N: prohlídka zbraně (jako v Rustu / CoD)
var _ex_w:=0.0
var _ex_t:=0.0
var _ex_step:=0
var _ex_pos:=Vector3.ZERO
var _ex_pos_v:=Vector3.ZERO
var _ex_rot:=Vector3.ZERO
var _ex_rot_v:=Vector3.ZERO
var _ex_off:=0.0
var examine_override:=[]   # ladění: pevná póza prohlídky [posun, natočení]
var _left_relax:=0.0        # levá ruka mimo zbraň: uvolněné prsty
var steady:=0.0           # 0..1 míření / držené R / přebíjení
var steady_keep:=0.1      # nastavení: kolik houpání při tom zůstane (0 = žádné)
var _head_slow:=Vector3.ZERO
const HEAD_REST_Z:=-0.022      # poloha hlavy v klidu (k ní jsou naladěné pózy zbraně)
var head_offset:=Vector3.ZERO     # o kolik kamera posune oko oproti kosti hlavy (tlumení houpání)
var _last_mag_shift:=Vector3.ZERO
var _head_smooth:=Vector3.ZERO
var _reach:=Vector3.ZERO
var _reach_v:=Vector3.ZERO
var _head_v:=Vector3.ZERO
var _full_reload: AudioStream
var reload_time:=2.2
var reload_empty:=true
var reload_mul:=1.0           # pokřtěné / vylepšené zbraně přebíjejí rychleji
var _rpitch:=1.0
var _pap:={}                  # zbraně pokřtěné v andělově vodě (náš Pack-a-Punch)
var _pap_mat: ShaderMaterial
var _pap_lights: Array=[]
var _pap_arcs: Array=[]          # výboje po povrchu zbraní (stupeň 3 a 4)
var _pap_strength:=1.0
var _pap_surge:=0.0
var holster:=0.0             # 0 držení, 1 zbraň schovaná pod obrazem
var muzzle:=Vector3(0,0.09,-0.66)
var handle:=Vector3(0.045,0.075,-0.02)
var hip_pose:=Vector3(-0.15,-0.235,0.30)
var CLAV_L_TP:=Vector3(0,-0.04,0.13)      # levé rameno se k podpěře předsune
var CLAV_L_FP:=Vector3(0.08,-0.04,0.20)
var CLAV_R_TP:=Vector3(0.0,-0.08,-0.08)     # kam míří pravá klíční kost (3. osoba)
var CLAV_R_FP:=Vector3(-0.15,-0.08,-0.06)  # totéž ve vlastním pohledu
var ELBOW_AUTO:=1.0        # jak moc loket sleduje rovné zápěstí (0 = jen zadaný pól)
var FOREARM_TWIST:=0.75    # podíl otočení dlaně, který nese předloktí místo zápěstí
var UPPER_TWIST:=0.4       # u natažené paže nese část otočení i rameno
var _hand_axis:={}           # kost ruky → směr ke kořeni prostředníčku v souřadnicích ruky (klid)
const ADS_PULL:=0.06        # při míření se oko vzdálí od mířidel (jinak pouzdro závěru zakryje půl obrazu)
const HIP_YAW:=0.05
const HIP_ROLL:=-0.09
const SPRINT_MOVE:=Vector3(0.0,0.05,-0.02)
const SPRINT_YAW:=0.6
const SPRINT_PITCH:=-0.06
const SPRINT_ROLL:=-0.55
var sprint:=0.0          # 0..1 běh se sklopenou zbraní
var melee:=0.0           # 0..1 průběh úderu pažbou (0 = žádný)
var _kick:=Vector3.ZERO
# --- Zpětný ráz a pohyb zbraně jako tlumené pružiny (rychlý ráz, překmit, usazení).
# back = rychlost odskoku dozadu (m/s), up = nahoru, rise = zdvih hlavně (rad/s), yaw/roll = náhodný rozptyl.
const RECOIL:={
	"ak":     {"back":0.95,"up":0.22,"rise":0.55,"yaw":0.28,"roll":0.75,"cam_roll":0.006},
	"mp40":   {"back":0.70,"up":0.14,"rise":0.38,"yaw":0.24,"roll":0.55,"cam_roll":0.004},
	"deagle": {"back":1.05,"up":0.45,"rise":2.2,"yaw":0.45,"roll":1.1,"cam_roll":0.012},
	"izh54":  {"back":1.70,"up":0.55,"rise":2.6,"yaw":0.55,"roll":1.3,"cam_roll":0.018},
}
var _rk_p:=Vector3.ZERO      # posun: x do strany, y nahoru, z dozadu (ke kameře)
var _rk_pv:=Vector3.ZERO
var _rk_r:=Vector3.ZERO      # rotace: x zdvih hlavně, y vybočení, z náklon
var _rk_rv:=Vector3.ZERO
var recoil_scale:=1.0
var _drops: Array=[]
var _mag_dropped:=false
var _draw:=0.0               # 1 → 0 vytažení zbraně po přepnutí
var local_velocity:=Vector3.ZERO   # rychlost hráče v jeho souřadnicích (nastavuje player_weapon)
var step_phase:=0.0                # fáze kroku z hráče (houpání v rytmu chůze)
var _move_tilt:=0.0
var _move_push:=0.0
var _velocity_smooth:=Vector3.ZERO
var _inertia_offset:=Vector3.ZERO
var _aim_last:=0.0
var _aim_roll:=0.0
# Váha zbraně v rukou (bez míření): pružiny s překmitem místo prostého dotahování.
var sway_scale:=1.0                # nastavení „Kývání zbraně“
var obstruct:=0.0                  # 0..1 jak moc zbraň narazila před sebou do zdi (nastavuje player_weapon)
var _ob:=0.0
var _ob_v:=0.0
var air_vy:=0.0                    # svislá rychlost ve vzduchu (0 na zemi)
var _air:=Vector2.ZERO             # x posun nahoru/dolů, y náklon hlavně
var _air_v:=Vector2.ZERO
var _foot_idx:=0
var crouch_now:=false
var _sway_v:=Vector2.ZERO
var _tilt_v:=0.0
var _gait:=0.0
var _gait_v:=0.0
var _inertia_v:=Vector3.ZERO
var _breath_boost:=0.0
var _idle_drift:=Vector3.ZERO      # pomalé „přehmátnutí“ rukou: x, y posun, z náklon
var _idle_goal:=Vector3.ZERO
var _idle_next:=2.0
var _was_crouch:=false
const MASS:={"ak":1.0,"mp40":0.9,"deagle":0.6,"izh54":1.15}

func impulse(pos_vel: Vector3, rot_vel: Vector3) -> void:
	# Vnější náraz do zbraně: dopad ze skoku, cvaknutí zásobníku, natažení závěru.
	_rk_pv+=pos_vel
	_rk_rv+=rot_vel

func _springs(dt: float) -> void:
	var steps:=maxi(1,ceili(dt/0.006))
	var h:=dt/steps
	for i in steps:
		# posun: tuhost 420, mírně podtlumené (zeta 0.55) → rychlý ráz a krátký překmit
		_rk_pv+=(-420.0*_rk_p-2.0*0.55*20.5*_rk_pv)*h
		_rk_p+=_rk_pv*h
		# rotace: měkčí (tuhost 300, zeta 0.45) → hlaveň vyskočí a s houpnutím se vrátí
		_rk_rv+=(-300.0*_rk_r-2.0*0.45*17.3*_rk_rv)*h
		_rk_r+=_rk_rv*h
var _sway:=Vector2.ZERO
var _last_yaw:=0.0
var _last_pitch:=0.0
var _reload_step:=0
var _remote:=false
var _light: OmniLight3D
var _shells: Array=[]
var _shell_mesh: CylinderMesh
var _sounds: Dictionary={}

func _ready() -> void:
	grip_solver=HandGrip.new()
	grip_solver.setup(avatar.skeleton)
	full = make_gun(4)
	first = make_gun(8)
	avatar.model.add_child(full)
	avatar.model.add_child(first)
	# klidové polohy pohyblivých dílů (zásobník, sklopné hlavně) pro distanční pole úchopu
	for key in GUNS:
		var model: Node3D=full.get_node_or_null(key)
		if model==null: continue
		var rest:={}
		for part in ["Magazine","Barrel"]:
			var n: Node3D=model.get_node_or_null(part)
			if n: rest[part.to_lower()]=n.transform
		grip_solver.part_rest[key]=rest
	if OS.get_environment("GRIP_BAKE")=="": _load_grips()
	full.visible=false
	first.visible=false
	# Velmi slabé odražené světlo pouze pro vlastní ruce a zbraň.
	# Zachová siluetu a materiál bez prosvětlení místnosti nebo nepřátel.
	var fill:=OmniLight3D.new()
	fill.name="ViewmodelBounce"
	fill.position=Vector3(-0.25,0.35,0.12)
	fill.light_color=Color(0.62,0.72,0.76)
	fill.light_energy=0.22
	fill.omni_range=1.4
	fill.light_cull_mask=8
	fill.shadow_enabled=false
	fill.light_specular=0.25
	fill.light_volumetric_fog_energy=0.0
	first.add_child(fill)
	_light=OmniLight3D.new()
	_light.position=muzzle+Vector3(0,0,-0.15)
	_light.light_color=Color(1.0,0.72,0.4)
	_light.light_energy=0.0
	_light.omni_range=7.0
	_light.omni_attenuation=1.4
	_light.shadow_enabled=false
	_light.light_volumetric_fog_energy=0.0
	_light.omni_range=5.5
	full.add_child(_light)
	_shell_mesh=CylinderMesh.new()
	_shell_mesh.top_radius=0.0045
	_shell_mesh.bottom_radius=0.0055
	_shell_mesh.height=0.036
	_shell_mesh.radial_segments=8
	_shell_mesh.rings=1
	var brass:=StandardMaterial3D.new()
	brass.albedo_color=Color(0.78,0.6,0.25)
	brass.metallic=1.0
	brass.roughness=0.32
	_shell_mesh.material=brass
	_sounds={"out":_make_sound("ak_mag_out.wav",-6.0),"in":_make_sound("ak_mag_in.wav",-4.0),"bolt":_make_sound("ak_bolt.wav",-3.0),"handle":_make_sound("gun_handle_1.wav",-13.0)}
	set_gun("ak")

func set_gun(name: String, draw: bool=true) -> void:
	if not GUNS.has(name) and not ITEM_POSES.has(name): return
	cancel_reload()
	gun=name
	var info: Dictionary=_gi_of(name)
	muzzle=info.muzzle
	handle=info.handle
	hip_pose=info.hip
	reload_time=info.reload_time
	reload_left=0.0
	_draw=1.0 if draw else 0.0
	_rk_p=Vector3.ZERO
	_rk_pv=Vector3.ZERO
	_rk_r=Vector3.ZERO
	_rk_rv=Vector3.ZERO
	for holder in [full,first]:
		if holder==null: continue
		for key in GUNS.keys()+ITEM_POSES.keys():
			var model: Node3D=holder.get_node_or_null(key)
			if model==null: continue
			model.visible=key==name
			if not GUNS.has(key): continue
			var mag:=model.get_node_or_null("Magazine")
			if mag:
				mag.position=Vector3.ZERO
				mag.rotation=Vector3.ZERO
				mag.visible=true
			var barrel:=model.get_node_or_null("Barrel")
			if barrel: barrel.rotation.x=0.0
	for flash in _flashes:
		flash.position=muzzle
		flash.scale=Vector3.ONE*float(info.flash)
	for holder in [full,first]:
		if holder==null: continue
		for i in SMOKE_POOL:
			var sm: Node3D=holder.get_node_or_null("smoke%d"%i)
			if sm: sm.position=muzzle+Vector3(0,0,-0.03)
	if _light: _light.position=muzzle+Vector3(0,0,-0.15)
	_update_flash_tint()
	_full_reload=null
	if _sounds.has("in") and ResourceLoader.exists("res://audio/ak_mag_in.wav"): _sounds["in"].stream=load("res://audio/ak_mag_in.wav")
	if info.rsnd!="" and ResourceLoader.exists("res://audio/"+info.rsnd): _full_reload=load("res://audio/"+info.rsnd)

func _part(holder: Node3D, part: String) -> Node3D:
	return holder.get_node_or_null(gun+"/"+part)

func make_gun(layer: int) -> Node3D:
	var gun:=Node3D.new()
	for key in GUNS:
		var model: Node3D=load(GUNS[key].scene).instantiate()
		model.name=key
		model.visible=key=="ak"
		gun.add_child(model)
	var syr:=_make_syringe()
	syr.visible=false
	gun.add_child(syr)
	var bomb:=Node3D.new()
	bomb.name="pumpkin"
	bomb.visible=false
	var pk:=Props.make("pumpkin")
	pk.scale=Vector3.ONE*0.4
	pk.position=Vector3(0.0,0.0,-0.06)
	bomb.add_child(pk)
	gun.add_child(bomb)
	for mesh in gun.find_children("*","MeshInstance3D",true,false): mesh.layers=layer
	# Záblesk: čelní zubatá hvězda + tři zkřížené boční plameny (každá rána jiná varianta z atlasu).
	var flash:=Node3D.new()
	flash.position=muzzle
	var star_tex: Texture2D=load("res://assets/fx/muzzle_star.png")
	var side_tex: Texture2D=load("res://assets/fx/muzzle_side.png")
	for i in 4:
		var mat:=StandardMaterial3D.new()
		mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode=BaseMaterial3D.CULL_DISABLED
		mat.disable_fog=true
		mat.disable_receive_shadows=true
		mat.albedo_texture=star_tex if i==3 else side_tex
		mat.uv1_scale=Vector3(0.25,1,1)
		mat.albedo_color=FLASH_BASE
		var quad:=MeshInstance3D.new()
		var mesh:=QuadMesh.new()
		mesh.size=Vector2(0.27,0.27) if i==3 else Vector2(0.44,0.17)
		quad.mesh=mesh
		quad.material_override=mat
		quad.layers=layer
		quad.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i<3:
			# plocha podél hlavně: levý okraj textury (ústí) přesně na ústí
			quad.rotation=Vector3(0,PI/2,0)
			quad.position=Vector3(0,0,-0.215)
			quad.name="side"
			var holder:=Node3D.new()
			holder.rotation.z=i*PI/3.0
			holder.add_child(quad)
			flash.add_child(holder)
		else:
			quad.position=Vector3(0,0,-0.015)
			quad.name="star"
			flash.add_child(quad)
	# Kouř z hlavně: pár obláčků, které zůstanou viset ve vzduchu (střídá se několik emitorů).
	var smoke_tex: Texture2D=load("res://assets/fx/smoke_puff.png")
	var smoke_mat:=StandardMaterial3D.new()
	smoke_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.billboard_mode=BaseMaterial3D.BILLBOARD_PARTICLES
	smoke_mat.vertex_color_use_as_albedo=true
	smoke_mat.albedo_texture=smoke_tex
	smoke_mat.albedo_color=Color(0.78,0.78,0.76)
	smoke_mat.roughness=1.0
	smoke_mat.disable_receive_shadows=true
	var smoke_pm:=ParticleProcessMaterial.new()
	smoke_pm.direction=Vector3(0,0,-1)
	smoke_pm.spread=16.0
	smoke_pm.initial_velocity_min=0.35
	smoke_pm.initial_velocity_max=1.1
	smoke_pm.damping_min=1.4
	smoke_pm.damping_max=2.4
	smoke_pm.gravity=Vector3(0,0.22,0)
	smoke_pm.angle_min=-180.0
	smoke_pm.angle_max=180.0
	smoke_pm.angular_velocity_min=-25.0
	smoke_pm.angular_velocity_max=25.0
	smoke_pm.scale_min=0.7
	smoke_pm.scale_max=1.2
	var grow:=Curve.new()
	grow.add_point(Vector2(0.0,0.35))
	grow.add_point(Vector2(1.0,1.0))
	var grow_tex:=CurveTexture.new()
	grow_tex.curve=grow
	smoke_pm.scale_curve=grow_tex
	var fade:=Gradient.new()
	fade.offsets=PackedFloat32Array([0.0,0.15,1.0])
	fade.colors=PackedColorArray([Color(1,1,1,0.0),Color(1,1,1,0.2),Color(1,1,1,0.0)])
	var fade_tex:=GradientTexture1D.new()
	fade_tex.gradient=fade
	smoke_pm.color_ramp=fade_tex
	var smoke_quad:=QuadMesh.new()
	smoke_quad.size=Vector2(0.12,0.12)
	smoke_quad.material=smoke_mat
	for i in SMOKE_POOL:
		var sm:=GPUParticles3D.new()
		sm.name="smoke%d"%i
		sm.amount=4
		sm.lifetime=1.2
		sm.one_shot=true
		sm.explosiveness=0.85
		sm.local_coords=false
		sm.emitting=false
		sm.process_material=smoke_pm
		sm.draw_pass_1=smoke_quad
		sm.layers=layer
		sm.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sm.visibility_aabb=AABB(Vector3(-3,-3,-3),Vector3(6,6,6))
		sm.position=muzzle+Vector3(0,0,-0.03)
		gun.add_child(sm)
	flash.visible=false
	gun.add_child(flash)
	_flashes.append(flash)
	return gun

func _make_sound(file: String, volume: float) -> AudioStreamPlayer3D:
	var player:=AudioStreamPlayer3D.new()
	if ResourceLoader.exists("res://audio/"+file): player.stream=load("res://audio/"+file)
	player.volume_db=volume
	player.unit_size=4.0
	player.bus="World" if AudioServer.get_bus_index("World")>=0 else "Master"
	full.add_child(player)
	return player

func set_remote_layers() -> void:
	_remote=true
	for mesh in full.find_children("*","GeometryInstance3D",true,false): mesh.layers=16
	for mesh in first.find_children("*","GeometryInstance3D",true,false): mesh.layers=0

func muzzle_global() -> Vector3:
	var holder:=full if _remote or avatar.first_mesh.layers==0 else first
	return holder.global_transform*muzzle

func kick() -> void:
	_trigger_pull=1.0
	if _pap.has(gun): _pap_surge=1.0
	var r: Dictionary=RECOIL.get(gun,RECOIL.ak)
	# Při míření drží zbraň pevněji u ramene: méně rotace, odskok jde víc dozadu do ramene.
	var rot_k:=lerpf(1.0,0.55,aim)*recoil_scale
	var pos_k:=lerpf(1.0,0.8,aim)*recoil_scale
	_rk_pv+=Vector3(randf_range(-0.12,0.12)*float(r.back),float(r.up)*randf_range(0.8,1.15),float(r.back)*randf_range(0.9,1.1))*pos_k
	_rk_rv+=Vector3(float(r.rise)*randf_range(0.85,1.15),randf_range(-1.0,1.0)*float(r.yaw),randf_range(-1.0,1.0)*float(r.roll))*rot_k
	# Kamera se při ráně krátce natočí (u těžkých zbraní víc).
	var p=avatar.get_parent()
	if p and "_roll" in p: p._roll+=randf_range(-1.0,1.0)*float(r.cam_roll)*recoil_scale
	_flash_time=FLASH_TIME
	var side_f:=randi()%4
	var star_f:=randi()%4
	var len_k:=randf_range(0.75,1.3)
	var wid_k:=randf_range(0.85,1.15)
	for flash in _flashes:
		flash.rotation.z=randf()*TAU
		flash.scale=Vector3(wid_k,wid_k,len_k)*float(_gi().flash)
		for q in flash.find_children("*","MeshInstance3D",true,false):
			var m:=(q as MeshInstance3D).material_override as StandardMaterial3D
			if m==null: continue
			var f:=star_f if q.name=="star" else (side_f+q.get_index()+int(q.get_parent().rotation.z*2.0))%4
			m.uv1_offset=Vector3(0.25*f,0,0)
	# Obláček kouře z hlavně (oba držáky, každá kamera vidí svůj).
	if float(_gi().flash)>0.0:
		for holder in [full,first]:
			var sm: GPUParticles3D=holder.get_node_or_null("smoke%d"%_smoke_next)
			if sm:
				sm.amount=3 if aim>0.5 else 4
				sm.restart()
		_smoke_next=(_smoke_next+1)%SMOKE_POOL
	if _light: _light.light_energy=randf_range(2.2,3.2)*float(_gi().flash)
	if _gi().shell!=Vector3.ZERO: _eject_shell(_gi().shell)

func _eject_shell(from: Vector3) -> void:
	if not is_inside_tree(): return
	var holder:=full if _remote or avatar.first_mesh.layers==0 else first
	var shell:=MeshInstance3D.new()
	shell.mesh=_shell_mesh
	shell.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().root.add_child(shell)
	shell.global_transform=Transform3D(holder.global_basis.orthonormalized(),holder.global_transform*from)
	var basis:=holder.global_basis.orthonormalized()
	var velocity:=basis.x*randf_range(1.8,2.6)+basis.y*randf_range(1.2,1.9)+basis.z*randf_range(-0.5,0.2)
	_shells.append({"node":shell,"velocity":velocity,"spin":Vector3(randf_range(-25,25),randf_range(-25,25),randf_range(-25,25)),"age":0.0})

func _drop_magazine() -> void:
	if not is_inside_tree() or _remote: return
	var src:=_part(full,"Magazine")
	if src==null: return
	var mag: Node3D=src.duplicate()
	get_tree().root.add_child(mag)
	mag.global_transform=src.global_transform
	for m in mag.find_children("*","MeshInstance3D",true,false): (m as MeshInstance3D).layers=1
	if mag is MeshInstance3D: (mag as MeshInstance3D).layers=1
	var b:=full.global_basis.orthonormalized()
	_drops.append({"node":mag,"velocity":b.y*-0.6+b.x*randf_range(-0.3,0.3),"spin":Vector3(randf_range(-6,6),randf_range(-3,3),randf_range(-6,6)),"age":0.0,"rest":false})

func _update_drops(dt: float) -> void:
	for d in _drops:
		d.age+=dt
		var node: Node3D=d.node
		if not is_instance_valid(node): continue
		if not d.rest:
			d.velocity.y-=9.8*dt
			var from:=node.global_position
			var to:=from+(d.velocity as Vector3)*dt
			var hit:=node.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to+Vector3.DOWN*0.03,1))
			if hit.is_empty():
				node.global_position=to
				node.rotate_object_local((d.spin as Vector3).normalized(),(d.spin as Vector3).length()*dt)
			else:
				# Dopad: poskočí a lehne si na bok.
				node.global_position=hit.position+Vector3.UP*0.02
				if (d.velocity as Vector3).length()>2.0:
					d.velocity=Vector3(d.velocity.x*0.3,-d.velocity.y*0.25,d.velocity.z*0.3)
					d.spin*=0.4
				else:
					d.rest=true
					var yaw:=randf()*TAU
					var sc:=node.global_basis.get_scale()
					node.global_basis=(Basis(Vector3.UP,yaw)*Basis(Vector3.FORWARD,PI*0.5)).scaled_local(sc)
		if d.age>25.0: node.queue_free()
	_drops=_drops.filter(func(d): return d.age<=25.0)

func _update_shells(dt: float) -> void:
	for shell in _shells:
		shell.age+=dt
		shell.velocity.y-=9.8*dt
		var node: MeshInstance3D=shell.node
		node.global_position+=shell.velocity*dt
		node.rotate_object_local((shell.spin as Vector3).normalized(),(shell.spin as Vector3).length()*dt)
		if shell.age>0.9: node.queue_free()
	_shells=_shells.filter(func(shell): return shell.age<=0.9)

func inspect_point() -> Vector3:
	# Skutečný střed zásobníku (u dvojky zadní konec hlavní s náboji), ve světových souřadnicích.
	var holder:=full if _remote or avatar.first_mesh.layers==0 else first
	var part:=_part(holder,"Barrel" if _gi().reload=="break" else "Magazine")
	if part==null: return holder.global_transform*(_gi().mag_hand as Vector3)
	var box:=AABB()
	var first_box:=true
	var inv:=part.global_transform.affine_inverse()
	for m in part.find_children("*","MeshInstance3D",true,false):
		var mi: MeshInstance3D=m
		var a: AABB=(inv*mi.global_transform)*mi.get_aabb()
		box=a if first_box else box.merge(a)
		first_box=false
	if first_box: return part.global_position
	var local:=box.get_center()
	if _gi().reload=="break": local.z=box.end.z-0.03       # komory jsou u pantu, ne u ústí
	return part.global_transform*local

func _reload_kick(step: int, kind: String) -> void:
	# Fyzické „cvaknutí“ v přebíjení: vytažení, zasunutí zásobníku a natažení závěru zbraní trhne.
	match kind:
		"mag", "pistol":
			if step==1: impulse(Vector3(0,-0.35,0),Vector3(-0.6,0,0.4))       # zásobník ven
			elif step==2: impulse(Vector3(0,0.55,0),Vector3(0.9,0,-0.3))      # zásobník dovnitř (úder zespodu)
			elif step==3: impulse(Vector3(0,0,0.6),Vector3(0.4,0.3,0.6))      # natažení závěru
		"break":
			if step==1: impulse(Vector3(0,-0.4,0),Vector3(-0.8,0,0))
			elif step==2 or step==3: impulse(Vector3(0,-0.2,0),Vector3(-0.3,0,0.2))
			elif step==4: impulse(Vector3(0,0.6,0.2),Vector3(1.4,0,0))         # zaklapnutí hlavní

func cancel_reload() -> void:
	reload_left=0.0
	_reload_step=0
	_mag_dropped=false
	for sound in _sounds.values(): sound.stop()

func begin_reload(empty: bool=true) -> void:
	reload_empty=empty or _gi().reload=="break"
	reload_time=float(_gi().reload_time)*(1.0 if reload_empty else 0.84)*reload_mul
	_rpitch=1.0/maxf(reload_mul,0.3)
	reload_left=reload_time
	_reload_step=0
	if not reload_empty and _sounds.has("in"):
		_sounds["in"].stream=load("res://audio/ak_mag_in.wav")
	# Zbraně s nahraným celým přebíjením ho přehrají najednou místo jednotlivých cvaků.
	if _full_reload and reload_empty and is_inside_tree():
		var sound: AudioStreamPlayer3D=_sounds.get("in")
		if sound:
			sound.stream=_full_reload
			sound.pitch_scale=_rpitch
			sound.play()

## O kolik se oko při míření odtáhne od mířidel (dlouhá pažba IŽ-54 má pravou ruku u obličeje).
func ads_pull() -> float:
	return float(_gi().get("ads_pull",ADS_PULL))

static func _key(phase: float, keys: Array) -> Variant:
	# Klíčové snímky [čas, hodnota] s měkkým přechodem.
	if phase<=keys[0][0]: return keys[0][1]
	for i in range(1,keys.size()):
		if phase<=keys[i][0]:
			var span:=float(keys[i][0])-float(keys[i-1][0])
			var u: float=(phase-float(keys[i-1][0]))/span
			if keys[i][1] is Vector3:
				# Plynulá rychlost mezi body dráhy ruky; opakované body jsou záměrné zastavení v úchopu.
				var a: Vector3=keys[i-1][1]
				var b: Vector3=keys[i][1]
				var va:=Vector3.ZERO
				var vb:=Vector3.ZERO
				if i>1 and not a.is_equal_approx(keys[i-2][1]) and not a.is_equal_approx(b):
					va=((b-keys[i-2][1])/(float(keys[i][0])-float(keys[i-2][0]))*span).limit_length(a.distance_to(b)*1.5)
				if i+1<keys.size() and not b.is_equal_approx(keys[i+1][1]) and not a.is_equal_approx(b):
					vb=((keys[i+1][1]-a)/(float(keys[i+1][0])-float(keys[i-1][0]))*span).limit_length(a.distance_to(b)*1.5)
				return a*(2*u*u*u-3*u*u+1)+va*(u*u*u-2*u*u+u)+b*(-2*u*u*u+3*u*u)+vb*(u*u*u-u*u)
			var t:=smoothstep(0.0,1.0,u)
			return lerp(keys[i-1][1],keys[i][1],t)
	return keys[keys.size()-1][1]

# Prohlídka zbraně (držené N). Klíče [čas s, hodnota]: posun zbraně (jako r_move: x doprava,
# y nahoru, z k tělu), natočení (x = sklon, záporný zvedá hlaveň; y = stočení; z = náklon bokem)
# a u pistole kolik levá ruka pustí zbraň. Mezi časy "loop" se při dalším držení přehrává dokola,
# "snd" = šustnutí rukavice / ťuknutí o zbraň.
const EXAMINE:={
	# puška: pravý bok (hlaveň vlevo) → levý bok (hlaveň vpravo) → pohled podél hlavně nahoru
	"rifle":{"loop":[0.75,5.3],"snd":[0.3,1.75,3.55],
		"move":[[0.0,Vector3.ZERO],[0.75,Vector3(-0.045,0.14,-0.08)],[1.5,Vector3(-0.05,0.148,-0.088)],
			[2.15,Vector3(-0.08,0.135,0.01)],[2.75,Vector3(-0.16,0.165,0)],[3.4,Vector3(-0.17,0.171,-0.005)],
			[4.0,Vector3(-0.05,0.11,0.02)],[4.6,Vector3(-0.055,0.116,0.015)],[5.3,Vector3(-0.045,0.14,-0.08)]],
		"rot":[[0.0,Vector3.ZERO],[0.75,Vector3(0.12,1.0,0.35)],[1.5,Vector3(0.1,1.08,0.42)],
			[2.15,Vector3(0.22,0.1,0.0)],[2.75,Vector3(0.1,-0.82,-0.3)],[3.4,Vector3(0.13,-0.9,-0.36)],
			[4.0,Vector3(0.62,0.32,0.08)],[4.6,Vector3(0.7,0.38,0.14)],[5.3,Vector3(0.12,1.0,0.35)]],
		"off":[[0.0,0.0]]},
	# dlouhá dvojka: menší natočení, aby pažba nevjela do obličeje
	"long":{"loop":[0.8,5.4],"snd":[0.32,1.8,3.6],
		"move":[[0.0,Vector3.ZERO],[0.8,Vector3(-0.04,0.13,-0.05)],[1.55,Vector3(-0.045,0.136,-0.055)],
			[2.2,Vector3(-0.07,0.12,0.05)],[2.8,Vector3(-0.1,0.13,0.06)],[3.45,Vector3(-0.105,0.135,0.055)],
			[4.05,Vector3(-0.05,0.1,0.03)],[4.7,Vector3(-0.055,0.106,0.025)],[5.4,Vector3(-0.04,0.13,-0.05)]],
		"rot":[[0.0,Vector3.ZERO],[0.8,Vector3(0.1,0.85,0.3)],[1.55,Vector3(0.09,0.92,0.36)],
			[2.2,Vector3(0.2,0.15,0.0)],[2.8,Vector3(0.1,-0.5,-0.25)],[3.45,Vector3(0.12,-0.56,-0.3)],
			[4.05,Vector3(0.55,0.28,0.06)],[4.7,Vector3(0.62,0.33,0.12)],[5.4,Vector3(0.1,0.85,0.3)]],
		"off":[[0.0,0.0]]},
	# pistole: levá ruka pustí, pravý bok → náklon s horní stranou k oku → pohled na hlaveň nahoru
	"pistol":{"loop":[0.7,4.9],"snd":[0.26,1.6,3.2],
		"move":[[0.0,Vector3.ZERO],[0.7,Vector3(-0.065,0.08,-0.01)],[1.4,Vector3(-0.07,0.085,-0.015)],
			[2.0,Vector3(-0.08,0.09,-0.01)],[2.6,Vector3(-0.09,0.095,-0.02)],[3.2,Vector3(-0.09,0.1,-0.025)],
			[3.75,Vector3(-0.07,0.065,0.01)],[4.3,Vector3(-0.075,0.071,0.005)],[4.9,Vector3(-0.065,0.08,-0.01)]],
		"rot":[[0.0,Vector3.ZERO],[0.7,Vector3(0.12,1.0,0.35)],[1.4,Vector3(0.14,1.06,0.4)],
			[2.0,Vector3(0.3,0.6,0.9)],[2.6,Vector3(0.35,0.45,1.25)],[3.2,Vector3(0.38,0.4,1.32)],
			[3.75,Vector3(0.65,0.3,0.1)],[4.3,Vector3(0.72,0.35,0.16)],[4.9,Vector3(0.12,1.0,0.35)]],
		"off":[[0.0,0.0],[0.4,1.0]]},
}

## Prohlídka: [posun, natočení, váha, levá ruka pryč]. Váha i dráha jdou přes tlumenou pružinu,
## takže zbraň má setrvačnost a při puštění N se měkce vrátí.
func _examine(dt: float, reloading: bool) -> Array:
	var want: bool=examine_hold and equipped and not reloading and inspect<0.05 and melee<=0.0 and not ITEM_POSES.has(gun) and GUNS.has(gun)
	_ex_w=move_toward(_ex_w,1.0 if want else 0.0,dt*(2.4 if want else 3.0))
	if _ex_w<=0.0 and not want and _ex_pos.length()<0.001 and _ex_rot.length()<0.002:
		_ex_t=0.0
		_ex_step=0
		_ex_pos=Vector3.ZERO
		_ex_pos_v=Vector3.ZERO
		_ex_rot=Vector3.ZERO
		_ex_rot_v=Vector3.ZERO
		_ex_off=0.0
		return [Vector3.ZERO,Vector3.ZERO,0.0,0.0]
	var kind: String=_gi().reload
	var track: Dictionary=EXAMINE["pistol" if kind=="pistol" else ("long" if kind=="break" else "rifle")]
	var lp: Array=track.loop
	if want:
		_ex_t+=dt
		var snd: Array=track.snd
		if _ex_step<snd.size() and _ex_t>=float(snd[_ex_step]):
			_ex_step+=1
			_examine_sound()
		if _ex_t>float(lp[1]):
			_ex_t=float(lp[0])+fmod(_ex_t-float(lp[0]),float(lp[1])-float(lp[0]))
			_ex_step=0
			while _ex_step<snd.size() and float(snd[_ex_step])<_ex_t: _ex_step+=1
	var w:=smoothstep(0.0,1.0,_ex_w)
	var goal_p: Vector3=(_key(_ex_t,track.move) as Vector3)*w
	var goal_r: Vector3=(_key(_ex_t,track.rot) as Vector3)*w
	if examine_override.size()==2:     # ladění póz (tools/t_examine.gd)
		goal_p=examine_override[0]*w
		goal_r=examine_override[1]*w
	var off: float=float(_key(_ex_t,track.off))*w
	# pružina: zbraň dojíždí za klíči s váhou (malý překmit), dílčí kroky kvůli stabilitě
	var sub:=maxi(1,ceili(dt/0.006))
	var h:=dt/sub
	for i in sub:
		_ex_pos_v+=((goal_p-_ex_pos)*196.0-_ex_pos_v*2.0*0.72*14.0)*h
		_ex_pos+=_ex_pos_v*h
		_ex_rot_v+=((goal_r-_ex_rot)*169.0-_ex_rot_v*2.0*0.7*13.0)*h
		_ex_rot+=_ex_rot_v*h
	_ex_off=move_toward(_ex_off,off,dt*3.0)
	return [_ex_pos,_ex_rot,w,smoothstep(0.0,1.0,_ex_off)]

func _examine_sound() -> void:
	var sound: AudioStreamPlayer3D=_sounds.get("handle")
	if sound==null or not is_inside_tree(): return
	var file:="res://audio/gun_handle_%d.wav"%(randi()%3+1)
	if ResourceLoader.exists(file): sound.stream=load(file)
	sound.pitch_scale=randf_range(0.92,1.08)*(1.12 if _gi().reload=="pistol" else 1.0)
	sound.play()

func pose(dt: float, swimming: bool) -> void:
	_time+=dt
	_springs(dt)
	recoil=_rk_p.z
	_kick=_rk_r
	_draw=maxf(0.0,_draw-dt/0.5)
	# Pohyb: při úkroku se zbraň nakloní na stranu, při rozběhu se opozdí dozadu.
	var mass: float=MASS.get(gun,1.0)
	var k_sw:=sway_scale
	# Úkrok: náklon do strany pružinou – při zastavení se zbraň trochu přehoupne zpět.
	var tilt_goal:=clampf(-local_velocity.x*0.042,-0.2,0.2)*k_sw
	_tilt_v+=((tilt_goal-_move_tilt)*95.0/mass-_tilt_v*2.0*0.65*9.7/sqrt(mass))*dt
	_move_tilt+=_tilt_v*dt
	_move_push=lerpf(_move_push,clampf(local_velocity.z*0.006,-0.03,0.03),1.0-exp(-6.0*dt))
	# Zrychlení, brzdění a změna směru: omezená setrvačnost společná oběma úchopům.
	var acceleration:=(local_velocity-_velocity_smooth)*7.0
	_velocity_smooth=_velocity_smooth.lerp(local_velocity,1.0-exp(-7.0*dt))
	var inertia_target:=Vector3(-acceleration.x, -acceleration.y*0.2, acceleration.z)*0.0018
	# Setrvačnost jako tlumená pružina: při rozjezdu se zbraň opozdí, při zastavení
	# mírně „dojede“ dopředu a měkce se usadí – bez zlomů v rychlosti.
	var in_goal:=inertia_target.limit_length(0.024)
	var w_in:=11.0
	_inertia_v+=((in_goal-_inertia_offset)*w_in*w_in-_inertia_v*2.0*0.72*w_in)*dt
	_inertia_offset+=_inertia_v*dt
	# Přechod do míření: krátké pootočení a „usazení“ k oku.
	var aim_rate:=(aim-_aim_last)/maxf(dt,0.001)
	_aim_last=aim
	_aim_roll=lerpf(_aim_roll,clampf(aim_rate*0.05,-0.12,0.12),1.0-exp(-12.0*dt))
	_flash_time=maxf(0,_flash_time-dt)
	if _flash_time>0.0:
		var fk:=_flash_time/FLASH_TIME          # 1 → 0: záblesk se rozšíří a zhasne
		for flash in _flashes:
			for q in flash.find_children("*","MeshInstance3D",true,false):
				(q as MeshInstance3D).transparency=1.0-pow(fk,0.7)
	if _light: _light.light_energy=move_toward(_light.light_energy,0.0,dt*45.0)
	_update_shells(dt)
	_update_drops(dt)
	_update_pap(dt)
	var reloading:=reload_left>0
	reload_left=maxf(0,reload_left-dt)
	weight=move_toward(weight,1.0 if equipped and not swimming else 0.0,dt*5.5)
	full.visible=weight>0.01 and holster<0.985
	first.visible=weight>0.01 and holster<0.985
	for flash in _flashes: flash.visible=_flash_time>0 and equipped and not swimming
	_follow_extra_fingers(avatar.skeleton)
	if weight<0.001: return
	var sk: Skeleton3D=avatar.skeleton
	# Držení musí mít vlastní pózu paží. Roll a posuny z běžeckého klipu by se
	# jinak přičítaly k IK a vytáčely rukáv před vlastní kameru.
	for bone in [7,8,9,10,19,20,21,22]:
		var rest:=sk.get_bone_rest(bone)
		sk.set_bone_pose_rotation(bone,sk.get_bone_pose_rotation(bone).slerp(rest.basis.get_rotation_quaternion(),weight))
		sk.set_bone_pose_position(bone,sk.get_bone_pose_position(bone).lerp(rest.origin,weight))
	var head_raw:=bone_pose(5).origin
	# Hlava z animace (předklon při chůzi, napřímení při zastavení) jde do kamery i do zbraně
	# přes stejnou kriticky tlumenou pružinu: obě se pohnou spolu a přechod chůze → stání
	# plynule dojede místo trhnutí.
	if _head_smooth==Vector3.ZERO:
		_head_smooth=head_raw
	else:
		var w_h:=24.0-20.0*inspect
		_head_v+=((head_raw-_head_smooth)*w_h*w_h-_head_v*2.0*w_h)*dt
		_head_smooth+=_head_v*dt
	# Při míření a drženém R nesleduje pohupování hlavy z animace chůze ani zbraň, ani kamera:
	# obě berou jen pomalý průměr polohy hlavy (kamera přes head_offset), takže zbraň drží v záběru na místě.
	_head_slow=head_raw if _head_slow==Vector3.ZERO else _head_slow.lerp(head_raw,1.0-exp(-1.6*dt))
	var still:=steady*(1.0-steady_keep)
	var head:=_head_smooth.lerp(_head_slow,still)
	# Klidná hlava (míření) se nesmí od skutečné vzdálit víc než pár cm: jinak na zbraň
	# po zastavení z běhu nedosáhnou ruce, korekce dosahu ji přitáhne k oku a kamera
	# se pak dívá „skrz“ AK.
	if still>0.0: head=head_raw+(head-head_raw).limit_length(lerpf(0.5,0.04,still))
	head_offset=head-head_raw            # kamera bere stejnou (vyhlazenou) hlavu jako zbraň
	# Setrvačnost zbraně: při otáčení pohledu se zpožďuje a naklání.
	var yaw_now: float=avatar.rotation.y
	var turn:=Vector2(wrapf(yaw_now-_last_yaw,-PI,PI),pitch-_last_pitch)/maxf(dt,0.001)
	_last_yaw=yaw_now
	_last_pitch=pitch
	var hip:=1.0-aim*0.8
	# Rozhlížení: zbraň se za pohledem opožďuje (víc těžké zbraně) a po zastavení se s houpnutím usadí.
	var sway_goal:=(turn*0.019*mass).limit_length(0.075)*hip*k_sw
	var w_sw:=13.0/sqrt(mass)
	var sub:=maxi(1,ceili(dt/0.008))
	for i in sub:
		_sway_v+=((sway_goal-_sway)*w_sw*w_sw-_sway_v*2.0*0.6*w_sw)*(dt/sub)
		_sway+=_sway_v*(dt/sub)
	# Reload: náklon zbraně, vytažení zásobníku, nový zásobník, natažení závěru.
	var phase:=1.0-reload_left/reload_time if reloading else 0.0
	var kind: String=_gi().reload
	var barrel_angle:=0.0
	var r_roll:=0.0
	var r_pitch:=0.0
	var r_move:=Vector3.ZERO
	var mag_shift:=Vector3.ZERO
	var mag_tilt:=0.0
	var left_blend:=0.0
	var left_reload:=Vector3.ZERO
	var wrist_turn:=0.0
	var insp_relax:=0.0
	var mag_check:=0.0       # kontrola nábojů: levá ruka drží vysunutý zásobník (úchop "mag")
	if reloading and kind=="mag":
		r_roll=_key(phase,[[0.0,0.0],[0.1,0.42],[0.66,0.42],[0.74,-0.3],[0.9,-0.3],[1.0,0.0]])
		r_pitch=_key(phase,[[0.0,0.0],[0.1,0.2],[0.6,0.22],[0.66,0.27],[0.72,0.16],[0.84,0.1],[0.87,0.16],[1.0,0.0]])
		r_move=_key(phase,[[0.0,Vector3.ZERO],[0.1,Vector3(-0.07,0.12,0.02)],[0.62,Vector3(-0.07,0.12,0.02)],[0.66,Vector3(-0.07,0.135,0.02)],[0.75,Vector3(-0.04,0.07,0.07)],[0.84,Vector3(-0.04,0.07,0.06)],[0.87,Vector3(-0.04,0.07,0.035)],[0.92,Vector3(-0.04,0.07,0.07)],[1.0,Vector3.ZERO]])
		mag_shift=_key(phase,[[0.0,Vector3.ZERO],[0.13,Vector3.ZERO],[0.2,Vector3(0,-0.07,-0.05)],[0.3,Vector3(0,-0.55,-0.02)],[0.44,Vector3(0,-0.6,0.0)],[0.58,Vector3(0,-0.1,-0.05)],[0.64,Vector3(0,-0.03,-0.015)],[0.67,Vector3.ZERO],[1.0,Vector3.ZERO]])
		mag_tilt=_key(phase,[[0.0,0.0],[0.13,0.0],[0.2,-0.35],[0.44,-0.1],[0.58,-0.3],[0.67,0.0],[1.0,0.0]])
		left_blend=_key(phase,[[0.0,0.0],[0.11,1.0],[0.92,1.0],[1.0,0.0]])
		var mag_grip: Vector3=_gi().mag_hand
		left_reload=_key(phase,[[0.0,mag_grip],[0.69,mag_grip],[0.78,handle+Vector3(0,0,-0.02)],[0.82,handle+Vector3(0,0,-0.02)],[0.86,handle+Vector3(0,0,0.07)],[0.9,handle],[1.0,handle]])
		if phase<0.69: left_reload+=mag_shift
		wrist_turn=_key(phase,[[0.0,0.0],[0.12,0.5],[0.66,0.5],[0.78,0.08],[0.9,0.08],[1.0,0.0]])
		for step in [[0.14,"out"],[0.655,"in"],[0.83,"bolt"]]:
			if _reload_step<3 and step==[[0.14,"out"],[0.655,"in"],[0.83,"bolt"]][_reload_step] and phase>=float(step[0]):
				_reload_step+=1
				if _reload_step==3 and not reload_empty: continue
				_reload_kick(_reload_step,kind)
				var sound: AudioStreamPlayer3D=_sounds.get(step[1])
				if sound and sound.stream and is_inside_tree() and (_full_reload==null or not reload_empty):
					sound.pitch_scale=sqrt(_rpitch)
					sound.play()
	elif reloading and kind=="pistol":
		# Pistole: zásobník vypadne z rukojeti, levá ruka zasune nový a natáhne závěr.
		r_roll=_key(phase,[[0.0,0.0],[0.12,0.5],[0.6,0.5],[0.7,-0.15],[0.9,-0.15],[1.0,0.0]])
		r_pitch=_key(phase,[[0.0,0.0],[0.12,0.25],[0.6,0.25],[0.75,0.15],[0.85,0.2],[1.0,0.0]])
		r_move=_key(phase,[[0.0,Vector3.ZERO],[0.12,Vector3(-0.06,0.1,0.16)],[0.4,Vector3(-0.06,0.1,0.16)],[0.5,Vector3(-0.11,0.15,0.17)],[0.64,Vector3(-0.11,0.15,0.17)],[0.75,Vector3(-0.06,0.12,0.16)],[0.85,Vector3(-0.06,0.1,0.16)],[1.0,Vector3.ZERO]])
		mag_shift=_key(phase,[[0.0,Vector3.ZERO],[0.12,Vector3.ZERO],[0.2,Vector3(0,-0.12,0.01)],[0.32,Vector3(0,-0.6,0.0)],[0.42,Vector3(0,-0.55,0.0)],[0.55,Vector3(0,-0.1,0.01)],[0.62,Vector3.ZERO],[1.0,Vector3.ZERO]])
		left_blend=_key(phase,[[0.0,0.0],[0.1,1.0],[0.9,1.0],[1.0,0.0]])
		var hand: Vector3=_gi().mag_hand
		left_reload=_key(phase,[[0.0,hand+Vector3(-0.02,-0.05,0)],[0.3,hand+Vector3(-0.08,-0.25,0.05)],[0.45,hand+Vector3(0,-0.45,0)],[0.6,hand],[0.72,hand+Vector3(0.0,0.03,-0.04)],[0.8,hand+Vector3(0,0.03,0.03)],[0.88,hand],[1.0,hand]])
		if phase>=0.42 and phase<0.62: left_reload+=mag_shift
		wrist_turn=_key(phase,[[0.0,0.0],[0.12,0.4],[0.61,0.4],[0.76,-0.45],[0.87,-0.45],[1.0,0.0]])
		for step in [[0.14,"out"],[0.6,"in"],[0.76,"bolt"]]:
			if _reload_step<3 and step==[[0.14,"out"],[0.6,"in"],[0.76,"bolt"]][_reload_step] and phase>=float(step[0]):
				_reload_step+=1
				if _reload_step==3 and not reload_empty: continue
				_reload_kick(_reload_step,kind)
				var sound: AudioStreamPlayer3D=_sounds.get(step[1])
				if sound and sound.stream and is_inside_tree() and (_full_reload==null or not reload_empty):
					sound.pitch_scale=1.25*sqrt(_rpitch)
					sound.play()
	elif reloading and kind=="break":
		# Dvojka: zlomit hlavně dolů, vypadnou nábojnice, vložit dva nové, zaklapnout.
		barrel_angle=_key(phase,[[0.0,0.0],[0.08,0.0],[0.18,0.8],[0.78,0.8],[0.86,0.0],[1.0,0.0]])
		r_roll=_key(phase,[[0.0,0.0],[0.12,0.25],[0.8,0.25],[0.9,0.0]])
		r_pitch=_key(phase,[[0.0,0.0],[0.12,-0.1],[0.8,-0.1],[0.86,0.08],[1.0,0.0]])
		r_move=_key(phase,[[0.0,Vector3.ZERO],[0.12,Vector3(-0.12,0.13,0.12)],[0.8,Vector3(-0.12,0.13,0.12)],[1.0,Vector3.ZERO]])
		left_blend=_key(phase,[[0.0,0.0],[0.22,0.0],[0.3,1.0],[0.72,1.0],[0.8,0.0]])
		var breech: Vector3=_gi().mag_hand
		left_reload=_key(phase,[[0.0,breech],[0.3,breech+Vector3(-0.12,-0.25,0.1)],[0.42,breech+Vector3(-0.02,0.02,0)],[0.52,breech],[0.6,breech+Vector3(-0.12,-0.25,0.1)],[0.68,breech+Vector3(0.02,0.02,0)],[0.72,breech]])
		for step in [[0.17,"out"],[0.45,"in"],[0.66,"in"],[0.85,"bolt"]]:
			if _reload_step<4 and step==[[0.17,"out"],[0.45,"in"],[0.66,"in"],[0.85,"bolt"]][_reload_step] and phase>=float(step[0]):
				_reload_step+=1
				_reload_kick(_reload_step,kind)
				var sound: AudioStreamPlayer3D=_sounds.get(step[1])
				if sound and sound.stream and is_inside_tree() and _full_reload==null:
					sound.pitch_scale=0.8*sqrt(_rpitch)
					sound.play()
				if _reload_step==1 and is_inside_tree():
					for shell in 2: _eject_shell(Vector3(-0.01+shell*0.02,0.06,-0.1))
	if reloading and not reload_empty:
		# Náboj zůstává v komoře: po zasunutí zásobníku ruka rovnou zpět na předpažbí.
		var pistol:=kind=="pistol"
		var grip: Vector3=_gi().mag_hand
		r_roll=_key(phase,[[0.0,0.0],[0.12,0.35 if pistol else 0.42],[0.67,0.35 if pistol else 0.42],[1.0,0.0]])
		r_pitch=_key(phase,[[0.0,0.0],[0.12,0.22],[0.67,0.22],[1.0,0.0]])
		var tm:=Vector3(-0.06,0.1,0.16) if pistol else Vector3(-0.07,0.12,0.02)
		r_move=_key(phase,[[0.0,Vector3.ZERO],[0.12,tm],[0.67,tm],[1.0,Vector3.ZERO]])
		left_blend=_key(phase,[[0.0,0.0],[0.11,1.0],[0.69,1.0],[0.96,0.0],[1.0,0.0]])
		if phase>=0.67: left_reload=grip
		wrist_turn=_key(phase,[[0.0,0.0],[0.12,0.45],[0.66,0.45],[0.95,0.0],[1.0,0.0]])
	if not reloading and inspect>0.001:
		# Kontrola nábojů: zásobník ven a natočit k oku, u dvojky zlomit hlavně.
		var k:=smoothstep(0.0,1.0,inspect)
		if kind=="break":
			# levá ruka drží předpažbí a hlavně jen sklopí; závěr se zvedne k oku (paže zůstane pod zbraní)
			barrel_angle=0.6*k
			r_pitch=0.25*k
			r_roll=0.2*k
			r_move=Vector3(0.04,0.08,0.0)*k
		else:
			# Zbraň se nakloní bokem k oku a zásobník povyjede ven.
			var pistol: bool=kind=="pistol"
			r_roll=(0.65 if pistol else 0.95)*k
			r_pitch=0.12*k
			r_move=(Vector3(-0.03,0.06,0.03) if pistol else Vector3(-0.08,0.14,0.0))*k
			mag_shift=Vector3(0,-0.07 if not pistol else -0.05,0)*k
			if pistol:
				# pistole: levá ruka pustí a uvolněně klesne (jako při prohlídce), zásobník jen povyjede
				insp_relax=k
			else:
				left_blend=k
				left_reload=(_gi().mag_hand as Vector3)+mag_shift
				mag_check=k
	# Prohlídka zbraně (držené N): zvednout, ukázat jeden bok, přetočit na druhý, hlaveň nahoru.
	var ex: Array=_examine(dt,reloading)
	var ex_move: Vector3=ex[0]
	var ex_rot: Vector3=ex[1]
	var ex_w: float=ex[2]
	var ex_off: float=maxf(ex[3],insp_relax)
	r_move+=ex_move
	r_pitch+=ex_rot.x
	r_roll+=ex_rot.z
	var speed_now:=minf(avatar.blend_speed,4.0)
	# Sprint: zbraň šikmo přes tělo hlavní vzhůru, výraznější houpání. Úder pažbou: krátký výpad vpřed.
	var run:=sprint*(1.0-aim)*(0.0 if reloading else 1.0)
	# Úder zbraní: krátký nápřah, prudký výpad doleva vpřed s natočením na bok, výdrž, návrat.
	# Pistole: úder rukojetí shora dolů (hlaveň se sklopí), puška: výpad bokem zbraně.
	var mel_pistol: bool=_gi().reload=="pistol"
	var mel_move:=Vector3.ZERO
	var mel_rot:=Vector3.ZERO
	if melee>0.0:
		if mel_pistol:
			mel_move=_key(melee,[[0.0,Vector3.ZERO],[0.12,Vector3(0.0,0.035,-0.06)],[0.27,Vector3(0.025,0.04,0.17)],[0.42,Vector3(0.02,0.035,0.15)],[1.0,Vector3.ZERO]])
			mel_rot=_key(melee,[[0.0,Vector3.ZERO],[0.12,Vector3(0.35,-0.05,0.12)],[0.27,Vector3(-0.28,0.15,-0.35)],[0.42,Vector3(-0.25,0.13,-0.3)],[1.0,Vector3.ZERO]])
		else:
			mel_move=_key(melee,[[0.0,Vector3.ZERO],[0.1,Vector3(-0.02,-0.03,-0.07)],[0.25,Vector3(0.05,0.07,0.22)],[0.4,Vector3(0.045,0.065,0.19)],[1.0,Vector3.ZERO]])
			mel_rot=_key(melee,[[0.0,Vector3.ZERO],[0.1,Vector3(0.06,-0.15,0.25)],[0.25,Vector3(-0.25,0.3,-0.55)],[0.4,Vector3(-0.22,0.27,-0.5)],[1.0,Vector3.ZERO]])
	var calm:=1.0-maxf(maxf(inspect*0.85,ex_w*0.8),still)        # při míření a drženém R se zbraň houpe jen tolik, kolik dovolí nastavení
	# Houpání v rytmu kroků: osmička do stran, propad a kývnutí hlavně při došlapu.
	# Jde ve stejném rytmu jako kamera, jen se o kousek opožďuje – zbraň má váhu.
	var gait_goal:=clampf(speed_now/2.2,0.0,1.6)*(1.0-aim*0.85)*(1.0+run*0.9)*calm*k_sw
	# Síla houpání: kriticky tlumená pružina (plynulý náběh i doběh, žádné škubnutí).
	var w_g:=6.5 if gait_goal>_gait else 7.5
	_gait_v+=((gait_goal-_gait)*w_g*w_g-_gait_v*2.0*w_g)*dt
	_gait=maxf(0.0,_gait+_gait_v*dt)
	var gait:=_gait
	var sp:=step_phase-0.45*mass
	var s1:=sin(sp)
	var fall:=s1*s1                          # 1 = došlap; sin² je hladké (|sin| mělo zlom nahoře)
	var dip:=0.6*fall+0.4*fall*fall          # došlap ostřejší než zvednutí, pořád hladce
	var bob:=Vector3(cos(sp)*0.013,(0.5-dip)*0.017,fall*0.005)*gait
	var bob_roll:=cos(sp)*0.032*gait
	var bob_yaw:=cos(sp)*0.022*gait
	var bob_pitch:=(dip-0.5)*0.03*gait
	# Došlap: krátké „ťuknutí“ při dopadu chodidla a náklon k noze, která došlápla
	# (hladké houpání nahoře ho samo neumí – skutečný krok má na patě malý náraz).
	var foot:=floori((sp-PI*0.5)/PI)
	if foot!=_foot_idx:
		var forward_step: bool=foot>_foot_idx
		_foot_idx=foot
		var g:=clampf(gait,0.0,1.4)*(1.0-aim*0.75)*calm*(1.0+run*0.6)
		if forward_step and g>0.08:
			var side:=1.0 if foot%2==0 else -1.0
			impulse(Vector3(0.0,-0.085,0.02)*g,Vector3(-0.16,0.03*side,0.11*side)*g)
	# Ve vzduchu: při výskoku zbraň zaostane dolů a hlaveň klesne, při pádu „vyplave“ nahoru.
	var air_goal:=Vector2(clampf(-air_vy*0.0035,-0.022,0.03),clampf(-air_vy*0.012,-0.09,0.1))*calm*k_sw
	var w_air:=9.0
	_air_v+=((air_goal-_air)*w_air*w_air-_air_v*2.0*0.7*w_air)*dt
	_air+=_air_v*dt
	# Zbraň u zdi: stáhne se k tělu a hlaveň se zvedne, ať neprojíždí stěnou.
	var w_ob:=14.0
	_ob_v+=((obstruct-_ob)*w_ob*w_ob-_ob_v*2.0*0.85*w_ob)*dt
	_ob=clampf(_ob+_ob_v*dt,-0.05,2.1)
	var obk:=smoothstep(0.0,1.0,clampf(_ob,0.0,1.0))
	var ob_more:=maxf(_ob-1.0,0.0)          # úplně u zdi: zbraň se odkloní ven a zvedne
	var ob_long:=clampf((absf(float(_gi().muzzle.z))-0.6)/0.3,0.0,1.0)   # dlouhá hlaveň (IŽ-54) potřebuje víc
	# Dech: v klidu pomalá osmička; po sprintu se rozdýchává víc a rychleji.
	_breath_boost=move_toward(_breath_boost,1.0,dt*0.5) if run>0.5 else move_toward(_breath_boost,0.0,dt*0.45)
	var bb:=_breath_boost*_breath_boost
	var br_t:=_time*(1.0+bb*0.9)
	var idle:=(1.0-aim*0.7)*(1.0-clampf(gait,0.0,1.0)*0.6)*k_sw
	var breathe:=Vector3(sin(br_t*0.8)*0.003,sin(br_t*1.6)*0.0026+sin(br_t*0.37)*0.0016,0)*(1.0+bb*0.8)*idle
	var breathe_pitch:=sin(br_t*1.6+0.6)*0.006*(1.0+bb*0.9)*idle
	# Občas ruce zbraň nepatrně přehmátnou a pomalu se do nové polohy přesunou.
	_idle_next-=dt
	if _idle_next<=0.0:
		_idle_next=randf_range(3.5,8.0)
		_idle_goal=Vector3(randf_range(-0.004,0.004),randf_range(-0.003,0.002),randf_range(-0.014,0.014))
	_idle_drift=_idle_drift.lerp(_idle_goal*idle,1.0-exp(-1.4*dt))
	breathe+=Vector3(_idle_drift.x,_idle_drift.y,0)
	# Přikrčení / vstání: zbraň se propadne a srovná.
	if crouch_now!=_was_crouch:
		_was_crouch=crouch_now
		impulse(Vector3(0,-0.32 if crouch_now else 0.22,0)*k_sw,Vector3(-0.5 if crouch_now else 0.35,0,0.35*(1.0 if crouch_now else -1.0))*k_sw)
	# Zbraň se naklání kolem oka kamery: při pohledu nahoru i dolů drží v záběru stejné místo
	# a nezajíždí hráči do obličeje.
	var pivot:=Vector3(0,head.y+0.08,head.z+0.06)
	# Hloubka se počítá od hlavy (kamery): když se postava při chůzi předkloní, zbraň jde s ní a nevjede do obličeje.
	var offset:=Vector3(head.x+lerpf(hip_pose.x,0.0,aim),head.y+lerpf(hip_pose.y,float(_gi().aim_y),aim),lerpf(hip_pose.z,0.25,aim)+(head.z-HEAD_REST_Z))
	offset+=_inertia_offset*calm*(1.0-aim*0.9)+bob+breathe*calm+Vector3(-_sway.x,_sway.y,0)*0.6*calm+Vector3(-r_move.x,r_move.y,r_move.z)
	offset+=Vector3(SPRINT_MOVE.x,SPRINT_MOVE.y,SPRINT_MOVE.z)*run+mel_move
	# zpětný ráz (posun) + pohyb + vytažení zbraně
	offset+=Vector3(_rk_p.x,_rk_p.y,0)+Vector3(0,0,-_move_push*calm)
	offset+=Vector3(0,_air.x,0)+Vector3(0.015,-0.035,-0.15)*obk+Vector3(-0.07,-0.07,-0.03)*ob_more
	var draw_k:=_draw*_draw*(3.0-2.0*_draw)
	var lower:=maxf(draw_k,holster)
	offset+=Vector3(0.08,-0.65,-0.12)*lower
	var tilt:=Basis(Vector3.RIGHT,-pitch-aim*0.015)
	var extra_roll:=_move_tilt*calm*(1.0-aim*0.6)+bob_roll+_aim_roll+0.45*lower+_idle_drift.z
	var extra_pitch:=-0.65*lower+bob_pitch+breathe_pitch+_air.y+0.8*obk+(0.25+0.35*ob_long)*ob_more
	# Těžká hlaveň: při rozjezdu do strany zaostává víc než ruce (vybočí), při brzdění se přehoupne.
	var inertia_yaw:=-_inertia_offset.x*2.6*calm*(1.0-aim*0.85)
	extra_roll+=0.22*obk+0.35*ob_more
	var local:=Basis(Vector3.UP,ex_rot.y+_kick.y+inertia_yaw+0.12*obk-(0.55+0.35*ob_long)*ob_more+bob_yaw+_sway.x*1.2*calm+lerpf(HIP_YAW,0.0,aim)+SPRINT_YAW*run+mel_rot.y)*Basis(Vector3.RIGHT,_kick.x+r_pitch-_sway.y*0.8*calm+SPRINT_PITCH*run+mel_rot.x+extra_pitch)*Basis(Vector3.FORWARD,_kick.z-_sway.x*1.5*calm+r_roll+lerpf(HIP_ROLL,0.0,aim)+SPRINT_ROLL*run+mel_rot.z+extra_roll)
	# Model míří do +Z; záporný úhel kolem X zvedá hlaveň.
	var gun_basis:=tilt*Basis(Vector3.UP,PI)*local
	var position_now:=pivot+tilt*(offset-pivot)+tilt*Vector3(0,0,-recoil)
	full.transform=Transform3D(gun_basis/0.86,position_now)
	first.transform=full.transform
	first.position+=avatar.first_mesh.position
	# Injekce: levá ruka nastaví předloktí, pravá do něj vpíchne jehlu a palcem stlačí píst.
	var item_left:=Vector3.ZERO
	var item_left_basis:=Basis.IDENTITY
	if gun=="pumpkin":
		# Hod dýňovou bombou: nápřah dozadu nad rameno, švih dopředu, pustit, ruka se vrátí prázdná.
		var p:=inject
		var wind: float=_key(p,[[0.0,0.0],[0.3,1.0],[0.4,1.0],[0.5,0.0],[1.0,0.0]]) if p>0.0 else 0.0
		var thrust: float=_key(p,[[0.0,0.0],[0.38,0.0],[0.5,1.0],[0.62,0.8],[1.0,0.0]]) if p>0.0 else 0.0
		var move:=Vector3(-0.13,0.08,-0.24)*wind+Vector3(0.06,0.07,0.3)*thrust
		position_now+=tilt*move
		gun_basis=gun_basis*Basis(Vector3.RIGHT,0.7*wind-0.45*thrust)
		full.transform=Transform3D(gun_basis/0.86,position_now)
		first.transform=full.transform
		first.position+=avatar.first_mesh.position
		for holder in [full,first]:
			var pk: Node=holder.get_node_or_null("pumpkin")
			if pk: pk.visible=p<0.47
		item_left=pivot+tilt*(head+Vector3(0.24,-0.7,0.06)-pivot)
		item_left_basis=tilt*Basis(Vector3.UP,PI)*Basis(Vector3.UP,ARM_YAW)*Basis(Vector3.RIGHT,-PI/2)*Basis(Vector3.UP,PI/2)
	if gun=="syringe":
		var p:=inject
		var present: float=_key(p,[[0.0,0.0],[0.2,1.0],[0.84,1.0],[1.0,0.0]])
		var low:=head+Vector3(0.24,-0.7,0.06)
		var up:=head+Vector3(0.0,-0.12,0.42)
		item_left=pivot+tilt*(low.lerp(up,present)-pivot)
		# Předloktí míří dopředu a ke středu, dlaň nahoru (vnitřní strana paže ke kameře).
		item_left_basis=tilt*Basis(Vector3.UP,PI)*Basis(Vector3.UP,ARM_YAW)*Basis(Vector3.FORWARD,ARM_ROLL)
		item_left_basis=item_left_basis*Basis(Vector3.RIGHT,-PI/2)*Basis(Vector3.UP,PI/2)
		if p>0.0:
			aim_bone(7,8,bone_pose(7).origin+Vector3(0.13,0,0)+tilt*Vector3(0,-0.04,0.13))
			solve_arm(8,9,10,item_left,Vector3(0.6,head.y-0.48,0.15),item_left_basis)
			var elbow:=bone_pose(9).origin
			var wrist:=bone_pose(10).origin
			var spot:=elbow.lerp(wrist,0.55)+tilt*Vector3(0,0.035,0)
			var dir:=(tilt*NEEDLE_DIR).normalized()
			var inj_basis:=Basis.looking_at(dir,tilt*NEEDLE_UP)
			var reach: float=_key(p,[[0.0,0.0],[0.22,0.0],[0.42,1.0],[0.78,1.0],[0.95,0.0],[1.0,0.0]])
			var depth: float=_key(p,[[0.0,0.12],[0.36,0.08],[0.46,-0.012],[0.74,-0.012],[0.84,0.08],[1.0,0.12]])
			var tip: Vector3=_syringe_tip
			var tip_at:=spot-dir*depth
			var pos_inj:=tip_at-(inj_basis/0.86)*tip
			gun_basis=Basis(gun_basis.get_rotation_quaternion().slerp(inj_basis.get_rotation_quaternion(),reach))
			position_now=position_now.lerp(pos_inj,reach)
			full.transform=Transform3D(gun_basis/0.86,position_now)
			first.transform=full.transform
			first.position+=avatar.first_mesh.position
		var push: float=_key(p,[[0.0,0.0],[0.48,0.0],[0.72,1.0],[1.0,1.0]]) if p>0.0 else 0.0
		for holder in [full,first]:
			var syr: Node=holder.get_node_or_null("syringe")
			if syr and syr.has_meta("pusher"):
				var pusher: Node3D=syr.get_meta("pusher")
				pusher.position=syr.get_meta("pusher_rest")+(syr.get_meta("pusher_dir") as Vector3)*push
	# Starý zásobník při přebíjení vypadne na zem; nový přijde zespodu.
	var mag_out:=reloading and (kind=="mag" or kind=="pistol") and phase>=0.2 and phase<0.42
	if mag_out and not _mag_dropped:
		_mag_dropped=true
		_drop_magazine()
	if not reloading: _mag_dropped=false
	for holder in [full,first]:
		_last_mag_shift=mag_shift
		var magazine:=_part(holder,"Magazine")
		if magazine:
			magazine.position=mag_shift
			magazine.rotation.x=mag_tilt
			magazine.visible=not mag_out
		var barrel:=_part(holder,"Barrel")
		if barrel: barrel.rotation.x=-barrel_angle
	var right_target:=full.transform*Vector3(0.025,-0.01,0.02)
	var left_local: Vector3=(_gi().left as Vector3).lerp(left_reload,left_blend)
	var left_target:=full.transform*left_local
	var right_basis:=gun_basis*Basis(Vector3.RIGHT,0.55)*Basis(Vector3.FORWARD,PI)
	var left_basis:=gun_basis*Basis(Vector3.RIGHT,-PI/2)*Basis(Vector3.UP,PI/2)
	left_basis=left_basis*Basis(Vector3.FORWARD,wrist_turn*left_blend)
	# Úchopové body zbraně (AAA úchop): zápěstí spočítané z rozměrů ruky a tvaru zbraně.
	_socket_mode=not ITEM_POSES.has(gun) and grip_solver.has(gun)
	if _socket_mode:
		var rw: Transform3D=grip_solver.wrist(gun,"Right")
		right_target=full.transform*rw.origin
		right_basis=gun_basis*rw.basis
		var lw: Transform3D=_left_support.get(gun,grip_solver.wrist(gun,"Left"))
		# levá ruka drží díl, který se hýbe (předpažbí na sklápěcích hlavních): jde s ním
		var lpart: String=(grip_solver.SOCKETS[gun]["left"] as Dictionary).get("part","")
		if lpart!="":
			var pn:=_part(full,lpart.capitalize())
			var pr: Transform3D=(grip_solver.part_rest.get(gun,{}) as Dictionary).get(lpart,Transform3D())
			if pn: lw=pn.transform*pr.affine_inverse()*lw
		var reload_basis:=left_basis
		var reload_wrist:=full.transform*((_gi().left as Vector3).lerp(left_reload,left_blend))-reload_basis.orthonormalized()*_raw_grip_offset(10)
		if mag_check>0.0 and (grip_solver.SOCKETS[gun] as Dictionary).has("mag"):
			# úchop zásobníku spočítaný stejně jako držení (dlaň na boku, prsty kolem přední hrany),
			# jede se zásobníkem, jak povyjíždí ven
			var mw: Transform3D=grip_solver.wrist(gun,"Left",[],"mag")
			var mn:=_part(full,"Magazine")
			var mr: Transform3D=(grip_solver.part_rest.get(gun,{}) as Dictionary).get("magazine",Transform3D())
			if mn: mw=mn.transform*mr.affine_inverse()*mw
			reload_wrist=full.transform*mw.origin
			reload_basis=gun_basis*mw.basis
		var support_basis:=gun_basis*lw.basis
		# cesta mezi úchopem a zásobníkem / závěrem vede obloukem pod zbraní, ne skrz ni
		var sg: Vector3=lw.origin
		var rg: Vector3=full.transform.affine_inverse()*reload_wrist
		var cg:=(sg+rg)*0.5
		cg.y=minf(sg.y,rg.y)-0.075
		var bt:=clampf(left_blend,0.0,1.0)
		left_target=full.transform*(sg*(1.0-bt)*(1.0-bt)+cg*2.0*bt*(1.0-bt)+rg*bt*bt)
		left_basis=Basis(support_basis.get_rotation_quaternion().slerp(reload_basis.get_rotation_quaternion(),left_blend))
		if ex_off>0.0:
			# prohlídka pistole: levá ruka pustí a uvolněně klesne mimo záběr
			var low:=head+Vector3(0.2,-0.6,0.14)
			var mid:=left_target.lerp(low,0.5)+Vector3(0.06,-0.04,0.0)
			var u:=ex_off
			left_target=left_target*(1.0-u)*(1.0-u)+mid*2.0*u*(1.0-u)+low*u*u
	if ITEM_POSES.has(gun):
		left_target=item_left
		left_basis=item_left_basis
		left_blend=1.0
	# Levé rameno se přirozeně předsune; dosah nesmí řešit natahování kostí.
	aim_bone(7,8,bone_pose(7).origin+Vector3(0.13,0,0)+tilt*CLAV_L_TP)
	aim_bone(19,20,bone_pose(19).origin+Vector3(-0.13,0,0)+tilt*CLAV_R_TP)
	# Při krajním pohledu dolů zbraň lehce přitáhnout do dosahu obou paží.
	# Výpočet je na kopiích cílů; výsledný posun se přenese přes tlumenou pružinu,
	# jinak by každé naklonění trupu v animaci (rozběh, zastavení) zbraní cuklo.
	var want_reach:=Vector3.ZERO
	var rt:=right_target
	var lt:=left_target
	for attempt in 3:
		for arm in [[20,21,22],[8,9,10]]:
			var target: Vector3=rt if arm[0]==20 else lt
			var start:=bone_pose(arm[0]).origin
			var a:=start.distance_to(bone_pose(arm[1]).origin)
			var b:=bone_pose(arm[1]).origin.distance_to(bone_pose(arm[2]).origin)
			var delta:=start+(target-start).normalized()*clampf(start.distance_to(target),absf(a-b)+0.008,a+b-0.008)-target
			# Při přebíjení levá ruka zbraň opouští; nesmí ji táhnout za sebou.
			if arm[0]==8: delta*=1.0-left_blend
			want_reach+=delta
			rt+=delta
			lt+=delta
	if ITEM_POSES.has(gun): want_reach=Vector3.ZERO
	# Krok pružiny omezený: při záseku (dlouhý snímek) by se explicitní pružina rozkmitala do nekonečna.
	var dt_r:=minf(get_process_delta_time(),1.0/30.0)
	var w_r:=22.0
	for sub_r in 2:
		_reach_v+=((want_reach-_reach)*w_r*w_r-_reach_v*2.0*w_r)*dt_r*0.5
		_reach+=_reach_v*dt_r*0.5
	if not _reach.is_finite() or not _reach_v.is_finite():
		_reach=Vector3.ZERO
		_reach_v=Vector3.ZERO
	# Ruce se od úchopu nesmí odtrhnout o víc než ~1 cm.
	var gap:=_reach-want_reach
	if gap.length()>0.012:
		_reach=want_reach+gap.normalized()*0.012
	full.position+=_reach
	first.position+=_reach
	right_target+=_reach
	left_target+=_reach
	solve_arm(20,21,22,right_target,Vector3(-1.2,head.y-0.40,-0.3),right_basis)
	if _socket_mode and left_blend>0.02:
		left_target+=full.transform.basis*_lpush
	solve_arm(8,9,10,left_target,Vector3(0.6,head.y-0.48,0.15),left_basis)
	# díly zbraně tak, jak právě jsou (zásobník venku, hlavně sklopené)
	var part_xf:={}
	for part in ["Magazine","Barrel"]:
		var n:=_part(full,part)
		if n: part_xf[part.to_lower()]=n.transform
	if _socket_mode and left_blend>0.02:
		# Levá ruka při přebíjení / kontrole nesmí projít zbraní: vytlačit ven podél povrchu.
		var to_gun:=full.transform.affine_inverse()
		# Vytlačení si pamatuje (souřadnice zbraně) a jen pomalu povoluje: ruka se o zbraň opře,
		# místo aby každý snímek skákala dovnitř a ven.
		var pushed:=false
		for it in 3:
			var push: Vector3=grip_solver.push_out(gun,"Left",to_gun,part_xf)
			if push.length()<0.0005: break
			pushed=true
			_lpush=(_lpush+push*1.1).limit_length(0.09)
			# od skutečné polohy ruky (když cíl není na dosah, ruka je jinde než cíl)
			left_target=bone_pose(10).origin+full.transform.basis*(push*1.15)
			solve_arm(8,9,10,left_target,Vector3(0.6,head.y-0.48,0.15),left_basis)
		if not pushed: _lpush*=exp(-dt*4.0)
	else:
		_lpush=Vector3.ZERO
	_left_relax=ex_off
	if ex_off>0.0:
		# volná ruka visí v prodloužení předloktí
		var rest_q:=sk.get_bone_rest(10).basis.get_rotation_quaternion()
		sk.set_bone_pose_rotation(10,sk.get_bone_pose_rotation(10).slerp(rest_q,ex_off*0.85))
	right_error=bone_pose(22).origin.distance_to(right_target)*0.86
	left_error=bone_pose(10).origin.distance_to(left_target)*0.86
	_left_grip=left_target
	_right_grip=right_target
	_left_basis=left_basis
	_right_basis=right_basis
	_left_free=left_blend
	_trigger_pull=move_toward(_trigger_pull,0.0,dt*9.0)
	var disc_goal:=1.0 if (reloading or inspect>0.05 or ex_w>0.05 or run>0.35 or lower>0.2 or melee>0.0) else 0.0
	_discipline=move_toward(_discipline,disc_goal,dt*(5.0 if disc_goal>_discipline else 3.5))
	if _socket_mode and _fingers_on_gun(sk,dt,left_blend,part_xf): return
	# Palec a ukazovák (indexy jako u scientisty); prostředníček, prsteníček a malíček mají
	# vlastní kosti (41+) a obepnou rukojeť o něco víc.
	for bone in [11,12,13,15,16,17,23,24,25,27,28,29]+_extra_fingers(sk):
		var rest:=sk.get_bone_rest(bone).basis.get_rotation_quaternion()
		var nm:=sk.get_bone_name(bone)
		var curl:=0.35 if "Thumb" in nm else (0.75 if "Index" in nm else (0.95 if "Pinky" in nm else 0.85))
		if not "Thumb" in nm: curl+=float(sk.get_meta("finger_curl_boost",0.0))
		sk.set_bone_pose_rotation(bone,sk.get_bone_pose_rotation(bone).slerp(rest*Quaternion(Vector3.RIGHT,curl),weight))

## Úchopy upečené offline (tools/bake_grips.gd): poloha rukou na zbrani a ohyby prstů.
## Bez nich se vše dopočítá za běhu při prvním klidném držení zbraně.
const GRIPS_PATH:="res://assets/guns_sdf/grips.res"
func _load_grips() -> void:
	if not ResourceLoader.exists(GRIPS_PATH): return
	var r: Resource=load(GRIPS_PATH)
	if r==null or str(r.get_meta("sig",""))!=grip_solver.signature():
		push_warning("úchopy zbraní: upečená data neodpovídají postavě, počítám za běhu")
		return
	var guns: Dictionary=r.get_meta("guns",{})
	var by_name:=func(side: String, nm: String) -> Dictionary:
		for ch in grip_solver.chains(side):
			if ch.name==nm: return ch
		return {}
	for g in guns:
		var d: Dictionary=guns[g]
		grip_solver._wrist_cache[g+":Right"]=d.wR
		grip_solver._wrist_cache[g+":Left"]=d.wL
		_left_support[g]=d.support
		var rc:={}
		for nm in d.right:
			if nm.begins_with("index_"): rc[nm]=d.right[nm]
			else: rc[nm]=[by_name.call("Right",nm),d.right[nm]]
		rc["index_ch"]=by_name.call("Right","Index")
		_rf_cache[g]=rc
		var lc:=[]
		for nm in d.left: lc.append([by_name.call("Left",nm),d.left[nm]])
		_lf_cache[g]=lc

## Data pro tools/bake_grips.gd (jen pro zbraně, které už mají vše spočítané).
func baked_grip(g: String) -> Dictionary:
	if not (_rf_cache.has(g) and _lf_cache.has(g) and _left_support.has(g)): return {}
	var right:={}
	for k in _rf_cache[g]:
		if k=="index_ch": continue
		right[k]=_rf_cache[g][k] if k.begins_with("index_") else _rf_cache[g][k][1]
	var left:={}
	for e in _lf_cache[g]: left[e[0].name]=e[1]
	return {"wR":grip_solver.wrist(g,"Right"),"wL":grip_solver.wrist(g,"Left"),"support":_left_support[g],"right":right,"left":left}

## Prsty na zbrani: pravá ruka (rukojeť + ukazovák na spoušti / podél pouzdra) a levá (předpažbí,
## při přebíjení zásobník). Výsledky v mezipaměti; počítají se, až ruce drží zbraň v klidu.
func _fingers_on_gun(sk: Skeleton3D, dt: float, left_blend: float, part_xf: Dictionary) -> bool:
	var to_gun:=full.transform.affine_inverse()
	var steady_hold:=weight>0.99 and right_error<0.006 and reload_left<=0.0 and inspect<0.01 and _ex_w<=0.0 and holster<0.01 and _draw<0.01
	if not _rf_cache.has(gun):
		if not steady_hold: return false
		var t0:=Time.get_ticks_usec()
		var hand_xf:=bone_pose(22)
		var res:={}
		var tr: Vector3=grip_solver.SOCKETS[gun].trigger
		for ch in grip_solver.chains("Right"):
			if ch.name=="Index":
				var on: Array=grip_solver.reach(gun,hand_xf,to_gun,ch,tr,part_xf)
				var off: Array=grip_solver.along(gun,hand_xf,to_gun,ch,part_xf)
				res["index_on"]=on
				res["index_off"]=off
				res["index_ch"]=ch
				res["index_path"]=grip_solver.index_path(gun,hand_xf,to_gun,ch,part_xf,on,off)
			else:
				res[ch.name]=[ch,grip_solver.wrap(gun,hand_xf,to_gun,ch,part_xf)]
		_rf_cache[gun]=res
		if _grip_debug!="":
			print("pravé prsty %s: %s" % [gun,res.keys().filter(func(k): return not k.begins_with("index")).map(func(k): return [k,(res[k][1] as Array).map(func(v): return snappedf(v,0.01))])])
			print("  ukazovák na spoušti %s, mimo %s" % [res.index_on.map(func(v): return snappedf(float(v),0.01)),res.index_off.map(func(v): return snappedf(float(v),0.01))])
		if _grip_debug!="":
			print("úchop %s: prsty pravé ruky %.1f ms, ukazovák od spouště %.1f mm" % [gun,(Time.get_ticks_usec()-t0)/1000.0,float(res.index_on[4])*1000.0])
	var rc: Dictionary=_rf_cache[gun]
	var pull:=_trigger_pull*(1.0-_discipline)
	for key in rc:
		if key.begins_with("index_"): continue
		var e: Array=rc[key]
		_set_chain(sk,e[0],e[1],float(e[1][3]) if (e[1] as Array).size()>3 else 0.0,weight)
	var a: Array=rc.index_on
	var b: Array=rc.index_off
	var mix: Array=grip_solver.index_blend(a,b,_discipline,int(rc.get("index_path",0)))
	for j in 3: mix[j]=float(mix[j])+pull*[0.05,0.16,0.14][j]
	_set_chain(sk,rc.index_ch,mix,float(mix[3]),weight)
	# levá ruka: kapsle prstů pravé ruky jsou překážka (pistole oběma rukama)
	if not _left_support.has(gun) and steady_hold:
		_left_support[gun]=grip_solver.wrist(gun,"Left",grip_solver.capsules("Right",to_gun))
	if left_blend<0.02:
		if not _lf_cache.has(gun):
			if not steady_hold or not _left_support.has(gun) or left_error>0.008: return true
			var hand_xf:=bone_pose(10)
			var caps: Array=grip_solver.capsules("Right",to_gun)
			var res:=[]
			for ch in grip_solver.chains("Left"): res.append([ch,grip_solver.wrap(gun,hand_xf,to_gun,ch,part_xf,caps)])
			_lf_cache[gun]=res
			if OS.is_debug_build() and _grip_debug!="":
				print("levé prsty %s: %s" % [gun,res.map(func(e): return [e[0].name,(e[1] as Array).map(func(v): return snappedf(v,0.01))])])
		for e in _lf_cache[gun]: _set_chain(sk,e[0],e[1],float(e[1][3]) if (e[1] as Array).size()>3 else 0.0,weight)
	else:
		# přebíjení: prsty se ovinou kolem toho, co ruka zrovna drží (zásobník, závěr, předpažbí)
		_lf_tick+=1
		if true:
			var t_live:=Time.get_ticks_usec()
			var hand_xf:=bone_pose(10)
			var res:=[]
			for ch in grip_solver.chains("Left"):
				if ch.name=="Thumb":
					# palec: jen doladit z minulé polohy (levné), aby neprošel zásobníkem
					var prev: Array=[]
					for e in (_lf_live.get("res",[]) if _lf_live.get("gun","")==gun else _lf_cache.get(gun,[])):
						if e[0].name=="Thumb": prev=e[1]
					res.append([ch,grip_solver.thumb(gun,hand_xf,to_gun,ch,part_xf,[],prev if prev.size()>=4 else [0.2,0.3,0.3,0.0])])
					continue
				# prst pokračuje z minulého snímku (časová soudržnost, pár vzorků)
				var t0:=0.55
				for e in (_lf_live.get("res",[]) if _lf_live.get("gun","")==gun else []):
					if e[0].name==ch.name and (e[1] as Array).size()>4: t0=float(e[1][4])
				res.append([ch,grip_solver.wrap_live(gun,hand_xf,to_gun,ch,part_xf,t0)])
			_lf_live={"gun":gun,"res":res}
			if _grip_debug=="time": print("živé prsty: %.2f ms" % ((Time.get_ticks_usec()-t_live)/1000.0))
		if _lf_live.get("gun","")==gun:
			for e in _lf_live.res: _set_chain(sk,e[0],e[1],float(e[1][3]) if (e[1] as Array).size()>3 else 0.0,weight)
	if _left_relax>0.0:
		for ch in grip_solver.chains("Left"):
			_set_chain(sk,ch,[0.15,0.15,0.1] if ch.name=="Thumb" else [0.3,0.42,0.28],0.0,weight*_left_relax)
	return true

func _set_chain(sk: Skeleton3D, ch: Dictionary, c: Array, side_angle: float, w: float) -> void:
	for j in 3:
		var bone: int=ch.bones[j]
		var q:=(ch.rest[j] as Transform3D).basis.get_rotation_quaternion()
		if j==0 and side_angle!=0.0: q=q*Quaternion(Vector3.BACK,side_angle)
		q=q*Quaternion(Vector3.RIGHT,float(c[j]))
		sk.set_bone_pose_rotation(bone,sk.get_bone_pose_rotation(bone).slerp(q,w))

var _extra_cache: Array=[]
var _extra_src: Array=[]
func _extra_fingers(sk: Skeleton3D) -> Array:
	if _extra_cache.is_empty() and sk.get_bone_count()>41:
		for i in range(41,sk.get_bone_count()):
			var nm:=sk.get_bone_name(i)
			if "HandMiddle" in nm or "HandRing" in nm or "HandPinky" in nm:
				_extra_cache.append(i)
				var src:=nm.replace("Middle","Index").replace("Ring","Index").replace("Pinky","Index")
				_extra_src.append(sk.find_bone(src))
	return _extra_cache

## Bez zbraně: další prsty kopírují pohyb ukazováku z animace (ruka nevypadá jako lopata).
func _follow_extra_fingers(sk: Skeleton3D) -> void:
	var extra:=_extra_fingers(sk)
	for k in extra.size():
		var src: int=_extra_src[k]
		if src<0: continue
		var delta:=sk.get_bone_rest(src).basis.get_rotation_quaternion().inverse()*sk.get_bone_pose_rotation(src)
		sk.set_bone_pose_rotation(extra[k],sk.get_bone_rest(extra[k]).basis.get_rotation_quaternion()*delta)

func pose_first_person() -> void:
	if avatar.first_mesh.layers==0: return
	var source: Skeleton3D=avatar.skeleton
	var target: Skeleton3D=avatar.first_skeleton
	for bone in source.get_bone_count():
		target.set_bone_pose_position(bone,source.get_bone_pose_position(bone))
		target.set_bone_pose_rotation(bone,source.get_bone_pose_rotation(bone))
		target.set_bone_pose_scale(bone,source.get_bone_pose_scale(bone))
	if weight<0.001: return
	# Vlastní objektiv je před rameny. Paže i AK mají pro tento pohled
	# samostatnou shodnou korekci; plná postava ve 3. osobě se tím nedeformuje.
	var correction:=Vector3(0,0,0.15/0.86*weight)
	first.position+=correction
	_pose_skeleton=target
	var head:=bone_pose(5).origin
	# Při pohledu vzhůru se ve vlastním pohledu paže otáčejí kolem oka spolu se zbraní.
	# Jinak by natažená levá paže procházela těsně před objektivem.
	var eye:=head+Vector3(0,0.08,0.06)+correction
	var lift:=Basis(Vector3.RIGHT,-pitch*weight)
	var swing:=Transform3D(lift,eye-lift*eye)
	for shoulder in [7,19]:
		var moved:=swing*bone_pose(shoulder)
		var local_pose:=bone_pose(target.get_bone_parent(shoulder)).affine_inverse()*moved
		target.set_bone_pose_position(shoulder,local_pose.origin)
		target.set_bone_pose_rotation(shoulder,local_pose.basis.get_rotation_quaternion())
	aim_bone(7,8,bone_pose(7).origin+lift*CLAV_L_FP)
	aim_bone(19,20,bone_pose(19).origin+lift*CLAV_R_FP)
	var right_target:=_right_grip+correction
	var left_target:=_left_grip+correction
	# Vlastní kostra má posunutá ramena. Její dosah se musí vyřešit zvlášť:
	# jinak levá dlaň při chůzi visela i 15 cm za předpažbím.
	for attempt in 4:
		for arm in [[20,21,22],[8,9,10]]:
			var grip: Vector3=right_target if arm[0]==20 else left_target
			var start:=bone_pose(arm[0]).origin
			var reach:=start.distance_to(bone_pose(arm[1]).origin)+bone_pose(arm[1]).origin.distance_to(bone_pose(arm[2]).origin)-0.012
			var delta: Vector3=start+(grip-start).limit_length(reach)-grip
			if aim>0.0 and not delta.is_zero_approx():
				# Přes mířidla se smí zbraň přiblížit jen podél osy pohledu,
				# jinak by oprava dosahu odsunula mířidla stranou od střely.
				var axis:=lift*Vector3.BACK
				var v:=grip-start
				var depth:=v.dot(axis)
				var radius:=sqrt(maxf(0.0,reach*reach-(v-axis*depth).length_squared()))
				delta=delta.lerp(axis*(clampf(depth,-radius,radius)-depth),aim)
			if arm[0]==8: delta*=1.0-_left_free
			first.position+=delta
			right_target+=delta
			left_target+=delta
	solve_arm(20,21,22,right_target,swing*Vector3(-0.7,head.y-0.5,-0.1),_right_basis)
	solve_arm(8,9,10,left_target,swing*Vector3(0.6,head.y-0.5,0.15),_left_basis)
	first_right_error=bone_pose(22).origin.distance_to(right_target-_right_basis.orthonormalized()*grip_offset(22))*0.86
	first_left_error=bone_pose(10).origin.distance_to(left_target-_left_basis.orthonormalized()*grip_offset(10))*0.86
	_pose_skeleton=null

func pose_skeleton() -> Skeleton3D:
	return _pose_skeleton if _pose_skeleton else avatar.skeleton

func bone_pose(bone: int) -> Transform3D:
	var sk: Skeleton3D=pose_skeleton()
	var pose_now:=sk.get_bone_pose(bone)
	var parent:=sk.get_bone_parent(bone)
	return bone_pose(parent)*pose_now if parent>=0 else pose_now

func aim_bone(bone: int, child: int, target: Vector3) -> void:
	var sk: Skeleton3D=pose_skeleton()
	var pose_now:=bone_pose(bone)
	var old_direction: Vector3=(bone_pose(child).origin-pose_now.origin).normalized()
	var new_direction: Vector3=(target-pose_now.origin).normalized()
	if old_direction.is_zero_approx() or new_direction.is_zero_approx(): return
	var arc:=Quaternion.IDENTITY
	if old_direction.dot(new_direction)<-0.9995:
		# Přesně opačný směr: oblouk nemá osu, otočit kolem libovolné kolmice.
		var perp:=old_direction.cross(Vector3.UP)
		if perp.length_squared()<0.0001: perp=old_direction.cross(Vector3.RIGHT)
		arc=Quaternion(perp.normalized(),PI)
	else:
		arc=Quaternion(old_direction,new_direction)
	var corrected:=Basis(arc)*pose_now.basis
	var parent:=sk.get_bone_parent(bone)
	var local_basis: Basis=bone_pose(parent).basis.inverse()*corrected
	var before:=sk.get_bone_pose_rotation(bone)
	sk.set_bone_pose_rotation(bone,before.slerp(local_basis.get_rotation_quaternion().normalized(),weight))

## Úchopy jsou laděné na scientistu. Jiná postava (hazmat: kloub ruky v zápěstí, větší rukavice)
## má střed dlaně jinde vůči kloubu ruky; o ten rozdíl (uložený v kostře) se posune cíl zápěstí,
## aby rukojeť ležela v dlani.
func grip_offset(hand: int) -> Vector3:
	if _socket_mode: return Vector3.ZERO
	return _raw_grip_offset(hand)

func _raw_grip_offset(hand: int) -> Vector3:
	var sk: Skeleton3D=avatar.skeleton
	var key:="grip_offset_Left" if hand==10 else "grip_offset_Right"
	return sk.get_meta(key,Vector3.ZERO)

func solve_arm(upper: int, lower: int, hand: int, target: Vector3, pole: Vector3, hand_basis: Basis) -> void:
	var sk: Skeleton3D=pose_skeleton()
	target-=hand_basis.orthonormalized()*grip_offset(hand)
	var start:=bone_pose(upper).origin
	var elbow:=bone_pose(lower).origin
	var end:=bone_pose(hand).origin
	var a:=start.distance_to(elbow)
	var b:=elbow.distance_to(end)
	var distance_now:=clampf(start.distance_to(target),absf(a-b)+0.001,a+b-0.001)
	var direction: Vector3=(target-start).normalized()
	# Loket se natočí tak, aby předloktí šlo co nejvíc v prodloužení ruky (rovné zápěstí);
	# zadaný pól jen přidává směr (loket dolů / ven) a hlídá, aby nešel nad rameno.
	if not _hand_axis.has(hand):
		var mid:=-1
		for c in sk.get_bone_children(hand):
			if "Middle" in sk.get_bone_name(c): mid=c
		_hand_axis[hand]=sk.get_bone_rest(mid).origin.normalized() if mid>=0 else Vector3.UP
	var hand_dir: Vector3=(hand_basis.orthonormalized()*(_hand_axis[hand] as Vector3)).normalized()
	var straight: Vector3=target-hand_dir*b
	straight.y=minf(straight.y,start.y+0.02)
	# loket před hrudníkem smí, do hrudníku ne: čím víc ke středu těla, tím víc musí být vpředu
	var inward:=clampf(1.0-absf(straight.x)/maxf(absf(start.x),0.01),0.0,1.0)
	straight.z=maxf(straight.z,start.z+0.14*inward)
	pole=pole.lerp(straight,ELBOW_AUTO if _socket_mode else 0.0)
	var side: Vector3=(pole-start)-direction*(pole-start).dot(direction)
	if side.length_squared()<0.0001:
		# Cíl leží v ose pólu (ruka napříč těla): loket ohnout dolů.
		side=Vector3.DOWN-direction*Vector3.DOWN.dot(direction)
	side=side.normalized()
	var along: float=(a*a-b*b+distance_now*distance_now)/(2.0*distance_now)
	var bend:=sqrt(maxf(a*a-along*along,0.0))
	aim_bone(upper,lower,start+direction*along+side*bend)
	aim_bone(lower,hand,target)
	var local_basis: Basis=bone_pose(lower).basis.inverse()*hand_basis
	# Otočení dlaně (pronace/supinace) nese předloktí, ne zápěstí: bez kostí pro zkrut by se
	# celé otočení stočilo v zápěstí a rukáv by se tam „uškrtil“ (useknuté zápěstí).
	var rest_q:=sk.get_bone_rest(hand).basis.get_rotation_quaternion()
	var rel:=rest_q.inverse()*local_basis.get_rotation_quaternion().normalized()
	var tw:=_twist_angle(rel,Vector3.UP)
	if absf(tw)>0.001:
		# U skoro natažené paže (podpěrná ruka) nese část otočení i rameno (rotace pažní kosti),
		# u pokrčené by to vychýlilo loket do strany.
		var e_now:=bone_pose(lower).origin
		var bend_e:=(e_now-start).angle_to(bone_pose(hand).origin-e_now)
		var straight_k:=1.0-clampf(bend_e/deg_to_rad(65.0),0.0,1.0)
		var up_share:=UPPER_TWIST*straight_k
		if up_share>0.01:
			var uq:=sk.get_bone_pose_rotation(upper)
			sk.set_bone_pose_rotation(upper,uq*Quaternion(Vector3.UP,tw*up_share*weight))
			aim_bone(lower,hand,target)
			local_basis=bone_pose(lower).basis.inverse()*hand_basis
			rel=rest_q.inverse()*local_basis.get_rotation_quaternion().normalized()
			tw=_twist_angle(rel,Vector3.UP)
		var fq:=sk.get_bone_pose_rotation(lower)
		sk.set_bone_pose_rotation(lower,fq*Quaternion(Vector3.UP,tw*FOREARM_TWIST*weight))
		local_basis=bone_pose(lower).basis.inverse()*hand_basis
	sk.set_bone_pose_rotation(hand,sk.get_bone_pose_rotation(hand).slerp(local_basis.get_rotation_quaternion().normalized(),weight))

## Úhel natočení rotace q kolem osy (rozklad swing–twist), -PI..PI.
static func _twist_angle(q: Quaternion, axis: Vector3) -> float:
	var p:=Vector3(q.x,q.y,q.z).project(axis)
	var t:=Quaternion(p.x,p.y,p.z,q.w)
	if t.length_squared()<1e-9: return 0.0
	t=t.normalized()
	var ang:=2.0*atan2(Vector3(t.x,t.y,t.z).length(),t.w)
	if Vector3(t.x,t.y,t.z).dot(axis)<0.0: ang=-ang
	return wrapf(ang,-PI,PI)


# --- Vylepšené zbraně (náš Pack-a-Punch): každý stupeň má vlastní barvu kamufláže a víc efektů,
# křest v andělově vodě je vrchol – tyrkysová, záře i jiskry.
const PAP_COLOR:=Color(0.35,1.0,0.92)
# stupeň: [barva žilek, podklad, rychlost, jemné žilky, záře, duha, světlo kolem, jiskry]
const TIER_LOOK:={
	1:[Color(1.0,0.62,0.22),Color(0.07,0.04,0.02),0.55,0.0,0.4,0.0,0.0,false],
	2:[Color(0.72,0.38,1.0),Color(0.04,0.02,0.08),0.8,0.6,0.7,0.4,0.22,false],
	3:[Color(1.0,0.16,0.12),Color(0.08,0.012,0.012),1.15,1.0,1.0,0.6,0.38,true],
	4:[Color(0.35,1.0,0.92),Color(0.015,0.07,0.085),1.0,1.0,1.0,1.0,0.48,true],
}
var _tier_mats:={}
var _pap_fx_light:={}          # světlo → síla podle stupně

func is_pap(name: String) -> bool:
	return int(_pap.get(name,0))>=4

func set_pap(name: String, on: bool) -> void:
	set_look(name,4 if on else 0)

func _tier_mat(t: int) -> ShaderMaterial:
	if _tier_mats.has(t): return _tier_mats[t]
	var look: Array=TIER_LOOK[t]
	var m:=ShaderMaterial.new()
	m.shader=load("res://shaders/baptized.gdshader")
	m.set_shader_parameter("vein_color",look[0])
	m.set_shader_parameter("base_color",look[1])
	m.set_shader_parameter("flow_speed",look[2])
	m.set_shader_parameter("detail",look[3])
	m.set_shader_parameter("halo_amt",look[4])
	m.set_shader_parameter("iri_amt",look[5])
	m.set_shader_parameter("vein_energy",2.6 if t<4 else 3.4)
	_tier_mats[t]=m
	if t==4: _pap_mat=m
	return m

func set_look(name: String, t: int) -> void:
	t=clampi(t,0,4)
	if int(_pap.get(name,0))==t: return
	if t>0: _pap[name]=t
	else: _pap.erase(name)
	var look: Array=TIER_LOOK[t] if t>0 else []
	for holder in [full,first]:
		if holder==null: continue
		var model: Node3D=holder.get_node_or_null(name)
		if model==null: continue
		for m in model.find_children("*","MeshInstance3D",true,false):
			(m as MeshInstance3D).material_overlay=_tier_mat(t) if t>0 else null
		var old:=model.get_node_or_null("PapFx")
		if old:
			model.remove_child(old)
			old.queue_free()
		if t>0 and (float(look[6])>0.0 or bool(look[7])): _make_pap_fx(model,look+[t])
	if t>0: _pap_strength=0.0          # nová kamufláž se rozlije postupně
	if name==gun: _update_flash_tint()

func apply_pap_overlay(root: Node) -> void:
	# Stejná kamufláž pro kopii zbraně mimo ruce (křtitelnice).
	for m in root.find_children("*","MeshInstance3D",true,false):
		(m as MeshInstance3D).material_overlay=_tier_mat(4)

func _make_pap_fx(model: Node3D, look: Array) -> void:
	var col: Color=look[0]
	var layer:=1
	var meshes:=model.find_children("*","MeshInstance3D",true,false)
	if meshes.size()>0: layer=(meshes[0] as MeshInstance3D).layers
	var fx:=Node3D.new()
	fx.name="PapFx"
	model.add_child(fx)
	if fx.is_inside_tree(): fx.global_basis=fx.global_basis.orthonormalized()   # efekty v metrech bez ohledu na měřítko modelu
	var box: AABB=fx.transform.affine_inverse()*Props._bounds_of(model,model) if meshes.size()>0 else AABB(Vector3(-0.05,-0.05,-0.3),Vector3(0.1,0.1,0.6))
	var center:=box.get_center()
	var light:=OmniLight3D.new()
	light.light_color=col
	light.light_energy=0.0
	_pap_fx_light[light]=float(look[6])
	light.omni_range=0.9
	light.omni_attenuation=1.6
	light.shadow_enabled=false
	light.light_specular=0.4
	light.position=center
	fx.add_child(light)
	_pap_lights.append(light)
	if not bool(look[7]): return
	var t: int=look[8] if look.size()>8 else 3
	var angel: bool=t>=4
	# Jiskřičky: stupeň 3 žhavé uhlíky stoupající v turbulenci, stupeň 4 třpytivé hvězdičky.
	var parts:=GPUParticles3D.new()
	parts.amount=16 if angel else 22
	parts.lifetime=1.6 if angel else 0.95
	parts.local_coords=false
	parts.layers=layer
	parts.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parts.position=center
	parts.visibility_aabb=AABB(-box.size-Vector3.ONE*0.5,box.size*2.0+Vector3.ONE)
	var pm:=ParticleProcessMaterial.new()
	pm.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents=box.size*0.45
	pm.direction=Vector3(0,1,0)
	pm.spread=70.0
	pm.initial_velocity_min=0.02 if angel else 0.08
	pm.initial_velocity_max=0.08 if angel else 0.4
	pm.gravity=Vector3(0,0.05 if angel else 0.35,0)
	pm.damping_min=0.5
	pm.damping_max=1.5
	pm.turbulence_enabled=true
	pm.turbulence_noise_strength=0.6 if angel else 1.4
	pm.turbulence_noise_scale=1.2
	pm.turbulence_noise_speed=Vector3(0.0,0.6,0.0)
	pm.turbulence_influence_min=0.05
	pm.turbulence_influence_max=0.25
	pm.scale_min=0.5
	pm.scale_max=1.3
	pm.scale_curve=_pap_curve([Vector2(0,0),Vector2(0.12,1),Vector2(0.5,0.55 if angel else 0.8),Vector2(0.62,1.0 if angel else 0.7),Vector2(1,0)])
	var g:=Gradient.new()
	g.offsets=PackedFloat32Array([0.0,0.3,1.0])
	if angel: g.colors=PackedColorArray([Color(1,1,1,1),Color(col.lerp(Color.WHITE,0.5),0.9),Color(col,0.0)])
	else: g.colors=PackedColorArray([Color(1,0.9,0.75,1),Color(col.lerp(Color(1,0.5,0.2),0.4),1),Color(col*0.6,0.0)])
	var ramp:=GradientTexture1D.new()
	ramp.gradient=g
	pm.color_ramp=ramp
	parts.process_material=pm
	var mat:=StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo=true
	mat.disable_fog=true
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	var quad:=QuadMesh.new()
	if angel:
		mat.billboard_mode=BaseMaterial3D.BILLBOARD_PARTICLES
		mat.albedo_texture=load("res://assets/fx/glint.png")
		mat.albedo_color=Color(2.4,2.4,2.4)
		quad.size=Vector2(0.03,0.03)
	else:
		mat.albedo_texture=load("res://assets/fx/spark.png")
		mat.albedo_color=Color(3.2,1.7,1.1)
		quad.size=Vector2(0.004,0.03)
		parts.transform_align=GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	quad.material=mat
	parts.draw_pass_1=quad
	fx.add_child(parts)
	# Elektrické výboje po povrchu zbraně.
	var arc_mat:=ShaderMaterial.new()
	arc_mat.shader=load("res://shaders/arc.gdshader")
	arc_mat.set_shader_parameter("tint",col)
	arc_mat.set_shader_parameter("energy",1.6 if angel else 2.6)
	var im:=ImmediateMesh.new()
	var mi:=MeshInstance3D.new()
	mi.name="Arcs"
	mi.mesh=im
	mi.material_override=arc_mat
	mi.layers=layer
	mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin=1.0
	fx.add_child(mi)
	# Body na povrchu zbraně (podle plochy trojúhelníků), v souřadnicích efektu.
	var to_fx:=fx.transform.affine_inverse()
	var tris: Array=[]
	var areas: Array=[]
	var total:=0.0
	for m in meshes:
		var mm: MeshInstance3D=m
		if mm.mesh==null: continue
		var xf: Transform3D=to_fx*Props._xf(mm,model)
		var faces:=mm.mesh.get_faces()
		for k in range(0,faces.size(),3):
			var a3: Vector3=xf*faces[k]
			var b3: Vector3=xf*faces[k+1]
			var c3: Vector3=xf*faces[k+2]
			var ar:=(b3-a3).cross(c3-a3).length()*0.5
			if ar<1e-7: continue
			tris.append([a3,b3,c3])
			total+=ar
			areas.append(total)
	var samples:=PackedVector3Array()
	if total>0.0:
		for k in 320:
			var r:=randf()*total
			var idx:=areas.bsearch(r)
			var tri: Array=tris[mini(idx,tris.size()-1)]
			var u:=randf()
			var v:=randf()
			if u+v>1.0:
				u=1.0-u
				v=1.0-v
			samples.append(tri[0]+(tri[1]-tri[0])*u+(tri[2]-tri[0])*v)
	var axis:=Vector3.FORWARD
	if box.size.x>=box.size.y and box.size.x>=box.size.z: axis=Vector3.RIGHT
	elif box.size.y>=box.size.z: axis=Vector3.UP
	_pap_arcs.append({"fx":fx,"mi":mi,"mesh":im,"samples":samples,"center":center,"axis":axis,
		"arcs":[],"rate":(5.0 if angel else 16.0),"len":(0.16 if angel else 0.22),"angel":angel,"light":light,"spawn":0.0})

func _pap_curve(points: Array) -> CurveTexture:
	var c:=Curve.new()
	for p in points: c.add_point(p)
	var t:=CurveTexture.new()
	t.curve=c
	return t

## Klikatý blesk mezi dvěma body: dělení úseček s náhodným odklonem, prohnutý od zbraně ven.
func _arc_points(a: Vector3, b: Vector3, out: Vector3) -> PackedVector3Array:
	var pts:=PackedVector3Array([a,b])
	var amp:=a.distance_to(b)*0.22
	for level in 4:
		var next:=PackedVector3Array()
		for i in pts.size()-1:
			next.append(pts[i])
			var mid:=(pts[i]+pts[i+1])*0.5
			mid+=Vector3(randf_range(-1,1),randf_range(-1,1),randf_range(-1,1))*amp
			next.append(mid)
		next.append(pts[pts.size()-1])
		pts=next
		amp*=0.5
	var n:=pts.size()-1
	var bulge:=a.distance_to(b)*0.28
	for i in pts.size():
		pts[i]+=out*bulge*sin(PI*float(i)/float(n))
	return pts

func _update_pap_arcs(dt: float) -> void:
	var cam:=get_viewport().get_camera_3d() if is_inside_tree() else null
	for i in range(_pap_arcs.size()-1,-1,-1):
		var e: Dictionary=_pap_arcs[i]
		if not is_instance_valid(e.fx):
			_pap_arcs.remove_at(i)
			continue
		var fx: Node3D=e.fx
		var im: ImmediateMesh=e.mesh
		im.clear_surfaces()
		if cam==null or not fx.is_visible_in_tree() or (e.samples as PackedVector3Array).size()<2: continue
		var samples: PackedVector3Array=e.samples
		var arcs: Array=e.arcs
		# nové výboje (Poissonův proces), občas jeden velký přes celou zbraň
		e.spawn=float(e.spawn)+dt*float(e.rate)*(0.6+_pap_surge*3.0)
		while float(e.spawn)>=1.0 and arcs.size()<6:
			e.spawn=float(e.spawn)-1.0
			var a: Vector3=samples[randi()%samples.size()]
			var big:=randf()<0.12
			var want: float=float(e.len)*(randf_range(1.6,2.6) if big else randf_range(0.35,1.0))
			var b:=a
			for tries in 14:
				var c: Vector3=samples[randi()%samples.size()]
				if absf(c.distance_to(a)-want)<absf(b.distance_to(a)-want): b=c
			if a.distance_to(b)<0.02: continue
			var life:=randf_range(0.07,0.16)*(1.6 if big else 1.0)
			arcs.append({"a":a,"b":b,"life":life,"max":life,"w":(1.6 if big else 1.0),"pts":PackedVector3Array(),"jit":0.0})
		if float(e.spawn)>=1.0: e.spawn=0.0
		var to_local:=fx.global_transform.affine_inverse()
		var eye: Vector3=to_local*cam.global_position
		var center: Vector3=e.center
		var axis: Vector3=e.axis
		var glow:=0.0
		var drawn:=false
		for k in range(arcs.size()-1,-1,-1):
			var arc: Dictionary=arcs[k]
			arc.life=float(arc.life)-dt
			if float(arc.life)<=0.0:
				arcs.remove_at(k)
				continue
			arc.jit=float(arc.jit)-dt
			if float(arc.jit)<=0.0 or (arc.pts as PackedVector3Array).is_empty():
				arc.jit=0.025
				var mid: Vector3=(arc.a+arc.b)*0.5-center
				var out:=(mid-axis*mid.dot(axis))
				out=out.normalized() if out.length_squared()>1e-6 else Vector3.UP
				arc.pts=_arc_points(arc.a,arc.b,out)
			var fade: float=sqrt(float(arc.life)/float(arc.max))*randf_range(0.55,1.0)
			glow+=fade*float(arc.w)
			var pts: PackedVector3Array=arc.pts
			if not drawn:
				im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
				drawn=true
			for pass_i in 2:
				var w: float=(0.011 if pass_i==0 else 0.0032)*float(arc.w)
				var core: float=0.0 if pass_i==0 else 1.0
				for j in pts.size()-1:
					var p0: Vector3=pts[j]
					var p1: Vector3=pts[j+1]
					var side:=(p1-p0).cross(eye-p0)
					if side.length_squared()<1e-12: continue
					side=side.normalized()*w
					im.surface_set_color(Color(1,1,1,fade*(0.35 if pass_i==0 else 0.9)))
					im.surface_set_uv(Vector2(0,core)); im.surface_add_vertex(p0-side)
					im.surface_set_uv(Vector2(1,core)); im.surface_add_vertex(p0+side)
					im.surface_set_uv(Vector2(1,core)); im.surface_add_vertex(p1+side)
					im.surface_set_uv(Vector2(0,core)); im.surface_add_vertex(p0-side)
					im.surface_set_uv(Vector2(1,core)); im.surface_add_vertex(p1+side)
					im.surface_set_uv(Vector2(0,core)); im.surface_add_vertex(p1-side)
		if drawn: im.surface_end()
		e.glow=glow

func _update_pap(dt: float) -> void:
	if _pap.is_empty(): return
	_pap_strength=move_toward(_pap_strength,1.0,dt*0.6)
	_pap_surge=move_toward(_pap_surge,0.0,dt*5.0)
	var cur:=int(_pap.get(gun,0))
	for t in _tier_mats:
		var m: ShaderMaterial=_tier_mats[t]
		m.set_shader_parameter("strength",smoothstep(0.0,1.0,_pap_strength))
		m.set_shader_parameter("surge",_pap_surge if t==cur else 0.0)
	_update_pap_arcs(dt)
	var arc_glow:={}
	for e in _pap_arcs: arc_glow[e.light]=float(e.get("glow",0.0))
	var flick:=1.0+0.24*sin(_time*3.1)+0.14*sin(_time*7.7)
	for i in range(_pap_lights.size()-1,-1,-1):
		var l=_pap_lights[i]
		if not is_instance_valid(l):
			_pap_lights.remove_at(i)
			_pap_fx_light.erase(l)
			continue
		var base: float=float(_pap_fx_light.get(l,0.4))
		# světlo zablikne s každým výbojem
		var zap: float=minf(float(arc_glow.get(l,0.0)),2.0)*0.9
		(l as OmniLight3D).light_energy=(base*flick+base*zap+_pap_surge*base*3.0)*_pap_strength

func _update_flash_tint() -> void:
	# Záblesk výstřelu v barvě stupně (obyčejná zbraň: oranžový).
	var t:=int(_pap.get(gun,0))
	var col: Color=TIER_LOOK[t][0] if t>0 else Color(1.0,0.72,0.4)
	for flash in _flashes:
		for q in flash.find_children("*","MeshInstance3D",true,false):
			var m:=(q as MeshInstance3D).material_override as StandardMaterial3D
			if m: m.albedo_color=FLASH_BASE if t==0 else Color(0.6+col.r*2.0,0.6+col.g*2.0,0.6+col.b*2.0)
	if _light: _light.light_color=col


# --- injekce v ruce
const ARM_YAW:=0.5          # natočení předloktí ke středu
const ARM_ROLL:=0.0         # natočení dlaně
const NEEDLE_DIR:=Vector3(0.85,-0.38,0.2)   # směr jehly při vpichu (zprava, mírně shora)
const NEEDLE_UP:=Vector3(0.0,1.0,0.1)
const SYRINGE_LEN:=0.3
var _syringe_tip:=Vector3(0,0,-0.2)

func _make_syringe() -> Node3D:
	# Injektor s pistolovou rukojetí: osa jehly do -Z (jako hlaveň), rukojeť dolů, úchop u počátku.
	var holder:=Node3D.new()
	holder.name="syringe"
	var pivot:=Node3D.new()
	holder.add_child(pivot)
	var path:="res://assets/props/syringe/source/syringe.glb"
	if not ResourceLoader.exists(path): return holder
	var raw: Node3D=load(path).instantiate()
	pivot.add_child(raw)
	var parts:={}
	for m in raw.find_children("*","MeshInstance3D",true,false):
		for key in ["Tip","Glass","wood","Pusher"]:
			if key in String(m.name): parts[key]=m
	if not (parts.has("Tip") and parts.has("Glass") and parts.has("wood")): return holder
	var c:=func(m: MeshInstance3D) -> Vector3: return (Props._xf(m,pivot)*m.get_aabb()).get_center()
	var tip: Vector3=c.call(parts.Tip)
	var glass: Vector3=c.call(parts.Glass)
	var wood: Vector3=c.call(parts.wood)
	var axis:=(tip-glass).normalized()
	var down:=wood-glass
	down=(down-axis*down.dot(axis)).normalized()
	var z:=-axis
	var y:=-down
	var x:=y.cross(z).normalized()
	y=z.cross(x)
	var to_holder:=Basis(x,y,z).transposed()
	var all: AABB=Props._bounds(pivot)
	var length:=0.0
	for i in 8:
		var corner:=all.get_endpoint(i)
		length=maxf(length,absf((to_holder*corner).z-(to_holder*tip).z))
	var k:=SYRINGE_LEN/maxf(length,0.0001)
	pivot.basis=to_holder.scaled(Vector3.ONE*k)
	# Úchop: horní část rukojeti, kousek pod osou.
	var w:=pivot.basis*wood
	var g:=pivot.basis*glass
	var on_axis:=Vector3(g.x,g.y,w.z)
	var grip:=w.lerp(on_axis,0.45)
	pivot.position=GRIP_AT-grip
	_syringe_tip=pivot.transform*tip
	if parts.has("Pusher"):
		var pusher: Node3D=parts.Pusher
		holder.set_meta("pusher",pusher)
		holder.set_meta("pusher_rest",pusher.position)
		var to_parent:=Props._xf(pusher.get_parent(),holder).basis.inverse()
		holder.set_meta("pusher_dir",to_parent*Vector3(0,0,-0.05))
	for m in holder.find_children("*","MeshInstance3D",true,false):
		(m as MeshInstance3D).cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return holder

const GRIP_AT:=Vector3(0.0,0.035,0.035)
