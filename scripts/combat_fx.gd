extends Node3D
const BloodDressing:=preload("res://scripts/blood_dressing.gd")
## Efekty střelby a krve. Všechno je ze zásobníků: při střelbě se nevyrábí žádné nové uzly ani materiály.
const BLOOD_MAX:=36
const SPLAT_MAX:=70           # velké cákance z textur (zdi za zombie, kaluže)
const BLOOD_DIR:="res://assets/blood/"
# Směrové stříkance: [textura, směr stříkání v textuře (rad, 0 = doprava, záporně = nahoru)]
const SPRAYS:=[["splatters_02_horizontal_spray",0.0],["splatters_03_diagonal_impact",-0.75],["splatters_08_droplet_trail",-0.5]]
const BURSTS:=["splatters_01_radial_impact","splatters_05_heavy_splash","splatters_07_double_impact","splatters_06_scattered_drops"]
const RUNS:=["smears_04_gravity_drips","smears_05_thin_drip"]
var _splats: Array=[]
var _splat_next:=0
var _blood_tex:={}
var water_y:=0.0
var _tracers: Array=[]
var _tracer_next:=0
var _puffs: Array=[]
var _puff_next:=0
var _sprays: Array=[]
var _spray_next:=0
var _decals: Array=[]
var _decal_next:=0
var _textures: Array=[]
var _chunks: Array=[]
var _chunk_next:=0
var _spurt_pool: Array=[]
var _spurts: Array=[]
var _holes: Array=[]
var _hole_next:=0
var _hole_texture: ImageTexture
const HOLE_MAX:=48

var _dot_texture: GradientTexture2D

func _dot() -> GradientTexture2D:
	# Měkká kulatá tečka: částice nevypadají jako čtverečky.
	if _dot_texture==null:
		var gradient:=Gradient.new()
		gradient.offsets=PackedFloat32Array([0.0,0.55,1.0])
		gradient.colors=PackedColorArray([Color(1,1,1,1),Color(1,1,1,0.85),Color(1,1,1,0)])
		_dot_texture=GradientTexture2D.new()
		_dot_texture.gradient=gradient
		_dot_texture.fill=GradientTexture2D.FILL_RADIAL
		_dot_texture.fill_from=Vector2(0.5,0.5)
		_dot_texture.fill_to=Vector2(1.0,0.5)
		_dot_texture.width=32
		_dot_texture.height=32
	return _dot_texture

func _particles(amount: int, color_from: Color, color_to: Color, size: float, lifetime: float) -> CPUParticles3D:
	var emitter:=CPUParticles3D.new()
	emitter.one_shot=true
	emitter.emitting=false
	emitter.amount=amount
	emitter.lifetime=lifetime
	emitter.explosiveness=0.95
	var fade:=Gradient.new()
	fade.colors=PackedColorArray([color_from,color_to])
	emitter.color_ramp=fade
	var quad:=QuadMesh.new()
	quad.size=Vector2(size,size)
	var material:=StandardMaterial3D.new()
	material.billboard_mode=BaseMaterial3D.BILLBOARD_PARTICLES
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo=true
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture=_dot()
	quad.material=material
	emitter.mesh=quad
	emitter.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(emitter)
	return emitter

func _splat(seed_now: int) -> ImageTexture:
	# Procedurální cákanec: nepravidelná skvrna a rozstříknuté kapky.
	var rng:=RandomNumberGenerator.new()
	rng.seed=seed_now
	var size:=128
	var image:=Image.create(size,size,false,Image.FORMAT_RGBA8)
	var blobs:=[]
	for i in 7: blobs.append([Vector2(rng.randf_range(0.36,0.64),rng.randf_range(0.36,0.64))*size,rng.randf_range(0.07,0.19)*size])
	for i in 26:
		var angle:=rng.randf()*TAU
		var far:=rng.randf_range(0.18,0.47)*size
		blobs.append([Vector2(size*0.5,size*0.5)+Vector2(cos(angle),sin(angle))*far,rng.randf_range(0.008,0.035)*size*(1.3-far/size)])
	for y in size:
		for x in size:
			var alpha:=0.0
			var point:=Vector2(x,y)
			for blob in blobs:
				var d: float=point.distance_to(blob[0])/float(blob[1])
				if d<1.0: alpha=maxf(alpha,1.0-smoothstep(0.55,1.0,d))
			var shade:=0.75+0.25*alpha
			image.set_pixel(x,y,Color(0.33*shade,0.012,0.012,alpha*0.94))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _ready() -> void:
	var glow:=StandardMaterial3D.new()
	glow.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color=Color(1.0,0.82,0.5)
	glow.emission_enabled=true
	glow.emission=Color(1.0,0.7,0.3)
	glow.emission_energy_multiplier=5.0
	var box:=BoxMesh.new()
	box.size=Vector3(0.012,0.012,1.0)
	box.material=glow
	for i in 6:
		var tracer:=MeshInstance3D.new()
		tracer.mesh=box
		tracer.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tracer.visible=false
		add_child(tracer)
		_tracers.append(tracer)
	for i in 6:
		var puff:=_particles(14,Color(0.92,0.92,0.9,0.85),Color(0.85,0.85,0.83,0.0),0.035,0.55)
		puff.spread=38.0
		puff.initial_velocity_min=0.8
		puff.initial_velocity_max=3.2
		puff.gravity=Vector3(0,-5.0,0)
		puff.damping_min=2.0
		puff.damping_max=4.0
		puff.scale_amount_min=0.4
		puff.scale_amount_max=1.3
		_puffs.append(puff)
	for i in 8:
		# Krev: kapky letící ve směru střely a jemná mlha u rány.
		var drops:=_particles(30,Color(0.42,0.01,0.01,1.0),Color(0.28,0.0,0.0,0.0),0.03,0.6)
		drops.spread=24.0
		drops.initial_velocity_min=1.2
		drops.initial_velocity_max=7.0
		drops.gravity=Vector3(0,-9.0,0)
		drops.scale_amount_min=0.4
		drops.scale_amount_max=1.5
		var mist:=_particles(7,Color(0.45,0.02,0.02,0.55),Color(0.3,0.0,0.0,0.0),0.16,0.4)
		mist.spread=60.0
		mist.initial_velocity_min=0.2
		mist.initial_velocity_max=1.1
		mist.gravity=Vector3(0,-1.0,0)
		mist.scale_amount_min=0.6
		mist.scale_amount_max=1.6
		_sprays.append([drops,mist])
	for i in 4: _textures.append(_splat(40+i))
	# Kusy masa při rozstřelení: malé tmavé úlomky, které odletí a spadnou.
	var meat:=StandardMaterial3D.new()
	meat.albedo_color=Color(0.3,0.025,0.02)
	meat.roughness=0.35
	for i in 4:
		var chunk:=CPUParticles3D.new()
		chunk.one_shot=true
		chunk.emitting=false
		chunk.amount=12
		chunk.lifetime=1.0
		chunk.explosiveness=1.0
		chunk.spread=65.0
		chunk.initial_velocity_min=1.5
		chunk.initial_velocity_max=5.0
		chunk.gravity=Vector3(0,-9.8,0)
		chunk.scale_amount_min=0.5
		chunk.scale_amount_max=1.7
		var piece:=BoxMesh.new()
		piece.size=Vector3(0.04,0.03,0.035)
		piece.material=meat
		chunk.mesh=piece
		add_child(chunk)
		_chunks.append(chunk)
	# Tepenné stříkání z pahýlu: pulzující proud, který sleduje tělo.
	for i in 10:
		var jet:=_particles(26,Color(0.5,0.01,0.01,1.0),Color(0.3,0.0,0.0,0.0),0.035,0.55)
		jet.one_shot=false
		jet.explosiveness=0.0
		jet.spread=13.0
		jet.initial_velocity_min=1.4
		jet.initial_velocity_max=2.6
		jet.gravity=Vector3(0,-9.0,0)
		jet.scale_amount_min=0.5
		jet.scale_amount_max=1.4
		_spurt_pool.append(jet)
	# Díra po kulce: tmavý střed se světlejším vyštípnutým okrajem.
	var size:=32
	var image:=Image.create(size,size,false,Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d:=Vector2(x-15.5,y-15.5).length()/15.5
			var core:=1.0-smoothstep(0.22,0.4,d)
			var rim:=(1.0-smoothstep(0.4,0.95,d))*0.55
			image.set_pixel(x,y,Color(0.05+0.25*(1.0-core),0.05+0.24*(1.0-core),0.05+0.22*(1.0-core),maxf(core,rim)))
	image.generate_mipmaps()
	_hole_texture=ImageTexture.create_from_image(image)

func _process(dt: float) -> void:
	var _perf_t0:=Time.get_ticks_usec()
	_process_timed(dt)
	PerfMon.add("Efekty boje",Time.get_ticks_usec()-_perf_t0)

func _process_timed(dt: float) -> void:
	if _spurts.is_empty(): return
	for item in _spurts:
		item.left-=dt
		var jet: CPUParticles3D=item.jet
		if item.left<=0.0 or not is_instance_valid(item.zombie):
			jet.emitting=false
			continue
		var frame: Transform3D=item.zombie.stump(item.bone)
		if not frame.origin.is_finite(): continue
		jet.global_position=frame.origin
		var weak: float=item.get("power",1.0)
		# Slabé krvácení (rána po smrti) víc teče dolů, silné tepenné stříká podél kosti.
		jet.direction=(frame.basis.y.normalized()*weak+Vector3.UP*0.25*weak+Vector3.DOWN*(1.0-weak)).normalized()
		# Tep slábne: proud pulzuje a postupně řídne.
		var beat:=0.45+0.55*absf(sin(item.left*8.5))
		jet.initial_velocity_max=2.8*beat*clampf(item.left/1.2,0.3,1.0)*weak
		item.drip-=dt
		if item.drip<=0.0:
			item.drip=0.3
			var below:=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(frame.origin,frame.origin+Vector3.DOWN*2.5,1))
			if not below.is_empty(): mark(below.position+Vector3(randf_range(-0.15,0.15),0,randf_range(-0.15,0.15)),below.normal,randf_range(0.18,0.34))
	_spurts=_spurts.filter(func(item): return item.left>0.0 and is_instance_valid(item.zombie))

func prewarm(point: Vector3) -> void:
	# Každý efekt se jednou vykreslí už při načítání, aby první přestřelka necukla kompilací shaderů.
	for list in [_puffs,_chunks,_spurt_pool]:
		for emitter in list:
			emitter.global_position=point
			emitter.restart()
	for pair in _sprays:
		for emitter in pair:
			emitter.global_position=point
			emitter.restart()
	for tracer in _tracers:
		tracer.global_position=point
		tracer.visible=true
	await get_tree().create_timer(0.4).timeout
	for emitter in _spurt_pool: emitter.emitting=false
	for tracer in _tracers: tracer.visible=false

func gib(point: Vector3, direction: Vector3) -> void:
	var chunk: CPUParticles3D=_chunks[_chunk_next]
	_chunk_next=(_chunk_next+1)%_chunks.size()
	chunk.global_position=point
	chunk.direction=(direction*0.6+Vector3.UP).normalized()
	chunk.restart()
	blood(point,direction,true)
	blood(point,(direction+Vector3.UP*0.8).normalized(),true)

func spurt(zombie: Node3D, bone: int, duration: float, power: float=1.0) -> void:
	var jet: CPUParticles3D=null
	for candidate in _spurt_pool:
		if not candidate.emitting:
			jet=candidate
			break
	if jet==null: return
	jet.emitting=true
	_spurts.append({"jet":jet,"zombie":zombie,"bone":bone,"left":duration,"drip":0.15,"power":power})

func hole(point: Vector3, normal: Vector3) -> void:
	if point.y<water_y: return
	var decal: Decal
	if _holes.size()<HOLE_MAX:
		decal=Decal.new()
		decal.cull_mask=1
		decal.texture_albedo=_hole_texture
		decal.size=Vector3(0.075,0.12,0.075)
		decal.normal_fade=0.55
		decal.distance_fade_enabled=true
		decal.distance_fade_begin=18.0
		decal.distance_fade_length=6.0
		add_child(decal)
		_holes.append(decal)
	else:
		decal=_holes[_hole_next]
		_hole_next=(_hole_next+1)%HOLE_MAX
	var up:=normal.normalized()
	var side:=up.cross(Vector3.UP if absf(up.y)<0.9 else Vector3.RIGHT).normalized()
	decal.global_transform=Transform3D(Basis(side,up,side.cross(up)).rotated(up,randf()*TAU),point+up*0.01)

func mark(point: Vector3, normal: Vector3, size: float, grow: float=0.0) -> void:
	if point.y<water_y-0.6: return   # v hluboké vodě se krev rozpustí; pod mělkou zůstane na dlaždicích
	var decal: Decal
	if _decals.size()<BLOOD_MAX:
		decal=Decal.new()
		decal.cull_mask=1
		decal.upper_fade=0.3
		decal.lower_fade=0.3
		decal.normal_fade=0.55
		decal.distance_fade_enabled=true
		decal.distance_fade_begin=22.0
		decal.distance_fade_length=8.0
		add_child(decal)
		_decals.append(decal)
	else:
		decal=_decals[_decal_next]
		_decal_next=(_decal_next+1)%BLOOD_MAX
	decal.texture_albedo=_textures[randi()%_textures.size()]
	# Čerstvá krev je o kus jasnější než zaschlá, ale nesvítí; pod vodou tmavne do černa.
	decal.modulate=Color(0.22,0.05,0.045) if point.y<water_y-0.06 else Color(0.6,0.16,0.13)
	var up:=normal.normalized()
	var side:=up.cross(Vector3.UP if absf(up.y)<0.9 else Vector3.RIGHT).normalized()
	decal.global_transform=Transform3D(Basis(side,up,side.cross(up)).rotated(up,randf()*TAU),point+up*0.02)
	decal.size=Vector3(size,0.3,size)
	if grow>0.0:
		create_tween().tween_property(decal,"size",Vector3(grow,0.3,grow),6.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)

func _btex(name: String) -> Texture2D:
	if not _blood_tex.has(name): _blood_tex[name]=load(BLOOD_DIR+name+".png")
	return _blood_tex[name]

func _splat_decal() -> Decal:
	var decal: Decal
	if _splats.size()<SPLAT_MAX:
		decal=Decal.new()
		decal.cull_mask=1
		decal.layers=1<<19
		decal.upper_fade=0.25
		decal.lower_fade=0.25
		decal.normal_fade=0.6       # přes roh se nepromítat
		decal.distance_fade_enabled=true
		decal.distance_fade_begin=24.0
		decal.distance_fade_length=8.0
		decal.texture_orm=load("res://textures/walldecals/rough_orm.png")
		add_child(decal)
		_splats.append(decal)
	else:
		decal=_splats[_splat_next]
		_splat_next=(_splat_next+1)%SPLAT_MAX
		var old: Tween=decal.get_meta("tween",null)
		if old and old.is_valid(): old.kill()
	return decal

func _fresh(point: Vector3) -> Color:
	# Čerstvá krev: sytě tmavě rudá, mokrá; pod vodou skoro černá.
	return Color(0.2,0.03,0.03) if point.y<water_y-0.06 else Color(0.62,0.07,0.06)

func splatter(point: Vector3, normal: Vector3, direction: Vector3, size: float, burst: bool=false) -> void:
	# Rozprsknutí krve z textury: směrové stříkance se natočí podle letu střely po zdi.
	if point.y<water_y-0.6: return
	var n:=normal.normalized()
	var name: String
	var spin:=randf()*TAU
	var flat:=direction-n*direction.dot(n)
	if burst or flat.length()<0.15:
		name=BURSTS[randi()%BURSTS.size()]
	else:
		var pick: Array=SPRAYS[randi()%SPRAYS.size()]
		name=pick[0]
		var frame: Basis=BloodDressing.orient(n,0.0)
		var beta:=atan2(flat.dot(frame.z),flat.dot(frame.x))
		spin=float(pick[1])-beta+randf_range(-0.15,0.15)
	var decal:=_splat_decal()
	decal.texture_albedo=_btex(name)
	decal.modulate=_fresh(point)
	decal.albedo_mix=1.0
	var tex: Texture2D=decal.texture_albedo
	var aspect:=float(tex.get_width())/maxf(1.0,float(tex.get_height()))
	decal.size=Vector3(size*aspect,0.22,size)
	decal.global_transform=Transform3D(BloodDressing.orient(n,spin),point+n*0.02)
	# Rozprsk se během zlomku vteřiny „rozlije“ do plné velikosti.
	var final_size:=decal.size
	decal.size=final_size*0.55
	var tw:=create_tween()
	tw.tween_property(decal,"size",final_size,0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	decal.set_meta("tween",tw)
	# Na zdi pak krev pomalu stéká dolů.
	if absf(n.y)<0.35 and randf()<0.75: run(point+Vector3.DOWN*size*0.15,n,size*0.6)

func run(point: Vector3, normal: Vector3, width: float) -> void:
	# Stékající krev: stružky rostou dolů několik vteřin.
	if point.y<water_y+0.05: return
	var decal:=_splat_decal()
	decal.texture_albedo=_btex(RUNS[randi()%RUNS.size()])
	decal.modulate=_fresh(point)*Color(0.9,0.9,0.9)
	decal.albedo_mix=1.0
	var n:=normal.normalized()
	var length:=randf_range(0.6,1.3)*width*2.0
	decal.size=Vector3(width,0.22,width*0.25)
	var top:=point+n*0.021
	decal.global_transform=Transform3D(BloodDressing.orient(n,0.0),top+Vector3.DOWN*width*0.125)
	var tw:=create_tween().set_parallel(true)
	var secs:=randf_range(3.0,6.0)
	tw.tween_property(decal,"size",Vector3(width,0.22,length),secs).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(decal,"global_position",top+Vector3.DOWN*length*0.5,secs).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	decal.set_meta("tween",tw)

func blood(point: Vector3, direction: Vector3, lethal: bool) -> void:
	var spray: Array=_sprays[_spray_next]
	_spray_next=(_spray_next+1)%_sprays.size()
	for emitter in spray:
		emitter.global_position=point
		emitter.direction=direction
		emitter.restart()
	var space:=get_world_3d().direct_space_state
	# Cákanec na zdi za zombie a kapky na zemi pod ránou.
	var scatter:=(direction+Vector3(randf_range(-0.15,0.15),randf_range(-0.2,0.05),randf_range(-0.15,0.15))).normalized()
	var behind: Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(point,point+scatter*3.5,1))
	if not behind.is_empty():
		# Čím blíž je zeď, tím hustší a menší rozprsk; z dálky se kapky rozletí víc.
		var d: float=point.distance_to(behind.position)
		var size:=lerpf(0.8,1.6,clampf(d/3.5,0.0,1.0))*(1.35 if lethal else 1.0)
		splatter(behind.position,behind.normal,scatter,size,d<0.5)
		# Zabití u zdi: velký rozprsk navíc.
		if lethal and d<1.6: splatter(behind.position+Vector3(randf_range(-0.2,0.2),randf_range(-0.1,0.2),randf_range(-0.2,0.2)),behind.normal,scatter,size*1.4,true)
	if lethal or randf()<0.6:
		var spot:=point+direction*randf_range(0.2,0.9)
		var below: Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(spot,spot+Vector3.DOWN*2.5,1))
		if not below.is_empty(): mark(below.position,below.normal,randf_range(0.25,0.5))

func pool(victim: Node3D) -> void:
	# Kaluž, která se pomalu rozlévá pod ležícím tělem.
	await get_tree().create_timer(1.6).timeout
	if not is_instance_valid(victim): return
	var hips: Vector3=victim.bodies[0].global_position
	var below: Dictionary=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(hips+Vector3.UP*0.3,hips+Vector3.DOWN*1.5,1))
	if below.is_empty() or below.position.y<water_y-0.6: return
	# Kaluž z textury, která se pod tělem pomalu rozlévá (ve vodě se nekreslí, rozpustí se).
	var decal:=_splat_decal()
	decal.texture_albedo=_btex("smears_06_blood_pool")
	decal.modulate=_fresh(below.position)*Color(0.85,0.85,0.85)
	decal.albedo_mix=1.0
	decal.global_transform=Transform3D(BloodDressing.orient(Vector3.UP,randf()*TAU),below.position+Vector3.UP*0.02)
	var final:=randf_range(1.3,1.9)
	decal.size=Vector3(0.3,0.22,0.3)
	var tw:=create_tween()
	tw.tween_property(decal,"size",Vector3(final,0.22,final),14.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	decal.set_meta("tween",tw)

func shot(origin: Vector3, hit: Vector3, solid: bool) -> bool:
	# Svítící stopa střely od ústí hlavně; vrací, zda vznikl prach z dopadu.
	var length:=origin.distance_to(hit)
	if length>1.5:
		var tracer: MeshInstance3D=_tracers[_tracer_next]
		_tracer_next=(_tracer_next+1)%_tracers.size()
		var streak:=minf(length*0.5,9.0)
		var to:=hit-(hit-origin).normalized()*streak*0.5
		tracer.look_at_from_position(origin.lerp(hit,0.12),hit,Vector3.UP if absf((hit-origin).normalized().y)<0.98 else Vector3.RIGHT)
		tracer.scale=Vector3(1,1,streak)
		tracer.visible=true
		var fly:=create_tween()
		fly.tween_property(tracer,"global_position",to,clampf(length/260.0,0.02,0.09))
		fly.tween_callback(tracer.hide)
	if not solid: return false
	var puff: CPUParticles3D=_puffs[_puff_next]
	_puff_next=(_puff_next+1)%_puffs.size()
	puff.global_position=hit
	puff.direction=(origin-hit).normalized()
	puff.restart()
	return true
