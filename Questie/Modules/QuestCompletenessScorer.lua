---@class QuestCompletenessScorer
local QuestCompletenessScorer = QuestieLoader:CreateModule("QuestCompletenessScorer")

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")

-- Quest completeness categories and their impact
local COMPLETENESS_WEIGHTS = {
    HAS_NAME = 10,           -- Basic quest name exists
    HAS_STARTER_NPC = 20,    -- Quest giver NPC defined
    HAS_FINISHER_NPC = 15,   -- Turn-in NPC defined  
    HAS_OBJECTIVES = 25,     -- Quest objectives defined
    HAS_STARTER_SPAWNS = 15, -- Quest giver spawn locations
    HAS_FINISHER_SPAWNS = 10,-- Turn-in NPC spawn locations
    HAS_PROPER_LEVEL = 5     -- Appropriate quest level
}

local MAX_COMPLETENESS_SCORE = 100

-- Categories for quest states
QuestCompletenessScorer.COMPLETENESS_STATES = {
    COMPLETE = "complete",      -- 90-100% complete
    MOSTLY_COMPLETE = "mostly", -- 70-89% complete  
    PARTIAL = "partial",        -- 40-69% complete
    MINIMAL = "minimal",        -- 10-39% complete
    MISSING = "missing"         -- 0-9% complete (essentially not in DB)
}

-- User-friendly prefixes based on completeness
QuestCompletenessScorer.COMPLETENESS_PREFIXES = {
    [QuestCompletenessScorer.COMPLETENESS_STATES.COMPLETE] = "",
    [QuestCompletenessScorer.COMPLETENESS_STATES.MOSTLY_COMPLETE] = "",
    [QuestCompletenessScorer.COMPLETENESS_STATES.PARTIAL] = "[EpochDB Partial] ",
    [QuestCompletenessScorer.COMPLETENESS_STATES.MINIMAL] = "[EpochDB Minimal] ",
    [QuestCompletenessScorer.COMPLETENESS_STATES.MISSING] = "[EpochDB Missing] "
}

---Analyze quest completeness and return detailed scoring
---@param questId number
---@return table completenessInfo
function QuestCompletenessScorer:AnalyzeQuestCompleteness(questId)
    local quest = QuestieDB.GetQuest(questId)
    if not quest then
        return {
            score = 0,
            percentage = 0,
            state = self.COMPLETENESS_STATES.MISSING,
            prefix = self.COMPLETENESS_PREFIXES[self.COMPLETENESS_STATES.MISSING],
            missingFields = {"name", "startedBy", "finishedBy", "objectives", "spawns"},
            availableFields = {},
            canShowPins = false,
            canTrackObjectives = false
        }
    end
    
    local score = 0
    local availableFields = {}
    local missingFields = {}
    
    -- Check quest name
    if quest.name and quest.name ~= "" and not string.find(quest.name, "Quest %d+$") then
        score = score + COMPLETENESS_WEIGHTS.HAS_NAME
        table.insert(availableFields, "name")
    else
        table.insert(missingFields, "name")
    end
    
    -- Check starter NPC
    if quest.startedBy and quest.startedBy[1] and #quest.startedBy[1] > 0 then
        score = score + COMPLETENESS_WEIGHTS.HAS_STARTER_NPC
        table.insert(availableFields, "startedBy")
        
        -- Check starter spawns
        local starterNpcId = quest.startedBy[1][1]
        local npcData = QuestieDB.GetNPC(starterNpcId)
        if npcData and npcData.spawns and next(npcData.spawns) then
            score = score + COMPLETENESS_WEIGHTS.HAS_STARTER_SPAWNS
            table.insert(availableFields, "starterSpawns")
        else
            table.insert(missingFields, "starterSpawns")
        end
    else
        table.insert(missingFields, "startedBy")
        table.insert(missingFields, "starterSpawns")
    end
    
    -- Check finisher NPC
    if quest.finishedBy and quest.finishedBy[1] and #quest.finishedBy[1] > 0 then
        score = score + COMPLETENESS_WEIGHTS.HAS_FINISHER_NPC
        table.insert(availableFields, "finishedBy")
        
        -- Check finisher spawns  
        local finisherNpcId = quest.finishedBy[1][1]
        local npcData = QuestieDB.GetNPC(finisherNpcId)
        if npcData and npcData.spawns and next(npcData.spawns) then
            score = score + COMPLETENESS_WEIGHTS.HAS_FINISHER_SPAWNS
            table.insert(availableFields, "finisherSpawns")
        else
            table.insert(missingFields, "finisherSpawns")
        end
    else
        table.insert(missingFields, "finishedBy")
        table.insert(missingFields, "finisherSpawns")
    end
    
    -- Check objectives
    if quest.Objectives and (
        (quest.Objectives[1] and #quest.Objectives[1] > 0) or  -- creatures
        (quest.Objectives[2] and #quest.Objectives[2] > 0) or  -- objects
        (quest.Objectives[3] and #quest.Objectives[3] > 0)     -- items
    ) then
        score = score + COMPLETENESS_WEIGHTS.HAS_OBJECTIVES
        table.insert(availableFields, "objectives")
    else
        table.insert(missingFields, "objectives")
    end
    
    -- Check quest level appropriateness
    if quest.Level and quest.Level > 0 and quest.Level <= 80 then
        score = score + COMPLETENESS_WEIGHTS.HAS_PROPER_LEVEL
        table.insert(availableFields, "level")
    else
        table.insert(missingFields, "level")
    end
    
    -- Calculate percentage and determine state
    local percentage = math.floor((score / MAX_COMPLETENESS_SCORE) * 100)
    local state = self:_DetermineCompletenessState(percentage)
    
    -- Determine functional capabilities
    local canShowPins = self:_Contains(availableFields, "startedBy") and self:_Contains(availableFields, "starterSpawns")
    local canTrackObjectives = self:_Contains(availableFields, "objectives")
    
    return {
        score = score,
        percentage = percentage,
        state = state,
        prefix = self.COMPLETENESS_PREFIXES[state],
        missingFields = missingFields,
        availableFields = availableFields,
        canShowPins = canShowPins,
        canTrackObjectives = canTrackObjectives,
        questData = quest -- Include the actual quest data for merging
    }
end

---Determine completeness state from percentage
---@param percentage number
---@return string state
function QuestCompletenessScorer:_DetermineCompletenessState(percentage)
    if percentage >= 90 then
        return self.COMPLETENESS_STATES.COMPLETE
    elseif percentage >= 70 then
        return self.COMPLETENESS_STATES.MOSTLY_COMPLETE
    elseif percentage >= 40 then
        return self.COMPLETENESS_STATES.PARTIAL
    elseif percentage >= 10 then
        return self.COMPLETENESS_STATES.MINIMAL
    else
        return self.COMPLETENESS_STATES.MISSING
    end
end

---Helper function to check if table contains value
---@param tbl table
---@param value any
---@return boolean
function QuestCompletenessScorer:_Contains(tbl, value)
    for _, v in ipairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

---Get human-readable completeness summary
---@param questId number
---@return string summary
function QuestCompletenessScorer:GetCompletenessSummary(questId)
    local info = self:AnalyzeQuestCompleteness(questId)
    
    local summary = string.format("Quest %d is %d%% complete (%s)", 
        questId, info.percentage, info.state)
    
    if #info.missingFields > 0 then
        summary = summary .. "\nMissing: " .. table.concat(info.missingFields, ", ")
    end
    
    if #info.availableFields > 0 then
        summary = summary .. "\nAvailable: " .. table.concat(info.availableFields, ", ")
    end
    
    return summary
end

return QuestCompletenessScorer