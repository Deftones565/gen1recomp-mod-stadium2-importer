-- Scene-only watercolor finish. GLES 2 / GLSL 1 syntax, RGBA8 targets,
-- no derivatives, float buffers, depth reads, dynamic loops or extra textures.
local Watercolor={}
local shader,target,tw,th
-- Shared pigment palette and paper response preserve the rendered light values:
-- warm flames stay warm, cool shadows stay cool, and black receives no paper lift.
local PAINT=[[
float luminance(vec3 c){return dot(c,vec3(.299,.587,.114));}
vec3 finishPaint(vec3 rgb,float edge){
 float lum=luminance(rgb);
 // Keep flat colors spatially uniform: no screen-space grain or hatching.
 // Soft pigment bands, not independent RGB posterization (which changes hue).
 float band=(floor(lum*7.)+smoothstep(.18,.82,fract(lum*7.)))/7.;
 rgb*=mix(1.,band/max(lum,.015),.32);
 vec3 paper=vec3(1.,.97,.89);
 rgb=mix(rgb,rgb*paper,.24);
 // Restrained colored ink follows silhouettes and large tonal boundaries.
 float ink=smoothstep(.12,.42,edge)*.24;
 rgb*=1.-ink;
 rgb=mix(rgb,paper,.035*smoothstep(.18,.75,lum));
 return clamp(rgb,0.,1.);
}
]]
local FULL=[[uniform vec2 texel;
]]..PAINT..[[
vec4 effect(vec4 color,Image tex,vec2 uv,vec2 px){
 vec4 center=Texel(tex,uv);
 vec3 a=Texel(tex,uv+vec2(texel.x,0.)).rgb;
 vec3 b=Texel(tex,uv-vec2(texel.x,0.)).rgb;
 vec3 c=Texel(tex,uv+vec2(0.,texel.y)).rgb;
 vec3 d=Texel(tex,uv-vec2(0.,texel.y)).rgb;
 float edge=length(a-b)+length(c-d);
 vec3 sum=center.rgb*2.;float weight=2.;
 // Broad, edge-aware washes combine neighboring pigments without smearing eyes
 // or leaking warm light across silhouettes into unlit background objects.
 for(int x=-1;x<=1;x+=2){for(int y=-1;y<=1;y+=2){
  vec3 sampleColor=Texel(tex,uv+vec2(float(x),float(y))*texel*2.5).rgb;
  float w=1.-smoothstep(.035,.24,length(sampleColor-center.rgb));
  sum+=sampleColor*w;weight+=w;
 }}
 vec3 wash=mix(center.rgb,sum/weight,.72);
 return vec4(finishPaint(wash,edge),center.a)*color;
}]]
local SIMPLE=[[uniform vec2 texel;
]]..PAINT..[[
vec4 effect(vec4 color,Image tex,vec2 uv,vec2 px){
 vec4 c=Texel(tex,uv);
 vec3 a=Texel(tex,uv+vec2(texel.x,0.)).rgb;
 vec3 b=Texel(tex,uv-vec2(texel.x,0.)).rgb;
 vec3 d=Texel(tex,uv+vec2(0.,texel.y)).rgb;
 vec3 e=Texel(tex,uv-vec2(0.,texel.y)).rgb;
 float edge=length(a-b)+length(d-e);
 vec3 wash=mix(c.rgb,(c.rgb*4.+a+b+d+e)*.125,.45*(1.-smoothstep(.06,.25,edge)));
 return vec4(finishPaint(wash,edge),c.a)*color;
}]]
Watercolor.fullSource=FULL
Watercolor.simpleSource=SIMPLE

function Watercolor.choose(g)
 local mobile=love and love.system and love.system.getOS
   and (love.system.getOS()=="Android" or love.system.getOS()=="iOS")
 -- The mod sandbox exposes renderer information even without love.system.
 if not mobile and g.getRendererInfo then
  local ok,name=pcall(g.getRendererInfo)
  if ok then
   local label=tostring(name):lower()
   mobile=label:find('opengl es',1,true)~=nil or label:find('gles',1,true)~=nil
  end
 end
 local sources=mobile and {SIMPLE} or {FULL,SIMPLE}
 for _,source in ipairs(sources) do
  local ok,value=pcall(g.newShader,source)
  if ok and value then return value,source==FULL and "full" or "simple" end
 end
 return false,"off"
end

function Watercolor.resolve(source,style)
 if style=="stadium" then return source end
 local g=love and love.graphics
 if not (source and g) then return source end
 if shader==nil then shader,Watercolor.mode=Watercolor.choose(g) end
 if not shader then return source end
 local w,h=source:getDimensions()
 if not target or tw~=w or th~=h then
  local ok,value=pcall(g.newCanvas,w,h,{format="rgba8",readable=true,dpiscale=1})
  if not ok then Watercolor.error=tostring(value);return source end
  if target then target:release() end
  target,tw,th=value,w,h
 end
 local pushed=pcall(g.push,"all")
 if not pushed then return source end
 local ok,err=pcall(function()
  g.setCanvas(target);g.origin();g.setScissor()
  g.setDepthMode("always",false);g.setBlendMode("replace","premultiplied")
  g.setColor(1,1,1,1);g.setShader(shader)
  if Watercolor.mode=="full" or Watercolor.mode=="simple" then
   -- Physical resolution follows the existing scene/AA output.
   local scale=math.max(1,h/720)
   shader:send("texel",{scale/w,scale/h})
  end
  g.draw(source)
 end)
 g.pop()
 if not ok then Watercolor.error=tostring(err);return source end
 Watercolor.error=nil
 return target
end

function Watercolor.release()
 if target then target:release() end
 if shader then shader:release() end
 target,shader,tw,th=nil,nil,nil,nil
 Watercolor.mode,Watercolor.error=nil,nil
end
return Watercolor
