-- Ice cave: a frozen cavern. A glassy, snow-dusted floor, icicles hanging
-- from the vault, frozen pillars and glowing crystal clusters that throw
-- cold light. Painted with the shared watercolor kit.
local Kit=require('mods.STADIUM2_IMPORTER.lib.scene_kit')

local function height(x,z)
 local r=math.sqrt(x*x+z*z)
 return .8*math.sin(x*.06)*math.sin(z*.05)*math.min(1,r/50)+math.max(0,r-140)*.25
end
local CLUSTERS={{-120,-95},{-150,40},{-40,-150},{110,-120},{140,70},{-90,130}}
local function ceiling(x,z)
 local r=math.sqrt(x*x+z*z)/185
 return -4+120*math.sqrt(math.max(0,1-r*r))
end

return Kit.scene{
 id='ice_cave',ground=height,
 fog={color={.24,.36,.48},range={140,420}},
 lighting=function(out)
  out.modelTint={.72,.82,.96};out.ambient={.42,.48,.58};out.diffuse={.30,.34,.42}
  out.light={-.25,-1,-.2};out.shadowStrength=.35
  out.bands={{.05,.09,.14},{.05,.09,.14}}
  return out
 end,
 glows=function()
  local out={}
  for i,c in ipairs(CLUSTERS) do out[i]={c[1],12,c[2],110,.10,.26,.36} end
  return out
 end,
 build=function(k)
  local h=k.hash
  k.terrain(-200,200,-200,200,8,height,function(x,y,z,ny)
   local n=h(math.floor(x*.4)+math.floor(z*.4)*977)
   local drift=math.sin(x*.045+math.sin(z*.03)*2)*math.sin(z*.05+1.3)
   if drift>.35 or math.sqrt(x*x+z*z)>150 then return {.80,.85,.93},11 end
   return {.52+n*.05,.68+n*.04,.82},8
  end)
  local ground=#k.rows
  k.shell(0,0,185,185,-4,120,3.1,function(f,a,n)
   if f<.22 then return {.64+n*.06,.78+n*.05,.90},8 end
   if f<.7 then return {.40+n*.06,.48+n*.05,.62},3 end
   return {.30+n*.05,.36+n*.04,.50},3
  end)
  -- Icicles hang from the vault; smaller ones gather round the walls.
  for i=0,140 do
   local a=i*2.39996;local r=30+h(i)*150
   local x,z=math.cos(a)*r,math.sin(a)*r
   k.spike(x,ceiling(x,z)+2,z,2+h(i+5)*4,10+h(i+9)*30,-1,{.78+h(i)*.08,.90,.98},8)
  end
  -- Glowing crystal clusters and frozen pillars.
  for c,p in ipairs(CLUSTERS) do
   for j=0,6 do
    local a=j*2.4+c;local d=h(c*9+j)*9
    local x,z=p[1]+math.cos(a)*d,p[2]+math.sin(a)*d
    k.spike(x,height(x,z)-1,z,2.5+h(c+j)*3.5,14+h(c*3+j)*26,1,{.55,.86,.96},j%2==0 and 7 or 8)
   end
  end
  for i,p in ipairs({{-70,-70,10,110},{95,-40,8,110},{-120,-10,12,110},{30,-120,9,110}}) do
   k.pillar(p[1],p[2],p[3],p[4],i*2.2,{.62,.78,.88},nil,nil,-3,.25)
  end
  for i=0,18 do
   local a=i*2.1;local r=55+h(i+40)*70
   local x,z=math.cos(a)*r,math.sin(a)*r
   k.place(({'rock-large-a','rock-tall-e','rock-large-c'})[i%3+1],x,z,8+h(i+50)*10,a,
    {y=height(x,z)-.5,tone={.70,.84,.94},material=8})
  end
  return ground
 end,
}
