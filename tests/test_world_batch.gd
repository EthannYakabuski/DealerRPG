extends SceneTree

var checks:=0
var failures:=0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("WORLD BATCH: "+message)

func _run() -> void:
	var batch=load("res://scripts/world_batch.gd").new()
	var parent:=Node3D.new()
	root.add_child(parent)
	batch.box(Vector3(-70,0.01,6),Vector3(3,0.02,2),Color.WHITE,0.7)
	batch.box(Vector3(5,0.01,6),Vector3(3,0.02,2),Color.WHITE,0.7)
	batch.box(Vector3(8,0.01,6),Vector3(1,0.02,1),Color.WHITE)
	batch.cylinder(Vector3(6,1,7),0.5,2,Color.GREEN)
	var expected: Array[Dictionary]=[]
	for group: Dictionary in batch.groups.values():
		for transform: Transform3D in group.transforms:
			expected.append({"transform":transform,"mesh":group.mesh,"shadow":group.casts_shadows})
	batch.flush(parent)
	_check(parent.get_child_count()==3,"Nearby details share a batch while distant details can be culled separately")
	var actual: Array[Dictionary]=[]
	for node: MultiMeshInstance3D in parent.get_children():
		for index in node.multimesh.instance_count:
			actual.append({"transform":node.multimesh.get_instance_transform(index),"mesh":node.multimesh.mesh,"shadow":node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON})
	_check(actual.size()==expected.size(),"Every detail survives spatial batching exactly once")
	for shape: String in ["BoxMesh","CylinderMesh"]:
		var expected_count:=0
		var actual_count:=0
		for wanted: Dictionary in expected:
			if wanted.mesh.is_class(shape): expected_count+=1
		for item: Dictionary in actual:
			if item.mesh.is_class(shape) and item.shadow==(shape=="CylinderMesh"): actual_count+=1
		_check(actual_count==expected_count,"Mesh instances retain their material resource and shadow policy")
	# The dummy headless renderer returns identity for MultiMesh readback.
	# Native execution additionally validates the real submitted transforms.
	if DisplayServer.get_name()!="headless":
		for wanted: Dictionary in expected:
			var matches:=0
			for item: Dictionary in actual:
				if item.transform.is_equal_approx(wanted.transform) and item.mesh==wanted.mesh and item.shadow==wanted.shadow: matches+=1
			_check(matches==1,"World position, rotation, scale and material remain intact")
	batch.flush(parent)
	_check(parent.get_child_count()==3,"Flushing twice does not duplicate submitted geometry")
	parent.queue_free()
	await process_frame
	print("WORLD BATCH TESTS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
