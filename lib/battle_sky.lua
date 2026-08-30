local okPalettes, Palettes = pcall(require,"src.world.gen2.Palettes")
if not okPalettes then Palettes=nil end

local Sky = {}
local gradientMesh, gradientCount

local PRESETS = {
  MORN={bands={{.18,.19,.32},{.34,.30,.43},{.62,.46,.48},{.90,.67,.48},{.98,.79,.58}},
    ambient={.58,.52,.55},diffuse={.82,.67,.57},light={-.45,-.78,-.43},
    modelTint={1,.88,.82},orb={1,.72,.48,.38}},
  DAY={bands={{.10,.24,.46},{.16,.35,.61},{.27,.51,.76},{.49,.69,.84},{.72,.82,.88}},
    ambient={.57,.59,.62},diffuse={.78,.78,.73},light={-.42,-.82,-.39},
    modelTint={1,1,1},orb={1,.88,.58,.33}},
  NITE={bands={{.018,.025,.075},{.035,.055,.13},{.065,.095,.19},{.11,.14,.23},{.17,.19,.27}},
    ambient={.34,.38,.51},diffuse={.50,.55,.67},light={.35,-.82,-.45},
    modelTint={.58,.65,.86},orb={.78,.86,1,.30}},
  DARK={bands={{.008,.009,.018},{.012,.014,.025},{.018,.021,.032},{.025,.028,.039},{.032,.035,.046}},
    ambient={.18,.19,.24},diffuse={.34,.35,.40},light={-.4,-.8,-.45},
    modelTint={.32,.34,.45},orb={.3,.35,.5,.12}},
}

local INDOOR = {
  bands={{.075,.073,.082},{.105,.102,.112},{.14,.135,.145},{.18,.173,.18},{.22,.21,.21}},
  ambient={.52,.50,.50},diffuse={.66,.63,.59},light={-.45,-.82,-.35},
  modelTint={.86,.83,.82},indoor=true,
}
local CAVE = {
  bands={{.025,.027,.035},{.038,.039,.047},{.052,.051,.055},{.069,.064,.061},{.087,.077,.068}},
  ambient={.35,.34,.35},diffuse={.51,.46,.41},light={-.38,-.84,-.39},
  modelTint={.62,.58,.56},indoor=true,
}

local function copy(source)
  local out = {}
  for k,v in pairs(source) do out[k]=v end
  return out
end

local function mix(a,b,t)
  local out={}
  for i=1,math.max(#a,#b) do out[i]=(a[i] or 0)*(1-t)+(b[i] or 0)*t end
  return out
end

local function mixPreset(a,b,t)
  local out={bands={}}
  for i=1,#a.bands do out.bands[i]=mix(a.bands[i],b.bands[i],t) end
  out.ambient=mix(a.ambient,b.ambient,t)
  out.diffuse=mix(a.diffuse,b.diffuse,t)
  out.modelTint=mix(a.modelTint,b.modelTint,t)
  out.orb=mix(a.orb,b.orb,t)
  return out
end

-- Smooth, cyclic outdoor lighting.  Gold's palette category still labels the
-- scene, but the battle sky and shadows no longer jump at category borders.
local function outdoorAt(hour)
  hour=(tonumber(hour) or 12)%24
  local keys={
    {0,PRESETS.NITE},{5,PRESETS.NITE},{7,PRESETS.MORN},
    {10,PRESETS.DAY},{17,PRESETS.DAY},{19,PRESETS.MORN},
    {21,PRESETS.NITE},{24,PRESETS.NITE},
  }
  local left,right=keys[1],keys[#keys]
  for i=1,#keys-1 do
    if hour>=keys[i][1] and hour<=keys[i+1][1] then
      left,right=keys[i],keys[i+1];break
    end
  end
  local t=(hour-left[1])/math.max(.001,right[1]-left[1])
  t=t*t*(3-2*t)
  local out=mixPreset(left[2],right[2],t)
  local day=hour>=6 and hour<19
  local phase
  if day then phase=(hour-6)/13 else phase=((hour+5)%24)/11 end
  local elevation=math.max(.12,math.sin(math.pi*phase))
  local horizontal=math.cos(math.pi*phase)
  out.light={-.72*horizontal,-elevation,-.42}
  out.shadowStrength=day and (.42+.58*elevation) or (.24+.20*elevation)
  out.orbKind=day and "sun" or "moon"
  out.orbX=.12+.76*phase
  out.orbY=.20-.13*elevation
  local azimuth=math.rad(-137.7)+(phase-.5)*math.rad(90)
  local radius=150
  out.orbWorld={
    math.cos(azimuth)*radius,
    38+62*math.sin(math.pi*phase),
    math.sin(azimuth)*radius,
  }
  return out
end

function Sky.resolve(game)
  local world = game and game.world
  local def = world and world.map and world.map.def or nil
  local env = def and def.environment or "TOWN"
  local hour = world and world.clockHour or nil
  if world and type(world.hour)=="function" then
    local ok,value=pcall(world.hour,world)
    if ok then hour=value end
  end
  local minute=0
  if world and type(world.minute)=="function" then
    local ok,value=pcall(world.minute,world)
    if ok then minute=tonumber(value) or 0 end
  end
  local clock=(tonumber(hour) or 12)+minute/60
  local daytime=world and world.daytime
  if not daytime and Palettes and Palettes.daytimeFor then
    daytime=Palettes.daytimeFor(def,hour,world and world.flashUsed)
  end
  if not daytime then
    local h=(tonumber(hour) or 12)%24
    daytime=(h>=6 and h<10) and "MORN" or (h>=10 and h<19) and "DAY" or "NITE"
  end
  local outdoor = env == "TOWN" or env == "ROUTE"
  local preset
  if outdoor then preset = outdoorAt(clock)
  elseif env == "CAVE" or env == "DUNGEON" or env == "ENVIRONMENT_5" then
    preset = CAVE
  else preset = INDOOR end
  local result = copy(preset)
  result.environment, result.daytime, result.outdoor = env, daytime, outdoor
  result.hour=clock
  return result
end

local function projectOrb(frame,width,height,point)
  local vp=frame and frame.vp
  if not (vp and point) then return nil end
  local x,y,z=point[1],point[2],point[3]
  local cx=vp[1]*x+vp[2]*y+vp[3]*z+vp[4]
  local cy=vp[5]*x+vp[6]*y+vp[7]*z+vp[8]
  local cw=vp[13]*x+vp[14]*y+vp[15]*z+vp[16]
  if cw<=.001 then return nil end
  return (cx/cw*.5+.5)*width,(cy/cw*.5+.5)*height
end

local function drawSun(g,x,y,r,c,a)
  g.setColor(c[1],c[2],c[3],a*.08)
  g.circle("fill",x,y,r*2.25,64)
  g.setColor(c[1],c[2],c[3],a*.14)
  g.circle("fill",x,y,r*1.65,64)
  g.setColor(c[1],c[2],c[3],a*.24)
  g.circle("fill",x,y,r*1.22,64)
  g.setColor(1,.90,.58,.94)
  g.circle("fill",x,y,r*.96,64)
  g.setColor(1,.98,.82,.90)
  g.circle("fill",x-r*.10,y-r*.10,r*.58,64)
  g.setColor(1,1,.94,.52)
  g.circle("fill",x-r*.18,y-r*.18,r*.16,32)
end

local function drawMoon(g,x,y,r,c,a)
  g.setColor(c[1],c[2],c[3],a*.10)
  g.circle("fill",x,y,r*2.7,64)
  g.setColor(c[1],c[2],c[3],a*.18)
  g.circle("fill",x,y,r*1.9,64)
  g.setColor(.68,.76,.90,.85)
  g.circle("fill",x,y,r*1.04,64)
  g.setColor(.93,.96,1,.98)
  g.circle("fill",x,y,r,64)
  g.setColor(.73,.79,.88,.25)
  g.circle("fill",x-r*.28,y-r*.18,r*.25,40)
  g.circle("fill",x+r*.29,y+r*.12,r*.18,40)
  g.circle("fill",x-r*.05,y+r*.36,r*.13,32)
  g.circle("fill",x+r*.18,y-r*.38,r*.10,32)
  g.setColor(1,1,1,.28)
  g.circle("fill",x-r*.18,y-r*.28,r*.20,40)
end

function Sky.paint(g, width, height, env, frame)
  local bands = env.bands
  g.setShader()
  if g.setDepthMode then g.setDepthMode("always",false) end
  local vertices={}
  local last=math.max(1,#bands-1)
  for i,c in ipairs(bands) do
    local y=(i-1)/last*height
    vertices[#vertices+1]={0,y,0,0,c[1],c[2],c[3],1}
    vertices[#vertices+1]={width,y,1,0,c[1],c[2],c[3],1}
  end
  if g.newMesh and g.draw then
    if not gradientMesh or gradientCount~=#vertices then
      if gradientMesh and gradientMesh.release then pcall(gradientMesh.release,gradientMesh) end
      gradientMesh=g.newMesh(vertices,"strip","stream")
      gradientCount=#vertices
    else
      gradientMesh:setVertices(vertices)
    end
    g.setColor(1,1,1,1)
    g.draw(gradientMesh)
  else
    for y=0,height-1 do
      local p=(height>1 and y/(height-1) or 0)*last
      local i=math.min(#bands-1,math.floor(p)+1)
      local t=p-math.floor(p)
      local a,b=bands[i],bands[math.min(#bands,i+1)]
      g.setColor(a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t,1)
      g.rectangle("fill",0,y,width,1)
    end
  end
  if env.outdoor and env.orb then
    local night=env.orbKind=="moon" or env.daytime=="NITE"
    local x,y=projectOrb(frame,width,height,env.orbWorld)
    if not x then
      x=width*(env.orbX or (night and .24 or .78))
      y=height*(env.orbY or .19)
    end
    local r=math.max(10,height*.036)
    if not night then r=r*.68 end
    local a=math.max(.2,math.min(1,env.orb[4] or .3))
    if night then drawMoon(g,x,y,r,env.orb,a)
    else drawSun(g,x,y,r,env.orb,a) end
  end
  g.setColor(1,1,1,1)
end

function Sky.draw(g, width, height, env, frame)
  local bands=env and env.bands or nil
  local c=bands and bands[1] or {0,0,0}
  g.setShader()
  if g.setDepthMode then g.setDepthMode("always",false) end
  g.clear(c[1] or 0,c[2] or 0,c[3] or 0,1,true,true)
  return Sky.paint(g,width,height,env,frame)
end

return Sky
