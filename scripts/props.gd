extends RefCounted
class_name Props
## Modely interaktivních předmětů. Každý vrací Node3D s počátkem uprostřed podstavy,
## přední stranou k -Z a skutečnou velikostí v metrech.

const DIR:="res://assets/props/"
static var _cache:={}

static func _tex(path: String) -> Texture2D:
	return load(DIR+path) if ResourceLoader.exists(DIR+path) else null

static func _pbr(albedo: String, normal: String="", rough: String="", metal: String="", ao: String="") -> StandardMaterial3D:
	var key:=albedo+normal
	if _cache.has(key): return _cache[key]
	var m:=StandardMaterial3D.new()
	m.albedo_texture=_tex(albedo)
	if normal!="":
		m.normal_enabled=true
		m.normal_texture=_tex(normal)
	if rough!="":
		m.roughness_texture=_tex(rough)
		m.roughness=1.0
	if metal!="":
		m.metallic_texture=_tex(metal)
		m.metallic=1.0
	if ao!="":
		m.ao_enabled=true
		m.ao_texture=_tex(ao)
	_cache[key]=m
	return m

static func _xf(n: Node, root: Node) -> Transform3D:
	var t:=Transform3D()
	while n and n!=root and n is Node3D:
		t=(n as Node3D).transform*t
		n=n.get_parent()
	return t

static func _bounds(root: Node3D) -> AABB:
	var total:=AABB()
	var first:=true
	for m in root.find_children("*","MeshInstance3D",true,false):
		var a: AABB=_xf(m,root)*(m as MeshInstance3D).get_aabb()
		total=a if first else total.merge(a)
		first=false
	return total

static func _fit(inner: Node3D, scale_by: float, turn: float) -> Node3D:
	# Zabalí model: otočení kolem Y, měřítko a posun tak, aby stál na zemi uprostřed.
	var outer:=Node3D.new()
	var pivot:=Node3D.new()
	outer.add_child(pivot)
	pivot.add_child(inner)
	pivot.basis=Basis(Vector3.UP,turn).scaled(Vector3.ONE*scale_by)
	var b:=_bounds(outer)
	pivot.position=-Vector3(b.get_center().x,b.position.y,b.get_center().z)
	for m in outer.find_children("*","MeshInstance3D",true,false):
		var mesh_node: MeshInstance3D=m
		mesh_node.layers=1
		if mesh_node.material_override is StandardMaterial3D:
			mesh_node.material_override=_dull(mesh_node.material_override)
		elif mesh_node.mesh:
			for i in mesh_node.mesh.get_surface_count():
				var mat=mesh_node.get_surface_override_material(i)
				if mat==null: mat=mesh_node.mesh.surface_get_material(i)
				if mat is StandardMaterial3D: mesh_node.set_surface_override_material(i,_dull(mat))
	return outer

static func _dull(mat: StandardMaterial3D) -> StandardMaterial3D:
	# Ve tmě bez odrazů okolí jsou kovové plochy úplně černé; necháme jen náznak kovu.
	if _cache.has(mat): return _cache[mat]
	var copy: StandardMaterial3D=mat.duplicate()
	copy.metallic=minf(copy.metallic,0.2)
	copy.metallic_specular=0.6
	if copy.roughness_texture==null: copy.roughness=maxf(copy.roughness,0.55)
	_cache[mat]=copy
	return copy

static func crate() -> Node3D:
	# Bedna je jeden mesh: víko (vrchní desky) se oddělí podle výšky a dostane pant vzadu.
	var src: Node3D=load(DIR+"crate/source/crate.fbx").instantiate()
	var mi: MeshInstance3D=src.find_children("*","MeshInstance3D",true,false)[0]
	var to_root:=_xf(mi,src)
	var mat:=_pbr("crate/source/WeaponCrate_Albedo.png","crate/source/WeaponCrate_Normal.png","crate/source/WeaponCrate_Roughness.png","","crate/source/WeaponCrate_AO.png")
	var arrays:=mi.mesh.surface_get_arrays(0)
	var b:=to_root*mi.get_aabb()
	var cut:=b.position.y+b.size.y-float(OS.get_environment("LIDCUT") if OS.get_environment("LIDCUT")!="" else "0.07")
	var body:=SurfaceTool.new()
	var lid:=SurfaceTool.new()
	for st in [body,lid]: st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	if idx.is_empty():
		idx.resize(verts.size())
		for i in verts.size(): idx[i]=i
	# Model má víko otevřené a opřené vzadu: jeho ostrůvky (podle sdílených vrcholů) zahodíme
	# a postavíme víko vlastní, přesně na míru korpusu.
	var parent:=PackedInt32Array()
	parent.resize(verts.size())
	for i in verts.size(): parent[i]=i
	var seen:={}
	for i in verts.size():
		var k: Vector3=(verts[i]*2000.0).round()
		if seen.has(k): _union(parent,i,seen[k])
		else: seen[k]=i
	for t in range(0,idx.size(),3):
		_union(parent,idx[t],idx[t+1])
		_union(parent,idx[t],idx[t+2])
	var island_min:={}
	for i in verts.size():
		var r:=_root_of(parent,i)
		var x:=(to_root*verts[i]).x
		island_min[r]=minf(island_min.get(r,INF),x)
	var limit:=b.position.x+b.size.x*0.28
	for t in range(0,idx.size(),3):
		if float(island_min[_root_of(parent,idx[t])])<limit: continue
		for k in 3:
			var v:=idx[t+k]
			body.set_normal((to_root.basis*normals[v]).normalized())
			if uvs.size()>v: body.set_uv(uvs[v])
			body.add_vertex(to_root*verts[v])
	body.generate_tangents()
	var root:=Node3D.new()
	var body_mesh:=MeshInstance3D.new()
	body_mesh.name="Body"
	body_mesh.mesh=body.commit()
	body_mesh.material_override=mat
	root.add_child(body_mesh)
	src.free()
	var core: AABB=body_mesh.get_aabb()
	# Úchyty na čelech zvětšují obrys v ose Z; víko je jen přes korpus.
	var lid_size:=Vector3(core.size.x+0.01,0.022,core.size.z-0.09)
	var top:=core.position.y+core.size.y
	var hinge:=Node3D.new()
	hinge.name="Hinge"
	hinge.position=Vector3(core.position.x,top,core.get_center().z)
	root.add_child(hinge)
	var lid_mat: StandardMaterial3D=mat.duplicate()
	lid_mat.uv1_scale=Vector3(0.5,0.3,1)
	var plate:=MeshInstance3D.new()
	var box:=BoxMesh.new()
	box.size=lid_size
	plate.mesh=box
	plate.material_override=lid_mat
	plate.position=Vector3(lid_size.x*0.5,lid_size.y*0.5,0)
	hinge.add_child(plate)
	# Příčné lišty na víku.
	for z in [-0.36,0.0,0.36]:
		var batten:=MeshInstance3D.new()
		var bm:=BoxMesh.new()
		bm.size=Vector3(lid_size.x,0.016,0.05)
		batten.mesh=bm
		batten.material_override=lid_mat
		batten.position=Vector3(lid_size.x*0.5,lid_size.y+0.008,z*lid_size.z)
		hinge.add_child(batten)
	return _fit(root,1.8,PI/2)

static func _root_of(parent: PackedInt32Array, x: int) -> int:
	while parent[x]!=x:
		parent[x]=parent[parent[x]]
		x=parent[x]
	return x

static func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra:=_root_of(parent,a)
	var rb:=_root_of(parent,b)
	if ra!=rb: parent[rb]=ra

static func open_crate(model: Node3D, amount: float) -> void:
	var hinge: Node3D=model.find_child("Hinge",true,false)
	if hinge: hinge.basis=Basis(Vector3(0,0,1),amount*1.75)

static func locker() -> Node3D:
	var src: Node3D=load(DIR+"locker/source/locker.glb").instantiate()
	var doors:=[]
	for n in src.find_children("*Door*","Node3D",true,false):
		if n.get_child_count()>0 and not n is MeshInstance3D and (n as Node3D).position.length()>1.0:
			doors.append(n)
	for d in doors:
		var name_now: String=d.name
		d.set_meta("closed",d.rotation)
		d.set_meta("side",1.0 if "R_Door" in name_now else -1.0)
		d.add_to_group("locker_door")
	# Levé dveře jsou v modelu pootevřené: zavřeme je zrcadlově k pravým.
	var right: Node3D=null
	var left: Node3D=null
	for d in doors:
		if "R_Door" in String(d.name): right=d
		else: left=d
	if right and left:
		left.rotation=Vector3(right.rotation.x,-right.rotation.y if absf(right.rotation.y)>0.01 else 0.0,right.rotation.z)
		# Ověření: zavřené dveře jsou tenké v ose Z. Když ne, vrátit opačné znaménko.
		var test:=_bounds_of(left,src)
		if test.size.z>0.2: left.rotation.y=-left.rotation.y
		if _bounds_of(left,src).size.z>0.2: left.rotation.y=right.rotation.y+PI
		left.set_meta("closed",left.rotation)
	return _fit(src,1.0,PI)

static func _bounds_of(n: Node3D, root: Node3D) -> AABB:
	var total:=AABB()
	var first:=true
	for m in n.find_children("*","MeshInstance3D",true,false):
		var a: AABB=_xf(m,root)*(m as MeshInstance3D).get_aabb()
		total=a if first else total.merge(a)
		first=false
	return total

static func open_locker(model: Node3D, amount: float) -> void:
	for d in model.find_children("*Door*","Node3D",true,false):
		if not d.has_meta("closed"): continue
		var closed: Vector3=d.get_meta("closed")
		var node: Node3D=d
		node.rotation=closed
		node.rotate_object_local(Vector3.FORWARD,-float(d.get_meta("side"))*amount*1.6)

static func ammo() -> Node3D:
	var src: Node3D=load(DIR+"ammo/source/ammo.fbx").instantiate()
	for ap in src.find_children("*","AnimationPlayer",true,false): ap.queue_free()
	var mat:=_pbr("ammo/source/BaseColor.png","ammo/source/Normal.png","ammo/source/Roughness.png","ammo/source/Metallic.png")
	for m in src.find_children("*","MeshInstance3D",true,false): m.material_override=mat
	return _fit(src,1.0,0.0)

static func skull() -> Node3D:
	var src: Node3D=load(DIR+"skull/source/skull.fbx").instantiate()
	var bone:=StandardMaterial3D.new()
	bone.albedo_color=Color(0.86,0.8,0.68)
	bone.roughness=0.7
	bone.emission_enabled=true
	bone.emission=Color(1.0,0.25,0.15)
	bone.emission_energy_multiplier=0.35
	for m in src.find_children("*","MeshInstance3D",true,false):
		m.material_override=bone
		m.add_to_group("skull_part")
	return _fit(src,1.2,PI)

static func pumpkin() -> Node3D:
	var mesh: Mesh=load(DIR+"pumpkin/source/pumpkin.obj")
	var m:=MeshInstance3D.new()
	m.mesh=mesh
	var mat:=_pbr("pumpkin/source/pumpkin_diffuse.png","pumpkin/source/pumpkin_normal_map.png","pumpkin/source/pumpkin_roughness.png")
	mat.emission_enabled=true
	mat.emission=Color(1.0,0.45,0.05)
	mat.emission_energy_multiplier=0.25
	m.material_override=mat
	var holder:=Node3D.new()
	holder.add_child(m)
	return _fit(holder,0.17,0.0)

static func syringe() -> Node3D:
	var src: Node3D=load(DIR+"syringe/source/syringe.glb").instantiate()
	return _fit(src,0.0011,PI/2)

static func bench() -> Node3D:
	var src: Node3D=load(DIR+"bench/source/bench.fbx").instantiate()
	var mi: MeshInstance3D=src.find_children("*","MeshInstance3D",true,false)[0]
	var sets:=["B01","Tanks01","Drill01","A01"]
	for i in mi.mesh.get_surface_count():
		var key: String=sets[mini(i,3)]
		var normal:="bench/source/WorkstationWeapons%s_n.png" % key
		mi.set_surface_override_material(i,_pbr("bench/source/WorkstationWeapons%s_d.png" % key,normal if ResourceLoader.exists(DIR+normal) else ""))
	return _fit(src,1.7,0.0)

static func angel(height: float) -> Node3D:
	# Hřbitovní anděl: zmenšený/zvětšený na danou výšku, počátek uprostřed podstavy.
	if OS.get_environment("NOANGEL")!="": return Node3D.new()      # rychlé testovací snímky
	var src: Node3D=load(DIR+"angel/source/angel.glb").instantiate()
	for light in src.find_children("*","Light3D",true,false): light.queue_free()
	var b:=_bounds(src)
	var outer:=_fit(src,height/b.size.y,0.0)
	for m in outer.find_children("*","MeshInstance3D",true,false):
		(m as MeshInstance3D).cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(m as MeshInstance3D).visibility_range_end=50.0
		m.set_meta("angel",true)
	return outer

static func money() -> Node3D:
	# Štos bankovek: pár balíčků s texturou bankovky a páskou.
	var root:=Node3D.new()
	var bill:=StandardMaterial3D.new()
	bill.albedo_texture=_tex("money/source/7l2461_large.png")
	bill.normal_enabled=true
	bill.normal_texture=_tex("money/source/moneynormal.png")
	bill.roughness=0.8
	var side:=StandardMaterial3D.new()
	side.albedo_color=Color(0.78,0.82,0.7)
	side.roughness=0.9
	var band:=StandardMaterial3D.new()
	band.albedo_color=Color(0.75,0.62,0.35)
	var layout:=[[Vector3(0,0,0),0.0],[Vector3(0.012,0.045,0.006),0.08],[Vector3(-0.07,0,0.09),-0.15],[Vector3(0.08,0.0,0.085),0.2]]
	for item in layout:
		var stack:=Node3D.new()
		root.add_child(stack)
		stack.position=item[0]
		stack.rotation.y=item[1]
		var body:=MeshInstance3D.new()
		var bm:=BoxMesh.new()
		bm.size=Vector3(0.156,0.04,0.066)
		body.mesh=bm
		body.material_override=side
		body.position.y=0.02
		stack.add_child(body)
		var top:=MeshInstance3D.new()
		var qm:=QuadMesh.new()
		qm.size=Vector2(0.156,0.066)
		top.mesh=qm
		top.material_override=bill
		top.rotation.x=-PI/2
		top.position.y=0.0405
		stack.add_child(top)
		var strap:=MeshInstance3D.new()
		var sm:=BoxMesh.new()
		sm.size=Vector3(0.03,0.042,0.068)
		strap.mesh=sm
		strap.material_override=band
		strap.position.y=0.02
		stack.add_child(strap)
	return root

static func _noisy(colors: Array, rough: float, metal: float) -> StandardMaterial3D:
	# Oprýskaný kov: barevné skvrny a mikronerovnosti ze šumu, triplanárně.
	var key:=str(colors)
	if _cache.has(key): return _cache[key]
	var m:=StandardMaterial3D.new()
	var n:=FastNoiseLite.new()
	n.frequency=0.03
	var t:=NoiseTexture2D.new()
	t.seamless=true
	t.noise=n
	var g:=Gradient.new()
	g.offsets=PackedFloat32Array([0.0,0.7,1.0])
	g.colors=PackedColorArray(colors)
	t.color_ramp=g
	m.albedo_texture=t
	var nn:=FastNoiseLite.new()
	nn.frequency=0.1
	var nt:=NoiseTexture2D.new()
	nt.seamless=true
	nt.noise=nn
	nt.as_normal_map=true
	nt.bump_strength=1.5
	m.normal_enabled=true
	m.normal_texture=nt
	m.uv1_triplanar=true
	m.uv1_scale=Vector3(2,2,2)
	m.roughness=rough
	m.metallic=metal
	_cache[key]=m
	return m

static func gate(width: float, height: float) -> Node3D:
	# Kovová mříž přes průchod (vyjede nahoru do stropu).
	var root:=Node3D.new()
	var steel:=_noisy([Color(0.3,0.29,0.27),Color(0.4,0.38,0.35),Color(0.42,0.24,0.12)],0.55,0.35)
	var rust:=_noisy([Color(0.3,0.15,0.07),Color(0.48,0.26,0.11),Color(0.32,0.3,0.28)],0.9,0.15)
	var bars:=int(width/0.16)
	for i in bars+1:
		var bar:=MeshInstance3D.new()
		var cm:=CylinderMesh.new()
		cm.top_radius=0.022
		cm.bottom_radius=0.022
		cm.height=height
		cm.radial_segments=8
		bar.mesh=cm
		bar.material_override=steel
		bar.position=Vector3(-width*0.5+width*i/bars,height*0.5,0)
		root.add_child(bar)
	for y in [0.12,height*0.5,height-0.12]:
		var rail:=MeshInstance3D.new()
		var rm:=BoxMesh.new()
		rm.size=Vector3(width,0.08,0.06)
		rail.mesh=rm
		rail.material_override=rust if y==height*0.5 else steel
		rail.position=Vector3(0,y,0)
		root.add_child(rail)
	return root

static func vase() -> Node3D:
	# Váza s kytkou (GrowFX): váza, stonky, růžové a zelené listy.
	var src: Node3D=load(DIR+"vase/source/vase.fbx").instantiate()
	var ceramic:=_pbr("vase/source/002.jpg")
	ceramic.roughness=0.25
	for m in src.find_children("*","MeshInstance3D",true,false):
		var mi: MeshInstance3D=m
		if mi.mesh.get_surface_count()==1:
			mi.material_override=ceramic
		else:
			var maps:=["vase/source/kora.png","vase/source/pink_leaf.jpg","vase/source/leaf.jpg"]
			for i in mi.mesh.get_surface_count():
				var leaf:=_pbr(maps[mini(i,2)])
				leaf.cull_mode=BaseMaterial3D.CULL_DISABLED
				leaf.roughness=0.7
				mi.set_surface_override_material(i,leaf)
	return _fit(src,1.0,0.0)

static func _size_to(src: Node3D, axis: int, length: float, turn: float) -> Node3D:
	var b:=_bounds(src)
	return _fit(src,length/maxf(b.size[axis],0.001),turn)

static func cashier() -> Node3D:
	return _size_to(load(DIR+"cashier/source/model.gltf").instantiate(),1,1.08,0.0)

static func lounger() -> Node3D:
	var src: Node3D=load(DIR+"lounger/source/lounger.fbx").instantiate()
	var mat:=_pbr("lounger/source/Sun_lounger_DefaultMaterial_BaseColor.png","lounger/source/Sun_lounger_DefaultMaterial_Normal.png","lounger/source/Sun_lounger_DefaultMaterial_Roughness.png","lounger/source/Sun_lounger_DefaultMaterial_Metallic.png")
	for m in src.find_children("*","MeshInstance3D",true,false): m.material_override=mat
	# Skládací plážové lehátko: hloubka ~1 m, výška ~0,9 m (dřív 1,95 m = dvojnásobek).
	return _size_to(src,2,1.02,0.0)

static func shelves() -> Node3D:
	return _fit(load(DIR+"shelves/source/shelves.glb").instantiate(),1.0,0.0)

static func lifeguard() -> Node3D:
	var src: Node3D=load(DIR+"lifeguard/source/chair.fbx").instantiate()
	var mat:=_pbr("lifeguard/source/DefaultMaterial_Base_Color.png","","lifeguard/source/DefaultMaterial_Roughness.png","lifeguard/source/DefaultMaterial_Metallic.png")
	for m in src.find_children("*","MeshInstance3D",true,false): m.material_override=mat
	return _size_to(src,1,2.4,0.0)

static func vending() -> Node3D:
	var src: Node3D=load(DIR+"vending/source/vending.fbx").instantiate()
	var body:=_pbr("vending/source/vendingMachine_BaseColor.jpg","vending/source/vendingMachine_Normal.jpg","vending/source/vendingMachine_Roughness.jpg","vending/source/vendingMachine_Metallic.jpg")
	body.emission_enabled=true
	body.emission_texture=_tex("vending/source/vendingMachine_Emission.jpg")
	body.emission_energy_multiplier=0.8
	var glass:=StandardMaterial3D.new()
	glass.albedo_color=Color(0.7,0.8,0.85,0.25)
	glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness=0.08
	glass.metallic_specular=0.9
	for m in src.find_children("*","MeshInstance3D",true,false):
		m.material_override=glass if "Glass" in String(m.name) else body
	return _size_to(src,1,1.9,0.0)

static func merge(root: Node3D) -> void:
	# Sloučí jednoduché díly (kvádry, válce, koule...) se stejným materiálem do jednoho meshe:
	# z desítek draw callů je jeden. Volat až když je root ve stromu.
	var groups:={}
	for m in root.find_children("*","MeshInstance3D",true,false):
		var mi: MeshInstance3D=m
		if not (mi.mesh is PrimitiveMesh) or mi.get_child_count()>0 or mi.material_override==null: continue
		var key:=[mi.material_override,mi.get_instance_shader_parameter("tint"),mi.get_instance_shader_parameter("tile_scale"),mi.cast_shadow]
		var id:=str(key)
		if not groups.has(id): groups[id]={"key":key,"items":[]}
		groups[id].items.append(mi)
	var inv:=root.global_transform.affine_inverse()
	for id in groups:
		var items: Array=groups[id].items
		if items.size()<2: continue
		var st:=SurfaceTool.new()
		for mi in items:
			st.append_from((mi as MeshInstance3D).mesh,0,inv*(mi as MeshInstance3D).global_transform)
		var merged:=MeshInstance3D.new()
		merged.mesh=st.commit()
		var key: Array=groups[id].key
		merged.material_override=key[0]
		merged.cast_shadow=key[3]
		root.add_child(merged)
		if key[1]!=null: merged.set_instance_shader_parameter("tint",key[1])
		if key[2]!=null: merged.set_instance_shader_parameter("tile_scale",key[2])
		merged.visibility_range_end=(items[0] as MeshInstance3D).visibility_range_end
		for mi in items:
			(mi as Node).get_parent().remove_child(mi)
			(mi as Node).queue_free()

static func make(kind: String) -> Node3D:
	match kind:
		"crate": return crate()
		"locker": return locker()
		"ammo": return ammo()
		"skull": return skull()
		"pumpkin": return pumpkin()
		"syringe": return syringe()
		"bench": return bench()
		"money": return money()
		"vase": return vase()
		"cashier": return cashier()
		"lounger": return lounger()
		"shelves": return shelves()
		"lifeguard": return lifeguard()
		"vending": return vending()
	return Node3D.new()
