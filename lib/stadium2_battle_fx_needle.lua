-- US fragment79 family 17: 84158588 / 84165670 / 84165C2C / 84165CC0.
local f=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float')
local Needle={}
local function copy(v)if type(v)~='table' then return v end local t={} for k,x in pairs(v) do t[k]=copy(x) end return t end
local function vec(v)return {f(v[1]),f(v[2]),f(v[3])}end
local function short(v)return (v+32768)%65536-32768 end
local function trunc(v)return v<0 and math.ceil(v) or math.floor(v)end
function Needle.new(origin,direction,species,rng,frameOrigin)
  local slot={active=true,age=0,life=40,sign=direction[1]<0 and -1 or 1,
    maxRadius=species==13 and 2 or 4,scale=f(species==13 and .08 or .16),rotation=f(.6),nodes={}}
  for j=0,14 do
    slot.nodes[j+1]={alpha=math.floor(160*(14-j)/15),radius=2,
      angle=f(f((rng:next()%120)*f(2*math.pi))/120),position=vec(origin),
      velocity={f(direction[1]*5),f(direction[2]*5),f(direction[3]*5)}}
  end
  return {family=17,slots={slot},frameOrigin=copy(frameOrigin or {0,0,0})}
end
function Needle.step(s)
  for _,slot in ipairs(s.slots) do if slot.active then
    slot.age=short(slot.age+1)
    if slot.age>slot.life then slot.active=false else
      local previous
      for j,n in ipairs(slot.nodes) do
        local saved={radius=n.radius,angle=n.angle,position=copy(n.position),velocity=copy(n.velocity)}
        if j==1 then
          for k=1,3 do n.position[k]=f(n.position[k]+n.velocity[k]) end
          n.angle=f(n.angle+slot.rotation)
          n.velocity[1]=slot.sign>0 and math.min(20,f(n.velocity[1]+.4)) or math.max(-20,f(n.velocity[1]-.4))
          n.radius=math.min(slot.maxRadius,f(n.radius+2))
        else
          n.radius,n.angle,n.position,n.velocity=previous.radius,previous.angle,previous.position,previous.velocity
        end
        previous=saved
      end
    end
  end end
  -- Unlike Swift, the native pool never ends the lifecycle; wrapper expires at 50.
  return 0
end
local function rotation(angle,sign)
  local r=f(f(f(f(angle*-360)*sign)/6.2831854820251465)*f(3.1415926/180))
  local p=f((90-sign*90)*f(3.1415926/180))
  local sr,cr,sp,cp=f(math.sin(r)),f(math.cos(r)),f(math.sin(p)),f(math.cos(p))
  return function(v)
    return {f(f(f(v[1]*cp)+f(v[2]*f(sr*sp)))+f(v[3]*f(cr*sp))),
      f(f(v[2]*cr)-f(v[3]*sr)),
      f(f(f(-v[1]*sp)+f(v[2]*f(sr*cp)))+f(v[3]*f(cr*cp)))}
  end
end
function Needle.geometry(s,asset)
  if not asset then return nil end
  local g={kind='rom-beam',family=17,layers={}}
  for i=1,4 do
    local slot=s.slots[i];local active=slot and slot.active
    for _,trail in ipairs({false,true}) do
      local cycle=trail and {15,15,31,4,7,7,7,4} or {5,4,1,4,1,7,4,7}
      local layer={pos={},uv={},idx={},color={},nrm=not trail and {} or nil,lighting=not trail,
        geometryMode=trail and 0x200005 or 0x220405,
        draw={textures=trail and {} or {-3},cycles=1,primary={197,184,122,255},environment={197,184,122,255},
          cycle0=cycle,cycle1=cycle,lodFraction=255,alpha=1,uv={0,0,0,0},scrollAndShift={0,0,0,0,0,0,0,0}}}
      local head=active and slot.nodes[1]
      local visible=active and (trail or head.position[2]>0)
      local transform=head and rotation(head.angle,slot.sign)
      for v=1,trail and 30 or #asset.pos/3 do
        local p={0,0,0};local n=visible and (trail and slot.nodes[math.floor((v-1)/2)+1] or head)
        if trail then
          if n then
            local angle=f(n.angle+(v%2==0 and 3.1415927410125732 or 0))
            local rad=f(f(angle*360/6.2831854820251465)*f(3.1415926/180))
            p={short(trunc(n.position[1])),math.max(0,short(trunc(f(n.position[2]-f(f(math.sin(rad))*n.radius))))),
              short(trunc(f(n.position[3]+f(f(math.cos(rad))*n.radius))))}
          end
          for _,c in ipairs({192,255,255,n and n.alpha or 0}) do layer.color[#layer.color+1]=c end
        else
          local offset=(v-1)*3
          local normal={asset.nrm[offset+1],asset.nrm[offset+2],asset.nrm[offset+3]}
          if transform then normal=transform(normal) end
          for k=1,3 do layer.nrm[#layer.nrm+1]=normal[k] end
          if n then
            p=transform({asset.pos[offset+1]*slot.scale,asset.pos[offset+2]*slot.scale,asset.pos[offset+3]*slot.scale})
            for k=1,3 do p[k]=f(p[k]+n.position[k]) end
          end
          for _,c in ipairs({255,255,255,n and 255 or 0}) do layer.color[#layer.color+1]=c end
        end
        for k=1,3 do layer.pos[#layer.pos+1]=p[k]-s.frameOrigin[k] end
        layer.uv[#layer.uv+1]=trail and 0 or asset.uv[v*2-1]
        layer.uv[#layer.uv+1]=trail and 0 or asset.uv[v*2]
      end
      if trail then for j=0,13 do for _,v in ipairs({1,3,2,3,4,2}) do layer.idx[#layer.idx+1]=j*2+v end end
      else layer.idx=asset.idx end
      g.layers[#g.layers+1]=layer
    end
  end
  return g
end
function Needle.snapshot(s)local out=copy(s);out.kind='rom-needle-state';out.drawReady=true;return out end
return Needle
