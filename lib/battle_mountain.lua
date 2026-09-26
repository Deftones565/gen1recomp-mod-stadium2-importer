-- Mountain: an alpine meadow on a high ledge. Ahead the ground drops into a
-- hazy valley below snow-capped peaks; pines climb the slope behind.
-- Kenney Nature Kit meshes (CC0), painted with the shared watercolor kit.
local Kit=require('mods.STADIUM2_IMPORTER.lib.scene_kit')

-- The default camera looks along VIEW. The ledge drops away that way into a
-- valley, with snowy peaks on the far side; behind the camera a slope rises.
local VX,VZ=-.73,-.69
local PEAKS={{-560,-820,520,300},{-900,-420,600,360},{-250,-980,430,260},{-1050,-900,700,420},
 {-760,-1180,480,300},{-1200,-120,520,330},{80,-1050,380,230},{-1300,-600,460,280},{-420,-1350,560,320}}
local function peaks(x,z)
 local y=0
 for _,p in ipairs(PEAKS) do
  local d=math.sqrt((x-p[1])^2+(z-p[2])^2)
  local f=math.max(0,1-d/p[4])
  local a=math.atan2(z-p[2],x-p[1])
  y=math.max(y,p[3]*f^1.25*(1+.10*math.sin(a*5+p[1])+.06*math.sin(a*11)))
 end
 return y
end
local function height(x,z)
 local d=x*VX+z*VZ
 local near=1.4*math.sin(x*.05)*math.sin(z*.045)
 if d<-70 then return near+(-d-70)^1.3*.22 end            -- slope behind the camera
 if d<110 then return near end                            -- the ledge
 local drop=-math.min(170,(d-110)^1.12*.62)                -- down into the valley
 return drop+peaks(x,z)+near*.5
end
Kit.mountainHeight=height

return Kit.scene{
 id='mountain',outdoor=true,visitors=true,
 ground=height,
 sky={haze={.74,.81,.87}},
 fog={color={.74,.81,.87},night={.10,.14,.24},range={330,2000}},
 moon={-.84,.24,-.48},
 lighting=function(out,daytime)
  if daytime=='NITE' then out.modelTint={.28,.33,.50} end
  return out
 end,
 build=function(k)
  local h=k.hash
  local function paint(x,y,z,ny)
   local n=h(math.floor(x*.3)+math.floor(z*.7)*131)
   local r=math.sqrt(x*x+z*z)
   local peak=peaks(x,z)
   if peak>120 and y>-170+peak*.55+18*math.sin(x*.01) and ny>.45 then return {.93,.95,.98},11 end
   if ny<.70 or (peak>60 and y>-110) then return {.54+n*.05,.53+n*.05,.50+n*.04},3 end
   local worn=1-math.min(1,math.max(0,(r-26)/40))
   return {.44+n*.06+worn*.12,.55+n*.05-worn*.02,.31+n*.03+worn*.06},1
  end
  k.terrain(-300,300,-300,300,10,height,paint)
  -- A coarser far field fills the valley and the peaks around the near grid.
  k.terrain(-1700,1700,-1700,1700,34,height,function(x,y,z,ny)
   if math.abs(x)<300 and math.abs(z)<300 then return nil end
   return paint(x,y,z,ny)
  end)
  local ground=#k.rows
  -- Rock spires behind the battle, crowned with snow.
  for i,s in ipairs({{-300,-250,24,150},{-190,-400,18,120},{-420,-80,28,170},{-80,-470,20,130},{-470,-380,30,190},{120,-420,14,90}}) do
   k.pillar(s[1],s[2],s[3],s[4],i*1.9,{.55,.54,.52},{.93,.95,.98},11,height(s[1],s[2])-4,.55)
  end
  -- Pines on the lower slopes.
  local pines={'pine-a','pine-b','pine-tall','pine-small'}
  for i=0,260 do
   local a=i*2.39996;local r=90+h(i+3)*520
   local x,z=math.cos(a)*r,math.sin(a)*r
   local y=height(x,z)
   local d,l=x*VX+z*VZ,x*VZ-z*VX
   local wedge=d>0 and math.abs(l)<d*.9+40
   if y<95 and y>-165 and (x*x+z*z)>80*80 and peaks(x,z)<60 and (not wedge or d>200) then
    k.place(pines[i%4+1],x,z,20+h(i+9)*16,h(i+17)*6.28,{tone={.22+h(i)*.05,.40+h(i+1)*.06,.30},y=y-.5})
   end
  end
  -- Boulders, flowers and grass round the meadow.
  for i=0,40 do
   local a=i*2.1+h(i+50);local r=48+h(i+60)*80
   local x,z=math.cos(a)*r,math.sin(a)*r
   local d,l=x*VX+z*VZ,x*VZ-z*VX
   if not (d>0 and math.abs(l)<d*.9+30) then
   k.place(({'rock-large-a','rock-tall-a','stone-tall-b','rock-large-c'})[i%4+1],x,z,8+h(i+70)*12,a,{y=height(x,z)-.6,tone={.56,.55,.52}})
   end
  end
  for i=0,110 do
   local a=i*2.39996;local r=30+h(i+90)*95
   local x,z=math.cos(a)*r,math.sin(a)*r
   if r>38 then
    k.place(i%3==0 and 'flower_purpleA' or 'grass-large',x,z,9+h(i+100)*6,a,{y=height(x,z)-.1,
     tone=i%3~=0 and {.40,.56,.30} or nil})
   end
  end
  k.place('log',-58,18,24,1.2,{tone={.52,.40,.29}})
  k.place('stump',52,-40,26,.4,{tone={.54,.42,.30}})
  return ground
 end,
}
