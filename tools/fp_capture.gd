extends SceneTree
## Snímky první osoby přes skutečnou herní kameru a skutečný vstup (klávesy/myš).
## Spouštět s pevným krokem:  godot --fixed-fps 60 --rendering-driver vulkan --path . --script res://tools/fp_capture.gd
## GUNS=ak,mp40  SEQ=idle,walk,sprint,ads,fire,reload,empty,check,examine,melee,draw  OUT=/tmp/fp  W=960 H=540
## Výstup: OUT/<zbraň>_<akce>_<index>.png
var player: Player
var out_dir:="/tmp/fp"
var frame:=0
var shots:={}     # frame -> name

func _initialize() -> void: call_deferred("run")

func key(k: Key, down: bool) -> void:
	var e:=InputEventKey.new(); e.physical_keycode=k; e.keycode=k; e.pressed=down
	Input.parse_input_event(e)

func mouse(b: MouseButton, down: bool) -> void:
	var e:=InputEventMouseButton.new(); e.button_index=b; e.pressed=down
	e.position=Vector2(480,270); e.global_position=e.position
	Input.parse_input_event(e)

## Posune hru o t sekund; snímky v časech caps (sekundy od začátku kroku).
func step(t: float, caps: Array=[], name:="") -> void:
	var n:=int(round(t*60.0))
	var cap_frames:={}
	for i in caps.size(): cap_frames[int(round(float(caps[i])*60.0))]=i
	for f in n:
		var snap:=cap_frames.has(f)
		RenderingServer.render_loop_enabled=snap
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		await process_frame
		if snap:
			if OS.get_environment("DBG")!="": dbg(name)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s_%02d.png"%[out_dir,name,cap_frames[f]])
	RenderingServer.render_loop_enabled=false

func dbg(name: String) -> void:
	var rig: Node=player.body.weapon
	var ci: Transform3D=player.camera.global_transform.affine_inverse()
	var first: Node3D=rig.first
	var g: Dictionary=rig._gi()
	var sk: Skeleton3D=rig.avatar.first_skeleton
	var lh:=sk.global_transform*sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftHand")).origin
	var rh:=sk.global_transform*sk.get_bone_global_pose(sk.find_bone("mixamorig_RightHand")).origin
	print("%s muzzle %s L %s R %s fov %.1f sprint %.2f spd %.2f floor %s errR %.3f errL %.3f" % [name, ci*(first.global_transform*(g.muzzle as Vector3)), ci*lh, ci*rh, player.camera.fov, player.weapon.sprint_amount, Vector2(player.velocity.x,player.velocity.z).length(), player.is_on_floor(), rig.first_right_error, rig.first_left_error])

func room() -> void:
	var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR; env.background_color=Color(0.05,0.06,0.07)
	var dark:=OS.get_environment("DARK")!=""
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color=Color(0.55,0.6,0.62); env.ambient_light_energy=0.08 if dark else 0.55
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	var we:=WorldEnvironment.new(); we.environment=env; root.add_child(we)
	var mat:=ShaderMaterial.new()
	mat.shader=Shader.new()
	mat.shader.code="shader_type spatial;\nvarying vec3 wp;\nvoid vertex(){ wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }\nvoid fragment(){ vec3 g=abs(fract(wp*4.0+0.5)-0.5); float gl=1.0-smoothstep(0.0,0.025,min(min(g.x,g.y),g.z)); ALBEDO=mix(vec3(0.3,0.42,0.42),vec3(0.12,0.14,0.14),gl*0.8); ROUGHNESS=mix(0.25,0.7,gl); }"
	var body:=StaticBody3D.new(); root.add_child(body)
	for b in [[Vector3(0,-0.5,0),Vector3(8,1,30)],[Vector3(-3,1.5,0),Vector3(0.4,4,30)],[Vector3(3,1.5,0),Vector3(0.4,4,30)],[Vector3(0,3.3,0),Vector3(8,0.4,30)]]:
		var cs:=CollisionShape3D.new(); var bs:=BoxShape3D.new(); bs.size=b[1]; cs.shape=bs; cs.position=b[0]; body.add_child(cs)
		var mi:=MeshInstance3D.new(); var bm:=BoxMesh.new(); bm.size=b[1]; mi.mesh=bm; mi.position=b[0]; mi.material_override=mat; body.add_child(mi)
	for z in [-2.0,-7.0,3.0]:
		var l:=OmniLight3D.new(); l.position=Vector3(0.6,2.8,z); l.light_energy=2.2 if OS.get_environment("DARK")=="" else (1.6 if z<-5.0 else 0.0); l.omni_range=9.0; l.light_color=Color(1.0,0.86,0.68); l.shadow_enabled=true; root.add_child(l)

func run() -> void:
	out_dir=OS.get_environment("OUT") if OS.get_environment("OUT")!="" else "/tmp/fp"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var w:=int(OS.get_environment("W")) if OS.get_environment("W")!="" else 960
	var h:=int(OS.get_environment("H")) if OS.get_environment("H")!="" else 540
	root.size=Vector2i(w,h)
	room()
	Player.water_at=func(_p: Vector3) -> float: return -50.0
	player=Player.new()
	root.add_child(player)
	if OS.get_environment("BODYCAM")!="":
		var stub: Node=load("res://tools/_bc_stub.gd").new()
		root.add_child(stub)
		stub.player=player
		stub.cam_attr=CameraAttributesPractical.new()
		player.camera.attributes=stub.cam_attr
		var layer:=CanvasLayer.new(); layer.layer=10; root.add_child(layer)
		var rect:=ColorRect.new(); rect.set_anchors_preset(Control.PRESET_FULL_RECT); rect.size=Vector2(root.size); rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var pm:=ShaderMaterial.new(); pm.shader=load("res://shaders/post.gdshader"); rect.material=pm
		layer.add_child(rect)
		var bc: Node=load("res://scripts/bodycam.gd").new()
		stub.add_child(bc)
		bc.setup(stub,rect,pm)
		player.cam_fx=bc
		bc.set_enabled(true)
		if OS.get_environment("VHS")!="": pm.set_shader_parameter("vhs",1.0)
		stub.settings["bodycam_blur"]=float(OS.get_environment("BLUR")) if OS.get_environment("BLUR")!="" else 1.0
	player.teleport(Vector3(0,0.05,8),0.0,0.0)
	var wpn: Node=player.weapon
	for g in wpn.ORDER: wpn.give(g,false)
	var guns:=OS.get_environment("GUNS").split(",") if OS.get_environment("GUNS")!="" else PackedStringArray(wpn.ORDER)
	var seq:=OS.get_environment("SEQ").split(",") if OS.get_environment("SEQ")!="" else PackedStringArray(["idle","walk","sprint","ads","fire","reload","empty","check","examine","melee","draw"])
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	for g in guns:
		wpn.switch_to(g,true)
		wpn.debug_ammo=false
		await step(1.2)
		for s in seq:
			var nm:="%s_%s"%[g,s]
			player.teleport(Vector3(0,0.05,8),0.0,-0.05)
			match s:
				"idle":
					await step(1.0,[0.99],nm)
				"turn":
					# švihnutí myší doleva a zpátky (zpoždění kamery, rozmazání, rolling shutter)
					for i in 12:
						var mm:=InputEventMouseMotion.new(); mm.relative=Vector2(-55,0); Input.parse_input_event(mm)
						await step(1.0/60.0,[0.0] if i in [4,8,11] else [],nm+"_%d"%i)
					await step(0.5,[0.05,0.15,0.3],nm+"_after")
				"look":
					# malý pohyb myší: zbraň se pohne v okně, kamera zůstane (volné míření)
					for i in 10:
						var mm:=InputEventMouseMotion.new(); mm.relative=Vector2(12,-5); Input.parse_input_event(mm)
						await step(1.0/60.0)
					await step(0.6,[0.0,0.25,0.55],nm)
				"walk":
					key(KEY_W,true); await step(1.6,[1.0,1.15,1.3,1.45],nm); key(KEY_W,false); await step(0.8)
				"sprint":
					key(KEY_W,true); key(KEY_SHIFT,true); await step(1.6,[1.0,1.2,1.4],nm)
					key(KEY_SHIFT,false); key(KEY_W,false); await step(1.0)
				"ads":
					mouse(MOUSE_BUTTON_RIGHT,true); await step(0.9,[0.06,0.15,0.89],nm); mouse(MOUSE_BUTTON_RIGHT,false); await step(0.6)
				"fire":
					wpn.ammo=int(wpn.stats().mag)
					mouse(MOUSE_BUTTON_LEFT,true); await step(0.05,[0.0,0.034],nm+"a"); mouse(MOUSE_BUTTON_LEFT,false)
					await step(0.6,[0.05,0.12,0.25],nm+"b")
				"reload","empty":
					wpn.ammo=0 if s=="empty" else mini(5,int(wpn.stats().mag)-1)
					key(KEY_R,true); await step(0.1); key(KEY_R,false)
					for i in 6:
						if float(wpn.reload_left)>0.0: break
						await step(1.0/60.0)
					if OS.get_environment("DBG")!="": print("reload_left ",wpn.reload_left," ammo ",wpn.ammo," r_held ",wpn._r_held)
					var rt: float=float(wpn.reload_left)
					var caps:=[]
					for i in 10: caps.append(rt*(i+0.5)/10.0)
					await step(rt+0.6,caps,nm)
				"check":
					wpn.ammo=maxi(1,int(wpn.stats().mag)-3)
					key(KEY_R,true); await step(2.0,[0.4,0.55,0.75,1.2,1.9],nm+"a"); key(KEY_R,false)
					await step(0.8,[0.08,0.2,0.5],nm+"b")
				"examine":
					key(KEY_N,true); await step(7.0,[0.3,0.8,1.5,2.3,3.1,3.9,4.7,5.5,6.3],nm); key(KEY_N,false); await step(1.0,[0.25],nm+"x")
				"melee":
					key(KEY_Q,true); await step(0.05); key(KEY_Q,false)
					await step(0.9,[0.05,0.13,0.2,0.3,0.42,0.55],nm)
				"draw":
					var other:="mp40" if g!="mp40" else "ak"
					wpn.switch_to(other); await step(1.5)
					wpn.switch_to(g); await step(1.2,[0.1,0.25,0.4,0.55,0.75,1.0],nm)
	quit()
