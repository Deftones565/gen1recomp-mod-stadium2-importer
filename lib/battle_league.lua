-- League: the grand hall of an Elite Four chamber. A dark marble floor with
-- a red carpet through the battle, rows of tall columns with braziers,
-- banners, and stairs up to a statue dais, lit by firelight.
-- Kenney Graveyard, Castle and Mini Arena meshes (CC0).
local Kit=require('mods.STADIUM2_IMPORTER.lib.scene_kit')

local HX,HZ,H=120,190,120
local BRAZIERS={{-70,-110},{70,-110},{-70,-30},{70,-30},{-70,60},{70,60}}

return Kit.scene{
 id='league',sceneShadows=false,
 fog={color={.10,.08,.12},range={200,560}},
 lighting=function(out)
  out.modelTint={.78,.74,.82};out.ambient={.40,.38,.46};out.diffuse={.40,.36,.36}
  out.light={-.3,-1,-.2};out.shadowStrength=.4
  out.bands={{.06,.05,.08},{.06,.05,.08}}
  return out
 end,
 glows=function()
  local out={}
  for i,b in ipairs(BRAZIERS) do out[i]={b[1],30,b[2],95,.62,.36,.12} end
  return out
 end,
 build=function(k)
  local h=k.hash
  k.floor(HX,HZ,0,{.42,.40,.50},10)
  local ground=#k.rows
  k.box(0,.15,-10,18,.15,HZ-20,0,{.58,.14,.16},5)
  k.box(0,.2,-10,20,.1,HZ-18,0,{.78,.62,.30},9)
  k.box(0,.32,-10,18,.1,HZ-20,0,{.58,.14,.16},5)
  k.hall(HX,HZ,H,{.34,.30,.36},3,{.18,.16,.22},3)
  -- Columns in two rows, with capitals and bases.
  for z=-150,150,60 do for _,x in ipairs({-80,80}) do
   k.column(x,z,0,H,7,6.2,16,{.66,.62,.66},3)
   k.box(x,H-4,z,10,4,10,0,{.58,.54,.58},3);k.box(x,3,z,10,3,10,0,{.58,.54,.58},3)
  end end
  -- Braziers on pedestals with flames.
  for i,b in ipairs(BRAZIERS) do
   k.column(b[1],b[2],0,20,4,3,10,{.50,.46,.50},3)
   k.place('fire-basket',b[1],b[2],24,i,{y=20,center=true,tone={.40,.34,.28}})
   for j=0,4 do
    local a=j*1.3+i
    k.spike(b[1]+math.cos(a)*2.5,23,b[2]+math.sin(a)*2.5,2.4,8+h(i*7+j)*6,1,{1.0,.62+h(j)*.2,.24},7)
   end
  end
  -- Banners hanging between the columns.
  for z=-120,120,60 do for _,x in ipairs({-HX+2,HX-2}) do
   k.box(x,70,z,.6,34,12,0,{.56,.14,.18},5)
   k.box(x,38,z,.8,2,12,0,{.80,.64,.30},9)
  end end
  -- Stairs up to a dais with a statue.
  for s=0,5 do k.box(0,s*2.5+1.25,-HZ+40-s*5,46,1.25+s*2.5,4,0,{.50,.48,.56},10) end
  k.box(0,15,-HZ+15,50,1,15,0,{.46,.44,.52},10)
  k.place('arena-statue',0,-HZ+14,56,0,{y=16,center=true,tone={.74,.66,.40},material=9})
  for _,x in ipairs({-40,40}) do k.place('arena-banner',x,-HZ+4,50,0,{y=18,center=true,tone={.60,.16,.18},material=5}) end
  -- Ceiling beams.
  for z=-160,160,40 do k.box(0,H-3,z,HX,3,3,0,{.26,.22,.26},2) end
  return ground
 end,
}
