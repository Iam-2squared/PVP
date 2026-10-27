extends Node3D
## Sandbox tuning only. README does not yet define ranges, costs or damage.
## One call creates one attack; click arbitration belongs to the controller.

signal attack_fired(strong: bool)
signal feedback(message: String, strong: bool)
signal status_changed

const JOBS := {
	"warrior": {"damage": 18.0, "range": 2.7, "delay": 0.48, "skill": "強撃", "cost": 15.0},
	"mage": {"damage": 14.0, "range": 24.0, "delay": 0.55, "skill": "火炎爆発", "cost": 20.0},
	"scout": {"damage": 14.0, "range": 2.2, "delay": 0.35, "skill": "急所突き", "cost": 15.0},
	"archer": {"damage": 16.0, "range": 32.0, "delay": 0.65, "skill": "貫通矢", "cost": 18.0},
	"cleric": {"damage": 12.0, "range": 22.0, "delay": 0.55, "skill": "ヒール", "cost": 20.0},
	"artisan": {"damage": 20.0, "range": 2.5, "delay": 0.62, "skill": "投擲爆弾", "cost": 20.0},
}
const SKILL_COOLDOWN := 3.0
const UNARMED_DAMAGE := 8.0
const UNARMED_RANGE := 1.65
const MAX_PROJECTILES := 24

var camera: Camera3D
var job_id: String = "warrior"
var equipped: bool = true
var health: float = 100.0
var mana: float = 100.0
var enabled: bool = true
var _attack_cooldown: float = 0.0
var _skill_cooldown: float = 0.0
var _projectiles: Array[Dictionary] = []
var shots_fired: int = 0
var last_damage: float = 0.0
var last_range: float = 0.0


func configure(job: String, armed: bool = true) -> void:
	job_id = job if JOBS.has(job) else "warrior"
	equipped = armed
	health = 100.0
	mana = 100.0
	_attack_cooldown = 0.0
	_skill_cooldown = 0.0
	for projectile: Dictionary in _projectiles:
		if is_instance_valid(projectile.node):
			projectile.node.queue_free()
	_projectiles.clear()
	status_changed.emit()


func get_skill_name() -> String:
	return str(JOBS[job_id].skill)


func get_cooldown() -> float:
	return _skill_cooldown


func get_attack_cooldown() -> float:
	return _attack_cooldown


func request_attack(strong: bool = false) -> bool:
	if not enabled or not is_instance_valid(camera) or _attack_cooldown > 0.0:
		return false
	var info: Dictionary = JOBS[job_id]
	var damage: float = float(info.damage) if equipped else UNARMED_DAMAGE
	var reach: float = float(info.range) if equipped else UNARMED_RANGE
	damage *= 1.2 if strong else 1.0
	_attack_cooldown = float(info.delay) if equipped else 0.4
	last_damage = damage
	last_range = reach
	shots_fired += 1
	attack_fired.emit(strong)
	feedback.emit("強攻撃 ×1.2" if strong else "通常攻撃", strong)
	if not equipped or job_id in ["warrior", "scout", "artisan"]:
		_melee(damage, reach)
	else:
		_launch(damage, reach, job_id)
	return true


func use_skill() -> bool:
	if not enabled or not is_instance_valid(camera):
		return false
	if not equipped:
		feedback.emit("職業スキルには武器が必要です", false)
		return false
	if _skill_cooldown > 0.0:
		feedback.emit("スキル準備中", false)
		return false
	var info: Dictionary = JOBS[job_id]
	var cost: float = float(info.cost)
	if mana < cost:
		feedback.emit("MPが足りません", false)
		return false
	mana -= cost
	_skill_cooldown = SKILL_COOLDOWN
	_attack_cooldown = maxf(_attack_cooldown, float(info.delay))
	attack_fired.emit(true)
	feedback.emit(get_skill_name(), true)
	match job_id:
		"warrior":
			_melee(36.0, float(info.range))
		"mage":
			_launch(30.0, float(info.range), "fire_explosion")
		"scout":
			# Deterministic critical strike for this training sandbox.
			_melee(32.0, float(info.range))
		"archer":
			_launch(26.0, float(info.range), "piercing_arrow")
		"cleric":
			health = minf(100.0, health + 35.0)
			_burst(camera.global_position + Vector3.DOWN * 0.5, Color("bcecc3"), 0.65)
		"artisan":
			_launch(34.0, 18.0, "bomb")
	status_changed.emit()
	return true


func _physics_process(delta: float) -> void:
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_skill_cooldown = maxf(0.0, _skill_cooldown - delta)
	if not enabled:
		return
	if mana < 100.0:
		mana = minf(100.0, mana + delta * 4.0)
	for i in range(_projectiles.size() - 1, -1, -1):
		var p: Dictionary = _projectiles[i]
		var node: Node3D = p.node
		if not is_instance_valid(node):
			_projectiles.remove_at(i)
			continue
		if p.kind == "bomb":
			p.velocity += Vector3.DOWN * 6.0 * delta
		var motion: Vector3 = p.velocity * delta
		if motion.length() > float(p.remaining):
			motion = motion.normalized() * float(p.remaining)
		var from: Vector3 = node.global_position
		var destination: Vector3 = from + motion
		var hit: Dictionary = _ray(from, destination, p.excluded)
		var remove: bool = false
		if not hit.is_empty():
			node.global_position = hit.position
			var collider: Object = hit.collider
			if collider.has_method("take_damage"):
				if p.kind not in ["bomb", "fire_explosion"]:
					collider.take_damage(float(p.damage))
				if p.kind == "piercing_arrow":
					p.excluded.append(collider.get_rid())
					# Next sweep starts exactly at contact and excludes this body.
					# It still checks walls and the next target on the next tick.
					p.remaining -= from.distance_to(hit.position)
					_burst(hit.position, Color("c9dce7"), 0.12)
					continue
			if p.kind in ["bomb", "fire_explosion"]:
				_explode(hit.position + hit.normal * 0.05, float(p.damage), 2.8)
			else:
				_burst(hit.position, _projectile_color(str(p.kind)), 0.15)
			remove = true
		else:
			node.global_position = destination
			p.remaining -= motion.length()
			if float(p.remaining) <= 0.001:
				if p.kind in ["bomb", "fire_explosion"]:
					_explode(destination, float(p.damage), 2.8)
				remove = true
		if remove:
			node.queue_free()
			_projectiles.remove_at(i)


func _melee(damage: float, reach: float) -> void:
	var origin := camera.global_position
	var end := origin - camera.global_basis.z * reach
	var hit := _ray(origin, end)
	if not hit.is_empty():
		var collider: Object = hit.collider
		if collider.has_method("take_damage"):
			collider.take_damage(damage)
		_burst(hit.position, Color("ded4b3"), 0.15)


func _launch(damage: float, reach: float, kind: String) -> void:
	if _projectiles.size() >= MAX_PROJECTILES:
		return
	var projectile := Node3D.new()
	projectile.name = "Projectile"
	add_child(projectile)
	# Start at the camera, so firing beside a wall cannot spawn beyond it.
	projectile.global_position = camera.global_position
	var direction: Vector3 = -camera.global_basis.z
	projectile.global_basis = camera.global_basis
	var arrow: bool = kind in ["archer", "piercing_arrow"]
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.035, 0.035, 0.6) if arrow else Vector3.ONE * (0.17 if kind == "bomb" else 0.13)
	visual.mesh = mesh
	visual.material_override = _material(_projectile_color(kind), not arrow)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	projectile.add_child(visual)
	if arrow:
		var tip := MeshInstance3D.new()
		var tip_mesh := BoxMesh.new()
		tip_mesh.size = Vector3(0.075, 0.075, 0.12)
		tip.mesh = tip_mesh
		tip.position.z = -0.32
		tip.material_override = _material(Color("bac8d1"))
		projectile.add_child(tip)
	var speed: float = 27.0 if arrow else 15.0
	if kind == "bomb":
		speed = 12.0
		direction = (direction + Vector3.UP * 0.12).normalized()
	_projectiles.append({"node": projectile, "kind": kind, "damage": damage,
		"velocity": direction * speed, "remaining": reach, "excluded": _owner_rids()})


func _explode(center: Vector3, damage: float, radius: float) -> void:
	_burst(center, Color("ffaf65"), radius)
	for target: Node3D in get_tree().get_nodes_in_group("practice_targets"):
		if not is_instance_valid(target) or not target.has_method("take_damage"):
			continue
		var point: Vector3 = target.global_position + Vector3.UP * 0.9
		if center.distance_to(point) > radius:
			continue
		var obstruction := _ray(center, point)
		if obstruction.is_empty() or obstruction.collider == target:
			target.take_damage(damage)


func _owner_rids() -> Array[RID]:
	var excluded: Array[RID] = []
	var ancestor: Node = get_parent()
	while ancestor != null:
		if ancestor is CollisionObject3D:
			excluded.append(ancestor.get_rid())
		ancestor = ancestor.get_parent()
	return excluded


func _ray(from: Vector3, to: Vector3, excluded: Array[RID] = []) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 3)
	query.exclude = _owner_rids() if excluded.is_empty() else excluded
	return get_world_3d().direct_space_state.intersect_ray(query)


func _projectile_color(kind: String) -> Color:
	match kind:
		"mage", "fire_explosion": return Color("ff974e")
		"cleric": return Color("eee4ac")
		"bomb": return Color("574c47")
		_: return Color("bcbba9")


func _material(color: Color, glowing: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if glowing:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.6
	return material


func _burst(point: Vector3, color: Color, radius: float) -> void:
	var effect := Node3D.new()
	add_child(effect)
	effect.global_position = point
	for i in range(6):
		var particle := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * minf(radius * 0.25, 0.16)
		particle.mesh = box
		particle.material_override = _material(color, true)
		particle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		effect.add_child(particle)
		var direction := Vector3(sin(float(i) * 2.4), 0.3 + float(i % 3) * 0.3, cos(float(i) * 2.4))
		var tween := particle.create_tween().set_parallel()
		tween.tween_property(particle, "position", direction * radius * 0.65, 0.3)
		tween.tween_property(particle, "scale", Vector3.ONE * 0.01, 0.35)
	var cleanup := get_tree().create_timer(0.4)
	cleanup.timeout.connect(effect.queue_free)
