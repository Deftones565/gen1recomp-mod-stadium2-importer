local Nav=require('mods.STADIUM2_IMPORTER.lib.visitor_navigation')
local Catalog=require('mods.STADIUM2_IMPORTER.lib.visitor_catalog')
local B={}
local slots={-24,24}
local turns={0,.6,-.6,1.2,-1.2,2,-2,math.pi}
function B.start(v,environment,random,accept)
 local spec=Catalog[v.name];v.spec=spec;v.motion=spec[3]
 local r=v.actor.renderer
 local m=r:worldMetrics();local k=spec[2]/math.max(.001,m.height)
 v.modelScale=k;v.modelFloor=m.floor or 0
 local bounds=r.bindBounds or m.bounds
 -- Use a circumscribed radius so yaw cannot swing the bind mesh into objects.
 local rx=bounds and math.max(math.abs(bounds.minX),math.abs(bounds.maxX))*k or spec[2]*.65
 local rz=bounds and math.max(math.abs(bounds.minZ),math.abs(bounds.maxZ))*k or spec[2]*.65
 v.radius=math.sqrt(rx*rx+rz*rz)+2
 v.baseRadius=v.radius;v.baseHeight=spec[2]+3
 v.bodyHeight=spec[2]+3;v.nextAction=4+random()*5;v.heading=random()*math.pi*2
 v.random=random;v.goalCount=0
 if v.motion=='perch' then return not accept or accept(v) end
 local map=Nav.maps[environment]
 if not map then return false end
 for attempt=1,128 do
  local angle=random()*math.pi*2
  local radius=environment=='cave' and 26+random()*25 or environment=='town' and 50+random()*25 or 35+random()*50
  local x,z=math.cos(angle)*radius,math.sin(angle)*radius
  local y=v.motion=='ground' and 0 or v.motion=='high' and 95 or v.motion=='hover' and 10 or environment=='cave' and 13 or 22
  local clear=true
  for _,bz in ipairs(slots) do if x*x+(z-bz)^2<(v.radius+20)^2 then clear=false end end
  -- Reject isolated pockets: a safe point must also have an escape corridor.
  local escape=false
  if clear then
   for direction=0,15 do
    local a=direction*math.pi/8;local ex,ez=x+math.sin(a)*8,z+math.cos(a)*8
    local open=ex*ex+ez*ez<(environment=='cave' and 66 or v.motion=='high' and 175 or 88)^2
    for _,bz in ipairs(slots) do if ex*ex+(ez-bz)^2<(v.radius+20)^2 then open=false end end
    if open and Nav.sweep(map,x,y,z,ex,y,ez,v.radius+.3,v.bodyHeight+.3) then escape=true;break end
   end
  end
  if clear and escape and Nav.free(map,x,y,z,v.radius,v.bodyHeight) then
   v.x,v.y,v.z=x,y,z;v.yaw=v.heading
   if not accept or accept(v) then return true end
  end
 end
 return false
end
function B.validate(v,environment)
 if v.motion=='perch' or not v.x then return true end
 local r=v.actor.renderer
 if not r.poseBounds then return true end
 v.poseBounds=v.poseBounds or {}
 local b=r:poseBounds(v.poseBounds);local k=v.modelScale
 local rx=math.max(math.abs(b.minX),math.abs(b.maxX))*k
 local rz=math.max(math.abs(b.minZ),math.abs(b.maxZ))*k
 local radius=math.max(v.baseRadius or v.radius,math.sqrt(rx*rx+rz*rz)+.5)
 local bottom=math.min(0,(b.minY-v.modelFloor)*k)
 local height=math.max(v.baseHeight or v.bodyHeight,(b.maxY-v.modelFloor)*k)-bottom
 if Nav.free(Nav.maps[environment],v.x,math.max(0,v.y+bottom),v.z,radius,height) then
  v.radius,v.bodyHeight=radius,height
  v.safeAnimation,v.safeFrame,v.safeContext=r.animIndex,r.frame,v.actor.context
  if v.gait then v.safeGaitPhase,v.safeGaitAmount=v.gait.phase,v.gait.amount end
  return true
 end
 -- A wing/gesture may extend beyond the bind pose. Restore its previous safe
 -- animation frame rather than displaying it inside the scenery.
 if v.safeAnimation and r.setAnimation and r.seekFrame then
  if v.gait then v.gait.phase,v.gait.amount=v.safeGaitPhase or 0,v.safeGaitAmount or 0 end
  r:setAnimation(v.safeAnimation,true);r:seekFrame(v.safeFrame or 0)
  v.actor.context=v.safeContext
 end
 return false
end
local function gesture(v)
 local action=v.spec[4];local r=v.actor.renderer
 v.actor.context='idle'
 if type(action)=='number' and r.setMove then
  if r:setMove(action,false) then v.actor.context='attack';return end
 elseif r.setContext and r:setContext(action,action=='sleep') then
  v.actor.context=action;return
 end
 v.actor:play('idle',true)
end
local function safe(v,x,y,z,environment,others)
 local limit=environment=='cave' and 66 or v.motion=='high' and 175 or 88
 if x*x+z*z>limit*limit then return false end
 for _,bz in ipairs(slots) do if x*x+(z-bz)^2<(v.radius+20)^2 then return false end end
 for _,other in ipairs(others) do
  if other~=v and other.x and math.abs(other.y-y)<v.bodyHeight+other.bodyHeight
   and (other.x-x)^2+(other.z-z)^2<(v.radius+other.radius+1)^2 then return false end
 end
 return Nav.sweep(Nav.maps[environment],v.x,v.y,v.z,x,y,z,v.radius,v.bodyHeight)
end
local function chooseGoal(v,environment,others)
 local rand=v.random
 -- Occasionally approach another visitor, stopping outside both body volumes.
 if rand()<.35 and v.age>(v.socialAfter or 5) then
  for _,other in ipairs(others) do
   if other~=v and other.x and not other.partner and math.abs(other.y-v.y)<5 then
    local dx,dz=v.x-other.x,v.z-other.z;local d=math.sqrt(dx*dx+dz*dz)
    local spacing=v.radius+other.radius+7
    if d>spacing then
     local x,z=other.x+dx/d*spacing,other.z+dz/d*spacing
     if safe(v,x,v.y,z,environment,others) then
      v.goalX,v.goalZ=x,z;v.goalDeadline=v.age+18;v.goalCount=v.goalCount+1;return true
     end
    end
   end
  end
 end
 for attempt=1,20 do
  local angle=rand()*math.pi*2;local distance=6+rand()*30
  local x,z=v.x+math.sin(angle)*distance,v.z+math.cos(angle)*distance
  if safe(v,x,v.y,z,environment,others) then
   v.goalX,v.goalZ=x,z;v.goalCount=v.goalCount+1
   v.goalDeadline=v.age+18;return true
  end
 end
 v.goalX,v.goalZ=nil,nil;v.waitUntil=v.age+2+rand()*3
 return false
end
function B.update(v,dt,environment,others)
 if v.motion=='perch' then return end
 v.moved=0
 if v.pauseUntil then
  if v.age<v.pauseUntil then return end
  v.pauseUntil=nil;v.partner=nil;v.actor.context='idle';v.actor:play('idle',true)
 end
 if v.waitUntil and v.age<v.waitUntil then return end
 v.waitUntil=nil
 -- Nearby visitors acknowledge one another, face their partner and trade
 -- species gestures. Both reserve their positions; cooldown prevents loops.
 if v.age>(v.socialAfter or 5) then
  for _,other in ipairs(others) do
   if other~=v and other.x and not other.pauseUntil and not v.pauseUntil
    and other.age>(other.socialAfter or 5) and math.abs(other.y-v.y)<5 then
    local dx,dz=other.x-v.x,other.z-v.z;local distance=math.sqrt(dx*dx+dz*dz)
    if distance>v.radius+other.radius and distance<v.radius+other.radius+14 then
     v.yaw=math.atan2(dx,dz);other.yaw=v.yaw+math.pi
     v.partner,other.partner=other,v
     v.pauseUntil,other.pauseUntil=v.age+4,other.age+4
     v.socialAfter,other.socialAfter=v.age+25,other.age+25
     v.goalX,other.goalX=nil,nil
     gesture(v);gesture(other);return
    end
   end
  end
 end
 if v.age>=v.nextAction then
  v.nextAction=v.age+14+v.random()*10;v.pauseUntil=v.age+(v.spec[4]=='sleep' and 8 or 3)
  gesture(v);return
 end
 if not v.goalX or v.age>(v.goalDeadline or 0) then
  if not chooseGoal(v,environment,others) then return end
 end
 local dx,dz=v.goalX-v.x,v.goalZ-v.z;local distance=math.sqrt(dx*dx+dz*dz)
 if distance<.3 then
  v.goalX=nil;v.waitUntil=v.age+1+v.random()*3;return
 end
 local speed=v.motion=='ground' and 2 or v.motion=='hover' and 2.5 or 5
 local step=math.min(distance,speed*dt)
 local x,z=v.x+dx/distance*step,v.z+dz/distance*step
 if safe(v,x,v.y,z,environment,others) then
  v.x,v.z=x,z;v.yaw=math.atan2(dx,dz);v.moved=step
 else
  -- Replan from rest instead of repeatedly rotating the velocity into circles.
  v.goalX=nil;v.waitUntil=v.age+.8+v.random()
 end
end
return B
