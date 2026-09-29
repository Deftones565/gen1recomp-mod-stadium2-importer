package.path="./?.lua;./?/init.lua;"..package.path
-- Regression: models invisible in Kenney scenes on a player's Android phone
-- (fine on classic, fine on the developer's own Android).
--
-- Only Kenney scenes hand the model shader a lighting binder
-- (battle_scene.lua: bindTorchLighting=environmentScene.bindTorchLighting).
-- A throw in it failed drawScene: the scene marked that side "native" and
-- drew no model. LOVE's Shader:send throws for a uniform the driver optimised
-- out, and which unused uniforms a driver keeps differs between GPUs; each
-- binder guarded one uniform only and sent the rest unguarded.
--
-- Every binder here gets a shader that behaves like LOVE's (send throws for a
-- missing uniform), with one of its uniforms missing at a time.
local checks,failures=0,{}
local function ok(v,m)
  checks=checks+1
  if not v then failures[#failures+1]=m end
end

local function shaderWithout(missing,sent)
  return {
    hasUniform=function(_,name) return name~=missing end,
    send=function(_,name,...)
      if name==missing then
        error(("Shader uniform '%s' does not exist.\nA common error is to define but not use the variable."):format(name),2)
      end
      sent[name]=true
    end,
  }
end

-- the uniforms each binder sends when everything is present
local function uniformsSent(bind)
  local sent={}
  bind(shaderWithout(nil,sent))
  local list={}
  for name in pairs(sent) do list[#list+1]=name end
  table.sort(list)
  return list
end

local F=require("mods.STADIUM2_IMPORTER.lib.battle_fireflies")
local binders={
  {"grass (Nature torches)",require("mods.STADIUM2_IMPORTER.lib.battle_nature").bindTorchLighting},
  {"cave (torches)",require("mods.STADIUM2_IMPORTER.lib.battle_cave").bindTorchLighting},
  {"town (lamps)",require("mods.STADIUM2_IMPORTER.lib.battle_town").bindTorchLighting},
  {"freshwater (fireflies, night)",function(s) F.update({daytime="NITE"},8) return F.bindLighting(s) end},
}

for _,b in ipairs(binders) do
  local label,bind=b[1],b[2]
  local names=uniformsSent(bind)
  ok(#names>0,label..": sends model uniforms")
  for _,missing in ipairs(names) do
    local okBind,err=pcall(bind,shaderWithout(missing,{}))
    ok(okBind,("%s: the driver dropped '%s' and the binder threw (%s), so drawScene fails and the model is not drawn")
      :format(label,missing,tostring(err):match("^[^\n]*")))
  end
end

-- and whatever a binder does, drawScene keeps the model: the binder runs in
-- its own pcall inside the model pass
local source=assert(io.open("mods/STADIUM2_IMPORTER/lib/renderer.lua","rb")):read("*a")
ok(source:find("pcall(options.bindTorchLighting, self.shader)",1,true)~=nil,
  "drawScene isolates the scene's lighting binder from the model draw")

if #failures>0 then
  for _,m in ipairs(failures) do print("FAIL "..m) end
  error(("%d of %d checks failed (Kenney model lighting binders)"):format(#failures,checks),0)
end
print(checks.." checks passed (Kenney model lighting binders)")
