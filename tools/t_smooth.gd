extends SceneTree
## Plynulost pohybu zombie tak, jak se skutečně vykreslí (póza kostry po fyzice), snímek po snímku.
## Hledá „švy“: snímek, kde se kost pohne skokem oproti okolním snímkům (přepnutí animace,
## nástup / konec fyziky, vstávání). Scénáře: zásahy různými zbraněmi do různých míst.
##   godot --headless --fixed-fps 60 --path . --script res://tools/t_smooth.gd [-- --only=jméno --trace]
const Z:=preload("res://scripts/zombie.gd")
const BONES:=["Hips","Spine2","Head","LeftArm","LeftForeArm","RightForeArm","RightHand","LeftLeg","RightFoot"]
const DEV:=["Spine2","Head","LeftArm","LeftForeArm","RightForeArm"]
var dev:={}         # největší odchylka vykreslené pózy od animace (°) – jak moc rána tělem hnula
var z: Node3D
var frames:={}       # process frame -> {bone: Transform3D}
var states:={}
var args:={}
func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv:=a.trim_prefix("--").split("=",true,1)
		args[kv[0]]=kv[1] if kv.size()>1 else "1"
	call_deferred("run")

func snap() -> void:
	if z==null or not is_instance_valid(z): return
	var f:=Engine.get_process_frames()
	var d:={}
	for n in BONES:
		var b: int=z.skeleton.find_bone("mixamorig_"+n)
		d[n]=z.skeleton.global_transform*z.skeleton.get_bone_global_pose(b)
	frames[f]=d
	if z._hitrag_on:
		var G: Array=z._anim_globals()
		for n in DEV:
			var b: int=z.skeleton.find_bone("mixamorig_"+n)
			var a: Basis=(G[b] as Transform3D).basis.orthonormalized()
			var r: Basis=z.skeleton.get_bone_global_pose(b).basis.orthonormalized()
			dev[n]=maxf(float(dev.get(n,0.0)),rad_to_deg(a.get_rotation_quaternion().angle_to(r.get_rotation_quaternion())))
	states[f]="%s%.2f%s%s%s%s"%["H" if z._hitrag_on else "-",z.simulator.influence,"S" if z._stagger_clip!="" else "-","R" if z._ragdolled else "-","D" if z.dead else "-",z._clip.left(10)]

## weapon: [poškození, síla, broky]
const W:={"mp40":[38.0,1.0,1],"ak":[50.0,1.0,1],"deagle":[130.0,1.0,1],"izh54":[32.0*1.25,0.45,9]}

func shoot(weapon: String, bone_name: String, from_dir:=Vector3.FORWARD) -> void:
	var w: Array=W[weapon]
	var b: int=z._ids[bone_name]
	for p in int(w[2]):
		var body: PhysicalBone3D=z.bodies[b]
		var at: Vector3=z.skeleton.global_transform*z.bone_pose(b)*body.body_offset.origin+Vector3(randf_range(-0.04,0.04),randf_range(-0.04,0.04),0.08)
		z.hit(b,at,from_dir,float(w[1]),float(w[0]))

func scenario(name: String, hp: float, walk: bool, script: Array, length: float) -> void:
	if args.has("only") and not String(args["only"]).split(",").has(name): return
	frames.clear(); states.clear()
	var goal:=Node3D.new(); root.add_child(goal); goal.position=Vector3(0,0,30)
	z=Z.new(); z.max_health=hp; z.health=hp
	z.position=Vector3(0,0,-4)
	root.add_child(z)
	z.skeleton.skeleton_updated.connect(snap)
	if walk:
		z.target=goal; z.tier="walk"; z.alert(false)
	for i in 40: await physics_frame
	frames.clear(); states.clear(); dev.clear()
	var t:=0.0
	var si:=0
	while t<length:
		while si<script.size() and t>=float(script[si][0]):
			var s: Array=script[si]
			shoot(s[1],s[2],s[3] if s.size()>3 else Vector3.FORWARD)
			si+=1
		await physics_frame
		t+=1.0/60.0
	report(name)
	z.queue_free(); goal.queue_free()
	await process_frame

func report(name: String) -> void:
	var keys:=frames.keys()
	keys.sort()
	var worst:=[]
	for n in BONES:
		var rot:=[]   # úhlová rychlost °/snímek
		var pos:=[]   # cm/snímek
		for i in range(1,keys.size()):
			var a: Transform3D=frames[keys[i-1]][n]; var c: Transform3D=frames[keys[i]][n]
			rot.append(rad_to_deg(a.basis.get_rotation_quaternion().angle_to(c.basis.get_rotation_quaternion())))
			pos.append(a.origin.distance_to(c.origin)*100.0)
		# šev = náhlý skok rychlosti: zrychlení oproti sousedům (druhá diference)
		for i in range(1,rot.size()-1):
			var jr:=absf(rot[i]-0.5*(rot[i-1]+rot[i+1]))
			var jp:=absf(pos[i]-0.5*(pos[i-1]+pos[i+1]))
			if (jr>4.0 and rot[i]>2.0*maxf(rot[i-1],rot[i+1])) or (jp>2.5 and pos[i]>2.0*maxf(pos[i-1],pos[i+1])):
				worst.append([maxf(jr/4.0,jp/2.5),"%s f%d %.1f°/f (%.1f,%.1f) %.1fcm/f [%s→%s]"%[n,i,rot[i],rot[i-1],rot[i+1],pos[i],states.get(keys[i],""),states.get(keys[i+1],"")]])
		if args.has("trace") and n in String(args.get("tb","Spine2,LeftArm")).split(","):
			var line: String=n+":"
			for i in rot.size(): line+=" %.1f"%rot[i]
			print(line)
	worst.sort_custom(func(a,b): return a[0]>b[0])
	var dv:=""
	for n in DEV: dv+=" %s %d°"%[n,int(dev.get(n,0.0))]
	print("== %s: %d švů   | výchylka:%s"%[name,worst.size(),dv])
	for w in worst.slice(0,6): print("   ",w[1])

func run() -> void:
	var fb:=StaticBody3D.new(); var cs:=CollisionShape3D.new(); var bs:=BoxShape3D.new(); bs.size=Vector3(60,1,60); cs.shape=bs; cs.position.y=-0.5; fb.add_child(cs); root.add_child(fb)
	await scenario("ak_hrudnik_chuze",400,true,[[0.3,"ak","Spine2"]],1.6)
	await scenario("ak_davka",600,true,[[0.3,"ak","Spine2"],[0.4,"ak","Spine2"],[0.5,"ak","RightArm"],[0.6,"ak","Spine"],[0.7,"ak","Head"]],2.0)
	await scenario("mp40_paze",400,true,[[0.3,"mp40","LeftArm"],[0.42,"mp40","LeftForeArm"]],1.4)
	await scenario("ak_noha",400,true,[[0.3,"ak","RightLeg"]],1.4)
	await scenario("ak_stehno",400,true,[[0.3,"ak","LeftUpLeg"]],1.4)
	await scenario("deagle_hrudnik",400,true,[[0.3,"deagle","Spine2"]],2.0)
	await scenario("deagle_hlava",900,true,[[0.3,"deagle","Head"]],2.0)
	await scenario("brokovnice",400,true,[[0.3,"izh54","Spine2"]],4.5)
	await scenario("pad_a_vstani",400,false,[[0.3,"ak","LeftUpLeg"],[0.32,"ak","Spine2"],[0.34,"ak","Spine2"]],6.0)
	await scenario("smrt_ak",40,true,[[0.3,"ak","Spine2"]],3.0)
	await scenario("smrt_deagle",100,true,[[0.3,"deagle","Spine2"]],3.0)
	await scenario("ak_bok",400,true,[[0.3,"ak","Spine2",Vector3.RIGHT]],1.6)
	await scenario("ak_hlava",900,true,[[0.3,"ak","Head"]],1.6)
	await scenario("deagle_paze",400,true,[[0.3,"deagle","RightArm"]],1.8)
	await scenario("ak_predlokti",400,true,[[0.3,"ak","LeftForeArm"]],1.4)
	await scenario("ak_bricho",400,true,[[0.3,"ak","Spine"]],1.6)
	quit()
