-- Cosmetic visitors own no battle state and never use the gameplay RNG.
local Actor=require('mods.STADIUM2_IMPORTER.lib.battle_actor')
local Mat=require('mods.STADIUM2_IMPORTER.lib.renderer')
local V={};V.__index=V
local serial=0
local species={caterpie=10,meowth=52,zubat=41,pidgey=16,hooh=250,mew=151}
local heights={caterpie=4.5,meowth=7,zubat=6,pidgey=5,hooh=16,mew=5}
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
 if #self.active>=2 or self.failed[name] then return end
 local actor=Actor.new('visitor',{dexOf=function(_,mon) return mon.species end})
 local ok,result=pcall(actor.load,actor,nil,{species=species[name]})
 if not ok or not result then actor:release();self.failed[name]=true;return end
 actor:play('idle',true)
 self.active[#self.active+1]={name=name,actor=actor,age=0,duration=name=='caterpie' and math.huge or name=='meowth' and 22 or 18}
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
function V:update(dt)
 self.age=self.age+math.min(math.max(dt,0),.1)
 for i=#self.active,1,-1 do
  local v=self.active[i];v.age=v.age+math.min(math.max(dt,0),.1)
  v.actor:update(math.min(math.max(dt,0),.1))
  if v.name=='meowth' and v.age>8 and not v.played then v.actor:play('attack',false);v.played=true end
 end
 if self.age<self.nextVisit then return end
 self.nextVisit=self.age+24+random(self)*20
 if self.mode=='preview' then
  local list=self.environment=='cave' and {'zubat','mew'} or self.environment=='town' and {'meowth','pidgey','mew','hooh'} or {'pidgey','mew','hooh'}
  self.preview=self.preview%#list+1;self:spawn(list[self.preview]);self.nextVisit=self.age+23
 elseif not self.rareRolled then
  self.rareRolled=true
  local roll=random(self)
  if roll<.005 then self:spawn('mew')
  elseif roll<.01 and self.environment~='cave' then self:spawn('hooh')
  else self:spawn(self.environment=='cave' and 'zubat' or self.environment=='town' and 'meowth' or 'pidgey') end
 else self:spawn(self.environment=='cave' and 'zubat' or self.environment=='town' and (random(self)<.7 and 'meowth' or 'pidgey') or 'pidgey') end
 if self.environment=='grass' and not self.resident then self.resident=true;self:spawn('caterpie') end
end
function V:matrix(v)
 local x,y,z,yaw,size=V.pose(v.name,v.age,self.environment)
 local metrics=v.actor.renderer:worldMetrics();local k=heights[v.name]/math.max(.001,metrics.height)*size
 local c,s=math.cos(yaw),math.sin(yaw)
 return {k*c,0,k*s,x,0,k,0,y-metrics.floor*k,-k*s,0,k*c,z,0,0,0,1},yaw
end
-- Test the whole posed model against the final camera, including mod camera
-- overrides. A small screen margin prevents popping at the edge of the view.
function V.visible(vp,matrix,bounds)
 if not vp or not bounds then return true end
 local padded={}
 for i,n in ipairs(vp) do padded[i]=i<=8 and n/1.1 or n end
 return require('mods.STADIUM2_IMPORTER.lib.battle_torch_shadows').visibleInFace(padded,matrix,bounds)
end
function V:prune(frame)
 for i=#self.active,1,-1 do
  local v=self.active[i]
  if v.age>v.duration then
   local r=v.actor.renderer
   local bounds=r.poseBounds and r:poseBounds() or r.bindBounds
   if not V.visible(frame and frame.vp,self:matrix(v),bounds) then
    v.actor:release();table.remove(self.active,i)
   end
  end
 end
end
function V:castShadow(vp)
 for _,v in ipairs(self.active) do v.actor.renderer:drawShadowMap(self:matrix(v),vp) end
end
function V:shadowActors(actors,matrices,modes)
 local a,m,b={},{},{}
 for k,v in pairs(actors) do a[k]=v end
 for k,v in pairs(matrices) do m[k]=v end
 for k,v in pairs(modes) do b[k]=v end
 for i,v in ipairs(self.active) do local k='visitor'..i;a[k]=v.actor;m[k]={self:matrix(v)};b[k]='host' end
 return a,m,b
end
function V:draw(g,frame,env,scene,shadow)
 g.push('all')
 for _,v in ipairs(self.active) do
  local r=v.actor.renderer;local matrix,yaw=self:matrix(v)
  for _,pass in ipairs({'opaque','additive'}) do
   r:drawScene(pass,matrix,{viewProjection=frame.vp,viewMatrix=frame.view,
    normalMatrix=Mat.normalMatrix(yaw,0,false),bindTorchLighting=scene.bindTorchLighting,
    sceneWatercolor=true,lightDir=env.light,ambient=env.ambient,diffuse=env.diffuse,
    tint={(env.modelTint or {1,1,1})[1],(env.modelTint or {1,1,1})[2],(env.modelTint or {1,1,1})[3],1},disableCulling=true,flipWinding=true,
    skipHandlers=pass=='additive',sunMap=shadow and shadow.map,sunVP=shadow and shadow.sunVP,
    sunDark=shadow and shadow.sunDark,sunBias=shadow and shadow.sunBias,sunTexel=shadow and shadow.sunTexel})
  end
 end
 g.pop()
end
function V:release() for _,v in ipairs(self.active) do v.actor:release() end;self.active={} end
V.species=species
return V
