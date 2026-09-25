-- Exercise the real CPU renderer: a successful draw stub cannot detect lost
-- FRAGMENT callbacks or the resulting untextured primitives.
local prefix='mods.STADIUM2_IMPORTER.lib.'
local Resources=require(prefix..'stadium2_battle_fx_resources')
local Rom=require(prefix..'stadium2_battle_fx_rom')
local Renderer=require(prefix..'renderer')
local Player=require(prefix..'stadium2_battle_fx_player')
local file=io.open(os.getenv('STADIUM2_ROM') or
  'mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb')
if not file then
  assert(os.getenv('STADIUM2_REQUIRE_ROM')~='1','required ROM unavailable')
  print('SKIP battle FX model material ROM');return
end
local rom=file:read('*a');file:close()
local catalog=assert(Rom.catalog(rom))
local checks=0
for _,fixture in ipairs({{5,448,1},{14,140,2},{16,142,1},{43,261,1},{46,161,1}}) do
  local resources=assert(Resources.resolve(rom:sub(Resources.ROM_START+1,
    Resources.ROM_END),catalog.moves[fixture[1]].resources))
  local shape=assert(Resources.shapeFromResolved(resources,fixture[2]))
  local model=assert(Resources.modelFromShape(shape,'material-regression'))
  assert(model.handlers and #model.handlers.records>0,'compiled callbacks retained')
  local renderer=assert(Renderer.new(model,{flipY=false}))
  renderer:setHandlerRuntime({callbackFrame=10,materialFrame=10},false)
  assert(renderer:currentTexture(model.prims[1])==fixture[3],
    'ROM callback must bind the expected first texture for move '..fixture[1])
  for _,prim in ipairs(model.prims) do
    local slot=renderer:currentTexture(prim)
    assert(model.textures[slot],'reported untextured model must resolve its material texture')
    assert(prim.additive==(prim.blend=='add'),'render pass preserves decoded blend')
    if prim.callbackTextureRequired then
      assert(renderer:callbackUsesMaterialFx(prim),'compiled FX must apply callback material and scrolling')
    end
    checks=checks+2
  end
  for _,record in ipairs(model.handlers.records) do
    local material=record.program and record.program.phase5Material
    if record.descriptor==0x81000138 and material then
      assert(material.submissionMode==0,'FX callback must retain native mode-0 alpha')
    end
  end
  renderer:release()
  checks=checks+2
end
-- These ROM image sequences must advance even when frameRule selected a
-- nonzero, constant spawn hold. Exercise packet -> Player -> real renderer.
for _,fixture in ipairs({{7,47,2},{8,1,2},{9,102,1},{53,51,2},{55,70,2}}) do
  local resources=assert(Resources.resolve(rom:sub(Resources.ROM_START+1,
    Resources.ROM_END),catalog.moves[fixture[1]].resources))
  local shape=assert(Resources.shapeFromResolved(resources,fixture[2]))
  local model=assert(Resources.modelFromShape(shape,'animated-material-regression'))
  assert(model.prims[1].material.submissionMode==0,'direct FX uses mode 0')
  local renderer=assert(Renderer.new(model,{flipY=false}))
  local particle={id=1,effectId=1,age=0,frame=17,shapeId=fixture[2],
    scale={1,1,1},event={},material={shapeId=fixture[2]}}
  local snapshot={frame=0,effects={{id=1,moveId=fixture[1]}},particles={particle}}
  -- Direct shapes need the ROM angle tables and a camera for 84102B3C.
  local player=Player.new({runtime={snapshot=function()return snapshot end,
      catalog={trigTables=catalog.trigTables}},
    loadRenderer=function()return renderer end,
    resolvePlacement=function()return {resolved=true,position={0,0,0},scale=1} end})
  local samples={}
  renderer.drawScene=function(self,pass)
    if pass=='opaque' then samples[#samples+1]=self:currentTexture(model.prims[1]) end
    return true
  end
  local scene={camera={eye={0,0,10},focus={0,0,0},up={0,1,0}}}
  for age=0,6 do
    particle.age=age
    assert(player:draw(scene).drawn==1)
    assert(samples[#samples]==math.floor(age/fixture[3])+1,
      'ROM texture advances by live age for move '..fixture[1])
    local selected=samples[#samples]
    player:draw(scene)
    assert(samples[#samples]==selected,'redraw must not advance the material')
    checks=checks+3
  end
  renderer:release()
end
print(checks..' checks passed (battle FX model material ROM)')
