---@class QuestieDataValidator
local QuestieDataValidator = {}

-- Validation rules and sanity checks for collected data
local VALID_ZONES = {
    [1] = "Dun Morogh",
    [14] = "Durotar", 
    [15] = "Dustwallow Marsh",
    [16] = "Azshara",
    [17] = "The Barrens",
    -- Add more valid zones as needed
}

-- NPC ID ranges for WoW 3.3.5
local VALID_NPC_ID_MIN = 1
local VALID_NPC_ID_MAX = 100000  -- Adjust based on actual data

-- Quest ID ranges for Project Epoch
local VALID_QUEST_ID_MIN = 1
local VALID_QUEST_ID_MAX = 50000

-- Item ID ranges
local VALID_ITEM_ID_MIN = 1
local VALID_ITEM_ID_MAX = 100000

-- Coordinate validation
local function ValidateCoordinates(coords)
    if not coords then return false, "No coordinates provided" end
    if not coords.x or not coords.y then return false, "Missing x or y coordinate" end
    
    -- Check coordinate ranges (0-100)
    if coords.x < 0 or coords.x > 100 then 
        return false, string.format("X coordinate out of range: %.2f", coords.x)
    end
    if coords.y < 0 or coords.y > 100 then
        return false, string.format("Y coordinate out of range: %.2f", coords.y) 
    end
    
    -- Check for suspicious coordinates
    if coords.x == 0 and coords.y == 0 then
        return false, "Coordinates at origin (0,0) - likely invalid"
    end
    
    return true
end

-- NPC validation
local function ValidateNPC(npcData)
    if not npcData then return false, "No NPC data" end
    if not npcData.id then return false, "No NPC ID" end
    
    -- Validate ID range
    if npcData.id < VALID_NPC_ID_MIN or npcData.id > VALID_NPC_ID_MAX then
        return false, string.format("NPC ID out of range: %d", npcData.id)
    end
    
    -- Validate name
    if not npcData.name or npcData.name == "" then
        return false, "NPC has no name"
    end
    
    -- Validate coordinates if present
    if npcData.coords then
        local valid, err = ValidateCoordinates(npcData.coords)
        if not valid then
            return false, "NPC coordinates invalid: " .. err
        end
    end
    
    return true
end

-- Quest validation
local function ValidateQuest(questData)
    if not questData then return false, "No quest data" end
    if not questData.id then return false, "No quest ID" end
    
    -- Validate ID range
    if questData.id < VALID_QUEST_ID_MIN or questData.id > VALID_QUEST_ID_MAX then
        return false, string.format("Quest ID out of range: %d", questData.id)
    end
    
    -- Check for required fields
    if not questData.name or questData.name == "" then
        return false, "Quest has no name"
    end
    
    -- Validate quest giver if present
    if questData.questGiver then
        local valid, err = ValidateNPC(questData.questGiver)
        if not valid then
            return false, "Invalid quest giver: " .. err
        end
    end
    
    -- Validate turn-in NPC if present (check both field names)
    local turnInNpc = questData.turnIn or questData.turnInNpc
    if turnInNpc then
        local valid, err = ValidateNPC(turnInNpc)
        if not valid then
            return false, "Invalid turn-in NPC: " .. err
        end
    end
    
    -- Check for data completeness
    local warnings = {}
    if not questData.questGiver then
        table.insert(warnings, "Missing quest giver")
    end
    if not questData.turnIn and not questData.turnInNpc and not questData.autoComplete then
        table.insert(warnings, "Missing turn-in NPC")
    end
    if not questData.objectives or #questData.objectives == 0 then
        table.insert(warnings, "No objectives captured")
    elseif questData.objectives then
        -- Check if objectives have text
        for i, obj in ipairs(questData.objectives) do
            if not obj.text or obj.text == "" then
                table.insert(warnings, "Objective " .. i .. " has no text")
            end
        end
    end
    if questData.wasAlreadyAccepted then
        table.insert(warnings, "Quest was already in log when collection started")
    end
    
    -- Validate prerequisite tracking data
    if questData.potentialPrerequisites and type(questData.potentialPrerequisites) ~= "table" then
        table.insert(warnings, "Invalid potential prerequisites format")
    end
    if questData.unlocksQuests and type(questData.unlocksQuests) ~= "table" then
        table.insert(warnings, "Invalid unlocks quests format")
    end
    
    -- Validate commission quest data
    if questData.isCommission then
        if not questData.playerProfessions then
            table.insert(warnings, "Commission quest but no profession data captured")
        elseif type(questData.playerProfessions) ~= "table" then
            table.insert(warnings, "Invalid profession data format")
        elseif #questData.playerProfessions == 0 then
            table.insert(warnings, "Commission quest accepted with no professions")
        end
    end
    
    -- Check if quest is actually complete
    if questData.turnedIn or questData.turnIn or questData.turnInNpc then
        -- Quest has been turned in or has turn-in data
        if #warnings <= 1 then -- Allow one minor warning for completed quests
            -- Mark as complete if it has most required data
            questData.isComplete = true
        end
    end
    
    return true, nil, warnings
end

-- Profession validation
local function ValidateProfession(profData)
    if not profData then return false, "No profession data" end
    if not profData.name or profData.name == "" then
        return false, "Profession has no name"
    end
    if not profData.skillLevel then
        return false, "Profession has no skill level"
    end
    if not profData.maxSkillLevel then
        return false, "Profession has no max skill level"
    end
    if profData.skillLevel < 0 or profData.skillLevel > profData.maxSkillLevel then
        return false, string.format("Invalid skill level: %d/%d", profData.skillLevel, profData.maxSkillLevel)
    end
    return true
end

-- Item validation
local function ValidateItem(itemData)
    if not itemData then return false, "No item data" end
    if not itemData.id then return false, "No item ID" end
    
    -- Validate ID range
    if itemData.id < VALID_ITEM_ID_MIN or itemData.id > VALID_ITEM_ID_MAX then
        return false, string.format("Item ID out of range: %d", itemData.id)
    end
    
    -- Validate name
    if not itemData.name or itemData.name == "" then
        return false, "Item has no name"
    end
    
    return true
end

-- Main validation function for a complete quest submission
function QuestieDataValidator:ValidateQuestSubmission(questData)
    local errors = {}
    local warnings = {}
    
    -- Validate the quest itself
    local valid, err, questWarnings = ValidateQuest(questData)
    if not valid then
        table.insert(errors, err)
    end
    if questWarnings then
        for _, warning in ipairs(questWarnings) do
            table.insert(warnings, warning)
        end
    end
    
    -- Validate all NPCs in mobs
    if questData.mobs then
        for mobId, mobData in pairs(questData.mobs) do
            local valid, err = ValidateNPC(mobData)
            if not valid then
                table.insert(errors, "Mob " .. mobId .. ": " .. err)
            end
        end
    end
    
    -- Validate all items
    if questData.items then
        for itemId, itemData in pairs(questData.items) do
            local valid, err = ValidateItem(itemData)
            if not valid then
                table.insert(errors, "Item " .. itemId .. ": " .. err)
            end
            
            -- Validate item sources
            if itemData.sources then
                for _, source in ipairs(itemData.sources) do
                    if source.type == "npc" and source.id then
                        if source.id < VALID_NPC_ID_MIN or source.id > VALID_NPC_ID_MAX then
                            table.insert(warnings, string.format("Item %d has invalid source NPC ID: %d", itemId, source.id))
                        end
                    end
                end
            else
                table.insert(warnings, string.format("Item %d has no source information", itemId))
            end
        end
    end
    
    -- Validate profession data if present
    if questData.playerProfessions then
        for _, profData in ipairs(questData.playerProfessions) do
            local valid, err = ValidateProfession(profData)
            if not valid then
                table.insert(errors, "Profession data: " .. err)
            end
        end
    end
    
    -- Validate prerequisite data
    if questData.potentialPrerequisites then
        if type(questData.potentialPrerequisites) ~= "table" then
            table.insert(errors, "potentialPrerequisites must be a table")
        else
            for _, prereqId in ipairs(questData.potentialPrerequisites) do
                if type(prereqId) ~= "number" then
                    table.insert(errors, "Invalid prerequisite ID: " .. tostring(prereqId))
                elseif prereqId < VALID_QUEST_ID_MIN or prereqId > VALID_QUEST_ID_MAX then
                    table.insert(errors, string.format("Prerequisite quest ID out of range: %d", prereqId))
                end
            end
        end
    end
    
    if questData.unlocksQuests then
        if type(questData.unlocksQuests) ~= "table" then
            table.insert(errors, "unlocksQuests must be a table")
        else
            for _, questName in ipairs(questData.unlocksQuests) do
                if type(questName) ~= "string" or questName == "" then
                    table.insert(warnings, "Invalid unlocked quest name: " .. tostring(questName))
                end
            end
        end
    end
    
    -- Validate objects
    if questData.objects then
        for objName, objData in pairs(questData.objects) do
            if objData.locations then
                for locKey, loc in pairs(objData.locations) do
                    -- Location can be either {x=n, y=n} or {n, n} format
                    local coords
                    if loc.x and loc.y then
                        coords = {x = loc.x, y = loc.y}
                    elseif loc[1] and loc[2] then
                        coords = {x = loc[1], y = loc[2]}
                    else
                        -- Try to parse from the key if it's in "x,y" format
                        local x, y = string.match(locKey, "^([%d%.]+),([%d%.]+)$")
                        if x and y then
                            coords = {x = tonumber(x), y = tonumber(y)}
                        else
                            table.insert(errors, "Object '" .. objName .. "': Invalid location format")
                            coords = nil
                        end
                    end
                    
                    if coords then
                        local valid, err = ValidateCoordinates(coords)
                        if not valid then
                            table.insert(errors, "Object '" .. objName .. "': " .. err)
                        end
                    end
                end
            end
        end
    end
    
    -- Determine if data is acceptable
    local isValid = #errors == 0
    local isComplete = #warnings == 0
    
    return {
        valid = isValid,
        complete = isComplete,
        errors = errors,
        warnings = warnings,
        recommendation = DetermineRecommendation(isValid, isComplete, warnings)
    }
end

-- Determine recommendation based on validation results
function DetermineRecommendation(isValid, isComplete, warnings)
    if not isValid then
        return "REJECT", "Data contains critical errors and cannot be used"
    end
    
    if not isComplete then
        -- Check severity of warnings
        local hasCriticalWarning = false
        for _, warning in ipairs(warnings) do
            if string.find(warning, "Missing quest giver") or 
               string.find(warning, "Missing turn-in NPC") or
               string.find(warning, "already in log") then
                hasCriticalWarning = true
                break
            end
        end
        
        if hasCriticalWarning then
            return "PARTIAL", "Data is incomplete but may contain useful information"
        else
            return "REVIEW", "Data has minor issues that should be reviewed"
        end
    end
    
    return "ACCEPT", "Data is complete and valid"
end

-- Check if coordinates are suspiciously close to another set
function QuestieDataValidator:CheckCoordinateDuplication(coords1, coords2, threshold)
    threshold = threshold or 0.5  -- Default threshold of 0.5 units
    
    if not coords1 or not coords2 then return false end
    if not coords1.x or not coords1.y or not coords2.x or not coords2.y then return false end
    
    local distance = math.sqrt((coords1.x - coords2.x)^2 + (coords1.y - coords2.y)^2)
    return distance < threshold
end

-- Validate that an NPC ID matches expected patterns
function QuestieDataValidator:ValidateNPCGuid(guid)
    if not guid then return false, "No GUID provided" end
    
    -- WoW 3.3.5 GUID format: 0xF13000085800126C
    if not string.match(guid, "^0x%x+$") then
        return false, "Invalid GUID format"
    end
    
    -- Extract and validate NPC ID
    local npcId = tonumber(guid:sub(6, 12), 16)
    if not npcId then
        return false, "Could not extract NPC ID from GUID"
    end
    
    if npcId < VALID_NPC_ID_MIN or npcId > VALID_NPC_ID_MAX then
        return false, string.format("Extracted NPC ID out of range: %d", npcId)
    end
    
    return true, npcId
end

-- Export validation results as formatted string
function QuestieDataValidator:FormatValidationReport(results)
    local report = {}
    
    table.insert(report, "=== DATA VALIDATION REPORT ===")
    table.insert(report, "")
    
    -- Status
    table.insert(report, "Status: " .. (results.valid and "VALID" or "INVALID"))
    table.insert(report, "Completeness: " .. (results.complete and "COMPLETE" or "INCOMPLETE"))
    table.insert(report, "")
    
    -- Recommendation
    local action, reason = results.recommendation
    table.insert(report, "Recommendation: " .. action)
    table.insert(report, "Reason: " .. reason)
    table.insert(report, "")
    
    -- Errors
    if #results.errors > 0 then
        table.insert(report, "ERRORS (" .. #results.errors .. "):")
        for _, error in ipairs(results.errors) do
            table.insert(report, "  • " .. error)
        end
        table.insert(report, "")
    end
    
    -- Warnings
    if #results.warnings > 0 then
        table.insert(report, "WARNINGS (" .. #results.warnings .. "):")
        for _, warning in ipairs(results.warnings) do
            table.insert(report, "  • " .. warning)
        end
        table.insert(report, "")
    end
    
    table.insert(report, "=== END REPORT ===")
    
    return table.concat(report, "\n")
end

_G.QuestieDataValidator = QuestieDataValidator
return QuestieDataValidator