-- Own direct engine replacements, including raw/inherited fields and sentinels.
-- A later mod may wrap ours: retained gates become pass-through on teardown.
local Scope={};Scope.__index=Scope
function Scope.new() return setmetatable({entries={},active=true},Scope) end
function Scope:capture(targets,install)
 local before={}
 for i,target in ipairs(targets) do
  local snapshot={};before[i]=snapshot
  for key,value in pairs(target) do snapshot[key]=value end
 end
 local ok,err=pcall(install)
 for i,target in ipairs(targets) do
  local snapshot=before[i];local keys={}
  for key in pairs(snapshot) do keys[key]=true end
  for key in pairs(target) do keys[key]=true end
  for key in pairs(keys) do
   local previous=snapshot[key];local replacement=rawget(target,key)
   if replacement~=previous then
    local entry={target=target,key=key,previous=previous,replacement=replacement}
    if type(replacement)=='function' then
     local fallback=previous
     if fallback==nil then
      local mt=getmetatable(target)
      local index=mt and mt.__index
      if type(index)=='table' then fallback=index[key] end
     end
     local gate=function(...)
      if self.active then return replacement(...) end
      if type(fallback)=='function' then return fallback(...) end
     end
     entry.replacement=gate;target[key]=gate
    end
    self.entries[#self.entries+1]=entry
   end
  end
 end
 if not ok then self:restore();error(err,0) end
end
function Scope:restore()
 self.active=false
 for i=#self.entries,1,-1 do
  local e=self.entries[i]
  if rawget(e.target,e.key)==e.replacement then e.target[e.key]=e.previous end
 end
 self.entries={}
end
return Scope
