extends RefCounted
## The client keeps identity credentials and a display cache, never progression authority.
const Progression = preload("res://scripts/battle/progression.gd")
const DEFAULT_ENDPOINT := "ws://127.0.0.1:8910"
const DEFAULT_PATH := "user://pvp_frontend_profile.json"

var path: String
var data: Dictionary = {}

func _init(save_path: String = DEFAULT_PATH) -> void:
	path = save_path
	_load()

func _suggested_endpoint() -> String:
	# Only the temporary Cloudflare host uses the same origin as its game socket.
	# Leave existing desktop/LAN or other hosted preview settings unchanged.
	if OS.has_feature("web"):
		var host: Variant = JavaScriptBridge.eval("window.location.hostname", true)
		if host is String and str(host).ends_with(".trycloudflare.com"):
			var authority: Variant = JavaScriptBridge.eval("window.location.host", true)
			if authority is String and not str(authority).is_empty():
				return "wss://" + str(authority) + "/ws"
	return DEFAULT_ENDPOINT


func _load() -> void:
	var proposed := _suggested_endpoint()
	data = {"version":1,"endpoint":proposed,"username":"冒険者","job_id":"warrior","female":false,"identities":{},"profiles":{}}
	if not FileAccess.file_exists(path): return
	var parser:=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path))!=OK: return
	var saved: Variant = parser.data
	if not saved is Dictionary: return
	for key in ["endpoint","username","job_id"]:
		if saved.get(key) is String: data[key] = saved[key]
	if saved.get("female") is bool: data["female"] = saved["female"]
	for key in ["identities","profiles"]:
		if saved.get(key) is Dictionary: data[key] = saved[key]
	if proposed != DEFAULT_ENDPOINT and str(data["endpoint"]) == DEFAULT_ENDPOINT:
		data["endpoint"] = proposed

func save() -> bool:
	var temporary:=path+".tmp"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(data))
	file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(path))==OK

func endpoint() -> String:
	return str(data.get("endpoint",DEFAULT_ENDPOINT))

func configure(url: String, username: String, job_id: String, female: bool) -> void:
	data["endpoint"] = url.strip_edges()
	data["username"] = username.strip_edges().left(24) if not username.strip_edges().is_empty() else "冒険者"
	data["job_id"] = job_id
	data["female"] = female
	save()

func identity_for(url: String) -> Dictionary:
	var entry: Variant = data["identities"].get(url,{})
	if not entry is Dictionary or not entry.get("player_id") is String or str(entry.get("player_id","")).is_empty():
		entry = {"player_id":Crypto.new().generate_random_bytes(16).hex_encode(),"token":""}
		data["identities"][url] = entry
		save()
	return {"player_id":str(entry["player_id"]),"token":str(entry.get("token","")),"username":str(data["username"]),"job_id":str(data["job_id"]),"female":bool(data["female"]),"in_home":true}

func remember_identity(url: String, received: Dictionary) -> void:
	var existing := identity_for(url)
	if str(received.get("player_id","")) != str(existing["player_id"]): return
	var token: Variant = received.get("token","")
	if not token is String or str(token).is_empty(): return
	data["identities"][url] = {"player_id":existing["player_id"],"token":token}
	save()

func remember_snapshot(url: String, snapshot: Dictionary) -> bool:
	var clean: Dictionary = Progression.normalize_profile(snapshot)
	if clean.is_empty() or str(clean.get("player_id","")) != str(identity_for(url)["player_id"]): return false
	data["profiles"][url] = clean.duplicate(true)
	for key in ["username","job_id","female"]: data[key]=clean[key]
	save()
	return true

func display_profile(url: String) -> Dictionary:
	var saved: Variant = data["profiles"].get(url,{})
	if saved is Dictionary:
		var clean: Dictionary = Progression.normalize_profile(saved)
		if not clean.is_empty() and str(clean.get("player_id","")) == str(identity_for(url)["player_id"]): return clean
	var identity := identity_for(url)
	return Progression.new_profile(identity["player_id"],identity["username"],identity["job_id"],identity["female"])

func has_registered_identity(url: String) -> bool:
	return not str(identity_for(url).get("token","")).is_empty()

func export_recovery_code(url: String) -> String:
	var entry: Variant = data["identities"].get(url,{})
	if not entry is Dictionary: return ""
	var id := str(entry.get("player_id",""))
	var token := str(entry.get("token",""))
	if id.length()!=32 or token.length()!=64 or not id.is_valid_hex_number() or not token.is_valid_hex_number(): return ""
	return "PVP1-" + id + "-" + token


func import_recovery_code(url: String, code: String) -> bool:
	# This code is a bearer credential, never send it to logs or share links.
	var parts := code.strip_edges().split("-",false)
	if parts.size()!=3 or parts[0]!="PVP1": return false
	var id := str(parts[1]).to_lower()
	var token := str(parts[2]).to_lower()
	if id.length()!=32 or token.length()!=64 or not id.is_valid_hex_number() or not token.is_valid_hex_number(): return false
	var existing: Variant = data["identities"].get(url,{})
	if existing is Dictionary and not str(existing.get("token","")).is_empty():
		return str(existing.get("player_id",""))==id and str(existing.get("token",""))==token
	data["identities"][url]={"player_id":id,"token":token}
	data["profiles"].erase(url)
	if save(): return true
	if existing is Dictionary and not existing.is_empty(): data["identities"][url]=existing
	else: data["identities"].erase(url)
	return false
