extends SceneTree
var main: Node3D
func _initialize() -> void:
	call_deferred("run")
func walk(p: Player, from: Vector3, yaw: float, secs: float) -> void:
	p.teleport(from,yaw,0.0)
	await create_timer(0.3).timeout
	var ev:=InputEventKey.new(); ev.physical_keycode=KEY_W; ev.keycode=KEY_W; ev.pressed=true
	Input.parse_input_event(ev)
	await create_timer(secs).timeout
	ev=ev.duplicate(); ev.pressed=false
	Input.parse_input_event(ev)
	await create_timer(0.2).timeout
	print("z ",from," -> ",p.global_position.snapped(Vector3.ONE*0.01))
func run() -> void:
	main=load("res://main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.6).timeout
	main._on_play()
	await create_timer(1.5).timeout
	var p: Player=main.player
	await walk(p,Vector3(33,-0.35,2.0),PI,4.0)        # terasy nahoru (+z)
	await walk(p,Vector3(44,1.45,13.0),-PI/2,3.0)      # chodba schody nahoru (+x)
	await walk(p,Vector3(51,2.45,14.5),PI,6.0)         # dlouhé schody dolů (+z)
	await walk(p,Vector3(51,-0.35,23.0),0.0,6.0)       # a zase nahoru (-z)
	await walk(p,Vector3(39,1.45,16.0),PI,6.0)          # zadní chodba dolů
	await walk(p,Vector3(39.5,-0.35,27.0),-PI/2,5.0)    # do kulaté síně
	await walk(p,Vector3(39,-0.35,26.0),0.0,6.0)        # zpátky nahoru na terasy
	await walk(p,Vector3(28.5,-0.35,-54.0),PI,8.0)      # atrium: schody na balkon
	await walk(p,Vector3(-20.2,-0.35,-21.0),0.0,3.0)     # z chodby do bludiště (brána zavřená -> zastaví se)
	await walk(p,Vector3(5.5,-0.35,-52.0),-PI/2,5.0)     # tunelem do atria
	quit()
