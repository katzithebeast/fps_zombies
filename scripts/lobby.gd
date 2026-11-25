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

var settings:={"mouse": 1.0, "fov": 75.0, "volume": 0.8, "bob": 1.0}
var look:=[]
var _mats:={}
var wing: RefCounted
var player: CharacterBody3D
var cam: Camera3D
var _prompt: Label
var _toast: Label
var _toast_t:=0.0
var _radio: AudioStreamPlayer3D
var _radio_on:=false
var _radio_next:=0.0
var _drip_t:=3.0
var _sink_pos:=Vector3.ZERO
var _steps:=[]

## Mapa pokoje a křídla je normální scéna: maps/lobby_map.tscn (upravuje se v editoru).
## Kód níže ji umí znovu vygenerovat (tools/bake_lobby.gd), ale tím by se ruční úpravy přepsaly.
const MAP:="res://maps/lobby_map.tscn"
static var bake:=false
var map: Node3D

func _ready() -> void:
	add_to_group("lobby_main")
	_load_settings()
	if bake or (not ResourceLoader.exists(MAP) and get_node_or_null("LobbyMap")==null):
		_generate()
		if bake: return
		map=self
	else:
		map=get_node_or_null("LobbyMap")       # mapa je vložená v lobby.tscn (dá se upravovat i tam)
		if map==null:
			map=load(MAP).instantiate()
			add_child(map)
	if OS.get_environment("LOBBY_LITE")=="1":      # jen pro náhledy v softwarovém renderu (málo paměti)
		var we: WorldEnvironment=map.find_children("*","WorldEnvironment",true,false).front()
		if we:
			we.environment.sdfgi_enabled=false
			we.environment.volumetric_fog_enabled=false
	_build_runtime_sound()
	_build_player()
	_build_hud()

## Vygeneruje celé křídlo kódem (původní stavba). Používá ho tools/bake_lobby.gd.
func _generate() -> void:
	_build_environment()
	_build_room()
	_build_window()
	wing=preload("res://scripts/lobby_wing.gd").new()
	wing.L=self
	_build_door_and_corridor()
	_build_props()
	_build_lamp()
	_build_decals()
	_build_papers()
	wing.build(self)
	_build_dust()
	_build_sound()
	var sp:=Marker3D.new()
	sp.name="SpawnHrace"
	sp.position=Vector3(-1.0,0.02,1.3)
	sp.rotation.y=deg_to_rad(-25.0)
	add_child(sp)

# ------------------------------------------------------------------ nastavení

func _load_settings() -> void:
	var cf:=ConfigFile.new()
	if cf.load("user://settings.cfg")==OK:
		for k in settings:
			if cf.has_section_key("s",k): settings[k]=float(cf.get_value("s",k))
		var keys:=["look_suit","look_rubber","look_visor","look_pattern","look_pattern_color","look_pattern_scale","look_rubber_fx"]
		if cf.has_section_key("s","look_suit"):
			for k in keys: look.append(cf.get_value("s",k))
			look[3]=int(look[3]); look[5]=clampf(float(look[5]),0.2,4.0); look[6]=int(look[6])
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(float(settings.volume),0.001)))

# ------------------------------------------------------------------ materiály

## Materiál z balíčku: barva + normála + drsnost, mapované podle světa (nezáleží na UV kvádrů).
func mat(key: String, meters: float, tint:=Color.WHITE, normal:=1.0) -> StandardMaterial3D:
	var id:="%s_%.2f_%s_%.2f"%[key,meters,tint.to_html(),normal]
	if _mats.has(id): return _mats[id]
	var m:=StandardMaterial3D.new()
	var dir:=M+("" if key.begins_with("gen/") else "mats/")
	m.albedo_texture=load(dir+"%s_albedo.jpg"%key)
	m.albedo_color=tint
	m.normal_enabled=true
	if ResourceLoader.exists(dir+"%s_normal.jpg"%key):
		m.normal_texture=load(dir+"%s_normal.jpg"%key)
		m.normal_scale=normal
	else: m.normal_enabled=false
	if ResourceLoader.exists(dir+"%s_rough.jpg"%key): m.roughness_texture=load(dir+"%s_rough.jpg"%key)
	else: m.roughness=0.9
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
	env.sdfgi_cascades=4
	env.sdfgi_min_cell_size=0.1
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
	var paint:=mat("gen/paint_green",1.7,Color(1.04,0.97,0.9))
	var ceiling:=mat("gen/plaster",1.9)
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
	glass.albedo_texture=load(M+"gen/glass_dirty.png")
	glass.albedo_color=Color(1,1,1,0.9)
	glass.roughness=0.15
	glass.metallic_specular=0.8
	glass.cull_mode=BaseMaterial3D.CULL_DISABLED
	for half in [[x0+0.06,(x0+x1)*0.5-0.025],[(x0+x1)*0.5+0.025,x1-0.06]]:
		var g:=MeshInstance3D.new()
		var q:=QuadMesh.new()
		q.size=Vector2(half[1]-half[0],WIN.size.y-0.12)
		g.mesh=q
		g.material_override=glass
		g.position=Vector3((half[0]+half[1])*0.5,(y0+y1)*0.5,zf)
		g.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)

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
	# dveře pokoje 7 (dvoukřídlé plechové s okénky) – otevírají se do chodby
	wing.double_door(DOOR.get_center().x,D+T*0.5,180.0,"closed","pokoj 7",-1.0)
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
	var bed:=_place("bed",0.0095,-90.0,Vector3(0,0,-0.8),{"x_min":-W+0.04})
	swap_material(bed,"lagen",mat("gen/blanket",0.55))
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
	interact(_body_for(radio,Vector3(0.5,0.4,0.4)),"[E] Rádio","radio")
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
	interact(_body_for(tv),"[E] Televize","","Televize zatím nehraje. Tady budou tvoje statistiky.")
	# gauč u východní zdi, čelem k televizi přes celý pokoj
	_place("sofa",0.72,-90.0,Vector3(0,0,0.1),{"x_max":W-0.04})
	# skříňka v jihovýchodním rohu (oblek)
	var locker:=_place("res://assets/props/locker/source/locker.glb",1.0,180.0,Vector3(0,0,0),{"x_max":W-0.03,"z_max":D-0.03})
	interact(locker.get_meta("body"),"[E] Skříňka","","Skříňka s oblekem. Skiny přijdou sem.")
	# umyvadlo u jižní zdi a zrcadlo nad ním
	# mezi vypínačem u dveří a skříňkou, s mezerou od skříňky
	var la:=_aabb(locker)
	var sink:=_place("sink",0.0095,-90.0,Vector3(0,0,0),{"z_max":D-0.02,"x_max":la.position.x-0.15})
	_sink_pos=_aabb(sink).get_center()
	var sa:=_aabb(sink)
	box(Vector3(0.5,0.62,0.03),Vector3(sa.get_center().x,sa.end.y+0.5,D-0.03),flat(Color(0.18,0.17,0.15),0.5),false)
	_build_mirror(Vector3(sa.get_center().x,sa.end.y+0.5,D-0.05),Vector3(0,0,-1),Vector2(0.44,0.56))

## Komponenty z scripts/lobby/ (v editoru se dají posouvat a nastavovat v inspektoru)
func interact(body: StaticBody3D, prompt: String, action:="", message:="") -> StaticBody3D:
	body.set_script(load("res://scripts/lobby/interact.gd"))
	body.prompt=prompt
	body.action=action
	body.message=message
	body.set_meta("prompt",prompt)
	return body

func swap_material(holder: Node3D, surface: String, m: Material) -> void:
	holder.set_script(load("res://scripts/lobby/material_swap.gd"))
	holder.surface_name=surface
	holder.material=m

func _build_mirror(center: Vector3, normal: Vector3, size: Vector2) -> void:
	var mr:=Node3D.new()
	mr.name="Zrcadlo"
	mr.set_script(load("res://scripts/lobby/mirror.gd"))
	add_child(mr)
	mr.global_transform=Transform3D(Basis.looking_at(-normal),center)
	mr.size=size

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
	wing.lamp(Vector3(0.2,H,0.0),1.25,true,"rare",false,true)

# ------------------------------------------------------------------ špína, plíseň, praskliny

func _decal(file: String, pos: Vector3, normal: Vector3, size: Vector2, rot:=0.0, alpha:=1.0) -> void:
	_decal_file("decals/%s.png"%file,pos,normal,size,rot,alpha)

func _decal_file(file: String, pos: Vector3, normal: Vector3, size: Vector2, rot:=0.0, alpha:=1.0) -> void:
	var d:=Decal.new()
	d.texture_albedo=load(M+file)
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
	# velké nepravidelné zašpinění stěn (rozbije opakování textury)
	var g:=[[Vector3(-1.6,2.3,-D),Vector3(0,0,1),Vector2(2.6,2.2)],[Vector3(1.6,2.5,-D),Vector3(0,0,1),Vector2(2.2,1.8)],
		[Vector3(-W,2.2,0.4),Vector3(1,0,0),Vector2(3.0,2.2)],[Vector3(W,2.4,-0.8),Vector3(-1,0,0),Vector2(2.8,2.0)],
		[Vector3(W,1.9,1.2),Vector3(-1,0,0),Vector2(1.6,2.0)],[Vector3(1.2,2.4,D),Vector3(0,0,-1),Vector2(2.6,2.0)],
		[Vector3(-1.4,2.85,D),Vector3(0,0,-1),Vector2(2.0,1.2)],[Vector3(0.0,H,-0.5),Vector3(0,-1,0),Vector2(3.0,2.6)]]
	for i in g.size(): _decal_file("gen/grunge_wall.png",g[i][0],g[i][1],g[i][2],float(i)*1.7,0.4 if i==g.size()-1 else 0.85)
	# špína u podlahy podél všech zdí a v rozích
	for w in [[Vector3(0,0.13,-D),Vector3(0,0,1),5.0],[Vector3(0,0.13,D),Vector3(0,0,-1),5.0],
			[Vector3(-W,0.13,0),Vector3(1,0,0),3.8],[Vector3(W,0.13,0),Vector3(-1,0,0),3.8]]:
		_decal_file("gen/dirt_floor_strip.png",w[0],w[1],Vector2(w[2],0.3),0.0,0.9)
	for c in [Vector2(-W,-D),Vector2(W,-D),Vector2(-W,D),Vector2(W,D)]:
		var n:=Vector3(-signf(c.x),0,-signf(c.y)).normalized()
		_decal_file("gen/dirt_corner.png",Vector3(c.x,H*0.5,c.y),n,Vector2(0.35,H),0.0,0.9)

## Plochý obdélník (papír, zrcadlo) natočený lícem ve směru `normal`, `roll` = pootočení v rovině.
func _quad(size: Vector2, pos: Vector3, normal: Vector3, m: Material, roll:=0.0) -> MeshInstance3D:
	var mi:=MeshInstance3D.new()
	var q:=QuadMesh.new()
	q.size=size
	mi.mesh=q
	mi.material_override=m
	add_child(mi)
	var z:=normal.normalized()
	var y:=Vector3.UP if absf(z.dot(Vector3.UP))<0.95 else Vector3.FORWARD
	var x:=y.cross(z).normalized()
	y=z.cross(x)
	mi.global_transform=Transform3D(Basis(x,y,z).rotated(z,roll),pos)
	return mi

func _paper(file: String, w: float, pos: Vector3, normal: Vector3, roll:=0.0) -> MeshInstance3D:
	var t: Texture2D=load(M+"gen/"+file)
	var m:=StandardMaterial3D.new()
	m.albedo_texture=t
	m.roughness=0.85
	return _quad(Vector2(w,w*float(t.get_height())/float(t.get_width())),pos,normal,m,roll)

func _build_papers() -> void:
	# cedulka na dveřích (zevnitř) a dobové papíry na zdech
	var door: Node3D=get_node_or_null("door")
	var dz:=_aabb(door).position.z if door else D
	_paper("sign_quarantine.jpg",0.42,Vector3(DOOR.get_center().x-0.38,1.28,dz-0.004),Vector3(0,0,-1))
	_paper("calendar_1993.jpg",0.3,Vector3(0.5,1.82,-D+0.006),Vector3(0,0,1),0.02)
	_paper("poster_civil_defense.jpg",0.5,Vector3(W-0.006,1.95,0.1),Vector3(-1,0,0),-0.01)
	# nástěnka: mapka areálu a poznámky na připínáčcích
	var cz:=-D+0.046
	var pin:=flat(Color(0.7,0.08,0.06),0.3)
	var items:=[["map_site.jpg",0.36,Vector3(1.15,1.84,cz),0.03],["note_1.jpg",0.2,Vector3(1.6,1.88,cz),-0.06],
		["note_2.jpg",0.19,Vector3(1.55,1.6,cz),0.05],["note_3.jpg",0.18,Vector3(1.02,1.57,cz),-0.03]]
	for it in items:
		var p: MeshInstance3D=_paper(it[0],it[1],it[2],Vector3(0,0,1),it[3])
		var top: Vector3=p.global_transform*Vector3(0,(p.mesh as QuadMesh).size.y*0.42,0.004)
		var pm:=MeshInstance3D.new()
		var sp:=SphereMesh.new()
		sp.radius=0.008
		sp.height=0.016
		pm.mesh=sp
		pm.material_override=pin
		pm.position=top
		add_child(pm)

## Prach ve vzduchu: měkké kulaté smítko (ne pixel), různě velké, pomalu se vznáší a točí.
## Je osvětlené – v paprsku slunce září, ve stínu skoro zmizí; u kamery se rozplyne.
func _build_dust() -> void:
	var p:=GPUParticles3D.new()
	p.amount=700
	p.lifetime=16.0
	p.preprocess=16.0
	p.fixed_fps=30
	p.visibility_aabb=AABB(Vector3(-W,-H*0.5,-D),Vector3(W*2,H,D*2))
	p.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm:=ParticleProcessMaterial.new()
	pm.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents=Vector3(W-0.15,H*0.5-0.1,D-0.15)
	pm.gravity=Vector3(0,-0.003,0)
	pm.direction=Vector3(0,1,0)
	pm.spread=180.0
	pm.initial_velocity_min=0.0
	pm.initial_velocity_max=0.025
	pm.damping_min=0.01
	pm.damping_max=0.03
	pm.turbulence_enabled=true
	pm.turbulence_noise_strength=0.6
	pm.turbulence_noise_scale=1.6
	pm.turbulence_noise_speed_random=0.3
	pm.turbulence_influence_min=0.008
	pm.turbulence_influence_max=0.03
	pm.angle_min=0.0
	pm.angle_max=360.0
	pm.angular_velocity_min=-20.0
	pm.angular_velocity_max=20.0
	pm.scale_min=0.35
	pm.scale_max=1.6
	# rozsvítit a zhasnout plynule (žádné vyskakování)
	var fade:=Gradient.new()
	fade.set_color(0,Color(1,1,1,0))
	fade.set_color(1,Color(1,1,1,0))
	fade.add_point(0.15,Color(1,1,1,1))
	fade.add_point(0.85,Color(1,1,1,1))
	var gt:=GradientTexture1D.new()
	gt.gradient=fade
	pm.color_ramp=gt
	p.process_material=pm
	var q:=QuadMesh.new()
	q.size=Vector2(0.007,0.007)
	var dm:=StandardMaterial3D.new()
	dm.billboard_mode=BaseMaterial3D.BILLBOARD_PARTICLES
	dm.billboard_keep_scale=true
	dm.albedo_texture=load(M+"gen/dust_mote.png")
	dm.albedo_color=Color(1.0,0.96,0.88,0.55)
	dm.vertex_color_use_as_albedo=true
	dm.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode=BaseMaterial3D.SHADING_MODE_PER_PIXEL
	dm.diffuse_mode=BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	dm.backlight_enabled=true
	dm.backlight=Color(0.8,0.75,0.65)
	dm.roughness=1.0
	dm.distance_fade_mode=BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	dm.distance_fade_min_distance=0.15
	dm.distance_fade_max_distance=0.5
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
	a.autoplay=loop
	add_child(a)
	if loop: a.play()
	return a

func _build_sound() -> void:
	_snd("res://audio/amb_room.wav",Vector3(0,1.5,0),-14.0,true,10.0)

## Zvuky, které hraje kód za běhu: rádio u modelu rádia, kapky z umyvadla, kroky.
func _build_runtime_sound() -> void:
	var radio_body: Node3D=null
	for n in get_tree().get_nodes_in_group("lobby_radio"): radio_body=n
	if radio_body==null:
		for b in map.find_children("*","StaticBody3D",true,false):
			if b.get("action")=="radio": radio_body=b
	_radio=_snd("res://audio/radio/radio_check_c1.wav",radio_body.global_position if radio_body else Vector3(1.05,0.95,-1.62),-4.0,false,3.0)
	_radio.autoplay=false
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
	var sink: Node3D=map.find_child("sink",true,false)
	_sink_pos=_aabb(sink).get_center() if sink else Vector3(0.3,0.9,1.7)
	for i in range(1,7): _steps.append(load("res://audio/step_tile_%d.wav"%i))

# ------------------------------------------------------------------ hráč

## Herní postava (scripts/player.gd): celé tělo v obleku, vlastní ruce a nohy v pohledu,
## v zrcadle celá postava. Zbraň v pokoji není, ruce jsou volné.
func _build_player() -> void:
	if OS.get_environment("LOBBY_NOPLAYER")=="1":      # náhledy v softwarovém renderu: jen kamera
		cam=Camera3D.new()
		cam.fov=float(settings.fov)
		add_child(cam)
		cam.current=true
		return
	var P:=preload("res://scripts/player.gd")
	preload("res://scripts/weapon_rig.gd").skip_gun_models=true
	P.water_at=func(_p: Vector3) -> float: return -50.0     # v pokoji žádná voda
	player=P.new()
	add_child(player)
	player.mouse_scale=float(settings.mouse)
	player.base_fov=float(settings.fov)
	player.bob_scale=float(settings.bob)
	var sp: Node3D=map.find_child("SpawnHrace",true,false)
	if sp: player.teleport(sp.global_position,sp.global_rotation.y,deg_to_rad(4.0))
	else: player.teleport(Vector3(-1.0,0.02,1.3),deg_to_rad(-25.0),deg_to_rad(4.0))
	cam=player.camera
	# zbraňový skript v pokoji nepotřebujeme (střelba, přebíjení, házení)
	for f in ["set_process","set_physics_process","set_process_input","set_process_unhandled_input"]:
		player.weapon.call(f,false)
	if look.size()==7 and player.body.has_method("apply_look"):
		player.body.call_deferred("apply_look",look)
	player.footstep.connect(_on_footstep)
	player.interact_requested.connect(_on_interact)
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	# po přepnutí z menu ještě jednou, až scéna doběhne (menu mohlo myš uvolnit)
	get_tree().create_timer(0.2).timeout.connect(func(): Input.mouse_mode=Input.MOUSE_MODE_CAPTURED)

func _exit_tree() -> void:
	preload("res://scripts/weapon_rig.gd").skip_gun_models=false
	# statická hladina hráče nesmí ukazovat na lambdu zrušeného pokoje (pád při ukončení)
	preload("res://scripts/player.gd").water_at=Callable()

func _on_footstep(kind: String, strength: float) -> void:
	var a:=AudioStreamPlayer.new()
	a.stream=_steps.pick_random()
	a.volume_db=-17.0+linear_to_db(maxf(strength,0.1))*0.5
	a.pitch_scale=randf_range(0.92,1.06)
	add_child(a)
	a.play()
	a.finished.connect(a.queue_free)

func _on_interact() -> void:
	var hit:=_look_target()
	if hit and hit.has_meta("use"): (hit.get_meta("use") as Callable).call()
	elif hit and hit.has_method("use"): hit.use()

func _on_action(action: String, node: Node) -> void:
	if action=="radio": _on_radio()

func say(t: String) -> void: _say(t)

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
	# zachycená myš stojí uprostřed okna – tečka nesmí brát pohyb myši pro sebe
	dot.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_prompt.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_toast.mouse_filter=Control.MOUSE_FILTER_IGNORE
	cl.add_child(dot)
	_say("Karanténa. Pohyb WASD, přikrčení C, interakce E, Esc zpět do menu.")

func _say(t: String) -> void:
	_toast.text=t
	_toast_t=4.0

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_ESCAPE:
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://main.tscn")

func _look_target() -> Object:
	if cam==null: return null
	var from:=cam.global_position
	var q:=PhysicsRayQueryParameters3D.create(from,from-cam.global_basis.z*2.2)
	q.exclude=[player.get_rid()]
	var r:=get_world_3d().direct_space_state.intersect_ray(q)
	return r.get("collider") if r else null

func _physics_process(_dt: float) -> void:
	if player==null: return
	var t:=_look_target()
	_prompt.text=String(t.get_meta("prompt")) if t and t.has_meta("prompt") else ""

func _process(dt: float) -> void:
	if bake: return
	_toast_t-=dt
	if _toast: _toast.modulate.a=clampf(_toast_t,0.0,1.0)
	_update_radio(dt)
	_drip_t-=dt
	if _drip_t<=0.0:
		_drip_t=randf_range(5.0,14.0)
		var d:=_snd("res://audio/drip_%d.wav"%randi_range(2,6),_sink_pos,-20.0,false,1.5)
		d.play()
		d.finished.connect(d.queue_free)

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
