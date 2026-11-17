extends SceneTree
## Spuštění: Godot --headless --path . --script res://tools/build_zombie.gd
## Z klipů v assets/zombie/anims připraví knihovnu animací přenesenou na kostru zombie.
const BASE:="res://assets/zombie/"
const CLIPS:={"idle":true,"walk":true,"run":true,"crawl":true,"crawl_fast":true,"attack":false,"scream":false}

func _initialize() -> void:
	var model: Node3D=load(BASE+"zombie.fbx").instantiate()
	root.add_child(model)
	var target: Skeleton3D=model.get_node("Skeleton3D")
	var library:=AnimationLibrary.new()
	for clip in CLIPS:
		var scene: Node3D=load(BASE+"anims/"+clip+".fbx").instantiate()
		var source: Skeleton3D=scene.find_children("*","Skeleton3D",true,false)[0]
		var player: AnimationPlayer=scene.find_children("*","AnimationPlayer",true,false)[0]
		var from: Animation=player.get_animation(player.get_animation_list()[0])
		var looped: bool=CLIPS[clip]
		var anim:=Animation.new()
		anim.length=from.length
		anim.loop_mode=Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE
		var ratio:=target.get_bone_rest(target.find_bone("mixamorig_Hips")).origin.y/source.get_bone_rest(source.find_bone("mixamorig_Hips")).origin.y
		var travel:=0.0
		for track in from.get_track_count():
			var type:=from.track_get_type(track)
			var bone_name:=String(from.track_get_path(track)).get_slice(":",1)
			var bone:=target.find_bone(bone_name)
			var source_bone:=source.find_bone(bone_name)
			if bone<0 or source_bone<0: continue
			var count:=from.track_get_key_count(track)
			if count==0: continue
			if type==Animation.TYPE_ROTATION_3D:
				var index:=anim.add_track(Animation.TYPE_ROTATION_3D)
				anim.track_set_path(index,NodePath("Skeleton3D:"+bone_name))
				var rest_source:=source.get_bone_rest(source_bone).basis.get_rotation_quaternion()
				var rest_target:=target.get_bone_rest(bone).basis.get_rotation_quaternion()
				var first: Quaternion=from.track_get_key_value(track,0)
				for key in count:
					var t:=from.track_get_key_time(track,key)
					var value: Quaternion=from.track_get_key_value(track,key)
					if looped: value=value.slerp(first,smoothstep(from.length-0.1,from.length,t))
					anim.rotation_track_insert_key(index,t,(rest_target*(rest_source.inverse()*value)).normalized())
			elif type==Animation.TYPE_POSITION_3D and bone_name=="mixamorig_Hips":
				var index:=anim.add_track(Animation.TYPE_POSITION_3D)
				anim.track_set_path(index,NodePath("Skeleton3D:"+bone_name))
				var rest_source:=source.get_bone_rest(source_bone).origin
				var rest_target:=target.get_bone_rest(bone).origin
				var first: Vector3=from.track_get_key_value(track,0)
				var last: Vector3=from.track_get_key_value(track,count-1)
				travel=Vector2(last.x-first.x,last.z-first.z).length()*ratio
				for key in count:
					var t:=from.track_get_key_time(track,key)
					var value: Vector3=from.track_get_key_value(track,key)
					# Odstranit jen plynulý posun vpřed; kolébání boků zůstává. Světem hýbe skript.
					var along:=t/from.length
					value.x-=first.x+(last.x-first.x)*along
					value.z-=first.z+(last.z-first.z)*along
					value.y-=rest_source.y
					if looped: value=value.lerp(Vector3(0,first.y-rest_source.y,0),smoothstep(from.length-0.1,from.length,t))
					anim.position_track_insert_key(index,t,rest_target+value*ratio)
		anim.set_meta("speed",travel/from.length)
		print(clip," length=%.2f tracks=%d speed=%.2f m/s ratio=%.2f"%[anim.length,anim.get_track_count(),travel/from.length,ratio])
		library.add_animation(clip,anim)
		scene.free()
	print("SAVE ",ResourceSaver.save(library,BASE+"zombie_anims.res"))
	quit()
