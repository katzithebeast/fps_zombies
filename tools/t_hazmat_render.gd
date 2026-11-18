extends SceneTree
# Render: scientist vs hazmat v klidu a v animacích (idle, běh, krčení).
func _initialize() -> void: call_deferred("run")
func rig(scene: PackedScene, lib: AnimationLibrary, x: float, anim: String, t: float) -> Node3D:
	var m: Node3D=scene.instantiate(); root.add_child(m); m.position=Vector3(x,0,0); m.scale=Vector3.ONE*0.86
	if anim!="":
		var ap:=AnimationPlayer.new(); m.add_child(ap); ap.add_animation_library("",lib); ap.play(anim); ap.seek(t,true); ap.pause()
	return m
func run() -> void:
	root.size=Vector2i(1280,720)
	var env:=Environment.new(); env.background_mode=Environment.BG_COLOR; env.background_color=Color(0.16,0.18,0.2)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color=Color(0.6,0.65,0.7); env.ambient_light_energy=0.7
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	var we:=WorldEnvironment.new(); we.environment=env; root.add_child(we)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-35,25,0); sun.light_energy=1.3; sun.shadow_enabled=true; root.add_child(sun)
	var cam:=Camera3D.new(); root.add_child(cam); cam.current=true
	var sci: PackedScene=load("res://assets/scientist/ScientistRigged.fbx")
	var hz: PackedScene=load("res://assets/hazmat/hazmat_player.tscn")
	var sl: AnimationLibrary=load("res://assets/scientist/locomotion.res")
	var hl: AnimationLibrary=load("res://assets/hazmat/locomotion.res")
	var set_:=[["",0.0],["idle",0.5],["fast_run",0.3],["slow_run",0.55]]
	var shots:=[]
	for i in set_.size():
		rig(sci,sl,-3.6+i*2.4,set_[i][0],set_[i][1])
		var h:=rig(hz,hl,-2.6+i*2.4,set_[i][0],set_[i][1])
	var floor:=MeshInstance3D.new(); var pm:=PlaneMesh.new(); pm.size=Vector2(30,10); floor.mesh=pm; root.add_child(floor)
	cam.position=Vector3(0.0,1.05,4.6); cam.look_at(Vector3(0.0,0.8,0))
	for k in 6: await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hz_front.png")
	cam.position=Vector3(-5.5,1.0,2.6); cam.look_at(Vector3(0.0,0.75,0))
	for k in 4: await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hz_side.png")
	quit()
