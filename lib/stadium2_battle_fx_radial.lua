-- US fragment79 Radial20 mode 2, families 4/6/21. Native pool at
-- *(84187530)+3C8; ten records, twenty independently delayed nodes each.
local f=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float')
local Radial={families={[4]=true,[6]=true,[21]=true}}
local function copy(v)if type(v)~='table' then return v end local out={} for k,x in pairs(v) do out[k]=copy(x) end return out end
local function vec(v)return {f(v[1]),f(v[2]),f(v[3])}end
local function short(v)return (v+32768)%65536-32768 end
local function trunc(v)return v<0 and math.ceil(v) or math.floor(v)end
local function sine(n,d)return f(math.sin(f(n*6.2831854820251465/d)))end
function Radial.new(family,frameOrigin)
  assert(Radial.families[family]);return {family=family,slots={},frameOrigin=copy(frameOrigin or {0,0,0})}
end
function Radial.spawn(s,origin,direction,scale,rng)
  local c=s.family==6
  local r1,r2=rng:next(),rng:next()
  local velocity={f(direction[1]*8),f(f(f((r1%(c and 5 or 4))*f(c and .1 or .01))+f(f(direction[2]*4)+6))-f(c and .2 or .02)),
    f(-f((r2%5)*f(.3))+f(.6))}
  local index
  for i=1,10 do if not s.slots[i] or not s.slots[i].active then index=i;break end end
  if not index then return end
  local slot={active=true,age=0,life=60,mode=2,maxRadius=f(scale*(c and 3 or 4)),rotation=f(.1),nodes={},
    primary=s.family==4 and {100,200,255,200} or c and {255,255,255,100} or {255,255,100,255},
    environment=s.family==4 and {0,100,200,0} or c and {100,150,150,0} or {150,150,0,0}}
  local start1,period1,start2,period2=rng:next()%20+2,rng:next()%10+4,rng:next()%20+2,rng:next()%10+4
  for j=0,19 do
    local v=vec(velocity)
    local slow=sine((start2+j)%(period2+20),period2+20)
    local fast=sine((start1+j)%period1,period1)
    local ripple=sine((start2+j)%period2,period2)
    local axis=c and 2 or 3
    v[axis]=f(v[axis]+(c and 2 or 2.5)*fast*slow)
    axis=c and 3 or 2;v[axis]=f(v[axis]+.5*ripple)
    local p=vec(origin);p[1]=f(p[1]+v[1]*(j*.5-math.floor(j*.5)))
    slot.nodes[j+1]={delay=j,alpha=slot.primary[4],radius=f(scale),angle=0,position=p,velocity=v}
  end
  s.slots[index]=slot
end
function Radial.step(s,anchor)
  anchor=vec(anchor);local count=0
  for _,slot in ipairs(s.slots) do if slot.active then
    slot.age=short(slot.age+1)
    if slot.age>slot.life then slot.active=false else
      count=count+1
      for _,n in ipairs(slot.nodes) do
        if n.delay>0 then n.position=vec(anchor);n.delay=f(n.delay-1) else
          for k=1,3 do n.position[k]=f(n.position[k]+n.velocity[k]) end
          n.angle=f(n.angle+slot.rotation)
          if n.velocity[1]>1 then n.velocity[1]=f(n.velocity[1]-.1) end
          if n.velocity[1]<-1 then n.velocity[1]=f(n.velocity[1]+.1) end
          n.velocity[2]=math.max(-1,f(n.velocity[2]-.2))
          n.position[2]=math.max(0,n.position[2])
        end
      end
    end
  end end
  return count>0 and 0 or -1
end
function Radial.geometry(s)
  local g={kind='rom-beam',family=s.family,layers={}}
  for i=1,10 do
    local slot=s.slots[i];local active=slot and slot.active
    local cycle={3,5,1,5,1,7,3,7}
    local layer={pos={},uv={},idx={},color={},geometryMode=0x220005,draw={textures={-2},cycles=1,
      primary=active and copy(slot.primary) or {0,0,0,0},environment=active and copy(slot.environment) or {0,0,0,0},
      cycle0=cycle,cycle1=cycle,lodFraction=0,alpha=1,uv={0,0,0,0},scrollAndShift={0,0,0,0,0,0,0,0}}}
    for j=0,19 do
      local n=active and slot.nodes[j+1]
      for side=0,1 do
        local p={0,0,0}
        if n then
          local angle=side==1 and n.delay<=0 and f(n.angle+3.1415927410125732) or n.angle
          local degrees=f(angle*360/6.2831854820251465)
          local radians=f(degrees*f(3.1415926/180))
          p={n.position[1],f(n.position[2]-f(f(math.sin(radians))*n.radius)),f(n.position[3]+f(f(math.cos(radians))*n.radius))}
        end
        for k=1,3 do layer.pos[#layer.pos+1]=short(trunc(p[k]))-s.frameOrigin[k] end
        -- Raw S=j*256,T=0/512, full texture scale, native IA8 image 8x16.
        layer.uv[#layer.uv+1]=j;layer.uv[#layer.uv+1]=side
        for _,v in ipairs({255,255,255,255}) do layer.color[#layer.color+1]=v end
      end
    end
    for j=0,18 do for _,v in ipairs({1,3,2,3,4,2}) do layer.idx[#layer.idx+1]=j*2+v end end
    g.layers[#g.layers+1]=layer
  end
  return g
end
function Radial.snapshot(s)local out=copy(s);out.kind='rom-radial-state';out.drawReady=true;return out end
return Radial
