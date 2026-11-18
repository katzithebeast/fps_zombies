extends SceneTree
# Render efektů Pack-a-Punch (výboje + jiskry) pro stupeň 3 a 4. Spouštět s --fixed-fps 60.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size=Vector2i(1280,720)
	var env:=Environment.new(); env.background_mode=Environment.BG_COLOR; env.background_color=Color(0.03,0.05,0.06)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color=Color(0.25,0.3,0.32); env.ambient_light_energy=0.6
	env.glow_enabled=true; env.glow_intensity=0.9; env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	var we:=WorldEnvironment.new(); we.environment=env; root.add_child(we)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-40,30,0); sun.light_energy=0.5; root.add_child(sun)
	var cam:=Camera3D.new(); cam.position=Vector3(0.0,0.0,0.62); cam.fov=60; root.add_child(cam); cam.current=true
	var rig_src: GDScript=load("res://scripts/weapon_rig.gd")
	var rig=rig_src.new(); root.add_child(rig)
	var guns: Dictionary=rig_src.GUNS
	var tiers:=[3,4]
	var names:=["ak","deagle"]
	for i in 2:
		var h:=Node3D.new(); root.add_child(h)
		var m: Node3D=load(guns[names[i]].scene).instantiate(); m.name=names[i]; h.add_child(m)
		h.position=Vector3(0.0,0.13-i*0.27,-0.2); h.rotation_degrees=Vector3(0,-80,0)
		var mat=rig._tier_mat(tiers[i]); mat.set_shader_parameter("strength",1.0)
		for mi in m.find_children("*","MeshInstance3D",true,false): mi.material_overlay=mat
		rig._make_pap_fx(m,rig_src.TIER_LOOK[tiers[i]]+[tiers[i]])
	rig._pap_strength=1.0
	rig._pap={"ak":3,"deagle":4}
	for f in 90:
		rig._update_pap(1.0/60.0)
		await RenderingServer.frame_post_draw
		if f in [40,55,70,85]: root.get_texture().get_image().save_png("/tmp/papfx_%d.png"%f)
	quit()
