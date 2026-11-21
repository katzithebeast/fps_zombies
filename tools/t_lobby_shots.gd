extends SceneTree
## Náhledy pokoje: --script res://tools/t_lobby_shots.gd -- --out=/tmp/lobby
var views:=[
	["vstup",Vector3(-1.0,0,1.3),-25.0,2.0],
	["okno",Vector3(1.6,0,1.2),35.0,10.0],
	["postel",Vector3(1.0,0,-0.9),100.0,-10.0],
	["tv",Vector3(1.2,0,0.6),90.0,-8.0],
	["dvere",Vector3(0.8,0,-1.0),160.0,-2.0],
	["stul",Vector3(0.8,0,-0.6),20.0,-25.0],
	["umyvadlo",Vector3(0.4,0,0.3),180.0,-12.0],
]
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var out:="/tmp/lobby"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out=a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	var lob: Node3D=load("res://lobby.tscn").instantiate()
	root.add_child(lob)
	for i in 100: await process_frame
	for v in views:
		lob._flicker_t=999.0
		lob._flicker=0.0
		lob.player.position=v[1]
		lob._yaw=deg_to_rad(float(v[2]))
		lob._pitch=deg_to_rad(float(v[3]))
		for i in 25: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s.png"%[out,v[0]])
		print("shot ",v[0])
	quit()
