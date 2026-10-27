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

func _load() -> void:
	data = {"version":1,"endpoint":DEFAULT_ENDPOINT,"username":"冒険者","job_id":"warrior","female":false,"identities":{},"profiles":{}}
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
