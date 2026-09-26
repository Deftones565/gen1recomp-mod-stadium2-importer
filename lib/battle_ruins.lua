-- Ruins: an ancient stone court in warm late light. The battle sits on a
-- worn round plaza ringed by broken columns; tumbled walls, an archway,
-- urns and lanterns stand among grass and crooked pines. Kenney Graveyard
-- and Castle Kit meshes (CC0), painted with the shared watercolor kit.
local Kit=require('mods.STADIUM2_IMPORTER.lib.scene_kit')

local function height(x,z)
 local r=math.sqrt(x*x+z*z)
 if r<66 then return 0 end
 return math.max(0,r-66)^1.2*.03+1.2*math.sin(x*.04)*math.sin(z*.05)
end
local LANTERNS={{-62,-40},{40,-64},{-30,70},{66,30}}

return Kit.scene{
 id='ruins',outdoor=true,visitors=true,ground=height,
 sky={haze={.86,.78,.64},tint={1.05,.96,.86}},
 fog={color={.84,.77,.64},night={.10,.12,.22},range={260,1300}},
 moon={-.86,.26,-.44},
 lighting=function(out,daytime)
  if daytime=='NITE' then out.modelTint={.28,.32,.48}
  else out.modelTint={1.05,.96,.86} end
  return out
 end,
 glows=function(env)
  local out={}
  local night=env.daytime=='NITE'
  for i,p in ipairs(LANTERNS) do out[i]={p[1],14,p[2],night and 80 or 40,night and .55 or .18,night and .36 or .12,night and .14 or .05} end
  return out
 end,
 build=function(k)
  local h=k.hash
  k.terrain(-700,700,-700,700,14,height,function(x,y,z,ny)
   local r=math.sqrt(x*x+z*z)
   if r<200 then return nil end
   local n=h(math.floor(x*.2)+math.floor(z*.3)*977)
   return {.46+n*.06,.54+n*.05,.31},1
  end)
  k.terrain(-210,210,-210,210,7,height,function(x,y,z,ny)
   local r=math.sqrt(x*x+z*z)
   local n=h(math.floor(x*.3)+math.floor(z*.5)*977)
   if r<62 then
    -- Worn flagstones with grass creeping through the cracks.
    local moss=math.sin(x*.05+math.sin(z*.04)*2)*math.sin(z*.045+1.1)
    local m=math.max(0,moss-.3)*.5
    return {.72+n*.05-m*.25,.66+n*.05-m*.10,.56+n*.04-m*.25},10
   end
   if r<70 then return {.60,.56,.48},3 end
   return {.46+n*.06,.54+n*.05,.31},1
  end)
  local ground=#k.rows
  -- A ring of columns, some broken.
  -- Only the far half of the ring, so the camera always sees the battle.
  for i=0,9 do
   local a=math.pi*.62+i/9*math.pi*1.12
   local x,z=math.cos(a)*84,math.sin(a)*84
   local broken=i%3==1
   k.place('column-large',x,z,40,a,{stretch=broken and .45 or 1,tone={.74,.70,.62},materials={[2]=3,[4]=3},center=true})
   if broken then k.place('debris',x+8,z+6,40,a,{tone={.70,.66,.58},center=true}) end
  end
  -- Tumbled walls and an archway behind the court.
  for i,w in ipairs({{-150,-80,.9},{-120,-140,.4},{-40,-170,.1},{60,-160,-.3},{140,-100,-.8},{-170,40,1.4}}) do
   k.place(i%2==0 and 'stone-wall-damaged' or 'stone-wall-column',w[1],w[2],70,w[3],{tone={.70,.66,.58},center=true})
  end
  k.place('tower-arch',-95,-110,70,.7,{tone={.74,.70,.62},center=true})
  for i,p in ipairs({{-104,-60},{-60,-120},{120,-40},{-120,70}}) do
   k.place('pillar-square',p[1],p[2],60,i,{stretch=.6+h(i)*.6,tone={.72,.68,.60},center=true})
  end
  for i,p in ipairs(LANTERNS) do
   k.column(p[1],p[2],0,6,3,2.4,8,{.62,.58,.50},3)
   k.place('lantern',p[1],p[2],26,i,{y=6,center=true})
  end
  for i,p in ipairs({{-56,-56},{58,-52},{-40,60},{62,44}}) do k.place('urn',p[1],p[2],32,i,{tone={.66,.52,.40},center=true}) end
  k.place('altar',0,-110,60,0,{tone={.70,.66,.58},center=true})
  k.place('stairs-stone',0,-92,42,math.pi/2,{tone={.70,.66,.58},center=true})
  -- Greenery: crooked pines, bushes and grass.
  for i=0,40 do
   local a=i*2.39996;local r=150+h(i+5)*260
   local x,z=math.cos(a)*r,math.sin(a)*r
   k.place(i%3==0 and 'pine-crooked' or 'pine-a',x,z,i%3==0 and 30+h(i)*10 or 34+h(i)*16,a,{y=height(x,z)-.5,tone={.24+h(i)*.05,.42,.28}})
  end
  for i=0,120 do
   local a=i*2.39996;local r=70+h(i+30)*110
   local x,z=math.cos(a)*r,math.sin(a)*r
   k.place(i%4==0 and 'bush-large' or 'grass-large',x,z,i%4==0 and 40+h(i)*20 or 12+h(i)*8,a,{y=height(x,z)-.2,tone={.36+h(i)*.06,.52,.29}})
  end
  return ground
 end,
}
