-- US fragment79 family 7 / BattleAnim_StartEffect34TerrainGrid (Surf).
--
-- The water's simulation and draw builder are the Lua port in
-- stadium2_battle_fx_terrain_grid_native.lua, run on Stadium's own memory
-- layout; this module steps it at 30 Hz and reads the grid and the camera
-- cover back into renderer geometry. No procedural wave substitute is used.
local Native=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_terrain_grid_native")
local Memory=require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")

local Terrain={families={[7]=true}}

local VRAM_BASE=0x84100000
local ROM_BASE=0x36F890
local ROM_END=0x419480
local SCROLL0=0x841A4D62
local SCROLL1=0x841A4D64
local ROWS,COLS=16,16
local VERTEX_BASE=0x1010
local VERTEX_STRIDE=0x14

local function signed16(v)return v>=0x8000 and v-0x10000 or v end
local function trunc(v)return v<0 and math.ceil(v) or math.floor(v)end
local function byte(v)return math.max(0,math.min(255,trunc(v)))end

local PRIMARY_SAMPLER={cms=0,cmt=0,masks=5,maskt=5,shifts=1,shiftt=1}
local SECONDARY_SAMPLER={cms=0,cmt=0,masks=5,maskt=5,shifts=0,shiftt=0}

-- FC276A60 35D09F47 from D_84187338, decoded as gDPSetCombineLERP.
local COMBINER={cycles=2,
  color0={2,3,14,1},alpha0={6,1,5,7},
  color1={3,5,0,5},alpha1={6,0,4,7}}

local function refresh(s)
  local vm,base=s.mem,s.base
  s.counter=signed16(vm:read(base+4,2))
  s.duration=signed16(vm:read(base+8,2))
  s.scroll0=signed16(vm:read(SCROLL0,2))
  s.scroll1=signed16(vm:read(SCROLL1,2))
  s.alpha=Native.alpha(vm)
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

-- mainKernel: main code at 0x80000400 (ROM 0x1000..), for the arctangent
-- table 84159FA8's slope angle reads; without it that angle (which the
-- draw never uses) comes out 0.
function Terrain.new(side,overlay,camera,mainKernel)
  overlay=fragmentImage(overlay)
  if not overlay or #overlay<(0x8415ADDC-VRAM_BASE+4) then
    return nil,"Fragment 79 ROM image is unavailable for the terrain grid"
  end
  side=tonumber(side) or -1
  side=side<0 and -1 or 1
  local images={{base=VRAM_BASE,bytes=overlay}}
  if type(mainKernel)=="string" then images[#images+1]={base=0x80000400,bytes=mainKernel} end
  local mem=Memory.new(images)
  local hookState={signal=0,allocation=0x85200000,allocations={}}
  local callbacks={
    signal=function()return hookState.signal end,
    alloc=function(n)
      local at=hookState.allocation
      hookState.allocations[#hookState.allocations+1]={address=at,size=n}
      hookState.allocation=at+n
      return at
    end,
  }
  local ok,err=pcall(Native.init,mem,callbacks,side,0)
  if not ok then return nil,"terrain-grid init failed: "..tostring(err) end
  local base=Native.state(mem)
  if base<0x8419F070 or base>=0x841B0000 then
    return nil,("terrain-grid state pointer is invalid: %08X"):format(base)
  end
  local out={family=7,side=side,mem=mem,callbacks=callbacks,base=base,hookState=hookState,
    active=true,native=true,error=nil,counter=0,duration=0,scroll0=0,scroll1=0,alpha=0,camera=camera}
  refresh(out)
  Terrain.geometry(out)
  if out.error then return nil,out.error end
  return out
end

-- 8415AD58 (the Lua port). Its only external input is BattleAnim's
-- presentation-complete signal.
function Terrain.step(s,signal,camera)
  if not s or not s.active then return -1 end
  s.hookState.signal=signal==1 and 1 or 0
  local ok,err=pcall(Native.update,s.mem,s.callbacks)
  if not ok then
    s.active=false;s.error=tostring(err);return nil,s.error
  end
  refresh(s)
  if err==-1 then s.active=false;return -1 end
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
  if not s or not s.mem then return nil end
  if s.cachedGeometry then return s.cachedGeometry end
  refresh(s)
  local vm=s.mem
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
      g.pos[#g.pos+1]=signed16(trunc(vm:f32(at))%65536)
      g.pos[#g.pos+1]=signed16(trunc(vm:f32(at+4))%65536)
      g.pos[#g.pos+1]=signed16(trunc(vm:f32(at+8))%65536)
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
  local ok,err=pcall(Native.setAlpha,vm,s.alpha)
  if not ok then s.error="terrain-grid alpha write failed: "..tostring(err);return nil end
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
    vm:write(Native.CAMERA_POINTER,at,4)
    vm:setVec(at+0xA8,camera.eye);vm:setVec(at+0xB4,camera.focus)
    vm:setVec(at+0xC0,camera.up or {0,1,0})
    vm:setF32(at+0x2C,camera.fov);vm:setF32(at+0x30,camera.aspect);vm:setF32(at+0x34,camera.near)
    s.hookState.allocation=0x85200000;s.hookState.allocations={}
    local drawn,drawError=pcall(Native.draw,vm,s.callbacks,0x85400000)
    if not drawn then s.error='terrain-grid draw failed: '..tostring(drawError);return nil end
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
