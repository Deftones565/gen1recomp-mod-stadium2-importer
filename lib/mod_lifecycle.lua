-- Older hosts do not expose a mod-unload callback. Observe their real teardown
-- boundaries with reversible patches; no watcher survives this mod's session.
local Scope=require('mods.STADIUM2_IMPORTER.lib.patch_scope')
local Lifecycle={};Lifecycle.__index=Lifecycle
local current
function Lifecycle:stop()
 if not self.active then return end
 self.active=false
 self.patches:restore()
 for i=#self.subscriptions,1,-1 do pcall(self.subscriptions[i]) end
 self.subscriptions={}
 for _,fn in ipairs(self.cleanup) do
  local ok,err=pcall(fn)
  if not ok and self.mod.log then pcall(self.mod.log.warn,self.mod.log,'Stadium teardown: %s',tostring(err)) end
 end
 self.cleanup={}
 if current==self then current=nil end
end
function Lifecycle:add(fn) self.cleanup[#self.cleanup+1]=fn end
function Lifecycle.new(mod)
 if current then current:stop() end
 local self=setmetatable({mod=mod,active=true,patches=Scope.new(),subscriptions={},cleanup={}},Lifecycle)
 current=self
 -- Keep unsubscribe handles for the ordinary API too. Gates also protect an
 -- event snapshot or another mod that retained an old callback.
 local wrap=mod.hooks.wrap
 mod.hooks.wrap=function(api,name,fn,priority)
  local off=wrap(api,name,function(next,...)
   if not self.active then return next(...) end
   return fn(next,...)
  end,priority)
  if type(off)=='function' then self.subscriptions[#self.subscriptions+1]=off end
  return off
 end
 for _,method in ipairs({'on','once'}) do
  local register=mod.events[method]
  if register then mod.events[method]=function(api,name,fn,priority)
   local off=register(api,name,function(...)
    if self.active then return fn(...) end
   end,priority)
   if type(off)=='function' then self.subscriptions[#self.subscriptions+1]=off end
   return off
  end end
 end
 local function observe(module,method,before)
  local ok,target=pcall(require,module)
  if not (ok and type(target[method])=='function') then return end
  local original=target[method]
  self.patches:capture({target},function()
   target[method]=function(...)
    if before(...) then self:stop() end
    return original(...)
   end
  end)
 end
 local yes=function() return true end
 observe('src.core.SessionLifecycle','endGameSession',yes)
 observe('src.core.SessionLifecycle','endMountedSession',yes)
 observe('src.mods.Runtime','reset',yes)
 observe('src.mods.Runtime','install',yes)
 observe('src.mods.Loader','_rollback',function(_,id) return id=='STADIUM2_IMPORTER' end)
 -- setEnabled persists a per-game decision. Respect refusal (safe mode or
 -- unknown ID) and let the host save it before removing our wrappers.
 local ok,Loader=pcall(require,'src.mods.Loader')
 if ok and type(Loader.setEnabled)=='function' then
  local original=Loader.setEnabled
  self.patches:capture({Loader},function()
   Loader.setEnabled=function(loader,id,enabled)
    local result=original(loader,id,enabled)
    if result and id=='STADIUM2_IMPORTER' and not enabled then self:stop() end
    return result
   end
  end)
 end
 -- The launcher checkboxes are scoped to a version; changing another
 -- game's checkbox must not tear down the currently running game.
 local hasLauncher,Launcher=pcall(require,'src.mods.LauncherMods')
 local hasVersion,Version=pcall(require,'src.core.GameVersion')
 local version=hasVersion and Version.get and Version.get()
 if hasLauncher then
  for _,method in ipairs({'uninstall','setEnabled'}) do
   local original=Launcher[method]
   if type(original)=='function' then self.patches:capture({Launcher},function()
    Launcher[method]=function(id,enabled,selectedVersion)
     local result,err=original(id,enabled,selectedVersion)
     if result and id=='STADIUM2_IMPORTER' and (method=='uninstall'
       or (enabled==false and (selectedVersion==nil or selectedVersion==version))) then self:stop() end
     return result,err
    end
   end) end
  end
 end
 mod.exports.uninstall=function() self:stop() end
 return self
end
return Lifecycle
