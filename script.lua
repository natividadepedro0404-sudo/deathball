repeat task.wait() until game:IsLoaded()

local Players = game:GetService('Players')
local Player = Players.LocalPlayer
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService('RunService')

getgenv().AutoParry_Enabled = false
getgenv().Parry_Distance = 4
getgenv().Prediction_Enabled = true
getgenv().Prediction_Factor = 0.15
getgenv().Parry_Cooldown = 0.1

local BALL_NAME = "Part"
local Ball = nil
local BallConnection = nil
local LastParryTime = 0
local isParryInProgress = false

local BallVelocity = Vector3.new(0, 0, 0)
local LastBallPos = nil
local LastBallTime = tick()

local function isRedDeathBall(instance)
    if instance.Name ~= BALL_NAME or not instance:IsA("MeshPart") then
        return false
    end
    
    local highlight = instance:FindFirstChild("Highlight")
    if not highlight or not highlight:IsA("Highlight") or not highlight.Enabled then
        return false
    end
    
    local fillColor = highlight.FillColor
    return fillColor.R > 0.7 and fillColor.G < 0.4 and fillColor.B < 0.4
end

local function doParry()
    local now = tick()
    
    if isParryInProgress then return end
    if now - LastParryTime < getgenv().Parry_Cooldown then return end
    
    isParryInProgress = true
    LastParryTime = now
    
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
    task.wait(0.02)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
    
    task.delay(getgenv().Parry_Cooldown, function()
        isParryInProgress = false
    end)
    
end

local function updateBallVelocity(ball)
    if not ball then return end
    
    local currentTime = tick()
    local currentPos = ball.Position
    
    if LastBallPos and LastBallTime then
        local deltaTime = currentTime - LastBallTime
        if deltaTime > 0 and deltaTime < 0.1 then
            BallVelocity = (currentPos - LastBallPos) / deltaTime
        end
    end
    
    LastBallPos = currentPos
    LastBallTime = currentTime
end

local function predictPosition(ball, currentPos)
    if not getgenv().Prediction_Enabled then
        return currentPos
    end
    
    local speed = BallVelocity.Magnitude
    
    if speed < 50 then
        return currentPos
    end
    
    local predTime = getgenv().Prediction_Factor
    if speed > 300 then
        predTime = predTime * 1.5
    elseif speed > 200 then
        predTime = predTime * 1.3
    end
    
    return currentPos + (BallVelocity * predTime)
end

local LastParryDistance = 0

local function monitorBall(ball)
    if not ball then return end
    
    if BallConnection then
        BallConnection:Disconnect()
        BallConnection = nil
    end
    
    BallVelocity = Vector3.new(0, 0, 0)
    LastBallPos = ball.Position
    LastBallTime = tick()
    
    BallConnection = ball:GetPropertyChangedSignal("Position"):Connect(function()
        if not ball or not ball.Parent then
            if BallConnection then
                BallConnection:Disconnect()
                BallConnection = nil
            end
            Ball = nil
            return
        end
        
        if not getgenv().AutoParry_Enabled then
            return
        end
        
        if not isRedDeathBall(ball) then
            return
        end
        
        if not Player.Character or not Player.Character:FindFirstChild("HumanoidRootPart") then
            return
        end
        
        local currentPos = ball.Position
        
        updateBallVelocity(ball)
        
        local root = Player.Character.HumanoidRootPart
        local playerPos = root.Position
        
        local realDistance = (playerPos - currentPos).Magnitude
        
        local effectiveDistance = realDistance
        if getgenv().Prediction_Enabled then
            local predictedPos = predictPosition(ball, currentPos)
            effectiveDistance = (playerPos - predictedPos).Magnitude
        end
        
        LastParryDistance = effectiveDistance
        
        if effectiveDistance <= getgenv().Parry_Distance and not isParryInProgress then
            doParry()
        end
    end)
end

local function findBall()
    for _, child in ipairs(workspace:GetChildren()) do
        if isRedDeathBall(child) then
            Ball = child
            monitorBall(Ball)
            return true
        end
    end
    return false
end

findBall()

workspace.ChildAdded:Connect(function(child)
    task.wait(0.05)
    if isRedDeathBall(child) then
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
        Ball = nil
    end
end)

task.spawn(function()
    while true do
        task.wait(0.5)
        if getgenv().AutoParry_Enabled and (not Ball or not Ball.Parent) then
            findBall()
        end
    end
end)

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/natividadepedro0404-sudo/deathball/refs/heads/main/main.lua"))()
local main = Library.new()

local tab = main:create_tab('Auto Parry', 'rbxassetid://76499042599127')

local mainModule = tab:create_module({
    title = 'Auto Parry',
    flag = 'Auto_Parry_Exact',
    description = 'Monitora mudança de POSIÇÃO da bola',
    section = 'left',
    callback = function(state)
        getgenv().AutoParry_Enabled = state
        if not state then
            if BallConnection then
                BallConnection:Disconnect()
                BallConnection = nil
            end
        else
            if Ball and Ball.Parent and isRedDeathBall(Ball) then
                monitorBall(Ball)
            else
                findBall()
            end
        end
    end
})

mainModule:create_slider({
    title = 'Distância do Parry',
    flag = 'Parry_Distance',
    maximum_value = 35,
    minimum_value = 2,
    value = 20,
    suffix = ' studs',
    round_number = true,
    callback = function(v)
        getgenv().Parry_Distance = v
    end
})

mainModule:create_slider({
    title = 'Cooldown',
    flag = 'Parry_Cooldown',
    maximum_value = 0.25,
    minimum_value = 0.01,
    value = 0.12,
    suffix = ' segundos',
    round_number = false,
    callback = function(v)
        getgenv().Parry_Cooldown = v
    end
})

main:load()
