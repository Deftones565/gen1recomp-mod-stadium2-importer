package.path="./?.lua;./?/init.lua;"..package.path
-- Test room entry points: the game OPTIONS action row and a safe refusal
-- when there is no running game.
local Room=require("mods.STADIUM2_IMPORTER.lib.test_room")
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end
local row=Room.optionsRow({})
ok(row.label=="FX TEST ROOM" and row.value()=="OPEN","options row reads FX TEST ROOM / OPEN")
ok(type(row.activate)=="function" and row.stadium2TestRoom==true,"options row is an action row")
ok(Room.open(nil)==false and Room.isOpen()==false,"no game: the room does not open")
Room.closeCurrent()
ok(Room.isOpen()==false,"closeCurrent is safe when nothing is open")
-- Classic/Kenney scenes put the player on +Z facing -Z; effects see Stadium's
-- layout (player on -X, yaw +90 degrees). Arenas pass through unchanged.
local Adapter=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter")
local function rotY(a,x,z) local c,s=math.cos(a),math.sin(a) return {c,0,s,x,0,1,0,0,-s,0,c,z,0,0,0,1} end
local host={modelMatrix=function(_,side) if side=="player" then return rotY(math.pi,0,24),math.pi end return rotY(0,0,-24),0 end}
local ext={scene={host=host,arena=false},world={actorSlots={player={position={0,0,24}},enemy={position={0,0,-24}}}},
  camera={eye={0,8,40},focus={0,0,0},view={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}}}
local f=Adapter.stadiumFrame(ext)
ok(f.world.actorSlots.player.x==-24 and f.world.actorSlots.enemy.x==24,"battlers sit on Stadium's X axis")
local m,yaw=f.scene.host:modelMatrix("player")
ok(math.abs(yaw-math.pi/2)<1e-9 and math.abs(m[4]+24)<1e-9,"player faces +X like Stadium's layout")
ok(Adapter.stadiumFrame({scene={host=host,arena=true}}).scene.host==host,"arena scenes pass through")
print(("%d checks passed (Stadium 2 test room)"):format(checks))
