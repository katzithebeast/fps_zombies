class_name WaterSim
extends Node
signal impulse_added(point: Vector2, radius: float, strength: float)
## GPU simulace vodní hladiny (vlnová rovnice v compute shaderu).
## Výška hladiny je v textuře R32F, kterou čte shader vody i dlaždic (kaustiky).
## Vlny se odrážejí od stěn a sloupů podle masky.

const RES := 1024            # rozlišení simulace (texely na stranu)
const SUBSTEPS := 1          # kroků simulace na fyzikální tik
const MAX_POINTS := 6        # 112 B push constants: funguje i na GPU s limitem 128 B

var origin := Vector2(-32.0, -28.0)   # světové XZ levého horního rohu
var size := 48.0                      # délka strany v metrech
var wave_c2 := 0.24                   # (rychlost vln)^2 v texelech na krok, musí být < 0.5
var damping := 0.9965
var texture := Texture2DRD.new()

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _tex: Array[RID] = []
var _sets: Array = []
var _mask_tex: RID
var _mask_set: RID
var _idx := 0
var _points: Array[Vector4] = []
var _mask_bytes: PackedByteArray
var _ready_rd := false

const COMPUTE_SRC := """#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D cur_img;
layout(r32f, set = 1, binding = 0) uniform restrict readonly image2D prev_img;
layout(r32f, set = 2, binding = 0) uniform restrict writeonly image2D out_img;
layout(r8, set = 3, binding = 0) uniform restrict readonly image2D mask_img;
layout(push_constant, std430) uniform Params {
	vec4 pts[6];
	float c2;
	float damp;
	float count;
	float pad;
} p;

void main() {
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
	ivec2 sz = imageSize(cur_img);
	if (uv.x >= sz.x || uv.y >= sz.y) return;
	if (imageLoad(mask_img, uv).r < 0.5) { imageStore(out_img, uv, vec4(0.0)); return; }
	float h = imageLoad(cur_img, uv).r;
	float sum = 0.0;
	const ivec2 d[4] = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
	for (int i = 0; i < 4; i++) {
		ivec2 q = clamp(uv + d[i], ivec2(0), sz - 1);
		// pevna prekazka = odraz vlny (Neumannova podminka)
		sum += imageLoad(mask_img, q).r < 0.5 ? h : imageLoad(cur_img, q).r;
	}
	float pv = imageLoad(prev_img, uv).r;
	float nh = h + (h - pv) * p.damp + p.c2 * (sum - 4.0 * h);
	int n = int(p.count);
	for (int i = 0; i < n; i++) {
		vec2 dd = vec2(uv) - p.pts[i].xy;
		float r = p.pts[i].z;
		nh += p.pts[i].w * exp(-dot(dd, dd) / (r * r));
	}
	nh = clamp(nh * 0.9997, -4.0, 4.0);
	imageStore(out_img, uv, vec4(nh, 0.0, 0.0, 1.0));
}
"""

func setup(mask: Image) -> void:
	_mask_bytes = mask.get_data()
	RenderingServer.call_on_render_thread(_init_rd)

## Přidá do hladiny impuls. strength < 0 hladinu zatlačí, > 0 zvedne.
func add_impulse(world_xz: Vector2, radius_m: float, strength: float) -> void:
	_queue_impulse(world_xz, radius_m, strength)
	impulse_added.emit(world_xz, radius_m, strength)

func apply_network_impulse(world_xz: Vector2, radius_m: float, strength: float) -> void:
	# Cizí impulz se znovu neposílá do sítě.
	_queue_impulse(world_xz, radius_m, strength)

func _queue_impulse(world_xz: Vector2, radius_m: float, strength: float) -> void:
	var p := (world_xz - origin) / size * float(RES)
	if p.x < 0.0 or p.y < 0.0 or p.x >= RES or p.y >= RES:
		return
	_points.append(Vector4(p.x, p.y, maxf(radius_m / size * float(RES), 1.0), strength))

var _quiet := 0.0

func _physics_process(dt: float) -> void:
	var _perf_t0:=Time.get_ticks_usec()
	_physics_process_timed(dt)
	PerfMon.add("Voda simulace",Time.get_ticks_usec()-_perf_t0)

func _physics_process_timed(dt: float) -> void:
	if not _ready_rd:
		return
	# Klidná hladina: když dlouho nic nevlnilo, výpočet na GPU se vynechá (vlny už doznily).
	if _points.is_empty():
		_quiet += dt
		if _quiet > 10.0:
			return
	else:
		_quiet = 0.0
	for s in SUBSTEPS:
		var pts: Array[Vector4] = []
		while pts.size() < MAX_POINTS and not _points.is_empty():
			pts.append(_points.pop_front())
		var nxt := (_idx + 1) % 3
		var prv := (_idx + 2) % 3
		var pc := _pack(pts)
		RenderingServer.call_on_render_thread(_step.bind(_idx, prv, nxt, pc))
		_idx = nxt
	texture.texture_rd_rid = _tex[_idx]
	if _points.size() > 48:
		_points.clear()

func _pack(pts: Array[Vector4]) -> PackedByteArray:
	var f := PackedFloat32Array()
	f.resize(MAX_POINTS * 4 + 4)
	for i in pts.size():
		f[i * 4] = pts[i].x
		f[i * 4 + 1] = pts[i].y
		f[i * 4 + 2] = pts[i].z
		f[i * 4 + 3] = pts[i].w
	f[MAX_POINTS * 4] = wave_c2
	f[MAX_POINTS * 4 + 1] = damping
	f[MAX_POINTS * 4 + 2] = float(pts.size())
	return f.to_byte_array()

func _init_rd() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		push_error("WaterSim: RenderingDevice není k dispozici (je potřeba Forward+ renderer).")
		return
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = COMPUTE_SRC
	var spirv := _rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		push_error("WaterSim compute shader: " + spirv.compile_error_compute)
		return
	_shader = _rd.shader_create_from_spirv(spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)

	var tf := RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = RES
	tf.height = RES
	tf.depth = 1
	tf.array_layers = 1
	tf.mipmaps = 1
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var zero := PackedByteArray()
	zero.resize(RES * RES * 4)
	for i in 3:
		_tex.append(_rd.texture_create(tf, RDTextureView.new(), [zero]))

	var mf := RDTextureFormat.new()
	mf.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	mf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	mf.width = RES
	mf.height = RES
	mf.depth = 1
	mf.array_layers = 1
	mf.mipmaps = 1
	mf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	_mask_tex = _rd.texture_create(mf, RDTextureView.new(), [_mask_bytes])
	_mask_bytes = PackedByteArray()

	for i in 3:
		var per_set := []
		for s in 3:
			per_set.append(_make_set(_tex[i], s))
		_sets.append(per_set)
	_mask_set = _make_set(_mask_tex, 3)
	texture.texture_rd_rid = _tex[0]
	_ready_rd = true

func _make_set(tex: RID, set_index: int) -> RID:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = 0
	u.add_id(tex)
	return _rd.uniform_set_create([u], _shader, set_index)

func _step(cur: int, prv: int, nxt: int, pc: PackedByteArray) -> void:
	var groups := int((RES - 1) / 8.0) + 1
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipeline)
	_rd.compute_list_bind_uniform_set(cl, _sets[cur][0], 0)
	_rd.compute_list_bind_uniform_set(cl, _sets[prv][1], 1)
	_rd.compute_list_bind_uniform_set(cl, _sets[nxt][2], 2)
	_rd.compute_list_bind_uniform_set(cl, _mask_set, 3)
	_rd.compute_list_set_push_constant(cl, pc, pc.size())
	_rd.compute_list_dispatch(cl, groups, groups, 1)
	_rd.compute_list_end()

func _exit_tree() -> void:
	if not _ready_rd:
		return
	_ready_rd = false
	texture.texture_rd_rid = RID()
	for r in _tex:
		if r.is_valid():
			_rd.free_rid(r)
	_tex.clear()
	if _mask_tex.is_valid():
		_rd.free_rid(_mask_tex)
	if _pipeline.is_valid():
		_rd.free_rid(_pipeline)
	if _shader.is_valid():
		_rd.free_rid(_shader)
