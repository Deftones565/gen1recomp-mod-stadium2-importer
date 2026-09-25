package.path="./?.lua;./?/init.lua;"..package.path
local E=require("mods.STADIUM2_IMPORTER.lib.extract")
local P=require("mods.STADIUM2_IMPORTER.lib.pack")
local f=assert(io.open(assert(arg[1],"ROM path required"),"rb"))
local rom=f:read("*a");f:close()
local doll
local job=E.newJob(rom,function() return true end,function(name,bytes)
  if name=="substitute" then
    doll=assert(P.parse(bytes))
    assert(doll.species==252 and #doll.bones==24 and #doll.prims>2,
      "Substitute must be the articulated Pokédoll, never the Egg")
    local idle=P.contextIndex(doll,"idle")
    local hit=P.contextIndex(doll,"hit")
    assert(idle and hit and idle~=hit,"Substitute idle must not loop the hit clip")
    assert(doll.anims[idle].frames==1 and next(doll.anims[idle].tracks)==nil,
      "Substitute idle must hold its bind pose")
    assert(doll.anims[hit].frames==94,"authored hit reaction was lost")
    local Actor=require("mods.STADIUM2_IMPORTER.lib.battle_actor")
    local actor=Actor.new("player")
    local selected,looped
    actor.renderer={setContext=function(_,name,loop)
      selected=P.contextIndex(doll,name);looped=loop;return selected~=nil
    end,setHandlerRuntime=function() end,step=function() end}
    assert(actor:play("idle",true) and selected==idle and looped)
    assert(actor:hit() and selected==hit and not looped,"hit must play once")
    actor.renderer.finished=true
    actor:update(1/30)
    assert(actor.context=="idle" and selected==idle and looped,
      "completed hit must return to stationary idle")
  end
  return true
end,{species={}})
while job:step() do end
assert(job.success,job.error)
assert(doll,"Substitute pack was not built")
print("Production special import: Pokédoll record 252, skeleton and pack validation passed")
