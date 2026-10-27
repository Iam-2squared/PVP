extends SceneTree
const HUD=preload("res://scripts/battle/arena_hud.gd")
var jumps:=0
var presses:=0
var failures:Array=[]
var checks:=0
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures.append(message)
func _initialize():run.call_deferred()
func touch_at(pos:Vector2,index:int,pressed:bool):
	var e:=InputEventScreenTouch.new();e.position=pos;e.index=index;e.pressed=pressed
	root.push_input(e,true)
func click_at(pos:Vector2):
	var move:=InputEventMouseMotion.new();move.position=pos;move.global_position=pos
	root.push_input(move,true)
	var down:=InputEventMouseButton.new();down.position=pos;down.global_position=pos;down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true
	root.push_input(down,true)
	var up:=InputEventMouseButton.new();up.position=pos;up.global_position=pos;up.button_index=MOUSE_BUTTON_LEFT;up.pressed=false
	root.push_input(up,true)
func run():
	root.size=Vector2i(1280,720)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	Input.emulate_mouse_from_touch=false
	var button:=Button.new();button.text="Battle";root.add_child(button)
	button.pressed.connect(func():presses+=1)
	var hud=HUD.new();root.add_child(hud)
	hud.jump_requested.connect(func():jumps+=1)
	await process_frame
	var rect:Rect2=hud._control_rects()["jump"]
	var point:=rect.get_center()
	button.position=point-Vector2(45,22);button.size=Vector2(90,44)
	await process_frame
	hud.visible=false
	click_at(point)
	check(presses==1,"hidden HUD blocked actual underlying Button click")
	check(jumps==0,"hidden HUD emitted jump from mouse")
	touch_at(point,0,true);touch_at(point,0,false)
	check(jumps==0,"hidden HUD emitted jump from touch")
	hud.visible=true
	touch_at(point,1,true);touch_at(point,1,false)
	check(jumps==1,"visible HUD did not emit native touch jump")
	click_at(point)
	check(presses==1,"visible HUD leaked mouse into underlying Button")
	check(jumps==2,"visible HUD did not own mouse click")
	print("HIDDEN_ARENA_INPUT ",JSON.stringify({"checks":checks,"failures":failures,"jumps":jumps,"button_presses":presses,"position":point}))
	hud.queue_free();button.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
