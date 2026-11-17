extends RefCounted
## Architektonické detaily bazénů: plovoucí dělicí lana drah, startovní bloky, žebříky do všech
## bazénů, záchranné kruhy na zdech, malované hloubky na okrajích, odtokové mřížky a zábradlí.
## Volá se z main._ready před sloučením geometrie, takže boxy a trubky se spojí se zbytkem světa.

static func build(main: Node) -> void:
	var chrome: Material = main.chrome_mat
	var steel: Material = main._surface("steel")
	_lane_ropes(main)
	_start_blocks(main, steel)
	# Žebříky: síň anděla (hluboký), kulatá síň, vypuštěný bazén na terasách.
	var ap: Rect2 = main.ANGEL_POOL
	for lz in [ap.position.y + 4.0, ap.end.y - 4.0]:
		_ladder(main, chrome, Vector3(ap.position.x, -0.35, lz), Vector3.RIGHT, 5.0)
		_ladder(main, chrome, Vector3(ap.end.x, -0.35, lz), Vector3.LEFT, 5.0)
	var rp := Rect2(50, 28, 8, 8)
	_ladder(main, chrome, Vector3(rp.position.x + 2.0, -0.35, rp.position.y), Vector3.BACK, 2.6)
	_ladder(main, chrome, Vector3(rp.end.x - 2.0, -0.35, rp.end.y), Vector3.FORWARD, 2.6)
	_ladder(main, chrome, Vector3(34.4, 1.45, 15.5), Vector3.FORWARD, 1.1)
	# Zábradlí kolem vypuštěného bazénu (kus chybí – někdo ho vylomil).
	for seg in [[Vector3(28.0, 1.45, 10.85), Vector3(33.0, 1.45, 10.85)], [Vector3(36.15, 1.45, 11.0), Vector3(36.15, 1.45, 15.5)]]:
		_railing(main, chrome, seg[0], seg[1])
	# Záchranné kruhy na zdech.
	for r in [[Vector3(11.94, 1.55, -11.0), Vector3.LEFT], [Vector3(-11.94, 1.55, -5.0), Vector3.RIGHT], [Vector3(46.53, 1.5, -18.0), Vector3.LEFT],
			[Vector3(46.06, 1.4, 32.0), Vector3.RIGHT], [Vector3(24.06, 2.4, 13.0), Vector3.RIGHT]]:
		_lifebuoy(main, r[0], r[1])
	# Malované hloubky na okrajích bazénů.
	for d in [[Vector3(0, -0.34, -7.6), 0.0, "2,6 m"], [Vector3(0, -0.34, -20.4), PI, "2,6 m"], [Vector3(-6.4, -0.34, -14.0), PI / 2, "2,6 m"],
			[Vector3(ap.get_center().x, -0.34, ap.position.y - 0.35), PI, "14 m"], [Vector3(ap.get_center().x, -0.34, ap.end.y + 0.35), 0.0, "14 m  ·  NESKÁKAT"],
			[Vector3(54, -0.34, 27.3), PI, "2,6 m"], [Vector3(32, 1.46, 16.2), 0.0, "1,1 m"]]:
		_depth_mark(main, d[0], d[1], d[2])
	# Odtokové mřížky v dalších částech mapy.
	for g in [Vector2(-6, -36), Vector2(6, -42), Vector2(-4, -52), Vector2(22, -40), Vector2(38, -8), Vector2(30, 0.5),
			Vector2(48.5, 38.5), Vector2(59.5, 25.5), Vector2(15.5, -14.0)]:
		_grate(main, steel, g)
	# Kruhová výpusť na dně hlavního bazénu.
	main.box(-0.35, 0.35, -2.6, -2.585, -14.35, -13.65, main.C_WALL, false, 1.0, steel)

static func _lane_ropes(main: Node) -> void:
	# Dělicí lana: řada plováků střídavě červená a bílá, ke krajům modrá. Leží na hladině.
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for lx in [-4.6, -1.6, 1.6, 4.6]:
		var z := -19.85
		var i := 0
		while z < -8.15:
			# Lano se mírně prohýbá a plováky jsou trochu natočené – nic není dokonale rovné.
			var sag := sin((z + 20.0) / 11.7 * PI) * 0.06
			var t := Transform3D(Basis(Vector3.RIGHT, PI / 2).rotated(Vector3.UP, randf_range(-0.05, 0.05)), Vector3(lx + sag, 0.01, z))
			xforms.append(t)
			var edge := z < -18.5 or z > -9.5
			colors.append(Color(0.12, 0.25, 0.75) if edge else (Color(0.8, 0.1, 0.08) if i % 2 == 0 else Color(0.92, 0.9, 0.85)))
			z += 0.14
			i += 1
		# Lano: tenká trubka mezi kotvami.
		main.tube([Vector3(lx, 0.01, -20.0), Vector3(lx + 0.03, 0.01, -14.0), Vector3(lx, 0.01, -8.0)] as Array[Vector3], 0.008, main._surface("steel"), 6, 2)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.055
	mesh.bottom_radius = 0.055
	mesh.height = 0.11
	mesh.radial_segments = 10
	mesh.rings = 1
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.35
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
		mm.set_instance_color(k, colors[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mmi.visibility_range_end = 45.0
	main.add_child(mmi)

static func _start_blocks(main: Node, steel: Material) -> void:
	# Startovní bloky na konci hlavního bazénu, s číslem dráhy.
	var n := 1
	for lx in [-3.1, -0.1, 3.1]:
		var base := Vector3(lx, -0.35, -20.55)
		main.box(lx - 0.28, lx + 0.28, -0.35, 0.25, -20.85, -20.25, Color(0.82, 0.84, 0.83), true)
		var top := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.6, 0.06, 0.66)
		top.mesh = b
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.1, 0.3, 0.6)
		m.roughness = 0.7
		top.material_override = m
		main.add_child(top)
		top.position = base + Vector3(0, 0.65, 0)
		top.rotation.x = -0.12             # nakloněná deska směrem k vodě
		main.tube([Vector3(lx - 0.22, 0.25, -20.84), Vector3(lx - 0.22, 0.62, -20.84)] as Array[Vector3], 0.018, main.chrome_mat, 6, 1)
		main.tube([Vector3(lx + 0.22, 0.25, -20.84), Vector3(lx + 0.22, 0.62, -20.84)] as Array[Vector3], 0.018, main.chrome_mat, 6, 1)
		var num := Label3D.new()
		num.text = str(n)
		num.font_size = 96
		num.pixel_size = 0.0025
		num.modulate = Color(0.08, 0.08, 0.1)
		num.outline_size = 0
		num.shaded = true
		num.double_sided = false
		main.add_child(num)
		num.position = base + Vector3(0, 0.45, 0.31)
		n += 1

static func _ladder(main: Node, chrome: Material, edge: Vector3, into: Vector3, depth: float) -> void:
	# Klasický bazénový žebřík: dvě madla přes okraj a příčky dolů pod hladinu.
	var side := into.cross(Vector3.UP).normalized()
	for s in [-0.26, 0.26]:
		var o: Vector3 = edge + side * s
		main.tube([o - into * 0.55, o - into * 0.5 + Vector3.UP * 0.85, o - into * 0.15 + Vector3.UP * 1.12,
			o + into * 0.15 + Vector3.UP * 0.85, o + into * 0.18 + Vector3.UP * 0.3, o + into * 0.18 + Vector3.DOWN * depth] as Array[Vector3], 0.022, chrome)
	var y := -0.25
	while y > -depth + 0.2:
		main.tube([edge + into * 0.16 - side * 0.26 + Vector3.UP * y, edge + into * 0.16 + side * 0.26 + Vector3.UP * y] as Array[Vector3], 0.018, chrome, 8, 1)
		y -= 0.4

static func _railing(main: Node, chrome: Material, a: Vector3, b: Vector3) -> void:
	var dir := b - a
	var count := maxi(2, int(dir.length() / 1.4) + 1)
	for i in count:
		var p: Vector3 = a + dir * (float(i) / float(count - 1))
		main.tube([p, p + Vector3.UP * 0.95] as Array[Vector3], 0.02, chrome, 8, 1)
	main.tube([a + Vector3.UP * 0.95, b + Vector3.UP * 0.95] as Array[Vector3], 0.025, chrome, 8, 2)
	main.tube([a + Vector3.UP * 0.5, b + Vector3.UP * 0.5] as Array[Vector3], 0.016, chrome, 8, 2)

static func _lifebuoy(main: Node, pos: Vector3, normal: Vector3) -> void:
	# Oranžovo-bílý záchranný kruh pověšený na zdi.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.2
	torus.outer_radius = 0.34
	torus.rings = 24
	torus.ring_segments = 10
	ring.mesh = torus
	var img := Image.create(8, 1, false, Image.FORMAT_RGB8)
	for x in 8: img.set_pixel(x, 0, Color(0.92, 0.35, 0.08) if x % 2 == 0 else Color(0.93, 0.92, 0.88))
	var tex := ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 0.55
	ring.material_override = m
	main.add_child(ring)
	# Osa kruhu míří ze zdi ven (kruh leží naplocho na zdi).
	var x := Vector3.UP.cross(normal).normalized()
	ring.transform = Transform3D(Basis(x, normal, x.cross(normal)), pos)
	# Provaz kolem kruhu.
	var rope := MeshInstance3D.new()
	var t2 := TorusMesh.new()
	t2.inner_radius = 0.335
	t2.outer_radius = 0.35
	t2.rings = 24
	t2.ring_segments = 4
	rope.mesh = t2
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.75, 0.7, 0.55)
	rope.material_override = rm
	ring.add_child(rope)

static func _depth_mark(main: Node, pos: Vector3, yaw: float, text: String) -> void:
	# Hloubka namalovaná na okraji bazénu (opraná barva, leží na dlaždicích).
	var l := Label3D.new()
	l.text = text
	l.font_size = 120
	l.pixel_size = 0.0022
	l.modulate = Color(0.08, 0.12, 0.3, 0.85)
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	main.add_child(l)
	l.position = pos
	l.rotation = Vector3(-PI / 2, yaw, 0)

static func _grate(main: Node, steel: Material, at: Vector2) -> void:
	# Odtoková mřížka v podlaze: rám a příčky těsně nad dlaždicemi.
	var y := -0.35
	main.box(at.x - 0.25, at.x + 0.25, y - 0.01, y + 0.008, at.y - 0.25, at.y - 0.22, main.C_WALL, false, 1.0, steel)
	main.box(at.x - 0.25, at.x + 0.25, y - 0.01, y + 0.008, at.y + 0.22, at.y + 0.25, main.C_WALL, false, 1.0, steel)
	main.box(at.x - 0.25, at.x - 0.22, y - 0.01, y + 0.008, at.y - 0.22, at.y + 0.22, main.C_WALL, false, 1.0, steel)
	main.box(at.x + 0.22, at.x + 0.25, y - 0.01, y + 0.008, at.y - 0.22, at.y + 0.22, main.C_WALL, false, 1.0, steel)
	var k := -0.17
	while k < 0.2:
		main.box(at.x + k - 0.012, at.x + k + 0.012, y - 0.01, y + 0.006, at.y - 0.22, at.y + 0.22, main.C_WALL, false, 1.0, steel)
		k += 0.068
	# Tma pod mřížkou.
	main.box(at.x - 0.22, at.x + 0.22, y - 0.012, y - 0.009, at.y - 0.22, at.y + 0.22, Color(0.02, 0.02, 0.02), false)
