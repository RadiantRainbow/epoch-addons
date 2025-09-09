-- Auto-generated Epoch-only overlay (validated)
local entries = {
[27419] = {"Boom! Boom! Boom!",{{46195},nil,nil},{{3516},nil},44,44,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,1446,nil,nil,nil,nil,nil,0,0,nil,nil,nil,nil,nil,nil},
[27253] = {"Massive Profits",{{11438},nil,nil},{{11438},nil},39,39,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,1443,nil,nil,nil,nil,nil,0,0,nil,nil,nil,nil,nil,nil},
[27197] = {"The Merchant's Daughter",{{7161},nil,nil},{{7161},nil},17,17,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,1413,nil,nil,nil,nil,nil,0,0,nil,nil,nil,nil,nil,nil},
[27485] = {"Herbal Medicine",{{3604},nil,nil},{{3604},nil},8,8,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,141, nil,nil,nil,nil,nil,0,0,nil,nil,nil,nil,nil,nil},
}

local function apply_quest_overlay()
  local QL = _G.QuestieLoader
  local QDB = _G.QuestieDB
  if QL and not QDB and QL.ImportModule then
    local ok, mod = pcall(function() return QL:ImportModule("QuestieDB") end)
    if ok then QDB = mod end
  end
  if not QDB or not QDB.questDataOverrides then return false end
  for id, row in pairs(entries) do
    QDB.questDataOverrides[id] = row
  end
  return true
end

if not apply_quest_overlay() then
  local f = CreateFrame and CreateFrame("Frame")
  if f and f.RegisterEvent then
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self, event)
      if apply_quest_overlay() then self:UnregisterAllEvents(); self:SetScript("OnEvent", nil) end
    end)
  end
end

if QuestieCompat and QuestieCompat.RegisterBlacklist then
  QuestieCompat.RegisterBlacklist("hiddenQuests", function()
    local unhide = {}
    for id, _ in pairs(entries) do unhide[id] = false end
    return unhide
  end)
end

