package.path = "./?.lua;./?/init.lua;" .. package.path

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end
local function eq(got, want, message)
  checks = checks + 1
  if got ~= want then
    error(("FAIL %s (got %s, want %s)"):format(message, tostring(got), tostring(want)), 0)
  end
end

package.loaded["mods.STADIUM2_IMPORTER.lib.importer"] = nil
local Importer = require("mods.STADIUM2_IMPORTER.lib.importer")
local status = Importer.status()
local savedLove = _G.love
local savedBeginFrom = Importer.beginFrom

local pickerCalls = 0
local pickerArg = "unset"
local pickedReady = false
local pickedRemoved = false
local focused = true
local selectedBytes, selectedLabel

_G.love = {
  system = {
    getOS = function() return "Android" end,
    pickFile = function(kind)
      pickerCalls = pickerCalls + 1
      pickerArg = kind
      return true
    end,
  },
  filesystem = {
    getInfo = function(path)
      if path == Importer.NATIVE_PICKED and pickedReady then
        return { type="file", size=64 * 1024 * 1024, modtime=2 }
      end
      return nil
    end,
    read = function(path)
      if path == Importer.NATIVE_PICKED and pickedReady then return "stadium2-rom" end
      return nil
    end,
    remove = function(path)
      if path == Importer.NATIVE_PICKED then
        pickedRemoved = true
        pickedReady = false
        return true
      end
      return false
    end,
  },
  window = {
    hasFocus = function() return focused end,
  },
}

ok(Importer.nativePickerAvailable(), "Android exposes the native Stadium 2 picker")
status.state, status.phase, status.error, status.rom = "idle", nil, nil, nil
local row = Importer.row()
ok(type(row.activate) == "function" and row.step == nil,
  "Stadium 2 ROM is an action row, matching Gen1Recomp option-menu activation")
row.activate()
local opened, openErr = status.state == "picking", status.error
ok(opened, openErr or "Android picker opens from the options-row action")
eq(pickerCalls, 1, "options-row action calls the native Android picker once")
eq(pickerArg, nil, "Stadium 2 matches Gen1Recomp 0.1.36 ROM picker no-argument call")
eq(status.state, "picking", "importer remains asynchronous while Android owns the picker")
eq(Importer.row().value(), "PICKING", "options row reports the pending Android picker")

Importer.step()
eq(status.state, "picking", "picker does not fabricate a result before the handoff exists")
focused = false
Importer.step()
eq(status.state, "picking", "losing focus keeps the Android picker pending")
focused = true
Importer.step()
eq(status.state, "idle", "returning without a handoff restores the pre-picker state")

Importer.beginFrom = function(bytes, label)
  selectedBytes, selectedLabel = bytes, label
  status.state = "building"
  status.phase = "scan"
  return true
end
pickerCalls = 0
pickerArg = "unset"
pickedReady = false
pickedRemoved = false
focused = true
opened, openErr = Importer.request()
ok(opened, openErr or "Android picker reopens after cancellation")
eq(pickerCalls, 1, "reopened Android picker is called once")
eq(pickerArg, nil, "reopened picker keeps the release ROM-picker call shape")
pickedReady = true
Importer.step()
eq(selectedBytes, "stadium2-rom", "Android handoff bytes enter the normal Stadium 2 importer")
eq(selectedLabel, "Android file picker", "Android handoff gets a useful ROM source label")
ok(pickedRemoved, "transient picked_rom.gb is removed after the importer accepts it")
eq(status.state, "building", "successful Android selection transitions into extraction")

Importer.beginFrom = savedBeginFrom
_G.love = savedLove

print(("%d checks passed (Stadium 2 Android picker)"):format(checks))
