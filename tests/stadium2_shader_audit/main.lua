local function exists(path)
  local file = io.open(path, "rb")
  if not file then return false end
  file:close()
  return true
end

local root = os.getenv("GEN1RECOMP_ROOT") or love.filesystem.getWorkingDirectory()
if not exists(root .. "/mods/STADIUM2_IMPORTER/lib/renderer.lua") then
  error("run the shader audit from the gen1recomp root or set GEN1RECOMP_ROOT")
end
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")

function love.load()
  local ok, err = Renderer.compileShaderAudit()
  if ok then
    print("shader parity audit: lit=compiled fallback=unused failures=0")
    love.event.quit(0)
  else
    print("shader parity audit: lit=rejected fallback=active failures=1")
    print("FAIL " .. tostring(err))
    love.event.quit(1)
  end
end
