extends Node3D
## Stará krev po zdech a podlahách: cákance, otisky dlaní, šmouhy a stékající krev ve spodní části zdí.
## Místa se hledají paprsky z náhodných bodů v místnostech, takže sedí na skutečné stěny.

const DIR:="res://assets/blood/"
const SPLAT:=["splatters_01_radial_impact","splatters_02_horizontal_spray","splatters_03_diagonal_impact","splatters_05_heavy_splash","splatters_06_scattered_drops","splatters_07_double_impact","splatters_08_droplet_trail"]
const HANDS:=["handprints_01_full_palm_01","handprints_02_full_palm_02","handprints_03_partial_palm_01","handprints_04_dry_palm_02","handprints_05_short_drag","handprints_06_long_drag","handprints_07_sideways_smear","handprints_08_paired_partial_prints"]
const SMEARS:=["smears_01_horizontal_wipe","smears_02_diagonal_scrape","smears_03_vertical_wipe","smears_07_curved_drag","smears_08_dried_wipe"]
const DRIPS:=["smears_04_gravity_drips","smears_05_thin_drip"]
const POOLS:=["smears_06_blood_pool"]
const WALL_DECALS:=1500
const FLOOR_DECALS:=380

var _tex:={}

func _texture(name: String) -> Texture2D:
	if not _tex.has(name): _tex[name]=load(DIR+name+".png")
	return _tex[name]

static func orient(normal: Vector3, spin: float) -> Basis:
	# Decal promítá podél své osy -Y; na stěně drží „nahoru“ textury nahoře (+Z obrázku dolů).
	var y:=normal.normalized()
	var ref:=Vector3.UP if absf(y.y)<0.9 else Vector3.FORWARD
	var x:=ref.cross(y).normalized()
	var z:=x.cross(y).normalized()
	return Basis(x,y,z)*Basis(Vector3.UP,spin)

func make_decal(name: String, at: Vector3, normal: Vector3, size: float, spin: float, strength: float) -> Decal:
	var d:=Decal.new()
	d.texture_albedo=_texture(name)
	var t: Texture2D=d.texture_albedo
	var aspect:=float(t.get_width())/maxf(float(t.get_height()),1.0)
	size*=1.4
	d.size=Vector3(size*aspect,0.24,size)
	# Přes roh se nepromítat: plochy natočené jinak než zeď krev nedostanou (jinak se roztáhne do šmouh).
	d.normal_fade=0.6
	d.albedo_mix=1.0
	# Stará krev je zaschlá a tmavá (ne zářivě červená); pod hladinou ještě tmavší, téměř černá.
	var under: bool=at.y<-0.06
	d.modulate=Color(0.17,0.045,0.04,1.0) if under else Color(0.42,0.13,0.11,1.0)
	d.albedo_mix=clampf(strength+0.15,0.8,1.0)
	d.cull_mask=1
	d.layers=1<<19          # v odrazu vody se nekreslí
	d.distance_fade_enabled=true
	d.distance_fade_begin=18.0
	d.distance_fade_length=6.0
	d.upper_fade=0.15
	d.lower_fade=0.15
	add_child(d)
	d.global_transform=Transform3D(orient(normal,spin),at+normal*0.02)
	return d

# Hustota na 100 m² podlahy; každá místnost dostane aspoň minimum, ať není žádná čistá.
const WALL_PER_100:=34.0      # (dřív 60, ale 70 % končilo na střeše)
const FLOOR_PER_100:=9.0
const WALL_MIN:=20
const FLOOR_MIN:=6

# Paprsek na podlahu začíná pod stropem: ze 7 m trefil střechu a 70 % krve skončilo nahoře, kde ji nikdo neviděl.
const FLOOR_PROBE:=2.5
# Každá místnost má svůj příběh: masakr, běžně zašpiněná, nebo skoro čistá (kontrast dělá strach).
const TIERS:=[["masakr",1.9],["masakr",1.9],["špína",1.0],["špína",1.0],["špína",1.0],["špína",1.0],["klid",0.3],["klid",0.3]]

# Míra krve podle příběhu místa (indexy = main.MAP_RECTS): bufet, sprchy a kulatá síň jsou jatka,
# bludiště a les sloupů skoro čisté – liminální ticho, ve kterém je strach víc slyšet.
const AREA_TIERS:={0:["klid",0.3],1:["špína",1.0],2:["špína",1.0],3:["špína",1.0],4:["klid",0.35],5:["masakr",1.9],
	6:["špína",1.1],7:["klid",0.5],8:["špína",1.0],9:["masakr",1.9],10:["masakr",1.4],11:["klid",0.25],
	12:["klid",0.15],13:["masakr",2.0],14:["klid",0.5],15:["špína",1.0],16:["špína",1.3],17:["špína",1.1]}

static func room_tier(index: int, seed_value: int=7) -> Array:
	if AREA_TIERS.has(index): return AREA_TIERS[index]
	var rng:=RandomNumberGenerator.new()
	rng.seed=seed_value*7919+index*104729
	return TIERS[rng.randi()%TIERS.size()]

func scatter(rects: Array, seed_value: int=7) -> void:
	var rng:=RandomNumberGenerator.new()
	rng.seed=seed_value
	var walls:=0
	for i in rects.size():
		var r: Rect2=rects[i]
		var area: float=r.get_area()
		var mult: float=room_tier(i,seed_value)[1]
		var w:=maxi(int(WALL_MIN*mult),int(WALL_PER_100*area/100.0*mult))
		var f:=maxi(int(FLOOR_MIN*mult),int(FLOOR_PER_100*area/100.0*mult))
		walls+=_scatter_room([r],rng,w,f)
	print("krev: %d stop na zdech" % walls)

func _scatter_room(rects: Array, rng: RandomNumberGenerator, wall_count: int, floor_count: int) -> int:
	var space:=get_world_3d().direct_space_state
	var total:=0.0
	for r in rects: total+=(r as Rect2).get_area()
	var placed:=0
	var tries:=0
	while placed<wall_count and tries<wall_count*12:
		tries+=1
		var at:=_pick(rects,total,rng)
		var floor_hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x,FLOOR_PROBE,at.y),Vector3(at.x,-4.0,at.y),1))
		if floor_hit.is_empty() or (floor_hit.normal as Vector3).y<0.8: continue
		var floor_y: float=floor_hit.position.y
		var kind:=rng.randf()
		var height:=rng.randf_range(0.15,0.9) if kind<0.55 else rng.randf_range(0.6,1.5)
		var from:=Vector3(at.x,floor_y+height,at.y)
		var dir:=Vector3.FORWARD.rotated(Vector3.UP,rng.randf()*TAU)
		var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(from,from+dir*5.0,1))
		if hit.is_empty(): continue
		var n: Vector3=hit.normal
		if absf(n.y)>0.2: continue
		var name: String
		var size: float
		var spin:=0.0
		if kind<0.3:
			name=SPLAT[rng.randi()%SPLAT.size()]
			size=rng.randf_range(0.7,1.6)
			spin=rng.randf_range(-0.6,0.6)
		elif kind<0.5:
			name=DRIPS[rng.randi()%DRIPS.size()]
			size=rng.randf_range(0.5,0.9)
		elif kind<0.75:
			name=SMEARS[rng.randi()%SMEARS.size()]
			size=rng.randf_range(0.5,1.0)
			spin=rng.randf_range(-0.3,0.3)
		else:
			name=HANDS[rng.randi()%HANDS.size()]
			size=rng.randf_range(0.2,0.32)
			spin=rng.randf_range(-0.5,0.5)
		make_decal(name,hit.position,n,size,spin,rng.randf_range(0.6,0.95))
		placed+=1
	var on_walls:=placed
	# Kaluže a šmouhy na podlaze.
	placed=0
	tries=0
	while placed<floor_count and tries<floor_count*10:
		tries+=1
		var at:=_pick(rects,total,rng)
		var floor_hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x,FLOOR_PROBE,at.y),Vector3(at.x,-4.0,at.y),1))
		if floor_hit.is_empty() or (floor_hit.normal as Vector3).y<0.8: continue
		var list: Array=POOLS if rng.randf()<0.4 else SMEARS
		make_decal(list[rng.randi()%list.size()],floor_hit.position,Vector3.UP,rng.randf_range(0.9,2.2),rng.randf()*TAU,rng.randf_range(0.55,0.85))
		placed+=1
	return on_walls

func _pick(rects: Array, total: float, rng: RandomNumberGenerator) -> Vector2:
	var roll:=rng.randf()*total
	for r in rects:
		var rect: Rect2=r
		roll-=rect.get_area()
		if roll<=0.0: return Vector2(rng.randf_range(rect.position.x,rect.end.x),rng.randf_range(rect.position.y,rect.end.y))
	var last: Rect2=rects[rects.size()-1]
	return last.get_center()
