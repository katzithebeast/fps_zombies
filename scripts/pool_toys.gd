extends Node3D
## Bazénové hračky: nafukovací jednorožci (jdou rozstřelit), plovoucí míčky a tobogány ze zdí.

const ZombieScript:=preload("res://scripts/zombie.gd")
const UNICORN_PATH:="res://assets/props/unicorn/source/"
const DEEP:=Rect2(-5.2,-19.4,10.4,10.8)        # hluboký bazén (x, z)
const BALL_AREA:=[Rect2(-11.5,-25.5,23,5),Rect2(-11.5,-19.5,6,11),Rect2(5.5,-19.5,6,11),Rect2(-5.5,-19.5,11,11),Rect2(-11.5,-7.8,23,5.6)]
const BALL_COLORS:=[Color(0.9,0.12,0.1),Color(1.0,0.8,0.1),Color(0.1,0.35,0.9),Color(0.15,0.7,0.25),Color(0.95,0.95,0.95),Color(1.0,0.45,0.1)]
const BALLS:=46
const BALL_R:=0.11
# Tobogány: body cesty od otvoru ve zdi dolů do vody.
# Tobogány: uzavřené trubky ve šroubovici, mimo sloupy haly (x ±9, z -5/-11/-17/-23).
const SLIDES:=[
	{"entry":Vector3(-12.0,3.4,-8.0),"inward":Vector3(1,0,0),"center":Vector2(-10.1,-8.0),"radius":1.05,"top":3.0,"bottom":0.75,"turns":1.25,"exit":2.4},
	{"entry":Vector3(4.6,3.4,-1.8),"inward":Vector3(0,0,-1),"center":Vector2(4.6,-3.55),"radius":1.05,"top":3.0,"bottom":0.75,"turns":1.25,"exit":2.4},
]

var main: Node
var _floats: Array=[]
var _balls: Array=[]
var _time:=0.0
var _frame:=0
var _unicorn_mesh: Mesh
var _unicorn_mat: Material

func setup(main_node: Node) -> void:
	main=main_node
	_unicorn_mesh=load(UNICORN_PATH+"PoolFloat2.obj")
	_unicorn_mat=StandardMaterial3D.new()
	_unicorn_mat.albedo_texture=load(UNICORN_PATH+"Diffuse5.png")
	_unicorn_mat.normal_enabled=true
	_unicorn_mat.normal_texture=load(UNICORN_PATH+"Normal2.png")
	_unicorn_mat.roughness=0.35
	_unicorn_mat=preload("res://scripts/water_clip.gd").clip_material(_unicorn_mat)
	for i in 2: _spawn_float(Vector3(-2.5+i*5.0,0,-12.0-i*3.0))
	_make_balls()
	for spec in SLIDES:
		var pts:=_spiral(spec.entry,spec.inward,spec.center,spec.radius,spec.top,spec.bottom,spec.turns,spec.exit)
		_make_slide(pts)
		# Střední nosný sloup šroubovice.
		var pole:=MeshInstance3D.new()
		var cyl:=CylinderMesh.new()
		cyl.top_radius=0.09
		cyl.bottom_radius=0.11
		cyl.height=spec.top+0.4+0.35
		pole.mesh=cyl
		var steel:=StandardMaterial3D.new()
		steel.albedo_color=Color(0.6,0.6,0.62)
		steel.metallic=0.3
		steel.roughness=0.4
		pole.material_override=steel
		add_child(pole)
		pole.global_position=Vector3(spec.center.x,-0.35+cyl.height*0.5,spec.center.y)
	if main.sim: main.sim.impulse_added.connect(_on_impulse)

# --- jednorožci ---------------------------------------------------------------

func _spawn_float(at: Vector3) -> void:
	var root:=Node3D.new()
	add_child(root)
	var mesh:=MeshInstance3D.new()
	mesh.mesh=_unicorn_mesh
	mesh.material_override=_unicorn_mat
	mesh.scale=Vector3.ONE*0.3
	var box: AABB=_unicorn_mesh.get_aabb()
	mesh.position=-Vector3(box.get_center().x,box.position.y+box.size.y*0.12,box.get_center().z)*0.3
	root.add_child(mesh)
	# Zásahový objem: střely ho trefí, hráč ani zombie se o něj nezachytí.
	var body:=StaticBody3D.new()
	body.collision_layer=64
	body.collision_mask=0
	var shape:=CollisionShape3D.new()
	var capsule:=BoxShape3D.new()
	capsule.size=Vector3(box.size.x,box.size.y*0.6,box.size.z)*0.3
	shape.shape=capsule
	shape.position.y=box.size.y*0.3*0.3
	body.add_child(shape)
	root.add_child(body)
	var entry:={"root":root,"body":body,"pos":at,"vel":Vector2(randf_range(-0.15,0.15),randf_range(-0.15,0.15)),"yaw":randf()*TAU,"spin":randf_range(-0.08,0.08),"phase":randf()*TAU,"dead":0.0}
	body.set_meta("shootable",self)
	body.set_meta("toy",entry)
	_floats.append(entry)

func shot(collider: Object, point: Vector3, direction: Vector3) -> void:
	var entry: Dictionary=collider.get_meta("toy")
	if entry.has("ball"):
		var push:=Vector2(direction.x,direction.z).normalized()*randf_range(1.6,2.4)
		entry.vel+=push
		entry.hop=0.35
		main.sfx.play_at("ball_hit",point,-10.0,randf_range(0.9,1.2))
		return
	if entry.dead>0.0: return
	_pop(entry,point)

func _pop(entry: Dictionary, point: Vector3) -> void:
	# Prasknutí: kruh rychle splaskne a zmizí, bez dalších efektů.
	entry.dead=25.0
	entry.body.collision_layer=0
	main.sfx.play_at("float_pop",point,-2.0,randf_range(0.9,1.1))
	var root: Node3D=entry.root
	var tw:=create_tween()
	tw.tween_property(root,"scale",Vector3(1.15,0.08,1.15),0.35).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.6)
	tw.tween_callback(func(): root.visible=false; root.scale=Vector3.ONE)

# --- míčky --------------------------------------------------------------------

func _make_balls() -> void:
	var sphere:=SphereMesh.new()
	sphere.radius=BALL_R
	sphere.height=BALL_R*2
	sphere.radial_segments=16
	sphere.rings=8
	var mats:=[]
	for c in BALL_COLORS:
		var m:=StandardMaterial3D.new()
		m.albedo_color=c
		m.roughness=0.3
		m.metallic_specular=0.7
		mats.append(m)
	var shape:=SphereShape3D.new()
	shape.radius=BALL_R*1.4
	for i in BALLS:
		var area: Rect2=BALL_AREA[i%BALL_AREA.size()]
		var at:=Vector3(randf_range(area.position.x,area.end.x),0,randf_range(area.position.y,area.end.y))
		var mesh:=MeshInstance3D.new()
		mesh.mesh=sphere
		mesh.material_override=mats[i%mats.size()]
		add_child(mesh)
		var body:=StaticBody3D.new()
		body.collision_layer=64
		body.collision_mask=0
		var col:=CollisionShape3D.new()
		col.shape=shape
		body.add_child(col)
		mesh.add_child(body)
		var entry:={"ball":true,"node":mesh,"pos":at,"vel":Vector2(randf_range(-0.08,0.08),randf_range(-0.08,0.08)),"phase":randf()*TAU,"hop":0.0,"spin":Vector3.ZERO}
		body.set_meta("shootable",self)
		body.set_meta("toy",entry)
		_balls.append(entry)

func _inside(p: Vector3) -> bool:
	for area in BALL_AREA:
		if (area as Rect2).has_point(Vector2(p.x,p.z)): return true
	return false

# --- tobogány -----------------------------------------------------------------

static func _spiral(entry: Vector3, inward: Vector3, center: Vector2, radius: float, top: float, bottom: float, turns: float, exit_len: float) -> Array:
	# Vstup ze zdi, šroubovice kolem středu a rovný výjezd do vody.
	var pts:=[entry,entry+inward*0.7]
	var start_angle:=atan2((entry+inward*1.0).z-center.y,(entry+inward*1.0).x-center.x)
	var steps:=int(turns*16)
	var last:=Vector3.ZERO
	for i in range(1,steps+1):
		var t:=float(i)/steps
		var a:=start_angle+t*turns*TAU
		last=Vector3(center.x+cos(a)*radius,lerpf(top,bottom,t),center.y+sin(a)*radius)
		pts.append(last)
	var a_end:=start_angle+turns*TAU
	var tangent:=Vector3(-sin(a_end),0,cos(a_end))
	pts.append(last+tangent*exit_len*0.5+Vector3(0,-0.15,0))
	pts.append(last+tangent*exit_len+Vector3(0,-0.25,0))
	return pts

func _make_slide(points: Array) -> void:
	var path:=Path3D.new()
	var curve:=Curve3D.new()
	for i in points.size():
		var p: Vector3=points[i]
		var tangent:=Vector3.ZERO
		if i>0 and i<points.size()-1: tangent=((points[i+1] as Vector3)-(points[i-1] as Vector3))*0.3
		curve.add_point(p,-tangent,tangent)
	path.curve=curve
	add_child(path)
	# Vnitřek se odečítá po o kus delší dráze, aby konce trubky byly čistě otevřené.
	var inner_path:=Path3D.new()
	var inner_curve:=Curve3D.new()
	var first_dir:=((points[0] as Vector3)-(points[1] as Vector3)).normalized()
	var last_dir:=((points[points.size()-1] as Vector3)-(points[points.size()-2] as Vector3)).normalized()
	inner_curve.add_point((points[0] as Vector3)+first_dir*0.4)
	for i in curve.point_count: inner_curve.add_point(curve.get_point_position(i),curve.get_point_in(i),curve.get_point_out(i))
	inner_curve.add_point((points[points.size()-1] as Vector3)+last_dir*0.4)
	inner_path.curve=inner_curve
	add_child(inner_path)
	var m:=StandardMaterial3D.new()
	m.albedo_color=Color(0.95,0.5,0.06)
	m.roughness=0.18
	m.metallic_specular=0.9
	m.clearcoat_enabled=true
	m.clearcoat=0.6
	# Uzavřená trubka: vnější válec minus vnitřní, takže je dutá jako skutečný tobogán.
	var combo:=CSGCombiner3D.new()
	combo.use_collision=true
	add_child(combo)
	for pass_i in 2:
		var poly:=CSGPolygon3D.new()
		var ring:=PackedVector2Array()
		var r:=0.52 if pass_i==0 else 0.45
		for i in 24: ring.append(Vector2(cos(TAU*i/24.0),sin(TAU*i/24.0))*r)
		poly.polygon=ring
		poly.mode=CSGPolygon3D.MODE_PATH
		poly.path_node=poly.get_path_to(path) if poly.is_inside_tree() else NodePath()
		poly.path_interval_type=CSGPolygon3D.PATH_INTERVAL_DISTANCE
		poly.path_interval=0.2
		poly.path_rotation=CSGPolygon3D.PATH_ROTATION_PATH_FOLLOW
		poly.smooth_faces=true
		poly.material=m
		if pass_i==1:
			poly.operation=CSGShape3D.OPERATION_SUBTRACTION
			var inner_m: StandardMaterial3D=m.duplicate()
			inner_m.albedo_color=Color(0.85,0.35,0.04)
			poly.material=inner_m
		combo.add_child(poly)
		poly.path_node=poly.get_path_to(path if pass_i==0 else inner_path)
	# Obruby (příruby) po délce, jak bývají u skládaných tobogánů.
	var length:=curve.get_baked_length()
	var flange_m: StandardMaterial3D=m.duplicate()
	flange_m.albedo_color=Color(0.98,0.62,0.12)
	var d:=1.0
	while d<length-0.4:
		var xf:=curve.sample_baked_with_rotation(d,true)
		var flange:=MeshInstance3D.new()
		var torus:=TorusMesh.new()
		torus.inner_radius=0.5
		torus.outer_radius=0.57
		torus.rings=24
		torus.ring_segments=8
		flange.mesh=torus
		flange.material_override=flange_m
		add_child(flange)
		flange.global_transform=Transform3D(xf.basis*Basis(Vector3.RIGHT,PI/2),xf.origin)
		d+=1.6
	# Výjezd: zesílený lem a neviditelná zábrana, aby se dovnitř nedalo vlézt.
	for at in [0.02,length-0.02]:
		var xf_end:=curve.sample_baked_with_rotation(at,true)
		var lip:=MeshInstance3D.new()
		var lip_torus:=TorusMesh.new()
		lip_torus.inner_radius=0.44
		lip_torus.outer_radius=0.6
		lip_torus.rings=32
		lip_torus.ring_segments=10
		lip.mesh=lip_torus
		lip.material_override=flange_m
		add_child(lip)
		lip.global_transform=Transform3D(xf_end.basis*Basis(Vector3.RIGHT,PI/2),xf_end.origin)
	var exit_xf:=curve.sample_baked_with_rotation(length-0.3,true)
	var grate:=StaticBody3D.new()
	var col:=CollisionShape3D.new()
	var cyl:=CylinderShape3D.new()
	cyl.radius=0.46
	cyl.height=0.1
	col.shape=cyl
	grate.add_child(col)
	add_child(grate)
	grate.global_transform=Transform3D(exit_xf.basis*Basis(Vector3.RIGHT,PI/2),exit_xf.origin)
	# Uvnitř u výjezdu tma: tmavý kotouč kousek v trubce.
	var deep:=MeshInstance3D.new()
	var deep_disc:=CylinderMesh.new()
	deep_disc.top_radius=0.45
	deep_disc.bottom_radius=0.45
	deep_disc.height=0.01
	deep.mesh=deep_disc
	var dark:=StandardMaterial3D.new()
	dark.albedo_color=Color(0.03,0.01,0.0)
	deep.material_override=dark
	add_child(deep)
	var deep_xf:=curve.sample_baked_with_rotation(length-1.2,true)
	deep.global_transform=Transform3D(deep_xf.basis*Basis(Vector3.RIGHT,PI/2),deep_xf.origin)
	# Tmavý otvor u zdi.
	var hole:=MeshInstance3D.new()
	var disc:=CylinderMesh.new()
	disc.top_radius=0.44
	disc.bottom_radius=0.44
	disc.height=0.02
	hole.mesh=disc
	var black:=StandardMaterial3D.new()
	black.albedo_color=Color(0.0,0.0,0.0)
	hole.material_override=black
	add_child(hole)
	var dir: Vector3=((points[1] as Vector3)-(points[0] as Vector3)).normalized()
	hole.global_transform=Transform3D(Basis(Quaternion(Vector3.UP,dir)),(points[0] as Vector3)+dir*0.05)

# --- vlny a hráč -------------------------------------------------------------

var _ripples: Array=[]      # {p: Vector2, t: float, a: float}

func _on_impulse(point: Vector2, _radius: float, strength: float) -> void:
	# Kroky a pohyb hráče posílají impulzy každý snímek; slévají se do pár vln.
	var amp:=clampf(absf(strength)*0.05,0.004,0.06)
	for r in _ripples:
		if r.t<0.25 and (r.p as Vector2).distance_to(point)<0.6:
			r.a=minf(0.07,r.a+amp*0.3)
			return
	_ripples.append({"p":point,"t":0.0,"a":amp})
	if _ripples.size()>12: _ripples.pop_front()

func _wave(at: Vector2) -> Vector3:
	# Výška hladiny a vodorovný tlak vln v daném bodě (x, výška, z).
	if _ripples.is_empty(): return Vector3.ZERO
	var h:=0.0
	var push:=Vector2.ZERO
	for r in _ripples:
		var d:=(r.p as Vector2).distance_to(at)
		var front:=float(r.t)*1.4
		if d>front or d>7.0: continue
		var fade:=exp(-float(r.t)*0.9)/(1.0+d*0.8)
		var phase:=(d-front)*7.0
		h+=float(r.a)*sin(phase)*fade*exp((d-front)*1.5)
		if d>0.01: push+=(at-(r.p as Vector2))/d*float(r.a)*fade*6.0*exp((d-front)*2.0)
	return Vector3(push.x,h,push.y)

func _bodies() -> Array:
	# Kdo ve vodě odstrkuje hračky: hráč a zombie.
	# Jen ti, kdo jsou ve vodě poblíž hráče (hračky dál se stejně nepočítají).
	var list:=[]
	if main.player == null: return list
	var here: Vector3=main.player.global_position
	list.append([here,(main.player.velocity as Vector3)])
	for z in ZombieScript.crowd:
		if not is_instance_valid(z) or z.dead or not z.ai: continue
		var at: Vector3=z.global_position
		if absf(at.x-here.x)>24.0 or absf(at.z-here.z)>24.0: continue
		list.append([at,z.velocity if "velocity" in z else Vector3.ZERO])
	return list

func _near_body(pos: Vector3, bodies: Array, radius: float) -> bool:
	for b in bodies:
		var at: Vector3=b[0]
		if absf(at.x-pos.x)<radius and absf(at.z-pos.z)<radius: return true
	return false

func _shove(pos: Vector3, vel: Vector2, radius: float, bodies: Array, dt: float) -> Vector2:
	for b in bodies:
		var at: Vector3=b[0]
		if absf(at.y-main.WATER_Y)>1.6: continue
		var off:=Vector2(pos.x-at.x,pos.z-at.z)
		var d:=off.length()
		if d<radius and d>0.001:
			var speed:=Vector2(b[1].x,b[1].z).length()
			vel+=off/d*(radius-d)*(3.0+speed*2.5)*dt*4.0
	return vel

# --- pohyb --------------------------------------------------------------------

func _process(dt: float) -> void:
	var _perf_t0:=Time.get_ticks_usec()
	_process_timed(dt)
	PerfMon.add("Bazénové hračky",Time.get_ticks_usec()-_perf_t0)

func _process_timed(dt: float) -> void:
	_time+=dt
	var water: float=main.WATER_Y
	for r in _ripples: r.t+=dt
	_ripples=_ripples.filter(func(r): return r.t<3.5)
	var bodies:=_bodies()
	for f in _floats:
		if f.dead>0.0:
			f.dead-=dt
			if f.dead<=0.0:
				f.pos=Vector3(randf_range(DEEP.position.x+1,DEEP.end.x-1),0,randf_range(DEEP.position.y+1,DEEP.end.y-1))
				f.root.visible=true
				f.body.collision_layer=64
			continue
		var w:=_wave(Vector2(f.pos.x,f.pos.z))
		f.vel+=Vector2(w.x,w.z)*dt*0.6
		f.vel=_shove(f.pos,f.vel,1.25,bodies,dt)
		f.vel=f.vel.limit_length(1.2)
		f.vel*=exp(-0.35*dt)
		if f.vel.length()<0.05: f.vel+=Vector2(randf_range(-0.03,0.03),randf_range(-0.03,0.03))
		f.spin=lerpf(f.spin,f.vel.length()*0.3*sign(f.spin+0.0001),dt)
		f.pos+=Vector3(f.vel.x,0,f.vel.y)*dt
		if f.pos.x<DEEP.position.x+0.9 or f.pos.x>DEEP.end.x-0.9: f.vel.x=-f.vel.x
		if f.pos.z<DEEP.position.y+0.9 or f.pos.z>DEEP.end.y-0.9: f.vel.y=-f.vel.y
		f.pos.x=clampf(f.pos.x,DEEP.position.x+0.9,DEEP.end.x-0.9)
		f.pos.z=clampf(f.pos.z,DEEP.position.y+0.9,DEEP.end.y-0.9)
		f.yaw+=f.spin*dt
		var root: Node3D=f.root
		root.global_position=Vector3(f.pos.x,main.water_level_at(f.pos)+sin(_time*1.3+f.phase)*0.03+w.y*0.8,f.pos.z)
		var tilt:=_wave(Vector2(f.pos.x+0.6,f.pos.z)).y-_wave(Vector2(f.pos.x-0.6,f.pos.z)).y
		var roll:=_wave(Vector2(f.pos.x,f.pos.z+0.6)).y-_wave(Vector2(f.pos.x,f.pos.z-0.6)).y
		root.rotation=Vector3(sin(_time*0.9+f.phase)*0.04+roll*1.5,f.yaw,cos(_time*1.1+f.phase)*0.04-tilt*1.5)
	_frame+=1
	var here: Vector3=main.player.global_position if main.player else Vector3.ZERO
	for bi in _balls.size():
		var b: Dictionary=_balls[bi]
		# Vzdálené míčky stojí; blízké se počítají každý druhý snímek (střídavě), s dvojnásobným krokem.
		if absf(b.pos.x-here.x)>22.0 or absf(b.pos.z-here.z)>22.0: continue
		# Míček v klidu a bez vln kolem: nic nepočítat.
		if _ripples.is_empty() and b.vel.length()<0.06 and b.hop<=0.0 and not _near_body(b.pos,bodies,0.7): continue
		if (bi+_frame)%2==1: continue
		var dt2:=dt*2.0
		var old: Vector3=b.pos
		var bw:=_wave(Vector2(b.pos.x,b.pos.z))
		b.vel+=Vector2(bw.x,bw.z)*dt2*1.5
		b.vel=_shove(b.pos,b.vel,0.55,bodies,dt2)
		b.vel=b.vel.limit_length(3.0)
		b.pos+=Vector3(b.vel.x,0,b.vel.y)*dt2
		b.vel*=exp(-0.8*dt2)
		if b.vel.length()<0.05: b.vel+=Vector2(randf_range(-0.02,0.02),randf_range(-0.02,0.02))
		if not _inside(b.pos):
			b.pos=old
			b.vel=-b.vel*0.6
		b.hop=maxf(0.0,b.hop-dt2)
		var node: MeshInstance3D=b.node
		var jump: float=sin(b.hop/0.35*PI)*0.25 if b.hop>0.0 else 0.0
		node.global_position=Vector3(b.pos.x,main.water_level_at(b.pos)+BALL_R*0.35+sin(_time*2.0+b.phase)*0.012+jump+bw.y,b.pos.z)
		node.rotate_x(b.vel.y*dt2/BALL_R)
		node.rotate_z(-b.vel.x*dt2/BALL_R)
