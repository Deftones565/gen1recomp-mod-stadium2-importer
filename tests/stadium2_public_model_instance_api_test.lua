package.path = "./?.lua;./?/init.lua;" .. package.path

local prefix = "mods.STADIUM2_IMPORTER.lib."
local rendererReleases, modelReleases, pushes, pops = 0, 0, 0, 0

love = {graphics={
  push=function(mode) assert(mode=="all"); pushes=pushes+1 end,
  pop=function() pops=pops+1 end,
}}

local function identity()
  return {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}
end

local Renderer = {
  identity=identity,
  matMul=function(a,b)
    local out={}
    for r=0,3 do for c=0,3 do
      local value=0
      for k=0,3 do value=value+a[r*4+k+1]*b[k*4+c+1] end
      out[r*4+c+1]=value
    end end
    return out
  end,
  perspective=function() return {kind="perspective"} end,
  lookAt=function() return {kind="lookAt"} end,
  ortho=function() return {kind="ortho"} end,
  modelMatrix=function() return {kind="stadiumModel"} end,
  normalMatrix=function() return {kind="stadiumNormal"} end,
}
package.loaded[prefix.."renderer"] = Renderer
package.loaded[prefix.."model_api"] = nil

local nextModel = 0
local function makeRenderer(model, options)
  local renderer={
    model=model, options=options, animIndex=2, frame=3, time=0.1,
    loop=true, finished=false, draws={},
  }
  function renderer:setContext(name,loop)
    self.context=name; self.loop=loop~=false
    return name=="idle"
  end
  function renderer:setAnimation(value,loop,aux)
    self.animation=value; self.loop=loop~=false; self.aux=aux
    return value==4 or value=="named"
  end
  function renderer:setMove(move,loop) self.move=move; return loop~=false end
  function renderer:seekFrame(frame) self.frame=frame; return true end
  function renderer:setHandlerRuntime(runtime,defer)
    self.runtime=runtime; self.defer=defer
  end
  function renderer:step(dt) self.time=self.time+dt; return true end
  function renderer:worldMetrics()
    return {height=2,floor=-1,radius=3,rootScale=4,bounds={minX=-1,maxX=1}}
  end
  function renderer:poseBounds() return {minX=-2,maxX=2,radius=2} end
  function renderer:geometryAnchor() return {1,2,3} end
  function renderer:drawScene(pass,matrix,drawOptions)
    self.draws[#self.draws+1]={pass=pass,matrix=matrix,options=drawOptions}
    return true
  end
  function renderer:drawShadowMap(matrix,lightVP)
    self.shadow={matrix=matrix,lightVP=lightVP}; return true
  end
  function renderer:release() rendererReleases=rendererReleases+1 end
  return renderer
end

local Importer={}
function Importer.createModel(species,variant)
  nextModel=nextModel+1
  return {species=species,variant=variant,id=nextModel}
end
function Importer.createSpecialModel(name) return {special=name,id=100} end
function Importer.releaseModel(model)
  if model.released then return false,"already released" end
  model.released=true; modelReleases=modelReleases+1; return true
end
function Importer.newRendererFromModel(model,options) return makeRenderer(model,options) end
function Importer.loadModel() end
function Importer.newRenderer() end
function Importer.readPack() end
function Importer.parsePack() end

local Models=require(prefix.."model_api").new(Importer)
local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end

local capabilities=Models.capabilities()
ok(Models.apiVersion==2 and capabilities.apiVersion==2
  and capabilities.sceneNeutralDraw,"versioned scene-neutral capability")
ok(capabilities.ownedInstances and capabilities.animation.move
  and capabilities.shadows.cast,"instance feature discovery")

local actor=assert(Models.newInstance(25,"shiny",{textureFilter="nearest"}))
local model=assert(actor:model())
local renderer=assert(actor:renderer())
ok(model.species==25 and model.variant=="shiny","instance owns requested model")
ok(renderer.options.textureFilter=="nearest","renderer options forwarded")
ok(actor:play("idle",true) and renderer.context=="idle","context animation helper")
ok(actor:playContext("idle",true),"explicit context animation helper")
ok(actor:play(4,false,7) and renderer.animation==4 and renderer.aux==7,
  "indexed animation helper")
ok(actor:playAnimation("named",true),"explicit raw animation helper")
ok(actor:playMove(85,true) and renderer.move==85,"move animation helper")
ok(actor:seekFrame(12) and renderer.frame==12,"frame seek helper")
ok(actor:update(0.25,{weather="rain"}) and renderer.runtime.weather=="rain"
  and renderer.defer,"animation update and handler runtime")

local state=assert(actor:animationState())
ok(state.index==2 and state.frame==12 and state.finished==false,
  "stable animation state")
ok(actor:isFinished()==false,"animation completion helper")
local metrics=assert(actor:metrics())
metrics.bounds.minX=99
ok(actor:metrics().bounds.minX==-1,"metrics are defensive copies")
local bounds=assert(actor:bounds())
bounds.minX=99
ok(actor:bounds().minX==-2,"pose bounds are defensive copies")
ok(actor:geometryAnchor()[2]==2,"geometry anchor helper")

local matrix=Models.matrix.transform({position={5,6,7},scale={2,3,4}})
ok(matrix[4]==5 and matrix[8]==6 and matrix[12]==7,
  "transform helper uses row-major translation")
local normal=Models.matrix.normalFromModel(matrix)
ok(math.abs(normal[1]-0.5)<1e-9 and math.abs(normal[5]-1/3)<1e-9
  and math.abs(normal[9]-0.25)<1e-9,"normal matrix supports non-uniform scale")

local vp=identity()
ok(actor:draw({modelMatrix=matrix,camera={view=identity(),vp=vp},
  light={direction={0,1,0},ambient={0.2,0.2,0.2}},
  shadow={map="shadow-map",vp=identity(),darkness=0.5}}),
  "draw accepts scene-neutral camera, light, and shadow inputs")
ok(#renderer.draws==2 and renderer.draws[1].pass=="opaque"
  and renderer.draws[2].pass=="additive","all pass has stable draw order")
ok(renderer.draws[1].options.viewProjection==vp
  and renderer.draws[1].options.sunMap=="shadow-map"
  and renderer.draws[1].options.sunDark==0.5,"draw options map to renderer contract")
ok(pushes==1 and pops==1,"draw restores graphics state")
ok(actor:drawShadow({modelMatrix=matrix,lightViewProjection=vp})
  and renderer.shadow.lightVP==vp,"shadow casting helper")
ok(pushes==2 and pops==2,"shadow draw restores graphics state")

ok(actor:release() and model.released,"owned instance releases model")
ok(rendererReleases==1 and modelReleases==1,"owned lifecycle releases both resources")
ok(not actor:release() and actor:model()==nil,"released instance rejects reuse")

local external={id="external"}
local borrowed=assert(Models.newInstanceFromModel(external,{takeOwnership=false}))
ok(borrowed:release() and not external.released,"external model remains caller-owned")
local transferred={id="transferred"}
local owned=assert(Models.newInstanceFromModel(transferred,{takeOwnership=true}))
ok(owned:release() and transferred.released,"model ownership may be transferred")

local special=assert(Models.newSpecialInstance("substitute"))
ok(special:model().special=="substitute" and special:release(),
  "special models use the same owned lifecycle")

print(("%d checks passed (Stadium 2 public model instance API)"):format(checks))
