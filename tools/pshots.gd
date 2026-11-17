extends SceneTree
# Náhled předmětů: --kinds=crate,locker  --open=0.0
var args:={}
func _init():
	for a in OS.get_cmdline_user_args():
		var kv:=a.trim_prefix("--").split("=")
		args[kv[0]]=kv[1] if kv.size()>1 else "1"
	var Props=load("res://scripts/props.gd")
	var world:=Node3D.new(); root.add_child(world)
	var env:=WorldEnvironment.new(); env.environment=Environment.new(); env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(0.25,0.27,0.3); env.environment.ambient_light_color=Color.WHITE; env.environment.ambient_light_energy=0.6; env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; world.add_child(env)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-45,-30,0); world.add_child(sun)
	var kinds:PackedStringArray=String(args.get("kinds","crate")).split(",")
	var amount:=float(args.get("open","0"))
	var x:=0.0
	for k in kinds:
		var m: Node3D=Props.make(k)
		world.add_child(m)
		m.position.x=x
		if k=="crate": Props.open_crate(m,amount)
		if k=="locker": Props.open_locker(m,amount)
		var b: AABB=Props._bounds(m)
		print(k," size ",b.size.snapped(Vector3.ONE*0.01))
		x+=maxf(b.size.x,0.4)+0.5
	var cam:=Camera3D.new(); world.add_child(cam)
	cam.look_at_from_position(Vector3(x*0.5-0.3+float(args.get("cx","0")),float(args.get("cy","1.4")),float(args.get("cz","2.6"))),Vector3(x*0.5-0.3,float(args.get("ty","0.4")),0))
	cam.current=true
	for i in 8: await process_frame
	root.get_texture().get_image().save_png("/tmp/ws/props_%s.png"%args.get("name","p"))
	quit()
