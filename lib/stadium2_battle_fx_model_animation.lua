-- 84104D28 binds material+2 as a skeletal-animation export for mode 0.
-- 8410491C/4958/49B4 select direction/start; 8003E6DC advances the header.
local Animation={}
local function flag(value,bit)return math.floor((tonumber(value) or 0)/bit)%2==1 end
function Animation.packet(particle,tick)
  local event=particle.event or {}
  local material=event.material or particle.material or {}
  local id=tonumber(material.secondaryShapeId)
  if event.mode~=0 or not id or id<=0 then return nil end
  return {id=id,reverse=flag(event.flags,0x4000),
    startAtEnd=flag(event.flags,0x8000),
    ticks=math.max(0,(tick or particle.age or 0)-(tick and particle.born or 0))}
end
function Animation.frame(anim,state)
  local last=math.max(0,anim.frames-1)
  local first=math.max(0,math.min(last,anim.loopStart or 0))
  local start=(state.reverse or state.startAtEnd) and last or (anim.startFrame or 0)
  local frame=start+(state.reverse and -state.ticks or state.ticks)
  local once=flag(anim.flags,2)
  if state.reverse and frame<first then
    return once and first or last-((first-frame-1)%(last-first+1))
  elseif not state.reverse and frame>last then
    return once and last or first+((frame-last-1)%(last-first+1))
  end
  return frame
end
function Animation.finishesParticle(particle)
  return particle.event and particle.event.mode==0
    and not flag(particle.event.flags,0x2000)
end
function Animation.finished(anim,state)
  -- 8410291C only retires a model on animation completion when header bit 1
  -- is set; reverse playback checks zero, forward playback checks last frame.
  if not flag(anim.flags,2) then return false end
  local frame=Animation.frame(anim,state)
  return state.reverse and frame==0 or not state.reverse and frame>=anim.frames-1
end
return Animation
