-- Isolated MIPS III/FPU execution for ROM-authored presentation kernels.
-- No host pointers, I/O, battle RNG, or executable host code are accessible.
local bit=require("bit")
local ffi=require("ffi")
local band,bor,bxor,bs,rs,ars=bit.band,bit.bor,bit.bxor,bit.lshift,bit.rshift,bit.arshift
local cell=ffi.new("union { double d; float f[2]; uint32_t u[2]; }")
local VM={};VM.__index=VM
local function u(v)return v%4294967296 end
local function s(v)return bit.tobit(v) end
local function trunc(v)return v<0 and math.ceil(v) or math.floor(v)end
local function float(v)cell.u[0]=u(v);return tonumber(cell.f[0])end
local function word(v)cell.f[0]=v;return tonumber(cell.u[0])end
function VM.new(images,hooks)
  local self=setmetatable({images=images or {},hooks=hooks or {},memory={},code={},r={},f={},steps=0},VM)
  for i=0,31 do self.r[i]=0;self.f[i]=0 end
  return self
end
function VM:byte(a)
  a=u(a)
  local v=self.memory[a];if v~=nil then return v end
  for _,image in ipairs(self.images) do
    local offset=a-image.base
    if offset>=0 and offset<#image.bytes then return image.bytes:byte(offset+1) end
  end
  if (a>=0x8419F070 and a<0x841B0000) or (a>=0x85000000 and a<0x85800000) then return 0 end
  error(("unmapped native read %08X"):format(a))
end
function VM:read(a,n)
  local v=0;for i=0,n-1 do v=v*256+self:byte(a+i) end;return v
end
function VM:write(a,v,n)
  a=u(a);v=u(v)
  for i=n-1,0,-1 do self.memory[a+i]=v%256;v=math.floor(v/256) end
end
function VM:float(a)return float(self:read(a,4))end
function VM:putFloat(a,v)self:write(a,word(v),4)end
function VM:vector(a)return {self:float(a),self:float(a+4),self:float(a+8)}end
function VM:putVector(a,v)for i=1,3 do self:putFloat(a+(i-1)*4,v[i])end end
function VM:double(i)
  cell.u[0]=u(self.f[i]);cell.u[1]=u(self.f[i+1]);return tonumber(cell.d)
end
function VM:setDouble(i,v)
  cell.d=v;self.f[i]=tonumber(cell.u[0]);self.f[i+1]=tonumber(cell.u[1])
end
function VM:call(address,args,limit)
  local r,F=self.r,self.f
  r[29]=s(0x857FF000);r[31]=0
  for i,v in ipairs(args or {})do r[i+3]=s(v)end
  local pc,nextpc=u(address),u(address+4)
  for step=1,limit or 2000000 do
    self.steps=self.steps+1
    if pc==0 then return r[2] end
    local hook=self.hooks[pc]
    if hook then
      hook(self);pc=u(r[31]);nextpc=u(pc+4)
    else
      local w=self.code[pc]
      if not w then w=self:read(pc,4);self.code[pc]=w end
      local op=rs(w,26);local a=band(rs(w,21),31);local b=band(rs(w,16),31)
      local c=band(rs(w,11),31);local sh=band(rs(w,6),31);local fn=band(w,63)
      local imm=band(w,65535);local si=imm>=32768 and imm-65536 or imm
      local dest=u(nextpc+4)
      local function branch(yes,likely)
        if yes then dest=u(pc+4+si*4) elseif likely then nextpc=u(nextpc+4);dest=u(nextpc+4) end
      end
      if op==0 then
        if fn==0 then r[c]=bs(r[b],sh)
        elseif fn==2 then r[c]=s(rs(r[b],sh))
        elseif fn==3 then r[c]=ars(r[b],sh)
        elseif fn==4 then r[c]=bs(r[b],band(r[a],31))
        elseif fn==6 then r[c]=s(rs(r[b],band(r[a],31)))
        elseif fn==7 then r[c]=ars(r[b],band(r[a],31))
        elseif fn==8 or fn==9 then dest=u(r[a]);if fn==9 then r[c]=s(pc+8)end
        elseif fn==16 then r[c]=self.hi or 0
        elseif fn==18 then r[c]=self.lo or 0
        elseif fn==24 or fn==25 then
          local x,y=u(r[a]),u(r[b]);local xl,yl=x%65536,y%65536
          local cross=math.floor(x/65536)*yl+math.floor(y/65536)*xl+math.floor(xl*yl/65536)
          self.lo=s((cross%65536)*65536+(xl*yl)%65536)
          local high=math.floor(x/65536)*math.floor(y/65536)+math.floor(cross/65536)
          if fn==24 then if r[a]<0 then high=high-y end;if r[b]<0 then high=high-x end end
          self.hi=s(high)
        elseif fn==26 or fn==27 then
          local x,y=r[a],r[b];if fn==27 then x,y=u(x),u(y)end
          assert(y~=0,"native division by zero");local q=trunc(x/y)
          self.lo=s(q);self.hi=s(x-q*y)
        elseif fn==32 or fn==33 then r[c]=s(r[a]+r[b])
        elseif fn==34 or fn==35 then r[c]=s(r[a]-r[b])
        elseif fn==36 then r[c]=band(r[a],r[b])
        elseif fn==37 then r[c]=bor(r[a],r[b])
        elseif fn==38 then r[c]=bxor(r[a],r[b])
        elseif fn==39 then r[c]=bit.bnot(bor(r[a],r[b]))
        elseif fn==42 then r[c]=r[a]<r[b] and 1 or 0
        elseif fn==43 then r[c]=u(r[a])<u(r[b]) and 1 or 0
        else error(("unsupported MIPS special %02X at %08X"):format(fn,pc))end
      elseif op==1 then
        if b>=16 then r[31]=s(pc+8)end
        local positive=b%2==1
        branch(positive and r[a]>=0 or not positive and r[a]<0,band(b,2)~=0)
      elseif op==2 or op==3 then
        dest=bor(band(pc+4,0xF0000000),bs(band(w,0x3FFFFFF),2));dest=u(dest)
        if op==3 then r[31]=s(pc+8)end
      elseif op==4 or op==20 then branch(r[a]==r[b],op==20)
      elseif op==5 or op==21 then branch(r[a]~=r[b],op==21)
      elseif op==6 or op==22 then branch(r[a]<=0,op==22)
      elseif op==7 or op==23 then branch(r[a]>0,op==23)
      elseif op==8 or op==9 then r[b]=s(r[a]+si)
      elseif op==10 then r[b]=r[a]<si and 1 or 0
      elseif op==11 then r[b]=u(r[a])<u(si) and 1 or 0
      elseif op==12 then r[b]=band(r[a],imm)
      elseif op==13 then r[b]=bor(r[a],imm)
      elseif op==14 then r[b]=bxor(r[a],imm)
      elseif op==15 then r[b]=bs(imm,16)
      elseif op==17 then
        if a==0 then r[b]=s(F[c])
        elseif a==4 then F[c]=u(r[b])
        elseif a==2 then r[b]=self.fcsr or 0
        elseif a==6 then self.fcsr=r[b]
        elseif a==8 then branch((b%2==1)==(self.condition==true),band(b,2)~=0)
        else
          local x=a==17 and self:double(c) or a==20 and s(F[c]) or float(F[c])
          local y=a==17 and self:double(b) or float(F[b]);local v
          if fn==0 then v=x+y elseif fn==1 then v=x-y elseif fn==2 then v=x*y
          elseif fn==3 then v=x/y elseif fn==4 then v=math.sqrt(x)
          elseif fn==5 then v=math.abs(x) elseif fn==6 then v=x elseif fn==7 then v=-x
          elseif fn==32 then F[sh]=word(x)
          elseif fn==33 then self:setDouble(sh,x)
          elseif fn==13 then F[sh]=u(trunc(x))
          elseif fn==12 or fn==36 then
            local low=math.floor(x);local frac=x-low
            F[sh]=u(frac>.5 or (frac==.5 and low%2~=0) and low+1 or low)
          elseif fn>=48 then
            self.condition=(band(fn,4)~=0 and x<y) or (band(fn,2)~=0 and x==y)
              or (band(fn,1)~=0 and (x~=x or y~=y))
          else error(("unsupported FPU %02X at %08X"):format(fn,pc))end
          if v~=nil then if a==17 then self:setDouble(sh,v)else F[sh]=word(v)end end
        end
      elseif op==32 or op==33 or op==35 or op==36 or op==37 then
        local n=(op==32 or op==36) and 1 or (op==33 or op==37) and 2 or 4
        local v=self:read(u(r[a]+si),n)
        if (op==32 or op==33) and v>=2^(n*8-1)then v=v-2^(n*8)end
        r[b]=s(v)
      elseif op==40 or op==41 or op==43 then self:write(r[a]+si,r[b],op==40 and 1 or op==41 and 2 or 4)
      elseif op==49 then F[b]=self:read(u(r[a]+si),4)
      elseif op==57 then self:write(r[a]+si,F[b],4)
      elseif op==53 then local at=u(r[a]+si);F[b+1]=self:read(at,4);F[b]=self:read(at+4,4)
      elseif op==61 then local at=u(r[a]+si);self:write(at,F[b+1],4);self:write(at+4,F[b],4)
      elseif op==34 or op==38 or op==42 or op==46 then
        local at=u(r[a]+si);local base=at-at%4;local left=op==34 or op==42
        local first,last=left and at%4 or 0,left and 3 or at%4
        for i=first,last do
          local lane=left and i-at%4 or 3-at%4+i
          local shift=(3-lane)*8
          if op==34 or op==38 then
            r[b]=bor(band(r[b],bit.bnot(bs(255,shift))),bs(self:byte(base+i),shift))
          else self:write(base+i,band(rs(r[b],shift),255),1)end
        end
      else error(("unsupported MIPS opcode %02X at %08X"):format(op,pc))end
      r[0]=0;pc,nextpc=nextpc,dest
    end
  end
  error(("native instruction budget exceeded at %08X"):format(pc))
end
VM.floatWord=word
return VM
