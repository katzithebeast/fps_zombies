extends SceneTree
const NAMES:=["clock","valve","fuse"]
func _bounds(root: Node3D) -> AABB:
	var b:=AABB(); var first:=true
	for m in root.find_children("*","MeshInstance3D",true,false):
		var a:AABB=(m as MeshInstance3D).global_transform*(m as MeshInstance3D).get_aabb()
		if first: b=a; first=false
		else: b=b.merge(a)
	return b
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var w:=Node3D.new(); root.add_child(w)
	var env:=WorldEnvironment.new(); var e:=Environment.new(); e.background_mode=Environment.BG_COLOR; e.background_color=Color(0.25,0.27,0.3); e.ambient_light_color=Color(0.6,0.6,0.65); e.ambient_light_energy=0.8; e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.environment=e; w.add_child(env)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-40,35,0); sun.light_energy=1.6; w.add_child(sun)
	var cam:=Camera3D.new(); w.add_child(cam); cam.current=true
	for n in NAMES:
		var scene: PackedScene=load("res://assets/quest/%s.glb" % n)
		if scene==null: print("FAIL ",n); continue
		var inst: Node3D=scene.instantiate(); w.add_child(inst)
		await process_frame
		var b:=_bounds(inst)
		print(n," size ",b.size.snapped(Vector3.ONE*0.001)," pos ",b.position.snapped(Vector3.ONE*0.001))
		var c:=b.get_center(); var r:=b.size.length()*0.75
		cam.look_at_from_position(c+Vector3(0.6,0.45,1.0).normalized()*r*1.25,c,Vector3.UP)
		cam.near=r*0.01; cam.far=r*10
		for i in 4: await process_frame
		var img:=root.get_viewport().get_texture().get_image()
		img.save_png("/tmp/ws/model_%s.png" % n)
		inst.queue_free()
		await process_frame
	quit()
