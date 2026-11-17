extends SceneTree
class Stub extends Node3D:
	var tile_mat:=StandardMaterial3D.new()
	func _surface(_k): 
		var m:=StandardMaterial3D.new(); m.albedo_color=Color(0.4,0.2,0.1); return m
func _init():
	var world:=Node3D.new(); root.add_child(world)
	var env:=WorldEnvironment.new(); env.environment=Environment.new(); env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(0.2,0.2,0.22); env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color=Color.WHITE; env.environment.ambient_light_energy=0.8; world.add_child(env)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-40,-30,0); world.add_child(sun)
	var wall:=MeshInstance3D.new(); var bm:=BoxMesh.new(); bm.size=Vector3(4,3,0.2); wall.mesh=bm; wall.position=Vector3(0,1.5,-0.1); world.add_child(wall)
	var fl:=MeshInstance3D.new(); var fm:=BoxMesh.new(); fm.size=Vector3(4,0.2,3); fl.mesh=fm; fl.position=Vector3(0,-0.1,1.5); world.add_child(fl)
	var stub:=Stub.new(); stub.tile_mat.albedo_color=Color(0.85,0.87,0.85); world.add_child(stub)
	var M=load("res://scripts/zombie_mode.gd")
	var mode=M.new()
	mode.main=stub
	var blood: Node3D=load("res://scripts/blood_dressing.gd").new(); world.add_child(blood)
	mode._breach(Vector3(0,0,0),Vector3(0,0,1),blood)
	var cam:=Camera3D.new(); world.add_child(cam); cam.current=true
	cam.look_at_from_position(Vector3(0.8,1.4,2.8),Vector3(0,0.7,0))
	for i in 6: await process_frame
	root.get_texture().get_image().save_png("/tmp/ws/breach.png")
	quit()
