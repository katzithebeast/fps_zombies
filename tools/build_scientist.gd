extends SceneTree
## Spuštění: Godot --headless --path . --script res://tools/build_scientist.gd
## Z původních FBX připraví sdílenou knihovnu animací. Vlastní pohled připraví build_first_person.gd.

const BASE := "res://assets/scientist/"

func _initialize() -> void:
	var model: Node3D = load(BASE + "ScientistRigged.fbx").instantiate()
	root.add_child(model)
	var skeleton: Skeleton3D = model.get_node("Skeleton3D")
	var library := AnimationLibrary.new()
	# RESET obsahuje všechny kosti: korektní výchozí hodnoty při míchání klipů.
	var reset := Animation.new()
	reset.length = 0.001
	for bone in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(bone)
		var path := NodePath("Skeleton3D:" + skeleton.get_bone_name(bone))
		var pos := reset.add_track(Animation.TYPE_POSITION_3D)
		reset.track_set_path(pos, path)
		reset.position_track_insert_key(pos, 0.0, rest.origin)
		var rot := reset.add_track(Animation.TYPE_ROTATION_3D)
		reset.track_set_path(rot, path)
		reset.rotation_track_insert_key(rot, 0.0, rest.basis.get_rotation_quaternion())
	library.add_animation("RESET", reset)
	for clip in ["idle", "slow_run", "fast_run", "strafe_left", "strafe_right", "crouch_walk", "tread_water", "swim", "pick_up", "jump", "turn"]:
		var scene: Node3D = load(BASE + "animations/" + clip + ".fbx").instantiate()
		var player: AnimationPlayer = scene.get_node("AnimationPlayer")
		var anim: Animation = player.get_animation("mixamo_com").duplicate(true)
		var action: bool = clip in ["pick_up", "jump", "turn"]
		anim.loop_mode = Animation.LOOP_NONE if action else Animation.LOOP_LINEAR
		for track in anim.get_track_count():
			var type := anim.track_get_type(track)
			var path := String(anim.track_get_path(track))
			var count := anim.track_get_key_count(track)
			for key in count:
				if type == Animation.TYPE_POSITION_3D and path.ends_with(":mixamorig_Hips"):
					var value: Vector3 = anim.track_get_key_value(track, key)
					# Pohyb světem řídí CharacterBody; animace si nechá vertikální pružení.
					value.x = skeleton.get_bone_rest(0).origin.x
					value.z = skeleton.get_bone_rest(0).origin.z
					anim.track_set_key_value(track, key, value)
			if action:
				continue
			# Uzavřít posledních 80 ms cyklu, aby na smyčce nevznikl skok.
			var first: Variant = anim.track_get_key_value(track, 0)
			for key in count:
				var t := anim.track_get_key_time(track, key)
				var weight := smoothstep(anim.length - 0.08, anim.length, t)
				var value: Variant = anim.track_get_key_value(track, key)
				if type == Animation.TYPE_ROTATION_3D:
					anim.track_set_key_value(track, key, (value as Quaternion).slerp(first, weight))
				elif type == Animation.TYPE_POSITION_3D:
					anim.track_set_key_value(track, key, (value as Vector3).lerp(first, weight))
		if action:
			anim = bake_action(anim, clip)
		library.add_animation(clip, anim)
		if clip == "turn":
			# Nepřerušované rozhlížení potřebuje opakovat kroky bez restartu one-shotu.
			var loop: Animation = anim.duplicate(true)
			loop.loop_mode = Animation.LOOP_LINEAR
			for track in loop.get_track_count():
				var first: Variant = loop.track_get_key_value(track, 0)
				for key in loop.track_get_key_count(track):
					var weight := smoothstep(loop.length - 0.18, loop.length, loop.track_get_key_time(track, key))
					var value: Variant = loop.track_get_key_value(track, key)
					if loop.track_get_type(track) == Animation.TYPE_ROTATION_3D:
						loop.track_set_key_value(track, key, (value as Quaternion).slerp(first, weight))
					elif loop.track_get_type(track) == Animation.TYPE_POSITION_3D:
						loop.track_set_key_value(track, key, (value as Vector3).lerp(first, weight))
			library.add_animation("turn_loop", loop)
		if clip == "crouch_walk":
			var held: Animation = anim.duplicate(true)
			held.length = 1.0
			for track in held.get_track_count():
				var value: Variant = held.track_get_key_value(track, 0)
				while held.track_get_key_count(track) > 0:
					held.track_remove_key(track, 0)
				held.track_insert_key(track, 0.0, value)
				held.track_insert_key(track, 1.0, value)
			library.add_animation("crouch_idle", held)
		if clip == "slow_run":
			var reverse: Animation = anim.duplicate(true)
			for track in reverse.get_track_count():
				var times := PackedFloat64Array()
				var values: Array = []
				for key in reverse.track_get_key_count(track):
					times.append(reverse.track_get_key_time(track, key))
					values.append(reverse.track_get_key_value(track, key))
				while reverse.track_get_key_count(track) > 0:
					reverse.track_remove_key(track, 0)
				for key in times.size():
					reverse.track_insert_key(track, reverse.length - times[key], values[key])
			library.add_animation("backward", reverse)
		print("Animation ", clip, ": ", anim.length, " s, ", anim.get_track_count(), " tracks")
		scene.free()
	var error := ResourceSaver.save(library, BASE + "locomotion.res")
	assert(error == OK)
	model.free()
	quit()

func bake_action(source: Animation, name: String) -> Animation:
	var result := Animation.new()
	result.length = {"jump":0.90,"turn":1.0,"pick_up":1.8}[name]
	result.loop_mode = Animation.LOOP_NONE
	var frames := int(ceil(result.length*60.0))
	for track in source.get_track_count():
		var type := source.track_get_type(track)
		if type not in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D]:
			continue
		var target := result.add_track(type)
		var path := source.track_get_path(track)
		result.track_set_path(target,path)
		for frame in frames+1:
			var t := result.length*frame/frames
			var sample := 0.0
			match name:
				"jump":
					sample = lerpf(0.47,1.10,t/0.64) if t<=0.64 else lerpf(1.10,1.75,(t-0.64)/0.26)
				"turn": sample = t*2.5
				"pick_up": sample = lerpf(0.5,5.1,t/result.length)
			var value: Variant
			if type == Animation.TYPE_ROTATION_3D:
				value = source.rotation_track_interpolate(track,sample)
				if name in ["jump","turn"] and String(path).ends_with(":mixamorig_Hips"):
					# Natočení světem řídí tělo, nikoli zdvojená rotace v klipu.
					value = Quaternion(Vector3.UP,-value.get_euler().y)*value
			elif type == Animation.TYPE_POSITION_3D:
				value = source.position_track_interpolate(track,sample)
				if name == "jump" and String(path).ends_with(":mixamorig_Hips"):
					# Samotný zdvih obstará fyzika skoku; ponechat podřep a tlumení dopadu.
					value.y = clampf(value.y,0.65,1.03)
			else:
				value = source.scale_track_interpolate(track,sample)
			result.track_insert_key(target,t,value)
	if name == "pick_up": result.set_meta("contact_time",0.74)
	if name == "jump": result.set_meta("landing_time",0.64)
	return result
