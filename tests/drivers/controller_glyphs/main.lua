-- From repository root: SDL_VIDEODRIVER=offscreen love
-- mods/STADIUM2_IMPORTER/tests/drivers/controller_glyphs
-- Optional STADIUM2_CONTROLLER_PREVIEW=/tmp/controller-preview.png
package.path=love.filesystem.getWorkingDirectory().."/?.lua;"..package.path
function love.load()
  local g=love.graphics
  local success,err=pcall(function()
    -- The standalone test's source directory is this driver, not the host
    -- repository. Decode its repository-relative images through FileData in
    -- this trusted test process; installed mods use assets:path normally.
    local newImage=g.newImage
    g.newImage=function(source,...)
      if type(source)=="string" then
        local f=assert(io.open(source,"rb"))
        local data=love.filesystem.newFileData(f:read("*a"),source); f:close()
        local image=newImage(data,...);data:release();return image
      end
      return newImage(source,...)
    end
    local Controller=require("mods.STADIUM2_IMPORTER.lib.stadium_controller")
    local Glyphs=require("mods.STADIUM2_IMPORTER.lib.stadium_button_glyphs")
    local Assets=require("mods.STADIUM2_IMPORTER.lib.stadium_ui_assets")
    local UI=require("mods.STADIUM2_IMPORTER.lib.stadium_ui")
    local Menu=require("mods.STADIUM2_IMPORTER.lib.stadium_menu")
    local f=assert(io.open("mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb"))
    local decoded=assert(Assets.fromRom(f:read("*a"))); f:close()
    Assets.load=function()return decoded end
    local warnings={}
    Glyphs.bindMod({assets={path=function(_,p)return "mods/STADIUM2_IMPORTER/"..p end}})
    Glyphs.bindWarning(function(s)warnings[#warnings+1]=s end)
    local input={padBindings={a="a",b="b",start="start",
      dpup="up",dpdown="down",dpleft="left",dpright="right"},isDown=function()return false end}
    local tabs={{button="A",label="BATTLE",hostIndex=1},{button="B",label="POK\233MON",hostIndex=2},
      {button="S",label="RUN",hostIndex=4},{button="R",label="PACK",hostIndex=3}}
    local moves={{name="THUNDERBOLT",type="electric",pp=15,maxPp=15},
      {name="QUICK ATTACK",type="normal",pp=30,maxPp=30},
      {name="SURF",type="water",pp=15,maxPp=15},{name="IRON TAIL",type="steel",pp=15,maxPp=15}}
    local canvas=g.newCanvas(1440,840)
    g.setCanvas(canvas); g.clear(.035,.055,.09,1)
    for i,family in ipairs({"xbox","playstation","ayn_thor","steamdeck"}) do
      local y=(i-1)*210
      Controller.setStyle(family); Glyphs.setStyle(family)
      g.setColor(1,1,1,1); g.print(family:upper(),24,y+12)
      g.push(); g.translate(0,y+26); g.scale(2,2)
      Menu.draw({kind="command",tabs=tabs,game={input=input},mode="stadium"})
      g.pop()
      g.push(); g.translate(720,y+8); g.scale(2,2)
      Menu.draw({kind="moves",moves=moves,game={input=input},mode="stadium"})
      g.pop()
      for j,logical in ipairs({"A","B","S","L","R","CUP","CRIGHT","CDOWN","CLEFT","DPAD"}) do
        assert(Glyphs.draw(g,logical,40+(j-1)*64,y+120,32,34))
      end
    end
    g.setCanvas()
    assert(#warnings==0,table.concat(warnings,"\n"))
    local pixels=canvas:newImageData()
    local target=os.getenv("STADIUM2_CONTROLLER_PREVIEW")
    if target then
      local png=pixels:encode("png")
      local out=assert(io.open(target,"wb")); out:write(png:getString());out:close();png:release()
    end
    pixels:release();canvas:release();Glyphs.release();Controller.reset()
    g.newImage=newImage
    print("Four controller atlases uploaded and drawn through Stadium menus without fallback")
  end)
  g.setCanvas();if not success then print(err) end
  love.event.quit(success and 0 or 1)
end
