-- Industrial: a factory floor (power plant, Silph, hideouts). Concrete
-- tiles with painted safety lines, steel walls with ribs and high windows,
-- conveyors, hoppers, tanks, a gantry crane, pipes and glowing control
-- panels. Kenney Factory, City Industrial and Space Station meshes (CC0).
local Kit=require('mods.STADIUM2_IMPORTER.lib.scene_kit')

local HX,HZ,H=140,150,100

return Kit.scene{
 id='industrial',sceneShadows=false,
 fog={color={.22,.24,.28},range={220,560}},
 lighting=function(out)
  out.modelTint={.86,.90,.98};out.ambient={.50,.52,.56};out.diffuse={.46,.48,.52}
  out.light={-.3,-1,-.25};out.shadowStrength=.4
  out.bands={{.16,.17,.20},{.16,.17,.20}}
  return out
 end,
 glows=function()
  return {{-60,90,-60,140,.14,.15,.16},{60,90,-60,140,.14,.15,.16},{0,90,70,140,.14,.15,.16},
   {-120,20,-100,70,.04,.24,.20},{110,20,-120,70,.24,.16,.04}}
 end,
 build=function(k)
  local h=k.hash
  k.floor(HX,HZ,0,{.56,.56,.54},10)
  local ground=#k.rows
  -- Painted safety lines round the battle area.
  local yellow={.86,.70,.24}
  for _,s in ipairs({{-44,0,1.2,60},{44,0,1.2,60},{0,-60,44,1.2},{0,60,44,1.2}}) do k.box(s[1],.1,s[2],s[3],.1,s[4],0,yellow,6) end
  for i=-40,40,8 do k.box(i,.1,-66,2,.1,2.5,.7,i%16==0 and yellow or {.20,.20,.22},6) end
  k.hall(HX,HZ,H,{.46,.50,.56},9,{.30,.32,.36},9)
  -- Wall ribs and high windows.
  for x=-HX+20,HX-20,30 do k.box(x,H/2,-HZ+2,2,H/2,2,0,{.38,.42,.48},9) end
  for z=-HZ+20,HZ-20,30 do k.box(-HX+2,H/2,z,2,H/2,2,0,{.38,.42,.48},9) end
  for x=-HX+35,HX-35,30 do k.box(x,82,-HZ+1.2,9,6,.6,0,{.56,.70,.82},7) end
  -- Roof trusses and hanging lamps.
  for z=-120,120,60 do k.box(0,H-6,z,HX,2,2,0,{.34,.36,.40},9) end
  for _,p in ipairs({{-60,-60},{60,-60},{0,70}}) do
   k.box(p[1],H-18,p[2],.4,12,.4,0,{.30,.30,.32},9)
   k.column(p[1],p[2],H-34,H-30,7,2,10,{.40,.42,.46},9,{1.0,.96,.84},7)
  end
  -- Machinery behind the battle (the camera looks towards -x/-z).
  local steel,dark,rust={.56,.60,.64},{.36,.40,.46},{.62,.38,.26}
  for i,t in ipairs({{-96,-58,15,56},{-64,-98,13,48},{-104,10,11,40}}) do
   k.column(t[1],t[2],0,t[4],t[3],t[3],18,i%2==1 and steel or {.46,.56,.52},9,dark,9)
   for b=10,t[4]-6,14 do k.column(t[1],t[2],b,b+1.5,t[3]+.6,t[3]+.6,18,dark,9) end
   k.box(t[1],t[4]+3,t[2],3,3,3,0,dark,9)
  end
  -- A conveyor line on legs, carrying boxes.
  for x=-30,70,10 do
   k.box(x,12,-96,5,1.2,6,0,{.30,.32,.36},9)
   k.box(x,6,-101,.8,6,.8,0,dark,9);k.box(x,6,-91,.8,6,.8,0,dark,9)
  end
  for i,x in ipairs({-20,5,35,58}) do k.place('box-large',x,-96,14,i*.3,{y=13.2,center=true}) end
  k.place('hopper',80,-86,34,0,{center=true});k.place('hopper',104,-58,30,.5,{center=true})
  k.place('crane',-20,-118,22,0,{center=true})
  -- An overhead catwalk with rails on posts.
  k.box(0,42,-72,120,1,6,0,{.46,.48,.52},9)
  for _,dz in ipairs({-5.6,5.6}) do k.box(0,47,-72+dz,120,.4,.3,0,yellow,6) end
  for x=-110,110,44 do k.box(x,21,-72,1.5,21,1.5,0,dark,9) end
  -- Overhead pipes and wall risers.
  k.box(0,60,-60,HX,2.4,2.4,0,rust,9);k.box(0,54,-60,HX,1.6,1.6,0,{.42,.56,.52},9)
  for _,x in ipairs({-130,-124,124,130}) do k.column(x,-HZ+8,0,H,2.2,2.2,10,{.50,.54,.58},9) end
  -- Crates, cones and a control desk to the sides.
  for i,p in ipairs({{96,40,0},{104,62,.3},{92,84,-.2},{100,62,.1,true}}) do
   k.place('box-large',p[1],p[2],22,p[3],{y=p[4] and 12 or 0,center=true})
  end
  k.place('computer-system',-100,52,30,math.pi/2,{center=true})
  k.place('display-wall',-40,-HZ+6,34,0,{y=30,center=true});k.place('display-wall',20,-HZ+6,34,0,{y=30,center=true})
  for i,p in ipairs({{-50,-66},{50,-66},{-50,66},{50,66}}) do k.place('cone',p[1],p[2],18,i,{center=true}) end
  return ground
 end,
}
