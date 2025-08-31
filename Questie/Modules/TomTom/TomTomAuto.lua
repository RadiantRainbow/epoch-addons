---@class TomTomAuto
local TomTomAuto = QuestieLoader:CreateModule("TomTomAuto")

-------------------------
-- Import Questie modules.
-------------------------
---@type QuestiePlayer
local QuestiePlayer = QuestieLoader:ImportModule("QuestiePlayer")
---@type QuestieMap
local QuestieMap = QuestieLoader:ImportModule("QuestieMap")
---@type TrackerUtils
local TrackerUtils = QuestieLoader:ImportModule("TrackerUtils")
---@type ThreadLib
local ThreadLib = QuestieLoader:ImportModule("ThreadLib")

--- COMPATIBILITY ---
local C_Timer = QuestieCompat.C_Timer


local tomtomAutoTrackTimer
local lastWaypoint

--- Finds the closest incomplete quest in the player's quest log for TomTom auto-targeting.
--- @return table|nil The closest quest table, or nil if none found or TomTom is not enabled.
function TomTomAuto:GetTomTomAutoTargetQuest()
    if not TomTom or not Questie.db.profile.tomtomAutoTargetMode then return nil end

    -- Don't run if quest log is being populated or isn't ready
    if QuestiePlayer._populatingQuestlog or not QuestiePlayer.currentQuestlog or next(QuestiePlayer.currentQuestlog) == nil then
        return nil
    end

    local closestQuest = nil
    local closestDistance = math.huge

    -- Iterate all quests in the player's quest log
    for questId, quest in pairs(QuestiePlayer.currentQuestlog) do
        if quest and type(quest) == "table" then
            -- Skip completed quests
            local isComplete = 0
            if quest.IsComplete and type(quest.IsComplete) == "function" then
                isComplete = quest:IsComplete()
            elseif quest.isComplete ~= nil then
                isComplete = quest.isComplete and 1 or 0
            end

            if isComplete ~= 1 and questId then
                -- Calculate distance to this quest's objectives
                local distance = TrackerUtils:GetDistanceToClosestObjective(questId)
                if distance and distance < closestDistance then
                    closestDistance = distance
                    closestQuest = quest
                end
            end
        end
    end

    return closestQuest
end

-- Gets the closest quest and set the TomTom target
function TomTomAuto:updateQuestWaypoint()
    local quest = TomTomAuto:GetTomTomAutoTargetQuest()
    if quest then
        local questId = quest.Id or tostring(quest)
        local spawn, zone, name = QuestieMap:GetNearestQuestSpawn(quest)
        if (not spawn) and quest.objective ~= nil then
            spawn, zone, name = QuestieMap:GetNearestSpawn(quest.objective)
        end
        if spawn then
            TrackerUtils:SetTomTomTarget(name, zone, spawn[1], spawn[2])
        end
    end
end


--- Starts automatic TomTom waypoint tracking to the closest incomplete quest.
--- Sets a timer to update the waypoint every 5 seconds.
function TomTomAuto:StartTomTomAutoTracking()
    if not TomTom or not TomTom.AddWaypoint or not Questie.db.profile.tomtomAutoTargetMode then return end

    if tomtomAutoTrackTimer then
        tomtomAutoTrackTimer:Cancel()
        tomtomAutoTrackTimer = nil
    end

    -- Delay initial start to ensure quest log is populated
    C_Timer.After(1.0, function()
        tomtomAutoTrackTimer = C_Timer.NewTicker(5.0, function()
            -- Only update if quest log is populated and not currently being updated
            if not QuestiePlayer._populatingQuestlog and QuestiePlayer.currentQuestlog and next(QuestiePlayer.currentQuestlog) ~= nil then
                TomTomAuto:updateQuestWaypoint()
            end
        end)
    end)
end

--- Stops the TomTom auto-tracking timer and clears the last waypoint reference.
function TomTomAuto:StopTomTomAutoTracking()
    if tomtomAutoTrackTimer then
        tomtomAutoTrackTimer:Cancel()
        tomtomAutoTrackTimer = nil
    end
    lastWaypoint = nil
end
