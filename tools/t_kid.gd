extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run():
	var w:=Node3D.new(); root.add_child(w)
	var env:=WorldEnvironment.new(); var e:=Environment.new(); e.background_mode=Environment.BG_COLOR; e.background_color=Color(0.3,0.3,0.32); e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color=Color(0.7,0.7,0.7); env.environment=e; w.add_child(env)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-30,20,0); w.add_child(sun)
	var Z=load("res://scripts/zombie.gd")
	var kid: Node3D=load("res://assets/zombie/types/kid.scn").instantiate(); w.add_child(kid)
	var adult: Node3D=load("res://assets/zombie/zombie.fbx").instantiate(); w.add_child(adult); adult.position.x=50.0
	var ap: AnimationPlayer=kid.get_node("AnimationPlayer"); ap.add_animation_library("z",Z._anims_for(0.647))
	var ap2: AnimationPlayer=adult.get_node("AnimationPlayer"); ap2.add_animation_library("z",Z._anims_for(1.0))
	var cam:=Camera3D.new(); w.add_child(cam); cam.current=true
	var i:=0
	for c in [["z/walk",0.3],["z/walk",0.9],["z/attack",1.0],["z/run",0.4],["z/crawl",0.5]]:
		ap.play(c[0]); ap.seek(c[1],true); ap2.play(c[0]); ap2.seek(c[1],true)
		for v in [Vector3(0.6,1.0,3.2),Vector3(3.2,1.0,0.6)]:
			cam.look_at_from_position(v*0.55-Vector3(0.3,0,0),Vector3(0,0.7,0),Vector3.UP)
			for f in 4: await process_frame
			root.get_viewport().get_texture().get_image().save_png("/tmp/ws/kidz_%d.png"%i); i+=1
	quit()
