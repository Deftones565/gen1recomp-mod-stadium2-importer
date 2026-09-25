-- Sonic Boom, US family 12. Four pool records, three emitted projectiles,
-- fifteen history nodes each. Verified against 841580C8/84163B4C/84163E60.
local f=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float')
local Needle=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_needle')
local FourStream={families={[12]=true}}
local function copy(v)if type(v)~='table' then return v end local t={} for k,x in pairs(v) do t[k]=copy(x) end return t end
local function vec(v)return {f(v[1]),f(v[2]),f(v[3])}end
function FourStream.new(frameOrigin,scale)
  return {family=12,slots={},frameOrigin=copy(frameOrigin or {0,0,0}),scale=f((scale or 1)*.75),counter=0}
end
function FourStream.spawn(s,origin,rng)
  local a=f(f((s.counter%3)*f(math.pi))/3+0.5235987901687622)
  local y,z=f(math.sin(a)),f(math.cos(a))
  local length=f(math.sqrt(f(f(1+f(y*y))+f(z*z))))
  y,z=f(y/length),f(z/length)
  local velocity={origin[1]<0 and -10 or 10,f(f(y*20)*s.scale),f(f(z*20)*s.scale)}
  local spin=f((rng:next()%2*2-1)*.3)
  local index
  for i=1,4 do if not s.slots[i] or not s.slots[i].active then index=i;break end end
  if not index then return end
  local slot={active=true,age=0,life=40,scale=s.scale,sign=velocity[1]<0 and -1 or 1,
    origin=vec(origin),rotation=spin,maxRadius=13,nodes={}}
  for j=0,14 do slot.nodes[j+1]={alpha=math.floor(128*(14-j)/15),radius=2,
    angle=f(f((rng:next()%120)*f(2*math.pi))/120),position=vec(origin),velocity=vec(velocity)} end
  s.slots[index]=slot
end
function FourStream.step(s,origin,rng)
  s.counter=s.counter+1
  if s.counter>=50 then return -1 end
  if s.counter<4 then FourStream.spawn(s,origin,rng) end
  if s.counter<2 then return 0 end
  for _,slot in ipairs(s.slots) do if slot.active then
    slot.age=slot.age+1
    if slot.age>slot.life then slot.active=false else
      local previous
      for j,n in ipairs(slot.nodes) do
        local saved={radius=n.radius,angle=n.angle,position=copy(n.position),velocity=copy(n.velocity)}
        if j==1 then
          for k=1,3 do n.position[k]=f(n.position[k]+n.velocity[k]) end
          n.angle=f(n.angle+slot.rotation)
          n.velocity[1]=slot.sign<0 and math.min(20,f(n.velocity[1]+1.5)) or math.max(-20,f(n.velocity[1]-1.5))
          for k=2,3 do
            local delta=f(slot.origin[k]-n.position[k])
            if slot.age<15 then
              n.velocity[k]=f(n.velocity[k]+f(delta*f((15-slot.age)*.03/15)))
              n.position[k]=f(n.position[k]+f(delta*f(slot.age*.15/15)))
            else
              n.velocity[k]=f(n.velocity[k]+delta*.03)
              n.position[k]=f(n.position[k]+delta*.15)
            end
          end
          n.radius=math.min(slot.maxRadius,f(n.radius+2))
        else n.radius,n.angle,n.position,n.velocity=previous.radius,previous.angle,previous.position,previous.velocity end
        previous=saved
      end
    end
  end end
  return 0
end
function FourStream.geometry(s,asset)
  -- Shared native 30-vertex shade ribbon; distinct ROM quad, texture and pitch.
  return Needle.geometry(s,asset,{texture=37,pitchSign=1,alpha=200,lighting=false,trailScale=true})
end
function FourStream.snapshot(s)local out=copy(s);out.kind='rom-four-stream-state';out.drawReady=true;return out end
return FourStream
