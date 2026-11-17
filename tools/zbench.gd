extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func window(label: String) -> void:
	await create_timer(1.2).timeout
	var total:=0.0
	for i in 3:
		await create_timer(1.01).timeout
		total+=Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0
	print(label,": %.2f ms/snimek"%(total/3))
func run() -> void:
	var fb:=StaticBody3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(80,0.5,80)
	var cs:=CollisionShape3D.new()
	cs.shape=shape
	fb.add_child(cs)
	root.add_child(fb)
	fb.position.y=-0.25
	var goal:=Node3D.new()
	root.add_child(goal)
	goal.position=Vector3(0,0,60)
	var script: GDScript=load("res://scripts/zombie.gd")
	var all:=[]
	var worst:=0.0
	var sum:=0.0
	for i in 12:
		var t0:=Time.get_ticks_usec()
		var z: Node3D=script.new()
		z.position=Vector3((i%4)*1.5-2.25,0,-(i/4)*1.5)
		z.target=goal
		z.runner=i%3==0
		root.add_child(z)
		z.alert(false)
		var cost:=(Time.get_ticks_usec()-t0)/1000.0
		worst=maxf(worst,cost)
		sum+=cost
		all.append(z)
		await physics_frame
	print("spawn: prumer %.1f ms, nejhorsi %.1f ms"%[sum/12,worst])
	await window("12 zombie zije")
	sum=0.0
	worst=0.0
	for z in all:
		var bone: int=z.skeleton.find_bone("mixamorig_Spine2")
		z.health=1
		z.hit(bone,z.global_position+Vector3.UP*1.3,Vector3.FORWARD,1.0)
		var t0:=Time.get_ticks_usec()
		await physics_frame
		var cost:=(Time.get_ticks_usec()-t0)/1000.0
		worst=maxf(worst,cost)
		sum+=cost
	print("smrt (snimek se zabitim): prumer %.1f ms, nejhorsi %.1f ms"%[sum/12,worst])
	await create_timer(0.3).timeout
	var t:=0.0
	for i in 1: t=Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0
	await create_timer(1.0).timeout
	print("12 ragdollu pada: %.2f ms/snimek"%(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0))
	await create_timer(4.0).timeout
	await window("12 mrtvol lezi")
	quit()
