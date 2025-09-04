---@class QuestieVersionCheck
local QuestieVersionCheck = QuestieLoader:CreateModule("QuestieVersionCheck")

---@type QuestieLib
local QuestieLib = QuestieLoader:ImportModule("QuestieLib")

-- Compatibility layer for C_Timer
local C_Timer = QuestieCompat and QuestieCompat.C_Timer or C_Timer

-- Current version and latest known version
local CURRENT_VERSION = GetAddOnMetadata("Questie", "Version")
local LATEST_KNOWN_VERSION = "1.1.3"  -- Update this with each release
local VERSION_CHECK_SHOWN = false

-- GitHub releases URL for manual checking
local GITHUB_RELEASES_URL = "https://github.com/trav346/Questie-Epoch/releases"

function QuestieVersionCheck:Initialize()
    -- Check version on login
    if not VERSION_CHECK_SHOWN then
        C_Timer.After(5, function()
            QuestieVersionCheck:CheckVersion()
        end)
    end

    -- Listen for other players' version messages and broadcast ours once
    QuestieVersionCheck:RegisterAddonMessages()
    C_Timer.After(8, function()
        QuestieVersionCheck:BroadcastVersion()
    end)
end

function QuestieVersionCheck:CheckVersion()
    if VERSION_CHECK_SHOWN then return end
    
    local current = QuestieVersionCheck:ParseVersion(CURRENT_VERSION)
    local latest = QuestieVersionCheck:ParseVersion(LATEST_KNOWN_VERSION)
    
    if not current or not latest then return end
    
    if QuestieVersionCheck:CompareVersions(current, latest) < 0 then
        QuestieVersionCheck:ShowUpdateNotification()
        VERSION_CHECK_SHOWN = true
    end
end

function QuestieVersionCheck:ParseVersion(versionString)
    if not versionString then return nil end
    
    -- Remove 'v' prefix if present
    versionString = string.gsub(versionString, "^v", "")
    
    -- Parse semantic version (e.g., "1.0.64")
    local major, minor, patch = string.match(versionString, "(%d+)%.(%d+)%.(%d+)")
    
    if major and minor and patch then
        return {
            major = tonumber(major),
            minor = tonumber(minor),
            patch = tonumber(patch),
            string = versionString
        }
    end
    
    return nil
end

function QuestieVersionCheck:CompareVersions(version1, version2)
    -- Returns: -1 if version1 < version2, 0 if equal, 1 if version1 > version2
    if version1.major ~= version2.major then
        return version1.major < version2.major and -1 or 1
    end
    
    if version1.minor ~= version2.minor then
        return version1.minor < version2.minor and -1 or 1
    end
    
    if version1.patch ~= version2.patch then
        return version1.patch < version2.patch and -1 or 1
    end
    
    return 0
end

function QuestieVersionCheck:ShowUpdateNotification()
    -- Silent popup reminder 
    local QuestieUpdateReminder = QuestieLoader:ImportModule("QuestieUpdateReminder")
    if QuestieUpdateReminder and QuestieUpdateReminder.ShowPopup then
        QuestieUpdateReminder:ShowPopup(CURRENT_VERSION, LATEST_KNOWN_VERSION, GITHUB_RELEASES_URL)
        return
    end

    -- Falls back to chat as a redundant reminder
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Questie Epoch:|r Update available: " .. LATEST_KNOWN_VERSION .. " — " .. GITHUB_RELEASES_URL, 1, 0.5, 0)
end

-- Manual version slash commands removed to reduce command surface

-- Advanced: Check version from other players (optional)
function QuestieVersionCheck:RegisterAddonMessages()
    if RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix("QuestieVersion")
    end
    
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
        if prefix == "QuestieVersion" and sender ~= UnitName("player") then
            QuestieVersionCheck:HandleVersionMessage(message, sender)
        end
    end)
end

function QuestieVersionCheck:HandleVersionMessage(version, sender)
    local theirVersion = QuestieVersionCheck:ParseVersion(version)
    local ourVersion = QuestieVersionCheck:ParseVersion(CURRENT_VERSION)
    
    if theirVersion and ourVersion then
        if QuestieVersionCheck:CompareVersions(theirVersion, ourVersion) > 0 then
            
            local QuestieUpdateReminder = QuestieLoader:ImportModule("QuestieUpdateReminder")
            if QuestieUpdateReminder and QuestieUpdateReminder.ShowPopup then
                QuestieUpdateReminder:ShowPopup(CURRENT_VERSION, version, GITHUB_RELEASES_URL)
                VERSION_CHECK_SHOWN = true
            else
                -- Fallback to minimal chat message
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Questie Epoch:|r Newer version detected: " .. version .. " — " .. GITHUB_RELEASES_URL, 1, 0.5, 0)
                VERSION_CHECK_SHOWN = true
            end
        end
    end
end

function QuestieVersionCheck:BroadcastVersion()
    if IsInGuild() then
        SendAddonMessage("QuestieVersion", CURRENT_VERSION, "GUILD")
    end
    if GetNumRaidMembers() > 0 then
        SendAddonMessage("QuestieVersion", CURRENT_VERSION, "RAID")
    elseif GetNumPartyMembers() > 0 then
        SendAddonMessage("QuestieVersion", CURRENT_VERSION, "PARTY")
    end
end

return QuestieVersionCheck
