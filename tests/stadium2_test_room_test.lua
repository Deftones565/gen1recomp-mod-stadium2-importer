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
print(("%d checks passed (Stadium 2 test room)"):format(checks))
