extends SceneTree
## Exercise the real WebSocket protocol and saved city physics with two users.
## Server-owned placements are fixtures, never a client teleport/damage endpoint.
const RULES = preload("res://scripts/battle/arena_rules.gd")
var checks := 0
var failures: Array[String] = []
var _server: Node3D
var _clients: Array = []
var _save_directory := ""
var _port := 0

class WireClient extends RefCounted:
	var socket := WebSocketPeer.new()
	var inbox: Array[Dictionary] = []
	var identity: Dictionary = {}
	var input_seq := 0
	var attack_seq := 0
	var auto_ack := true
	func poll() -> void:
		socket.poll()
		while socket.get_available_packet_count() > 0:
			var data: Variant = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if data is Dictionary:
				inbox.append(data)
				if auto_ack and str(data.get("type","")) == "snapshot" and data.has("seq"):
					send({"type":"snapshot_ack","seq":data["seq"]})
				if str(data.get("type","")) == "welcome":
					identity = {"player_id":data.get("player_id",""),"token":data.get("token","")}
		if inbox.size() > 500: inbox.pop_front()
	func send(packet: Dictionary) -> void:
		if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
			socket.send_text(JSON.stringify(packet))
	func input(move: Vector2 = Vector2.ZERO, yaw: float = 0.0) -> void:
		input_seq += 1
		send({"type":"input","seq":input_seq,"move":[move.x,move.y],"yaw":yaw,"pitch":0.0,"jump":false,"sprint":false})
	func attack() -> void:
		attack_seq += 1
		send({"type":"attack","seq":attack_seq,"strong":false,"skill":false})
	func latest_snapshot() -> Dictionary:
		for i in range(inbox.size()-1,-1,-1):
			if str(inbox[i].get("type","")) == "snapshot": return inbox[i]
		return {}

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _frames(count: int = 1) -> void:
	for i in range(count):
		await physics_frame
		for client in _clients: client.poll()

func _wait_until(deadline: float) -> void:
	# Cooldowns are deliberately wall-clock based on the authoritative server.
	# A --fixed-fps run can process 36 simulated frames before 0.48s elapses.
	while _server.now() < deadline:
		await _frames()

func _wait_state(condition: Callable, timeout: float = 4.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(timeout*1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call(): return true
		await _frames()
	return false

func _wait_attack_ready(client: WireClient) -> void:
	var session := _session(client)
	var delay: float = _server.JOBS[str(_profile(client)["job_id"])]["delay"]
	await _wait_until(float(session["last_attack_at"])+delay+0.03)

func _wait_packet(client: WireClient, kind: String, predicate: Callable = Callable(), timeout: float = 4.0) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(timeout*1000)
	while Time.get_ticks_msec() < deadline:
		client.poll()
		for i in range(client.inbox.size()):
			var packet: Dictionary = client.inbox[i]
			if str(packet.get("type","")) == kind and (not predicate.is_valid() or predicate.call(packet)):
				client.inbox.remove_at(i)
				return packet
		await _frames()
	return {}

func _new_client(port: int) -> WireClient:
	var client := WireClient.new()
	_clients.append(client)
	var error := client.socket.connect_to_url("ws://127.0.0.1:%d" % port)
	_check(error == OK,"WebSocket client starts connection")
	var deadline := Time.get_ticks_msec()+4000
	while client.socket.get_ready_state() != WebSocketPeer.STATE_OPEN and Time.get_ticks_msec() < deadline:
		await _frames()
	_check(client.socket.get_ready_state() == WebSocketPeer.STATE_OPEN,"Real WebSocket handshake succeeds")
	return client

func _join(client: WireClient, id: String, token: String = "") -> Dictionary:
	client.send({"type":"join","player_id":id,"token":token,"username":"検証用冒険者","job_id":"warrior","female":false,"in_home":true})
	var welcome := await _wait_packet(client,"welcome")
	_check(not welcome.is_empty(),"Joined real user receives authoritative welcome")
	return welcome

func _session(client: WireClient) -> Dictionary:
	for value in _server.sessions.values():
		if str(value.get("player_id","")) == str(client.identity.get("player_id","")):
			return value
	return {}

func _profile(client: WireClient) -> Dictionary:
	var stored: Dictionary = _server.profiles.get(str(client.identity.get("player_id","")),{})
	return stored.get("profile",{}).duplicate(true)

func _start_server(port: int) -> void:
	_server = load("res://scripts/battle/arena_server.gd").new()
	_server.port = port
	_server.save_directory = _save_directory
	root.add_child(_server)
	await _frames(10)
	_check(_server.listen_error == OK,"Headless authoritative server listens")

func _enter(client: WireClient) -> Dictionary:
	client.send({"type":"enter"})
	var packet := await _wait_packet(client,"entered")
	_check(not packet.is_empty(),"Home user can enter the unlimited battle")
	await _frames(8)
	await _wait_state(func() -> bool: return not bool(_session(client).get("awaiting_ready",true)))
	return _session(client)

func _check_snapshot_backpressure() -> void:
	var slow := await _new_client(_port)
	await _join(slow,"test_slow_client")
	slow.auto_ack=false
	slow.send({"type":"enter"})
	await _wait_packet(slow,"entered")
	var first := await _wait_packet(slow,"snapshot")
	_check(first.has("seq"),"Loading client receives a sequenced snapshot")
	if not first.has("seq"): return
	var session:=_session(slow)
	var first_seq:=int(first["seq"])
	_check(bool(session.get("awaiting_ready",false)),"First life waits for the rendered-snapshot acknowledgement")
	await _wait_until(_server.now()+0.42)
	var extra:=0
	for packet:Dictionary in slow.inbox:
		if str(packet.get("type",""))=="snapshot":extra+=1
	_check(extra==0 and int(session["snapshot_seq"])==first_seq and bool(session["snapshot_inflight"]),"Unacknowledged snapshots do not accumulate while a browser is loading")
	slow.send({"type":"snapshot_ack","seq":first_seq+1000})
	await _frames(5)
	_check(bool(session["awaiting_ready"]) and bool(session["snapshot_inflight"]),"An unrelated acknowledgement cannot unlock a life or its snapshot queue")
	# Re-enter before acknowledging that old life, as a rapid leave/rejoin can.
	var old_serial:=int(session["spawn_serial"])
	await _home(slow)
	slow.send({"type":"enter"})
	await _wait_packet(slow,"entered")
	_check(int(session["spawn_serial"])>old_serial,"Re-entry creates a distinct authoritative life")
	slow.send({"type":"snapshot_ack","seq":first_seq})
	await _frames(4)
	_check(bool(session["awaiting_ready"]),"An old-life acknowledgement cannot activate the new life")
	var next := await _wait_packet(slow,"snapshot",func(p:Dictionary)->bool:return int(p.get("seq",-1))>first_seq)
	_check(next.has("seq"),"Acknowledgement resumes the latest snapshot instead of replaying a backlog")
	if not next.has("seq"):return
	# Consume part of the initial spawn grace period before acknowledging. The
	# resulting full window must therefore come from ACK, not spawn time.
	await _wait_until(float(session["protection_until"])-2.0)
	slow.send({"type":"snapshot_ack","seq":next["seq"]})
	await _wait_state(func()->bool:return not bool(session["awaiting_ready"]))
	var remaining:float=float(session["protection_until"])-float(_server.now())
	_check(not bool(session["awaiting_ready"]) and remaining>2.6 and remaining<=3.1,"The correct life acknowledgement arms a fresh three-second protection window")
	_check(int(session["body"].collision_layer)==2,"A correctly loaded life becomes a real combat body")
	slow.auto_ack=true
	await _home(slow)

func _home(client: WireClient) -> Dictionary:
	client.send({"type":"home"})
	var packet := await _wait_packet(client,"profile",func(p: Dictionary) -> bool: return bool(p.get("in_home",false)))
	_check(not packet.is_empty(),"Returning home receives saved authoritative profile")
	await _frames(8)
	return packet

func _fixture_duel(a: Dictionary,b: Dictionary) -> void:
	a["body"].position = Vector3(0,2.15,112)
	a["body"].velocity = Vector3.ZERO
	a["move"] = Vector2.ZERO
	a["yaw"] = 0.0
	a["pitch"] = 0.0
	b["body"].position = Vector3(0,2.15,110)
	b["body"].velocity = Vector3.ZERO
	b["move"] = Vector2.ZERO

func _check_gate_geometry() -> void:
	var space := _server.get_world_3d().direct_space_state
	for pair in [[Vector3(0,6,151),Vector3(0,6,166)],[Vector3(-151,6,0),Vector3(-166,6,0)],[Vector3(0,6,-151),Vector3(0,6,-166)],[Vector3(151,6,0),Vector3(166,6,0)]]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pair[0],pair[1]))
		_check(not hit.is_empty() and str(hit.collider.name) == "GateBarrier","Each existing gate has an actual blocking portcullis")

func _run() -> void:
	Engine.max_fps = 120
	_port = 19000 + int(Time.get_ticks_msec()%20000)
	_save_directory = OS.get_user_data_dir().path_join("battle_test_%d" % Time.get_ticks_usec())
	await _start_server(_port)
	if _server.listen_error != OK:
		_finish()
		return
	_check_gate_geometry()
	var a := await _new_client(_port)
	var b := await _new_client(_port)
	var wa := await _join(a,"test_player_a")
	var wb := await _join(b,"test_player_b")
	if wa.is_empty() or wb.is_empty():
		_finish()
		return
	_check(not str(a.identity.get("token","")).is_empty(),"Server issues an identity token")
	_check(_profile(a).get("level",0) == 1 and _profile(a).get("exp",-1) == 0,"New real user starts at level one with zero EXP")
	_check(bool(_session(a).get("in_home",false)),"Connecting from home does not place a combat target in the arena")
	await _check_snapshot_backpressure()
	var sa := await _enter(a)
	var sb := await _enter(b)
	_check(not sa.is_empty() and not sb.is_empty(),"Two real network peers own authoritative player sessions")
	if sa.is_empty() or sb.is_empty():
		_finish()
		return
	for session in [sa,sb]:
		var p: Vector3 = session["body"].position
		var near_gate := false
		for spawn in RULES.spawn_points():
			near_gate = near_gate or p.distance_to(spawn)<1.0
		_check(RULES.inside_city(p) and near_gate,"Users spawn inside one of the four kingdom gates")
	_fixture_duel(sa,sb)
	sa["protection_until"] = 0.0
	sb["protection_until"] = _server.now()+3.0
	a.input()
	a.attack()
	await _frames(10)
	await _wait_state(func() -> bool: return int(sa["attack_seq"]) >= a.attack_seq)
	_check(is_equal_approx(float(sb["hp"]),float(sb["max_hp"])),"Spawn protection prevents an immediate spawn kill")
	_check(_profile(a).get("kills",-1) == 0,"Protected targets never grant EXP or kills")
	sb["protection_until"] = 0.0
	await _wait_attack_ready(a)
	a.attack()
	await _wait_state(func() -> bool: return float(sb["hp"]) < float(sb["max_hp"]))
	var hp_after_hit := float(sb["hp"])
	_check(hp_after_hit>0 and hp_after_hit<float(sb["max_hp"]),"A real attack hits the other network user's actual body")
	a.attack()
	a.send({"type":"attack","seq":a.attack_seq,"strong":false,"skill":false})
	await _frames(4)
	_check(is_equal_approx(float(sb["hp"]),hp_after_hit),"Cooldown and duplicate attack packets cannot add extra hits")
	await _wait_attack_ready(a)
	sb["hp"] = 1.0
	a.attack()
	a.send({"type":"attack","seq":a.attack_seq,"strong":false,"skill":false})
	await _wait_state(func() -> bool: return not bool(sb["alive"]))
	_check(not bool(sb["alive"]),"Real player death is resolved by the server")
	var earned := _profile(a)
	_check(earned.get("kills",0) == 1 and earned.get("level",0) == 2 and earned.get("exp",-1) == 0,"One level-one player kill grants exactly 100 EXP and one level")
	_check(earned.get("unspent_points",0) == 5,"Level-up grants the configured unspent allocation points")
	_check(_profile(b).get("deaths",0) == 1,"Victim death is counted once")
	a.send({"type":"award_exp","amount":100000,"victim_id":"npc"})
	a.send({"type":"kill","victim_id":"npc","exp":100000})
	a.attack()
	await _frames(8)
	_check(_profile(a) == earned,"Client reward claims, NPC identifiers and repeated corpse attacks grant no EXP")
	await _wait_state(func() -> bool: return bool(sb["alive"]))
	_check(bool(sb["alive"]),"Dead user respawns without ending the unlimited battle")
	var respawn: Vector3 = sb["body"].position
	var at_gate := false
	for spawn in RULES.spawn_points(): at_gate = at_gate or respawn.distance_to(spawn)<1.0
	_check(at_gate and RULES.inside_city(respawn),"Respawn stays at an inside-gate location")
	_check(float(sb["protection_until"])>_server.now(),"Respawn protection is renewed")
	a.send({"type":"allocate","stat":"筋力","points":1})
	await _frames(8)
	_check(_profile(a) == earned,"Spending ability points during a battle is rejected")
	# Actual movement meets the real gate collider, independent of metadata.
	sa["body"].position=Vector3(0,2.15,151)
	sa["body"].velocity=Vector3.ZERO
	for i in range(80):
		if i%5 == 0: a.input(Vector2(0,1),PI)
		await _frames()
	a.input()
	await _frames(5)
	var stopped: Vector3 = sa["body"].position
	_check(stopped.z>153 and stopped.z<157.1 and RULES.inside_city(stopped),"The real player moves up to the closed south gate and cannot leave")
	a.send({"type":"input","seq":a.input_seq+1,"move":[0,0],"yaw":0,"pitch":0,"position":[999,999,999],"damage":999999})
	a.input_seq+=1
	await _frames(5)
	_check(RULES.inside_city(sa["body"].position),"Client-supplied positions cannot teleport outside the kingdom")
	await _home(b)
	await _frames(8)
	var left_body: Variant = _session(b).get("body")
	_check(not is_instance_valid(left_body) or int(left_body.collision_layer)==0,"A home user leaves no collidable combat body behind")
	var snapshot := a.latest_snapshot()
	var ghost := false
	for peer in snapshot.get("players",[]): ghost = ghost or str(peer.get("id","")) == str(b.identity["player_id"])
	_check(not ghost,"Home users are absent from the opponent list")
	await _home(a)
	a.send({"type":"allocate","stat":"筋力","points":1})
	var strength_ack := await _wait_packet(a,"profile",func(p: Dictionary) -> bool: return int(p.get("profile",{}).get("unspent_points",-1))==4)
	_check(not strength_ack.is_empty(),"Home allocation is acknowledged by the server")
	_check(is_equal_approx(float(_profile(a).get("stats",{}).get("筋力",0)),11.1),"Warrior allocation applies the class's ten-percent growth bonus")
	a.send({"type":"allocate","stat":"HP","points":1})
	await _wait_packet(a,"profile",func(p: Dictionary) -> bool: return int(p.get("profile",{}).get("unspent_points",-1))==3)
	var allocated := _profile(a)
	_check(allocated.get("stats",{}).get("HP",0) == 101,"Allocated HP is part of the real profile")
	for packet in [{"type":"allocate","stat":"unknown","points":1},{"type":"allocate","stat":"HP","points":999},{"type":"allocate","stat":"HP","points":-1},{"type":"allocate","stat":"HP","points":1.5}]:
		a.send(packet)
	await _frames(12)
	_check(_profile(a) == allocated,"Unknown, negative, fractional and overspent allocations cannot change the profile")
	var impostor := await _new_client(_port)
	impostor.send({"type":"join","player_id":a.identity["player_id"],"token":"wrong-token","in_home":true})
	var denied := await _wait_packet(impostor,"error")
	_check(not denied.is_empty(),"Another client cannot claim an existing player's profile without its token")
	_check(a.socket.get_ready_state() == WebSocketPeer.STATE_OPEN and _profile(a)==allocated,"Rejected impersonation leaves the real user and profile intact")
	var saved_identity := a.identity.duplicate(true)
	for client in _clients: client.socket.close()
	await _frames(12)
	_server.shutdown()
	_server.queue_free()
	await _frames(6)
	await _start_server(_port+1)
	var restored := await _new_client(_port+1)
	var rejoined := await _join(restored,str(saved_identity["player_id"]),str(saved_identity["token"]))
	_check(not rejoined.is_empty() and _profile(restored)==allocated,"Server restart and reconnect retain kills, EXP, points and allocations")
	_check(bool(_session(restored).get("in_home",false)),"Reconnected user returns to home without a ghost combatant")
	_finish()

func _finish() -> void:
	for client in _clients: client.socket.close()
	if is_instance_valid(_server): _server.shutdown()
	print("BATTLE_SERVER_TEST_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"two_real_websocket_users":true,"persistent_restart_checked":failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
