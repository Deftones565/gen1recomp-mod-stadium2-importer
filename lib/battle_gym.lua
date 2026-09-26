-- Gym: a bright battle hall. A painted court with white lines and a centre
-- ring on a polished floor, tiered stands down both sides, banners, statues
-- by the entrance and tall windows under a lit ceiling. Kenney Mini Arena
-- meshes (CC0), painted with the shared watercolor kit.
local Kit=require('mods.STADIUM2_IMPORTER.lib.scene_kit')

local HX,HZ,H=130,150,96

return Kit.scene{
 id='gym',sceneShadows=false,
 fog={color={.70,.72,.76},range={280,650}},
 lighting=function(out)
  out.modelTint={1.02,1.0,.98};out.ambient={.70,.70,.72};out.diffuse={.70,.68,.64}
  out.light={-.3,-1,-.3};out.shadowStrength=.45
  out.bands={{.60,.62,.66},{.60,.62,.66}}
  return out
 end,
 glows=function()
  return {{0,90,-40,170,.14,.14,.13},{0,90,60,170,.14,.14,.13},{-90,80,-110,110,.12,.11,.09},{90,80,-110,110,.12,.11,.09}}
 end,
 build=function(k)
  local h=k.hash
  k.floor(HX,HZ,0,{.82,.76,.62},10)
  local ground=#k.rows
  -- The court: painted surface, white border, centre line and ring.
  k.box(0,.12,0,38,.12,58,0,{.36,.58,.52},6)
  local white={.96,.96,.94}
  for _,s in ipairs({{-38,0,1,58},{38,0,1,58},{0,-58,38,1},{0,58,38,1},{0,0,38,.8}}) do k.box(s[1],.3,s[2],s[3],.08,s[4],0,white,5) end
  k.disc(0,.3,0,14,40,white,5,12.4)
  k.disc(0,.29,0,12.4,40,{.82,.30,.26},6)
  for _,z in ipairs({-40,40}) do k.box(0,.3,z,22,.08,.8,0,white,5) end
  k.hall(HX,HZ,H,{.86,.84,.80},4,{.92,.92,.90},4)
  -- Tiered stands along both sides: stepped seat rows with a front rail.
  for _,side in ipairs({-1,1}) do
   for t=0,5 do
    local x=side*(HX-6-t*8)
    k.box(x,2+t*4,0,4,2+t*4,HZ-30,0,{.78,.76,.72},4)
    k.box(x-side*1.5,4.3+t*8,0,2.2,.6,HZ-32,0,t%2==0 and {.80,.36,.30} or {.30,.46,.70},6)
   end
   k.box(side*(HX-52),5,0,.5,5,HZ-30,0,{.70,.70,.72},9)
   k.box(side*(HX-52),10,0,1,.5,HZ-30,0,{.70,.70,.72},9)
  end
  -- Windows and wall trim on the far wall; banners between them.
  for i=-2,2 do
   k.box(i*48,62,-HZ+1.4,16,20,.7,0,{.84,.93,1.0},7)
   k.box(i*48,62,-HZ+1.9,18,22,.4,0,{.90,.90,.88},4)
  end
  for i=-3,3,2 do k.place('arena-banner',i*24,-HZ+6,34,0,{y=18,center=true}) end
  k.box(0,8,-HZ+1,HX,8,1,0,{.52,.46,.40},2)
  -- Statues flank the entrance; trophies on plinths.
  for _,x in ipairs({-60,60}) do
   k.box(x,6,-HZ+22,10,6,10,0,{.86,.84,.80},4)
   k.place('arena-statue',x,-HZ+22,30,0,{y=12,center=true})
  end
  k.box(0,5,-HZ+16,8,5,8,0,{.86,.84,.80},4);k.place('arena-trophy',0,-HZ+16,26,0,{y=10,center=true})
  -- Ceiling light panels.
  for x=-60,60,60 do for z=-100,100,50 do k.box(x,H-.6,z,12,.6,12,0,{1.0,.98,.90},7) end end
  return ground
 end,
}
