package.path='./?.lua;./?/init.lua;'..package.path
local Scope=require('mods.STADIUM2_IMPORTER.lib.patch_scope')
local original=function(...) return ... end
local parent={draw=original};local target=setmetatable({},{__index=parent})
local scope=Scope.new();local calls=0
scope:capture({target},function()
 target.installed=true
 target.draw=function(...) calls=calls+1;return original(...) end
end)
local retained=target.draw
local a,b,c=target.draw(1,nil,3);assert(a==1 and b==nil and c==3 and calls==1)
local later=function(...) return retained(...) end;target.draw=later
scope:restore();scope:restore()
assert(target.draw==later and target.installed==nil)
a,b,c=target.draw(1,nil,3);assert(a==1 and b==nil and c==3 and calls==1)
local fail=Scope.new();local t={draw=original}
assert(not pcall(function() fail:capture({t},function() t.draw=function() end;t.flag=true;error('partial install') end) end))
assert(t.draw==original and t.flag==nil)
local Lifecycle=require('mods.STADIUM2_IMPORTER.lib.mod_lifecycle')
local Session={endGameSession=original,endMountedSession=original}
local Runtime={reset=original,install=original}
local Loader={_rollback=original,setEnabled=function(self,id,enabled)
 if self.safeMode then return false end
 self.enabled=enabled;return true
end}
package.loaded['src.core.SessionLifecycle']=Session
package.loaded['src.mods.Runtime']=Runtime
package.loaded['src.mods.Loader']=Loader
local Launcher={uninstall=function() return true end,setEnabled=function() return true end}
package.loaded['src.mods.LauncherMods']=Launcher
package.loaded['src.core.GameVersion']={get=function() return 'gold' end}
local setter=Loader.setEnabled
for _,boundary in ipairs({'disable','game','mount','reset','replace','rollback','uninstall','delete','checkbox'}) do
 local hooks,events={},{}
 local mod={exports={},hooks={wrap=function(_,name,fn) hooks[name]=fn;return function() hooks[name]=nil end end},
 events={on=function(_,name,fn) events[name]=fn;return function() events[name]=nil end end}}
 local lifecycle=Lifecycle.new(mod);local cleaned=0
 lifecycle:add(function() cleaned=cleaned+1 end)
 local effects=0
 mod.hooks:wrap('test',function(next,...) effects=effects+1;return next(...) end)
 mod.events:on('test',function() effects=effects+1 end)
 local hook,event=hooks.test,events.test
 hook(original,1);event();assert(effects==2)
 assert(Loader:setEnabled('other',false));assert(cleaned==0)
 Loader:_rollback('other');assert(cleaned==0)
 assert(Loader.setEnabled({safeMode=true},'STADIUM2_IMPORTER',false)==false);assert(cleaned==0)
 Launcher.setEnabled('STADIUM2_IMPORTER',false,'red');assert(cleaned==0,'other game checkbox')
 if boundary=='delete' then Launcher.uninstall('STADIUM2_IMPORTER')
 elseif boundary=='checkbox' then Launcher.setEnabled('STADIUM2_IMPORTER',false,'gold')
 elseif boundary=='disable' then Loader:setEnabled('STADIUM2_IMPORTER',false)
 elseif boundary=='game' then Session.endGameSession()
 elseif boundary=='mount' then Session.endMountedSession()
 elseif boundary=='reset' then Runtime.reset()
 elseif boundary=='replace' then Runtime.install()
 elseif boundary=='rollback' then Loader:_rollback('STADIUM2_IMPORTER')
 else mod.exports.uninstall() end
 assert(cleaned==1 and hooks.test==nil and events.test==nil,boundary)
 assert(Session.endGameSession==original and Session.endMountedSession==original)
 assert(Runtime.reset==original and Runtime.install==original and Loader.setEnabled==setter)
 hook(original,1);event();assert(effects==2,'retained callback ran after '..boundary)
 lifecycle:stop();assert(cleaned==1)
end
print('Patch ownership, inherited methods, partial failure, nine teardown boundaries and repeat activation passed')
