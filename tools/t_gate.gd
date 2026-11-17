extends SceneTree
var main: Node3D
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	main=load("res://main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.6).timeout
	main._on_play()
	await create_timer(1.5).timeout
	var p: Player=main.player
	var mode=main.mode
	p.weapon.equip()
	mode.begin()
	await create_timer(0.5).timeout
	var st=mode.stations
	p.teleport(Vector3(10.8,-0.35,-14.0),-PI/2,0.0)
	await create_timer(0.6).timeout
	print("pozice ",p.global_position," popis='",st.prompt_text,"' body=",mode.points)
	Input.action_press("ui_accept")
	mode.points=5000
	await create_timer(0.3).timeout
	print("s body popis='",st.prompt_text,"'")
	var ev:=InputEventKey.new(); ev.physical_keycode=KEY_E; ev.pressed=true
	Input.parse_input_event(ev)
	await create_timer(0.3).timeout
	var ev2:=InputEventKey.new(); ev2.physical_keycode=KEY_E; ev2.pressed=false
	Input.parse_input_event(ev2)
	await create_timer(2.5).timeout
	for it in st.items: if it.kind=="gate": print("brana ",it.pos," stav ",it.state)
	print("body ",mode.points," spawny ",mode._zone_spawns.size())
	p.teleport(Vector3(15.0,-0.35,-14.0),-PI/2,0.0)
	await create_timer(1.0).timeout
	print("v chodbe ",p.global_position)
	quit()
