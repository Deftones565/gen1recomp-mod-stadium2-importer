# Stadium 2 ROM evidence

The importer targets the US ROM with MD5 `1561c75d11cedf356a8ddb1a4a5f9d5d`.

The current `pret/pokestadiumgs` decomp at commit `c0e10f23d90cc4f335b654711f13e53c2c07323b` identifies `0x437610` as the start of the opaque remainder of the US ROM and `0x4000000` as the end of the ROM.

The retained Stadium GS reverse-engineering notes in `pret/pokestadium`, file `oldnotes/stadiumgs/main.s`, identify `0x27ED000..0x2D7D000` as the Pokémon models table and `0x2D7D000..0x3FD5000` as the Pokémon poses table. These boundaries are therefore treated as sourced layout facts. The species-to-record indexing and the internal pose structures are still subject to ROM audit.

The same notes identify `0x3FD5000..0x3FED000` as another table and describe the data beginning at `0x3FED000` as a file whose prefix appears to contain 253 records of 16 bytes. That region is treated as a species-metadata candidate until its fields and indexing are decoded.

`pret/pokestadium/oldnotes/utils/cattbl.c` defines the archive-table format used by the old extraction work. The header is four big-endian 32-bit words: tag, zero, total size, and record count. The tag is either `0` or `0xEF`. Each record is four big-endian 32-bit words: relative offset, 16-byte-aligned size, zero, zero. Payload offsets and sizes are 16-byte aligned and must remain inside the table total size. `lib/rom.lua` now enforces these invariants.

`pret/pokestadium/tools/decompress_persszp.py` verifies the PERS-SZP wrapper: the first eight bytes are `PERS-SZP`, the big-endian 32-bit value at offset `0x08` is the wrapper header size, and Yay0 data begins at that offset.

A US-ROM audit on the exact supported MD5 confirmed that the model root is a 282-record archive and that records 1, 25, 151, 152, 201, and 251 decode to FRAGMENT species IDs 1, 25, 151, 152, 201, and 251 respectively. Model species indexing is therefore treated as record `N` = species `N`; record 0 is not Bulbasaur. The pose root and post-pose root are also 282-record archives, but pose record identity and internal animation semantics still require independent decoding.

The same exact-ROM audit confirms record 253 is Substitute and model records
254 through 278 carry matching internal IDs 254 through 278. Their parallel
pose records each contain a four-record nested archive. Stadium 2 uses these
25 records for Unown B through Z; the ordinary species-201 record is Unown A.
The importer therefore packages all 26 Gen 2 letters (normal and shiny), not
only the species-table A model. Gen 2 has no `!` or `?` Unown forms; those were
introduced after Stadium 2.

Production extraction now requires the model root exactly at `0x27ED000` and the pose root exactly at `0x2D7D000`, each with exactly 282 records. It does not scan nearby addresses or remap records from embedded species values. Model and pose outer-record indexing uses record `N` for species `N`, and model FRAGMENT species IDs are validated against that record number.

Model geometry command `0x08` contains a handler pointer and an argument pointer. A 251-model US-ROM audit found 13 distinct handler addresses: `0x81000030`, `0x81000038`, `0x81000040`, `0x81000048`, `0x81000050`, `0x81000058`, `0x81000060`, `0x81000068`, `0x81000070`, `0x81000078`, `0x81000080`, `0x81000088`, and `0x81000140`. They are used by 142 models across 551 unique command sites.

The current `pret/pokestadiumgs` US layout maps `fragment26` from ROM `0x15E8B0` at VRAM `0x81000000`. Its `fragment26_unk_table` occupies ROM `0x15E8D0..0x15EA30`, corresponding to VRAM `0x81000020..0x81000180`; the first known executable function is `func_81000180`. Every model handler address above lies inside that table, so the command-`0x08` field is a pointer to a fragment26 descriptor, not directly to executable MIPS code.

The exact US ROM shows that every used descriptor is an eight-byte MIPS jump stub: a `j` instruction followed by a zero delay slot. The 13 used descriptors resolve to `func_810039CC`, `func_81005AC0`, `func_81003A74`, `func_81005DB4`, `func_81003B78`, `func_81003C30`, `func_81003CC0`, `func_81005F38`, `func_81005524`, `func_81003680`, `func_81005F80`, `func_81003DAC`, and `func_810033DC` respectively.

The root function code also establishes distinct lifecycle phases. `func_810033DC` handles phase 5, `func_81005F80` handles phase 0, `func_81003DAC` handles phases 0 and 2, and the remaining ten audited roots handle phase 2. This rules out treating every command-`0x08` site as an animated visual particle callback.

`lib/fragment26.lua` records the mapping, the fragment26 function boundaries present in the current decomp symbol map, the verified lifecycle-phase sets, and a recursive direct-call walker. The dedicated audit recursively fingerprints all reachable fragment26 helpers and fingerprints the model-fragment argument blocks used by the handlers.

The 0.3.6 call-graph audit reached 39 fragment26 functions and 17 external runtime targets. The model-handler roots can now be separated into verified operation families. `0x81000080` is a phase-0 model-context registration hook. `0x81000058` and `0x81000060` are inverse phase-2 visibility gates. The common predicate is `selector == arg[0]` and `arg[2] <= ((global+0x48 >> 16) & 0xFFFF) <= arg[4]`; `0x81000058` writes bit 0 to the predicate result and `0x81000060` writes the inverse. `0x81000030` and `0x81000040` allocate and build display-list wrappers. `0x81000038`, `0x81000048`, `0x81000050`, and `0x81000068` build dynamic N64 material/display-list state. `0x81000070` reaches the libultra `random`, `mtxxfmf`, and `mtxcatl` paths and is classified as a randomized transform emitter. `0x81000140` is a phase-5 render-time geometry pipeline. `0x81000078` and `0x81000088` remain only partially classified as an attribute transform and a runtime-dispatch bridge.

`lib/model_handlers.lua` now compiles these families into a portable `S2HX` v2 trailer on every generated `DSM3` pack. It evaluates the two visibility predicates and phase-0 model-context registration directly, preserves distinct physical command sites, and retains the decoded model FRAGMENT so runtime material, emitter, attribute, dispatch, and phase-5 geometry operations can resolve their original `0x8FF...` data pointers without reopening the ROM. The standalone DSM3 renderer now owns pack decoding, rigid-bone skinning, source-rate skeletal animation, auxiliary texture animation, primitive culling, additive second-pass drawing, embedded texture upload, and verified handler state. The remaining renderer contracts are the exact execution of the dynamic material/emitter families, the two partial handlers, and the phase-5 geometry pipeline. Pose record contents and Stadium 2 battle-animation selection tables remain separate extraction work.
