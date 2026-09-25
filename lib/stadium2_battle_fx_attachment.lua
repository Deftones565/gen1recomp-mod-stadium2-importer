-- Pure fragment-79 common-particle placement evaluator. The ROM proves
-- low-bit operations and vector addition, not world/battler/camera labels.
local Attachment={}
local function copy(v,s) if type(v)~="table" then return v end s=s or{} if s[v] then return s[v] end local o={} s[v]=o for k,x in pairs(v) do o[copy(k,s)]=copy(x,s) end return o end
local function vector(v) if type(v)~="table" then return nil end local x=tonumber(v.x~=nil and v.x or v[1]);local y=tonumber(v.y~=nil and v.y or v[2]);local z=tonumber(v.z~=nil and v.z or v[3]);if x==nil or y==nil or z==nil then return nil end return{x=x,y=y,z=z,[1]=x,[2]=y,[3]=z} end
local function add(a,b) return vector({a[1]+b[1],a[2]+b[2],a[3]+b[3]}) end
local function cv(c,k) if c[k]~=nil then return c[k] end for _,n in ipairs({"effect","event","particle"}) do if type(c[n])=="table" and c[n][k]~=nil then return c[n][k] end end end
local function diag(c,x,code,msg) return{code=code,severity="warning",effectId=cv(x,"effectId"),programId=cv(x,"programId"),address=cv(x,"address") or c.descriptor,kind="attachment",message=msg} end
local function bad(c,x,code,msg,p) return{resolved=false,position=nil,scale=p and p.scale,diagnostic=diag(c,x,code,msg),partial=copy(p),raw={contract=copy(c),context=copy(x)}} end
local function call(x,name,address,...)
  local r=type(x.resolvers)=="table" and x.resolvers or x; local f=r[name]
  local external=false;if type(f)~="function" and type(r.external)=="function" then f=r.external;external=true end
  if type(f)~="function" then return nil,"missing" end
  local ok,v,e;if external then ok,v,e=pcall(f,address,...) else ok,v,e=pcall(f,...) end
  if not ok then return nil,tostring(v) end return v,e
end
function Attachment.operations(flags)
  flags=tonumber(flags) or 0;local function h(m)return math.floor(flags/m)%2==1 end
  return{placementPreparation=h(1),primaryVisualPolicy=h(2),zeroAnchorY=h(4),externalScaleOffsetY=h(8),anchorCallback=h(0x10),modelAndSavedOrigin=h(0x20),fixedInitialScale=h(0x80),zeroAnchor=h(0x100),laneScalar=h(0x400),secondaryVisualPolicy=h(0x4000)}
end
-- Exact func_84104D28 order: anchor + common offset + transform + motion.
function Attachment.sum(anchor,offset,transform,motion)
  local v={vector(anchor),vector(offset),vector(transform),vector(motion)}
  for _,x in ipairs(v) do if not x then return nil,"placement requires four complete vectors" end end
  return add(add(v[1],v[2]),add(v[3],v[4]))
end
function Attachment.resolve(c,x)
  if type(c)~="table" then return nil,"missing attachment contract" end;if type(x)~="table" then return nil,"missing attachment context" end
  local flags=tonumber(c.flags);if flags==nil then return nil,"attachment contract has no raw flags" end
  local op=Attachment.operations(flags);local p={operations=op,flags=flags,flags2=c.flags2,scale=op.fixedInitialScale and 1 or x.scale}
  if p.scale~=nil and tonumber(p.scale)==nil and not vector(p.scale) then return bad(c,x,"invalid-scale","scale is not scalar or vector",p) end
  local offset=vector(x.commonOffset or{0,0,0});local transform=vector(x.transform or{0,0,0});local motion=vector(x.motion or{0,0,0})
  if not offset or not transform or not motion then return bad(c,x,"invalid-placement-vector","placement offsets must be complete vectors",p) end
  local anchor
  if x.nestedAnchor~=nil then anchor=vector(x.nestedAnchor)
  elseif op.zeroAnchor then anchor=vector({0,0,0})
  elseif op.laneScalar then local v,e=call(x,"laneScalar",0x8411E1D4,copy(x));v=tonumber(v);if not v then return bad(c,x,"unsupported-attachment-external","lane scalar unresolved: "..tostring(e),p) end;anchor=vector({-150*v,0,0})
  elseif op.anchorCallback then local v,e=call(x,"anchor",0x8411DCCC,copy(x));anchor=vector(v);if not anchor then return bad(c,x,"unsupported-attachment-external","anchor callback unresolved: "..tostring(e),p) end
  elseif op.modelAndSavedOrigin then local v,e=call(x,"modelAnchor",0x8003C9B8,copy(x));anchor=vector(v);if not anchor then v,e=call(x,"anchor",0x8411DCCC,copy(x));anchor=vector(v) end;if not anchor then return bad(c,x,"unsupported-attachment-external","model/fallback anchor unresolved: "..tostring(e),p) end
  elseif not op.fixedInitialScale then local shared=vector(x.sharedOrigin);if not shared then return bad(c,x,"unsupported-shared-origin","shared-origin candidate is unresolved",p) end;offset=add(offset,shared);anchor=vector(x.anchor or{0,0,0})
  else local v,e=call(x,"anchor",0x8411DCCC,copy(x));anchor=vector(v);if not anchor then return bad(c,x,"unsupported-attachment-external","base anchor unresolved: "..tostring(e),p) end end
  if not anchor then return bad(c,x,"invalid-anchor","anchor is not a complete vector",p) end
  if op.zeroAnchorY then anchor=vector({anchor[1],0,anchor[3]}) elseif op.externalScaleOffsetY then local v,e=call(x,"anchorY",0x8411EF90,copy(x));v=tonumber(v);if not v then return bad(c,x,"unsupported-attachment-external","anchor Y unresolved: "..tostring(e),p) end;anchor=vector({anchor[1],v,anchor[3]}) end
  if op.modelAndSavedOrigin and x.useSavedOrigin==true then local saved=vector(x.savedOrigin);if not saved then return bad(c,x,"unsupported-saved-origin","saved origin is unresolved",p) end;anchor=saved;offset=vector({0,0,0}) end
  if x.actorTableRequired then local v,e=call(x,"actorTable",0x8411E1F8,copy(anchor),copy(x));anchor=vector(v);if not anchor then return bad(c,x,"unsupported-attachment-external","actor-table tail unresolved: "..tostring(e),p) end end
  local position,e=Attachment.sum(anchor,offset,transform,motion);if not position then return bad(c,x,"invalid-placement-vector",e,p) end
  return{resolved=true,position=position,scale=copy(p.scale),anchor=anchor,commonOffset=offset,transform=transform,motion=motion,operations=op,raw={contract=copy(c),context=copy(x)}}
end
Attachment.anchor=Attachment.resolve;Attachment.resolveAnchor=Attachment.resolve
return Attachment
