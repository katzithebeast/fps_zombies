extends SceneTree
## Přebíjení zblízka (ruce 1. osoby, pohled zleva zepředu): GUNS=ak,... → /tmp/gr_<zbraň>_<k>.png
var player: Player
func _initialize() -> void: call_deferred("run")
func tick(dt: float) -> void:
	player.weapon.update(dt)
	player.body.update_body(dt,Vector3.ZERO,0,Vector3.ZERO,false,false,true)
func run() -> void:
	root.size=Vector2i(640,480)
	var env:=Environment.new(); env.background_mode=Environment.BG_COLOR; env.background_color=Color(0.33,0.37,0.4)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color=Color(0.75,0.78,0.82); env.ambient_light_energy=0.75
	var we:=WorldEnvironment.new(); we.environment=env; root.add_child(we)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-45,140,0); sun.light_energy=1.1; root.add_child(sun)
	var fill:=DirectionalLight3D.new(); fill.rotation_degrees=Vector3(-20,-60,0); fill.light_energy=0.5; root.add_child(fill)
	player=Player.new(); root.add_child(player); player.set_process(false); player.set_physics_process(false)
	var cam:=Camera3D.new(); root.add_child(cam); cam.current=true; cam.near=0.02; cam.fov=50
	cam.cull_mask=0xFFFFF & ~4
	player.body.reset(0)
	var w: Node=player.weapon
	var rig: Node=player.body.weapon
	var guns:=OS.get_environment("GUNS").split(",") if OS.get_environment("GUNS")!="" else PackedStringArray(["ak","mp40","deagle","izh54"])
	var phases:=[0.06,0.14,0.22,0.5,0.66,0.74,0.86,0.95]
	for gun in guns:
		w.give(gun,false); w.switch_to(gun,true)
		for i in 100: tick(1.0/60.0)
		w.ammo=0
		w.reload()
		var k:=0
		var total: float=rig.reload_time
		var t:=0.0
		while k<phases.size():
			tick(1.0/60.0)
			t+=1.0/60.0
			if t/total>=phases[k]:
				var gx: Transform3D=rig.first.global_transform
				var gb: Basis=gx.basis.orthonormalized()
				var c: Vector3=gx*Vector3(0,-0.04,-0.16 if gun!="deagle" else -0.03)
				cam.global_position=c+gb*Vector3(-0.42,-0.12,-0.38)
				cam.look_at(c,gb.y)
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("/tmp/gr_%s_%d.png"%[gun,k])
				k+=1
	quit()
