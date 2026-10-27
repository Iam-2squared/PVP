extends RefCounted
## Sparse construction data. Empty cells never allocate a node or rendered cube.
## This is used only when baking, then discarded by the runtime scene.

const VOXEL_SIZE := 0.5
var cells: Dictionary = {}

func set_voxel(position: Vector3i, material_id: int) -> void:
	if material_id == 0:
		cells.erase(position)
	else:
		cells[position] = material_id

func get_voxel(position: Vector3i) -> int:
	return cells.get(position, 0)

func box(minimum: Vector3i, maximum_exclusive: Vector3i, material_id: int) -> void:
	for y in range(minimum.y, maximum_exclusive.y):
		for z in range(minimum.z, maximum_exclusive.z):
			for x in range(minimum.x, maximum_exclusive.x):
				var position := Vector3i(x, y, z)
				if material_id == 0:
					cells.erase(position)
				else:
					cells[position] = material_id

func erase_box(minimum: Vector3i, maximum_exclusive: Vector3i) -> void:
	box(minimum, maximum_exclusive, 0)
