extends SceneTree
class MockWeapon extends Node:
	var owned:={"ak":true,"deagle":true}
	var current:="ak"
	var equipped:=true
	const STATS:={"ak":{"name":"AK-47"},"mp40":{"name":"MP 40"},"izh54":{"name":"IŽ-54"},"deagle":{"name":"Desert Eagle"}}
	func display_name(): return "AK-47 II"
	func switch_to(g): current=g; equipped=true
	func holster(): equipped=false
	func refill_reserve(): pass
class MockBodyW extends Node:
	var GUNS={"ak":{"scene":"res://assets/ak47/ak47.tscn"},"mp40":{"scene":"res://assets/mp40/mp40.tscn"},"izh54":{"scene":"res://assets/izh54/izh54.tscn"},"deagle":{"scene":"res://assets/deagle/deagle.tscn"}}
class MockBody extends Node:
	var weapon=MockBodyW.new()
class MockPlayer extends Node3D:
	var weapon=MockWeapon.new()
	var body=MockBody.new()
	var control_enabled:=true
	var input_suspended:=false
class MockMode extends Node:
	var active:=true
	var health:=40.0
	var _regen_wait:=0.0
	func _popup(t,b): print("popup ",t)
class MockSfx extends Node:
	func play(a,b=0.0,c=1.0): pass
class MockMain extends Node3D:
	var player
	var mode=MockMode.new()
	var sfx=MockSfx.new()
	var quest
	var menu=null
	var notes=null
func _initialize() -> void:
	call_deferred("run")
func run():
	var m:=MockMain.new(); root.add_child(m)
	m.player=MockPlayer.new(); m.add_child(m.player)
	var env:=WorldEnvironment.new(); var e:=Environment.new(); e.background_mode=Environment.BG_COLOR; e.background_color=Color(0.18,0.2,0.16); env.environment=e; m.add_child(env)
	m.quest=load("res://scripts/quest.gd").new(); m.add_child(m.quest)
	var inv=load("res://scripts/inventory.gd").new(); m.add_child(inv); inv.setup(m)
	inv.add("syringe",2); inv.add("ammo",1); inv.add("scrap",7); inv.add("parts",3); inv.add("chlor",2); inv.add("fuse",2); inv.add("uv"); inv.add("band"); inv.add("wheel")
	for i in 120: await process_frame
	print("icons ",inv.icons.keys())
	print("count syringe ",inv.count("syringe")," hotbar ",inv.hotbar)
	inv.use("syringe"); print("health ",m.mode.health," syr ",inv.count("syringe"))
	inv.move("bag",0,"bag",7)
	inv.toggle()
	for i in 20: await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/ws/inv.png")
	inv.toggle()
	for i in 5: await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/ws/inv_hud.png")
	quit()
