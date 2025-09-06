---@class AvailableQuests
local AvailableQuests = QuestieLoader:CreateModule("AvailableQuests")

---@type ThreadLib
local ThreadLib = QuestieLoader:ImportModule("ThreadLib")
---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
---@type ZoneDB
local ZoneDB = QuestieLoader:ImportModule("ZoneDB")
---@type QuestiePlayer
local QuestiePlayer = QuestieLoader:ImportModule("QuestiePlayer")
---@type QuestieMap
local QuestieMap = QuestieLoader:ImportModule("QuestieMap")
---@type QuestieTooltips
local QuestieTooltips = QuestieLoader:ImportModule("QuestieTooltips")
---@type QuestieCorrections
local QuestieCorrections = QuestieLoader:ImportModule("QuestieCorrections")
---@type QuestieQuestBlacklist
local QuestieQuestBlacklist = QuestieLoader:ImportModule("QuestieQuestBlacklist")
---@type IsleOfQuelDanas
local IsleOfQuelDanas = QuestieLoader:ImportModule("IsleOfQuelDanas")
---@type QuestieLib
local QuestieLib = QuestieLoader:ImportModule("QuestieLib")

local GetQuestGreenRange = GetQuestGreenRange
local yield = coroutine.yield
local tinsert = table.insert
local NewThread = ThreadLib.ThreadSimple
local bitband = bit.band

local QUESTS_PER_YIELD = 24

--- Used to keep track of the active timer for CalculateAndDrawAll
---@type Ticker|nil
local timer

-- Keep track of all available quests to unload undoable when abandoning a quest
local availableQuests = {}

local dungeons = ZoneDB:GetDungeons()

local _CalculateAvailableQuests, _DrawChildQuests, _AddStarter, _DrawAvailableQuest, _GetQuestIcon, _GetIconScaleForAvailable, _HasProperDistanceToAlreadyAddedSpawns, _HasMinimumViableData

---@param callback function | nil
function AvailableQuests.CalculateAndDrawAll(callback)
    Questie:Debug(Questie.DEBUG_INFO, "[AvailableQuests.CalculateAndDrawAll]")

    --? Cancel the previously running timer to not have multiple running at the same time
    if timer then
        timer:Cancel()
    end
    timer = ThreadLib.Thread(_CalculateAvailableQuests, 0, "Error in AvailableQuests.CalculateAndDrawAll", callback)
end

--Draw a single available quest, it is used by the CalculateAndDrawAll function.
---@param quest Quest
function AvailableQuests.DrawAvailableQuest(quest) -- prevent recursion
    -- The actual visibility check happens in QuestieFrame:ShouldBeHidden()
    -- which properly checks enableAvailableWorldMap and enableAvailableMinimap
    -- This early return is just for performance when ALL available quest settings are disabled
    if not Questie.db.profile.enableAvailable and 
       not Questie.db.profile.enableAvailableWorldMap and 
       not Questie.db.profile.enableAvailableMinimap then
        return
    end
    
    --? Some quests can be started by both an NPC and a GameObject
    Questie:Debug(Questie.DEBUG_INFO, "[DrawAvailableQuest] Drawing quest " .. quest.Id)
    

    if quest.Starts["GameObject"] then
        local gameObjects = quest.Starts["GameObject"]
        if type(gameObjects) ~= "table" then
            gameObjects = {gameObjects}  -- Convert single ID to table
        end
        for i = 1, #gameObjects do
            local obj = QuestieDB:GetObject(gameObjects[i])
            if obj then
                _AddStarter(obj, quest, "o_" .. obj.id)
            else
                Questie:Debug(Questie.DEBUG_DEVELOP, "[AvailableQuests] Missing GameObject data for ID:", gameObjects[i], "in quest", quest.Id)
            end
        end
    end
    if (quest.Starts["NPC"]) then
        local npcs = quest.Starts["NPC"]
        if type(npcs) ~= "table" then
            npcs = {npcs}  -- Convert single ID to table
        end
        for i = 1, #npcs do
            local npc = QuestieDB:GetNPC(npcs[i])
            if npc then
                _AddStarter(npc, quest, "m_" .. npc.id)
            else
                Questie:Debug(Questie.DEBUG_DEVELOP, "[AvailableQuests] Missing NPC data for ID:", npcs[i], "in quest", quest.Id)
            end
        end
    end
end

function AvailableQuests.UnloadUndoable()
    for questId, _ in pairs(availableQuests) do
        if (not QuestieDB.IsDoable(questId)) then
            QuestieMap:UnloadQuestFrames(questId)
        end
    end
end

_CalculateAvailableQuests = function()
    -- Localize the variables for speeeeed
    local debugEnabled = Questie.db.profile.debugEnabled

    local questData = QuestieDB.QuestPointers or QuestieDB.questData
    
    -- Debug: Check if we have quest data
    if not questData then
        Questie:Print("|cFFFF0000[ERROR] No quest data available! QuestPointers and questData are both nil!|r")
        return
    end
    
    -- Debug: Count available quests
    local questCount = 0
    for _ in pairs(questData) do
        questCount = questCount + 1
    end
    Questie:Debug(Questie.DEBUG_INFO, "[AvailableQuests] Found " .. questCount .. " quests in database")

    local playerLevel = QuestiePlayer.GetPlayerLevel()
    local minLevel = playerLevel - GetQuestGreenRange("player")
    local maxLevel = playerLevel
    
    -- With "Show only quests granting experience" setting, allow higher level quests
    -- Originally was +4, but increasing to +6 to show more quests (especially for Epoch content)
    if Questie.db.profile.lowLevelStyle == Questie.LOWLEVEL_NONE then
        maxLevel = playerLevel + 6
    end

    if Questie.db.profile.lowLevelStyle == Questie.LOWLEVEL_RANGE then
        minLevel = Questie.db.profile.minLevelFilter
        maxLevel = Questie.db.profile.maxLevelFilter
    elseif Questie.db.profile.lowLevelStyle == Questie.LOWLEVEL_OFFSET then
        minLevel = playerLevel - Questie.db.profile.manualLevelOffset
    end

    local completedQuests = Questie.db.char.complete
    local showRepeatableQuests = Questie.db.profile.showRepeatableQuests
    local showDungeonQuests = Questie.db.profile.showDungeonQuests
    local showRaidQuests = Questie.db.profile.showRaidQuests
    local showPvPQuests = Questie.db.profile.showPvPQuests
    local showAQWarEffortQuests = Questie.db.profile.showAQWarEffortQuests

    local autoBlacklist = QuestieDB.autoBlacklist
    local hiddenQuests = QuestieCorrections.hiddenQuests
    local hidden = Questie.db.char.hidden

    local currentQuestlog = QuestiePlayer.currentQuestlog
    local currentIsleOfQuelDanasQuests = IsleOfQuelDanas.quests[Questie.db.profile.isleOfQuelDanasPhase] or {}
    local aqWarEffortQuests = QuestieQuestBlacklist.AQWarEffortQuests

    QuestieDB.activeChildQuests = {} -- Reset here so we don't need to keep track in the quest event system
    local activeChildQuests = QuestieDB.activeChildQuests

    -- We create a local function here to improve readability but use the localized variables above.
    -- The order of checks is important here to bring the speed to a max
    local function _DrawQuestIfAvailable(questId)
        
        if (autoBlacklist[questId] or       -- Don't show autoBlacklist quests marked as such by IsDoable
            completedQuests[questId] or     -- Don't show completed quests
            hiddenQuests[questId] or        -- Don't show blacklisted quests
            hidden[questId] or              -- Don't show quests hidden by the player
            activeChildQuests[questId]      -- We already drew this quest in a previous loop iteration
        ) then
            return
        end
        
        
        -- DISABLED: This was preventing ALL quests from showing after finding one placeholder
        -- -- Don't show placeholder Epoch quests with "[Epoch] Quest XXXXX" names on the map
        -- -- Also hide Epoch quests with missing or incorrect level data
        -- local questName = QuestieDB.QueryQuestSingle(questId, "name")
        -- if questName and string.find(questName, "^%[Epoch%] Quest %d+$") then
        --     return
        -- end
        
        -- TEMPORARILY DISABLED: Special Epoch quest filtering was preventing ALL quests from showing
        -- This needs to be reworked to not interfere with normal quest display
        -- -- Fix Epoch quests (26000+) with missing/incorrect requiredLevel data
        -- if questId >= 26000 then
        --     local requiredLevel = QuestieDB.QueryQuestSingle(questId, "requiredLevel")
        --     local questLevel = QuestieDB.QueryQuestSingle(questId, "questLevel")
        --     
        --     -- If requiredLevel is missing/0, use questLevel for filtering
        --     if not requiredLevel or requiredLevel == 0 then
        --         requiredLevel = questLevel or 1
        --     end
        --     
        --     -- Apply level filtering based on current settings
        --     -- Be more lenient with Epoch quests since many have placeholder/incorrect level data
        --     if Questie.db.profile.lowLevelStyle == Questie.LOWLEVEL_NONE then
        --         -- For Epoch quests, allow a wider range since level data may be incorrect
        --         -- Allow up to +10 levels for Epoch quests instead of +4
        --         if requiredLevel > (playerLevel + 10) then
        --             return
        --         end
        --     elseif Questie.db.profile.lowLevelStyle ~= Questie.LOWLEVEL_ALL then
        --         -- For other filtering modes, be more lenient with Epoch quests
        --         -- Add 6 levels to the max threshold for Epoch quests
        --         local epochMaxLevel = maxLevel + 6
        --         if requiredLevel > epochMaxLevel or (questLevel and questLevel > epochMaxLevel) then
        --             return
        --         end
        --     end
        -- end

        if currentQuestlog[questId] then
            _DrawChildQuests(questId, currentQuestlog, completedQuests)

            if QuestieDB.IsComplete(questId) ~= -1 then -- The quest in the quest log is not failed, so we don't show it as available
                return
            end
        end

        if (
            ((not showRepeatableQuests) and QuestieDB.IsRepeatable(questId)) or     -- Don't show repeatable quests if option is disabled
            ((not showPvPQuests) and QuestieDB.IsPvPQuest(questId)) or              -- Don't show PvP quests if option is disabled
            ((not showDungeonQuests) and QuestieDB.IsDungeonQuest(questId)) or      -- Don't show dungeon quests if option is disabled
            ((not showRaidQuests) and QuestieDB.IsRaidQuest(questId)) or            -- Don't show raid quests if option is disabled
            ((not showAQWarEffortQuests) and aqWarEffortQuests[questId]) or         -- Don't show AQ War Effort quests if the option disabled
            (Questie.IsClassic and currentIsleOfQuelDanasQuests[questId]) or        -- Don't show Isle of Quel'Danas quests for Era/HC/SoX
            (Questie.IsSoD and QuestieDB.IsRuneAndShouldBeHidden(questId))          -- Don't show SoD Rune quests with the option disabled
        ) then
            return
        end

        -- Check level requirements first
        local levelOk = QuestieDB.IsLevelRequirementsFulfilled(questId, minLevel, maxLevel, playerLevel)
        local isDoableResult = QuestieDB.IsDoable(questId, debugEnabled)
        local hasMinViableData = _HasMinimumViableData(questId)
        
        if (
            (not levelOk) or
            (not isDoableResult and not hasMinViableData)
        ) then
            --If the quests are not within level range we want to unload them
            --(This is for when people level up or change settings etc)
            

            if availableQuests[questId] then
                QuestieMap:UnloadQuestFrames(questId)
                QuestieTooltips:RemoveQuest(questId)
            end
            return
        end
        

        availableQuests[questId] = true

        if QuestieMap.questIdFrames[questId] then
            -- We already drew this quest so we might need to update the icon (config changed/level up)
            for _, frame in ipairs(QuestieMap:GetFramesForQuest(questId)) do
                if frame and frame.data and frame.data.QuestData then
                    local newIcon = _GetQuestIcon(frame.data.QuestData)

                    if newIcon ~= frame.data.Icon then
                        frame:UpdateTexture(Questie.usedIcons[newIcon])
                    end
                end
            end
            return
        end

        _DrawAvailableQuest(questId)
    end

    local questCount = 0
    local drawnCount = 0
    
    for questId in pairs(questData) do
        local wasDrawn = availableQuests[questId] or false
        _DrawQuestIfAvailable(questId)
        if not wasDrawn and availableQuests[questId] then
            drawnCount = drawnCount + 1
        end

        -- Reset the questCount
        questCount = questCount + 1
        if questCount > QUESTS_PER_YIELD then
            questCount = 0
            yield()
        end
    end
end

--- Mark all child quests as active when the parent quest is in the quest log
---@param questId number
---@param currentQuestlog table<number, boolean>
---@param completedQuests table<number, boolean>
_DrawChildQuests = function(questId, currentQuestlog, completedQuests)
    local childQuests = QuestieDB.QueryQuestSingle(questId, "childQuests")
    if (not childQuests) then
        return
    end

    for _, childQuestId in pairs(childQuests) do
        if (not completedQuests[childQuestId]) and (not currentQuestlog[childQuestId]) then
            local childQuestExclusiveTo = QuestieDB.QueryQuestSingle(childQuestId, "exclusiveTo")
            local blockedByExclusiveTo = false
            for _, exclusiveToQuestId in pairs(childQuestExclusiveTo or {}) do
                if QuestiePlayer.currentQuestlog[exclusiveToQuestId] or completedQuests[exclusiveToQuestId] then
                    blockedByExclusiveTo = true
                    break
                end
            end
            if (not blockedByExclusiveTo) then
                QuestieDB.activeChildQuests[childQuestId] = true
                availableQuests[childQuestId] = true
                -- Draw them right away and skip all other irrelevant checks
                _DrawAvailableQuest(childQuestId)
            end
        end
    end
end

---@param questId number
_DrawAvailableQuest = function(questId)
    NewThread(function()
        local quest = QuestieDB.GetQuest(questId)
        if (not quest.tagInfoWasCached) then
            QuestieDB.GetQuestTagInfo(questId) -- cache to load in the tooltip

            quest.tagInfoWasCached = true
        end

        AvailableQuests.DrawAvailableQuest(quest)
    end, 0)
end

---@param quest Quest
_GetQuestIcon = function(quest)
    if Questie.IsSoD == true and QuestieDB.IsSoDRuneQuest(quest.Id) then
        return Questie.ICON_TYPE_SODRUNE
    elseif QuestieDB.IsActiveEventQuest(quest.Id) then
        return Questie.ICON_TYPE_EVENTQUEST
    end
    if QuestieDB.IsPvPQuest(quest.Id) then
        return Questie.ICON_TYPE_PVPQUEST
    end
    -- Only show gray if quest is truly unavailable (more than 5 levels above player)
    -- This allows orange/red quests to show as yellow icons
    if quest.requiredLevel and quest.requiredLevel > (QuestiePlayer.GetPlayerLevel() + 5) then
        return Questie.ICON_TYPE_AVAILABLE_GRAY
    end
    if quest.IsRepeatable then
        -- Extra validation for Epoch quests (GitHub #90)
        -- Only show repeatable icon if we're certain it's actually repeatable
        if quest.Id >= 26000 and quest.specialFlags and bitband(quest.specialFlags, 1) == 0 then
            -- Epoch quest incorrectly marked as repeatable, skip the repeatable icon
            Questie:Debug(Questie.DEBUG_INFO, "[REPEATABLE FIX] Available quest " .. quest.Id .. " was marked repeatable but specialFlags=" .. (quest.specialFlags or "nil"))
            -- Don't return repeatable icon, let it fall through to check trivial/normal
        else
            return Questie.ICON_TYPE_REPEATABLE
        end
    end
    if (QuestieDB.IsTrivial(quest.level)) then
        return Questie.ICON_TYPE_AVAILABLE_GRAY
    end
    return Questie.ICON_TYPE_AVAILABLE
end

---@param starter table Either an object or an NPC
---@param quest Quest
---@param tooltipKey string the tooltip key. For objects it's "o_<ID>", for NPCs it's "m_<ID>"
_AddStarter = function(starter, quest, tooltipKey)
    if (not starter) then
        return
    end

    QuestieTooltips:RegisterQuestStartTooltip(quest.Id, starter.name, starter.id, tooltipKey)

    local starterIcons = {}
    local starterLocs = {}
    for zone, spawns in pairs(starter.spawns or {}) do
        local alreadyAddedSpawns = {}
        if (zone and spawns) then
            local coords
            for spawnIndex = 1, #spawns do
                coords = spawns[spawnIndex]
                if #spawns == 1 or _HasProperDistanceToAlreadyAddedSpawns(coords, alreadyAddedSpawns) then
                    local data = {
                        Id = quest.Id,
                        Icon = _GetQuestIcon(quest),
                        GetIconScale = _GetIconScaleForAvailable,
                        IconScale = _GetIconScaleForAvailable(),
                        Type = "available",
                        QuestData = quest,
                        Name = starter.name,
                        IsObjectiveNote = false,
                        Priority = 50,  -- Lower priority than complete quests (100)
                    }

                    if (coords[1] == -1 or coords[2] == -1) then
                        local dungeonLocation = ZoneDB:GetDungeonLocation(zone)
                        if dungeonLocation then
                            for _, value in ipairs(dungeonLocation) do
                                QuestieMap:DrawWorldIcon(data, value[1], value[2], value[3])
                            end
                        end
                    else
                        local icon = QuestieMap:DrawWorldIcon(data, zone, coords[1], coords[2])
                        if starter.waypoints then
                            -- This is only relevant for waypoint drawing
                            starterIcons[zone] = icon
                            if not starterLocs[zone] then
                                starterLocs[zone] = { coords[1], coords[2] }
                            end
                        end
                        tinsert(alreadyAddedSpawns, coords)
                    end
                end
            end
        end
    end

    -- Only for NPCs since objects do not move
    if starter.waypoints then
        for zone, waypoints in pairs(starter.waypoints or {}) do
            if not dungeons[zone] and waypoints[1] and waypoints[1][1] and waypoints[1][1][1] then
                if not starterIcons[zone] then
                    local data = {
                        Id = quest.Id,
                        Icon = _GetQuestIcon(quest),
                        GetIconScale = _GetIconScaleForAvailable,
                        IconScale = _GetIconScaleForAvailable(),
                        Type = "available",
                        QuestData = quest,
                        Name = starter.name,
                        IsObjectiveNote = false,
                        Priority = 50,  -- Lower priority than complete quests (100)
                    }
                    starterIcons[zone] = QuestieMap:DrawWorldIcon(data, zone, waypoints[1][1][1], waypoints[1][1][2])
                    starterLocs[zone] = { waypoints[1][1][1], waypoints[1][1][2] }
                end
                QuestieMap:DrawWaypoints(starterIcons[zone], waypoints, zone)
            end
        end
    end
end

_HasProperDistanceToAlreadyAddedSpawns = function(coords, alreadyAddedSpawns)
    for _, alreadyAdded in pairs(alreadyAddedSpawns) do
        local distance = QuestieLib.GetSpawnDistance(alreadyAdded, coords)
        -- 29 seems like a good distance. The "Undying Laborer" in Westfall shows both spawns for the "Horn of Lordaeron" rune
        if distance < 29 then
            return false
        end
    end
    return true
end

_GetIconScaleForAvailable = function()
    return Questie.db.profile.availableScale or 1.3
end

--- Check if quest has minimum viable data for display even if not fully doable
--- Requirements: quest name, quest ID, quest giver NPC ID, NPC location in database
---@param questId number
---@return boolean
_HasMinimumViableData = function(questId)
    local quest = QuestieDB.GetQuest(questId)
    if not quest then
        return false
    end
    
    -- Must have a real quest name (not a runtime stub)
    if not quest.name or string.find(quest.name, "%[Epoch%]") then
        return false
    end
    
    -- Must have quest giver NPC
    local questGiver = quest.startedBy and quest.startedBy[1] and quest.startedBy[1][1]
    if not questGiver then
        return false
    end
    
    -- NPC must exist in database
    local npc = QuestieDB.GetNPC(questGiver)
    if not npc then
        return false
    end
    
    -- NPC must have spawn locations
    if not npc.spawns then
        return false
    end
    
    -- Check if NPC has valid spawn coordinates in at least one zone
    for zone, spawns in pairs(npc.spawns) do
        if spawns and #spawns > 0 then
            for _, coords in ipairs(spawns) do
                if coords[1] and coords[2] and coords[1] > 0 and coords[2] > 0 then
                    return true  -- Found valid coordinates
                end
            end
        end
    end
    
    return false  -- No valid spawn coordinates found
end
