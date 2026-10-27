extends Node3D
## Remote players are visual replicas; every result comes from the server.
const Figure=preload("res://scripts/frontend/characters/voxel_character.gd")
var player_id:=""
var target_position:=Vector3.ZERO
var target_yaw:=0.0
var _figure:Node3D
var _label:Label3D
var _last_position:=Vector3.ZERO
var _configured_job:=""
var _configured_female:=false
var _initial:=true

func _ready()->void:
	_figure=Figure.new()
	add_child(_figure)
	_label=Label3D.new()
	_label.font=load("res://assets/frontend/ui.otf")
	_label.font_size=34
	_label.pixel_size=0.009
	_label.position.y=2.12
	_label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test=false
	add_child(_label)

func apply_snapshot(data:Dictionary)->void:
	var pos:Array=data.get("position",[0,2.15,150])
	if pos.size()!=3:return
	target_position=Vector3(float(pos[0]),float(pos[1]),float(pos[2]))
	target_yaw=float(data.get("yaw",0))
	if _initial or position.distance_to(target_position)>8:
		position=target_position
		rotation.y=target_yaw
		_initial=false
	var job:=str(data.get("job_id","warrior"))
	var female:=bool(data.get("female",false))
	if job!=_configured_job or female!=_configured_female:
		_configured_job=job
		_configured_female=female
		_figure.configure(job,female)
	visible=bool(data.get("alive",true))
	_label.text=str(data.get("name",data.get("username","冒険者")))+"  Lv."+str(data.get("level",1))
	_label.modulate=Color("9bdab6") if bool(data.get("spawn_protected",false)) else Color("f1ead5")

func _process(delta:float)->void:
	if _figure==null or not is_visible_in_tree():return
	var before:=position
	position=position.lerp(target_position,1-exp(-delta*16))
	rotation.y=lerp_angle(rotation.y,target_yaw,1-exp(-delta*16))
	_figure.animate(clampf(before.distance_to(position)/maxf(delta*5,0.001),0,1),delta)
	_last_position=position

func play_attack(strong:bool=false)->void:
	if _figure!=null:_figure.play_attack(strong)
