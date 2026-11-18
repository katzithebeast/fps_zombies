extends RefCounted
## Distanční pole zbraně (metry, souřadnice zbraně): záporné uvnitř, kladné venku.
## Díly: body (pevné), magazine (posouvá se při přebíjení), barrel (sklápí se u dvojky).
## Pečeno offline: tools/export_gun_meshes.gd → tools/gun_sdf.py → tools/import_gun_sdf.gd
static var _cache:={}
var parts:={}            # díl → [data: PackedFloat32Array, origin: Vector3, cell: float, dims: Vector3i]

static func of(gun: String) -> RefCounted:
	if _cache.has(gun): return _cache[gun]
	var s=(load("res://scripts/gun_sdf.gd") as GDScript).new()
	for part in ["body","magazine","barrel"]:
		var path:="res://assets/guns_sdf/%s_%s.res"%[gun,part]
		if not ResourceLoader.exists(path): continue
		var img: Image=load(path)
		s.parts[part]=[img.get_data().to_float32_array(),img.get_meta("origin"),float(img.get_meta("cell")),img.get_meta("dims")]
	_cache[gun]=s
	return s

func has_data() -> bool:
	return not parts.is_empty()

## Vzdálenost bodu p (souřadnice dílu) k povrchu dílu; mimo mřížku odhad zvenku.
func part_distance(part: String, p: Vector3) -> float:
	var e: Array=parts.get(part,[])
	if e.is_empty(): return 1.0
	var d: PackedFloat32Array=e[0]
	var o: Vector3=e[1]
	var c: float=e[2]
	var n: Vector3i=e[3]
	var g:=(p-o)/c
	var gx:=clampf(g.x,0.0,n.x-1.001)
	var gy:=clampf(g.y,0.0,n.y-1.001)
	var gz:=clampf(g.z,0.0,n.z-1.001)
	var outside:=Vector3(g.x-gx,g.y-gy,g.z-gz).length()*c
	var ix:=int(gx)
	var iy:=int(gy)
	var iz:=int(gz)
	var fx:=gx-ix
	var fy:=gy-iy
	var fz:=gz-iz
	var sx:=1
	var sy:=n.x
	var sz:=n.x*n.y
	var i0:=iz*sz+iy*sy+ix
	var c00:=lerpf(d[i0],d[i0+sx],fx)
	var c10:=lerpf(d[i0+sy],d[i0+sy+sx],fx)
	var c01:=lerpf(d[i0+sz],d[i0+sz+sx],fx)
	var c11:=lerpf(d[i0+sz+sy],d[i0+sz+sy+sx],fx)
	return lerpf(lerpf(c00,c10,fy),lerpf(c01,c11,fy),fz)+outside

## Vzdálenost bodu (souřadnice zbraně) k celé zbrani; xf = transformace dílů (zbraň ← díl).
func distance(p: Vector3, xf: Dictionary) -> float:
	var best:=part_distance("body",p)
	for part in ["magazine","barrel"]:
		if not parts.has(part): continue
		var t: Transform3D=xf.get(part,Transform3D.IDENTITY)
		best=minf(best,part_distance(part,t.affine_inverse()*p))
	return best

func gradient(p: Vector3, xf: Dictionary) -> Vector3:
	var h:=0.003
	var gx:=distance(p+Vector3(h,0,0),xf)-distance(p-Vector3(h,0,0),xf)
	var gy:=distance(p+Vector3(0,h,0),xf)-distance(p-Vector3(0,h,0),xf)
	var gz:=distance(p+Vector3(0,0,h),xf)-distance(p-Vector3(0,0,h),xf)
	var g:=Vector3(gx,gy,gz)
	return g.normalized() if g.length_squared()>1e-12 else Vector3.UP
