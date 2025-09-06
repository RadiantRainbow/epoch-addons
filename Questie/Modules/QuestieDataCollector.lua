---@class QuestieDataCollector
local QuestieDataCollector = QuestieLoader:CreateModule("QuestieDataCollector")

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
---@type QuestieLib
local QuestieLib = QuestieLoader:ImportModule("QuestieLib")
---@type QuestieQuest
local QuestieQuest = QuestieLoader:ImportModule("QuestieQuest")
---@type ZoneDB
local ZoneDB = QuestieLoader:ImportModule("ZoneDB")
---@type QuestieCompat
local QuestieCompat = QuestieLoader:ImportModule("QuestieCompat")

-- Compatibility reassignments (following codebase pattern)
local C_Timer -- Will be assigned after initialization

-- Version control - use TOC file as single source of truth
local CURRENT_VERSION = GetAddOnMetadata("Questie", "Version") or "Unknown"
-- Accept data from previous stable versions or later
local MINIMUM_VERSION = "1.1.0" -- Oldest compatible version for data collection

-- WoW AreaID to Questie zone ID mapping for problematic zones
local WOW_AREA_TO_QUESTIE_ZONE = {
    [21] = 85,  -- Tirisfal Glades (WoW sometimes returns 21, Questie uses 85)
    -- Add more mappings as we discover them
}

-- Load comprehensive subzone mappings
-- CRITICAL: 1969 subzone names and 2117 subzone-to-parent mappings
local QuestieSubzoneMappings = QuestieLoader:ImportModule("QuestieSubzoneMappings")

local function LoadSubzoneMappings()
    -- Try to access the QuestieSubzoneMappings module
    if QuestieSubzoneMappings and QuestieSubzoneMappings.SUBZONE_NAME_TO_ID then
        return QuestieSubzoneMappings.SUBZONE_NAME_TO_ID, QuestieSubzoneMappings.SUBZONE_TO_PARENT
    else
        -- Fallback to basic Tirisfal mappings if module fails to load
        local fallback_names = {
            ["Deathknell"] = 154,
            ["Brill"] = 159,
            ["Ruins of Lordaeron"] = 153,
            ["Night Web's Hollow"] = 155,
            ["Solliden Farmstead"] = 156,
            ["Agamand Mills"] = 157,
            ["Agamand Family Crypt"] = 158,
            ["Whispering Gardens"] = 160,
        }
        local fallback_parent = {
            [21] = 85,   -- Tirisfal alternate ID
            [154] = 85,  -- Deathknell -> Tirisfal
            [159] = 85,  -- Brill -> Tirisfal
        }
        return fallback_names, fallback_parent
    end
end

local SUBZONE_NAME_TO_ID, SUBZONE_TO_PARENT = LoadSubzoneMappings()

-- Zone name to Questie zone ID mapping (most common zones)
local ZONE_NAME_TO_ID = {
    ["Durotar"] = 14,
    ["Elwynn Forest"] = 12,
    ["Teldrassil"] = 141,
    ["Dun Morogh"] = 1,
    ["Tirisfal Glades"] = 85,
    ["The Barrens"] = 17,
    ["Westfall"] = 40,
    ["Darkshore"] = 148,
    ["Loch Modan"] = 38,
    ["Silverpine Forest"] = 130,
    ["Stormwind City"] = 1519,
    ["Orgrimmar"] = 1637,
    ["Thunder Bluff"] = 1638,
    ["Ironforge"] = 1537,
    ["Undercity"] = 1497,
    ["Darnassus"] = 1657,
}

-- SavedVariables table for collected data
-- This will be initialized after ADDON_LOADED event

local _activeTracking = {} -- Currently tracking these quest IDs
local _lastQuestGiver = nil -- Store last NPC interacted with
local _lastInteractedNPC = nil -- Track last NPC interaction for service NPC capture
local _questAcceptCoords = {} -- Store coordinates when accepting quests
local _originalTooltipSettings = nil -- Store original tooltip settings for restoration
local _recentKills = {} -- Store recent combat kills for objective correlation
local _initialized = false -- Track if we've initialized
local _currentLootSource = nil -- Track what we're currently looting from
local _lastInteractedObject = nil -- Track last object we moused over
local _dataMismatches = {} -- Track database mismatches for reporting
local _availableQuestsBeforeTurnIn = {} -- Track quests available at NPC before turn-in
local _lastNPCWithQuests = nil -- Track last NPC we checked for available quests
local _completedQuests = {} -- Track all completed quests for prereq detection
local _serviceNPCs = {} -- Track service NPCs (vendors, trainers, etc)
local _mailboxes = {} -- Track mailbox locations
local _gatheringNodes = {} -- Track gathering nodes (herbs, ore)
local _treasureChests = {} -- Track treasure chests and containers
local _flightMasters = {} -- Track flight masters
local _pendingXPReward = nil -- Track XP reward for quest turn-in

-- Coordinate caching to improve performance
local _coordinateCache = {
    coords = nil,
    zoneData = nil,
    lastUpdate = 0,
    lastZoneUpdate = 0,
    cacheTime = 0.1, -- Cache for 100ms
    zoneCacheTime = 5.0 -- Zone data cache for 5 seconds
}

-- Forward declaration of helper function for creating clickable quest data links
local CreateQuestDataLink

-- Helper function to extract NPC ID from GUID (WoW 3.3.5 format)
local function ExtractNpcIdFromGuid(guid)
    if not guid then return nil end
    -- WoW 3.3.5 GUID format: 0xF13000085800126C
    -- Bytes 6-12 contain the NPC ID in hex (confirmed working for quest-compatible IDs)
    local npcId = tonumber(guid:sub(6, 12), 16)
    return npcId
end

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

-- Helper function to validate zone data
local function ValidateZoneData(questId, expectedZone, actualZone)
    if not expectedZone or not actualZone then
        return true -- Can't validate without data
    end
    
    if expectedZone ~= actualZone then
        DebugMessage("|cFFFF0000[DATA VALIDATION WARNING]|r Quest " .. questId .. " expected zone '" .. expectedZone .. "' but got '" .. actualZone .. "'", 1, 0, 0)
        
        -- Record the mismatch
        if not _dataMismatches[questId] then
            _dataMismatches[questId] = {}
        end
        _dataMismatches[questId].zoneExpected = expectedZone
        _dataMismatches[questId].zoneActual = actualZone
        
        return false
    end
    
    return true
end

-- Helper function to check if quest exists in database
local function IsQuestInDatabase(questId)
    -- Always return false to collect ALL quests when data collection is enabled
    -- This ensures we get complete data for validation and fixing corrupted entries
    return false  -- Always collect everything for maximum data quality
end

-- Helper function to check for database mismatches
local function CheckDatabaseMismatch(entityType, entityId, fieldName, collectedValue, databaseValue)
    if not collectedValue or not databaseValue then
        return false
    end
    
    -- Compare values (handle different types)
    local mismatch = false
    if type(collectedValue) ~= type(databaseValue) then
        mismatch = true
    elseif type(collectedValue) == "table" then
        -- For coordinates, check if they're significantly different
        if collectedValue.x and databaseValue.x then
            local xDiff = math.abs(collectedValue.x - databaseValue.x)
            local yDiff = math.abs(collectedValue.y - databaseValue.y)
            if xDiff > 1 or yDiff > 1 then -- Allow 1% tolerance
                mismatch = true
            end
        end
    else
        mismatch = (collectedValue ~= databaseValue)
    end
    
    if mismatch then
        local key = entityType .. "_" .. entityId .. "_" .. fieldName
        if not _dataMismatches[key] then
            _dataMismatches[key] = {
                entityType = entityType,
                entityId = entityId,
                fieldName = fieldName,
                collectedValue = collectedValue,
                databaseValue = databaseValue,
                timestamp = time()
            }
            
            DebugMessage("|cFFFFAA00[DATABASE MISMATCH]|r " .. entityType .. " " .. entityId .. " field '" .. fieldName .. "': DB has '" .. tostring(databaseValue) .. "' but found '" .. tostring(collectedValue) .. "'", 1, 0.7, 0)
        end
        return true
    end
    
    return false
end

function QuestieDataCollector:Initialize()
    -- Prevent double initialization
    if _initialized then
        return
    end
    
    -- Initialize C_Timer from QuestieCompat
    if QuestieCompat and QuestieCompat.C_Timer then
        C_Timer = QuestieCompat.C_Timer
    end
    
    -- Only initialize if explicitly enabled
    if not Questie or not Questie.db or not Questie.db.profile.enableDataCollection then
        return
    end
    
    -- Create or ensure the character-specific SavedVariable exists
    -- This is now PER CHARACTER, so no contamination possible!
    if type(QuestieDataCollection) ~= "table" then
        _G.QuestieDataCollection = {}
    end
    
    -- Initialize structure for this character
    if not QuestieDataCollection.quests then
        QuestieDataCollection.quests = {}
    end
    if not QuestieDataCollection.mismatches then
        QuestieDataCollection.mismatches = {}
    end
    if not QuestieDataCollection.serviceNPCs then
        QuestieDataCollection.serviceNPCs = {}
    end
    if not QuestieDataCollection.mailboxes then
        QuestieDataCollection.mailboxes = {}
    end
    if not QuestieDataCollection.gatheringNodes then
        QuestieDataCollection.gatheringNodes = {}
    end
    if not QuestieDataCollection.treasureChests then
        QuestieDataCollection.treasureChests = {}
    end
    if not QuestieDataCollection.flightMasters then
        QuestieDataCollection.flightMasters = {}
    end
    if not QuestieDataCollection.version then
        QuestieDataCollection.version = CURRENT_VERSION
    end
    if not QuestieDataCollection.sessionStart then
        QuestieDataCollection.sessionStart = date("%Y-%m-%d %H:%M:%S")
    end
    
    -- Store character info for reference (not for validation)
    QuestieDataCollection.characterName = UnitName("player") .. "-" .. GetRealmName()
    QuestieDataCollection.characterLevel = UnitLevel("player")
    QuestieDataCollection.characterClass = UnitClass("player")
    QuestieDataCollection.characterRace = UnitRace("player")
    
    -- Update version for existing data
    QuestieDataCollection.version = CURRENT_VERSION
    
    
    -- Count tracked quests (only missing ones)
    local questCount = 0
    local inDatabaseCount = 0
    for questId in pairs(QuestieDataCollection.quests) do
        if not IsQuestInDatabase(questId) then
            questCount = questCount + 1
        else
            inDatabaseCount = inDatabaseCount + 1
        end
    end
    
    -- Hook into events
    QuestieDataCollector:RegisterEvents()
    
    -- Hook tooltip to capture object names on mouseover
    -- This helps identify containers/objects before we interact with them
    if not _tooltipHooked then
        GameTooltip:HookScript("OnShow", function()
            if GameTooltip:IsVisible() then
                local name = GameTooltipTextLeft1:GetText()
                if name and name ~= "" then
                    -- Get coordinates when tooltip shows (this is likely when we interact with objects)
                    local coords = QuestieDataCollector:GetPlayerCoordinates()
                    
                    -- Store as potential object we might interact with
                    _lastInteractedObject = {
                        name = name,
                        timestamp = time(),
                        coords = coords -- Add coordinates here too!
                    }
                    
                    -- DEBUG: Show tooltip interaction with coordinate status
                    if coords then
                        DebugMessage("|cFFFF9900[DATA]|r Tooltip shown for: " .. name .. " at [" .. QuestieDataCollector:SafeFormatCoords(coords) .. "] in " .. (coords.zone or "Unknown Zone"), 1, 0.6, 0)
                    else
                        DebugMessage("|cFFFF9900[DATA]|r Tooltip shown for: " .. name .. " - WARNING: No coordinates captured!", 1, 0.6, 0)
                    end
                end
            end
        end)
        _tooltipHooked = true
    end
    
    -- Enable tooltip IDs
    QuestieDataCollector:EnableTooltipIDs()
    
    -- Only show messages on first initialization, not after login
    if not _initialized then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[Questie Data Collector v" .. CURRENT_VERSION .. "]|r Ready!", 0, 1, 0)
        
        if Questie.db.profile.dataCollectionDevMode then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[DEV MODE] Collecting ALL quests (including known ones)|r", 1, 0, 0)
        end
        
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Mismatch detection enabled for improved accuracy|r", 1, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Type /qdc for commands|r", 1, 1, 0)
    end
    
    _initialized = true
    
    -- Wait for Questie to be fully initialized before checking quests
    if not Questie.started then
        if C_Timer and C_Timer.After then
            C_Timer.After(5, function()
                QuestieDataCollector:CheckActiveQuests()
            end)
        else
            -- Fallback if C_Timer isn't available - use a frame with OnUpdate
            local waitFrame = CreateFrame("Frame")
            local elapsed = 0
            waitFrame:SetScript("OnUpdate", function(self, delta)
                elapsed = elapsed + delta
                if elapsed >= 5 then
                    self:SetScript("OnUpdate", nil)
                    QuestieDataCollector:CheckActiveQuests()
                end
            end)
        end
    else
        QuestieDataCollector:CheckActiveQuests()
    end
end

-- Store zone data properly
local function GetCurrentZoneData()
    local zoneData = {}
    
    -- Get zone text directly from API
    zoneData.zone = GetZoneText()
    zoneData.subZone = GetSubZoneText()
    zoneData.realZone = GetRealZoneText()
    
    -- Get map IDs
    local mapId = nil
    if WorldMapFrame and WorldMapFrame.GetMapID then
        mapId = WorldMapFrame:GetMapID()
    end
    
    -- Get area ID from current position
    local areaId = nil
    if GetCurrentMapAreaID then
        areaId = GetCurrentMapAreaID()
    end
    
    -- Try to get Questie's zone ID
    local questieZoneId = nil
    
    -- Method 1: Try using QuestieCompat to get proper UiMapId
    if not questieZoneId and QuestieCompat and QuestieCompat.GetCurrentUiMapID then
        local uiMapId = QuestieCompat.GetCurrentUiMapID()
        if uiMapId and ZoneDB and ZoneDB.GetAreaIdByUiMapId then
            local success, result = pcall(function()
                return ZoneDB:GetAreaIdByUiMapId(uiMapId)
            end)
            if success and result then
                questieZoneId = result
            end
        end
    end
    
    -- Method 2: Try using mapId if available
    if not questieZoneId and mapId and ZoneDB and ZoneDB.GetAreaIdByUiMapId then
        -- Use pcall to safely handle any errors from ZoneDB
        local success, result = pcall(function()
            return ZoneDB:GetAreaIdByUiMapId(mapId)
        end)
        if success and result then
            questieZoneId = result
        end
    end
    
    -- Method 3: Check if we're in a subzone and can map it to proper ID
    -- This is CRITICAL for quests to show up on the map with precise locations
    if zoneData.subZone and zoneData.subZone ~= "" and SUBZONE_NAME_TO_ID[zoneData.subZone] then
        -- We have a subzone name like "Brill" - convert to proper subzone ID (159)
        questieZoneId = SUBZONE_NAME_TO_ID[zoneData.subZone]
        DebugMessage(string.format("[ZONE] Mapped subzone '%s' to ID %d", zoneData.subZone, questieZoneId), 0, 1, 0)
    end
    
    -- Method 4: If that didn't work, try using zone name (parent zone)
    if not questieZoneId and zoneData.zone and ZONE_NAME_TO_ID[zoneData.zone] then
        questieZoneId = ZONE_NAME_TO_ID[zoneData.zone]
    end
    
    -- Method 5: Try GetRealZoneText if zone didn't work
    if not questieZoneId and zoneData.realZone and ZONE_NAME_TO_ID[zoneData.realZone] then
        questieZoneId = ZONE_NAME_TO_ID[zoneData.realZone]
    end
    
    -- Method 6: Direct WoW AreaID to Questie zone mapping
    if not questieZoneId and areaId and WOW_AREA_TO_QUESTIE_ZONE[areaId] then
        questieZoneId = WOW_AREA_TO_QUESTIE_ZONE[areaId]
    end
    
    -- Debug zone detection for problematic zones or when debug is enabled
    if _debugEnabled or areaId == 21 or questieZoneId == 85 or zoneData.zone == "Tirisfal Glades" or zoneData.subZone then
        DebugMessage(string.format("[ZONE DETECTION] zone='%s', subZone='%s', realZone='%s', areaId=%s, questieZoneId=%s", 
            tostring(zoneData.zone), 
            tostring(zoneData.subZone),
            tostring(zoneData.realZone), 
            tostring(areaId), 
            tostring(questieZoneId)), 1, 1, 0)
    end
    
    zoneData.mapId = mapId
    -- CRITICAL: Use the mapped subzone ID if we found one, otherwise fall back to area ID
    -- Example: In Brill, subZone="Brill" maps to 159, which is what we need for precise map display
    zoneData.areaId = areaId  -- Keep the raw area ID from API (might be 21)
    zoneData.parentZoneId = SUBZONE_TO_PARENT[questieZoneId] or questieZoneId  -- Get parent zone if this is a subzone
    zoneData.questieZoneId = questieZoneId or areaId  -- Use the mapped zone ID (159 for Brill, not 21)
    
    -- Get coordinates
    local coords = QuestieDataCollector:GetPlayerCoordinates()
    if coords then
        zoneData.x = coords.x
        zoneData.y = coords.y
    end
    
    return zoneData
end

-- Enhanced coordinate capture with zone validation
function QuestieDataCollector:GetPlayerCoordinates()
    local currentTime = GetTime()
    
    -- Check if we have cached coordinates that are still fresh
    if _coordinateCache.coords and (currentTime - _coordinateCache.lastUpdate) < _coordinateCache.cacheTime then
        -- Return cached coordinates with cached zone data
        if _coordinateCache.zoneData then
            return {
                x = _coordinateCache.coords.x,
                y = _coordinateCache.coords.y,
                zone = _coordinateCache.zoneData.zone,
                subZone = _coordinateCache.zoneData.subZone,
                areaId = _coordinateCache.zoneData.areaId,
                mapId = _coordinateCache.zoneData.mapId
            }
        else
            return _coordinateCache.coords
        end
    end
    
    -- Get fresh coordinates
    local x, y = nil, nil
    
    -- Try QuestieCoords first
    if QuestieCoords and QuestieCoords.GetPlayerMapPosition then
        -- FIX Issue #3: QuestieCoords returns (position_table, mapID), not (x, y)
        local position, mapID = QuestieCoords.GetPlayerMapPosition()
        if position and type(position) == "table" and position.x and position.y then
            x, y = position.x, position.y
        end
    end
    
    -- Fallback to standard API
    if not x or not y then
        x, y = GetPlayerMapPosition("player")
        -- DEBUG: Check standard API return types
        if x and y and (type(x) ~= "number" or type(y) ~= "number") then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[DEBUG]|r GetPlayerMapPosition('player') returned bad types: x=" .. type(x) .. " y=" .. type(y), 1, 0.5, 0)
            x, y = nil, nil -- Clear bad data
        end
    end
    
    -- CRITICAL FIX: Defensive type checking - coordinate APIs can return unexpected types
    if x and y and type(x) == "number" and type(y) == "number" and x > 0 and y > 0 then
        -- Convert coordinates once and cache them
        local coords = {
            x = math.floor(x * 1000) / 10, -- Convert to percentage with 1 decimal
            y = math.floor(y * 1000) / 10
        }
        
        -- Check if we need to update zone data (less frequently)
        if not _coordinateCache.zoneData or (currentTime - _coordinateCache.lastZoneUpdate) > _coordinateCache.zoneCacheTime then
            -- Safely get zone data
            local success, zoneData = pcall(GetCurrentZoneData)
            if success and zoneData then
                _coordinateCache.zoneData = {
                    zone = zoneData.zone or "Unknown",
                    subZone = zoneData.subZone or "",
                    areaId = zoneData.areaId,
                    mapId = zoneData.mapId
                }
                _coordinateCache.lastZoneUpdate = currentTime
            elseif not _coordinateCache.zoneData then
                -- If we've never had zone data, set defaults
                _coordinateCache.zoneData = {
                    zone = "Unknown",
                    subZone = "",
                    areaId = nil,
                    mapId = nil
                }
            end
        end
        
        -- Cache the coordinates
        _coordinateCache.coords = coords
        _coordinateCache.lastUpdate = currentTime
        
        -- Return combined data
        return {
            x = coords.x,
            y = coords.y,
            zone = _coordinateCache.zoneData.zone,
            subZone = _coordinateCache.zoneData.subZone,
            areaId = _coordinateCache.zoneData.areaId,
            mapId = _coordinateCache.zoneData.mapId
        }
    end
    
    return nil
end

function QuestieDataCollector:RegisterEvents()
    local frame = CreateFrame("Frame")
    
    -- Quest events
    frame:RegisterEvent("QUEST_ACCEPTED")
    frame:RegisterEvent("QUEST_COMPLETE")
    frame:RegisterEvent("QUEST_TURNED_IN")
    frame:RegisterEvent("QUEST_LOG_UPDATE")
    
    -- NPC interaction events
    frame:RegisterEvent("GOSSIP_SHOW")
    frame:RegisterEvent("QUEST_DETAIL")
    frame:RegisterEvent("QUEST_GREETING")
    frame:RegisterEvent("QUEST_PROGRESS")
    frame:RegisterEvent("QUEST_FINISHED")
    
    -- Zone change events (to invalidate coordinate cache)
    frame:RegisterEvent("ZONE_CHANGED")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("ZONE_CHANGED_INDOORS")
    
    -- Combat and loot events for tracking mob kills and item sources
    -- WoW 3.3.5a compatibility: Try both modern and legacy combat log events
    frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    frame:RegisterEvent("COMBAT_LOG_EVENT")  -- Fallback for older clients
    frame:RegisterEvent("LOOT_OPENED")
    frame:RegisterEvent("CHAT_MSG_LOOT")
    frame:RegisterEvent("ITEM_PUSH")
    
    -- Targeting events for mob tracking
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    
    -- Service NPC events
    frame:RegisterEvent("MERCHANT_SHOW")
    frame:RegisterEvent("MERCHANT_CLOSED")
    frame:RegisterEvent("TRAINER_SHOW")
    frame:RegisterEvent("TRAINER_CLOSED")
    frame:RegisterEvent("MAIL_SHOW")
    frame:RegisterEvent("MAIL_CLOSED")
    frame:RegisterEvent("BANKFRAME_OPENED")
    frame:RegisterEvent("BANKFRAME_CLOSED")
    frame:RegisterEvent("GUILDBANKFRAME_OPENED")
    frame:RegisterEvent("GUILDBANKFRAME_CLOSED")
    frame:RegisterEvent("TAXIMAP_OPENED")
    frame:RegisterEvent("AUCTION_HOUSE_SHOW")  -- Auctioneer
    frame:RegisterEvent("PET_STABLE_SHOW")     -- Stable Master
    frame:RegisterEvent("BATTLEFIELDS_SHOW")   -- Battlemaster
    
    -- XP tracking events
    frame:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
    frame:RegisterEvent("CHAT_MSG_SYSTEM")
    
    frame:SetScript("OnEvent", function(self, event, ...)
        QuestieDataCollector:OnEvent(event, ...)
    end)
end

function QuestieDataCollector:OnEvent(event, ...)
    if not Questie.db.profile.enableDataCollection then
        return
    end
    
    if event == "QUEST_ACCEPTED" then
        local questIndex, questId = ...
        
        -- In WoW 3.3.5, QUEST_ACCEPTED doesn't always provide questId
        -- We need to get it from the quest log (position 9)
        if not questId or questId == 0 then
            -- GetQuestLogTitle returns: title, level, tag, isHeader, isCollapsed, isComplete, frequency, unknown, questID (9th position)
            local _, _, _, _, _, _, _, _, retrievedQuestId = GetQuestLogTitle(questIndex)
            questId = retrievedQuestId
        end
        
        -- Ensure we have a valid quest ID
        if not questId or questId == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[DATA ERROR]|r Could not get quest ID for index " .. tostring(questIndex), 1, 0, 0)
            return
        end
        
        -- Always collect data for ALL quests to validate/improve database
        local questTitle = GetQuestLogTitle(questIndex) or ("Quest " .. questId)
        DebugMessage("|cFFFFFF00[DATA]|r Collecting quest data: " .. questId .. " (" .. questTitle .. ")", 1, 1, 0)
        
        QuestieDataCollector:TrackQuestAccepted(questIndex, questId)
        
    elseif event == "QUEST_COMPLETE" then
        QuestieDataCollector:TrackQuestComplete()
        
    elseif event == "QUEST_TURNED_IN" then
        local questId, xpReward, moneyReward = ...
        
        -- Store XP if provided directly in event (newer WoW versions)
        if xpReward and xpReward > 0 then
            _pendingXPReward = xpReward
        end
        
        -- Sometimes questId is nil, try to get from recently completed quest
        if not questId or questId == 0 then
            -- Method 1: Find the most recently completed quest that's being tracked
            local mostRecentTime = 0
            local mostRecentId = nil
            for qId in pairs(_activeTracking) do
                local qData = QuestieDataCollection.quests[qId]
                if qData and qData.completedTimestamp and qData.completedTimestamp > mostRecentTime then
                    mostRecentTime = qData.completedTimestamp
                    mostRecentId = qId
                end
            end
            if mostRecentId and (time() - mostRecentTime) < 10 then -- Increased time window
                questId = mostRecentId
                DebugMessage("|cFFFFFF00[DATA]|r Using recently completed quest ID: " .. questId, 1, 1, 0)
            end
        end
        
        -- Method 2: If still no quest ID, check for any active quest with a pending XP reward
        if (not questId or questId == 0) and _pendingXPReward then
            -- Find any active quest that could be turning in
            for qId in pairs(_activeTracking) do
                local qData = QuestieDataCollection.quests[qId]
                -- If there's only one active quest, assume it's the one
                if qData and not qData.turnedIn then
                    questId = qId
                    DebugMessage("|cFFFFFF00[DATA]|r Using active quest ID from pending XP: " .. questId, 1, 1, 0)
                    break
                end
            end
        end
        
        if questId and _activeTracking[questId] then
            QuestieDataCollector:TrackQuestTurnIn(questId)
        elseif _pendingXPReward then
            -- We have XP but couldn't find the quest
            DebugMessage("|cFFFF0000[DATA ERROR]|r Have pending XP reward but couldn't determine quest ID", 1, 0, 0)
        end
        
    elseif event == "QUEST_LOG_UPDATE" then
        QuestieDataCollector:CheckQuestProgress()
        
    elseif event == "GOSSIP_SHOW" then
        QuestieDataCollector:CaptureNPCInfo()
        -- Check for innkeeper service
        local numOptions = GetNumGossipOptions()
        for i = 1, numOptions do
            local text, gossipType = GetGossipOptions()
            -- In WoW 3.3.5, gossipType "binder" indicates innkeeper
            if gossipType == "binder" then
                QuestieDataCollector:CaptureServiceNPC("innkeeper")
                break
            end
        end
        
    elseif event == "QUEST_DETAIL" or event == "QUEST_GREETING" then
        QuestieDataCollector:CaptureNPCInfo()
        
    elseif event == "PLAYER_TARGET_CHANGED" then
        QuestieDataCollector:TrackTargetedMob()
        
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        QuestieDataCollector:TrackMouseoverUnit()
        
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" or event == "COMBAT_LOG_EVENT" then
        QuestieDataCollector:HandleCombatEvent(...)
        
    elseif event == "LOOT_OPENED" then
        QuestieDataCollector:HandleLootOpened()
        
    elseif event == "CHAT_MSG_LOOT" then
        local message = ...
        QuestieDataCollector:HandleLootMessage(message)
        
    elseif event == "ITEM_PUSH" then
        local bagSlot, iconPath = ...
        QuestieDataCollector:HandleItemPush(bagSlot, iconPath)
        
    elseif event == "MERCHANT_SHOW" then
        QuestieDataCollector:CaptureServiceNPC("vendor")
        QuestieDataCollector:DetectNPCService("VENDOR")
        -- Check if merchant can repair
        if CanMerchantRepair() then
            QuestieDataCollector:DetectNPCService("REPAIR")
        end
        
    elseif event == "TRAINER_SHOW" then
        QuestieDataCollector:CaptureServiceNPC("trainer")
        QuestieDataCollector:DetectNPCService("TRAINER")
        
    elseif event == "MAIL_SHOW" then
        QuestieDataCollector:CaptureMailbox()
        
    elseif event == "BANKFRAME_OPENED" then
        QuestieDataCollector:CaptureServiceNPC("banker")
        QuestieDataCollector:DetectNPCService("BANKER")
        
    elseif event == "GUILDBANKFRAME_OPENED" then
        QuestieDataCollector:CaptureServiceNPC("guild_banker")
        
    elseif event == "TAXIMAP_OPENED" then
        -- Flight masters are special - we need to capture them differently
        -- First try to capture NPC info if we haven't already
        local guid = UnitGUID("target") or UnitGUID("npc") or UnitGUID("questnpc") or UnitGUID("mouseover")
        if guid then
            -- Store the NPC info first
            local npcId = ExtractNpcIdFromGuid(guid)
            local npcName = UnitName("target") or UnitName("npc") or UnitName("questnpc") or UnitName("mouseover")
            if npcId and npcName then
                _lastInteractedNPC = {
                    guid = guid,
                    id = npcId,
                    name = npcName,
                    timestamp = time(),
                    coords = QuestieDataCollector:GetPlayerCoordinates(),
                    detectedServices = {}
                }
                DebugMessage("|cFF00FFFF[DATA]|r Captured flight master from TAXIMAP_OPENED: " .. npcName, 0, 1, 1)
            end
            QuestieDataCollector:DetectNPCService("FLIGHT_MASTER")
        end
        QuestieDataCollector:CaptureServiceNPC("flight_master")
        
    elseif event == "AUCTION_HOUSE_SHOW" then
        QuestieDataCollector:CaptureNPCInfo()
        QuestieDataCollector:DetectNPCService("AUCTIONEER")
        
    elseif event == "PET_STABLE_SHOW" then
        QuestieDataCollector:CaptureNPCInfo()
        QuestieDataCollector:DetectNPCService("STABLEMASTER")
        
    elseif event == "BATTLEFIELDS_SHOW" then
        QuestieDataCollector:CaptureNPCInfo()
        QuestieDataCollector:DetectNPCService("BATTLEMASTER")
        
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        local message = ...
        -- Parse XP from quest completion: "Experience gained: 450."
        local xp = string.match(message, "Experience gained: (%d+)")
        if xp then
            _pendingXPReward = tonumber(xp)
            -- XP message comes right before QUEST_TURNED_IN, so we store it temporarily
            DebugMessage("|cFF00FFFF[DATA]|r Captured XP reward: " .. xp, 0, 1, 1)
        end
        
    elseif event == "CHAT_MSG_SYSTEM" then
        local message = ...
        -- Also check system messages for XP (sometimes comes through here)
        local xp = string.match(message, "Experience gained: (%d+)")
        if xp then
            _pendingXPReward = tonumber(xp)
            DebugMessage("|cFF00FFFF[DATA]|r Captured XP reward: " .. xp, 0, 1, 1)
        end
        
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED_INDOORS" then
        -- Invalidate zone cache when zone changes
        _coordinateCache.zoneData = nil
        _coordinateCache.lastZoneUpdate = 0
    end
end

function QuestieDataCollector:TrackQuestAccepted(questIndex, questId)
    if not questId or questId == 0 then
        return
    end
    
    -- Skip if quest is already in database
    if IsQuestInDatabase(questId) then
        DebugMessage("|cFFFFAA00[DATA]|r Quest " .. questId .. " already in database, skipping collection", 1, 0.7, 0)
        return
    end
    
    local questName = GetQuestLogTitle(questIndex)
    if not questName then
        return
    end
    
    -- Always show this message for missing quests (bypass toggle)
    DebugMessage("|cFF00FF00[DATA]|r Epoch quest not in database accepted: " .. questName .. " (ID: " .. questId .. ")", 0, 1, 0)
    
    -- Initialize quest data if needed
    if not QuestieDataCollection.quests[questId] then
        QuestieDataCollection.quests[questId] = {
            id = questId,
            objectives = {},
            mobs = {},
            items = {},
            objects = {},
            kills = {},
            mismatches = {}
        }
    end
    
    local questData = QuestieDataCollection.quests[questId]
    
    -- Store quest info
    questData.name = questName
    questData.acceptedTimestamp = time()
    questData.acceptedDate = date("%Y-%m-%d %H:%M:%S")
    
    -- Look for potential quest chain relationships
    -- Check for sequential quest IDs and similar names in our tracked data
    local potentialChain = {}
    
    -- Check for sequential quest IDs (e.g., 27001, 27002, 27003)
    for trackedId, trackedData in pairs(QuestieDataCollection.quests) do
        if trackedData and trackedData.name then
            -- Check if quest ID is sequential (within 5 of current)
            if math.abs(trackedId - questId) <= 5 and trackedId ~= questId then
                table.insert(potentialChain, {
                    id = trackedId,
                    name = trackedData.name,
                    reason = "Sequential ID"
                })
            end
            
            -- Check for similar quest names (common patterns like "Part 1", "Part 2")
            local currentName = questName:upper()
            local trackedName = trackedData.name:upper()
            
            -- Remove common suffixes for comparison
            local patterns = {"PART %d+", "CHAPTER %d+", "STEP %d+", "%(1%)", "%(2%)", "%(3%)", "I+$", "I+V$", "V?I+$"}
            local currentBase = currentName
            local trackedBase = trackedName
            
            for _, pattern in ipairs(patterns) do
                currentBase = currentBase:gsub(pattern, "")
                trackedBase = trackedBase:gsub(pattern, "")
            end
            
            currentBase = currentBase:gsub("%s+$", ""):gsub("^%s+", "")
            trackedBase = trackedBase:gsub("%s+$", ""):gsub("^%s+", "")
            
            -- If base names match, likely part of a chain
            if currentBase == trackedBase and trackedId ~= questId then
                table.insert(potentialChain, {
                    id = trackedId,
                    name = trackedData.name,
                    reason = "Similar name"
                })
            end
        end
    end
    
    if #potentialChain > 0 then
        questData.potentialChain = potentialChain
        DebugMessage("|cFF00FFFF[DATA]|r Found " .. #potentialChain .. " potential chain quests", 0, 1, 1)
        for _, chainQuest in ipairs(potentialChain) do
            DebugMessage("|cFF00FFFF[DATA]|r   - " .. chainQuest.name .. " (" .. chainQuest.id .. ") - " .. chainQuest.reason, 0, 1, 1)
        end
    end
    
    -- Store player class, race, and faction information (useful for class/race/faction specific quests)
    local playerClass, playerClassLocal = UnitClass("player")
    local playerRace, playerRaceLocal = UnitRace("player")
    local playerFaction = UnitFactionGroup("player") -- Returns "Alliance" or "Horde"
    questData.playerClass = playerClass
    questData.playerRace = playerRace
    questData.playerFaction = playerFaction
    questData.playerLevel = UnitLevel("player")
    
    -- Check if this quest has profession requirements (not just commission quests)
    local questDB = QuestieDB.GetQuest(questId)
    local hasSkillRequirement = false
    
    if questDB and questDB.requiredSkill then
        hasSkillRequirement = true
        questData.requiredSkill = questDB.requiredSkill
        DebugMessage("|cFFFFFF00[DATA]|r Quest requires profession skill: " .. tostring(questDB.requiredSkill[1] or "unknown") .. " (" .. tostring(questDB.requiredSkill[2] or "0") .. ")", 1, 1, 0)
    end
    
    -- Also check for commission quests by name (fallback for quests not in database)
    if string.find(questName:upper(), "COMMISSION") then
        questData.isCommission = true
        hasSkillRequirement = true
        DebugMessage("|cFFFFFF00[DATA]|r Commission quest detected by name pattern", 1, 1, 0)
    end
    
    -- Capture player's professions for ANY quest with skill requirements
    -- ALWAYS capture for commission quests to ensure we have the data
    if hasSkillRequirement or questData.isCommission then
        local profs = QuestieDataCollector:GetPlayerProfessions()
        questData.playerProfessions = profs
        if profs and #profs > 0 then
            DebugMessage("|cFF00FF00[DATA]|r Captured " .. #profs .. " professions for quest", 0, 1, 0)
            for _, prof in ipairs(profs) do
                DebugMessage("|cFF00FFFF[DATA]|r   - " .. prof.name .. ": " .. prof.skillLevel .. "/" .. prof.maxSkillLevel, 0, 1, 1)
            end
        else
            DebugMessage("|cFFFF0000[DATA]|r No professions captured - player may not have any!", 1, 0, 0)
        end
    end
    
    -- Get quest level and objectives text
    local level, questTag, _, _, _, _, _, _ = select(2, GetQuestLogTitle(questIndex))
    questData.level = level
    questData.tag = questTag
    
    -- Try to get objectives text
    SelectQuestLogEntry(questIndex)
    local questDescription, objectivesText = GetQuestLogQuestText()
    if questDescription and questDescription ~= "" then
        questData.questDescription = questDescription
    end
    if objectivesText and objectivesText ~= "" then
        questData.objectivesText = objectivesText
    end
    
    -- Store zone data when accepting
    local zoneData = GetCurrentZoneData()
    if zoneData then
        questData.acceptZone = zoneData.zone
        questData.acceptSubZone = zoneData.subZone
        questData.acceptAreaId = zoneData.areaId  -- The actual area ID (could be subzone like 154)
        questData.acceptParentZoneId = zoneData.parentZoneId  -- Parent zone (like 85 for Tirisfal)
        questData.acceptQuestieZoneId = zoneData.questieZoneId  -- What should be used in database
        
        -- Store coordinates for quest acceptance
        if zoneData.x and zoneData.y then
            _questAcceptCoords[questId] = {
                x = zoneData.x,
                y = zoneData.y,
                zone = zoneData.zone,
                subZone = zoneData.subZone,
                areaId = zoneData.areaId,
                parentZoneId = zoneData.parentZoneId,
                questieZoneId = zoneData.questieZoneId
            }
        end
    end
    
    -- Capture quest giver info (if we have it)
    -- Check for both NPC quest givers and item/object quest starters
    local questStarterCaptured = false
    
    -- First check for NPC quest giver (traditional quest acceptance)
    if _lastQuestGiver and (_lastQuestGiver.timestamp and (time() - _lastQuestGiver.timestamp) < 10) then
        questData.questGiver = {
            id = _lastQuestGiver.id,
            name = _lastQuestGiver.name,
            coords = _lastQuestGiver.coords
        }
        DebugMessage("|cFF00FF00[DATA]|r Quest Giver: " .. _lastQuestGiver.name .. " (ID: " .. _lastQuestGiver.id .. ")", 0, 1, 0)
        
        -- Check for database mismatch
        local dbQuest = QuestieDB.GetQuest(questId)
        if dbQuest and dbQuest.startedBy and dbQuest.startedBy[1] then
            local dbNpcIds = dbQuest.startedBy[1]
            if dbNpcIds and #dbNpcIds > 0 then
                local found = false
                for _, npcId in ipairs(dbNpcIds) do
                    if npcId == _lastQuestGiver.id then
                        found = true
                        break
                    end
                end
                if not found then
                    CheckDatabaseMismatch("quest", questId, "questGiver", _lastQuestGiver.id, dbNpcIds[1])
                end
            end
        end
        
        questStarterCaptured = true
        
    -- Check for item/object quest starter (quest items found on ground, in chests, etc)
    elseif _lastInteractedObject and (_lastInteractedObject.timestamp and (time() - _lastInteractedObject.timestamp) < 15) then
        questData.questStarter = {
            type = "object",
            name = _lastInteractedObject.name,
            id = _lastInteractedObject.id, -- May be nil if server doesn't provide it
            guid = _lastInteractedObject.guid, -- Store for debugging/analysis
            coords = _lastInteractedObject.coords
        }
        
        local debugMsg = "Quest started from object: " .. (_lastInteractedObject.name or "Unknown Object")
        if _lastInteractedObject.id and _lastInteractedObject.id > 0 then
            debugMsg = debugMsg .. " (ID: " .. _lastInteractedObject.id .. ")"
        else
            debugMsg = debugMsg .. " (ID: Server not providing - GUID: " .. (_lastInteractedObject.guid or "nil") .. ")"
        end
        
        -- DEBUG: Check coordinate capture
        if _lastInteractedObject.coords then
            debugMsg = debugMsg .. " at [" .. QuestieDataCollector:SafeFormatCoords(_lastInteractedObject.coords) .. "] in " .. (_lastInteractedObject.coords.zone or "Unknown Zone")
        else
            debugMsg = debugMsg .. " - WARNING: No coordinates captured!"
        end
        
        DebugMessage("|cFF00FF00[DATA]|r " .. debugMsg, 0, 1, 0)
        questStarterCaptured = true
    end
    
    -- Only show warning if we didn't capture any quest starter
    if not questStarterCaptured then
        DebugMessage("|cFFFFFF00[DATA]|r Warning: Quest starter not captured for quest " .. questId .. " (neither NPC nor object)", 1, 1, 0)
    end
    
    -- Clear objectives to prevent duplicates if re-accepting
    questData.objectives = {}
    
    -- Get quest objectives
    SelectQuestLogEntry(questIndex)
    local numObjectives = GetNumQuestLeaderBoards(questIndex)
    
    for i = 1, numObjectives do
        local text, objectiveType, finished = GetQuestLogLeaderBoard(i, questIndex)
        
        -- Try to enhance incomplete objective text
        if text and objectiveType == "monster" then
            -- Check if the text is missing the mob name (e.g., just "slain: 0/10")
            if string.find(text, "^%s*slain:") or string.find(text, "^%s*killed:") then
                -- Try to extract mob name from objectives text
                if questData.objectivesText then
                    -- Common patterns in objectives text:
                    -- "Kill 10 Panthers"
                    -- "Slay 10 Stranglethorn Tigers"
                    -- "Defeat 10 Lashtail Raptors"
                    local patterns = {
                        "[Kk]ill%s+%d+%s+(.+)",
                        "[Ss]lay%s+%d+%s+(.+)",
                        "[Dd]efeat%s+%d+%s+(.+)",
                        "[Dd]estroy%s+%d+%s+(.+)",
                        "(%S+)%s+slain:",
                        "(%S+%s+%S+)%s+slain:",
                        "(%S+%s+%S+%s+%S+)%s+slain:"
                    }
                    
                    for _, pattern in ipairs(patterns) do
                        local mobName = string.match(questData.objectivesText, pattern)
                        if mobName then
                            -- Clean up the mob name
                            mobName = string.gsub(mobName, "%.$", "")  -- Remove trailing period
                            mobName = string.gsub(mobName, "^%s+", "")  -- Remove leading spaces
                            mobName = string.gsub(mobName, "%s+$", "")  -- Remove trailing spaces
                            
                            -- Check if it's a reasonable mob name
                            if mobName and mobName ~= "" and not string.find(mobName, "^%d") then
                                -- Reconstruct the objective text with the mob name
                                local count = string.match(text, "(%d+/%d+)")
                                if count then
                                    text = mobName .. " slain: " .. count
                                else
                                    text = mobName .. " " .. text
                                end
                                DebugMessage("|cFF00FF00[DATA]|r Enhanced objective text: " .. text, 0, 1, 0)
                                break
                            end
                        end
                    end
                end
            end
        end
        
        -- Always store the objective
        table.insert(questData.objectives, {
            index = i,
            text = text or "",  -- Store empty string if nil
            type = objectiveType,
            finished = finished,
            progress = {}
        })
        
        if text and text ~= "" then
            DebugMessage("|cFF00FFFF[DATA]|r Objective " .. i .. ": " .. text, 0, 1, 1)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[DEBUG]|r Objective " .. i .. " has empty or nil text!", 1, 0, 0)
        end
    end
    
    -- Get quest text
    local _, questText = GetQuestLogQuestText()
    if questText then
        questData.questText = questText
    end
    
    -- Mark as actively tracking
    _activeTracking[questId] = true
    
    DebugMessage("|cFF00FF00[DATA]|r Now tracking quest: " .. questName .. " (ID: " .. questId .. ")", 0, 1, 0)
    
    -- Always show this message for missing quests (bypass toggle)
    DebugMessage("|cFF00FF00[DATA]|r Quest tracked: " .. questName .. " (ID: " .. questId .. ")", 0, 1, 0)
end

function QuestieDataCollector:TrackQuestComplete()
    -- CRITICAL: Capture the NPC immediately when QUEST_COMPLETE fires
    -- This happens when you click "Complete Quest" at the turn-in NPC
    QuestieDataCollector:CaptureNPCInfo()
    DebugMessage("|cFF00FFFF[DATA]|r QUEST_COMPLETE event - capturing turn-in NPC", 0, 1, 1)
    
    -- Try to identify which quest is being turned in
    -- Scan the quest log for complete quests that we're tracking
    local questId = nil
    local questName = nil
    
    for i = 1, GetNumQuestLogEntries() do
        local title, level, tag, isHeader, _, isComplete, _, _, qID = GetQuestLogTitle(i)
        -- Check if this quest is complete and we're tracking it
        if not isHeader and isComplete and _activeTracking[qID] then
            questId = qID
            questName = title
            DebugMessage("|cFF00FF00[DATA]|r Found completed quest: " .. questName .. " (ID: " .. questId .. ")", 0, 1, 0)
            break
        end
    end
    
    -- Fallback: Try GetQuestID if available
    if not questId or questId == 0 then
        questId = GetQuestID and GetQuestID() or nil
        if questId then
            DebugMessage("|cFFFFFF00[DATA]|r Got quest ID from GetQuestID: " .. questId, 1, 1, 0)
        end
    end
    
    -- Fallback: Try to get from the complete dialog title
    if not questId or questId == 0 then
        local questTitle = GetTitleText and GetTitleText() or nil
        if questTitle then
            for qId, qData in pairs(QuestieDataCollection.quests) do
                if qData.name == questTitle and _activeTracking[qId] then
                    questId = qId
                    questName = questTitle
                    DebugMessage("|cFFFFFF00[DATA]|r Found quest ID from title: " .. questId .. " (" .. questTitle .. ")", 1, 1, 0)
                    break
                end
            end
        end
    end
    
    if not questId or questId == 0 then
        DebugMessage("|cFFFF0000[DATA ERROR]|r Could not determine quest ID for completion", 1, 0, 0)
        return
    end
    
    -- Skip if quest is already in database
    if IsQuestInDatabase(questId) then
        return
    end
    
    if not _activeTracking[questId] then
        return
    end
    
    local questData = QuestieDataCollection.quests[questId]
    if not questData then
        return
    end
    
    questData.completedTimestamp = time()
    questData.completedDate = date("%Y-%m-%d %H:%M:%S")
    
    -- Capture turn-in NPC if available (increased window to 10 seconds)
    if _lastQuestGiver and (_lastQuestGiver.timestamp and (time() - _lastQuestGiver.timestamp) < 10) then
        questData.turnInNpc = {
            id = _lastQuestGiver.id,
            name = _lastQuestGiver.name,
            coords = _lastQuestGiver.coords
        }
        
        -- Check for database mismatch
        local dbQuest = QuestieDB.GetQuest(questId)
        if dbQuest and dbQuest.finishedBy and dbQuest.finishedBy[1] then
            local dbNpcIds = dbQuest.finishedBy[1]
            if dbNpcIds and #dbNpcIds > 0 then
                local found = false
                for _, npcId in ipairs(dbNpcIds) do
                    if npcId == _lastQuestGiver.id then
                        found = true
                        break
                    end
                end
                if not found then
                    CheckDatabaseMismatch("quest", questId, "turnInNpc", _lastQuestGiver.id, dbNpcIds[1])
                end
            end
        end
        
        DebugMessage("|cFF00FF00[DATA]|r Turn-in NPC: " .. (_lastQuestGiver.name or "Unknown") .. " (ID: " .. (_lastQuestGiver.id or 0) .. ")", 0, 1, 0)
    end
    
    -- Store completion zone data
    local zoneData = GetCurrentZoneData()
    if zoneData then
        questData.turnInZone = zoneData.zone
        questData.turnInSubZone = zoneData.subZone
        questData.turnInAreaId = zoneData.areaId  -- The actual area ID (could be subzone)
        questData.turnInParentZoneId = zoneData.parentZoneId  -- Parent zone
        questData.turnInQuestieZoneId = zoneData.questieZoneId  -- What should be used in database
        
        if zoneData.x and zoneData.y then
            questData.turnInCoords = {
                x = zoneData.x,
                y = zoneData.y,
                zone = zoneData.zone,
                subZone = zoneData.subZone,
                areaId = zoneData.areaId,
                parentZoneId = zoneData.parentZoneId,
                questieZoneId = zoneData.questieZoneId
            }
        end
    end
    
    DebugMessage("|cFF00FF00[DATA]|r Quest completed: " .. (questData.name or "Unknown") .. " (ID: " .. questId .. ")", 0, 1, 0)
end

function QuestieDataCollector:TrackQuestTurnIn(questId)
    if not questId or questId == 0 then
        return
    end
    
    -- Skip if quest is already in database
    if IsQuestInDatabase(questId) then
        return
    end
    
    if not _activeTracking[questId] then
        return
    end
    
    local questData = QuestieDataCollection.quests[questId]
    if not questData then
        return
    end
    
    -- Mark quest as turned in
    questData.turnedIn = true
    questData.turnInTimestamp = time()
    questData.turnInDate = date("%Y-%m-%d %H:%M:%S")
    
    -- Capture XP reward if we have it
    if _pendingXPReward and _pendingXPReward > 0 then
        questData.xpReward = _pendingXPReward
        DebugMessage("|cFF00FFFF[DATA]|r Quest XP reward: " .. _pendingXPReward, 0, 1, 1)
        _pendingXPReward = nil -- Clear it after using
    end
    
    -- CRITICAL: Capture turn-in NPC and available quests BEFORE detecting prerequisites
    if _lastInteractedNPC then
        questData.turnInNPC = {
            id = _lastInteractedNPC.id,
            name = _lastInteractedNPC.name,
            coords = _lastInteractedNPC.coords,
            zone = _lastInteractedNPC.zone
        }
        DebugMessage("|cFF00FF00[DATA]|r Turn-in NPC: " .. _lastInteractedNPC.name .. " (" .. _lastInteractedNPC.id .. ")", 0, 1, 0)
    end
    
    -- Detect prerequisites - check what new quests became available after this turn-in
    local newQuests = QuestieDataCollector:DetectPrerequisites(questId)
    
    -- Store the quests that became available after turn-in
    if newQuests and #newQuests > 0 then
        questData.unlockedQuests = {}
        for _, newQuest in ipairs(newQuests) do
            table.insert(questData.unlockedQuests, {
                name = newQuest.title,
                level = newQuest.level,
                npcId = _lastInteractedNPC and _lastInteractedNPC.id,
                npcName = _lastInteractedNPC and _lastInteractedNPC.name
            })
        end
        DebugMessage("|cFFFFFF00[DATA]|r Quest unlocked " .. #newQuests .. " new quest(s) at turn-in NPC", 1, 1, 0)
    end
    
    -- Remove from active tracking
    _activeTracking[questId] = nil
    
    -- Mark quest as completed for prerequisite tracking
    _completedQuests[questId] = true
    
    DebugMessage("|cFF00FF00[DATA]|r Quest turned in: " .. (questData.name or "Unknown") .. " (ID: " .. questId .. ")", 0, 1, 0)
end

function QuestieDataCollector:CheckQuestProgress()
    for questId in pairs(_activeTracking) do
        -- In dev mode, never stop tracking quests - collect all data regardless of database status
        if Questie.db.profile.dataCollectionDevMode then
            QuestieDataCollector:UpdateQuestObjectives(questId)
        else
            -- Normal mode: Skip if quest is now in database
            local inDB = IsQuestInDatabase(questId)
            local dbQuest = QuestieDB.GetQuest(questId)
            local dbQuestName = dbQuest and dbQuest.name or "nil"
            
            if inDB then
                _activeTracking[questId] = nil
                DebugMessage("|cFFFFAA00[DATA]|r Quest " .. questId .. " now in database ('" .. tostring(dbQuestName) .. "'), stopping collection", 1, 0.7, 0)
            else
                QuestieDataCollector:UpdateQuestObjectives(questId)
            end
        end
    end
end

function QuestieDataCollector:UpdateQuestObjectives(questId)
    local questData = QuestieDataCollection.quests[questId]
    if not questData then
        return
    end
    
    -- Find quest in log
    local questIndex = nil
    for i = 1, GetNumQuestLogEntries() do
        local _, _, _, _, _, _, _, qId = GetQuestLogTitle(i)
        if qId == questId then
            questIndex = i
            break
        end
    end
    
    if not questIndex then
        return
    end
    
    SelectQuestLogEntry(questIndex)
    local numObjectives = GetNumQuestLeaderBoards(questIndex)
    
    -- Ensure objectives table exists (defensive check for old save data)
    if not questData.objectives then
        questData.objectives = {}
    end
    
    for i = 1, numObjectives do
        local text, objectiveType, finished = GetQuestLogLeaderBoard(i, questIndex)
        if text and questData.objectives[i] then
            local objective = questData.objectives[i]
            
            -- Check if progress changed
            if objective.text ~= text or objective.finished ~= finished then
                -- Capture location of progress
                local coords = QuestieDataCollector:GetPlayerCoordinates()
                if coords then
                    -- Check if this progress update is related to a recent kill
                    local recentKill = QuestieDataCollector:GetRecentKillInfo()
                    local progressEntry = {
                        text = text,
                        finished = finished,
                        timestamp = time(),
                        coords = coords
                    }
                    
                    -- Add kill information if available
                    if recentKill then
                        progressEntry.killedMob = recentKill.name
                        DebugMessage("|cFF00FF00[DATA]|r Progress update linked to kill: " .. recentKill.name, 0, 1, 0)
                    end
                    
                    table.insert(objective.progress, progressEntry)
                    
                    DebugMessage("|cFF00FFFF[DATA]|r Objective progress: " .. text, 0, 1, 1)
                end
                
                -- Update objective
                objective.text = text
                objective.finished = finished
            end
        end
    end
end

function QuestieDataCollector:DetectNPCService(serviceType)
    -- Store detected service type for the last interacted NPC
    if _lastInteractedNPC and _lastInteractedNPC.id then
        if not _lastInteractedNPC.detectedServices then
            _lastInteractedNPC.detectedServices = {}
        end
        _lastInteractedNPC.detectedServices[serviceType] = true
        
        -- Also store in our tracked NPCs data
        local npcId = _lastInteractedNPC.id
        if not QuestieDataCollection.npcs then
            QuestieDataCollection.npcs = {}
        end
        if not QuestieDataCollection.npcs[npcId] then
            QuestieDataCollection.npcs[npcId] = {
                id = npcId,
                name = _lastInteractedNPC.name,
                coords = {},
                detectedServices = {}
            }
        end
        if not QuestieDataCollection.npcs[npcId].detectedServices then
            QuestieDataCollection.npcs[npcId].detectedServices = {}
        end
        QuestieDataCollection.npcs[npcId].detectedServices[serviceType] = true
        
        DebugMessage("|cFFFFFF00[DATA]|r Detected service: " .. serviceType .. " for NPC " .. (_lastInteractedNPC.name or "Unknown"), 1, 1, 0)
    end
end

function QuestieDataCollector:CaptureNPCInfo()
    -- Try multiple unit types to capture NPC info
    local guid = UnitGUID("target") or UnitGUID("npc") or UnitGUID("questnpc") or UnitGUID("mouseover")
    if not guid then
        -- As a fallback, if we're in a quest dialog, try to get the NPC another way
        local npcName = GetUnitName("questnpc") or GetUnitName("npc")
        if npcName then
            DebugMessage("|cFFFFFF00[DATA]|r Captured NPC by name: " .. npcName, 1, 1, 0)
        end
        return
    end
    
    -- Check if this is actually an NPC GUID (not an object)
    -- In WoW 3.3.5, GUID format is 0xF1TNNNNNNSSSSSS where T is the type (positions 5-6)
    -- 0x30 = Creature (NPC), 0x10 = Pet, 0x40 = Vehicle
    -- 0x50 = GameObject, 0x60 = Item, 0x70 = DynamicObject
    local guidType = tonumber(guid:sub(5, 6), 16)
    if not guidType or (guidType ~= 0x30 and guidType ~= 0x10 and guidType ~= 0x40) then
        -- This is likely an object, not an NPC
        DebugMessage("|cFFFFFF00[DATA]|r Skipping non-NPC entity (GUID type: 0x" .. string.format("%02X", guidType or 0) .. ")", 1, 1, 0)
        return
    end
    
    -- Extract NPC ID from GUID
    local npcId = ExtractNpcIdFromGuid(guid)
    if not npcId or npcId == 0 then
        return
    end
    
    local npcName = UnitName("target") or UnitName("npc") or UnitName("questnpc") or UnitName("mouseover")
    if not npcName then
        return
    end
    
    -- Get coordinates
    local coords = QuestieDataCollector:GetPlayerCoordinates()
    
    -- Store as last quest giver
    _lastQuestGiver = {
        id = npcId,
        name = npcName,
        timestamp = time(),
        coords = coords
    }
    
    -- Also store as last interacted NPC for service NPC capture
    _lastInteractedNPC = {
        guid = guid,
        id = npcId,
        name = npcName,
        timestamp = time(),
        coords = coords,
        zone = GetRealZoneText(),
        subZone = GetSubZoneText()
    }
    
    DebugMessage("|cFF00FF00[DATA]|r Captured NPC: " .. npcName .. " (ID: " .. npcId .. ")", 0, 1, 0)
    
    -- Check for database mismatch
    local dbNpc = QuestieDB:GetNPC(npcId)
    if dbNpc then
        if dbNpc.name and dbNpc.name ~= npcName then
            CheckDatabaseMismatch("npc", npcId, "name", npcName, dbNpc.name)
        end
        
        -- Check zone and coordinate mismatches if we have coordinates
        if coords and (coords.areaId or coords.questieZoneId) and dbNpc.spawns then
            local foundZone = false
            local closestDistance = 9999
            
            -- Use questieZoneId if available, otherwise areaId
            local currentZone = coords.questieZoneId or coords.areaId
            
            -- Debug logging to understand zone detection
            if npcId == 1568 or npcId == 1569 then
                DebugMessage(string.format("[ZONE DEBUG] NPC %d: questieZoneId=%s, areaId=%s, using=%s", 
                    npcId, 
                    tostring(coords.questieZoneId), 
                    tostring(coords.areaId), 
                    tostring(currentZone)), 1, 1, 0)
            end
            
            for zoneId, spawns in pairs(dbNpc.spawns) do
                -- Check if zones match directly OR if current zone is a subzone of the database zone
                local zonesMatch = false
                if zoneId == currentZone then
                    zonesMatch = true
                elseif SUBZONE_TO_PARENT[currentZone] and SUBZONE_TO_PARENT[currentZone] == zoneId then
                    -- Current zone is a subzone of the database zone (e.g., Brill (21) -> Tirisfal (85))
                    zonesMatch = true
                elseif SUBZONE_TO_PARENT[zoneId] and SUBZONE_TO_PARENT[zoneId] == currentZone then
                    -- Database zone is a subzone of current zone (less common but possible)
                    zonesMatch = true
                end
                
                if zonesMatch then
                    foundZone = true
                    
                    -- Check coordinate accuracy within this zone
                    if spawns and type(spawns) == "table" then
                        for _, spawn in ipairs(spawns) do
                            if spawn and spawn[1] and spawn[2] then
                                local xDiff = math.abs(coords.x - spawn[1])
                                local yDiff = math.abs(coords.y - spawn[2])
                                local distance = math.sqrt(xDiff * xDiff + yDiff * yDiff)
                                
                                if distance < closestDistance then
                                    closestDistance = distance
                                end
                            end
                        end
                    end
                    break
                end
            end
            
            -- Report zone mismatch
            if not foundZone then
                CheckDatabaseMismatch("npc", npcId, "zone", currentZone, next(dbNpc.spawns))
            end
            
            -- Report coordinate mismatch if NPC is too far from any known spawn
            -- Using 10% distance threshold (10 units in 0-100 coordinate system)
            -- This avoids false positives from minor movement or patrol paths
            if foundZone and closestDistance > 10 then
                CheckDatabaseMismatch("npc", npcId, "coords", 
                    {x = coords.x, y = coords.y}, 
                    {distance = closestDistance})
                DebugMessage("|cFFFFAA00[DATA MISMATCH]|r NPC " .. npcId .. " found " .. string.format("%.1f", closestDistance) .. " units from nearest DB spawn", 1, 0.7, 0)
            end
        end
    end
    
    DebugMessage("|cFF00FF00[DATA]|r Captured NPC: " .. npcName .. " (ID: " .. npcId .. ")", 0, 1, 0)
    
    -- Capture available quests at this NPC for prerequisite tracking
    QuestieDataCollector:CaptureAvailableQuests(npcId, npcName)
end

-- Capture what quests are available at an NPC (for prerequisite detection)
function QuestieDataCollector:CaptureAvailableQuests(npcId, npcName)
    if not npcId then return end
    
    -- Get available quests from gossip
    local availableQuests = {}
    local numAvailable = GetNumGossipAvailableQuests()
    
    if numAvailable and numAvailable > 0 then
        for i = 1, numAvailable do
            local title, level, isTrivial, isComplete, isLegendary, isIgnored = select((i-1)*7+1, GetGossipAvailableQuests())
            if title then
                table.insert(availableQuests, {
                    title = title,
                    level = level,
                    isTrivial = isTrivial
                })
                DebugMessage("|cFF00FFFF[DATA]|r Available quest at NPC: " .. title .. " (Level " .. (level or "?") .. ")", 0, 1, 1)
            end
        end
    end
    
    -- Store the available quests for this NPC
    _lastNPCWithQuests = {
        npcId = npcId,
        npcName = npcName,
        availableQuests = availableQuests,
        timestamp = time()
    }
    
    -- Store for comparison after quest turn-in
    _availableQuestsBeforeTurnIn[npcId] = availableQuests
    
    return availableQuests
end

-- Get player's professions and skill levels (WoW 3.3.5 compatible)
function QuestieDataCollector:GetPlayerProfessions()
    local professions = {}
    
    -- Use QuestieProfessions module for 3.3.5 compatibility (GetProfessions doesn't exist in 3.3.5)
    local QuestieProfessions = QuestieLoader:ImportModule("QuestieProfessions")
    if not QuestieProfessions then
        DebugMessage("|cFFFF0000[DATA]|r QuestieProfessions module not available", 1, 0, 0)
        return professions -- Return empty table if module not available
    end
    
    -- Initialize if not already done
    if not QuestieProfessions.professionTable then
        QuestieProfessions:Init()
    end
    
    -- CRITICAL: Must call Update() first to populate the professions table!
    QuestieProfessions:Update()
    
    local playerProfessions = QuestieProfessions:GetPlayerProfessions()
    if not playerProfessions then
        DebugMessage("|cFFFFFF00[DATA]|r No profession data available", 1, 1, 0)
        return professions
    end
    
    -- Convert QuestieProfessions format to our expected format
    for professionId, professionData in pairs(playerProfessions) do
        if professionData and professionData[1] and professionData[2] then
            local name = professionData[1]  -- Profession name
            local skillLevel = professionData[2]  -- Current skill level
            
            -- Determine profession type based on name (simplified classification)
            local profType = "secondary"
            if name == "Herbalism" or name == "Mining" or name == "Skinning" or 
               name == "Alchemy" or name == "Blacksmithing" or name == "Enchanting" or
               name == "Engineering" or name == "Leatherworking" or name == "Tailoring" or
               name == "Jewelcrafting" or name == "Inscription" then
                profType = "primary"
            elseif name == "Cooking" then
                profType = "cooking"
            elseif name == "First Aid" then
                profType = "firstAid"
            elseif name == "Fishing" then
                profType = "fishing"
            elseif name == "Archaeology" then
                profType = "archaeology"
            end
            
            table.insert(professions, {
                name = name,
                type = profType,
                skillLevel = skillLevel,
                maxSkillLevel = 450, -- WoW 3.3.5 max skill level
                skillLine = professionId
            })
            DebugMessage("|cFF00FFFF[DATA]|r Profession: " .. name .. " (" .. skillLevel .. "/450)", 0, 1, 1)
        end
    end
    
    if #professions > 0 then
        DebugMessage("|cFF00FF00[DATA]|r Found " .. #professions .. " professions for player", 0, 1, 0)
    else
        DebugMessage("|cFFFFFF00[DATA]|r No professions found - player may not have any professions", 1, 1, 0)
    end
    
    return professions
end

-- Detect new quests that became available after turn-in (prerequisites)
function QuestieDataCollector:DetectPrerequisites(questId)
    if not _lastNPCWithQuests or not _lastNPCWithQuests.npcId then 
        DebugMessage("|cFFFF0000[DATA]|r No NPC data for prerequisite detection", 1, 0, 0)
        return {}
    end
    
    local npcId = _lastNPCWithQuests.npcId
    local questsBeforeTurnIn = _availableQuestsBeforeTurnIn[npcId] or {}
    
    -- Capture quests available NOW (after turn-in)
    local questsAfterTurnIn = QuestieDataCollector:CaptureAvailableQuests(npcId, _lastNPCWithQuests.npcName)
    
    -- Find NEW quests that weren't available before
    local newQuests = {}
    for _, afterQuest in ipairs(questsAfterTurnIn) do
        local wasAvailableBefore = false
        for _, beforeQuest in ipairs(questsBeforeTurnIn) do
            if beforeQuest.title == afterQuest.title then
                wasAvailableBefore = true
                break
            end
        end
        
        if not wasAvailableBefore then
            table.insert(newQuests, afterQuest)
            DebugMessage("|cFFFFFF00[DATA]|r NEW quest available after turn-in: " .. afterQuest.title .. " (unlocked by completing quest " .. questId .. ")", 1, 1, 0)
            
            -- Store bidirectional relationship
            -- 1. This quest unlocks the new quest
            if questId and QuestieDataCollection.quests[questId] then
                if not QuestieDataCollection.quests[questId].unlocksQuests then
                    QuestieDataCollection.quests[questId].unlocksQuests = {}
                end
                table.insert(QuestieDataCollection.quests[questId].unlocksQuests, {
                    name = afterQuest.title,
                    level = afterQuest.level
                })
            end
            
            -- 2. Look for the new quest in our data and mark it as requiring this quest
            for trackedId, trackedData in pairs(QuestieDataCollection.quests) do
                if trackedData.name == afterQuest.title then
                    if not trackedData.requiresQuest then
                        trackedData.requiresQuest = {}
                    end
                    table.insert(trackedData.requiresQuest, {
                        id = questId,
                        name = QuestieDataCollection.quests[questId].name
                    })
                    DebugMessage("|cFF00FFFF[DATA]|r Linked prerequisite: Quest " .. trackedId .. " requires quest " .. questId, 0, 1, 1)
                    break
                end
            end
        end
    end
    
    -- Also check if any quests that were available are now GONE (exclusive quests)
    local removedQuests = {}
    for _, beforeQuest in ipairs(questsBeforeTurnIn) do
        local stillAvailable = false
        for _, afterQuest in ipairs(questsAfterTurnIn) do
            if beforeQuest.title == afterQuest.title then
                stillAvailable = true
                break
            end
        end
        
        if not stillAvailable then
            table.insert(removedQuests, beforeQuest)
            DebugMessage("|cFFFF8800[DATA]|r Quest no longer available after turn-in: " .. beforeQuest.title .. " (may be exclusive with quest " .. questId .. ")", 1, 0.5, 0)
        end
    end
    
    if #removedQuests > 0 and questId and QuestieDataCollection.quests[questId] then
        QuestieDataCollection.quests[questId].removedQuests = removedQuests
    end
    
    -- Clear the before turn-in cache for this NPC
    _availableQuestsBeforeTurnIn[npcId] = nil
    
    return newQuests
end

function QuestieDataCollector:TrackTargetedMob()
    if not UnitExists("target") or UnitIsPlayer("target") or UnitIsFriend("player", "target") then
        return
    end
    
    local guid = UnitGUID("target")
    if not guid then
        return
    end
    
    -- Extract NPC ID from GUID
    local npcId = tonumber(guid:sub(6, 12), 16)
    if not npcId or npcId == 0 then
        return
    end
    
    local npcName = UnitName("target")
    local npcLevel = UnitLevel("target")
    
    -- Get coordinates
    local coords = QuestieDataCollector:GetPlayerCoordinates()
    
    -- Check all tracked quests to see if this mob is relevant
    for questId in pairs(_activeTracking) do
        -- Skip if quest is now in database
        if not IsQuestInDatabase(questId) then
            local questData = QuestieDataCollection.quests[questId]
            if questData then
                -- Ensure mobs table exists (defensive check for old save data)
                if not questData.mobs then
                    questData.mobs = {}
                end
                
                -- Store mob info
                if not questData.mobs[npcId] then
                    questData.mobs[npcId] = {
                        id = npcId,
                        name = npcName,
                        level = npcLevel,
                        locations = {}
                    }
                end
                
                -- Add location if we have valid coords
                if coords and coords.x and coords.y and coords.x > 0 and coords.y > 0 then
                    -- Check if this location is not a duplicate (within 1 unit distance)
                    local isDuplicate = false
                    for _, existingLoc in ipairs(questData.mobs[npcId].locations) do
                        if existingLoc and existingLoc.x and existingLoc.y then
                            local distance = math.abs(coords.x - existingLoc.x) + math.abs(coords.y - existingLoc.y)
                            if distance < 1 then
                                isDuplicate = true
                                break
                            end
                        end
                    end
                    
                    if not isDuplicate then
                        table.insert(questData.mobs[npcId].locations, coords)
                    end
                else
                    DebugMessage("|cFFFF0000[DATA]|r Invalid coordinates for mob " .. npcName, 1, 0, 0)
                end
                
                -- Disabled: Too spammy even for debug mode
                -- DebugMessage("|cFFAA8833[DATA]|r Tracked quest mob: " .. npcName .. " (ID: " .. npcId .. ") for quest " .. questId, 0.67, 0.53, 0.2)
            end
        end
    end
end

function QuestieDataCollector:TrackMouseoverUnit()
    if not UnitExists("mouseover") or UnitIsPlayer("mouseover") then
        return
    end
    
    local guid = UnitGUID("mouseover")
    if not guid then
        return
    end
    
    -- Check if it's an object (GameObjects have different GUID format)
    local guidType = tonumber(guid:sub(1, 5), 16)
    if guidType and bit.band(guidType, 0x00F) == 0x00B then -- GameObject type
        local objectName = UnitName("mouseover")
        if objectName then
            local coords = QuestieDataCollector:GetPlayerCoordinates()
            
            -- Try to extract object ID from GUID (WoW 3.3.5 format attempt)
            -- GameObject GUIDs in 3.3.5: Different format than NPCs, but let's try to extract what we can
            local objectId = nil
            if guid then
                -- Try different GUID parsing approaches for GameObjects
                -- Method 1: Try the same approach as NPCs (bytes 6-12)
                objectId = tonumber(guid:sub(6, 12), 16)
                -- Method 2: If that doesn't work, try other byte ranges
                if not objectId or objectId == 0 then
                    objectId = tonumber(guid:sub(10, 16), 16)
                end
                -- Method 3: Extract from different position  
                if not objectId or objectId == 0 then
                    objectId = tonumber(guid:sub(14, 20), 16)
                end
            end
            
            _lastInteractedObject = {
                name = objectName,
                id = objectId, -- Will be nil if we can't extract it
                guid = guid,   -- Store full GUID for debugging
                timestamp = time(),
                coords = coords
            }
            
            -- DEBUG: Show coordinate capture status
            local coordsDebug = ""
            if coords then
                coordsDebug = " at [" .. QuestieDataCollector:SafeFormatCoords(coords) .. "] in " .. (coords.zone or "Unknown Zone")
            else
                coordsDebug = " - WARNING: Failed to get coordinates!"
            end
            
            if objectId and objectId > 0 then
                DebugMessage("|cFF00AAFF[DATA]|r Moused over object: " .. objectName .. " (ID: " .. objectId .. ")" .. coordsDebug, 0, 0.67, 1)
            else
                DebugMessage("|cFF00AAFF[DATA]|r Moused over object: " .. objectName .. " (ID unknown, GUID: " .. (guid or "nil") .. ")" .. coordsDebug, 0, 0.67, 1)
            end
        end
    else
        -- It's an NPC, track it similar to targeted mob
        QuestieDataCollector:TrackTargetedMob()
    end
end

function QuestieDataCollector:HandleCombatEvent(...)
    local args = {...}
    
    -- Debug: Show all parameters for WoW 3.3.5a compatibility analysis
    DebugMessage("|cFFFF00FF[DATA]|r Combat event args count: " .. #args, 1, 0, 1)
    for i = 1, math.min(10, #args) do
        DebugMessage("|cFFFF00FF[DATA]|r Arg[" .. i .. "]: " .. tostring(args[i]), 1, 0, 1)
    end
    
    -- WoW 3.3.5a combat log parameter parsing
    local timestamp = args[1]
    local event = args[2] 
    local sourceGUID = args[3]
    local sourceName = args[4]
    local sourceFlags = args[5]
    local destGUID = args[6]  -- Real GUID is at position 6
    local destName = args[7]  -- Name is at position 7
    local destNPCId = args[8] -- Direct NPC ID at position 8
    
    -- Debug: Show all combat events
    DebugMessage("|cFFFF00FF[DATA]|r Combat event: " .. (event or "nil"), 1, 0, 1)
    
    if event == "UNIT_DIED" or event == "PARTY_KILL" then
        -- Debug: Show what we got from combat log
        DebugMessage("|cFFFFFFFF[DATA]|r Kill event details - destGUID: " .. (destGUID or "nil") .. ", destName: " .. (destName or "nil"), 1, 1, 1)
        
        if destGUID and destName then
            -- Debug: Show corrected parsing
            DebugMessage("|cFFFFFFFF[DATA]|r Corrected - destGUID: " .. destGUID .. ", destName: " .. destName, 1, 1, 1)
            
            -- PRIORITY FIX: Use GUID extraction for data collection (more accurate for quest tracking)
            -- Extract NPC ID from GUID first (this gives us the quest-compatible ID like 46835)
            local npcId = ExtractNpcIdFromGuid(destGUID)
            
            -- Only fall back to direct combat log NPC ID if GUID extraction fails
            if not npcId or npcId <= 0 then
                npcId = destNPCId
                DebugMessage("|cFFFFAA00[DATA]|r Using fallback combat log NPC ID: " .. (destNPCId or "nil"), 1, 0.7, 0)
            end
            DebugMessage("|cFFFFFFFF[DATA]|r Using NPC ID: " .. (npcId or "nil"), 1, 1, 1)
            
            if npcId and npcId > 0 then
                -- Debug: Show when we detect a kill
                DebugMessage("|cFFFF6600[DATA]|r Kill detected: " .. destName .. " (ID: " .. npcId .. ") from GUID: " .. tostring(destGUID), 1, 0.4, 0)
                
                -- Store recent kill for item correlation and progress tracking
                local coords = QuestieDataCollector:GetPlayerCoordinates()
                _recentKills[npcId] = {
                    name = destName,
                    timestamp = time(),
                    coords = coords  -- Include location of kill for progress tracking
                }
                
                -- Also track this kill directly for all relevant quests
                QuestieDataCollector:TrackMobKill(npcId, destName, coords)
                
                -- Debug message for kill tracking
                if coords then
                    DebugMessage("|cFF8B4513[DATA]|r Tracked kill: " .. destName .. " at " .. 
                               string.format("%.1f, %.1f", coords.x or 0, coords.y or 0) .. " in " .. 
                               (coords.zone or "Unknown"), 0.5, 0.3, 0.1)
                end
                
                -- Clean up old kills (older than 10 seconds)
                for id, data in pairs(_recentKills) do
                    if (time() - data.timestamp) > 10 then
                        _recentKills[id] = nil
                    end
                end
            end
        end
    end
end

-- Track a mob kill directly for all relevant quests
function QuestieDataCollector:TrackMobKill(npcId, npcName, coords)
    local activeCount = 0
    for _ in pairs(_activeTracking) do activeCount = activeCount + 1 end
    DebugMessage("|cFFFFFF00[DATA]|r Checking kill tracking for " .. npcName .. " (ID: " .. npcId .. ") against " .. activeCount .. " tracked quests", 1, 1, 0)
    
    -- Debug: Show what's actually in _activeTracking
    DebugMessage("|cFFFFFF00[DATA]|r _activeTracking contents:", 1, 1, 0)
    for questId, value in pairs(_activeTracking) do
        DebugMessage("|cFFFFFF00[DATA]|r   Quest " .. questId .. " = " .. tostring(value), 1, 1, 0)
    end
    
    -- Debug: Show what's in QuestieDataCollection.quests
    DebugMessage("|cFFFFFF00[DATA]|r QuestieDataCollection.quests contents:", 1, 1, 0)
    if QuestieDataCollection and QuestieDataCollection.quests then
        for questId, questData in pairs(QuestieDataCollection.quests) do
            DebugMessage("|cFFFFFF00[DATA]|r   Quest " .. questId .. " exists with name: " .. (questData.name or "nil"), 1, 1, 0)
        end
    else
        DebugMessage("|cFFFFFF00[DATA]|r QuestieDataCollection.quests is nil!", 1, 1, 0)
    end
    
    -- Check all tracked quests to see if this mob is relevant
    for questId in pairs(_activeTracking) do
        local inDB = IsQuestInDatabase(questId)
        local dbQuest = QuestieDB.GetQuest(questId)
        local dbQuestName = dbQuest and dbQuest.name or "nil"
        DebugMessage("|cFFFFFF00[DATA]|r Checking quest " .. questId .. " - In DB: " .. tostring(inDB) .. " - DB Quest Name: " .. tostring(dbQuestName), 1, 1, 0)
        if not IsQuestInDatabase(questId) then
            local questData = QuestieDataCollection.quests[questId]
            if questData then
                -- Ensure required tables exist
                if not questData.mobs then
                    questData.mobs = {}
                end
                if not questData.kills then
                    questData.kills = {}
                end
                
                -- Initialize mob data if needed
                if not questData.mobs[npcId] then
                    questData.mobs[npcId] = {
                        id = npcId,
                        name = npcName,
                        level = nil, -- Will be filled from mouseover data
                        locations = {}
                    }
                end
                
                -- Record the kill
                local killEntry = {
                    mobId = npcId,
                    mobName = npcName,
                    timestamp = time(),
                    coords = coords
                }
                
                table.insert(questData.kills, killEntry)
                
                -- Also add this location to mob locations if not duplicate
                if coords and coords.x and coords.y and coords.x > 0 and coords.y > 0 then
                    local isDuplicate = false
                    for _, existingLoc in ipairs(questData.mobs[npcId].locations) do
                        if existingLoc and existingLoc.x and existingLoc.y then
                            local distance = math.abs(coords.x - existingLoc.x) + math.abs(coords.y - existingLoc.y)
                            if distance < 2 then  -- 2 yard threshold for kill locations
                                isDuplicate = true
                                break
                            end
                        end
                    end
                    
                    if not isDuplicate then
                        table.insert(questData.mobs[npcId].locations, coords)
                    end
                end
                
                DebugMessage("|cFF90EE90[DATA]|r Recorded kill: " .. npcName .. " for quest " .. (questData.name or questId), 0.6, 0.9, 0.6)
            end
        end
    end
end

-- Helper function to get the most recent kill info for progress tracking
function QuestieDataCollector:GetRecentKillInfo()
    local mostRecentKill = nil
    local newestTimestamp = 0
    
    -- Find the most recent kill within the last 5 seconds
    local currentTime = time()
    for npcId, killData in pairs(_recentKills) do
        if (currentTime - killData.timestamp) <= 5 and killData.timestamp > newestTimestamp then
            newestTimestamp = killData.timestamp
            mostRecentKill = killData
        end
    end
    
    return mostRecentKill
end

-- Helper function to safely format coordinates (prevents nil errors)
function QuestieDataCollector:SafeFormatCoords(coords)
    if not coords then
        return "[No coordinates available]"
    end
    
    local x = coords.x
    local y = coords.y
    
    if x and y and type(x) == "number" and type(y) == "number" then
        return string.format("%.1f, %.1f", x, y)
    else
        return "[Invalid coordinates]"
    end
end

function QuestieDataCollector:HandleLootOpened()
    -- Get current location
    local coords = QuestieDataCollector:GetPlayerCoordinates()
    local zone = GetRealZoneText()
    local subZone = GetSubZoneText()
    
    -- Determine what we're looting from
    local lootSourceName = nil
    local lootSourceId = nil
    local lootSourceType = nil
    
    -- Check if we're looting a corpse
    local targetGuid = UnitGUID("target")
    if targetGuid and UnitIsDead("target") then
        lootSourceName = UnitName("target")
        lootSourceId = ExtractNpcIdFromGuid(targetGuid)
        lootSourceType = "npc"
    else
        -- Try to get container name from GameTooltip
        local containerName = nil
        if GameTooltip:IsVisible() then
            local tooltipText = GameTooltipTextLeft1:GetText()
            if tooltipText and tooltipText ~= "" then
                containerName = tooltipText
            end
        end
        
        -- Check loot frame for container name
        if not containerName and LootFrame:IsVisible() then
            local lootName = GetLootSourceInfo and GetLootSourceInfo(1) or nil
            if not lootName and LootFrameTitle and LootFrameTitle:GetText() then
                lootName = LootFrameTitle:GetText()
            end
            if lootName then
                containerName = lootName
            end
        end
        
        -- Use the container name we found, or fall back to last interacted object
        if containerName and containerName ~= "" then
            lootSourceName = containerName
            lootSourceType = "object"
            -- Update _lastInteractedObject with better name
            if not _lastInteractedObject then
                _lastInteractedObject = {}
            end
            _lastInteractedObject.name = containerName
            _lastInteractedObject.timestamp = time()
        elseif _lastInteractedObject and _lastInteractedObject.name then
            lootSourceName = _lastInteractedObject.name
            lootSourceType = "object"
        else
            lootSourceName = "Ground Object"
            lootSourceType = "object"
        end
    end
    
    -- Store current loot source for item tracking
    _currentLootSource = {
        name = lootSourceName,
        id = lootSourceId,
        type = lootSourceType,
        timestamp = time()
    }
    
    -- CRITICAL: Track this object/container for ALL active quests
    -- This is how v1.0.68 builds the extensive GROUND OBJECTS list
    if lootSourceName and lootSourceType == "object" then
        for questId in pairs(_activeTracking) do
            local questData = QuestieDataCollection.quests[questId]
            if questData then
                questData.objects = questData.objects or {}
                
                -- Use object name as key for grouping locations
                if not questData.objects[lootSourceName] then
                    questData.objects[lootSourceName] = {
                        name = lootSourceName,
                        id = lootSourceId,
                        locations = {}
                    }
                end
                
                -- Add this location if we have coordinates
                if coords and coords.x and coords.y then
                    -- Use rounded coordinates as key to prevent duplicates
                    local locKey = string.format("%.1f,%.1f", coords.x, coords.y)
                    if not questData.objects[lootSourceName].locations[locKey] then
                        questData.objects[lootSourceName].locations[locKey] = {
                            x = coords.x,
                            y = coords.y,
                            zone = zone,
                            subZone = subZone,
                            timestamp = time()
                        }
                        DebugMessage("|cFF00FFFF[DATA]|r Tracked object '" .. lootSourceName .. 
                            "' at [" .. string.format("%.1f, %.1f", coords.x, coords.y) .. "] in " .. zone, 0, 1, 1)
                    end
                end
            end
        end
    end
    
    -- Detect and capture gathering nodes and treasure chests
    if lootSourceName and lootSourceType == "object" then
        local lowerName = string.lower(lootSourceName)
        
        -- Check for common gathering node patterns
        if string.find(lowerName, "herb") or 
           string.find(lowerName, "flower") or
           string.find(lowerName, "plant") or
           string.find(lowerName, "bloom") or
           string.find(lowerName, "root") or
           string.find(lowerName, "moss") or
           string.find(lowerName, "petal") then
            QuestieDataCollector:CaptureGatheringNode("herb", lootSourceName)
        elseif string.find(lowerName, "ore") or
               string.find(lowerName, "vein") or
               string.find(lowerName, "deposit") or
               string.find(lowerName, "copper") or
               string.find(lowerName, "tin") or
               string.find(lowerName, "iron") or
               string.find(lowerName, "silver") or
               string.find(lowerName, "gold") or
               string.find(lowerName, "mithril") or
               string.find(lowerName, "thorium") then
            QuestieDataCollector:CaptureGatheringNode("ore", lootSourceName)
        elseif string.find(lowerName, "chest") or
               string.find(lowerName, "crate") or
               string.find(lowerName, "barrel") or
               string.find(lowerName, "cache") or
               string.find(lowerName, "stash") or
               string.find(lowerName, "treasure") or
               string.find(lowerName, "coffer") or
               string.find(lowerName, "strongbox") then
            QuestieDataCollector:CaptureTreasureChest(lootSourceName)
        end
    end
end

function QuestieDataCollector:HandleLootMessage(message)
    -- Parse loot message for quest items
    local itemLink = string.match(message, "|c%x+|Hitem:.-|h%[(.-)%]|h|r")
    if not itemLink then
        return
    end
    
    local itemId = tonumber(string.match(message, "|Hitem:(%d+):"))
    if not itemId then
        return
    end
    
    -- Check if this is a quest item by checking if we looted it while on a quest
    -- We'll track ALL items looted while questing, not just ones mentioned in objectives
    for questId in pairs(_activeTracking) do
        if not IsQuestInDatabase(questId) then
            local questData = QuestieDataCollection.quests[questId]
            if questData then
                -- Ensure items table exists (defensive check for old save data)
                if not questData.items then
                    questData.items = {}
                end
                
                -- Store item info for any item looted while on this quest
                if not questData.items[itemId] then
                    questData.items[itemId] = {
                        id = itemId,
                        name = itemLink,
                        sources = {}
                    }
                end
                
                -- Link to source if we have one (from recent kill or loot opened)
                local sourceLinked = false
                
                -- First check _currentLootSource (from LOOT_OPENED)
                if _currentLootSource and _currentLootSource.timestamp and (time() - _currentLootSource.timestamp) < 5 then
                    local source = {
                        type = _currentLootSource.type,
                        name = _currentLootSource.name,
                        id = _currentLootSource.id,
                        timestamp = time()
                    }
                    table.insert(questData.items[itemId].sources, source)
                    sourceLinked = true
                    
                    if _currentLootSource.type == "npc" then
                        DebugMessage("|cFF00FF00[DATA]|r Quest item " .. itemLink .. " dropped from " .. (_currentLootSource.name or "Unknown"), 0, 1, 0)
                    else
                        DebugMessage("|cFF00FFFF[DATA]|r Quest item " .. itemLink .. " obtained from " .. (_currentLootSource.name or "object"), 0, 1, 1)
                    end
                    
                -- If no current loot source, check recent kills
                elseif not sourceLinked then
                    for npcId, killData in pairs(_recentKills) do
                        if (time() - killData.timestamp) < 5 then
                            local source = {
                                type = "npc",
                                name = killData.name,
                                id = npcId,
                                timestamp = time()
                            }
                            table.insert(questData.items[itemId].sources, source)
                            sourceLinked = true
                            DebugMessage("|cFF00FF00[DATA]|r Quest item " .. itemLink .. " dropped from recent kill: " .. (killData.name or "Unknown"), 0, 1, 0)
                            break
                        end
                    end
                end
                
                -- If still no source, just track that we got the item
                if not sourceLinked then
                    DebugMessage("|cFFFFFF00[DATA]|r Quest item " .. itemLink .. " looted (source unknown)", 1, 1, 0)
                end
            end
        end
    end
end

function QuestieDataCollector:HandleItemPush(bagSlot, iconPath)
    -- This is called when an item is added to inventory
    -- We can use this to correlate items with recent interactions
end

function QuestieDataCollector:CaptureServiceNPC(serviceType)
    -- Service NPCs are ALWAYS captured regardless of mode
    -- They provide valuable reference data for the database
    DebugMessage("|cFF00FFFF[DATA]|r Attempting to capture " .. serviceType, 0, 1, 1)
    
    -- Try multiple unit types - many service NPCs are interacted with via right-click without targeting
    local guid = UnitGUID("target") or UnitGUID("npc") or UnitGUID("mouseover") or UnitGUID("questnpc")
    if not guid then
        -- Try to get from interaction frame as fallback
        if _lastInteractedNPC and _lastInteractedNPC.guid then
            guid = _lastInteractedNPC.guid
            DebugMessage("|cFF00FFFF[DATA]|r Using last interacted NPC GUID", 0, 1, 1)
        else
            DebugMessage("|cFFFF0000[DATA]|r No GUID found for " .. serviceType, 1, 0, 0)
            return
        end
    end
    
    -- Extract NPC ID from GUID (WoW 3.3.5 format)
    local npcId = ExtractNpcIdFromGuid(guid)
    if not npcId or npcId == 0 then
        return
    end
    
    local npcName = UnitName("target") or UnitName("npc") or UnitName("mouseover") or UnitName("questnpc")
    if not npcName and _lastInteractedNPC and _lastInteractedNPC.name then
        npcName = _lastInteractedNPC.name
    end
    if not npcName then
        return
    end
    
    -- Get coordinates
    local coords = QuestieDataCollector:GetPlayerCoordinates()
    
    -- Handle flight masters separately (but also add to serviceNPCs)
    if serviceType == "flight_master" then
        -- Initialize flight master data if needed
        if not QuestieDataCollection.flightMasters[npcId] then
            QuestieDataCollection.flightMasters[npcId] = {
                id = npcId,
                name = npcName,
                locations = {}
            }
        end
        
        local npcData = QuestieDataCollection.flightMasters[npcId]
        
        -- Update name if different
        if npcData.name ~= npcName then
            npcData.name = npcName
        end
        
        -- Add location if we have coords and it's new
        if coords then
            local isNewLocation = true
            for _, loc in ipairs(npcData.locations) do
                if loc.zone == coords.zone and loc.areaId == coords.areaId then
                    -- Check if coords are significantly different (more than 10 units)
                    if loc.x and loc.y then
                        local distance = math.sqrt((coords.x - loc.x)^2 + (coords.y - loc.y)^2)
                        if distance < 10 then
                            isNewLocation = false
                            break
                        end
                    end
                end
            end
            
            if isNewLocation then
                table.insert(npcData.locations, coords)
            end
        end
        
        DebugMessage("|cFF00FF00[DATA]|r Captured flight master: " .. npcName .. " (ID: " .. npcId .. ")", 0, 1, 0)
        -- Don't return here - also add to serviceNPCs collection
    end
    
    -- Initialize service NPC data if needed (for all service NPCs including flight masters)
    if not QuestieDataCollection.serviceNPCs[npcId] then
        QuestieDataCollection.serviceNPCs[npcId] = {
            id = npcId,
            name = npcName,
            services = {},
            locations = {}
        }
    end
    
    local npcData = QuestieDataCollection.serviceNPCs[npcId]
    
    -- Update name if different
    if npcData.name ~= npcName then
        npcData.name = npcName
    end
    
    -- Service priority: innkeeper > banker > flight_master > trainer > repair > vendor
    local servicePriority = {
        innkeeper = 1,
        banker = 2,
        guild_banker = 2,
        flight_master = 3,
        trainer = 4,
        repair = 5,
        vendor = 6
    }
    
    -- Add service type if not already tracked
    local hasService = false
    local hasHigherPriority = false
    for _, service in ipairs(npcData.services) do
        if service == serviceType then
            hasService = true
            break
        end
        -- Check if we already have a higher priority service
        -- Don't add vendor if we already know it's an innkeeper
        if service == "innkeeper" and serviceType == "vendor" then
            hasHigherPriority = true
            break
        end
    end
    
    if not hasService and not hasHigherPriority then
        table.insert(npcData.services, serviceType)
        
        -- Sort services by priority
        table.sort(npcData.services, function(a, b)
            local priorityA = servicePriority[a] or 99
            local priorityB = servicePriority[b] or 99
            return priorityA < priorityB
        end)
    end
    
    -- Check for additional services based on type
    if serviceType == "vendor" then
        -- Check if NPC can repair
        if CanMerchantRepair and CanMerchantRepair() then
            local hasRepair = false
            for _, service in ipairs(npcData.services) do
                if service == "repair" then
                    hasRepair = true
                    break
                end
            end
            if not hasRepair then
                table.insert(npcData.services, "repair")
            end
        end
    end
    
    -- Add location if we have coords and it's new
    if coords then
        local isNewLocation = true
        for _, loc in ipairs(npcData.locations) do
            if loc.zone == coords.zone and loc.areaId == coords.areaId then
                -- Check if coords are significantly different (more than 10 units)
                if loc.x and loc.y then
                    local distance = math.sqrt((coords.x - loc.x)^2 + (coords.y - loc.y)^2)
                    if distance < 10 then
                        isNewLocation = false
                        break
                    end
                end
            end
        end
        
        if isNewLocation then
            table.insert(npcData.locations, {
                x = coords.x,
                y = coords.y,
                zone = coords.zone,
                subZone = coords.subZone,
                areaId = coords.areaId,
                timestamp = time()
            })
        end
    end
    
    -- Check database for this service NPC
    local dbNpc = QuestieDB:GetNPC(npcId)
    if not dbNpc then
        DebugMessage("|cFF00FFFF[DATA]|r New service NPC discovered: " .. npcName .. " (ID: " .. npcId .. ") - " .. serviceType, 0, 1, 1)
    else
        -- Check if services match what's in database
        local servicesStr = table.concat(npcData.services, ", ")
        DebugMessage("|cFF00AAFF[DATA]|r Service NPC: " .. npcName .. " (ID: " .. npcId .. ") - Services: " .. servicesStr, 0, 0.67, 1)
    end
end

function QuestieDataCollector:CaptureMailbox()
    -- Mailboxes are objects, not NPCs, so we need to handle them differently
    -- We'll capture the location where the player opened mail
    local coords = QuestieDataCollector:GetPlayerCoordinates()
    if not coords then
        return
    end
    
    -- Create a unique key for this mailbox location
    local locKey = string.format("%s_%.0f_%.0f", coords.zone or "Unknown", coords.x or 0, coords.y or 0)
    
    -- Check if we already have this mailbox
    if not QuestieDataCollection.mailboxes[locKey] then
        QuestieDataCollection.mailboxes[locKey] = {
            x = coords.x,
            y = coords.y,
            zone = coords.zone,
            subZone = coords.subZone,
            areaId = coords.areaId,
            firstSeen = time(),
            lastSeen = time(),
            timesUsed = 1
        }
        
        DebugMessage("|cFF00FF00[DATA]|r New mailbox discovered at " .. string.format("%.1f, %.1f", coords.x, coords.y) .. " in " .. (coords.zone or "Unknown"), 0, 1, 0)
    else
        -- Update last seen and increment usage count
        QuestieDataCollection.mailboxes[locKey].lastSeen = time()
        QuestieDataCollection.mailboxes[locKey].timesUsed = (QuestieDataCollection.mailboxes[locKey].timesUsed or 1) + 1
    end
end

function QuestieDataCollector:CaptureGatheringNode(nodeType, nodeName)
    if not nodeName then
        -- Try to get from last interacted object
        if _lastInteractedObject and _lastInteractedObject.name then
            nodeName = _lastInteractedObject.name
        else
            return
        end
    end
    
    local coords = QuestieDataCollector:GetPlayerCoordinates()
    if not coords then
        return
    end
    
    -- Create a unique key for this gathering node location
    local locKey = string.format("%s_%s_%.0f_%.0f", coords.zone or "Unknown", nodeName, coords.x or 0, coords.y or 0)
    
    -- Check if we already have this node
    if not QuestieDataCollection.gatheringNodes[locKey] then
        QuestieDataCollection.gatheringNodes[locKey] = {
            name = nodeName,
            type = nodeType, -- "herb", "ore", "treasure", etc.
            x = coords.x,
            y = coords.y,
            zone = coords.zone,
            subZone = coords.subZone,
            areaId = coords.areaId,
            firstSeen = time(),
            lastSeen = time(),
            timesGathered = 1
        }
        
        DebugMessage("|cFF00FF00[DATA]|r New " .. nodeType .. " discovered: " .. nodeName .. " at " .. string.format("%.1f, %.1f", coords.x, coords.y) .. " in " .. (coords.zone or "Unknown"), 0, 1, 0)
    else
        -- Update last seen and increment usage count
        QuestieDataCollection.gatheringNodes[locKey].lastSeen = time()
        QuestieDataCollection.gatheringNodes[locKey].timesGathered = (QuestieDataCollection.gatheringNodes[locKey].timesGathered or 1) + 1
    end
end

function QuestieDataCollector:CaptureTreasureChest(chestName)
    if not chestName then
        -- Try to get from last interacted object
        if _lastInteractedObject and _lastInteractedObject.name then
            chestName = _lastInteractedObject.name
        else
            return
        end
    end
    
    local coords = QuestieDataCollector:GetPlayerCoordinates()
    if not coords then
        return
    end
    
    -- Create a unique key for this treasure chest location
    local locKey = string.format("%s_%s_%.0f_%.0f", coords.zone or "Unknown", chestName, coords.x or 0, coords.y or 0)
    
    -- Check if we already have this chest
    if not QuestieDataCollection.treasureChests[locKey] then
        QuestieDataCollection.treasureChests[locKey] = {
            name = chestName,
            x = coords.x,
            y = coords.y,
            zone = coords.zone,
            subZone = coords.subZone,
            areaId = coords.areaId,
            firstSeen = time(),
            lastSeen = time(),
            timesLooted = 1
        }
        
        DebugMessage("|cFF00FF00[DATA]|r New treasure chest discovered: " .. chestName .. " at " .. string.format("%.1f, %.1f", coords.x, coords.y) .. " in " .. (coords.zone or "Unknown"), 0, 1, 0)
    else
        -- Update last seen and increment usage count
        QuestieDataCollection.treasureChests[locKey].lastSeen = time()
        QuestieDataCollection.treasureChests[locKey].timesLooted = (QuestieDataCollection.treasureChests[locKey].timesLooted or 1) + 1
    end
end

function QuestieDataCollector:CheckActiveQuests()
    -- Check all quests in the log
    local numEntries = GetNumQuestLogEntries()
    local addedQuests = 0
    local skippedQuests = 0
    
    for i = 1, numEntries do
        local title, level, tag, isHeader, isCollapsed, isComplete, frequency, questId = GetQuestLogTitle(i)
        
        if not isHeader and questId and questId > 0 then
            -- Skip if quest is already in database
            if IsQuestInDatabase(questId) then
                skippedQuests = skippedQuests + 1
            else
                -- Initialize tracking for missing quests
                if not QuestieDataCollection.quests[questId] then
                    QuestieDataCollection.quests[questId] = {
                        id = questId,
                        name = title,
                        level = level,
                        wasAlreadyAccepted = true, -- Flag that we didn't see the accept event
                        objectives = {},
                        mobs = {},
                        items = {},
                        objects = {},
                        kills = {},
                        mismatches = {}
                    }
                    
                    -- Get current objectives
                    SelectQuestLogEntry(i)
                    local numObjectives = GetNumQuestLeaderBoards(i)
                    
                    for j = 1, numObjectives do
                        local text, objectiveType, finished = GetQuestLogLeaderBoard(j, i)
                        if text then
                            table.insert(QuestieDataCollection.quests[questId].objectives, {
                                index = j,
                                text = text,
                                type = objectiveType,
                                finished = finished,
                                progress = {}
                            })
                        end
                    end
                    
                    _activeTracking[questId] = true
                    addedQuests = addedQuests + 1
                    
                    DebugMessage("|cFFFFFF00[DATA]|r Added existing quest to tracking: " .. title .. " (ID: " .. questId .. ")", 1, 1, 0)
                end
            end
        end
    end
    
    if addedQuests > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[Data Collector]|r Added " .. addedQuests .. " missing quests from your log to tracking", 0, 1, 1)
    end
    if skippedQuests > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFAA00[Data Collector]|r Skipped " .. skippedQuests .. " quests already in database", 1, 0.7, 0)
    end
end

function QuestieDataCollector:EnableTooltipIDs()
    -- Store original settings to restore later
    if not _originalTooltipSettings then
        _originalTooltipSettings = {
            questId = Questie.db.profile.enableTooltipsQuestID,
            npcId = Questie.db.profile.enableTooltipsNPCID,
            objectId = Questie.db.profile.enableTooltipsObjectID,
            itemId = Questie.db.profile.enableTooltipsItemID
        }
    end
    
    -- Enable all IDs in tooltips for better data collection
    Questie.db.profile.enableTooltipsQuestID = true
    Questie.db.profile.enableTooltipsNPCID = true
    Questie.db.profile.enableTooltipsObjectID = true
    Questie.db.profile.enableTooltipsItemID = true
end

function QuestieDataCollector:RestoreTooltipSettings()
    if _originalTooltipSettings then
        Questie.db.profile.enableTooltipsQuestID = _originalTooltipSettings.questId
        Questie.db.profile.enableTooltipsNPCID = _originalTooltipSettings.npcId
        Questie.db.profile.enableTooltipsObjectID = _originalTooltipSettings.objectId
        Questie.db.profile.enableTooltipsItemID = _originalTooltipSettings.itemId
        
        _originalTooltipSettings = nil
    end
end

-- Export window for batch exporting all tracked quests
function QuestieDataCollector:ValidateQuest(questId)
    if not QuestieDataValidator then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r Validator not loaded!", 1, 0, 0)
        return
    end
    
    if not QuestieDataCollection or not QuestieDataCollection.quests then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r No data collected yet!", 1, 0, 0)
        return
    end
    
    local questData = QuestieDataCollection.quests[questId]
    if not questData then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r Quest " .. questId .. " not found in collected data", 1, 0, 0)
        return
    end
    
    -- Run validation
    local results = QuestieDataValidator:ValidateQuestSubmission(questData)
    
    -- Display results
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF=== Validation Results for Quest " .. questId .. " ===|r", 0, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("Status: " .. (results.valid and "|cFF00FF00VALID|r" or "|cFFFF0000INVALID|r"), 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("Completeness: " .. (results.complete and "|cFF00FF00COMPLETE|r" or "|cFFFFFF00INCOMPLETE|r"), 1, 1, 1)
    
    if results.recommendation then
        local action, reason = results.recommendation
        DEFAULT_CHAT_FRAME:AddMessage("Recommendation: |cFFFFFF00" .. action .. "|r", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("Reason: " .. reason, 1, 1, 1)
    end
    
    if #results.errors > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000Errors:|r", 1, 0.5, 0.5)
        for i, error in ipairs(results.errors) do
            if i <= 5 then  -- Show first 5 errors
                DEFAULT_CHAT_FRAME:AddMessage("  * " .. error, 1, 0.8, 0.8)
            end
        end
        if #results.errors > 5 then
            DEFAULT_CHAT_FRAME:AddMessage("  ... and " .. (#results.errors - 5) .. " more errors", 1, 0.8, 0.8)
        end
    end
    
    if #results.warnings > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Warnings:|r", 1, 1, 0.5)
        for i, warning in ipairs(results.warnings) do
            if i <= 5 then  -- Show first 5 warnings
                DEFAULT_CHAT_FRAME:AddMessage("  * " .. warning, 1, 1, 0.8)
            end
        end
        if #results.warnings > 5 then
            DEFAULT_CHAT_FRAME:AddMessage("  ... and " .. (#results.warnings - 5) .. " more warnings", 1, 1, 0.8)
        end
    end
end

function QuestieDataCollector:ValidateAllQuests()
    if not QuestieDataValidator then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r Validator not loaded!", 1, 0, 0)
        return
    end
    
    if not QuestieDataCollection or not QuestieDataCollection.quests then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r No data collected yet!", 1, 0, 0)
        return
    end
    
    local totalQuests = 0
    local validQuests = 0
    local completeQuests = 0
    local invalidQuests = {}
    local incompleteQuests = {}
    
    for questId, questData in pairs(QuestieDataCollection.quests) do
        totalQuests = totalQuests + 1
        local results = QuestieDataValidator:ValidateQuestSubmission(questData)
        
        if results.valid then
            validQuests = validQuests + 1
            -- Check if quest was turned in (completed)
            -- Check: turnedIn flag, turnInNpc (actual field name), or results.complete
            if questData.turnedIn or questData.turnInNpc or (questData.turnIn and #results.warnings <= 1) then
                completeQuests = completeQuests + 1
            elseif results.complete then
                completeQuests = completeQuests + 1
            else
                table.insert(incompleteQuests, {id = questId, name = questData.name, warnings = #results.warnings})
            end
        else
            table.insert(invalidQuests, {
                id = questId, 
                name = questData.name, 
                errors = #results.errors,
                firstError = results.errors[1] -- Capture first error for display
            })
        end
    end
    
    -- Display summary
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF=== Validation Summary ===|r", 0, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("Total Quests: " .. totalQuests, 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("Valid: |cFF00FF00" .. validQuests .. "|r (" .. string.format("%.1f%%", (validQuests/totalQuests)*100) .. ")", 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("Complete: |cFF00FF00" .. completeQuests .. "|r (" .. string.format("%.1f%%", (completeQuests/totalQuests)*100) .. ")", 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("Incomplete: |cFFFFFF00" .. #incompleteQuests .. "|r", 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("Invalid: |cFFFF0000" .. #invalidQuests .. "|r", 1, 1, 1)
    
    -- Show invalid quests with error details
    if #invalidQuests > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000Invalid Quests:|r", 1, 0.5, 0.5)
        for i, quest in ipairs(invalidQuests) do
            if i <= 5 then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  * %s (ID: %d) - %d errors", quest.name or "Unknown", quest.id, quest.errors), 1, 0.8, 0.8)
                -- Show first error for each invalid quest
                if quest.firstError then
                    DEFAULT_CHAT_FRAME:AddMessage("    → " .. quest.firstError, 1, 0.7, 0.7)
                end
            end
        end
        if #invalidQuests > 5 then
            DEFAULT_CHAT_FRAME:AddMessage("  ... and " .. (#invalidQuests - 5) .. " more", 1, 0.8, 0.8)
        end
    end
    
    -- Show incomplete quests
    if #incompleteQuests > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Incomplete Quests:|r", 1, 1, 0.5)
        for i, quest in ipairs(incompleteQuests) do
            if i <= 5 then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  * %s (ID: %d) - %d warnings", quest.name or "Unknown", quest.id, quest.warnings), 1, 1, 0.8)
            end
        end
        if #incompleteQuests > 5 then
            DEFAULT_CHAT_FRAME:AddMessage("  ... and " .. (#incompleteQuests - 5) .. " more", 1, 1, 0.8)
        end
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("Use |cFFFFFFFF/qdc validate <questId>|r to see details for a specific quest", 1, 1, 1)
end

function QuestieDataCollector:ShowExportWindow(questId)
    -- If no questId specified, show ALL data we have
    if not questId then
        -- Check if we have ANY data at all (quests, service NPCs, etc.)
        local hasData = false
        
        if QuestieDataCollection then
            if (QuestieDataCollection.quests and next(QuestieDataCollection.quests)) or
               (QuestieDataCollection.serviceNPCs and next(QuestieDataCollection.serviceNPCs)) or
               (QuestieDataCollection.mailboxes and next(QuestieDataCollection.mailboxes)) or
               (QuestieDataCollection.flightMasters and next(QuestieDataCollection.flightMasters)) then
                hasData = true
            end
        end
        
        if not hasData then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[QUESTIE]|r No data to export yet. Complete quests or interact with NPCs first!", 1, 0, 0)
            return
        end
    else
        -- Specific quest requested
        if not QuestieDataCollection or not QuestieDataCollection.quests then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[QUESTIE]|r No quest data available!", 1, 0, 0)
            return
        end
        
        local data = QuestieDataCollection.quests[questId]
        if not data then 
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[QUESTIE]|r No data for quest " .. questId .. "!", 1, 0, 0)
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
        
        -- Scroll frame for data
        local scrollFrame = CreateFrame("ScrollFrame", "QuestieDataCollectorScrollFrame", f, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 20, -45)
        scrollFrame:SetPoint("BOTTOMRIGHT", -40, 55)
        
        local editBox = CreateFrame("EditBox", "QuestieDataCollectorEditBox", scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetFontObject(ChatFontNormal)
        editBox:SetWidth(540)
        editBox:SetAutoFocus(false)
        editBox:EnableMouse(true)
        editBox:SetScript("OnEditFocusGained", function(self) 
            self:HighlightText()
        end)
        editBox:SetScript("OnEscapePressed", function() f:Hide() end)
        editBox:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                self:SetText(self.originalText or "")
                self:HighlightText()
            end
        end)
        
        editBox:SetHeight(2000)
        
        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            local current = self:GetVerticalScroll()
            local maxScroll = self:GetVerticalScrollRange()
            local scrollStep = 30
            
            if delta > 0 then
                self:SetVerticalScroll(math.max(0, current - scrollStep))
            else
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
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00Data selected! Press Ctrl+C to copy, then paste in GitHub issue.|r", 0, 1, 0)
        end)
        
        -- Step 3: Close & Purge button
        local purgeButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        purgeButton:SetPoint("BOTTOMRIGHT", -20, 20)
        purgeButton:SetWidth(160)
        purgeButton:SetHeight(25)
        purgeButton:SetText("|cFF00FF00Step 3:|r Close & Purge Data")
        purgeButton:SetScript("OnClick", function()
            -- Use the same ClearData function as /qdc clear
            QuestieDataCollector:ClearData()
            
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[QUESTIE]|r Thank you for contributing! All collected data has been purged.", 0, 1, 0)
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Use /reload to ensure all memory is freed.|r", 1, 1, 0)
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
        exportText = self:FormatQuestExport(questId, data)
    else
        -- Export ALL collected data (Batch submission with smart splitting detection)
        
        -- Count eligible quests (missing from database)
        local eligibleQuests = 0
        for questId, questData in pairs(QuestieDataCollection.quests) do
            if not IsQuestInDatabase(questId) then
                eligibleQuests = eligibleQuests + 1
            end
        end
        
        -- GitHub issue body character limits
        local GITHUB_MAX_CHARS = 65536
        local GITHUB_SAFE_CHARS = math.floor(GITHUB_MAX_CHARS * 0.9)  -- 90% safety buffer = ~59,000 chars
        
        -- Pre-calculate content to determine if we need slicing
        local testExport = ""
        local questCount = 0
        
        -- Build header for character counting
        local headerText = "════════════════════════════════════════════════════════════════\n"
        headerText = headerText .. "                  HOW TO SUBMIT YOUR REPORT                     \n" 
        headerText = headerText .. "════════════════════════════════════════════════════════════════\n\n"
        headerText = headerText .. "1. Copy all text below (Ctrl+C to copy)\n"
        headerText = headerText .. "2. Go to: https://github.com/trav346/Questie/issues\n"
        headerText = headerText .. "3. Click 'New Issue'\n"
        headerText = headerText .. "4. Title: Missing Quest Data: [Brief Description]\n"
        headerText = headerText .. "5. Paste the copied text and click 'Submit new issue'\n\n"
        headerText = headerText .. "═══════════════════════════════════════════════════════════════\n"
        headerText = headerText .. "                     COLLECTED QUEST DATA                        \n"
        headerText = headerText .. "═══════════════════════════════════════════════════════════════\n\n"
        
        -- Calculate total content size
        local totalChars = string.len(headerText)
        
        for questId, questData in pairs(QuestieDataCollection.quests) do
            if not IsQuestInDatabase(questId) then
                questCount = questCount + 1
                local questExport = self:FormatQuestExport(questId, questData)
                totalChars = totalChars + string.len(questExport)
                if questCount > 1 then
                    totalChars = totalChars + string.len("\n========================================================================\n\n")
                end
            end
        end
        
        if totalChars > GITHUB_SAFE_CHARS then
            -- Content too large - use character-based slicing
            self:ShowStagedExportWindow(questCount, nil, totalChars, GITHUB_SAFE_CHARS)
            return
        else
            -- Normal single submission
            exportText = "════════════════════════════════════════════════════════════════\n"
            exportText = exportText .. "                  HOW TO SUBMIT YOUR REPORT                     \n"
            exportText = exportText .. "════════════════════════════════════════════════════════════════\n\n"
        end
        
        exportText = exportText .. "1. Copy all text below (Ctrl+C to copy)\n"
        exportText = exportText .. "2. Go to: https://github.com/trav346/Questie/issues\n"
        exportText = exportText .. "3. Click 'New Issue'\n"
        if eligibleQuests > maxQuestsPerSubmission then
            exportText = exportText .. "4. Title: Large Batch Submission (" .. eligibleQuests .. " quests - MAY BE TOO BIG)\n"
        else
            exportText = exportText .. "4. Title: Batch Submission (" .. eligibleQuests .. " quests)\n"
        end
        exportText = exportText .. "5. Paste this entire report in the description\n"
        exportText = exportText .. "6. Click 'Submit new issue'\n\n"
        exportText = exportText .. "════════════════════════════════════════════════════════════════\n"
        exportText = exportText .. "              QUESTIE DATA COLLECTION EXPORT                    \n"
        exportText = exportText .. "════════════════════════════════════════════════════════════════\n\n"
        exportText = exportText .. "Version: " .. (QuestieDataCollection.version or CURRENT_VERSION) .. "\n"
        exportText = exportText .. "Date: " .. date("%Y-%m-%d %H:%M:%S") .. "\n"
        
        -- Player character information
        local playerClass = UnitClass("player")
        local playerRace = UnitRace("player") 
        local playerFaction = UnitFactionGroup("player")
        local playerLevel = UnitLevel("player")
        if playerClass and playerRace then
            exportText = exportText .. "Player: " .. playerRace .. " " .. playerClass
            if playerFaction then
                exportText = exportText .. " (" .. playerFaction .. ")"
            end
            if playerLevel then
                exportText = exportText .. " Level " .. playerLevel
            end
            exportText = exportText .. "\n"
        end
        
        -- Clearly explain the capture mode
        if _captureAllData then
            exportText = exportText .. "Collection Mode: DEV MODE - Capturing ALL data\n"
            exportText = exportText .. "  * ALL quests tracked (even if in database)\n"
            exportText = exportText .. "  * ALL service NPCs captured\n"
            exportText = exportText .. "  * ALL interactions logged\n"
        else
            exportText = exportText .. "Collection Mode: NORMAL - Missing quests only\n"
            exportText = exportText .. "  * Only missing quests tracked\n"
            exportText = exportText .. "  * Service NPCs always captured\n"
            exportText = exportText .. "  * Mailboxes & flight masters always logged\n"
        end
        
        -- Count all data types
        local questCount = 0
        local serviceNPCCount = 0
        local mailboxCount = 0
        local flightMasterCount = 0
        
        if QuestieDataCollection.quests then
            for _ in pairs(QuestieDataCollection.quests) do
                questCount = questCount + 1
            end
        end
        
        if QuestieDataCollection.serviceNPCs then
            for _ in pairs(QuestieDataCollection.serviceNPCs) do
                serviceNPCCount = serviceNPCCount + 1
            end
        end
        
        if QuestieDataCollection.mailboxes then
            for _ in pairs(QuestieDataCollection.mailboxes) do
                mailboxCount = mailboxCount + 1
            end
        end
        
        if QuestieDataCollection.flightMasters then
            for _ in pairs(QuestieDataCollection.flightMasters) do
                flightMasterCount = flightMasterCount + 1
            end
        end
        
        -- Count database mismatches
        local mismatchCount = 0
        for _ in pairs(_dataMismatches) do
            mismatchCount = mismatchCount + 1
        end
        
        exportText = exportText .. "Total Quests: " .. questCount .. "\n"
        exportText = exportText .. "Service NPCs: " .. serviceNPCCount .. "\n"
        exportText = exportText .. "Mailboxes: " .. mailboxCount .. "\n"
        exportText = exportText .. "Flight Masters: " .. flightMasterCount .. "\n"
        if mismatchCount > 0 then
            exportText = exportText .. "DATABASE MISMATCHES: " .. mismatchCount .. " ⚠️\n"
        end
        exportText = exportText .. "=====================================\n\n"
        
        -- DATABASE MISMATCHES SECTION (CRITICAL - ALWAYS SHOW FIRST IF ANY EXIST)
        if mismatchCount > 0 then
            exportText = exportText .. "========================================================================\n"
            exportText = exportText .. "                    ⚠️ DATABASE MISMATCHES DETECTED ⚠️\n"
            exportText = exportText .. "========================================================================\n\n"
            exportText = exportText .. "CRITICAL: The following data conflicts with the current database.\n"
            exportText = exportText .. "This likely means the database needs updating!\n\n"
            
            -- Group mismatches by type
            local questMismatches = {}
            local npcMismatches = {}
            
            for key, mismatch in pairs(_dataMismatches) do
                if mismatch.entityType == "quest" then
                    if not questMismatches[mismatch.entityId] then
                        questMismatches[mismatch.entityId] = {}
                    end
                    table.insert(questMismatches[mismatch.entityId], mismatch)
                elseif mismatch.entityType == "npc" then
                    if not npcMismatches[mismatch.entityId] then
                        npcMismatches[mismatch.entityId] = {}
                    end
                    table.insert(npcMismatches[mismatch.entityId], mismatch)
                end
            end
            
            -- Export quest mismatches
            local hasQuestMismatches = false
            for questId, mismatches in pairs(questMismatches) do
                if not hasQuestMismatches then
                    exportText = exportText .. "QUEST MISMATCHES:\n"
                    exportText = exportText .. "----------------\n\n"
                    hasQuestMismatches = true
                end
                
                -- Get quest name if available
                local questName = "Unknown"
                if QuestieDataCollection.quests[questId] then
                    questName = QuestieDataCollection.quests[questId].name or "Unknown"
                end
                
                exportText = exportText .. "Quest " .. questId .. ": " .. questName .. "\n"
                for _, mismatch in ipairs(mismatches) do
                    exportText = exportText .. "  • " .. mismatch.fieldName .. ":\n"
                    exportText = exportText .. "    Database: " .. tostring(mismatch.databaseValue) .. "\n"
                    exportText = exportText .. "    Collected: " .. tostring(mismatch.collectedValue) .. "\n"
                end
                exportText = exportText .. "\n"
            end
            
            -- Export NPC mismatches
            local hasNpcMismatches = false
            for npcId, mismatches in pairs(npcMismatches) do
                if not hasNpcMismatches then
                    if hasQuestMismatches then
                        exportText = exportText .. "\n"
                    end
                    exportText = exportText .. "NPC MISMATCHES:\n"
                    exportText = exportText .. "---------------\n\n"
                    hasNpcMismatches = true
                end
                
                -- Get NPC name from our data
                local npcName = "Unknown"
                for questId, questData in pairs(QuestieDataCollection.quests) do
                    if questData.questGiver and questData.questGiver.id == npcId then
                        npcName = questData.questGiver.name or "Unknown"
                        break
                    elseif questData.turnInNpc and questData.turnInNpc.id == npcId then
                        npcName = questData.turnInNpc.name or "Unknown"
                        break
                    end
                end
                
                exportText = exportText .. "NPC " .. npcId .. ": " .. npcName .. "\n"
                for _, mismatch in ipairs(mismatches) do
                    if mismatch.fieldName == "zone" then
                        exportText = exportText .. "  • Zone mismatch:\n"
                        exportText = exportText .. "    Database zone: " .. tostring(mismatch.databaseValue) .. "\n"
                        exportText = exportText .. "    Found in zone: " .. tostring(mismatch.collectedValue) .. "\n"
                    elseif mismatch.fieldName == "coords" then
                        exportText = exportText .. "  • Location mismatch:\n"
                        if mismatch.collectedValue and mismatch.collectedValue.x then
                            exportText = exportText .. "    Found at: " .. string.format("%.1f, %.1f", mismatch.collectedValue.x, mismatch.collectedValue.y) .. "\n"
                        end
                        if mismatch.databaseValue and mismatch.databaseValue.distance then
                            exportText = exportText .. "    Distance from DB: " .. string.format("%.1f units", mismatch.databaseValue.distance) .. "\n"
                        end
                    elseif mismatch.fieldName == "name" then
                        exportText = exportText .. "  • Name mismatch:\n"
                        exportText = exportText .. "    Database: " .. tostring(mismatch.databaseValue) .. "\n"
                        exportText = exportText .. "    Collected: " .. tostring(mismatch.collectedValue) .. "\n"
                    else
                        exportText = exportText .. "  • " .. mismatch.fieldName .. ":\n"
                        exportText = exportText .. "    Database: " .. tostring(mismatch.databaseValue) .. "\n"
                        exportText = exportText .. "    Collected: " .. tostring(mismatch.collectedValue) .. "\n"
                    end
                end
                exportText = exportText .. "\n"
            end
            
            exportText = exportText .. "========================================================================\n\n"
        end
        
        -- Export Quests FIRST (if any)
        if questCount > 0 then
            exportText = exportText .. "========================================================================\n"
            exportText = exportText .. "                              QUEST DATA\n"
            exportText = exportText .. "========================================================================\n\n"
            
            local questIndex = 0
            for qId, qData in pairs(QuestieDataCollection.quests) do
                questIndex = questIndex + 1
                exportText = exportText .. self:FormatQuestExport(qId, qData)
                -- Add separator between quests (but not after the last one)
                if questIndex < questCount then
                    exportText = exportText .. "\n========================================================================\n\n"
                else
                    exportText = exportText .. "\n"
                end
            end
        end
        
        -- Export Mailboxes (if any)
        if mailboxCount > 0 then
            exportText = exportText .. "\n========================================================================\n"
            exportText = exportText .. "                          MAILBOX LOCATIONS\n"
            exportText = exportText .. "========================================================================\n\n"
            
            for locKey, locData in pairs(QuestieDataCollection.mailboxes) do
                exportText = exportText .. "Location: " .. (locData.zone or "Unknown Zone") .. "\n"
                exportText = exportText .. "Coords: " .. QuestieDataCollector:SafeFormatCoords(locData) .. "\n\n"
            end
        end
        
        -- Export Flight Masters (if any)
        if flightMasterCount > 0 then
            exportText = exportText .. "\n========================================================================\n"
            exportText = exportText .. "                           FLIGHT MASTERS\n"
            exportText = exportText .. "========================================================================\n\n"
            
            for npcId, fmData in pairs(QuestieDataCollection.flightMasters) do
                exportText = exportText .. "Flight Master: " .. (fmData.name or "Unknown") .. " (ID: " .. npcId .. ")\n"
                
                -- Include detected services and calculated flag value
                if QuestieDataCollection.npcs and QuestieDataCollection.npcs[npcId] and QuestieDataCollection.npcs[npcId].detectedServices then
                    local services = {}
                    local flagValue = 0
                    for service, _ in pairs(QuestieDataCollection.npcs[npcId].detectedServices) do
                        table.insert(services, service)
                        -- Calculate flag value based on detected services
                        if service == "FLIGHT_MASTER" then flagValue = flagValue + 8192 end
                        if service == "QUEST_GIVER" then flagValue = flagValue + 2 end
                        if service == "VENDOR" then flagValue = flagValue + 128 end
                        if service == "TRAINER" then flagValue = flagValue + 16 end
                        if service == "INNKEEPER" then flagValue = flagValue + 65536 end
                        if service == "BANKER" then flagValue = flagValue + 131072 end
                        if service == "REPAIR" then flagValue = flagValue + 4096 end
                        if service == "AUCTIONEER" then flagValue = flagValue + 2097152 end
                        if service == "STABLEMASTER" then flagValue = flagValue + 4194304 end
                        if service == "BATTLEMASTER" then flagValue = flagValue + 1048576 end
                    end
                    if #services > 0 then
                        exportText = exportText .. "Detected Services: " .. table.concat(services, ", ") .. "\n"
                        exportText = exportText .. "NPC Flags: " .. flagValue .. " (WotLK value)\n"
                    end
                else
                    -- Flight master without detected services - default to FLIGHT_MASTER flag
                    exportText = exportText .. "NPC Flags: 8192 (FLIGHT_MASTER - default)\n"
                end
                
                if fmData.locations and #fmData.locations > 0 then
                    for _, loc in ipairs(fmData.locations) do
                        if loc.x and loc.y then
                            exportText = exportText .. "Location: " .. (loc.zone or "Unknown Zone") .. " at " .. string.format("%.1f, %.1f", loc.x, loc.y) .. "\n"
                        end
                    end
                end
                exportText = exportText .. "\n"
            end
        end
        
        -- Export Service NPCs LAST (if any)
        if serviceNPCCount > 0 then
            exportText = exportText .. "\n========================================================================\n"
            exportText = exportText .. "                       SERVICE NPCs ENCOUNTERED\n"
            exportText = exportText .. "========================================================================\n\n"
            
            for npcId, npcData in pairs(QuestieDataCollection.serviceNPCs) do
                exportText = exportText .. "NPC: " .. (npcData.name or "Unknown") .. " (ID: " .. npcId .. ")\n"
                local services = npcData.services or {"Unknown"}
                exportText = exportText .. "Services: " .. table.concat(services, ", ") .. "\n"
                
                if npcData.locations and #npcData.locations > 0 then
                    exportText = exportText .. "Locations:\n"
                    for _, loc in ipairs(npcData.locations) do
                        if loc.x and loc.y then
                            exportText = exportText .. "  * " .. (loc.zone or "Unknown Zone") .. " at " .. string.format("%.1f, %.1f", loc.x, loc.y) .. "\n"
                        end
                    end
                end
                exportText = exportText .. "\n"
            end
        end
        
        -- If no data at all
        if questCount == 0 and serviceNPCCount == 0 and mailboxCount == 0 and flightMasterCount == 0 then
            exportText = exportText .. "No data collected yet.\n\n"
            exportText = exportText .. "In DEV MODE, ALL interactions are tracked:\n"
            exportText = exportText .. "* Accept any quest\n"
            exportText = exportText .. "* Talk to any NPC with services (flight master, vendor, etc.)\n"
            exportText = exportText .. "* Click on mailboxes\n"
            exportText = exportText .. "* Complete quest objectives\n"
        end
    end
    
    -- Show the frame
    local f = QuestieDataCollectorExportFrame
    f.editBox.originalText = exportText
    f.editBox:SetText(exportText)
    f:Show()
    
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[QUESTIE]|r Export window opened. Follow the 3 steps to submit your data!", 0, 1, 0)
end

-- Calculate how to slice quest data based on character limits
function QuestieDataCollector:CalculateCharacterSlices(totalChars, maxChars)
    local headerText = "════════════════════════════════════════════════════════════════\n"
    headerText = headerText .. "                  HOW TO SUBMIT YOUR REPORT                     \n" 
    headerText = headerText .. "════════════════════════════════════════════════════════════════\n\n"
    headerText = headerText .. "1. Copy all text below (Ctrl+C to copy)\n"
    headerText = headerText .. "2. Go to: https://github.com/trav346/Questie/issues\n"
    headerText = headerText .. "3. Click 'New Issue'\n"
    headerText = headerText .. "4. Title: Missing Quest Data - Part X of Y\n"
    headerText = headerText .. "5. Paste the copied text and click 'Submit new issue'\n\n"
    headerText = headerText .. "═══════════════════════════════════════════════════════════════\n"
    headerText = headerText .. "                     COLLECTED QUEST DATA                        \n"
    headerText = headerText .. "═══════════════════════════════════════════════════════════════\n\n"
    
    local headerSize = string.len(headerText)
    local availableChars = maxChars - headerSize - 100  -- Leave 100 chars buffer
    
    -- Get all eligible quests
    local allQuests = {}
    for questId, questData in pairs(QuestieDataCollection.quests) do
        if not IsQuestInDatabase(questId) then
            local questExport = self:FormatQuestExport(questId, questData)
            table.insert(allQuests, {
                id = questId,
                data = questData,
                export = questExport,
                size = string.len(questExport)
            })
        end
    end
    
    -- Sort by quest ID for consistent ordering
    table.sort(allQuests, function(a, b) return a.id < b.id end)
    
    -- Slice into pages based on character limits
    local slices = {}
    local currentSlice = {}
    local currentSize = 0
    local separatorSize = string.len("\n========================================================================\n\n")
    
    for i, quest in ipairs(allQuests) do
        local questSize = quest.size
        local withSeparator = (currentSize > 0) and (questSize + separatorSize) or questSize
        
        if currentSize + withSeparator > availableChars and #currentSlice > 0 then
            -- This quest would exceed limit, start a new slice
            table.insert(slices, {
                quests = currentSlice,
                totalSize = currentSize + headerSize,
                questCount = #currentSlice
            })
            currentSlice = { quest }
            currentSize = questSize
        else
            -- Quest fits in current slice
            table.insert(currentSlice, quest)
            currentSize = currentSize + withSeparator
        end
    end
    
    -- Add the final slice if it has content
    if #currentSlice > 0 then
        table.insert(slices, {
            quests = currentSlice,
            totalSize = currentSize + headerSize,
            questCount = #currentSlice
        })
    end
    
    return {
        slices = slices,
        totalQuests = #allQuests,
        headerText = headerText,
        maxChars = maxChars
    }
end

-- Format a single quest for export
function QuestieDataCollector:ShowStagedExportWindow(totalQuests, maxPerPage, totalChars, maxChars)
    -- Determine slicing method: character-based (new) vs quest-based (legacy)
    local useCharacterSlicing = (totalChars and maxChars)
    local totalPages, sliceInfo
    
    if useCharacterSlicing then
        -- Calculate pages based on character limits
        sliceInfo = self:CalculateCharacterSlices(totalChars, maxChars)
        totalPages = #sliceInfo.slices
    else
        -- Legacy quest-based slicing
        maxPerPage = maxPerPage or 20
        totalPages = math.ceil(totalQuests / maxPerPage)
    end
    
    -- Create staged export frame if it doesn't exist
    if not QuestieStagedExportFrame then
        local f = CreateFrame("Frame", "QuestieStagedExportFrame", UIParent)
        f:SetFrameStrata("DIALOG")
        f:SetWidth(700)
        f:SetHeight(500)
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
        title:SetText("|cFFFFAA00Questie Export|r")
        f.title = title
        
        -- Friendly message
        local notice = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        notice:SetPoint("TOP", 0, -45)
        notice:SetText("|cFF66FF66Large submission detected! GitHub limits issues to ~65k characters, so we've sliced this automatically.|r")
        f.notice = notice
        
        -- Current page indicator
        local pageInfo = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        pageInfo:SetPoint("TOP", 0, -70)
        f.pageInfo = pageInfo
        
        -- Scroll frame for quest data
        local scrollFrame = CreateFrame("ScrollFrame", "QuestieStagedScrollFrame", f, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 20, -95)
        scrollFrame:SetPoint("BOTTOMRIGHT", -40, 100)
        
        local editBox = CreateFrame("EditBox", "QuestieStagedEditBox", scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetFontObject(ChatFontNormal)
        editBox:SetWidth(640)
        editBox:SetAutoFocus(false)
        editBox:EnableMouse(true)
        editBox:SetScript("OnEditFocusGained", function(self) 
            self:HighlightText()
        end)
        editBox:SetScript("OnEscapePressed", function() f:Hide() end)
        editBox:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                self:SetText(self.originalText or "")
                self:HighlightText()
            end
        end)
        editBox:SetHeight(2000)
        
        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            local current = self:GetVerticalScroll()
            local maxScroll = self:GetVerticalScrollRange()
            local scrollStep = 30
            
            if delta > 0 then
                self:SetVerticalScroll(math.max(0, current - scrollStep))
            else
                self:SetVerticalScroll(math.min(maxScroll, current + scrollStep))
            end
        end)
        
        scrollFrame:SetScrollChild(editBox)
        f.editBox = editBox
        f.scrollFrame = scrollFrame
        
        -- Navigation buttons row
        local navFrame = CreateFrame("Frame", nil, f)
        navFrame:SetPoint("BOTTOMLEFT", 20, 50)
        navFrame:SetPoint("BOTTOMRIGHT", -20, 50)
        navFrame:SetHeight(30)
        f.navFrame = navFrame
        
        -- Previous page button
        local prevButton = CreateFrame("Button", nil, navFrame, "UIPanelButtonTemplate")
        prevButton:SetPoint("LEFT", 0, 0)
        prevButton:SetWidth(80)
        prevButton:SetHeight(25)
        prevButton:SetText("Previous")
        f.prevButton = prevButton
        
        -- Page indicator in nav bar
        local navPageInfo = navFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        navPageInfo:SetPoint("CENTER", 0, 0)
        f.navPageInfo = navPageInfo
        
        -- Next page button
        local nextButton = CreateFrame("Button", nil, navFrame, "UIPanelButtonTemplate")
        nextButton:SetPoint("RIGHT", 0, 0)
        nextButton:SetWidth(80)
        nextButton:SetHeight(25)
        nextButton:SetText("Next")
        f.nextButton = nextButton
        
        -- Action buttons row
        local actionFrame = CreateFrame("Frame", nil, f)
        actionFrame:SetPoint("BOTTOMLEFT", 20, 15)
        actionFrame:SetPoint("BOTTOMRIGHT", -20, 15)
        actionFrame:SetHeight(30)
        f.actionFrame = actionFrame
        
        -- Select All button
        local selectAllButton = CreateFrame("Button", nil, actionFrame, "UIPanelButtonTemplate")
        selectAllButton:SetPoint("LEFT", 0, 0)
        selectAllButton:SetWidth(100)
        selectAllButton:SetHeight(25)
        selectAllButton:SetText("Select All")
        selectAllButton:SetScript("OnClick", function()
            editBox:SetFocus()
            editBox:HighlightText()
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00Page data selected! Press Ctrl+C to copy.|r", 0, 1, 0)
        end)
        
        -- Go to GitHub button
        local githubButton = CreateFrame("Button", nil, actionFrame, "UIPanelButtonTemplate")
        githubButton:SetPoint("LEFT", selectAllButton, "RIGHT", 10, 0)
        githubButton:SetWidth(120)
        githubButton:SetHeight(25)
        githubButton:SetText("Go to GitHub")
        githubButton:SetScript("OnClick", function()
            -- Use same GitHub popup as main export window
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
                
                local titleText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                titleText:SetPoint("TOP", 0, -15)
                titleText:SetText("|cFFFFFFFFCopy this URL to your browser:|r")
                
                local urlBox = CreateFrame("EditBox", nil, popup)
                urlBox:SetPoint("CENTER", 0, 5)
                urlBox:SetWidth(400)
                urlBox:SetHeight(20)
                urlBox:SetFontObject(GameFontHighlight)
                urlBox:SetText("https://github.com/trav346/Questie/issues")
                urlBox:SetAutoFocus(false)
                urlBox:SetScript("OnEditFocusGained", function(self)
                    self:HighlightText()
                end)
                urlBox:SetScript("OnEscapePressed", function(self)
                    self:ClearFocus()
                    popup:Hide()
                end)
                urlBox:SetScript("OnTextChanged", function(self, userInput)
                    if userInput then
                        self:SetText("https://github.com/trav346/Questie/issues")
                        self:HighlightText()
                    end
                end)
                
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
                
                local closeBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
                closeBtn:SetPoint("BOTTOM", 0, 10)
                closeBtn:SetWidth(80)
                closeBtn:SetHeight(22)
                closeBtn:SetText("Close")
                closeBtn:SetScript("OnClick", function() popup:Hide() end)
                
                popup.urlBox = urlBox
            end
            GitHubURLFrame:Show()
            GitHubURLFrame.urlBox:SetFocus()
            GitHubURLFrame.urlBox:HighlightText()
        end)
        
        -- Close & Purge button (only on final page)
        local purgeButton = CreateFrame("Button", nil, actionFrame, "UIPanelButtonTemplate")
        purgeButton:SetPoint("RIGHT", 0, 0)
        purgeButton:SetWidth(140)
        purgeButton:SetHeight(25)
        purgeButton:SetText("Close & Purge Data")
        purgeButton:SetScript("OnClick", function()
            QuestieDataCollector:ClearData()
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[QUESTIE]|r Thank you for contributing! All data has been purged.", 0, 1, 0)
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Use /reload to ensure all memory is freed.|r", 1, 1, 0)
            f:Hide()
        end)
        f.purgeButton = purgeButton
        
        -- Close button (X)
        local closeButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeButton:SetPoint("TOPRIGHT", -5, -5)
        closeButton:SetScript("OnClick", function() f:Hide() end)
        
        f:Hide()
        
        -- Store pagination state
        f.currentPage = 1
        f.totalPages = totalPages
        f.maxPerPage = maxPerPage
        f.totalQuests = totalQuests
        f.useCharacterSlicing = useCharacterSlicing
        f.sliceInfo = sliceInfo
    end
    
    local frame = QuestieStagedExportFrame
    frame.currentPage = 1
    frame.totalPages = totalPages
    frame.maxPerPage = maxPerPage
    frame.totalQuests = totalQuests
    frame.useCharacterSlicing = useCharacterSlicing
    frame.sliceInfo = sliceInfo
    
    -- Set up navigation button handlers
    frame.prevButton:SetScript("OnClick", function()
        if frame.currentPage > 1 then
            frame.currentPage = frame.currentPage - 1
            QuestieDataCollector:UpdateStagedExportPage()
        end
    end)
    
    frame.nextButton:SetScript("OnClick", function()
        if frame.currentPage < frame.totalPages then
            frame.currentPage = frame.currentPage + 1
            QuestieDataCollector:UpdateStagedExportPage()
        end
    end)
    
    -- Load first page and show
    self:UpdateStagedExportPage()
    frame:Show()
end

function QuestieDataCollector:UpdateStagedExportPage()
    local frame = QuestieStagedExportFrame
    if not frame then return end
    
    local currentPage = frame.currentPage
    local maxPerPage = frame.maxPerPage
    local totalPages = frame.totalPages
    local startIndex = (currentPage - 1) * maxPerPage + 1
    local endIndex = math.min(currentPage * maxPerPage, frame.totalQuests)
    
    -- Update page indicators with character counting info
    if frame.useCharacterSlicing and frame.sliceInfo then
        local slice = frame.sliceInfo.slices[currentPage]
        if slice then
            local charInfo = string.format("%.1fk/%.1fk chars", slice.totalSize / 1000, frame.sliceInfo.maxChars / 1000)
            frame.pageInfo:SetText("|cFFAAFFAAPage " .. currentPage .. " of " .. totalPages .. " |cFFFFFFFF(" .. slice.questCount .. " quests, " .. charInfo .. ")|r")
            frame.navPageInfo:SetText("Page " .. currentPage .. " of " .. totalPages .. " (" .. charInfo .. ")")
        else
            frame.pageInfo:SetText("|cFFAAFFAAPage " .. currentPage .. " of " .. totalPages .. "|r")
            frame.navPageInfo:SetText("Page " .. currentPage .. " of " .. totalPages)
        end
    else
        -- Legacy quest-based display
        frame.pageInfo:SetText("|cFFAAFFAAPage " .. currentPage .. " of " .. totalPages .. " |cFFFFFFFF(" .. (endIndex - startIndex + 1) .. " quests)|r")
        frame.navPageInfo:SetText("Page " .. currentPage .. " of " .. totalPages)
    end
    
    -- Update navigation buttons (WoW 3.3.5 compatible)
    if currentPage > 1 then
        frame.prevButton:Enable()
    else
        frame.prevButton:Disable()
    end
    
    if currentPage < totalPages then
        frame.nextButton:Enable()
    else
        frame.nextButton:Disable()
    end
    
    -- Only show purge button on final page
    if currentPage == totalPages then
        frame.purgeButton:Show()
    else
        frame.purgeButton:Hide()
    end
    
    -- Generate export data for current page
    local exportText = self:GenerateStagedPageContent(currentPage, maxPerPage)
    
    frame.editBox.originalText = exportText
    frame.editBox:SetText(exportText)
    frame.editBox:SetCursorPosition(0)
    frame.scrollFrame:SetVerticalScroll(0)
end

function QuestieDataCollector:GenerateStagedPageContent(pageNum, maxPerPage)
    local frame = QuestieStagedExportFrame
    
    -- Check if using character-based slicing
    if frame.useCharacterSlicing and frame.sliceInfo then
        -- Use character-based slicing (new method)
        local slice = frame.sliceInfo.slices[pageNum]
        if not slice then
            return "Error: No data for page " .. pageNum
        end
        
        -- Use the pre-calculated header from sliceInfo
        local exportText = frame.sliceInfo.headerText:gsub("Part X of Y", "Part " .. pageNum .. " of " .. frame.totalPages)
        
        -- Add character count info to title
        local charInfo = string.format(" (%.1fk chars)", slice.totalSize / 1000)
        exportText = exportText .. "Page " .. pageNum .. " of " .. frame.totalPages .. charInfo .. "\n\n"
        
        -- Add all quests in this slice
        for i, quest in ipairs(slice.quests) do
            exportText = exportText .. quest.export
            if i < #slice.quests then
                exportText = exportText .. "\n========================================================================\n\n"
            end
        end
        
        return exportText
    else
        -- Legacy quest-based slicing
        local startIndex = (pageNum - 1) * maxPerPage
        local endIndex = startIndex + maxPerPage - 1
        
        -- Header
        local exportText = "════════════════════════════════════════════════════════════════\n"
        exportText = exportText .. "                    QUESTIE STAGED EXPORT                       \n" 
        exportText = exportText .. "                      Page " .. pageNum .. " of " .. QuestieStagedExportFrame.totalPages .. "                           \n"
        exportText = exportText .. "════════════════════════════════════════════════════════════════\n\n"
    end
    
    exportText = exportText .. "HOW TO SUBMIT THIS PAGE:\n"
    exportText = exportText .. "1. Select All Data (button below)\n"
    exportText = exportText .. "2. Copy with Ctrl+C\n"
    exportText = exportText .. "3. Go to GitHub (button below)\n"
    exportText = exportText .. "4. Create New Issue\n"
    exportText = exportText .. "5. Title: 'Batch Submission - Page " .. pageNum .. " of " .. QuestieStagedExportFrame.totalPages .. "'\n"
    exportText = exportText .. "6. Paste this data and submit\n"
    exportText = exportText .. "7. Use Next button for remaining pages\n\n"
    
    -- Export metadata
    exportText = exportText .. "Version: " .. (QuestieDataCollection.version or CURRENT_VERSION) .. "\n"
    exportText = exportText .. "Date: " .. date("%Y-%m-%d %H:%M:%S") .. "\n"
    
    local playerClass = UnitClass("player")
    local playerRace = UnitRace("player") 
    local playerFaction = UnitFactionGroup("player")
    local playerLevel = UnitLevel("player")
    if playerClass and playerRace then
        exportText = exportText .. "Player: " .. playerRace .. " " .. playerClass
        if playerFaction then
            exportText = exportText .. " (" .. playerFaction .. ")"
        end
        if playerLevel then
            exportText = exportText .. " Level " .. playerLevel
        end
        exportText = exportText .. "\n"
    end
    exportText = exportText .. "\n"
    
    -- Get eligible quests for this page
    local eligibleQuests = {}
    for questId, questData in pairs(QuestieDataCollection.quests) do
        if not IsQuestInDatabase(questId) then
            table.insert(eligibleQuests, {id = questId, data = questData})
        end
    end
    
    -- Sort by quest ID for consistent pagination
    table.sort(eligibleQuests, function(a, b) return a.id < b.id end)
    
    -- Export quests for this page
    local questsOnPage = 0
    for i = startIndex + 1, math.min(endIndex + 1, #eligibleQuests) do
        local quest = eligibleQuests[i]
        if quest then
            questsOnPage = questsOnPage + 1
            exportText = exportText .. self:FormatQuestExport(quest.id, quest.data)
            
            if questsOnPage < maxPerPage and i < #eligibleQuests then
                exportText = exportText .. "\n════════════════════════════════════════════════════════════════\n\n"
            else
                exportText = exportText .. "\n"
            end
        end
    end
    
    -- Page footer
    exportText = exportText .. "════════════════════════════════════════════════════════════════\n"
    exportText = exportText .. "                    END OF PAGE " .. pageNum .. " of " .. QuestieStagedExportFrame.totalPages .. "                         \n"
    exportText = exportText .. "         Submitted " .. questsOnPage .. " quests from this page           \n"
    exportText = exportText .. "════════════════════════════════════════════════════════════════\n"
    
    return exportText
end

function QuestieDataCollector:FormatQuestExport(questId, questData)
    local export = "Quest ID: " .. questId .. "\n"
    export = export .. "Quest Name: " .. (questData.name or "Unknown") .. "\n"
    export = export .. "Level: " .. (questData.level or "Unknown") .. "\n"
    
    -- Zone information
    if questData.acceptZone then
        export = export .. "Zone: " .. questData.acceptZone .. "\n"
    end
    if questData.acceptAreaId or questData.acceptQuestieZoneId then
        export = export .. "Zone ID: " .. (questData.acceptQuestieZoneId or questData.acceptAreaId or "Unknown") .. "\n"
    end
    
    -- Show quest status
    if questData.turnedIn then
        export = export .. "Status: COMPLETED\n"
    elseif _activeTracking[questId] then
        export = export .. "Status: IN PROGRESS\n"
    else
        export = export .. "Status: PARTIAL DATA\n"
    end
    export = export .. "\n"
    
    if questData.wasAlreadyAccepted then
        export = export .. ">>> WARNING: INCOMPLETE DATA <<<\n"
        export = export .. "Quest was already in log when collection started.\n\n"
    end
    
    -- Quest giver (NPC) or quest starter (object/item)
    if questData.questGiver then
        export = export .. "QUEST GIVER:\n"
        export = export .. "  NPC: " .. (questData.questGiver.name or "Unknown") .. " (ID: " .. (questData.questGiver.id or 0) .. ")\n"
        if questData.questGiver.coords then
            export = export .. "  Location: " .. (questData.questGiver.coords.zone or "Unknown") .. "\n"
            export = export .. "  Coords: " .. QuestieDataCollector:SafeFormatCoords(questData.questGiver.coords) .. "\n"
        end
        export = export .. "\n"
    elseif questData.questStarter then
        export = export .. "QUEST STARTER:\n"
        export = export .. "  Type: " .. (questData.questStarter.type or "Unknown") .. "\n"
        export = export .. "  Object Name: " .. (questData.questStarter.name or "Unknown") .. "\n"
        
        -- Include object ID if available
        if questData.questStarter.id and questData.questStarter.id > 0 then
            export = export .. "  Object ID: " .. questData.questStarter.id .. "\n"
        else
            export = export .. "  Object ID: Not available from server\n"
            -- Include GUID for debugging purposes
            if questData.questStarter.guid then
                export = export .. "  Object GUID: " .. questData.questStarter.guid .. "\n"
            end
        end
        
        if questData.questStarter.coords then
            export = export .. "  Location: " .. (questData.questStarter.coords.zone or "Unknown") .. "\n"
            export = export .. "  Coords: " .. QuestieDataCollector:SafeFormatCoords(questData.questStarter.coords) .. "\n"
        end
        export = export .. "\n"
    end
    
    -- Quest description and objectives text
    if questData.questDescription then
        export = export .. "DESCRIPTION:\n"
        export = export .. "  " .. questData.questDescription .. "\n\n"
    end
    
    if questData.objectivesText then
        export = export .. "OBJECTIVES TEXT:\n"
        export = export .. "  " .. questData.objectivesText .. "\n\n"
    end
    
    -- Objectives
    if questData.objectives and #questData.objectives > 0 then
        export = export .. "OBJECTIVES:\n\n"
        for i, obj in ipairs(questData.objectives) do
            local status = obj.finished and "[x]" or "[ ]"
            -- Debug: Show what we actually have
            if not obj.text or obj.text == "" then
                export = export .. status .. " " .. i .. ". [NO TEXT CAPTURED - type: " .. (obj.type or "nil") .. "]\n"
            else
                -- Enhanced display with objective type information like v1.0.68
                local objText = obj.text
                
                -- Try to determine objective type based on text patterns
                local objType = nil
                if objText:find("slain:") or objText:find("killed") then
                    objType = "monster"
                elseif objText:find(": %d+/%d+ %(item%)") or objText:find("Collect") then
                    objType = "item"
                elseif objText:find("explored") or objText:find("Discover") then
                    objType = "area"
                end
                
                -- Format like v1.0.68: "Bloodtalon Scythemaw slain: 10/10 (monster)"
                if objType and not objText:find("%(.-%)") then
                    export = export .. objText .. " (" .. objType .. ")\n"
                else
                    export = export .. objText .. "\n"
                end
            end
            
            -- Show progress locations if available (matching v1.0.68 format)
            if obj.progress and #obj.progress > 0 then
                export = export .. "Progress locations:\n"
                for _, progressEntry in ipairs(obj.progress) do
                    if progressEntry.coords and progressEntry.coords.x and progressEntry.coords.y then
                        local coordStr = "[" .. QuestieDataCollector:SafeFormatCoords(progressEntry.coords) .. "]"
                        local zoneStr = progressEntry.coords.zone or "Unknown"
                        
                        -- Add mob kill information if available
                        if progressEntry.killedMob then
                            export = export .. coordStr .. " in " .. zoneStr .. " - Killed " .. progressEntry.killedMob .. "\n"
                        else
                            export = export .. coordStr .. " in " .. zoneStr .. "\n"
                        end
                    end
                end
            end
            export = export .. "\n"
        end
    else
        export = export .. "OBJECTIVES: [NONE CAPTURED]\n\n"
    end
    
    -- Turn-in NPC
    if questData.turnInNpc then
        export = export .. "TURN-IN NPC:\n"
        export = export .. "  NPC: " .. (questData.turnInNpc.name or "Unknown") .. " (ID: " .. (questData.turnInNpc.id or 0) .. ")\n"
        if questData.turnInNpc.coords then
            export = export .. "  Location: " .. (questData.turnInNpc.coords.zone or "Unknown") .. "\n"
            export = export .. "  Coords: " .. QuestieDataCollector:SafeFormatCoords(questData.turnInNpc.coords) .. "\n"
        end
        export = export .. "\n"
    end
    
    -- XP reward
    if questData.xpReward then
        export = export .. "REWARDS:\n"
        export = export .. "  Experience: " .. questData.xpReward .. " XP\n\n"
    end
    
    -- Related mobs
    if questData.mobs and next(questData.mobs) then
        export = export .. "RELATED MOBS:\n"
        for mobId, mobData in pairs(questData.mobs) do
            -- Count kills for this mob
            local killCount = 0
            if questData.kills then
                for _, kill in ipairs(questData.kills) do
                    if kill.mobId == mobId then
                        killCount = killCount + 1
                    end
                end
            end
            
            export = export .. "  " .. (mobData.name or "Unknown") .. " (ID: " .. mobId .. ", Level: " .. (mobData.level or "?") .. ")"
            if killCount > 0 then
                export = export .. " - KILLED " .. killCount .. " times"
            end
            export = export .. "\n"
            if mobData.locations and #mobData.locations > 0 then
                local validCoords = {}
                for i = 1, #mobData.locations do
                    local loc = mobData.locations[i]
                    if loc and loc.x and loc.y then
                        table.insert(validCoords, loc)
                    end
                end
                
                if #validCoords > 0 then
                    export = export .. "    Spawn locations (" .. #validCoords .. " total): "
                    for i = 1, math.min(3, #validCoords) do
                        local loc = validCoords[i]
                        export = export .. "(" .. QuestieDataCollector:SafeFormatCoords(loc) .. ") "
                    end
                    if #validCoords > 3 then
                        export = export .. "... and " .. (#validCoords - 3) .. " more"
                    end
                    export = export .. "\n"
                else
                    export = export .. "    WARNING: Invalid coordinate data detected\n"
                end
            end
        end
        export = export .. "\n"
    end
    
    -- Quest items
    if questData.items and next(questData.items) then
        export = export .. "> QUEST ITEMS:\n"
        for itemId, itemData in pairs(questData.items) do
            export = export .. "  " .. (itemData.name or "Unknown") .. " (ID: " .. itemId .. ")\n"
            if itemData.sources and #itemData.sources > 0 then
                for _, source in ipairs(itemData.sources) do
                    export = export .. "    Source: " .. (source.name or "Unknown") .. " (" .. (source.type or "unknown") .. ")\n"
                end
            end
        end
        export = export .. "\n"
    end
    
    -- Ground objects/containers (matching v1.0.68 format)
    if questData.objects and next(questData.objects) then
        export = export .. "GROUND OBJECTS/CONTAINERS:\n"
        for objName, objData in pairs(questData.objects) do
            local firstLocation = true
            -- Sort locations for consistent output
            local sortedLocs = {}
            for locKey, locData in pairs(objData.locations or {}) do
                table.insert(sortedLocs, locData)
            end
            table.sort(sortedLocs, function(a, b) 
                return (a.timestamp or 0) < (b.timestamp or 0) 
            end)
            
            -- Output each location
            for i, locData in ipairs(sortedLocs) do
                if firstLocation then
                    export = export .. "  " .. objName
                    if objData.id then
                        export = export .. " (ID: " .. objData.id .. ")"
                    end
                    export = export .. " at [" .. QuestieDataCollector:SafeFormatCoords(locData) .. "]"
                    if locData.zone then
                        export = export .. " in " .. locData.zone
                    end
                    export = export .. "\n"
                    firstLocation = false
                else
                    -- Additional locations
                    export = export .. "    Additional location: [" .. QuestieDataCollector:SafeFormatCoords(locData) .. "]"
                    if locData.zone then
                        export = export .. " in " .. locData.zone
                    end
                    export = export .. "\n"
                end
            end
        end
        export = export .. "\n"
    end
    
    -- Prerequisites tracking
    if questData.potentialPrerequisites and #questData.potentialPrerequisites > 0 then
        export = export .. "POTENTIAL PREREQUISITES:\n"
        export = export .. "  " .. #questData.potentialPrerequisites .. " quests were completed before accepting this quest\n\n"
    end
    
    if questData.unlocksQuests and #questData.unlocksQuests > 0 then
        export = export .. "UNLOCKS QUESTS:\n"
        export = export .. "  Completing this quest unlocked:\n"
        for _, questName in ipairs(questData.unlocksQuests) do
            export = export .. "    * " .. questName .. "\n"
        end
        export = export .. "\n"
    end
    
    -- Commission quest data
    if questData.isCommission then
        export = export .. "COMMISSION QUEST DATA:\n"
        export = export .. "  This is a profession commission quest\n"
        if questData.playerProfessions and #questData.playerProfessions > 0 then
            export = export .. "  Player professions at time of acceptance:\n"
            for _, prof in ipairs(questData.playerProfessions) do
                export = export .. "    * " .. prof.name .. " (" .. prof.skillLevel .. "/" .. prof.maxSkillLevel .. ")\n"
            end
        end
        export = export .. "\n"
    end
    
    -- Add database entries
    export = export .. "\n" .. QuestieDataCollector:GenerateDatabaseEntries(questId, questData)
    
    -- Add database mismatches if any
    if questData.mismatches and next(questData.mismatches) then
        export = export .. "\nDATABASE MISMATCHES DETECTED:\n"
        export = export .. "==============================\n"
        for entityType, entities in pairs(questData.mismatches) do
            for entityId, fields in pairs(entities) do
                for fieldName, mismatch in pairs(fields) do
                    export = export .. string.format("[MISMATCH] %s %s field '%s': DB has '%s' but found '%s'\n",
                        entityType, entityId, fieldName, 
                        tostring(mismatch.databaseValue), 
                        tostring(mismatch.collectedValue))
                end
            end
        end
        export = export .. "\n"
    end
    
    return export
end

-- Export functions for slash commands
function QuestieDataCollector:ExportQuest(questId)
    questId = tonumber(questId)
    if not questId then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r Invalid quest ID", 1, 0, 0)
        return
    end
    
    local questData = QuestieDataCollection.quests[questId]
    if not questData then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r No data collected for quest " .. questId, 1, 0, 0)
        return
    end
    
    -- Generate export text with clear visual separators
    local export = "\n"
    export = export .. "════════════════════════════════════════════════════════════════\n"
    export = export .. "                  HOW TO SUBMIT YOUR REPORT                     \n"
    export = export .. "════════════════════════════════════════════════════════════════\n\n"
    export = export .. "1. Copy all text below (Ctrl+C to copy)\n"
    export = export .. "2. Go to: https://github.com/trav346/Questie/issues\n"
    export = export .. "3. Click 'New Issue'\n"
    export = export .. "4. Title: Missing Quest: " .. (questData.name or "Unknown") .. " (ID: " .. questId .. ")\n"
    export = export .. "5. Paste this entire report in the description\n"
    export = export .. "6. Click 'Submit new issue'\n\n"
    export = export .. "════════════════════════════════════════════════════════════════\n"
    export = export .. "                     QUEST DATA EXPORT                          \n"
    export = export .. "════════════════════════════════════════════════════════════════\n\n"
    export = export .. "Quest ID: " .. questId .. "\n"
    export = export .. "Quest Name: " .. (questData.name or "Unknown") .. "\n"
    export = export .. "Level: " .. (questData.level or "Unknown") .. "\n"
    export = export .. "Player Level: " .. (questData.playerLevel or "Unknown") .. "\n"
    
    -- Zone information (CRITICAL: Show both subzone and parent zone)
    if questData.acceptZone then
        export = export .. "Zone: " .. questData.acceptZone
        if questData.acceptSubZone and questData.acceptSubZone ~= "" then
            export = export .. " - " .. questData.acceptSubZone
        end
        export = export .. "\n"
    end
    if questData.acceptAreaId or questData.acceptParentZoneId then
        export = export .. "Zone IDs: "
        if questData.acceptAreaId then
            export = export .. "Area=" .. questData.acceptAreaId
        end
        if questData.acceptParentZoneId then
            export = export .. " Parent=" .. questData.acceptParentZoneId
        end
        if questData.acceptQuestieZoneId then
            export = export .. " (Use: " .. questData.acceptQuestieZoneId .. ")"
        end
        export = export .. "\n"
    end
    
    -- Add profession data for skill-required quests  
    if questData.playerProfessions and #questData.playerProfessions > 0 then
        export = export .. "Player Professions:\n"
        for _, prof in ipairs(questData.playerProfessions) do
            export = export .. "  * " .. prof.name .. " (" .. prof.skillLevel .. "/" .. prof.maxSkillLevel .. ")\n"
        end
    end
    
    -- Add required skill info if available
    if questData.requiredSkill then
        export = export .. "Required Skill: " .. (questData.requiredSkill[1] or "Unknown") .. " (" .. (questData.requiredSkill[2] or "0") .. ")\n"
    end
    
    export = export .. "Version: " .. (QuestieDataCollection.version or "Unknown") .. "\n"
    export = export .. "────────────────────────────────────────────────────────────────\n\n"
    
    if questData.wasAlreadyAccepted then
        export = export .. "WARNING: WARNING: INCOMPLETE DATA WARNING:\n"
        export = export .. "This quest was already in your log when data collection started.\n"
        export = export .. "Quest giver information may be missing.\n\n"
    end
    
    -- Add quest giver info
    if questData.questGiver then
        export = export .. "> QUEST GIVER:\n"
        export = export .. "  NPC: " .. (questData.questGiver.name or "Unknown") .. " (ID: " .. (questData.questGiver.id or 0) .. ")\n"
        if questData.questGiver.coords then
            export = export .. "  Location: " .. (questData.questGiver.coords.zone or "Unknown") .. "\n"
            export = export .. "  Coords: " .. QuestieDataCollector:SafeFormatCoords(questData.questGiver.coords) .. "\n"
        end
        export = export .. "\n"
    end
    
    -- Add objectives
    if questData.objectives and #questData.objectives > 0 then
        export = export .. "> OBJECTIVES:\n"
        for i, obj in ipairs(questData.objectives) do
            export = export .. "  " .. i .. ". " .. (obj.text or "Unknown") .. "\n"
        end
        export = export .. "\n"
    end
    
    -- Add turn-in info
    if questData.turnInNpc then
        export = export .. "> TURN-IN NPC:\n"
        export = export .. "  NPC: " .. (questData.turnInNpc.name or "Unknown") .. " (ID: " .. (questData.turnInNpc.id or 0) .. ")\n"
        if questData.turnInNpc.coords then
            export = export .. "  Location: " .. (questData.turnInNpc.coords.zone or "Unknown") .. "\n"
            export = export .. "  Coords: " .. QuestieDataCollector:SafeFormatCoords(questData.turnInNpc.coords) .. "\n"
        end
        export = export .. "\n"
    elseif questData.turnInNPC then  -- Also check for turnInNPC (capital NPC)
        export = export .. "> TURN-IN NPC:\n"
        export = export .. "  NPC: " .. (questData.turnInNPC.name or "Unknown") .. " (ID: " .. (questData.turnInNPC.id or 0) .. ")\n"
        if questData.turnInNPC.coords then
            export = export .. "  Location: " .. (questData.turnInNPC.zone or "Unknown") .. "\n"
            export = export .. "  Coords: " .. QuestieDataCollector:SafeFormatCoords(questData.turnInNPC.coords) .. "\n"
        end
        export = export .. "\n"
    end
    
    -- Add quest chain and prerequisite information
    if questData.potentialChain and #questData.potentialChain > 0 then
        export = export .. "> POTENTIAL QUEST CHAIN:\n"
        for _, chainQuest in ipairs(questData.potentialChain) do
            export = export .. "  * " .. chainQuest.name .. " (ID: " .. chainQuest.id .. ") - " .. chainQuest.reason .. "\n"
        end
        export = export .. "\n"
    end
    
    if questData.requiresQuest and #questData.requiresQuest > 0 then
        export = export .. "> PREREQUISITE QUESTS:\n"
        for _, prereq in ipairs(questData.requiresQuest) do
            export = export .. "  * " .. prereq.name .. " (ID: " .. prereq.id .. ")\n"
        end
        export = export .. "\n"
    end
    
    if questData.unlockedQuests and #questData.unlockedQuests > 0 then
        export = export .. "> UNLOCKS QUESTS:\n"
        for _, unlocked in ipairs(questData.unlockedQuests) do
            export = export .. "  * " .. unlocked.name
            if unlocked.level then
                export = export .. " (Level " .. unlocked.level .. ")"
            end
            if unlocked.npcName then
                export = export .. " from " .. unlocked.npcName
            end
            export = export .. "\n"
        end
        export = export .. "\n"
    end
    
    if questData.removedQuests and #questData.removedQuests > 0 then
        export = export .. "> EXCLUSIVE WITH (these quests disappear after accepting this):\n"
        for _, removed in ipairs(questData.removedQuests) do
            export = export .. "  * " .. removed.title
            if removed.level then
                export = export .. " (Level " .. removed.level .. ")"
            end
            export = export .. "\n"
        end
        export = export .. "\n"
    end
    
    -- Add XP reward info
    if questData.xpReward then
        export = export .. "> REWARDS:\n"
        export = export .. "  Experience: " .. questData.xpReward .. " XP\n\n"
    end
    
    -- Add mobs
    if questData.mobs and next(questData.mobs) then
        export = export .. "> RELATED MOBS:\n"
        for mobId, mobData in pairs(questData.mobs) do
            export = export .. "  " .. (mobData.name or "Unknown") .. " (ID: " .. mobId .. ", Level: " .. (mobData.level or "?") .. ")\n"
        end
        export = export .. "\n"
    end
    
    -- Add items
    if questData.items and next(questData.items) then
        export = export .. "> QUEST ITEMS:\n"
        for itemId, itemData in pairs(questData.items) do
            export = export .. "  " .. (itemData.name or "Unknown") .. " (ID: " .. itemId .. ")\n"
            if itemData.sources and #itemData.sources > 0 then
                for _, source in ipairs(itemData.sources) do
                    export = export .. "    Source: " .. (source.name or "Unknown") .. " (" .. (source.type or "unknown") .. ")\n"
                end
            end
        end
        export = export .. "\n"
    end
    
    -- Add service NPCs encountered in the same zone
    local zoneServiceNPCs = {}
    local totalServiceNPCs = 0
    for _ in pairs(QuestieDataCollection.serviceNPCs) do
        totalServiceNPCs = totalServiceNPCs + 1
    end
    
    -- Debug: Show total service NPCs
    if totalServiceNPCs > 0 then
        export = export .. "-- Debug: Total service NPCs in collection: " .. totalServiceNPCs .. " --\n"
        -- List all service NPC IDs for debugging
        local npcList = {}
        for npcId, npcData in pairs(QuestieDataCollection.serviceNPCs) do
            table.insert(npcList, npcId .. ":" .. (npcData.name or "Unknown"))
        end
        export = export .. "-- Service NPCs: " .. table.concat(npcList, ", ") .. " --\n\n"
    else
        export = export .. "-- Debug: No service NPCs in collection --\n\n"
    end
    
    if questData.questGiver and questData.questGiver.coords and questData.questGiver.coords.zone then
        local questZone = questData.questGiver.coords.zone
        for npcId, npcData in pairs(QuestieDataCollection.serviceNPCs) do
            for _, location in ipairs(npcData.locations) do
                if location.zone == questZone then
                    zoneServiceNPCs[npcId] = npcData
                    break
                end
            end
        end
    end
    
    if next(zoneServiceNPCs) then
        export = export .. "> SERVICE NPCs IN QUEST AREA:\n"
        for npcId, npcData in pairs(zoneServiceNPCs) do
            export = export .. "  " .. (npcData.name or "Unknown") .. " (ID: " .. npcId .. ")\n"
            export = export .. "    Services: " .. table.concat(npcData.services, ", ") .. "\n"
            if #npcData.locations > 0 then
                for _, loc in ipairs(npcData.locations) do
                    if loc.x and loc.y then
                        export = export .. "    Location: " .. string.format("%.1f, %.1f", loc.x, loc.y) .. " (" .. (loc.zone or "Unknown") .. ")\n"
                    end
                end
            end
        end
        export = export .. "\n"
    end
    
    -- Add ALL service NPCs encountered (not just zone-specific)
    local allServiceNPCs = {}
    for npcId, npcData in pairs(QuestieDataCollection.serviceNPCs) do
        -- Skip if already shown in zone-specific section
        if not zoneServiceNPCs[npcId] then
            allServiceNPCs[npcId] = npcData
        end
    end
    
    if next(allServiceNPCs) then
        export = export .. "> OTHER SERVICE NPCs ENCOUNTERED:\n"
        for npcId, npcData in pairs(allServiceNPCs) do
            export = export .. "  " .. (npcData.name or "Unknown") .. " (ID: " .. npcId .. ")\n"
            export = export .. "    Services: " .. table.concat(npcData.services, ", ") .. "\n"
            if #npcData.locations > 0 then
                for _, loc in ipairs(npcData.locations) do
                    if loc.x and loc.y then
                        export = export .. "    At: " .. string.format("%.1f, %.1f", loc.x, loc.y) .. " in " .. (loc.zone or "Unknown") .. "\n"
                    end
                end
            end
        end
        export = export .. "\n"
    end
    
    -- Add detected mismatches
    local hasMismatches = false
    for key, mismatch in pairs(_dataMismatches) do
        if mismatch.entityType == "quest" and mismatch.entityId == questId then
            if not hasMismatches then
                export = export .. "> DATABASE MISMATCHES DETECTED:\n"
                hasMismatches = true
            end
            export = export .. "  Field: " .. mismatch.fieldName .. "\n"
            export = export .. "    Collected: " .. tostring(mismatch.collectedValue) .. "\n"
            export = export .. "    Database: " .. tostring(mismatch.databaseValue) .. "\n"
        end
    end
    
    -- Check for NPC mismatches related to this quest
    if questData.questGiver and questData.questGiver.id then
        local npcKey = "npc_" .. questData.questGiver.id .. "_coords"
        if _dataMismatches[npcKey] then
            if not hasMismatches then
                export = export .. "> DATABASE MISMATCHES DETECTED:\n"
                hasMismatches = true
            end
            export = export .. "  Quest Giver NPC " .. questData.questGiver.id .. " coordinates:\n"
            local mismatch = _dataMismatches[npcKey]
            if mismatch.collectedValue and mismatch.collectedValue.x then
                export = export .. "    Found at: " .. string.format("%.1f, %.1f", mismatch.collectedValue.x, mismatch.collectedValue.y) .. "\n"
            end
            if mismatch.databaseValue and mismatch.databaseValue.distance then
                export = export .. "    Distance from DB: " .. string.format("%.1f units", mismatch.databaseValue.distance) .. "\n"
            end
        end
    end
    
    if questData.turnInNpc and questData.turnInNpc.id then
        local npcKey = "npc_" .. questData.turnInNpc.id .. "_coords"
        if _dataMismatches[npcKey] then
            if not hasMismatches then
                export = export .. "> DATABASE MISMATCHES DETECTED:\n"
                hasMismatches = true
            end
            export = export .. "  Turn-in NPC " .. questData.turnInNpc.id .. " coordinates:\n"
            local mismatch = _dataMismatches[npcKey]
            if mismatch.collectedValue and mismatch.collectedValue.x then
                export = export .. "    Found at: " .. string.format("%.1f, %.1f", mismatch.collectedValue.x, mismatch.collectedValue.y) .. "\n"
            end
            if mismatch.databaseValue and mismatch.databaseValue.distance then
                export = export .. "    Distance from DB: " .. string.format("%.1f units", mismatch.databaseValue.distance) .. "\n"
            end
        end
    end
    
    if hasMismatches then
        export = export .. "\n"
    end
    
    -- Save to a frame for copying
    if not QuestieDataCollectorExportFrame then
        local f = CreateFrame("Frame", "QuestieDataCollectorExportFrame", UIParent)
        f:SetSize(600, 400)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        
        -- Background
        f.bg = f:CreateTexture(nil, "BACKGROUND")
        f.bg:SetAllPoints()
        f.bg:SetColorTexture(0, 0, 0, 0.8)
        
        -- Title
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        f.title:SetPoint("TOP", 0, -10)
        f.title:SetText("Quest Data Export")
        
        -- Scroll frame
        f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        f.scroll:SetPoint("TOPLEFT", 10, -40)
        f.scroll:SetPoint("BOTTOMRIGHT", -30, 40)
        
        -- Edit box
        f.editBox = CreateFrame("EditBox", nil, f.scroll)
        f.editBox:SetMultiLine(true)
        f.editBox:SetFontObject(GameFontNormalSmall)
        f.editBox:SetWidth(550)
        f.editBox:SetAutoFocus(false)
        f.editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        
        f.scroll:SetScrollChild(f.editBox)
        
        -- Instructions
        f.instructions = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.instructions:SetPoint("BOTTOM", 0, 20)
        f.instructions:SetText("Ctrl+A to select all, Ctrl+C to copy")
        
        -- Close button
        f.closeButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        f.closeButton:SetPoint("TOPRIGHT", -5, -5)
    end
    
    -- Generate database entries
    export = export .. "\n" .. QuestieDataCollector:GenerateDatabaseEntries(questId, questData)
    
    -- Add footer separator
    export = export .. "\n════════════════════════════════════════════════════════════════\n"
    export = export .. "                        END OF QUEST                           \n"
    export = export .. "════════════════════════════════════════════════════════════════\n\n"
    
    QuestieDataCollectorExportFrame.editBox:SetText(export)
    QuestieDataCollectorExportFrame.editBox:HighlightText()
    QuestieDataCollectorExportFrame:Show()
    
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[Data Collector]|r Quest data exported. Copy from the window and submit to GitHub.", 0, 1, 0)
end

function QuestieDataCollector:GenerateDatabaseEntries(questId, questData)
    local output = "DATABASE ENTRIES:\n"
    output = output .. "================\n\n"
    
    -- Generate quest entry with EXACT field order and format
    output = output .. "-- Add to epochQuestDB.lua:\n"
    
    -- Add zone information comment if we have subzone data
    if questData.acceptAreaId and questData.acceptParentZoneId and questData.acceptAreaId ~= questData.acceptParentZoneId then
        output = output .. "-- Zone: " .. (questData.acceptZone or "Unknown") 
        output = output .. " (ID: " .. questData.acceptAreaId .. " -> Parent: " .. questData.acceptParentZoneId .. ")\n"
    elseif questData.acceptAreaId then
        output = output .. "-- Zone: " .. (questData.acceptZone or "Unknown") .. " (ID: " .. questData.acceptAreaId .. ")\n"
    end
    
    output = output .. "[" .. questId .. "] = {"
    
    -- Field 1: Quest name (string)
    output = output .. '"' .. (questData.name or "Unknown Quest") .. '"'
    
    -- Field 2: Started by {{NPCs},{Objects},{Items}}
    output = output .. ","
    if questData.questGiver and questData.questGiver.id then
        output = output .. "{{" .. questData.questGiver.id .. "}}"
    else
        output = output .. "nil"
    end
    
    -- Field 3: Finished by {{NPCs},{Objects}}
    output = output .. ","
    if questData.turnInNpc and questData.turnInNpc.id then
        output = output .. "{{" .. questData.turnInNpc.id .. "}}"
    else
        output = output .. "nil"
    end
    
    -- Field 4: Required level (int or nil)
    output = output .. ",nil"
    
    -- Field 5: Quest level (int)
    output = output .. "," .. (questData.level or "nil")
    
    -- Field 6: Required races (bitmask or nil)
    output = output .. ",nil"
    
    -- Field 7: Required classes (bitmask or nil) 
    output = output .. ",nil"
    
    -- Field 8: Objectives text (table of strings or nil)
    output = output .. ",nil"
    
    -- Field 9: Trigger end (exploration trigger or nil)
    output = output .. ",nil"
    
    -- Field 10: Objectives structure
    output = output .. ","
    if questData.objectives and #questData.objectives > 0 then
        local creatures = {}
        local objects = {}
        local items = {}
        local hasAnyObjective = false
        
        -- Parse each objective
        for _, obj in ipairs(questData.objectives) do
            if obj.text then
                -- Check for creature kills
                local mobName, current, total = string.match(obj.text, "(.+) slain: (%d+)/(%d+)")
                if not mobName then
                    mobName, current, total = string.match(obj.text, "(.+) killed: (%d+)/(%d+)")
                end
                if not mobName then
                    mobName, current, total = string.match(obj.text, "Kill (%d+) (.+)")
                    if mobName and total then
                        mobName, total = total, mobName  -- Swap them
                    end
                end
                
                if mobName and total then
                    -- Try to find the mob ID from our tracked mobs
                    if questData.mobs then
                        for mobId, mobData in pairs(questData.mobs) do
                            if mobData.name and (mobData.name == mobName or string.find(mobData.name, mobName) or string.find(mobName, mobData.name)) then
                                table.insert(creatures, string.format('{%s,%s}', mobId, total))
                                hasAnyObjective = true
                                break
                            end
                        end
                    end
                end
                
                -- Check for item collection
                local itemName, itemCurrent, itemTotal = string.match(obj.text, "(.+): (%d+)/(%d+)")
                if itemName and itemTotal and not string.find(itemName, "slain") and not string.find(itemName, "killed") then
                    -- Try to find item ID from tracked items
                    if questData.items then
                        for itemId, itemInfo in pairs(questData.items) do
                            if itemInfo.name and (itemInfo.name == itemName or string.find(itemInfo.name, itemName)) then
                                table.insert(items, string.format('{%s,%s}', itemId, itemTotal))
                                hasAnyObjective = true
                                break
                            end
                        end
                    end
                end
            end
        end
        
        -- Build objectives structure: {creatures, objects, items, reputation, killCredit, spells}
        if hasAnyObjective then
            output = output .. "{"
            
            -- Creatures sub-table
            if #creatures > 0 then
                output = output .. "{" .. table.concat(creatures, ",") .. "}"
            else
                output = output .. "nil"
            end
            
            -- Objects sub-table
            output = output .. ","
            if #objects > 0 then
                output = output .. "{" .. table.concat(objects, ",") .. "}"
            else
                output = output .. "nil"
            end
            
            -- Items sub-table
            output = output .. ","
            if #items > 0 then
                output = output .. "{" .. table.concat(items, ",") .. "}"
            else
                output = output .. "nil"
            end
            
            -- Reputation, killCredit, spells (all nil for now)
            output = output .. ",nil,nil,nil"
            
            output = output .. "}"
        else
            output = output .. "nil"
        end
    else
        output = output .. "nil"
    end
    
    -- Fields 11-16: nil for basic entry
    for i = 11, 16 do
        output = output .. ",nil"
    end
    
    -- Field 17: zoneOrSort (zone ID where quest is)
    output = output .. ","
    local questZoneId = 0
    if questData.questGiver and questData.questGiver.coords then
        -- Use proper questieZoneId which has been mapped from subzone names
        -- This ensures we use 159 for Brill, 154 for Deathknell, etc.
        if questData.acceptQuestieZoneId then
            -- Use the mapped zone ID from quest acceptance (preferred)
            questZoneId = questData.acceptQuestieZoneId
        elseif questData.questGiver.coords.questieZoneId then
            -- Use the mapped zone ID from quest giver location
            questZoneId = questData.questGiver.coords.questieZoneId
        elseif questData.acceptAreaId then
            -- Fallback to raw area ID from quest acceptance
            questZoneId = questData.acceptAreaId
        elseif questData.questGiver.coords.areaId then
            -- Fallback to raw area ID from quest giver location
            questZoneId = questData.questGiver.coords.areaId
        end
        
        -- Only fallback to zone name mapping if we have no zone ID
        if (not questZoneId or questZoneId == 0) and questData.questGiver.coords.zone and ZONE_NAME_TO_ID[questData.questGiver.coords.zone] then
            questZoneId = ZONE_NAME_TO_ID[questData.questGiver.coords.zone]
        end
    end
    if questZoneId > 0 then
        output = output .. questZoneId
    else
        output = output .. "nil"
    end
    
    -- Fields 18-23: nil for basic entry
    for i = 18, 23 do
        output = output .. ",nil"
    end
    
    -- Field 24: specialFlags (use 0 for standard quest)
    output = output .. ",0"
    
    -- Fields 25-30: nil for basic entry
    for i = 25, 30 do
        output = output .. ",nil"
    end
    
    output = output .. "},\n\n"
    
    -- Generate NPC entries (aggregate all quest info for each NPC)
    local npcData = {}
    
    -- Process quest giver
    if questData.questGiver and questData.questGiver.id then
        local npcId = questData.questGiver.id
        if not npcData[npcId] then
            npcData[npcId] = {
                name = questData.questGiver.name or "Unknown",
                coords = questData.questGiver.coords,
                level = questData.level or "nil",
                questStarts = {},
                questEnds = {}
            }
        end
        table.insert(npcData[npcId].questStarts, questId)
    end
    
    -- Process turn-in NPC
    if questData.turnInNpc and questData.turnInNpc.id then
        local npcId = questData.turnInNpc.id
        if not npcData[npcId] then
            npcData[npcId] = {
                name = questData.turnInNpc.name or "Unknown",
                coords = questData.turnInNpc.coords,
                level = questData.level or "nil",
                questStarts = {},
                questEnds = {}
            }
        end
        table.insert(npcData[npcId].questEnds, questId)
    end
    
    -- Generate NPC entries with EXACT 15-field structure
    local npcEntries = {}
    for npcId, npc in pairs(npcData) do
        -- Get proper zone ID
        local zoneId = 0
        if npc.coords then
            -- Use the mapped questieZoneId which has correct subzone IDs
            -- This ensures we use 159 for Brill, 154 for Deathknell, etc.
            if npc.coords.questieZoneId then
                zoneId = npc.coords.questieZoneId
            elseif npc.coords.areaId then
                -- Fallback to raw area ID if no mapped zone
                zoneId = npc.coords.areaId
            end
            
            -- Only fallback to zone name mapping if we have no zone ID
            if (not zoneId or zoneId == 0) and npc.coords.zone and ZONE_NAME_TO_ID[npc.coords.zone] then
                zoneId = ZONE_NAME_TO_ID[npc.coords.zone]
            end
        end
        
        -- Field 7: Spawn coordinates {[zoneId]={{x,y}}}
        local coords = "nil"
        if npc.coords and npc.coords.x and npc.coords.y and zoneId > 0 then
            coords = string.format("{[%d]={{%.1f,%.1f}}}", 
                zoneId, npc.coords.x, npc.coords.y)
        end
        
        -- Field 10: Quest starts array
        local questStarts = "nil"
        if #npc.questStarts > 0 then
            questStarts = "{" .. table.concat(npc.questStarts, ",") .. "}"
        end
        
        -- Field 11: Quest ends array
        local questEnds = "nil"
        if #npc.questEnds > 0 then
            questEnds = "{" .. table.concat(npc.questEnds, ",") .. "}"
        end
        
        -- Calculate NPC flags based on detected services (WotLK values)
        local npcFlags = 0
        
        -- Check if we have detected services for this NPC
        local detectedServices = {}
        if QuestieDataCollection.npcs and QuestieDataCollection.npcs[npcId] and QuestieDataCollection.npcs[npcId].detectedServices then
            detectedServices = QuestieDataCollection.npcs[npcId].detectedServices
        end
        
        -- Add appropriate flags based on detected services
        if detectedServices["QUEST_GIVER"] or #npc.questStarts > 0 or #npc.questEnds > 0 then
            npcFlags = npcFlags + 2  -- QUEST_GIVER
        end
        if detectedServices["VENDOR"] then
            npcFlags = npcFlags + 128  -- VENDOR
        end
        if detectedServices["TRAINER"] then
            npcFlags = npcFlags + 16  -- TRAINER
        end
        if detectedServices["FLIGHT_MASTER"] then
            npcFlags = npcFlags + 8192  -- FLIGHT_MASTER
        end
        if detectedServices["INNKEEPER"] then
            npcFlags = npcFlags + 65536  -- INNKEEPER
        end
        if detectedServices["BANKER"] then
            npcFlags = npcFlags + 131072  -- BANKER
        end
        if detectedServices["REPAIR"] then
            npcFlags = npcFlags + 4096  -- REPAIR
        end
        if detectedServices["AUCTIONEER"] then
            npcFlags = npcFlags + 2097152  -- AUCTIONEER
        end
        if detectedServices["STABLEMASTER"] then
            npcFlags = npcFlags + 4194304  -- STABLEMASTER
        end
        if detectedServices["BATTLEMASTER"] then
            npcFlags = npcFlags + 1048576  -- BATTLEMASTER
        end
        
        -- Default to QUEST_GIVER if no services detected but NPC gives/ends quests
        if npcFlags == 0 and (#npc.questStarts > 0 or #npc.questEnds > 0) then
            npcFlags = 2
        end
        
        -- Build NPC entry with exact 15 fields
        -- [npcId] = {name, minHP, maxHP, minLvl, maxLvl, rank, spawns, waypoints, zoneID, questStarts, questEnds, factionID, friendlyTo, subName, npcFlags}
        npcEntries[npcId] = string.format(
            '[%d] = {"%s",nil,nil,%s,%s,0,%s,nil,%d,%s,%s,nil,nil,nil,%d},',
            npcId,            -- NPC ID
            npc.name,         -- Field 1: name
            npc.level,        -- Field 4: minLevel
            npc.level,        -- Field 5: maxLevel
            coords,           -- Field 7: spawns
            zoneId,           -- Field 9: zoneID
            questStarts,      -- Field 10: questStarts
            questEnds,        -- Field 11: questEnds
            npcFlags          -- Field 15: npcFlags (calculated based on detected services)
        )
    end
    
    -- Output NPC entries (sorted for consistency)
    if next(npcEntries) then
        output = output .. "-- Add to epochNpcDB.lua:\n"
        output = output .. "-- Note: NPC flags are automatically calculated based on detected services\n"
        
        -- Add zone information for NPCs if we have subzone data
        local hasSubzoneNPCs = false
        for npcId, npc in pairs(npcData) do
            if npc.coords and npc.coords.areaId and npc.coords.parentZoneId and npc.coords.areaId ~= npc.coords.parentZoneId then
                if not hasSubzoneNPCs then
                    output = output .. "-- NPCs with subzone data:\n"
                    hasSubzoneNPCs = true
                end
                output = output .. "--   " .. (npc.name or "NPC " .. npcId) 
                output = output .. ": Zone " .. npc.coords.areaId .. " -> Parent " .. npc.coords.parentZoneId .. "\n"
            end
        end
        
        -- List detected services for each NPC as a comment
        for npcId, npc in pairs(npcData) do
            if QuestieDataCollection.npcs and QuestieDataCollection.npcs[npcId] and QuestieDataCollection.npcs[npcId].detectedServices then
                local services = {}
                for service, _ in pairs(QuestieDataCollection.npcs[npcId].detectedServices) do
                    table.insert(services, service)
                end
                if #services > 0 then
                    output = output .. string.format("-- NPC %d (%s): %s\n", npcId, npc.name, table.concat(services, ", "))
                end
            end
        end
        output = output .. "\n"
        
        -- Sort NPC IDs for consistent output
        local sortedNpcIds = {}
        for npcId in pairs(npcEntries) do
            table.insert(sortedNpcIds, npcId)
        end
        table.sort(sortedNpcIds, function(a, b) return tonumber(a) < tonumber(b) end)
        
        for _, npcId in ipairs(sortedNpcIds) do
            output = output .. npcEntries[npcId] .. "\n"
        end
    end
    
    
    return output
end

function QuestieDataCollector:ShowStatus()
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF=== Questie Data Collector Status ===|r", 0, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("Version: " .. CURRENT_VERSION, 1, 1, 1)
    
    if Questie.db.profile.dataCollectionDevMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[DEV MODE ACTIVE] Collecting ALL quests|r", 1, 0, 0)
    end
    
    local questCount = 0
    local missingCount = 0
    local inDatabaseCount = 0
    
    for questId in pairs(QuestieDataCollection.quests) do
        questCount = questCount + 1
        if IsQuestInDatabase(questId) then
            inDatabaseCount = inDatabaseCount + 1
        else
            missingCount = missingCount + 1
        end
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("Total quests tracked: " .. questCount, 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("Missing from database: " .. missingCount, 1, 1, 0)
    DEFAULT_CHAT_FRAME:AddMessage("Now in database (skipped): " .. inDatabaseCount, 0.7, 0.7, 0.7)
    
    local activeCount = 0
    for _ in pairs(_activeTracking) do
        activeCount = activeCount + 1
    end
    DEFAULT_CHAT_FRAME:AddMessage("Currently tracking: " .. activeCount .. " quests", 0, 1, 0)
    
    local mismatchCount = 0
    for _ in pairs(_dataMismatches) do
        mismatchCount = mismatchCount + 1
    end
    if mismatchCount > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("Database mismatches detected: " .. mismatchCount, 1, 0.5, 0)
    end
    
    local serviceNPCCount = 0
    for _ in pairs(QuestieDataCollection.serviceNPCs) do
        serviceNPCCount = serviceNPCCount + 1
    end
    if serviceNPCCount > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("Service NPCs tracked: " .. serviceNPCCount, 0.5, 0.5, 1)
    end
    
    local mailboxCount = 0
    for _ in pairs(QuestieDataCollection.mailboxes) do
        mailboxCount = mailboxCount + 1
    end
    if mailboxCount > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("Mailboxes discovered: " .. mailboxCount, 0.5, 0.5, 1)
    end
    
    if Questie.db.profile.enableDataCollection then
        DEFAULT_CHAT_FRAME:AddMessage("Status: |cFF00FF00ENABLED|r", 0, 1, 0)
    else
        DEFAULT_CHAT_FRAME:AddMessage("Status: |cFFFF0000DISABLED|r", 1, 0, 0)
    end
end

function QuestieDataCollector:ShowTrackedQuests()
    local count = 0
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF=== Tracked Missing Quests ===|r", 0, 1, 1)
    
    for questId, questData in pairs(QuestieDataCollection.quests) do
        if not IsQuestInDatabase(questId) then
            count = count + 1
            local status = ""
            if questData.turnedIn then
                status = "|cFF00FF00[COMPLETE]|r"
            elseif _activeTracking[questId] then
                status = "|cFFFFFF00[IN PROGRESS]|r"
            else
                status = "|cFFAAAAAA[PARTIAL DATA]|r"
            end
            
            DEFAULT_CHAT_FRAME:AddMessage(string.format("%s %s (ID: %d) %s", 
                status,
                questData.name or "Unknown",
                questId,
                questData.wasAlreadyAccepted and "|cFFFF8800[INCOMPLETE]|r" or ""
            ), 1, 1, 1)
        end
    end
    
    if count == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("No quests currently being tracked.", 1, 1, 1)
    else
        DEFAULT_CHAT_FRAME:AddMessage("Total: " .. count .. " quests being tracked", 1, 1, 0)
    end
end

function QuestieDataCollector:ManualTurnIn(questId)
    local questData = QuestieDataCollection.quests[questId]
    if not questData then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r No data for quest " .. questId, 1, 0, 0)
        return
    end
    
    -- Capture turn-in NPC from current target
    local guid = UnitGUID("target")
    if guid then
        local npcId = ExtractNpcIdFromGuid(guid)
        if npcId then
            local npcName = UnitName("target")
            local coords = QuestieDataCollector:GetPlayerCoordinates()
            
            questData.turnInNpc = {
                id = npcId,
                name = npcName,
                coords = coords
            }
            DebugMessage("|cFF00FF00[Data Collector]|r Turn-in NPC captured: " .. npcName .. " (ID: " .. npcId .. ")", 0, 1, 0)
        end
    end
    
    -- Mark as turned in
    questData.turnedIn = true
    questData.turnInTimestamp = time()
    questData.turnInDate = date("%Y-%m-%d %H:%M:%S")
    
    -- If we have pending XP, assign it
    if _pendingXPReward and _pendingXPReward > 0 then
        questData.xpReward = _pendingXPReward
        DebugMessage("|cFF00FF00[Data Collector]|r XP reward captured: " .. _pendingXPReward, 0, 1, 0)
        _pendingXPReward = nil
    end
    
    -- Remove from active tracking
    _activeTracking[questId] = nil
    
    DebugMessage("|cFF00FF00[Data Collector]|r Quest marked as turned in: " .. (questData.name or "Unknown"), 0, 1, 0)
end

function QuestieDataCollector:CaptureQuestGiver(questId)
    local questData = QuestieDataCollection.quests[questId]
    if not questData then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r No data for quest " .. questId, 1, 0, 0)
        return
    end
    
    -- Capture quest giver NPC from current target
    local guid = UnitGUID("target")
    if not guid then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r No target selected", 1, 0, 0)
        return
    end
    
    local npcId = ExtractNpcIdFromGuid(guid)
    if npcId then
        local npcName = UnitName("target")
        local coords = QuestieDataCollector:GetPlayerCoordinates()
        
        questData.questGiver = {
            id = npcId,
            name = npcName,
            coords = coords
        }
        DebugMessage("|cFF00FF00[Data Collector]|r Quest giver captured: " .. npcName .. " (ID: " .. npcId .. ")", 0, 1, 0)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r Could not extract NPC ID from target", 1, 0, 0)
    end
end

function QuestieDataCollector:RescanQuestLog()
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[Data Collector]|r Rescanning quest log for missing data...", 0, 1, 1)
    
    local scannedCount = 0
    local updatedCount = 0
    local restoredCount = 0
    
    -- Debug quest log access
    local numEntries = GetNumQuestLogEntries()
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[DEBUG]|r GetNumQuestLogEntries() returned: " .. numEntries, 1, 1, 0)
    
    -- Scan through the quest log
    for i = 1, numEntries do
        local title, level, tag, isHeader, _, _, _, _, questId = GetQuestLogTitle(i)
        
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[DEBUG]|r Entry " .. i .. ": " .. (title or "nil") .. " (ID: " .. (questId or "nil") .. ", header: " .. tostring(isHeader), 1, 1, 0)
        
        if not isHeader and questId and questId > 0 then
            scannedCount = scannedCount + 1
            
            -- Check if we're tracking this quest
            if QuestieDataCollection.quests[questId] then
                local questData = QuestieDataCollection.quests[questId]
                local updated = false
                
                -- Update basic info if missing
                if not questData.name then
                    questData.name = title
                    updated = true
                end
                
                if not questData.level then
                    questData.level = level
                    updated = true
                end
                
                -- Always update objectives to get current progress
                SelectQuestLogEntry(i)
                local numObjectives = GetNumQuestLeaderBoards(i)
                
                -- If objectives don't exist, create them
                if not questData.objectives or #questData.objectives == 0 then
                    questData.objectives = {}
                    for j = 1, numObjectives do
                        table.insert(questData.objectives, {
                            index = j,
                            text = "",
                            type = "",
                            finished = false,
                            progress = {}
                        })
                    end
                    updated = true
                end
                
                -- Update current objective state
                for j = 1, numObjectives do
                    local text, objectiveType, finished = GetQuestLogLeaderBoard(j, i)
                    if text and questData.objectives[j] then
                        -- Update the current state
                        questData.objectives[j].text = text
                        questData.objectives[j].type = objectiveType
                        questData.objectives[j].finished = finished
                        
                        -- Add to progress history if changed
                        local lastProgress = nil
                        if questData.objectives[j].progress and #questData.objectives[j].progress > 0 then
                            lastProgress = questData.objectives[j].progress[#questData.objectives[j].progress]
                        end
                        
                        if not lastProgress or lastProgress.text ~= text then
                            -- Check if this progress update is related to a recent kill
                            local recentKill = QuestieDataCollector:GetRecentKillInfo()
                            local progressEntry = {
                                text = text,
                                finished = finished,
                                timestamp = time(),
                                coords = QuestieDataCollector:GetPlayerCoordinates()
                            }
                            
                            -- Add kill information if available
                            if recentKill then
                                progressEntry.killedMob = recentKill.name
                            end
                            
                            table.insert(questData.objectives[j].progress, progressEntry)
                            updated = true
                        end
                    end
                end
                
                if updated and numObjectives > 0 then
                    DebugMessage("|cFF00FF00[DATA]|r Updated " .. numObjectives .. " objectives for quest " .. questId, 0, 1, 0)
                end
                
                -- Get quest text if missing
                if not questData.objectivesText then
                    SelectQuestLogEntry(i)
                    local objectivesText = GetQuestLogQuestText()
                    if objectivesText and objectivesText ~= "" then
                        questData.objectivesText = objectivesText
                        updated = true
                    end
                end
                
                if updated then
                    updatedCount = updatedCount + 1
                    DebugMessage("|cFF00FF00[DATA]|r Updated: " .. title .. " (ID: " .. questId .. ")", 0, 1, 0)
                end
                
                -- CRITICAL: Restore quest to active tracking if it should be tracked
                -- This fixes the issue where quests exist in collection but not in _activeTracking
                if not _activeTracking[questId] and not questData.turnedIn then
                    -- Check if quest should be actively tracked
                    if not IsQuestInDatabase(questId) then  -- This respects dev mode
                        _activeTracking[questId] = true
                        restoredCount = restoredCount + 1
                        DebugMessage("|cFF00FF00[DATA]|r Restored to active tracking: " .. title .. " (ID: " .. questId .. ")", 0, 1, 0)
                    end
                end
            else
                -- Quest is in log but we don't have data for it - start tracking if needed
                if not IsQuestInDatabase(questId) then  -- This respects dev mode
                    QuestieDataCollector:TrackQuestAccepted(i, questId)
                    restoredCount = restoredCount + 1
                end
            end
        end
    end
    
    if numEntries == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r No quest log entries found! Make sure your QUEST LOG IS OPEN when running /qdc rescan", 1, 0, 0)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[Data Collector]|r Rescan complete. Scanned " .. scannedCount .. " quests, updated " .. updatedCount .. ", restored " .. restoredCount .. " to active tracking", 0, 1, 1)
    end
end

function QuestieDataCollector:ExportBatchPart(partNumber)
    if not Questie.db.profile.enableDataCollection then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r Data collection is disabled", 1, 0, 0)
        return
    end
    
    -- Collect all quest IDs for export
    local allQuests = {}
    for questId, questData in pairs(QuestieDataCollection.quests) do
        if not IsQuestInDatabase(questId) then
            table.insert(allQuests, questId)
        end
    end
    
    -- Sort quest IDs for consistent output
    table.sort(allQuests)
    
    local questCount = #allQuests
    local maxQuestsPerSubmission = 20  -- Conservative limit for GitHub
    local totalParts = math.ceil(questCount / maxQuestsPerSubmission)
    
    if partNumber < 1 or partNumber > totalParts then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r Invalid part number. Use 1-" .. totalParts, 1, 0, 0)
        return
    end
    
    -- Calculate quest range for this part
    local startIndex = (partNumber - 1) * maxQuestsPerSubmission + 1
    local endIndex = math.min(partNumber * maxQuestsPerSubmission, questCount)
    local questsInThisPart = endIndex - startIndex + 1
    
    -- Create part-specific export
    local exportText = "════════════════════════════════════════════════════════════════\n"
    exportText = exportText .. "                  HOW TO SUBMIT THIS PART                       \n"
    exportText = exportText .. "════════════════════════════════════════════════════════════════\n\n"
    exportText = exportText .. "1. Copy all text below (Ctrl+C to copy)\n"
    exportText = exportText .. "2. Go to: https://github.com/trav346/Questie/issues\n"
    exportText = exportText .. "3. Click 'New Issue'\n"
    exportText = exportText .. "4. Title: Batch Submission - Part " .. partNumber .. " of " .. totalParts .. "\n"
    exportText = exportText .. "5. Paste this entire report in the description\n"
    exportText = exportText .. "6. Click 'Submit new issue'\n"
    exportText = exportText .. "7. Continue with '/qdc export part " .. (partNumber + 1) .. "' for next part\n\n"
    
    exportText = exportText .. "════════════════════════════════════════════════════════════════\n"
    exportText = exportText .. "         QUESTIE DATA COLLECTION EXPORT - PART " .. partNumber .. " of " .. totalParts .. "         \n"
    exportText = exportText .. "════════════════════════════════════════════════════════════════\n\n"
    exportText = exportText .. "Version: " .. (QuestieDataCollection.version or CURRENT_VERSION) .. "\n"
    exportText = exportText .. "Date: " .. date("%Y-%m-%d %H:%M:%S") .. "\n"
    exportText = exportText .. "Part: " .. partNumber .. " of " .. totalParts .. " (" .. questsInThisPart .. " quests in this part)\n"
    exportText = exportText .. "Total Quests: " .. questCount .. " across all parts\n\n"
    
    if Questie.db.profile.dataCollectionDevMode then
        exportText = exportText .. "Collection Mode: DEV MODE - Capturing ALL data\n"
        exportText = exportText .. "  * All quests tracked regardless of database status\n"
        exportText = exportText .. "  * Service NPCs always captured\n"
        exportText = exportText .. "  * Mailboxes & flight masters always logged\n"
    else
        exportText = exportText .. "Collection Mode: NORMAL - Missing quests only\n"
        exportText = exportText .. "  * Only missing quests tracked\n"
        exportText = exportText .. "  * Service NPCs always captured\n"
        exportText = exportText .. "  * Mailboxes & flight masters always logged\n"
    end
    
    exportText = exportText .. "═════════════════════════════════════════════════════════════════\n\n"
    
    -- Export quests for this part
    for i = startIndex, endIndex do
        local questId = allQuests[i]
        local questData = QuestieDataCollection.quests[questId]
        exportText = exportText .. self:FormatQuestExport(questId, questData)
        if i < endIndex then
            exportText = exportText .. "\n" .. string.rep("=", 72) .. "\n\n"
        end
    end
    
    -- Show export window
    self:ShowExportText(exportText)
    
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[Data Collector]|r Exported part " .. partNumber .. " of " .. totalParts .. " (" .. questsInThisPart .. " quests)", 0, 1, 0)
    if partNumber < totalParts then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[Data Collector]|r Next: /qdc export part " .. (partNumber + 1), 1, 1, 0)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[Data Collector]|r All parts exported! Submit each as a separate GitHub issue.", 0, 1, 0)
    end
end

function QuestieDataCollector:ExportAreaData(zoneName)
    if not zoneName then
        zoneName = GetRealZoneText() or "Current Area"
    end
    
    local export = "=== AREA DATA EXPORT ===\n"
    export = export .. "Version: " .. (QuestieDataCollection.version or "Unknown") .. "\n"
    export = export .. "Zone: " .. zoneName .. "\n"
    export = export .. "Export Date: " .. date("%Y-%m-%d %H:%M:%S") .. "\n\n"
    
    local hasData = false
    
    -- Service NPCs in the zone
    local zoneServiceNPCs = {}
    for npcId, npcData in pairs(QuestieDataCollection.serviceNPCs) do
        for _, location in ipairs(npcData.locations) do
            if location.zone == zoneName then
                zoneServiceNPCs[npcId] = npcData
                break
            end
        end
    end
    
    if next(zoneServiceNPCs) then
        hasData = true
        export = export .. "SERVICE NPCs:\n"
        for npcId, npcData in pairs(zoneServiceNPCs) do
            export = export .. "  " .. (npcData.name or "Unknown") .. " (ID: " .. npcId .. ")\n"
            export = export .. "    Services: " .. table.concat(npcData.services, ", ") .. "\n"
            for _, loc in ipairs(npcData.locations) do
                if loc.zone == zoneName and loc.x and loc.y then
                    export = export .. "    Location: " .. string.format("%.1f, %.1f", loc.x, loc.y) .. "\n"
                end
            end
            export = export .. "\n"
        end
    end
    
    -- Gathering nodes in the zone
    local zoneGatheringNodes = {}
    for locKey, nodeData in pairs(QuestieDataCollection.gatheringNodes) do
        if nodeData.zone == zoneName then
            zoneGatheringNodes[locKey] = nodeData
        end
    end
    
    if next(zoneGatheringNodes) then
        hasData = true
        export = export .. "GATHERING NODES:\n"
        local herbNodes = {}
        local oreNodes = {}
        for locKey, nodeData in pairs(zoneGatheringNodes) do
            if nodeData.type == "herb" then
                table.insert(herbNodes, nodeData)
            elseif nodeData.type == "ore" then
                table.insert(oreNodes, nodeData)
            end
        end
        
        if #herbNodes > 0 then
            export = export .. "  Herbs:\n"
            for _, node in ipairs(herbNodes) do
                export = export .. "    " .. node.name .. " at " .. string.format("%.1f, %.1f", node.x, node.y) .. 
                         " (gathered " .. node.timesGathered .. " times)\n"
            end
            export = export .. "\n"
        end
        
        if #oreNodes > 0 then
            export = export .. "  Ore Veins:\n"
            for _, node in ipairs(oreNodes) do
                export = export .. "    " .. node.name .. " at " .. string.format("%.1f, %.1f", node.x, node.y) .. 
                         " (mined " .. node.timesGathered .. " times)\n"
            end
            export = export .. "\n"
        end
    end
    
    -- Treasure chests in the zone
    local zoneTreasures = {}
    for locKey, treasureData in pairs(QuestieDataCollection.treasureChests) do
        if treasureData.zone == zoneName then
            zoneTreasures[locKey] = treasureData
        end
    end
    
    if next(zoneTreasures) then
        hasData = true
        export = export .. "TREASURE CHESTS:\n"
        for locKey, treasure in pairs(zoneTreasures) do
            export = export .. "  " .. treasure.name .. " at " .. string.format("%.1f, %.1f", treasure.x, treasure.y) .. 
                     " (looted " .. treasure.timesLooted .. " times)\n"
        end
        export = export .. "\n"
    end
    
    -- Mailboxes in the zone
    local zoneMailboxes = {}
    for locKey, mailboxData in pairs(QuestieDataCollection.mailboxes) do
        if mailboxData.zone == zoneName then
            zoneMailboxes[locKey] = mailboxData
        end
    end
    
    if next(zoneMailboxes) then
        hasData = true
        export = export .. "MAILBOXES:\n"
        for locKey, mailbox in pairs(zoneMailboxes) do
            export = export .. "  Mailbox at " .. string.format("%.1f, %.1f", mailbox.x, mailbox.y) .. 
                     " (used " .. mailbox.timesUsed .. " times)\n"
        end
        export = export .. "\n"
    end
    
    if not hasData then
        export = export .. "No area data collected for " .. zoneName .. " yet.\n"
        export = export .. "Enable data collection with /qdc enable and explore the area to gather data.\n"
    end
    
    -- Save to export frame for copying (reuse quest export frame)
    if not QuestieDataCollectorExportFrame then
        -- Frame will be created by quest export system if not exists
        QuestieDataCollector:ExportQuest(0) -- This will create the frame but fail safely
    end
    
    if QuestieDataCollectorExportFrame then
        QuestieDataCollectorExportFrame.title:SetText("Area Data Export - " .. zoneName)
        QuestieDataCollectorExportFrame.editBox:SetText(export)
        QuestieDataCollectorExportFrame.editBox:HighlightText()
        QuestieDataCollectorExportFrame:Show()
        
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[Data Collector]|r Area data export ready. Copy from the window that opened.", 0, 1, 0)
    else
        -- Fallback: print to chat
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[Data Collector]|r Area data for " .. zoneName .. ":", 0, 1, 0)
        for line in export:gmatch("[^\n]+") do
            DEFAULT_CHAT_FRAME:AddMessage(line, 1, 1, 1)
        end
    end
end

function QuestieDataCollector:ExportServiceNPCs()
    -- Check if we have any service NPCs
    if not QuestieDataCollection or not QuestieDataCollection.serviceNPCs or not next(QuestieDataCollection.serviceNPCs) then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r No service NPCs captured yet!", 1, 0, 0)
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[Data Collector]|r Interact with vendors, trainers, flight masters, etc. to capture them.", 1, 1, 0)
        return
    end
    
    -- Build export text
    local export = "\n"
    export = export .. "════════════════════════════════════════════════════════════════\n"
    export = export .. "                   SERVICE NPC EXPORT                          \n"
    export = export .. "════════════════════════════════════════════════════════════════\n\n"
    
    -- Count by service type
    local serviceTypes = {}
    local totalNPCs = 0
    
    for npcId, npcData in pairs(QuestieDataCollection.serviceNPCs) do
        totalNPCs = totalNPCs + 1
        for _, service in ipairs(npcData.services) do
            serviceTypes[service] = (serviceTypes[service] or 0) + 1
        end
    end
    
    export = export .. "Total Service NPCs: " .. totalNPCs .. "\n"
    export = export .. "────────────────────────────────────────────────────────────────\n\n"
    
    -- Show counts by type
    export = export .. "> SERVICE TYPES:\n"
    for service, count in pairs(serviceTypes) do
        export = export .. "  " .. service .. ": " .. count .. "\n"
    end
    export = export .. "\n"
    
    -- Export each NPC grouped by service type
    local serviceGroups = {
        ["flight_master"] = {},
        ["vendor"] = {},
        ["trainer"] = {},
        ["banker"] = {},
        ["guild_banker"] = {},
        ["innkeeper"] = {},
        ["stable_master"] = {},
        ["battlemaster"] = {},
        ["auctioneer"] = {}
    }
    
    -- Group NPCs by their primary service
    for npcId, npcData in pairs(QuestieDataCollection.serviceNPCs) do
        local primaryService = npcData.services[1] or "unknown"
        if not serviceGroups[primaryService] then
            serviceGroups[primaryService] = {}
        end
        table.insert(serviceGroups[primaryService], {id = npcId, data = npcData})
    end
    
    -- Export each group
    for service, npcs in pairs(serviceGroups) do
        if #npcs > 0 then
            export = export .. "> " .. string.upper(string.gsub(service, "_", " ")) .. "S:\n"
            
            -- Sort by NPC ID
            table.sort(npcs, function(a, b) return a.id < b.id end)
            
            for _, npc in ipairs(npcs) do
                export = export .. "  " .. (npc.data.name or "Unknown") .. " (ID: " .. npc.id .. ")\n"
                
                -- Show all services if NPC provides multiple
                if #npc.data.services > 1 then
                    export = export .. "    Also provides: " .. table.concat(npc.data.services, ", ") .. "\n"
                end
                
                -- Show locations
                if npc.data.locations and #npc.data.locations > 0 then
                    for _, loc in ipairs(npc.data.locations) do
                        if loc.x and loc.y then
                            export = export .. "    Location: " .. string.format("%.1f, %.1f", loc.x, loc.y) .. " in " .. (loc.zone or "Unknown") .. "\n"
                        end
                    end
                end
            end
            export = export .. "\n"
        end
    end
    
    -- Add footer
    export = export .. "════════════════════════════════════════════════════════════════\n"
    export = export .. "                    END OF SERVICE NPCS                        \n"
    export = export .. "════════════════════════════════════════════════════════════════\n\n"
    
    -- Create export window
    if not QuestieDataCollectorExportFrame then
        QuestieDataCollector:ShowExportWindow(0) -- Create the frame
    end
    
    if QuestieDataCollectorExportFrame then
        QuestieDataCollectorExportFrame.title:SetText("Service NPC Export")
        QuestieDataCollectorExportFrame.editBox:SetText(export)
        QuestieDataCollectorExportFrame.editBox:HighlightText()
        QuestieDataCollectorExportFrame:Show()
        
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[Data Collector]|r Service NPC data ready for export!", 0, 1, 0)
    else
        -- Fallback to chat
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[Data Collector]|r Service NPCs:", 0, 1, 0)
        for line in export:gmatch("[^\n]+") do
            DEFAULT_CHAT_FRAME:AddMessage(line, 1, 1, 1)
        end
    end
end

function QuestieDataCollector:ClearData()
    -- Initialize if nil
    if not QuestieDataCollection then
        QuestieDataCollection = {}
    end
    
    -- Clear all data
    QuestieDataCollection.quests = {}
    QuestieDataCollection.mismatches = {}
    QuestieDataCollection.serviceNPCs = {}
    QuestieDataCollection.mailboxes = {}
    QuestieDataCollection.gatheringNodes = {}
    QuestieDataCollection.treasureChests = {}
    QuestieDataCollection.flightMasters = {}
    
    -- Clear local tracking
    _activeTracking = {}
    _dataMismatches = {}
    _serviceNPCs = {}
    _mailboxes = {}
    _gatheringNodes = {}
    _treasureChests = {}
    _flightMasters = {}
    
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r All collected data cleared.", 1, 0, 0)
    
    -- Check if collection is enabled
    if Questie.db.profile.enableDataCollection then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[Data Collector]|r Data collection is ENABLED - ready to collect new data.", 0, 1, 0)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[Data Collector]|r Data collection is DISABLED - use /qdc enable to start collecting.", 1, 1, 0)
    end
end

-- Slash command handler
SLASH_QUESTIEDATACOLLECTOR1 = "/qdc"
SlashCmdList["QUESTIEDATACOLLECTOR"] = function(msg)
    local args = {strsplit(" ", msg)}
    local cmd = args[1] and string.lower(args[1]) or ""
    
    if cmd == "enable" then
        Questie.db.profile.enableDataCollection = true
        QuestieDataCollector:Initialize()
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[Data Collector]|r Enabled", 0, 1, 0)
    elseif cmd == "disable" then
        Questie.db.profile.enableDataCollection = false
        QuestieDataCollector:RestoreTooltipSettings()
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r Disabled", 1, 0, 0)
    elseif cmd == "status" then
        QuestieDataCollector:ShowStatus()
    elseif cmd == "show" then
        QuestieDataCollector:ShowTrackedQuests()
    elseif cmd == "export" then
        local questId = tonumber(args[2])
        -- Wrap export functions in pcall to prevent third-party addon conflicts
        local success, err = pcall(function()
            if questId then
                -- Export specific quest if ID provided
                QuestieDataCollector:ExportQuest(questId)
            elseif args[2] == "part" and tonumber(args[3]) then
                -- Export specific part of batch submission
                local partNumber = tonumber(args[3])
                QuestieDataCollector:ExportBatchPart(partNumber)
            else
                -- Show quest selection window for export
                QuestieDataCollector:ShowExportWindow()
            end
        end)
        
        if not success then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[QUESTIE]|r Export failed due to addon conflict. Try disabling Skada addon temporarily.", 1, 0, 0)
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFFFF[QUESTIE]|r The error was: " .. tostring(err), 1, 1, 1)
        end
    elseif cmd == "services" or cmd == "service" then
        -- Export all service NPCs
        QuestieDataCollector:ExportServiceNPCs()
    elseif cmd == "area" then
        local zoneName = args[2]
        if zoneName then
            -- Export specific zone if provided
            QuestieDataCollector:ExportAreaData(zoneName)
        else
            -- Export current zone
            QuestieDataCollector:ExportAreaData()
        end
    elseif cmd == "clear" then
        QuestieDataCollector:ClearData()
    elseif cmd == "rescan" then
        QuestieDataCollector:RescanQuestLog()
    elseif cmd == "questgiver" then
        local questId = tonumber(args[2])
        if questId then
            QuestieDataCollector:CaptureQuestGiver(questId)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r Usage: /qdc questgiver <questId> (target NPC first)", 1, 0, 0)
        end
    elseif cmd == "turnin" then
        local questId = tonumber(args[2])
        if questId then
            QuestieDataCollector:ManualTurnIn(questId)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r Usage: /qdc turnin <questId> (target NPC first)", 1, 0, 0)
        end
    elseif cmd == "debug" then
        -- Check for specific quest ID
        local questId = tonumber(args[2])
        if questId then
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF=== Quest " .. questId .. " Debug ===|r", 0, 1, 1)
            
            -- Show dev mode status
            local devMode = Questie.db.profile.dataCollectionDevMode
            DEFAULT_CHAT_FRAME:AddMessage("Dev Mode: " .. (devMode and "|cFF00FF00ENABLED|r" or "|cFFFF0000DISABLED|r"), 1, 1, 1)
            
            -- Check if in database
            local inDB = IsQuestInDatabase(questId)
            DEFAULT_CHAT_FRAME:AddMessage("IsQuestInDatabase(): " .. tostring(inDB), 1, 1, 1)
            
            -- Check raw database quest
            local dbQuest = QuestieDB.GetQuest(questId)
            if dbQuest then
                DEFAULT_CHAT_FRAME:AddMessage("Raw DB Quest Name: '" .. (dbQuest.name or "nil") .. "'", 1, 1, 1)
            else
                DEFAULT_CHAT_FRAME:AddMessage("Raw DB Quest: nil", 1, 1, 1)
            end
            
            -- Check if actively tracking
            local activelyTracking = _activeTracking[questId] and "YES" or "NO"
            DEFAULT_CHAT_FRAME:AddMessage("In _activeTracking: " .. activelyTracking, 1, 1, 1)
            
            -- Check collected data
            local questData = QuestieDataCollection.quests[questId]
            if questData then
                DEFAULT_CHAT_FRAME:AddMessage("Collected Data: YES ('" .. (questData.name or "no name") .. "')", 1, 1, 1)
                DEFAULT_CHAT_FRAME:AddMessage("Kill Count: " .. (questData.kills and #questData.kills or 0), 1, 1, 1)
                DEFAULT_CHAT_FRAME:AddMessage("Turned In: " .. (questData.turnedIn and "YES" or "NO"), 1, 1, 1)
            else
                DEFAULT_CHAT_FRAME:AddMessage("Collected Data: NO", 1, 1, 1)
            end
            
            return
        end
        
        -- Toggle debug messages
        Questie.db.profile.debugDataCollector = not Questie.db.profile.debugDataCollector
        if Questie.db.profile.debugDataCollector then
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[Data Collector]|r Debug messages enabled", 0, 1, 0)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r Debug messages disabled", 1, 0, 0)
        end
        DEFAULT_CHAT_FRAME:AddMessage("Usage: /qdc debug [questId] - Debug specific quest", 0.7, 0.7, 0.7)
    elseif cmd == "forcetrack" then
        local questId = tonumber(args[2])
        if questId then
            -- Force add to active tracking regardless of conditions
            _activeTracking[questId] = true
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[Data Collector]|r FORCED quest " .. questId .. " into active tracking", 0, 1, 0)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r Usage: /qdc forcetrack <questId>", 1, 0, 0)
        end
    elseif cmd == "restore" then
        local questId = tonumber(args[2])
        if questId and QuestieDataCollection.quests[questId] then
            local questData = QuestieDataCollection.quests[questId]
            if not questData.turnedIn and not IsQuestInDatabase(questId) then
                _activeTracking[questId] = true
                DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[Data Collector]|r Restored quest " .. questId .. " (" .. (questData.name or "Unknown") .. ") to active tracking", 0, 1, 0)
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r Cannot restore quest " .. questId .. " - either turned in or in database", 1, 0, 0)
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Data Collector]|r Quest " .. (questId or "invalid") .. " not found in collected data", 1, 0, 0)
        end
    elseif cmd == "devmode" then
        Questie.db.profile.dataCollectionDevMode = not Questie.db.profile.dataCollectionDevMode
        if Questie.db.profile.dataCollectionDevMode then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[DEV MODE ENABLED]|r Now collecting ALL quests (including database quests)", 1, 0, 0)
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFAA00Note:|r Use /reload to apply to existing tracked quests", 1, 0.7, 0)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[DEV MODE DISABLED]|r Now only collecting missing quests", 0, 1, 0)
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFAA00Note:|r Use /reload to stop tracking database quests", 1, 0.7, 0)
        end
    elseif cmd == "validate" then
        local questId = tonumber(args[2])
        if questId then
            QuestieDataCollector:ValidateQuest(questId)
        else
            QuestieDataCollector:ValidateAllQuests()
        end
    elseif cmd == "recompile" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[Data Collector]|r Forcing database recompile and reloading UI...", 0, 1, 0)
        -- Set the compile flag to false
        if Questie.IsSoD then
            Questie.db.global.sod.dbIsCompiled = false
        else
            Questie.db.global.dbIsCompiled = false
        end
        -- Immediately reload the UI
        ReloadUI()
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF=== Questie Data Collector Commands ===|r", 0, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc status - Show collection status", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc enable - Enable data collection", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc disable - Disable data collection", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc show - Show all tracked quests", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc export [questId] - Export quest data", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc export part [X] - Export part X of large batch submission", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc service - Export all service NPCs", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc area [zoneName] - Export area data (service NPCs, gathering nodes, treasures)", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc questgiver <questId> - Manually capture quest giver (target NPC first)", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc turnin <questId> - Manually capture turn-in NPC (target NPC first)", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc clear - Clear all collected data", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc rescan - Re-scan quest log for missing data (QUEST LOG MUST BE OPEN)", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc restore <questId> - Manually restore quest to active tracking", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc recompile - Force database recompile (reloads UI)", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc validate [questId] - Validate collected quest data", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc debug [questId] - Toggle debug messages or debug specific quest", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc devmode - Toggle dev mode (collect ALL quest data)", 1, 1, 1)
    end
end

--- Check if data collection is currently enabled
function QuestieDataCollector:IsDataCollectionEnabled()
    return Questie.db and Questie.db.profile and Questie.db.profile.enableDataCollection or false
end

--- Prompt user to enable data collection (only shows once per character)
--- @param questId number The quest ID that triggered this prompt
--- @param questName string The quest name for context
function QuestieDataCollector:PromptForDataCollection(questId, questName)
    -- Check if user has already been prompted and made a choice
    if Questie.db.profile.dataCollectionPrompted ~= nil then
        return -- User already made a choice, don't prompt again
    end
    
    -- Mark that we've prompted so it only happens once
    Questie.db.profile.dataCollectionPrompted = true
    
    -- Create popup frame for data collection prompt
    StaticPopup_Show("QUESTIE_DATA_COLLECTION_PROMPT", questName or "this quest", questId or "")
end

-- Static popup definition for data collection prompt
StaticPopupDialogs["QUESTIE_DATA_COLLECTION_PROMPT"] = {
    text = "You just accepted '%s' which has incomplete data!\n\nWould you like to enable data collection to help complete quest data for the community?\n\n• Your progress will be tracked\n• No personal information is shared\n• Data helps improve Questie for everyone\n• You can disable this anytime with /qdc disable",
    button1 = "Yes, Enable Collection",
    button2 = "No Thanks", 
    OnAccept = function()
        -- Enable data collection
        Questie.db.profile.enableDataCollection = true
        if QuestieDataCollector and QuestieDataCollector.Initialize then
            QuestieDataCollector:Initialize()
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[Questie] Data collection enabled! Thank you for contributing to the community.|r")
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[Questie] Use '/qdc status' to check collection status, '/qdc disable' to turn off.|r")
    end,
    OnCancel = function()
        -- User declined - we won't prompt again due to dataCollectionPrompted being set to true
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[Questie] Data collection remains disabled. You can enable it anytime with '/qdc enable'.|r")
    end,
    timeout = 0, -- No auto-timeout
    whileDead = true,
    hideOnEscape = false, -- Force user to make a choice
    showAlert = true, -- Make it more prominent
}