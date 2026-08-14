local function read(path)
  local file=assert(io.open(path,"rb"))
  local text=file:read("*a")
  file:close()
  return text
end

local root=((arg and arg[0]) or ""):gsub("\\","/")
  :match("^(.*)/tests/[^/]+$") or "mods/STADIUM2_IMPORTER"
local scene=read(root.."/lib/battle_scene.lua")
local shadow=read(root.."/lib/battle_shadow.lua")
local renderer=read(root.."/lib/renderer.lua")
local checks,failures=0,0

local function check(value,name)
  checks=checks+1
  if value then print("PASS "..name)
  else failures=failures+1;print("FAIL "..name) end
end

check(scene:find('"depth24stencil8","depth24","depth16","depth32f"',1,true),
  "battle scene tries mobile-compatible depth formats")
check(scene:find("return {self.canvas,depth=true}",1,true),
  "battle scene falls back to an internal depth attachment")
check(shadow:find('"depth24stencil8","depth24","depth16","depth32f"',1,true),
  "shadow pass tries mobile-compatible depth formats")
check(shadow:find("g.setCanvas({color,depth=true})",1,true),
  "shadow pass falls back to an internal depth attachment")
check(renderer:find("self.canvas, self.depth, self.temporaryDepth = makeCanvas",1,true),
  "standalone renderer records internal-depth fallback")
check(renderer:find("g.setCanvas({self.canvas,depth=true})",1,true),
  "standalone renderer never silently renders depthless")

print(("RESULT checks=%d failures=%d"):format(checks,failures))
if failures>0 then os.exit(1) end
