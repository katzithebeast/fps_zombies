extends SceneTree
# Zombie u zdi: jak hluboko zajede nejhorší část těla do zdi (stěna x>=1.0). wall_guard zap/vyp.
const Z:=preload("res://scripts/zombie.gd")
func _initialize() -> void: call_deferred("run")
func body(pos: Vector3, size: Vector3) -> void:
	var b:=StaticBody3D.new(); var c:=CollisionShape3D.new(); var sh:=BoxShape3D.new(); sh.size=size; c.shape=sh; b.add_child(c); b.position=pos; root.add_child(b)
var worst_part:=""
func pen(z) -> float:
	var worst:=0.0
	for id in z.bodies:
		var bd=z.bodies[id]
		var t: Transform3D=z.skeleton.global_transform*z.bone_pose(id)*bd.body_offset
		var h: float=bd.get_meta("half"); var r: float=bd.get_meta("radius")
		for e in [-1.0,0.0,1.0]:
			var p: Vector3=t.origin+t.basis.y.normalized()*h*e
			if p.x+r-1.0>worst:
				worst=p.x+r-1.0; worst_part="%s%+d" % [bd.get_meta("part_name"),int(e)]
	return worst
func scenario(name: String, guard: bool, setup: Callable, secs: float, orbit:=false) -> float:
	Z.wall_guard=guard
	var z=Z.new(); root.add_child(z)
	var tg:=Node3D.new(); root.add_child(tg)
	await physics_frame
	setup.call(z,tg)
	z.target=tg
	var xs:=[]; var wp:=""; var worst:=0.0; var tt:=0.0; var frames:=0; var badf:=0
	while tt<secs:
		await physics_frame
		tt+=1.0/60.0
		if orbit: tg.global_position=z.global_position+Vector3(cos(tt*1.3),0,sin(tt*1.3))*2.5
		if tt>0.5:
			var p: float=pen(z); frames+=1
			if p>worst: worst=p; wp=worst_part
			if p>0.02: badf+=1
			if tt>secs-1.5: xs.append(z.global_position)
	var jit:=0.0
	for i in range(2,xs.size()): jit=maxf(jit,((xs[i]-xs[i-1])-(xs[i-1]-xs[i-2])).length())
	print("trhani(max zmena rychlosti/snimek) %.4f m" % jit)
	print("%-28s guard=%-5s max zajeti %.3f m, snimku >2cm: %d/%d  pos.x %.2f  %s" % [name,str(guard),worst,badf,frames,z.global_position.x,wp])
	z.queue_free(); tg.queue_free()
	await physics_frame
	return worst
func run() -> void:
	Engine.physics_ticks_per_second=60
	body(Vector3(0,-0.25,0),Vector3(30,0.5,30))
	body(Vector3(1.4,1.5,0),Vector3(0.8,3,30))        # zeď, líc x=1.0
	await physics_frame
	await physics_frame
	for g in [true]:
		await scenario("chodec tlačí do zdi",g,func(z,tg): z.global_position=Vector3(0.2,0,0); z.ai=true; z.tier="walk"; tg.global_position=Vector3(4,0,0.5),4.0)
		await scenario("sprinter tlačí do zdi",g,func(z,tg): z.global_position=Vector3(-2,0,0); z.ai=true; z.tier="sprint"; tg.global_position=Vector3(4,0,0.3),4.0)
		await scenario("útok podél zdi",g,func(z,tg): z.global_position=Vector3(0.62,0,0); z.ai=true; z.tier="jog"; tg.global_position=Vector3(0.62,0,1.3),4.0)
		await scenario("plazivec tlačí do zdi",g,func(z,tg): z.global_position=Vector3(-1,0,0); z.ai=true; z.crawling=true; tg.global_position=Vector3(4,0,0.6),5.0)
		await scenario("plazivec se točí u zdi",g,func(z,tg): z.global_position=Vector3(0.4,0,0); z.ai=true; z.crawling=true,6.0,true)
		body(Vector3(-0.6,1.5,0),Vector3(0.8,3,30))   # protější zeď: chodba 1.2 m (líc x=-0.2)
		await scenario("plazivec v chodbě 1.2 m",g,func(z,tg): z.global_position=Vector3(0.4,0,0); z.ai=true; z.crawling=true,6.0,true)
		await scenario("sprinter v chodbě 1.2 m",g,func(z,tg): z.global_position=Vector3(0.4,0,0); z.ai=true; z.tier="sprint",6.0,true)
		await scenario("sprinter krouží u zdi",g,func(z,tg): z.global_position=Vector3(0.5,0,0); z.ai=true; z.tier="sprint",6.0,true)
	quit()
