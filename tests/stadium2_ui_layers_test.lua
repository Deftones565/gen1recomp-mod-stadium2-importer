package.path="./?.lua;./?/init.lua;"..package.path
local Layers=require("mods.STADIUM2_IMPORTER.lib.battle_ui_layers")
local stack,draws={},{}
local target="native"
local g={}
function g.newCanvas() return {setFilter=function() end} end
function g.push() stack[#stack+1]=target end
function g.pop() target=table.remove(stack) end
function g.setCanvas(value) target=value end
function g.newQuad(x,y,w,h) return {x=x,y=y,w=w,h=h} end
function g.draw(_,q,x,y)
  draws[#draws+1]={target=target,q=q,x=x,y=y}
end
for _,name in ipairs({"origin","setScissor","setShader","clear","setColor","setBlendMode"}) do
  g[name]=function() end
end
love={graphics=g}
local scene={}
local rects={{8,0,80,32},{72,56,88,40}}
Layers.begin(scene)
assert(target==scene.statusOverlay)
Layers.finish(scene,rects)
assert(target=="native" and #stack==0,"capture restores its caller")
target="hud"
Layers.status(scene,rects)
assert(target=="hud" and #stack==0,"status composition restores its caller")
local coverage={}
for _,draw in ipairs(draws) do
  local q=draw.q
  for y=q.y,q.y+q.h-1 do
    for x=q.x,q.x+q.w-1 do
      local key=y*160+x
      assert(not coverage[key],"overlay pixel duplicated")
      coverage[key]=draw.target
      local inside=false
      for _,r in ipairs(rects) do
        if x>=r[1] and x<r[1]+r[3] and y>=r[2] and y<r[2]+r[4] then inside=true end
      end
      assert(draw.target==(inside and "hud" or "native"),"overlay pixel sent to wrong region")
    end
  end
end
for index=0,160*144-1 do assert(coverage[index],"overlay pixel lost") end
local count=#draws
scene.statusOverlayReady=nil
Layers.status(scene,rects)
assert(#draws==count,"stale overlay reused")
print("23040 overlay pixels routed exactly once; graphics scope and stale-frame checks passed")
