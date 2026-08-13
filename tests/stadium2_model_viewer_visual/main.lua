-- Generic entry point.  Keep the old Koffing/Croconaw path as a compatibility
-- fixture because audit scripts and saved launch commands still reference it.
assert(loadfile("mods/STADIUM2_IMPORTER/tests/stadium2_koffing_croconaw_visual/main.lua"))()
