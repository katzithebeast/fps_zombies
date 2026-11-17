extends Node
## Režim přežití po vzoru starých CoD Zombies: kola, body, zdraví hráče, bonusy, HUD a navigační síť úrovně.
const ZombieScript:=preload("res://scripts/zombie.gd")
const Props:=preload("res://scripts/props.gd")
const Interactables:=preload("res://scripts/interactables.gd")
# Bedna, skříňka, munice a pracovní stůl: [pozice, natočení].
const PLACES:={
	"crate":[[Vector3(10.6,0.5,5.2),0.0]],
	"locker":[[Vector3(7.15,0.5,8.72),0.0],[Vector3(3.62,0.5,8.72),0.0],[Vector3(4.84,0.5,8.72),0.0],[Vector3(9.0,0.5,8.72),0.0],[Vector3(-9.0,-0.35,-58.2),PI]],
	# Brány do východního křídla: [pozice, natočení, cena, šířka, výška] jako v CoD.
	"gate":[[Vector3(12.3,-0.35,-14.0),PI/2,750,2.0,2.95],[Vector3(20.3,-0.35,-14.0),PI/2,1250,2.0,2.95],[Vector3(33.5,-0.35,-1.7),0.0,1000,3.0,2.95],
		[Vector3(0.0,-0.35,-26.3),0.0,1000,2.4,2.95],[Vector3(-20.2,-0.35,-22.5),0.0,750,2.0,2.95],[Vector3(25.0,-0.35,-34.3),0.0,750,2.0,2.95]],
	"ammo":[[Vector3(-19.0,-0.35,-12.0),0.0]],
	"bench":[[Vector3(-14.3,-0.35,-18.25),0.0]],
}
var stations: Node3D
var _zone_spawns: Array=[]
# Místa, odkud chodí zombie v odemčených částech mapy (podle pořadí bran v PLACES).
const ZONE_SPAWNS:=[
	[Vector3(19.2,-0.35,-14.0)],
	[Vector3(22.0,-0.35,-32.5),Vector3(45.0,-0.35,-32.5),Vector3(45.0,-0.35,-3.5),Vector3(22.0,-0.35,-3.5),Vector3(33.5,-0.35,-33.0),
		Vector3(21.2,-0.35,-24.0),Vector3(46.0,-0.35,-18.0),Vector3(40.0,-0.35,-2.6)],
	[Vector3(25.0,-0.35,-0.5),Vector3(41.0,-0.35,-0.5),Vector3(25.0,1.45,16.5),Vector3(41.0,1.45,16.5),Vector3(51.0,2.45,13.0),
		Vector3(47.0,-0.35,39.0),Vector3(61.0,-0.35,39.0),Vector3(61.0,-0.35,25.0),Vector3(39.0,-0.35,27.4),Vector3(39.0,1.45,18.3),
		Vector3(24.6,1.45,13.0),Vector3(41.4,1.45,12.0),Vector3(54.0,-0.35,39.4),Vector3(50.6,1.2,19.0)],
	[Vector3(-10.8,-0.35,-45.0),Vector3(10.8,-0.35,-45.0),Vector3(0.0,-0.35,-45.2),Vector3(-8.5,-0.35,-57.5),Vector3(2.5,-0.35,-48.0),
		Vector3(-11.8,-0.35,-30.0),Vector3(11.8,-0.35,-33.0),Vector3(6.0,-0.35,-45.4),Vector3(-6.0,-0.35,-45.4)],
	[Vector3(-30.2,-0.35,-25.8),Vector3(-30.2,-0.35,-55.8),Vector3(-20.2,-0.35,-47.8),Vector3(-14.2,-0.35,-29.8),Vector3(-24.2,-0.35,-51.8),
		Vector3(-28.2,-0.35,-35.8),Vector3(-16.2,-0.35,-43.8),Vector3(-18.2,-0.35,-57.8)],
	[Vector3(15.0,-0.35,-55.0),Vector3(29.0,-0.35,-36.0),Vector3(16.0,4.15,-37.0),Vector3(8.9,-0.35,-52.0),Vector3(14.4,-0.35,-46.0),Vector3(26.0,-0.35,-55.4)],
	# Nádrž pod Síní anděla (mříž z hlavní linky secretů).
	[Vector3(25.0,-14.4,-59.0),Vector3(43.0,-14.4,-59.0),Vector3(25.0,-14.4,-43.0),Vector3(43.0,-14.4,-43.0),Vector3(33.5,-14.4,-36.0),Vector3(30.0,-14.4,-14.0)],
]

func zone_opened(index: int) -> void:
	if index>=0 and index<ZONE_SPAWNS.size(): _zone_spawns.append_array(ZONE_SPAWNS[index])
var _nav_region: RID
const POOL:=Rect2(-4.6,-18.6,9.2,9.2)                 # kde se zombie vynořují z hlubokého bazénu
const WALK_SPAWNS:=[Vector3(-22.5,-0.35,-21.0),Vector3(10.6,-0.35,-24.6),Vector3(-10.6,-0.35,-24.6),Vector3(10.6,-0.35,-3.4),
	Vector3(-10.6,-0.35,-3.4),Vector3(-10.8,-0.35,-9.0),Vector3(-4.5,-0.35,-25.0),Vector3(10.4,0.5,8.0),Vector3(-21.0,-0.35,-17.5)]
# Galerie pod stropem: [místo, směr k hraně]. Hráč se tam nedostane.
const LEDGES:=[[Vector3(11.4,4.2,-8.0),Vector3(-1,0,0)],[Vector3(11.4,4.2,-14.0),Vector3(-1,0,0)],[Vector3(11.4,4.2,-20.0),Vector3(-1,0,0)],
	[Vector3(-5.0,4.2,-25.4),Vector3(0,0,1)],[Vector3(0.0,4.2,-25.4),Vector3(0,0,1)],[Vector3(5.0,4.2,-25.4),Vector3(0,0,1)]]
const ROUND_SIZES:=[8,12,17,23,30]
const MAX_ALIVE:=24
const RESPAWN_DIST:=26.0      # zombie, které hráč nechal daleko za sebou, se přesunou blíž (jako v CoD)
const RESPAWN_TIME:=6.0
const RED:=Color(0.7,0.06,0.03)
const GOLD:=Color(1.0,0.86,0.42)
var main: Node3D
var player: Player
var active:=false
var state:="off"             # off | wait | round | dead
var round_now:=0
var points:=0
var kills:=0
var headshots:=0
var health:=100.0
var _timer:=0.0
var _to_spawn:=0
var _spawn_timer:=0.0
var _stall:=0.0
var _regen_wait:=0.0
var _zombies: Array=[]
var _powerups: Array=[]
var debug_god:=false       # testování: hráč nedostává zranění
var debug_hold:=false      # testování: kola stojí, nic nespawnuje
var _drops:=0
var _ammo_clock:=60.0
var _insta_left:=0.0
var _dead_time:=0.0
var _pulse:=0.0
var _muffle:=0.0
var _damage_marks: Array=[]
var _damage_draw: Control
var _muffle_fx: AudioEffectLowPassFilter
var _time:=0.0
var _layer: CanvasLayer
var _root: Control
var _font: Font
var _round_label: Label
var _points_label: Label
var _shown_points:=-1
var _points_fade:=0.0
var _banner: Label
var _sub: Label
var _status: Label
var _hint: Label
var _popups: Array=[]
var _popup_next:=0
var _vignette: ColorRect
var _vignette_material: ShaderMaterial
var _splats: Array=[]
var _splat_next:=0
var _cross: Control
var _over: ColorRect
var _over_title: Label
var _over_text: Label
var _heart: AudioStreamPlayer
var _breath: AudioStreamPlayer
var _banner_tween: Tween
var _sub_tween: Tween

func _ready() -> void:
	var system:=SystemFont.new()
	system.font_names=PackedStringArray(["Impact","Haettenschweiler","Arial Black","DejaVu Sans"])
	system.font_weight=700
	_font=system
	_build_hud()
	_heart=AudioStreamPlayer.new()
	if ResourceLoader.exists("res://audio/heartbeat.wav"):
		var beat: AudioStreamWAV=load("res://audio/heartbeat.wav")
		beat.loop_mode=AudioStreamWAV.LOOP_FORWARD
		beat.loop_begin=0
		beat.loop_end=int(beat.get_length()*beat.mix_rate)
		_heart.stream=beat
	_heart.volume_db=-30.0
	add_child(_heart)
	# Zadýchání: smyčka, hlasitější čím hůř na tom hráč je.
	_breath=AudioStreamPlayer.new()
	if ResourceLoader.exists("res://audio/player_breath.wav"):
		var br: AudioStreamWAV=load("res://audio/player_breath.wav")
		br.loop_mode=AudioStreamWAV.LOOP_FORWARD
		br.loop_begin=0
		br.loop_end=int(br.get_length()*br.mix_rate)
		_breath.stream=br
	_breath.volume_db=-60.0
	add_child(_breath)
	_make_stations.call_deferred()
	_bake_navigation.call_deferred()

# Mrtvoly od začátku hry: některé jen leží (kulisa), jiné vstanou, když jde hráč kolem.
const CORPSES:=[Vector3(-8.0,-0.35,-3.6),Vector3(8.5,-0.35,-24.0),Vector3(-10.0,-0.35,-19.0),Vector3(10.0,0.5,3.0),Vector3(-17.0,-0.35,-17.0),
	Vector3(22.0,-0.35,-30.0),Vector3(44.0,-0.35,-6.0),Vector3(40.0,1.45,10.6),Vector3(5.0,-0.35,-40.0),Vector3(-1.0,-0.35,-48.2),
	Vector3(-30.2,-0.35,-41.8),Vector3(17.0,-0.35,-50.0),Vector3(48.0,-0.35,30.0),Vector3(-20.2,-0.35,-33.8)]
const SLEEPERS:=[Vector3(-6.0,-0.35,-23.8),Vector3(17.5,-0.35,-13.6),Vector3(40.0,-0.35,-31.0),Vector3(-6.0,-0.35,-30.4),Vector3(34.0,-0.35,1.0),Vector3(-24.2,-0.35,-49.8)]

var _holes:={}       # spawn -> upravená pozice před dírou ve zdi

func _make_holes() -> void:
	# U každého místa, odkud chodí zombie, vyrazit do nejbližší zdi tmavou díru (rozbité obklady, tma).
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space:=main.get_world_3d().direct_space_state
	var blood: Node3D=load("res://scripts/blood_dressing.gd").new()
	main.add_child(blood)
	var all:=WALK_SPAWNS.duplicate()
	for zone in ZONE_SPAWNS: all.append_array(zone)
	for spot in all:
		var best:={}
		var best_d:=3.2
		for k in 8:
			var dir:=Vector3.FORWARD.rotated(Vector3.UP,TAU*k/8.0)
			var from: Vector3=spot+Vector3.UP*0.8
			var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(from,from+dir*3.2,1))
			# Jen opravdové zdi úrovně (ne brány, nábytek ani předměty).
			if hit.is_empty() or hit.collider!=main.world_body or absf((hit.normal as Vector3).y)>0.2: continue
			var d: float=from.distance_to(hit.position)
			if d<best_d:
				best_d=d
				best=hit
		if best.is_empty(): continue
		var n: Vector3=best.normal
		var base: Vector3=Vector3(best.position.x,spot.y,best.position.z)
		# Díra musí sedět na souvislé zdi: nesmí přesahovat do dveří, průchodu ani za roh.
		# Když na místě nesedí, zkusí se posunout podél zdi.
		var placed:=false
		for shift in [0.0,0.5,-0.5,1.0,-1.0,1.5,-1.5]:
			var tangent:=n.cross(Vector3.UP).normalized()
			var cand: Vector3=base+tangent*float(shift)
			if _wall_fits(space,cand,n):
				base=cand
				placed=true
				break
		if not placed: continue
		_breach(base,n,blood)
		_holes[spot]=base+n*0.55

func _wall_fits(space: PhysicsDirectSpaceState3D, base: Vector3, n: Vector3) -> bool:
	# Paprsky proti zdi v mřížce přes celou plochu díry (±0,8 m do stran, do výšky 1,9 m) musí
	# všechny narazit na tutéž rovinu zdi úrovně.
	var tangent:=n.cross(Vector3.UP).normalized()
	for side in [-0.8,-0.4,0.0,0.4,0.8]:
		for h in [0.15,0.9,1.7]:
			var target: Vector3=base+tangent*side+Vector3.UP*h
			var from: Vector3=target+n*0.6
			var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(from,target-n*0.3,1))
			if hit.is_empty() or hit.collider!=main.world_body: return false
			if (hit.normal as Vector3).dot(n)<0.95: return false
			if absf((hit.position-base).dot(n))>0.06: return false
	# A před dírou musí být volno (suť a krev nesmí ležet v průchodu za rohem).
	var front:=space.intersect_ray(PhysicsRayQueryParameters3D.create(base+n*0.1+Vector3.UP*0.8,base+n*1.2+Vector3.UP*0.8,1))
	return front.is_empty()

func _breach(base: Vector3, n: Vector3, blood: Node3D) -> void:
	# Proražená díra ve zdi: zubatý tmavý otvor s rudým šerem uvnitř, ulomené kachle po okraji,
	# trčící dráty, suť na zemi a krvavá stopa, jak se tudy něco plazilo ven.
	var root:=Node3D.new()
	main.add_child(root)
	root.global_transform=Transform3D(Basis.looking_at(-n,Vector3.UP),base+n*0.012)
	var rng:=RandomNumberGenerator.new()
	rng.seed=int(base.x*131.0+base.z*17.0)
	var points:=PackedVector2Array()
	var count:=20
	for i in count:
		var a:=PI+PI*float(i)/(count-1)      # horní oblouk zleva doprava
		var r:=rng.randf_range(0.78,1.08)
		points.append(Vector2(cos(a)*0.58*r,0.82+sin(-a)*0.82*r))
	points.append(Vector2(0.62,0.0))
	points.append(Vector2(-0.62,0.0))
	# Otvor: vějíř trojúhelníků, uprostřed tmavě rudé šero, k okrajům čerň.
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center:=Vector3(0,0.7,0)
	for i in points.size():
		var p0:=points[i]
		var p1:=points[(i+1)%points.size()]
		st.set_color(Color(0.09,0.005,0.0))
		st.add_vertex(center)
		st.set_color(Color(0,0,0))
		st.add_vertex(Vector3(p0.x,p0.y,0))
		st.set_color(Color(0,0,0))
		st.add_vertex(Vector3(p1.x,p1.y,0))
	var hole:=MeshInstance3D.new()
	hole.mesh=st.commit()
	var dark:=StandardMaterial3D.new()
	dark.vertex_color_use_as_albedo=true
	dark.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.cull_mode=BaseMaterial3D.CULL_DISABLED
	hole.material_override=dark
	hole.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(hole)
	var rim_tint:=Color(0.8,0.82,0.8).darkened(rng.randf_range(0.05,0.3))
	# Ulomené kachle a omítka kolem okraje (oblouk i boky).
	var rim:=Array(points.slice(0,count))
	for k in 5:
		rim.append(Vector2(-0.6,0.8*k/5.0))
		rim.append(Vector2(0.6,0.8*k/5.0))
	for i in rim.size():
		var p: Vector2=rim[i]
		for k in 2:
			var shard:=MeshInstance3D.new()
			var bm:=BoxMesh.new()
			bm.size=Vector3(rng.randf_range(0.07,0.17),rng.randf_range(0.05,0.14),rng.randf_range(0.03,0.07))
			shard.mesh=bm
			shard.material_override=main.tile_mat
			shard.set_instance_shader_parameter("tint",rim_tint)
			shard.set_instance_shader_parameter("tile_scale",3.0)
			var out:=p+(p-Vector2(0,0.7)).normalized()*rng.randf_range(0.02,0.1)
			shard.position=Vector3(out.x,maxf(out.y,0.04),rng.randf_range(0.0,0.05))
			shard.rotation=Vector3(rng.randf_range(-0.5,0.5),rng.randf_range(-0.5,0.5),rng.randf_range(-1.0,1.0))
			root.add_child(shard)
	# Trčící rezavé dráty.
	var rust: Material=main._surface("rust")
	for i in 4:
		var p:=points[rng.randi_range(2,count-3)]
		var bar:=MeshInstance3D.new()
		var cyl:=CylinderMesh.new()
		cyl.top_radius=0.008
		cyl.bottom_radius=0.008
		cyl.height=rng.randf_range(0.25,0.5)
		cyl.radial_segments=6
		bar.mesh=cyl
		bar.material_override=rust
		bar.position=Vector3(p.x*0.9,p.y*0.95,0.06)
		bar.rotation=Vector3(rng.randf_range(0.6,1.3),0,atan2(-p.x,p.y-0.7)+rng.randf_range(-0.4,0.4))
		root.add_child(bar)
	# Suť na zemi před dírou.
	for i in 9:
		var chunk:=MeshInstance3D.new()
		var cm:=BoxMesh.new()
		var size:=rng.randf_range(0.05,0.2)
		cm.size=Vector3(size,size*rng.randf_range(0.4,0.9),size*rng.randf_range(0.6,1.2))
		chunk.mesh=cm
		chunk.material_override=main.tile_mat
		chunk.set_instance_shader_parameter("tint",rim_tint)
		chunk.set_instance_shader_parameter("tile_scale",3.0)
		chunk.position=Vector3(rng.randf_range(-0.7,0.7),size*0.25,rng.randf_range(0.1,0.9))
		chunk.rotation=Vector3(rng.randf_range(-0.4,0.4),rng.randf()*TAU,rng.randf_range(-0.4,0.4))
		root.add_child(chunk)
	Props.merge(root)
	for part in root.find_children("*","MeshInstance3D",true,false): (part as MeshInstance3D).visibility_range_end=28.0
	# Krvavá stopa ven z díry a otisky dlaní na okraji.
	var floor_at:=base+n*0.8+Vector3.UP*0.01
	blood.make_decal("smears_07_curved_drag" if rng.randf()<0.5 else "handprints_06_long_drag",floor_at,Vector3.UP,rng.randf_range(0.9,1.4),atan2(n.x,n.z)+PI/2,0.9)
	var edge:=points[rng.randi_range(3,count-4)]
	blood.make_decal("handprints_0%d_full_palm_0%d" % [[1,2][rng.randi()%2],[1,2][rng.randi()%2]] if false else "handprints_01_full_palm_01",root.global_transform*Vector3(edge.x*1.1,edge.y*1.05,0),n,0.3,rng.randf_range(-0.6,0.6),0.95)

func _extra_corpses() -> Array:
	# Další mrtvoly po celé mapě: v každé místnosti podle plochy (1–4), na suché podlaze,
	# ne u startu hráče a ne těsně u sebe.
	var space:=main.get_world_3d().direct_space_state
	var rng:=RandomNumberGenerator.new()
	rng.seed=91
	var out:=[]
	for r in main.MAP_RECTS:
		var rect: Rect2=r
		var want:=clampi(int(rect.get_area()/140.0),1,4)
		var tries:=0
		var made:=0
		while made<want and tries<40:
			tries+=1
			var p:=Vector2(rng.randf_range(rect.position.x+0.8,rect.end.x-0.8),rng.randf_range(rect.position.y+0.8,rect.end.y-0.8))
			var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x,2.5,p.y),Vector3(p.x,-4.0,p.y),1))   # pod stropem, ne na střeše
			if hit.is_empty() or (hit.normal as Vector3).y<0.85 or hit.collider!=main.world_body: continue
			var spot: Vector3=hit.position
			if spot.y<main.WATER_Y-0.1: continue
			if spot.distance_to(main.SPAWN)<6.0: continue
			var clash:=false
			for q in out+CORPSES+SLEEPERS:
				if (q as Vector3).distance_to(spot)<2.2: clash=true
			if clash: continue
			# Kolem musí být místo, aby tělo nespadlo do zdi.
			var room:=true
			for k in 6:
				var d:=Vector3.FORWARD.rotated(Vector3.UP,TAU*k/6.0)
				if not space.intersect_ray(PhysicsRayQueryParameters3D.create(spot+Vector3.UP*0.4,spot+Vector3.UP*0.4+d*1.0,1)).is_empty(): room=false
			if not room: continue
			out.append(spot)
			made+=1
	return out

func _place_bodies() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var extra:=_extra_corpses()
	var blood: Node3D=null
	for c in main.get_children():
		if c.has_method("make_decal"): blood=c
	for spot in CORPSES+SLEEPERS+extra:
		var zombie:=_make(1,["classic","cop","girl","classic","cop","girl","ch10","parasite"].pick_random())
		_zombies.erase(zombie)          # nepočítají se do kola a restart je nesmaže
		zombie.position=spot
		zombie.rotation.y=randf()*TAU
		zombie.target=main.player
		main.add_child(zombie)
		if spot in CORPSES or spot in extra:
			zombie.keep_corpse=true
			# Kaluž krve pod tělem.
			if blood: blood.make_decal("smears_06_blood_pool",spot,Vector3.UP,randf_range(1.4,2.4),randf()*TAU,0.85)
			zombie.kill.call_deferred(spot+Vector3.UP,Vector3(randf_range(-1,1),0,randf_range(-1,1)),zombie._ids.get("Spine2",0))
		else:
			zombie.lie_down.call_deferred()
		await get_tree().physics_frame

func _make_stations() -> void:
	stations=Interactables.new()
	main.add_child(stations)
	stations.setup(self,main,PLACES)
	if main.get("quest"): main.quest.stations_ready(stations)
	_place_bodies.call_deferred()
	_make_holes.call_deferred()
	var toys: Node3D=load("res://scripts/pool_toys.gd").new()
	main.add_child(toys)
	toys.setup(main)

var _nav_static: NavigationMeshSourceGeometryData3D   # geometrie úrovně bez bran – parsuje se jen jednou
var _nav_baking:=false
var _nav_again:=false

func _nav_template() -> NavigationMesh:
	var mesh:=NavigationMesh.new()
	mesh.cell_size=0.2
	mesh.cell_height=0.1
	mesh.agent_radius=0.4
	mesh.agent_height=0.8
	mesh.agent_max_climb=0.3
	mesh.agent_max_slope=50.0
	mesh.geometry_parsed_geometry_type=NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask=1
	return mesh

func _bake_navigation() -> void:
	# Navigační síť z kolizí úrovně; hluboký bazén se počítá jako průchozí (zombie ho přeplavou).
	# Statická geometrie se parsuje jen poprvé (brány vynechané), zavřené brány se přidají jako kvádry
	# a samotné pečení běží na vlákně – otevření brány tak hru nezasekne.
	if _nav_baking:
		_nav_again=true
		return
	var gates:=[]
	if stations:
		for item in stations.items:
			if item.kind=="gate": gates.append(item)
	if _nav_static==null:
		var layers:=[]
		for g in gates:
			layers.append(g.body.collision_layer)
			g.body.collision_layer=0
		_nav_static=NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(_nav_template(),_nav_static,main)
		for i in gates.size(): gates[i].body.collision_layer=layers[i]
		var level: float=main.WATER_Y-0.35
		var a:=Vector3(-6.6,level,-20.6)
		var b:=Vector3(6.6,level,-20.6)
		var c:=Vector3(6.6,level,-7.4)
		var d:=Vector3(-6.6,level,-7.4)
		_nav_static.add_faces(PackedVector3Array([a,b,c,a,c,d]),Transform3D.IDENTITY)
	var source:=NavigationMeshSourceGeometryData3D.new()
	source.merge(_nav_static)
	for g in gates:
		if g.state=="open": continue
		var cs: CollisionShape3D=g.body.get_child(0)
		var bm:=BoxMesh.new()
		bm.size=(cs.shape as BoxShape3D).size
		source.add_mesh_array(bm.get_mesh_arrays(),cs.global_transform)   # z CPU dat, bez čtení z GPU
	var mesh:=_nav_template()
	_nav_baking=true
	if _nav_region.is_valid():
		NavigationServer3D.bake_from_source_geometry_data_async(mesh,source,func(): _nav_baked.call_deferred(mesh))
	else:
		NavigationServer3D.bake_from_source_geometry_data(mesh,source)
		_nav_baked(mesh)

func _nav_baked(mesh: NavigationMesh) -> void:
	_nav_baking=false
	var map: RID=main.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map,0.2)
	NavigationServer3D.map_set_cell_height(map,0.1)
	if not _nav_region.is_valid():
		_nav_region=NavigationServer3D.region_create()
		NavigationServer3D.region_set_map(_nav_region,map)
	NavigationServer3D.region_set_navigation_mesh(_nav_region,mesh)
	if _nav_again:
		_nav_again=false
		_bake_navigation()

# ------------------------------------------------------------------ HUD

func _label(size: int, color: Color, big: bool=false) -> Label:
	var label:=Label.new()
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	label.add_theme_color_override("font_outline_color",Color(0,0,0,0.85))
	label.add_theme_constant_override("outline_size",maxi(3,size/9))
	if big: label.add_theme_font_override("font",_font)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_root.add_child(label)
	return label

func _build_hud() -> void:
	_layer=CanvasLayer.new()
	_layer.layer=21
	add_child(_layer)
	_root=Control.new()
	_root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)
	# Zranění: červené okraje obrazu, které při nízkém zdraví pulzují.
	_vignette=ColorRect.new()
	_vignette.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var shader:=Shader.new()
	shader.code="shader_type canvas_item;\nuniform float amount=0.0;\nuniform float pulse=0.0;\nvoid fragment(){\n\tvec2 d=(UV-0.5)*vec2(1.0,0.82);\n\tfloat edge=smoothstep(0.3,0.75,length(d));\n\tCOLOR=vec4(0.42,0.0,0.0,clamp(edge*amount*0.85+pulse*(0.06+0.5*edge),0.0,0.9));\n}\n"
	_vignette_material=ShaderMaterial.new()
	_vignette_material.shader=shader
	_vignette.material=_vignette_material
	_root.add_child(_vignette)
	for i in 4:
		var splat:=TextureRect.new()
		splat.mouse_filter=Control.MOUSE_FILTER_IGNORE
		splat.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		splat.stretch_mode=TextureRect.STRETCH_SCALE
		splat.modulate.a=0.0
		_root.add_child(splat)
		_splats.append(splat)
	_damage_draw=Control.new()
	_damage_draw.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_damage_draw.draw.connect(_draw_damage)
	_root.add_child(_damage_draw)
	_cross=Control.new()
	_cross.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_cross.draw.connect(_draw_cross)
	_root.add_child(_cross)
	_round_label=_label(132,RED,true)
	_points_label=_label(44,GOLD,true)
	_points_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_hint=_label(26,Color(1,1,1,0.9))
	_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_status=_label(34,Color(1.0,0.35,0.25),true)
	_status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_banner=_label(118,RED,true)
	_banner.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a=0.0
	_sub=_label(34,Color(0.92,0.9,0.86))
	_sub.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_sub.modulate.a=0.0
	for i in 8:
		var popup:=_label(34,GOLD,true)
		popup.modulate.a=0.0
		_popups.append(popup)
	_over=ColorRect.new()
	_over.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_over.color=Color(0.07,0.0,0.0,0.86)
	_over.modulate.a=0.0
	_root.add_child(_over)
	_over_title=_label(130,RED,true)
	_over_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_over_title.text="KONEC HRY"
	_over_title.reparent(_over)
	_over_text=_label(36,Color(0.93,0.9,0.86))
	_over_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_over_text.reparent(_over)

func _layout() -> void:
	var view:=get_viewport().get_visible_rect().size
	var scale:=view.y/1080.0
	var width:=view.x/scale
	_root.scale=Vector2(scale,scale)
	_vignette.size=Vector2(width,1080)
	_over.size=Vector2(width,1080)
	_cross.position=Vector2(width*0.5,540)
	_damage_draw.position=Vector2(width*0.5,540)
	_round_label.position=Vector2(46,1080-205)
	_points_label.size=Vector2(360,56)
	_points_label.position=Vector2(width-250-130,1080-150)
	_hint.size=Vector2(width,40)
	_hint.position=Vector2(0,690)
	_status.size=Vector2(width,44)
	_status.position=Vector2(0,54)
	_banner.size=Vector2(width,140)
	_banner.position=Vector2(0,230)
	_sub.size=Vector2(width,48)
	_sub.position=Vector2(0,372)
	_over_title.size=Vector2(width,150)
	_over_title.position=Vector2(0,270)
	_over_text.size=Vector2(width,360)
	_over_text.position=Vector2(0,450)

func _draw_cross() -> void:
	if player==null or not player.weapon.equipped: return
	var weapon: Node=player.weapon
	var view:=get_viewport().get_visible_rect().size
	# Mezera odpovídá skutečnému kuželu rozptylu při aktuálním zorném poli.
	var gap:=maxf(4.0,tan(weapon.spread)/tan(deg_to_rad(player.camera.fov)*0.5)*540.0)
	var alpha: float=(1.0-clampf(float(weapon.aim_amount)*1.7,0.0,1.0))*(1.0-float(weapon.sprint_amount))
	if view.y<=0.0 or alpha<=0.02: return
	for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		_cross.draw_line(direction*(gap-1.0),direction*(gap+12.0),Color(0,0,0,0.45*alpha),4.0)
		_cross.draw_line(direction*gap,direction*(gap+11.0),Color(1,1,1,0.9*alpha),2.0)
	_cross.draw_circle(Vector2.ZERO,1.3,Color(1,1,1,0.55*alpha))

func _show_banner(text: String, sub: String, hold: float=2.4) -> void:
	if _banner_tween: _banner_tween.kill()
	_banner.text=text
	_sub.text=sub
	_banner.modulate.a=0.0
	_sub.modulate.a=0.0
	_banner_tween=create_tween()
	_banner_tween.tween_property(_banner,"modulate:a",1.0,0.35)
	_banner_tween.parallel().tween_property(_sub,"modulate:a",1.0,0.5)
	_banner_tween.tween_interval(hold)
	_banner_tween.tween_property(_banner,"modulate:a",0.0,0.9)
	_banner_tween.parallel().tween_property(_sub,"modulate:a",0.0,0.9)

func horror() -> bool:
	# Hororový režim: žádné body na obrazovce, munice a zdraví jsou vzácné, zombie méně, ale silnější.
	return main != null and bool(main.settings.get("horror",false))

func _popup(text: String, big: bool) -> void:
	if horror(): return
	var popup: Label=_popups[_popup_next]
	_popup_next=(_popup_next+1)%_popups.size()
	popup.text=text
	popup.add_theme_font_size_override("font_size",44 if big else 32)
	var from:=_points_label.position+Vector2(190+randf_range(-30,30),-10)
	popup.position=from
	popup.modulate=Color(1,1,1,1) if big else Color(1,1,1,0.95)
	var tween:=create_tween().set_parallel(true)
	tween.tween_property(popup,"position",from+Vector2(randf_range(-150,-40),randf_range(-95,-40)),0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(popup,"modulate:a",0.0,0.5).set_delay(0.45)

func _splat() -> void:
	# Krev na obrazovce po zásahu od zombie.
	var textures: Array=main._combat_fx()._textures
	if textures.is_empty(): return
	var splat: TextureRect=_splats[_splat_next]
	_splat_next=(_splat_next+1)%_splats.size()
	var width:=get_viewport().get_visible_rect().size.x/_root.scale.x
	var size:=randf_range(380.0,620.0)
	splat.texture=textures[randi()%textures.size()]
	splat.size=Vector2(size,size)
	splat.pivot_offset=Vector2(size,size)*0.5
	splat.rotation=randf()*TAU
	var side:=randf()<0.5
	splat.position=Vector2(randf_range(-0.12,0.18)*width if side else randf_range(0.6,0.9)*width,randf_range(-60.0,700.0))
	splat.modulate=Color(1,1,1,randf_range(0.45,0.65))
	create_tween().tween_property(splat,"modulate:a",0.0,2.6).set_delay(0.5)

# ------------------------------------------------------------------ průběh hry

func begin() -> void:
	# Spouští se sebráním zbraně; v multiplayeru se režim nehraje.
	if active or main.network.active: return
	player=main.player
	main._combat_fx()
	active=true
	state="wait"
	_timer=5.0
	round_now=0
	points=500           # jako v CoD: na začátku na první dveře nestačí, po pár zabitích ano
	_zone_spawns=[]
	kills=0
	headshots=0
	health=100.0
	_drops=0
	_ammo_clock=60.0
	player.weapon.infinite_reserve=false
	player.weapon.refill()
	if stations: stations.reset()
	if main.get("quest"): main.quest.reset()
	_show_banner("","Něco se blíží…",2.5)
	var dummy: Node3D=main.zombie
	if is_instance_valid(dummy) and not dummy.dead:
		dummy.target=player
		dummy.alert(true)

func reset() -> void:
	_clear()
	active=false
	state="off"
	health=100.0
	_pulse=0.0
	_insta_left=0.0
	ZombieScript.insta_kill=false
	_over.modulate.a=0.0
	if stations: stations.reset()
	if main and main.player: main.player.weapon.infinite_reserve=true

func restart() -> void:
	_clear()
	ZombieScript.insta_kill=false
	_insta_left=0.0
	_over.modulate.a=0.0
	player.teleport(main.SPAWN,0.0,-0.03)
	player.control_enabled=true
	player.weapon.refill()
	player.weapon.reload_left=0.0
	health=100.0
	points=500           # jako v CoD: na začátku na první dveře nestačí, po pár zabitích ano
	_zone_spawns=[]
	kills=0
	headshots=0
	round_now=0
	_drops=0
	state="wait"
	_timer=3.5
	main.sfx.fade=1.0
	player.weapon.upgraded={}
	if stations: stations.reset()
	if main.get("quest"): main.quest.reset()

func _clear() -> void:
	for zombie in _zombies:
		if is_instance_valid(zombie): zombie.queue_free()
	_zombies.clear()
	for item in _powerups:
		if is_instance_valid(item.node): item.node.queue_free()
	_powerups.clear()

func clear_debug() -> void:
	_clear()
	main.toast("Zombie uklizeny")

func _alive() -> int:
	var count:=0
	for zombie in ZombieScript.crowd:
		if is_instance_valid(zombie) and zombie.ai: count+=1
	return count

func _pick_kind(level: int) -> String:
	# Běžné typy od začátku; silnější Parasite od 3. kola, alfa kostlivec od 5. kola
	# (vzácně, nanejvýš jeden – od 10. kola dva – naživu najednou).
	var alphas:=0
	for z in ZombieScript.crowd:
		if is_instance_valid(z) and z.ai and not z.dead and z.kind=="alpha": alphas+=1
	if level>=5 and alphas<(2 if level>=10 else 1) and randf()<0.06+0.01*mini(level-5,8):
		return "alpha"
	var pool:={"classic":30.0,"cop":22.0,"girl":22.0,"ch10":8.0}
	if level>=2: pool["kid"]=9.0
	if level>=3: pool["parasite"]=minf(10.0+3.0*(level-3),28.0)
	var sum:=0.0
	for k in pool: sum+=pool[k]
	var roll:=randf()*sum
	for k in pool:
		roll-=pool[k]
		if roll<=0.0: return k
	return "classic"

func _make(level: int, kind_override: String="") -> Node3D:
	main._combat_fx()
	var zombie: Node3D=ZombieScript.new()
	zombie.kind=kind_override if kind_override!="" else _pick_kind(level)
	var info: Dictionary=ZombieScript.TYPES[zombie.kind]
	# Zdraví roste s kolem jako v CoD; rychlejší typy přibývají postupně.
	zombie.max_health=(100.0+45.0*(level-1) if level<10 else 505.0*pow(1.1,level-9))*float(info.hp)*(1.3 if horror() else 1.0)
	zombie.health=zombie.max_health
	zombie.attack_damage*=float(info.dmg)*(1.35 if horror() else 1.0)
	var roll:=randf()
	if level<=2: zombie.tier="walk"
	elif level==3: zombie.tier="jog" if roll<0.35 else "walk"
	elif level==4: zombie.tier="sprint" if roll<0.12 else ("jog" if roll<0.6 else "walk")
	elif level<8: zombie.tier="sprint" if roll<0.35 else ("jog" if roll<0.8 else "walk")
	else: zombie.tier="sprint" if roll<0.6 else "jog"
	if zombie.kind=="alpha":
		zombie.tier="walk"            # alfa jde pomalu, ale nezastavitelně
		# Příchod alfy se ohlásí: temný basový propad z jejího směru.
		get_tree().process_frame.connect(func():
			if is_instance_valid(zombie) and zombie.is_inside_tree() and is_instance_valid(player) and zombie.global_position.distance_to(player.global_position)<40.0:
				main.sfx.play_at("stinger",zombie.global_position+Vector3(0,1.5,0),-2.0,0.82),CONNECT_ONE_SHOT)
	elif zombie.kind=="parasite" and zombie.tier=="walk" and level>=4: zombie.tier="jog"
	zombie.target=player
	zombie.attacked.connect(func(damage: float): hurt(damage,zombie))
	zombie.died.connect(func(_point: Vector3,_impulse: Vector3,_bone: int): _on_died(zombie))
	_zombies=_zombies.filter(func(item): return is_instance_valid(item))
	_zombies.append(zombie)
	return zombie

func _free_spot(position_now: Vector3, radius: float) -> bool:
	for zombie in ZombieScript.crowd:
		if is_instance_valid(zombie) and zombie.global_position.distance_to(position_now)<radius: return false
	return true

func _spawn() -> bool:
	var here:=player.global_position
	var eye:=player.camera.global_position
	var look: Vector3=-player.camera.global_basis.z
	var space:=main.get_world_3d().direct_space_state
	# Třetina spadne z galerií, třetina se vynoří z bazénu, zbytek přijde z míst, kam hráč zrovna nevidí.
	var pick:=randf()
	# Galerie a bazén v hale jen když je hráč poblíž; jinak zombie přijdou z okolí hráče.
	var near_hall:=Vector2(here.x,here.z).distance_to(Vector2(0,-14))<26.0
	if pick<0.33 and near_hall:
		var ledge: Array=LEDGES[randi()%LEDGES.size()]
		var landing: Vector3=ledge[0]+ledge[1]*1.6
		if Vector2(landing.x-here.x,landing.z-here.z).length()>4.0 and _free_spot(ledge[0],1.2):
			var jumper:=_make(round_now)
			jumper.position=ledge[0]
			main.add_child(jumper)
			jumper.drop(ledge[1])
			return true
	if pick<0.66 and near_hall:
		for attempt in 8:
			var spot:=Vector3(randf_range(POOL.position.x,POOL.end.x),0.0,randf_range(POOL.position.y,POOL.end.y))
			if Vector2(spot.x-here.x,spot.z-here.z).length()>5.0 and _free_spot(spot,1.3):
				var zombie:=_make(round_now)
				zombie.position=spot
				main.add_child(zombie)
				zombie.emerge()
				return true
	var best:=Vector3.ZERO
	var best_score:=-1e9
	for spot in WALK_SPAWNS+_zone_spawns:
		var away: float=Vector2(spot.x-here.x,spot.z-here.z).length()
		if away<8.0 or not _free_spot(spot,1.2): continue
		var score:=randf_range(0.0,6.0)-absf(away-16.0)*0.25
		var to: Vector3=(spot+Vector3.UP*1.2-eye).normalized()
		var blocked:=not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye,spot+Vector3.UP*1.2,1)).is_empty()
		if blocked or to.dot(look)<0.25: score+=8.0
		if score>best_score:
			best_score=score
			best=spot
	if best_score<-1e8: return false
	var walker:=_make(round_now)
	walker.position=_holes.get(best,best)+Vector3(randf_range(-0.15,0.15),0,randf_range(-0.15,0.15))
	main.add_child(walker)
	walker.alert(randf()<0.2)
	return true

var _respawn_t:=0.0

func _respawn_far(dt: float) -> void:
	# Jako v CoD: zombie, která zůstala daleko a hráč ji nevidí, po chvíli zmizí
	# a vyleze znovu z díry blízko hráče. Nepočítá se jako zabití, kolo jen pokračuje.
	_respawn_t-=dt
	if _respawn_t>0.0: return
	_respawn_t=0.5
	var eye: Vector3=player.camera.global_position
	var space:=main.get_world_3d().direct_space_state
	for zombie in ZombieScript.crowd.duplicate():
		if not is_instance_valid(zombie) or not zombie.ai or zombie.dead or zombie.has_meta("quest"): continue
		var z: Node3D=zombie
		var d:=z.global_position.distance_to(player.global_position)
		var far_t: float=z.get_meta("far_t",0.0)
		if d>RESPAWN_DIST:
			var seen:=space.intersect_ray(PhysicsRayQueryParameters3D.create(eye,z.global_position+Vector3.UP*1.2,1)).is_empty()
			far_t=0.0 if seen and d<40.0 else far_t+0.5
		else:
			far_t=0.0
		z.set_meta("far_t",far_t)
		if far_t>=RESPAWN_TIME:
			z.queue_free()
			_to_spawn+=1
			_spawn_timer=minf(_spawn_timer,0.6)

func spawn_debug() -> void:
	# Klávesa Z: zombie na místo, kam se hráč dívá (zkoušení zbraně mimo kola).
	if main.network.active:
		main.toast("Přivolání zombie funguje jen mimo multiplayer")
		return
	player=main.player
	if not player.control_enabled: return
	if _alive()>=MAX_ALIVE:
		main.toast("Nejvýš %d živých zombie najednou" % MAX_ALIVE)
		return
	var space:=main.get_world_3d().direct_space_state
	var forward: Vector3=-player.camera.global_basis.z
	forward.y=0
	forward=(forward.normalized() if forward.length()>0.1 else Vector3.FORWARD).rotated(Vector3.UP,randf_range(-0.4,0.4))
	var eye:=player.global_position+Vector3.UP*1.2
	var reach:=randf_range(5.5,9.0)
	var wall: Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(eye,eye+forward*(reach+0.8),1))
	if not wall.is_empty(): reach=maxf(1.6,eye.distance_to(wall.position)-0.8)
	var spot:=eye+forward*reach
	var ground: Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(spot,spot+Vector3.DOWN*8.0,1))
	if ground.is_empty():
		main.toast("Tady není kam zombie postavit")
		return
	var zombie:=_make(maxi(round_now,1))
	zombie.position=ground.position
	zombie.rotation.y=atan2(-forward.x,-forward.z)
	main.add_child(zombie)
	if ground.position.y<main.WATER_Y-ZombieScript.DEEP: zombie.emerge()
	else: zombie.alert(randf()<0.4)

func _start_round() -> void:
	round_now+=1
	if stations: stations.round_started()
	_to_spawn=ROUND_SIZES[round_now-1] if round_now<=ROUND_SIZES.size() else 30+(round_now-ROUND_SIZES.size())*5
	if horror(): _to_spawn=maxi(4,int(_to_spawn*0.6))
	_spawn_timer=1.2
	_stall=0.0
	_drops=0
	state="round"
	main.sfx.play("round_start",-4.0)
	# Hluboký basový propad pod začátkem kola: od 3. kola, ať první kola zůstanou tichá.
	if round_now>=3: main.sfx.play("stinger",-9.0+minf(round_now,10.0)*0.4,randf_range(0.9,1.0))
	if not horror(): _show_banner("KOLO %d" % round_now,"")
	_round_label.modulate=Color(3.0,3.0,3.0,1.0)
	create_tween().tween_property(_round_label,"modulate",Color(1,1,1,1),2.5)

func _end_round() -> void:
	state="wait"
	_timer=8.0
	main.sfx.play("round_end",-5.0)
	_show_banner("","Kolo %d přežito" % round_now,2.0)

func on_hit(victim: Node3D, region: String, lethal: bool, melee: bool) -> void:
	# Body jako v CoD: 10 za zásah, 60 za zabití, 100 za zabití do hlavy, 130 pažbou.
	if not active or state=="dead": return
	_stall=0.0
	var gain:=10
	if lethal:
		kills+=1
		if melee: gain=130
		elif region=="head":
			gain=100
			headshots+=1
		else: gain=60
	points+=gain
	_popup("+%d" % gain,lethal)

func _on_died(zombie: Node3D) -> void:
	main._combat_fx().pool(zombie)
	if active and main.get("quest"): main.quest.zombie_died(zombie,zombie.global_position)
	if not active or zombie.swimming: return
	var spot: Vector3=zombie.global_position
	# Bonusy: občas náhodně, munice jistě ve chvíli, kdy hráči dochází.
	var weapon: Node=player.weapon
	var starving: bool=weapon.ammo+weapon.reserve<int(weapon.stats().mag)*1.5 and _ammo_clock>25.0
	if starving: _drop("ammo",spot)
	elif _drops<2 and randf()<0.05:
		_drops+=1
		var roll:=randf()
		_drop("ammo" if roll<0.35 else "insta" if roll<0.6 else "heal" if roll<0.82 else "kaboom",spot)

func _drop(kind: String, spot: Vector3) -> void:
	if kind=="ammo": _ammo_clock=0.0
	var color: Color={"ammo":Color(0.25,1.0,0.35),"insta":Color(1.0,0.3,0.2),"heal":Color(0.3,0.8,1.0),"kaboom":Color(1.0,0.55,0.1)}[kind]
	var node:=Node3D.new()
	main.add_child(node)
	node.global_position=Vector3(spot.x,maxf(spot.y,main.WATER_Y)+0.8,spot.z)
	var shape: Node3D=Props.make({"ammo":"ammo","insta":"skull","heal":"syringe","kaboom":"pumpkin"}[kind])
	if kind=="ammo": shape.scale=Vector3.ONE*0.7
	for mesh in shape.find_children("*","MeshInstance3D",true,false):
		(mesh as MeshInstance3D).cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(shape)
	var glow:=OmniLight3D.new()
	glow.light_color=color
	glow.light_energy=1.6
	glow.omni_range=4.5
	glow.shadow_enabled=false
	node.add_child(glow)
	var caption:=Label3D.new()
	caption.text={"ammo":"MAX AMMO","insta":"INSTA-KILL","heal":"ZDRAVOTNÍK","kaboom":"KABOOM"}[kind]
	caption.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	caption.font=_font
	caption.font_size=56
	caption.outline_size=12
	caption.pixel_size=0.0032
	caption.modulate=color.lerp(Color.WHITE,0.35)
	caption.position.y=0.62
	node.add_child(caption)
	var entry:={"node":node,"shape":shape,"kind":kind,"left":26.0,"height":node.global_position.y,"glow":glow}
	if kind=="insta": _prepare_skull(entry)
	_powerups.append(entry)
	main.sfx.play_at("powerup_spawn",node.global_position,-4.0)

func _take(kind: String) -> void:
	main.sfx.play("powerup",-3.0)
	if kind=="ammo":
		player.weapon.refill_reserve()
		_show_banner("MAX AMMO","",1.4)
	elif kind=="heal":
		health=100.0
		_regen_wait=0.0
		_pulse=0.0
		_show_banner("ZDRAVOTNÍK","Zdraví obnoveno",1.4)
	elif kind=="kaboom":
		_kaboom()
	else:
		ZombieScript.insta_kill=true
		_insta_left=25.0
		_show_banner("INSTA-KILL","Každá rána zabíjí",1.4)

func _kaboom() -> void:
	# Všechny zombie v okolí to roztrhá; za každou body jako v CoD.
	_show_banner("KABOOM","",1.6)
	main.sfx.play("gib",0.0,0.6)
	var flash:=ColorRect.new()
	flash.color=Color(1.0,0.6,0.2,0.55)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_banner.get_parent().add_child(flash)
	create_tween().tween_property(flash,"color:a",0.0,0.9).finished.connect(flash.queue_free)
	var count:=0
	for zombie in ZombieScript.crowd.duplicate():
		if not is_instance_valid(zombie) or zombie.dead: continue
		var center: Vector3=zombie.global_position+Vector3.UP
		var push: Vector3=(center-player.global_position).normalized()+Vector3.UP*0.6
		zombie.hit(randi()%8,center,push.normalized(),2.5,99999.0)
		count+=1
	if count>0:
		points+=400
		_popup("+400",true)

func _prepare_skull(entry: Dictionary) -> void:
	# Kosti lebky: klidová poloha a směr, kterým se při roztříštění rozletí (v souřadnicích lebky).
	var shape: Node3D=entry.shape
	var parts: Array=[]
	var center:=Props._bounds(shape).get_center()
	for m in shape.find_children("*","MeshInstance3D",true,false):
		var mi: MeshInstance3D=m
		var c: Vector3=(Props._xf(mi,shape)*mi.get_aabb()).get_center()
		var dir:=(c-center)
		dir=(dir.normalized() if dir.length()>0.001 else Vector3.UP)+Vector3(randf_range(-0.35,0.35),randf_range(-0.1,0.45),randf_range(-0.35,0.35))
		parts.append({"node":mi,"pos":mi.position,"basis":mi.basis,"dir":dir.normalized(),"dist":randf_range(0.16,0.32),
			"spin":Vector3(randf_range(-1,1),randf_range(-1,1),randf_range(-1,1)).normalized(),"turn":randf_range(1.5,4.0)})
	entry["parts"]=parts
	entry["cycle"]=randf()*0.5

func _animate_skull(item: Dictionary) -> void:
	# Lebka se pravidelně roztříští na kosti, chvíli krouží kolem a zase se s cvaknutím složí.
	if not item.has("parts"): return
	var shape: Node3D=item.shape
	var period:=3.4
	var c: float=fmod(_time*1.0+float(item.cycle)*period,period)/period
	var apart:=0.0
	if c<0.14: apart=0.0
	elif c<0.32: apart=1.0-pow(1.0-(c-0.14)/0.18,3.0)          # prudký rozlet
	elif c<0.56: apart=1.0+sin((c-0.32)/0.24*PI)*0.12            # vznáší se kolem
	elif c<0.8:
		var u:=(c-0.56)/0.24
		apart=1.0-u*u*(3.0-2.0*u)                                  # složení zpět
		if u>0.85: apart-=sin((u-0.85)/0.15*PI)*0.06             # cvaknutí do sebe (malý přešvih)
	var swirl:=clampf(apart,0.0,1.0)
	for part in item.parts:
		var mi: MeshInstance3D=part.node
		if not is_instance_valid(mi): continue
		var offset_world: Vector3=shape.global_basis*(part.dir as Vector3)*float(part.dist)*apart
		var parent: Node3D=mi.get_parent()
		mi.position=(part.pos as Vector3)+parent.global_basis.inverse()*offset_world
		mi.basis=(part.basis as Basis)*Basis(part.spin,float(part.turn)*swirl*sin(c*TAU*0.5))
	# Záblesk při roztříštění.
	var glow: OmniLight3D=item.get("glow")
	if glow: glow.light_energy=1.6+swirl*1.8

func _explode_skull(node: Node3D) -> void:
	# Lebka se při sebrání rozletí na jednotlivé kosti.
	var parts: Array=node.find_children("*","MeshInstance3D",true,false)
	if parts.is_empty(): return
	var center: Vector3=node.global_position
	for part in parts:
		var mesh: MeshInstance3D=part
		var at: Transform3D=mesh.global_transform
		mesh.get_parent().remove_child(mesh)
		main.add_child(mesh)
		mesh.global_transform=at
		var away: Vector3=(at.origin-center+Vector3(randf_range(-0.05,0.05),0.05,randf_range(-0.05,0.05))).normalized()
		var tween:=create_tween().set_parallel()
		tween.tween_property(mesh,"global_position",at.origin+away*randf_range(0.6,1.4)+Vector3.UP*randf_range(0.1,0.5),0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(mesh,"rotation",mesh.rotation+Vector3(randf_range(-6,6),randf_range(-6,6),randf_range(-6,6)),0.7)
		tween.tween_property(mesh,"scale",Vector3.ZERO,0.35).set_delay(0.5)
		tween.chain().tween_callback(mesh.queue_free)

func hurt(damage: float, source: Node3D=null) -> void:
	if state=="dead" or player==null: return
	if debug_god: return
	_pulse=1.0
	_muffle=1.0
	main.sfx.play("player_hurt",-2.0)
	player.pitch=clampf(player.pitch+randf_range(0.03,0.07),-1.5,1.5)
	if source and is_instance_valid(source):
		# Úder odněkud: šipka na okraji obrazu a hlava cukne od útočníka.
		_damage_marks.append({"pos":source.global_position,"t":0.0})
		if _damage_marks.size()>6: _damage_marks.pop_front()
		var local: Vector3=player.camera.global_basis.inverse()*(source.global_position-player.camera.global_position)
		player.yaw+=clampf(local.x,-1.0,1.0)*-0.09+randf_range(-0.02,0.02)
	else:
		player.yaw+=randf_range(-0.07,0.07)
	_splat()
	if not active: return
	health-=damage
	_regen_wait=4.5
	if health<=0.0: _die()

# ------------------------------------------------------------------ zpětná vazba zranění
func _update_damage_feedback(dt: float) -> void:
	for mark in _damage_marks: mark.t+=dt
	_damage_marks=_damage_marks.filter(func(mark): return mark.t<1.6)
	_damage_draw.queue_redraw()
	# Po ráně a při nízkém zdraví se svět utlumí (jako by zalehly uši), hudba i zvuky.
	_muffle=maxf(0.0,_muffle-dt*1.4)
	var weak:=clampf(1.0-health/100.0,0.0,1.0) if active and state!="dead" else 0.0
	var amount:=maxf(_muffle*0.8,smoothstep(0.55,0.9,weak)*0.65)
	if _muffle_fx==null:
		_muffle_fx=AudioEffectLowPassFilter.new()
		_muffle_fx.cutoff_hz=20000.0
		AudioServer.add_bus_effect(0,_muffle_fx,0)
	_muffle_fx.cutoff_hz=lerpf(20000.0,700.0,pow(amount,0.7))
	AudioServer.set_bus_effect_enabled(0,0,amount>0.01)

func _draw_damage() -> void:
	if player==null or player.camera==null: return
	var cam: Camera3D=player.camera
	for mark in _damage_marks:
		var local: Vector3=cam.global_basis.inverse()*(Vector3(mark.pos)-cam.global_position)
		var angle:=atan2(local.x,-local.z)-PI*0.5        # 0 = před hráčem = nahoře
		var fade:=1.0-smoothstep(0.5,1.6,float(mark.t))
		var grow:=1.0-exp(-float(mark.t)*14.0)
		for pass_i in 2:
			var width:=26.0 if pass_i==0 else 12.0
			var color:=Color(0,0,0,0.35*fade) if pass_i==0 else Color(0.85,0.05,0.03,0.85*fade)
			_damage_draw.draw_arc(Vector2.ZERO,215.0+20.0*(1.0-grow),angle-0.32,angle+0.32,24,color,width,true)

func _die() -> void:
	health=0.0
	state="dead"
	_dead_time=0.0
	if _banner_tween: _banner_tween.kill()
	_banner.modulate.a=0.0
	_sub.modulate.a=0.0
	_insta_left=0.0
	ZombieScript.insta_kill=false
	player.control_enabled=false
	main.sfx.play("game_over",-1.0)
	for zombie in ZombieScript.crowd:
		if is_instance_valid(zombie): zombie.target=null
	if horror(): _over_text.text="Vydržel jsi %d vln\n\nZabití: %d        Do hlavy: %d\n\n\nEnter — hrát znovu          Esc — menu" % [round_now,kills,headshots]
	else: _over_text.text="Přežil jsi do kola %d\n\nZabití: %d        Do hlavy: %d        Body: %d\n\n\nEnter — hrát znovu          Esc — menu" % [round_now,kills,headshots,points]
	create_tween().tween_property(_over,"modulate:a",1.0,1.6).set_delay(0.5)

func _unhandled_input(event: InputEvent) -> void:
	if state!="dead" or _dead_time<1.6: return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE,KEY_R]:
		get_viewport().set_input_as_handled()
		restart()

func _process(dt: float) -> void:
	var _perf_t0:=Time.get_ticks_usec()
	_process_timed(dt)
	PerfMon.add("Zombie režim",Time.get_ticks_usec()-_perf_t0)

var _scratch_t:=8.0
var _tension_t:=0.0

func _update_tension() -> void:
	# Temná hudební plocha sílí s blízkostí a počtem zombie.
	_tension_t-=get_process_delta_time()
	if _tension_t>0.0: return
	_tension_t=0.3
	var t:=0.0
	if active and player:
		var near:=0
		var closest:=99.0
		for z in ZombieScript.crowd:
			if not is_instance_valid(z) or not z.ai or z.dead: continue
			var d: float=(z as Node3D).global_position.distance_to(player.global_position)
			closest=minf(closest,d)
			if d<18.0: near+=1
		t=clampf(near/6.0,0.0,1.0)*0.6+clampf((20.0-closest)/16.0,0.0,1.0)*0.4
	main.sfx.tension=t

func _wall_scratching(dt: float) -> void:
	# Z proražených děr ve zdech se občas ozve škrábání a skřípění – něco se tam hýbe.
	_scratch_t-=dt
	if _scratch_t>0.0 or _holes.is_empty(): return
	_scratch_t=randf_range(9.0,24.0)
	var near:=[]
	for spot in _holes:
		var p: Vector3=_holes[spot]
		var d:=p.distance_to(player.global_position)
		if d>4.0 and d<22.0: near.append(p)
	if near.is_empty(): return
	main.sfx.play_at("wall_scratch",near.pick_random()+Vector3(0,0.9,0),-6.0,randf_range(0.8,1.05))

func _process_timed(dt: float) -> void:
	if main==null or main.player==null or main.menu==null: return
	player=main.player
	_time+=dt
	_wall_scratching(dt)
	_update_tension()
	_layout()
	_layer.visible=not main.menu.is_open
	_cross.visible=player.weapon.equipped and bool(main.settings.get("crosshair_on",false))
	_cross.queue_redraw()
	_pulse=maxf(0.0,_pulse-dt*1.9)
	_update_damage_feedback(dt)
	var weak:=clampf(1.0-health/100.0,0.0,1.0) if active else 0.0
	var throb:=(0.5+0.5*sin(_time*6.5))*0.25*smoothstep(0.5,0.9,weak)
	_vignette_material.set_shader_parameter("amount",weak*(0.75+throb))
	_vignette_material.set_shader_parameter("pulse",_pulse)
	for element in [_round_label,_points_label,_status,_hint]: element.visible=active
	if not active:
		if _heart.playing: _heart.stop()
		if _breath.playing: _breath.stop()
		return
	if main.network.active:
		reset()
		return
	_round_label.text=str(round_now) if round_now>0 else ""
	# Body se ukážou jen chvíli po změně (hra je bez stálého HUD).
	if points!=_shown_points:
		_shown_points=points
		_points_label.text=str(points)
		_points_fade=3.0
	_points_fade=maxf(0.0,_points_fade-get_process_delta_time())
	_points_label.modulate.a=0.0 if horror() else clampf(_points_fade,0.0,1.0)
	_round_label.visible=not horror()
	player.weapon.reserve_scale=0.4 if horror() else 1.0
	var weapon: Node=player.weapon
	if not weapon.equipped or state=="dead": _hint.text=""
	elif weapon.ammo==0 and weapon.reserve==0: _hint.text="Bez munice — Q: úder pažbou"
	elif weapon.ammo<=maxi(1,int(weapon.stats().mag)/5) and weapon.reload_left<=0 and weapon.reserve>0: _hint.text="R — přebít   (podrž R — zkontrolovat)"
	else: _hint.text=""
	_ammo_clock+=dt
	if _insta_left>0.0:
		_insta_left-=dt
		_status.text="INSTA-KILL  %d" % ceili(_insta_left)
		if _insta_left<=0.0: ZombieScript.insta_kill=false
	else: _status.text=""
	_update_powerups(dt)
	# Zdraví se po chvíli bez zásahu samo doplní; při nízkém je slyšet tep.
	if state!="dead":
		_regen_wait-=dt
		# V hororu se rány samy nezahojí úplně: jen do třetiny a pomalu (zbytek léčí injekce ze skříněk).
		if _regen_wait<=0.0:
			if horror(): health=maxf(health,minf(35.0,health+6.0*dt))
			else: health=minf(100.0,health+32.0*dt)
	if state!="dead" and health<60.0 and _heart.stream:
		if not _heart.playing: _heart.play()
		_heart.volume_db=lerpf(-26.0,-5.0,clampf((60.0-health)/50.0,0.0,1.0))
		_heart.pitch_scale=lerpf(1.0,1.35,clampf((60.0-health)/60.0,0.0,1.0))
	elif _heart.playing: _heart.stop()
	var gasp:=clampf((70.0-health)/50.0,0.0,1.0) if state!="dead" else 0.0
	if gasp>0.01 and _breath.stream:
		if not _breath.playing: _breath.play(randf()*6.0)
		_breath.volume_db=lerpf(-30.0,-9.0,gasp)
	elif _breath.playing:
		_breath.volume_db-=dt*30.0
		if _breath.volume_db<-40.0: _breath.stop()
	match state:
		"wait":
			if not debug_hold: _timer-=dt
			if _timer<=0.0: _start_round()
		"round":
			_spawn_timer-=dt
			_stall+=dt
			var alive:=_alive()
			_respawn_far(dt)
			if debug_hold: _stall=0.0
			elif _to_spawn>0 and _spawn_timer<=0.0 and alive<(mini(3+round_now*2,12) if horror() else mini(6+round_now*3,MAX_ALIVE)):
				if _spawn(): _to_spawn-=1
				_spawn_timer=maxf(0.45,1.9-round_now*0.17)*randf_range(0.6,1.3)
			elif _to_spawn==0 and alive==0:
				_end_round()
			elif _to_spawn==0 and alive<=3 and _stall>50.0:
				# Poslední zombie se někde zasekly: přijdou znovu odjinud, ať kolo nezamrzne.
				_stall=0.0
				for zombie in ZombieScript.crowd.duplicate():
					if is_instance_valid(zombie) and zombie.ai:
						zombie.queue_free()
						_to_spawn+=1
		"dead":
			_dead_time+=dt
			player.pitch=move_toward(player.pitch,-0.75,dt*0.9)

func _update_powerups(dt: float) -> void:
	for item in _powerups:
		var node: Node3D=item.node
		item.left-=dt
		(item.shape as Node3D).rotate_y(dt*2.2)
		if item.kind=="insta": _animate_skull(item)
		node.global_position.y=float(item.height)+sin(_time*2.4)*0.07
		node.visible=item.left>6.0 or fmod(item.left,0.4)>0.14
		var away:=Vector2(node.global_position.x-player.global_position.x,node.global_position.z-player.global_position.z).length()
		if away<1.25 and state!="dead":
			_take(item.kind)
			if item.kind=="insta": _explode_skull(item.shape)
			item.left=0.0
		if item.left<=0.0: node.queue_free()
	_powerups=_powerups.filter(func(item): return item.left>0.0)
