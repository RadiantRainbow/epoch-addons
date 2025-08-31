---@class QuestieEpochStormwindObjectFixes
local QuestieEpochStormwindObjectFixes = QuestieLoader:CreateModule("QuestieEpochStormwindObjectFixes")
-------------------------
--Import modules.
-------------------------
---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")

-- Project Epoch specific fixes for Stormwind City Objects
-- Epoch uses Classic world but WotLK Stormwind layout, so we need to override
-- Stormwind (zone 1519) coordinates with WotLK data

function QuestieEpochStormwindObjectFixes:Load()
    local objectKeys = QuestieDB.objectKeys

    -- Stormwind City Objects with WotLK coordinates for Project Epoch
    return {
        -- Object ID 142075: Mailbox (important for players)
        [142075] = {
            [objectKeys.spawns] = {[1519]={
                {62.4,74.6},  -- Trade District
                {61.7,75.9},  -- Trade District
                {61.6,70.6},  -- Trade District
                {75.7,64.6},  -- Cathedral Square
                {74.5,55.4},  -- Cathedral Square
                {67.4,49.8},  -- Park District
                {61.4,43.5},  -- Mage Quarter
                {50.9,70.5},  -- Old Town
                {49.7,86.9},  -- Dwarven District
                {50.6,89.7}   -- Dwarven District
            }},
        },
        -- Object ID 1561: Sealed Crate (quest object)
        [1561] = {
            [objectKeys.spawns] = {[1519]={{42.46,72.04}}},
        },
    }
end
