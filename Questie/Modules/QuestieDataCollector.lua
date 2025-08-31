---@class QuestieDataCollector
local QuestieDataCollector = QuestieLoader:CreateModule("QuestieDataCollector")

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
---@type QuestieLib
local QuestieLib = QuestieLoader:ImportModule("QuestieLib")

-- Compatibility reassignments (following codebase pattern)
local C_Timer = QuestieCompat.C_Timer

-- SavedVariables table for collected data
-- This will be initialized after ADDON_LOADED event

local _activeTracking = {} -- Currently tracking these quest IDs
local _lastQuestGiver = nil -- Store last NPC interacted with
local _questAcceptCoords = {} -- Store coordinates when accepting quests
local _originalTooltipSettings = nil -- Store original tooltip settings for restoration
local _recentKills = {} -- Store recent combat kills for objective correlation
local _initialized = false -- Track if we've initialized
local _currentLootSource = nil -- Track what we're currently looting from
local _lastInteractedObject = nil -- Track last object we moused over
local _trackAllEpochQuests = true -- Track all Epoch quests (26xxx range) by default

-- Forward declaration of helper function for creating clickable quest data links
local CreateQuestDataLink

-- Helper function for debug messages
local function DebugMessage(msg, r, g, b)
    -- Check if this is a [DEBUG] or [DataCollector Debug] message
    if string.find(msg, "%[DEBUG%]") or string.find(msg, "%[DataCollector Debug%]") then
        if Questie.db and Questie.db.profile and Questie.db.profile.showDataCollectionMessages then
            DEFAULT_CHAT_FRAME:AddMessage(msg, r or 1, g or 1, b or 1)
        end
        return
    end
    
    -- Check if this is a [DATA] message
    if string.find(msg, "%[DATA%]") then
        -- [DATA] messages only show if showDataCollectionMessages is enabled
        if Questie.db and Questie.db.profile and Questie.db.profile.showDataCollectionMessages then
            DEFAULT_CHAT_FRAME:AddMessage(msg, r or 1, g or 1, b or 1)
        end
    else
        -- Regular debug messages show if debugDataCollector is enabled
        if Questie.db and Questie.db.profile and Questie.db.profile.debugDataCollector then
            DEFAULT_CHAT_FRAME:AddMessage(msg, r or 1, g or 1, b or 1)
        end
    end
end

function QuestieDataCollector:Initialize()
    -- Prevent double initialization
    if _initialized then
        return
    end
    
    -- Only initialize if explicitly enabled
    if not Questie or not Questie.db or not Questie.db.profile.enableDataCollection then
        return
    end
    
    -- Create or ensure the global SavedVariable exists
    -- This happens AFTER SavedVariables are loaded
    if type(QuestieDataCollection) ~= "table" then
        _G.QuestieDataCollection = {}
    end
    if not QuestieDataCollection.quests then
        QuestieDataCollection.quests = {}
    end
    if not QuestieDataCollection.version then
        QuestieDataCollection.version = 1
    end
    if not QuestieDataCollection.sessionStart then
        QuestieDataCollection.sessionStart = date("%Y-%m-%d %H:%M:%S")
    end
    
    -- Count tracked quests
    local questCount = 0
    for _ in pairs(QuestieDataCollection.quests) do
        questCount = questCount + 1
    end
    
    -- Silently initialized
    
    -- Hook into events
    QuestieDataCollector:RegisterEvents()
    
    -- Enable tooltip IDs
    QuestieDataCollector:EnableTooltipIDs()
    
    -- Only show messages on first initialization, not after login
    if not _initialized then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[Questie Data Collector]|r Ready! You can now accept quests for data collection.", 0, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Type /qdc for commands|r", 1, 1, 0)
    end
    
    _initialized = true
    
    -- Wait for Questie to be fully initialized before checking quests
    -- This prevents GetQuest failures during startup
    local C_Timer = QuestieCompat.C_Timer
    C_Timer.After(2.0, function()
        -- Only check existing quests after Questie is fully loaded
        if QuestieDB and QuestieDB.GetQuest then
            -- Don't clear _activeTracking on reinit - preserve existing tracking
            -- _activeTracking = {}
            QuestieDataCollector:CheckExistingQuests()
        end
        
        -- Count how many quests we're tracking
        local count = 0
        for _ in pairs(_activeTracking) do
            count = count + 1
        end
        
        -- Silently complete the auto-rescan (no chat message)
        -- if count > 0 then
        --     DebugMessage(string.format("|cFF00FF00[Data Collector] Auto-rescan complete: Tracking %d quest(s)|r", count), 0, 1, 0)
        -- end
    end)
end

function QuestieDataCollector:CheckExistingQuests()
    -- Scan quest log for any missing (Epoch) quests
    local startTime = debugprofilestop()
    local trackedCount = 0
    local numEntries = GetNumQuestLogEntries()
    -- Silently scan quest log
    
    for i = 1, numEntries do
        -- Use QuestieCompat version which handles WoW 3.3.5 properly
        local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID = QuestieCompat.GetQuestLogTitle(i)
        
        if not isHeader and questID then
            -- Make a local copy to avoid any potential corruption
            local safeQuestID = questID
            
            -- Ensure questID is a number (sometimes it comes as a table)
            if type(safeQuestID) == "table" then
                -- Debug: Log what fields the table has
                if Questie.db.profile.debugDataCollector then
                    local fields = {}
                    for k,v in pairs(safeQuestID) do
                        table.insert(fields, tostring(k) .. "=" .. tostring(v))
                    end
                    DebugMessage("|cFFFF0000[DataCollector Debug]|r questID is table with fields: " .. table.concat(fields, ", "), 1, 0, 0)
                end
                
                -- Try to extract ID from table
                local extractedID = safeQuestID.Id or safeQuestID.ID or safeQuestID.id or safeQuestID.questID or safeQuestID.QuestID
                if extractedID and type(extractedID) == "number" then
                    safeQuestID = extractedID
                else
                    -- If we can't extract a valid ID, skip this quest
                    safeQuestID = nil
                end
            elseif type(safeQuestID) ~= "number" then
                safeQuestID = tonumber(safeQuestID)
            end
            
            -- Only proceed if we have a valid numeric questID
            if safeQuestID and type(safeQuestID) == "number" and safeQuestID > 0 then
                questID = safeQuestID  -- Reassign to the safe copy (don't redeclare)
                -- Final safety check before calling GetQuest
                if type(questID) ~= "number" then
                    DebugMessage("|cFFFF0000[DataCollector ERROR]|r questID passed check but is still " .. type(questID), 1, 0, 0)
                    -- Continue to next iteration instead of return
                else
                    -- Use pcall to catch any errors from GetQuest
                    local success, questData = pcall(function()
                        return QuestieDB.GetQuest(questID)  -- Use dot notation, not colon
                    end)
                    
                    if not success then
                        -- GetQuest failed - but for Epoch quests, we should still track them!
                        if questID >= 26000 then
                            -- This is an Epoch quest, track it anyway (silently)
                            if not _activeTracking[questID] then
                                _activeTracking[questID] = true
                                trackedCount = trackedCount + 1
                            end
                            
                            -- Initialize basic quest data
                            if not QuestieDataCollection.quests[questID] then
                                QuestieDataCollection.quests[questID] = {
                                    id = questID,
                                    name = title or ("Quest " .. questID),
                                    level = level,
                                    objectives = {},
                                    npcs = {},
                                    items = {},
                                    objects = {},
                                    sessionStart = date("%Y-%m-%d %H:%M:%S"),
                                    wasAlreadyAccepted = true,
                                    incompleteData = true
                                }
                            end
                            
                            -- Populate objectives for the quest
                            SelectQuestLogEntry(i)
                            local numObjectives = GetNumQuestLeaderBoards()  -- WoW 3.3.5: no parameter needed
                            if numObjectives > 0 and #QuestieDataCollection.quests[questID].objectives == 0 then
                                for objIdx = 1, numObjectives do
                                    local text, objectiveType, finished = GetQuestLogLeaderBoard(objIdx)  -- WoW 3.3.5: only needs objective index
                                    table.insert(QuestieDataCollection.quests[questID].objectives, {
                                        text = text or ("Objective " .. objIdx),
                                        type = objectiveType or "unknown",
                                        index = objIdx,
                                        completed = finished or false,
                                        progressLocations = {},
                                        lastText = text
                                    })
                                end
                            end
                        end
                    else
                        -- Now process the quest data
                        local needsTracking = false
                        local trackReason = nil
                        local isEpochQuest = (questID >= 26000)  -- All custom Epoch quests
                        
                        if isEpochQuest then
                            -- ALWAYS track Epoch quests to continuously improve their data
                            needsTracking = true
                            if not questData then
                                trackReason = "missing Epoch quest"
                            elseif questData.name and string.find(questData.name, "%[Epoch%]") then
                                trackReason = "has [Epoch] prefix"
                            else
                                trackReason = "is Epoch quest (improving data)"
                            end
                        end
                        
                        if needsTracking then
                            -- This quest needs data collection
                            -- Silently track quest
                            if not _activeTracking[questID] then
                                _activeTracking[questID] = true
                                trackedCount = trackedCount + 1
                                
                                -- Silently track without spam messages
                                
                                -- Initialize quest data if not exists
                                if not QuestieDataCollection.quests[questID] then
                                    QuestieDataCollection.quests[questID] = {
                                        id = questID,
                                        name = title or ("Quest " .. questID),
                                        level = level,
                                        objectives = {},
                                        npcs = {},
                                        items = {},
                                        objects = {},
                                        sessionStart = date("%Y-%m-%d %H:%M:%S"),
                                        wasAlreadyAccepted = true,  -- Flag that this quest was in log when addon loaded
                                        incompleteData = true  -- We don't have quest giver info
                                    }
                                else
                                    -- Quest already exists in collection, but we need to ensure objectives are current
                                    -- Update name and level if they were placeholders
                                    if title and (not QuestieDataCollection.quests[questID].name or 
                                       string.find(QuestieDataCollection.quests[questID].name, "Quest %d+")) then
                                        QuestieDataCollection.quests[questID].name = title
                                    end
                                    if level then
                                        QuestieDataCollection.quests[questID].level = level
                                    end
                                end
                                
                                -- Always refresh objectives from quest log (they might have changed or be missing)
                                SelectQuestLogEntry(i)
                                local numObjectives = GetNumQuestLeaderBoards()  -- WoW 3.3.5: no parameter needed
                                
                                -- Only update objectives if we don't have them or if the count is different
                                if not QuestieDataCollection.quests[questID].objectives or 
                                   #QuestieDataCollection.quests[questID].objectives ~= numObjectives or
                                   #QuestieDataCollection.quests[questID].objectives == 0 then
                                    
                                    -- Save old progress locations if they exist
                                    local oldProgressLocations = {}
                                    local oldContainers = {}
                                    if QuestieDataCollection.quests[questID].objectives then
                                        for idx, oldObj in ipairs(QuestieDataCollection.quests[questID].objectives) do
                                            if oldObj.progressLocations then
                                                oldProgressLocations[idx] = oldObj.progressLocations
                                            end
                                            if oldObj.containers then
                                                oldContainers[idx] = oldObj.containers
                                            end
                                        end
                                    end
                                    
                                    QuestieDataCollection.quests[questID].objectives = {}
                                    for objIdx = 1, numObjectives do
                                        local text, objectiveType, finished = GetQuestLogLeaderBoard(objIdx)  -- WoW 3.3.5: only needs objective index
                                        
                                        -- Parse current progress from text
                                        local current, total = 0, 0
                                        if text then
                                            current, total = string.match(text, "(%d+)/(%d+)")
                                            current = tonumber(current) or 0
                                            total = tonumber(total) or 0
                                        end
                                        
                                        table.insert(QuestieDataCollection.quests[questID].objectives, {
                                            text = text or ("Objective " .. objIdx),
                                            type = objectiveType or "unknown",
                                            index = objIdx,
                                            completed = finished or false,
                                            progressLocations = oldProgressLocations[objIdx] or {},
                                            containers = oldContainers[objIdx] or {},
                                            lastText = text,
                                            current = current,
                                            total = total
                                        })
                                    end
                                else
                                    -- Update existing objectives with current text (might have progress changes)
                                    for objIdx = 1, numObjectives do
                                        local text, objectiveType, finished = GetQuestLogLeaderBoard(objIdx)  -- WoW 3.3.5: only needs objective index
                                        if QuestieDataCollection.quests[questID].objectives[objIdx] then
                                            -- Update the text to reflect current progress
                                            if text then
                                                QuestieDataCollection.quests[questID].objectives[objIdx].text = text
                                                QuestieDataCollection.quests[questID].objectives[objIdx].lastText = text
                                            end
                                            QuestieDataCollection.quests[questID].objectives[objIdx].type = objectiveType or QuestieDataCollection.quests[questID].objectives[objIdx].type
                                            QuestieDataCollection.quests[questID].objectives[objIdx].completed = finished or false
                                            
                                            -- Parse current progress from text (e.g., "Sun-Ripened Banana: 3/10")
                                            local current, total = string.match(text or "", "(%d+)/(%d+)")
                                            if current and total then
                                                QuestieDataCollection.quests[questID].objectives[objIdx].current = tonumber(current)
                                                QuestieDataCollection.quests[questID].objectives[objIdx].total = tonumber(total)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end -- end of success check
                end -- end of type check
            end -- Close questID > 0 check
        end
    end
    
    if trackedCount > 0 then
        local elapsed = debugprofilestop() - startTime
        -- Finished scanning quest log
    end
end

function QuestieDataCollector:RegisterEvents()
    -- Create event frame if it doesn't exist
    local eventFrame
    if QuestieDataCollector.eventFrame then
        eventFrame = QuestieDataCollector.eventFrame
        -- Re-register all events in case they were lost after login
    else
        eventFrame = CreateFrame("Frame")
        QuestieDataCollector.eventFrame = eventFrame
    end
    
    -- Register all needed events
    eventFrame:RegisterEvent("QUEST_ACCEPTED")
    eventFrame:RegisterEvent("QUEST_TURNED_IN")
    eventFrame:RegisterEvent("QUEST_COMPLETE")
    eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    eventFrame:RegisterEvent("GOSSIP_SHOW")
    eventFrame:RegisterEvent("QUEST_DETAIL")
    eventFrame:RegisterEvent("CHAT_MSG_LOOT")
    eventFrame:RegisterEvent("UI_INFO_MESSAGE")
    eventFrame:RegisterEvent("ITEM_PUSH")
    eventFrame:RegisterEvent("LOOT_OPENED")
    eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("LOOT_OPENED")
    eventFrame:RegisterEvent("ITEM_PUSH")
    
    eventFrame:SetScript("OnEvent", function(self, event, ...)
        QuestieDataCollector:HandleEvent(event, ...)
    end)
    
    -- Hook interact with target to capture NPC data
    hooksecurefunc("InteractUnit", function(unit)
        if UnitExists(unit) and not UnitIsPlayer(unit) then
            QuestieDataCollector:CaptureNPCData(unit)
        end
    end)
    
    -- Hook using items (for quest items used on NPCs)
    if UseContainerItem then
        hooksecurefunc("UseContainerItem", function(bag, slot)
            -- When a quest item is used, check if we have a target
            if UnitExists("target") and not UnitIsPlayer("target") then
                QuestieDataCollector:TrackMob("target")
                
                -- Also track as potential quest item target
                local itemLink = GetContainerItemLink(bag, slot)
                if itemLink then
                    local itemId = tonumber(string.match(itemLink, "item:(%d+)"))
                    if itemId then
                        QuestieDataCollector:TrackQuestItemUsage(itemId, "target")
                    end
                end
            end
        end)
    end
    
    -- Hook tooltip functions to capture IDs
    QuestieDataCollector:SetupTooltipHooks()
    
    -- Hook game object interactions
    QuestieDataCollector:SetupObjectTracking()
    
    -- Enable ID display in tooltips when data collection is active
    if Questie.db.profile.enableDataCollection then
        QuestieDataCollector:EnableTooltipIDs()
    end
end

function QuestieDataCollector:EnableTooltipIDs()
    -- Only enable tooltips if data collection is actually enabled
    if not Questie.db.profile.enableDataCollection then
        return
    end
    
    -- Store original settings
    if not _originalTooltipSettings then
        _originalTooltipSettings = {
            itemID = Questie.db.profile.enableTooltipsItemID,
            npcID = Questie.db.profile.enableTooltipsNPCID,
            objectID = Questie.db.profile.enableTooltipsObjectID,
            questID = Questie.db.profile.enableTooltipsQuestID
        }
    end
    
    -- Enable all ID displays for data collection
    Questie.db.profile.enableTooltipsItemID = true
    Questie.db.profile.enableTooltipsNPCID = true
    Questie.db.profile.enableTooltipsObjectID = true
    Questie.db.profile.enableTooltipsQuestID = true
    
    -- Removed redundant message since we already show enabled status in Initialize()
end

function QuestieDataCollector:RestoreTooltipIDs()
    -- Restore original settings
    if _originalTooltipSettings then
        Questie.db.profile.enableTooltipsItemID = _originalTooltipSettings.itemID
        Questie.db.profile.enableTooltipsNPCID = _originalTooltipSettings.npcID
        Questie.db.profile.enableTooltipsObjectID = _originalTooltipSettings.objectID
        Questie.db.profile.enableTooltipsQuestID = _originalTooltipSettings.questID
        _originalTooltipSettings = nil
    end
end

function QuestieDataCollector:SetupTooltipHooks()
    -- Hook GameTooltip to capture item/NPC info when shown
    GameTooltip:HookScript("OnTooltipSetItem", function(self)
        if not Questie.db.profile.enableDataCollection then return end
        
        local name, link = self:GetItem()
        if link then
            local itemId = tonumber(string.match(link, "item:(%d+)"))
            if itemId then
                QuestieDataCollector:CaptureItemData(itemId, name, link)
            end
        end
    end)
    
    GameTooltip:HookScript("OnTooltipSetUnit", function(self)
        if not Questie.db.profile.enableDataCollection then return end
        
        local name, unit = self:GetUnit()
        if unit and not UnitIsPlayer(unit) then
            local guid = UnitGUID(unit)
            if guid then
                local npcId = tonumber(string.match(guid, "Creature%-0%-%d+%-%d+%-%d+%-(%d+)%-")) or 
                              tonumber(string.match(guid, "Creature%-0%-%d+%-%d+%-(%d+)%-"))
                if npcId then
                    QuestieDataCollector:CaptureTooltipNPCData(npcId, name)
                end
            end
        end
    end)
    
    -- Hook container item tooltips (bags)
    hooksecurefunc(GameTooltip, "SetBagItem", function(self, bag, slot)
        if not Questie.db.profile.enableDataCollection then return end
        
        local texture, count, locked, quality, readable, lootable, link = GetContainerItemInfo(bag, slot)
        if link then
            local itemId = tonumber(string.match(link, "item:(%d+)"))
            local name = GetItemInfo(link)
            if itemId and name then
                QuestieDataCollector:CaptureItemData(itemId, name, link)
            end
        end
    end)
end

function QuestieDataCollector:CaptureItemData(itemId, name, link)
    -- Store item data for active quests
    for questId, _ in pairs(_activeTracking) do
        if QuestieDataCollection.quests[questId] then
            if not QuestieDataCollection.quests[questId].items then
                QuestieDataCollection.quests[questId].items = {}
            end
            
            -- Check if this item is a quest objective
            local questLogIndex = QuestieDataCollector:GetQuestLogIndexById(questId)
            if questLogIndex then
                SelectQuestLogEntry(questLogIndex)
                local numObjectives = GetNumQuestLeaderBoards()  -- WoW 3.3.5: no parameter needed
                
                for i = 1, numObjectives do
                    local text, objectiveType, finished = GetQuestLogLeaderBoard(i)  -- WoW 3.3.5: only needs objective index
                    if objectiveType == "item" and string.find(text, name) then
                        QuestieDataCollection.quests[questId].items[itemId] = {
                            name = name,
                            objectiveIndex = i,
                            link = link
                        }
                        
                        -- Update objective with item ID
                        if QuestieDataCollection.quests[questId].objectives[i] then
                            QuestieDataCollection.quests[questId].objectives[i].itemId = itemId
                            QuestieDataCollection.quests[questId].objectives[i].itemName = name
                        end
                    end
                end
            end
        end
    end
end

function QuestieDataCollector:CaptureTooltipNPCData(npcId, name)
    -- Store NPC data for active quests
    for questId, _ in pairs(_activeTracking) do
        if QuestieDataCollection.quests[questId] then
            if not QuestieDataCollection.quests[questId].npcs then
                QuestieDataCollection.quests[questId].npcs = {}
            end
            
            -- Store with current location
            local coords = QuestieDataCollector:GetPlayerCoords()
            QuestieDataCollection.quests[questId].npcs[npcId] = {
                name = name,
                coords = coords,
                zone = GetRealZoneText(),
                timestamp = time()
            }
        end
    end
end

function QuestieDataCollector:HandleEvent(event, ...)
    if event == "QUEST_ACCEPTED" then
        local questLogIndex, questId = ...
        -- In 3.3.5a, second param might be questId or nil
        if not questId or questId == 0 then
            questId = QuestieDataCollector:GetQuestIdFromLogIndex(questLogIndex)
        end
        QuestieDataCollector:OnQuestAccepted(questId)
        
    elseif event == "QUEST_TURNED_IN" then
        local questId = ...
        QuestieDataCollector:OnQuestTurnedIn(questId)
        
    elseif event == "QUEST_COMPLETE" then
        QuestieDataCollector:OnQuestComplete()
        
    elseif event == "GOSSIP_SHOW" or event == "QUEST_DETAIL" then
        DebugMessage("|cFFCCCCCC[DEBUG] " .. event .. " event fired!|r", 0.8, 0.8, 0.8)
        QuestieDataCollector:CaptureNPCData("target")
        
    elseif event == "CHAT_MSG_LOOT" then
        local message = ...
        QuestieDataCollector:OnLootReceived(message)
        
    elseif event == "UI_INFO_MESSAGE" then
        local message = ...
        QuestieDataCollector:OnUIInfoMessage(message)
        
    elseif event == "QUEST_LOG_UPDATE" then
        QuestieDataCollector:OnQuestLogUpdate()
        
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        QuestieDataCollector:OnCombatLogEvent(...)
        
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        if UnitExists("mouseover") and not UnitIsPlayer("mouseover") then
            QuestieDataCollector:TrackMob("mouseover")
        end
        
    elseif event == "PLAYER_TARGET_CHANGED" then
        if UnitExists("target") and not UnitIsPlayer("target") and not UnitIsFriend("player", "target") then
            QuestieDataCollector:TrackMob("target")
        end
        
    elseif event == "LOOT_OPENED" then
        QuestieDataCollector:OnLootOpened()
        
    elseif event == "ITEM_PUSH" then
        local bagSlot, iconFileID = ...
        QuestieDataCollector:OnItemPush(bagSlot)
    end
end

function QuestieDataCollector:GetQuestIdFromLogIndex(index)
    local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questId = QuestieCompat.GetQuestLogTitle(index)
    
    -- Ensure questId is a number
    if type(questId) == "table" then
        -- Try to extract ID from table
        local extractedID = questId.Id or questId.ID or questId.id or questId.questID or questId.QuestID
        if extractedID and type(extractedID) == "number" then
            questId = extractedID
        else
            questId = nil
        end
    elseif type(questId) ~= "number" then
        questId = tonumber(questId)
    end
    
    if questId and questId > 0 then
        return questId
    end
    
    -- Try to find quest ID by matching title in quest log
    for i = 1, GetNumQuestLogEntries() do
        local qTitle, qLevel, _, qIsHeader, _, _, _, qId = QuestieCompat.GetQuestLogTitle(i)
        
        -- Ensure qId is a number
        if type(qId) == "table" then
            local extractedID = qId.Id or qId.ID or qId.id or qId.questID or qId.QuestID
            if extractedID and type(extractedID) == "number" then
                qId = extractedID
            else
                qId = nil
            end
        elseif type(qId) ~= "number" then
            qId = tonumber(qId)
        end
        
        if not qIsHeader and qTitle == title and qLevel == level then
            if qId and qId > 0 then
                return qId
            end
        end
    end
    
    return nil
end

function QuestieDataCollector:TrackQuestItemUsage(itemId, unit)
    if not UnitExists(unit) or UnitIsPlayer(unit) then return end
    
    local name = UnitName(unit)
    local guid = UnitGUID(unit)
    
    if guid then
        local npcId = tonumber(guid:sub(6, 12), 16)
        if npcId then
            local coords = QuestieDataCollector:GetPlayerCoords()
            
            -- Check all active quests for this item
            for questId, questData in pairs(QuestieDataCollection.quests or {}) do
                if _activeTracking[questId] then
                    -- Check if this quest uses this item
                    local usesItem = false
                    
                    -- Check objectives for spell/item usage objectives
                    for _, objective in ipairs(questData.objectives or {}) do
                        if objective.type == "spell" or objective.type == "event" or string.find(string.lower(objective.text or ""), "use") then
                            usesItem = true
                            
                            -- Store the target NPC for this objective
                            objective.targetNPCs = objective.targetNPCs or {}
                            table.insert(objective.targetNPCs, {
                                npcId = npcId,
                                name = name,
                                coords = coords,
                                zone = GetRealZoneText(),
                                subzone = GetSubZoneText(),
                                itemUsed = itemId
                            })
                            
                            DebugMessage("|cFF00FF00[DATA] Tracked quest item " .. itemId .. " used on " .. name .. " (ID: " .. npcId .. ") at " .. coords.x .. ", " .. coords.y .. "|r", 0, 1, 0)
                        end
                    end
                end
            end
        end
    end
end

function QuestieDataCollector:TrackMob(unit)
    if not UnitExists(unit) or UnitIsPlayer(unit) then return end
    
    local name = UnitName(unit)
    local guid = UnitGUID(unit)
    
    -- Track both hostile mobs AND any NPC (for quest item targets, friendly NPCs, etc.)
    if guid then
        -- Extract NPC ID using same method as quest givers
        local npcId = tonumber(guid:sub(6, 12), 16)
        
        if npcId then
            local coords = QuestieDataCollector:GetPlayerCoords()
            
            -- Count how many quests track this mob
            local trackedForQuests = {}
            local isNewMob = false
            
            -- Check all active tracked quests
            for questId, _ in pairs(_activeTracking or {}) do
                local questData = QuestieDataCollection.quests[questId]
                if questData then
                    -- Store in the quest's npcs table
                    questData.npcs = questData.npcs or {}
                    
                    -- Only store each NPC once per quest
                    if not questData.npcs[npcId] then
                        questData.npcs[npcId] = {
                            name = name,
                            coords = coords,
                            zone = GetRealZoneText(),
                            subzone = GetSubZoneText(),
                            level = UnitLevel(unit),
                            timestamp = time()
                        }
                        table.insert(trackedForQuests, questId)
                        isNewMob = true
                    end
                    
                    -- Also check if this mob matches any objectives (more flexible matching)
                    for _, objective in ipairs(questData.objectives or {}) do
                        if objective.type == "monster" then
                            -- Try to match the mob name in the objective text
                            -- Remove common words like "slain", "killed", etc. for better matching
                            local cleanText = string.lower(objective.text or "")
                            local cleanName = string.lower(name)
                            
                            if string.find(cleanText, cleanName) or string.find(cleanText, string.gsub(cleanName, "s$", "")) then
                                -- Store mob location with the quest objective
                                objective.mobLocations = objective.mobLocations or {}
                                
                                -- Check if we already have this location
                                local alreadyTracked = false
                                for _, loc in ipairs(objective.mobLocations) do
                                    if loc.npcId == npcId then
                                        alreadyTracked = true
                                        break
                                    end
                                end
                                
                                if not alreadyTracked then
                                    table.insert(objective.mobLocations, {
                                        npcId = npcId,
                                        name = name,
                                        coords = coords,
                                        zone = GetRealZoneText(),
                                        subzone = GetSubZoneText(),
                                        level = UnitLevel(unit)
                                    })
                                    
                                    DebugMessage("|cFF00AA00[DATA] Linked " .. name .. " to objective: " .. objective.text .. "|r", 0, 0.7, 0)
                                end
                            end
                        end
                    end
                end
            end
            
            -- Show consolidated message for all quests that tracked this mob
            if isNewMob and #trackedForQuests > 0 then
                if #trackedForQuests > 3 then
                    DebugMessage("|cFF888800[DATA] Tracked " .. name .. " (ID: " .. npcId .. 
                        ") for " .. #trackedForQuests .. " quests at [" .. (coords.x or 0) .. ", " .. (coords.y or 0) .. "]|r", 0.5, 0.5, 0)
                else
                    DebugMessage("|cFF888800[DATA] Tracked " .. name .. " (ID: " .. npcId .. 
                        ") for quests: " .. table.concat(trackedForQuests, ", ") .. " at [" .. (coords.x or 0) .. ", " .. (coords.y or 0) .. "]|r", 0.5, 0.5, 0)
                end
            end
        end
    end
end

function QuestieDataCollector:CaptureNPCData(unit)
    if not UnitExists(unit) then 
        DebugMessage("|cFFFF0000[DEBUG] Unit doesn't exist: " .. tostring(unit) .. "|r", 1, 0, 0)
        return 
    end
    
    if UnitIsPlayer(unit) then 
        DebugMessage("|cFFFF0000[DEBUG] Unit is a player, not an NPC|r", 1, 0, 0)
        return 
    end
    
    local name = UnitName(unit)
    local guid = UnitGUID(unit)
    DebugMessage("|cFF00FFFF[DEBUG] Capturing NPC: " .. (name or "nil") .. " GUID: " .. (guid or "nil") .. "|r", 0, 1, 1)
    
    if guid then
        -- WoW 3.3.5 GUID format: 0xF13000085800126C
        -- Use same extraction as QuestieCompat.UnitGUID
        local npcId = tonumber(guid:sub(6, 12), 16)
        
        DebugMessage("|cFFCCCCCC[DEBUG] Extracted NPC ID: " .. (npcId or "nil") .. " from GUID: " .. guid .. "|r", 0.8, 0.8, 0.8)
        
        if npcId then
            local coords = QuestieDataCollector:GetPlayerCoords()
            _lastQuestGiver = {
                name = name,
                npcId = npcId,
                coords = coords,
                zone = GetRealZoneText(),
                subzone = GetSubZoneText(),
                timestamp = time()
            }
            
            -- Debug output to verify NPC capture
            -- NPC captured silently
        end
    end
end

function QuestieDataCollector:GetPlayerCoords()
    -- Use Questie's coordinate system for better compatibility
    local QuestieCoords = QuestieLoader:ImportModule("QuestieCoords")
    if QuestieCoords and QuestieCoords.GetPlayerMapPosition then
        local position = QuestieCoords.GetPlayerMapPosition()
        if position and position.x and position.y and (position.x > 0 or position.y > 0) then
            return {x = math.floor(position.x * 1000) / 10, y = math.floor(position.y * 1000) / 10}
        end
    end
    
    -- Fallback to direct API if QuestieCoords not available
    local x, y = GetPlayerMapPosition("player")
    if x and y and (x > 0 or y > 0) then
        return {x = math.floor(x * 1000) / 10, y = math.floor(y * 1000) / 10}
    end
    
    -- Return approximate coordinates based on zone if map position fails
    return {x = 0, y = 0}
end

function QuestieDataCollector:OnQuestAccepted(questId)
    if not questId then return end
    
    -- Ensure questId is a number (sometimes it comes as a table)
    if type(questId) == "table" then
        -- Debug: Log what fields the table has
        if Questie.db.profile.debugDataCollector then
            local fields = {}
            for k,v in pairs(questId) do
                table.insert(fields, tostring(k) .. "=" .. tostring(v))
            end
            DebugMessage("|cFFFF0000[DataCollector Debug]|r OnQuestAccepted questId is table with fields: " .. table.concat(fields, ", "), 1, 0, 0)
        end
        
        -- Try to extract ID from table
        local extractedID = questId.Id or questId.ID or questId.id or questId.questID or questId.QuestID
        if extractedID and type(extractedID) == "number" then
            questId = extractedID
        else
            -- If we can't extract a valid ID, skip
            return
        end
    elseif type(questId) ~= "number" then
        questId = tonumber(questId)
        if not questId then return end
    end
    
    -- Debug: Log quest acceptance
    if Questie.db.profile.debugDataCollector then
        DebugMessage("|cFF00FFFF[DataCollector Debug]|r OnQuestAccepted called for questId: " .. tostring(questId), 0, 1, 1)
    end
    
    -- Double-check that data collection is enabled
    if not Questie.db.profile.enableDataCollection then
        return
    end
    
    -- Ensure we're initialized
    if not QuestieDataCollection or not QuestieDataCollection.quests then
        QuestieDataCollector:Initialize()
    end
    
    -- Check for ALL custom/Epoch quests, not just 26000-26999 range
    local questData = nil
    if QuestieDB and QuestieDB.GetQuest then
        questData = QuestieDB.GetQuest(questId)  -- Use dot notation, not colon
    end
    
    local isEpochQuest = (questId >= 26000)  -- All custom Epoch quests start at 26000+
    
    -- Check for runtime stubs in QuestiePlayer.currentQuestlog
    local runtimeStub = QuestiePlayer and QuestiePlayer.currentQuestlog and QuestiePlayer.currentQuestlog[questId]
    
    local hasEpochPrefix = false
    local isMissingFromDB = not questData
    
    -- Debug logging
    if Questie.db.profile.debugDataCollector then
        DebugMessage(string.format("|cFF00FFFF[DataCollector Debug]|r Quest %d: isEpochQuest=%s, isMissingFromDB=%s, hasRuntimeStub=%s", 
            questId, tostring(isEpochQuest), tostring(isMissingFromDB), tostring(runtimeStub ~= nil)), 0, 1, 1)
    end
    
    -- Check both database quest and runtime stub for [Epoch] prefix
    if questData and questData.name and string.find(questData.name, "%[Epoch%]") then
        hasEpochPrefix = true
    elseif runtimeStub and runtimeStub.name and string.find(runtimeStub.name, "%[Epoch%]") then
        hasEpochPrefix = true
    elseif runtimeStub and runtimeStub.__isRuntimeStub then
        -- All runtime stubs are missing quests that need data collection
        hasEpochPrefix = true
    end
    
    -- Check if quest has incomplete data (missing quest givers or objectives)
    local hasIncompleteData = false
    if questData and isEpochQuest and QuestieDB.QueryQuestSingle then
        -- Check if quest is missing critical data using individual queries to avoid compiler error
        local startedBy = QuestieDB.QueryQuestSingle(questId, "startedBy")
        local objectives = QuestieDB.QueryQuestSingle(questId, "objectives")
        local objectivesText = QuestieDB.QueryQuestSingle(questId, "objectivesText")
        
        -- Check if quest givers are missing
        if not startedBy or (type(startedBy) == "table" and 
                             (not startedBy[1] or #startedBy[1] == 0) and
                             (not startedBy[2] or #startedBy[2] == 0) and
                             (not startedBy[3] or #startedBy[3] == 0)) then
            hasIncompleteData = true
        end
        
        -- Check if objectives are missing or empty
        if not hasIncompleteData then
            if not objectives then
                -- No objectives at all is incomplete
                hasIncompleteData = true
            elseif type(objectives) == "table" then
                -- Check if all objective arrays are empty
                local hasAnyObjective = false
                if objectives[1] and #objectives[1] > 0 then hasAnyObjective = true end
                if objectives[2] and #objectives[2] > 0 then hasAnyObjective = true end
                if objectives[3] and #objectives[3] > 0 then hasAnyObjective = true end
                if objectives[4] and #objectives[4] > 0 then hasAnyObjective = true end
                if objectives[5] and #objectives[5] > 0 then hasAnyObjective = true end
                if objectives[6] and #objectives[6] > 0 then hasAnyObjective = true end
                if not hasAnyObjective then
                    -- Empty objectives = incomplete, even if objectivesText exists
                    -- objectivesText is just description, not actual trackable objectives
                    hasIncompleteData = true
                end
            end
        end
    end
    
    
    -- Debug: Log the final decision factors
    if Questie.db.profile.debugDataCollector then
        DebugMessage(string.format("|cFF00FFFF[DataCollector Debug]|r Final check - isEpochQuest=%s, isMissingFromDB=%s, hasEpochPrefix=%s, hasIncompleteData=%s", 
            tostring(isEpochQuest), tostring(isMissingFromDB), tostring(hasEpochPrefix), tostring(hasIncompleteData)), 0, 1, 1)
    end
    
    -- Track if it's an Epoch quest (by ID range) OR any quest that's missing from the database
    -- This will catch ALL custom quests including new starting zones
    -- ALWAYS track Epoch quests to improve their data, even if they have some data already
    if isEpochQuest or isMissingFromDB or hasEpochPrefix or hasIncompleteData then
        -- ALERT! Missing quest detected!
        local questTitle = QuestieCompat.GetQuestLogTitle(QuestieDataCollector:GetQuestLogIndexById(questId))
        
        -- Silently track the quest without alert messages
        -- User requested to remove all printing
        
        -- Initialize collection data for this quest
        if not QuestieDataCollection.quests[questId] then
            QuestieDataCollection.quests[questId] = {
                id = questId,
                name = questTitle,
                acceptTime = time(),
                level = nil,
                zone = GetRealZoneText(),
                faction = UnitFactionGroup("player"),  -- "Alliance" or "Horde"
                race = select(2, UnitRace("player")),
                class = select(2, UnitClass("player")),
                objectives = {},
                items = {},
                npcs = {}
            }
        else
            -- Quest already exists, just update accept time and clear duplicate objectives
            QuestieDataCollection.quests[questId].acceptTime = time()
            -- Reset objectives to prevent duplicates
            QuestieDataCollection.quests[questId].objectives = {}
        end
        
        -- Capture quest giver data
        if _lastQuestGiver and (time() - _lastQuestGiver.timestamp < 5) then
            QuestieDataCollection.quests[questId].questGiver = _lastQuestGiver
            -- Quest giver captured
        else
            DebugMessage("|cFFFFFF00Tip: Target the quest giver when accepting to capture their location|r", 1, 1, 0)
        end
        
        -- Get quest details from log
        local questLogIndex = QuestieDataCollector:GetQuestLogIndexById(questId)
        if questLogIndex then
            SelectQuestLogEntry(questLogIndex)
            local _, level = QuestieCompat.GetQuestLogTitle(questLogIndex)
            QuestieDataCollection.quests[questId].level = level
            
            -- Get objectives (with retry for text that might not be loaded yet)
            local numObjectives = GetNumQuestLeaderBoards()  -- WoW 3.3.5: no parameter needed
            for i = 1, numObjectives do
                local text, objectiveType, finished = GetQuestLogLeaderBoard(i)  -- WoW 3.3.5: only needs objective index
                
                -- If text is empty, try to get it from quest description
                if not text or text == "" then
                    -- Try getting full quest text
                    local questDescription, questObjectives = GetQuestLogQuestText()
                    -- Extract objective from objectives text if available
                    if questObjectives and questObjectives ~= "" then
                        -- Parse out individual objectives (usually separated by newlines)
                        local objNum = 1
                        for line in string.gmatch(questObjectives, "[^\n]+") do
                            if objNum == i then
                                text = line
                                break
                            end
                            objNum = objNum + 1
                        end
                    end
                    
                    -- If still no text, use a placeholder that will be updated later
                    if not text or text == "" then
                        text = "Objective " .. i .. " (loading...)"
                    end
                end
                
                table.insert(QuestieDataCollection.quests[questId].objectives, {
                    text = text,
                    type = objectiveType or "unknown",
                    index = i,
                    completed = finished or false,
                    progressLocations = {},
                    lastText = text  -- Track for changes
                })
            end
        end
        
        -- Simple one-line message as requested by user
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF8000Quest not in database. This quest is now being tracked by Data Collector!|r", 1, 0.5, 0)
        
        _activeTracking[questId] = true
        
        -- Schedule an update to get proper objective text after a short delay
        -- Sometimes the quest log isn't fully updated when QUEST_ACCEPTED fires
        C_Timer.After(0.5, function()
            QuestieDataCollector:UpdateQuestObjectives(questId)
        end)
    end
end

-- Helper function to update quest objectives from the quest log
function QuestieDataCollector:UpdateQuestObjectives(questId)
    if not questId or not QuestieDataCollection.quests[questId] then return end
    
    local questLogIndex = QuestieDataCollector:GetQuestLogIndexById(questId)
    if questLogIndex then
        SelectQuestLogEntry(questLogIndex)
        local numObjectives = GetNumQuestLeaderBoards()  -- WoW 3.3.5: no parameter needed
        
        for i = 1, numObjectives do
            local text, objectiveType, finished = GetQuestLogLeaderBoard(i)  -- WoW 3.3.5: only needs objective index
            if QuestieDataCollection.quests[questId].objectives[i] then
                -- Update the objective with current text
                if text and text ~= "" then
                    QuestieDataCollection.quests[questId].objectives[i].text = text
                    QuestieDataCollection.quests[questId].objectives[i].lastText = text
                    QuestieDataCollection.quests[questId].objectives[i].type = objectiveType or QuestieDataCollection.quests[questId].objectives[i].type
                    QuestieDataCollection.quests[questId].objectives[i].completed = finished or false
                    
                    -- Parse progress
                    local current, total = string.match(text, "(%d+)/(%d+)")
                    if current and total then
                        QuestieDataCollection.quests[questId].objectives[i].current = tonumber(current)
                        QuestieDataCollection.quests[questId].objectives[i].total = tonumber(total)
                    end
                end
            end
        end
    end
end

function QuestieDataCollector:GetQuestLogIndexById(questId)
    for i = 1, GetNumQuestLogEntries() do
        local _, _, _, isHeader, _, _, _, qId = QuestieCompat.GetQuestLogTitle(i)
        if not isHeader then
            if qId == questId then
                return i
            end
        end
    end
    return nil
end

function QuestieDataCollector:OnQuestTurnedIn(questId)
    -- This event might not fire properly in 3.3.5, but keep it as fallback
    if not questId or not QuestieDataCollection.quests[questId] then return end
    
    -- Capture turn-in NPC
    if _lastQuestGiver and (time() - _lastQuestGiver.timestamp < 5) then
        QuestieDataCollection.quests[questId].turnInNpc = _lastQuestGiver
        
        DebugMessage("|cFF00FF00[DATA] Turn-in NPC Captured: " .. _lastQuestGiver.name .. " (ID: " .. _lastQuestGiver.npcId .. ")|r", 0, 1, 0)
        
        -- Show hyperlink notification
        local questName = QuestieDataCollection.quests[questId].name or "Unknown Quest"
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[QUESTIE] Epoch quest completed! Please " .. CreateQuestDataLink(questId) .. "|r", 0, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Quest: " .. questName .. " (ID: " .. questId .. ")|r", 1, 1, 0)
        
        PlaySound("QUESTCOMPLETED")
    end
    
    _activeTracking[questId] = nil
end

function QuestieDataCollector:OnQuestComplete()
    -- Capture the NPC we're turning in to
    QuestieDataCollector:CaptureNPCData("target")
    
    -- Try to identify which quest is being turned in
    -- In 3.3.5, we need to scan the quest log for quests that are complete
    local questId = nil
    local questName = nil
    
    for i = 1, GetNumQuestLogEntries() do
        local title, _, _, _, _, isComplete, _, qID = QuestieCompat.GetQuestLogTitle(i)
        -- Use our tracked quests to identify Epoch quests
        if isComplete and _activeTracking[qID] then
            questId = qID
            questName = title
            break
        end
    end
    
    if questId and QuestieDataCollection.quests[questId] then
        -- Capture turn-in NPC
        if _lastQuestGiver and (time() - _lastQuestGiver.timestamp < 5) then
            QuestieDataCollection.quests[questId].turnInNpc = _lastQuestGiver
            
            DebugMessage("|cFF00FF00[DATA] Turn-in NPC Captured: " .. _lastQuestGiver.name .. " (ID: " .. _lastQuestGiver.npcId .. ")|r", 0, 1, 0)
            
            -- Show hyperlink notification instead of auto-popup
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[QUESTIE] Epoch quest completed! Please " .. CreateQuestDataLink(questId) .. "|r", 0, 1, 0)
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Quest: " .. questName .. " (ID: " .. questId .. ")|r", 1, 1, 0)
            
            -- Play a subtle sound to notify completion
            PlaySound("QUESTCOMPLETED")
        end
    end
end

function QuestieDataCollector:OnCombatLogEvent(...)
    local timestamp, eventType, _, sourceGUID, sourceName, _, _, destGUID, destName = ...
    
    -- Track when player kills something
    if eventType == "PARTY_KILL" or eventType == "UNIT_DIED" then
        if sourceGUID == UnitGUID("player") and destGUID then
            -- Extract NPC ID from GUID
            local npcId = tonumber(destGUID:sub(9, 12), 16)
            if npcId then
                -- Store recent kill for correlation with quest updates
                _recentKills = _recentKills or {}
                table.insert(_recentKills, {
                    npcId = npcId,
                    name = destName,
                    timestamp = time(),
                    coords = QuestieDataCollector:GetPlayerCoords(),
                    zone = GetRealZoneText(),
                    subzone = GetSubZoneText()
                })
                
                -- Keep only last 10 kills
                if #_recentKills > 10 then
                    table.remove(_recentKills, 1)
                end
            end
        end
    end
end

function QuestieDataCollector:OnQuestLogUpdate()
    -- Debug: Check if _activeTracking is populated
    if Questie.db.profile.debugDataCollector then
        local count = 0
        for _ in pairs(_activeTracking) do
            count = count + 1
        end
        if count == 0 then
            DebugMessage("|cFFFF0000[DEBUG] OnQuestLogUpdate: _activeTracking is EMPTY!|r", 1, 0, 0)
        end
    end
    
    -- Check all tracked quests for objective changes
    for questId, _ in pairs(_activeTracking) do
        if QuestieDataCollection.quests[questId] then
            local questLogIndex = QuestieDataCollector:GetQuestLogIndexById(questId)
            if questLogIndex then
                SelectQuestLogEntry(questLogIndex)
                local numObjectives = GetNumQuestLeaderBoards()  -- WoW 3.3.5: no parameter needed
                
                for i = 1, numObjectives do
                    local text, objectiveType, finished = GetQuestLogLeaderBoard(i)  -- WoW 3.3.5: only needs objective index
                    local objData = QuestieDataCollection.quests[questId].objectives[i]
                    
                    -- Always update objective text to keep it current
                    if objData then
                        if text and text ~= "" then
                            objData.text = text
                            objData.type = objectiveType
                        elseif not objData.text or objData.text == "" or string.find(objData.text, "loading") then
                            objData.text = text or ("Objective " .. i)
                        end
                    end
                    
                    -- Check for actual progress (not just text updates)
                    if objData and objData.lastText ~= text and text and text ~= "" then
                        -- Parse progress numbers to see if there's actual progress
                        local oldNum = tonumber(string.match(objData.lastText or "", "(%d+)/") or "0")
                        local newNum = tonumber(string.match(text or "", "(%d+)/") or "0")
                        
                        -- Only record if there's actual numerical progress or completion change
                        if newNum > oldNum or (finished and not objData.completed) then
                            objData.lastText = text
                            objData.type = objectiveType
                            objData.completed = finished
                            
                            if not objData.progressLocations then
                                objData.progressLocations = {}
                            end
                            
                            local locData = {
                                coords = QuestieDataCollector:GetPlayerCoords(),
                                zone = GetRealZoneText(),
                                subzone = GetSubZoneText(),
                                text = text,
                                timestamp = time()
                            }
                        
                        -- Special handling for exploration objectives
                        if objectiveType == "event" or objectiveType == "area" then
                            locData.action = "Explored area"
                            DebugMessage("|cFF00FF00[DATA] Exploration objective captured at [" .. 
                                (locData.coords and locData.coords.x or 0) .. ", " .. 
                                (locData.coords and locData.coords.y or 0) .. "] in " .. 
                                (locData.subzone or locData.zone or "Unknown") .. "|r", 0, 1, 0)
                        -- Try to correlate with recent kills for monster objectives
                        elseif objectiveType == "monster" and _recentKills and #_recentKills > 0 then
                            -- Check most recent kill (within 2 seconds)
                            local recentKill = _recentKills[#_recentKills]
                            if time() - recentKill.timestamp <= 2 then
                                locData.npcId = recentKill.npcId
                                locData.npcName = recentKill.name
                                locData.action = "Killed " .. recentKill.name .. " (ID: " .. recentKill.npcId .. ")"
                                objData.objectiveType = "kill"
                                
                                -- Store NPC info for this objective
                                if not objData.npcs then
                                    objData.npcs = {}
                                end
                                objData.npcs[recentKill.npcId] = recentKill.name
                            end
                        elseif objectiveType == "item" then
                            objData.objectiveType = "item"
                            locData.action = "Item collection"
                            
                            -- Check if we have a target for source info
                            if UnitExists("target") then
                                local targetGUID = UnitGUID("target")
                                if targetGUID then
                                    local npcId = tonumber(targetGUID:sub(9, 12), 16)
                                    if npcId then
                                        locData.sourceNpcId = npcId
                                        locData.sourceNpcName = UnitName("target")
                                        locData.action = locData.action .. " from " .. UnitName("target") .. " (ID: " .. npcId .. ")"
                                    end
                                end
                            end
                        elseif objectiveType == "object" then
                            objData.objectiveType = "object"
                            locData.action = "Object interaction"
                        elseif objectiveType == "event" then
                            objData.objectiveType = "event"
                            locData.action = "Event/Exploration completed"
                            
                            -- Special handling for exploration/discovery objectives
                            if string.find(string.lower(text or ""), "explore") or 
                               string.find(string.lower(text or ""), "discover") or
                               string.find(string.lower(text or ""), "find") or
                               string.find(string.lower(text or ""), "reach") then
                                
                                -- Mark this as a discovery/exploration point
                                objData.discoveryPoint = {
                                    coords = locData.coords,
                                    zone = locData.zone,
                                    subzone = locData.subzone,
                                    completedText = text,
                                    timestamp = time()
                                }
                                
                                DebugMessage("|cFF00FFFF[DATA] DISCOVERY POINT CAPTURED!|r", 0, 1, 1)
                                DebugMessage("|cFF00FFFF  Objective: " .. text .. "|r", 0, 1, 1)
                                DebugMessage("|cFF00FFFF  Exact coords: [" .. locData.coords.x .. ", " .. locData.coords.y .. "]|r", 0, 1, 1)
                                DebugMessage("|cFF00FFFF  Zone: " .. locData.zone .. (locData.subzone ~= "" and " (" .. locData.subzone .. ")" or "") .. "|r", 0, 1, 1)
                            end
                        end
                        
                        -- Check for duplicate progress location (same coords within 5 seconds)
                        local isDuplicate = false
                        if objData.progressLocations and #objData.progressLocations > 0 then
                            local lastLoc = objData.progressLocations[#objData.progressLocations]
                            if lastLoc.timestamp and (time() - lastLoc.timestamp < 5) and 
                               lastLoc.coords and locData.coords and
                               math.abs(lastLoc.coords.x - locData.coords.x) < 1 and
                               math.abs(lastLoc.coords.y - locData.coords.y) < 1 then
                                isDuplicate = true
                            end
                        end
                        
                        if not isDuplicate then
                            table.insert(objData.progressLocations, locData)
                            
                            -- Objective progress tracked silently (debug messages disabled)
                            -- if locData.action then
                            --     DebugMessage("|cFF00FF00  Action: " .. locData.action .. "|r", 0, 1, 0)
                            -- end
                            -- DebugMessage("|cFF00FF00  Location: [" .. locData.coords.x .. ", " .. locData.coords.y .. "] in " .. locData.zone .. "|r", 0, 1, 0)
                        end
                        end
                    end
                end
            end
        end
    end
end

function QuestieDataCollector:OnLootReceived(message)
    -- Parse loot message for item info
    local itemLink = string.match(message, "|c.-|Hitem:.-|h%[.-%]|h|r")
    if itemLink then
        local itemId = tonumber(string.match(itemLink, "item:(%d+):"))
        local itemName = string.match(itemLink, "%[(.-)%]")
        
        if itemId and itemName then
            -- Use current loot source if available (from LOOT_OPENED)
            if _currentLootSource and (time() - _currentLootSource.timestamp < 3) then
                -- We know exactly what we looted from
                for questId, _ in pairs(_activeTracking or {}) do
                    local questData = QuestieDataCollection.quests[questId]
                    if questData then
                        for objIndex, objective in ipairs(questData.objectives or {}) do
                            if objective.type == "item" and string.find(string.lower(objective.text or ""), string.lower(itemName)) then
                                -- Quest item received!
                                objective.itemLootData = objective.itemLootData or {}
                                
                                local lootEntry = {
                                    itemId = itemId,
                                    itemName = itemName,
                                    sourceType = _currentLootSource.type,
                                    sourceId = _currentLootSource.id,
                                    sourceName = _currentLootSource.name,
                                    coords = _currentLootSource.coords,
                                    zone = _currentLootSource.zone,
                                    subzone = _currentLootSource.subzone,
                                    timestamp = time()
                                }
                                
                                table.insert(objective.itemLootData, lootEntry)
                                
                                -- Update quest progress location
                                objective.progressLocations = objective.progressLocations or {}
                                table.insert(objective.progressLocations, {
                                    coords = _currentLootSource.coords,
                                    zone = _currentLootSource.zone,
                                    subzone = _currentLootSource.subzone,
                                    text = objective.text,
                                    action = "Looted " .. itemName .. " from " .. _currentLootSource.name,
                                    timestamp = time()
                                })
                                
                                if _currentLootSource.type == "mob" then
                                    DebugMessage("|cFF00FF00[DATA] Confirmed: '" .. itemName .. 
                                        "' (ID: " .. itemId .. ") from mob " .. _currentLootSource.name .. "|r", 0, 1, 0)
                                else
                                    DebugMessage("|cFF00AAFF[DATA] Confirmed: '" .. itemName .. 
                                        "' (ID: " .. itemId .. ") from object " .. _currentLootSource.name .. "|r", 0, 0.67, 1)
                                end
                            end
                        end
                    end
                end
            elseif _recentKills and #_recentKills > 0 then
                -- Fallback: Check recent kills
                local mostRecentKill = _recentKills[#_recentKills]
                if (time() - mostRecentKill.timestamp) < 5 then
                    -- Link this item drop to the mob
                    for questId, questData in pairs(QuestieDataCollection.quests or {}) do
                        for _, objective in ipairs(questData.objectives or {}) do
                            if objective.type == "item" and string.find(string.lower(objective.text or ""), string.lower(itemName)) then
                                objective.itemSources = objective.itemSources or {}
                                table.insert(objective.itemSources, {
                                    itemId = itemId,
                                    itemName = itemName,
                                    sourceNpcId = mostRecentKill.npcId,
                                    sourceNpcName = mostRecentKill.name,
                                    coords = mostRecentKill.coords,
                                    zone = mostRecentKill.zone,
                                    subzone = mostRecentKill.subzone
                                })
                                
                                DebugMessage("|cFF00AA00[DATA] Quest item '" .. itemName .. 
                                    "' likely from " .. mostRecentKill.name .. " (ID: " .. mostRecentKill.npcId .. ")|r", 0, 0.7, 0)
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Trigger quest log check when loot is received
    QuestieDataCollector:OnQuestLogUpdate()
end

function QuestieDataCollector:SetupObjectTracking()
    -- Track when player interacts with game objects
    -- Don't clear _lastInteractedObject here as it may have valid data
    
    -- Hook the tooltip to capture object names and IDs when mousing over
    GameTooltip:HookScript("OnShow", function(self)
        if Questie.db.profile.enableDataCollection then
            local name = GameTooltipTextLeft1:GetText()
            if name and not UnitExists("mouseover") then
                -- This might be a game object - capture its name!
                -- Look for object ID in the tooltip lines
                local objectId = nil
                for i = 1, self:NumLines() do
                    local text = _G["GameTooltipTextLeft" .. i]:GetText()
                    if text then
                        -- Look for ID pattern like "ID: 4000003" or just "4000003"
                        local id = string.match(text, "ID:%s*(%d+)") or string.match(text, "^(%d+)$")
                        if id then
                            objectId = tonumber(id)
                            break
                        end
                    end
                end
                
                -- IMPORTANT: Don't overwrite _lastInteractedObject if we're currently in a loot window
                -- Check if loot window is open to preserve the container name
                if _lastInteractedObject and 
                   (time() - _lastInteractedObject.timestamp) < 2 and
                   GetNumLootItems and GetNumLootItems() > 0 then
                    -- We're in the middle of looting, don't overwrite unless it's a better name
                    if _lastInteractedObject.name ~= "Ground Object" or name == "Ground Object" then
                        -- We already have a good name, or the new name is no better
                        if Questie.db.profile.debugDataCollector then
                            DebugMessage("|cFFFFFF00[DEBUG] Preserving loot source '" .. _lastInteractedObject.name .. 
                                "', ignoring tooltip: " .. name .. "|r", 1, 1, 0)
                        end
                        return
                    end
                    -- If we currently have "Ground Object" and tooltip has a better name, use it
                    if _lastInteractedObject.name == "Ground Object" and name ~= "Ground Object" then
                        _lastInteractedObject.name = name
                        if Questie.db.profile.debugDataCollector then
                            DebugMessage("|cFF00FF00[DEBUG] Updating Ground Object with better name: " .. name .. "|r", 0, 1, 0)
                        end
                        return
                    end
                end
                
                _lastInteractedObject = {
                    name = name,
                    id = objectId,
                    coords = QuestieDataCollector:GetPlayerCoords(),
                    zone = GetRealZoneText(),
                    subzone = GetSubZoneText(),
                    timestamp = time()
                }
                -- Only show this in debug mode - disabled due to spam issues
                -- The db.profile isn't always loaded when tooltips are processed
                --[[
                if Questie.db and Questie.db.profile and Questie.db.profile.debugDataCollector then
                    DebugMessage("|cFF00FFFF[DEBUG] Captured object from tooltip: '" .. name .. "'" .. 
                        (objectId and " (ID: " .. objectId .. ")" or "") .. "|r", 0, 1, 1)
                end
                --]]
                
                if objectId then
                    DebugMessage("|cFF8888FF[DATA] Hovering object: " .. name .. " (ID: " .. objectId .. ")|r", 0.5, 0.5, 1)
                end
            end
        end
    end)
end

function QuestieDataCollector:OnLootOpened()
    local coords = QuestieDataCollector:GetPlayerCoords()
    local zone = GetRealZoneText()
    local subzone = GetSubZoneText()
    
    -- Determine loot source type
    local lootSourceType = nil
    local lootSourceId = nil
    local lootSourceName = nil
    
    -- Check if we're looting a corpse (mob)
    if UnitExists("target") and UnitIsDead("target") then
        lootSourceType = "mob"
        lootSourceName = UnitName("target")
        local guid = UnitGUID("target")
        if guid then
            lootSourceId = tonumber(guid:sub(6, 12), 16)
        end
        
        if coords and coords.x and coords.y then
            DebugMessage("|cFFAA8800[DATA] Looting mob: " .. lootSourceName .. 
                " (ID: " .. (lootSourceId or "unknown") .. ") at [" .. coords.x .. ", " .. coords.y .. "]|r", 0.67, 0.53, 0)
        else
            DebugMessage("|cFFAA8800[DATA] Looting mob: " .. lootSourceName .. 
                " (ID: " .. (lootSourceId or "unknown") .. ") - location unknown|r", 0.67, 0.53, 0)
        end
    else
        -- This is likely an object interaction
        lootSourceType = "object"
        
        -- Try multiple methods to get the object name
        local lootName = nil
        
        -- Method 1: Try GetLootSourceInfo (might work for some objects)
        if GetLootSourceInfo then
            lootName = GetLootSourceInfo(1)
        end
        
        -- Method 2: Try to get from loot frame title
        if not lootName and LootFrame and LootFrame:IsVisible() and LootFrameTitle then
            local title = LootFrameTitle:GetText()
            if title and title ~= "" and title ~= "Loot" then
                lootName = title
                if Questie.db.profile.debugDataCollector then
                    DebugMessage("|cFF00FF00[DEBUG] Got container name from loot frame: " .. title .. "|r", 0, 1, 0)
                end
            end
        end
        
        if lootName then
            lootSourceName = lootName
        elseif _lastInteractedObject then
            -- Use the last interacted object regardless of age
            -- This should have the container name from when we moused over it
            lootSourceName = _lastInteractedObject.name
            lootSourceId = _lastInteractedObject.id
            
            -- Disabled due to spam issues
            --[[
            if Questie.db and Questie.db.profile and Questie.db.profile.debugDataCollector then
                local age = _lastInteractedObject.timestamp and (time() - _lastInteractedObject.timestamp) or "unknown"
                DebugMessage("|cFFFFFF00[DEBUG] Using _lastInteractedObject: '" .. (lootSourceName or "nil") .. 
                    "' (age: " .. tostring(age) .. "s)|r", 1, 1, 0)
            end
            --]]
            
            -- Don't accept placeholder names
            if not lootSourceName or lootSourceName == "Ground Object" or lootSourceName == "Unknown Container" or lootSourceName == "Unidentified Container" then
                -- Make one more attempt to get a meaningful name
                DebugMessage("|cFFFFFF00[DATA] Container detected but name unknown. TIP: Mouse over before looting!|r", 1, 1, 0)
                
                -- For known quest items, we can make educated guesses
                local numItems = GetNumLootItems()
                for i = 1, numItems do
                    local _, itemName = GetLootSlotInfo(i)
                    if itemName then
                        if string.find(itemName, "Banana") then
                            lootSourceName = "Banana Bunch"  -- Common name for banana containers
                        elseif string.find(itemName, "Apple") then
                            lootSourceName = "Apple Tree"
                        elseif string.find(itemName, "Herb") then
                            lootSourceName = "Herb Node"
                        else
                            -- Generic but better than nothing
                            lootSourceName = itemName .. " Container"
                        end
                        break
                    end
                end
            end
        else
            -- We don't have the container name - provide helpful message
            DebugMessage("|cFFFFFF00[DATA] Container location saved but name unknown. TIP: Mouse over before looting!|r", 1, 1, 0)
            lootSourceName = "Unidentified Container"
        end
        
        -- Update _lastInteractedObject for UI_INFO_MESSAGE handler
        -- Only update if we have a meaningful name (not a placeholder)
        local isPlaceholder = (lootSourceName == "Ground Object" or 
                              lootSourceName == "Unknown Container" or 
                              lootSourceName == "Unidentified Container" or
                              string.find(lootSourceName, "Container$"))
        
        if not isPlaceholder or not _lastInteractedObject then
            -- Store the loot source for container tracking
            _lastInteractedObject = {
                name = lootSourceName,
                id = lootSourceId,
                coords = coords,
                zone = zone,
                subzone = subzone,
                timestamp = time()
            }
            if Questie.db.profile.debugDataCollector then
                DebugMessage("|cFFFF00FF[DEBUG] Setting _lastInteractedObject from LOOT_OPENED: " .. lootSourceName .. "|r", 1, 0, 1)
            end
        else
            -- Keep the existing _lastInteractedObject but update coords if better
            if _lastInteractedObject and coords and coords.x and coords.y then
                _lastInteractedObject.coords = coords
                _lastInteractedObject.zone = zone
                _lastInteractedObject.subzone = subzone
            end
            if Questie.db.profile.debugDataCollector then
                DebugMessage("|cFFFF00FF[DEBUG] Keeping existing _lastInteractedObject: " .. (_lastInteractedObject and _lastInteractedObject.name or "nil") .. 
                    " (not overwriting with placeholder: " .. lootSourceName .. ")|r", 1, 0, 1)
            end
        end
        
        if coords and coords.x and coords.y then
            DebugMessage("|cFF8888FF[DATA] Looting object: " .. lootSourceName .. 
                " at [" .. coords.x .. ", " .. coords.y .. "]|r", 0.5, 0.5, 1)
        else
            DebugMessage("|cFF8888FF[DATA] Looting object: " .. lootSourceName .. 
                " - location unknown|r", 0.5, 0.5, 1)
        end
        
        -- Store object data in any active quest that might use this object
        local activeCount = 0
        for _ in pairs(_activeTracking or {}) do
            activeCount = activeCount + 1
        end
        
        if activeCount == 0 then
            DebugMessage("|cFFFF0000[DATA] Warning: No quests being tracked! Use /qdc rescan|r", 1, 0, 0)
        else
            for questId, _ in pairs(_activeTracking or {}) do
                local questData = QuestieDataCollection.quests[questId]
                if questData then
                    questData.objects = questData.objects or {}
                    
                    -- Use object name as key, but store ID if we have it
                    if not questData.objects[lootSourceName] then
                        questData.objects[lootSourceName] = {
                            name = lootSourceName,
                            id = lootSourceId,
                            locations = {}
                        }
                    elseif lootSourceId and not questData.objects[lootSourceName].id then
                        -- Update ID if we didn't have it before
                        questData.objects[lootSourceName].id = lootSourceId
                    end
                    
                    -- Add this location if not already tracked
                    if coords and coords.x and coords.y then
                        local locKey = string.format("%.1f,%.1f", coords.x, coords.y)
                        if not questData.objects[lootSourceName].locations[locKey] then
                            questData.objects[lootSourceName].locations[locKey] = {
                                coords = coords,
                                zone = zone,
                                subzone = subzone,
                                timestamp = time()
                            }
                            if lootSourceName ~= "Ground Object" then
                                DebugMessage("|cFF00FFFF[DATA] Tracked object '" .. lootSourceName .. 
                                    "' for quest " .. questId .. " at [" .. coords.x .. ", " .. coords.y .. "]|r", 0, 1, 1)
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Store loot source for item tracking
    _currentLootSource = {
        type = lootSourceType,
        id = lootSourceId,
        name = lootSourceName,
        coords = coords,
        zone = zone,
        subzone = subzone,
        timestamp = time()
    }
    
    -- Check all loot items
    local numItems = GetNumLootItems()
    for i = 1, numItems do
        local lootIcon, lootName, lootQuantity, rarity, locked = GetLootSlotInfo(i)
        if lootName then
            local itemLink = GetLootSlotLink(i)
            if itemLink then
                local itemId = tonumber(string.match(itemLink, "item:(%d+):"))
                
                -- Check if this is a quest item
                local isQuestItem = false
                local matchedQuestId = nil
                local matchedObjIndex = nil
                
                -- Check by name matching
                for questId, _ in pairs(_activeTracking or {}) do
                    local questData = QuestieDataCollection.quests[questId]
                    if questData then
                        for objIndex, objective in ipairs(questData.objectives or {}) do
                            if objective.type == "item" and (
                                string.find(string.lower(objective.text or ""), string.lower(lootName)) or
                                string.find(string.lower(lootName), string.lower(objective.lastText or ""))
                            ) then
                                isQuestItem = true
                                matchedQuestId = questId
                                matchedObjIndex = objIndex
                                break
                            end
                        end
                        if isQuestItem then break end
                    end
                end
                
                if isQuestItem and matchedQuestId then
                    local questData = QuestieDataCollection.quests[matchedQuestId]
                    if questData and questData.objectives and questData.objectives[matchedObjIndex] then
                        local objective = questData.objectives[matchedObjIndex]
                        -- This is a quest item!
                        objective.itemLootData = objective.itemLootData or {}
                        
                        local lootEntry = {
                            itemId = itemId,
                            itemName = lootName,
                            sourceType = lootSourceType,  -- "mob" or "object"
                            sourceId = lootSourceId,
                            sourceName = lootSourceName,
                            coords = coords,
                            zone = zone,
                            subzone = subzone,
                            timestamp = time()
                        }
                        
                        table.insert(objective.itemLootData, lootEntry)
                        
                        -- Also store in quest's items table
                        questData.items = questData.items or {}
                        questData.items[itemId] = {
                            name = lootName,
                            objectiveIndex = matchedObjIndex,
                            sources = questData.items[itemId] and questData.items[itemId].sources or {}
                        }
                        table.insert(questData.items[itemId].sources, lootEntry)
                        
                        if lootSourceType == "mob" then
                            DebugMessage("|cFF00FF00[DATA] Quest item '" .. lootName .. 
                                "' (ID: " .. itemId .. ") from mob: " .. lootSourceName .. "|r", 0, 1, 0)
                        else
                            DebugMessage("|cFF00AAFF[DATA] Quest item '" .. lootName .. 
                                "' (ID: " .. itemId .. ") from object: " .. lootSourceName .. "|r", 0, 0.67, 1)
                        end
                    end
                end
            end
        end
    end
end

function QuestieDataCollector:OnItemPush(bagSlot)
    -- Disabled - we capture this data via UI_INFO_MESSAGE now to avoid duplicates
    -- The UI_INFO_MESSAGE handler captures container data when quest progress updates
end

function QuestieDataCollector:OnUIInfoMessage(message)
    -- Only process if we have a message
    if not message or message == "" then return end
    
    -- Debug: Show UI_INFO_MESSAGE only when debug mode is on
    DebugMessage("|cFFFFFF00[DEBUG] UI_INFO_MESSAGE: " .. message .. "|r", 1, 1, 0)
    
    -- Check if this is a quest progress message (pattern: "Item Name: X/Y")
    local itemName, current, total = string.match(message, "(.+):%s*(%d+)/(%d+)")
    if not itemName then
        -- Try alternate pattern without colon
        itemName, current, total = string.match(message, "(.+)%s+(%d+)/(%d+)")
    end
    
    -- If it's not a progress message, we're done
    if not (itemName and current and total) then return end
    
    -- Debug: Show what we parsed
    if Questie.db.profile.debugDataCollector then
        DebugMessage("|cFFFFFF00[DEBUG] Quest progress detected: '" .. itemName .. "' " .. current .. "/" .. total .. "|r", 1, 1, 0)
    end
    
    -- We have a quest progress update!
    local coords = QuestieDataCollector:GetPlayerCoords()
    local zone = GetRealZoneText()
    local subzone = GetSubZoneText()
    local foundMatch = false
    
    -- Check if we're currently looting something (for ground objects)
    local objectData = nil
    if _lastInteractedObject and (time() - _lastInteractedObject.timestamp < 3) then
        -- Debug: Show what we're comparing
        if Questie.db.profile.debugDataCollector then
            DebugMessage("|cFFFFFF00[DEBUG] Checking container: _lastInteractedObject.name='" .. 
                (_lastInteractedObject.name or "nil") .. "' vs itemName='" .. itemName .. "'|r", 1, 1, 0)
        end
        
        -- Use the container name even if it matches the item name
        -- (Some containers like bananas are named the same as their contents!)
        objectData = {
            name = _lastInteractedObject.name,
            id = _lastInteractedObject.id,
            coords = coords,
            zone = zone,
            subzone = subzone
        }
        if Questie.db.profile.debugDataCollector then
            DebugMessage("|cFF00FF00[DEBUG] Container data prepared: " .. objectData.name .. "|r", 0, 1, 0)
        end
    else
        if Questie.db.profile.debugDataCollector then
            if not _lastInteractedObject then
                DebugMessage("|cFFFF0000[DEBUG] No _lastInteractedObject|r", 1, 0, 0)
            else
                DebugMessage("|cFFFF0000[DEBUG] _lastInteractedObject too old: " .. 
                    (time() - _lastInteractedObject.timestamp) .. " seconds|r", 1, 0, 0)
            end
        end
    end
    
    -- Find which quest this progress belongs to
    for questId, _ in pairs(_activeTracking) do
        local questData = QuestieDataCollection.quests[questId]
        if questData and not foundMatch then
            -- Check objectives for matching item
            for objIndex, objective in ipairs(questData.objectives or {}) do
                -- Check if this objective matches the item name
                -- Handle both singular and plural forms by removing trailing 's' for comparison
                local objTextLower = string.lower(objective.text or "")
                local itemNameLower = string.lower(itemName)
                local itemNameSingular = string.gsub(itemNameLower, "s$", "")  -- Remove trailing 's'
                local itemNamePlural = itemNameLower .. "s"
                
                -- Match if:
                -- 1. Exact match found in objective text
                -- 2. Singular form found in objective text (e.g., "Banana" matches "Bananas")
                -- 3. Plural form found in objective text
                -- 4. The objective is an item type and progress format matches (X/Y pattern)
                if string.find(objTextLower, itemNameLower) or
                   string.find(objTextLower, itemNameSingular) or
                   string.find(objTextLower, itemNamePlural) or
                   (objective.type == "item" and current and total) then
                    
                    foundMatch = true -- Found the matching quest/objective
                            
                    -- Store container/object information
                    if objectData then
                        objective.containers = objective.containers or {}
                        -- Check if we already have this container at this location
                        local found = false
                        for _, container in ipairs(objective.containers) do
                            if container.name == objectData.name and 
                               container.coords and objectData.coords and
                               math.abs(container.coords.x - objectData.coords.x) < 1 and
                               math.abs(container.coords.y - objectData.coords.y) < 1 then
                                found = true
                                break
                            end
                        end
                        if not found then
                            table.insert(objective.containers, objectData)
                            if objectData.name ~= "Unknown Container" then
                                DebugMessage("|cFF00FF00[DATA] Container captured: '" .. objectData.name .. 
                                    "' at [" .. coords.x .. ", " .. coords.y .. "]|r", 0, 1, 0)
                            else
                                DebugMessage("|cFFFF0000[DATA] Container location captured but name unknown at [" .. 
                                    coords.x .. ", " .. coords.y .. "]. Mouse over objects before looting!|r", 1, 0, 0)
                            end
                        end
                    end
                    
                    -- Update progress
                    objective.current = tonumber(current)
                    objective.total = tonumber(total)
                    
                    -- Store progress location (limit to prevent spam)
                    objective.progressLocations = objective.progressLocations or {}
                    -- Only add if the progress changed or location is significantly different
                    local shouldAdd = true
                    if #objective.progressLocations > 0 then
                        local last = objective.progressLocations[#objective.progressLocations]
                        if last.progress == current .. "/" .. total and 
                           last.coords and coords and
                           math.abs(last.coords.x - coords.x) < 2 and
                           math.abs(last.coords.y - coords.y) < 2 then
                            shouldAdd = false -- Same progress at nearby location
                        end
                    end
                    
                    if shouldAdd then
                        table.insert(objective.progressLocations, {
                            coords = coords,
                            zone = zone,
                            subzone = subzone,
                            progress = current .. "/" .. total,
                            container = objectData,
                            timestamp = time()
                        })
                        
                        -- Only show progress message once per update
                        DebugMessage("|cFF00FF00[DATA] Progress: " .. itemName .. " " .. current .. "/" .. total .. "|r", 0, 1, 0)
                    end
                    
                    break -- Stop checking objectives once we found a match
                end
            end
            
            if foundMatch then break end -- Stop checking quests once we found a match
        end
    end
    
    -- Store general exploration messages for all tracked quests (but not progress messages)
    if not foundMatch then
        for questId, _ in pairs(_activeTracking) do
            local questData = QuestieDataCollection.quests[questId]
            if questData then
                questData.explorations = questData.explorations or {}
                
                -- Store the exploration event
                local explorationData = {
                    message = message,
                    coords = coords,
                    zone = zone,
                    subzone = subzone,
                    timestamp = time()
                }
                table.insert(questData.explorations, explorationData)
                
                -- Check objectives for exploration/event types
                for objIndex, objective in ipairs(questData.objectives or {}) do
                    if objective.type == "event" or objective.type == "object" or 
                       string.find(string.lower(objective.text or ""), "explore") or
                       string.find(string.lower(objective.text or ""), "discover") or
                       string.find(string.lower(objective.text or ""), "find") or
                       string.find(string.lower(objective.text or ""), "reach") then
                        
                        -- Store as progress location
                        objective.progressLocations = objective.progressLocations or {}
                        table.insert(objective.progressLocations, {
                            coords = coords,
                            zone = zone,
                            subzone = subzone,
                            text = objective.text,
                            action = "Discovery: " .. message,
                            timestamp = time()
                        })
                        
                        -- Store specific discovery coordinates
                        objective.discoveryCoords = objective.discoveryCoords or {}
                        table.insert(objective.discoveryCoords, {
                            coords = coords,
                            zone = zone,
                            subzone = subzone,
                            trigger = message,
                            timestamp = time()
                        })
                        
                        DebugMessage("|cFF00FFFF[DATA] Discovery objective progress: " .. message .. "|r", 0, 1, 1)
                        DebugMessage("|cFF00FFFF  Location: [" .. coords.x .. ", " .. coords.y .. "] in " .. zone .. 
                            (subzone ~= "" and " (" .. subzone .. ")" or "") .. "|r", 0, 1, 1)
                    end
                end
                
                -- Always log exploration messages for Epoch quests
                if string.find(message, "Explored") or string.find(message, "Discovered") or 
                   string.find(message, "Reached") or string.find(message, "Found") then
                    DebugMessage("|cFF00FF00[DATA] Exploration captured: " .. message .. " at [" .. 
                        string.format("%.1f, %.1f", coords.x, coords.y) .. "]|r", 0, 1, 0)
                end
            end
        end
    end
end


-- Export function to generate database entry
function QuestieDataCollector:ExportQuest(questId)
    local data = QuestieDataCollection.quests[questId]
    if not data then
        DEFAULT_CHAT_FRAME:AddMessage("No data collected for quest " .. questId, 1, 0, 0)
        return
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("=== QUEST DATA EXPORT FOR #" .. questId .. " ===", 0, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("Quest: " .. (data.name or "Unknown"), 1, 1, 0)
    
    -- Quest giver info
    if data.questGiver then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("Quest Giver: %s (ID: %d) at %.1f, %.1f in %s",
            data.questGiver.name, data.questGiver.npcId, 
            data.questGiver.coords.x, data.questGiver.coords.y,
            data.questGiver.zone or "Unknown"), 0, 1, 0)
    end
    
    -- Turn in info
    if data.turnInNpc then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("Turn In: %s (ID: %d) at %.1f, %.1f in %s",
            data.turnInNpc.name, data.turnInNpc.npcId,
            data.turnInNpc.coords.x, data.turnInNpc.coords.y,
            data.turnInNpc.zone or "Unknown"), 0, 1, 0)
    end
    
    -- Objectives
    if data.objectives and #data.objectives > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("Objectives:", 0, 1, 1)
        for _, obj in ipairs(data.objectives) do
            DEFAULT_CHAT_FRAME:AddMessage("  - " .. obj, 1, 1, 1)
        end
    end
    
    -- Mobs tracked
    if data.mobs and next(data.mobs) then
        DEFAULT_CHAT_FRAME:AddMessage("Mobs:", 0, 1, 1)
        for mobId, mobData in pairs(data.mobs) do
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s (ID: %d) Level %s",
                mobData.name, mobId, mobData.level or "?"), 1, 1, 1)
            if mobData.coords and #mobData.coords > 0 then
                DEFAULT_CHAT_FRAME:AddMessage("    Locations:", 0.8, 0.8, 0.8)
                for i = 1, math.min(3, #mobData.coords) do
                    local coord = mobData.coords[i]
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("      %.1f, %.1f", coord.x, coord.y), 0.8, 0.8, 0.8)
                end
                if #mobData.coords > 3 then
                    DEFAULT_CHAT_FRAME:AddMessage("      ... and " .. (#mobData.coords - 3) .. " more locations", 0.8, 0.8, 0.8)
                end
            end
        end
    end
    
    -- Items looted
    if data.items and next(data.items) then
        DEFAULT_CHAT_FRAME:AddMessage("Items:", 0, 1, 1)
        for itemId, itemData in pairs(data.items) do
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s (ID: %d)",
                itemData.name, itemId), 1, 1, 1)
            if itemData.source then
                DEFAULT_CHAT_FRAME:AddMessage("    Source: " .. itemData.source, 0.8, 0.8, 0.8)
            end
        end
    end
    
    -- Objects interacted
    if data.objects and next(data.objects) then
        DEFAULT_CHAT_FRAME:AddMessage("Objects:", 0, 1, 1)
        for objName, objData in pairs(data.objects) do
            if objData.id then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s (ID: %d)", objName, objData.id), 1, 1, 1)
            else
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s", objName), 1, 1, 1)
            end
            if objData.locations then
                DEFAULT_CHAT_FRAME:AddMessage("    Locations:", 0.8, 0.8, 0.8)
                local locCount = 0
                for locKey, locData in pairs(objData.locations) do
                    locCount = locCount + 1
                    if locCount <= 3 then
                        DEFAULT_CHAT_FRAME:AddMessage(string.format("      %.1f, %.1f in %s", 
                            locData.coords.x, locData.coords.y, locData.zone or "Unknown"), 0.8, 0.8, 0.8)
                    end
                end
                if locCount > 3 then
                    DEFAULT_CHAT_FRAME:AddMessage("      ... and " .. (locCount - 3) .. " more locations", 0.8, 0.8, 0.8)
                end
            end
        end
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("=== END EXPORT ===", 0, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("Copy this data to create a GitHub issue", 0, 1, 0)
end

-- This slash command handler is replaced by the more complete one below

-- Helper function for creating clickable quest data links
CreateQuestDataLink = function(questId, questName)
    local linkText = "|cFF00FF00|Hquestiedata:" .. questId .. "|h[Click here to submit quest data]|h|r"
    return linkText
end

function QuestieDataCollector:ShowTrackedQuests()
    DEFAULT_CHAT_FRAME:AddMessage("=== Tracked Quest Data ===", 0, 1, 1)
    local incompleteCount = 0
    local completeCount = 0
    
    for questId, data in pairs(QuestieDataCollection.quests) do
        local status = _activeTracking[questId] and "|cFF00FF00[ACTIVE]|r" or "|cFFFFFF00[COMPLETE]|r"
        
        -- Add warning for incomplete data
        if data.wasAlreadyAccepted or data.incompleteData then
            status = status .. " |cFFFF0000[INCOMPLETE DATA]|r"
            incompleteCount = incompleteCount + 1
        else
            completeCount = completeCount + 1
        end
        
        DEFAULT_CHAT_FRAME:AddMessage(string.format("%s %d: %s", status, questId, data.name or "Unknown"), 1, 1, 1)
        
        if data.questGiver then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  Giver: %s (%d) at [%.1f, %.1f]", 
                data.questGiver.name, data.questGiver.npcId, 
                data.questGiver.coords.x, data.questGiver.coords.y), 0.7, 0.7, 0.7)
        elseif data.wasAlreadyAccepted then
            DEFAULT_CHAT_FRAME:AddMessage("  |cFFFF0000Quest Giver: MISSING (quest was already accepted)|r", 1, 0.5, 0)
        end
        
        if data.turnInNpc then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  Turn-in: %s (%d) at [%.1f, %.1f]", 
                data.turnInNpc.name, data.turnInNpc.npcId,
                data.turnInNpc.coords.x, data.turnInNpc.coords.y), 0.7, 0.7, 0.7)
        end
    end
    
    DEFAULT_CHAT_FRAME:AddMessage(string.format("\nTotal: %d quests (%d complete, %d incomplete)", 
        completeCount + incompleteCount, completeCount, incompleteCount), 1, 1, 0)
    
    if incompleteCount > 0 then
        DebugMessage("|cFFFF0000To get complete data: Abandon and re-accept quests marked as INCOMPLETE|r", 1, 0.5, 0)
    end
end

function QuestieDataCollector:ShowQuestSelectionWindow()
    -- Show ALL captured quest data in one window
    QuestieDataCollector:ShowExportWindow()
end

function QuestieDataCollector:ShowExportableQuests()
    local activeQuests = {}
    local completedQuests = {}
    
    -- Debug: Check what we're working with
    local totalCount = 0
    for _ in pairs(QuestieDataCollection.quests or {}) do
        totalCount = totalCount + 1
    end
    
    if totalCount == 0 then
        DebugMessage("|cFFFF0000[QUESTIE] No quest data found! Try /qdc debug to check status.|r", 1, 0, 0)
        return
    end
    
    -- Separate active and completed quests
    for questId, data in pairs(QuestieDataCollection.quests or {}) do
        -- All quests are valuable, even incomplete ones!
        -- Just mark them differently based on completion status
        if data.turnInNpc then
            -- Has turn-in data, so it's fully complete
            table.insert(completedQuests, {id = questId, data = data})
        else
            -- Partial data is still useful - may have quest giver, objectives, NPCs, etc.
            table.insert(completedQuests, {id = questId, data = data})
        end
    end
    
    if #activeQuests == 0 and #completedQuests == 0 then
        DebugMessage("|cFF00FF00[QUESTIE] No quest data captured yet.|r", 0, 1, 0)
        DebugMessage("|cFFFFFF00Accept and complete some [Epoch] quests to collect data!|r", 1, 1, 0)
        return
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("===========================================", 0, 1, 1)
    DebugMessage("|cFF00FF00[QUESTIE] Captured Quest Data:|r", 0, 1, 0)
    DEFAULT_CHAT_FRAME:AddMessage("===========================================", 0, 1, 1)
    
    -- Show all quests (all data is valuable!)
    if #completedQuests > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00QUESTS WITH DATA (All Can Be Exported):|r", 0, 1, 0)
        table.sort(completedQuests, function(a, b) return a.id < b.id end)
        
        for _, quest in ipairs(completedQuests) do
            local questName = quest.data.name or "Unknown Quest"
            local questId = quest.id
            
            -- Show quest with clickable export link and completion status
            local status = quest.data.turnInNpc and "|cFF00FF00[COMPLETE]|r" or "|cFFFFAA00[INCOMPLETE]|r"
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFFFFFF00%d: %s %s - |r" .. CreateQuestDataLink(questId), questId, questName, status), 1, 1, 0)
            
            -- Show data summary inline
            local hasGiver = quest.data.questGiver and "Giver" or ""
            local hasTurnIn = quest.data.turnInNpc and "Turn-in" or ""
            local npcCount = 0
            local itemCount = 0
            local objectCount = 0
            
            if quest.data.npcs then
                for _ in pairs(quest.data.npcs) do npcCount = npcCount + 1 end
            end
            if quest.data.items then
                for _ in pairs(quest.data.items) do itemCount = itemCount + 1 end
            end
            if quest.data.objects then
                for _ in pairs(quest.data.objects) do objectCount = objectCount + 1 end
            end
            
            local dataParts = {}
            if hasGiver ~= "" then table.insert(dataParts, hasGiver) end
            if hasTurnIn ~= "" then table.insert(dataParts, hasTurnIn) end
            if npcCount > 0 then table.insert(dataParts, npcCount .. " NPCs") end
            if itemCount > 0 then table.insert(dataParts, itemCount .. " Items") end
            if objectCount > 0 then table.insert(dataParts, objectCount .. " Objects") end
            
            if #dataParts > 0 then
                DEFAULT_CHAT_FRAME:AddMessage("    Data: " .. table.concat(dataParts, ", "), 0.7, 0.7, 0.7)
            end
        end
        DEFAULT_CHAT_FRAME:AddMessage("", 1, 1, 1)
    end
    
    -- Show active quests (still being tracked)
    if #activeQuests > 0 then
        DebugMessage("|cFFFFFF00ACTIVE QUESTS (Still Tracking):|r", 1, 1, 0)
        table.sort(activeQuests, function(a, b) return a.id < b.id end)
        
        for _, quest in ipairs(activeQuests) do
            local questName = quest.data.name or "Unknown Quest"
            local questId = quest.id
            
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFF888888%d: %s|r", questId, questName), 0.5, 0.5, 0.5)
            
            -- Show what data we have so far
            local dataParts = {}
            if quest.data.questGiver then table.insert(dataParts, "Giver") end
            if quest.data.npcs then 
                local count = 0
                for _ in pairs(quest.data.npcs) do count = count + 1 end
                if count > 0 then table.insert(dataParts, count .. " NPCs") end
            end
            if quest.data.items then
                local count = 0
                for _ in pairs(quest.data.items) do count = count + 1 end
                if count > 0 then table.insert(dataParts, count .. " Items") end
            end
            
            if #dataParts > 0 then
                DEFAULT_CHAT_FRAME:AddMessage("    Collected so far: " .. table.concat(dataParts, ", "), 0.5, 0.5, 0.5)
            else
                DEFAULT_CHAT_FRAME:AddMessage("    No data collected yet", 0.5, 0.5, 0.5)
            end
        end
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("===========================================", 0, 1, 1)
    DebugMessage("|cFFFFFF00Click [Export] links to submit quest data to GitHub|r", 1, 1, 0)
end

-- Community contribution popup
function QuestieDataCollector:ShowContributionPopup()
    StaticPopupDialogs["QUESTIE_CONTRIBUTE_DATA"] = {
        text = "|cFF00FF00Help Improve Questie for Project Epoch!|r\n\nWe've detected you're playing on Project Epoch. Many quests are missing from our database.\n\nWould you like to help the community by automatically collecting quest data? This will:\n\n• Alert you when accepting missing quests\n• Capture NPC locations and IDs\n• Enable tooltip IDs to show item/NPC/object IDs\n• Track where quest objectives are completed\n• Generate data for GitHub contributions\n\n|cFFFFFF00Your data will only be saved locally.|r",
        button1 = "Yes, I'll Help!",
        button2 = "No Thanks",
        OnAccept = function()
            Questie.db.profile.enableDataCollection = true
            Questie.db.profile.dataCollectionPrompted = true
            QuestieDataCollector:Initialize()
            QuestieDataCollector:EnableTooltipIDs()
            DebugMessage("|cFF00FF00[Questie] Thank you for contributing! Data collection is now active.|r", 0, 1, 0)
            DebugMessage("|cFFFFFF00Tooltip IDs have been enabled to help with data collection.|r", 1, 1, 0)
            DebugMessage("|cFFFFFF00When you complete a missing quest, we'll show you the data to submit.|r", 1, 1, 0)
        end,
        OnCancel = function()
            Questie.db.profile.dataCollectionPrompted = true
            DebugMessage("|cFFFFFF00[Questie] Data collection disabled. You can enable it later in Advanced settings.|r", 1, 1, 0)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false,
        preferredIndex = 3,
    }
    StaticPopup_Show("QUESTIE_CONTRIBUTE_DATA")
end

-- Export window for completed quests
function QuestieDataCollector:ShowExportWindow(questId)
    -- If no questId specified, show ALL quests
    if not questId then
        -- Check if we have any data at all
        if not QuestieDataCollection or not QuestieDataCollection.quests or not next(QuestieDataCollection.quests) then
            DebugMessage("|cFFFF0000[QUESTIE] No quest data to export. Complete some Epoch quests first!|r", 1, 0, 0)
            return
        end
    else
        -- Specific quest requested
        if not QuestieDataCollection or not QuestieDataCollection.quests then
            DebugMessage("|cFFFF0000[QUESTIE] No quest data available!|r", 1, 0, 0)
            return
        end
        
        local data = QuestieDataCollection.quests[questId]
        if not data then 
            DebugMessage("|cFFFF0000[QUESTIE] No data for quest " .. questId .. "!|r", 1, 0, 0)
            return 
        end
    end
    
    -- Create frame if it doesn't exist
    if not QuestieDataCollectorExportFrame then
        local f = CreateFrame("Frame", "QuestieDataCollectorExportFrame", UIParent)
        f:SetFrameStrata("DIALOG")
        f:SetWidth(600)
        f:SetHeight(400)
        f:SetPoint("CENTER")
        
        -- Use Questie's frame style
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        })
        
        -- Title
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -20)
        title:SetText("|cFF00FF00Quest Data Ready for Export|r")
        f.title = title
        
        -- Scroll frame for data (adjusted to use more space since we removed instructions)
        local scrollFrame = CreateFrame("ScrollFrame", "QuestieDataCollectorScrollFrame", f, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 20, -45)
        scrollFrame:SetPoint("BOTTOMRIGHT", -40, 55)
        
        local editBox = CreateFrame("EditBox", "QuestieDataCollectorEditBox", scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetFontObject(ChatFontNormal)
        editBox:SetWidth(540)
        editBox:SetAutoFocus(false)
        editBox:EnableMouse(true)
        -- Don't clear focus immediately - allow selection and copying
        editBox:SetScript("OnEditFocusGained", function(self) 
            self:HighlightText()  -- Auto-select all text when focused
        end)
        editBox:SetScript("OnEscapePressed", function() f:Hide() end)
        -- Prevent editing while allowing selection
        editBox:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                -- If user tries to type, restore original text
                self:SetText(self.originalText or "")
                self:HighlightText()
            end
        end)
        
        -- Set a large initial height for the edit box to enable scrolling
        editBox:SetHeight(2000)
        
        -- Enable mouse wheel scrolling
        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            local current = self:GetVerticalScroll()
            local maxScroll = self:GetVerticalScrollRange()
            local scrollStep = 30
            
            if delta > 0 then
                -- Scroll up
                self:SetVerticalScroll(math.max(0, current - scrollStep))
            else
                -- Scroll down
                self:SetVerticalScroll(math.min(maxScroll, current + scrollStep))
            end
        end)
        
        scrollFrame:SetScrollChild(editBox)
        f.editBox = editBox
        f.scrollFrame = scrollFrame
        
        -- Step 1: Go to GitHub button
        local githubButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        githubButton:SetPoint("BOTTOMLEFT", 20, 20)
        githubButton:SetWidth(140)
        githubButton:SetHeight(25)
        githubButton:SetText("|cFF00FF00Step 1:|r Go to GitHub")
        githubButton:SetScript("OnClick", function()
            -- Create a simple popup with the GitHub URL
            if not GitHubURLFrame then
                local popup = CreateFrame("Frame", "GitHubURLFrame", UIParent)
                popup:SetFrameStrata("TOOLTIP")
                popup:SetWidth(450)
                popup:SetHeight(120)
                popup:SetPoint("CENTER")
                popup:SetBackdrop({
                    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                    tile = true, tileSize = 32, edgeSize = 16,
                    insets = { left = 5, right = 5, top = 5, bottom = 5 }
                })
                
                -- Title text
                local titleText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                titleText:SetPoint("TOP", 0, -15)
                titleText:SetText("|cFFFFFFFFCopy this URL to your browser:|r")
                
                -- Create an EditBox for the URL so it can be selected
                local urlBox = CreateFrame("EditBox", nil, popup)
                urlBox:SetPoint("CENTER", 0, 5)
                urlBox:SetWidth(400)
                urlBox:SetHeight(20)
                urlBox:SetFontObject(GameFontHighlight)
                urlBox:SetText("https://github.com/trav346/Questie-Epoch/issues")
                urlBox:SetAutoFocus(false)
                urlBox:SetScript("OnEditFocusGained", function(self)
                    self:HighlightText()
                end)
                urlBox:SetScript("OnEscapePressed", function(self)
                    self:ClearFocus()
                    popup:Hide()
                end)
                -- Prevent editing but allow selection
                urlBox:SetScript("OnTextChanged", function(self, userInput)
                    if userInput then
                        self:SetText("https://github.com/trav346/Questie-Epoch/issues")
                        self:HighlightText()
                    end
                end)
                
                -- Visual frame around the EditBox
                local urlBorder = CreateFrame("Frame", nil, popup)
                urlBorder:SetPoint("CENTER", urlBox, "CENTER", 0, 0)
                urlBorder:SetWidth(410)
                urlBorder:SetHeight(30)
                urlBorder:SetBackdrop({
                    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 16,
                    insets = { left = 4, right = 4, top = 4, bottom = 4 }
                })
                urlBorder:SetBackdropColor(0, 0, 0, 0.5)
                
                -- Close button (centered)
                local closeBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
                closeBtn:SetPoint("BOTTOM", 0, 10)
                closeBtn:SetWidth(80)
                closeBtn:SetHeight(22)
                closeBtn:SetText("Close")
                closeBtn:SetScript("OnClick", function() popup:Hide() end)
                
                popup.urlBox = urlBox
            end
            GitHubURLFrame:Show()
            -- Auto-select the URL when showing
            GitHubURLFrame.urlBox:SetFocus()
            GitHubURLFrame.urlBox:HighlightText()
        end)
        
        -- Step 2: Copy Data button
        local copyButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        copyButton:SetPoint("BOTTOM", 0, 20)
        copyButton:SetWidth(180)
        copyButton:SetHeight(25)
        copyButton:SetText("|cFF00FF00Step 2:|r Copy Collected Data")
        copyButton:SetScript("OnClick", function()
            editBox:SetFocus()
            editBox:HighlightText()
            DebugMessage("|cFF00FF00Data selected! Press Ctrl+C to copy, then paste in GitHub issue.|r", 0, 1, 0)
        end)
        
        -- Step 3: Close & Purge button
        local purgeButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        purgeButton:SetPoint("BOTTOMRIGHT", -20, 20)
        purgeButton:SetWidth(160)
        purgeButton:SetHeight(25)
        purgeButton:SetText("|cFF00FF00Step 3:|r Close & Purge Data")
        purgeButton:SetScript("OnClick", function()
            -- Clear ALL quest data from the saved variable
            _G.QuestieDataCollection = {
                quests = {},
                enableDataCollection = QuestieDataCollection and QuestieDataCollection.enableDataCollection or false
            }
            -- Also clear the local reference
            QuestieDataCollection = _G.QuestieDataCollection
            
            -- Force the cleared state to be saved immediately
            -- This ensures the empty state persists after reload
            local db = Questie.db.global
            if db then
                db.dataCollectionQuests = {}
            end
            
            DebugMessage("|cFF00FF00[QUESTIE] Thank you for contributing! All collected quest data has been purged.|r", 0, 1, 0)
            DebugMessage("|cFFFFFF00Your local quest data storage has been cleared to free up memory.|r", 1, 1, 0)
            f:Hide()
        end)
        
        -- Close button
        local closeButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeButton:SetPoint("TOPRIGHT", -5, -5)
        closeButton:SetScript("OnClick", function() f:Hide() end)
        
        f:Hide()
    end
    
    -- Generate export data
    local exportText = ""
    
    if questId then
        -- Single quest export
        local data = QuestieDataCollection.quests[questId]
        exportText = QuestieDataCollector:GenerateExportText(questId, data)
    else
        -- Export ALL quests
        local questList = {}
        for qId, _ in pairs(QuestieDataCollection.quests) do
            -- Include all Epoch quests (26000+)
            if qId >= 26000 then
                table.insert(questList, qId)
            end
        end
        
        -- Sort by quest ID
        table.sort(questList)
        
        if #questList == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[QUESTIE] No Epoch quest data to export!|r", 1, 0, 0)
            return
        end
        
        -- Generate combined export text
        exportText = "=== BATCH QUEST DATA SUBMISSION ===\n"
        exportText = exportText .. "Total Quests: " .. #questList .. "\n"
        exportText = exportText .. "Addon Version: " .. (QuestieLib and QuestieLib:GetAddonVersionString() or "Unknown") .. "\n"
        exportText = exportText .. "Data Exported: " .. date("%Y-%m-%d %H:%M:%S") .. "\n\n"
        -- Create comma-separated list of quest IDs for the title
        local questIdList = table.concat(questList, ", ")
        exportText = exportText .. "=== GITHUB ISSUE TITLE ===\n"
        exportText = exportText .. "Missing Quests: " .. questIdList .. "\n\n"
        exportText = exportText .. "=== PASTE EVERYTHING BELOW THIS LINE ===\n\n"
        
        for _, qId in ipairs(questList) do
            local data = QuestieDataCollection.quests[qId]
            exportText = exportText .. "════════════════════════════════════════\n"
            -- Skip instructions for batch exports since they're already at the top
            exportText = exportText .. QuestieDataCollector:GenerateExportText(qId, data, true)
            exportText = exportText .. "\n"
        end
    end
    
    -- Update and show frame
    QuestieDataCollectorExportFrame.editBox:SetText(exportText)
    QuestieDataCollectorExportFrame.editBox.originalText = exportText  -- Store for OnTextChanged handler
    QuestieDataCollectorExportFrame.editBox:SetCursorPosition(0)  -- Start at top of text
    
    -- Reset scroll position to top
    if QuestieDataCollectorExportFrame.scrollFrame then
        QuestieDataCollectorExportFrame.scrollFrame:SetVerticalScroll(0)
    end
    
    QuestieDataCollectorExportFrame:Show()
end

function QuestieDataCollector:GenerateExportText(questId, data, skipInstructions)
    local text = ""
    
    if not skipInstructions then
        text = "=== GITHUB ISSUE TITLE ===\n"
        text = text .. "Missing Quest: " .. (data.name or "Unknown") .. " (ID: " .. questId .. ")\n\n"
        text = text .. "=== PASTE EVERYTHING BELOW THIS LINE ===\n\n"
    end
    
    text = text .. "=== QUEST DATA ===\n\n"
    
    -- Add addon version and collection date for debugging
    text = text .. "Addon Version: " .. (QuestieLib and QuestieLib:GetAddonVersionString() or "Unknown") .. "\n"
    text = text .. "Data Collected: " .. date("%Y-%m-%d %H:%M:%S") .. "\n\n"
    
    -- Add warning if quest has incomplete data
    if data.wasAlreadyAccepted or data.incompleteData then
        text = text .. "WARNING: INCOMPLETE DATA\n"
        text = text .. "This quest was already in the quest log when the addon was installed.\n"
        text = text .. "Quest giver NPC information is missing.\n"
        text = text .. "Please abandon and re-accept this quest for complete data.\n\n"
    elseif not data.turnInNpc then
        text = text .. "NOTE: QUEST NOT YET COMPLETED\n"
        text = text .. "Turn-in NPC data is missing (quest still in progress).\n"
        text = text .. "This partial data is still valuable and can be submitted!\n\n"
    end
    
    text = text .. "Quest ID: " .. questId .. "\n"
    text = text .. "Quest Name: " .. (data.name or "Unknown") .. "\n"
    text = text .. "Level: " .. (data.level or "Unknown") .. "\n"
    text = text .. "Zone: " .. (data.zone or "Unknown") .. "\n"
    -- Use current player's faction if not stored in data
    text = text .. "Faction: " .. (data.faction or UnitFactionGroup("player") or "Unknown") .. "\n\n"
    
    if data.questGiver then
        text = text .. "QUEST GIVER:\n"
        text = text .. "  NPC: " .. data.questGiver.name .. " (ID: " .. data.questGiver.npcId .. ")\n"
        text = text .. "  Location: [" .. data.questGiver.coords.x .. ", " .. data.questGiver.coords.y .. "]\n"
        text = text .. "  Zone: " .. data.questGiver.zone .. "\n\n"
    end
    
    if data.objectives and #data.objectives > 0 then
        text = text .. "OBJECTIVES:\n"
        for i, obj in ipairs(data.objectives) do
            text = text .. "  " .. i .. ". " .. obj.text .. " (" .. (obj.type or "unknown") .. ")\n"
            
            -- Show item IDs if collected
            if obj.itemId then
                text = text .. "     Item: " .. obj.itemName .. " (ID: " .. obj.itemId .. ")\n"
            end
            
            -- Show NPC IDs for kill objectives
            -- Check both npcs and mobLocations for mob data
            if obj.npcs then
                text = text .. "     NPCs: "
                for npcId, npcName in pairs(obj.npcs) do
                    text = text .. npcName .. " (ID: " .. npcId .. ") "
                end
                text = text .. "\n"
            elseif obj.mobLocations and #obj.mobLocations > 0 then
                text = text .. "     Mobs tracked:\n"
                local mobsByName = {}
                for _, mobLoc in ipairs(obj.mobLocations) do
                    if not mobsByName[mobLoc.name] then
                        mobsByName[mobLoc.name] = {
                            id = mobLoc.npcId,
                            locations = {}
                        }
                    end
                    table.insert(mobsByName[mobLoc.name].locations, {
                        coords = mobLoc.coords,
                        zone = mobLoc.zone
                    })
                end
                
                for mobName, mobInfo in pairs(mobsByName) do
                    text = text .. "       - " .. mobName .. " (ID: " .. mobInfo.id .. ")\n"
                    if #mobInfo.locations > 0 then
                        for i = 1, math.min(3, #mobInfo.locations) do
                            local loc = mobInfo.locations[i]
                            text = text .. "         [" .. loc.coords.x .. ", " .. loc.coords.y .. "] in " .. loc.zone .. "\n"
                        end
                        if #mobInfo.locations > 3 then
                            text = text .. "         ... and " .. (#mobInfo.locations - 3) .. " more locations\n"
                        end
                    end
                end
            end
            
            -- Show containers/objects for collection objectives
            if obj.containers and #obj.containers > 0 then
                text = text .. "     |cFF00FF00Containers/Objects:|r\n"
                for _, cont in ipairs(obj.containers) do
                    text = text .. "       - " .. cont.name
                    if cont.id then
                        text = text .. " (ID: " .. cont.id .. ")"
                    end
                    text = text .. " at [" .. cont.coords.x .. ", " .. cont.coords.y .. "] in " .. cont.zone .. "\n"
                end
            end
            
            -- Show progress locations
            if obj.progressLocations and #obj.progressLocations > 0 then
                text = text .. "     Progress locations:\n"
                for _, loc in ipairs(obj.progressLocations) do
                    text = text .. "       - [" .. loc.coords.x .. ", " .. loc.coords.y .. "] in " .. loc.zone
                    if loc.action then
                        text = text .. " - " .. loc.action
                    end
                    text = text .. "\n"
                end
            end
        end
        text = text .. "\n"
    end
    
    -- Only show quest items (items that are objective requirements)
    if data.items then
        local questItems = {}
        for itemId, itemInfo in pairs(data.items) do
            if itemInfo.objectiveIndex then  -- Only quest items have objective index
                questItems[itemId] = itemInfo
            end
        end
        
        if next(questItems) then
            text = text .. "QUEST ITEMS:\n"
            for itemId, itemInfo in pairs(questItems) do
                text = text .. "  " .. itemInfo.name .. " (ID: " .. itemId .. ")\n"
                
                -- Show drop sources if available
                if itemInfo.sources and #itemInfo.sources > 0 then
                    local mobSources = {}
                    local objectSources = {}
                    
                    for _, source in ipairs(itemInfo.sources) do
                        if source.sourceType == "mob" and source.sourceName then
                            mobSources[source.sourceName] = source.sourceId or true
                        elseif source.sourceType == "object" and source.sourceName then
                            objectSources[source.sourceName] = true
                        end
                    end
                    
                    for mobName, mobId in pairs(mobSources) do
                        if type(mobId) == "number" then
                            text = text .. "    Drops from: " .. mobName .. " (ID: " .. mobId .. ")\n"
                        else
                            text = text .. "    Drops from: " .. mobName .. "\n"
                        end
                    end
                    
                    for objName, _ in pairs(objectSources) do
                        text = text .. "    From object: " .. objName .. "\n"
                    end
                end
            end
            text = text .. "\n"
        end
    end
    
    -- Show objects/containers at quest level (legacy format)
    if data.objects and next(data.objects) then
        text = text .. "GROUND OBJECTS/CONTAINERS:\n"
        for objName, objData in pairs(data.objects) do
            text = text .. "  " .. objName
            if objData.id then
                text = text .. " (ID: " .. objData.id .. ")"
            end
            
            -- Handle both old format (coords) and new format (locations table)
            if objData.coords then
                text = text .. " at [" .. objData.coords.x .. ", " .. objData.coords.y .. "]"
                if objData.zone then
                    text = text .. " in " .. objData.zone
                end
            elseif objData.locations then
                -- New format with multiple locations
                local first = true
                for locKey, locData in pairs(objData.locations) do
                    if first then
                        text = text .. " at [" .. locData.coords.x .. ", " .. locData.coords.y .. "] in " .. (locData.zone or "Unknown")
                        first = false
                    else
                        text = text .. "\n       Additional location: [" .. locData.coords.x .. ", " .. locData.coords.y .. "] in " .. (locData.zone or "Unknown")
                    end
                end
            end
            text = text .. "\n"
        end
        text = text .. "\n"
    end
    
    if data.turnInNpc then
        text = text .. "TURN-IN NPC:\n"
        text = text .. "  NPC: " .. data.turnInNpc.name .. " (ID: " .. data.turnInNpc.npcId .. ")\n"
        text = text .. "  Location: [" .. data.turnInNpc.coords.x .. ", " .. data.turnInNpc.coords.y .. "]\n"
        text = text .. "  Zone: " .. data.turnInNpc.zone .. "\n\n"
    end
    
    text = text .. "DATABASE ENTRIES:\n"
    text = text .. "-- Add to epochQuestDB.lua:\n"
    
    local questGiver = data.questGiver and "{{" .. data.questGiver.npcId .. "}}" or "nil"
    local turnIn = data.turnInNpc and "{{" .. data.turnInNpc.npcId .. "}}" or "nil"
    
    text = text .. string.format('[%d] = {"%s",%s,%s,nil,%d,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,85,nil,nil,nil,nil,nil,nil,0,nil,nil,nil,nil,nil,nil},\n\n',
        questId, data.name or "Unknown", questGiver, turnIn, data.level or 1)
    
    if data.questGiver then
        text = text .. "-- Add to epochNpcDB.lua:\n"
        text = text .. string.format('[%d] = {"%s",nil,nil,%d,%d,0,{[85]={{%.1f,%.1f}}},nil,85,{%d},nil,nil,nil,nil,0},\n',
            data.questGiver.npcId, data.questGiver.name, data.level or 1, data.level or 1,
            data.questGiver.coords.x, data.questGiver.coords.y, questId)
    end
    
    if data.turnInNpc and (not data.questGiver or data.turnInNpc.npcId ~= data.questGiver.npcId) then
        text = text .. string.format('[%d] = {"%s",nil,nil,%d,%d,0,{[85]={{%.1f,%.1f}}},nil,85,nil,{%d},nil,nil,nil,0},\n',
            data.turnInNpc.npcId, data.turnInNpc.name, data.level or 1, data.level or 1,
            data.turnInNpc.coords.x, data.turnInNpc.coords.y, questId)
    end
    
    return text
end

-- Create clickable hyperlink for quest data submission
-- Hook for custom hyperlink handling
local originalSetItemRef = SetItemRef
SetItemRef = function(link, text, button)
    if string.sub(link, 1, 11) == "questiedata" then
        local questId = tonumber(string.sub(link, 13))
        if questId then
            QuestieDataCollector:ShowExportWindow(questId)
        end
    else
        originalSetItemRef(link, text, button)
    end
end

-- Modified turn-in handler to show export window
local originalOnQuestTurnedIn = QuestieDataCollector.OnQuestTurnedIn
function QuestieDataCollector:OnQuestTurnedIn(questId)
    originalOnQuestTurnedIn(self, questId)
    
    -- If this was a tracked quest and data collection is enabled
    if questId and QuestieDataCollection.quests[questId] and Questie.db.profile.enableDataCollection then
        local questData = QuestieDataCollection.quests[questId]
        local questName = questData.name or "Unknown Quest"
        
        -- Play subtle sound for quest completion
        PlaySound("QUESTCOMPLETED")
        
        -- Print hyperlink notification in chat (no auto-popup)
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[QUESTIE] Epoch quest completed! Please " .. CreateQuestDataLink(questId) .. "|r", 0, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Quest: " .. questName .. " (ID: " .. questId .. ")|r", 1, 1, 0)
    end
end

-- Auto-initialize on first load if enabled
local autoInitFrame = CreateFrame("Frame")
autoInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
autoInitFrame:RegisterEvent("ADDON_LOADED")
autoInitFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Questie" then
        -- Try initializing as soon as Questie loads
        C_Timer.After(0.1, function()
            if Questie and Questie.db and Questie.db.profile.enableDataCollection then
                if not _initialized then
                    -- Silently initialize - we'll show the message in Initialize()
                    QuestieDataCollector:Initialize()
                end
            end
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Don't unregister - we need this for every login/reload
        -- Reinitialize after every login to ensure tracking continues
        C_Timer.After(0.5, function()
            if Questie and Questie.db and Questie.db.profile.enableDataCollection then
                -- Always reinitialize after login to restore tracking (silently)
                QuestieDataCollector:Initialize()
            end
        end)
    end
end)

-- Register slash commands for debugging and control
SLASH_QUESTIEDATACOLLECTOR1 = "/qdc"
SlashCmdList["QUESTIEDATACOLLECTOR"] = function(msg)
    local cmd = string.lower(msg)
    
    if cmd == "enable" then
        Questie.db.profile.enableDataCollection = true
        Questie.db.profile.dataCollectionPrompted = true
        
        -- Force re-initialization even if already initialized
        _initialized = false
        QuestieDataCollector.eventFrame = nil
        
        QuestieDataCollector:Initialize()
        QuestieDataCollector:EnableTooltipIDs()
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[DATA COLLECTOR] ENABLED!|r", 0, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Abandon and re-accept quests to collect data|r", 1, 1, 0)
        
    elseif cmd == "disable" then
        Questie.db.profile.enableDataCollection = false
        QuestieDataCollector:RestoreTooltipIDs()
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[DATA COLLECTOR] DISABLED|r", 1, 0, 0)
        
    elseif cmd == "status" then
        DEFAULT_CHAT_FRAME:AddMessage("=== DATA COLLECTOR STATUS ===", 0, 1, 1)
        if Questie.db.profile.enableDataCollection then
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00Collection: ENABLED|r", 0, 1, 0)
            if Questie.db.profile.showDataCollectionMessages then
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Messages: SHOWN|r", 1, 1, 0)
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00Messages: HIDDEN (silent mode)|r", 0, 1, 0)
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000Collection: DISABLED|r", 1, 0, 0)
        end
        
        -- Check initialization status
        DEFAULT_CHAT_FRAME:AddMessage("Initialized: " .. (_initialized and "|cFF00FF00YES|r" or "|cFFFF0000NO|r"))
        DEFAULT_CHAT_FRAME:AddMessage("Event Frame: " .. (QuestieDataCollector.eventFrame and "|cFF00FF00EXISTS|r" or "|cFFFF0000MISSING|r"))
        
        -- Check if QUEST_ACCEPTED is registered
        if QuestieDataCollector.eventFrame then
            local registered = QuestieDataCollector.eventFrame:IsEventRegistered("QUEST_ACCEPTED")
            DEFAULT_CHAT_FRAME:AddMessage("QUEST_ACCEPTED registered: " .. (registered and "|cFF00FF00YES|r" or "|cFFFF0000NO|r"))
        end
        
        if QuestieDataCollection and QuestieDataCollection.quests then
            local count = 0
            for _ in pairs(QuestieDataCollection.quests) do count = count + 1 end
            DEFAULT_CHAT_FRAME:AddMessage("Tracked quests: " .. count, 1, 1, 1)
        else
            DEFAULT_CHAT_FRAME:AddMessage("No data collected yet", 1, 1, 0)
        end
        
    elseif cmd == "test" then
        -- Force test with current target quest
        DEFAULT_CHAT_FRAME:AddMessage("Testing with quest 26926...", 0, 1, 1)
        QuestieDataCollector:OnQuestAccepted(26926)
        
    elseif cmd == "active" then
        -- Show actively tracked quests
        DebugMessage("|cFFFFFF00=== Actively Tracked Quests ===|r", 1, 1, 0)
        local count = 0
        for questId, _ in pairs(_activeTracking or {}) do
            count = count + 1
            local questData = QuestieDataCollection.quests[questId]
            if questData then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  %d: %s", questId, questData.name or "Unknown"), 0, 1, 0)
            else
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  %d: (no data yet)", questId), 1, 0.5, 0)
            end
        end
        if count == 0 then
            DebugMessage("|cFFFF0000No quests currently being tracked! Use /qdc rescan|r", 1, 0, 0)
        else
            DEFAULT_CHAT_FRAME:AddMessage(string.format("Total: %d quest(s) being tracked", count), 0.7, 0.7, 0.7)
        end
    
    elseif cmd == "questlog" then
        -- Show all quests in quest log
        DebugMessage("|cFFFFFF00=== Quest Log ===|r", 1, 1, 0)
        for i = 1, GetNumQuestLogEntries() do
            local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID = QuestieCompat.GetQuestLogTitle(i)
            if not isHeader and questID and questID > 0 then
                local color = "|cFFFFFFFF"
                if questID >= 26000 then  -- All Epoch quests
                    color = "|cFFFF00FF" -- Magenta for Epoch quests
                end
                DEFAULT_CHAT_FRAME:AddMessage(string.format("%s  %d: %s (Level %d)|r", color, questID, title or "Unknown", level or 0), 1, 1, 1)
            end
        end
    
    elseif string.sub(cmd, 1, 5) == "track" then
        -- Manually track a specific quest for testing
        local questId = tonumber(string.sub(cmd, 7))
        if questId then
            -- Check if quest is in quest log
            local inQuestLog = false
            local questTitle = nil
            for i = 1, GetNumQuestLogEntries() do
                local title, level, _, isHeader, _, _, _, qId = QuestieCompat.GetQuestLogTitle(i)
                if not isHeader and qId == questId then
                    inQuestLog = true
                    questTitle = title
                    break
                end
            end
            
            if inQuestLog then
                _activeTracking[questId] = true
                -- Initialize quest data if not exists
                if not QuestieDataCollection.quests[questId] then
                    QuestieDataCollection.quests[questId] = {
                        id = questId,
                        name = questTitle,
                        acceptTime = time(),
                        zone = GetRealZoneText(),
                        objectives = {},
                        npcs = {},
                        items = {},
                        objects = {},
                        sessionStart = date("%Y-%m-%d %H:%M:%S")
                    }
                end
                DebugMessage("|cFF00FF00[DATA] Now tracking quest " .. questId .. ": " .. (questTitle or "Unknown") .. "|r", 0, 1, 0)
            else
                DebugMessage("|cFFFF0000[DATA] Quest " .. questId .. " not found in your quest log|r", 1, 0, 0)
            end
        else
            DebugMessage("|cFFFFFF00Usage: /qdc track <questId>|r", 1, 1, 0)
        end
        
    elseif string.sub(cmd, 1, 6) == "export" then
        -- Export specific quest or show selection window
        local questId = tonumber(string.sub(cmd, 8))
        -- DEBUG: Export command received
        if questId then
            -- Export specific quest: /qdc export 26934
            DebugMessage("|cFFCCCCCC[DEBUG] Calling ShowExportWindow with questId: " .. questId .. "|r", 0.8, 0.8, 0.8)
            QuestieDataCollector:ShowExportWindow(questId)
        else
            -- No quest ID specified, show selection window
            -- DEBUG: Calling ShowQuestSelectionWindow
            QuestieDataCollector:ShowQuestSelectionWindow()
        end
        
    elseif string.sub(cmd, 1, 6) == "turnin" then
        -- Manual turn-in capture: /qdc turnin <questId>
        local questId = tonumber(string.sub(cmd, 8))
        if questId and QuestieDataCollection.quests[questId] then
            -- Capture current target as turn-in NPC
            if UnitExists("target") and not UnitIsPlayer("target") then
                local name = UnitName("target")
                local guid = UnitGUID("target")
                local npcId = nil
                
                if guid then
                    npcId = tonumber(guid:sub(6, 12), 16)
                end
                
                if npcId then
                    local coords = QuestieDataCollector:GetPlayerCoords()
                    QuestieDataCollection.quests[questId].turnInNpc = {
                        npcId = npcId,
                        name = name,
                        coords = coords,
                        zone = GetRealZoneText(),
                        subzone = GetSubZoneText(),
                        timestamp = time()
                    }
                    
                    DebugMessage("|cFF00FF00[DATA] Turn-in NPC manually captured: " .. name .. " (ID: " .. npcId .. ")|r", 0, 1, 0)
                    DebugMessage("|cFF00FF00Quest " .. questId .. " now has complete data!|r", 0, 1, 0)
                else
                    DebugMessage("|cFFFF0000[DATA] Error: Could not get NPC ID from target|r", 1, 0, 0)
                end
            else
                DebugMessage("|cFFFF0000[DATA] Error: Target an NPC first|r", 1, 0, 0)
            end
        else
            DebugMessage("|cFFFF0000[DATA] Usage: /qdc turnin <questId> (while targeting the turn-in NPC)|r", 1, 0, 0)
        end
        
    elseif cmd == "messages" then
        -- Toggle message visibility
        Questie.db.profile.showDataCollectionMessages = not Questie.db.profile.showDataCollectionMessages
        if Questie.db.profile.showDataCollectionMessages then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[DATA COLLECTOR] Messages ENABLED - you will see [DATA] messages|r", 1, 1, 0)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[DATA COLLECTOR] Messages DISABLED - collecting silently|r", 0, 1, 0)
        end
        
    elseif cmd == "clear" then
        QuestieDataCollection = {quests = {}, version = 1, sessionStart = date("%Y-%m-%d %H:%M:%S")}
        _activeTracking = {} -- Also clear active tracking
        DebugMessage("|cFF00FF00[DATA COLLECTOR] All quest data cleared.|r", 0, 1, 0)
        -- Automatically rescan to re-initialize tracking for current quests
        QuestieDataCollector:CheckExistingQuests()
        local count = 0
        for questId, _ in pairs(_activeTracking or {}) do
            count = count + 1
        end
        if count > 0 then
            DebugMessage("|cFF00FF00[DATA COLLECTOR] Re-initialized tracking for " .. count .. " quests in your log|r", 0, 1, 0)
        end
        DebugMessage("|cFFFFFF00Do /reload to save the cleared state.|r", 1, 1, 0)
        
    elseif cmd == "rescan" then
        -- Re-scan quest log for missing quests
        DebugMessage("|cFFFFFF00[QuestieDataCollector] Starting rescan...|r", 1, 1, 0)
        _activeTracking = {} -- Clear current tracking
        QuestieDataCollector:CheckExistingQuests()
        local count = 0
        for questId, _ in pairs(_activeTracking or {}) do
            count = count + 1
        end
        DebugMessage("|cFF00FF00[QuestieDataCollector] Re-scanned quest log. Now tracking " .. count .. " quests|r", 0, 1, 0)
    elseif cmd == "save" then
        -- Force save data to SavedVariables
        DebugMessage("|cFFFFFF00[DATA COLLECTOR] Forcing save of quest data...|r", 1, 1, 0)
        
        -- Ensure the global is accessible
        if not _G.QuestieDataCollection then
            _G.QuestieDataCollection = {}
        end
        if not _G.QuestieDataCollection.quests then
            _G.QuestieDataCollection.quests = {}
        end
        
        -- Count quests
        local count = 0
        for questId, questData in pairs(QuestieDataCollection.quests or {}) do
            count = count + 1
            -- Force write to global
            _G.QuestieDataCollection.quests[questId] = questData
        end
        
        DebugMessage("|cFF00FF00[DATA COLLECTOR] Saved " .. count .. " quests to SavedVariables|r", 0, 1, 0)
        DebugMessage("|cFFFFFF00Use /reload to persist to disk|r", 1, 1, 0)
        
    elseif cmd == "check" and args then
        -- Check specific quest data (e.g., /qdc check 28757 for banana quest)
        local questId = tonumber(args)
        if questId then
            local data = QuestieDataCollection.quests[questId]
            if data then
                DebugMessage("|cFF00FF00[DATA] Quest " .. questId .. " data found:|r", 0, 1, 0)
                DebugMessage("  Name: " .. (data.name or "Unknown"), 1, 1, 1)
                DEFAULT_CHAT_FRAME:AddMessage("  Level: " .. (data.level or "?"), 1, 1, 1)
                
                -- Check objectives
                if data.objectives and #data.objectives > 0 then
                    DEFAULT_CHAT_FRAME:AddMessage("  Objectives:", 1, 1, 1)
                    for i, obj in ipairs(data.objectives) do
                        DEFAULT_CHAT_FRAME:AddMessage("    " .. i .. ": " .. (obj.text or "Unknown"), 0.8, 0.8, 0.8)
                        if obj.containers and #obj.containers > 0 then
                            DebugMessage("      |cFF00FF00Containers: " .. #obj.containers .. " found|r", 0, 1, 0)
                            for _, cont in ipairs(obj.containers) do
                                DEFAULT_CHAT_FRAME:AddMessage(string.format("        %s at [%.1f, %.1f]", 
                                    cont.name, cont.coords.x, cont.coords.y), 0.6, 0.6, 1)
                            end
                        else
                            DebugMessage("      |cFFFF0000No containers captured yet|r", 1, 0, 0)
                        end
                    end
                else
                    DEFAULT_CHAT_FRAME:AddMessage("  |cFFFF0000Objectives: None captured yet|r", 1, 0.5, 0)
                end
                
                -- Check NPCs
                if data.npcs then
                    local npcCount = 0
                    for _ in pairs(data.npcs) do npcCount = npcCount + 1 end
                    DEFAULT_CHAT_FRAME:AddMessage("  NPCs: " .. npcCount .. " tracked", 1, 1, 1)
                end
                
                -- Check objects/containers at quest level
                if data.objects then
                    local objCount = 0
                    for objName, objData in pairs(data.objects) do 
                        objCount = objCount + 1
                        DEFAULT_CHAT_FRAME:AddMessage("  Object: " .. objName, 0.6, 0.6, 1)
                    end
                    if objCount > 0 then
                        DEFAULT_CHAT_FRAME:AddMessage("  |cFF00FF00Objects: " .. objCount .. " tracked|r", 0, 1, 0)
                    end
                end
                
                DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFFF00Tracked: " .. (_activeTracking[questId] and "YES" or "NO") .. "|r", 1, 1, 0)
                
                -- Show if quest was already accepted
                if data.wasAlreadyAccepted then
                    DEFAULT_CHAT_FRAME:AddMessage("  |cFFFF0000WARNING: Quest was already in log when tracking started|r", 1, 0, 0)
                    DEFAULT_CHAT_FRAME:AddMessage("  |cFFFF0000Missing quest giver data. Abandon and re-accept for complete data.|r", 1, 0, 0)
                end
            else
                DebugMessage("|cFFFF0000[DATA] Quest " .. questId .. " not found in data collection|r", 1, 0, 0)
                DebugMessage("|cFFFFFF00Is data collection enabled? Try: /qdc enable|r", 1, 1, 0)
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000Usage: /qdc check <questId>|r", 1, 0, 0)
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Example: /qdc check 28757 (for banana quest)|r", 1, 1, 0)
        end
        
    elseif cmd == "test" then
        DebugMessage("|cFFFFFF00[QDC Test] Checking if collector is working...|r", 1, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("  Initialized: " .. tostring(_initialized), 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("  Enabled: " .. tostring(Questie and Questie.db and Questie.db.profile.enableDataCollection), 1, 1, 1)
        local count = 0
        for k,v in pairs(_activeTracking or {}) do count = count + 1 end
        DEFAULT_CHAT_FRAME:AddMessage("  Tracking: " .. count .. " quests", 1, 1, 1)
        
    elseif cmd == "debug" then
        -- Toggle debug mode
        if not Questie.db.profile.debugDataCollector then
            Questie.db.profile.debugDataCollector = true
            DebugMessage("|cFFFF0000[Questie Data Collector]|r Debug mode ENABLED - will show table quest IDs", 1, 0, 0)
        else
            Questie.db.profile.debugDataCollector = false
            DebugMessage("|cFFFF0000[Questie Data Collector]|r Debug mode DISABLED", 1, 0, 0)
        end
        DEFAULT_CHAT_FRAME:AddMessage("QuestieDataCollection table:", 0, 1, 1)
        if QuestieDataCollection then
            DEFAULT_CHAT_FRAME:AddMessage("  Exists: YES", 0, 1, 0)
            DEFAULT_CHAT_FRAME:AddMessage("  Type: " .. type(QuestieDataCollection), 1, 1, 1)
            if QuestieDataCollection.quests then
                local count = 0
                for k,v in pairs(QuestieDataCollection.quests) do 
                    count = count + 1
                    DEFAULT_CHAT_FRAME:AddMessage("    Quest " .. k .. ": " .. (v.name or "Unknown"), 1, 1, 1)
                end
                DEFAULT_CHAT_FRAME:AddMessage("  Total quests: " .. count, 1, 1, 1)
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("  Exists: NO", 1, 0, 0)
        end
        
    else
        DebugMessage("|cFF00FFFF=== QUESTIE DATA COLLECTOR ===|r", 0, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc enable - Enable data collection", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc disable - Disable data collection", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc status - Check current status", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc export - Open export window for first Epoch quest", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc export <id> - Export specific quest data", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc turnin <id> - Manually capture turn-in NPC (target NPC first)", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc clear - Clear all data", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc rescan - Re-scan quest log for missing quests", 1, 1, 1)
    end
end

return QuestieDataCollector