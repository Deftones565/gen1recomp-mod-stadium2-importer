-- Ship: the deck of a tall ship at sea. Planked deck, rails, two masts with
-- furled rigging, cannons, crates, barrels and a lifeboat; open painted sea
-- all around with wake along the hull. Kenney Pirate Kit meshes (CC0).
local Kit=require('mods.STADIUM2_IMPORTER.lib.scene_kit')

local HW,HL=76,150   -- deck half width (x) and half length (z): wider than the camera orbit
local SEA=-26        -- waterline below the deck

return Kit.scene{
 id='ship',outdoor=true,visitors=true,
 sky={haze={.66,.77,.80}},
 fog={color={.66,.77,.80},night={.10,.15,.26},range={300,1500}},
 moon={-.87,.14,-.47},
 lighting=function(out,daytime)
  if daytime=='NITE' then out.modelTint={.27,.33,.50} end
  return out
 end,
 glows=function(env)
  if env.daytime~='NITE' then return {} end
  return {{-HW+4,16,-60,70,.50,.34,.14},{HW-4,16,40,70,.50,.34,.14},{0,24,HL-20,80,.50,.34,.14}}
 end,
 water={level=SEA,x=0,z=0,rafts={{0,0,HW+4,HL+6},{9999,9999,0,0}}},
 build=function(k)
  local h=k.hash
  -- Deck planks along the ship.
  for x=-HW,HW-4,4 do
   local shade=.9+h(x+500)*.14
   k.box(x+2,-.5,0,1.95,.5,HL,0,{.62*shade,.48*shade,.34*shade},2,true)
  end
  local ground=#k.rows
  -- Hull: dark wood sides with a painted band, and a pointed bow.
  for _,side in ipairs({-1,1}) do
   k.box(side*(HW+1.5),(SEA-4)/2,0,1.5,(-SEA+4)/2+2,HL,0,{.36,.26,.18},2)
   k.box(side*(HW+3.1),-4,0,.2,2.2,HL,0,{.86,.84,.76},6)
   k.box(side*(HW+3.1),SEA+6,0,.2,3,HL,0,{.62,.24,.20},6)
  end
  for i=0,7 do
   local f0,f1=i/8,(i+1)/8
   local w0,w1=HW*(1-f0^1.6),HW*(1-f1^1.6)
   local z0,z1=-HL-f0*40,-HL-f1*40
   for _,side in ipairs({-1,1}) do
    k.quad({side*w0,2,z0},{side*w1,2,z1},{side*w1,SEA-4,z1},{side*w0,SEA-4,z0},{side,0,-.4},{.36,.26,.18},2)
   end
   k.quad({-w0,-.1,z0},{w0,-.1,z0},{w1,-.1,z1},{-w1,-.1,z1},{0,1,0},{.60,.46,.33},2)
  end
  k.box(0,-.5,HL+5,HW+3,.5,5,0,{.58,.44,.31},2)
  k.box(0,(SEA-4)/2,HL+10,HW+3,(-SEA+4)/2+2,1.5,0,{.36,.26,.18},2)
  -- Stern cabin with lit windows.
  k.box(0,11,HL-14,HW-4,11,12,0,{.52,.38,.26},2)
  k.box(0,23,HL-14,HW-2,1.2,14,0,{.46,.33,.22},2)
  for _,x in ipairs({-18,-6,6,18}) do k.box(x,12,HL-26.3,3,4,.4,0,{.96,.84,.56},7) end
  -- Rails along both sides.
  for _,side in ipairs({-1,1}) do
   k.box(side*(HW-1),7.5,0,1,.8,HL,0,{.50,.37,.26},2)
   k.box(side*(HW-1),4,0,.5,.4,HL,0,{.50,.37,.26},2)
   for z=-HL+4,HL-4,12 do k.box(side*(HW-1),3.5,z,.8,3.5,.8,0,{.46,.34,.24},2) end
  end
  -- Masts well clear of the battle.
  k.place('mast',0,-82,14,0,{center=true})
  k.place('mast',0,86,12,0,{center=true})
  k.place('flag-high',0,-82,9,0,{y=100,center=true})
  -- Deck cargo and cannons along the rails.
  for i,p in ipairs({{-HW+10,-70,math.pi/2},{HW-10,-70,-math.pi/2},{-HW+10,-20,math.pi/2},{HW-10,70,-math.pi/2}}) do
   k.place('cannon',p[1],p[2],8,p[3],{center=true})
  end
  k.place('crate',-40,-110,9,.2,{center=true});k.place('crate-bottles',-28,-116,9,.1,{center=true})
  k.place('barrel',36,-104,7,0,{center=true});k.place('barrel',44,-112,7,.5,{center=true})
  k.place('crate',50,96,9,.4,{center=true});k.place('barrel',-52,100,7,0,{center=true})
  k.place('boat-row-large',HW-20,24,7,0,{y=1,center=true})
  -- The sea: distant islets and a sail on the horizon.
  for i,s in ipairs({{-520,-620,40,60},{-800,-200,55,70},{-260,-900,30,50}}) do
   k.pillar(s[1],s[2],s[3],s[4],i*2.1,{.58,.56,.50},{.36,.52,.30},1,SEA-3,.35)
  end
  k.place('boat-sail',-420,-480,12,.8,{y=SEA-.5})
  return ground
 end,
}
