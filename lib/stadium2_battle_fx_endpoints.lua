-- Native endpoint rules: 84109780 (source), 841098FC (target),
-- 8411DCCC (missing source marker), and 84109630 (signed offsets).
-- Positions and the rotation matrix are already in the caller's native frame.
local Endpoints={}
local function flag(value,mask) return math.floor((value or 0)/mask)%2==1 end
function Endpoints.resolve(actor,target)
  local p=actor.position
  local marker=actor.marker
  local out={marker and marker[1] or p[1],0,marker and marker[3] or p[3]}
  if target then
    out[2]=p[2]+actor.targetHeight
  elseif marker then
    out[2]=marker[2]
  elseif flag(actor.flags,2) then
    out[2]=actor.centerY+200
  elseif flag(actor.flags,4) then
    out[2]=0
  else
    out[2]=actor.centerY
  end
  local offset=actor.offset or {0,0,0}
  local r=actor.rotation or {1,0,0,0,1,0,0,0,1}
  for i=1,3 do
    local j=(i-1)*3
    out[i]=out[i]+r[j+1]*offset[1]+r[j+2]*offset[2]+r[j+3]*offset[3]
  end
  if target then
    if flag(actor.flags,4) then out[3]=0;out[2]=math.min(out[2],30) end
    out[2]=math.max(0,math.min(out[2],200))
  end
  return out
end
return Endpoints
