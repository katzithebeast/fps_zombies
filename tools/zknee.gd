extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func ang(z,a: String,b: String,c: String) -> float:
	# znaménkový ohyb kolem osy "vlevo" postavy: + = správný směr pro koleno (pata dozadu)
	var pa: Vector3=z.bodies[z._ids[a]].global_transform*(z.bodies[z._ids[a]].body_offset.affine_inverse().origin)
	var pb: Vector3=z.bodies[z._ids[b]].global_transform*(z.bodies[z._ids[b]].body_offset.affine_inverse().origin)
	var pc: Vector3=z.bodies[z._ids[c]].global_transform*(z.bodies[z._ids[c]].body_offset.affine_inverse().origin)
	var u:=(pb-pa).normalized()
	var v:=(pc-pb).normalized()
	var hips: PhysicalBone3D=z.bodies[0]
	var axis: Vector3=z.bodies[z._ids[a]].global_basis*z.get_meta("ax_"+a)
	return rad_to_deg(u.signed_angle_to(v,axis))
func run() -> void:
	var fb:=StaticBody3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(30,0.5,30)
	var cs:=CollisionShape3D.new()
	cs.shape=shape
	fb.add_child(cs)
	root.add_child(fb)
	fb.position.y=-0.25
	for cfg in [["Spine2",3,1.0],["Spine2",3,-1.0],["Head",1,1.0],["LeftLeg",3,1.0]]:
		var z: Node3D=preload("res://scripts/zombie.gd").new()
		root.add_child(z)
		await create_timer(0.3).timeout
		var bone: int=z.skeleton.find_bone("mixamorig_"+cfg[0])
		for i in cfg[1]:
			z.hit(bone,z.skeleton.global_transform*z.bone_pose(bone).origin,Vector3.FORWARD*cfg[2],1.0)
			if i<cfg[1]-1: await create_timer(0.2).timeout
		await physics_frame
		await physics_frame
		# osa ohybu = osa X postavy vyjádřená v lokálním prostoru stehna/paže (drží se s tělem)
		for a in ["LeftUpLeg","RightUpLeg"]:
			z.set_meta("ax_"+a,z.bodies[z._ids[a]].global_basis.inverse()*z.skeleton.global_basis.x)
		for side in ["Left","Right"]:
			var b0: Vector3=z.bodies[z._ids[side+"Arm"]].global_basis.y
			var b1: Vector3=z.bodies[z._ids[side+"ForeArm"]].global_basis.y
			z.set_meta("ax_"+side+"Arm",z.bodies[z._ids[side+"Arm"]].global_basis.inverse()*b0.cross(b1).normalized())
		var toe: int=z.skeleton.find_bone("mixamorig_LeftToeBase")
		var foot: int=z.skeleton.find_bone("mixamorig_LeftFoot")
		print("toe-foot local: ",z.bone_pose(toe).origin-z.bone_pose(foot).origin," leftfoot x=",z.bone_pose(foot).origin.x)
		var names:=[["LeftUpLeg","LeftLeg","LeftFoot"],["RightUpLeg","RightLeg","RightFoot"],["LeftArm","LeftForeArm","LeftHand"],["RightArm","RightForeArm","RightHand"]]
		var lo:=[999.0,999.0,999.0,999.0]
		var hi:=[-999.0,-999.0,-999.0,-999.0]
		var first:=[]
		for n in names: first.append(ang(z,n[0],n[1],n[2]))
		for f in 240:
			await physics_frame
			for k in 4:
				var v:=ang(z,names[k][0],names[k][1],names[k][2])
				lo[k]=minf(lo[k],v)
				hi[k]=maxf(hi[k],v)
		print(cfg[0]," dir=",cfg[2])
		for k in 4: print("   %s start=%.0f min=%.0f max=%.0f"%[names[k][1],first[k],lo[k],hi[k]])
		z.queue_free()
		await process_frame
	quit()
