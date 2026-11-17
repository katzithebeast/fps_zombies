extends CanvasLayer
class_name PerfMon
## Měřič výkonu.
## F4  – podrobný přehled: GPU/CPU čas snímku, čas jednotlivých systémů (skripty), počty objektů a paměť.
## F5  – nahrávání výkonu: zmáčkni a normálně hraj, druhým F5 nahrávání ukončíš.
##       Každý snímek se zapíše (čas, GPU, CPU, skripty po systémech, draw calls, místo na mapě, počet zombie)
##       do složky perf/ v projektu: perf_log.csv (surová data) a perf_report.txt (shrnutí po místech, špičky).
## F6  – automatický benchmark efektů (stůj na místě ~25 s).

static var _acc:={}            # systém -> mikrosekundy za aktuální interval
static var _frames:=0
static var _frame_acc:={}     # systém -> µs v tomto snímku (pro nahrávání)

static func add(system: String, usec: int) -> void:
	_acc[system]=int(_acc.get(system,0))+usec
	_frame_acc[system]=int(_frame_acc.get(system,0))+usec

var main: Node
var _label: Label
var _panel: PanelContainer
var _shown:=false
var _timer:=0.0
var _avg:={}                   # systém -> ms na snímek (poslední interval)
var _gpu:=0.0
var _cpu:=0.0
var _refl_gpu:=0.0
var _bench_running:=false
var _report:=""
var _recording:=false
var _rec_start:=0
var _rows:=[]                  # nahrané snímky
var _systems:={}               # všechny systémy, které se objevily
var _rec_label: Label
var _last_save:=0
var _csv: FileAccess          # otevřený log, řádky se připisují průběžně (žádné záseky)
var _written:=0
const SYSTEMS:=["Bazénové hračky","Efekty boje","Hlavní smyčka","Hráč a zbraň","Hráč fyzika","Stanice a popisky","Voda simulace","Zombie AI","Zombie režim","Zvuky"]

func setup(main_node: Node) -> void:
	main=main_node
	layer=50
	_panel=PanelContainer.new()
	var style:=StyleBoxFlat.new()
	style.bg_color=Color(0,0,0,0.72)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel",style)
	_panel.position=Vector2(16,16)
	add_child(_panel)
	_label=Label.new()
	var font:=SystemFont.new()
	font.font_names=PackedStringArray(["Consolas","DejaVu Sans Mono","Courier New","monospace"])
	_label.add_theme_font_override("font",font)
	_label.add_theme_font_size_override("font_size",15)
	_panel.add_child(_label)
	_panel.visible=false
	_rec_label=Label.new()
	_rec_label.text="● REC  výkon se nahrává (F5 = konec)"
	_rec_label.add_theme_color_override("font_color",Color(1,0.25,0.2))
	_rec_label.add_theme_font_size_override("font_size",16)
	_rec_label.position=Vector2(16,8)
	_rec_label.visible=false
	add_child(_rec_label)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	if main.refl_vp: RenderingServer.viewport_set_measure_render_time(main.refl_vp.get_viewport_rid(),true)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_F4:
			_shown=not _shown
			_panel.visible=_shown or _bench_running
			get_viewport().set_input_as_handled()
		elif event.physical_keycode==KEY_F5:
			get_viewport().set_input_as_handled()
			if _recording: _stop_recording()
			else: _start_recording()
		elif event.physical_keycode==KEY_F6 and not _bench_running:
			get_viewport().set_input_as_handled()
			_benchmark()

func _process(dt: float) -> void:
	_frames+=1
	_timer+=dt
	if _recording: _record(dt)
	_frame_acc.clear()
	var vp:=get_viewport().get_viewport_rid()
	_gpu=lerpf(_gpu,RenderingServer.viewport_get_measured_render_time_gpu(vp),0.1)
	_cpu=lerpf(_cpu,RenderingServer.viewport_get_measured_render_time_cpu(vp),0.1)
	if main.refl_vp:
		_refl_gpu=lerpf(_refl_gpu,RenderingServer.viewport_get_measured_render_time_gpu(main.refl_vp.get_viewport_rid()),0.1)
	if _timer<0.5: return
	_avg={}
	for key in _acc: _avg[key]=float(_acc[key])/1000.0/maxf(_frames,1)
	_acc.clear()
	_frames=0
	_timer=0.0
	if _panel.visible: _label.text=_text()

func _text() -> String:
	var lines:=PackedStringArray()
	var fps:=Engine.get_frames_per_second()
	lines.append("VÝKON   %d FPS   (%.1f ms/snímek)" % [fps,1000.0/maxf(fps,1)])
	lines.append("GPU celkem %6.2f ms   z toho odraz vody %5.2f ms" % [_gpu+_refl_gpu,_refl_gpu])
	lines.append("CPU kreslení %5.2f ms   skripty %5.2f ms   fyzika %5.2f ms" % [_cpu,Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0])
	lines.append("")
	lines.append("SKRIPTY (ms na snímek)")
	var keys:=_avg.keys()
	keys.sort_custom(func(a,b): return _avg[a]>_avg[b])
	var total:=0.0
	for key in keys:
		lines.append("  %-22s %6.3f" % [key,_avg[key]])
		total+=float(_avg[key])
	lines.append("  %-22s %6.3f" % ["ostatní (engine)",maxf(0.0,Performance.get_monitor(Performance.TIME_PROCESS)*1000.0-total)])
	lines.append("")
	lines.append("SCÉNA")
	lines.append("  vykreslení (draw calls) %d" % Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	lines.append("  objektů ve snímku       %d" % Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	lines.append("  trojúhelníků            %d tis." % int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)/1000.0))
	lines.append("  uzlů celkem             %d" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	lines.append("  aktivní fyz. tělesa     %d" % Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	lines.append("  video paměť             %d MB (textury %d MB)" % [int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0),int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)/1048576.0)])
	lines.append("")
	lines.append("F5 = nahrávat výkon při hraní   F6 = benchmark efektů (stůj ~25 s)")
	if _report!="": lines.append("\n"+_report)
	return "\n".join(lines)

# ------------------------------------------------------------------ nahrávání při hraní

func _area(p: Vector3) -> String:
	var x:=p.x
	var z:=p.z
	if x>-2.6 and x<2.6 and z>-1.2: return "vstup"
	if x>2.6 and x<12.6 and z>-1.2: return "šatny"
	if x>-12.6 and x<12.6 and z>-26.6 and z<=-1.2: return "hala"
	if x>-22.6 and x<-12.6 and z>-19.8 and z<-10.4: return "technická"
	if x>-31.2 and x<=-12.6 and z>-22.8 and z<=-19.8: return "chodba k východu"
	if x>12.0 and x<20.0 and z>-15.6 and z<-12.4: return "chodba se sprchami"
	if x>=20.0 and x<47.2 and z>-34.6 and z<-1.4: return "síň s andělem"
	if x>23.4 and x<42.6 and z>=-1.4 and z<17.6: return "terasy"
	if x>=42.6 and x<52.6 and z>11.4 and z<24.0: return "chodba se schody"
	if x>45.4 and x<62.6 and z>=23.4 and z<40.6: return "kulatá síň"
	if x>37.4 and x<=45.4 and z>=17.6 and z<28.6: return "zadní chodba"
	if x>-13.2 and x<13.2 and z>-46.6 and z<=-26.0: return "les sloupů"
	if x>-33.8 and x<=-13.2 and z>-59.4 and z<=-22.8: return "bludiště"
	if x>-10.6 and x<4.6 and z>-59.4 and z<=-46.6: return "bufet"
	if x>=4.6 and x<13.8 and z>-53.5 and z<-50.5: return "tunel"
	if x>=13.2 and x<30.6 and z>-56.6 and z<=-34.0: return "atrium"
	return "jinde"

func _start_recording() -> void:
	_recording=true
	_rows.clear()
	_systems.clear()
	_rec_start=Time.get_ticks_msec()
	_last_save=_rec_start
	_rec_label.visible=true
	if main.has_method("toast"): main.toast("Nahrávání výkonu spuštěno — hraj normálně, F5 ukončí")

func _stop_recording() -> void:
	_recording=false
	_rec_label.visible=false
	var path:=_save()
	if main.has_method("toast"): main.toast("Výkon uložen: "+path)

func _record(dt: float) -> void:
	var vp:=get_viewport().get_viewport_rid()
	var row:={
		"t":(Time.get_ticks_msec()-_rec_start)/1000.0,
		"ms":dt*1000.0,
		"gpu":RenderingServer.viewport_get_measured_render_time_gpu(vp),
		"refl":RenderingServer.viewport_get_measured_render_time_gpu(main.refl_vp.get_viewport_rid()) if main.refl_vp else 0.0,
		"cpu":RenderingServer.viewport_get_measured_render_time_cpu(vp),
		"draws":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects":int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"tris":int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"physics":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,
		"zombies":_zombie_count(),
		"area":_area(main.player.global_position) if main.player else "?",
		"pos":main.player.global_position if main.player else Vector3.ZERO,
		"scripts":{},
	}
	var measured:=0.0
	for key in _frame_acc:
		row.scripts[key]=float(_frame_acc[key])/1000.0
		measured+=row.scripts[key]
		_systems[key]=true
	# Čas „skripty“ (TIME_PROCESS), který žádný systém nenahlásil: animace, kosti, částice, tweeny enginu.
	row.scripts["Ostatní (engine)"]=maxf(0.0,Performance.get_monitor(Performance.TIME_PROCESS)*1000.0-measured)
	_systems["Ostatní (engine)"]=true
	_rows.append(row)
	# Průběžné uložení každých 30 s, ať data nezmizí, kdyby hra spadla.
	# Malá dávka řádků na disk každou sekundu – data přežijí pád a nic nezasekne snímek.
	if Time.get_ticks_msec()-_last_save>1000:
		_last_save=Time.get_ticks_msec()
		_flush_csv()

func _zombie_count() -> int:
	var n:=0
	for z in load("res://scripts/zombie.gd").crowd:
		if is_instance_valid(z) and z.ai: n+=1
	return n

func _dir() -> String:
	var dir:=ProjectSettings.globalize_path("res://perf")
	if OS.has_feature("editor") or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://")):
		DirAccess.make_dir_recursive_absolute(dir)
		if DirAccess.dir_exists_absolute(dir): return dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://perf"))
	return ProjectSettings.globalize_path("user://perf")

func _flush_csv() -> void:
	if _csv==null:
		_csv=FileAccess.open(_dir()+"/perf_log.csv",FileAccess.WRITE)
		if _csv==null: return
		var head:=["t","frame_ms","gpu_ms","reflection_ms","cpu_render_ms","physics_ms","draw_calls","objects","triangles","zombies","area","x","y","z"]
		head.append_array(SYSTEMS)
		_csv.store_line(",".join(head))
		_written=0
	while _written<_rows.size():
		var r: Dictionary=_rows[_written]
		var cols:=["%.3f"%r.t,"%.2f"%r.ms,"%.2f"%r.gpu,"%.2f"%r.refl,"%.2f"%r.cpu,"%.2f"%r.physics,str(r.draws),str(r.objects),str(r.tris),str(r.zombies),r.area,"%.1f"%r.pos.x,"%.1f"%r.pos.y,"%.1f"%r.pos.z]
		for key in SYSTEMS: cols.append("%.3f" % float(r.scripts.get(key,0.0)))
		_csv.store_line(",".join(cols))
		_written+=1
	_csv.flush()

func _save() -> String:
	if _rows.is_empty(): return ""
	var dir:=_dir()
	var systems:=_systems.keys()
	systems.sort()
	_flush_csv()
	if _csv:
		_csv.close()
		_csv=null
	var report:=FileAccess.open(dir+"/perf_report.txt",FileAccess.WRITE)
	if report:
		report.store_string(_summary(systems))
		report.close()
	return dir

static func _avg_of(rows: Array, key: String) -> float:
	var t:=0.0
	for r in rows: t+=float(r[key])
	return t/maxf(rows.size(),1)

func _summary(systems: Array) -> String:
	var out:=PackedStringArray()
	var times:=[]
	for r in _rows: times.append(r.ms)
	times.sort()
	var n:=times.size()
	var p99: float=times[int(n*0.99)] if n>0 else 0.0
	var p50: float=times[int(n*0.5)] if n>0 else 0.0
	out.append("HLADINA – záznam výkonu  (%s)" % Time.get_datetime_string_from_system())
	out.append("Délka %.0f s, %d snímků, okno %s" % [_rows[-1].t,n,str(get_viewport().get_visible_rect().size)])
	out.append("")
	out.append("CELKEM")
	out.append("  průměr %.1f FPS (%.2f ms)   medián %.2f ms   1%% nejhorších %.2f ms (%.0f FPS)" % [1000.0/maxf(_avg_of(_rows,"ms"),0.01),_avg_of(_rows,"ms"),p50,p99,1000.0/maxf(p99,0.01)])
	out.append("  GPU %.2f ms (z toho odraz vody %.2f)   CPU kreslení %.2f ms   fyzika %.2f ms" % [_avg_of(_rows,"gpu")+_avg_of(_rows,"refl"),_avg_of(_rows,"refl"),_avg_of(_rows,"cpu"),_avg_of(_rows,"physics")])
	out.append("  draw calls %.0f   objektů %.0f   trojúhelníků %.0f tis.   zombie %.1f" % [_avg_of(_rows,"draws"),_avg_of(_rows,"objects"),_avg_of(_rows,"tris")/1000.0,_avg_of(_rows,"zombies")])
	out.append("")
	out.append("SKRIPTY (průměr ms/snímek, max)")
	var sys_rows:=[]
	for key in systems:
		var total:=0.0
		var peak:=0.0
		for r in _rows:
			var v: float=r.scripts.get(key,0.0)
			total+=v
			peak=maxf(peak,v)
		sys_rows.append([key,total/maxf(n,1),peak])
	sys_rows.sort_custom(func(a,b): return a[1]>b[1])
	for s in sys_rows: out.append("  %-22s %6.3f   max %6.2f" % s)
	out.append("")
	out.append("PODLE MÍST")
	out.append("  %-20s %7s %6s %7s %7s %7s %7s %6s" % ["místo","snímků","FPS","ms","GPU","odraz","draws","zombie"])
	var areas:={}
	for r in _rows:
		if not areas.has(r.area): areas[r.area]=[]
		areas[r.area].append(r)
	var names:=areas.keys()
	names.sort_custom(func(a,b): return _avg_of(areas[a],"ms")>_avg_of(areas[b],"ms"))
	for a in names:
		var rs: Array=areas[a]
		out.append("  %-20s %7d %6.0f %7.2f %7.2f %7.2f %7.0f %6.1f" % [a,rs.size(),1000.0/maxf(_avg_of(rs,"ms"),0.01),_avg_of(rs,"ms"),_avg_of(rs,"gpu"),_avg_of(rs,"refl"),_avg_of(rs,"draws"),_avg_of(rs,"zombies")])
	out.append("")
	out.append("NEJHORŠÍ SNÍMKY (záseky)")
	var worst:=_rows.duplicate()
	worst.sort_custom(func(a,b): return a.ms>b.ms)
	for i in mini(15,worst.size()):
		var r: Dictionary=worst[i]
		var top:=""
		var best_v:=0.0
		for key in r.scripts:
			if r.scripts[key]>best_v:
				best_v=r.scripts[key]
				top="%s %.1f ms" % [key,best_v]
		out.append("  t=%6.1f s  %6.1f ms  GPU %5.1f  fyzika %5.1f  %-18s zombie %2d  nejdražší skript: %s" % [r.t,r.ms,r.gpu+r.refl,r.physics,r.area,r.zombies,top])
	return "\n".join(out)

func _measure(seconds: float) -> float:
	# Průměrný GPU čas (hlavní obraz + odraz) za daný čas.
	await get_tree().create_timer(0.6).timeout      # ustálení po přepnutí
	var total:=0.0
	var n:=0
	var end:=Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<end:
		await get_tree().process_frame
		var g:=RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		if main.refl_vp: g+=RenderingServer.viewport_get_measured_render_time_gpu(main.refl_vp.get_viewport_rid())
		total+=g
		n+=1
	return total/maxf(n,1)

func _benchmark() -> void:
	_bench_running=true
	_panel.visible=true
	_report="BENCHMARK běží…"
	_label.text=_text()
	var env: Environment=main.env
	var tests:=[
		["Globální osvětlení (SDFGI)",func(on): env.sdfgi_enabled=on],
		["Volumetrická mlha",func(on): env.volumetric_fog_enabled=on],
		["SSAO + SSIL",func(on): env.ssao_enabled=on; env.ssil_enabled=on],
		["SSR odrazy",func(on): env.ssr_enabled=on],
		["Glow / bloom",func(on): env.glow_enabled=on],
		["Odraz vody (planar)",func(on): main.refl_vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED],
		["Krev na zdech (decaly)",func(on): for d in main.find_children("*","Decal",true,false): d.visible=on],
		["Stíny lamp",func(on): for l in main.find_children("*","OmniLight3D",true,false): l.shadow_enabled=on if l.get_meta("had_shadow",l.shadow_enabled) else false],
		["Světelné paprsky",func(on): for s in main.light_shafts: s.visible=on],
		["Socha anděla",func(on): for m in main.find_children("*","MeshInstance3D",true,false): if m.get_meta("angel",false): m.visible=on],
	]
	for l in main.find_children("*","OmniLight3D",true,false): l.set_meta("had_shadow",l.shadow_enabled)
	var original:=[env.sdfgi_enabled,env.volumetric_fog_enabled,env.ssao_enabled,env.ssil_enabled,env.ssr_enabled,env.glow_enabled]
	var base:=await _measure(2.0)
	var rows:=[]
	for test in tests:
		var name: String=test[0]
		var toggle: Callable=test[1]
		toggle.call(false)
		var without:=await _measure(1.6)
		toggle.call(true)
		rows.append([name,base-without])
		_report="BENCHMARK: %s hotovo" % name
		_label.text=_text()
	env.sdfgi_enabled=original[0]
	env.volumetric_fog_enabled=original[1]
	env.ssao_enabled=original[2]
	env.ssil_enabled=original[3]
	env.ssr_enabled=original[4]
	env.glow_enabled=original[5]
	for setting in ["planar","gi","volumetric","ssr","ao","bloom"]:
		if main.settings.has(setting): main.apply_setting(setting)
	rows.sort_custom(func(a,b): return a[1]>b[1])
	var out:=PackedStringArray()
	out.append("BENCHMARK (GPU, místo %s)" % str(main.player.global_position.snapped(Vector3.ONE)))
	out.append("  základ: %.2f ms GPU na snímek" % base)
	for r in rows:
		out.append("  %-28s %+6.2f ms  (%4.1f %%)" % [r[0],r[1],100.0*r[1]/maxf(base,0.001)])
	out.append("  skripty: "+", ".join(_avg.keys().map(func(k): return "%s %.2f" % [k,_avg[k]])))
	_report="\n".join(out)
	var file:=FileAccess.open("user://perf_report.txt",FileAccess.WRITE)
	if file:
		file.store_string(_text())
		file.close()
	DisplayServer.clipboard_set(_text())
	_bench_running=false
	_label.text=_text()
	print(_report)
