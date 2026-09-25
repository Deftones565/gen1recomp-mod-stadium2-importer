-- US fragment79 family 7 / BattleAnim_StartEffect34TerrainGrid (Surf).
--
-- Family 7 still contains GLOBAL_ASM entries in the decomp, but the importer
-- already caches the user's exact Fragment 79 image.  Execute the unresolved
-- simulation kernel from those ROM bytes in the isolated MIPS VM and decode
-- the draw builder's proven vertex/RDP contract directly.  No procedural wave
-- substitute is used here.
local ffi=require("ffi")
local Mips=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_mips")
local f=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float')

local Terrain={families={[7]=true}}

local VRAM_BASE=0x84100000
local ROM_BASE=0x36F890
local ROM_END=0x419480
local INIT=0x8415A9E4
local ALPHA_WRITE=0x8415AC64
local UPDATE=0x8415AD58
local PRESENTATION_SIGNAL=0x841094EC
local SINF=0x80073F70
local STATE_POINTER=0x84187330
local SCROLL0=0x841A4D62
local SCROLL1=0x841A4D64
local ROWS,COLS=16,16
local VERTEX_BASE=0x1010
local VERTEX_STRIDE=0x14

local scalar=ffi.new("union { float f; uint32_t u; }")
local function bitsFloat(v) scalar.u=v%4294967296;return tonumber(scalar.f) end
local function signed16(v)return v>=0x8000 and v-0x10000 or v end
local function trunc(v)return v<0 and math.ceil(v) or math.floor(v)end
local function byte(v)return math.max(0,math.min(255,trunc(v)))end

local PRIMARY_SAMPLER={cms=0,cmt=0,masks=5,maskt=5,shifts=1,shiftt=1}
local SECONDARY_SAMPLER={cms=0,cmt=0,masks=5,maskt=5,shifts=0,shiftt=0}

-- FC276A60 35D09F47 from D_84187338, decoded as gDPSetCombineLERP.
local COMBINER={cycles=2,
  color0={2,3,14,1},alpha0={6,1,5,7},
  color1={3,5,0,5},alpha1={6,0,4,7}}

local function nativeAlpha(age,duration)
  local value=255
  if age<20 then
    value=trunc(age*255/20)
  elseif duration-20<age then
    value=trunc((duration-age)*255/20)
  end
  -- 8415B30C passes the result through `andi a0, v0, 0xFF`.
  return value%256
end

local function refresh(s)
  local vm,base=s.vm,s.base
  s.counter=signed16(vm:read(base+4,2))
  s.duration=signed16(vm:read(base+8,2))
  s.scroll0=signed16(vm:read(SCROLL0,2))
  s.scroll1=signed16(vm:read(SCROLL1,2))
  s.alpha=nativeAlpha(s.counter,s.duration)
end

local function fragmentImage(rom)
  if type(rom)~="string" then return nil end
  -- FxRom.catalog normally carries the complete Stadium 2 ROM, while tests
  -- and research tools may supply the already-isolated 0x36F890..0x419480
  -- fragment.  The MIPS VM is mapped at fragment VRAM 0x84100000, so a full
  -- ROM must be normalized before any native instruction is fetched.
  if #rom>=ROM_END then return rom:sub(ROM_BASE+1,ROM_END) end
  if #rom>=ROM_END-ROM_BASE then return rom:sub(1,ROM_END-ROM_BASE) end
  return nil
end

function Terrain.new(side,overlay,camera)
  overlay=fragmentImage(overlay)
  if not overlay or #overlay<(0x8415ADDC-VRAM_BASE+4) then
    return nil,"Fragment 79 ROM image is unavailable for native terrain-grid execution"
  end
  side=tonumber(side) or -1
  side=side<0 and -1 or 1
  local hookState={signal=0,allocation=0x85200000,allocations={}}
  local hooks={}
  hooks[PRESENTATION_SIGNAL]=function(vm) vm.r[2]=hookState.signal end
  hooks[SINF]=function(vm)
    vm.f[0]=Mips.floatWord(math.sin(bitsFloat(vm.f[12])))
  end
  hooks[0x8007E9C0]=function(vm)vm.f[0]=Mips.floatWord(math.cos(bitsFloat(vm.f[12])))end
  hooks[0x80070B7C]=function(vm)vm.f[0]=Mips.floatWord(math.abs(bitsFloat(vm.f[12])))end
  hooks[0x80070C14]=function(vm)
    local x,y,z=vm:float(vm.r[4]),vm:float(vm.r[5]),vm:float(vm.r[6])
    local length=f(math.sqrt(f(f(f(x*x)+f(y*y))+f(z*z))))
    if length>0 then x,y,z=f(x/length),f(y/length),f(z/length)end
    vm:putFloat(vm.r[4],x);vm:putFloat(vm.r[5],y);vm:putFloat(vm.r[6],z)
    vm.f[0]=Mips.floatWord(length)
  end
  hooks[0x80070BA4]=function(vm)
    local sp=vm.r[29]
    local a={bitsFloat(vm.f[12]),bitsFloat(vm.f[14]),bitsFloat(vm.r[6])}
    local b={bitsFloat(vm.r[7]),vm:float(sp+16),vm:float(sp+20)}
    for k=1,3 do local j,k2=k%3+1,(k+1)%3+1
      vm:putFloat(vm:read(sp+20+k*4,4),f(f(a[j]*b[k2])-f(a[k2]*b[j])))
    end
  end
  -- 84159FA8 also computes a slope angle which Surf's draw never consumes.
  hooks[0x8000B3B0]=function(vm)vm.r[2]=0 end
  hooks[0x80006DEC]=function(vm)
    vm.r[2]=hookState.allocation
    hookState.allocations[#hookState.allocations+1]={address=vm.r[2],size=vm.r[4]}
    hookState.allocation=hookState.allocation+vm.r[4]
  end
  hooks[0x80073EC0]=function(vm)
    for j=0,15 do
      local value=0
      if j==0 then value=bitsFloat(vm.r[5]) elseif j==5 then value=bitsFloat(vm.r[6])
      elseif j==10 then value=bitsFloat(vm.r[7]) elseif j==15 then value=1 end
      local fixed=trunc(value*65536)%2^32
      vm:write(vm.r[4]+j*2,math.floor(fixed/65536),2)
      vm:write(vm.r[4]+32+j*2,fixed%65536,2)
    end
  end
  local vm=Mips.new({{base=VRAM_BASE,bytes=overlay}},hooks)
  local ok,err=pcall(vm.call,vm,INIT,{side,0,0x4650})
  if not ok then return nil,"native terrain-grid init failed: "..tostring(err) end
  local base=vm:read(STATE_POINTER,4)
  if base<0x8419F070 or base>=0x841B0000 then
    return nil,("native terrain-grid state pointer is invalid: %08X"):format(base)
  end
  local out={family=7,side=side,vm=vm,base=base,hookState=hookState,
    active=true,native=true,error=nil,counter=0,duration=0,scroll0=0,scroll1=0,alpha=0,camera=camera}
  refresh(out)
  Terrain.geometry(out)
  if out.error then return nil,out.error end
  return out
end

-- 8415AD58 is run instruction-for-instruction.  Its only external input is
-- BattleAnim's presentation-complete signal; 8415A364 and all of its state
-- integration stay in the ROM VM.  The libc sinf call is isolated to math.sin
-- and rounded back to an N64 single before native execution resumes.
function Terrain.step(s,signal,camera)
  if not s or not s.active then return -1 end
  s.hookState.signal=signal==1 and 1 or 0
  local ok,err=pcall(s.vm.call,s.vm,UPDATE,{})
  if not ok then
    s.active=false;s.error=tostring(err);return nil,s.error
  end
  refresh(s)
  if err==-1 or err==0xFFFFFFFF then s.active=false;return -1 end
  s.camera=camera or s.camera
  s.cachedGeometry=nil
  Terrain.geometry(s)
  if s.error then s.active=false;return nil,s.error end
  return 0
end

local function vertexAddress(s,row,col)
  return s.base+VERTEX_BASE+(row*COLS+col)*VERTEX_STRIDE
end

function Terrain.geometry(s)
  if not s or not s.vm then return nil end
  if s.cachedGeometry then return s.cachedGeometry end
  refresh(s)
  local vm=s.vm
  local g={kind="rom-terrain-grid",family=7,pos={},idx={},nrm={},uv={},color={},
    rows=ROWS,columns=COLS,native=true,alpha=s.alpha,
    scroll={s.scroll0,s.scroll1},counter=s.counter,duration=s.duration,
    textureSymbols={31,32}}

  -- Native copies the previous draw's alpha before writing the new one.
  -- Capture once per simulation tick, so repeated host draws cannot advance it.

  -- 8415ADE0 allocates 0x1000 bytes and copies the 16x16 state grid into
  -- 256 Vtx records. S/T are (row|column * 0x800) / 3 with integer division.
  -- RGB bytes are not consumed by this combiner; alpha is read back from the
  -- exact +0x10 field written by 8415AC64.
  for row=0,ROWS-1 do
    local rawS=trunc(row*0x800/3)
    for col=0,COLS-1 do
      local at=vertexAddress(s,row,col)
      g.pos[#g.pos+1]=signed16(trunc(vm:float(at))%65536)
      g.pos[#g.pos+1]=signed16(trunc(vm:float(at+4))%65536)
      g.pos[#g.pos+1]=signed16(trunc(vm:float(at+8))%65536)
      g.nrm[#g.nrm+1]=0;g.nrm[#g.nrm+1]=1;g.nrm[#g.nrm+1]=0
      g.uv[#g.uv+1]=rawS/1024
      g.uv[#g.uv+1]=trunc(col*0x800/3)/1024
      local alpha=signed16(vm:read(at+16,2))%256
      g.color[#g.color+1]=255;g.color[#g.color+1]=255;g.color[#g.color+1]=255
      g.color[#g.color+1]=byte(alpha)
    end
  end

  -- 8415B58C..8415B628 loads four adjacent Vtx and emits
  -- G_TRI2 06000402 / 00040602: (0,2,1) + (2,3,1).
  for row=0,14 do for col=0,14 do
    local a=row*COLS+col+1
    local list={a,a+COLS,a+1,a+COLS,a+COLS+1,a+1}
    for _,index in ipairs(list) do g.idx[#g.idx+1]=index end
  end end
  local ok,err=pcall(vm.call,vm,ALPHA_WRITE,{s.alpha})
  if not ok then s.error="native terrain-grid alpha write failed: "..tostring(err);return nil end
  g.cover={pos={},uv={},color={},idx={1,3,2,3,4,2},visible=false}
  local camera=s.camera
  if camera then
    local function finite(n)return type(n)=='number' and n==n and math.abs(n)<math.huge end
    for _,name in ipairs({'eye','focus'}) do
      if type(camera[name])~='table' then s.error='invalid terrain camera '..name;return nil end
      for k=1,3 do if not finite(camera[name][k]) then s.error='invalid terrain camera '..name;return nil end end
    end
    if not finite(camera.fov) or camera.fov<=0 or camera.fov>=180 or not finite(camera.aspect)
      or camera.aspect<=0 or not finite(camera.near) or camera.near<0 then s.error='invalid terrain camera projection';return nil end
    local at=0x85100000
    vm:write(0x80094908,at,4)
    vm:putVector(at+0xA8,camera.eye);vm:putVector(at+0xB4,camera.focus)
    vm:putVector(at+0xC0,camera.up or {0,1,0})
    vm:putFloat(at+0x2C,camera.fov);vm:putFloat(at+0x30,camera.aspect);vm:putFloat(at+0x34,camera.near)
    s.hookState.allocation=0x85200000;s.hookState.allocations={}
    local drawn,drawError=pcall(vm.call,vm,0x8415ADE0,{0x85400000},1000000)
    if not drawn then s.error='native terrain-grid draw failed: '..tostring(drawError);return nil end
    local allocations=s.hookState.allocations
    if #allocations==3 then
      g.cover.visible=true
      local vertices=allocations[2].address
      -- Native draw scales the camera quad by a fixed-point .1 matrix.
      local matrix=allocations[3].address
      local scale=vm:read(matrix,2)+vm:read(matrix+32,2)/65536
      for i=0,3 do
        for k=0,2 do g.cover.pos[#g.cover.pos+1]=signed16(vm:read(vertices+i*16+k*2,2))*scale end
        for k=0,1 do g.cover.uv[#g.cover.uv+1]=signed16(vm:read(vertices+i*16+8+k*2,2))/1024 end
      end
    end
  end
  if not g.cover.visible then for i=1,12 do g.cover.pos[i]=0 end;for i=1,8 do g.cover.uv[i]=0 end end
  for i=1,4 do for _,c in ipairs({255,255,255,g.cover.visible and 255 or 0}) do g.cover.color[#g.cover.color+1]=c end end
  s.cachedGeometry=g
  return g
end

local function textureSet(g)
  return {1,2,phase5=true,wrap="repeat",formats={4,4},
    samplers={PRIMARY_SAMPLER,SECONDARY_SAMPLER},
    scroll={{-((g.scroll[1] or 0)%4096)/128,0},
      {-((g.scroll[2] or 0)%4096)/128,0}}}
end

function Terrain.model(g,textures)
  assert(type(textures)=="table" and textures[31] and textures[31].rgba,
    "terrain-grid ROM texture export 31 unavailable")
  assert(textures[32] and textures[32].rgba,
    "terrain-grid ROM texture export 32 unavailable")
  local p={pos=g.pos,nrm=g.nrm,idx=g.idx,nverts=ROWS*COLS,nidx=#g.idx,
    uv=g.uv,skin={},color=g.color,tex=1,texAnim=-1,additive=false,cull=false,
    lighting=false,vertexSemantics="color",alphaMode="blend",
    geometryMode=0x200005,sampler=PRIMARY_SAMPLER,
    material={phase5=true,
      -- 8415B314: FA00007D AFFFFFFF
      primitiveColor={175/255,1,1,1},primitiveLodFraction=0x7D/255,
      -- 8415B338: FB000000 0028AF37
      environmentColor={0,40/255,175/255,55/255},combiner=COMBINER},
    battleFxTextures=textureSet(g)}
  for i=1,ROWS*COLS do p.skin[i]=0 end
  return {file="stadium2-lifecycle-terrain-grid",species=0,rootScale=1,
    staticPose=true,
    bones={{parent=-1,boneId=0,chan=-1,t={0,0,0},r={0,0,0},s={1,1,1}}},
    anims={},auxAnims={},fx={},moveAnim={},contextAnim={},prims={p,(function()
      local cover=g.cover
      -- 841873B0 uses primitive color only; its uploaded textures 33/34
      -- do not participate in either combiner cycle.
      return {pos=cover.pos,uv=cover.uv,idx=cover.idx,nverts=4,nidx=6,
        nrm={0,1,0,0,1,0,0,1,0,0,1,0},skin={0,0,0,0},color=cover.color,
        tex=-1,texAnim=-1,lighting=false,vertexSemantics='color',alphaMode='blend',cull=false,
        geometryMode=0x200004,battleFxNoDepth=true,
        material={phase5=true,primitiveColor={0,150/255,200/255,130/255},environmentColor={0,0,0,0},
          primitiveLodFraction=128/255,combiner={cycles=2,color0={15,15,31,3},alpha0={7,7,7,3},
          color1={15,15,31,0},alpha1={7,7,7,0}}}}
    end)()},
    textures={textures[31],textures[32]}}
end

function Terrain.updateModel(model,g)
  local p=model and model.prims and model.prims[1]
  if not p then return false end
  p.pos,p.nrm,p.uv,p.idx,p.nidx,p.color=g.pos,g.nrm,g.uv,g.idx,#g.idx,g.color
  p.battleFxTextures=textureSet(g)
  local cover=model.prims[2]
  cover.pos,cover.uv,cover.color=g.cover.pos,g.cover.uv,g.cover.color
  return true
end

function Terrain.snapshot(s)
  if not s then return nil end
  return {kind="rom-terrain-grid-state",family=7,side=s.side,
    counter=s.counter,duration=s.duration,active=s.active,alpha=s.alpha,
    scroll={s.scroll0,s.scroll1},native=s.native==true,error=s.error,drawReady=not s.error,
    cameraCover=s.cachedGeometry and s.cachedGeometry.cover.visible or false}
end

return Terrain
