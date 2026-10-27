extends SceneTree
## Real frontend controls -> ArenaClient -> WebSocket server -> saved profile.
## A separate server World3D prevents client prediction colliders from entering
## authoritative hit tests. The opponent is a second real network connection.
const Frontend=preload("res://scenes/frontend/start_home.tscn")
const Store=preload("res://scripts/battle/profile_store.gd")
const WireSupport=preload("res://tools/test_battle_server.gd")
var checks:=0
var failures:Array[String]=[]
var _app:Control
var _server:Node3D
var _viewport:SubViewport
var _opponent:RefCounted
var _store_path:=""

func _initialize()->void:
	_run.call_deferred()

func _check(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures.append(message)
		push_error(message)

func _frame()->void:
	await physics_frame
	if _opponent!=null:_opponent.poll()

func _wait(condition:Callable,message:String,timeout:float=7.0)->bool:
	var deadline:=Time.get_ticks_msec()+int(timeout*1000)
	while Time.get_ticks_msec()<deadline:
		if condition.call():
			_check(true,message)
			return true
		await _frame()
	_check(false,message)
	return false

func _frames(count:int)->void:
	for i in range(count):await _frame()

func _session_for(id:String)->Dictionary:
	for session:Dictionary in _server.sessions.values():
		if str(session.get("player_id",""))==id:return session
	return {}

func _press(name:String)->bool:
	var button:Button=_app.find_child(name,true,false)
	_check(button!=null and not button.disabled,"Usable actual frontend control: "+name)
	if button==null or button.disabled:return false
	button.pressed.emit()
	return true

func _run()->void:
	Engine.max_fps=120
	root.size=Vector2i(1280,720)
	var stamp:=Time.get_ticks_usec()
	var port:=25000+int(stamp%10000)
	var endpoint:="ws://127.0.0.1:%d"%port
	_store_path="user://test_real_battle_flow_%d.json"%stamp
	_viewport=SubViewport.new()
	_viewport.size=Vector2i(16,16)
	_viewport.own_world_3d=true
	_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	root.add_child(_viewport)
	_server=load("res://scripts/battle/arena_server.gd").new()
	_server.port=port
	_server.save_directory=OS.get_user_data_dir().path_join("battle_flow_server_%d"%stamp)
	_viewport.add_child(_server)
	await _frames(8)
	_check(_server.listen_error==OK,"Real authoritative server starts in a separate physics world")
	if _server.listen_error!=OK:
		_finish();return
	_app=Frontend.instantiate()
	_app.store_path=_store_path
	root.add_child(_app)
	await _frames(4)
	_app._store.configure(endpoint,"実対戦検証","warrior",false)
	_app.set_profile(_app._store.display_profile(endpoint))
	_press("StartButton")
	await _frames(4)
	_check(_app.visible and _app.current_page=="home","Title opens the real home")
	_check(_app.profile.level==1 and _app.profile.unspent_points==0,"Home starts with actual unearned progression")
	_press("BattleButton")
	var entered:=await _wait(func()->bool:return is_instance_valid(_app._session) and _app._session.is_connected_to_server() and not _app._session.is_in_home() and _app._session.player!=null and _app._session.player.active,"Home button connects and activates the player after the first authoritative living snapshot")
	if not entered:
		_finish();return
	var client:Node3D=_app._session
	_check(not _app.visible and client.player.active,"Accepted battle entry hides home and enables the real player")
	_check(client.world.get_node_or_null("ArenaGateClosures")!=null,"Battle loads the city with its four closed gates")
	_check(client.player.hud!=null and client.player.hud.visible,"Battle displays its live combat HUD")
	var identity:Dictionary=_app._store.identity_for(endpoint)
	_check(not str(identity.token).is_empty(),"Issued server identity is retained by the home store")
	_check(client.get_world_3d()!=_server.get_world_3d(),"Client-rendered city cannot contaminate authoritative physics")
	_opponent=WireSupport.WireClient.new()
	_check(_opponent.socket.connect_to_url(endpoint)==OK,"Second actual user starts a WebSocket connection")
	if not await _wait(func()->bool:return _opponent.socket.get_ready_state()==WebSocketPeer.STATE_OPEN,"Second user's WebSocket handshake succeeds"):
		_finish();return
	_opponent.send({"type":"join","player_id":"real_flow_opponent","token":"","username":"相手ユーザー","job_id":"warrior","female":true,"in_home":true})
	if not await _wait(func()->bool:return not _opponent.identity.is_empty(),"Second user receives its own server-issued identity"):
		_finish();return
	_opponent.send({"type":"enter"})
	if not await _wait(func()->bool:return not _session_for("real_flow_opponent").is_empty() and not bool(_session_for("real_flow_opponent").get("in_home",true)),"Opponent joins the same persistent battle"):
		_finish();return
	var a:=_session_for(str(identity.player_id))
	var b:=_session_for("real_flow_opponent")
	if not await _wait(func()->bool:return not bool(a.get("awaiting_ready",true)) and not bool(b.get("awaiting_ready",true)),"Both loaded lives are acknowledged before arranging the server-owned duel fixture"):
		_finish();return
	a.body.position=Vector3(0,2.15,112)
	a.body.velocity=Vector3.ZERO
	a.last_safe=a.body.position
	a.protection_until=0.0
	a.yaw=0.0
	a.pitch=0.0
	b.body.position=Vector3(0,2.15,110)
	b.body.velocity=Vector3.ZERO
	b.last_safe=b.body.position
	b.protection_until=0.0
	b.hp=1.0
	client.player.rotation.y=0.0
	client.player.camera.rotation.x=0.0
	client.player._pitch=0.0
	await _frames(20)
	_check(client.player.position.distance_to(a.body.position)<1.0,"Snapshot places the real controlled player at the authoritative position")
	_check(client._actors.has("real_flow_opponent"),"Other real users appear as actual character models")
	# This is the HUD's real tap signal, including normal/double arbitration.
	client.player.hud.attack_tapped.emit()
	if not await _wait(func()->bool:return int(_app.profile.get("kills",0))==1,"HUD attack defeats the opponent through the server and updates the home profile cache"):
		_finish();return
	_check(_app.profile.level==2 and _app.profile.exp==0 and _app.profile.unspent_points==5,"A real player kill drives level-up and earned allocation points")
	_check(not bool(b.alive),"The defeated opponent is in authoritative respawn state")
	client.player.hud.home_requested.emit()
	if not await _wait(func()->bool:return _app.visible and _app.current_page=="home" and client.is_in_home(),"Actual HUD return-home control restores home after server acknowledgement"):
		_finish();return
	_check(not client.player.active and not client.visible,"Returning home disables the combat player and hides its world")
	_check(_app.find_child("UnspentPointsLabel",true,false).text.contains("5"),"Home displays earned unspent points")
	var before:Dictionary=_app.profile.duplicate(true)
	_press("Allocate_0")
	_check(_app.profile==before,"Point button waits for authority instead of applying a local grant")
	if not await _wait(func()->bool:return int(_app.profile.get("unspent_points",-1))==4,"Real point button spends one point through the connected server"):
		_finish();return
	_check(is_equal_approx(float(_app.profile.stats["筋力"]),11.1),"Confirmed warrior stat retains its class multiplier")
	_press("Allocate_3")
	await _wait(func()->bool:return int(_app.profile.get("unspent_points",-1))==3,"Home HP allocation receives a real server acknowledgement")
	_check(_app.profile.stats.HP==101,"Home displays the allocated HP")
	var persisted:Dictionary=Store.new(_store_path).display_profile(endpoint)
	_check(persisted==_app.profile,"Displayed earned progression survives local cache reload")
	_press("BattleButton")
	if not await _wait(func()->bool:return not _app.visible and not client.is_in_home() and client.player.active,"Home can re-enter the unlimited battle without recreating an identity"):
		_finish();return
	_check(float(_session_for(str(identity.player_id)).max_hp)==101,"Home allocation affects the next real battle character")
	_check(_app._store.identity_for(endpoint).token==identity.token,"Battle/home/re-entry retains the same authenticated user")
	client.player.hud.home_requested.emit()
	await _wait(func()->bool:return _app.visible and client.is_in_home(),"Second return restores the same home")
	_server.shutdown()
	await _wait(func()->bool:return not _app._connected() and _app.visible,"Disconnect returns safely to the real home")
	_check(_app.find_child("Allocate_0",true,false).disabled,"Disconnected home cannot spend cached progression")
	_check(_app.profile.level==2 and _app.profile.unspent_points==3,"Disconnect preserves the last server-confirmed display profile")
	_finish()

func _finish()->void:
	if _opponent!=null:_opponent.socket.close()
	if is_instance_valid(_app):_app.queue_free()
	if is_instance_valid(_server):_server.shutdown()
	print("BATTLE_FLOW_TEST_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"actual_frontend_client_server":true}))
	quit(0 if failures.is_empty() else 1)
