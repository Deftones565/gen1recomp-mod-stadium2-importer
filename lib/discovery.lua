local Discovery = {}

local NAMES = {
  "Pokemon Stadium 2 (USA).z64",
  "Pokemon Stadium 2 (USA).n64",
  "Pokemon Stadium 2 (USA).v64",
  "pokemon_stadium_2.z64",
  "pokemonstadium2.z64",
  "stadium2.z64",
}

local function readable(path)
  if type(path) ~= "string" or path == "" or not (io and io.open) then return false end
  local file = io.open(path, "rb")
  if not file then return false end
  file:close()
  return true
end

local function join(a, b)
  if not a or a == "" then return b end
  local sep = a:find("\\", 1, true) and "\\" or "/"
  return a:gsub("[/\\]+$", "") .. sep .. b
end

local function dirname(path)
  return type(path) == "string" and path:match("^(.*)[/\\][^/\\]+$") or nil
end

local function directories()
  local out, seen = {}, {}
  local function add(path)
    if type(path) == "string" and path ~= "" and not seen[path] then
      seen[path] = true
      out[#out + 1] = path
    end
  end
  if os and os.getenv then
    add(dirname(os.getenv("APPIMAGE")))
    add(os.getenv("PWD"))
  end
  if love and love.filesystem then
    if love.filesystem.getWorkingDirectory then
      local ok, value = pcall(love.filesystem.getWorkingDirectory)
      if ok then add(value) end
    end
    if love.filesystem.getSourceBaseDirectory then
      local ok, value = pcall(love.filesystem.getSourceBaseDirectory)
      if ok then add(value) end
    end
  end
  if type(arg) == "table" then add(dirname(arg[0])) end
  return out
end

local function saveCandidates()
  local out = {}
  if not (love and love.filesystem and love.filesystem.getInfo) then return out end
  for _, name in ipairs(NAMES) do
    for _, prefix in ipairs({ "", "baseroms/" }) do
      local path = prefix .. name
      local ok, info = pcall(love.filesystem.getInfo, path, "file")
      if ok and info then out[#out + 1] = { kind = "love", path = path } end
    end
  end
  return out
end

function Discovery.find()
  if os and os.getenv then
    local env = os.getenv("STADIUM2_ROM")
    if readable(env) then return { kind = "host", path = env } end
  end
  local save = saveCandidates()
  if save[1] then return save[1] end
  for _, dir in ipairs(directories()) do
    for _, name in ipairs(NAMES) do
      local path = join(dir, name)
      if readable(path) then return { kind = "host", path = path } end
    end
  end
  return nil
end

function Discovery.read(candidate)
  if not candidate then return nil, "no Stadium 2 ROM found" end
  if candidate.kind == "love" then
    local ok, bytes = pcall(love.filesystem.read, candidate.path)
    if ok and type(bytes) == "string" then return bytes end
    return nil, "could not read Stadium 2 ROM"
  end
  if not (io and io.open) then return nil, "host file access unavailable" end
  local file, err = io.open(candidate.path, "rb")
  if not file then return nil, tostring(err or "could not open Stadium 2 ROM") end
  local bytes = file:read("*a")
  file:close()
  if type(bytes) ~= "string" or bytes == "" then return nil, "could not read Stadium 2 ROM" end
  return bytes
end

local function commandOutput(command)
  local pipe, close
  local okHost, HostShell = pcall(require, "src.core.HostShell")
  if okHost and HostShell and type(HostShell.popen) == "function" then
    pipe = HostShell.popen(command, "r")
    close = function(p)
      if type(HostShell.pclose) == "function" then
        HostShell.pclose(p)
      else
        pcall(p.close, p)
      end
    end
  elseif io and io.popen then
    local ok, opened = pcall(io.popen, command, "r")
    pipe = ok and opened or nil
    close = function(p) pcall(p.close, p) end
  end
  if not pipe then return nil end
  local okRead, output = pcall(pipe.read, pipe, "*a")
  close(pipe)
  if not okRead or type(output) ~= "string" then return nil end
  output = output:gsub("^%s+", ""):gsub("%s+$", "")
  return output ~= "" and output or nil
end

function Discovery.choose()
  local platform = love and love.system and love.system.getOS and love.system.getOS() or nil
  if platform == "Linux" then
    return commandOutput([[zenity --file-selection --title="Choose Pokemon Stadium 2 (US) ROM" --file-filter="Nintendo 64 ROM | *.z64 *.n64 *.v64" 2>/dev/null]])
      or commandOutput([[kdialog --getopenfilename "$HOME" "*.z64 *.n64 *.v64|Nintendo 64 ROM" 2>/dev/null]])
  end
  if platform == "OS X" then
    return commandOutput([[osascript -e 'POSIX path of (choose file with prompt "Choose Pokemon Stadium 2 (US) ROM" of type {"z64", "n64", "v64"})' 2>/dev/null]])
  end
  if platform == "Windows" then
    local script = "Add-Type -AssemblyName System.Windows.Forms;$d=New-Object System.Windows.Forms.OpenFileDialog;$d.Title='Choose Pokemon Stadium 2 (US) ROM';$d.Filter='Nintendo 64 ROM (*.z64;*.n64;*.v64)|*.z64;*.n64;*.v64|All files (*.*)|*.*';if($d.ShowDialog() -eq 'OK'){[Console]::OutputEncoding=[Text.Encoding]::UTF8;[Console]::Write($d.FileName)}"
    return commandOutput('powershell -NoProfile -STA -Command "' .. script .. '"')
  end
  return nil
end

Discovery.names = NAMES

return Discovery
