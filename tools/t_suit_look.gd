extends SceneTree
## Vzhled obleku: celá postava (suchá / mokrá do pasu), detaily trupu, nohou, rukavice, hledí.
## → /tmp/suit_<pohled>.png
func _initialize() -> void: call_deferred("run")
func shot(name: String) -> void:
	for k in 4: await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(name)
func run() -> void:
	root.size=Vector2i(900,900)
	var env:=Environment.new()
	var sky:=Sky.new(); var sm:=ProceduralSkyMaterial.new()
	sm.sky_top_color=Color(0.55,0.5,0.42); sm.sky_horizon_color=Color(0.85,0.8,0.68); sm.ground_bottom_color=Color(0.25,0.27,0.27); sm.ground_horizon_color=Color(0.6,0.6,0.55)
	sky.sky_material=sm; env.sky=sky; env.background_mode=Environment.BG_COLOR; env.background_color=Color(0.12,0.12,0.11)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_SKY; env.ambient_light_energy=0.55
	env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC; env.ssao_enabled=true
	var we:=WorldEnvironment.new(); we.environment=env; root.add_child(we)
	var key:=DirectionalLight3D.new(); key.rotation_degrees=Vector3(-30,35,0); key.light_energy=1.4; key.light_color=Color(1.0,0.93,0.8); key.shadow_enabled=true; root.add_child(key)
	var spot:=SpotLight3D.new(); spot.position=Vector3(-1.2,1.6,1.6); spot.light_energy=6.0; spot.spot_range=6; spot.spot_angle=30; root.add_child(spot); spot.look_at(Vector3(0,1.1,0))
	var hz: PackedScene=load("res://assets/hazmat/hazmat_player.tscn")
	var m: Node3D=hz.instantiate(); root.add_child(m); m.scale=Vector3.ONE*0.86
	var lib: AnimationLibrary=load("res://assets/hazmat/locomotion.res")
	var ap:=AnimationPlayer.new(); m.add_child(ap); ap.add_animation_library("",lib); ap.play("idle"); ap.seek(0.5,true); ap.pause()
	var body: MeshInstance3D=m.get_node("Skeleton3D/Body")
	var floor:=MeshInstance3D.new(); var pm:=PlaneMesh.new(); pm.size=Vector2(10,10); floor.mesh=pm
	var fm:=StandardMaterial3D.new(); fm.albedo_color=Color(0.75,0.74,0.7); fm.roughness=0.3; floor.material_override=fm; root.add_child(floor)
	var cam:=Camera3D.new(); root.add_child(cam); cam.current=true
	var views:=[["full",Vector3(0,1.0,3.3),Vector3(0,0.9,0),35.0],["torso",Vector3(-0.3,1.45,0.9),Vector3(0,1.25,0),35.0],
		["legs",Vector3(0.3,0.5,1.2),Vector3(0,0.35,0),35.0],["hand",Vector3(-0.75,1.0,0.45),Vector3(-0.62,0.85,0.0),30.0],
		["visor",Vector3(0.15,1.75,0.55),Vector3(0,1.66,0),30.0],["back",Vector3(0.4,1.1,-2.8),Vector3(0,0.9,0),35.0]]
	for wetv in ([["",-100.0],["_wet",0.75]] if OS.get_environment("ONLY")=="" else [["_wet",0.75]]):
		body.set_instance_shader_parameter("wet_line",wetv[1])
		print("wet_line ",body.get_instance_shader_parameter("wet_line"), " body ", body.get_class(), " ", body.mesh.resource_path)
		for v in views:
			if wetv[0]!="" and not v[0] in ["full","legs"]: continue
			cam.fov=v[3]; cam.position=v[1]; cam.look_at(v[2])
			await shot("/tmp/suit_%s%s.png"%[v[0],wetv[0]])
	quit()
