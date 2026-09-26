-- Cave water: an underground lake. Both battlers ride log rafts on dark,
-- still water; stalactites hang overhead, rock pillars rise out of the lake
-- and glowing teal crystals and mushrooms light the rocky shore.
local Kit=require('mods.STADIUM2_IMPORTER.lib.scene_kit')

local SHORE=130
local function height(x,z)
 local r=math.sqrt(x*x+z*z);local a=math.atan2(z,x)
 local edge=SHORE+8*math.sin(a*4)+5*math.sin(a*9+1)
 if r<edge then return -6 end
 return -.95+(r-edge)*.22+2*math.sin(x*.07)*math.sin(z*.06)
end
local PILLARS={{-70,-60,11},{60,-80,9},{-95,35,8},{35,85,7}}
local GLOWS={{-150,-40},{-60,-150},{95,-120},{150,50},{-120,110}}
local function ceiling(x,z)
 local r=math.sqrt(x*x+z*z)/200
 return -8+115*math.sqrt(math.max(0,1-r*r))
end

return Kit.scene{
 id='cave_water',ground=height,
 fog={color={.06,.13,.16},range={120,380}},
 lighting=function(out)
  out.modelTint={.66,.78,.86};out.ambient={.30,.36,.42};out.diffuse={.18,.22,.26}
  out.light={-.2,-1,-.3};out.shadowStrength=.35
  out.bands={{.02,.05,.06},{.02,.05,.06}}
  return out
 end,
 glows=function()
  local out={}
  for i,g in ipairs(GLOWS) do out[i]={g[1],10,g[2],120,.06,.30,.28} end
  out[6]={0,60,0,160,.10,.14,.16}
  return out
 end,
 water={level=-.95,deep={.03,.10,.13},mid={.05,.20,.24},shallow={.12,.32,.32},calm=.6,
  shore={0,0,SHORE},rafts={{0,24,13.5,7.5},{0,-24,13.5,7.5}},
  foams=(function() local f={} for i,p in ipairs(PILLARS) do f[i]={p[1],p[2],p[3]} end return f end)()},
 build=function(k)
  local h=k.hash
  k.terrain(-220,220,-220,220,8,height,function(x,y,z,ny)
   if y<-2 then return nil end
   local n=h(math.floor(x*.4)+math.floor(z*.4)*977)
   return {.36+n*.05,.36+n*.05,.34+n*.04},3
  end)
  local ground=#k.rows
  k.shell(0,0,205,205,-8,115,5.3,function(f,a,n)
   if f<.25 then return {.34+n*.05,.33+n*.05,.31},3 end
   return {.24+n*.04,.25+n*.04,.26},3
  end)
  for i=0,120 do
   local a=i*2.39996;local r=20+h(i)*170
   local x,z=math.cos(a)*r,math.sin(a)*r
   k.spike(x,ceiling(x,z)+2,z,3+h(i+5)*5,12+h(i+9)*34,-1,{.34+h(i)*.06,.33,.31},3)
  end
  for i,p in ipairs(PILLARS) do k.pillar(p[1],p[2],p[3],120,i*1.7,{.36,.35,.33},nil,nil,-6,.3) end
  -- Stalagmites and glowing crystals along the shore.
  for i=0,40 do
   local a=i*2.39996;local r=SHORE+12+h(i+30)*50
   local x,z=math.cos(a)*r,math.sin(a)*r
   k.spike(x,height(x,z)-1,z,3+h(i+31)*4,10+h(i+32)*22,1,{.38,.37,.35},3)
  end
  for c,g in ipairs(GLOWS) do
   for j=0,5 do
    local a=j*2.4+c;local d=h(c*9+j)*10
    local x,z=g[1]+math.cos(a)*d,g[2]+math.sin(a)*d
    k.spike(x,height(x,z)-1,z,2+h(c+j)*3,10+h(c*3+j)*20,1,{.40,.92,.84},j%2==0 and 7 or 8)
   end
   k.place('mushroom',g[1]+14,g[2]+6,26,c,{y=height(g[1]+14,g[2]+6)-.5,tone={.46,.86,.78},material=7})
  end
  k.raft(24);k.raft(-24)
  return ground
 end,
}
