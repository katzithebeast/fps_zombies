extends Node3D
## Bedna se zbraní, skříňka, munice a pracovní stůl na vylepšení. Ovládání: E.

const Props:=preload("res://scripts/props.gd")
const CRATE_COST:=950
const AMMO_COST:=750
const UPGRADE_COST:=2500
const REACH:=1.9
const OUTLINE:=preload("res://assets/props/outline.tres")

var mode: Node          # zombie_mode
var main: Node
var items: Array=[]     # {kind, node, pos, state, t, ...}
var _canvas: Control
var _tag_font: Font
var prompt_text:=""
var _focus: Dictionary={}

func setup(zombie_mode: Node, main_node: Node, places: Dictionary) -> void:
	mode=zombie_mode
	main=main_node
	# Zbraně do bedny načíst předem, jinak se hra při otevření zasekne.
	for gun in main.player.body.weapon.GUNS:
		_gun_scenes[gun]=load(main.player.body.weapon.GUNS[gun].scene)
	for kind in places:
		for place in places[kind]:
			_add(kind,place[0],place[1],place.slice(2))
	_stock_all()
	_add_wallbuys.call_deferred()
	var layer:=CanvasLayer.new()
	layer.layer=5
	add_child(layer)
	# Popisek u předmětu: tečka na modelu, šikmá čára nahoru a vodorovná čára se jménem.
	_canvas=Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_tags)
	layer.add_child(_canvas)
	var system:=SystemFont.new()
	system.font_names=PackedStringArray(["Bahnschrift","Segoe UI","Helvetica Neue","Arial","DejaVu Sans"])
	system.font_weight=600
	_tag_font=system

# ------------------------------------------------------------------ zbraně na zdi (jako v CoD)
# Křídou nakreslený obrys zbraně na zdi; E = koupit zbraň, když ji máš, E = munice do ní za polovic.
const WALLBUYS:=[
	# [místnost (obdélník půdorysu), zbraň, cena]
	[Rect2(2.6,-1.2,10.0,12.0),"mp40",1000], [Rect2(-12.6,-26.6,25.2,25.4),"deagle",1200],
	[Rect2(-22.6,-19.8,10.0,9.4),"izh54",1500], [Rect2(20.0,-34.6,27.2,33.2),"ak",2000],
	[Rect2(23.4,-1.4,19.2,19.0),"deagle",1200], [Rect2(45.4,23.4,17.2,17.2),"ak",2000],
	[Rect2(-13.2,-46.6,26.4,20.6),"mp40",1000], [Rect2(-33.8,-59.4,20.6,36.6),"mp40",1000],
	[Rect2(-10.6,-59.4,15.2,12.8),"deagle",1200], [Rect2(13.2,-56.6,17.4,22.6),"izh54",1500],
]
const WALLBUY_LEN:={"ak":1.25,"mp40":1.15,"deagle":0.62,"izh54":1.4}

func _add_wallbuys() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space: PhysicsDirectSpaceState3D=main.get_world_3d().direct_space_state
	var rng:=RandomNumberGenerator.new()
	rng.seed=404
	for entry in WALLBUYS:
		var rect: Rect2=entry[0]
		var gun: String=entry[1]
		var tex: Texture2D=load("res://textures/wallbuy/%s.png" % gun)
		var w: float=float(WALLBUY_LEN[gun])
		var h: float=w*float(tex.get_height())/float(tex.get_width())
		var spot:=_find_wall(space,rect,w+0.3,h+0.2,rng)
		if spot.is_empty(): continue
		var n: Vector3=spot.normal
		var d:=Decal.new()
		d.texture_albedo=tex
		d.texture_emission=tex
		d.emission_energy=0.15        # křída jemně svítí, aby byla vidět i v šeru
		d.texture_orm=load("res://textures/walldecals/rough_orm.png")
		d.size=Vector3(w,0.2,h)
		d.normal_fade=0.6
		d.cull_mask=1
		d.layers=1<<19
		d.upper_fade=0.2
		d.lower_fade=0.2
		add_child(d)
		d.global_transform=Transform3D(load("res://scripts/blood_dressing.gd").orient(n,0.0),spot.pos+n*0.03)
		# Zbraň na zdi míří doprava od hráče (jako na obrázku); otočit podle strany zdi není potřeba.
		items.append({"kind":"wallbuy","node":d,"pos":spot.pos+n*0.35-Vector3(0,0.6,0),"top":0.0,"state":"idle","t":0.0,
			"gun":gun,"cost":int(entry[2]),"prize":"","show":null,"open":0.0})

func _find_wall(space: PhysicsDirectSpaceState3D, rect: Rect2, w: float, h: float, rng: RandomNumberGenerator) -> Dictionary:
	# Volná rovná zeď v dané místnosti ve výšce ~1,4 m nad podlahou, co nejblíž středu místnosti.
	var best:={}
	var best_d:=1e9
	for attempt in 24:
		var p:=rect.get_center() if attempt==0 else Vector2(rng.randf_range(rect.position.x+1,rect.end.x-1),rng.randf_range(rect.position.y+1,rect.end.y-1))
		# Shora dolů projít všechny plochy (strop, podlaha, dno bazénu) a vzít nejnižší podlahu nad vodou.
		var fy:=INF
		var top:=8.0
		for layer_i in 6:
			var hit_f:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x,top,p.y),Vector3(p.x,-6.0,p.y),1))
			if hit_f.is_empty(): break
			var hy: float=hit_f.position.y
			# Podlaha = plocha nahoru s místem nad sebou.
			# (mělká voda do 0,6 m je pořád podlaha, hluboký bazén ne; střechy jsou výš než 2 m)
			if (hit_f.normal as Vector3).y>0.85 and hy>=main.WATER_Y-0.6 and hy<2.0 and top-hy>2.2: fy=hy
			top=hy-0.05
		if fy==INF: continue
		var from:=Vector3(p.x,fy+1.4,p.y)
		for k in 16:
			var dir:=Vector3.FORWARD.rotated(Vector3.UP,TAU*k/16.0)
			var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(from,from+dir*12.0,1))
			if hit.is_empty() or hit.collider!=main.world_body: continue
			var n: Vector3=hit.normal
			if absf(n.y)>0.1: continue
			var center: Vector3=hit.position
			if not _flat_wall(space,center,n,w,h): continue
			var clash:=false
			for item in items:
				if (item.pos as Vector3).distance_to(center)<2.5: clash=true
			if clash: continue
			var d:=from.distance_to(center)
			if d<best_d:
				best_d=d
				best={"pos":center,"normal":n}
		if not best.is_empty() and attempt>=6: break
	return best

func _flat_wall(space: PhysicsDirectSpaceState3D, center: Vector3, n: Vector3, w: float, h: float) -> bool:
	var tangent:=n.cross(Vector3.UP).normalized()
	for sx in [-0.5,-0.25,0.0,0.25,0.5]:
		for sy in [-0.5,0.0,0.5]:
			var t: Vector3=center+tangent*float(sx)*w+Vector3.UP*float(sy)*h
			var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(t+n*0.4,t-n*0.2,1))
			if hit.is_empty(): return false
			if (hit.normal as Vector3).dot(n)<0.97 or absf((hit.position-center).dot(n))>0.04: return false
	# Před zdí volno (nic tam nestojí).
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(center+n*0.1,center+n*1.3,1)).is_empty()

func _add(kind: String, pos: Vector3, yaw: float, extra: Array=[]) -> void:
	if kind=="gate":
		_add_gate(pos,yaw,extra)
		return
	var model_kind: String={"crate":"crate","locker":"locker","ammo":"ammo","bench":"bench"}[kind]
	var model: Node3D=Props.make(model_kind)
	add_child(model)
	model.global_position=pos
	model.rotation.y=yaw
	# Kolize podle rozměrů modelu, ať jimi hráč ani zombie neprochází.
	var size: Vector3=Props._bounds(model).size
	if kind=="locker":
		# Skříňka má přesnou kolizi z modelu (bez dvířek), aby věci ležely na policích.
		for mesh in model.find_children("*","MeshInstance3D",true,false):
			if "Door" in String(mesh.get_path()): continue
			var solid:=StaticBody3D.new()
			var trimesh:=CollisionShape3D.new()
			trimesh.shape=(mesh as MeshInstance3D).mesh.create_trimesh_shape()
			solid.add_child(trimesh)
			mesh.add_child(solid)
	else:
		var body:=StaticBody3D.new()
		var shape:=CollisionShape3D.new()
		var box:=BoxShape3D.new()
		box.size=Vector3(size.x,size.y,size.z)*0.95
		shape.shape=box
		shape.position.y=size.y*0.5
		body.add_child(shape)
		model.add_child(body)
	var glow:=OmniLight3D.new()
	glow.light_color={"crate":Color(0.35,0.75,1.0),"locker":Color(1.0,0.85,0.55),"ammo":Color(1.0,0.75,0.25),"bench":Color(0.75,0.35,1.0)}[kind]
	glow.light_energy=0.35
	glow.omni_range=2.8
	glow.shadow_enabled=false
	glow.position=Vector3(0,size.y+0.5,0)
	model.add_child(glow)
	items.append({"kind":kind,"node":model,"pos":pos,"top":size.y,"state":"idle","t":0.0,"gun":"","prize":"","show":null,"open":0.0})

func _add_gate(pos: Vector3, yaw: float, extra: Array) -> void:
	var cost: int=extra[0]
	var width: float=extra[1]
	var height: float=extra[2]
	var model: Node3D=Props.gate(width,height)
	add_child(model)
	Props.merge(model)
	model.global_position=pos
	model.rotation.y=yaw
	var body:=StaticBody3D.new()
	var shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(width,height,0.25)
	shape.shape=box
	shape.position.y=height*0.5
	body.add_child(shape)
	model.add_child(body)
	items.append({"kind":"gate","node":model,"pos":pos,"top":height*0.7,"state":"idle","t":0.0,"gun":"","prize":"","show":null,"open":0.0,"cost":cost,"body":body,"base":pos,"index":_gate_count})
	_gate_count+=1

func reset() -> void:
	var reopened:=false
	for item in items:
		if item.kind=="gate":
			if item.state!="idle": reopened=true
			item.node.global_position=item.base
			item.body.process_mode=Node.PROCESS_MODE_INHERIT
			(item.body.get_child(0) as CollisionShape3D).disabled=false
		item.state="idle"
		item.open=0.0
		item.t=0.0
		_hide_show(item)
		_pose(item)
	_stock_all()

func _stock(item: Dictionary) -> void:
	# Obsah skříňky leží uvnitř už předem, za zavřenými dvířky.
	if item.show: item.show.queue_free()
	item.show=null
	var roll:=randf()
	item.prize="ammo" if roll<0.35 else "syringe" if roll<0.65 else "points" if roll<0.85 else ""
	if item.prize=="": return
	var prize: Node3D=Props.make({"ammo":"ammo","syringe":"syringe","points":"money"}[item.prize])
	if item.prize=="ammo": prize.scale=Vector3.ONE*0.7
	item.node.add_child(prize)
	var from: Vector3=item.node.global_transform*Vector3(0,1.15,0.02)
	var hit: Dictionary=item.node.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,from+Vector3.DOWN*1.3,1))
	var spot: Vector3=hit.position if hit else item.node.global_transform*Vector3(0,0.12,0)
	prize.global_position=spot+Vector3.UP*0.003
	prize.rotation.y=randf_range(-0.4,0.4)+(PI/2 if item.prize=="syringe" else 0.0)
	item.show=prize

func _stock_all() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	for item in items:
		if item.kind=="locker" and item.state=="idle": _stock(item)

func round_started() -> void:
	# Prázdné skříňky se novým kolem zase zavřou a naplní.
	for item in items:
		if item.kind=="locker" and item.state=="empty": item.state="closing"
		item["used_round"]=false        # hororový režim: bedna a munice jednou za kolo

func _pose(item: Dictionary) -> void:
	if item.kind=="crate": Props.open_crate(item.node,item.open)
	elif item.kind=="locker": Props.open_locker(item.node,item.open)

func _label(item: Dictionary) -> Array:
	# [jméno nad čarou, akce pod čarou]
	var weapon: Node=main.player.weapon
	var paid: bool=mode.active and not mode.horror()
	if mode.active and mode.horror():
		# Hororový režim: věci jsou vzácné – bedna a munice jednou za kolo, každá zbraň na zdi jen jednou.
		if item.kind in ["crate","ammo"] and item.get("used_round",false) and item.state=="idle":
			return ["Tajemná bedna" if item.kind=="crate" else "Munice","prázdné – zkus další kolo"]
		if item.kind=="wallbuy" and item.get("taken",false): return ["Prázdný držák",""]
		if item.kind=="wallbuy" and weapon.owned.has(item.gun): return [weapon.STATS[item.gun].name,"už ji máš"]
	if item.kind=="quest": return item.lbl.call()
	match item.kind:
		"crate":
			match item.state:
				"idle": return ["Tajemná bedna","E  otevřít" + ("   %d" % CRATE_COST if paid else "")]
				"ready": return [weapon.STATS[item.gun].name,"E  vzít"]
				"rolling": return ["Tajemná bedna",""]
		"locker":
			match item.state:
				"idle":
					if item.get("lock37",false) and not item.get("opened37",false):
						var q=main.get("quest")
						return ["Skříňka č. 37","E  odemknout náramkem" if q and q.has_band else "zamčeno"]
					return ["Skříňka","E  otevřít"]
				"ready": return [{"ammo":"Munice","syringe":"Injekce","points":"300 bodů","uv":"UV lampa"}.get(item.prize,""),"E  vzít"]
				"empty": return ["Skříňka","prázdná"]
		"ammo":
			if item.state=="idle": return ["Munice","E  doplnit" + ("   %d" % AMMO_COST if paid else "")]
		"gate":
			if item.state=="idle":
				if item.get("locked",false): return ["Zarezlá mříž","nehne se"]
				return ["Brána","E  otevřít" + ("   %d" % item.cost if paid else "")]
		"note":
			var read: bool=main.notes._read.has(item.note) if main.get("notes") else false
			return [String(main.notes.NOTES[item.note][1]) if read else "Vzkaz","E  číst" + ("  znovu" if read else "")]
		"wallbuy":
			var gname: String=weapon.STATS[item.gun].name
			if weapon.owned.has(item.gun): return ["Munice – "+gname,"E  doplnit" + ("   %d" % int(item.cost/2) if paid else "")]
			return [gname,"E  koupit" + ("   %d" % item.cost if paid else "")]
		"bench":
			if item.state=="idle":
				var q=main.get("quest")
				if q==null or not mode.active:
					if weapon.upgraded.has(weapon.current): return ["Pracovní stůl","%s je vylepšená" % weapon.display_name()]
					return ["Pracovní stůl","E  vylepšit %s" % weapon.display_name()]
				if not q.power: return ["Pracovní stůl","bez proudu"]
				var tier: int=weapon.tier(weapon.current)
				if tier>=3: return ["Pracovní stůl","%s – stůl víc nezvládne" % weapon.display_name()]
				var cost: Dictionary=q.bench_cost(tier+1)
				return ["Pracovní stůl  →  stupeň %s" % ["I","II","III"][tier],("E  " if q.can_afford(cost) else "chybí: ")+q.cost_text(cost,paid)]
	return []

func _target(item: Dictionary) -> Node3D:
	# Co se má zvýraznit: vystavená věc (zbraň v bedně, obsah skříňky), jinak celý předmět.
	if item.get("show") and item.state=="ready" and is_instance_valid(item.show): return item.show
	return item.node

func _anchor(item: Dictionary) -> Vector3:
	var node:=_target(item)
	if node!=item.node:
		var b:=Props._bounds(node)
		return node.global_transform*b.get_center()
	return item.node.global_position+Vector3.UP*(float(item.top)*0.55)

func _set_outline(node, on: bool) -> void:
	if node==null or not is_instance_valid(node): return
	for m in node.find_children("*","MeshInstance3D",true,false):
		if not (m as MeshInstance3D).visible: continue
		(m as MeshInstance3D).material_overlay=OUTLINE if on else null

func _draw_tags() -> void:
	if _focus.is_empty(): return
	var lines: Array=_label(_focus)
	if lines.is_empty(): return
	var camera: Camera3D=main.player.camera
	var anchor: Vector3=_anchor(_focus)
	if camera.is_position_behind(anchor): return
	var dot: Vector2=camera.unproject_position(anchor)
	var bend:=dot+Vector2(46,-58)
	var name_size:=_tag_font.get_string_size(lines[0],HORIZONTAL_ALIGNMENT_LEFT,-1,30)
	var end:=bend+Vector2(maxf(name_size.x+24,150),0)
	var ink:=Color(1,1,1,0.92)
	var shade:=Color(0,0,0,0.6)
	for pass_i in 2:
		var c:=shade if pass_i==0 else ink
		var o:=Vector2(1.5,1.5) if pass_i==0 else Vector2.ZERO
		_canvas.draw_circle(dot+o,5.5,c)
		_canvas.draw_polyline(PackedVector2Array([dot+o,bend+o,end+o]),c,2.2,true)
		_canvas.draw_string(_tag_font,bend+o+Vector2(14,-10),lines[0],HORIZONTAL_ALIGNMENT_LEFT,-1,30,c)
		if lines[1]!="": _canvas.draw_string(_tag_font,bend+o+Vector2(14,24),lines[1],HORIZONTAL_ALIGNMENT_LEFT,-1,18,c if pass_i==0 else Color(1,0.85,0.5,0.95))

func _process(dt: float) -> void:
	var _perf_t0:=Time.get_ticks_usec()
	_process_timed(dt)
	PerfMon.add("Stanice a popisky",Time.get_ticks_usec()-_perf_t0)

var _bang_t:=12.0

func _gate_banging(dt: float, player: Node3D) -> void:
	# Za zavřenými branami občas něco buší do kovu – zombie čekají na druhé straně.
	_bang_t-=dt
	if _bang_t>0.0 or not mode.active: return
	_bang_t=randf_range(14.0,38.0)
	var near:=[]
	for item in items:
		if item.kind=="gate" and item.state=="idle" and (item.pos as Vector3).distance_to(player.global_position)<26.0: near.append(item)
	if near.is_empty(): return
	var gate: Dictionary=near.pick_random()
	var behind: Vector3=(gate.node as Node3D).global_transform.basis.z
	if behind.dot(player.global_position-gate.pos)>0.0: behind=-behind
	main.sfx.play_at("zombie_bang",gate.pos+behind*1.2+Vector3(0,1.2,0),-4.0,randf_range(0.88,1.05))

func _process_timed(dt: float) -> void:
	if main==null or main.player==null: return
	var player: Node3D=main.player
	_gate_banging(dt,player)
	var live: bool=mode.state!="dead"
	_focus={}
	var best:=REACH
	var eye: Vector3=player.camera.global_position
	var look: Vector3=-player.camera.global_basis.z
	for item in items:
		_update(item,dt)
		if not live: continue
		var center: Vector3=item.pos+Vector3(0,0.6,0)
		var to: Vector3=center-eye
		var d:=Vector2(to.x,to.z).length()
		if d<best and (to.normalized().dot(look)>0.55 or d<0.9):
			best=d
			_focus=item
	var lines: Array=_label(_focus) if not _focus.is_empty() else []
	var target: Node3D=_target(_focus) if not lines.is_empty() else null
	if target!=_outlined:
		_set_outline(_outlined,false)
		_set_outline(target,true)
		_outlined=target
	prompt_text=" / ".join(lines)
	_canvas.queue_redraw()
	if not lines.is_empty() and Input.is_physical_key_pressed(KEY_E) and not _e_held:
		_use(_focus)
	_e_held=Input.is_physical_key_pressed(KEY_E)

var _e_held:=false
var _gate_count:=0
var _outlined=null
var _gun_scenes:={}
var _gun_models:={}

func _pay(cost: int) -> bool:
	if not mode.active: return true     # mimo zombie režim zdarma
	if mode.horror(): return true       # v hororu se neplatí body – vzácnost hlídá omezený počet použití
	if mode.points<cost:
		main.sfx.play("tick",-6.0)
		mode._popup("Potřebuješ %d bodů" % cost,false)
		return false
	mode.points-=cost
	mode._popup("-%d" % cost,false)
	return true

func _use(item: Dictionary) -> void:
	var weapon: Node=main.player.weapon
	if mode.active and mode.horror():
		if item.kind in ["crate","ammo"] and item.state=="idle":
			if item.get("used_round",false):
				main.sfx.play("tick",-6.0)
				return
			item["used_round"]=true
		if item.kind=="wallbuy":
			if item.get("taken",false) or weapon.owned.has(item.gun):
				main.sfx.play("tick",-6.0)
				return
			item["taken"]=true
			(item.node as Decal).modulate=Color(1,1,1,0.25)      # obrys zbyde jen jako vybledlá stopa
		if item.kind=="bench" and item.state=="idle":
			if item.get("taken",false): return
			item["taken"]=true
	match item.kind:
		"quest":
			item.use.call()
		"note":
			if main.notes and not main.notes.is_open() and Engine.get_process_frames()-int(main.notes.closed_frame)>3: main.notes.open(item.note)
		"crate":
			if item.state=="idle" and _pay(CRATE_COST):
				item.state="rolling"
				item.t=0.0
				main.sfx.play_at("crate_open",item.pos+Vector3(0,0.6,0),-1.0)
				main.sfx.play_at("powerup_spawn",item.pos,-9.0)
			elif item.state=="ready":
				weapon.give(item.gun,true)
				main.sfx.play("powerup",-4.0)
				_close(item)
		"locker":
			if item.state=="idle" and item.get("lock37",false) and not item.get("opened37",false):
				var q=main.get("quest")
				if q==null or not q.has_band:
					main.sfx.play_at("lamp_click",item.pos+Vector3(0,1,0),-6.0,1.3)
					return
				item["opened37"]=true
				if item.show: item.show.queue_free()
				var holder: Node3D=q._inst("uv_flashlight",0.22,2)
				item.node.add_child(holder)
				holder.position=Vector3(0,1.12,0.0)
				holder.rotation.y=PI/2
				item.show=holder
				item.prize="uv"
			if item.state=="idle":
				item.state="opening"
				item.t=0.0
				main.sfx.play_at("locker_open",item.pos+Vector3(0,1,0),-2.0)
			elif item.state=="ready":
				_give_prize(item.prize)
				main.sfx.play("item_pickup",-4.0)
				item.show.queue_free()
				item.show=null
				item.state="empty"
		"gate":
			if item.state=="idle" and _pay(item.cost):
				item.state="opening"
				item.t=0.0
				(item.body.get_child(0) as CollisionShape3D).disabled=true
				main.sfx.play_at("gate_open",item.pos+Vector3(0,1.5,0),0.0)
		"wallbuy":
			if not weapon.owned.has(item.gun):
				if _pay(item.cost):
					weapon.give(item.gun,true)
					main.sfx.play("item_pickup",-2.0)
					main.sfx.play("powerup",-8.0)
			elif _pay(int(item.cost/2)):
				# Munice jen do této zbraně: plný zásobník i rezerva.
				weapon._store()
				weapon.clips[item.gun]=[weapon.stats_of(item.gun).mag,weapon.stats_of(item.gun).reserve]
				weapon._load_current()
				main.sfx.play("item_pickup",-2.0)
				mode._show_banner("","Munice doplněna",1.2)
		"ammo":
			if item.state=="idle" and _pay(AMMO_COST):
				weapon.refill_reserve()
				weapon.ammo=int(weapon.stats().mag)
				main.sfx.play("powerup",-5.0)
				mode._show_banner("","Munice doplněna",1.2)
		"bench":
			var q=main.get("quest")
			if item.state=="idle" and q!=null and mode.active:
				if not q.power or weapon.tier(weapon.current)>=3:
					main.sfx.play("tick",-6.0)
					return
				var cost: Dictionary=q.bench_cost(weapon.tier(weapon.current)+1)
				if not q.can_afford(cost):
					main.sfx.play("tick",-6.0)
					mode._popup("Chybí materiál",false)
					return
				if not _pay(int(cost.get("points",0))): return
				q.spend(cost)
				item.state="working"
				item.t=0.0
				weapon.upgrade(weapon.current)
				main.sfx.play_at("gib",item.pos,-8.0,0.5)
				mode._show_banner(weapon.display_name(),["","Větší zásobník a zásoba","Větší poškození, přesnost","Chlórové náboje"][weapon.tier(weapon.current)],2.0)
			elif item.state=="idle" and not weapon.upgraded.has(weapon.current) and _pay(UPGRADE_COST):
				item.state="working"
				item.t=0.0
				weapon.upgrade(weapon.current)
				main.sfx.play_at("gib",item.pos,-8.0,0.5)
				mode._show_banner(weapon.display_name(),"Vylepšeno: větší poškození a zásobník",2.0)

func _give_prize(prize: String) -> void:
	match prize:
		"uv":
			var q=main.get("quest")
			if q: q.took_uv()
		"ammo":
			if main.get("inventory"): main.inventory.add("ammo")
			else: mode._take("ammo")
		"syringe":
			if main.get("inventory"): main.inventory.add("syringe")
			else: mode._take("heal")
		"points":
			mode.points+=300
			mode._popup("+300",true)

func _hide_show(item: Dictionary) -> void:
	if item.show:
		if item.kind=="crate": item.show.visible=false
		else: item.show.queue_free()
	item.show=null

func _close(item: Dictionary) -> void:
	if item.kind=="crate": main.sfx.play_at("crate_close",item.pos+Vector3(0,0.6,0),-3.0)
	_hide_show(item)
	item.state="closing"

func _update(item: Dictionary, dt: float) -> void:
	item.t+=dt
	if item.kind=="gate":
		if item.state=="opening":
			var k:=clampf(item.t/1.6,0.0,1.0)
			item.node.global_position=item.base+Vector3.UP*smoothstep(0.0,1.0,k)*3.0+Vector3(randf_range(-0.01,0.01),0,0)*(1.0-k)
			if k>=1.0:
				item.state="open"
				if mode.has_method("_bake_navigation"): mode._bake_navigation()
				if mode.has_method("zone_opened"): mode.zone_opened(item.index)
		return
	match item.state:
		"rolling":
			# Bedna se otevře a uvnitř se střídají zbraně, nakonec jedna zůstane.
			item.open=minf(1.0,item.open+dt*2.5)
			var ending: bool=item.t>2.6
			if item.show==null or (not ending and fmod(item.t,0.16)<dt):
				var options:=["ak","mp40","izh54","deagle"]
				var pick: String=options[randi()%options.size()]
				if ending:
					var others:=options.filter(func(gun): return gun!=main.player.weapon.current)
					pick=others[randi()%others.size()]
				_show_gun(item,pick)
			if item.show: item.show.position.y=lerpf(0.15,0.55,minf(1.0,item.t/1.2))
			if ending:
				item.state="ready"
				item.t=0.0
				main.sfx.play_at("powerup",item.pos,-3.0)
		"ready":
			if item.kind=="crate":
				if item.show: item.show.rotation.y+=dt*0.6
				if item.t>9.0: _close(item)
		"closing":
			item.open=maxf(0.0,item.open-dt*2.0)
			if item.open<=0.0:
				item.state="idle"
				if item.kind=="locker": _stock(item)
		"opening":
			item.open=minf(1.0,item.open+dt*1.8)
			if item.open>=1.0:
				if item.prize=="":
					item.state="empty"
					mode._popup("Prázdná",false)
				else:
					item.state="ready"
		"working":
			if item.t>1.2: item.state="idle"

	_pose(item)

func _show_gun(item: Dictionary, gun: String) -> void:
	# Modely zbraní v bedně se vytvoří jednou a jen se přepíná viditelnost.
	if not _gun_models.has(item.node):
		var holder:=Node3D.new()
		item.node.add_child(holder)
		var models:={}
		for key in _gun_scenes:
			var model: Node3D=_gun_scenes[key].instantiate()
			model.rotation=Vector3(0,PI/2,0)
			model.position.x=0.25
			holder.add_child(model)
			models[key]=model
		_gun_models[item.node]={"holder":holder,"models":models}
	var entry: Dictionary=_gun_models[item.node]
	for key in entry.models: entry.models[key].visible=key==gun
	entry.holder.visible=true
	item.show=entry.holder
	item.gun=gun
