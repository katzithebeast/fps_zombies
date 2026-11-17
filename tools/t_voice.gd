extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var main=load("res://main.tscn").instantiate()
	root.add_child(main)
	main.settings["intro"]=false
	await create_timer(0.6).timeout
	main._on_play()
	var v=main.voice
	print("streams ",v._streams.size())
	var seen := []
	for i in 160:
		await create_timer(0.25).timeout
		if v._current!="" and not (v._current in seen):
			seen.append(v._current); print("t=",snapped(v._clock,0.1)," ",v._current," prompt=",v._prompt_on," sub=",v._sub.text.substr(0,50))
	print("flash ",main.flashlight.visible)
	main.flashlight.visible=true
	main.notes.open(0); await create_timer(0.3).timeout; main.notes.close()
	v._last_think=-1000.0
	main.player.teleport(Vector3(54,-2.5,32) if false else main.player.global_position,0,0)
	for i in 60:
		await create_timer(0.25).timeout
		if v._current!="" and not (v._current in seen):
			seen.append(v._current); print("t=",snapped(v._clock,0.1)," ",v._current," prompt=",v._prompt_on)
	print("done ",v._done.keys())
	quit()
