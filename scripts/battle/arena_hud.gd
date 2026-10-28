extends "res://scripts/battle/arena_controls_base.gd"
## Native multitouch controls reused from the character playground.
signal home_requested
var profile: Dictionary={}
var players_count:=0
var connection_text:="接続中…":
	set(value):
		if connection_text==value:return
		connection_text=value
		_request_redraw()
var alive:=false:
	set(value):
		if alive==value:return
		alive=value
		_request_redraw()
var protected_spawn:=false
var max_hp:=100.0
var max_mp:=100.0
const SKILL_NAMES:Dictionary={"warrior":"強撃","mage":"火炎爆発","scout":"急所突き","archer":"貫通矢","cleric":"ヒール","artisan":"投擲爆弾"}

func _ready()->void:
	super._ready()
	_font=load("res://assets/frontend/ui.otf")
	_canvas.name="ArenaControls"

func _build_control_rects(view:Vector2,s:float)->Dictionary:
	var rects:Dictionary=super._build_control_rects(view,s)
	rects.erase("equipment")
	rects.erase("selection")
	rects["home"]=Rect2(Vector2(view.x-165*s,22*s),Vector2(137,46)*s)
	return rects

func _emit_tap(owner:String)->void:
	if owner=="home": home_requested.emit()
	else: super._emit_tap(owner)

func get_move_vector()->Vector2:
	return move_vector

func _feedback_fades()->bool:
	return false

func set_profile(value:Dictionary)->void:
	if profile==value:return
	profile=value.duplicate(true)
	_skill_name=str(SKILL_NAMES.get(str(profile.get("job_id","warrior")),"強撃"))
	_request_redraw()

func set_battle_status(data:Dictionary,count:int)->void:
	var next_alive:=bool(data.get("alive",false))
	var next_protected:=bool(data.get("spawn_protected",false))
	var next_max_hp:=maxf(1,float(data.get("max_hp",100)))
	var next_max_mp:=maxf(1,float(data.get("max_mp",100)))
	var next_hp:=float(data.get("hp",0))
	var next_mp:=float(data.get("mp",0))
	if players_count==count and alive==next_alive and protected_spawn==next_protected and max_hp==next_max_hp and max_mp==next_max_mp and _hp==next_hp and _mp==next_mp and connection_text.is_empty():return
	players_count=count
	alive=next_alive
	protected_spawn=next_protected
	max_hp=next_max_hp
	max_mp=next_max_mp
	_hp=next_hp
	_mp=next_mp
	connection_text=""
	_request_redraw()

func _draw_hud(canvas:Control)->void:
	var view:=_viewport_size()
	var s:=_layout_scale()
	var rects:=_control_rects()
	var left:=30*s
	var level:=int(profile.get("level",1))
	var exp:=int(profile.get("exp",0))
	var kills:=int(profile.get("kills",0))
	var deaths:=int(profile.get("deaths",0))
	_text(canvas,"王都セレシア  /  時間無制限",Vector2(left,36*s),int(13*s),MUTED)
	_text(canvas,"%s   Lv.%d"%[str(profile.get("username","冒険者")),level],Vector2(left,65*s),int(21*s))
	_text(canvas,"HP  %d / %d"%[int(_hp),int(max_hp)],Vector2(left,87*s),int(12*s))
	_meter(canvas,Rect2(Vector2(left,96*s),Vector2(190,5)*s),_hp/max_hp,Color("88b99a"))
	_text(canvas,"MP  %d / %d"%[int(_mp),int(max_mp)],Vector2(left,120*s),int(12*s))
	_meter(canvas,Rect2(Vector2(left,129*s),Vector2(190,4)*s),_mp/max_mp,Color("82a8ca"))
	_text(canvas,"EXP %d / %d   撃破 %d / ダウン %d"%[exp,level*100,kills,deaths],Vector2(left,151*s),int(12*s),GOLD)
	_panel(canvas,rects["home"])
	_center_text(canvas,"ホームへ戻る",rects["home"].get_center()+Vector2(0,5*s),int(14*s))
	_draw_stick(canvas,rects["stick"],s)
	_draw_round_button(canvas,rects["attack"],"攻撃","1回 / 2回","attack",s)
	_draw_round_button(canvas,rects["jump"],"跳ぶ","SPACE","jump",s)
	_draw_round_button(canvas,rects["skill"],"スキル",_skill_name,"skill",s)
	var center:=view*0.5
	canvas.draw_circle(center,2.4*s,Color(0.03,0.04,0.05,0.5))
	canvas.draw_circle(center,1.3*s,Color(0.97,0.96,0.87,0.95))
	if _feedback_remaining>0:
		_center_text(canvas,_feedback,center+Vector2(0,45*s),int(17*s),GOLD if _feedback_strong else PAPER)
	var message:=connection_text
	if message.is_empty():
		if not alive: message="倒されました · 門の内側でリスポーンします"
		elif protected_spawn: message="リスポーン保護中 · 攻撃すると解除されます"
		elif players_count<2: message="他のプレイヤーの参加を待っています"
	if not message.is_empty():
		_center_text(canvas,message,Vector2(view.x*0.5,77*s),int(15*s),PAPER)
	_center_text(canvas,"WASD 移動  ·  マウス 視点  ·  Space ジャンプ  ·  Esc マウス解除",Vector2(view.x*0.5,view.y-20*s),int(11*s),MUTED)
