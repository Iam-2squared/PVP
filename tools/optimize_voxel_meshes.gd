extends SceneTree
## Rewrite only existing visual ArrayMesh buffers; do not regenerate the world.
## Each saved candidate is reloaded and verified before any original is replaced.
const Optimizer=preload("res://scripts/voxel/mesh_optimizer.gd")
var _prepared: Array[Dictionary]=[]
var _report_path:="res://docs/mesh-optimization-stats.json"
var _only:=""
var _dry_run:=false
var _backup_dir:=""
var _committed: Array[Dictionary]=[]
var _pending_candidate:=""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument=="--dry-run": _dry_run=true
		elif argument.begins_with("--only="): _only=argument.trim_prefix("--only=")
		elif argument.begins_with("--report="): _report_path=argument.trim_prefix("--report=")
	_run.call_deferred()

func _run() -> void:
	var began:=Time.get_ticks_msec()
	var files:=DirAccess.get_files_at("res://generated/parts")
	files.sort()
	var totals: Dictionary={"meshes":0,"optimized_meshes":0,"surfaces":0,"vertices_before":0,"vertices_after":0,"vertices_removed":0,"triangles":0,"scene_bytes_before":0,"scene_bytes_after":0}
	for file in files:
		if not file.begins_with("component_") or not file.ends_with(".scn"): continue
		if not _only.is_empty() and file!=_only: continue
		var path: String="res://generated/parts/"+file
		var candidate_path: String="res://generated/parts/.weld_candidate_"+file
		_pending_candidate=candidate_path
		var optimizer:=Optimizer.new()
		var packed: PackedScene=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE)
		if packed==null:
			_abort("Cannot load "+path)
			return
		var node:=packed.instantiate()
		if node==null:
			_abort("Cannot instantiate "+path)
			return
		var corners_before:=optimizer.corner_digest(node)
		var immutable_before:=optimizer.immutable_digest(node)
		var collision_before:=optimizer.collision_digest(node)
		var stats:=optimizer.optimize_tree(node)
		if optimizer.corner_digest(node)!=corners_before or optimizer.immutable_digest(node)!=immutable_before or optimizer.collision_digest(node)!=collision_before:
			node.free()
			_abort("In-memory invariant mismatch: "+path)
			return
		var scene:=PackedScene.new()
		if scene.pack(node)!=OK or ResourceSaver.save(scene,candidate_path,ResourceSaver.FLAG_COMPRESS)!=OK:
			node.free()
			_abort("Cannot save candidate: "+path)
			return
		node.free()
		var saved: PackedScene=ResourceLoader.load(candidate_path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE)
		if saved==null:
			_abort("Cannot reload candidate: "+path)
			return
		var reloaded:=saved.instantiate()
		if reloaded==null:
			_abort("Cannot instantiate reloaded candidate: "+path)
			return
		var corners_after:=optimizer.corner_digest(reloaded)
		var immutable_after:=optimizer.immutable_digest(reloaded)
		var collision_after:=optimizer.collision_digest(reloaded)
		reloaded.free()
		if corners_after!=corners_before or immutable_after!=immutable_before or collision_after!=collision_before:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate_path))
			_abort("Reloaded invariant mismatch: "+path+" corners="+str(corners_after==corners_before)+" immutable="+str(immutable_after==immutable_before)+" collision="+str(collision_after==collision_before))
			return
		stats["file"]=file
		stats["source_sha256"]=FileAccess.get_sha256(path)
		stats["candidate_sha256"]=FileAccess.get_sha256(candidate_path)
		stats["ordered_corner_sha256"]=corners_before
		stats["immutable_sha256"]=immutable_before
		stats["collision_sha256"]=collision_before
		stats["reload_verified"]=true
		stats["scene_bytes_before"]=FileAccess.get_file_as_bytes(path).size()
		stats["scene_bytes_after"]=FileAccess.get_file_as_bytes(candidate_path).size()
		_prepared.append({"path":path,"candidate":candidate_path,"stats":stats})
		_pending_candidate=""
		for key in totals: totals[key]+=int(stats[key])
		print("MESH_WELD ",file," vertices ",stats.vertices_before," -> ",stats.vertices_after," verified")
	if not _dry_run and int(totals.optimized_meshes)==0:
		for part in _prepared: DirAccess.remove_absolute(ProjectSettings.globalize_path(part.candidate))
		print("MESH_WELD_RESULT ",JSON.stringify({"already_optimized":true,"parts":_prepared.size(),"totals":totals}))
		quit()
		return
	if not _dry_run:
		_backup_dir="/tmp/pvp-mesh-weld-backup-%d"%Time.get_ticks_usec()
		if DirAccess.make_dir_recursive_absolute(_backup_dir)!=OK:
			_abort("Cannot create transaction backup directory")
			return
		for part in _prepared:
			# The originals remain available until every scene has passed reload.
			if FileAccess.get_sha256(part.path)!=part.stats.source_sha256:
				_abort("Source changed while verifying: "+str(part.path))
				return
			part["backup"]=_backup_dir+"/"+str(part.path).get_file()
			var backup:=FileAccess.open(part.backup,FileAccess.WRITE)
			if backup==null:
				_abort("Cannot back up "+str(part.path))
				return
			backup.store_buffer(FileAccess.get_file_as_bytes(part.path))
			backup.close()
		for part in _prepared:
			var err:=DirAccess.rename_absolute(ProjectSettings.globalize_path(part.candidate),ProjectSettings.globalize_path(part.path))
			if err!=OK:
				_abort("Could not replace verified candidate: "+str(part.path))
				return
			_committed.append(part)
	else:
		for part in _prepared: DirAccess.remove_absolute(ProjectSettings.globalize_path(part.candidate))
	var parts: Array=[]
	for part in _prepared: parts.append(part.stats)
	var report: Dictionary={"method":"byte_exact_vertex_weld_original_triangle_order","engine":Engine.get_version_info(),"dry_run":_dry_run,"seconds":(Time.get_ticks_msec()-began)/1000.0,"backup_directory":_backup_dir,"parts":parts,"totals":totals,"constraints":{"ordered_corner_raw_bytes":"unchanged","triangle_order":"unchanged","materials":"unchanged","node_metadata":"unchanged","transforms_aabb_visibility_shadows":"unchanged","collision_shape_bytes":"unchanged","lod_blendshape_existing_shadow_mesh":"retained_without_optimization"}}
	var output:=FileAccess.open(_report_path,FileAccess.WRITE)
	if output==null:
		_abort("Cannot write report: "+_report_path)
		return
	output.store_string(JSON.stringify(report,"  ")+"\n")
	output.close()
	if not _dry_run: _update_metrics(totals)
	print("MESH_WELD_RESULT ",JSON.stringify({"parts":parts.size(),"totals":totals,"seconds":report.seconds,"dry_run":_dry_run}))
	quit()

func _update_metrics(totals: Dictionary) -> void:
	var path:="res://generated/world_metrics.json"
	var metrics: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not metrics is Dictionary: return
	var root_bytes:=FileAccess.get_file_as_bytes("res://generated/kingdom.scn").size()
	var total:=root_bytes
	for part: String in metrics.get("part_files",[]): total+=FileAccess.get_file_as_bytes(part).size()
	metrics["bytes"]=root_bytes
	metrics["total_scene_bytes"]=total
	metrics["render_optimization"]={"method":"byte_exact_vertex_weld_original_triangle_order","vertices_before":totals.vertices_before,"vertices_after":totals.vertices_after,"triangles":totals.triangles,"objects_materials_shadows_collision_unchanged":true}
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(metrics,"  ")+"\n")
		file.close()

func _abort(message: String) -> void:
	for part in _committed:
		var restore:=FileAccess.open(part.path,FileAccess.WRITE)
		if restore!=null:
			restore.store_buffer(FileAccess.get_file_as_bytes(part.backup))
			restore.close()
	if not _pending_candidate.is_empty() and FileAccess.file_exists(_pending_candidate):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_pending_candidate))
	for part in _prepared:
		if FileAccess.file_exists(part.candidate): DirAccess.remove_absolute(ProjectSettings.globalize_path(part.candidate))
	push_error(message)
	quit(1)
