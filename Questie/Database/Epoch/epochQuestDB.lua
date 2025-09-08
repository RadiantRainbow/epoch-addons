-- ARCHIVED - DO NOT USE
-- This database has been merged into wotlkQuestDB.lua
-- Using this file will cause missing vanilla quests!

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")

-- Provide empty table for compatibility with validator and merge logic
QuestieDB._epochQuestData = [[return {}]]
