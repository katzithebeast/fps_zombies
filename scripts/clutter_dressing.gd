extends Node3D
const BloodDressing := preload("res://scripts/blood_dressing.gd")
## Zanedbanost a nepořádek: vylomené kachle, praskliny, špína a plíseň u podlahy, zatečené mapy
## od stropu, kaluže, střepy kachlí, rozházené papíry, rezavé trubky pod stropem, smaltované cedule
## a převrácená lehátka. Místa se hledají paprsky z náhodných bodů v místnostech, takže sedí na
## skutečné zdi. Drobnosti (střepy, papíry) jsou v MultiMesh – jeden draw call pro stovky kusů.

const DIR := "res://textures/clutter/"
const WALL_DECALS := false
# Hustota na 100 m² podlahy (počty se přepočítají podle velikosti mapy).
const D_WALL_BROKEN := 2.2
const D_FLOOR_BROKEN := 1.0
const D_CRACKS := 3.0
const D_GRIME := 4.5
const D_STAINS := 2.2
const D_PUDDLES := 1.2
const D_PAPERS := 5.5
const D_PIPES := 0.45
var WALL_BROKEN := 0
var FLOOR_BROKEN := 0
var CRACKS := 0
var GRIME := 0
var STAINS := 0
var PUDDLES := 0
var PAPERS := 0
var PIPE_RUNS := 0
const SIGNS := [
	"ZÁKAZ SKÁKÁNÍ", "HLOUBKA 3,8 m", "POZOR – KLUZKÁ PODLAHA", "ŠATNY", "SPRCHY", "ZÁKAZ VSTUPU",
	"PLAVČÍK", "NEPLAVCI", "VSTUP JEN SE SVOLENÍM", "PŘED KOUPÁNÍM SE OSPRCHUJTE", "ÚNIKOVÝ VÝCHOD",
	"STROJOVNA", "HLOUBKA 1,2 m", "ZÁKAZ BĚHÁNÍ", "PRVNÍ POMOC", "VSTUP DO VODY ZAKÁZÁN",
]

var _tex := {}
var _space: PhysicsDirectSpaceState3D
var _rng := RandomNumberGenerator.new()
var _world_body: Object
var _water_y := 0.0
var _shards: Array[Transform3D] = []
var _shard_colors: Array[Color] = []

func _t(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load(DIR + name + ".png")
	return _tex[name]

func dress(rects: Array, world_body: Object, water_y: float, seed_value := 23) -> void:
	_rng.seed = seed_value
	_space = get_world_3d().direct_space_state
	_world_body = world_body
	_water_y = water_y
	var total := 0.0
	for r in rects:
		total += (r as Rect2).get_area()
	var k := total / 100.0
	WALL_BROKEN = int(D_WALL_BROKEN * k)
	FLOOR_BROKEN = int(D_FLOOR_BROKEN * k)
	CRACKS = int(D_CRACKS * k)
	GRIME = int(D_GRIME * k)
	STAINS = int(D_STAINS * k)
	PUDDLES = int(D_PUDDLES * k)
	PAPERS = int(D_PAPERS * k)
	PIPE_RUNS = maxi(1, int(D_PIPES * k))
	print("clutter: plocha %d m²" % int(total))
	# Nálepky na zdech (vylomené kachle, praskliny, plíseň, zatečení) jsou vypnuté – nahradí je nové.
	if WALL_DECALS: _walls(rects, total)
	_wall_pack(rects, total)
	_floors(rects, total)
	_pipes(rects, total)
	_signs(rects, total)
	_build_shards()
	_trash(rects, total)
	_loungers(rects, total)

# ------------------------------------------------------------------ pomocné

func _pick(rects: Array, total: float) -> Vector2:
	var roll := _rng.randf() * total
	for r in rects:
		var rect: Rect2 = r
		roll -= rect.get_area()
		if roll <= 0.0:
			return Vector2(_rng.randf_range(rect.position.x, rect.end.x), _rng.randf_range(rect.position.y, rect.end.y))
	return (rects[0] as Rect2).get_center()

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return _space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))

func _floor_at(p: Vector2) -> Dictionary:
	var hit := _ray(Vector3(p.x, 2.5, p.y), Vector3(p.x, -4.0, p.y))   # ze 7 m by paprsek trefil střechu
	if hit.is_empty() or (hit.normal as Vector3).y < 0.8:
		return {}
	return hit

func _wall_from(at: Vector2, height: float) -> Dictionary:
	# Najde zeď z náhodného bodu v místnosti: [bod na zdi, normála, výška podlahy].
	var floor_hit := _floor_at(at)
	if floor_hit.is_empty():
		return {}
	var fy: float = floor_hit.position.y
	var from := Vector3(at.x, fy + height, at.y)
	var dir := Vector3.FORWARD.rotated(Vector3.UP, _rng.randf() * TAU)
	var hit := _ray(from, from + dir * 6.0)
	if hit.is_empty() or hit.collider != _world_body or absf((hit.normal as Vector3).y) > 0.15:
		return {}
	return {"pos": hit.position, "normal": hit.normal, "floor": fy}

func _wall_top(at: Vector3, n: Vector3, floor_y: float) -> float:
	# Horní okraj zdi (strop nemusí mít kolizi): šplhá po zdi, dokud paprsek do ní naráží.
	var h := 0.5
	while h < 7.0:
		var p := Vector3(at.x, floor_y + h, at.z) + n * 0.3
		var hit := _ray(p, p - n * 0.6)
		if hit.is_empty() or absf((hit.normal as Vector3).dot(n)) < 0.9:
			return floor_y + h - 0.12
		h += 0.12
	return floor_y + 7.0

func _decal(tex: Texture2D, at: Vector3, normal: Vector3, size: Vector2, spin: float, modulate := Color.WHITE, orm: Texture2D = null) -> Decal:
	var d := Decal.new()
	d.texture_albedo = tex
	if orm:
		d.texture_orm = orm
	d.size = Vector3(size.x, 0.24, size.y)
	d.modulate = modulate
	d.cull_mask = 1
	d.layers = 1 << 19          # v odrazu vody se nekreslí
	d.distance_fade_enabled = true
	d.distance_fade_begin = 20.0
	d.distance_fade_length = 6.0
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.normal_fade = 0.6
	add_child(d)
	var basis: Basis = load("res://scripts/blood_dressing.gd").orient(normal, spin)
	d.global_transform = Transform3D(basis, at + normal * 0.03)
	return d

func _scatter_shards(center: Vector3, normal: Vector3, radius: float, count: int) -> void:
	# Střepy kachlí na podlaze pod vylomeným místem.
	for i in count:
		var off := Vector2(_rng.randf_range(-radius, radius), _rng.randf_range(-radius, radius))
		var p := center + Vector3(off.x, 0, off.y) + Vector3(normal.x, 0, normal.z) * _rng.randf_range(0.05, radius)
		var hit := _floor_at(Vector2(p.x, p.z))
		if hit.is_empty() or absf((hit.position as Vector3).y - center.y) > 0.25:
			continue
		var s := _rng.randf_range(0.35, 1.0)
		var b := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(-0.25, 0.25))
		b = b.scaled(Vector3(s * _rng.randf_range(0.6, 1.4), 1.0, s))
		_shards.append(Transform3D(b, (hit.position as Vector3) + Vector3.UP * 0.006))
		var tone := _rng.randf_range(0.82, 1.0)
		_shard_colors.append(Color(tone, tone * 0.98, tone * 0.94))

# ------------------------------------------------------------------ nálepky z Wall Damage Pack v2
# Každý motiv má kotvu: "top" visí od horního okraje zdi (zatečení, stékající plíseň),
# "bottom" roste od podlahy (plíseň, vlhkost, výkvěty), "mid" je ve výšce rukou (krev, škrábance,
# praskliny, vypadané kachle). Váha = jak často se motiv objeví, velikost v metrech (šířka).
const PACK_DIR := "res://textures/walldecals/"
const PACK_DENSITY := 11.0         # kusů na 100 m² podlahy (dřív 18, ale většina končila na střeše)
const PACK_MIN := 9
const PACK := [
	# [soubor, kotva, váha, min. šířka, max. šířka]
	["blood_vomit_01_blood_impact", "mid", 3.0, 0.6, 1.2], ["blood_vomit_02_dried_blood_wipe", "mid", 2.5, 0.7, 1.4],
	["blood_vomit_03_dragged_bloody_handprint", "mid", 2.0, 0.35, 0.55], ["blood_vomit_04_blood_drips", "mid", 2.5, 0.5, 1.0],
	["blood_vomit_05_vomit_splash", "mid", 0.6, 0.6, 1.0], ["blood_vomit_06_dried_vomit", "bottom", 0.6, 0.5, 0.9],
	["blood_vomit_07_bilious_splash", "mid", 0.8, 0.6, 1.1], ["blood_vomit_08_mixed_fluid_smear", "mid", 1.2, 0.7, 1.3],
	["cracks_tiles_01_vertical_structural_crack", "mid", 1.5, 0.8, 1.6], ["cracks_tiles_02_zigzag_fracture", "mid", 1.5, 0.8, 1.5],
	["cracks_tiles_03_stress_crack_network", "mid", 1.0, 0.8, 1.4], ["cracks_tiles_04_intersecting_cracks", "mid", 1.2, 0.7, 1.3],
	["cracks_tiles_05_missing_single_tile", "mid", 1.5, 0.45, 0.7], ["cracks_tiles_06_missing_green_tiles", "mid", 0.5, 0.6, 0.9],
	["cracks_tiles_07_broken_white_tiles", "mid", 1.5, 0.55, 0.9], ["cracks_tiles_08_missing_tile_strip", "mid", 1.2, 0.5, 0.8],
	["cracks_peeling_01_vertical_crack", "mid", 1.0, 0.7, 1.4], ["cracks_peeling_02_hairline_cracks", "mid", 0.8, 0.8, 1.4],
	["cracks_peeling_03_diagonal_crack", "mid", 1.0, 0.7, 1.4], ["cracks_peeling_04_flaked_paint", "mid", 0.5, 0.6, 1.0],
	["cracks_peeling_05_peeling_strip", "top", 0.4, 0.4, 0.7], ["cracks_peeling_06_chipped_plaster", "mid", 0.5, 0.5, 0.9],
	["cracks_peeling_07_impact_cracks", "mid", 1.0, 0.5, 0.9], ["cracks_peeling_08_crazed_paint", "mid", 0.5, 0.8, 1.3],
	["mold_01_sparse_black_mildew", "bottom", 1.2, 0.8, 1.6], ["mold_02_olive_mold", "bottom", 1.0, 0.7, 1.3],
	["mold_03_vertical_fungal_growth", "top", 1.0, 0.6, 1.2], ["mold_04_orange_bacterial_film", "bottom", 0.6, 0.7, 1.2],
	["mold_05_filament_mold", "mid", 0.6, 0.7, 1.3], ["mold_06_dense_black_mold", "bottom", 1.2, 0.8, 1.5],
	["mold_07_mixed_fungal_colony", "bottom", 0.8, 0.7, 1.3], ["mold_08_scattered_mold_spots", "mid", 0.8, 0.6, 1.1],
	["mold_damp_01_black_mildew", "bottom", 1.2, 0.8, 1.5], ["mold_damp_02_green_mold", "bottom", 0.8, 0.8, 1.4],
	["mold_damp_03_gray_mold", "bottom", 0.8, 0.8, 1.4], ["mold_damp_04_water_ingress", "top", 1.5, 0.8, 1.6],
	["mold_damp_05_damp_stain", "mid", 0.8, 0.9, 1.6], ["mold_damp_06_dirty_leaks", "top", 1.5, 0.7, 1.4],
	["mold_damp_07_heavy_mold_drips", "top", 1.0, 0.8, 1.5], ["mold_damp_08_salt_efflorescence", "bottom", 0.6, 0.8, 1.4],
	["scratches_01_diagonal_scratches", "mid", 1.5, 0.4, 0.8], ["scratches_02_horizontal_scrape", "mid", 1.0, 0.6, 1.2],
	["scratches_03_deep_gouges", "mid", 1.8, 0.45, 0.8], ["scratches_04_fine_scratches", "mid", 0.6, 0.6, 1.0],
	["scratches_05_abrasion", "mid", 0.6, 0.7, 1.2], ["scratches_06_vertical_scratches", "mid", 1.0, 0.4, 0.8],
	["scratches_07_branching_scratch", "mid", 0.8, 0.5, 0.9], ["scratches_08_worn_paint", "mid", 0.5, 0.6, 1.0],
	["strange_growth_01_tar_ooze", "top", 0.6, 0.7, 1.3], ["strange_growth_02_olive_slime", "top", 0.6, 0.7, 1.3],
	["strange_growth_03_purple_mycelium", "mid", 0.4, 0.7, 1.3], ["strange_growth_04_crusty_growth", "bottom", 0.5, 0.6, 1.1],
	["strange_growth_05_amber_seepage", "top", 0.8, 0.7, 1.3], ["strange_growth_06_black_mycelium", "mid", 0.6, 0.8, 1.4],
	["strange_growth_07_fungal_slime_nodules", "bottom", 0.5, 0.7, 1.2], ["strange_growth_08_decay_bloom", "mid", 0.5, 0.7, 1.3],
]

func _pack_pick() -> Array:
	var sum := 0.0
	for e in PACK:
		sum += float(e[2])
	var roll := _rng.randf() * sum
	for e in PACK:
		roll -= float(e[2])
		if roll <= 0.0:
			return e
	return PACK[0]

func _fits(center: Vector3, n: Vector3, w: float, h: float) -> bool:
	# Celý motiv musí ležet na jedné rovné zdi (ne přes dveře, roh ani okraj zdi).
	var tangent := n.cross(Vector3.UP).normalized()
	for sx in [-0.45, 0.0, 0.45]:
		for sy in [-0.45, 0.0, 0.45]:
			var target: Vector3 = center + tangent * float(sx) * w + Vector3.UP * float(sy) * h
			var hit := _ray(target + n * 0.3, target - n * 0.2)
			if hit.is_empty() or hit.collider != _world_body:
				return false
			if (hit.normal as Vector3).dot(n) < 0.95 or absf((hit.position - center).dot(n)) > 0.05:
				return false
	return true

func _wall_pack(rects: Array, _total: float) -> void:
	# Po místnostech: každá dostane podle plochy, ale aspoň PACK_MIN kusů.
	var count := 0
	for i in rects.size():
		var r: Rect2 = rects[i]
		var area: float = r.get_area()
		# Stejné rozdělení místností jako u krve: masakr / špína / klid.
		var mult: float = minf(1.5, float(BloodDressing.room_tier(i)[1]))
		count += _wall_pack_room([r], area, maxi(int(PACK_MIN * mult), int(PACK_DENSITY * area / 100.0 * mult)))
	print("wall pack: %d nálepek" % count)

func _wall_pack_room(rects: Array, total: float, want: int) -> int:
	var placed := 0
	var tries := 0
	while placed < want and tries < want * 15:
		tries += 1
		var e: Array = _pack_pick()
		var tex: Texture2D = load(PACK_DIR + String(e[0]) + ".png")
		var w := _rng.randf_range(float(e[3]), float(e[4]))
		var h := w * float(tex.get_height()) / float(tex.get_width())
		var at := _pick(rects, total)
		var wall := _wall_from(at, 1.2)
		if wall.is_empty():
			continue
		var n: Vector3 = wall.normal
		var fy: float = wall.floor
		var cy: float
		match String(e[1]):
			"top":
				var top := _wall_top(wall.pos, n, fy)
				if top - fy < 2.0:
					continue
				cy = top - h * 0.5 + 0.02
			"bottom":
				cy = fy + h * 0.5 - 0.02
			_:
				cy = fy + _rng.randf_range(0.7, 1.8)
		var center := Vector3(wall.pos.x, cy, wall.pos.z)
		if not _fits(center, n, w, h * 0.9):
			continue
		# Krev a tekutiny trochu natočit, ostatní (praskliny, plíseň, zatečení) svisle.
		var spin := _rng.randf_range(-0.35, 0.35) if String(e[0]).begins_with("blood") or String(e[0]).begins_with("scratches") else 0.0
		var tint := Color(0.82, 0.78, 0.78) if String(e[0]).begins_with("blood") else Color(1, 1, 1)
		# Matná ORM: nálepka přebije lesk glazury, jinak by přes ni prosvítal odlesk a vypadala vybledle.
		_decal(tex, center, n, Vector2(w, h), spin, tint, load(PACK_DIR + "rough_orm.png"))
		placed += 1
	return placed

# ------------------------------------------------------------------ zdi

func _walls(rects: Array, total: float) -> void:
	var placed := {"broken": 0, "crack": 0, "grime": 0, "stain": 0}
	var tries := 0
	while tries < 6000 and (placed.broken < WALL_BROKEN or placed.crack < CRACKS / 2 or placed.grime < GRIME or placed.stain < STAINS):
		tries += 1
		var at := _pick(rects, total)
		var kind: String = ["broken", "crack", "grime", "grime", "stain"][_rng.randi() % 5]
		match kind:
			"broken":
				if placed.broken >= WALL_BROKEN: continue
				var w := _wall_from(at, _rng.randf_range(0.3, 2.3))
				if w.is_empty(): continue

				# Díra po kachlích sedí přesně na mřížku obkladu (dlaždice 0,2 m, textura = 8×8 dlaždic).
				var wp: Vector3 = w.pos
				var wn: Vector3 = w.normal
				var snapped_pos := Vector3(snappedf(wp.x, 0.2) if absf(wn.x) < 0.5 else wp.x, snappedf(wp.y, 0.2), snappedf(wp.z, 0.2) if absf(wn.z) < 0.5 else wp.z)
				var bv := _rng.randi() % 3
				_decal(_t("broken_%d" % bv), snapped_pos, wn, Vector2(1.6, 1.6), 0.0, Color.WHITE, _t("broken_orm_%d" % bv))
				var foot := Vector3(w.pos.x, w.floor, w.pos.z) + (w.normal as Vector3) * 0.25
				if w.floor > _water_y - 0.05 or _rng.randf() < 0.3:
					_scatter_shards(foot, w.normal, 0.45, _rng.randi_range(4, 9))
				placed.broken += 1
			"crack":
				if placed.crack >= CRACKS / 2: continue
				var w2 := _wall_from(at, _rng.randf_range(0.2, 2.6))
				if w2.is_empty(): continue
				var s2 := _rng.randf_range(0.5, 1.4)
				_decal(_t("crack_%d" % (_rng.randi() % 3)), w2.pos, w2.normal, Vector2(s2, s2), _rng.randf() * TAU, Color(1, 1, 1, 0.9))
				placed.crack += 1
			"grime":
				if placed.grime >= GRIME: continue
				# Špína a plíseň v pásu u podlahy.
				var w3 := _wall_from(at, 0.35)
				if w3.is_empty(): continue
				var p3 := Vector3(w3.pos.x, w3.floor + 0.28, w3.pos.z)
				var length := _rng.randf_range(1.0, 2.6)
				_decal(_t("grime_%d" % (_rng.randi() % 2)), p3, w3.normal, Vector2(length, 0.6), 0.0, Color(1, 1, 1, _rng.randf_range(0.55, 0.95)))
				placed.grime += 1
			"stain":
				if placed.stain >= STAINS: continue
				# Zatečené mapy: od stropu dolů, rezavě hnědé.
				var w4 := _wall_from(at, 1.6)
				if w4.is_empty(): continue
				var top: float = _wall_top(w4.pos, w4.normal, w4.floor)
				var h := _rng.randf_range(0.8, minf(2.0, top - w4.floor - 0.2))
				if h < 0.5: continue
				var p4 := Vector3(w4.pos.x, top - h * 0.5 - 0.02, w4.pos.z)
				_decal(_t("stain_%d" % (_rng.randi() % 2)), p4, w4.normal, Vector2(_rng.randf_range(0.5, 1.2), h), 0.0, Color(1, 1, 1, _rng.randf_range(0.6, 1.0)))
				placed.stain += 1

# ------------------------------------------------------------------ podlahy

func _floors(rects: Array, total: float) -> void:
	var papers: Array[Transform3D] = []
	var paper_tex: Array[int] = []
	var broken := 0
	var cracks := 0
	var puddles := 0
	var tries := 0
	while tries < 5000 and (broken < FLOOR_BROKEN or cracks < CRACKS / 2 or puddles < PUDDLES or papers.size() < PAPERS):
		tries += 1
		var at := _pick(rects, total)
		var hit := _floor_at(at)
		if hit.is_empty() or hit.collider != _world_body:
			continue
		var p: Vector3 = hit.position
		var dry := p.y > _water_y - 0.02
		var roll := _rng.randf()
		if roll < 0.2 and broken < FLOOR_BROKEN:
			var s := 1.6
			var fv := _rng.randi() % 3
			_decal(_t("broken_%d" % fv), Vector3(snappedf(p.x, 0.2), p.y, snappedf(p.z, 0.2)), Vector3.UP, Vector2(s, s), _rng.randi_range(0, 3) * PI * 0.5, Color.WHITE, _t("broken_orm_%d" % fv))
			if dry:
				_scatter_shards(p, Vector3.ZERO, s * 0.7, _rng.randi_range(3, 7))
			broken += 1
		elif roll < 0.4 and cracks < CRACKS / 2:
			var s2 := _rng.randf_range(0.6, 1.6)
			_decal(_t("crack_%d" % (_rng.randi() % 3)), p, Vector3.UP, Vector2(s2, s2), _rng.randf() * TAU, Color(1, 1, 1, 0.85))
			cracks += 1
		elif roll < 0.55 and puddles < PUDDLES and dry:
			var v := _rng.randi() % 2
			var s3 := _rng.randf_range(0.8, 2.2)
			_decal(_t("puddle_%d" % v), p, Vector3.UP, Vector2(s3, s3 * _rng.randf_range(0.6, 1.0)), _rng.randf() * TAU, Color(1, 1, 1, 0.85), _t("puddle_orm_%d" % v))
			puddles += 1
		elif dry and papers.size() < PAPERS:
			# Papíry v hloučcích (rozházené letáky, rozpis směn...).
			for k in _rng.randi_range(1, 4):
				var q := p + Vector3(_rng.randf_range(-0.6, 0.6), 0, _rng.randf_range(-0.6, 0.6))
				var h2 := _floor_at(Vector2(q.x, q.z))
				if h2.is_empty() or absf((h2.position as Vector3).y - p.y) > 0.05:
					continue
				var b := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(-0.06, 0.06))
				papers.append(Transform3D(b, (h2.position as Vector3) + Vector3.UP * (0.004 + 0.002 * k)))
				paper_tex.append(_rng.randi() % 3)
	# Tři MultiMeshe papírů (podle textury).
	for v in 3:
		var list: Array[Transform3D] = []
		for i in papers.size():
			if paper_tex[i] == v:
				list.append(papers[i])
		if list.is_empty():
			continue
		var quad := QuadMesh.new()
		quad.size = Vector2(0.21, 0.297)
		quad.orientation = PlaneMesh.FACE_Y
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _t("paper_%d" % v)
		mat.roughness = 0.95
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		quad.material = mat
		_multimesh(quad, list, [], false)

# ------------------------------------------------------------------ odpadky: plechovky, lahve, ručníky
func _trash(rects: Array, total: float) -> void:
	var cans: Array[Transform3D] = []
	var can_colors: Array[Color] = []
	var bottles: Array[Transform3D] = []
	var towels: Array[Transform3D] = []
	var towel_colors: Array[Color] = []
	var want := int(total / 100.0 * 7.0)
	var palette := [Color(0.75, 0.12, 0.1), Color(0.1, 0.35, 0.7), Color(0.85, 0.75, 0.2), Color(0.2, 0.55, 0.25), Color(0.85, 0.85, 0.85)]
	var towel_palette := [Color(0.62, 0.7, 0.78), Color(0.85, 0.66, 0.55), Color(0.68, 0.74, 0.58), Color(0.9, 0.88, 0.8), Color(0.75, 0.42, 0.38)]
	var tries := 0
	while cans.size() + bottles.size() + towels.size() < want and tries < want * 6:
		tries += 1
		var hit := _floor_at(_pick(rects, total))
		if hit.is_empty() or (hit.position as Vector3).y < _water_y - 0.02:
			continue
		var p: Vector3 = hit.position
		var roll := _rng.randf()
		var yaw := Basis(Vector3.UP, _rng.randf() * TAU)
		if roll < 0.5:
			# Plechovka: většinou leží na boku, někdy stojí.
			var lying := _rng.randf() < 0.8
			var b := yaw * (Basis(Vector3.FORWARD, PI * 0.5) if lying else Basis())
			cans.append(Transform3D(b, p + Vector3.UP * (0.033 if lying else 0.06)))
			can_colors.append((palette[_rng.randi() % palette.size()] as Color).darkened(_rng.randf_range(0.1, 0.5)))
		elif roll < 0.8:
			var b2 := yaw * Basis(Vector3.FORWARD, PI * 0.5)
			bottles.append(Transform3D(b2, p + Vector3.UP * 0.035))
		else:
			towels.append(Transform3D(yaw, p + Vector3.UP * 0.006))
			towel_colors.append((towel_palette[_rng.randi() % towel_palette.size()] as Color).darkened(_rng.randf_range(0.2, 0.5)))
	var can_mesh := CylinderMesh.new()
	can_mesh.top_radius = 0.033
	can_mesh.bottom_radius = 0.033
	can_mesh.height = 0.12
	can_mesh.radial_segments = 10
	var can_mat := StandardMaterial3D.new()
	can_mat.vertex_color_use_as_albedo = true
	can_mat.metallic = 0.7
	can_mat.roughness = 0.45
	can_mesh.material = can_mat
	if not cans.is_empty(): _multimesh(can_mesh, cans, can_colors, false)
	var bottle_mesh := CylinderMesh.new()
	bottle_mesh.top_radius = 0.014
	bottle_mesh.bottom_radius = 0.035
	bottle_mesh.height = 0.26
	bottle_mesh.radial_segments = 10
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.12, 0.3, 0.14, 0.75)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.08
	glass.metallic_specular = 0.9
	bottle_mesh.material = glass
	if not bottles.is_empty(): _multimesh(bottle_mesh, bottles, [], false)
	# Ručník: zmačkaná síť (záhyby nahoru/dolů) s texturou froté, pruhy a skvrnami,
	# nepravidelný okraj přes alpha scissor. Barvu dává instance.
	var towel_mesh := _crumpled_cloth(Vector2(0.75, 0.42))
	var cloth := StandardMaterial3D.new()
	cloth.vertex_color_use_as_albedo = true
	cloth.albedo_texture = _t("towel")
	cloth.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	cloth.alpha_scissor_threshold = 0.5
	cloth.roughness = 1.0
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	towel_mesh.surface_set_material(0, cloth)
	if not towels.is_empty(): _multimesh(towel_mesh, towels, towel_colors, false)
	print("odpadky: %d plechovek, %d lahví, %d ručníků" % [cans.size(), bottles.size(), towels.size()])

func _crumpled_cloth(size: Vector2) -> ArrayMesh:
	var plane := PlaneMesh.new()
	plane.size = size
	plane.subdivide_width = 10
	plane.subdivide_depth = 6
	var arrays := plane.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var ph := rng.randf() * TAU
	for i in verts.size():
		var v := verts[i]
		var u := v.x / size.x
		var w := v.z / size.y
		# Pár měkkých záhybů napříč a jeden přehyb na kraji.
		var h := 0.018 * sin(u * 9.0 + ph) * cos(w * 4.0) + 0.012 * sin(w * 11.0 + u * 3.0)
		h += 0.03 * maxf(0.0, u - 0.3) * (1.0 - absf(w) * 1.5)
		verts[i] = Vector3(v.x, maxf(0.0, h + 0.012), v.z)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.generate_normals()
	return st.commit()

# ------------------------------------------------------------------ střepy (jeden MultiMesh)

func _build_shards() -> void:
	if _shards.is_empty():
		return
	var box := BoxMesh.new()
	box.size = Vector3(0.09, 0.012, 0.07)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.92, 0.88)
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.25
	box.material = mat
	_multimesh(box, _shards, _shard_colors, false)

func _multimesh(mesh: Mesh, xforms: Array[Transform3D], colors: Array[Color], shadows: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.layers = 1 << 17           # drobnosti: nekreslí se do odrazu vody
	mmi.visibility_range_end = 40.0
	add_child(mmi)

# ------------------------------------------------------------------ rezavé trubky pod stropem

func _pipes(rects: Array, total: float) -> void:
	var rust := StandardMaterial3D.new()
	rust.albedo_texture = _t("rust")
	rust.uv1_triplanar = true
	rust.uv1_scale = Vector3(1.5, 1.5, 1.5)
	rust.roughness = 0.75
	rust.metallic = 0.35
	var made := 0
	var tries := 0
	while made < PIPE_RUNS and tries < 600:
		tries += 1
		var at := _pick(rects, total)
		var w := _wall_from(at, 1.8)
		if w.is_empty():
			continue
		var n: Vector3 = w.normal
		var top: float = _wall_top(w.pos, n, w.floor)
		if top - w.floor < 2.6 or top - w.floor > 6.5:
			continue
		var y := top - _rng.randf_range(0.25, 0.4)
		var tangent := n.cross(Vector3.UP).normalized()
		var base := Vector3(w.pos.x, y, w.pos.z) + n * 0.14
		# Délka: dokud podél zdi pokračuje souvislá zeď a nic nepřekáží.
		var ends := []
		for sgn in [-1.0, 1.0]:
			var s: float = sgn
			var reach := 0.0
			while reach < 6.0:
				var probe := base + tangent * s * (reach + 0.25)
				var wall := _ray(probe, probe - n * 0.4)
				var block := _ray(base + tangent * s * reach, probe)
				if wall.is_empty() or not block.is_empty():
					break
				reach += 0.25
			ends.append(reach)
		var length: float = float(ends[0]) + float(ends[1])
		if length < 2.0:
			continue
		var center: Vector3 = base + tangent * (float(ends[1]) - float(ends[0])) * 0.5
		var count := _rng.randi_range(1, 2)
		for k in count:
			var r := _rng.randf_range(0.045, 0.085)
			var pipe := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = r
			cyl.bottom_radius = r
			cyl.height = length
			cyl.radial_segments = 10
			pipe.mesh = cyl
			pipe.material_override = rust
			add_child(pipe)
			var along := Basis.looking_at(tangent, Vector3.UP)
			pipe.global_transform = Transform3D(along * Basis(Vector3.RIGHT, PI * 0.5), center - Vector3.UP * k * 0.2 + n * k * 0.02)
			pipe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			pipe.visibility_range_end = 40.0
		# Objímky po metru.
		var clamp_mesh := BoxMesh.new()
		clamp_mesh.size = Vector3(0.05, 0.05 + 0.2 * (count - 1) + 0.12, 0.16)
		var steps := int(length)
		for i in steps:
			var c := MeshInstance3D.new()
			c.mesh = clamp_mesh
			c.material_override = rust
			add_child(c)
			var pos: Vector3 = center + tangent * (float(i) - (steps - 1) * 0.5) - Vector3.UP * 0.1 * (count - 1) - n * 0.06
			c.global_transform = Transform3D(Basis.looking_at(-n, Vector3.UP), pos)
			c.visibility_range_end = 30.0
		made += 1

# ------------------------------------------------------------------ smaltované cedule

func _signs(rects: Array, total: float) -> void:
	var plate_mat := StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.86, 0.85, 0.8)
	plate_mat.roughness = 0.35
	var used := 0
	var tries := 0
	var spots: Array[Vector3] = []
	var order := SIGNS.duplicate()
	order.shuffle()
	while used < order.size() and tries < 800:
		tries += 1
		var at := _pick(rects, total)
		var w := _wall_from(at, _rng.randf_range(1.8, 2.2))
		if w.is_empty():
			continue
		var n: Vector3 = w.normal
		# Celá cedule musí sedět na zdi.
		var tangent := n.cross(Vector3.UP).normalized()
		var ok := true
		for sv in [-0.45, 0.45]:
			var s: float = sv
			if _ray(w.pos + n * 0.2 + tangent * s, w.pos - n * 0.2 + tangent * s).is_empty():
				ok = false
		if not ok:
			continue
		var near := false
		for q in spots:
			if q.distance_to(w.pos) < 6.0:
				near = true
		if near:
			continue
		spots.append(w.pos)
		var text: String = order[used]
		var plate := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(maxf(0.7, text.length() * 0.075 + 0.16), 0.26, 0.012)
		plate.mesh = bm
		plate.material_override = plate_mat
		add_child(plate)
		var basis := Basis.looking_at(-n, Vector3.UP)
		# Některé cedule visí nakřivo.
		basis = basis * Basis(Vector3.FORWARD, _rng.randf_range(-0.12, 0.12) if _rng.randf() < 0.4 else 0.0)
		plate.global_transform = Transform3D(basis, w.pos + n * 0.008)
		var label := Label3D.new()
		label.text = text
		label.font_size = 64
		label.pixel_size = 0.0018
		label.modulate = Color(0.08, 0.18, 0.42, 0.92)
		label.outline_size = 0
		label.shaded = true
		label.double_sided = false
		plate.add_child(label)
		label.position = Vector3(0, 0, 0.0075)
		# Rez a špína přes ceduli.
		var dirt := Decal.new()
		dirt.texture_albedo = _t("stain_%d" % (_rng.randi() % 2))
		dirt.size = Vector3(bm.size.x, 0.1, 0.26)
		dirt.modulate = Color(1, 1, 1, 0.3)
		dirt.cull_mask = 1
		plate.add_child(dirt)
		dirt.rotation = Vector3(PI * 0.5, 0, 0)
		used += 1

# ------------------------------------------------------------------ převrácená lehátka

func _loungers(rects: Array, total: float) -> void:
	# Lehátka jen tam, kde dávají smysl: na suchém okraji u hlubokého bazénu, v řadách
	# čelem k vodě. Občas jedno převrácené na bok, ať je vidět, že se tu něco stalo.
	var Props: GDScript = load("res://scripts/props.gd")
	var spots: Array[Vector3] = []
	var tries := 0
	var rows := 0
	while rows < maxi(2, int(total / 100.0 * 0.12)) and tries < 600:
		tries += 1
		var hit := _floor_at(_pick(rects, total))
		if hit.is_empty() or (hit.position as Vector3).y < _water_y - 0.02:
			continue
		var p: Vector3 = hit.position
		var to_pool := _pool_dir(p)
		if to_pool == Vector3.ZERO:
			continue
		var along := to_pool.cross(Vector3.UP).normalized()
		var count := _rng.randi_range(2, 4)
		var placed := 0
		for k in count:
			var q: Vector3 = p + along * (float(k) - float(count - 1) * 0.5) * 0.85
			var ground := _floor_at(Vector2(q.x, q.z))
			if ground.is_empty() or absf((ground.position as Vector3).y - p.y) > 0.05 or _pool_dir(q) == Vector3.ZERO:
				continue
			var clash := false
			for s in spots:
				if s.distance_to(q) < 0.75: clash = true
			if clash or not _ray(q + Vector3.UP * 0.4, q + Vector3.UP * 0.4 - to_pool * 1.1).is_empty():
				continue
			spots.append(q)
			_place_lounger(Props, q, to_pool, _rng.randf() < 0.15)
			placed += 1
		if placed > 0: rows += 1

func _pool_dir(p: Vector3) -> Vector3:
	# Směr k okraji bazénu do 2,5 m, jinak nula.
	# Místo samo musí být rovné a suché – žádné rampy, schody ani tribuny.
	for k in 4:
		var side := Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 4.0) * 0.6
		var g := _ray(p + side + Vector3.UP * 0.5, p + side + Vector3.DOWN * 0.5)
		if g.is_empty() or absf((g.position as Vector3).y - p.y) > 0.04:
			return Vector3.ZERO
	if p.y < _water_y + 0.05 or p.y > 1.6:
		return Vector3.ZERO
	# Nad hlavou volno (jinak je to vršek nějakého předmětu, ne podlaha).
	if not _ray(p + Vector3.UP * 0.1, p + Vector3.UP * 2.1).is_empty():
		return Vector3.ZERO
	for k in 4:      # hrany bazénů jsou rovnoběžné s osami: řady lehátek pak stojí rovně podél hrany
		var d := Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 4.0)
		for dist in [1.2, 1.8, 2.5]:
			var q: Vector3 = p + d * float(dist)
			var down := _ray(Vector3(q.x, p.y + 0.5, q.z), Vector3(q.x, p.y - 4.0, q.z))
			# Bazén plný (pod hladinou) i vypuštěný (hrana s propadem aspoň 0,9 m).
			if not down.is_empty() and ((down.position as Vector3).y < _water_y - 0.3 or (down.position as Vector3).y < p.y - 0.9):
				return d
	return Vector3.ZERO

func _place_lounger(Props: GDScript, q: Vector3, to_pool: Vector3, knocked: bool) -> void:
	var model: Node3D = Props.lounger()
	add_child(model)
	# Sedící kouká po +Z modelu (opěradlo je na -Z): natočit čelem k vodě.
	var yaw := atan2(to_pool.x, to_pool.z) + _rng.randf_range(-0.15, 0.15)
	var basis := Basis(Vector3.UP, yaw)
	if knocked: basis = basis * Basis(Vector3.FORWARD, PI * 0.5)
	model.global_transform = Transform3D(basis, q)
	var b: AABB = Props._bounds(model)
	var gb: AABB = model.global_transform * b
	model.global_position += Vector3.UP * (q.y - gb.position.y)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	gb = model.global_transform * b
	shape.size = gb.size * 0.85
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	body.global_position = gb.get_center()
	for m in model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).visibility_range_end = 45.0
