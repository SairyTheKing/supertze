local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local FLY_KEY = Enum.KeyCode.H
local BOOST_KEY = Enum.KeyCode.E
local FLY_SPEED = 250
local BOOST_SPEED = 450
local BOOST_DURATION = 2

local isFlying = false
local isBoosting = false
local currentVelocity = Vector3.new(0, 0, 0)
local activeFlySpeed = FLY_SPEED

local character, hrp, humanoid, animator
local bodyVelocity, bodyGyro
local windSound
local flyAnimations = {}
local auraParticles = {}
local controls

local ANIM_IDS = {
    Forward = "rbxassetid://72366420543231",
    Backward = "rbxassetid://107832088158981",
    Right = "rbxassetid://83786328363421",
    Left = "rbxassetid://138713721731601",
    Hover = "rbxassetid://91428863336534"
}

local function shakeCamera(magnitude, duration)
    task.spawn(function()
        local startTime = tick()
        while tick() - startTime < duration do
            local offset = Vector3.new(
                math.random(-100, 100) / 100 * magnitude,
                math.random(-100, 100) / 100 * magnitude,
                math.random(-100, 100) / 100 * magnitude
            )
            camera.CFrame = camera.CFrame * CFrame.new(offset)
            RunService.RenderStepped:Wait()
        end
    end)
end

local function getReplicatedAsset(path)
    local current = ReplicatedStorage
    for _, name in ipairs(path) do
        current = current and current:FindFirstChild(name)
    end
    return current
end

local function setAnimWeight(name, weight)
    local track = flyAnimations[name]
    if not track then return end
    
    if weight > 0 then
        if not track.IsPlaying then track:Play(0.18) end
        track:AdjustWeight(weight, 0.18)
    else
        if track.IsPlaying then
            track:AdjustWeight(0, 0.18)
            task.delay(0.2, function()
                if track.IsPlaying and track.Weight <= 0.01 then track:Stop(0) end
            end)
        end
    end
end

local function updateAnimations(vel, speed, boosting)
    local hrpCF = hrp.CFrame
    local fwd, bwd, rgt, lft = 0, 0, 0, 0
    
    if speed > 2 then
        local dir = vel.Unit
        local dotF = dir:Dot(hrpCF.LookVector)
        local dotR = dir:Dot(hrpCF.RightVector)
        fwd = math.max(0, dotF)
        bwd = math.max(0, -dotF)
        rgt = math.max(0, dotR)
        lft = math.max(0, -dotR)
    end
    
    local sum = fwd + bwd + rgt + lft
    if sum > 0 then
        fwd, bwd, rgt, lft = fwd/sum, bwd/sum, rgt/sum, lft/sum
    end
    
    local isMovingForward = fwd > 0.5 and rgt < 0.15 and lft < 0.15
    
    if boosting then
        setAnimWeight("Forward", fwd > 0.05 and 1 or 0)
        setAnimWeight("Backward", 0)
        setAnimWeight("Right", 0)
        setAnimWeight("Left", 0)
        if fwd <= 0.05 then
            setAnimWeight("Hover", 1)
        else
            setAnimWeight("Hover", 0)
        end
        return
    end

    if sum <= 0.1 then
        setAnimWeight("Hover", 1)
        setAnimWeight("Forward", 0)
        setAnimWeight("Backward", 0)
        setAnimWeight("Right", 0)
        setAnimWeight("Left", 0)
    else
        if isMovingForward then
            setAnimWeight("Hover", 0.35)
        else
            setAnimWeight("Hover", 0)
        end
        setAnimWeight("Forward", fwd > 0.05 and fwd or 0)
        setAnimWeight("Backward", bwd > 0.05 and bwd or 0)
        setAnimWeight("Right", rgt > 0.05 and rgt or 0)
        setAnimWeight("Left", lft > 0.05 and lft or 0)
    end
end

local function attachAura()
    local limbs = {"Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg"}
    for _, limbName in ipairs(limbs) do
        local limb = character:FindFirstChild(limbName)
        if limb then
            local emitter = Instance.new("ParticleEmitter")
            emitter.Name = "AuraParticle"
            emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 127))
            emitter.LightEmission = 1
            emitter.LightInfluence = 0
            emitter.Size = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.5),
                NumberSequenceKeypoint.new(1, 0)
            })
            emitter.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.2),
                NumberSequenceKeypoint.new(1, 1)
            })
            emitter.Lifetime = NumberRange.new(0.3, 0.6)
            emitter.Rate = 30
            emitter.Speed = NumberRange.new(1, 3)
            emitter.SpreadAngle = Vector2.new(180, 180)
            emitter.RotSpeed = NumberRange.new(-45, 45)
            emitter.Rotation = NumberRange.new(0, 360)
            emitter.LockedToPart = false
            emitter.VelocityInheritance = 1
            emitter.Parent = limb
            table.insert(auraParticles, emitter)
        end
    end
end

local function removeAura()
    for _, emitter in ipairs(auraParticles) do
        if emitter and emitter.Parent then emitter:Destroy() end
    end
    auraParticles = {}
end

local function loadAnimations()
    flyAnimations = {}
    for name, id in pairs(ANIM_IDS) do
        local anim = Instance.new("Animation")
        anim.AnimationId = id
        local track = animator:LoadAnimation(anim)
        track.Priority = Enum.AnimationPriority.Action4
        if name == "Hover" then track.Looped = true end
        flyAnimations[name] = track
    end
end

local function startFlying()
    if isFlying then return end
    isFlying = true
    humanoid.PlatformStand = true
    
    bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.MaxForce = Vector3.new(50000, 50000, 50000)
    bodyVelocity.Velocity = Vector3.new(0, 0, 0)
    bodyVelocity.Parent = hrp
    
    bodyGyro = Instance.new("BodyGyro")
    bodyGyro.MaxTorque = Vector3.new(50000, 50000, 50000)
    bodyGyro.P = 20000
    bodyGyro.D = 800
    bodyGyro.CFrame = hrp.CFrame
    bodyGyro.Parent = hrp
    
    attachAura()
    
    if windSound then
        windSound:Play()
        TweenService:Create(windSound, TweenInfo.new(0.5), {Volume = 1}):Play()
    end
end

local function stopFlying()
    if not isFlying then return end
    isFlying = false
    isBoosting = false
    activeFlySpeed = FLY_SPEED
    currentVelocity = Vector3.new(0, 0, 0)
    
    if bodyVelocity then bodyVelocity:Destroy() end
    if bodyGyro then bodyGyro:Destroy() end
    
    humanoid.PlatformStand = false
    hrp.Velocity = Vector3.new(0, 0, 0)
    hrp.RotVelocity = Vector3.new(0, 0, 0)
    
    for _, track in pairs(flyAnimations) do
        if track.IsPlaying then track:Stop(0) end
    end
    
    TweenService:Create(camera, TweenInfo.new(0.5), {FieldOfView = 70}):Play()
    
    if windSound then
        TweenService:Create(windSound, TweenInfo.new(0.5), {Volume = 0}):Play()
        task.delay(0.5, function()
            if windSound and not isFlying then windSound:Stop() end
        end)
    end
    
    removeAura()
end

local function startBoost()
    if not isFlying or isBoosting then return end
    isBoosting = true
    activeFlySpeed = BOOST_SPEED
    
    pcall(function()
        local boostVFX = getReplicatedAsset({"Utils", "Misc", "S", "Boost"})
        if boostVFX then
            boostVFX = boostVFX:Clone()
            boostVFX.Parent = workspace:FindFirstChild("Effects") or workspace
            Debris:AddItem(boostVFX, 1.1)
            
            task.delay(0.7, function()
                for _, desc in ipairs(boostVFX:GetDescendants()) do
                    if desc:IsA("Beam") then
                        TweenService:Create(desc, TweenInfo.new(0.4), {Width0 = 0, Width1 = 0}):Play()
                    elseif desc:IsA("ParticleEmitter") then
                        desc.Enabled = false
                    end
                end
            end)
            
            local conn
            conn = RunService.Heartbeat:Connect(function()
                if not boostVFX or not boostVFX.Parent then 
                    if conn then conn:Disconnect() end
                    return 
                end
                if hrp and hrp.Parent then
                    local lookDir = hrp.Velocity
                    if lookDir.Magnitude < 1 then lookDir = hrp.CFrame.LookVector end
                    local targetCF = CFrame.lookAlong(hrp.Position, -lookDir) * CFrame.Angles(0, 0, math.rad(math.random(0, 3)))
                    if boostVFX:IsA("Model") and boostVFX.PrimaryPart then
                        boostVFX:PivotTo(targetCF)
                    elseif boostVFX:IsA("BasePart") then
                        boostVFX.CFrame = targetCF
                    end
                end
            end)
        end
    end)
    
    pcall(function()
        local dashSound = getReplicatedAsset({"Sounds", "Misc", "S", "Dash"})
        if dashSound then
            dashSound = dashSound:Clone()
            dashSound.Parent = hrp
            dashSound:Play()
            Debris:AddItem(dashSound, 2)
        end
    end)
    
    local boostLight = Instance.new("PointLight")
    boostLight.Color = Color3.fromRGB(150, 255, 255)
    boostLight.Brightness = 3
    boostLight.Range = 30
    boostLight.Parent = hrp
    TweenService:Create(boostLight, TweenInfo.new(BOOST_DURATION), {Brightness = 0}):Play()
    Debris:AddItem(boostLight, BOOST_DURATION)
    
    pcall(function()
        local windNum = math.random(1, 5)
        local windVFX = getReplicatedAsset({"Mahito", "BodyRepel", "Wind" .. windNum})
        if windVFX then
            windVFX = windVFX:Clone()
            windVFX.Parent = workspace:FindFirstChild("Effects") or workspace
            Debris:AddItem(windVFX, 0.2)
            
            local lookDir = hrp.Velocity
            if lookDir.Magnitude < 1 then lookDir = hrp.CFrame.LookVector end
            local startCF = CFrame.lookAlong(hrp.Position, lookDir) * CFrame.Angles(math.rad(90), math.rad(math.random(0, 360)), 0)
            
            if windVFX:IsA("Model") and windVFX.PrimaryPart then
                windVFX:PivotTo(startCF)
                for _, desc in ipairs(windVFX:GetDescendants()) do
                    if desc:IsA("BasePart") then
                        desc.Transparency = 0.4
                        desc.Size = Vector3.new(8, 8, 25)
                    end
                end
                TweenService:Create(windVFX.PrimaryPart, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
                    CFrame = startCF + hrp.CFrame.LookVector * 5,
                    Size = Vector3.new(50, 0, 50)
                }):Play()
                TweenService:Create(windVFX.PrimaryPart, TweenInfo.new(0.2), {Transparency = 0.5}):Play()
                task.delay(0.15, function()
                    TweenService:Create(windVFX.PrimaryPart, TweenInfo.new(0.2), {Transparency = 1}):Play()
                end)
            elseif windVFX:IsA("BasePart") then
                windVFX.CFrame = startCF
                windVFX.Transparency = 0.4
                windVFX.Size = Vector3.new(8, 8, 25)
                TweenService:Create(windVFX, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
                    CFrame = startCF + hrp.CFrame.LookVector * 5,
                    Size = Vector3.new(50, 0, 50)
                }):Play()
                TweenService:Create(windVFX, TweenInfo.new(0.2), {Transparency = 0.5}):Play()
                task.delay(0.15, function()
                    TweenService:Create(windVFX, TweenInfo.new(0.2), {Transparency = 1}):Play()
                end)
            end
        end
    end)
    
    shakeCamera(0.8, 0.3)
    
    task.delay(BOOST_DURATION, function()
        isBoosting = false
        local numVal = Instance.new("NumberValue")
        numVal.Value = BOOST_SPEED
        
        local tween = TweenService:Create(numVal, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Value = FLY_SPEED})
        tween:Play()
        
        local conn
        conn = numVal.Changed:Connect(function(val)
            if not isBoosting then
                activeFlySpeed = val
            else
                conn:Disconnect()
                numVal:Destroy()
            end
        end)
        
        tween.Completed:Connect(function()
            conn:Disconnect()
            numVal:Destroy()
            if not isBoosting then activeFlySpeed = FLY_SPEED end
        end)
    end)
end

local function onCharacterAdded(char)
    character = char
    hrp = char:WaitForChild("HumanoidRootPart")
    humanoid = char:WaitForChild("Humanoid")
    animator = humanoid:WaitForChild("Animator")
    
    windSound = Instance.new("Sound")
    windSound.SoundId = "rbxassetid://93035214379043"
    windSound.Looped = true
    windSound.Volume = 0
    windSound.PlaybackSpeed = 1
    windSound.Parent = hrp
    
    loadAnimations()
    
    pcall(function()
        local playerModule = require(player.PlayerScripts:WaitForChild("PlayerModule"))
        controls = playerModule:GetControls()
    end)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then onCharacterAdded(player.Character) end

RunService.RenderStepped:Connect(function(dt)
    if not isFlying or not hrp then return end
    
    local moveVector = Vector3.new(0, 0, 0)
    local camCF = camera.CFrame
    
    if controls then
        local vec = controls:GetMoveVector()
        if vec.Magnitude > 0 then
            moveVector = camCF.RightVector * vec.X - camCF.LookVector * vec.Z
            if moveVector.Magnitude > 0 then moveVector = moveVector.Unit end
        end
    else
        local ix, iz = 0, 0
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then iz = -1 end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then iz = 1 end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then ix = -1 end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then ix = 1 end
        moveVector = camCF.RightVector * ix - camCF.LookVector * iz
        if moveVector.Magnitude > 0 then moveVector = moveVector.Unit end
    end
    
    local targetVelocity = moveVector * activeFlySpeed
    local acceleration = (targetVelocity.Magnitude > currentVelocity.Magnitude) and 4 or 6
    currentVelocity = currentVelocity:Lerp(targetVelocity, math.clamp(acceleration * dt, 0, 1))
    
    if bodyVelocity then bodyVelocity.Velocity = currentVelocity end
    
    if bodyGyro then
        local camLook = camera.CFrame.LookVector
        local targetCFrame = CFrame.new(hrp.Position, hrp.Position + camLook)
        
        local isMoving = currentVelocity.Magnitude > 0.1
        local isMouseLocked = UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
        
        if isMoving or isMouseLocked then
            if not isBoosting then
                targetCFrame = targetCFrame * CFrame.Angles(math.rad(10), 0, 0)
            end
        else
            targetCFrame = bodyGyro.CFrame
        end
        
        bodyGyro.CFrame = bodyGyro.CFrame:Lerp(targetCFrame, math.clamp(dt * 7, 0, 0.3))
    end
    
    updateAnimations(currentVelocity, currentVelocity.Magnitude, isBoosting)
    
    local speed = currentVelocity.Magnitude
    local maxSpeed = FLY_SPEED * 1.6
    local targetFOV = 70 + math.clamp((speed - 50) / maxSpeed, 0, 1) * 40
    camera.FieldOfView = camera.FieldOfView + ((targetFOV - camera.FieldOfView) * dt) * 5
    
    if speed > 50 then
        local shakeMag = math.clamp(speed / maxSpeed, 0, 1) * 0.3
        local offset = Vector3.new(
            math.random(-100, 100) / 100 * shakeMag,
            math.random(-100, 100) / 100 * shakeMag,
            math.random(-100, 100) / 100 * shakeMag
        )
        camera.CFrame = camera.CFrame * CFrame.new(offset)
    end
    
    if windSound then
        windSound.Volume = 1.3 * math.clamp(speed / FLY_SPEED, 0.2, 1)
        windSound.PlaybackSpeed = 0.8 + (speed / FLY_SPEED) * 0.4
    end
    
    if #auraParticles > 0 then
        local velInheritance = speed >= 50 and 0 or 1
        for _, emitter in ipairs(auraParticles) do
            if emitter and emitter.Parent then
                emitter.VelocityInheritance = velInheritance
            end
        end
    end
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == FLY_KEY then
        if isFlying then stopFlying() else startFlying() end
    elseif input.KeyCode == BOOST_KEY then
        if isFlying then startBoost() end
    end
end)
