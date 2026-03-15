repeat task.wait() until game:IsLoaded()

local Players = game:GetService('Players')
local Player = Players.LocalPlayer
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService('RunService')

getgenv().Trail_Ball_Enabled = false
getgenv().self_effect_Enabled = false
getgenv().Parry_Distance = 18
getgenv().Spam_Distance  = 4
getgenv().ParryMode = "simples"

local BALL_NAME = "Part"

local function isTargetBall(instance)
    if instance.Name ~= BALL_NAME or not instance:IsA("MeshPart") then
        return false
    end
    
    local highlight = instance:FindFirstChild("Highlight")
    if not highlight or not highlight:IsA("Highlight") or not highlight.Enabled then
        return false
    end
    
    local fillColor = highlight.FillColor
    return fillColor.R > 0.8 and fillColor.G < 0.2 and fillColor.B < 0.2
end

local Ball = nil
local BallConnection = nil
local ParryCooldown = false
local SpamLoop = nil
local IsSpamming = false

local function stopSpam()
    if SpamLoop then
        SpamLoop:Disconnect()
        SpamLoop = nil
    end
    IsSpamming = false
end

local function startSpam()
    if IsSpamming then return end
    IsSpamming = true
    
    -- ← aqui você pode adicionar um tempo mínimo antes de permitir spam novamente depois de parar
    SpamLoop = RunService.Heartbeat:Connect(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
        task.wait(0.008)   -- ← diminua se quiser mais rápido, mas cuidado com kick
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
        task.wait(0.008)
    end)
end

local LastParryTime = 0
local MIN_PARRY_INTERVAL = 0.24   -- ajuste aqui

local function doSingleParry()
    local now = tick()
    if now - LastParryTime < MIN_PARRY_INTERVAL then
        return
    end
    
    LastParryTime = now
    
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
    task.wait(0.035)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
end

local function monitorBall(ball)
    if not ball then return end
    
    if BallConnection then
        BallConnection:Disconnect()
        BallConnection = nil
    end
    
    BallConnection = ball:GetPropertyChangedSignal("Position"):Connect(function()
        if not ball or not ball.Parent then 
            BallConnection:Disconnect()
            BallConnection = nil
            Ball = nil
            stopSpam()
            return 
        end
        
        if not Player.Character or not Player.Character:FindFirstChild("HumanoidRootPart") then 
            return 
        end
        
        local ballPos = ball.Position
        local playerPos = Player.Character.HumanoidRootPart.Position
        local distance = (playerPos - ballPos).Magnitude
        
        local speed = ball.AssemblyLinearVelocity.Magnitude
        
        local baseParry = getgenv().Parry_Distance or 18
        local baseSpam  = getgenv().Spam_Distance or 12
        
        local dynamicParry = baseParry
        local dynamicSpam  = baseSpam
        
        if speed > 300 then
            dynamicParry = baseParry + 15
            dynamicSpam  = baseSpam + 15
        elseif speed > 200 then
            dynamicParry = baseParry + 10
            dynamicSpam  = baseSpam + 10
        elseif speed > 100 then
            dynamicParry = baseParry + 6
            dynamicSpam  = baseSpam + 6
        elseif speed > 50 then
            dynamicParry = baseParry + 3
            dynamicSpam  = baseSpam + 3
        end
        
        if getgenv().ParryMode == "simples" then
            if distance <= dynamicParry 
   			and (tick() - LastParryTime > 0.18)           -- não parry se acabou de parryar
   			and ball.AssemblyLinearVelocity:Dot((playerPos - ballPos).Unit) > 0.4 then
    			doSingleParry()
			end
        else
            if distance <= dynamicSpam then
                startSpam()
            else
                stopSpam()
            end
        end
    end)
end

for _, child in pairs(workspace:GetChildren()) do
    if isTargetBall(child) then
        Ball = child
        monitorBall(Ball)
        break
    end
end

workspace.ChildAdded:Connect(function(child)
    task.wait(0.1)
    if isTargetBall(child) then
        Ball = child
        monitorBall(Ball)
    end
end)

workspace.ChildRemoved:Connect(function(child)
    if child == Ball then
        if BallConnection then
            BallConnection:Disconnect()
            BallConnection = nil
        end
        stopSpam()
        Ball = nil
    end
end)

task.spawn(function()
    while task.wait(1) do
        if not Ball or not Ball.Parent then
            for _, child in pairs(workspace:GetChildren()) do
                if isTargetBall(child) then
                    Ball = child
                    monitorBall(Ball)
                    break
                end
            end
        end
    end
end)

local function addTrail(ball)
    if ball and ball:IsA("MeshPart") and not ball:FindFirstChild("BlackTrail") then
        local att0 = Instance.new("Attachment")
        att0.Position = Vector3.new(0, 0.5, 0)
        att0.Parent = ball

        local att1 = Instance.new("Attachment")
        att1.Position = Vector3.new(0, -0.5, 0)
        att1.Parent = ball

        local trail = Instance.new("Trail")
        trail.Name = "BlackTrail"
        trail.Attachment0 = att0
        trail.Attachment1 = att1
        trail.Color = ColorSequence.new(Color3.new(0, 0, 0))
        trail.Lifetime = 0.2
        trail.Transparency = NumberSequence.new(0.2, 1)
        trail.MinLength = 0.1
        trail.Parent = ball
    end
end

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/natividadepedro0404-sudo/deathball/refs/heads/main/main.lua"))()
local main = Library.new()

local rage = main:create_tab('Auto Parry', 'rbxassetid://76499042599127')
local Visual = main:create_tab('Visuals', 'rbxassetid://85168909131990')

local module = rage:create_module({
    title = 'Auto Parry',
    flag = 'Auto_Parry',
    description = 'Auto Parry (Tecla F)',
    section = 'left',
    callback = function(state)
        if not state then
            if BallConnection then
                BallConnection:Disconnect()
                BallConnection = nil
            end
            stopSpam()
        end
    end
})

module:create_slider({
    title = 'Distância Base (Auto Parry)',
    flag = 'Parry_Distance',
    maximum_value = 30,
    minimum_value = 1,
    value = 18,
    suffix = ' studs',
    round_number = true,
    callback = function(v)
        getgenv().Parry_Distance = v
    end
})

module:create_slider({
    title = 'Distância do Spam',
    flag = 'Spam_Distance',
    maximum_value = 25,
    minimum_value = 2,
    value = 12,
    suffix = ' studs',
    round_number = true,
    callback = function(v)
        getgenv().Spam_Distance = v
    end
})

local modeToggle = rage:create_module({
    title = 'Modo Spam',
    flag = 'Spam_Mode',
    description = 'Ativar para spam rápido',
    section = 'left',
    callback = function(state)
        if state then
            getgenv().ParryMode = "spam"
        else
            getgenv().ParryMode = "simples"
            stopSpam()
        end
    end
})

main:load()

getgenv().Parry_Distance = 18
getgenv().Spam_Distance  = 12
