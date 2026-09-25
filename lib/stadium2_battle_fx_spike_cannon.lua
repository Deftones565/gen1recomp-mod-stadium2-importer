-- US fragment 79 family 16: 84158370/8415839C/84158520 and
-- 841647D0/84164924/84164C28/84165008/841650A8.
local f=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float')
local Needle=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_needle')
local Spike={}
local function vec(v)return {f(v[1]),f(v[2]),f(v[3])}end
local function copy(v)if type(v)~='table' then return v end local t={} for k,x in pairs(v)do t[k]=copy(x)end return t end
local function short(v)return (v+32768)%65536-32768 end
local function valid(v)
  if type(v)~='table' then return false end
  for k=1,3 do if type(v[k])~='number' or v[k]~=v[k] or math.abs(v[k])==math.huge then return false end end
  return true
end
function Spike.new(inputs,rng)
  if not inputs or not valid(inputs.swiftOrigin or inputs.origin) or not valid(inputs.direction)
      or (inputs.swiftFrameOrigin and not valid(inputs.swiftFrameOrigin)) then
    return nil,'Spike Cannon requires live source and target anchors'
  end
  if not rng or type(rng.next)~='function' then return nil,'Spike Cannon requires injected RNG' end
  return {family=16,age=0,active=true,slots={},rng=rng,
    frameOrigin=copy(inputs.swiftFrameOrigin or {0,0,0})}
end
local function spawn(s,inputs)
  local origin=inputs.swiftOrigin or inputs.origin
  local angle=f(f((2-((math.floor(s.age/4)+2)%3))*.3490658700466156)+.5235987901687622)
  local velocity={f(f(inputs.direction[1]*7)*f(math.cos(angle))),
    f(f(math.sin(angle))*10),0}
  local index
  for i=1,4 do if not s.slots[i] or not s.slots[i].active then index=i;break end end
  if not index then return end
  local slot={active=true,age=0,life=40,sign=velocity[1]<0 and -1 or 1,
    maxRadius=4,scale=.8,rotation=.8,origin=vec(origin),nodes={}}
  for j=0,14 do
    slot.nodes[j+1]={alpha=math.floor(128*(14-j)/15),radius=2,
      angle=f(f((s.rng:next()%120)*f(2*math.pi))/120),
      position=vec(origin),velocity=vec(velocity)}
  end
  s.slots[index]=slot
end
local function advance(slot)
  slot.age=short(slot.age+1)
  if slot.age>slot.life then slot.active=false;return end
  local previous
  for j,n in ipairs(slot.nodes)do
    local saved={alpha=n.alpha,radius=n.radius,angle=n.angle,
      position=copy(n.position),velocity=copy(n.velocity)}
    if j==1 then
      for k=1,3 do n.position[k]=f(n.position[k]+n.velocity[k])end
      n.angle=f(n.angle+slot.rotation)
      n.velocity[1]=slot.sign>0 and math.min(20,f(n.velocity[1]+.4))
        or math.max(-20,f(n.velocity[1]-.4))
      local delta=f(slot.origin[2]-n.position[2])
      if slot.age<10 then
        n.velocity[2]=f(n.velocity[2]+f(delta*f((10-slot.age)*.01/10)))
        n.position[2]=f(n.position[2]+f(delta*f(slot.age*.07/10)))
      else
        n.velocity[2]=f(n.velocity[2]+delta*.01)
        n.position[2]=f(n.position[2]+delta*.07)
      end
      n.radius=math.min(slot.maxRadius,f(n.radius+2))
    else
      n.alpha,n.radius,n.angle,n.position,n.velocity=previous.alpha,
        previous.radius,previous.angle,previous.position,previous.velocity
    end
    previous=saved
  end
end
function Spike.step(s,inputs)
  if not s.active then return -1 end
  if not inputs or not valid(inputs.swiftOrigin or inputs.origin) or not valid(inputs.direction) then
    return nil,'Spike Cannon lost live source or target anchors'
  end
  s.age=short(s.age+1)
  if math.floor(s.age/4)<4 and s.age%4==0 then spawn(s,inputs)end
  if s.age>=2 then for _,slot in ipairs(s.slots)do if slot.active then advance(slot)end end end
  -- 84165008 returns zero even after its three native projectiles expire.
  return 0
end
function Spike.geometry(s,asset)
  if not asset then return nil end
  return Needle.geometry(s,asset,{headScale=.09,trailScale=true,
    trailTint={208,255,255},alpha=255})
end
function Spike.snapshot(s)
  local out=copy(s);out.rng=nil;out.kind='rom-spike-cannon-state'
  out.drawReady=true;return out
end
return Spike
