package.path="./?.lua;./?/init.lua;"..package.path
local Controller=require("mods.STADIUM2_IMPORTER.lib.stadium_controller")
local Glyphs=require("mods.STADIUM2_IMPORTER.lib.stadium_button_glyphs")
local Atlas=require("mods.STADIUM2_IMPORTER.lib.stadium_button_atlas")
local checks=0
local function ok(v,m) checks=checks+1; assert(v,m) end
local function u32(s,o)
  local a,b,c,d=s:byte(o,o+3); return ((a*256+b)*256+c)*256+d
end
for family,spec in pairs(Atlas) do
  local f=assert(io.open("mods/STADIUM2_IMPORTER/assets/controller_buttons/"..spec.file,"rb"))
  local header=f:read(26); f:close()
  ok(header:sub(1,8)=="\137PNG\13\10\26\10",family.." is PNG")
  local w,h=u32(header,17),u32(header,21)
  ok(header:byte(26)==6,family.." retains RGBA transparency")
  local count=0
  for key,r in pairs(spec.rects) do
    count=count+1
    ok(r[1]>=0 and r[2]>=0 and r[3]>0 and r[4]>0
      and r[1]+r[3]<=w and r[2]+r[4]<=h,family..":"..key.." is inside actual PNG")
  end
  ok(count==12,family.." has twelve complete prompts")
end

local uploads,draws,prints,releasedImages,releasedQuads,warnings=0,{}, {},0,0,0
local color={.2,.4,.6,.8}
local fail=false
local loadedSources={}
local g={
  newImage=function(source)
    loadedSources[#loadedSources+1]=source
    uploads=uploads+1; if fail then error("simulated missing asset") end
    return {setFilter=function()end,setMipmapFilter=function()end,
      getDimensions=function()return 1448,1086 end,
      release=function()releasedImages=releasedImages+1 end}
  end,
  newQuad=function(x,y,w,h,iw,ih)
    assert(x+w<=iw and y+h<=ih,"out-of-bounds UVs")
    return {x=x,y=y,w=w,h=h,release=function()releasedQuads=releasedQuads+1 end}
  end,
  getColor=function()return unpack(color) end,
  setColor=function(...)color={...} end,
  draw=function(image,quad,x,y,rotation,sx,sy)draws[#draws+1]={quad=quad,x=x,y=y,sx=sx,sy=sy} end,
  getFont=function()return {getWidth=function(_,s)return #s*6 end,getHeight=function()return 10 end} end,
  print=function(s)prints[#prints+1]=s end,
  setLineWidth=function()end,rectangle=function()end,circle=function()end,
}
local bindings={a="a",b="b",start="start"}
local game={input={padBindings=bindings}}
Controller.reset(); Controller.setStyle("xbox")
-- Installed mods have sealed love.filesystem; assets:path resolves their
-- mounted package while newImage retains private ownership for cleanup.
love={filesystem=setmetatable({}, {__index=function()error("filesystem denied")end})}
Glyphs.bindMod({assets={path=function(_,path)return "mounted-mod/"..path end}})
Glyphs.setContext(game,"pad")
ok(Glyphs.draw(g,"A",0,0,16,17),"controller prompt draws")
ok(uploads==1 and #draws==1,"first prompt uploads one sheet")
ok(loadedSources[1]=="mounted-mod/assets/controller_buttons/xbox.png","sealed mod uses its mounted asset path")
ok(color[1]==.2 and color[4]==.8,"prompt restores caller color")
Glyphs.draw(g,"B",0,0,16,17)
Glyphs.draw(g,"CUP",0,0,16,17)
ok(uploads==1 and #draws==3 and #prints==0,"face and right-stick glyphs share one upload")
ok(draws[3].quad.y==Atlas.xbox.rects.r_up[2],"C-up uses the right-stick-up glyph")
local remapped={input={padBindings={x="a",b="b",start="start"}}}
Glyphs.setContext(remapped,"pad"); Glyphs.draw(g,"A",0,0,16,17)
ok(draws[#draws].quad.x==Atlas.xbox.rects.x[1],"remapped A shows physical X")
Glyphs.setContext({input={padBindings={triggerleft="a"}}},"pad")
Glyphs.draw(g,"A",0,0,16,17)
ok(prints[#prints]=="LT","unpictured binding gets its actual label")
Glyphs.setContext(game,"keyboard")
ok(not Glyphs.draw(g,"A",0,0,16,17),"AUTO yields to native keyboard prompts")
Glyphs.setStyle("playstation"); Controller.setStyle("playstation")
Glyphs.setContext(game,"keyboard"); Glyphs.draw(g,"A",0,0,16,17)
ok(uploads==2,"explicit family can preview on keyboard")
Glyphs.setStyle("native"); Glyphs.setContext(game,"pad")
ok(not Glyphs.draw(g,"A",0,0,16,17),"NATIVE yields to ROM glyphs")
Glyphs.release(); Glyphs.release()
ok(releasedImages==2 and releasedQuads==24,"teardown releases each cached image and quad exactly once")

fail=true; Glyphs.bindWarning(function()warnings=warnings+1 end)
Glyphs.setContext(game,"pad"); Controller.setStyle("xbox")
Glyphs.draw(g,"A",0,0,16,17); Glyphs.draw(g,"B",0,0,16,17)
ok(uploads==3 and warnings==1,"failed upload is reported once and not retried per button")
ok(prints[#prints]=="B","asset failure retains the actual button label")
Glyphs.release(); Controller.reset()
print(("%d checks passed (controller atlas bounds, bindings, cache, fallbacks and cleanup)"):format(checks))
