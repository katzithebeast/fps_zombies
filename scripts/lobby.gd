extends Node3D
## Karanténní pokoj (lobby): hráčův vlastní pokoj ve starém sanatoriu, kam se vrací mezi misemi.
## Zatím jedna místnost se zavřenými dveřmi. Postavená z kódu: stěny, okno, světlo a modely.

const M:="res://assets/lobby/"
const W:=2.5          # polovina šířky pokoje (x)
const D:=1.9          # polovina hloubky (z)
const H:=3.2          # výška stropu
const T:=0.25         # tloušťka zdí
const TILE_H:=1.45    # obklad do výšky
const WIN:=Rect2(-1.2,1.5,1.3,1.3)      # okno v severní zdi: x, y, šířka, výška
const DOOR:=Rect2(-2.2,0.0,1.6,2.2)     # dveře v jižní zdi

var settings:={"mouse": 1.0, "fov": 75.0, "volume": 0.8}
var _mats:={}
var player: CharacterBody3D
var cam: Camera3D
var _yaw:=0.0
var _pitch:=0.0
var _step_t:=0.0
var _bob:=0.0
var _prompt: Label
var _toast: Label
var _toast_t:=0.0
var _interact:={}            # collider -> {text, call}
var _lamp_light: SpotLight3D
var _lamp_tube: MeshInstance3D
var _lamp_fill: OmniLight3D
var _lamp_hum: AudioStreamPlayer3D
var _flicker_t:=4.0
var _flicker:=0.0
var _radio: AudioStreamPlayer3D
var _radio_on:=false
var _radio_next:=0.0
var _drip_t:=3.0
var _sink_pos:=Vector3.ZERO
var _steps:=[]

func _ready() -> void:
	_load_settings()
	_build_environment()
	_build_room()
	_build_window()
	_build_door_and_corridor()
	_build_props()
	_build_lamp()
	_build_decals()
	_build_dust()
	_build_sound()
	_build_player()
	_build_hud()

# ------------------------------------------------------------------ nastavení

func _load_settings() -> void:
	var cf:=ConfigFile.new()
	if cf.load("user://settings.cfg")==OK:
		for k in settings:
			if cf.has_section_key("s",k): settings[k]=float(cf.get_value("s",k))
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(float(settings.volume),0.001)))

# ------------------------------------------------------------------ materiály

## Materiál z balíčku: barva + normála + drsnost, mapované podle světa (nezáleží na UV kvádrů).
func mat(key: String, meters: float, tint:=Color.WHITE, normal:=1.0) -> StandardMaterial3D:
	var id:="%s_%.2f_%s_%.2f"%[key,meters,tint.to_html(),normal]
	if _mats.has(id): return _mats[id]
	var m:=StandardMaterial3D.new()
	m.albedo_texture=load(M+"mats/%s_albedo.jpg"%key)
	m.albedo_color=tint
	m.normal_enabled=true
	m.normal_texture=load(M+"mats/%s_normal.jpg"%key)
	m.normal_scale=normal
	m.roughness_texture=load(M+"mats/%s_rough.jpg"%key)
	m.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.uv1_triplanar=true
	m.uv1_world_triplanar=true
	m.uv1_triplanar_sharpness=6.0
	m.uv1_scale=Vector3.ONE/meters
	m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[id]=m
	return m

func flat(c: Color, rough:=0.6, metal:=0.0) -> StandardMaterial3D:
	var m:=StandardMaterial3D.new()
	m.albedo_color=c
	m.roughness=rough
	m.metallic=metal
	return m

func box(size: Vector3, center: Vector3, m: Material, collide:=true, parent: Node=self) -> MeshInstance3D:
	var mi:=MeshInstance3D.new()
	var bm:=BoxMesh.new()
	bm.size=size
	mi.mesh=bm
	mi.material_override=m
	mi.position=center
	parent.add_child(mi)
	if collide:
		var sb:=StaticBody3D.new()
		var cs:=CollisionShape3D.new()
		var sh:=BoxShape3D.new()
		sh.size=size
		cs.shape=sh
		sb.add_child(cs)
		mi.add_child(sb)
	return mi

## Kvádr zadaný rohy (min, max) – pro stěny se otvory se to píše přehledněji.
func slab(a: Vector3, b: Vector3, m: Material, collide:=true) -> MeshInstance3D:
	return box((b-a).abs(),(a+b)*0.5,m,collide)

func cyl(r: float, h: float, center: Vector3, m: Material, rot:=Vector3.ZERO, parent: Node=self) -> MeshInstance3D:
	var mi:=MeshInstance3D.new()
	var cm:=CylinderMesh.new()
	cm.top_radius=r
	cm.bottom_radius=r
	cm.height=h
	cm.radial_segments=12
	mi.mesh=cm
	mi.material_override=m
	mi.position=center
	mi.rotation=rot
	parent.add_child(mi)
	return mi

# ------------------------------------------------------------------ prostředí

func _build_environment() -> void:
	var we:=WorldEnvironment.new()
	var env:=Environment.new()
	var sky:=Sky.new()
	var ps:=ProceduralSkyMaterial.new()
	ps.sky_top_color=Color(0.33,0.47,0.68)
	ps.sky_horizon_color=Color(0.93,0.76,0.56)
	ps.ground_horizon_color=Color(0.6,0.5,0.42)
	ps.ground_bottom_color=Color(0.22,0.2,0.18)
	ps.sun_angle_max=20.0
	ps.sky_energy_multiplier=1.3
	sky.sky_material=ps
	env.background_mode=Environment.BG_SKY
	env.sky=sky
	env.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy=0.25
	env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode=Environment.TONE_MAPPER_ACES
	env.tonemap_white=6.0
	env.tonemap_exposure=1.05
	env.sdfgi_enabled=true
	env.sdfgi_use_occlusion=true
	env.sdfgi_cascades=2
	env.sdfgi_min_cell_size=0.08
	env.sdfgi_energy=0.9
	env.sdfgi_bounce_feedback=0.5
	env.ssao_enabled=true
	env.ssao_radius=0.8
	env.ssao_intensity=2.0
	env.ssil_enabled=true
	env.ssil_radius=2.0
	env.ssr_enabled=true
	env.ssr_max_steps=48
	env.glow_enabled=true
	env.glow_intensity=0.35
	env.glow_bloom=0.04
	env.glow_hdr_threshold=1.2
	env.volumetric_fog_enabled=true
	env.volumetric_fog_density=0.026
	env.volumetric_fog_albedo=Color(0.95,0.9,0.82)
	env.volumetric_fog_ambient_inject=0.05
	env.volumetric_fog_length=12.0
	env.volumetric_fog_detail_spread=1.5
	env.adjustment_enabled=true
	env.adjustment_saturation=0.92
	env.adjustment_contrast=1.06
	we.environment=env
	add_child(we)
	# Večerní slunce zvenku, šikmo přes mříže do pokoje (teplé, kontrast proti zářivce)
	var sun:=DirectionalLight3D.new()
	sun.light_color=Color(1.0,0.78,0.52)
	sun.light_energy=4.0
	sun.light_volumetric_fog_energy=2.6
	sun.shadow_enabled=true
	sun.shadow_blur=0.6
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance=14.0
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO,Vector3(0.32,-0.55,1.0))

# ------------------------------------------------------------------ místnost

func _build_room() -> void:
	var paint:=mat("peeling_paint",1.6)
	var ceiling:=mat("peeling_paint",2.4,Color(1.3,1.22,1.12),0.25)
	var tiles:=mat("ceramic_tiles",0.8,Color(0.97,0.97,0.94))
	var floor_m:=mat("terrazzo",1.3)
	var E:=W+T; var F:=D+T
	# podlaha a strop
	slab(Vector3(-E,-0.2,-F),Vector3(E,0.0,F),floor_m)
	slab(Vector3(-E,H,-F),Vector3(E,H+0.2,F),ceiling)
	# sever (okno)
	slab(Vector3(-E,0,-F),Vector3(WIN.position.x,H,-D),paint)
	slab(Vector3(WIN.end.x,0,-F),Vector3(E,H,-D),paint)
	slab(Vector3(WIN.position.x,0,-F),Vector3(WIN.end.x,WIN.position.y,-D),paint)
	slab(Vector3(WIN.position.x,WIN.end.y,-F),Vector3(WIN.end.x,H,-D),paint)
	# jih (dveře)
	slab(Vector3(-E,0,D),Vector3(DOOR.position.x,H,F),paint)
	slab(Vector3(DOOR.end.x,0,D),Vector3(E,H,F),paint)
	slab(Vector3(DOOR.position.x,DOOR.end.y,D),Vector3(DOOR.end.x,H,F),paint)
	# západ, východ
	slab(Vector3(-E,0,-D),Vector3(-W,H,D),paint)
	slab(Vector3(W,0,-D),Vector3(E,H,D),paint)
	# obklad do výšky 1,45 m s lištou (starý nemocniční sokl)
	var c:=0.016
	slab(Vector3(-W,0,-D),Vector3(W,TILE_H,-D+c),tiles,false)
	slab(Vector3(-W,0,D-c),Vector3(DOOR.position.x,TILE_H,D),tiles,false)
	slab(Vector3(DOOR.end.x,0,D-c),Vector3(W,TILE_H,D),tiles,false)
	slab(Vector3(-W,0,-D),Vector3(-W+c,TILE_H,D),tiles,false)
	slab(Vector3(W-c,0,-D),Vector3(W,TILE_H,D),tiles,false)
	var cap:=flat(Color(0.2,0.27,0.24),0.35)
	var k:=0.03
	slab(Vector3(-W,TILE_H,-D),Vector3(W,TILE_H+0.035,-D+k),cap,false)
	slab(Vector3(-W,TILE_H,D-k),Vector3(DOOR.position.x,TILE_H+0.035,D),cap,false)
	slab(Vector3(DOOR.end.x,TILE_H,D-k),Vector3(W,TILE_H+0.035,D),cap,false)
	slab(Vector3(-W,TILE_H,-D),Vector3(-W+k,TILE_H+0.035,D),cap,false)
	slab(Vector3(W-k,TILE_H,-D),Vector3(W,TILE_H+0.035,D),cap,false)
	# trubka topení v rohu a ke radiátoru
	var pipe:=mat("painted_metal",0.6,Color(0.85,0.85,0.8))
	cyl(0.028,H,Vector3(-W+0.08,H*0.5,-D+0.08),pipe)
	cyl(0.022,1.35,Vector3(-W+0.08+0.62,0.22,-D+0.07),pipe,Vector3(0,0,PI/2))

func _build_window() -> void:
	var x0:=WIN.position.x; var x1:=WIN.end.x; var y0:=WIN.position.y; var y1:=WIN.end.y
	var frame:=mat("painted_metal",0.5,Color(2.2,2.3,2.2),0.6)
	var zf:=-D-0.14
	# rám okna (zapuštěný ve zdi), střední sloupek a příčka
	var f:=0.06
	box(Vector3(WIN.size.x,f,0.08),Vector3((x0+x1)*0.5,y0+f*0.5,zf),frame,false)
	box(Vector3(WIN.size.x,f,0.08),Vector3((x0+x1)*0.5,y1-f*0.5,zf),frame,false)
	box(Vector3(f,WIN.size.y,0.08),Vector3(x0+f*0.5,(y0+y1)*0.5,zf),frame,false)
	box(Vector3(f,WIN.size.y,0.08),Vector3(x1-f*0.5,(y0+y1)*0.5,zf),frame,false)
	box(Vector3(0.05,WIN.size.y,0.07),Vector3((x0+x1)*0.5,(y0+y1)*0.5,zf),frame,false)
	box(Vector3(WIN.size.x,0.05,0.07),Vector3((x0+x1)*0.5,y0+WIN.size.y*0.68,zf),frame,false)
	# sklo: lehce zašpiněné, nevrhá stín
	var glass:=StandardMaterial3D.new()
	glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color=Color(0.75,0.8,0.78,0.08)
	glass.roughness=0.05
	glass.metallic_specular=0.8
	var g:=box(Vector3(WIN.size.x-0.08,WIN.size.y-0.08,0.008),Vector3((x0+x1)*0.5,(y0+y1)*0.5,zf),glass,false)
	g.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# parapet
	slab(Vector3(x0-0.06,y0-0.04,-D-0.06),Vector3(x1+0.06,y0+0.01,-D+0.07),mat("terrazzo",0.8,Color(1.15,1.15,1.15)),true)
	# mříže zevnitř
	var bars:=mat("rusty_metal",0.4,Color(0.75,0.72,0.7))
	for i in 6:
		var x:=lerpf(x0+0.1,x1-0.1,float(i)/5.0)
		cyl(0.011,WIN.size.y+0.06,Vector3(x,(y0+y1)*0.5,-D-0.03),bars)
	for yy in [y0+0.25,y1-0.25]:
		cyl(0.012,WIN.size.x+0.04,Vector3((x0+x1)*0.5,yy,-D-0.03),bars,Vector3(0,0,PI/2))
	# radiátor pod oknem (litinové články)
	var rad:=mat("painted_metal",0.5,Color(2.0,2.05,1.95),0.8)
	var cx:=(x0+x1)*0.5
	for i in 14:
		box(Vector3(0.045,0.58,0.16),Vector3(cx-0.34+i*0.052,0.47,-D+0.12),rad,i==0)
	cyl(0.02,0.74,Vector3(cx,0.2,-D+0.12),rad,Vector3(0,0,PI/2))
	cyl(0.02,0.74,Vector3(cx,0.74,-D+0.12),rad,Vector3(0,0,PI/2))
	for s in [-1,1]:
		box(Vector3(0.02,0.18,0.02),Vector3(cx+s*0.3,0.08,-D+0.14),rad,false)

func _build_door_and_corridor() -> void:
	# chodba za dveřmi: tlumené světlo, které je vidět okénky ve dveřích
	var cpaint:=mat("peeling_paint",1.6,Color(0.8,0.82,0.78))
	var z0:=D+T; var z1:=D+T+2.2
	slab(Vector3(-4.5,-0.2,z0),Vector3(1.5,0.0,z1),mat("linoleum",1.5),false)
	slab(Vector3(-4.5,2.8,z0),Vector3(1.5,3.0,z1),cpaint,false)
	slab(Vector3(-4.5,0,z1),Vector3(1.5,2.8,z1+0.2),cpaint,false)
	slab(Vector3(-4.7,0,z0),Vector3(-4.5,2.8,z1),cpaint,false)
	slab(Vector3(1.5,0,z0),Vector3(1.7,2.8,z1),cpaint,false)
	var cl:=OmniLight3D.new()
	cl.position=Vector3(-1.8,2.5,z0+1.1)
	cl.light_color=Color(1.0,0.86,0.62)
	cl.light_energy=1.6
	cl.omni_range=4.5
	cl.shadow_enabled=true
	add_child(cl)
	# dveře: dvoukřídlé plechové s okénky, zavřené
	var door:=_place("door",Vector3(1.72/375.7,2.3/356.66,0.0055),180.0,Vector3(DOOR.get_center().x,0,D+T*0.5))
	for mi in door.find_children("*","MeshInstance3D",true,false):
		var m: MeshInstance3D=mi
		for i in m.mesh.get_surface_count():
			var mt:=m.get_active_material(i)
			if mt and mt.resource_name.begins_with("glass"):
				var gl:=StandardMaterial3D.new()
				gl.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
				gl.albedo_color=Color(0.72,0.76,0.72,0.6)
				gl.roughness=0.55
				m.set_surface_override_material(i,gl)
				m.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var blocker:=StaticBody3D.new()
	var cs:=CollisionShape3D.new()
	var sh:=BoxShape3D.new()
	sh.size=Vector3(DOOR.size.x,DOOR.size.y,0.2)
	cs.shape=sh
	blocker.add_child(cs)
	blocker.position=Vector3(DOOR.get_center().x,DOOR.size.y*0.5,D+0.05)
	add_child(blocker)
	_interact[blocker]={"text":"[E] Dveře","call":_on_door}
	# vypínač vedle dveří
	box(Vector3(0.08,0.12,0.02),Vector3(DOOR.end.x+0.25,1.3,D-0.01),flat(Color(0.82,0.8,0.72),0.4),false)

# ------------------------------------------------------------------ modely

## Model na místo: měřítko, otočení (°), pozice středu půdorysu; dno na podlaze (nebo `y`).
## `snap` zarovná hranu k bodu: {"x_min":…, "x_max":…, "z_min":…, "z_max":…, "y":…}
func _place(name: String, scale: Variant, rot_y: float, pos: Vector3, snap:={}, collide:=true) -> Node3D:
	var path:=M+"models/%s.glb"%name if not name.begins_with("res://") else name
	var n: Node3D=load(path).instantiate()
	var holder:=Node3D.new()
	holder.name=name.get_file().get_basename()
	add_child(holder)
	holder.add_child(n)
	n.scale=scale if scale is Vector3 else Vector3.ONE*float(scale)
	holder.rotation.y=deg_to_rad(rot_y)
	var a:=_aabb(holder)
	var off:=Vector3(pos.x-a.get_center().x,(float(snap.get("y",pos.y)))-a.position.y,pos.z-a.get_center().z)
	if snap.has("x_min"): off.x=float(snap.x_min)-a.position.x
	if snap.has("x_max"): off.x=float(snap.x_max)-a.end.x
	if snap.has("z_min"): off.z=float(snap.z_min)-a.position.z
	if snap.has("z_max"): off.z=float(snap.z_max)-a.end.z
	holder.position+=off
	if collide:
		a=_aabb(holder)
		var sb:=StaticBody3D.new()
		var cs:=CollisionShape3D.new()
		var sh:=BoxShape3D.new()
		sh.size=a.size
		cs.shape=sh
		cs.position=a.get_center()
		sb.add_child(cs)
		add_child(sb)
		holder.set_meta("body",sb)
	for mi in holder.find_children("*","MeshInstance3D",true,false):
		(mi as MeshInstance3D).gi_mode=GeometryInstance3D.GI_MODE_STATIC
	return holder

func _aabb(n: Node3D) -> AABB:
	var a:=AABB()
	var first:=true
	for m in n.find_children("*","MeshInstance3D",true,false):
		var mi: MeshInstance3D=m
		var t:=n.global_transform.affine_inverse()*mi.global_transform if not n.is_inside_tree() else mi.global_transform
		var b: AABB=t*mi.get_aabb()
		if first: a=b; first=false
		else: a=a.merge(b)
	return a

func _build_props() -> void:
	# postel u západní zdi, čelo u okna
	_place("bed",0.0095,90.0,Vector3(0,0,-0.8),{"x_min":-W+0.04})
	# polička nad postelí (slot na trofeje)
	var wood:=mat("old_wood",0.9,Color(1.05,1.0,0.95))
	box(Vector3(0.22,0.03,1.0),Vector3(-W+0.11,1.62,-0.8),wood)
	var iron:=mat("painted_metal",0.5,Color(0.45,0.45,0.42))
	for z in [-1.2,-0.4]:
		box(Vector3(0.18,0.02,0.02),Vector3(-W+0.09,1.58,z),iron,false)
	# stůl pod nástěnkou, rádio a měřák
	var table:=_place("table",0.01,0.0,Vector3(1.35,0,0),{"z_min":-D+0.03})
	var top:=_aabb(table).end.y
	var radio:=_place("radio",0.00229,-12.0,Vector3(1.05,0,-1.62),{"y":top},false)
	_place("multimeter",1.0,18.0,Vector3(1.66,0,-1.55),{"y":top},false)
	_interact[_body_for(radio,Vector3(0.5,0.4,0.4))]={"text":"[E] Rádio","call":_on_radio}
	# nástěnka nad stolem (slot na stopy)
	var cork:=mat("cork",0.6)
	box(Vector3(0.95,0.65,0.025),Vector3(1.35,1.75,-D+0.03),cork,false)
	for s in [Vector3(0.0,0.335,0),Vector3(0.0,-0.335,0)]:
		box(Vector3(1.0,0.03,0.04),Vector3(1.35,1.75,-D+0.035)+s,wood,false)
	for s in [Vector3(0.49,0,0),Vector3(-0.49,0,0)]:
		box(Vector3(0.03,0.7,0.04),Vector3(1.35,1.75,-D+0.035)+s,wood,false)
	# komoda u západní zdi za postelí, na ní televize
	var drawers:=_place("drawers",0.21,0.0,Vector3(0,0,0.95),{"x_min":-W+0.025})
	var da:=_aabb(drawers)
	var tv:=_place("crt_tv",0.044,90.0,Vector3(da.get_center().x-0.04,0,da.get_center().z),{"y":da.end.y},false)
	_interact[_body_for(tv)]={"text":"[E] Televize","call":func(): _say("Televize zatím nehraje. Tady budou tvoje statistiky.")}
	# gauč u východní zdi, čelem k televizi přes celý pokoj
	_place("sofa",0.72,-90.0,Vector3(0,0,0.1),{"x_max":W-0.04})
	# umyvadlo u jižní zdi a zrcadlo nad ním
	var sink:=_place("sink",0.0095,-90.0,Vector3(0.55,0,0),{"z_max":D-0.02})
	_sink_pos=_aabb(sink).get_center()
	var sa:=_aabb(sink)
	box(Vector3(0.5,0.62,0.03),Vector3(0.55,sa.end.y+0.5,D-0.03),flat(Color(0.18,0.17,0.15),0.5),false)
	var mirror:=flat(Color(0.95,0.96,0.95),0.07,1.0)
	box(Vector3(0.44,0.56,0.01),Vector3(0.55,sa.end.y+0.5,D-0.05),mirror,false)
	var probe:=ReflectionProbe.new()
	probe.position=Vector3(0.55,1.6,1.2)
	probe.size=Vector3(5.0,3.2,3.8)
	probe.box_projection=true
	probe.interior=true
	probe.update_mode=ReflectionProbe.UPDATE_ONCE
	# zrcadlo se nasnímá, až se usadí světlo (GI potřebuje pár snímků)
	get_tree().create_timer(1.2).timeout.connect(func(): add_child(probe))
	# skříňka v jihovýchodním rohu (oblek)
	var locker:=_place("res://assets/props/locker/source/locker.glb",1.0,180.0,Vector3(0,0,0),{"x_max":W-0.03,"z_max":D-0.03})
	_interact[locker.get_meta("body")]={"text":"[E] Skříňka","call":func(): _say("Skříňka s oblekem. Skiny přijdou sem.")}

func _body_for(n: Node3D, min_size:=Vector3.ZERO) -> StaticBody3D:
	var a:=_aabb(n)
	var sb:=StaticBody3D.new()
	var cs:=CollisionShape3D.new()
	var sh:=BoxShape3D.new()
	sh.size=a.size.max(min_size)
	cs.shape=sh
	cs.position=a.get_center()
	sb.add_child(cs)
	add_child(sb)
	return sb

# ------------------------------------------------------------------ zářivka

func _build_lamp() -> void:
	var p:=Vector3(0.2,H,0.0)
	var housing:=mat("painted_metal",0.5,Color(1.9,1.95,1.9),0.5)
	box(Vector3(1.25,0.07,0.16),p+Vector3(0,-0.42,0),housing,false)
	for s in [-0.45,0.45]:
		cyl(0.006,0.38,p+Vector3(s,-0.19,0),flat(Color(0.3,0.3,0.3),0.4,0.8))
	var tm:=StandardMaterial3D.new()
	tm.albedo_color=Color(0.95,0.98,1.0)
	tm.emission_enabled=true
	tm.emission=Color(0.85,0.95,1.0)
	tm.emission_energy_multiplier=6.0
	_lamp_tube=cyl(0.016,1.15,p+Vector3(0,-0.47,0),tm,Vector3(0,0,PI/2))
	_lamp_tube.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lamp_light=SpotLight3D.new()
	_lamp_light.position=p+Vector3(0,-0.5,0)
	_lamp_light.rotation.x=-PI/2
	_lamp_light.spot_angle=78.0
	_lamp_light.spot_range=6.0
	_lamp_light.spot_attenuation=0.6
	_lamp_light.light_color=Color(0.86,0.94,1.0)
	_lamp_light.light_energy=1.25
	_lamp_light.light_volumetric_fog_energy=0.3
	_lamp_light.shadow_enabled=true
	add_child(_lamp_light)
	_lamp_fill=OmniLight3D.new()
	_lamp_fill.position=p+Vector3(0,-0.55,0)
	_lamp_fill.omni_range=5.0
	_lamp_fill.light_color=Color(0.86,0.94,1.0)
	_lamp_fill.light_energy=0.35
	_lamp_fill.light_volumetric_fog_energy=0.0
	add_child(_lamp_fill)

# ------------------------------------------------------------------ špína, plíseň, praskliny

func _decal(file: String, pos: Vector3, normal: Vector3, size: Vector2, rot:=0.0, alpha:=1.0) -> void:
	var d:=Decal.new()
	d.texture_albedo=load(M+"decals/%s.png"%file)
	d.size=Vector3(size.x,0.2,size.y)
	d.modulate=Color(1,1,1,alpha)
	d.cull_mask=1
	add_child(d)
	# decal promítá podél své -Y: otočit tak, aby -Y mířila do stěny
	var up:=normal.normalized()
	var ref:=Vector3.UP if absf(up.dot(Vector3.UP))<0.9 else Vector3.FORWARD
	var x:=ref.cross(up).normalized()
	var z:=x.cross(up).normalized()
	d.global_transform=Transform3D(Basis(x,up,z).rotated(up,rot),pos)

func _build_decals() -> void:
	var cx:=WIN.get_center().x
	_decal("decal_water_1_runoff_streaks",Vector3(cx,0.9,-D),Vector3(0,0,1),Vector2(1.2,1.0),0.0,0.8)
	_decal("decal_mold_4_mixed_mold_drips",Vector3(-W,2.9,-1.4),Vector3(1,0,0),Vector2(1.0,0.8),0.0,0.9)
	_decal("decal_mold_1_black_mildew",Vector3(-2.1,H,-1.6),Vector3(0,-1,0),Vector2(1.0,1.0),0.6,0.8)
	_decal("decal_water_2_damp_tide_mark",Vector3(1.2,H,0.6),Vector3(0,-1,0),Vector2(1.6,1.6),1.2,0.7)
	_decal("decal_cracks_1_vertical_branching",Vector3(W,2.4,-1.0),Vector3(-1,0,0),Vector2(0.8,1.1),0.0,0.9)
	_decal("decal_cracks_3_hairline_network",Vector3(-0.4,2.3,D),Vector3(0,0,-1),Vector2(1.2,0.9),0.0,0.8)
	_decal("decal_grime_4_greasy_finger_drag",Vector3(DOOR.end.x+0.25,1.25,D),Vector3(0,0,-1),Vector2(0.4,0.4),0.0,0.8)
	_decal("decal_grime_3_dusty_abrasion",Vector3(0.35,0.002,0.3),Vector3(0,1,0),Vector2(2.4,1.8),0.4,0.5)
	_decal("decal_grime_1_dark_smear",Vector3(-1.4,0.002,1.5),Vector3(0,1,0),Vector2(1.3,0.8),0.0,0.6)

func _build_dust() -> void:
	var p:=GPUParticles3D.new()
	p.amount=260
	p.lifetime=14.0
	p.preprocess=14.0
	p.visibility_aabb=AABB(Vector3(-W,0,-D),Vector3(W*2,H,D*2))
	var pm:=ParticleProcessMaterial.new()
	pm.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents=Vector3(W-0.2,H*0.5-0.1,D-0.2)
	pm.gravity=Vector3(0,-0.004,0)
	pm.initial_velocity_min=0.0
	pm.initial_velocity_max=0.03
	pm.direction=Vector3(0,1,0)
	pm.spread=180.0
	pm.turbulence_enabled=true
	pm.turbulence_noise_strength=0.4
	pm.turbulence_noise_speed_random=0.2
	pm.turbulence_influence_min=0.01
	pm.turbulence_influence_max=0.03
	pm.scale_min=0.6
	pm.scale_max=1.4
	p.process_material=pm
	var q:=QuadMesh.new()
	q.size=Vector2(0.004,0.004)
	var dm:=StandardMaterial3D.new()
	dm.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	dm.albedo_color=Color(1.0,0.95,0.85,0.7)
	dm.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.backlight_enabled=true
	dm.backlight=Color(1,1,1)
	q.material=dm
	p.draw_pass_1=q
	p.position=Vector3(0,H*0.5,0)
	add_child(p)

# ------------------------------------------------------------------ zvuk

func _snd(file: String, pos: Vector3, db:=0.0, loop:=false, unit:=6.0) -> AudioStreamPlayer3D:
	var a:=AudioStreamPlayer3D.new()
	var s: AudioStream=load(file)
	if loop and s is AudioStreamWAV:
		s=s.duplicate()
		(s as AudioStreamWAV).loop_mode=AudioStreamWAV.LOOP_FORWARD
		(s as AudioStreamWAV).loop_end=int((s as AudioStreamWAV).get_length()*(s as AudioStreamWAV).mix_rate)
	a.stream=s
	a.volume_db=db
	a.unit_size=unit
	a.position=pos
	add_child(a)
	if loop: a.play()
	return a

func _build_sound() -> void:
	_snd("res://audio/amb_room.wav",Vector3(0,1.5,0),-14.0,true,10.0)
	_lamp_hum=_snd("res://audio/lamp_hum.wav",Vector3(0.2,H-0.45,0),-22.0,true,2.0)
	_radio=_snd("res://audio/radio/radio_check_c1.wav",Vector3(1.05,0.95,-1.62),-4.0,false,3.0)
	var bus:=AudioServer.get_bus_index("Radio")
	if bus<0:
		AudioServer.add_bus()
		bus=AudioServer.bus_count-1
		AudioServer.set_bus_name(bus,"Radio")
		var bp:=AudioEffectBandPassFilter.new()
		bp.cutoff_hz=1600.0
		bp.resonance=0.7
		AudioServer.add_bus_effect(bus,bp)
		var dist:=AudioEffectDistortion.new()
		dist.mode=AudioEffectDistortion.MODE_LOFI
		dist.drive=0.25
		AudioServer.add_bus_effect(bus,dist)
	_radio.bus="Radio"
	for i in range(1,7): _steps.append(load("res://audio/step_tile_%d.wav"%i))

# ------------------------------------------------------------------ hráč

func _build_player() -> void:
	player=CharacterBody3D.new()
	var cs:=CollisionShape3D.new()
	var cap:=CapsuleShape3D.new()
	cap.radius=0.28
	cap.height=1.75
	cs.shape=cap
	cs.position.y=0.875
	player.add_child(cs)
	player.position=Vector3(-1.0,0.02,1.3)
	add_child(player)
	cam=Camera3D.new()
	cam.position.y=1.62
	cam.fov=float(settings.fov)
	cam.near=0.03
	player.add_child(cam)
	_yaw=deg_to_rad(-25.0)
	_pitch=deg_to_rad(4.0)
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED

func _build_hud() -> void:
	var cl:=CanvasLayer.new()
	add_child(cl)
	_prompt=Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.position=Vector2(-200,40)
	_prompt.size=Vector2(400,30)
	_prompt.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size",20)
	_prompt.add_theme_color_override("font_color",Color(0.92,0.9,0.82,0.9))
	_prompt.add_theme_color_override("font_shadow_color",Color(0,0,0,0.8))
	cl.add_child(_prompt)
	_toast=Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.position=Vector2(-400,-140)
	_toast.size=Vector2(800,40)
	_toast.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size",22)
	_toast.add_theme_color_override("font_shadow_color",Color(0,0,0,0.8))
	cl.add_child(_toast)
	var dot:=ColorRect.new()
	dot.color=Color(1,1,1,0.5)
	dot.size=Vector2(3,3)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.position=Vector2(-1.5,-1.5)
	cl.add_child(dot)
	_say("Karanténa. Pohyb WASD, interakce E, Esc zpět do menu.")

func _say(t: String) -> void:
	_toast.text=t
	_toast_t=4.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		_yaw-=event.relative.x*0.0022*float(settings.mouse)
		_pitch=clampf(_pitch-event.relative.y*0.0022*float(settings.mouse),-1.45,1.45)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_ESCAPE:
			Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
			get_tree().change_scene_to_file("res://main.tscn")
		elif event.physical_keycode==KEY_E:
			var hit:=_look_target()
			if hit and _interact.has(hit): (_interact[hit].call as Callable).call()

func _look_target() -> Object:
	if cam==null: return null
	var from:=cam.global_position
	var q:=PhysicsRayQueryParameters3D.create(from,from-cam.global_basis.z*2.2)
	q.exclude=[player.get_rid()]
	var r:=get_world_3d().direct_space_state.intersect_ray(q)
	return r.get("collider") if r else null

func _physics_process(dt: float) -> void:
	if player==null: return
	var dir:=Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): dir.z-=1
	if Input.is_physical_key_pressed(KEY_S): dir.z+=1
	if Input.is_physical_key_pressed(KEY_A): dir.x-=1
	if Input.is_physical_key_pressed(KEY_D): dir.x+=1
	dir=Basis(Vector3.UP,_yaw)*dir.normalized()
	var spd:=1.6 if Input.is_physical_key_pressed(KEY_SHIFT) else 2.4
	var v:=player.velocity
	var want:=dir*spd
	v.x=lerpf(v.x,want.x,1.0-exp(-10.0*dt))
	v.z=lerpf(v.z,want.z,1.0-exp(-10.0*dt))
	v.y=0.0 if player.is_on_floor() else v.y-9.8*dt
	player.velocity=v
	player.move_and_slide()
	var hs:=Vector2(v.x,v.z).length()
	_bob+=dt*hs*3.6
	_step_t-=dt*hs
	if _step_t<=0.0 and hs>0.5:
		_step_t=0.75
		var a:=AudioStreamPlayer.new()
		a.stream=_steps.pick_random()
		a.volume_db=-16.0
		a.pitch_scale=randf_range(0.92,1.06)
		add_child(a)
		a.play()
		a.finished.connect(a.queue_free)
	cam.position.y=1.62+sin(_bob*2.0)*0.018*minf(hs,1.0)
	cam.rotation=Vector3(_pitch,_yaw,sin(_bob)*0.003*minf(hs,1.0))
	var t:=_look_target()
	_prompt.text=String(_interact[t].text) if t and _interact.has(t) else ""

func _process(dt: float) -> void:
	_toast_t-=dt
	if _toast: _toast.modulate.a=clampf(_toast_t,0.0,1.0)
	_update_lamp(dt)
	_update_radio(dt)
	_drip_t-=dt
	if _drip_t<=0.0:
		_drip_t=randf_range(5.0,14.0)
		var d:=_snd("res://audio/drip_%d.wav"%randi_range(2,6),_sink_pos,-20.0,false,1.5)
		d.play()
		d.finished.connect(d.queue_free)

func _update_lamp(dt: float) -> void:
	if _lamp_light==null: return
	_flicker_t-=dt
	if _flicker_t<=0.0:
		_flicker_t=randf_range(6.0,18.0)
		_flicker=randf_range(0.25,0.6)
		var c:=_snd("res://audio/lamp_click.wav",_lamp_light.position,-18.0,false,2.0)
		c.play()
		c.finished.connect(c.queue_free)
	var k:=1.0
	if _flicker>0.0:
		_flicker-=dt
		k=0.25 if fmod(Time.get_ticks_msec()*0.001*23.0,1.0)<0.45 else 1.0
	_lamp_light.light_energy=1.25*k
	_lamp_fill.light_energy=0.35*k
	(_lamp_tube.material_override as StandardMaterial3D).emission_energy_multiplier=6.0*k

# ------------------------------------------------------------------ interakce

func _on_door() -> void:
	_say("Zamčeno. Eskorta pro tebe zatím nepřišla.")
	var a:=_snd("res://audio/locker_open.wav",Vector3(DOOR.get_center().x,1.1,D),-10.0,false,3.0)
	a.pitch_scale=0.7
	a.play()
	a.finished.connect(a.queue_free)

func _on_radio() -> void:
	_radio_on=not _radio_on
	_radio_next=0.3
	if not _radio_on: _radio.stop()
	_say("Rádio zapnuté – odposlech z terénu." if _radio_on else "Rádio vypnuté.")

func _update_radio(dt: float) -> void:
	if not _radio_on or _radio.playing: return
	_radio_next-=dt
	if _radio_next>0.0: return
	_radio_next=randf_range(3.0,8.0)
	var files:=[]
	var dir:=DirAccess.open("res://audio/radio")
	if dir:
		for f in dir.get_files():
			if f.ends_with(".wav"): files.append(f)
			elif f.ends_with(".wav.import"): files.append(f.trim_suffix(".import"))
	if files.is_empty(): return
	_radio.stream=load("res://audio/radio/"+String(files.pick_random()))
	_radio.play()
