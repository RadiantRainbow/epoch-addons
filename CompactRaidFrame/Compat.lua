local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local GetPartyMember = GetPartyMember
local InCombatLockdown = InCombatLockdown
local PartyMemberFrame_OnLoad = PartyMemberFrame_OnLoad
local IsActiveBattlefieldArena = IsActiveBattlefieldArena
local UpdatePartyMemberBackground = UpdatePartyMemberBackground

function GetDisplayedAllyFrames()
	local useCompact = CUF_CVar:GetCVarBool("useCompactPartyFrames")

	if ( IsActiveBattlefieldArena() and not useCompact ) then
		return "party"
	elseif ( IsInGroup() and ( IsInRaid() or useCompact ) ) then
		return "raid"
	elseif ( IsInGroup() ) then
		return "party"
	else
		return nil
	end
end

local function PartyFrame(Type)
	for i=1, MAX_PARTY_MEMBERS, 1 do
		if ( Type == "hide" ) then
			local Frame = _G["PartyMemberFrame"..i]
			Frame:SetAlpha(0)
			Frame:Hide()
			Frame:UnregisterAllEvents()
		elseif ( GetPartyMember(i) ) then
			local Frame = _G["PartyMemberFrame"..i]
			Frame:SetAlpha(1)
			Frame:Show()
			PartyMemberFrame_OnLoad(Frame)
		end
	end
end

function RaidOptionsFrame_UpdatePartyFrames()
	if ( InCombatLockdown() ) then
		return
	end

	if ( GetDisplayedAllyFrames() ~= "party" ) then
		PartyFrame("hide")
	else
		PartyFrame("hide")
		PartyFrame("show")
	end
	UpdatePartyMemberBackground()
end