extends Node3D
## Remote players are visual replicas; every result comes from the server.
const Figure=preload("res://scripts/frontend/characters/voxel_character.gd")
var player_id:=""
var target_position:=Vector3.ZERO
var target_yaw:=0.0
var snapshot_generation:=0
var _figure:Node3D
var _label:Label3D
var _configured_job:=""
var _configured_female:=false
var _initial:=true
var _display_name:=""
var _display_level:Variant
var _spawn_protected:=false
var _label_initialized:=false

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
	if _initial or position.distance_squared_to(target_position)>64:
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
	var display_name:=str(data.get("name",data.get("username","冒険者")))
	var level:Variant=data.get("level",1)
	if not _label_initialized or display_name!=_display_name or level!=_display_level:
		_display_name=display_name
		_display_level=level
		_label.text=display_name+"  Lv."+str(level)
	var protected_spawn:=bool(data.get("spawn_protected",false))
	if not _label_initialized or protected_spawn!=_spawn_protected:
		_spawn_protected=protected_spawn
		_label.modulate=Color("9bdab6") if protected_spawn else Color("f1ead5")
	_label_initialized=true

func _process(delta:float)->void:
	if _figure==null or not is_visible_in_tree():return
	var before:=position
	var blend:=1-exp(-delta*16)
	if before!=target_position:position=before.lerp(target_position,blend)
	if rotation.y!=target_yaw:rotation.y=lerp_angle(rotation.y,target_yaw,blend)
	_figure.animate(clampf(before.distance_to(position)/maxf(delta*5,0.001),0,1),delta)

func play_attack(strong:bool=false)->void:
	if _figure!=null:_figure.play_attack(strong)
