local GetTime = GetTime
local UnitGUID = UnitGUID
local UnitExists = UnitExists
local CompactUnitFrame_OnEvent = CompactUnitFrame_OnEvent

local HEALCOMM
local ABSORBCOMM

local function Handler(Self, Event, Arg1, Arg2, Arg3, Arg4, Arg5, ...)
	local Unit = Self.unit or Self.displayedUnit

	if ( UnitExists(Unit) ) then
		local GUID = UnitGUID(Unit)

		if ( (Event == "EffectApplied" or Event == "UnitUpdated" or Event == "EffectRemoved" or Event == "UnitCleared" or Event == "AreaCreated" or Event == "AreaCleared") ) then
			if ( Arg1 == GUID or Arg3 == GUID ) then
				CompactUnitFrame_OnEvent(Self, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", Unit)
			end
		else
			-- HealComm: Recursion
			if ( ... ) then
				Handler(Self, Event, nil, nil, nil, nil, ...)
			end

			if ( Arg5 == GUID ) then
				CompactUnitFrame_OnEvent(Self, "UNIT_HEAL_PREDICTION", Unit)
			end
		end
	end
end

local function Construct(Self)
	if ( HEALCOMM == nil ) then
		HEALCOMM = LibStub:GetLibrary("LibHealComm-4.0", true) or false
		ABSORBCOMM = LibStub:GetLibrary("AbsorbsMonitor-1.0", true) or false
	end

	if ( HEALCOMM ) then
		HEALCOMM.RegisterCallback(Self, "HealComm_HealStarted", Handler, Self)
		HEALCOMM.RegisterCallback(Self, "HealComm_HealUpdated", Handler, Self)
		HEALCOMM.RegisterCallback(Self, "HealComm_HealDelayed", Handler, Self)
		HEALCOMM.RegisterCallback(Self, "HealComm_HealStopped", Handler, Self)
		HEALCOMM.RegisterCallback(Self, "HealComm_ModifierChanged", Handler, Self)
		HEALCOMM.RegisterCallback(Self, "HealComm_GUIDDisappeared", Handler, Self)
	end

	if ( ABSORBCOMM ) then
		ABSORBCOMM.RegisterCallback(Self, "EffectApplied", Handler, Self)
		ABSORBCOMM.RegisterCallback(Self, "EffectUpdated", Handler, Self)
		ABSORBCOMM.RegisterCallback(Self, "EffectRemoved", Handler, Self)
		ABSORBCOMM.RegisterCallback(Self, "UnitUpdated", Handler, Self)
		ABSORBCOMM.RegisterCallback(Self, "UnitCleared", Handler, Self)
		ABSORBCOMM.RegisterCallback(Self, "AreaCreated", Handler, Self)
		ABSORBCOMM.RegisterCallback(Self, "AreaCleared", Handler, Self)
	end
end

if ( CompactUnitFrame_OnLoad ) then
	DefaultCompactUnitFrameOptions.displayHealPrediction = true
	DefaultCompactMiniFrameOptions.displayHealPrediction = true

	hooksecurefunc("CompactUnitFrame_OnLoad", Construct)

	function UnitGetIncomingHeals(Unit, Healer, GUID)
		if ( Unit ) then
			if ( HEALCOMM ) then
				if ( not GUID ) then
					Unit = UnitGUID(Unit)
					Healer = (Healer) and UnitGUID(Healer)
				end

				return HEALCOMM:GetHealAmount(Unit, HEALCOMM.ALL_HEALS, GetTime() + 5, Healer)
			end
		end
	end

	function UnitGetTotalAbsorbs(Unit)
		if ( Unit ) then
			return (ABSORBCOMM) and ABSORBCOMM.Unit_Total(UnitGUID(Unit)) or 0
		end
	end
end