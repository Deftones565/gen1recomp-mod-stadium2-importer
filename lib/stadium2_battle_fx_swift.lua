-- US fragment79 family 2: 84157128, 84162798, 84162AC8, 84162C88.
-- Fixed native pool; trail history advances at 30 Hz, never on host redraw.
local f=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float')
local Swift={}
local function copy(x) if type(x)~='table' then return x end local y={} for k,v in pairs(x) do y[k]=copy(v) end return y end
local function short(x)return (x+32768)%65536-32768 end
local function trunc(x)return x<0 and math.ceil(x) or math.floor(x) end
local function rotate(x,z,angle,heading)
  local p=f(f(angle*360/6.2831854820251465)*f(3.1415926/180))
  local h=heading and p or 0
  local r=f(90*f(3.1415926/180))
  local sr,cr,sp,cp,sh,ch=f(math.sin(r)),f(math.cos(r)),f(math.sin(p)),f(math.cos(p)),f(math.sin(h)),f(math.cos(h))
  return {f(f(x*f(cp*ch))+f(z*f(f(f(cr*sp)*ch)+f(sr*sh)))),
    f(f(x*f(cp*sh))+f(z*f(f(f(cr*sp)*sh)-f(sr*ch)))),f(f(-x*sp)+f(z*f(cr*cp)))}
end
local function capture(slot)
  local offset
  for i,n in ipairs(slot.nodes) do
    if i==1 or slot.age<2 then
      n.vertices={}
      for k=0,1 do
        if i==1 then offset=rotate(0,f(f(10*slot.scale)*f(.8)),f(n.angle+k*3.1415927410125732),true) end
        for axis=1,3 do n.vertices[#n.vertices+1]=short(trunc(f(n.position[axis]+offset[axis]))) end
      end
    end
  end
end
function Swift.new(frameOrigin)return {slots={},age=0,phase=0,threshold=0,family=2,frameOrigin=copy(frameOrigin or {0,0,0})}end
function Swift.spawn(s,origin,direction,scale,rng)
  local p={}
  for k=1,3 do p[k]=f(origin[k]+f(scale*(30-(rng:next()%60)))) end
  if s.phase==2 then return end
  local index
  for i=1,14 do if not s.slots[i] or not s.slots[i].active then index=i;break end end
  if not index then return end
  p[2]=f(f(p[2]+10)+25)
  local slot={active=true,age=0,phase=0,life=30,sign=p[1]>0 and -1 or 1,scale=f(scale*.5),nodes={}}
  for j=0,9 do
    slot.nodes[j+1]={alpha=math.floor(60*(9-j)/10),angle=f((rng:next()%100)*6.2831854820251465/100),
      position=copy(p),velocity={f(direction[1]*20),f(direction[2]*20),f(direction[3]*20)}}
  end
  capture(slot);s.slots[index]=slot
end
function Swift.step(s,signal)
  s.age=short(s.age+1)
  if signal==1 and s.phase==0 then s.threshold=short(s.age+70);s.phase=1
  elseif s.phase==1 and s.age>s.threshold-50 then s.phase=2
  elseif s.phase==2 and s.age>s.threshold then return -1 end
  local count=0
  for _,slot in ipairs(s.slots) do if slot.active then
    slot.age=short(slot.age+1)
    if slot.age>slot.life+10 then slot.active=false else
      count=count+1
      for j=10,2,-1 do slot.nodes[j].vertices=copy(slot.nodes[j-1].vertices) end
      local n=slot.nodes[1]
      if slot.phase==0 then
        n.position[2]=f(n.position[2]-1)
        if slot.age>=11 then slot.phase=1 end
        n.angle=f(n.angle+2*f(.3))
      else
        for k=1,3 do n.position[k]=f(n.position[k]+n.velocity[k]) end
        n.velocity[1]=slot.sign>0 and math.min(20,f(n.velocity[1]+2)) or math.max(-20,f(n.velocity[1]-2))
        n.angle=f(n.angle+f(.3))
      end
      capture(slot)
    end
  end end
  return count>0 and 0 or -1
end
function Swift.geometry(s)
  -- Beam's layered mesh protocol supports both textured stars and shade trails.
  local g={kind='rom-beam',family=2,layers={}}
  for i=1,14 do
    local slot=s.slots[i];local active=slot and slot.active
    for _,trail in ipairs({false,true}) do
      local layer={pos={},uv={},idx={},color={},draw={textures={39},primary={255,255,255,255},environment={255,255,64,20},
        cycles=1,lodFraction=0,alpha=1,uv={0,0,0,0},scrollAndShift={0,0,0,0,0,0,0,0}}}
      -- G_CC_SHADE or G_CC_BLENDIA: (ENV-SHADE)*TEXEL0+SHADE.
      local cycle=trail and {15,15,31,4,7,7,7,4} or {5,4,1,4,1,7,4,7}
      layer.draw.cycle0=cycle;layer.draw.cycle1=cycle
      local n=active and slot.nodes[1]
      local visible=active and (not trail or slot.phase==1)
      for v=1,trail and 20 or 4 do
        local p={0,0,0}
        if visible then
          if trail then local node=slot.nodes[math.floor((v-1)/2)+1];local at=(v-1)%2*3
            p={node.vertices[at+1],node.vertices[at+2],node.vertices[at+3]}
          else
            p=rotate((v%2==1 and -10 or 10)*slot.scale,(v<=2 and -10 or 10)*slot.scale,n.angle,slot.phase==1)
            for k=1,3 do p[k]=f(p[k]+n.position[k]) end
          end
        end
        for k=1,3 do layer.pos[#layer.pos+1]=p[k]-s.frameOrigin[k] end
        layer.uv[#layer.uv+1]=v%2==1 and 1984/2048 or 0;layer.uv[#layer.uv+1]=v<=2 and 0 or 1984/2048
        local alpha=visible and (trail and slot.nodes[math.floor((v-1)/2)+1].alpha or 200) or 0
        for _,c in ipairs({255,255,trail and 0 or 255,alpha}) do layer.color[#layer.color+1]=c end
      end
      if trail then for j=0,8 do for _,v in ipairs({1,2,3,2,4,3}) do layer.idx[#layer.idx+1]=j*2+v end end
      else layer.idx={1,3,2,3,4,2} end
      g.layers[#g.layers+1]=layer
    end
  end
  return g
end
function Swift.snapshot(s)
  local out=copy(s);out.kind="rom-swift-state";out.drawReady=true;return out
end
return Swift
