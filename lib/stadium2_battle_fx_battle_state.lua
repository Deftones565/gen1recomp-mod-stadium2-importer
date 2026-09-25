-- Presentation-only inputs to 841083B0; never reads or changes battle RNG.
local bit=require('bit')
local State={}
local speciesMoves={[10]=true,[15]=true,[22]=true,[154]=true,[163]=true,
  [206]=true,[210]=true,[211]=true,[231]=true,[232]=true}
local variantSpecies={[35]=true,[52]=true,[66]=true,[71]=true,[105]=true,
  [123]=true,[134]=true,[176]=true,[181]=true,[190]=true,[205]=true,
  [209]=true,[212]=true,[217]=true,[248]=true,[250]=true}
local statusContexts={[274]=true,[290]=true,[292]=true,[298]=true,[299]=true}
function State.condition(id,input,current)
  input=input or {};id=bit.tobit(bit.lshift(id or 0,16))/65536
  if speciesMoves[id] then
    if input.ownerSpecies==nil then return nil end
    return variantSpecies[input.ownerSpecies] and 1 or 0
  elseif id==168 or id==217 then
    if input.resultFlags==nil then return nil end
    return bit.band(input.resultFlags,id==168 and 0x20 or 0x40)~=0 and 1 or 0
  elseif id==173 then
    if input.sourceStatus==nil then return nil end
    if bit.band(input.sourceStatus,7)==0 then return 0 end
    if input.resultFlags==nil then return nil end
    return bit.band(input.resultFlags,7)==1 and 1 or 2
  elseif statusContexts[id] then
    if input.ownerStatusPattern==nil then return nil end
    return bit.band(input.ownerStatusPattern,0x2FFF)==0x2AAA and 1 or 0
  end
  return current or 0 -- unhandled IDs leave D_8416A210 untouched
end
return State
