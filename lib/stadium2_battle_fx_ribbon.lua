-- US fragment79: 8415BBA0 / 8415BD48 / 8415C2E0.
-- Persistent authored ribbon geometry, independent of rendering and battle RNG.
local f=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
local Ribbon={families={[23]=true,[26]=true,[27]=true}}
local colors={
  [23]={{100,200,255,200},{0,100,200,0}},
  [26]={{255,255,255,200},{100,150,150,0}},
  [27]={{255,255,100,200},{150,150,0,0}},
}
function Ribbon.new(id,context)
  context=context or {}
  local palette=assert(colors[id],"unsupported ribbon family")
  local scale=f(context.lifecycleScale or 1)
  local state={kind="rom-ribbon",counter=0,cycles=0,count=0,alpha=0,
    scale=scale,radius=f(scale*40),minimum=f(scale*20),factor=1,
    active=true,vertices={},colors={{unpack(palette[1])},{unpack(palette[2])}}}
  local origin=context.lifecycleAnchor or {0,0,0}
  state.anchor={origin[1],origin[2],origin[3]}
  for i=1,400 do state.vertices[i]={origin[1],origin[2],origin[3],state.radius} end
  return state
end
local function sin(x)return f(math.sin(f(x)))end
local function cos(x)return f(math.cos(f(x)))end
function Ribbon.step(s,anchor)
  if not s.active then return -1 end
  if anchor then s.anchor={anchor[1],anchor[2],anchor[3]} end
  anchor=s.anchor
  s.counter=s.counter+1
  if s.counter>70 then s.active=false;return -1 end
  if s.counter>30 then
    s.counter=18;s.cycles=s.cycles+1
    if s.cycles>=21 then s.active=false;return -1 end
  elseif s.counter<30 then s.alpha=math.min(200,s.alpha+10) end
  s.count=math.min(200,s.count+6)
  if s.counter>18 and s.counter<30 then s.factor=math.max(.25,f(s.factor-.1)) end
  for i=0,s.count-1 do
    local a,b=s.vertices[i*2+1],s.vertices[i*2+2]
    local phase=(s.counter+i)%200
    local wobble
    if s.counter>30 then
      a[4]=math.max(s.minimum,f(a[4]-6))
      wobble=f(sin(phase*251.32741928100586/200)*.1)
    elseif s.counter>25 then
      wobble=f(sin(phase*251.32741928100586/200)+2)
      a[4]=f(a[4]+wobble)
    elseif s.counter>18 then
      a[4]=math.max(s.minimum,f(a[4]-8))
      wobble=f(sin(phase*251.32741928100586/200)*.1)
    else
      wobble=sin(phase*188.4955644607544/200)
      a[4]=f(a[4]+wobble)
    end
    local angle=f(phase*69.11504030227661/200)
    local vertical=f(phase*12.566370964050293/200)
    local x=f(f(sin(angle)*a[4])+anchor[1])
    local y=f(sin(vertical)*(.7*a[4])+anchor[2])
    local z=f(f(cos(angle)*a[4])+anchor[3])
    a[1],a[2],a[3]=x,f(y+wobble),z
    b[1],b[2],b[3]=x,f(2*sin(f(vertical*3))+y+wobble),z
  end
  return 0
end
local function short(v)
  v=v<0 and math.ceil(v) or math.floor(v)
  v=v%65536;return v>=32768 and v-65536 or v
end
function Ribbon.geometry(s)
  local g={kind=s.kind,pos={},idx={},count=s.count,
    colors={{unpack(s.colors[1])},{unpack(s.colors[2])}}}
  for i,v in ipairs(s.vertices) do
    g.pos[i*3-2],g.pos[i*3-1],g.pos[i*3]=short(v[1]),short(math.max(0,v[2])),short(v[3])
  end
  for i=0,s.count-2 do
    local a=i*2+1
    for _,v in ipairs({a,a+2,a+1,a+2,a+3,a+1}) do g.idx[#g.idx+1]=v end
  end
  return g
end
function Ribbon.model(asset,g)
  assert(asset and asset.rgba,"ROM ribbon texture unavailable")
  local p={pos=g.pos,idx=g.idx,nverts=400,nidx=#g.idx,uv={},nrm={},skin={},color={},
    tex=1,texAnim=-1,additive=false,cull=false,lighting=false,
    vertexSemantics="color",alphaMode="blend",
    geometryMode=0x220005,sampler={cms=0,cmt=0},
    material={phase5=true,primitiveColor={1,1,1,200/255},environmentColor={0,0,0,0},
      combiner=asset.combiner}}
  for i=1,4 do
    p.material.primitiveColor[i]=g.colors[1][i]/255
    p.material.environmentColor[i]=g.colors[2][i]/255
  end
  for i=1,400 do
    p.uv[i*2-1]=math.floor((i-1)/2);p.uv[i*2]=(i-1)%2
    p.nrm[i*3-2],p.nrm[i*3-1],p.nrm[i*3]=0,1,0;p.skin[i]=0
    for j=1,4 do p.color[(i-1)*4+j]=255 end
  end
  return {file="stadium2-lifecycle-ribbon",species=0,rootScale=1,staticPose=true,
    bones={{parent=-1,boneId=0,chan=-1,t={0,0,0},r={0,0,0},s={1,1,1}}},
    anims={},auxAnims={},fx={},moveAnim={},contextAnim={},prims={p},
    textures={{w=8,h=16,rgba=asset.rgba,format=3,size=1}}}
end
return Ribbon
