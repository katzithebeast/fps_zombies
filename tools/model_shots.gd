extends SceneTree
## Náhledy modelů: godot --path . --script res://tools/model_shots.gd -- <out_dir> <res://a.glb> ...
## Vypíše strukturu (meshe, trojúhelníky, rozměry) a uloží snímek každého modelu.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.6, 0.65)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	env.environment.ambient_light_energy = 0.6
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	for p in args.slice(1):
		var n: Node3D = load(p).instantiate()
		world.add_child(n)
		var bb := AABB()
		var first := true
		var tris := 0
		var lines := []
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null: continue
			var b: AABB = m.global_transform * m.mesh.get_aabb()
			bb = b if first else bb.merge(b)
			first = false
			var t := 0
			for s in m.mesh.get_surface_count():
				var a := m.mesh.surface_get_arrays(s)
				t += (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] != null else a[Mesh.ARRAY_VERTEX].size()) / 3
			tris += t
			lines.append("   %s tris=%d size=%s pos=%s" % [m.name, t, b.size.snapped(Vector3.ONE*0.01), b.position.snapped(Vector3.ONE*0.01)])
		print("== ", p, " tris=", tris, " aabb pos=", bb.position.snapped(Vector3.ONE*0.01), " size=", bb.size.snapped(Vector3.ONE*0.01))
		for l in lines.slice(0, 20): print(l)
		var c := bb.get_center()
		var r := bb.size.length() * 0.75
		cam.look_at_from_position(c + Vector3(r, r * 0.35, r), c)
		cam.far = r * 10.0
		for i in 8: await process_frame
		root.get_texture().get_image().save_png(out + "/" + p.get_file().get_basename() + ".png")
		n.queue_free()
		await process_frame
	quit()
