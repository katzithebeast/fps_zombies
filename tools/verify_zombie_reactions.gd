extends SceneTree
## Reakce zombie: vrávorání se skutečnými kroky, pád a vstávání, smrt animací, krmení, útoky,
## zrcadlené klipy.   godot --headless --fixed-fps 60 --path . --script res://tools/verify_zombie_reactions.gd
var failures:=0
const Z:=preload("res://scripts/zombie.gd")
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")

func spawn(at:=Vector3.ZERO) -> Node3D:
	var z: Node3D=Z.new()
	z.position=at
	root.add_child(z)
	return z

func wait(t: float) -> void:
	for i in int(t*60.0): await physics_frame

func foot(z: Node3D, side: String) -> Vector3:
	return z.skeleton.global_transform*z.bone_pose(z._ids[side+"Foot"]).origin

func run() -> void:
	var floor_body:=StaticBody3D.new()
	var cs:=CollisionShape3D.new(); var bs:=BoxShape3D.new(); bs.size=Vector3(40,1,40); cs.shape=bs; cs.position.y=-0.5
	floor_body.add_child(cs); root.add_child(floor_body)
	var lib: AnimationLibrary=Z._anims_for(1.0)
	for a in ["idle_m","walk_m","run_m","attack_m","neck_bite","neck_bite_m","bite","bite2","death","dying","dying_m","stagger_back","stagger_left","stagger_right","getup_front","getup_back"]:
		check(lib.has_animation(a),"clip %s exists"%a)
	check((lib.get_animation("stagger_back").get_meta("root_motion") as PackedVector3Array).size()>30,"stagger clip carries root motion")

	# --- vrávorání: rána zepředu, dva kroky vzad, chodidla nekloužou
	var z:=spawn()
	await wait(0.4)
	var chest: int=z._ids.Spine2
	var start: Vector3=z.global_position
	z.hit(chest,z.bodies[chest].global_position,Vector3.FORWARD,1.0,50.0)
	check(z._stagger_clip.begins_with("stagger_back"),"AK body hit from the front staggers back (%s)"%z._stagger_clip)
	var slide:=0.0
	var prev_r:=foot(z,"Right")
	var prev_l:=foot(z,"Left")
	for i in 80:
		await physics_frame
		var r:=foot(z,"Right"); var l:=foot(z,"Left")
		# kotník, který se nehýbe nahoru (stojí), nesmí ujíždět po zemi
		if r.y<0.14 and prev_r.y<0.14: slide=maxf(slide,Vector2(r.x-prev_r.x,r.z-prev_r.z).length())
		if l.y<0.14 and prev_l.y<0.14: slide=maxf(slide,Vector2(l.x-prev_l.x,l.z-prev_l.z).length())
		prev_r=r; prev_l=l
	var moved: Vector3=z.global_position-start
	check(moved.z<-0.35,"root stepped back with the clip (%.2f m)"%moved.z)
	check(slide<0.035,"planted feet do not slide during stagger (max %.3f m per frame)"%slide)
	await wait(0.6)
	check(z._stagger_clip=="" and not z.dead,"stagger finishes and zombie carries on")
	z.queue_free()

	# --- rána z boku
	z=spawn(Vector3(4,0,0))
	await wait(0.4)
	z.hit(chest,z.bodies[chest].global_position,Vector3.RIGHT,1.0,50.0)
	check(z._stagger_clip.begins_with("stagger_left"),"bullet travelling +X pushes the zombie to its left (%s)"%z._stagger_clip)
	z.queue_free()

	# --- pád a vstávání: noha + trup
	z=spawn(Vector3(-4,0,0))
	await wait(0.4)
	var thigh: int=z._ids.LeftUpLeg
	z.hit(thigh,z.bodies[thigh].global_position,Vector3.FORWARD,1.0,50.0)
	z.hit(chest,z.bodies[chest].global_position,Vector3.FORWARD,1.0,50.0)
	check(z._ragdolled and z._knocked and not z.dead,"leg + body hit knocks the zombie down")
	await wait(1.6)
	var head_y: float=(z.skeleton.global_transform*z.bone_pose(z._ids.Head).origin).y
	check(head_y<0.7,"knocked zombie lies on the floor (head %.2f m)"%head_y)
	var t:=0.0
	while z._ragdolled and t<8.0:
		await physics_frame
		t+=1.0/60.0
	head_y=(z.skeleton.global_transform*z.bone_pose(z._ids.Head).origin).y
	check(not z._ragdolled and head_y>1.4,"zombie gets back up (%.1f s, head %.2f m)"%[t,head_y])
	z.queue_free()

	# --- rána do vstávající zombie ji znovu srazí
	z=spawn(Vector3(-8,0,0))
	await wait(0.4)
	z.hit(thigh,z.bodies[thigh].global_position,Vector3.FORWARD,1.0,50.0)
	z.hit(chest,z.bodies[chest].global_position,Vector3.FORWARD,1.0,50.0)
	t=0.0
	while not (z._rag_rise and not z.simulator.active) and t<6.0:
		await physics_frame
		t+=1.0/60.0
	z.health=500.0
	z.hit(chest,z.skeleton.global_transform*z.bone_pose(chest).origin,Vector3.FORWARD,1.0,50.0)
	check(z._knocked and not z._rag_rise,"heavy hit during the get-up knocks it down again")
	z.queue_free()

	# --- smrt animací a předání fyzice
	Z.death_anims=true
	var got:=0
	for attempt in 12:
		z=spawn(Vector3(8,0,attempt*2.0))
		await wait(0.3)
		z.health=1.0
		z.hit(chest,z.bodies[chest].global_position,Vector3.FORWARD,0.8,20.0)
		await physics_frame
		await physics_frame
		if z._death_anim!="":
			got+=1
			check(z.dead and not z.simulator.is_simulating_physics(),"death animation plays before physics (%s)"%z._death_anim)
			t=0.0
			while z._death_anim!="" and t<3.0:
				await physics_frame
				t+=1.0/60.0
			check(z.simulator.is_simulating_physics(),"death animation hands over to ragdoll after %.2f s"%t)
			z.queue_free()
			break
		z.queue_free()
	check(got>0,"weak killing shots sometimes play a death animation")
	z=spawn(Vector3(12,0,0))
	await wait(0.3)
	z.health=1.0
	var head: int=z._ids.Head
	z.hit(head,z.bodies[head].global_position,Vector3.FORWARD,1.0,50.0)
	await physics_frame
	await physics_frame
	check(z._death_anim=="" and z.simulator.is_simulating_physics(),"headshot drops straight into physics")
	z.queue_free()

	# --- brokovnice: devět broků naráz – silnou zombii srazí, slabou zabije rovnou fyzikou
	z=spawn(Vector3(16,0,0))
	await wait(0.3)
	z.health=400.0
	for i in 9: z.hit(chest,z.bodies[chest].global_position,Vector3.FORWARD,0.45,36.0)
	check(z._knocked and not z.dead,"close shotgun blast knocks a tough zombie down")
	z.queue_free()
	z=spawn(Vector3(16,0,4))
	await wait(0.3)
	for i in 9: z.hit(chest,z.bodies[chest].global_position,Vector3.FORWARD,0.45,36.0)
	await physics_frame
	await physics_frame
	check(z.dead and z._death_anim=="","shotgun kill is violent: straight into physics, no death animation")
	z.queue_free()

	# --- krmení: výstřel nablízku ji vyruší
	z=spawn(Vector3(0,0,10))
	await wait(0.2)
	z.feed()
	await wait(0.5)
	check(z.feeding and z._clip=="bite2","feeder crouches over a body")
	Z.noise(z.global_position+Vector3(6,0,0),18.0)
	check(not z.feeding and z._feed_rise_t>0.0,"gunshot nearby makes the feeder stand up")
	await wait(1.6)
	check(z.ai and z._feed_rise_t<=0.0,"feeder joins the hunt after standing up")
	z.queue_free()

	# --- útoky: chycení zraní dvakrát (chycení + kousnutí)
	var goal:=Node3D.new(); root.add_child(goal)
	goal.position=Vector3(0,0,-14.0+1.25)
	z=spawn(Vector3(0,0,-14))
	z.target=goal
	z.force_attack="grab"
	var hits:=[]
	z.attacked.connect(func(d: float): hits.append(d))
	z.alert(false)
	await wait(3.6)
	check(hits.size()>=2 and float(hits[0])<float(hits[1]),"grab attack hurts twice, the bite more than the grab: %s"%str(hits))
	z.force_attack="swipe"
	hits.clear()
	await wait(2.2)
	check(hits.size()>=1,"swipe attack lands")
	print("ZOMBIE REACTIONS FINISHED failures=%d"%failures)
	quit()
