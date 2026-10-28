extends Node3D
## Persistent WebSocket session: the home and arena share one authoritative profile.
signal home_requested(profile:Dictionary)
signal profile_received(profile:Dictionary)
signal identity_received(identity:Dictionary)
signal connection_failed(message:String)
signal operation_failed(message:String)
signal battle_started
const Rules=preload("res://scripts/battle/arena_rules.gd")
const LocalPlayer=preload("res://scripts/battle/arena_local_player.gd")
const Actor=preload("res://scripts/battle/arena_actor.gd")
var world:Node3D
var player:CharacterBody3D
var profile:Dictionary={}
var identity:Dictionary={}
var server_url:=""
var _socket:WebSocketPeer
var _welcomed:=false
var _in_home:=true
var _failed:=false
var _my_id:=""
var _seq:=0
var _input_clock:=0.0
var _connect_clock:=0.0
var _actors:Dictionary={}
var _requesting_home:=false
var _enter_pending:=false
var _last_event_id:=""
var _projectiles:Array[Dictionary]=[]
var _snapshot_ack_pending:=false
var _pending_snapshot_seq:=-1
var _connection_generation:=0
var _snapshot_generation:=0
var _stale_actor_ids:Array[String]=[]
var _arrow_mesh:BoxMesh
var _orb_mesh:SphereMesh
var _arrow_material:StandardMaterial3D
var _orb_material:StandardMaterial3D

func start_connection(url:String,new_identity:Dictionary)->void:
	if _socket!=null:_socket.close()
	identity=new_identity.duplicate(true)
	identity.erase("_join_sent")
	server_url=url.strip_edges()
	_my_id=str(identity.get("player_id",""))
	_welcomed=false
	_in_home=true
	_failed=false
	_requesting_home=false
	_enter_pending=false
	_connect_clock=0
	_seq=0
	_connection_generation+=1
	_snapshot_ack_pending=false
	_pending_snapshot_seq=-1
	_socket=WebSocketPeer.new()
	_socket.inbound_buffer_size=1048576
	_socket.outbound_buffer_size=1048576
	var error:=_socket.connect_to_url(server_url)
	if error!=OK:_fail("対戦サーバーへ接続できませんでした (%d)"%error)

func is_connected_to_server()->bool:
	return _welcomed and _socket!=null and _socket.get_ready_state()==WebSocketPeer.STATE_OPEN

func is_in_home()->bool:
	return _in_home

func enter_battle()->void:
	if not is_connected_to_server():
		operation_failed.emit("対戦サーバーへの接続を確認してください")
		return
	if not _in_home or _enter_pending:return
	_enter_pending=true
	_send({"type":"enter"})

func request_home()->void:
	if _in_home or _requesting_home:return
	_requesting_home=true
	if player!=null:
		player.set_active(false)
		player.hud.visible=true
		player.hud.connection_text="ホームへ戻っています…"
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	_send({"type":"input","seq":_next_seq(),"move":[0,0],"yaw":0,"pitch":0,"jump":false,"sprint":false})
	_send({"type":"home"})

func request_allocate(stat:String,points:int=1)->void:
	if not is_connected_to_server() or not _in_home:
		operation_failed.emit("能力値への振り分けはホームで行ってください")
		return
	_send({"type":"allocate","stat":stat,"points":points})

func close_connection()->void:
	if _socket!=null:_socket.close()
	_welcomed=false
	_in_home=true
	_failed=true
	_hide_battle()

func _exit_tree()->void:
	if _socket!=null:_socket.close()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func _process(delta:float)->void:
	_update_shots(delta)
	if _socket==null or _failed:return
	_socket.poll()
	var state:=_socket.get_ready_state()
	if state==WebSocketPeer.STATE_CONNECTING:
		_connect_clock+=delta
		if _connect_clock>12:_fail("対戦サーバーに接続できません。サーバーの起動と接続先を確認してください")
		return
	if state==WebSocketPeer.STATE_CLOSED:
		_fail("対戦サーバーとの接続が切れました。ホームから再接続できます")
		return
	if state!=WebSocketPeer.STATE_OPEN:return
	if not _welcomed:
		_connect_clock+=delta
		if _connect_clock>15:_fail("接続が完了しませんでした。ホームから再接続してください")
	if not bool(identity.get("_join_sent",false)):
		var join:=identity.duplicate(true)
		join.erase("_join_sent")
		join["type"]="join"
		join["in_home"]=true
		_send(join)
		identity["_join_sent"]=true
	var packets:=0
	while _socket.get_available_packet_count()>0 and packets<64:
		packets+=1
		var payload=_socket.get_packet()
		if payload.size()>262144:continue
		var value=JSON.parse_string(payload.get_string_from_utf8())
		if value is Dictionary:_handle_message(value)
	if not _in_home and _welcomed and player!=null and player.active and not _requesting_home:
		_input_clock-=delta
		if _input_clock<=0:
			_input_clock=0.05
			var input:Dictionary=player.input_packet()
			input["type"]="input"
			input["seq"]=_next_seq()
			_send(input)

func _next_seq()->int:
	_seq+=1
	return _seq

func _send(message:Dictionary)->void:
	if _socket!=null and _socket.get_ready_state()==WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(message))

func _handle_message(message:Dictionary)->void:
	var type:=str(message.get("type",""))
	match type:
		"welcome":
			_welcomed=true
			_in_home=bool(message.get("in_home",true))
			_my_id=str(message.get("player_id",identity.get("player_id","")))
			identity["player_id"]=_my_id
			if message.has("token"):identity["token"]=str(message["token"])
			identity.erase("_join_sent")
			# The flag is private to this socket; do not leak it into persisted identity.
			identity_received.emit(identity.duplicate(true))
			identity["_join_sent"]=true
			_apply_profile(message.get("profile",{}),true)
			if not _in_home:_show_battle()
		"entered":
			_enter_pending=false
			_in_home=false
			_requesting_home=false
			_apply_profile(message.get("profile",{}),true)
			_show_battle()
		"profile":
			_apply_profile(message.get("profile",{}),true)
			if message.has("in_home"):
				var was_home:=_in_home
				_in_home=bool(message["in_home"])
				if _in_home:
					_requesting_home=false
					_enter_pending=false
					_hide_battle()
					if not was_home:home_requested.emit(profile.duplicate(true))
		"snapshot":
			_apply_snapshot(message)
			_ack_snapshot_after_render(int(message.get("seq",-1)))
		"error":
			_enter_pending=false
			var text:=str(message.get("message","操作を完了できませんでした"))
			if not _welcomed:_fail(text)
			else:
				if player!=null:player.hud.show_feedback(text)
				operation_failed.emit(text)
		"event":_apply_event(message)
		"kill":
			_apply_profile(message.get("profile",{}),true)
			if player!=null:player.hud.show_feedback("撃破！ +%d EXP"%int(message.get("exp_gained",0)),true)
		"death":
			_apply_profile(message.get("profile",{}),true)
			if player!=null:
				player.set_active(false)
				player.hud.visible=true
				player.hud.alive=false
				player.hud.show_feedback("倒されました · 門の内側でリスポーンします")

func _apply_profile(value:Variant,force:bool=false)->void:
	if not value is Dictionary or value.is_empty():return
	if not force and profile==value:return
	profile=value.duplicate(true)
	if player!=null:player.configure_profile(profile)
	profile_received.emit(profile.duplicate(true))

func _show_battle()->void:
	_ensure_world()
	Input.emulate_mouse_from_touch=false
	visible=true
	world.visible=true
	player._presentation_visible=true
	player.camera.current=true
	player.prepare_spawn()
	player.configure_profile(profile)
	player.hud.alive=true
	player.hud.connection_text="リスポーン地点を確認しています…"
	_input_clock=0
	battle_started.emit()

func _hide_battle()->void:
	Input.emulate_mouse_from_touch=true
	visible=false
	if world!=null:world.visible=false
	if player!=null:
		player._presentation_visible=false
		player.set_active(false)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func _ensure_world()->void:
	if world!=null:return
	_lighting()
	world=load("res://generated/kingdom.scn").instantiate()
	add_child(world)
	world.set_meta("environment_preview",false)
	world.set_meta("world_extent",160.0)
	Rules.close_gates(world)
	player=LocalPlayer.new()
	player.name="ArenaPlayer"
	player.world=world
	player.job_id=str(profile.get("job_id","warrior"))
	add_child(player)
	player.position=Rules.spawn_points()[0]
	player.configure_profile(profile)
	player.attack_requested.connect(_send_attack)
	player.home_requested.connect(request_home)

func _send_attack(strong:bool,skill:bool)->void:
	if _in_home or _requesting_home:return
	_send({"type":"attack","strong":strong,"skill":skill,"seq":_next_seq()})

func _apply_snapshot(message:Dictionary)->void:
	if message.has("profile"):_apply_profile(message["profile"])
	if _in_home:return
	_ensure_world()
	_snapshot_generation+=1
	var players:Array=message.get("players",[])
	for data:Dictionary in players:
		var id:=str(data.get("id",""))
		if id==_my_id:
			player.reconcile(data)
			if _requesting_home:player.set_active(false);player.hud.visible=true
			player.hud.set_battle_status(data,players.size())
			if data.has("profile"):_apply_profile(data["profile"])
		else:
			if not _actors.has(id):
				var actor:=Actor.new()
				actor.player_id=id
				add_child(actor)
				_actors[id]=actor
			var actor:Node3D=_actors[id]
			actor.snapshot_generation=_snapshot_generation
			actor.apply_snapshot(data)
	_stale_actor_ids.clear()
	for id:String in _actors:
		if _actors[id].snapshot_generation!=_snapshot_generation:_stale_actor_ids.append(id)
	for id in _stale_actor_ids:
		_actors[id].queue_free()
		_actors.erase(id)
	for event in message.get("events",[]):
		if event is Dictionary:_apply_event(event)

func _apply_event(event:Dictionary)->void:
	if player==null:return
	var kind:=str(event.get("kind",event.get("event","")))
	var actor_id:=str(event.get("player_id",event.get("actor_id",event.get("attacker_id",""))))
	if kind=="attack":
		if _actors.has(actor_id):_actors[actor_id].play_attack(bool(event.get("strong",false)))
		if float(event.get("range",0))>4.5:_show_shot(event)
	elif kind=="hit":
		if actor_id==_my_id:player.hud.show_feedback("命中 · %d ダメージ"%int(event.get("damage",0)))
		elif str(event.get("victim_id",""))==_my_id:player.hud.show_feedback("被弾 · %d ダメージ"%int(event.get("damage",0)))
	if event.has("message"):player.hud.show_feedback(str(event["message"]),kind in ["kill","level_up"])

func _fail(message:String)->void:
	if _failed:return
	_failed=true
	_welcomed=false
	_in_home=true
	_enter_pending=false
	_requesting_home=false
	if _socket!=null:_socket.close()
	_hide_battle()
	connection_failed.emit(message)

func _lighting()->void:
	var sky_material:=ProceduralSkyMaterial.new()
	sky_material.sky_top_color=Color("649fc7")
	sky_material.sky_horizon_color=Color("d0dfdf")
	sky_material.ground_bottom_color=Color("a19070")
	var sky:=Sky.new()
	sky.sky_material=sky_material
	var environment:=Environment.new()
	environment.background_mode=Environment.BG_SKY
	environment.sky=sky
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("d3e2ed")
	environment.ambient_light_energy=0.42
	var world_environment:=WorldEnvironment.new()
	world_environment.environment=environment
	add_child(world_environment)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-43,-28,0)
	sun.light_color=Color("fff5e5")
	sun.light_energy=0.78
	sun.shadow_enabled=true
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance=120
	sun.shadow_bias=0.18
	sun.shadow_normal_bias=2
	add_child(sun)

func _show_shot(event:Dictionary)->void:
	if _in_home or world==null or _projectiles.size()>=24:return
	var origin:Array=event.get("origin",[])
	var direction:Array=event.get("direction",[])
	if origin.size()!=3 or direction.size()!=3:return
	var from:=Vector3(float(origin[0]),float(origin[1]),float(origin[2]))
	var forward:=Vector3(float(direction[0]),float(direction[1]),float(direction[2])).normalized()
	if not from.is_finite() or not forward.is_finite() or forward.length_squared()<0.5:return
	var reach:=clampf(float(event.get("range",20)),0,40)
	var query:=PhysicsRayQueryParameters3D.create(from,from+forward*reach)
	query.collision_mask=1
	query.exclude=[player.get_rid()]
	var hit:=world.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():reach=from.distance_to(hit.position)
	var visual:=MeshInstance3D.new()
	var job:=str(event.get("job_id","mage"))
	_ensure_shot_resources()
	visual.mesh=_arrow_mesh if job=="archer" else _orb_mesh
	visual.material_override=_arrow_material if job=="archer" else _orb_material
	visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	visual.position=from
	if absf(forward.dot(Vector3.UP))<0.995:visual.look_at(from+forward,Vector3.UP)
	_projectiles.append({"node":visual,"direction":forward,"remaining":reach,"life":1.2})

func _ensure_shot_resources()->void:
	if _arrow_mesh!=null:return
	_arrow_mesh=BoxMesh.new()
	_arrow_mesh.size=Vector3(0.035,0.035,0.65)
	_orb_mesh=SphereMesh.new()
	_orb_mesh.radius=0.13
	_orb_mesh.height=0.26
	_orb_mesh.radial_segments=8
	_orb_mesh.rings=4
	_arrow_material=StandardMaterial3D.new()
	_arrow_material.albedo_color=Color("e3c78e")
	_arrow_material.emission=_arrow_material.albedo_color
	_arrow_material.emission_energy_multiplier=0.7
	_arrow_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	_orb_material=StandardMaterial3D.new()
	_orb_material.albedo_color=Color("f7b45d")
	_orb_material.emission_enabled=true
	_orb_material.emission=_orb_material.albedo_color
	_orb_material.emission_energy_multiplier=0.7
	_orb_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED

func _update_shots(delta:float)->void:
	for index in range(_projectiles.size()-1,-1,-1):
		var shot:Dictionary=_projectiles[index]
		var visual:Node3D=shot.node
		shot.life-=delta
		var travel:=minf(float(shot.remaining),delta*45)
		if is_instance_valid(visual):visual.position+=shot.direction*travel
		shot.remaining-=travel
		if shot.life<=0 or shot.remaining<=0.01 or _in_home:
			if is_instance_valid(visual):visual.queue_free()
			_projectiles.remove_at(index)

func _ack_snapshot_after_render(seq:int)->void:
	if seq<0:return
	_pending_snapshot_seq=seq
	if _snapshot_ack_pending:return
	_snapshot_ack_pending=true
	var generation:=_connection_generation
	var socket:=_socket
	# Backpressure follows rendered frames rather than network arrival. A slow
	# or background browser cannot accumulate snapshots while its canvas stalls.
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
	if generation!=_connection_generation:return
	var acknowledged:=_pending_snapshot_seq
	_pending_snapshot_seq=-1
	_snapshot_ack_pending=false
	if socket==_socket and is_connected_to_server():
		_send({"type":"snapshot_ack","seq":acknowledged})
