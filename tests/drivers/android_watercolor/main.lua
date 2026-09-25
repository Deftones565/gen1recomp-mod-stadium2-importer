package.path=love.filesystem.getWorkingDirectory()..'/?.lua;'..package.path
function love.load()
 local g=love.graphics
 local ok,err=pcall(function()
  local R=require('mods.STADIUM2_IMPORTER.lib.renderer')
  local W=require('mods.STADIUM2_IMPORTER.lib.battle_watercolor')
  if g.validateShader then
   local valid,why=g.validateShader(true,R.MOBILE_SHADER_SOURCE);assert(valid,why)
   valid,why=g.validateShader(true,W.simpleSource);assert(valid,why)
  end
  local shader=g.newShader(R.MOBILE_SHADER_SOURCE)
  assert(shader:hasUniform('celShadingEnabled'),'mobile model shader ignores choice')
  local mesh=g.newMesh({{'VertexPosition','float',3},{'VertexTexCoord','float',2},{'VertexColor','float',4},{'VertexNormal','float',3}},
   {{-.8,-.8,0,0,0,1,1,1,1,0,1,.2},{.8,-.8,0,1,0,1,1,1,1,0,1,.2},{.8,.8,0,1,1,1,1,1,1,0,1,.2},
    {-.8,-.8,0,0,0,1,1,1,1,0,1,.2},{.8,.8,0,1,1,1,1,1,1,0,1,.2},{-.8,.8,0,0,1,1,1,1,1,0,1,.2}},'triangles')
  local source=g.newCanvas(128,128)
  local modelImages={}
  for i=0,1 do
   g.setCanvas(source);g.clear(0,0,0,0);g.setShader(shader)
   shader:send('mvp','row',R.identity());shader:send('viewMatrix','row',R.identity())
   shader:send('normalMatrix','row',{1,0,0,0,1,0,0,0,1})
   shader:send('primitiveColor',{.3,.6,.2,1});shader:send('environmentColor',{1,1,1,1})
   shader:send('sceneTint',{1,1,1,1});shader:send('lightingEnabled',1)
   shader:send('lightDir',{0,-1,-1});shader:send('celShadingEnabled',i)
   g.draw(mesh);g.setCanvas();g.setShader()
   modelImages[i+1]=source:newImageData()
  end
  assert(modelImages[1]:getString()~=modelImages[2]:getString(),'mobile toggle did not change pixels')
  -- A flat sky must not acquire screen-space waves on either shader tier.
  local flat=g.newCanvas(976,110)
  local painted=g.newCanvas(976,110)
  g.setCanvas(flat);g.clear(.35,.43,.62,1);g.setCanvas()
  for _,src in ipairs({W.fullSource,W.simpleSource}) do
   local finish=g.newShader(src)
   g.setCanvas(painted);g.setShader(finish)
   finish:send('texel',{1/976,1/110});g.setColor(1,1,1,1);g.draw(flat)
   g.setCanvas();g.setShader()
   local pixels=painted:newImageData()
   local r0,g0,b0=pixels:getPixel(10,10)
   for y=4,105 do for x=4,971 do
    local r,gc,b=pixels:getPixel(x,y)
    assert(math.abs(r-r0)<1/255 and math.abs(gc-g0)<1/255 and math.abs(b-b0)<1/255,
     'flat sky acquired a screen pattern')
   end end
   pixels:release();finish:release()
  end
  flat:release();painted:release()
  print('Desktop and Android flat-sky regression: no screen-space pattern')
  local oldSystem,oldInfo=love.system,g.getRendererInfo
  love.system=nil;g.getRendererInfo=function() return 'OpenGL ES' end
  assert(W.resolve(source,'stadium')==source)
  local output=W.resolve(source,'cel')
  assert(W.mode=='simple' and output~=source,'Android scene finish failed')
  local result=output:newImageData();assert(result:getString()~=modelImages[2]:getString())
  assert(W.resolve(source,'stadium')==source,'switching back kept manga enabled')
  love.system=oldSystem;g.getRendererInfo=oldInfo
  W.release()
  print('Mobile model shader toggles pixels; sandbox Android whole-scene manga renders; Stadium bypass works')
 end)
 g.setCanvas();g.setShader();if not ok then print(err) end
 love.event.quit(ok and 0 or 1)
end
