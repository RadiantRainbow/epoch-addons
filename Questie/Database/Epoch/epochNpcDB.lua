-- ARCHIVED - DO NOT USE
-- This database has been merged into wotlkNpcDB.lua
-- Using this file will cause missing vanilla NPCs!

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")

-- Provide empty table for compatibility with validator and merge logic
QuestieDB._epochNpcData = [[return {}]]
