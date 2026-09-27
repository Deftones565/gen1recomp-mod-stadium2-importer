package.path="./?.lua;./?/init.lua;"..package.path
-- Stadium UI assets from the ROM: the texture-set files func_8004C990 reads
-- (UI archive files 30..36), the font (archive D_437750 file 1) and its
-- character map, checked against what the game drew in a captured frame.
local path=os.getenv("STADIUM2_ROM") or arg[1]
  or (io.open("mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb")
    and "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64")
local f=path and io.open(path,"rb")
if not f then
  assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","required Stadium 2 ROM unavailable")
  print("SKIP: Stadium UI ROM test (ROM unavailable)")
  return
end
local Rom=require("mods.STADIUM2_IMPORTER.lib.rom")
local Assets=require("mods.STADIUM2_IMPORTER.lib.stadium_ui_assets")
local rom=assert(Rom.normalise(f:read("*a")))
f:close()
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end

local assets=assert(Assets.fromRom(rom))
local expected={[30]=9,[31]=1,[32]=10,[33]=4,[34]=2,[35]=7,[36]=18}
for file,count in pairs(expected) do
  local n=0 for _ in pairs(assets.sets[file]) do n=n+1 end
  ok(n==count,("UI file %d has %d entries"):format(file,count))
end
local function size(file,entry) local e=assets.sets[file][entry] return e.w.."x"..e.h end
ok(size(31,0)=="64x1","card gradient strip")
ok(size(32,7)=="112x9","digit strip")
ok(size(32,5)=="16x6","HP bar")
ok(size(33,3)=="16x4","frame corner piece")
ok(size(33,0)=="64x14","command tab")
ok(size(36,0)=="32x9","type label")
-- The gradient strip is 0.8 alpha (translucent cards).
local alpha=assets.sets[31][0].rgba:byte(4)
ok(alpha==204,"card strip alpha is 204")
ok(assets.font.count==176,"font has 176 glyphs")
-- The captured message frame drew "PIKACHU's THUNDERBOLT!" with the pen at
-- these x positions (fragment79_3ADCA0 message box, text origin x=36).
local text="PIKACHU's THUNDERBOLT!"
local want={36,41,46,51,56,61,66,71,73,78,82,88,93,98,103,108,113,118,123,128,133,139}
local x=36
for i=1,#text do
  ok(x==want[i],("glyph %d (%s) at x=%d"):format(i,text:sub(i,i),want[i]))
  local glyph=assert(Assets.glyphFor(assets.font,text:byte(i)),"glyph for "..text:sub(i,i))
  x=x+Assets.advance(assets.font,glyph)
end
ok(Assets.glyphFor(assets.font,65)==26 and Assets.glyphFor(assets.font,48)==16,"A and 0 map to their glyphs")
ok(Assets.glyphFor(assets.font,0xE9)==118,"Latin-1 e-acute maps to the font's e-acute (glyph 118)")

-- Small font (font archive file 0) and the move description table.
ok(assets.small and assets.small.count==176 and assets.small.glyphH==10,"small font has 176 16x10 glyphs")
ok(assets.descriptions and assets.descriptions[89]
  and assets.descriptions[89]:find("shaking the ground",1,true)~=nil,"move 89's description is Earthquake's")
ok(assets.descriptions[1]:find("NORMAL-type",1,true)~=nil,"move 1's description is Pound's")
-- The captured move-info frame drew Flame Wheel's (172) first line with the
-- pen at these x positions: small-font advance = width - 1, spaces included.
local line=assets.descriptions[172]:match("^[^\n]+")
local wantSmall={99,105,108,114,120,126,132,138,144,150}
local sx=99
for i=1,#wantSmall do
  ok(sx==wantSmall[i],("small glyph %d at x=%d"):format(i,wantSmall[i]))
  local glyph=assert(Assets.glyphFor(assets.small,line:byte(i)))
  sx=sx+(assets.small.widths[glyph]-1)
end

-- Portrait camera records (func_84113014): 32 bytes per species from ROM
-- 0x4A0EB0; the opponent's mirrors x and yaw unless the record names an
-- authored alternative (Pikachu's 0x188).
local function near(a,b) return math.abs(a-b)<1e-4 end
local pika=assert(Assets.portraitRecord(assets,25,false))
ok(pika.pitch==694 and pika.yaw==-5422 and pika.distance==74 and near(pika.x,1.3)
  and pika.y==15 and pika.frame==10 and pika.alt==0x188,"Pikachu's portrait record")
local pikaFoe=assert(Assets.portraitRecord(assets,25,true))
ok(pikaFoe.pitch==100 and pikaFoe.yaw==5882 and near(pikaFoe.x,-1.2),"the opponent's Pikachu uses the alternative record")
local bulba,bulbaFoe=Assets.portraitRecord(assets,1,false),Assets.portraitRecord(assets,1,true)
ok(bulba.yaw==-6664 and bulbaFoe.yaw==6664 and near(bulbaFoe.x,-bulba.x) and bulbaFoe.y==bulba.y,
  "an opponent without an alternative is mirrored")
ok(Assets.portraitRecord(assets,251,false).distance==108,"Celebi's record is inside the table")

-- YES/NO window constants (fragment 79 data; vaddr -> ROM via the US asm's
-- 0x8413A6D4 <-> 0x3A9F64), checked against stadium_ui.lua's UI.YESNO.
local UI=require("mods.STADIUM2_IMPORTER.lib.stadium_ui")
local function u16(vaddr)
  local o=vaddr-(0x8413A6D4-0x3A9F64)
  local hi,lo=rom:byte(o+1,o+2)
  return hi*256+lo
end
ok(u16(0x84186F98+15)==180*256+180,"fragment 79 data mapping (Rock's type colour)")
ok(u16(0x84186DD8)==UI.YESNO.x and u16(0x84186DDC)==UI.YESNO.y,"YES/NO player position")
ok(u16(0x84186DE0)==UI.YESNO.w and u16(0x84186DE4)==UI.YESNO.h,"YES/NO size")
ok(u16(0x84186DE8)==UI.YESNO.gap and u16(0x84186DEC)==UI.YESNO.slot,"YES/NO option spacing")
ok(u16(0x84186DF0)==UI.YESNO.questionX and u16(0x84186DF4)==UI.YESNO.questionY
  and u16(0x84186DF8)==UI.YESNO.optionY,"YES/NO text offsets")

print(("%d checks passed (Stadium UI ROM assets)"):format(checks))
