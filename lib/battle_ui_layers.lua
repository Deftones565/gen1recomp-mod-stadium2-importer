-- Native-coordinate overlay routing. Execute draw callbacks once, retaining
-- status pixels for the detached HUD and all other pixels in the native layer.
local Layers={}
local function canvas(old)
  if old then return old end
  local c=love.graphics.newCanvas(160,144,{dpiscale=1})
  c:setFilter("nearest","nearest")
  return c
end

function Layers.begin(scene)
  local g=love.graphics
  scene.statusOverlay=canvas(scene.statusOverlay)
  g.push("all")
  g.setCanvas(scene.statusOverlay)
  g.origin()
  g.setScissor()
  g.setShader()
  g.clear(0,0,0,0)
  g.setBlendMode("alpha","alphamultiply")
  scene.statusOverlayReady=true
end

function Layers.finish(scene,rects)
  local g=love.graphics
  g.pop()
  -- Draw the complement of the status rectangles, preserving every other
  -- overlay pixel without rerunning effects, counters or callbacks.
  g.push("all")
  g.setShader()
  g.setColor(1,1,1,1)
  g.setBlendMode("alpha","premultiplied")
  local edges={0,144}
  for _,r in ipairs(rects) do
    edges[#edges+1]=r[2];edges[#edges+1]=r[2]+r[4]
  end
  table.sort(edges)
  for index=1,#edges-1 do
    local y,h=edges[index],edges[index+1]-edges[index]
    if h>0 then
    local spans={{0,160}}
    for _,r in ipairs(rects) do
      if y>=r[2] and y<r[2]+r[4] then
        local out={}
        for _,s in ipairs(spans) do
          if s[1]<r[1] then out[#out+1]={s[1],math.min(s[2],r[1])} end
          if s[2]>r[1]+r[3] then out[#out+1]={math.max(s[1],r[1]+r[3]),s[2]} end
        end
        spans=out
      end
    end
    for _,s in ipairs(spans) do
      if s[2]>s[1] then
        local q=g.newQuad(s[1],y,s[2]-s[1],h,160,144)
        g.draw(scene.statusOverlay,q,s[1],y)
        if q.release then q:release() end
      end
    end
    end
  end
  g.pop()
end

function Layers.status(scene,rects)
  if not scene.statusOverlayReady then return end
  local g=love.graphics
  g.push("all")
  g.setShader()
  g.setColor(1,1,1,1)
  g.setBlendMode("alpha","premultiplied")
  for _,r in ipairs(rects) do
    local q=g.newQuad(r[1],r[2],r[3],r[4],160,144)
    g.draw(scene.statusOverlay,q,r[1],r[2])
    if q.release then q:release() end
  end
  g.pop()
end
return Layers
