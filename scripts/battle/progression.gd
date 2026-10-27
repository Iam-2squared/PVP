extends RefCounted
## Pure server-side progression rules for the temporary unlimited PvP mode.
## Damage, starting stats and the two reward constants are prototype tuning.
## Only the authoritative server calls award_player_kill once per real death.
## Callers persist the returned snapshot; no method mutates its input profile.

const SCHEMA_VERSION := 1
const POINTS_PER_LEVEL := 5
const KILL_EXP_PER_VICTIM_LEVEL := 100
const MAX_SAFE_INTEGER := 9007199254740991
const MAX_LEVEL := 1000000
const STAT_KEYS := ["筋力", "耐久力", "精神力", "HP", "MP", "回復力", "敏捷力", "器用さ"]
const JOBS := {
	"warrior": {"bonus":"筋力", "skill":"strong_strike", "weapon":"剣"},
	"mage": {"bonus":"MP", "skill":"flame_burst", "weapon":"魔法杖"},
	"scout": {"bonus":"敏捷力", "skill":"vital_thrust", "weapon":"短剣"},
	"archer": {"bonus":"器用さ", "skill":"piercing_arrow", "weapon":"弓"},
	"cleric": {"bonus":"精神力", "skill":"heal", "weapon":"聖杖"},
	"artisan": {"bonus":"器用さ", "skill":"thrown_bomb", "weapon":"工具槌"},
}


static func new_profile(player_id: String, username: String = "冒険者", job_id: String = "warrior", female: bool = false) -> Dictionary:
	if player_id.strip_edges().is_empty() or player_id.length() > 128:
		return {}
	var job: String = job_id if JOBS.has(job_id) else "warrior"
	var allocations := {}
	for key in STAT_KEYS: allocations[key] = 0
	var name := username.strip_edges().left(24)
	if name.is_empty(): name = "冒険者"
	return {
		"schema_version":SCHEMA_VERSION, "player_id":player_id,
		"username":name, "level":1, "job_id":job, "female":female,
		"exp":0, "unspent_points":0, "allocations":allocations,
		"stats":_effective_stats(job,allocations), "kills":0, "deaths":0,
		"gold":0, "fame":"なし", "skills":{JOBS[job]["skill"]:1},
		"equipment":{"head":"", "body":"", "legs":"", "feet":""},
		"owned_weapons":[{
			"id":"starter_"+job, "name":"初期装備の"+str(JOBS[job]["weapon"]),
			"type":JOBS[job]["weapon"], "rank":"コモン", "equipped":true,
			"description":"時間無制限対戦の初期装備",
		}],
	}


static func experience_required(level: int) -> int:
	return maxi(1,level)*100


static func award_player_kill(profile: Dictionary, victim_level: Variant) -> Dictionary:
	var result := normalize_profile(profile)
	var victim := _whole(victim_level,1,MAX_LEVEL)
	if result.is_empty() or victim < 1 or int(result["kills"]) >= MAX_SAFE_INTEGER:
		return {}
	# No timer, movement, mob, training or client-supplied EXP award path exists.
	var reward := victim*KILL_EXP_PER_VICTIM_LEVEL
	result["exp"] += reward
	result["kills"] += 1
	while result["exp"] >= experience_required(int(result["level"])):
		if int(result["level"]) >= MAX_LEVEL:
			# This is a persisted-number integrity bound, not a normal progression cap.
			return {}
		result["exp"] -= experience_required(int(result["level"]))
		result["level"] += 1
		result["unspent_points"] += POINTS_PER_LEVEL
	return result


static func allocate(profile: Dictionary, stat_key: String, points: Variant = 1) -> Dictionary:
	var result := normalize_profile(profile)
	var count := _whole(points,1,MAX_SAFE_INTEGER)
	if result.is_empty() or not STAT_KEYS.has(stat_key) or count < 1:
		return {}
	if count > int(result["unspent_points"]):
		return {}
	result["unspent_points"] -= count
	result["allocations"][stat_key] += count
	result["stats"] = _effective_stats(str(result["job_id"]),result["allocations"])
	return result


static func validate_profile(raw: Variant) -> bool:
	return not normalize_profile(raw).is_empty()


static func normalize_profile(raw: Variant) -> Dictionary:
	# Saved JSON stores integral numbers as floats; accept only exact finite
	# integers and reconstruct all derived stats instead of trusting a cache.
	if not raw is Dictionary:
		return {}
	if not raw.get("player_id") is String or not raw.get("job_id") is String:
		return {}
	var id: String = raw["player_id"]
	var job: String = raw["job_id"]
	if not JOBS.has(job) or not raw.get("female",false) is bool:
		return {}
	if _whole(raw.get("schema_version",SCHEMA_VERSION),SCHEMA_VERSION,SCHEMA_VERSION) < 0:
		return {}
	var level := _whole(raw.get("level"),1,MAX_LEVEL)
	var experience := _whole(raw.get("exp"),0,MAX_SAFE_INTEGER)
	var unspent := _whole(raw.get("unspent_points"),0,MAX_SAFE_INTEGER)
	if level < 1 or experience < 0 or unspent < 0 or experience >= experience_required(level):
		return {}
	var source_allocations: Variant = raw.get("allocations")
	if not source_allocations is Dictionary:
		return {}
	for key in source_allocations:
		if key not in STAT_KEYS: return {}
	var allocations := {}
	var spent := 0
	for key in STAT_KEYS:
		var count := _whole(source_allocations.get(key,0),0,POINTS_PER_LEVEL*(level-1))
		if count < 0: return {}
		allocations[key] = count
		spent += count
	if spent+unspent != POINTS_PER_LEVEL*(level-1):
		return {}
	var username: Variant = raw.get("username","冒険者")
	if not username is String: return {}
	var result := new_profile(id,username,job,bool(raw.get("female",false)))
	if result.is_empty(): return {}
	for key in ["kills","deaths","gold"]:
		var count := _whole(raw.get(key,0),0,MAX_SAFE_INTEGER)
		if count < 0: return {}
		result[key] = count
	result["level"] = level
	result["exp"] = experience
	result["unspent_points"] = unspent
	result["allocations"] = allocations
	result["stats"] = _effective_stats(job,allocations)
	if raw.get("fame","なし") is String: result["fame"] = str(raw.get("fame","なし")).left(40)
	# This prototype has a fixed starter loadout. No inventory or skill-growth
	# values from a display snapshot can grant equipment or a combat advantage.
	return result


static func _effective_stats(job: String, allocations: Dictionary) -> Dictionary:
	var result := {}
	for key in STAT_KEYS:
		var base: int = 100 if key in ["HP","MP"] else 10
		# Keep the allocation itself as an integer and calculate tenths exactly;
		# rounding every +1 point would otherwise erase the class's +10% bonus.
		var tenths: int = base*10+int(allocations[key])*(11 if JOBS[job]["bonus"]==key else 10)
		result[key] = float(tenths)/10.0
	return result


static func _whole(value: Variant, minimum: int, maximum: int) -> int:
	if typeof(value) not in [TYPE_INT,TYPE_FLOAT]: return -1
	if typeof(value)==TYPE_FLOAT and (not is_finite(value) or floorf(value)!=value): return -1
	if value < minimum or value > maximum: return -1
	return int(value)
