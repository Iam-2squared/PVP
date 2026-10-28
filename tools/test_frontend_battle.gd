extends SceneTree
## The home sends requests; only received server snapshots alter progression.
const Frontend=preload("res://scenes/frontend/start_home.tscn")
const Profiles=preload("res://scripts/battle/profile_store.gd")
const Progression=preload("res://scripts/battle/progression.gd")
var checks:=0
var failures:Array[String]=[]
var _paths:Array[String]=[]

class SessionDouble extends Node3D:
	var connected:=true
	var at_home:=true
	var allocations:Array=[]
	var entries:=0
	func is_connected_to_server()->bool: return connected
	func is_in_home()->bool: return at_home
	func request_allocate(stat:String,points:int=1)->void: allocations.append([stat,points])
	func enter_battle()->void: entries+=1

func _initialize()->void:
	_run.call_deferred()

func _check(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures.append(message)
		push_error(message)

func _frames()->void:
	for i in range(3): await process_frame

func _test_store()->void:
	var path:="user://test_home_store_%d.json"%Time.get_ticks_usec()
	_paths.append(path)
	var store=Profiles.new(path)
	store.configure("ws://test-a.invalid:8910","試験者","mage",true)
	var identity:Dictionary=store.identity_for(store.endpoint())
	_check(identity.player_id.length()==32 and identity.token=="","New endpoint needs a stable random identity, without a fabricated server token")
	_check(identity.job_id=="mage" and identity.female,"Pre-join appearance was not saved")
	_check(store.identity_for(store.endpoint()).player_id==identity.player_id,"Repeated connection generated a new identity")
	store.remember_identity(store.endpoint(),{"player_id":"foreign","token":"bad"})
	_check(not store.has_registered_identity(store.endpoint()),"Foreign server identity overwrote local credentials")
	store.remember_identity(store.endpoint(),{"player_id":identity.player_id,"token":"server-test-token"})
	var earned:=Progression.award_player_kill(Progression.new_profile(identity.player_id,"試験者","mage",true),1)
	_check(store.remember_snapshot(store.endpoint(),earned),"Authoritative snapshot was not accepted for its own identity")
	_check(not store.remember_snapshot(store.endpoint(),{"level":999}),"Malformed cache was accepted as progression")
	var reloaded=Profiles.new(path)
	_check(reloaded.identity_for(store.endpoint()).token=="server-test-token","Server token did not survive reload")
	_check(reloaded.display_profile(store.endpoint()).level==2 and reloaded.display_profile(store.endpoint()).unspent_points==5,"Earned progression did not survive the display-cache reload")
	var other:Dictionary=reloaded.identity_for("ws://test-b.invalid:8910")
	_check(other.player_id!=identity.player_id and other.token=="","Credentials leaked between server endpoints")
	_check(reloaded.display_profile("ws://test-b.invalid:8910").level==1,"One server's earned level leaked into another server")
	var copy:Dictionary=reloaded.display_profile(store.endpoint())
	copy.stats.HP=99999
	_check(reloaded.display_profile(store.endpoint()).stats.HP==100,"A displayed dictionary mutated stored authoritative progression")
	var recovery_path:="user://test_recovery_%d.json"%Time.get_ticks_usec()
	_paths.append(recovery_path)
	var recovery_store=Profiles.new(recovery_path)
	var original_url:="wss://one.trycloudflare.com/ws"
	var rotating_url:="wss://two.trycloudflare.com/ws"
	var first_identity:=recovery_store.identity_for(original_url)
	var private_token:="a".repeat(64)
	recovery_store.remember_identity(original_url,{"player_id":first_identity.player_id,"token":private_token})
	var recovery_code:=recovery_store.export_recovery_code(original_url)
	_check(recovery_code.begins_with("PVP1-") and recovery_code.length()==102,"A registered identity has no portable recovery code")
	_check(recovery_store.import_recovery_code(rotating_url,recovery_code),"Rotating public URL cannot restore an existing identity")
	_check(recovery_store.identity_for(rotating_url).player_id==first_identity.player_id and recovery_store.identity_for(rotating_url).token==private_token,"Recovered identity did not match the server authority")
	_check(not recovery_store.import_recovery_code(rotating_url,"PVP1-bad"),"Malformed recovery code replaced an identity")
	_check(not recovery_store.import_recovery_code(rotating_url,"PVP1-"+"b".repeat(32)+"-"+"b".repeat(64)),"Registered identity was silently overwritten")
	var recovery_reload:=Profiles.new(recovery_path)
	_check(recovery_reload.identity_for(rotating_url).token==private_token,"Restored token did not persist after reload")
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string("{")
	file.close()
	var recovered=Profiles.new(path)
	_check(recovered.display_profile(recovered.endpoint()).level==1,"A damaged cache became an earned profile")

func _run()->void:
	_test_store()
	root.size=Vector2i(1280,720)
	var app=Frontend.instantiate()
	var path:="user://test_home_ui_%d.json"%Time.get_ticks_usec()
	_paths.append(path)
	app.store_path=path
	root.add_child(app)
	await _frames()
	_check(app.current_page=="title" and app.profile.level==1 and app.profile.exp==0,"Frontend does not begin with the real initial profile")
	_check(app.profile.stats.HP==100 and app.profile.unspent_points==0 and not app.is_demo,"Display-only zero stats leaked into the playable home")
	app.show_home()
	await _frames()
	_check(app.find_child("BattleButton",true,false)!=null,"Home is missing the battle entry button")
	_check(app.find_child("PlayerSettingsButton",true,false)!=null,"Home is missing initial class/server settings")
	var buttons:=app.find_children("Allocate_*","Button",true,false)
	_check(buttons.size()==8,"All eight abilities need point-allocation controls")
	var grids:=app.find_children("*","GridContainer",true,false)
	_check(grids.size()==1 and grids[0].columns==4,"Home abilities must remain four columns and two rows")
	for button:Button in buttons: _check(button.disabled,"Offline home must not spend a cached point")
	app.show_player_settings()
	await _frames()
	_check(app.find_child("ServerUrlEdit",true,false).text==Profiles.DEFAULT_ENDPOINT,"Server setting does not expose the actual connection endpoint")
	_check(not app.find_child("FirstJobChoice",true,false).disabled,"New players cannot choose their initial class")
	app._close_popup()
	var session:=SessionDouble.new()
	root.add_child(session)
	app._session=session
	app._session_url=app._store.endpoint()
	var identity:Dictionary=app._store.identity_for(app._session_url)
	var earned:=Progression.award_player_kill(Progression.new_profile(identity.player_id),1)
	app.set_profile(earned)
	await _frames()
	_check(not app.find_child("Allocate_0",true,false).disabled,"Connected home did not enable earned points")
	var before:Dictionary=app.profile.duplicate(true)
	app._spend_point("筋力")
	_check(session.allocations==[["筋力",1]],"Stat control did not send exactly one server allocation request")
	_check(app.profile==before,"A button spent points locally before server acknowledgement")
	var allocated:=Progression.allocate(earned,"筋力",1)
	app._received_profile(allocated)
	await _frames()
	_check(app.profile.unspent_points==4 and is_equal_approx(app.profile.stats["筋力"],11.1),"Confirmed allocation lost its point or class growth bonus")
	app._request_battle()
	_check(session.entries==1 and app.visible,"Home hid before the server accepted battle entry")
	session.at_home=false
	app._battle_started()
	_check(not app.visible,"Battle entry acknowledgement did not hide Home")
	var after_kill:=Progression.award_player_kill(allocated,1)
	app._received_profile(after_kill)
	_check(not app.visible,"A battle EXP update unexpectedly reopened Home")
	session.at_home=true
	app._returned_home(after_kill)
	await _frames()
	_check(app.visible and app.current_page=="home" and app.profile==after_kill,"Return-to-home lost the authoritative battle result")
	session.connected=false
	app._connection_failed("検証用の切断")
	await _frames()
	for button:Button in app.find_children("Allocate_*","Button",true,false): _check(button.disabled,"Disconnected Home still allowed an authoritative allocation request")
	_check(app.visible and not app.find_child("BattleButton",true,false).disabled,"Connection failure left the user trapped outside Home")
	app.queue_free()
	await _frames()
	for item in _paths: DirAccess.remove_absolute(ProjectSettings.globalize_path(item))
	print("FRONTEND_BATTLE_TEST_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
