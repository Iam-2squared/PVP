extends SceneTree
## Class-specific combat travels over real sockets and hits saved city colliders.
## Level fixtures use the real progression helper; stat spending uses the normal
## home protocol. No client reward, teleport or damage API is introduced.
const WireSupport=preload("res://tools/test_battle_server.gd")
const Progression=preload("res://scripts/battle/progression.gd")
var checks:=0
var failures:Array[String]=[]
var _server:Node3D
var _clients:Array=[]
var _expected_profiles:Dictionary={}
var _port:=0

func _initialize()->void:
	_run.call_deferred()

func _check(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures.append(message)
		push_error(message)

func _frames(count:int=1)->void:
	for i in range(count):
		await physics_frame
		for client in _clients:client.poll()

func _wait(condition:Callable,timeout:float=5.0)->bool:
	var until:=Time.get_ticks_msec()+int(timeout*1000)
	while Time.get_ticks_msec()<until:
		if condition.call():return true
		await _frames()
	return false

func _session(client:RefCounted)->Dictionary:
	for session:Dictionary in _server.sessions.values():
		if str(session.get("player_id",""))==str(client.identity.get("player_id","")):return session
	return {}

func _profile(client:RefCounted)->Dictionary:
	return _server.profiles[str(client.identity["player_id"])]["profile"].duplicate(true)

func _connect(job:String)->RefCounted:
	var client=WireSupport.WireClient.new()
	_clients.append(client)
	var id:="combat_user_"+job
	if client.socket.connect_to_url("ws://127.0.0.1:%d"%_port)!=OK:
		_check(false,"Class user could not start a connection: "+job)
		return null
	if not await _wait(func()->bool:return client.socket.get_ready_state()==WebSocketPeer.STATE_OPEN):
		_check(false,"Class user WebSocket handshake timed out: "+job)
		return null
	client.send({"type":"join","player_id":id,"token":"","username":"職業検証","job_id":job,"female":false,"in_home":true})
	if not await _wait(func()->bool:return not client.identity.is_empty()):
		_check(false,"Class user did not receive an identity: "+job)
		return null
	_check(_profile(client).job_id==job,"Real network profile uses class "+job)
	_expected_profiles[id]=_profile(client)
	return client

func _enter(client:RefCounted)->Dictionary:
	client.send({"type":"enter"})
	var ready:=await _wait(func()->bool:return not _session(client).get("in_home",true) and not _session(client).get("awaiting_ready",true))
	if not ready:
		_check(false,"Class life did not acknowledge its first snapshot")
		return {}
	return _session(client)

func _home(client:RefCounted)->void:
	client.send({"type":"home"})
	if not await _wait(func()->bool:return bool(_session(client).get("in_home",false))):
		_check(false,"Class user failed to return home")

func _place(session:Dictionary,position:Vector3,hp:float=100.0)->void:
	session.body.position=position
	session.body.velocity=Vector3.ZERO
	session.last_safe=position
	session.move=Vector2.ZERO
	session.hp=minf(hp,float(session.max_hp))
	session.last_damage_at=_server.now()
	session.protection_until=0.0

func _aim(client:RefCounted,target:Dictionary,aim_height:float=1.0)->void:
	var actor:=_session(client)
	var eye:Vector3=actor.body.position+Vector3.UP*1.65
	var destination:Vector3=target.body.position+Vector3.UP*aim_height
	var direction:=destination-eye
	client.input_seq+=1
	var seq:int=client.input_seq
	client.send({"type":"input","seq":seq,"move":[0,0],"yaw":atan2(-direction.x,-direction.z),"pitch":atan2(direction.y,Vector2(direction.x,direction.z).length()),"jump":false,"sprint":false})
	if not await _wait(func()->bool:return int(actor.input_seq)>=seq):
		_check(false,"Authoritative aim input was not accepted")

func _fire(client:RefCounted,strong:bool=false,skill:bool=false,duplicate_burst:bool=false)->void:
	var actor:=_session(client)
	var delay:float=_server.JOBS[str(_profile(client).job_id)].delay
	if not await _wait(func()->bool:return float(_server.now())>=float(actor.last_attack_at)+delay+0.03):
		_check(false,"Class attack cooldown did not complete")
		return
	if skill and not await _wait(func()->bool:return float(_server.now())>=float(actor.last_skill_at)+3.03):
		_check(false,"Class skill cooldown did not complete")
		return
	client.attack_seq+=1
	var packet:={"type":"attack","seq":client.attack_seq,"strong":strong,"skill":skill}
	client.send(packet)
	if duplicate_burst:
		client.send(packet)
		client.attack_seq+=1
		client.send({"type":"attack","seq":client.attack_seq,"strong":strong,"skill":skill})
	var last_seq:int=client.attack_seq
	if not await _wait(func()->bool:return int(actor.attack_seq)>=last_seq):
		_check(false,"Class attack packet was not processed")
	await _frames(3)

func _open_duel(client:RefCounted,target:Dictionary,distance:float=12.0)->Dictionary:
	var actor:=_session(client)
	_place(actor,Vector3(0,2.15,112))
	_place(target,Vector3(0,2.15,112-distance))
	await _frames(3)
	await _aim(client,target)
	return actor

func _earn_and_spend(client:RefCounted,allocation:Dictionary)->void:
	await _home(client)
	# A legitimate earned-level snapshot is a server-owned test fixture. The
	# network interface still has no method for a client to grant this reward.
	var earned:=Progression.award_player_kill(_profile(client),1)
	if earned.is_empty() or not _server._save_profile(str(client.identity.player_id),earned):
		_check(false,"Server-owned earned-level fixture could not be saved")
		return
	for stat:String in allocation:
		var count:int=allocation[stat]
		client.send({"type":"allocate","stat":stat,"points":count})
		if not await _wait(func()->bool:return int(_profile(client).allocations[stat])==count):
			_check(false,"Real home allocation request was rejected: "+stat)
	_expected_profiles[str(client.identity.player_id)]=_profile(client)
	await _enter(client)

func _run()->void:
	Engine.max_fps=120
	_port=23000+int(Time.get_ticks_usec()%10000)
	_server=load("res://scripts/battle/arena_server.gd").new()
	_server.port=_port
	_server.save_directory=OS.get_user_data_dir().path_join("test_class_combat_%d"%Time.get_ticks_usec())
	root.add_child(_server)
	await _frames(8)
	_check(_server.listen_error==OK,"Class combat server starts against the accepted city")
	if _server.listen_error!=OK:_finish();return
	var victim:=await _connect("warrior")
	var mage:=await _connect("mage")
	var archer:=await _connect("archer")
	var cleric:=await _connect("cleric")
	var scout:=await _connect("scout")
	var artisan:=await _connect("artisan")
	for client in [victim,mage,archer,cleric,scout,artisan]:
		if client==null:_finish();return
	var target:=await _enter(victim)
	await _enter(mage)
	await _open_duel(mage,target)
	await _fire(mage)
	_check(float(target.hp)<float(target.max_hp),"Mage normal attack hits the real user's collider twelve metres away")
	var wizard:=_session(mage)
	_place(wizard,Vector3(-99,2.15,-5))
	_place(target,Vector3(-99,2.15,-17))
	await _frames(3)
	await _aim(mage,target)
	var ray:=PhysicsRayQueryParameters3D.create(wizard.body.position+Vector3.UP*1.65,target.body.position+Vector3.UP)
	ray.exclude=[wizard.body.get_rid()]
	var hit:=_server.get_world_3d().direct_space_state.intersect_ray(ray)
	_check(not hit.is_empty() and _server.world.is_ancestor_of(hit.collider),"Occlusion fixture crosses an actual preserved guild wall")
	await _fire(mage)
	_check(is_equal_approx(float(target.hp),float(target.max_hp)),"Mage ray cannot damage a user behind that city wall")
	var splash_target:=await _enter(archer)
	await _open_duel(mage,target)
	_place(splash_target,Vector3(2,2.15,100))
	await _frames(3)
	await _aim(mage,target)
	await _fire(mage,false,true)
	_check(float(target.hp)<float(target.max_hp) and float(splash_target.hp)<float(splash_target.max_hp),"Mage fire burst damages two nearby real users instead of only its first collider")
	_place(wizard,Vector3(-99,2.15,-1))
	_place(target,Vector3(-99,2.15,-9))
	_place(splash_target,Vector3(-99,2.15,-12))
	await _frames(3)
	var splash_ray:=PhysicsRayQueryParameters3D.create(target.body.position+Vector3.UP,splash_target.body.position+Vector3.UP)
	splash_ray.collision_mask=1
	var splash_wall:=_server.get_world_3d().direct_space_state.intersect_ray(splash_ray)
	_check(target.body.position.distance_to(splash_target.body.position)<3.5 and not splash_wall.is_empty() and _server.world.is_ancestor_of(splash_wall.collider),"Nearby splash target is separated by an actual preserved guild wall")
	await _aim(mage,target)
	await _fire(mage,false,true)
	_check(float(target.hp)<float(target.max_hp) and is_equal_approx(float(splash_target.hp),float(splash_target.max_hp)),"Mage splash damages the exposed player while the guild wall protects the nearby user")
	await _home(archer)
	await _home(mage)
	await _enter(archer)
	await _open_duel(archer,target)
	await _fire(archer)
	var normal_loss:float=float(target.max_hp)-float(target.hp)
	_check(normal_loss>0.0,"Archer arrow hits an aimed user twelve metres away")
	_place(target,Vector3(0,2.15,100))
	await _aim(archer,target)
	await _fire(archer,true,false,true)
	var strong_loss:float=float(target.max_hp)-float(target.hp)
	var weapon_power:float=_server.JOBS.archer.damage
	# The unchanged armor cancels: a strong hit adds 20% of weapon power.
	_check(is_equal_approx(strong_loss-normal_loss,weapon_power*0.2),"One strong arrow adds exactly twenty percent; duplicate/cooldown packets cannot add another hit")
	var pierce_target:=await _enter(cleric)
	await _open_duel(archer,target)
	_place(pierce_target,Vector3(0,2.15,96))
	await _frames(3)
	await _aim(archer,target,1.4)
	await _fire(archer,false,true)
	_check(float(target.hp)<float(target.max_hp) and float(pierce_target.hp)<float(pierce_target.max_hp),"Archer skill pierces two aligned real player colliders")
	_place(_session(archer),Vector3(-99,2.15,-1))
	_place(target,Vector3(-99,2.15,-9))
	_place(pierce_target,Vector3(-99,2.15,-17))
	await _frames(3)
	await _aim(archer,target,1.4)
	await _fire(archer,false,true)
	_check(float(target.hp)<float(target.max_hp) and is_equal_approx(float(pierce_target.hp),float(pierce_target.max_hp)),"Piercing arrow hits the exposed user but stops at solid guild architecture")
	await _home(cleric)
	var baseline_speed:float=_session(archer).body.speed_scale
	await _earn_and_spend(archer,{"敏捷力":1,"回復力":1,"器用さ":3})
	await _open_duel(archer,target)
	await _fire(archer)
	var growth_loss:float=float(target.max_hp)-float(target.hp)
	_check(growth_loss>normal_loss,"Home-allocated dexterity increases actual archer damage")
	_check(float(_session(archer).body.speed_scale)>baseline_speed,"Home-allocated agility changes the next authoritative pawn's movement")
	var ranger:=_session(archer)
	_place(ranger,Vector3(0,2.15,112),50)
	_place(target,Vector3(0,2.15,100),50)
	ranger.mp=50.0
	target.mp=50.0
	ranger.last_damage_at=float(_server.now())-10.0
	target.last_damage_at=float(_server.now())-10.0
	await _frames(45)
	_check(float(target.hp)>50.0 and float(ranger.hp)>50.0,"HP recovers naturally after combat on the authoritative server")
	_check(float(target.mp)>50.0 and float(ranger.mp)>50.0,"MP recovers naturally on the authoritative server")
	_check(float(ranger.hp)>float(target.hp)+0.02 and float(ranger.mp)>float(target.mp)+0.02,"Home-allocated recovery improves both real HP and MP regeneration")
	await _home(archer)
	await _enter(cleric)
	var healer:=await _open_duel(cleric,target)
	healer.hp=30.0
	healer.mp=float(healer.max_mp)
	healer.last_damage_at=_server.now()
	target.last_damage_at=_server.now()
	var untouched_hp:float=target.hp
	var healing_profile:=_profile(cleric)
	await _fire(cleric,false,true,true)
	_check(float(healer.hp)>30.0 and float(healer.hp)<=float(healer.max_hp),"Cleric skill heals the server's own HP within its maximum")
	_check(float(healer.mp)<float(healer.max_mp)-10.0,"Cleric skill consumes authoritative MP")
	_check(float(healer.hp)<90.0,"Duplicate skill/cooldown packets cannot apply a second heal")
	_check(is_equal_approx(float(target.hp),untouched_hp) and _profile(cleric)==healing_profile,"Healing neither damages another user nor grants EXP")
	await _home(cleric)
	await _enter(scout)
	await _open_duel(scout,target,2.0)
	await _fire(scout)
	var scout_normal:float=float(target.max_hp)-float(target.hp)
	_check(scout_normal>0.0,"Scout dagger hits an in-range real user")
	await _earn_and_spend(scout,{"器用さ":5})
	await _open_duel(scout,target,2.0)
	await _fire(scout)
	_check(float(target.max_hp)-float(target.hp)>scout_normal,"Home-allocated dexterity increases actual scout damage")
	await _home(scout)
	await _enter(artisan)
	var crafter:=await _open_duel(artisan,target,8.0)
	var bomb_target:=await _enter(mage)
	_place(bomb_target,Vector3(2,2.15,104))
	await _frames(3)
	await _aim(artisan,target)
	await _fire(artisan,false,true)
	_check(float(target.hp)<float(target.max_hp),"Artisan ranged skill hits a real user beyond normal melee range")
	_check(float(target.hp)<float(target.max_hp) and float(bomb_target.hp)<float(bomb_target.max_hp),"Artisan bomb damages a second nearby real user inside its three-metre blast")
	_check(float(crafter.mp)<float(crafter.max_mp)-10.0,"Artisan ranged skill consumes MP")
	var no_extra_progress:=true
	for client in _clients:
		no_extra_progress=no_extra_progress and _profile(client)==_expected_profiles[str(client.identity.player_id)]
	_check(no_extra_progress,"Nonlethal attacks, healing and passive recovery grant no EXP or points")
	_finish()

func _finish()->void:
	for client in _clients:client.socket.close()
	if is_instance_valid(_server):_server.shutdown()
	print("BATTLE_COMBAT_TEST_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"real_network_classes":["warrior","mage","archer","cleric","scout","artisan"]}))
	quit(0 if failures.is_empty() else 1)
