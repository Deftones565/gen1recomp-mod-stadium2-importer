-- Round each authored single-precision operation on both Lua and LuaJIT.
local ok, ffi=pcall(require,"ffi")
local cell=ok and ffi.new("float[1]") or nil
return function(value)
  if string.pack and string.unpack then
    return (string.unpack("<f",string.pack("<f",value)))
  end
  if cell then cell[0]=value;return tonumber(cell[0]) end
  -- Portable IEEE-754 binary32 fallback (round to nearest, ties to even).
  if value==0 or value~=value or math.abs(value)==math.huge then return value end
  local sign=value<0 and -1 or 1
  local mantissa,exponent=math.frexp(math.abs(value))
  local unit=2^math.max(exponent-24,-149)
  local scaled=math.abs(value)/unit
  local low=math.floor(scaled)
  if scaled-low>0.5 or (scaled-low==0.5 and low%2==1) then low=low+1 end
  local result=low*unit
  if result>=2^128 then result=math.huge end
  return sign*result
end
