---@class QuestRewardTooltipFix
local QuestRewardTooltipFix = QuestieLoader:CreateModule("QuestRewardTooltipFix")

-- Fix for GitHub issue #154: Invalid quest item tooltips causing errors
-- Some Epoch quests have invalid reward data that causes the game to error
-- when trying to show tooltips for quest rewards in the quest log

local _QuestRewardTooltipFix = QuestRewardTooltipFix.private

function QuestRewardTooltipFix:Initialize()
    -- Hook the GameTooltip's SetQuestLogItem to prevent errors with invalid quest rewards
    local originalSetQuestLogItem = GameTooltip.SetQuestLogItem
    
    GameTooltip.SetQuestLogItem = function(self, itemType, index)
        -- Validate that the quest reward actually exists before trying to show tooltip
        local success, err = pcall(function()
            -- Get the currently selected quest
            local questIndex = GetQuestLogSelection()
            if not questIndex or questIndex == 0 then
                return
            end
            
            -- Check if this is a valid reward index
            if itemType == "choice" then
                local numChoices = GetNumQuestLogChoices()
                if index > numChoices then
                    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestRewardTooltipFix] Invalid choice index:", index, "max:", numChoices)
                    return
                end
            elseif itemType == "reward" then
                local numRewards = GetNumQuestLogRewards()
                if index > numRewards then
                    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestRewardTooltipFix] Invalid reward index:", index, "max:", numRewards)
                    return
                end
            end
            
            -- Call the original function if validation passes
            originalSetQuestLogItem(self, itemType, index)
        end)
        
        if not success then
            -- Log the error but don't propagate it
            Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestRewardTooltipFix] Error in SetQuestLogItem:", err)
            -- Clear the tooltip instead of showing an error
            self:Hide()
        end
    end
    
    Questie:Debug(Questie.DEBUG_INFO, "[QuestRewardTooltipFix] Quest reward tooltip fix initialized")
end

return QuestRewardTooltipFix