extends SceneTree
## Živé zásahy: strana těla, skutečný zasažený článek, směr, návrat a série ran.
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func restore(z: Node3D, pose: Array) -> void:
	for id in pose.size(): z.skeleton.set_bone_pose(id,pose[id])
func run() -> void:
	var script:=preload("res://scripts/zombie.gd")
	for kind in script.TYPES:
		var z: Node3D=script.new()
		z.kind=kind
		z.health=1000.0
		root.add_child(z)
		z.set_physics_process(false)
		z._animation.seek(0.0,true)
		var pose:=[]
		for id in z.skeleton.get_bone_count(): pose.append(z.skeleton.get_bone_pose(id))
		for side in ["Left","Right"]:
			var knee: int=z._ids[side+"Leg"]
			var thigh: int=z._ids[side+"UpLeg"]
			var other: int=z._ids[("Right" if side=="Left" else "Left")+"Leg"]
			restore(z,pose)
			z._reactions.clear()
			z.hit(knee,z.skeleton.global_transform*z.bone_pose(knee).origin,Vector3.FORWARD,1.0,8.0)
			z._update_reactions(0.08)
			var knee_kick: float=pose[knee].basis.get_rotation_quaternion().angle_to(z.skeleton.get_bone_pose_rotation(knee))
			var other_kick: float=pose[other].basis.get_rotation_quaternion().angle_to(z.skeleton.get_bone_pose_rotation(other))
			check(knee_kick>0.08 and knee_kick>other_kick+0.05 and not z.dead,"%s %s calf jerks independently (%.2f rad, other %.2f)"%[kind,side,knee_kick,other_kick])
			# Stehno má vlastní směrový pohyb; ne stejnou animaci pro přední a zadní zásah.
			var deflections:=[]
			for direction in [Vector3.FORWARD,Vector3.BACK]:
				restore(z,pose)
				z._reactions.clear()
				var original: Vector3=z.bone_pose(knee).origin-z.bone_pose(thigh).origin
				z.hit(thigh,z.skeleton.global_transform*z.bone_pose(thigh).origin,direction,1.0,8.0)
				z._update_reactions(0.08)
				var moved: Vector3=z.bone_pose(knee).origin-z.bone_pose(thigh).origin
				deflections.append(moved.z-original.z)
			check(deflections[0]<-0.003 and deflections[1]>0.003,"%s %s thigh follows opposite impact directions"%[kind,side])
			# Přirozený návrat do animace a zachování délky končetin.
			restore(z,pose)
			z._update_reactions(1.5)
			check(z.skeleton.get_bone_pose_rotation(thigh).angle_to(pose[thigh].basis.get_rotation_quaternion())<0.02,"%s reaction decays back to locomotion"%kind)
			z._reactions.clear()
			restore(z,pose)
			for i in 6: z._react(knee,Vector3(0,0.5,0),Vector3.FORWARD,2.0,"leg")
			z._update_reactions(0.08)
			check(pose[knee].basis.get_rotation_quaternion().angle_to(z.skeleton.get_bone_pose_rotation(knee))<0.96,"%s burst cannot over-rotate knee"%kind)
		z.free()
	print("HIT REACTIONS failures=",failures)
	quit(1 if failures else 0)
