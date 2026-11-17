extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var main=load("res://main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.6).timeout
	main._on_play()
	await create_timer(4.0).timeout
	var mode=main.mode
	var all: Array=mode.WALK_SPAWNS.duplicate()
	for z in mode.ZONE_SPAWNS: all.append_array(z)
	print("spawnu ",all.size()," der ",mode._holes.size())
	for s in all:
		if not mode._holes.has(s): print("  bez diry ",s)
	print("krev ",main.find_children("*","Decal",true,false).size())
	quit()
