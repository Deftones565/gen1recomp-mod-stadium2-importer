-- 84104A00 / 84104D28. Inputs and results remain in native world units.
local f=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float')
local Anchor={}
local function has(n,m)return math.floor((n or 0)/m)%2==1 end
local function vec(v)return v and {v[1],v[2],v[3]} end
function Anchor.resolve(event,input,saved)
  local flags,flags2=event.flags or 0,event.flags2 or 0
  local diagnostics={}
  local function missing(code,message)
    diagnostics[#diagnostics+1]={code=code,message=message}
  end
  local base=vec(input.position) or {0,0,0}
  local center=input.centerY
  if center==nil then
    center=base[2]
    missing('unresolved-common-center','native actor center height is unavailable')
  end
  local fallback={base[1],has(input.flags,2) and f(center+200)
    or has(input.flags,4) and 0 or center,base[3]}
  if has(flags,8) and not input.contextMarkerResolved and not input.emissionResolved then
    missing('unresolved-common-context-marker','8411E244 context marker selection is unavailable')
  end
  if has(flags2,1) and not input.emissionResolved then
    missing('unsupported-common-all-markers','84107998 emission across all model markers is not implemented')
  elseif input.secondaryMarker and input.secondaryMarker~=255 then
    missing('unsupported-common-secondary-marker','84107998 secondary-marker particle emission is not implemented')
  end
  if event.mode==1 and has(flags,0x800000) then
    missing('unsupported-common-pool-origin','8410668C requires a prior particle-pool origin')
  end
  local anchor
  if input.dynamicAnchorMissing then
    missing('unresolved-dynamic-anchor-read','native anchor table slot has not been written')
  end
  if input.nestedAnchor then anchor=vec(input.nestedAnchor)
  elseif has(flags,1) then
    anchor=vec(input.preparedAnchor)
    if not anchor then missing('unresolved-common-prepared-anchor','84105930 needs the active emitter line');anchor=fallback end
  elseif has(flags,0x1000000) then anchor={0,0,0}
  elseif has(flags,0x4000000) then anchor={-150*(input.lane or 1),0,0}
  elseif has(flags,0x100000) then anchor=fallback
  else
    local label=has(flags,0x200000) and 100 or input.markerLabel
    anchor=input.markers and vec(input.markers[label])
    if not input.markers then
      missing('unresolved-common-model-anchor','posed native model markers are unavailable')
    end
    anchor=anchor or fallback -- 8003C9B8 returns NULL for an absent label.
  end
  local direct=has(flags,1) or input.nestedAnchor~=nil
  if not direct then
    if not has(flags,0x1000000) and not has(flags,0x4000000) then
      if has(flags,0x40000) then anchor[2]=0
      elseif has(flags,0x80000) then
        if input.anchorY~=nil then anchor[2]=input.anchorY
        else missing('unresolved-common-anchor-height','8411EF90 height inputs are unavailable') end
      end
    end
    if has(input.flags,4) and not has(flags2,8) and not has(flags,0x40000) then
      anchor={base[1],math.min(f(base[2]+(input.targetHeight or 0)),30),base[3]}
      if input.targetHeight==nil then missing('unresolved-common-target-height','native target height is unavailable') end
      if has(flags,0x80000) then anchor[2]=0 end
    end
    if has(flags2,0x20) then
      anchor=vec(saved)
      if not anchor then
        missing('unresolved-common-saved-origin','saved native origin has not been supplied')
        anchor=fallback
      end
    end
  end
  return {anchor=anchor,clearCommonOffset=not direct and has(flags2,0x20),
    saveOrigin=has(flags2,0x10),diagnostics=diagnostics}
end
return Anchor
