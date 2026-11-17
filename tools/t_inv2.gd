extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var main=load("res://main.tscn").instantiate()
	root.add_child(main)
	main.settings["intro"]=false
	await create_timer(0.6).timeout
	main._on_play()
	await create_timer(2.0).timeout
	main.mode.begin()
	await create_timer(1.0).timeout
	var inv=main.inventory
	print("weapons ",inv.count("ak"),inv.count("deagle")," hot ",inv.hotbar)
	main.quest.add_mat("scrap",5); inv.add("syringe",2)
	print("scrap ",inv.count("scrap")," quest mat ",main.quest.mat("scrap"))
	inv.toggle(); await create_timer(0.3).timeout
	var where=""; var idx=-1
	for c in inv.slots:
		for i in inv.slots[c].size():
			var s=inv.slots[c][i]
			if s!=null and s.id=="syringe": where=c; idx=i
	inv.move(where,idx,"ground",0)
	print("after drop syringe ",inv.count("syringe")," ground ",inv.ground.size())
	await create_timer(0.3).timeout
	inv.pick_from_ground(inv.ground[0])
	print("picked ",inv.count("syringe")," ground ",inv.ground.size())
	inv.toggle()
	main.mode.health=30.0
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var e=InputEventKey.new(); e.physical_keycode=KEY_1+inv.hotbar.find("syringe"); e.pressed=true; Input.parse_input_event(e)
	await create_timer(0.3).timeout
	print("health ",main.mode.health," syr ",inv.count("syringe"))
	quit()
