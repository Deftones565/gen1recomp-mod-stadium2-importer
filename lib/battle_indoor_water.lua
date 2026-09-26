-- Indoor water: a bright pool hall. A round turquoise pool fills the middle
-- of a tiled hall; the battlers stand on floating platforms. Columns, tall
-- windows, skylights, benches and potted plants frame it.
local Kit=require('mods.STADIUM2_IMPORTER.lib.scene_kit')

local POOL=96
local HX,HZ,H=150,150,95

return Kit.scene{
 id='indoor_water',
 fog={color={.70,.80,.86},range={260,600}},
 lighting=function(out)
  out.modelTint={1.0,1.0,1.02};out.ambient={.66,.70,.74};out.diffuse={.70,.70,.70}
  out.light={-.35,-1,-.25};out.shadowStrength=.45
  out.bands={{.72,.82,.88},{.72,.82,.88}}
  return out
 end,
 glows=function()
  return {{0,80,0,190,.10,.12,.14},{-120,60,-120,120,.10,.12,.14},{120,60,-120,120,.10,.12,.14}}
 end,
 water={level=-1.6,deep={.10,.42,.60},mid={.14,.52,.68},shallow={.30,.70,.78},calm=.7,
  shore={0,0,POOL},rafts={{0,24,12,8},{0,-24,12,8}}},
 build=function(k)
  local h=k.hash
  -- Tiled floor with the pool cut out: rings from the pool edge outward.
  k.disc(0,0,0,POOL+6,64,{.86,.90,.92},10,POOL)
  k.terrain(-HX,HX,-HZ,HZ,10,function() return 0 end,function(x,y,z)
   if math.sqrt(x*x+z*z)<POOL+10 then return nil end
   return {.84,.88,.90},10
  end)
  -- Pool walls and floor, seen through the water edge.
  for i=0,63 do
   local a,b=i/64*math.pi*2,(i+1)/64*math.pi*2
   k.quad({math.cos(a)*POOL,0,math.sin(a)*POOL},{math.cos(b)*POOL,0,math.sin(b)*POOL},
    {math.cos(b)*POOL,-12,math.sin(b)*POOL},{math.cos(a)*POOL,-12,math.sin(a)*POOL},{-math.cos(a),0,-math.sin(a)},{.42,.72,.80},10)
  end
  local ground=#k.rows
  k.hall(HX,HZ,H,{.80,.86,.90},4,{.90,.92,.94},4)
  -- Blue tile wainscot and trim.
  for _,s in ipairs({{0,-HZ+1,HX,1},{0,HZ-1,HX,1}}) do k.box(s[1],10,s[2],s[3],10,s[4],0,{.40,.64,.78},10) end
  for _,s in ipairs({{-HX+1,0,1,HZ},{HX-1,0,1,HZ}}) do k.box(s[1],10,s[2],s[3],10,s[4],0,{.40,.64,.78},10) end
  -- Tall windows on the far walls.
  for i=-2,2 do
   k.box(i*50,52,-HZ+1.5,15,26,.8,0,{.78,.90,.98},7)
   k.box(i*50,52,-HZ+2.2,17,28,.4,0,{.95,.96,.97},4)
   k.box(-HX+1.5,52,i*50,.8,26,15,0,{.78,.90,.98},7)
   k.box(-HX+2.2,52,i*50,.4,28,17,0,{.95,.96,.97},4)
  end
  -- Skylights.
  for _,p in ipairs({{-60,-60},{60,-60},{-60,60},{60,60}}) do k.box(p[1],H-.5,p[2],24,.6,24,0,{.84,.93,1.0},7) end
  -- Columns round the pool.
  for i=0,7 do
   local a=i/8*math.pi*2+math.pi/8
   local x,z=math.cos(a)*(POOL+26),math.sin(a)*(POOL+26)
   k.column(x,z,0,H,5,4.5,14,{.94,.95,.96},4)
   k.box(x,H-3,z,7,3,7,0,{.90,.92,.94},4);k.box(x,1.5,z,7,1.5,7,0,{.90,.92,.94},4)
  end
  -- Floating platforms for the battlers.
  for _,z in ipairs({24,-24}) do
   k.box(0,-1.2,z,12,1.2,8,0,{.94,.95,.96},4)
   k.box(0,.05,z,10,.1,6,0,{.30,.58,.80},6)
  end
  for i,p in ipairs({{-128,-128},{128,-128},{-128,128},{128,128},{-128,0},{0,-128}}) do
   k.place('potted-plant',p[1],p[2],44,i,{tone=nil})
  end
  for _,p in ipairs({{-60,-138,0},{60,-138,0},{-138,-60,math.pi/2},{-138,60,math.pi/2}}) do
   k.place('bench-cushion',p[1],p[2],50,p[3])
  end
  return ground
 end,
}
