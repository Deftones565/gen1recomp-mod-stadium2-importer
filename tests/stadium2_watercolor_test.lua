package.path="./?.lua;./?/init.lua;"..package.path
local W=require("mods.STADIUM2_IMPORTER.lib.battle_watercolor")
local original=love
local calls=0
love={system={getOS=function() return "Linux" end}}
local chosen,mode=W.choose({newShader=function(source)
 calls=calls+1
 if source==W.fullSource then error("unsupported") end
 return {source=source}
end})
assert(mode=="simple" and calls==2 and chosen.source==W.simpleSource)
chosen,mode=W.choose({newShader=function() error("no shaders") end})
assert(chosen==false and mode=="off")
love.system.getOS=function() return "Android" end
calls=0
chosen,mode=W.choose({newShader=function(source)
 calls=calls+1;assert(source==W.simpleSource);return {}
end})
assert(mode=="simple" and calls==1)
local source={getDimensions=function() return 1280,720 end}
love.graphics={newShader=function() return {release=function() end} end,newCanvas=function() error("out of memory") end}
assert(W.resolve(source)==source,"allocation failure must preserve scene")
W.release()
love=original
print("Watercolor shader selection and allocation fallback checks passed")
-- Android sandbox may omit love.system entirely.
love={graphics={getRendererInfo=function() return 'OpenGL ES','3.2','Qualcomm','Adreno' end}}
local chosenSource
love.graphics.newShader=function(src) chosenSource=src;return {} end
local _,tier=W.choose(love.graphics)
assert(tier=='simple' and chosenSource==W.simpleSource,'sandbox GLES must use Android finish')
love.graphics.newShader=function() error('Stadium mode must not compile watercolor') end
love.graphics.newCanvas=function() error('Stadium mode must not allocate watercolor') end
assert(W.resolve(source,'stadium')==source)
local Importer=require('mods.STADIUM2_IMPORTER.lib.importer')
local option='stadium'
Importer.bind({options={get=function(_,key) if key=='stadium2_shader' then return option end end}})
assert(Importer.shaderStyle()=='stadium');option='cel';assert(Importer.shaderStyle()=='cel')
option='invalid';assert(Importer.shaderStyle()=='stadium')
love=original
print('Sandbox Android detection, Stadium bypass and live shader choice passed')
