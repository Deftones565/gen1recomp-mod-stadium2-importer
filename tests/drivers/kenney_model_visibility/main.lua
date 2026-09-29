-- Regression: models invisible in Kenney scenes on a player's Android phone
-- (fine on classic, fine on the developer's own Android).
-- Run from the game root:  love mods/STADIUM2_IMPORTER/tests/drivers/kenney_model_visibility
--
-- Draws each torch/firefly-lit Kenney scene the way the battle does
-- (scene, then the world-target reset, then the model), with a stand-in model
-- through the real model shader at each battler's place, and checks the model
-- changed the picture. Variants stand in for a phone: the mobile shader tier,
-- a 16-bit depth buffer, no instancing (the scenery's fallback path), and a
-- driver that drops uniforms the shader does not use (LOVE's send throws for
-- a dropped uniform; drawScene's pcall then fails the model pass).
local root=love.filesystem.getWorkingDirectory()
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path

local W,H=480,270
local PREFIX='mods.STADIUM2_IMPORTER.lib.'
local assetMod={read=function(_,path)
  local f=assert(io.open(root..'/mods/STADIUM2_IMPORTER/'..path,'rb'))
  local s=f:read('*a');f:close();return s
end}

-- fresh modules, so a scene rebuilds its meshes under the variant's support
local function fresh()
  for name in pairs(package.loaded) do
    if name:sub(1,#PREFIX)==PREFIX then package.loaded[name]=nil end
  end
end

-- a unit cube in Renderer.FORMAT (position, uv, normal, colour)
local function cube()
  local faces={
    {{1,0,0},{{1,-1,-1},{1,1,-1},{1,1,1},{1,-1,1}}},
    {{-1,0,0},{{-1,-1,1},{-1,1,1},{-1,1,-1},{-1,-1,-1}}},
    {{0,1,0},{{-1,1,-1},{-1,1,1},{1,1,1},{1,1,-1}}},
    {{0,-1,0},{{-1,-1,1},{-1,-1,-1},{1,-1,-1},{1,-1,1}}},
    {{0,0,1},{{-1,-1,1},{1,-1,1},{1,1,1},{-1,1,1}}},
    {{0,0,-1},{{1,-1,-1},{-1,-1,-1},{-1,1,-1},{1,1,-1}}},
  }
  local rows={}
  for _,f in ipairs(faces) do
    local n,q=f[1],f[2]
    for _,i in ipairs({1,2,3,1,3,4}) do
      local p=q[i]
      rows[#rows+1]={p[1],p[2],p[3],0,0,n[1],n[2],n[3],1,1,1,1}
    end
  end
  return rows
end

-- a driver that dropped uniforms: send throws for any the shader does not use
-- (the stand-in for a phone driver that keeps a guard uniform alive but drops
-- the rest), exactly as LOVE reports an optimised-out uniform
local function droppingShader(shader,dropped,kept)
  return setmetatable({},{__index=function(_,k)
    if k=='hasUniform' then return function(_,name)
      if kept[name] then return true end
      return not dropped[name] and shader:hasUniform(name)
    end end
    if k=='send' then return function(_,name,...)
      if dropped[name] then error("Shader uniform '"..name.."' does not exist.",2) end
      if kept[name] and not shader:hasUniform(name) then return end
      return shader:send(name,...)
    end end
    local v=shader[k]
    if type(v)=='function' then return function(_,...) return v(shader,...) end end
    return v
  end})
end

local function render(sceneName,variant)
  fresh()
  local g=love.graphics
  local realSupported=g.getSupported
  if variant.noInstancing then
    g.getSupported=function(...) local t=realSupported(...);local c={} for k,v in pairs(t) do c[k]=v end c.instancing=false return c end
  end
  local result
  local ok,err=pcall(function()
    local R=require(PREFIX..'renderer')
    local Camera=require(PREFIX..'battle_camera')
    local Nature=require(PREFIX..'battle_nature')
    Nature.bind(assetMod)
    local scenes={grass=Nature,cave=require(PREFIX..'battle_cave'),town=require(PREFIX..'battle_town'),
      freshwater=require(PREFIX..'battle_freshwater')}
    local scene=scenes[sceneName]
    if scene.bind and scene~=Nature then scene.bind(assetMod) end
    local frame=(scene.frame or Nature.frame)(Camera.frame(W,H))
    local env=scene.lighting({daytime=variant.night and 'NITE' or 'DAY',light={-.4,-.8,-.4},
      ambient={.5,.5,.5},diffuse={.6,.6,.6},modelTint={1,1,1}})
    if sceneName=='freshwater' then require(PREFIX..'battle_fireflies').update(env,8) end

    local color=g.newCanvas(W,H,{format='rgba8',readable=true,dpiscale=1})
    local depth=g.newCanvas(W,H,{format=variant.depth or 'depth24',readable=false,dpiscale=1})
    local target={color,depthstencil=depth}
    local function drawScene()
      g.setCanvas(target);g.clear(0,0,0,1,true,true)
      if scene.sky then scene.sky(g,W,H,env,frame) end
      scene.draw(g,frame,env,nil)
      -- battle_scene.lua restoreWorldTarget
      g.setCanvas(target);g.setShader();g.setDepthMode('lequal',true)
      g.setMeshCullMode('none');g.setBlendMode('alpha','alphamultiply');g.setColor(1,1,1,1)
    end

    local src=variant.mobile and R.MOBILE_SHADER_SOURCE or R.SHADER_SOURCE
    local shader=g.newShader(src)
    local mesh=g.newMesh(R.FORMAT,cube(),'triangles','static')
    local white=love.image.newImageData(1,1);white:setPixel(0,0,1,1,1,1)
    mesh:setTexture(g.newImage(white))
    local bound=variant.dropUnused and droppingShader(shader,variant.dropped,variant.keep) or shader

    local function drawModel(side)
      local p=Camera.positions[side]
      local model=R.matMul({1,0,0,p[1], 0,1,0,p[2]+7, 0,0,1,p[3], 0,0,0,1},
        {7,0,0,0, 0,7,0,0, 0,0,7,0, 0,0,0,1})
      g.setShader(shader)
      local function send(name,...) pcall(shader.send,shader,name,...) end
      send('mvp','row',R.matMul(frame.vp,model));send('viewMatrix','row',frame.view)
      send('modelMatrix','row',model);send('normalMatrix','row',{1,0,0,0,1,0,0,0,1})
      send('primitiveColor',{1,0,1,1});send('environmentColor',{1,1,1,1})
      send('sceneTint',{1,1,1,1});send('lightingEnabled',1);send('lightDir',env.light or {-.4,-.8,-.4})
      send('ambient',env.ambient or {.5,.5,.5});send('diffuse',env.diffuse or {.6,.6,.6})
      send('localTorchEnabled',0);send('fireflyEnabled',0)
      -- Renderer:drawScene: the binder runs inside its pcall; a throw there
      -- is "model draw failed" and the side is not drawn
      if scene.bindTorchLighting then
        local okBind,why=pcall(scene.bindTorchLighting,bound)
        if not okBind then return false,why end
      end
      g.draw(mesh)
      return true
    end

    drawScene();g.setCanvas()
    local before=color:newImageData()
    local drawn,why={},{}
    drawScene()
    drawn.player,why.player=drawModel('player')
    drawn.enemy,why.enemy=drawModel('enemy')
    g.setCanvas();g.setShader()
    local after=color:newImageData()
    local changed=0
    for y=0,H-1,2 do for x=0,W-1,2 do
      local r0,g0,b0=before:getPixel(x,y);local r1,g1,b1=after:getPixel(x,y)
      if math.abs(r0-r1)+math.abs(g0-g1)+math.abs(b0-b1)>.06 then changed=changed+1 end
    end end
    result={changed=changed,drawn=drawn,why=why}
    before:release();after:release();color:release();depth:release();shader:release();mesh:release()
    if scene.release then pcall(scene.release) end
  end)
  g.getSupported=realSupported
  g.setCanvas();g.setShader()
  if not ok then return nil,err end
  return result
end

local VARIANTS={
  {name='desktop'},
  {name='mobile shader',mobile=true},
  {name='depth16',depth='depth16'},
  {name='no instancing',noInstancing=true},
  {name='phone (mobile+depth16+no instancing)',mobile=true,depth='depth16',noInstancing=true},
  {name='night',night=true},
  -- a driver that keeps the binder's guard uniform but drops the unused rest
  {name='driver drops unused uniforms',dropUnused=true,dropped={localTorchShadows=true,localTorchPower=true,
    localTorch1=true,localTorch2=true,localTorchMap1=true,localTorchMap2=true,
    firefly1=true,firefly2=true,firefly3=true,firefly4=true},night=true,
    keep={localTorchEnabled=true,fireflyEnabled=true}},
}

function love.load()
  print(love.graphics.getRendererInfo())
  local failures=0
  for _,sceneName in ipairs({'grass','cave','town','freshwater'}) do
    for _,v in ipairs(VARIANTS) do
      local r,err=render(sceneName,v)
      local line
      if not r then
        failures=failures+1
        line=('ERROR %-10s %-40s %s'):format(sceneName,v.name,tostring(err))
      else
        -- a 14-unit battler covers well over 200 of the sampled pixels
        local visible=r.drawn.player and r.drawn.enemy and r.changed>200
        if not visible then failures=failures+1 end
        line=('%s %-10s %-40s changed=%d player=%s enemy=%s%s'):format(visible and 'PASS ' or 'FAIL ',
          sceneName,v.name,r.changed,tostring(r.drawn.player),tostring(r.drawn.enemy),
          r.why.player and (' ('..tostring(r.why.player):match('[^\n]*')..')') or '')
      end
      print(line)
    end
  end
  print(failures==0 and 'Kenney model visibility: all variants draw the models'
    or ('Kenney model visibility: %d variant(s) lost the models'):format(failures))
  love.event.quit(failures==0 and 0 or 1)
end
