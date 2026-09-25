-- Cosmetic visitors own no battle state and never use the gameplay RNG.
local Actor=require('mods.STADIUM2_IMPORTER.lib.battle_actor')
local Mat=require('mods.STADIUM2_IMPORTER.lib.renderer')
local V={};V.__index=V
local serial=0
local passes={"opaque","additive"}
local TorchShadows=require("mods.STADIUM2_IMPORTER.lib.battle_torch_shadows")
local Catalog=require('mods.STADIUM2_IMPORTER.lib.visitor_catalog')
local Behaviour=require('mods.STADIUM2_IMPORTER.lib.visitor_behaviour')
local Locomotion=require('mods.STADIUM2_IMPORTER.lib.visitor_locomotion')
local species,heights={},{}
for name,spec in pairs(Catalog) do if name~='pools' then species[name]=spec[1];heights[name]=spec[2] end end
local function random(self)
 self.seed=self.seed*16807%2147483647;return self.seed/2147483647
end
local function smooth(t) t=math.max(0,math.min(1,t));return t*t*(3-2*t) end
function V.new(environment,mode,seed)
 serial=serial+1
 return setmetatable({environment=environment,mode=mode,seed=seed or (serial*7919+math.floor((love and love.timer and love.timer.getTime() or 0)*1000))%2147483646+1,
  age=0,nextVisit=2,active={},failed={},rareRolled=false,preview=0},V)
end
function V:spawn(name)
 if not (self.camera and self.camera.vp) then return false end
 if #self.active>=3 or self.failed[name] or not species[name] then return false end
 for _,v in ipairs(self.active) do if v.name==name then return false end end
 local actor=Actor.new('visitor',{dexOf=function(_,mon) return mon.species end})
 local ok,result=pcall(actor.load,actor,nil,{species=species[name]})
 if not ok or not result then actor:release();self.failed[name]=true;return end
 actor:play('idle',true)
 local v={name=name,actor=actor,age=0,duration=name=='caterpie' and math.huge or 32+random(self)*14}
 local r=actor.renderer
 local bounds=r.poseBounds and r:poseBounds() or r.bindBounds
 if not bounds then actor:release();return false end
 local candidate={}
 if not Behaviour.start(v,self.environment,function() return random(self) end,function()
  return not V.visible(self.camera.vp,self:matrix(v,candidate),bounds)
 end) then actor:release();return false end
 if v.x then
  for _,other in ipairs(self.active) do
   if other.x and math.abs(other.y-v.y)<other.bodyHeight+v.bodyHeight
    and (other.x-v.x)^2+(other.z-v.z)^2<(other.radius+v.radius)^2 then actor:release();return false end
  end
  if not Behaviour.validate(v,self.environment) then actor:release();return false end
 end
 Locomotion.attach(v)
 self.active[#self.active+1]=v
 return true
end
-- Paths lie around the scenery perimeter, outside the two battler slots.
function V.pose(name,t,environment)
 local u=t/18
 if name=='caterpie' then
  local x,y,z=require('mods.STADIUM2_IMPORTER.lib.woodland_perch').position()
  return x,y,z,.65,1
 elseif name=='meowth' then
  local x=t<7 and (-115+58*smooth(t/7)) or t<14 and -57 or (-57-58*smooth((t-14)/8))
  return x,.65*math.abs(math.sin(t*4))*((t<7 or t>14) and 1 or 0),-76,t<14 and math.pi/2 or -math.pi/2,smooth(t)
 elseif name=='mew' then
  local a=t*.55
  return -55+12*math.sin(a),18+6*math.sin(t*.9),-55+10*math.cos(a),a,smooth(t/2)
 else
  local cave=environment=='cave'
  local across=-160+320*u
  local depth=name=='hooh' and 180 or cave and 65 or 125
  local y=name=='hooh' and 55 or cave and 18 or 42
  return (across-depth)*.7071,y+3*math.sin(t*(cave and 3 or 1.3)),(-across-depth)*.7071,math.pi*.75,smooth(t)
 end
end
function V:update(dt,frame)
 if frame then self.camera=frame end
 self.age=self.age+math.min(math.max(dt,0),.1)
 for i=#self.active,1,-1 do
  local v=self.active[i];v.age=v.age+math.min(math.max(dt,0),.1)
  v.moved=0
  if Behaviour.validate(v,self.environment) then
   Behaviour.update(v,math.min(math.max(dt,0),.1),self.environment,self.active)
  end
  Locomotion.advance(v,v.moved or 0,math.min(math.max(dt,0),.1))
  v.actor:update(math.min(math.max(dt,0),.1))
  Behaviour.validate(v,self.environment)
 end
 if self.age<self.nextVisit then return end
 self.nextVisit=self.age+12+random(self)*10
 local pool=Catalog.pools[self.environment] or Catalog.pools.grass
 if self.environment=='grass' and not self.resident then self.resident=self:spawn('caterpie') end
 if self.mode=='preview' then
  self.preview=self.preview%(#pool+2)+1
  local name=pool[self.preview] or (self.preview==#pool+1 and 'mew' or self.environment=='cave' and 'golbat' or 'hooh')
  self:spawn(name);self.nextVisit=self.age+10
 elseif not self.rareRolled then
  self.rareRolled=true;local roll=random(self)
  if roll<.005 then self:spawn('mew')
  elseif roll<.01 and self.environment~='cave' then self:spawn('hooh')
  else self:spawn(pool[math.floor(random(self)*#pool)+1]) end
 else self:spawn(pool[math.floor(random(self)*#pool)+1]) end
end
function V:matrix(v,out)
 local x,y,z,yaw,size
 if v.x then x,y,z,yaw,size=v.x,v.y,v.z,v.yaw,1
 else x,y,z,yaw,size=V.pose(v.name,v.age,self.environment) end
 v.metrics=v.metrics or {}
 local metrics=v.actor.renderer:worldMetrics(v.metrics);local k=heights[v.name]/math.max(.001,metrics.height)*size
 local c,s=math.cos(yaw),math.sin(yaw)
 out=out or {}
 out[1],out[2],out[3],out[4]=k*c,0,k*s,x
 out[5],out[6],out[7],out[8]=0,k,0,y-metrics.floor*k
 out[9],out[10],out[11],out[12]=-k*s,0,k*c,z
 out[13],out[14],out[15],out[16]=0,0,0,1
 return out,yaw
end
-- Test the whole posed model against the final camera, including mod camera
-- overrides. A small screen margin prevents popping at the edge of the view.
function V.visible(vp,matrix,bounds)
 if not vp or not bounds then return true end
 return TorchShadows.visibleInFace(vp,matrix,bounds,1.1)
end
function V:prune(frame)
 for i=#self.active,1,-1 do
  local v=self.active[i]
  if v.age>v.duration then
   local r=v.actor.renderer
   v.bounds=v.bounds or {};v.matrix=v.matrix or {}
   local bounds=r.poseBounds and r:poseBounds(v.bounds) or r.bindBounds
   if not V.visible(frame and frame.vp,self:matrix(v,v.matrix),bounds) then
    for _,other in ipairs(self.active) do if other.partner==v then other.partner=nil end end
    v.actor:release();table.remove(self.active,i)
   end
  end
 end
end
function V:castShadow(vp)
 for _,v in ipairs(self.active) do
  v.matrix=v.matrix or {};v.actor.renderer:drawShadowMap(self:matrix(v,v.matrix),vp)
 end
end
function V:shadowActors(actors,matrices,modes)
 self.shadowScratch=self.shadowScratch or {actors={},matrices={},modes={}}
 local a,m,b=self.shadowScratch.actors,self.shadowScratch.matrices,self.shadowScratch.modes
 for k in pairs(a) do a[k]=nil end
 for k in pairs(m) do m[k]=nil end
 for k in pairs(b) do b[k]=nil end
 for k,v in pairs(actors) do a[k]=v end
 for k,v in pairs(matrices) do m[k]=v end
 for k,v in pairs(modes) do b[k]=v end
 for i,v in ipairs(self.active) do
  local k='visitor'..i;v.matrix=v.matrix or {};v.shadowEntry=v.shadowEntry or {}
  v.shadowEntry[1],v.shadowEntry[2]=self:matrix(v,v.matrix)
  a[k]=v.actor;m[k]=v.shadowEntry;b[k]='host'
 end
 return a,m,b
end
function V:draw(g,frame,env,scene,shadow)
 g.push('all')
 for _,v in ipairs(self.active) do
  local r=v.actor.renderer
  v.matrix=v.matrix or {};local matrix,yaw=self:matrix(v,v.matrix)
  v.drawOptions=v.drawOptions or {normalMatrix={},tint={1,1,1,1},sceneWatercolor=true,disableCulling=true,flipWinding=true}
  local opts=v.drawOptions
  opts.viewProjection,opts.viewMatrix=frame.vp,frame.view
  Mat.normalMatrix(yaw,0,false,opts.normalMatrix)
  opts.bindTorchLighting=scene.bindTorchLighting
  opts.lightDir,opts.ambient,opts.diffuse=env.light,env.ambient,env.diffuse
  for i=1,3 do opts.tint[i]=env.modelTint and env.modelTint[i] or 1 end
  opts.sunMap,opts.sunVP=shadow and shadow.map,shadow and shadow.sunVP
  opts.sunDark,opts.sunBias,opts.sunTexel=shadow and shadow.sunDark,shadow and shadow.sunBias,shadow and shadow.sunTexel
  for _,pass in ipairs(passes) do
   opts.skipHandlers=pass=='additive';r:drawScene(pass,matrix,opts)
  end
 end
 g.pop()
end
function V:release() for _,v in ipairs(self.active) do v.actor:release() end;self.active={};self.shadowScratch=nil end
V.species=species
return V
