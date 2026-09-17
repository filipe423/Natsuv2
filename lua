--// Natsu Hub - Steal + Egg Panel
--// Versao limpa

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local runtimeEnv = getgenv and getgenv() or _G

local Config = {
    AutoSteal = false,
    AutoParasiteSteal = false,
    AutoParasiteFeed = false,
    AutoParasiteClaim = false,
    StealAreas = {"None"},
    StealRarities = {"None"},
    StealMode = "Tween",
    StealNamesFilter = {"None"},
    StealMinValue = 0,
    TweenSpeedMultiplier = 40,
    AntiGuardKnockback = true,
    IsStealing = false,
    IsParasiteProcessing = false,
}

local SPOOF_CFG = {
    KEY = "__NatsuStealMovementSpoof",
    VERSION = 436,
    INTEGRITY_KEY = "__NatsuStealIntegritySpoof",
    SIGNAL = "ClientCharacter: GetDebugSnapshot",
    HEADROOM = 1.35,
    CLAMP = 0.15,
    PADDING = 24,
    MULTIPLIER = 10,
    MIN_INPUT = 1,
    MAX_INPUT = 100,
    DEF_INPUT = 40,
    MIN_SPEED = 10,
    MAX_SPEED = 1000,
    DEF_SPEED = 400,
    FIELDS = {
        "LastObservedSample", "LastSample", "LastGoodSample",
        "LastGameplayTrustedSample", "LastValidatedSample",
        "LastValidatedGroundedSample", "LastConfirmedGroundSample",
        "CandidateGroundedSample"
    }
}

local MOVEMENT_SPOOF_KEY = SPOOF_CFG.KEY
local MOVEMENT_SPOOF_VERSION = SPOOF_CFG.VERSION
local INTEGRITY_SPOOF_KEY = SPOOF_CFG.INTEGRITY_KEY
local INTEGRITY_SIGNAL_NAME = SPOOF_CFG.SIGNAL
local INTEGRITY_SPEED_HEADROOM = SPOOF_CFG.HEADROOM
local LONG_FRAME_CLAMP = SPOOF_CFG.CLAMP
local MOVEMENT_BASELINE_PADDING = SPOOF_CFG.PADDING
local MOVEMENT_SPEED_MULTIPLIER = SPOOF_CFG.MULTIPLIER
local MIN_MOVEMENT_SPEED_INPUT = SPOOF_CFG.MIN_INPUT
local MAX_MOVEMENT_SPEED_INPUT = SPOOF_CFG.MAX_INPUT
local DEFAULT_MOVEMENT_SPEED_INPUT = SPOOF_CFG.DEF_INPUT
local MIN_MOVEMENT_SPEED = SPOOF_CFG.MIN_SPEED
local MAX_MOVEMENT_SPEED = SPOOF_CFG.MAX_SPEED
local DEFAULT_MOVEMENT_SPEED = SPOOF_CFG.DEF_SPEED
local INTEGRITY_SAMPLE_FIELDS = SPOOF_CFG.FIELDS

local HOVER_PAD_SIZE_XZ = 8
local HOVER_PAD_THICKNESS = 1
local HOVER_PAD_NAME = "__NatsuHoverPad"
local HOVER_PAD_OWNER_ATTRIBUTE = "NatsuStealRuntimeOwner"

local hoverPadInstance = nil
local hoverPadOwnerId = tostring(math.random(100000, 999999))
local hoverPadConnection = nil
local hoverPadPostConnection = nil
local activeMoves = {}
local tweenArrivalHold = nil
local speedDialStuds

local function purgeOrphanHoverPads()
	for _, obj in ipairs(Workspace:GetChildren()) do
		if obj:IsA("BasePart") and obj.Name == HOVER_PAD_NAME and obj ~= hoverPadInstance then
			pcall(obj.Destroy, obj)
		end
	end
end

local function syncHoverPad(targetPos)
	if not hoverPadInstance or not hoverPadInstance.Parent then return false end
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then return false end
	local rootPosition = typeof(targetPos) == "Vector3" and targetPos or root.Position
	local feetOffset = humanoid.RigType == Enum.HumanoidRigType.R15
		and (root.Size.Y * 0.5 + math.max(humanoid.HipHeight, 0.5))
		or (root.Size.Y * 0.5 + 2)
	hoverPadInstance.CFrame = CFrame.new(
		rootPosition.X,
		rootPosition.Y - feetOffset - HOVER_PAD_THICKNESS * 0.5 - 0.05,
		rootPosition.Z
	)
	return true
end

local function startHoverPad()
	if not hoverPadInstance or not hoverPadInstance.Parent or hoverPadInstance:GetAttribute(HOVER_PAD_OWNER_ATTRIBUTE) ~= hoverPadOwnerId then
		purgeOrphanHoverPads()
		if hoverPadInstance and hoverPadInstance.Parent then pcall(hoverPadInstance.Destroy, hoverPadInstance) end
		local part = Instance.new("Part")
		part.Name = HOVER_PAD_NAME
		part:SetAttribute(HOVER_PAD_OWNER_ATTRIBUTE, hoverPadOwnerId)
		part.Anchored = true
		part.CanCollide = true
		part.CanQuery = true
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Material = Enum.Material.SmoothPlastic
		part.Size = Vector3.new(HOVER_PAD_SIZE_XZ, HOVER_PAD_THICKNESS, HOVER_PAD_SIZE_XZ)
		hoverPadInstance = part
		part.Parent = Workspace
	end
	syncHoverPad()
	if not hoverPadConnection then
		hoverPadConnection = RunService.PreSimulation:Connect(function()
			if not syncHoverPad() then startHoverPad() end
		end)
	end
	if not hoverPadPostConnection then
		hoverPadPostConnection = RunService.PostSimulation:Connect(function()
			syncHoverPad()
		end)
	end
end

local function stopHoverPad()
	if hoverPadConnection then
		pcall(hoverPadConnection.Disconnect, hoverPadConnection)
		hoverPadConnection = nil
	end
	if hoverPadPostConnection then
		pcall(hoverPadPostConnection.Disconnect, hoverPadPostConnection)
		hoverPadPostConnection = nil
	end
	if hoverPadInstance then
		pcall(hoverPadInstance.Destroy, hoverPadInstance)
		hoverPadInstance = nil
	end
	purgeOrphanHoverPads()
end

local function clearTweenArrivalHold()
	tweenArrivalHold = nil
end

local function setTweenArrivalHold(root, destination)
	if root and typeof(destination) == "CFrame" then
		tweenArrivalHold = {
			Character = LocalPlayer.Character,
			RootPart = root,
			CFrame = destination,
		}
	end
end

local function enforceTweenArrivalHold()
	local hold = tweenArrivalHold
	if type(hold) ~= "table" or typeof(hold.CFrame) ~= "CFrame" then return false end
	if LocalPlayer.Character ~= hold.Character or not hold.RootPart or not hold.RootPart.Parent then
		tweenArrivalHold = nil
		return false
	end
	startHoverPad()
	hold.RootPart.AssemblyLinearVelocity = Vector3.zero
	hold.RootPart.AssemblyAngularVelocity = Vector3.zero
	syncHoverPad(hold.CFrame.Position)
	hold.RootPart.CFrame = hold.CFrame
	syncHoverPad(hold.CFrame.Position)
	return true
end

local function stopAllActiveMovements()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    for _, move in pairs(activeMoves) do
        if type(move) == "table" then
            move.cancelled = true
        end
    end
    table.clear(activeMoves)
    if hrp then
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
    clearTweenArrivalHold()
    stopHoverPad()
end

do
    local EggState = require(game:GetService("ReplicatedStorage").Client.EggState)
    EggState.GetAreaEggSnapshot = EggState.ReadFieldEggs
    EggState.GetAreaEggRecord = EggState.ReadFieldEgg
    EggState.RequestAreaEggSnapshot = EggState.SyncFieldEggs
    EggState.RequestCarryAreaEgg = EggState.CarryFieldEgg
    EggState.AreaEggCarryStateChanged = EggState.CarryChanged
    EggState.AreaEggClaimed = EggState.FieldClaimed
    EggState.AreaEggUpdated = EggState.FieldShifted
    EggState.AreaEggRemoved = EggState.FieldGone
    EggState.GetOwnerRuntimeRecords = EggState.ReadOwnerEggs
    EggState.RequestEquipTool = EggState.WearEggTool

    local PlotState = require(game:GetService("ReplicatedStorage").Client.PlotState)
    PlotState.GetMySlot = PlotState.ResolveLocalSlot
    PlotState.GetPlotData = PlotState.ResolvePlot

    local AreaEggResetWall = require(game:GetService("ReplicatedStorage").Client.AreaEggResetWall)
    AreaEggResetWall.IsClosed = AreaEggResetWall.IsSealed
end

speedDialStuds = function()
    local inputSpeed = math.clamp(
        math.floor((tonumber(Config.TweenSpeedMultiplier) or SPOOF_CFG.DEF_INPUT) + 0.5),
        SPOOF_CFG.MIN_INPUT,
        SPOOF_CFG.MAX_INPUT
    )
    return inputSpeed * SPOOF_CFG.MULTIPLIER
end

function Config:applyStealValueInput(value)
    local normalized = string.lower(tostring(value or "")):gsub("[%s,]", "")
    if normalized == "" then
        self.StealMinValue = 0
        return true
    end
    local amountText, suffix = string.match(normalized, "^([%d]+%.?[%d]*)([kmb]?)$")
    local amount = tonumber(amountText)
    if not amount then return false end
    local multiplier = 1
    if suffix == "k" then
        multiplier = 1e3
    elseif suffix == "m" then
        multiplier = 1e6
    elseif suffix == "b" then
        multiplier = 1e9
    end
    self.StealMinValue = amount * multiplier
    return true
end

function Config:getAreaEggValue(record)
    if not self._assetGenerationUtil then
        self._assetGenerationUtil = require(game:GetService("ReplicatedStorage").Shared.Util.AssetEarnings)
    end
    return self._assetGenerationUtil.MutationOnlyRatePerSecond({
        Category = record.AssetCategory,
        Scale = record.AssetScale or 1,
        Mutations = record.Mutations or {},
        BaseMutation = record.BaseMutation,
        EyeColor = record.AssetEyeColor,
        ColorSeed = record.AssetColorSeed,
        ColorIndex = record.AssetColorIndex,
        Gender = record.Gender,
        Personality = record.Personality or "Normal",
        HasBeenFirstPlaced = record.HasBeenFirstPlaced == true,
    })
end
local function environment()
	return getgenv and getgenv() or _G
end

local function getMovementSpoof()
	local env = environment()
	local existing = env[MOVEMENT_SPOOF_KEY]
	if type(existing) ~= "table" or existing.Version ~= MOVEMENT_SPOOF_VERSION then
		if type(existing) == "table" then existing.Enabled = false end
		existing = {
			Version = MOVEMENT_SPOOF_VERSION,
			Installed = false,
			Enabled = false,
			Mode = "StateBaseline",
			Humanoid = nil,
			RootPart = nil,
			WalkSpeed = DEFAULT_MOVEMENT_SPEED,
		}
		env[MOVEMENT_SPOOF_KEY] = existing
	end
	return existing
end

local function setMovementSpoof(character, speed)
	local holder = getMovementSpoof()
	if not holder then return false end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	holder.Humanoid = humanoid
	holder.RootPart = root
	holder.WalkSpeed = math.clamp(
		tonumber(speed) or DEFAULT_MOVEMENT_SPEED,
		MIN_MOVEMENT_SPEED,
		MAX_MOVEMENT_SPEED * INTEGRITY_SPEED_HEADROOM
	)
	holder.Enabled = false
	return humanoid ~= nil and root ~= nil
end

local function clearMovementSpoof()
	local holder = environment()[MOVEMENT_SPOOF_KEY]
	if type(holder) == "table" then
		holder.Enabled = false
		holder.Humanoid = nil
		holder.RootPart = nil
	end
end

local function findIntegrityState(player, humanoid, root)
	local found = nil
	if type(getcallbackvalue) == "function" and type(debug) == "table" and type(debug.getupvalue) == "function" then
		local signalModule = ReplicatedStorage:FindFirstChild("Packages")
			and ReplicatedStorage.Packages:FindFirstChild("Signal")
		if signalModule then
			local okSig, Signal = pcall(require, signalModule)
			if okSig and type(Signal) == "table" and type(Signal.Invoked) == "function" then
				local okBind, bindable = pcall(Signal.Invoked, INTEGRITY_SIGNAL_NAME)
				if okBind and bindable then
					local okCb, callback = pcall(getcallbackvalue, bindable, "OnInvoke")
					if okCb and type(callback) == "function" then
						local okInfo, info = pcall(debug.getinfo, callback)
						if okInfo then
							local function scan(value, depth, seen)
								if found or type(value) ~= "table" or depth > 3 or seen[value] then return end
								seen[value] = true
								if rawget(value, "Player") == player
									and rawget(value, "Character") == player.Character
									and rawget(value, "Humanoid") == humanoid
									and rawget(value, "RootPart") == root
									and type(rawget(value, "SampleHistory")) == "table"
									and type(rawget(value, "Evidence")) == "table"
								then
									found = value
									return
								end
								local scanned = 0
								for _, child in pairs(value) do
									scanned = scanned + 1
									if scanned > 128 then break end
									if type(child) == "table" then scan(child, depth + 1, seen) end
								end
							end
							for idx = 1, info.nups or 0 do
								local okUp, upvalue = pcall(debug.getupvalue, callback, idx)
								if okUp and type(upvalue) == "table" then
									scan(upvalue, 0, {})
									if found then break end
								end
							end
						end
					end
				end
			end
		end
	end

	if not found and type(getgc) == "function" then
		local okGc, objects = pcall(getgc, true)
		if okGc and type(objects) == "table" then
			for _, obj in ipairs(objects) do
				if type(obj) == "table"
					and rawget(obj, "Player") == player
					and rawget(obj, "Character") == player.Character
					and rawget(obj, "Humanoid") == humanoid
					and rawget(obj, "RootPart") == root
					and type(rawget(obj, "SampleHistory")) == "table"
					and type(rawget(obj, "Evidence")) == "table"
				then
					found = obj
					break
				end
			end
		end
	end
	return found
end

local function patchIntegrityState(state, speed, travelVelocity)
	if type(state) ~= "table" then return false end
	local root = rawget(state, "RootPart")
	local rootCFrame = root and root.Parent and root.CFrame or nil
	local rootPosition = rootCFrame and rootCFrame.Position or nil
	local coherentVelocity = typeof(travelVelocity) == "Vector3" and travelVelocity or Vector3.zero

	local function patchSample(sample)
		if type(sample) == "table" then
			rawset(sample, "WalkSpeed", speed)
			if rootCFrame then
				rawset(sample, "CFrame", rootCFrame)
				rawset(sample, "Position", rootPosition)
				rawset(sample, "LinearVelocity", coherentVelocity)
				rawset(sample, "AngularVelocity", Vector3.zero)
			end
		end
	end

	for _, field in ipairs(INTEGRITY_SAMPLE_FIELDS) do
		patchSample(rawget(state, field))
	end
	for _, sample in pairs(rawget(state, "SampleHistory") or {}) do
		patchSample(sample)
	end
	for _, sample in pairs(rawget(state, "SafeGroundCheckpoints") or {}) do
		patchSample(sample)
	end

	local evidence = rawget(state, "Evidence")
	if type(evidence) == "table" then
		evidence.Speed = 0
		evidence.Teleport = 0
		evidence.Flight = 0
	end

	local impulse = rawget(state, "ImpulseContext")
	if type(impulse) == "table" then
		local horizontalSpeed = math.max(tonumber(impulse.MaxHorizontalSpeed) or 0, speed)
		local duration = math.max(
			(tonumber(impulse.ExpiresAt) or 0) - (tonumber(impulse.StartedAt) or 0),
			LONG_FRAME_CLAMP
		)
		impulse.MaxHorizontalSpeed = horizontalSpeed
		if rootPosition then impulse.OriginPosition = rootPosition end
		impulse.MaxHorizontalDistance = math.max(
			tonumber(impulse.MaxHorizontalDistance) or 0,
			horizontalSpeed * duration + MOVEMENT_BASELINE_PADDING * 2
		)
		patchSample(impulse.PreMovementSafeSample)
	end

	if rawget(state, "CorrectionContext") == nil then
		rawset(state, "FirstSuspiciousAt", nil)
		if rawget(state, "ThreatLevel") == "Observing" then
			rawset(state, "ThreatLevel", "Trusted")
		end
	end
	return true
end

local function getIntegritySpoof()
	local env = environment()
	local holder = env[INTEGRITY_SPOOF_KEY]
	if type(holder) ~= "table" then
		holder = {}
		env[INTEGRITY_SPOOF_KEY] = holder
	end
	return holder
end

local function integrityStateMatches(state, humanoid, root)
	return type(state) == "table"
		and rawget(state, "Player") == LocalPlayer
		and rawget(state, "Character") == LocalPlayer.Character
		and rawget(state, "Humanoid") == humanoid
		and rawget(state, "RootPart") == root
end

local function integrityStateCanTravel(state, humanoid, root)
	return integrityStateMatches(state, humanoid, root)
end

local function setIntegritySpoof(humanoid, root, speed)
	local holder = getIntegritySpoof()
	local state = holder.State
	if not integrityStateMatches(state, humanoid, root) then
		local now = os.clock()
		if now < (holder.NextSearchAt or 0) then return false end
		holder.NextSearchAt = now + 0.2
		state = findIntegrityState(LocalPlayer, humanoid, root)
	end
	if not state then
		return false
	end
	if not integrityStateCanTravel(state, humanoid, root) then
		holder.Enabled = false
		holder.Humanoid = humanoid
		holder.RootPart = root
		holder.State = state
		return false
	end
	holder.NextSearchAt = 0
	holder.Enabled = true
	holder.Humanoid = humanoid
	holder.RootPart = root
	holder.State = state
	holder.WalkSpeed = math.clamp(
		speed * INTEGRITY_SPEED_HEADROOM,
		MIN_MOVEMENT_SPEED,
		MAX_MOVEMENT_SPEED * INTEGRITY_SPEED_HEADROOM
	)
	holder.TravelVelocity = Vector3.zero
	patchIntegrityState(state, holder.WalkSpeed, holder.TravelVelocity)
	return true
end

local function refreshIntegritySpoof(humanoid, root, speed, travelVelocity)
	local holder = environment()[INTEGRITY_SPOOF_KEY]
	if type(holder) ~= "table"
		or not holder.Enabled
		or holder.Humanoid ~= humanoid
		or holder.RootPart ~= root
		or not integrityStateCanTravel(holder.State, humanoid, root)
	then
		return false
	end
	holder.WalkSpeed = math.clamp(
		speed * INTEGRITY_SPEED_HEADROOM,
		MIN_MOVEMENT_SPEED,
		MAX_MOVEMENT_SPEED * INTEGRITY_SPEED_HEADROOM
	)
	if typeof(travelVelocity) == "Vector3" then
		holder.TravelVelocity = travelVelocity
	elseif typeof(holder.TravelVelocity) ~= "Vector3" then
		holder.TravelVelocity = Vector3.zero
	end
	return patchIntegrityState(holder.State, holder.WalkSpeed, holder.TravelVelocity)
end

local function clearIntegritySpoof(humanoid)
	local holder = environment()[INTEGRITY_SPOOF_KEY]
	if type(holder) ~= "table" then return end
	if humanoid == nil or holder.Humanoid == humanoid then
		holder.Enabled = false
		holder.Humanoid = nil
		holder.RootPart = nil
		holder.State = nil
		holder.TravelVelocity = nil
		holder.NextSearchAt = 0
	end
end

local globalIntegrityConnection = nil
local function startGlobalMovementProtection()
	if globalIntegrityConnection then return end
	globalIntegrityConnection = RunService.PreSimulation:Connect(function()
		local char = LocalPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not char or not root or not hum then return end
		local targetSpeed = speedDialStuds()
		setMovementSpoof(char, targetSpeed * INTEGRITY_SPEED_HEADROOM)
		if not refreshIntegritySpoof(hum, root, targetSpeed) then
			setIntegritySpoof(hum, root, targetSpeed)
		end
		enforceTweenArrivalHold()
	end)
end

local function stopGlobalMovementProtection()
	if globalIntegrityConnection then
		pcall(globalIntegrityConnection.Disconnect, globalIntegrityConnection)
		globalIntegrityConnection = nil
	end
	clearMovementSpoof()
	clearIntegritySpoof()
end

local function applyKillPartIgnore(character)
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root then
        root:SetAttribute("KillPartIgnore", true)
    end
end

local MOVEMENT_ARRIVAL_HOLD = 0.4
local TWEEN_SAFE_ZONE_POSITION = Vector3.new(545, 71, -365)
local TWEEN_CRUISE_HEIGHT = 5
local TWEEN_STEAL_TIMING = {
    CarryRetry = 0.25,
    CarryTimeout = 2,
    EarlyCarryDistance = 60,
    SafeStable = 0.35,
    ReturnValidation = 0.08,
    NextTarget = 0.05,
    SafeHandoff = 0.15,
}
local MIN_TWEEN_DURATION = 0.08
local function TweenMoveTo(hrp, hum, targetCFrame, isCancelledFn, holdAfterArrival, earlyArrivalFn, flightProfile)
    if not hrp or not hum or typeof(targetCFrame) ~= "CFrame" then return false end
    if isCancelledFn and isCancelledFn() then return false end

    local prevMove = activeMoves[hrp]
    if prevMove then
        prevMove.cancelled = true
        activeMoves[hrp] = nil
    end

    local character = hrp.Parent
    if not character then return false end
    clearTweenArrivalHold()
    applyKillPartIgnore(character)
    startGlobalMovementProtection()

    local camera = workspace.CurrentCamera
    if camera and camera.CameraSubject ~= hum then
        pcall(function() camera.CameraSubject = hum end)
    end

    local originalAutoRotate = hum.AutoRotate
    hum.AutoRotate = false

    local cruiseY = flightProfile and math.max(
        hrp.Position.Y,
        targetCFrame.Position.Y + TWEEN_CRUISE_HEIGHT,
        TWEEN_SAFE_ZONE_POSITION.Y + TWEEN_CRUISE_HEIGHT
    ) or nil
    local destination = cruiseY
        and (CFrame.new(targetCFrame.Position.X, cruiseY, targetCFrame.Position.Z) * targetCFrame.Rotation)
        or targetCFrame
    local liveSpeed = math.clamp(speedDialStuds(), SPOOF_CFG.MIN_SPEED, SPOOF_CFG.MAX_SPEED)
    setMovementSpoof(character, liveSpeed * SPOOF_CFG.HEADROOM)

    local move = {cancelled = false}
    activeMoves[hrp] = move
    startHoverPad()

    local arrivalStableSince = nil
    local previousRemainingDistance = nil
    local correctionSlowUntil = 0
    local travelPhase = cruiseY and (math.abs(hrp.Position.Y - cruiseY) > 0.35 and "takeoff" or "cruise") or nil
    local initialDistance = (destination.Position - hrp.Position).Magnitude
    local timeoutAt = os.clock() + math.max(initialDistance / liveSpeed, MIN_TWEEN_DURATION) * 3 + 8
    local completed = false
    local earlyArrivalStarted = false

    while not move.cancelled do
        if isCancelledFn and isCancelledFn() then break end
        if not hrp.Parent then break end
        if os.clock() >= timeoutAt then break end

        local deltaTime = RunService.Heartbeat:Wait()
        local safeDeltaTime = math.max(math.min(deltaTime, LONG_FRAME_CLAMP), 1 / 240)

        liveSpeed = math.clamp(speedDialStuds(), SPOOF_CFG.MIN_SPEED, SPOOF_CFG.MAX_SPEED)
        setMovementSpoof(character, liveSpeed * SPOOF_CFG.HEADROOM)

        local holder = environment()[SPOOF_CFG.INTEGRITY_KEY]
        local integrityState = type(holder) == "table" and holder.State or nil
        if not integrityStateCanTravel(integrityState, hum, hrp) then
            previousRemainingDistance = nil
            arrivalStableSince = nil
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            syncHoverPad(hrp.Position)
            if integrityStateMatches(integrityState, hum, hrp) then
                patchIntegrityState(integrityState, liveSpeed * SPOOF_CFG.HEADROOM, Vector3.zero)
            else
                setIntegritySpoof(hum, hrp, liveSpeed)
            end
        else
            local position = hrp.Position
            local remaining = destination.Position - position
            local remainingDistance = remaining.Magnitude
            local horizontalRemaining = Vector3.new(remaining.X, 0, remaining.Z)
            if cruiseY and travelPhase == "takeoff" and math.abs(position.Y - cruiseY) <= 0.35 then
                travelPhase = "cruise"
            end
            local movementTarget = cruiseY and travelPhase == "takeoff"
                and Vector3.new(position.X, cruiseY, position.Z)
                or destination.Position
            local movementRemaining = movementTarget - position
            local movementDistance = movementRemaining.Magnitude
            local progressDistance = cruiseY and horizontalRemaining.Magnitude or remainingDistance
            if previousRemainingDistance and progressDistance > previousRemainingDistance + 2 then
                correctionSlowUntil = os.clock() + 0.5
            end
            previousRemainingDistance = progressDistance
            local effectiveSpeed = os.clock() < correctionSlowUntil
                and math.max(SPOOF_CFG.MIN_SPEED, liveSpeed * 0.45)
                or liveSpeed
            local stepDistance = effectiveSpeed * safeDeltaTime

            if earlyArrivalFn and not earlyArrivalStarted and remainingDistance <= 60 then
                earlyArrivalStarted = true
                task.spawn(earlyArrivalFn)
            end

            local currentLook = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
            local facingDirection = horizontalRemaining.Magnitude > 0.001 and horizontalRemaining.Unit
                or (currentLook.Magnitude > 0.001 and currentLook.Unit or Vector3.new(0, 0, -1))

            local canArrive = not cruiseY or travelPhase == "cruise"
            if canArrive and remainingDistance <= math.max(stepDistance, 0.05) then
                if remainingDistance > 0.5 then arrivalStableSince = nil end
                syncHoverPad(destination.Position)
                hrp.CFrame = CFrame.lookAt(destination.Position, destination.Position + facingDirection)
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                syncHoverPad(destination.Position)
                refreshIntegritySpoof(hum, hrp, liveSpeed, Vector3.zero)
                arrivalStableSince = arrivalStableSince or os.clock()
                if os.clock() - arrivalStableSince >= MOVEMENT_ARRIVAL_HOLD then
                    completed = true
                    break
                end
            else
                arrivalStableSince = nil
                if movementDistance <= 0.001 then
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    hrp.AssemblyAngularVelocity = Vector3.zero
                    syncHoverPad(position)
                    continue
                end
                local actualStepDistance = math.min(stepDistance, movementDistance)
                local nextPosition = position + movementRemaining.Unit * actualStepDistance
                local travelVelocity = (nextPosition - position) / safeDeltaTime
                syncHoverPad(nextPosition)
                hrp.CFrame = CFrame.lookAt(nextPosition, nextPosition + facingDirection)
                hrp.AssemblyLinearVelocity = travelVelocity
                syncHoverPad(nextPosition)
                if not refreshIntegritySpoof(hum, hrp, liveSpeed, travelVelocity) then
                    setIntegritySpoof(hum, hrp, liveSpeed)
                    refreshIntegritySpoof(hum, hrp, liveSpeed, travelVelocity)
                end
            end
        end
    end

    if hum.Parent and originalAutoRotate ~= nil then hum.AutoRotate = originalAutoRotate end
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
    if completed and holdAfterArrival then
        setTweenArrivalHold(hrp, destination)
    else
        stopHoverPad()
    end
    return completed and not move.cancelled
end

local function flyAutoSteal(hrp, hum, targetCFrame, isCancelledFn)
    return TweenMoveTo(hrp, hum, targetCFrame, isCancelledFn, false, nil, true)
end

local IC_MAX_TELEPORT_STUDS = 10000
local IC_SAFE_ZONE_POS = Vector3.new(545, 71, -365)
local IC_SAFE_ZONE_RADIUS = 30
local IC_SAFE_ZONE_VERTICAL_TOLERANCE = 18
local IC_HIT_TIMEOUT = 12
local IC_GUARD_HIT_DISTANCE_BOOST = 25

local function isStealNightBlocked()
    local ok, AreaEggCycleModule = pcall(function()
        return require(ReplicatedStorage.Shared.Util.AreaEggCycle)
    end)
    if ok and AreaEggCycleModule and type(AreaEggCycleModule.IsNightPhase) == "function" then
        local ok2, isNight = pcall(AreaEggCycleModule.IsNightPhase, workspace:GetServerTimeNow())
        if ok2 and isNight == true then return true end
    end
    local ok3, AreaEggResetWallModule = pcall(function()
        return require(ReplicatedStorage.Client.AreaEggResetWall)
    end)
    if ok3 and AreaEggResetWallModule then
        if type(AreaEggResetWallModule.IsSealed) == "function" then
            local ok4, sealed = pcall(AreaEggResetWallModule.IsSealed)
            if ok4 and sealed == true then return true end
        end
    end
    return false
end

local function fieldStealEnabled()
    return Config.AutoSteal or Config.AutoParasiteSteal
end

local function reserveAutoStealPriority(seconds)
    Config.StealPriorityUntil = math.max(Config.StealPriorityUntil or 0, os.clock() + (seconds or 5))
end

local function hasMonstrousMutation(record)
    if type(record) ~= "table" then return false end
    if record.HasParasite == true then return true end
    return false
end
local function safeRequire(mod)
    if not mod then return nil end
    local ok, res = pcall(require, mod)
    if ok then return res end
    return nil
end

local IC_MODULES = {
    EggState = safeRequire(ReplicatedStorage:FindFirstChild("Client") and ReplicatedStorage.Client:FindFirstChild("EggState")),
    AreaEggs = safeRequire(ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("Types") and ReplicatedStorage.Shared.Types:FindFirstChild("AreaEggs")),
    AssetItems = safeRequire(ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("Util") and ReplicatedStorage.Shared.Util:FindFirstChild("AssetItems")),
    AssetsData = safeRequire(ReplicatedStorage:FindFirstChild("Data") and ReplicatedStorage.Data:FindFirstChild("Assets")),
    SlotIdentity = safeRequire(ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("Util") and ReplicatedStorage.Shared.Util:FindFirstChild("AreaEggSlotIdentity")),
}

local function icTeleportRoot(root, dest)
    if not root or typeof(dest) ~= "CFrame" then return false end
    local ok = pcall(function()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        root.CFrame = dest
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
    if not ok then return false end
    syncHoverPad(dest.Position)
    local char = root.Parent
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        local liveSpeed = math.clamp(speedDialStuds(), SPOOF_CFG.MIN_SPEED, SPOOF_CFG.MAX_SPEED)
        setMovementSpoof(char, liveSpeed * SPOOF_CFG.HEADROOM)
        if not refreshIntegritySpoof(hum, root, liveSpeed, Vector3.zero) then
            setIntegritySpoof(hum, root, liveSpeed)
            refreshIntegritySpoof(hum, root, liveSpeed, Vector3.zero)
        end
    end
    return true
end

local function icTeleportHops(root, dest)
    if not root or typeof(dest) ~= "CFrame" then return false end
    local from = root.Position
    local to = dest.Position
    local dist = (to - from).Magnitude
    local hops = math.max(1, math.ceil(dist / IC_MAX_TELEPORT_STUDS))
    for i = 1, hops do
        local t = i / hops
        local point = from:Lerp(to, t)
        if not icTeleportRoot(root, CFrame.new(point) * dest.Rotation) then return false end
        if i < hops then task.wait() end
    end
    return true
end

local function icRequestFieldEggCarry(uid, slotKey)
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if root then
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end
    local EggWorld = require(ReplicatedStorage.Shared.Remotes).EggWorld
    local payload = { Uid = uid }
    if slotKey then payload.FirstAreaSlotKey = slotKey end
    return EggWorld.AskFieldEggCarry:InvokeServer(payload) == true
end

local function icIsInSafeArea(root)
    if not root then return false end
    local d = root.Position - IC_SAFE_ZONE_POS
    return Vector2.new(d.X, d.Z).Magnitude <= IC_SAFE_ZONE_RADIUS
        and math.abs(d.Y) <= IC_SAFE_ZONE_VERTICAL_TOLERANCE
end

local SharedRagdollModule = nil
pcall(function()
    SharedRagdollModule = require(ReplicatedStorage.Shared.Modules.Ragdoll)
end)

local function icReadRagdollState()
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local tEnd = LocalPlayer:GetAttribute("RagdollEndTime") or 0
	local remaining = tEnd - workspace:GetServerTimeNow()
	local physics = hum ~= nil and hum:GetState() == Enum.HumanoidStateType.Physics
	local isRagdolled = false
    if SharedRagdollModule and char then
        local ok, res = pcall(SharedRagdollModule.IsRagdolled, char)
        if ok and res == true then isRagdolled = true end
    end
    if not isRagdolled and char and remaining > 0 then
		for _, descendant in ipairs(char:GetDescendants()) do
			if (descendant:IsA("BallSocketConstraint") or descendant:IsA("HingeConstraint"))
				and descendant.Enabled
			then
				isRagdolled = true
				break
			end
		end
	end
	return remaining > 0.05 and (isRagdolled or physics), math.max(0, remaining), (physics or isRagdolled)
end

local function icSetAnchored(anchored)
	runtimeEnv.__NatsuInstantAnchorLock = anchored == true
    pcall(function()
        local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if root and root.Anchored ~= anchored then root.Anchored = anchored end
    end)
end

local function icRarityWeight(rarity)
    local weights = {
        Common = 1, Uncommon = 2, Rare = 3, Epic = 4,
        Legendary = 5, Mythic = 6, Cosmic = 7, Secret = 8,
        Eternal = 9, Divine = 10,
    }
    return weights[rarity] or 0
end

local function icGetRecordRarity(record)
    local Assets = require(game:GetService("ReplicatedStorage").Data.Assets)
    local categoryData = Assets and Assets.Directory and Assets.Directory[record.AssetCategory]
    local rarityData = categoryData and categoryData.Rarity
    if not rarityData then return "Unknown" end
    if type(rarityData) == "string" then return rarityData end
    return rarityData.DisplayName or rarityData._id or tostring(rarityData)
end

local DECOY_NAME = "__NatsuDecoy"
local DECOY_REMOVE_CLASSES = {
    Script = true,
    LocalScript = true,
    BillboardGui = true,
    Sound = true,
}

local InstantCarry = {}
InstantCarry.__index = InstantCarry

function InstantCarry.new()
    local self = setmetatable({}, InstantCarry)
    self.enabled = false
    self.running = false
    self.phase = "idle"
    self.primerUid = nil
    self.targetUid = nil
    self.activeTarget = nil
    self.carryActive = false
    self.carryUid = nil
    self.arrivalHold = nil
    self.hitTimer = nil
    self.planGeneration = 0
    self.carryGeneration = 0
    self.carryWorker = nil
    self.carryAttemptToken = nil
    self.ragdollEndTime = LocalPlayer:GetAttribute("RagdollEndTime") or 0
    self.targetCycleStartedAt = nil
    self.targetCycleSeconds = 0.9
    self.rearmSeconds = 0.55
    self.rearmStartedAt = nil
    self.baitRagdollBaseline = 0
    self.depositRetryScheduled = false
    self.connections = {}
    self.records = {}
    self.stats = { status = "Idle" }
    self._decoy = nil
    self._decoyCamera = nil
    self._decoyCameraConnection = nil
    self:_connect()
    return self
end

function InstantCarry:_connect()
    local EggCmds = require(ReplicatedStorage.Client.EggState)
    table.insert(self.connections, LocalPlayer:GetAttributeChangedSignal("RagdollEndTime"):Connect(function()
        local previousEndTime = self.ragdollEndTime
        self.ragdollEndTime = LocalPlayer:GetAttribute("RagdollEndTime") or 0
        if self.rearmStartedAt
            and self.ragdollEndTime > math.max(previousEndTime, self.baitRagdollBaseline) + 0.1
        then
            local observed = math.min(1.5, os.clock() - self.rearmStartedAt + 0.12)
            self.rearmSeconds = math.max(0.3, observed, self.rearmSeconds * 0.9)
            self.rearmStartedAt = nil
        end
    end))
    table.insert(self.connections, EggCmds.FieldRefreshed:Connect(function(snapshot)
        self:_replaceSnapshot(snapshot)
        if self.enabled and self.phase == "priming" then self:_refreshPlannedTarget() end
    end))
    table.insert(self.connections, EggCmds.FieldShifted:Connect(function(record)
        if record and record.Uid then self.records[record.Uid] = record end
        if self.enabled and self.phase == "priming" then self:_refreshPlannedTarget() end
    end))
    table.insert(self.connections, EggCmds.FieldGone:Connect(function(uid)
        self.records[uid] = nil
        if self.activeTarget and self.activeTarget.Uid == uid then
            if self.carryActive and self.carryUid == uid then return end
            self.carryAttemptToken = nil
            self:_clearArrivalHold(uid)
            local target = self.activeTarget
            task.delay(0.65, function()
                if self.destroyed or not self.enabled then return end
                if self.carryActive and self.carryUid == uid then return end
                if self.activeTarget == target and target.Uid == uid then
                    self:_finish("Target removed")
                end
            end)
        end
    end))
end
function InstantCarry:_replaceSnapshot(snapshot)
    table.clear(self.records)
    local records = snapshot and (snapshot.Records or snapshot) or {}
    for k, v in pairs(records) do
        if type(v) == "table" and type(v.Uid) == "string" then self.records[v.Uid] = v
        elseif type(k) == "string" and type(v) == "table" then self.records[k] = v end
    end
end

function InstantCarry:_refreshPlannedTarget()
    if self.phase ~= "priming" then return end
    local best = self:_chooseTarget()
    if best and best.Uid ~= self.primerUid then
        self.targetUid = best.Uid
    end
end

function InstantCarry:_setStatus(s)
    self.stats.status = s
end

function InstantCarry:_feetOffset(root, humanoid)
    if humanoid.RigType == Enum.HumanoidRigType.R15 then
        return root.Size.Y * 0.5 + math.max(humanoid.HipHeight, 0.5)
    end
    return root.Size.Y * 0.5 + 2
end

function InstantCarry:_resolveEggDestination(record, root, humanoid)
    if type(record) ~= "table" or typeof(record.BottomCFrame) ~= "CFrame" then return nil end
    if not root or not humanoid then return nil end
    local standingHeight = self:_feetOffset(root, humanoid) + 0.15
    return CFrame.new(record.BottomCFrame.Position + Vector3.new(0, standingHeight, 0))
end

function InstantCarry:_invalidateCarryWorker()
    self.carryWorker = nil
end

function InstantCarry:_claimCarryWorker(kind, uid)
    local current = self.carryWorker
    if current and current.generation == self.carryGeneration then return nil end
    local worker = { kind = kind, uid = uid, generation = self.carryGeneration }
    self.carryWorker = worker
    return worker
end

function InstantCarry:_isCarryWorkerCurrent(worker)
    return self.enabled and not self.destroyed
        and self.carryWorker == worker
        and worker.generation == self.carryGeneration
end

function InstantCarry:_releaseCarryWorker(worker)
    if self.carryWorker == worker then self.carryWorker = nil end
end

function InstantCarry:_recordShowsCarried(uid)
    local EggCmds = require(ReplicatedStorage.Client.EggState)
    local record = EggCmds.ReadFieldEgg(uid) or self.records[uid]
    return type(record) == "table"
        and record.State == "Carried"
        and record.CarrierUserId == LocalPlayer.UserId
end

function InstantCarry:_recordShowsForeignCarry(uid)
    local EggCmds = require(ReplicatedStorage.Client.EggState)
    local record = EggCmds.ReadFieldEgg(uid) or self.records[uid]
    return type(record) == "table"
        and record.State == "Carried"
        and record.CarrierUserId ~= nil
        and record.CarrierUserId ~= LocalPlayer.UserId
end

function InstantCarry:_kbCancelTimer()
    if self.hitTimer then
        pcall(task.cancel, self.hitTimer)
        self.hitTimer = nil
    end
end

function InstantCarry:_handleNightRetreat()
    self.running = false
    self.phase = "idle"
    self.primerUid = nil
    self.targetUid = nil
    self.activeTarget = nil
    self.carryActive = false
    self.carryUid = nil
    icSetAnchored(false)
    self:_clearArrivalHold()
    self:_kbCancelTimer()
    
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root and not icIsInSafeArea(root) then
        local safeDest = CFrame.new(IC_SAFE_ZONE_POS + Vector3.new(0, 3.5, 0))
        icTeleportRoot(root, safeDest)
    end
    self:_setStatus("Waiting for day (Safe)")

    task.delay(1.5, function()
        if self.enabled and not self.destroyed and not self.running then
            if not isStealNightBlocked() then
                self:_setStatus("Day arrived")
                self:_schedule()
            else
                self:_handleNightRetreat()
            end
        end
    end)
end

function InstantCarry:_choosePrimerEgg(excludeUid)
    local AreaEggs = require(ReplicatedStorage.Shared.Types.AreaEggs)
    local GuardAreas = workspace:FindFirstChild("__OBJECTS") 
        and workspace.__OBJECTS:FindFirstChild("Areas") 
        and workspace.__OBJECTS.Areas:FindFirstChild("GuardAreas")
    local forestGuard = GuardAreas and GuardAreas:FindFirstChild("Forest") and GuardAreas.Forest:FindFirstChild("Guard")
    local guardHrp = forestGuard and forestGuard:FindFirstChild("HumanoidRootPart")
    local guardPos = guardHrp and guardHrp.Position

    local best, bestDist = nil, math.huge
    for _, rec in pairs(self.records) do
        if rec.State ~= AreaEggs.States.Slot then continue end
        if rec.AreaId ~= "Forest" then continue end
        if rec.Uid == excludeUid then continue end
        if rec.HasParasite == true then continue end
        local dist = (guardPos and rec.BottomCFrame) 
            and (rec.BottomCFrame.Position - guardPos).Magnitude 
            or math.huge
        if dist < bestDist then
            best = rec
            bestDist = dist
        end
    end
    return best
end

function InstantCarry:_chooseTarget()
    local AssetItems = IC_MODULES.AssetItems
    local AreaEggs = IC_MODULES.AreaEggs
    if not AreaEggs then return nil end
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local best, bestRank, bestDist
    
    local filterNames = Config.StealNamesFilter or {}
    local filterAreas = Config.StealAreas or {}
    local filterRarities = Config.StealRarities or {}
    
    local hasRarityFilter = (#filterRarities > 0) 
        and (table.find(filterRarities, "None") == nil) 
        and (table.find(filterRarities, "All") == nil)
    local hasAreaFilter = (#filterAreas > 0) 
        and (table.find(filterAreas, "None") == nil) 
        and (table.find(filterAreas, "All") == nil)
    local hasNameFilter = (#filterNames > 0) 
        and (table.find(filterNames, "None") == nil) 
        and (table.find(filterNames, "All") == nil)
    
    local Assets = IC_MODULES.AssetsData
    local assetDirectory = Assets and Assets.Directory or {}
    
    for _, rec in pairs(self.records) do
        if rec.State ~= AreaEggs.States.Slot and rec.State ~= AreaEggs.States.Dropped then continue end
        if rec.Uid == self.primerUid then continue end
        
        local cat = rec.AssetCategory or "Unknown"
        local area = rec.AreaId or "Unknown"
        local rarity = icGetRecordRarity(rec)
        local isPremium = (rarity == "Cosmic" or rarity == "Secret" or rarity == "Eternal" or rarity == "Divine")
        
        local categoryData = assetDirectory[cat]
        local dispName = (categoryData and categoryData.DisplayName) or cat
        
        local areaMatch = (not hasAreaFilter) or (table.find(filterAreas, area) ~= nil)
        local rarityMatch = (not hasRarityFilter) or (table.find(filterRarities, rarity) ~= nil)
        local nameMatch = (not hasNameFilter) or (table.find(filterNames, cat) ~= nil) or (table.find(filterNames, dispName) ~= nil)
        local valueMatch = (not Config.StealMinValue) or (Config.StealMinValue <= 0) or (Config:getAreaEggValue(rec) > Config.StealMinValue)
        
        if areaMatch and rarityMatch and nameMatch and valueMatch then
            local dist = root and (rec.BottomCFrame.Position - root.Position).Magnitude or math.huge
            local rWeight = icRarityWeight(rarity)
            local rank = (rWeight > 0 and rWeight) or (AssetItems and AssetItems.RarityRankForCategory(cat) or 0)
            if isPremium then
                rank = rank + 2000
            end
            if not best or rank > bestRank or (rank == bestRank and dist < bestDist) then
                best = rec; bestRank = rank; bestDist = dist
            end
        end
    end
    
    return best
end
function InstantCarry:_schedule(forcePrimer)
    if self.destroyed or not self.enabled or self.running then return end

    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum then 
        self:_setStatus("No character")
        task.delay(1, function()
            if not self.destroyed and self.enabled and not self.running then
                self:_schedule()
            end
        end)
        return 
    end

    local EggCmds = IC_MODULES.EggState or require(ReplicatedStorage.Client.EggState)
    if EggCmds then
        pcall(function()
            local freshSnap = EggCmds.GetAreaEggSnapshot()
            if freshSnap then self:_replaceSnapshot(freshSnap) end
        end)
    end

    if isStealNightBlocked() then
        self:_handleNightRetreat()
        task.delay(1, function()
            if not self.destroyed and self.enabled and not self.running then 
                self:_schedule() 
            end
        end)
        return
    end

    local target = self:_chooseTarget()
    if not target then 
        self:_setStatus("Waiting for target egg")
        task.delay(1, function()
            if not self.destroyed and self.enabled and not self.running then 
                self:_schedule() 
            end
        end)
        return 
    end
    
    local tEnd = LocalPlayer:GetAttribute("RagdollEndTime") or 0
    local rawRemaining = tEnd - workspace:GetServerTimeNow()
    if not forcePrimer and rawRemaining >= (self.targetCycleSeconds + self.rearmSeconds + 0.35) then
        self.targetUid = target.Uid
        self.phase = "hunting"
        self.running = true
        self:_setStatus("Chain steal")
        self:_startHunt()
        return
    end
	if rawRemaining > 0 and not forcePrimer then forcePrimer = true end

    local primer = self:_choosePrimerEgg(target.Uid)
    if not primer then
        self:_setStatus("Waiting for Forest primer")
        task.delay(0.25, function()
            if not self.destroyed and self.enabled and not self.running then
                self:_schedule()
            end
        end)
        return
    end

    self.phase = "priming"
    self.baitRagdollBaseline = LocalPlayer:GetAttribute("RagdollEndTime") or 0
    self.rearmStartedAt = os.clock()
    self.primerUid = primer.Uid
    self.targetUid = target.Uid
    self.activeTarget = primer
    self.running = true
    self:_setStatus("Teleporting to primer")

    local dest = self:_resolveEggDestination(primer, root, hum)
    if not dest then self:_finish("Primer destination unavailable"); return end
	icSetAnchored(false)
    if not icTeleportHops(root, dest) then self:_finish("Teleport primer failed") return end
    self:_setArrivalHold(dest, primer.Uid, "primer")
    self:_requestCarry(primer, true)

    task.delay(2.5, function()
        if not self.destroyed and self.enabled and not self.carryActive and self.phase == "priming" then
            self:_finish("Primer carry timeout: retry")
        end
    end)
end

function InstantCarry:_requestCarry(record, teleportReapproach)
    local AreaEggSlotIdentity = require(ReplicatedStorage.Shared.Util.AreaEggSlotIdentity)
    if not self.running then return end
    local uid = record.Uid
    local attemptToken = {}
    self.carryAttemptToken = attemptToken
    self:_setStatus("Securing egg")
    task.spawn(function()
        local deadline = os.clock() + 2
        while self.enabled and not self.destroyed and self.running
            and self.carryAttemptToken == attemptToken
            and self.activeTarget and self.activeTarget.Uid == uid
        do
            if self.carryActive and self.carryUid == uid and self:_recordShowsCarried(uid) then
                self.carryAttemptToken = nil
                return
            end
            if os.clock() >= deadline then
                self.carryAttemptToken = nil
                self:_clearArrivalHold(uid)
                local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if root and not icIsInSafeArea(root) then
                    icTeleportRoot(root, CFrame.new(IC_SAFE_ZONE_POS) * root.CFrame.Rotation)
                end
                self:_finish("Carry confirmation timeout")
                return
            end
            local EggCmds = require(ReplicatedStorage.Client.EggState)
            local current = EggCmds.ReadFieldEgg(uid) or self.records[uid]
            if not current then self:_finish("Target unavailable"); return end
            if current.State == "Carried" and current.CarrierUserId ~= LocalPlayer.UserId then
                self:_finish("Egg carried by another player")
                return
            end
            local character = LocalPlayer.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local destination = self:_resolveEggDestination(current, root, humanoid)
            if not destination then self:_finish("Character unavailable"); return end
            if (root.Position - destination.Position).Magnitude > 10 then
                if teleportReapproach then
                    if not icTeleportRoot(root, destination) then
                        self:_finish("Egg teleport failed")
                        return
                    end
                end
            end
            local looksLikeFirst = AreaEggSlotIdentity.LooksLikeFirstAreaUid
                or AreaEggSlotIdentity.IsFirstAreaUid
            local slotKey = looksLikeFirst and looksLikeFirst(uid)
                and AreaEggSlotIdentity.SlotKey(current.AreaId, current.NestId)
                or nil
            pcall(icRequestFieldEggCarry, uid, slotKey)
            task.wait(0.08)
        end
    end)
end

function InstantCarry:_startHunt()
    local EggCmds = IC_MODULES.EggState or require(ReplicatedStorage.Client.EggState)
    local AreaEggs = IC_MODULES.AreaEggs
    self:_kbCancelTimer()
    self.phase = "hunting"
    self.primerUid = nil
    self.targetCycleStartedAt = os.clock()

    if EggCmds then
        pcall(function()
            local snapshot = EggCmds.GetAreaEggSnapshot()
            if snapshot then self:_replaceSnapshot(snapshot) end
        end)
    end
    local latestBest = self:_chooseTarget()
    if latestBest then self.targetUid = latestBest.Uid end

    local targetUid = self.targetUid
    self.targetUid = nil
    if not targetUid then self:_finish("No target"); return end

    local current = nil
    if type(EggCmds.ReadFieldEgg) == "function" then
        current = EggCmds.ReadFieldEgg(targetUid)
    end
    if not current then current = self.records[targetUid] end

    if not current or (current.State ~= AreaEggs.States.Slot and current.State ~= AreaEggs.States.Dropped) then
        self:_finish("Target gone"); return
    end

    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum then self:_finish("No character"); return end

    self.activeTarget = current
    self:_setStatus("Teleporting to target")
	local dest = self:_resolveEggDestination(current, root, hum)
	if not dest then self:_finish("Target destination unavailable"); return end
	self:_enforceArrivalHold()
	icSetAnchored(false)
	self:_clearArrivalHold()
    if not icTeleportHops(root, dest) then self:_finish("Teleport target failed") return end

    self:_setStatus("Securing target")
    self:_requestCarry(current, true)

    task.spawn(function()
        while not self.destroyed and self.enabled and not self.carryActive and self.phase == "hunting" do
            local tEnd = LocalPlayer:GetAttribute("RagdollEndTime") or 0
            local rawRemaining = tEnd - workspace:GetServerTimeNow()
            if rawRemaining <= 0.85 then
                local char = LocalPlayer.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                if root and not icIsInSafeArea(root) then
                    icTeleportRoot(root, CFrame.new(IC_SAFE_ZONE_POS) * root.CFrame.Rotation)
                end
                self:_finish("Ragdoll expiring: emergency abort")
                break
            end
            task.wait(0.02)
        end
    end)
    
    task.delay(0.25, function()
        if not self.destroyed and self.enabled and not self.carryActive and self.phase == "hunting" then
            local char = LocalPlayer.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root and not icIsInSafeArea(root) then
                icTeleportRoot(root, CFrame.new(IC_SAFE_ZONE_POS) * root.CFrame.Rotation)
            end
            self:_finish("Carry timeout: return safe")
        end
    end)
end
function InstantCarry:_returnToSafe()
    local uid = self.carryUid
    local worker = self:_claimCarryWorker("return", uid)
    if not worker then return end
    self:_clearArrivalHold(uid)
    if not self.carryActive or self:_recordShowsForeignCarry(uid) then
        self:_releaseCarryWorker(worker)
        self:_finish("Carry not confirmed")
        return
    end

    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then self:_releaseCarryWorker(worker); self:_finish("No character"); return end

    local safeDest = CFrame.new(IC_SAFE_ZONE_POS) * root.CFrame.Rotation
    if not icIsInSafeArea(root) then
        self:_setStatus("Teleporting to safe area")
        if not icTeleportHops(root, safeDest) then
            self:_releaseCarryWorker(worker)
            self:_finish("Safe teleport failed")
            return
        end
    end
	self:_setArrivalHold(safeDest, uid, "safe")
	icSetAnchored(false)

    local stableSince = os.clock()
    local deadline = os.clock() + 3.5
    while self:_isCarryWorkerCurrent(worker) and self.carryActive and os.clock() < deadline do
        local r = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not r then self:_releaseCarryWorker(worker); self:_finish("No character"); return end
        if os.clock() - stableSince >= 0.1 then self:_setStatus("Waiting for deposit") end
        
        local tEnd = LocalPlayer:GetAttribute("RagdollEndTime") or 0
        local rawRemaining = tEnd - workspace:GetServerTimeNow()
        if rawRemaining <= 0.45 then
            break
        end
        
        task.wait(0.02)
    end
    if not self:_isCarryWorkerCurrent(worker) then return end
    if not self.carryActive then
        self:_releaseCarryWorker(worker)
        self:_finish("Safe return complete")
        return
    end
    self:_setStatus("Deposit pending")
    self:_releaseCarryWorker(worker)
    if self.depositRetryScheduled then return end
    self.depositRetryScheduled = true
    local retryGeneration = self.carryGeneration
    task.delay(0.05, function()
        self.depositRetryScheduled = false
        if self.enabled and self.carryActive and self.carryGeneration == retryGeneration then
            self:_returnToSafe()
        end
    end)
end

function InstantCarry:_reStealDroppedEgg(uid)
    if type(uid) ~= "string" or uid == "" then self:_finish("Egg lost"); return end
    local worker = self:_claimCarryWorker("re-steal", uid)
    if not worker then return end
    task.spawn(function()
        local EggCmds = require(ReplicatedStorage.Client.EggState)
        local record = nil
        local deadline = os.clock() + 5
        self:_setStatus("Re-stealing dropped egg")
        while self:_isCarryWorkerCurrent(worker) and os.clock() < deadline do
            local candidate = EggCmds.ReadFieldEgg(uid) or self.records[uid]
            if candidate and (candidate.State == "Dropped" or candidate.State == "Slot") then
                record = candidate
                break
            end
            task.wait(0.03)
        end
        if not self:_isCarryWorkerCurrent(worker) then return end
        if not record then self:_releaseCarryWorker(worker); self:_finish("Egg lost"); return end
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local destination = self:_resolveEggDestination(record, root, humanoid)
        if not destination then self:_releaseCarryWorker(worker); self:_finish("No character"); return end
        self.activeTarget = record
        self.phase = "hunting"
        self.running = true
        if not icTeleportRoot(root, destination) then
            self:_releaseCarryWorker(worker)
            self:_finish("Dropped egg teleport failed")
            return
        end
        self:_releaseCarryWorker(worker)
        self:_requestCarry(record, true)
    end)
end

function InstantCarry:_setArrivalHold(cframe, uid, phase)
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if character and root and typeof(cframe) == "CFrame" then
        self.arrivalHold = {
			Character = character,
			RootPart = root,
			CFrame = cframe,
			Uid = uid,
			Phase = phase,
		}
    end
end

function InstantCarry:_clearArrivalHold(uid)
    if not self.arrivalHold then return end
    if uid == nil or self.arrivalHold.Uid == nil or self.arrivalHold.Uid == uid then
        self.arrivalHold = nil
    end
end

function InstantCarry:_enforceArrivalHold()
    local hold = self.arrivalHold
    if not hold or typeof(hold.CFrame) ~= "CFrame" then return end
    if LocalPlayer.Character ~= hold.Character or not hold.RootPart or not hold.RootPart.Parent then
        self.arrivalHold = nil
        return
    end
    local root = hold.RootPart
    pcall(function()
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.CFrame = hold.CFrame
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
    end)
end

function InstantCarry:_finish(reason)
    self.carryGeneration = self.carryGeneration + 1
    self:_invalidateCarryWorker()
    self.carryAttemptToken = nil
    self.depositRetryScheduled = false
    self.targetCycleStartedAt = nil
    self.phase = "idle"
    self.primerUid = nil
    self.targetUid = nil
    self.activeTarget = nil
    self.running = false
    icSetAnchored(false)
    self:_clearArrivalHold()
    self:_kbCancelTimer()
    self.planGeneration = self.planGeneration + 1
    self:_setStatus("Idle")

    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if self.enabled and root and not icIsInSafeArea(root) then
        local safeDest = CFrame.new(IC_SAFE_ZONE_POS) * root.CFrame.Rotation
        icTeleportRoot(root, safeDest)
    end
    if self.enabled then
        local tEnd = LocalPlayer:GetAttribute("RagdollEndTime") or 0
        local rawRemaining = tEnd - workspace:GetServerTimeNow()
        local canChain = rawRemaining >= (self.targetCycleSeconds + self.rearmSeconds + 0.35)
        local nextTarget = canChain and self:_chooseTarget()
        
        if canChain and nextTarget then
            self:_setStatus("Next target")
            task.defer(function()
                if not self.destroyed and self.enabled and not self.running then
                    self.targetUid = nextTarget.Uid
                    self.running = true
                    self:_startHunt()
                end
            end)
        else
            self:_schedule(true)
        end
    end
end

function InstantCarry:setEnabled(value)
    self.enabled = value == true
    if self.enabled then
        local EggCmds = require(ReplicatedStorage.Client.EggState)
        startGlobalMovementProtection()
        self:_setStatus("Starting")
        self:_replaceSnapshot(EggCmds.GetAreaEggSnapshot())
        self:_schedule()
    else
        self.carryGeneration = self.carryGeneration + 1
        self:_invalidateCarryWorker()
        self.carryAttemptToken = nil
        self.carryActive = false
        self.carryUid = nil
        self.targetCycleStartedAt = nil
        self.rearmStartedAt = nil
        self.planGeneration = self.planGeneration + 1
        self:_kbCancelTimer()
        icSetAnchored(false)
        self:_clearArrivalHold()
        self:_finish("Disabled")
        if not fieldStealEnabled() then stopGlobalMovementProtection() end
    end
end

function InstantCarry:destroy()
    self.destroyed = true
    self.enabled = false
    self.carryGeneration = self.carryGeneration + 1
    self:_invalidateCarryWorker()
    self.carryAttemptToken = nil
    self.targetCycleStartedAt = nil
    self.rearmStartedAt = nil
    self:_kbCancelTimer()
    icSetAnchored(false)
    self:_finish("Destroyed")
    for _, c in ipairs(self.connections) do
        pcall(c.Disconnect, c)
    end
    table.clear(self.connections)
    table.clear(self.records)
end

local previousIcRunner = runtimeEnv.icRunner
if type(previousIcRunner) == "table" and type(previousIcRunner.destroy) == "function" then
	pcall(previousIcRunner.destroy, previousIcRunner)
end
local icRunner = InstantCarry.new()
getgenv().icRunner = icRunner
getgenv().ZeroinConfig = Config
getgenv().stopAllActiveMovements = stopAllActiveMovements
getgenv().stopGlobalMovementProtection = stopGlobalMovementProtection
getgenv().startGlobalMovementProtection = startGlobalMovementProtection
getgenv().computeFirstAreaSlotKey = function(uid, areaId, nestId)
    local AreaEggSlotIdentity = IC_MODULES.SlotIdentity
    if not AreaEggSlotIdentity then return nil end
    local looksLikeFirstAreaUid = AreaEggSlotIdentity.LooksLikeFirstAreaUid
        or AreaEggSlotIdentity.IsFirstAreaUid
    local buildSlotKey = AreaEggSlotIdentity.SlotKey
        or AreaEggSlotIdentity.BuildSlotKey
    local isFirstOk, isFirst = pcall(looksLikeFirstAreaUid, tostring(uid))
    if isFirstOk and isFirst and type(areaId) == "string" and type(nestId) == "string" then
        local buildOk, built = pcall(buildSlotKey, areaId, nestId)
        if buildOk then return built end
    end
    return nil
end
getgenv().icRequestFieldEggCarry = icRequestFieldEggCarry
getgenv().fieldStealEnabled = fieldStealEnabled
getgenv().isStealNightBlocked = isStealNightBlocked
--// ===== UI do Natsu Hub =====

local NatsuState = {
    SelectedEggUid = nil,
    Modo = "Tween",
    Running = false,
    EggsCache = {},
    EggOrder = {},
}

local RARITY_COLORS = {
    Common = Color3.fromRGB(180, 180, 180),
    Uncommon = Color3.fromRGB(80, 200, 120),
    Rare = Color3.fromRGB(80, 150, 255),
    Epic = Color3.fromRGB(180, 90, 255),
    Legendary = Color3.fromRGB(255, 180, 60),
    Mythic = Color3.fromRGB(255, 90, 90),
    Cosmic = Color3.fromRGB(255, 100, 220),
    Secret = Color3.fromRGB(255, 220, 100),
    Eternal = Color3.fromRGB(120, 255, 220),
    Divine = Color3.fromRGB(255, 255, 180),
}

local NatsuAssets = require(ReplicatedStorage.Data.Assets).Directory
local NatsuEggCmds = require(ReplicatedStorage.Client.EggState)

local function NatsuGetEggInfo(record)
    local assetData = NatsuAssets[record.AssetCategory]
    local petName = (assetData and assetData.DisplayName) or record.AssetCategory or "?"
    local eggName = assetData and assetData.Egg and assetData.Egg.DisplayName or (petName .. " Egg")
    local rarityObj = assetData and assetData.Rarity
    local rarityName = rarityObj and (rarityObj.DisplayName or rarityObj._id) or "Common"
    local areaName = record.AreaId or "?"
    local color = RARITY_COLORS[rarityName] or Color3.fromRGB(180, 180, 180)
    return {
        petName = petName,
        eggName = eggName,
        rarityName = rarityName,
        areaName = areaName,
        color = color,
    }
end

local RARITY_RANK = {
    Common = 1, Uncommon = 2, Rare = 3, Epic = 4,
    Legendary = 5, Mythic = 6, Cosmic = 7, Secret = 8,
    Eternal = 9, Divine = 10,
}

local function NatsuRefreshCache()
    local snapshot = NatsuEggCmds.ReadFieldEggs()
    local cache = {}
    local orderList = {}
    if snapshot and snapshot.Records then
        for _, record in pairs(snapshot.Records) do
            if record.State == "Slot" or record.State == "Dropped" then
                local info = NatsuGetEggInfo(record)
                local rank = RARITY_RANK[info.rarityName] or 0
                cache[record.Uid] = { record = record, info = info, rank = rank }
                table.insert(orderList, record.Uid)
            end
        end
    end
    table.sort(orderList, function(a, b)
        local ra = cache[a] and cache[a].rank or 0
        local rb = cache[b] and cache[b].rank or 0
        return ra > rb
    end)
    NatsuState.EggsCache = cache
    NatsuState.EggOrder = orderList
end

local natsuGui = Instance.new("ScreenGui")
natsuGui.Name = "NatsuHub"
natsuGui.ResetOnSpawn = false
natsuGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
natsuGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local natsuToggle = Instance.new("TextButton")
natsuToggle.Name = "Toggle"
natsuToggle.Size = UDim2.fromOffset(48, 48)
natsuToggle.Position = UDim2.new(0, 20, 0.5, -24)
natsuToggle.BackgroundColor3 = Color3.fromRGB(25, 20, 40)
natsuToggle.Text = "N"
natsuToggle.TextColor3 = Color3.fromRGB(180, 90, 255)
natsuToggle.TextSize = 25
natsuToggle.Font = Enum.Font.GothamBold
natsuToggle.AutoButtonColor = false
natsuToggle.Parent = natsuGui
local ntc = Instance.new("UICorner"); ntc.CornerRadius = UDim.new(0, 14); ntc.Parent = natsuToggle
local nts = Instance.new("UIStroke"); nts.Color = Color3.fromRGB(145, 60, 255); nts.Thickness = 2; nts.Parent = natsuToggle

local natsuMain = Instance.new("Frame")
natsuMain.Name = "Main"
natsuMain.Size = UDim2.fromOffset(330, 420)
natsuMain.Position = UDim2.new(0.5, -165, 0.5, -210)
natsuMain.BackgroundColor3 = Color3.fromRGB(16, 14, 24)
natsuMain.Visible = true
natsuMain.Parent = natsuGui
local nmc = Instance.new("UICorner"); nmc.CornerRadius = UDim.new(0, 14); nmc.Parent = natsuMain
local nms = Instance.new("UIStroke"); nms.Color = Color3.fromRGB(125, 55, 220); nms.Thickness = 1.5; nms.Parent = natsuMain

local natsuTitle = Instance.new("TextLabel")
natsuTitle.Size = UDim2.new(1, -30, 0, 40)
natsuTitle.Position = UDim2.fromOffset(15, 8)
natsuTitle.BackgroundTransparency = 1
natsuTitle.Text = "Natsu Hub"
natsuTitle.TextColor3 = Color3.fromRGB(210, 150, 255)
natsuTitle.TextSize = 21
natsuTitle.Font = Enum.Font.GothamBold
natsuTitle.TextXAlignment = Enum.TextXAlignment.Left
natsuTitle.Parent = natsuMain

local natsuLine = Instance.new("Frame")
natsuLine.Size = UDim2.new(1, -30, 0, 1)
natsuLine.Position = UDim2.fromOffset(15, 48)
natsuLine.BackgroundColor3 = Color3.fromRGB(65, 50, 85)
natsuLine.BorderSizePixel = 0
natsuLine.Parent = natsuMain

local natsuPetLabel = Instance.new("TextLabel")
natsuPetLabel.Size = UDim2.fromOffset(100, 30)
natsuPetLabel.Position = UDim2.fromOffset(18, 63)
natsuPetLabel.BackgroundTransparency = 1
natsuPetLabel.Text = "Pet"
natsuPetLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
natsuPetLabel.TextSize = 15
natsuPetLabel.Font = Enum.Font.GothamMedium
natsuPetLabel.TextXAlignment = Enum.TextXAlignment.Left
natsuPetLabel.Parent = natsuMain

local natsuPetBtn = Instance.new("TextButton")
natsuPetBtn.Size = UDim2.fromOffset(185, 36)
natsuPetBtn.Position = UDim2.fromOffset(125, 60)
natsuPetBtn.BackgroundColor3 = Color3.fromRGB(27, 24, 38)
natsuPetBtn.Text = "Nenhum  v"
natsuPetBtn.TextColor3 = Color3.fromRGB(230, 230, 240)
natsuPetBtn.TextSize = 13
natsuPetBtn.Font = Enum.Font.Gotham
natsuPetBtn.AutoButtonColor = false
natsuPetBtn.TextTruncate = Enum.TextTruncate.AtEnd
natsuPetBtn.Parent = natsuMain
local npc = Instance.new("UICorner"); npc.CornerRadius = UDim.new(0, 9); npc.Parent = natsuPetBtn
local nps = Instance.new("UIStroke"); nps.Color = Color3.fromRGB(70, 60, 90); nps.Parent = natsuPetBtn

local natsuPetDrop = Instance.new("ScrollingFrame")
natsuPetDrop.Size = UDim2.fromOffset(185, 0)
natsuPetDrop.Position = UDim2.fromOffset(125, 100)
natsuPetDrop.BackgroundColor3 = Color3.fromRGB(23, 20, 32)
natsuPetDrop.BorderSizePixel = 0
natsuPetDrop.Visible = false
natsuPetDrop.ClipsDescendants = true
natsuPetDrop.ZIndex = 20
natsuPetDrop.ScrollBarThickness = 4
natsuPetDrop.ScrollBarImageColor3 = Color3.fromRGB(125, 55, 220)
natsuPetDrop.CanvasSize = UDim2.new(0, 0, 0, 0)
natsuPetDrop.AutomaticCanvasSize = Enum.AutomaticSize.Y
natsuPetDrop.Parent = natsuMain
local npdc = Instance.new("UICorner"); npdc.CornerRadius = UDim.new(0, 9); npdc.Parent = natsuPetDrop
local npdl = Instance.new("UIListLayout"); npdl.Padding = UDim.new(0, 2); npdl.Parent = natsuPetDrop
local npdp = Instance.new("UIPadding"); npdp.PaddingTop = UDim.new(0, 4); npdp.PaddingBottom = UDim.new(0, 4); npdp.Parent = natsuPetDrop

local natsuModoLabel = Instance.new("TextLabel")
natsuModoLabel.Size = UDim2.fromOffset(100, 30)
natsuModoLabel.Position = UDim2.fromOffset(18, 105)
natsuModoLabel.BackgroundTransparency = 1
natsuModoLabel.Text = "Modo"
natsuModoLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
natsuModoLabel.TextSize = 15
natsuModoLabel.Font = Enum.Font.GothamMedium
natsuModoLabel.TextXAlignment = Enum.TextXAlignment.Left
natsuModoLabel.Parent = natsuMain

local natsuModoBtn = Instance.new("TextButton")
natsuModoBtn.Size = UDim2.fromOffset(185, 36)
natsuModoBtn.Position = UDim2.fromOffset(125, 102)
natsuModoBtn.BackgroundColor3 = Color3.fromRGB(27, 24, 38)
natsuModoBtn.Text = "Tween  v"
natsuModoBtn.TextColor3 = Color3.fromRGB(230, 230, 240)
natsuModoBtn.TextSize = 13
natsuModoBtn.Font = Enum.Font.Gotham
natsuModoBtn.AutoButtonColor = false
natsuModoBtn.Parent = natsuMain
local nmdc = Instance.new("UICorner"); nmdc.CornerRadius = UDim.new(0, 9); nmdc.Parent = natsuModoBtn
local nmds = Instance.new("UIStroke"); nmds.Color = Color3.fromRGB(70, 60, 90); nmds.Parent = natsuModoBtn

local natsuModoDrop = Instance.new("Frame")
natsuModoDrop.Size = UDim2.fromOffset(185, 0)
natsuModoDrop.Position = UDim2.fromOffset(125, 142)
natsuModoDrop.BackgroundColor3 = Color3.fromRGB(23, 20, 32)
natsuModoDrop.Visible = false
natsuModoDrop.ClipsDescendants = true
natsuModoDrop.ZIndex = 20
natsuModoDrop.Parent = natsuMain
local nmddc = Instance.new("UICorner"); nmddc.CornerRadius = UDim.new(0, 9); nmddc.Parent = natsuModoDrop
local nmddl = Instance.new("UIListLayout"); nmddl.Padding = UDim.new(0, 2); nmddl.Parent = natsuModoDrop

for _, opt in ipairs({"Tween", "Instant"}) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -6, 0, 32)
    b.BackgroundColor3 = Color3.fromRGB(30, 27, 42)
    b.Text = opt
    b.TextColor3 = Color3.fromRGB(220, 220, 230)
    b.TextSize = 13
    b.Font = Enum.Font.Gotham
    b.AutoButtonColor = false
    b.ZIndex = 21
    b.Parent = natsuModoDrop
    local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 6); bc.Parent = b
    b.MouseButton1Click:Connect(function()
        NatsuState.Modo = opt
        natsuModoBtn.Text = opt .. "  v"
        natsuModoDrop.Visible = false
        TweenService:Create(natsuModoDrop, TweenInfo.new(0.15), {Size = UDim2.fromOffset(185, 0)}):Play()
    end)
end

natsuModoBtn.MouseButton1Click:Connect(function()
    natsuModoDrop.Visible = not natsuModoDrop.Visible
    local target = natsuModoDrop.Visible and UDim2.fromOffset(185, 70) or UDim2.fromOffset(185, 0)
    TweenService:Create(natsuModoDrop, TweenInfo.new(0.15), {Size = target}):Play()
end)
local natsuGoBtn = Instance.new("TextButton")
natsuGoBtn.Size = UDim2.fromOffset(140, 48)
natsuGoBtn.Position = UDim2.fromOffset(18, 150)
natsuGoBtn.BackgroundColor3 = Color3.fromRGB(25, 100, 65)
natsuGoBtn.Text = ">  GO"
natsuGoBtn.TextColor3 = Color3.fromRGB(235, 255, 245)
natsuGoBtn.TextSize = 16
natsuGoBtn.Font = Enum.Font.GothamBold
natsuGoBtn.AutoButtonColor = false
natsuGoBtn.Parent = natsuMain
local ngc = Instance.new("UICorner"); ngc.CornerRadius = UDim.new(0, 10); ngc.Parent = natsuGoBtn
local ngs = Instance.new("UIStroke"); ngs.Color = Color3.fromRGB(30, 220, 130); ngs.Thickness = 1.5; ngs.Parent = natsuGoBtn

local natsuStopBtn = Instance.new("TextButton")
natsuStopBtn.Size = UDim2.fromOffset(140, 48)
natsuStopBtn.Position = UDim2.fromOffset(172, 150)
natsuStopBtn.BackgroundColor3 = Color3.fromRGB(105, 30, 40)
natsuStopBtn.Text = "[]  STOP"
natsuStopBtn.TextColor3 = Color3.fromRGB(255, 235, 235)
natsuStopBtn.TextSize = 16
natsuStopBtn.Font = Enum.Font.GothamBold
natsuStopBtn.AutoButtonColor = false
natsuStopBtn.Parent = natsuMain
local nsc = Instance.new("UICorner"); nsc.CornerRadius = UDim.new(0, 10); nsc.Parent = natsuStopBtn
local nss = Instance.new("UIStroke"); nss.Color = Color3.fromRGB(240, 65, 80); nss.Thickness = 1.5; nss.Parent = natsuStopBtn

local natsuStatus = Instance.new("TextLabel")
natsuStatus.Size = UDim2.new(1, -30, 0, 20)
natsuStatus.Position = UDim2.fromOffset(18, 205)
natsuStatus.BackgroundTransparency = 1
natsuStatus.Text = "Parado"
natsuStatus.TextColor3 = Color3.fromRGB(150, 150, 165)
natsuStatus.TextSize = 12
natsuStatus.Font = Enum.Font.Gotham
natsuStatus.TextXAlignment = Enum.TextXAlignment.Left
natsuStatus.Parent = natsuMain

local natsuLine2 = Instance.new("Frame")
natsuLine2.Size = UDim2.new(1, -30, 0, 1)
natsuLine2.Position = UDim2.fromOffset(15, 230)
natsuLine2.BackgroundColor3 = Color3.fromRGB(65, 50, 85)
natsuLine2.BorderSizePixel = 0
natsuLine2.Parent = natsuMain

local natsuEggsTitle = Instance.new("TextLabel")
natsuEggsTitle.Size = UDim2.new(1, -100, 0, 22)
natsuEggsTitle.Position = UDim2.fromOffset(18, 235)
natsuEggsTitle.BackgroundTransparency = 1
natsuEggsTitle.Text = "Ovos no campo (0)"
natsuEggsTitle.TextColor3 = Color3.fromRGB(210, 150, 255)
natsuEggsTitle.TextSize = 13
natsuEggsTitle.Font = Enum.Font.GothamBold
natsuEggsTitle.TextXAlignment = Enum.TextXAlignment.Left
natsuEggsTitle.Parent = natsuMain

local natsuRefreshBtn = Instance.new("TextButton")
natsuRefreshBtn.Size = UDim2.fromOffset(70, 20)
natsuRefreshBtn.Position = UDim2.new(1, -88, 0, 236)
natsuRefreshBtn.BackgroundColor3 = Color3.fromRGB(40, 30, 60)
natsuRefreshBtn.Text = "Refresh"
natsuRefreshBtn.TextColor3 = Color3.fromRGB(200, 170, 255)
natsuRefreshBtn.TextSize = 11
natsuRefreshBtn.Font = Enum.Font.GothamMedium
natsuRefreshBtn.AutoButtonColor = false
natsuRefreshBtn.Parent = natsuMain
local nrbc = Instance.new("UICorner"); nrbc.CornerRadius = UDim.new(0, 6); nrbc.Parent = natsuRefreshBtn

local natsuEggList = Instance.new("ScrollingFrame")
natsuEggList.Size = UDim2.new(1, -30, 1, -275)
natsuEggList.Position = UDim2.fromOffset(15, 262)
natsuEggList.BackgroundColor3 = Color3.fromRGB(20, 18, 30)
natsuEggList.BorderSizePixel = 0
natsuEggList.ScrollBarThickness = 5
natsuEggList.ScrollBarImageColor3 = Color3.fromRGB(125, 55, 220)
natsuEggList.CanvasSize = UDim2.new(0, 0, 0, 0)
natsuEggList.AutomaticCanvasSize = Enum.AutomaticSize.Y
natsuEggList.Parent = natsuMain
local nelc = Instance.new("UICorner"); nelc.CornerRadius = UDim.new(0, 8); nelc.Parent = natsuEggList
local nell = Instance.new("UIListLayout"); nell.Padding = UDim.new(0, 4); nell.Parent = natsuEggList
local nelp = Instance.new("UIPadding")
nelp.PaddingTop = UDim.new(0, 6); nelp.PaddingBottom = UDim.new(0, 6)
nelp.PaddingLeft = UDim.new(0, 6); nelp.PaddingRight = UDim.new(0, 6)
nelp.Parent = natsuEggList

local function natsuClearList()
    for _, c in ipairs(natsuEggList:GetChildren()) do
        if c:IsA("Frame") or c:IsA("TextButton") then
            c:Destroy()
        end
    end
end

local lastRenderSignature = ""

local function natsuRenderList(force)
    local uids = NatsuState.EggOrder
    local sig = table.concat(uids, ",")
    if not force and sig == lastRenderSignature then return end
    lastRenderSignature = sig
    natsuClearList()
    natsuEggsTitle.Text = "Ovos no campo (" .. #uids .. ")"

    if #uids == 0 then
        local empty = Instance.new("TextLabel")
        empty.Size = UDim2.new(1, 0, 0, 40)
        empty.BackgroundTransparency = 1
        empty.Text = "Nenhum ovo disponivel no campo"
        empty.TextColor3 = Color3.fromRGB(120, 120, 140)
        empty.TextSize = 12
        empty.Font = Enum.Font.Gotham
        empty.Parent = natsuEggList
        return
    end

    for _, uid in ipairs(uids) do
        local entry = NatsuState.EggsCache[uid]
        if entry then
            local info = entry.info
            local card = Instance.new("Frame")
            card.Size = UDim2.new(1, 0, 0, 46)
            card.BackgroundColor3 = Color3.fromRGB(28, 24, 40)
            card.BorderSizePixel = 0
            card.Parent = natsuEggList
            local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 7); cc.Parent = card

            local bar = Instance.new("Frame")
            bar.Size = UDim2.new(0, 4, 1, -8)
            bar.Position = UDim2.new(0, 0, 0, 4)
            bar.BackgroundColor3 = info.color
            bar.BorderSizePixel = 0
            bar.Parent = card
            local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(1, 0); bc.Parent = bar

            local nameLbl = Instance.new("TextLabel")
            nameLbl.Size = UDim2.new(1, -140, 0, 16)
            nameLbl.Position = UDim2.fromOffset(12, 4)
            nameLbl.BackgroundTransparency = 1
            nameLbl.Text = info.eggName
            nameLbl.TextColor3 = Color3.fromRGB(235, 235, 245)
            nameLbl.TextSize = 12
            nameLbl.Font = Enum.Font.GothamBold
            nameLbl.TextXAlignment = Enum.TextXAlignment.Left
            nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
            nameLbl.Parent = card

            local subLbl = Instance.new("TextLabel")
            subLbl.Size = UDim2.new(1, -140, 0, 14)
            subLbl.Position = UDim2.fromOffset(12, 22)
            subLbl.BackgroundTransparency = 1
            subLbl.Text = info.areaName .. " - " .. info.rarityName
            subLbl.TextColor3 = info.color
            subLbl.TextSize = 10
            subLbl.Font = Enum.Font.Gotham
            subLbl.TextXAlignment = Enum.TextXAlignment.Left
            subLbl.Parent = card

            local selBtn = Instance.new("TextButton")
            selBtn.Size = UDim2.fromOffset(50, 20)
            selBtn.Position = UDim2.new(1, -116, 0, 4)
            selBtn.BackgroundColor3 = Color3.fromRGB(90, 50, 160)
            selBtn.Text = "Sel"
            selBtn.TextColor3 = Color3.fromRGB(240, 230, 255)
            selBtn.TextSize = 11
            selBtn.Font = Enum.Font.GothamBold
            selBtn.AutoButtonColor = false
            selBtn.Parent = card
            local sbc = Instance.new("UICorner"); sbc.CornerRadius = UDim.new(0, 5); sbc.Parent = selBtn

            local gotoBtn = Instance.new("TextButton")
            gotoBtn.Size = UDim2.fromOffset(50, 20)
            gotoBtn.Position = UDim2.new(1, -60, 0, 4)
            gotoBtn.BackgroundColor3 = Color3.fromRGB(30, 100, 80)
            gotoBtn.Text = "Goto"
            gotoBtn.TextColor3 = Color3.fromRGB(220, 255, 240)
            gotoBtn.TextSize = 11
            gotoBtn.Font = Enum.Font.GothamBold
            gotoBtn.AutoButtonColor = false
            gotoBtn.Parent = card
            local gbc = Instance.new("UICorner"); gbc.CornerRadius = UDim.new(0, 5); gbc.Parent = gotoBtn

            selBtn.MouseButton1Click:Connect(function()
                NatsuState.SelectedEggUid = uid
                natsuPetBtn.Text = info.eggName .. "  v"
                natsuStatus.Text = "Selecionado: " .. info.eggName
                natsuStatus.TextColor3 = Color3.fromRGB(200, 180, 255)
            end)

            gotoBtn.MouseButton1Click:Connect(function()
                local char = LocalPlayer.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if not root or not hum then return end
                local rec = NatsuEggCmds.ReadFieldEgg(uid)
                if not rec or typeof(rec.BottomCFrame) ~= "CFrame" then
                    natsuStatus.Text = "Ovo sumiu"
                    natsuStatus.TextColor3 = Color3.fromRGB(255, 150, 80)
                    return
                end
                natsuStatus.Text = "Indo ate " .. info.eggName
                natsuStatus.TextColor3 = Color3.fromRGB(60, 230, 140)

                task.spawn(function()
                    local dest = CFrame.new(rec.BottomCFrame.Position + Vector3.new(0, 3.5, 0))
                    pcall(function()
                        TweenMoveTo(root, hum, dest, function() return false end, false)
                    end)
                    local slotKey = getgenv().computeFirstAreaSlotKey and getgenv().computeFirstAreaSlotKey(rec.Uid, rec.AreaId, rec.NestId)
                    for _ = 1, 5 do
                        local ok2, res = pcall(icRequestFieldEggCarry, rec.Uid, slotKey)
                        if ok2 and res == true then
                            natsuStatus.Text = "Ovo pego: " .. info.eggName
                            return
                        end
                        task.wait(0.2)
                    end
                    natsuStatus.Text = "Cheguei mas nao deu pra pegar"
                    natsuStatus.TextColor3 = Color3.fromRGB(255, 150, 80)
                end)
            end)
        end
    end
end

local function natsuRebuildDrop()
    for _, c in ipairs(natsuPetDrop:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end

    if #NatsuState.EggOrder == 0 then
        local empty = Instance.new("TextButton")
        empty.Size = UDim2.new(1, -6, 0, 30)
        empty.BackgroundColor3 = Color3.fromRGB(30, 27, 42)
        empty.Text = "Nenhum ovo"
        empty.TextColor3 = Color3.fromRGB(150, 150, 165)
        empty.TextSize = 12
        empty.Font = Enum.Font.Gotham
        empty.AutoButtonColor = false
        empty.ZIndex = 21
        empty.Parent = natsuPetDrop
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = empty
        return
    end

    for _, uid in ipairs(NatsuState.EggOrder) do
        local entry = NatsuState.EggsCache[uid]
        if entry then
            local info = entry.info
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(1, -6, 0, 30)
            b.BackgroundColor3 = Color3.fromRGB(30, 27, 42)
            b.Text = "  " .. info.eggName .. " - " .. info.areaName
            b.TextColor3 = Color3.fromRGB(220, 220, 230)
            b.TextSize = 11
            b.Font = Enum.Font.Gotham
            b.AutoButtonColor = false
            b.TextXAlignment = Enum.TextXAlignment.Left
            b.TextTruncate = Enum.TextTruncate.AtEnd
            b.ZIndex = 21
            b.Parent = natsuPetDrop
            local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 6); bc.Parent = b

            local bar = Instance.new("Frame")
            bar.Size = UDim2.fromOffset(3, 18)
            bar.Position = UDim2.fromOffset(4, 6)
            bar.BackgroundColor3 = info.color
            bar.BorderSizePixel = 0
            bar.ZIndex = 22
            bar.Parent = b
            local brc = Instance.new("UICorner"); brc.CornerRadius = UDim.new(1, 0); brc.Parent = bar

            b.MouseButton1Click:Connect(function()
                NatsuState.SelectedEggUid = uid
                natsuPetBtn.Text = info.eggName .. "  v"
                natsuPetDrop.Visible = false
                TweenService:Create(natsuPetDrop, TweenInfo.new(0.15), {Size = UDim2.fromOffset(185, 0)}):Play()
            end)
        end
    end
end

natsuPetBtn.MouseButton1Click:Connect(function()
    natsuPetDrop.Visible = not natsuPetDrop.Visible
    local target
    if natsuPetDrop.Visible then
        local h = math.clamp(#NatsuState.EggOrder * 32 + 8, 40, 200)
        target = UDim2.fromOffset(185, h)
    else
        target = UDim2.fromOffset(185, 0)
    end
    TweenService:Create(natsuPetDrop, TweenInfo.new(0.15), {Size = target}):Play()
end)
natsuGoBtn.MouseButton1Click:Connect(function()
    if NatsuState.Running then
        natsuStatus.Text = "Ja executando"
        natsuStatus.TextColor3 = Color3.fromRGB(255, 190, 80)
        return
    end

    if not NatsuState.SelectedEggUid then
        natsuStatus.Text = "Selecione um ovo primeiro"
        natsuStatus.TextColor3 = Color3.fromRGB(255, 190, 80)
        return
    end

    if isStealNightBlocked and isStealNightBlocked() then
        natsuStatus.Text = "Noite - aguarde o dia"
        natsuStatus.TextColor3 = Color3.fromRGB(255, 150, 80)
        return
    end

    NatsuState.Running = true
    local entry = NatsuState.EggsCache[NatsuState.SelectedEggUid]
    local nome = entry and entry.info.eggName or "Ovo"
    natsuStatus.Text = "Roubando: " .. nome
    natsuStatus.TextColor3 = Color3.fromRGB(60, 230, 140)

    task.spawn(function()
        local uid = NatsuState.SelectedEggUid
        local rec = NatsuEggCmds.ReadFieldEgg(uid)
        if not rec or typeof(rec.BottomCFrame) ~= "CFrame" then
            natsuStatus.Text = "Ovo sumiu do campo"
            natsuStatus.TextColor3 = Color3.fromRGB(255, 150, 80)
            NatsuState.Running = false
            return
        end

        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not root or not hum then
            natsuStatus.Text = "Sem personagem"
            NatsuState.Running = false
            return
        end

        local oldSpeed = Config.TweenSpeedMultiplier
        Config.TweenSpeedMultiplier = (NatsuState.Modo == "Instant") and 100 or 40
        TweenMoveTo(root, hum, CFrame.new(rec.BottomCFrame.Position + Vector3.new(0, 3.5, 0)),
            function() return not NatsuState.Running end, false)
        Config.TweenSpeedMultiplier = oldSpeed

        if not NatsuState.Running then return end

        local slotKey = getgenv().computeFirstAreaSlotKey and getgenv().computeFirstAreaSlotKey(rec.Uid, rec.AreaId, rec.NestId)
        local pego = false
        for _ = 1, 10 do
            if not NatsuState.Running then return end
            local ok, res = pcall(icRequestFieldEggCarry, rec.Uid, slotKey)
            if ok and res == true then
                pego = true
                break
            end
            task.wait(0.15)
        end

        if pego then
            natsuStatus.Text = "Pego: " .. nome
            natsuStatus.TextColor3 = Color3.fromRGB(60, 230, 140)
        else
            natsuStatus.Text = "Nao consegui pegar"
            natsuStatus.TextColor3 = Color3.fromRGB(255, 150, 80)
        end
        NatsuState.Running = false
    end)
end)

natsuStopBtn.MouseButton1Click:Connect(function()
    Config.AutoSteal = false
    Config.AutoParasiteSteal = false
    if icRunner then icRunner:setEnabled(false) end
    stopAllActiveMovements()
    stopGlobalMovementProtection()

    NatsuState.Running = false
    natsuStatus.Text = "Parado"
    natsuStatus.TextColor3 = Color3.fromRGB(150, 150, 165)
end)

local natsuOpened = true
natsuToggle.MouseButton1Click:Connect(function()
    natsuOpened = not natsuOpened
    if natsuOpened then
        natsuMain.Visible = true
        natsuMain.Size = UDim2.fromOffset(0, 0)
        TweenService:Create(natsuMain, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Size = UDim2.fromOffset(330, 420)}):Play()
    else
        local a = TweenService:Create(natsuMain, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {Size = UDim2.fromOffset(0, 0)})
        a:Play()
        a.Completed:Connect(function()
            if not natsuOpened then natsuMain.Visible = false end
        end)
    end
end)

local function natsuFullRefresh()
    NatsuRefreshCache()
    natsuRenderList()
    natsuRebuildDrop()

    if NatsuState.SelectedEggUid and not NatsuState.EggsCache[NatsuState.SelectedEggUid] then
        NatsuState.SelectedEggUid = nil
        natsuPetBtn.Text = "Nenhum  v"
    end
end

natsuRefreshBtn.MouseButton1Click:Connect(function()
    pcall(function() NatsuEggCmds.RequestAreaEggSnapshot() end)
    task.wait(0.3)
    natsuFullRefresh()
    natsuStatus.Text = "Lista atualizada"
    natsuStatus.TextColor3 = Color3.fromRGB(200, 180, 255)
end)

local refreshQueued = false
local function queueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    task.delay(1.5, function()
        refreshQueued = false
        pcall(natsuFullRefresh)
    end)
end

pcall(function()
    NatsuEggCmds.FieldShifted:Connect(queueRefresh)
    NatsuEggCmds.FieldGone:Connect(queueRefresh)
    NatsuEggCmds.FieldRefreshed:Connect(queueRefresh)
end)

task.spawn(function()
    while true do
        task.wait(5)
        pcall(natsuFullRefresh)
    end
end)

task.spawn(function()
    task.wait(1)
    pcall(function() NatsuEggCmds.RequestAreaEggSnapshot() end)
    task.wait(0.5)
    natsuFullRefresh()
end)

print("[Natsu Hub] Carregado com sucesso!")
