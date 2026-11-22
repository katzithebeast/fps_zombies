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
	["zrcadlo",Vector3(0.32,0,1.05),180.0,-2.0],
	["dolu",Vector3(0.6,0,-0.6),20.0,-55.0],
	["dolu2",Vector3(0.6,0,-0.6),20.0,-80.0],
	["chuze",Vector3(0.6,0,-0.6),20.0,-35.0],
	["prach",Vector3(1.6,0,0.9),60.0,8.0],
	["chodba_z",Vector3(-3.6,0,3.25),-90.0,-3.0],
	["chodba_dv",Vector3(-2.0,0,3.9),-70.0,-10.0],
	["chodba_v",Vector3(12.0,0,3.25),90.0,-3.0],
	["schody",Vector3(-2.0,0,3.6),75.0,-12.0],
	["sal",Vector3(14.8,0,3.3),-100.0,-6.0],
	["sal2",Vector3(23.2,0,7.6),40.0,-8.0],
	["wc",Vector3(3.8,0,5.0),-150.0,-12.0],
	["wc2",Vector3(8.4,0,4.9),120.0,-10.0],
	["pokoj8",Vector3(4.2,0,1.6),-10.0,-15.0],
	["pokoj10",Vector3(1.6,0,4.8),170.0,-18.0],
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
	var only:=""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="): only=a.trim_prefix("--only=")
	for v in views:
		if only!="" and not (v[0] in only.split(",")): continue
		lob._flicker_t=999.0
		lob._flicker=0.0
		if lob.player: lob.player.teleport(v[1],deg_to_rad(float(v[2])),deg_to_rad(float(v[3])))
		else: lob.cam.global_transform=Transform3D(Basis.from_euler(Vector3(deg_to_rad(float(v[3])),deg_to_rad(float(v[2])),0)),v[1]+Vector3(0,1.6,0))
		for i in 25: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s.png"%[out,v[0]])
		print("shot ",v[0])
	quit()
