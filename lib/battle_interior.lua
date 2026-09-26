-- Interior: a cozy home. Warm plank floor with a rug under the battle,
-- cream plaster walls over wood wainscoting, ceiling beams, sunny windows,
-- and Kenney Furniture Kit pieces (CC0) along the walls.
local Kit=require('mods.STADIUM2_IMPORTER.lib.scene_kit')

local HX,HZ,H=105,105,78
local F=52 -- furniture scale: a bookcase stands about 46 units tall

return Kit.scene{
 id='interior',sceneShadows=false,
 fog={color={.60,.52,.42},range={260,600}},
 lighting=function(out)
  out.modelTint={1.0,.96,.90};out.ambient={.64,.60,.56};out.diffuse={.62,.56,.48}
  out.light={-.45,-1,-.2};out.shadowStrength=.45
  out.bands={{.40,.34,.28},{.40,.34,.28}}
  return out
 end,
 glows=function()
  return {{-86,40,-86,90,.34,.24,.10},{86,40,-90,80,.30,.22,.10},{0,72,0,150,.16,.12,.07},
   {-88,40,64,90,.26,.20,.10}}
 end,
 build=function(k)
  local h=k.hash
  -- Plank floor: long boards along X with slight tone changes.
  for i=-HZ,HZ-6,6 do
   local shade=.9+h(i+300)*.16
   k.box(0,-.6,i+3,HX,.6,2.9,0,{.62*shade,.46*shade,.32*shade},2,true)
  end
  local ground=#k.rows
  k.hall(HX,HZ,H,{.90,.84,.72},4,{.92,.88,.80},4)
  -- Wainscot, baseboard and crown moulding.
  for _,w in ipairs({{0,-HZ+1,HX,1},{0,HZ-1,HX,1},{-HX+1,0,1,HZ},{HX-1,0,1,HZ}}) do
   k.box(w[1],11,w[2],w[3],11,w[4],0,{.54,.40,.28},2)
   k.box(w[1],H-2,w[2],w[3]+.5,2,w[4]+.5,0,{.96,.93,.86},4)
  end
  -- Ceiling beams.
  for x=-80,80,40 do k.box(x,H-4,0,3,4,HZ,0,{.48,.35,.24},2) end
  -- Windows: bright panes in wooden frames on the far walls.
  for _,x in ipairs({-50,30}) do
   k.box(x,44,-HZ+1.4,18,16,.7,0,{.84,.92,.98},7)
   k.box(x,44,-HZ+1.9,20,18,.4,0,{.58,.44,.30},2)
   k.box(x,44,-HZ+2.4,1,16,.4,0,{.58,.44,.30},2);k.box(x,44,-HZ+2.4,18,1,.4,0,{.58,.44,.30},2)
  end
  for _,z in ipairs({-30,40}) do
   k.box(-HX+1.4,44,z,.7,16,18,0,{.84,.92,.98},7)
   k.box(-HX+1.9,44,z,.4,18,20,0,{.58,.44,.30},2)
  end
  -- A rug under the battle.
  k.place('rug',0,0,52,math.pi/2,{y=.02,tone={.66,.30,.26},material=5,center=true})
  k.place('rug-round',0,0,34,0,{y=.62,tone={.86,.76,.52},material=5,center=true})
  -- Furniture along the walls, clear of the battle.
  for i=0,2 do k.place('bookcase',-HX+8,-70+i*22,F,math.pi/2,{center=true}) end
  k.place('bookcase-wide',-40,-HZ+6,F,0)
  k.place('desk',50,-HZ+10,F,0);k.place('computer',44,-HZ+10,F,0,{y=.38*F})
  k.place('chair-desk',52,-HZ+26,F,math.pi)
  k.place('sofa',-HX+16,40,F,math.pi/2,{center=true});k.place('side-table',-HX+14,72,F,math.pi/2,{center=true})
  k.place('lamp-table',-HX+14,72,F,0,{y=.38*F,center=true})
  k.place('table-round',72,48,F,0,{y=.27*F,center=true})
  for i=0,3 do local a=i*math.pi/2;k.place('chair',72+math.cos(a)*24,48+math.sin(a)*24,F,-a-math.pi/2,{center=true}) end
  k.place('tv',HX-10,-30,F,-math.pi/2,{center=true})
  k.place('lamp-floor',-86,-86,F,0);k.place('lamp-floor',86,-90,F,0)
  k.place('potted-plant',-HX+10,-HZ+10,F*1.1,1);k.place('potted-plant',HX-10,HZ-10,F*1.1,2)
  k.place('potted-plant',HX-12,-HZ+12,F*1.1,3)
  k.place('coat-rack',HX-12,80,F,0)
  k.place('radio',-40,-HZ+8,F,0,{y=.79*F})
  k.place('box-closed',80,-60,F,.3);k.place('box-open',86,-72,F,1.2)
  k.place('kitchen-fridge',HX-12,-88,F,-math.pi/2,{center=true})
  return ground
 end,
}
