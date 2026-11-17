extends SceneTree
var failures:=0
func _initialize() -> void:
	call_deferred("verify")
func check(ok: bool,message: String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok: failures+=1
func verify() -> void:
	var floor_body:=StaticBody3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(12,0.5,12)
	var collision:=CollisionShape3D.new()
	collision.shape=shape
	floor_body.add_child(collision)
	root.add_child(floor_body)
	floor_body.position.y=-0.25
	var zombie: Node3D=preload("res://scripts/zombie.gd").new()
	root.add_child(zombie)
	await create_timer(0.5).timeout
	check(zombie.bodies.size()==17,"ragdoll has 17 articulated body parts, including neck and hands")
	var valid:=true
	for body in zombie.bodies.values():
		print("PHYSICAL ",body.name," bone_id ",body.get_bone_id())
		valid=valid and body.get_bone_id()>=0
	check(valid,"all physical bodies bind to skeleton bones")
	var head: int=zombie.skeleton.find_bone("mixamorig_Head")
	var before: Quaternion=zombie.skeleton.get_bone_pose_rotation(head)
	await create_timer(0.5).timeout
	check(before.angle_to(zombie.skeleton.get_bone_pose_rotation(head))>0.001,"idle animates head over time")
	var chest: int=zombie.skeleton.find_bone("mixamorig_Spine2")
	var point: Vector3=zombie.skeleton.global_transform*zombie.bone_pose(chest).origin
	zombie.hit(chest,point,Vector3.FORWARD)
	check(zombie.health==50 and not zombie.dead,"first body shot damages without killing")
	zombie.hit(chest,point,Vector3.FORWARD)
	await physics_frame
	await physics_frame
	check(zombie.dead and zombie.simulator.is_simulating_physics(),"second body shot starts real physics simulation")
	var initial: Vector3=zombie.bodies[head].global_position
	await create_timer(3.5).timeout
	var final_head: Vector3=zombie.bodies[head].global_position
	print("HEAD fall ",initial," -> ",final_head)
	check(final_head.y<0.65 and initial.distance_to(final_head)>0.5,"ragdoll falls and rests on ground")
	var finite:=true
	for body in zombie.bodies.values(): finite=finite and body.global_position.is_finite() and body.global_position.y>-0.4
	check(finite,"all body parts remain finite and above floor")
	zombie.queue_free()
	await process_frame
	var other: Node3D=preload("res://scripts/zombie.gd").new()
	root.add_child(other)
	await physics_frame
	other.hit(head,Vector3(0,1.9,0),Vector3.FORWARD)
	await physics_frame
	await physics_frame
	check(other.dead,"headshot kills immediately")
	print("ZOMBIE FINISHED failures=",failures)
	quit(1 if failures else 0)
