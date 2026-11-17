extends SceneTree
# Najde dvojice kvádrů se společnou viditelnou stěnou se stejnou orientací (z-fighting).
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var main=load("res://main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.5).timeout
	var boxes:=[]
	for m in main.find_children("*","MeshInstance3D",true,false):
		var mi: MeshInstance3D=m
		if not (mi.mesh is BoxMesh) or not mi.visible: continue
		if absf(mi.global_rotation.y)>0.01 or absf(mi.global_rotation.x)>0.01 or absf(mi.global_rotation.z)>0.01: continue
		var a: AABB=mi.global_transform*mi.get_aabb()
		if a.size.length()<0.05: continue
		var tint=mi.get_instance_shader_parameter("tint")
		var key=str(tint)+str(mi.material_override)
		boxes.append([a,mi,key])
	var found:=0
	var eps:=0.004
	for i in boxes.size():
		var a: AABB=boxes[i][0]
		for j in range(i+1,boxes.size()):
			var b: AABB=boxes[j][0]
			if boxes[i][2]==boxes[j][2]: continue
			for ax in 3:
				for side in [0,1]:
					var pa: float=a.position[ax]+a.size[ax]*side
					var pb: float=b.position[ax]+b.size[ax]*side
					if absf(pa-pb)>eps: continue
					if ax==1 and side==0: continue
					# překryv průmětu stěn ve zbylých dvou osách
					var area:=1.0
					for o in 3:
						if o==ax: continue
						var lo:=maxf(a.position[o],b.position[o])
						var hi:=minf(a.end[o],b.end[o])
						area*=maxf(0.0,hi-lo)
					if area>0.01:
						var c:=Vector3.ZERO
						for o in 3:
							c[o]=(maxf(a.position[o],b.position[o])+minf(a.end[o],b.end[o]))*0.5
						c[ax]=pa
						var n:=Vector3.ZERO
						n[ax]=1.0 if side==1 else -1.0
						var out:=c+n*0.05
						var hidden:=false
						for k in boxes:
							if (k[0] as AABB).grow(-0.001).has_point(out):
								hidden=true
								break
						if hidden: continue
						var space=main.get_world_3d().direct_space_state
						var dn=space.intersect_ray(PhysicsRayQueryParameters3D.create(out,out+Vector3.DOWN*20.0,1))
						var up=space.intersect_ray(PhysicsRayQueryParameters3D.create(out,out+Vector3.UP*20.0,1))
						if dn.is_empty() or up.is_empty(): continue
						found+=1
						if found<=120: print("ZF ax=",ax," side=",side," plane=",snappedf(pa,0.01)," A=",a.position.snapped(Vector3.ONE*0.01),"/",a.end.snapped(Vector3.ONE*0.01)," B=",b.position.snapped(Vector3.ONE*0.01),"/",b.end.snapped(Vector3.ONE*0.01)," area=",snappedf(area,0.01))
	print("celkem ",found," z ",boxes.size())
	quit()
