package.path = "./?.lua;./?/init.lua;" .. package.path

local Build = require("mods.STADIUM2_IMPORTER.lib.build")
local Discovery = require("mods.STADIUM2_IMPORTER.lib.discovery")
local DynamicObject = require("mods.STADIUM2_IMPORTER.lib.effects.dynamic_object")
local Fragment26 = require("mods.STADIUM2_IMPORTER.lib.fragment26")
local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")
local Manifest = require("mods.STADIUM2_IMPORTER.lib.effects.dynamic_object_manifest")
local Pack = require("mods.STADIUM2_IMPORTER.lib.pack")
local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")

local checks, failures = 0, 0
local function check(value, message)
  checks = checks + 1
  if not value then failures=failures+1; print("FAIL "..message) end
end
local function u32(data, offset)
  local a,b,c,d=data:byte(offset+1,offset+4)
  return d and ((a*256+b)*256+c)*256+d or nil
end
local function read(path)
  local f=io.open(path,"rb"); if not f then return nil end
  local value=f:read("*a");f:close();return value
end
local function cacheRoot()
  local supplied=os.getenv("STADIUM2_CACHE_ROOT")
  local candidates={"/home/deftones/.local/share/love/pokemon-love2d/stadium2_importer"}
  if supplied then table.insert(candidates,1,supplied) end
  for _,root in ipairs(candidates) do
    if read(root.."/normal/109.dsm") then return root end
  end
end

local candidate=assert(Discovery.find(),"Stadium 2 ROM not found")
local raw=assert(Discovery.read(candidate))
local rom=assert(Rom.validate(raw))
local speciesIds={77,92,109,110,134,144,146}
local expectedEmitters={[77]=3,[92]=1,[109]=18,[110]=15,[134]=1,[144]=8,[146]=21}
local expectedTextures={[77]=8,[92]=8,[109]=8,[110]=8,[134]=1,[144]=1,[146]=8}

for _,species in ipairs(speciesIds) do
  local profile=Manifest.profile(species)
  check(profile~=nil,"missing manifest profile for species "..species)
  for stage,base in pairs(Manifest.tableBases) do
    local address=base+(species-77)*4
    local actual=u32(rom,assert(Fragment26.romOffset(address)))
    check(actual==profile.routes[stage],("species %d %s route mismatch"):format(species,stage))
  end
  check(DynamicObject.INITIALIZERS[profile.routes.initialize]~=nil,"initializer strategy missing for "..species)
  check(DynamicObject.SPAWNERS[profile.routes.spawn]~=nil,"spawn strategy missing for "..species)
  check(DynamicObject.RENDERERS[profile.routes.render]~=nil,"render strategy missing for "..species)
  check(DynamicObject.UPDATERS[profile.routes.update]~=nil,"update strategy missing for "..species)
end

check(Manifest.profile(109).routes.initialize==Manifest.profile(110).routes.initialize
  and Manifest.profile(109).routes.spawn==Manifest.profile(110).routes.spawn
  and Manifest.profile(109).routes.render==Manifest.profile(110).routes.render
  and Manifest.profile(109).routes.update==Manifest.profile(110).routes.update,
  "Koffing and Weezing must share the complete lifecycle")
check(Manifest.profile(77).routes.render==Manifest.profile(146).routes.render,
  "Ponyta and Moltres must share rendering")
check(Manifest.profile(134).routes.render==Manifest.profile(144).routes.render,
  "Vaporeon and Articuno must share rendering")

local expectedInit = {
  [77]={.002,.5,10}, [92]={20,0,3}, [109]={1,.5,10}, [110]={1,.5,10},
  [134]={.5,0,10}, [144]={.5,0,10}, [146]={.1,1,10},
}
for species,expected in pairs(expectedInit) do
  local route=Manifest.profile(species).routes.initialize
  local actual=DynamicObject.INITIALIZERS[route]
  check(math.abs(actual.initialScale-expected[1])<1e-8,"initial scale mismatch for "..species)
  check(actual.speed==expected[2],"initial speed mismatch for "..species)
  check(actual.searchSlots==expected[3],"pool search limit mismatch for "..species)
end

check(DynamicObject.spawnExpected(92,{dynamicObjectRandomValue=6}),"Gastly must spawn every invocation")
for _,species in ipairs{77,134,144,146} do
  check(DynamicObject.spawnExpected(species,{dynamicObjectRandomValue=0}),"random route zero must spawn for "..species)
  check(not DynamicObject.spawnExpected(species,{dynamicObjectRandomValue=1}),"random route nonzero must not spawn for "..species)
end
check(DynamicObject.spawnExpected(109,{dynamicObjectIndex=0,animationState=2,animationFrame=115}),
  "Koffing schedule match must spawn")
check(not DynamicObject.spawnExpected(110,{dynamicObjectIndex=0,animationState=2,animationFrame=114}),
  "Weezing schedule mismatch must not spawn")

local expectedRender = {
  [77]={5,3,235}, [92]={5,3,nil}, [109]={15,8,5}, [110]={15,8,5},
  [134]={5,3,240}, [144]={5,3,240}, [146]={5,3,235},
}
for species,expected in pairs(expectedRender) do
  local material=assert(DynamicObject.renderState(species,expected[1]))
  check(material.frame==expected[2],"texture frame mismatch for "..species)
  check(expected[3]==nil or material.alphaByte==expected[3],"render alpha mismatch for "..species)
end

local expectedUpdate = {
  [77]={1,2.75,1.1}, [92]={2,2,1}, [109]={1,2.5,1.1}, [110]={1,2.5,1.1},
  [134]={1,2,.65}, [144]={1,1.5,.65}, [146]={1,3.5,1.005},
}
for species,expected in pairs(expectedUpdate) do
  local p={active=true,age=0,x=0,y=2,z=0,vx=0,vy=0,vz=0,sx=1,sy=1,sz=1}
  DynamicObject.UPDATERS[Manifest.profile(species).routes.update](p,{modelScaleY=1})
  check(p.age==expected[1],"age step mismatch for "..species)
  check(math.abs(p.y-expected[2])<1e-8,"vertical step mismatch for "..species)
  check(math.abs(p.sx-expected[3])<1e-8,"scale step mismatch for "..species)
end

local root=assert(cacheRoot(),"Stadium 2 cache not found")
for _,species in ipairs(speciesIds) do
  local bytes=assert(read(root..("/normal/%03d.dsm"):format(species)))
  local model=assert(Pack.parse(bytes))
  local profile=Manifest.profile(species)
  local record
  for _,row in ipairs(model.handlers and model.handlers.records or {}) do
    if row.descriptor==Manifest.descriptor then record=row break end
  end
  check(record~=nil,"dynamic-object record missing for "..species)
  check(record and record.program and record.program.geometry
      and #(record.program.geometry.vertices or {})==4,
    "callback billboard geometry missing for "..species)
  check(record and #(record.program.textures or {})==expectedTextures[species],
    "callback texture count mismatch for "..species)

  local matrices=Build.bindMatrices(model.bones)
  local emitters=Renderer.dynamicObjectEmitters(model,matrices)
  check(#emitters==expectedEmitters[species],"emitter count mismatch for "..species..": "..#emitters)
  local controlled, staticControlled=0,0
  for _,prim in ipairs(model.prims or {}) do
    if record and prim.callbackOffset==record.commandOffset then
      local state=Renderer.primitiveRenderState(model,prim,{disableCulling=true})
      if state.dynamicObjectCarrier then controlled=controlled+1 end
      if state.drawStatic then staticControlled=staticControlled+1 end
      if profile and profile.ownership=="inherited-model" then
        check(state.drawStatic and state.castsShadow,
          "inherited body geometry was suppressed for "..species)
      end
    end
  end
  if profile.ownership=="exclusive-card" then
    check(controlled>0 and staticControlled==0,"exclusive callback cards not identified for "..species)
  elseif profile.ownership=="mixed-card" then
    check(controlled==#profile.carrierPrimitives,"mixed callback cards not identified for "..species)
    check(staticControlled>0,"mixed profile suppressed inherited body geometry for "..species)
  else
    check(controlled==0,"inherited geometry classified as cards for "..species)
  end

  local runtime={species=species,callbackFrame=0,sourceFrame=0,dynamicObjectForceSpawn=true,
    dynamicObjectEmitters=emitters,dynamicObjectEnabled=true,dynamicObjectUpdateEnabled=true,
    dynamicObjectRandomValue=0,modelScaleX=1,modelScaleY=1,modelScaleZ=1}
  local state=select(1,Handlers.runExtension(model.handlers,2,runtime,{}))
  local effect=state.dynamicObjectsBySite and state.dynamicObjectsBySite[record.commandOffset]
  check(effect and effect.profile==profile,"runtime profile did not resolve for "..species)
  local active=0
  for _,emitter in ipairs(effect and effect.emitters or {}) do
    for _,particle in ipairs(emitter.particles or {}) do if particle.active then active=active+1 end end
  end
  check(active==#emitters,"forced spawn did not cover every emitter for "..species)
end

local unsupported={}
DynamicObject.updateState(unsupported,0x1234,{bone=0,callbackFrame=0,program={}},
  {species=25,dynamicObjectForceSpawn=true})
check(unsupported.dynamicObjectsBySite==nil,"unsupported species created invented FX")
check(unsupported.dynamicObjectDiagnostics and unsupported.dynamicObjectDiagnostics[0x1234],
  "unsupported species lacks an explicit diagnostic")

print(("%d checks passed (Stadium 2 dynamic-object route audit)"):format(checks-failures))
if failures>0 then error(("%d/%d dynamic-object audit checks failed"):format(failures,checks),0) end
