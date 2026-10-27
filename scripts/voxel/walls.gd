extends RefCounted
## Monumental half-metre fortifications: four distinct gatehouses, a wide
## continuous fighting deck, projecting shooting terraces and four stairways.
## This generator only describes solid cells; exposed-face greedy meshing is
## performed by the shared volume, so there is no node for every little block.

const BASE_Y := 4
const WALK_Y := 48
const HALF := 320
const CORNER := float(HALF) * (sqrt(2.0) - 1.0)
const STONE := 4
const LIGHT := 5
const DARK := 6
const BLUE := 7
const BLUE_LIGHT := 8
const WOOD := 9
const WOOD_DARK := 10
const GOLD := 17
const MOSS := 18
const CREAM := 20

var _v: Variant
var _writes := 0
var _columns := 0
var _stairs: Array[Dictionary] = []
var _shooting_positions: Array[Dictionary] = []
var _vertices := PackedVector2Array([
    Vector2(-CORNER,-HALF),Vector2(CORNER,-HALF),Vector2(HALF,-CORNER),Vector2(HALF,CORNER),
    Vector2(CORNER,HALF),Vector2(-CORNER,HALF),Vector2(-HALF,CORNER),Vector2(-HALF,-CORNER)])


func build(volume: Variant) -> Dictionary:
    _v=volume
    _writes=0
    _columns=0
    _stairs.clear()
    _shooting_positions.clear()
    for i in range(8):
        var a:=_vertices[i]
        var b:=_vertices[(i+1)%8]
        _wall_span(a,b)
        var tangent:=(b-a).normalized()
        var outward:=Vector2(tangent.y,-tangent.x)
        if i%2==1:
            _bastion((a+b)*0.5,tangent,outward)
        else:
            _bastion(a.lerp(b,0.22),tangent,outward)
            _bastion(a.lerp(b,0.78),tangent,outward)
        if i==5 or i==7:
            _hoarding(a.lerp(b,0.68),tangent,outward)
    for i in range(8):
        var q:=_vertices[i]
        _tower(roundi(q.x),roundi(q.y),18,76,true)
        _tower_passage(q,(_vertices[(i+7)%8]-q).normalized(),20)
        _tower_passage(q,(_vertices[(i+1)%8]-q).normalized(),20)
    var gate_data: Array[Dictionary]=[
        {"id":"north_gate","title":"北・王城門","c":Vector2i(0,-HALF),"t":Vector2i(1,0),"n":Vector2i(0,-1)},
        {"id":"east_gate","title":"東・海望門","c":Vector2i(HALF,0),"t":Vector2i(0,1),"n":Vector2i(1,0)},
        {"id":"south_gate","title":"南・戴冠門","c":Vector2i(0,HALF),"t":Vector2i(-1,0),"n":Vector2i(0,1)},
        {"id":"west_gate","title":"西・鉄衛門","c":Vector2i(-HALF,0),"t":Vector2i(0,-1),"n":Vector2i(-1,0)}]
    var gates: Array[Dictionary]=[]
    for i in range(gate_data.size()):
        var gate: Dictionary=gate_data[i]
        _gatehouse(gate["c"],gate["t"],gate["n"],i)
        var q: Vector2i=gate["c"]
        gates.append({"id":gate["id"],"title":gate["title"],"position":Vector3(q.x*0.5,2,q.y*0.5),"kind":"gate"})
    for i in [5,7,1,3]:
        _stair(_vertices[i],_vertices[(i+1)%8],i)
    var vertices_world:=PackedVector2Array()
    for q in _vertices:
        vertices_world.append(q*0.5)
    return {"city_vertices":vertices_world,"city_half_extent":HALF*0.5,"gates":gates,
        "stairs":_stairs[0],"stairways":_stairs.duplicate(true),"staircases":_stairs.duplicate(true),
        "shooting_positions":_shooting_positions.duplicate(true),"wall_walk_height":WALK_Y*0.5,
        "wall_walk_clear_width":5.0,"wall_thickness":7.0,"corner_towers":8,"gatehouses":4,"gate_towers":8,
        "projecting_bastions":12,"covered_hoardings":3,"corner_roof_peak":49.0,
        "wall_columns":_columns,"voxel_writes":_writes}


func _put(x: int,y: int,z: int, material: int) -> void:
    _v.set_voxel(Vector3i(x,y,z),material)
    _writes += 1


func _column(x: int,z: int,y0: int,y1: int,material: int) -> void:
    if y1 <= y0:
        return
    _v.box(Vector3i(x,y0,z),Vector3i(x+1,y1,z+1),material)
    _writes += y1-y0


func _erase_column(x: int,z: int,y0: int,y1: int) -> void:
    _v.erase_box(Vector3i(x,y0,z),Vector3i(x+1,y1,z+1))


func _wall_span(a: Vector2,b: Vector2) -> void:
    var tangent := (b-a).normalized()
    var outward := Vector2(tangent.y,-tangent.x)
    var length := a.distance_to(b)
    var min_x := floori(minf(a.x,b.x))-13
    var max_x := ceili(maxf(a.x,b.x))+13
    var min_z := floori(minf(a.y,b.y))-13
    var max_z := ceili(maxf(a.y,b.y))+13
    for x in range(min_x,max_x):
        for z in range(min_z,max_z):
            var p := Vector2(x+0.5,z+0.5)
            var t := (p-a).dot(tangent)
            if t < 0 or t > length:
                continue
            var distance := (p-a).dot(outward)
            var d := absf(distance)
            if d > 12.0:
                continue
            # A broad, stepped plinth gives the wall real weight at ground level.
            if d <= 10.0:
                _column(x,z,BASE_Y,BASE_Y+2,DARK)
            if d <= 8.5:
                _column(x,z,BASE_Y+2,BASE_Y+4,STONE)
            if d <= 7.0:
                _columns += 1
                _column(x,z,BASE_Y+4,WALK_Y,STONE)
                _column(x,z,BASE_Y+4,BASE_Y+5,LIGHT)
                _column(x,z,WALK_Y-3,WALK_Y-2,LIGHT)
                _column(x,z,WALK_Y-1,WALK_Y,DARK)
                if d > 5.0:
                    # Large masonry courses remain mergeable; no per-voxel noise.
                    for y in range(BASE_Y+5,WALK_Y-3,3):
                        var course := floori(float(y)/3.0)
                        var block_index := floori((t+float(course%2)*3.0)/6.0)
                        var hash_value := posmod(block_index*13+course*7,23)
                        if hash_value == 2 or hash_value == 3:
                            _column(x,z,y,mini(y+3,WALK_Y-3),LIGHT)
                        elif hash_value == 14:
                            _column(x,z,y,mini(y+3,WALK_Y-3),DARK)
                    _column(x,z,WALK_Y,WALK_Y+2,STONE)
                    if posmod(floori(t/3.0),2)==0:
                        _column(x,z,WALK_Y+2,WALK_Y+5,LIGHT)
                    # Arrow loops are recesses, not flat painted windows.
                    if distance > 5.5 and posmod(floori(t),28)==12:
                        _erase_column(x,z,18,23)
                if d > 6.5 and posmod(floori(t/9.0)+floori(float(x)/5.0),17)==0:
                    _column(x,z,BASE_Y+2,BASE_Y+4,MOSS)
            # The outer buttresses taper through three steps into the wall body.
            if distance > 7.0 and fposmod(t+4.0,28.0)<4.0:
                if distance < 12.0:
                    _column(x,z,BASE_Y+2,18,DARK)
                if distance < 10.5:
                    _column(x,z,18,31,STONE)
                if distance < 9.0:
                    _column(x,z,31,39,LIGHT)


func _inside_oct(x: float,z: float,radius: int) -> bool:
    return absf(x)<=radius and absf(z)<=radius and absf(x)+absf(z)<=float(radius)*1.41421356


func _tower(cx: int,cz: int,radius: int,top: int,corner_tower: bool) -> void:
    for x in range(cx-radius-2,cx+radius+2):
        for z in range(cz-radius-2,cz+radius+2):
            var dx := float(x)+0.5-cx
            var dz := float(z)+0.5-cz
            if _inside_oct(dx,dz,radius+2):
                _column(x,z,BASE_Y,BASE_Y+3,DARK)
            if not _inside_oct(dx,dz,radius):
                continue
            var outer_ring := not _inside_oct(dx,dz,radius-4)
            if outer_ring:
                _column(x,z,BASE_Y+3,top,STONE)
                _column(x,z,BASE_Y+5,BASE_Y+6,LIGHT)
                _column(x,z,top-5,top-3,LIGHT)
                _column(x,z,top-2,top,DARK)
                if posmod(floori((dx+dz)/4.0),7)==2:
                    _column(x,z,12,15,LIGHT)
                # Deep, narrow arrow slits on four faces of the tower.
                if ((absf(dx)<1.0 and absf(dz)>radius-2.0) or (absf(dz)<1.0 and absf(dx)>radius-2.0)):
                    _erase_column(x,z,top-16,top-7)
            # The accessible floor meets the wall walk, not an isolated upper room.
            _column(x,z,WALK_Y-1,WALK_Y,DARK)
            _column(x,z,top-14,top-13,WOOD)
    # A stepped eave and a faceted blue roof are made entirely of voxel cells.
    for layer in range(radius+2):
        var r := radius+2-layer
        var y := top+layer
        for x in range(cx-r,cx+r):
            for z in range(cz-r,cz+r):
                if _inside_oct(x+0.5-cx,z+0.5-cz,r):
                    var material := BLUE_LIGHT if layer%5==0 else BLUE
                    _put(x,y,z,material)
    _v.box(Vector3i(cx-1,top+radius+1,cz-1),Vector3i(cx+1,top+radius+4,cz+1),GOLD)
    if corner_tower:
        # Broad crest panels, set into the upper tower rather than floating signs.
        for side in [-1,1]:
            _v.box(Vector3i(cx-2,top-12,cz+side*(radius-1)),Vector3i(cx+2,top-5,cz+side*(radius-1)+1),BLUE)
            _v.box(Vector3i(cx-1,top-10,cz+side*(radius-1)-1),Vector3i(cx+1,top-7,cz+side*(radius-1)+2),CREAM)


func _tower_passage(center: Vector2,direction: Vector2,radius: int) -> void:
    var normal := Vector2(-direction.y,direction.x)
    for x in range(floori(center.x)-radius,ceili(center.x)+radius):
        for z in range(floori(center.y)-radius,ceili(center.y)+radius):
            var p := Vector2(x+0.5,z+0.5)-center
            if p.dot(direction)>=-1.0 and absf(p.dot(normal))<4.0:
                _erase_column(x,z,WALK_Y,WALK_Y+8)


func _gatehouse(center: Vector2i,tangent: Vector2i,normal: Vector2i,style: int) -> void:
    var top:=70 if style==0 else 64
    for u in range(-27,28):
        for n in range(-14,15):
            var p:=center+tangent*u+normal*n
            if abs(u)>=24 or abs(n)>=11:
                _column(p.x,p.y,BASE_Y,top,STONE)
                for band in [10,28,top-6]:
                    _column(p.x,p.y,band,band+2,LIGHT)
            _column(p.x,p.y,WALK_Y-2,WALK_Y,DARK)
            if absf(float(u)+0.5)<11:
                var crown:=20+floori(sqrt(maxf(0.0,121-pow(float(u)+0.5,2))))
                _erase_column(p.x,p.y,BASE_Y,crown)
                if abs(n)>=10:
                    _column(p.x,p.y,crown,crown+2,LIGHT)
                if abs(n)>=13:
                    _column(p.x,p.y,crown+2,crown+3,DARK)
            if abs(u)>=24 and abs(n)<5:
                _erase_column(p.x,p.y,WALK_Y,WALK_Y+9)
            if abs(n)>=11 and ((u>=-15 and u<=-12) or (u>=11 and u<=14)):
                _erase_column(p.x,p.y,WALK_Y+3,WALK_Y+11)
            if abs(n)>12 and posmod(u+27,7)<2:
                _column(p.x,p.y,WALK_Y-5,WALK_Y-2,DARK)
    for layer in range(16):
        for u in range(-30,31):
            for n in range(-16+layer,17-layer):
                var p:=center+tangent*u+normal*n
                _put(p.x,top+layer,p.y,BLUE_LIGHT if layer<2 else BLUE)
    for side in [-1,1]:
        var p: Vector2i=center+tangent*side*36
        _tower(p.x,p.y,14,top+3,false)
        _tower_passage(Vector2(p),Vector2(tangent),17)
        _tower_passage(Vector2(p),Vector2(-tangent),17)
    for u in range(-10,11,4):
        var p:=center+tangent*u+normal*15
        _column(p.x,p.y,31,45,WOOD_DARK)
    for y in [34,41,45]:
        for u in range(-11,12):
            var p:=center+tangent*u+normal*16
            _put(p.x,y,p.y,WOOD)
    for side in [-1,1]:
        var p: Vector2i=center+tangent*side*20+normal*15
        _banner(Vector2(p),Vector2(tangent),WALK_Y-15,8)
    _crest(center+normal*15,tangent,WALK_Y+4,10)
    if style==0:
        _bell_gable(center,tangent,normal,top+12)
    elif style==1:
        _gate_terrace(center,tangent,normal)
    elif style==2:
        for u in [-20,-10,0,10,20]:
            var p: Vector2i=center+tangent*u
            _column(p.x,p.y,top+12,top+18-int(abs(u)/10),GOLD)
    else:
        _hoarding(Vector2(center)+Vector2(normal)*8,Vector2(tangent),Vector2(normal))


func _bastion(center: Vector2,tangent: Vector2,outward: Vector2) -> void:
    for x in range(floori(center.x)-19,ceili(center.x)+19):
        for z in range(floori(center.y)-19,ceili(center.y)+19):
            var p:=Vector2(x+0.5,z+0.5)-center
            var u:=p.dot(tangent)
            var n:=p.dot(outward)
            if absf(u)>12 or n<5 or n>16:
                continue
            if n<10:
                _column(x,z,BASE_Y,WALK_Y,DARK if n<7 else STONE)
            _column(x,z,WALK_Y-3,WALK_Y,LIGHT)
            if n>14 or absf(u)>10:
                _column(x,z,WALK_Y,WALK_Y+2,STONE)
                if posmod(floori(u+12),6)<3:
                    _column(x,z,WALK_Y+2,WALK_Y+5,LIGHT)
            if n>=5 and n<8 and absf(u)<7:
                _erase_column(x,z,WALK_Y,WALK_Y+7)
    var foot := (center+tangent*4+outward*12)*0.5
    var target := foot+outward*20
    _shooting_positions.append({"position":Vector3(foot.x,WALK_Y*0.5,foot.y),
        "aim_point":Vector3(target.x,WALK_Y*0.5+0.5,target.y),
        "outward":Vector3(outward.x,0,outward.y),"eye_height":1.65})


func _hoarding(center: Vector2,tangent: Vector2,outward: Vector2) -> void:
    for x in range(floori(center.x)-25,ceili(center.x)+25):
        for z in range(floori(center.y)-25,ceili(center.y)+25):
            var p:=Vector2(x+0.5,z+0.5)-center
            var u:=p.dot(tangent)
            var n:=p.dot(outward)
            if absf(u)>19 or n<4 or n>12:
                continue
            _column(x,z,WALK_Y-1,WALK_Y,WOOD_DARK)
            if absf(u)>17 or n>10:
                _column(x,z,WALK_Y,WALK_Y+2,WOOD)
                if fposmod(u+19,8)<1.5:
                    _column(x,z,WALK_Y+2,WALK_Y+10,WOOD_DARK)
            if n>10 and fposmod(u+19,8)<3:
                _column(x,z,WALK_Y-6,WALK_Y-1,WOOD_DARK)
            var roof_height:=WALK_Y+10+floori((4-absf(n-8))*0.8)
            _column(x,z,roof_height,roof_height+1,BLUE)
            if n<7 and absf(u)<17:
                _erase_column(x,z,WALK_Y,WALK_Y+8)


func _gate_terrace(center: Vector2i,tangent: Vector2i,normal: Vector2i) -> void:
    for u in range(-18,19):
        for n in range(13,28):
            var p:=center+tangent*u+normal*n
            _column(p.x,p.y,WALK_Y-3,WALK_Y,LIGHT)
            if abs(u)>16 or n>25:
                _column(p.x,p.y,WALK_Y,WALK_Y+2,STONE)
                if posmod(u+18,6)<3:
                    _column(p.x,p.y,WALK_Y+2,WALK_Y+5,LIGHT)
            if abs(u)<8 and n<15:
                _erase_column(p.x,p.y,WALK_Y,WALK_Y+7)
            if abs(u)>13 and n<24:
                _column(p.x,p.y,WALK_Y-8,WALK_Y-3,DARK)


func _bell_gable(center: Vector2i,tangent: Vector2i,normal: Vector2i,y: int) -> void:
    for u in range(-5,6):
        for n in range(-3,4):
            var p:=center+tangent*u+normal*n
            if abs(u)>3:
                _column(p.x,p.y,y,y+10,LIGHT)
            _column(p.x,p.y,y+10-abs(u),y+12-abs(u),BLUE)
    var bell:=center+normal*2
    _v.box(Vector3i(bell.x-1,y+2,bell.y-1),Vector3i(bell.x+2,y+6,bell.y+2),GOLD)
    _v.box(Vector3i(bell.x-2,y+1,bell.y-2),Vector3i(bell.x+3,y+2,bell.y+3),GOLD)


func _crest(center: Vector2i,tangent: Vector2i,y: int,width: int) -> void:
    for u in range(-width/2,width/2+1):
        var p:=center+tangent*u
        var lower:=y+int(abs(u)/2)
        _column(p.x,p.y,lower,y+width+1,BLUE)
        if abs(u)<2:
            _column(p.x,p.y,lower+2,y+width-1,CREAM)
        if abs(u)<=3:
            _put(p.x,y+width-3,p.y,CREAM)
    for u in range(-width/2-1,width/2+2):
        var p:=center+tangent*u
        _put(p.x,y+width+1,p.y,GOLD)


func _banner(center: Vector2,tangent: Vector2,y: int,width: int) -> void:
    for u in range(-width/2,width/2+1):
        var p:=center+tangent*u
        _column(roundi(p.x),roundi(p.y),y+abs(u)%3,y+13,BLUE)
        if abs(u)<1:
            _column(roundi(p.x),roundi(p.y),y+3,y+11,CREAM)


func _stair(a: Vector2,b: Vector2,edge: int) -> void:
    var tangent:=(b-a).normalized()
    var outward:=Vector2(tangent.y,-tangent.x)
    var origin:=a+tangent*74-outward*12
    var run:=(WALK_Y-BASE_Y)*2
    var end:=origin+tangent*run
    for x in range(floori(minf(origin.x,end.x))-7,ceili(maxf(origin.x,end.x))+7):
        for z in range(floori(minf(origin.y,end.y))-7,ceili(maxf(origin.y,end.y))+7):
            var p:=Vector2(x+0.5,z+0.5)-origin
            var along:=p.dot(tangent)
            var side:=p.dot(outward)
            if along<0 or along>=run or absf(side)>4:
                continue
            var top:=BASE_Y+1+floori(along/2)
            _column(x,z,BASE_Y,top,STONE)
            _column(x,z,top-1,top,DARK)
            if absf(side)>3:
                _column(x,z,top,top+2,LIGHT)
    for x in range(floori(end.x)-20,ceili(end.x)+20):
        for z in range(floori(end.y)-20,ceili(end.y)+20):
            var p:=Vector2(x+0.5,z+0.5)-end
            var along:=p.dot(tangent)
            var side:=p.dot(outward)
            if along < -2 or along>7 or side < -4 or side>17:
                continue
            _column(x,z,WALK_Y-2,WALK_Y,DARK)
            if side>=4 and along<5:
                _erase_column(x,z,WALK_Y,WALK_Y+8)
            if (along>5 or side < -3) and side<10:
                _column(x,z,WALK_Y,WALK_Y+2,LIGHT)
    var bottom:=origin*0.5
    var top:=end*0.5
    _stairs.append({"id":"wall_stair_%d"%edge,"bottom":Vector3(bottom.x,2,bottom.y),"top":Vector3(top.x,24,top.y),"direction":Vector3(tangent.x,0,tangent.y),"width":3.0,"step_height":0.5,"step_depth":1.0})
