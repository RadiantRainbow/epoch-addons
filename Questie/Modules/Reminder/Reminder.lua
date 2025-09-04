---@class QuestieUpdateReminder
local QuestieUpdateReminder = QuestieLoader:CreateModule("QuestieUpdateReminder")

---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")

local C_Timer = (QuestieCompat and QuestieCompat.C_Timer) or C_Timer

local shownThisSession = false

-- Internal: defines the popup dialogs once
local function DefinePopups()
    if StaticPopupDialogs["QUESTIE_UPDATE_AVAILABLE"] then return end

    StaticPopupDialogs["QUESTIE_UPDATE_AVAILABLE"] = {
        text = "|cFFFFFF00Questie Epoch|r\nA new version is available.\n\nYour: %s\nLatest: %s\n\nCopy the download link?",
        button1 = l10n and l10n("Copy Link") or "Copy Link",
        button2 = l10n and l10n("Later") or "Later",
        hasEditBox = false,
        hideOnEscape = true,
        whileDead = true,
        timeout = 0,
        preferredIndex = 3,
        OnAccept = function(self, data)
            local url = data and data.url or ""
            StaticPopup_Show("QUESTIE_UPDATE_COPY_URL", nil, nil, { url = url })
        end,
    }

    StaticPopupDialogs["QUESTIE_UPDATE_COPY_URL"] = {
        text = "Questie Epoch Update URL:",
        button1 = l10n and l10n("Close") or "Close",
        hasEditBox = true,
        editBoxWidth = 280,
        hideOnEscape = true,
        whileDead = true,
        timeout = 0,
        preferredIndex = 3,
        OnShow = function(self, data)
            local url = data and data.url or ""
            local editBox = self.editBox
            editBox:SetText(url)
            editBox:HighlightText()
            editBox:SetFocus()
        end,
        EditBoxOnEscapePressed = function(self)
            self:GetParent():Hide()
        end,
    }
end

function QuestieUpdateReminder:Initialize()
    -- No-op: popups are defined on first use; kept for consistency
end

-- Show a silent popup reminding users to update
---@param current string
---@param latest string
---@param url string
function QuestieUpdateReminder:ShowPopup(current, latest, url)
    if Questie and Questie.db and Questie.db.profile and Questie.db.profile.disableUpdateReminder then
        return
    end
    if shownThisSession then return end

    DefinePopups()

    -- Delay slightly after login to avoid combat lockdowns or UI noise
    local function show()
        if shownThisSession then return end
        if Questie and Questie.db and Questie.db.profile and Questie.db.profile.disableUpdateReminder then
            return
        end
        shownThisSession = true
        StaticPopup_Show("QUESTIE_UPDATE_AVAILABLE", current or "?", latest or "?", { url = url or "" })
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(2, show)
    else
        show()
    end
end

return QuestieUpdateReminder
