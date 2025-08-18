if ( not C_Timer ) then
	local _G = _G
	local Next = next

	local C_Timer = TimerFrame or CreateFrame("Frame", "TimerFrame")
	local ObjPool = {}

	local function Pool(Timer)
		Timer.Ref = nil
		Timer.Callback = nil
		Timer.Iteration = nil
		ObjPool[#ObjPool+1] = Timer
	end

	local function Caller(Self)
		Self.Callback(Self.Ref)

		if ( Self.Callback ) then
			local Iteration = Self.Iteration
			if ( Iteration ) then
				if ( Iteration == 1 ) then
					Self.Ref:Cancel()
				else
					Self.Iteration = Iteration - 1
				end
			elseif ( not Self.Ref ) then
				Pool(Self)
			end
		end
	end

	local function New()
		local Index, Timer = Next(ObjPool)

		if ( Timer ) then
			ObjPool[Index] = nil
		else
			local A = C_Timer:CreateAnimationGroup()
			Timer = A:CreateAnimation("Animation")
			Timer:SetScript("OnFinished", Caller)
		end

		return Timer
	end

	local function Cancel(Self)
		if ( Self.__Timer ) then
			Self.__Timer:Stop()
			Pool(Self.__Timer)
			Self.__Timer = nil
		end
	end

	local function IsCancelled(Self)
		return not Self.__Timer
	end

	local function Create(Duration, Callback, Iteration, Ticker)
		local Timer = New()

		if ( Ticker ) then
			Timer.Ref = { __Timer = Timer, Cancel = Cancel, IsCancelled = IsCancelled }
			Timer.Iteration = Iteration
		end

		Timer.Callback = Callback
		Timer:GetParent():SetLooping((Ticker and (not Iteration or Iteration > 1)) and "REPEAT" or "NONE")
		Timer:SetDuration(Duration > 0 and Duration or .1)
		Timer:Play()

		return Timer.Ref
	end

	--[[
		METHOD
	]]

	function C_Timer.After(...)
		local Duration, Callback, _ = ...
		if ( _ and Duration[0] ) then
			_, Duration, Callback = ...
		end

		Create(Duration, Callback)
	end

	function C_Timer.NewTimer(...)
		local Duration, Callback, _ = ...
		if ( _ and Duration[0] ) then
			_, Duration, Callback = ...
		end

		return Create(Duration, Callback, 1, true)
	end

	function C_Timer.NewTicker(...)
		local Duration, Callback, Iteration, _ = ...
		if ( _ and Duration[0] ) then
			_, Duration, Callback, Iteration = ...
		end

		return Create(Duration, Callback, Iteration, true)
	end

	-- Global
	_G.C_Timer = C_Timer
	C_Timer._version = 2
end