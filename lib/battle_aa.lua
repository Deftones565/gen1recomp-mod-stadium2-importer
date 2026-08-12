-- Supersampling for the owned Gen 2 battle scene.  Values are samples per
-- output pixel, so 2X uses sqrt(2) in each axis and 4X uses twice the width
-- and height.  The native Gold UI is composited after this fold.
local AA = {}

local modRef, live = nil, 1
local target, targetW, targetH, shader
local unpack = table.unpack or unpack

local FOLD = [[
uniform vec2 tap;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 px) {
  vec4 a=Texel(tex,uv+vec2(-tap.x,-tap.y));
  vec4 b=Texel(tex,uv+vec2( tap.x,-tap.y));
  vec4 c=Texel(tex,uv+vec2(-tap.x, tap.y));
  vec4 d=Texel(tex,uv+vec2( tap.x, tap.y));
  float alpha=(a.a+b.a+c.a+d.a)*.25;
  if(alpha<=0.0) return vec4(0.0);
  vec3 rgb=(a.rgb*a.a+b.rgb*b.a+c.rgb*c.a+d.rgb*d.a)*.25/alpha;
  return vec4(rgb,alpha)*color;
}]]

local function release(value)
  if value and value.release then pcall(value.release,value) end
end

function AA.bind(mod) modRef=mod; return AA end

function AA.samples()
  local value=0
  if modRef and modRef.options and modRef.options.get then
    local ok,result=pcall(modRef.options.get,modRef.options,"stadium2_battle_aa")
    if ok then value=tonumber(result) or 0 end
  end
  return value==2 and 2 or value==4 and 4 or 0
end

function AA.expand(width,height)
  local samples=AA.samples()
  local factor=samples>1 and math.sqrt(samples) or 1
  local g=love and love.graphics
  if g and g.getSystemLimits then
    local ok,limits=pcall(g.getSystemLimits)
    local limit=ok and limits and tonumber(limits.texturesize)
    if limit and limit>0 then
      factor=math.min(factor,limit/math.max(1,width),limit/math.max(1,height))
    end
  end
  if factor<=1.01 then live=1; return width,height end
  local w,h=math.floor(width*factor+.5),math.floor(height*factor+.5)
  live=w/math.max(1,width)
  return w,h
end

function AA.factor() return live end

local function ensureTarget(width,height)
  if target and targetW==width and targetH==height then return target end
  local g=love and love.graphics
  if not g then return nil end
  local ok,value=pcall(g.newCanvas,width,height,
    {format="rgba8",readable=true,dpiscale=1})
  if not ok then return nil end
  release(target);target,targetW,targetH=value,width,height
  value:setFilter("nearest","nearest")
  return value
end

function AA.resolve(source,width,height)
  if not source then return nil end
  local sw,sh=source:getDimensions()
  if sw==width and sh==height then return source end
  local output=ensureTarget(width,height)
  if not output then return source end
  local g=love.graphics
  if shader==nil then
    local ok,value=pcall(g.newShader,FOLD);shader=ok and value or false
  end
  local previous=g.getCanvas and {g.getCanvas()} or nil
  local oldShader=g.getShader and g.getShader() or nil
  local oldBlend,oldAlpha=g.getBlendMode()
  local min,mag=source:getFilter();source:setFilter("linear","linear")
  local ok=pcall(function()
    g.setCanvas(output);g.clear(0,0,0,0)
    g.setBlendMode("replace","premultiplied")
    if shader then g.setShader(shader);shader:send("tap",{.5/sw,.5/sh}) end
    g.setColor(1,1,1,1);g.draw(source,0,0,0,width/sw,height/sh)
  end)
  if previous and #previous>0 then g.setCanvas(unpack(previous)) else g.setCanvas() end
  g.setShader(oldShader);g.setBlendMode(oldBlend or "alpha",oldAlpha)
  source:setFilter(min or "nearest",mag or "nearest")
  return ok and output or source
end

function AA.release()
  release(target);release(shader)
  target,targetW,targetH,shader=nil,0,0,nil;live=1
end

return AA
