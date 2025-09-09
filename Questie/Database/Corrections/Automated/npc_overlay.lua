-- Auto-generated (placeholder). Fill via experiments/generate_missing_npc_overlay.py when needed.
local entries = {
}

local function apply_npc_overlay()
  local QL = _G.QuestieLoader
  local QDB = _G.QuestieDB
  if QL and not QDB and QL.ImportModule then
    local ok, mod = pcall(function() return QL:ImportModule("QuestieDB") end)
    if ok then QDB = mod end
  end
  if not QDB or not QDB.npcDataOverrides then return false end
  for id, row in pairs(entries) do
    QDB.npcDataOverrides[id] = row
  end
  return true
end

if not apply_npc_overlay() then
  local f = CreateFrame and CreateFrame("Frame")
  if f and f.RegisterEvent then
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self, event)
      if apply_npc_overlay() then self:UnregisterAllEvents(); self:SetScript("OnEvent", nil) end
    end)
  end
end

