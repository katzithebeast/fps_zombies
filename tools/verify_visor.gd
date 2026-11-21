extends SceneTree
## VISOR (experiment): otření hledí – ruka dojde na sklo, maska se vyčistí zleva doprava,
## krev a kapky se označí jako setřené. Beze zbraně i se zbraní.
##   godot --headless --fixed-fps 60 --path . --script res://tools/verify_visor.gd
var failures:=0
func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ")+what)
	if not ok: failures+=1

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.size=Vector2i(960,540)
	var floor_body:=StaticBody3D.new(); root.add_child(floor_body)
	var cs:=CollisionShape3D.new(); var bs:=BoxShape3D.new(); bs.size=Vector3(20,1,20); cs.shape=bs; cs.position.y=-0.5; floor_body.add_child(cs)
	Player.water_at=func(_p: Vector3) -> float: return -50.0
	var player:=Player.new()
	root.add_child(player)
	player.teleport(Vector3(0,0.05,0),0.0,0.0)
	var stub: Node=load("res://tools/_bc_stub.gd").new()
	root.add_child(stub)
	stub.player=player
	var layer:=CanvasLayer.new(); root.add_child(layer)
	var visor: Node=load("res://scripts/visor.gd").new()
	stub.add_child(visor)
	visor.setup(stub,layer,player)
	visor.set_enabled(true)
	visor.auto_wipe=false
	for f in 30: await process_frame
	check(visor.active(),"visor active in first person")
	for armed in [false,true]:
		if armed:
			player.weapon.give("ak",true)
			for f in 60: await process_frame
		var tag:="armed" if armed else "unarmed"
		visor.clear()
		visor._add_splat(Vector2(0.3,0.45),0.4,0,0.9)
		visor._add_splat(Vector2(0.7,0.5),0.5,6,0.9)
		visor._wet=1.0; visor._wet_k=float(visor._wipes)
		for f in 5: await process_frame
		check(visor._dirt()>0.32,"%s: dirty visor wants a wipe (dirt %.2f)"%[tag,visor._dirt()])
		check(visor.wipe(),"%s: wipe starts"%tag)
		var rig: Node=player.body.weapon
		var contact:=0
		var xs:=[]
		var min_d:=9.0
		while float(rig.wipe)>0.0:
			await process_frame
			if float(rig.wipe_contact)>0.5:
				contact+=1
				var cam: Camera3D=player.camera
				var local: Vector3=cam.global_transform.affine_inverse()*(rig.wipe_palm as Vector3)
				min_d=minf(min_d,-local.z)
				xs.append(local.x)
		check(contact>15,"%s: palm on the visor for %d frames"%[tag,contact])
		check(xs.size()>2 and float(xs[0])<-0.03 and float(xs[xs.size()-1])>0.03,"%s: palm sweeps left -> right (%.3f -> %.3f m)"%[tag,float(xs[0]) if xs.size()>0 else 0.0,float(xs[xs.size()-1]) if xs.size()>0 else 0.0])
		check(min_d>0.05 and min_d<0.16,"%s: palm stays just in front of the eye (%.3f m)"%[tag,min_d])
		var clean:=0
		for x in visor.MASK_W:
			if visor._mask_img.get_pixel(x,visor.MASK_H/2).r*255.0>=float(visor._wipes)-0.5: clean+=1
		check(clean>visor.MASK_W*0.8,"%s: wiped band covers %d / %d columns"%[tag,clean,visor.MASK_W])
		var wiped:=0
		for s in visor._splats:
			if float(s.wiped)>=0.0: wiped+=1
		check(wiped==2,"%s: both blood splats marked wiped (%d)"%[tag,wiped])
		check(visor._dirt()<0.1,"%s: visor clean after wipe (dirt %.2f)"%[tag,visor._dirt()])
	print("VISOR FINISHED failures=%d"%failures)
	quit()
