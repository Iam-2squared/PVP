extends CharacterBody3D
var speed_scale:=1.0
## Server-only movement against the same baked collision geometry as the client.
func _ready() -> void:
	collision_layer=2
	collision_mask=3
	floor_snap_length=0.35
	floor_max_angle=deg_to_rad(48.0)
	safe_margin=0.02
	var collider:=CollisionShape3D.new()
	var shape:=CapsuleShape3D.new()
	shape.radius=0.34
	shape.height=1.8
	collider.shape=shape
	collider.position.y=0.9
	add_child(collider)

func step(delta:float,movement:Vector2,jump:bool,sprint:bool) -> void:
	var grounded:=is_on_floor()
	var speed:=(7.2 if sprint else 4.8)*speed_scale
	velocity.x=movement.x*speed
	velocity.z=movement.y*speed
	velocity.y=velocity.y-18.0*delta if not grounded else -0.2
	if jump and grounded: velocity.y=6.0
	var horizontal:=Vector3(velocity.x,0,velocity.z)*delta
	move_and_slide()
	if grounded and not jump and velocity.y<=0.1 and is_on_wall() and horizontal.length_squared()>0.000001:
		_step_up(horizontal)

func _step_up(motion:Vector3) -> void:
	var start:=global_transform
	if test_move(start,Vector3.UP*0.55): return
	var raised:=start
	raised.origin.y+=0.55
	var forward_motion:=motion.normalized()*maxf(motion.length(),0.38)
	if test_move(raised,forward_motion): return
	var forward:=raised
	forward.origin+=forward_motion
	var landing:=KinematicCollision3D.new()
	if not test_move(forward,Vector3.DOWN*0.63,landing): return
	if landing.get_normal().y<cos(floor_max_angle): return
	var destination:=forward.origin+landing.get_travel()
	var rise:=destination.y-start.origin.y
	if rise<0.015 or rise>0.555: return
	global_position=destination
	velocity.y=-0.2
	apply_floor_snap()
