package.path="./?.lua;./?/init.lua;"..package.path
-- Body-clip mapping comes from each model's ROM animation descriptor
-- ((species<<16)|1: count at +4, 4-byte entries at +0x0C, file at +2),
-- which 8003F2C4 indexes directly by the dispatch selector.
local Sem=require("mods.STADIUM2_IMPORTER.lib.animation_semantics")
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end
local function be32(n) return string.char(math.floor(n/16777216)%256,math.floor(n/65536)%256,math.floor(n/256)%256,n%256) end
-- A synthetic fragment: descriptor at 0x10, table at 0x40 (Slowpoke's layout).
local base=0x8FF00000
local files={0,0,0,1,2,3,4}
local frag=string.rep("\0",0x10)..be32(79*65536+1)..string.char(#files,0,0,0)..be32(0)..be32(base+0x40)
frag=frag..string.rep("\0",0x40-#frag)
for _,f in ipairs(files) do frag=frag..string.char(0,0,0,f) end
local t=Sem.readSelectorTable(frag,base,79)
ok(t and t.n==7 and t[6]==4 and t[3]==1 and t[0]==0,"reads Slowpoke's selector table")
ok(Sem.readSelectorTable(frag,base,80)==nil,"only the species' own descriptor matches")
-- Apply: selector 6 (hit) reaches clip 4; out-of-range selectors are none.
local anims={} for i=1,5 do anims[i]={} end
local Build={CONTEXTS={"idle","entrance","faint","hit"}}
local rows={n=255}
for r=0,254 do rows[r]={0,-1} end
rows[251]={0,-1};rows[252]={0,-1};rows[253]={5,-1};rows[254]={6,-1};rows[10]={3,-1};rows[20]={9,-1}
local moveRows,contexts=Sem.apply(anims,{},Build,nil,rows,t)
ok(contexts[4]==4 and contexts[3]==3,"hit and faint map through the table")
ok(moveRows[11][1]==1,"a move's selector maps through the table")
ok(moveRows[21][1]==0xFFFF,"a selector past the table is no clip, as in 8003F2C4")
print(("%d checks passed (ROM selector table)"):format(checks))
