local Mat = require("mods.STADIUM2_IMPORTER.lib.renderer")
local Camera = require("mods.STADIUM2_IMPORTER.lib.battle_camera")

local Stage = { positions=Camera.positions, MIN_RADIUS=18, MAX_RADIUS=34,
  PADDING=1.8, sink=.06 }
local texture, mesh, shader
local FORMAT={{"VertexPosition","float",3},{"VertexTexCoord","float",2}}
local SHADER=[[
varying vec3 vSun;
#ifdef VERTEX
uniform mat4 mvp; uniform mat4 modelMatrix; uniform mat4 sunVP;
vec4 position(mat4 tp,vec4 p){vSun=(sunVP*(modelMatrix*p)).xyz;return mvp*p;}
#endif
#ifdef PIXEL
uniform Image sunMap; uniform float sunEnabled; uniform float sunDark;
uniform float sunBias; uniform vec2 sunTexel; uniform vec3 stageTint;
float dep(vec2 uv){vec4 c=Texel(sunMap,uv);return c.r+c.g/255.0;}
float sunlight(vec3 p){
 if(sunEnabled<.5||p.x<0.||p.x>1.||p.y<0.||p.y>1.||p.z>1.)return 1.;
 float z=p.z-sunBias;
 float l=step(z,dep(p.xy+sunTexel*vec2(-1.5,-.5)))+step(z,dep(p.xy+sunTexel*vec2(.5,-1.5)))
  +step(z,dep(p.xy+sunTexel*vec2(1.5,.5)))+step(z,dep(p.xy+sunTexel*vec2(-.5,1.5)));
 return 1.-sunDark*(1.-l*.25);
}
vec4 effect(vec4 color,Image tex,vec2 tc,vec2 sc){
 vec4 p=Texel(tex,tc);if(p.a<.5)discard;
 return vec4(p.rgb*stageTint*sunlight(vSun),p.a);
}
#endif]]
local BAYER={{0,32,8,40,2,34,10,42},{48,16,56,24,50,18,58,26},
 {12,44,4,36,14,46,6,38},{60,28,52,20,62,30,54,22},
 {3,35,11,43,1,33,9,41},{51,19,59,27,49,17,57,25},
 {15,47,7,39,13,45,5,37},{63,31,55,23,61,29,53,21}}

local function assets()
  if texture and mesh and shader then return true end
  local g = love and love.graphics
  if not (g and love.image) then return false end
  local ok, err = pcall(function()
    local n, data = 128, love.image.newImageData(128,128)
    local half=(n-1)/2
    for y=0,n-1 do for x=0,n-1 do
      local dx,dy=(x-half)/half,(y-half)/half
      local d=math.sqrt(dx*dx+dy*dy)
      local cover=1
      if d>.76 then
        local t=math.min(1,(d-.76)/.24)
        cover=1-t*t*(3-2*t)
      end
      local threshold=(BAYER[y%8+1][x%8+1]+.5)/64
      local bx,by=math.floor(x/4),math.floor(y/4)
      local grain=(bx*37+by*71+((bx*by)%13)*17)%100<34
      local c=grain and {.67,.64,.57} or {.74,.71,.63}
      data:setPixel(x,y,c[1],c[2],c[3],cover>threshold and 1 or 0)
    end end
    texture=g.newImage(data);texture:setFilter("nearest","nearest")
    texture:setWrap("clampzero","clampzero")
    mesh=g.newMesh(FORMAT,{{-1,0,-1,0,0},{1,0,-1,1,0},
      {1,0,1,1,1},{-1,0,1,0,1}},"triangles","static")
    mesh:setVertexMap({1,2,3,1,3,4});mesh:setTexture(texture)
    shader=g.newShader(SHADER)
  end)
  if not ok then Stage.error=tostring(err) end
  return ok and true or false
end

function Stage.radius(actor)
  local m=actor and actor.renderer and actor.renderer:worldMetrics()
  if not (m and m.height and m.height>0) then return Stage.MIN_RADIUS end
  local wh=math.max(5,math.min(18,14*math.sqrt(m.height/52.25)))
  local footprint=m.radius/m.height*wh*Stage.PADDING
  return math.max(Stage.MIN_RADIUS,math.min(Stage.MAX_RADIUS,footprint))
end

function Stage.draw(g,w,h,frame,actors,shadow,environment)
  if not assets() then return nil,Stage.error or "stage graphics unavailable" end
  if g.setDepthMode then g.setDepthMode("lequal",true) end
  g.setMeshCullMode("none");g.setBlendMode("alpha","alphamultiply")
  g.setShader(shader)
  local marks={}
  for _,side in ipairs({"enemy","player"}) do
    local p,r=Stage.positions[side],Stage.radius(actors and actors[side])
    local model={r,0,0,p[1], 0,1,0,-Stage.sink, 0,0,r,p[3], 0,0,0,1}
    shader:send("mvp","row",Mat.matMul(frame.vp,model))
    shader:send("modelMatrix","row",model)
    shader:send("sunVP","row",shadow and shadow.sunVP or Mat.identity())
    shader:send("sunEnabled",shadow and shadow.map and 1 or 0)
    if shadow and shadow.map then shader:send("sunMap",shadow.map) end
    shader:send("sunDark",shadow and shadow.sunDark or .68)
    shader:send("sunBias",shadow and shadow.sunBias or .003)
    shader:send("sunTexel",shadow and shadow.sunTexel or {1/1024,1/1024})
    local tint=environment and environment.outdoor and {1,1,1} or {.84,.82,.82}
    shader:send("stageTint",tint)
    g.draw(mesh)
    local x,y=Camera.project(frame,w,h,p)
    marks[side]={x=x,y=y,radius=r}
  end
  g.setShader();g.setColor(1,1,1,1)
  return marks
end

function Stage.invalidate()
  for _,v in ipairs({texture,mesh,shader}) do
    if v and v.release then pcall(v.release,v) end
  end
  texture,mesh,shader=nil,nil,nil
end

return Stage
