extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var main=load("res://main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.6).timeout
	main._on_play()
	await create_timer(1.0).timeout
	var pm=null
	for n in main.get_children():
		if n.get_script()==load("res://scripts/perf_monitor.gd"): pm=n
	pm._start_recording()
	var p: Player=main.player
	p.teleport(Vector3(0,-0.35,-5),0.0,0.0)
	await create_timer(2.0).timeout
	p.teleport(Vector3(33,-0.35,-30),0.0,0.0)
	await create_timer(2.0).timeout
	pm._stop_recording()
	print(FileAccess.get_file_as_string(pm._dir()+"/perf_report.txt"))
	quit()
