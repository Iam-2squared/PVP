extends SceneTree
## Real progression/save invariants; no client or display-only EXP grant.
const Progression = preload("res://scripts/battle/progression.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var first := Progression.new_profile("player-a","冒険者","warrior",false)
	_check(first.level==1 and first.exp==0 and first.unspent_points==0,"New real profile must start at Lv1 with no EXP/points")
	_check(first.stats.HP==100 and first.stats.MP==100,"New real profile has playable HP and MP")
	_check(first.owned_weapons.size()==1 and first.owned_weapons[0].equipped,"Initial combat weapon must match displayed inventory")
	var original := first.duplicate(true)
	var second := Progression.award_player_kill(first,1)
	_check(second.level==2 and second.exp==0 and second.unspent_points==5 and second.kills==1,"One Lv1 player kill must cross the 100 EXP first threshold")
	_check(first==original,"Award mutated the caller's old saved profile")
	var paid := Progression.allocate(second,"筋力",1)
	_check(paid.unspent_points==4 and paid.allocations["筋力"]==1,"Allocation must spend exactly one earned point")
	_check(is_equal_approx(paid.stats["筋力"],11.1),"A single warrior strength point must retain its +10% fraction")
	_check(second.unspent_points==5 and second.allocations["筋力"]==0,"Allocation mutated its input profile")
	var endurance := Progression.allocate(paid,"耐久力",2)
	_check(endurance.unspent_points==2 and is_equal_approx(endurance.stats["耐久力"],12.0),"Unbonused points should retain their actual integer effect")
	var third := Progression.award_player_kill(endurance,7)
	_check(third.level==4 and third.exp==200 and third.unspent_points==12 and third.kills==2,"A high-level kill must preserve EXP across several thresholds")
	_check(Progression.experience_required(4)==400,"Next threshold must use current level times 100")
	var saved: Variant = JSON.parse_string(JSON.stringify(third))
	var restored := Progression.normalize_profile(saved)
	_check(restored==third,"JSON save/load lost allocated fractional growth, unspent points or EXP carry")
	var forged := third.duplicate(true)
	forged.stats["筋力"] = 999999
	_check(is_equal_approx(Progression.normalize_profile(forged).stats["筋力"],11.1),"Derived stats must be reconstructed instead of trusting saved/client cache")
	for points in [-1,0,1.5,"1",true,INF,NAN,999999]:
		_check(Progression.allocate(third,"HP",points).is_empty(),"Invalid/overspending allocation was accepted: "+str(points))
	_check(Progression.allocate(third,"魔力",1).is_empty(),"Unknown stat was accepted")
	for victim_level in [-1,0,1.5,"1",true,INF,NAN]:
		_check(Progression.award_player_kill(third,victim_level).is_empty(),"Invalid victim level was accepted: "+str(victim_level))
	for change in [{"key":"level","value":0},{"key":"level","value":-1},{"key":"level","value":1.5},{"key":"exp","value":-1},{"key":"exp","value":400},{"key":"unspent_points","value":-1},{"key":"unspent_points","value":999999},{"key":"job_id","value":"fake"},{"key":"female","value":"yes"},{"key":"kills","value":-1}]:
		var invalid := third.duplicate(true)
		invalid[change.key] = change.value
		_check(not Progression.validate_profile(invalid),"Corrupt persisted field was accepted: "+str(change.key)+"="+str(change.value))
	var invalid_allocations := third.duplicate(true)
	invalid_allocations.allocations["筋力"] = -1
	_check(not Progression.validate_profile(invalid_allocations),"Negative allocated points were accepted")
	invalid_allocations = third.duplicate(true)
	invalid_allocations.allocations["筋力"] = 999999
	_check(not Progression.validate_profile(invalid_allocations),"Allocated points exceeded earned progression budget")
	invalid_allocations = third.duplicate(true)
	invalid_allocations.allocations["魔力"] = 0
	_check(not Progression.validate_profile(invalid_allocations),"Unknown persisted allocation key was accepted")
	for job in Progression.JOBS:
		var candidate := Progression.award_player_kill(Progression.new_profile("test-"+job,"冒険者",job,true),1)
		var bonus_key: String = Progression.JOBS[job].bonus
		var base: float = candidate.stats[bonus_key]
		candidate = Progression.allocate(candidate,bonus_key,1)
		_check(is_equal_approx(candidate.stats[bonus_key]-base,1.1),"Job bonus was lost: "+str(job))
		_check(Progression.normalize_profile(JSON.parse_string(JSON.stringify(candidate)))==candidate,"Job profile did not survive a save roundtrip: "+str(job))
	_check(Progression.new_profile("").is_empty(),"Empty player identity was accepted")
	_check(not Progression.validate_profile(null) and not Progression.validate_profile({}),"Missing save was accepted as an earned profile")
	print("PROGRESSION_TEST_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
