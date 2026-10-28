extends RefCounted
## Lossless index welding for the baked Godot 4.6 ArrayMesh storage format.
## Raw records are copied: decoding/re-encoding octahedral normals is lossy.
## Triangle order, packed attributes, material, bounds and scene nodes stay intact.

var _mesh_cache: Dictionary={}
var _resource_cache: Dictionary={}

func optimize_tree(root: Node) -> Dictionary:
	_mesh_cache.clear()
	var stats: Dictionary={"meshes":0,"optimized_meshes":0,"surfaces":0,"vertices_before":0,"vertices_after":0,"triangles":0,"skipped":{}}
	_optimize_nodes(root,stats)
	stats["vertices_removed"]=stats.vertices_before-stats.vertices_after
	return stats

func _optimize_nodes(node: Node,stats: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh!=null:
		stats.meshes+=1
		var old: Mesh=node.mesh
		var id:=old.get_instance_id()
		if not _mesh_cache.has(id): _mesh_cache[id]=optimize_mesh(old)
		var result: Dictionary=_mesh_cache[id]
		stats.surfaces+=result.surfaces
		stats.vertices_before+=result.vertices_before
		stats.vertices_after+=result.vertices_after
		stats.triangles+=result.triangles
		if result.changed:
			node.mesh=result.mesh
			stats.optimized_meshes+=1
		elif result.get("reason","")!="":
			var reason: String=result.reason
			stats.skipped[reason]=int(stats.skipped.get(reason,0))+1
	for child in node.get_children(): _optimize_nodes(child,stats)

func optimize_mesh(mesh: Mesh) -> Dictionary:
	var result: Dictionary={"mesh":mesh,"changed":false,"surfaces":mesh.get_surface_count(),"vertices_before":0,"vertices_after":0,"triangles":0,"reason":""}
	if not mesh is ArrayMesh:
		result.reason="primitive_mesh_retained"
		for surface in range(mesh.get_surface_count()):
			var arrays: Array=mesh.surface_get_arrays(surface)
			result.vertices_before+=arrays[Mesh.ARRAY_VERTEX].size()
			var indices=arrays[Mesh.ARRAY_INDEX]
			result.triangles+=(indices.size() if indices!=null and indices.size()>0 else arrays[Mesh.ARRAY_VERTEX].size())/3
		result.vertices_after=result.vertices_before
		return result
	var source: Array=mesh.get("_surfaces")
	for s: Dictionary in source:
		result.vertices_before+=int(s.vertex_count)
		if int(s.primitive)==Mesh.PRIMITIVE_TRIANGLES: result.triangles+=int(s.get("index_count",s.vertex_count))/3
	result.vertices_after=result.vertices_before
	if mesh.get_blend_shape_count()>0 or mesh.shadow_mesh!=null:
		result.reason="blend_shape_or_existing_shadow_mesh"
		return result
	var info: Dictionary=Engine.get_version_info()
	if info.major!=4 or info.minor!=6:
		result.reason="unsupported_raw_storage_version"
		return result
	var target: Array=[]
	var new_count:=0
	for s: Dictionary in source:
		if not s.get("lods",[]).is_empty() or not s.get("blend_shapes",PackedByteArray()).is_empty():
			result.reason="lod_or_blend_shape_retained"
			return result
		var layout:=_layout(s)
		if not layout.valid:
			result.reason="unknown_buffer_layout"
			return result
		var welded:=_weld_surface(s,layout)
		target.append(welded)
		new_count+=int(welded.vertex_count)
	if new_count==int(result.vertices_before): return result
	var candidate:=ArrayMesh.new()
	# Copy non-surface storage properties and all resource metadata.
	for property in mesh.get_property_list():
		var name: String=property.name
		if (int(property.usage) & PROPERTY_USAGE_STORAGE)==0 or name=="_surfaces" or name.begins_with("surface_"): continue
		if name in ["resource_path","resource_scene_unique_id"]: continue
		candidate.set(name,mesh.get(name))
	for key in mesh.get_meta_list(): candidate.set_meta(key,mesh.get_meta(key))
	candidate.set("_surfaces",target)
	if candidate.get_aabb()!=mesh.get_aabb():
		result.reason="aabb_mismatch"
		return result
	result.mesh=candidate
	result.changed=true
	result.vertices_after=new_count
	return result

func _layout(s: Dictionary) -> Dictionary:
	var count: int=s.get("vertex_count",0)
	var format: int=s.get("format",0)
	var position_stride:=RenderingServer.mesh_surface_get_format_vertex_stride(format,count)
	var normal_stride:=RenderingServer.mesh_surface_get_format_normal_tangent_stride(format,count)
	var attribute_stride:=RenderingServer.mesh_surface_get_format_attribute_stride(format,count)
	var skin_stride:=RenderingServer.mesh_surface_get_format_skin_stride(format,count)
	var index_stride:=RenderingServer.mesh_surface_get_format_index_stride(format,count)
	var vertices: PackedByteArray=s.get("vertex_data",PackedByteArray())
	var attributes: PackedByteArray=s.get("attribute_data",PackedByteArray())
	var skin: PackedByteArray=s.get("skin_data",PackedByteArray())
	var indices: PackedByteArray=s.get("index_data",PackedByteArray())
	var valid:=count>0 and vertices.size()==count*(position_stride+normal_stride) and attributes.size()==count*attribute_stride and skin.size()==count*skin_stride
	valid=valid and int(s.get("index_count",0))>0 and indices.size()==int(s.get("index_count",0))*index_stride
	return {"valid":valid,"count":count,"p":position_stride,"n":normal_stride,"a":attribute_stride,"s":skin_stride,"i":index_stride,"normal_base":count*position_stride}

func _record(s: Dictionary,l: Dictionary,index: int) -> PackedByteArray:
	var vertices: PackedByteArray=s.vertex_data
	var record:=vertices.slice(index*l.p,(index+1)*l.p)
	if l.n>0: record.append_array(vertices.slice(l.normal_base+index*l.n,l.normal_base+(index+1)*l.n))
	if l.a>0: record.append_array(s.attribute_data.slice(index*l.a,(index+1)*l.a))
	if l.s>0: record.append_array(s.skin_data.slice(index*l.s,(index+1)*l.s))
	return record

func _index(bytes: PackedByteArray,index: int,stride: int) -> int:
	return bytes.decode_u16(index*2) if stride==2 else bytes.decode_u32(index*4)

func _weld_surface(source: Dictionary,l: Dictionary) -> Dictionary:
	var seen: Dictionary={}
	var representatives:=PackedInt32Array()
	var remap:=PackedInt32Array()
	remap.resize(l.count)
	for old in range(l.count):
		var key:=_record(source,l,old)
		if not seen.has(key):
			seen[key]=representatives.size()
			representatives.append(old)
		remap[old]=seen[key]
	if representatives.size()==int(l.count): return source
	var positions:=PackedByteArray()
	var normals:=PackedByteArray()
	var attributes:=PackedByteArray()
	var skin:=PackedByteArray()
	var vertices: PackedByteArray=source.vertex_data
	for old in representatives:
		positions.append_array(vertices.slice(old*l.p,(old+1)*l.p))
		if l.n>0: normals.append_array(vertices.slice(l.normal_base+old*l.n,l.normal_base+(old+1)*l.n))
		if l.a>0: attributes.append_array(source.attribute_data.slice(old*l.a,(old+1)*l.a))
		if l.s>0: skin.append_array(source.skin_data.slice(old*l.s,(old+1)*l.s))
	positions.append_array(normals)
	var target: Dictionary=source.duplicate()
	target.vertex_count=representatives.size()
	target.vertex_data=positions
	if source.has("attribute_data"): target.attribute_data=attributes
	if source.has("skin_data"): target.skin_data=skin
	var stride:=RenderingServer.mesh_surface_get_format_index_stride(source.format,target.vertex_count)
	var new_indices:=PackedByteArray()
	new_indices.resize(int(source.index_count)*stride)
	for corner in range(int(source.index_count)):
		var mapped: int=remap[_index(source.index_data,corner,l.i)]
		if stride==2: new_indices.encode_u16(corner*2,mapped)
		else: new_indices.encode_u32(corner*4,mapped)
	target.index_data=new_indices
	return target

## The hash expands the index stream in its original order. It includes every
## packed vertex channel, including automatically generated tangent data.
func corner_digest(root: Node) -> String:
	_resource_cache.clear()
	var hash:=HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	_digest_nodes(root,root,hash)
	return hash.finish().hex_encode()

func _digest_nodes(node: Node,root: Node,hash: HashingContext) -> void:
	if node is MeshInstance3D and node.mesh!=null:
		var mesh: Mesh=node.mesh
		hash.update(var_to_bytes(str(root.get_path_to(node))))
		if mesh is ArrayMesh:
			for s: Dictionary in mesh.get("_surfaces"):
				var header: Dictionary=s.duplicate()
				for key in ["vertex_data","attribute_data","skin_data","index_data","vertex_count"]: header.erase(key)
				hash.update(var_to_bytes(_canonical(header)))
				var l:=_layout(s)
				if not l.valid:
					# Unsupported/non-indexed surfaces are retained byte-for-byte.
					hash.update(var_to_bytes(_canonical(s)))
					continue
				var records: Array[PackedByteArray]=[]
				for index in range(l.count): records.append(_record(s,l,index))
				for corner in range(int(s.index_count)): hash.update(records[_index(s.index_data,corner,l.i)])
		else: hash.update(var_to_bytes(_canonical(mesh)))
	for child in node.get_children(): _digest_nodes(child,root,hash)

## Every stored node/shape/material property except the visual mesh itself.
## This checks transforms, shadows, visibility, collision data and metadata.
func immutable_digest(root: Node) -> String:
	_resource_cache.clear()
	var hash:=HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	_immutable_nodes(root,root,hash)
	return hash.finish().hex_encode()

func _immutable_nodes(node: Node,root: Node,hash: HashingContext) -> void:
	var data: Dictionary={"path":str(root.get_path_to(node)),"class":node.get_class(),"properties":{},"metadata":{}}
	for property in node.get_property_list():
		var name: String=property.name
		if (int(property.usage) & PROPERTY_USAGE_STORAGE)==0 or name in ["mesh","owner"]: continue
		data.properties[name]=node.get(name)
	for key in node.get_meta_list(): data.metadata[key]=node.get_meta(key)
	if node is MeshInstance3D and node.mesh!=null:
		data["mesh_aabb"]=node.mesh.get_aabb()
		var storage: Dictionary={}
		for property in node.mesh.get_property_list():
			var name: String=property.name
			if (int(property.usage) & PROPERTY_USAGE_STORAGE)==0 or name=="_surfaces" or name.begins_with("surface_"): continue
			if name in ["resource_path","resource_scene_unique_id"]: continue
			storage[name]=node.mesh.get(name)
		data["mesh_storage"]=storage
		var metadata: Dictionary={}
		for key in node.mesh.get_meta_list(): metadata[key]=node.mesh.get_meta(key)
		data["mesh_metadata"]=metadata
	hash.update(var_to_bytes(_canonical(data)))
	for child in node.get_children(): _immutable_nodes(child,root,hash)

func collision_digest(root: Node) -> String:
	_resource_cache.clear()
	var hash:=HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	_collision_nodes(root,root,hash)
	return hash.finish().hex_encode()

func _collision_nodes(node: Node,root: Node,hash: HashingContext) -> void:
	if node is CollisionShape3D:
		hash.update(var_to_bytes(str(root.get_path_to(node))))
		hash.update(var_to_bytes(_canonical(node.shape)))
	for child in node.get_children(): _collision_nodes(child,root,hash)

func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array=value.keys()
		keys.sort_custom(func(a: Variant,b: Variant) -> bool: return var_to_str(a)<var_to_str(b))
		var pairs: Array=[]
		for key in keys: pairs.append([_canonical(key),_canonical(value[key])])
		return pairs
	if value is Array:
		var values: Array=[]
		for item in value: values.append(_canonical(item))
		return values
	if value is Resource:
		var id: int=value.get_instance_id()
		if _resource_cache.has(id): return _resource_cache[id]
		var props: Dictionary={"class":value.get_class(),"properties":{},"metadata":{}}
		# Non-built-in resource paths identify external assets without serializing
		# their engine object IDs. Embedded resource IDs may change on saving.
		if not value.is_built_in(): props["external_path"]=value.resource_path
		_resource_cache[id]=["resource_cycle",value.get_class()]
		for property in value.get_property_list():
			var name: String=property.name
			if (int(property.usage) & PROPERTY_USAGE_STORAGE)==0 or name in ["resource_path","resource_scene_unique_id"]: continue
			props.properties[name]=value.get(name)
		for key in value.get_meta_list(): props.metadata[key]=value.get_meta(key)
		var result: Variant=_canonical(props)
		_resource_cache[id]=result
		return result
	return value
