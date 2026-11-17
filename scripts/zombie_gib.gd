extends SkeletonModifier3D
## Odstřelené části těla: kost (a s ní vše pod ní) se smrští do pahýlu.
## Děje se až jako úprava výsledné pózy, takže animace, zásahové zóny i ragdoll pracují s nezměněnou kostrou.
var bones: Array[int]=[]

func _process_modification_with_delta(_delta: float) -> void:
	var skeleton:=get_skeleton()
	if skeleton==null: return
	for bone in bones: skeleton.set_bone_pose_scale(bone,Vector3(0.001,0.001,0.001))
