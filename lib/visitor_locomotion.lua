-- Procedural visitor-only gait layered over the authored idle pose. Phase is
-- driven by distance travelled, so feet stop cycling when movement stops.
local L={}
local quadrupeds={eevee=true,persian=true,rattata=true,growlithe=true,paras=true}
function L.attach(v)
 if v.motion~='ground' then return end
 local r=v.actor.renderer
 if not (r.parts and r.bindBounds) then return end
 -- Prefer an explicitly named authored walk when the imported pack has one.
 local names=r.model and r.model.animByName
 local walk=names and (names.walk or names.walking or names.trot)
 if walk and r.setAnimation and r:setAnimation(walk,true) then
  v.walkAnimation=walk
  return
 end
 local bounds=r.bindBounds;local height=math.max(.001,bounds.maxY-bounds.minY)
 local gait={phase=0,amount=0,height=height,kind=v.name=='weedle' and 'crawl' or quadrupeds[v.name] and 'trot' or 'walk',masks={}}
 for pi,part in ipairs(r.parts) do
  local masks={};gait.masks[pi]=masks
  for i,row in ipairs(part.rows) do
   local h=math.max(0,math.min(1,(row[2]-bounds.minY)/height))
   local weight=math.max(0,1-h/.45);weight=weight*weight*(3-2*weight)
   local side=row[1]<bounds.cx and 0 or math.pi
   if gait.kind=='trot' and row[3]<bounds.cz then side=side+math.pi end
   masks[i]={weight,side,(row[3]-bounds.cz)/height}
  end
 end
 r.visitorLocomotion=gait;v.gait=gait
end
function L.advance(v,distance,dt)
 if v.walkAnimation then
  local r=v.actor.renderer
  if distance>.00001 and not v.pauseUntil then
   if r.animIndex~=v.walkAnimation then r:setAnimation(v.walkAnimation,true) end
  elseif not v.pauseUntil and r.animIndex==v.walkAnimation then v.actor.context='idle';v.actor:play('idle',true) end
  return
 end
 local gait=v.gait;if not gait then return end
 local stride=math.max(.5,v.spec[2]*.42)
 gait.phase=(gait.phase+distance/stride*math.pi*2)%(math.pi*2)
 local target=distance>.00001 and 1 or 0
 gait.amount=gait.amount+(target-gait.amount)*math.min(1,dt*14)
end
function L.apply(renderer)
 local g=renderer.visitorLocomotion
 if not g or g.amount<.001 then return end
 for pi,part in ipairs(renderer.parts) do
  for i,row in ipairs(part.rows) do
   local mask=g.masks[pi][i]
   if part.visible[i]~=false then
    local phase=g.phase+mask[2];local amount=g.amount
    if g.kind=='crawl' then
     row[1]=row[1]+math.sin(g.phase+mask[3]*5)*g.height*.055*amount
     row[2]=row[2]+(.5+.5*math.sin(g.phase+mask[3]*5))*g.height*.025*amount
    else
     local swing=math.sin(phase)
     row[3]=row[3]+swing*g.height*.105*mask[1]*amount
     row[2]=row[2]+math.max(0,math.cos(phase))*g.height*.085*mask[1]*amount
     row[2]=row[2]+(1-math.cos(g.phase*2))*g.height*.012*(1-mask[1])*amount
    end
   end
  end
  if part.mesh then part.mesh:setVertices(part.rows) end
 end
end
return L
