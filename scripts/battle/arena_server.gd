extends Node3D
## Dedicated authoritative WebSocket server. Clients send intent, never rewards,
## positions, damage, victim IDs or writable profile snapshots.
const Progression=preload("res://scripts/battle/progression.gd")
const Rules=preload("res://scripts/battle/arena_rules.gd")
const Pawn=preload("res://scripts/battle/server_pawn.gd")
const JOBS={
	"warrior":{"damage":18.0,"range":2.7,"delay":0.48,"cost":15.0},
	"mage":{"damage":14.0,"range":24.0,"delay":0.55,"cost":20.0},
	"scout":{"damage":14.0,"range":2.2,"delay":0.35,"cost":15.0},
	"archer":{"damage":16.0,"range":32.0,"delay":0.65,"cost":18.0},
	"cleric":{"damage":12.0,"range":22.0,"delay":0.55,"cost":20.0},
	"artisan":{"damage":20.0,"range":2.5,"delay":0.62,"cost":20.0}}
var port:=8910
var bind_address:="*"
var save_directory:="user://battle_server"
var listen_error:Error=OK
var sessions:Dictionary={}
var profiles:Dictionary={}
var world:Node3D
var _tcp:=TCPServer.new()
var _next_connection:=1
var _next_spawn:=0
var _snapshot_clock:=0.0
var _running:=false

func now() -> float:
	return Time.get_ticks_msec()/1000.0

func _ready() -> void:
	if not _load_profiles():
		listen_error=ERR_FILE_CORRUPT
		return
	world=load("res://generated/kingdom.scn").instantiate()
	add_child(world)
	Rules.close_gates(world)
	listen_error=_tcp.listen(port,bind_address)
	_running=listen_error==OK
	if _running: print("ARENA_SERVER_READY ",JSON.stringify({"port":port,"mode":"unlimited_pvp","spawn_gates":4}))
	else: push_error("Battle server listen failed: "+error_string(listen_error))

func _load_profiles() -> bool:
	var directory:=ProjectSettings.globalize_path(save_directory)
	if DirAccess.make_dir_recursive_absolute(directory)!=OK: return false
	var path:=directory.path_join("profiles.json")
	if not FileAccess.file_exists(path): return true
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("version")!=1 or not data.get("players") is Dictionary: return false
	for id:Variant in data.players:
		var entry:Variant=data.players[id]
		if not entry is Dictionary or not entry.get("token") is String or entry.token.length()!=64: return false
		var profile:Dictionary=Progression.normalize_profile(entry.get("profile"))
		if profile.is_empty() or profile.player_id!=id: return false
		profiles[id]={"token":entry.token,"profile":profile}
	return true

func _persist() -> bool:
	var directory:=ProjectSettings.globalize_path(save_directory)
	var temp:=directory.path_join("profiles.next.json")
	var file:=FileAccess.open(temp,FileAccess.WRITE)
	if file==null: return false
	file.store_string(JSON.stringify({"version":1,"players":profiles}))
	file.flush()
	file.close()
	return DirAccess.rename_absolute(temp,directory.path_join("profiles.json"))==OK

func _send(session:Dictionary,message:Dictionary) -> void:
	var peer:WebSocketPeer=session.peer
	if peer.get_ready_state()==WebSocketPeer.STATE_OPEN: peer.send_text(JSON.stringify(message))

func _error(session:Dictionary,message:String) -> void:
	_send(session,{"type":"error","message":message})

func _process(_delta:float) -> void:
	if not _running: return
	while _tcp.is_connection_available():
		var stream:=_tcp.take_connection()
		if sessions.size()>=64:
			stream.disconnect_from_host()
			continue
		var peer:=WebSocketPeer.new()
		peer.inbound_buffer_size=1048576
		peer.outbound_buffer_size=1048576
		if peer.accept_stream(stream)!=OK: continue
		sessions[_next_connection]={"peer":peer,"joined":false,"player_id":"","in_home":true,"body":null,"hp":100.0,"max_hp":100.0,"mp":100.0,"max_mp":100.0,"alive":false,"protection_until":0.0,"respawn_at":0.0,"move":Vector2.ZERO,"jump":false,"sprint":false,"yaw":0.0,"pitch":0.0,"input_seq":-1,"attack_seq":-1,"last_attack_at":-100.0,"last_skill_at":-100.0,"last_input_at":0.0,"created_at":now(),"rate_at":now(),"rate_count":0,"gate_index":0}
		_next_connection+=1
		sessions[_next_connection-1].merge({"snapshot_inflight":false,"snapshot_seq":0,"snapshot_spawn_serial":-1,"snapshot_sent_at":0.0,"awaiting_ready":false,"spawn_serial":-1})
	for connection:Variant in sessions.keys():
		if not sessions.has(connection): continue
		var session:Dictionary=sessions[connection]
		var peer:WebSocketPeer=session.peer
		peer.poll()
		if peer.get_ready_state()==WebSocketPeer.STATE_CLOSED or (not session.joined and now()-session.created_at>10):
			_drop(connection)
			continue
		while peer.get_available_packet_count()>0:
			var packet:=peer.get_packet()
			if packet.size()>8192:
				peer.close(1009,"packet too large")
				break
			if now()-session.rate_at>=1.0: session.rate_at=now(); session.rate_count=0
			session.rate_count+=1
			if session.rate_count>90: peer.close(1008,"rate limit"); break
			var message:Variant=JSON.parse_string(packet.get_string_from_utf8())
			if message is Dictionary: _message(connection,session,message)

func _message(connection:int,session:Dictionary,message:Dictionary) -> void:
	var type:=str(message.get("type",""))
	if type=="join":
		_join(connection,session,message)
		return
	if not session.joined: return
	match type:
		"enter":
			if not session.in_home: return
			session.in_home=false
			_spawn(session)
			_send(session,{"type":"entered","profile":_profile(session),"in_home":false})
		"home":
			_remove_body(session)
			session.in_home=true
			session.alive=false
			session.snapshot_inflight=false
			_send(session,{"type":"profile","profile":_profile(session),"in_home":true})
		"snapshot_ack":
			var seq:Variant=message.get("seq",-1)
			if _number(seq) and session.snapshot_inflight and seq==session.snapshot_seq:
				session.snapshot_inflight=false
				if session.awaiting_ready and session.snapshot_spawn_serial==session.spawn_serial and session.alive and is_instance_valid(session.body):
					session.awaiting_ready=false
					session.protection_until=now()+3.0
					session.body.collision_layer=2
		"allocate":
			if not session.in_home: _error(session,"能力値の配分はホームで行ってください"); return
			var updated:Dictionary=Progression.allocate(_profile(session),str(message.get("stat","")),message.get("points",1))
			if updated.is_empty(): _error(session,"使えるポイントまたは配分先を確認してください"); return
			if _save_profile(session.player_id,updated): _send(session,{"type":"profile","profile":updated,"in_home":true})
			else: _error(session,"保存できませんでした。もう一度お試しください")
		"input": _input_intent(session,message)
		"attack": _attack(session,message)
		"ping": _send(session,{"type":"pong"})
		_: _error(session,"未対応の操作です")

func _join(connection:int,session:Dictionary,message:Dictionary) -> void:
	if session.joined: return
	var id:=str(message.get("player_id",""))
	if not _valid_id(id): _error(session,"プレイヤーIDが無効です"); return
	var token:=str(message.get("token",""))
	if profiles.has(id):
		if token!=profiles[id].token: _error(session,"認証情報が一致しません"); return
	else:
		if not token.is_empty(): _error(session,"このサーバーにプレイヤーが登録されていません"); return
		var job:=str(message.get("job_id","warrior"))
		if not Progression.JOBS.has(job): job="warrior"
		var profile:Dictionary=Progression.new_profile(id,str(message.get("username","冒険者")),job,bool(message.get("female",false)))
		token=Crypto.new().generate_random_bytes(32).hex_encode()
		profiles[id]={"token":token,"profile":profile}
		if not _persist(): profiles.erase(id); _error(session,"プレイヤーを保存できませんでした"); return
	for other:Variant in sessions.keys():
		if other!=connection and sessions[other].player_id==id: _drop(other)
	session.player_id=id
	session.joined=true
	session.in_home=bool(message.get("in_home",true))
	if not session.in_home: _spawn(session)
	_send(session,{"type":"welcome","player_id":id,"token":token,"profile":_profile(session),"in_home":session.in_home})

func _profile(session:Dictionary) -> Dictionary:
	return profiles[session.player_id].profile.duplicate(true)

func _save_profile(id:String,profile:Dictionary) -> bool:
	var old:Dictionary=profiles[id].profile
	profiles[id].profile=profile
	if _persist(): return true
	profiles[id].profile=old
	return false

func _input_intent(session:Dictionary,message:Dictionary) -> void:
	if session.in_home or not session.alive or session.awaiting_ready: return
	var seq:Variant=message.get("seq",-1)
	var move:Variant=message.get("move")
	var yaw:Variant=message.get("yaw")
	var pitch:Variant=message.get("pitch")
	if not _number(seq) or seq!=floorf(seq) or seq<=session.input_seq: return
	if not move is Array or move.size()!=2 or not _number(move[0]) or not _number(move[1]) or not _number(yaw) or not _number(pitch): return
	session.input_seq=seq
	session.move=Vector2(move[0],move[1]).limit_length(1.0)
	session.yaw=wrapf(float(yaw),-PI,PI)
	session.pitch=clampf(float(pitch),-1.45,1.45)
	session.jump=session.jump or message.get("jump",false)==true
	session.sprint=message.get("sprint",false)==true
	session.last_input_at=now()

func _number(value:Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and absf(float(value))<1.0e12

func _valid_id(id:String) -> bool:
	if id.length()<8 or id.length()>128: return false
	for c in id.to_utf8_buffer():
		if not ((c>=48 and c<=57) or (c>=65 and c<=90) or (c>=97 and c<=122) or c==45 or c==95): return false
	return true

func _spawn(session:Dictionary) -> void:
	_remove_body(session)
	var body:=Pawn.new()
	body.name="ServerPawn_"+str(_next_spawn)
	add_child(body)
	session.gate_index=_next_spawn%4
	session.spawn_serial=_next_spawn
	_next_spawn+=1
	body.position=Rules.spawn_points()[session.gate_index]
	session.body=body
	session.last_safe=body.position
	# North opens onto the palace's rear service road; face along that road.
	session.yaw=[0.0,-PI*0.5,PI*0.5,PI*0.5][session.gate_index]
	var stats:Dictionary=_profile(session).stats
	body.speed_scale=clampf(1.0+(float(stats["敏捷力"])-10.0)*0.002,1.0,1.3)
	session.last_damage_at=-10.0
	session.max_hp=float(stats.HP)
	session.hp=session.max_hp
	session.max_mp=float(stats.MP)
	session.mp=session.max_mp
	session.alive=true
	session.awaiting_ready=true
	session.snapshot_inflight=false
	session.body.collision_layer=0
	session.protection_until=now()+3.0
	session.move=Vector2.ZERO
	session.jump=false
	session.last_input_at=0.0

func _remove_body(session:Dictionary) -> void:
	if is_instance_valid(session.body):
		session.body.collision_layer=0
		session.body.collision_mask=0
		session.body.queue_free()
	session.body=null
	session.move=Vector2.ZERO
	session.jump=false

func _physics_process(delta:float) -> void:
	if not _running: return
	for session:Dictionary in sessions.values():
		if not session.joined or session.in_home: continue
		if session.awaiting_ready and now()-session.protection_until>120.0:
			session.peer.close(1008,"loading timeout")
			continue
		if not session.alive:
			if now()>=session.respawn_at: _spawn(session)
			continue
		var movement:Vector2=session.move if not session.awaiting_ready and now()-session.last_input_at<0.6 else Vector2.ZERO
		session.body.step(delta,movement,session.jump,session.sprint)
		session.jump=false
		var safe:=Rules.safe_position(session.body.position,session.last_safe,session.gate_index)
		if safe!=session.body.position: session.body.position=safe; session.body.velocity=Vector3.ZERO
		session.last_safe=session.body.position
		var recovery:float=float(profiles[session.player_id].profile.stats["回復力"])
		session.mp=minf(session.max_mp,session.mp+(4.0+maxf(0.0,recovery-10.0)*0.15)*delta)
		if now()-float(session.get("last_damage_at",0.0))>=5.0:
			session.hp=minf(session.max_hp,session.hp+recovery*0.1*delta)
	_snapshot_clock+=delta
	if _snapshot_clock>=0.1:
		_snapshot_clock=0.0
		_snapshot()

func _snapshot() -> void:
	var players:Array=[]
	for session:Dictionary in sessions.values():
		if not session.joined or session.in_home or not is_instance_valid(session.body): continue
		var p:Vector3=session.body.position
		var profile:=_profile(session)
		players.append({"id":session.player_id,"name":profile.username,"level":profile.level,"spawn_serial":session.spawn_serial,"position":[p.x,p.y,p.z],"yaw":session.yaw,"job_id":profile.job_id,"female":profile.female,"hp":session.hp,"max_hp":session.max_hp,"mp":session.mp,"max_mp":session.max_mp,"alive":session.alive,"spawn_protected":session.awaiting_ready or now()<session.protection_until,"kills":profile.kills,"deaths":profile.deaths})
	for session:Dictionary in sessions.values():
		if session.joined and not session.in_home and not session.snapshot_inflight:
			session.snapshot_seq+=1
			session.snapshot_spawn_serial=session.spawn_serial
			session.snapshot_sent_at=now()
			session.snapshot_inflight=true
			_send(session,{"type":"snapshot","seq":session.snapshot_seq,"players":players,"profile":_profile(session),"in_home":false})

func _attack(session:Dictionary,message:Dictionary) -> void:
	if session.in_home or not session.alive or session.awaiting_ready or not is_instance_valid(session.body): return
	var seq:Variant=message.get("seq",-1)
	if not _number(seq) or seq!=floorf(seq) or seq<=session.attack_seq: return
	session.attack_seq=seq
	var profile:=_profile(session)
	var job:String=profile.job_id
	var tuning:Dictionary=JOBS[job]
	var skill:bool=message.get("skill",false)==true
	if now()-session.last_attack_at<float(tuning.delay): return
	if skill and (now()-session.last_skill_at<3.0 or session.mp<float(tuning.cost)): return
	session.last_attack_at=now()
	session.protection_until=0.0
	if skill:
		session.last_skill_at=now()
		session.mp-=float(tuning.cost)
		if job=="cleric": session.hp=minf(session.max_hp,session.hp+35.0+float(profile.stats["精神力"])); return
	var damage:=float(tuning.damage)+maxf(0.0,float(profile.stats["筋力"])-10.0)*0.65
	if job in ["archer","scout","artisan"]: damage+=maxf(0.0,float(profile.stats["器用さ"])-10.0)*0.65
	if job in ["mage","cleric"]: damage+=maxf(0.0,float(profile.stats["MP"])-100.0)*0.15
	if skill: damage*=2.0
	elif message.get("strong",false)==true: damage*=1.2
	var eye:Vector3=session.body.position+Vector3.UP*1.65
	var direction:=Vector3(-sin(session.yaw)*cos(session.pitch),sin(session.pitch),-cos(session.yaw)*cos(session.pitch))
	var ranged:bool=job in ["mage","archer","cleric"] or (skill and job=="artisan")
	var reach:float=18.0 if skill and job=="artisan" else float(tuning.range)
	_broadcast_event({"kind":"attack","player_id":session.player_id,"job_id":job,"strong":message.get("strong",false)==true,"skill":skill,"origin":[eye.x,eye.y,eye.z],"direction":[direction.x,direction.y,direction.z],"range":reach})
	if ranged:
		var ray:=PhysicsRayQueryParameters3D.create(eye,eye+direction*reach)
		ray.exclude=[session.body.get_rid()]
		var hit:=get_world_3d().direct_space_state.intersect_ray(ray)
		if skill and job in ["mage","artisan"]:
			var impact:Vector3=hit.position+hit.normal*0.08 if not hit.is_empty() else eye+direction*reach
			_area_damage(session,impact,3.5 if job=="mage" else 3.0,damage,job=="mage")
			return
		if skill and job=="archer":
			# Pierce real player bodies along the ray; solid architecture stops it.
			for _i in range(sessions.size()):
				if hit.is_empty(): break
				var target:=_session_for_body(hit.collider)
				if target.is_empty(): break
				_damage(session,target,damage,false)
				ray.exclude=ray.exclude+[target.body.get_rid()]
				hit=get_world_3d().direct_space_state.intersect_ray(ray)
			return
		if not hit.is_empty():
			for victim:Dictionary in sessions.values():
				if victim!=session and victim.joined and not victim.in_home and victim.alive and victim.body==hit.collider:
					_damage(session,victim,damage,job in ["mage","cleric"])
					break
		return
	var candidates:Array=[]
	for victim:Dictionary in sessions.values():
		if victim==session or not victim.joined or victim.in_home or not victim.alive or not is_instance_valid(victim.body): continue
		var target:Vector3=victim.body.position+Vector3.UP*1.0
		var delta:=target-eye
		if delta.length()>reach or delta.length()<0.01: continue
		if direction.dot(delta.normalized())<(0.992 if ranged else 0.55): continue
		var query:=PhysicsRayQueryParameters3D.create(eye,target)
		query.exclude=[session.body.get_rid()]
		var hit:=get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider==victim.body: candidates.append({"session":victim,"distance":delta.length()})
	candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.distance<b.distance)
	if candidates.is_empty(): return
	var victim:Dictionary=candidates[0].session
	_damage(session,victim,damage,job in ["mage","cleric"])

func _session_for_body(body:Object) -> Dictionary:
	for session:Dictionary in sessions.values():
		if session.joined and not session.in_home and session.alive and session.body==body: return session
	return {}

func _area_damage(attacker:Dictionary,center:Vector3,radius:float,damage:float,magic:bool) -> void:
	for victim:Dictionary in sessions.values():
		if victim==attacker or not victim.joined or victim.in_home or not victim.alive or not is_instance_valid(victim.body): continue
		var target:Vector3=victim.body.position+Vector3.UP
		if center.distance_to(target)>radius: continue
		var query:=PhysicsRayQueryParameters3D.create(center,target)
		query.collision_mask=1
		query.exclude=[attacker.body.get_rid()]
		var hit:=get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.collider==victim.body: _damage(attacker,victim,damage,magic)

func _damage(attacker:Dictionary,victim:Dictionary,amount:float,magic:bool) -> void:
	if not victim.alive or victim.awaiting_ready or now()<victim.protection_until: return
	var stat:Dictionary=_profile(victim).stats
	var armor:=float(stat["精神力"] if magic else stat["耐久力"])*0.1
	victim.hp=maxf(0.0,victim.hp-maxf(1.0,amount-armor))
	victim.last_damage_at=now()
	_broadcast_event({"kind":"hit","player_id":attacker.player_id,"victim_id":victim.player_id,"damage":maxf(1.0,amount-armor)})
	if victim.hp>0.0: return
	# Flip the life state before processing any further attack in this frame.
	victim.alive=false
	victim.respawn_at=now()+2.0
	victim.body.collision_layer=0
	victim.body.collision_mask=0
	victim.body.velocity=Vector3.ZERO
	victim.move=Vector2.ZERO
	var loser:=_profile(victim)
	loser.deaths+=1
	var winner:=Progression.award_player_kill(_profile(attacker),loser.level)
	var old_loser:Dictionary=profiles[victim.player_id].profile
	var old_winner:Dictionary=profiles[attacker.player_id].profile
	profiles[victim.player_id].profile=loser
	if not winner.is_empty(): profiles[attacker.player_id].profile=winner
	if not _persist():
		profiles[victim.player_id].profile=old_loser
		profiles[attacker.player_id].profile=old_winner
		_error(attacker,"撃破記録を保存できませんでした")
	else:
		_send(attacker,{"type":"kill","victim":victim.player_id,"profile":winner,"exp_gained":int(loser.level)*100})
		_send(victim,{"type":"death","killer":attacker.player_id,"profile":loser,"respawn_seconds":2})
		_send(attacker,{"type":"event","kind":"kill","player_id":attacker.player_id,"profile":winner,"message":"撃破！ +%d EXP"%(int(loser.level)*100)})
		_send(victim,{"type":"event","kind":"death","profile":loser,"message":"倒されました · 門の内側で復活します"})

func _broadcast_event(event:Dictionary) -> void:
	var packet:=event.duplicate(true)
	packet["type"]="event"
	for session:Dictionary in sessions.values():
		# Cosmetic bursts are dispensable while a renderer is catching up.
		if session.joined and not session.in_home and not session.awaiting_ready and (not session.snapshot_inflight or now()-session.snapshot_sent_at<0.5): _send(session,packet)

func _drop(connection:int) -> void:
	if not sessions.has(connection): return
	var session:Dictionary=sessions[connection]
	_remove_body(session)
	session.peer.close()
	sessions.erase(connection)

func shutdown() -> void:
	_running=false
	_tcp.stop()
	for connection:Variant in sessions.keys(): _drop(connection)

func _exit_tree() -> void:
	shutdown()
