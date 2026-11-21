extends SceneTree
## Náhled vstávání (bez fyziky): klip ve zvolených časech ze strany a zepředu.
##   CLIP=getup_front TIMES=0,0.5,... godot --rendering-driver vulkan --path . --script res://tools/t_getup_view.gd
## Výstup /tmp/gu_<klip>_<i>_<pohled>.png
func _initialize() -> void: call_deferred("run")
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(name)
func run() -> void:
	root.size=Vector2i(640,400)
	var env:=Environment.new(); env.background_mode=Environment.BG_COLOR; env.background_color=Color(0.2,0.22,0.25)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color=Color(0.6,0.62,0.66); env.ambient_light_energy=0.8
	var we:=WorldEnvironment.new(); we.environment=env; root.add_child(we)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-55,-35,0); sun.light_energy=1.6; sun.shadow_enabled=true; root.add_child(sun)
	var fl:=MeshInstance3D.new(); var pm:=PlaneMesh.new(); pm.size=Vector2(8,8); fl.mesh=pm
	var mat:=ShaderMaterial.new(); mat.shader=Shader.new()
	mat.shader.code="shader_type spatial;\nvarying vec3 wp;\nvoid vertex(){ wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }\nvoid fragment(){ vec2 g=abs(fract(wp.xz*4.0+0.5)-0.5); float l=1.0-smoothstep(0.0,0.03,min(g.x,g.y)); ALBEDO=mix(vec3(0.45),vec3(0.2),l); }"
	fl.material_override=mat; root.add_child(fl)
	var m: Node3D=(load(OS.get_environment("MODEL") if OS.get_environment("MODEL")!="" else "res://assets/zombie/zombie.fbx") as PackedScene).instantiate()
	root.add_child(m)
	m.scale=Vector3.ONE*0.85
	var ap: AnimationPlayer=m.get_node("AnimationPlayer")
	ap.add_animation_library("g",load("res://assets/zombie/getup_anims.res"))
	ap.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var clip:=OS.get_environment("CLIP") if OS.get_environment("CLIP")!="" else "getup_front"
	var times:=OS.get_environment("TIMES").split_floats(",") if OS.get_environment("TIMES")!="" else PackedFloat64Array([0,0.35,0.85,1.35,1.85,2.35,2.85])
	ap.play("g/"+clip,0.0)
	var cam:=Camera3D.new(); root.add_child(cam); cam.current=true; cam.fov=50
	for i in times.size():
		ap.seek(times[i],true)
		ap.advance(0)
		for v in [["S",Vector3(2.6,0.9,0.0)],["F",Vector3(0.9,1.1,2.4)]]:
			cam.global_position=v[1]
			cam.look_at(Vector3(0,0.45,-0.1),Vector3.UP)
			await shot("/tmp/gu_%s_%d_%s.png"%[clip,i,v[0]])
	quit()
