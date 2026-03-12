local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LP = game.Players.LocalPlayer
local BallShadow, RealBall
local WhiteColor = Color3.new(1, 1, 1)
local LastBallPos
local SpeedMulty = 3
local AutoParryEnabled = true

local ParryDistance = 15
local ReactionTime = 0.0001
local SafetyMargin = 1.3

local AutoClickerEnabled = false
local ClickSpeed = 1000
local LastClickTime = 0

local LastParryTime = 0
local ParryCooldown = 0.000001
local IsParrying = false

-- Настраиваемые пороги скорости и высоты
local SpeedHeightThresholds = {
    {speed = 7.5, maxHeight = 22},
    {speed = 10, maxHeight = 27},
    {speed = math.huge, maxHeight = 30}
}

local PlayerCoordsGui = nil
local PlayerCoordsLabel = nil

local IntermissionCoords = Vector3.new(567, 285, -783)
local AutoIntermissionEnabled = false
local LastIntermissionCheck = 0
local IntermissionCheckCooldown = 2

-- Бинды по умолчанию
local Binds = {
    ToggleGUI = Enum.KeyCode.K,
    AutoParry = nil,
    Clicker = Enum.KeyCode.E,
    Target = Enum.KeyCode.H,
    Teleport = Enum.KeyCode.T,
    AutoInter = nil,
    HVH = Enum.KeyCode.G
}

local BindingInProgress = false
local CurrentBindingButton = nil

-- Переменные для Target системы
local TargetEnabled = false
local currentTarget = nil
local currentRadius = 45
local rotationSpeed = 2
local targetLocked = false
local MAX_HEIGHT = 265
local currentAngle = 360
local targetConnection = nil
local noclipEnabled = false
local noclipConnection = nil
local isInGame = false

-- Переменные для HVH системы
local HVHEnabled = false
local HVHVisualBall = nil
local HVHConnection = nil
local OriginalHVHPosition = nil
local HVHState = "WAITING"
local LastBallColor = WhiteColor
local BallVelocity = Vector3.new(0, 0, 0)
local LastBallPosForVelocity = nil

-- Цвета для фиолетового градиента
local PurpleGradient = {
    Color3.fromRGB(100, 50, 200),
    Color3.fromRGB(150, 70, 250),
    Color3.fromRGB(200, 100, 255)
}

local AccentColor = Color3.fromRGB(180, 80, 255)
local TextColor = Color3.fromRGB(245, 245, 255)
local DarkTextColor = Color3.fromRGB(40, 20, 80)

local function IsInGame()
    local success, result = pcall(function()
        local healthBar = LP.PlayerGui.HUD.HolderBottom.HealthBar
        return healthBar.Visible == true
    end)
    return success and result
end

local function GetBallColor()
    if not RealBall then return WhiteColor end
    
    local highlight = RealBall:FindFirstChildOfClass("Highlight")
    if highlight then
        return highlight.FillColor
    end
    
    local surfaceGui = RealBall:FindFirstChildOfClass("SurfaceGui")
    if surfaceGui then
        local frame = surfaceGui:FindFirstChild("Frame")
        if frame and frame.BackgroundColor3 then
            return frame.BackgroundColor3
        end
    end
    
    if RealBall:IsA("Part") and RealBall.BrickColor ~= BrickColor.new("White") then
        return RealBall.Color
    end
    
    return WhiteColor
end

-- Функция для расчета высоты мяча по размеру тени (всегда +3 к расчету)
local function CalculateBallHeight(shadowSize)
    local baseShadowSize = 5
    local heightMultiplier = 20
    
    local shadowIncrease = math.max(0, shadowSize - baseShadowSize)
    local estimatedHeight = shadowIncrease * heightMultiplier
    
    -- Всегда добавляем +3 к высоте мяча
    return math.min(estimatedHeight + 3, 100)
end

-- Функция для создания визуального мяча (без пульсации)
local function CreateVisualBall(shadowPosition, shadowSize)
    if not shadowPosition then return nil end
    
    -- Удаляем старый мяч если есть
    if HVHVisualBall then
        HVHVisualBall:Destroy()
        HVHVisualBall = nil
    end
    
    -- Вычисляем высоту мяча с учетом +3
    local ballHeight = CalculateBallHeight(shadowSize)
    local ballYPosition = shadowPosition.Y + ballHeight
    local ballPosition = Vector3.new(shadowPosition.X, ballYPosition, shadowPosition.Z)
    
    -- Создаем новый визуальный мяч с размером 4,4,4
    HVHVisualBall = Instance.new("Part")
    HVHVisualBall.Name = "VisualBallTracker"
    HVHVisualBall.Anchored = true
    HVHVisualBall.CanCollide = false
    HVHVisualBall.Material = Enum.Material.Neon
    HVHVisualBall.Color = AccentColor
    HVHVisualBall.Transparency = 0.1
    HVHVisualBall.Size = Vector3.new(4, 4, 4)
    HVHVisualBall.Shape = Enum.PartType.Ball
    HVHVisualBall.Position = ballPosition
    HVHVisualBall.Parent = workspace
    
    -- Добавляем яркое свечение без пульсации
    local highlight = Instance.new("Highlight")
    highlight.FillColor = AccentColor
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.3
    highlight.OutlineTransparency = 0.1
    highlight.Parent = HVHVisualBall
    
    return HVHVisualBall, ballPosition
end

-- Функция для обновления позиции визуального мяча
local function UpdateVisualBall(shadowPosition, shadowSize)
    if not shadowPosition then return nil end
    
    if not HVHVisualBall then
        return CreateVisualBall(shadowPosition, shadowSize)
    else
        -- Вычисляем новую позицию с учетом +3
        local ballHeight = CalculateBallHeight(shadowSize)
        local ballYPosition = shadowPosition.Y + ballHeight
        local ballPosition = Vector3.new(shadowPosition.X, ballYPosition, shadowPosition.Z)
        
        HVHVisualBall.Position = ballPosition
        return ballPosition
    end
end

-- Функция для удаления визуального мяча
local function RemoveVisualBall()
    if HVHVisualBall then
        HVHVisualBall:Destroy()
        HVHVisualBall = nil
    end
end

-- Функция для выполнения HVH с новой логикой
local function ExecuteHVH(shadowPosition, shadowSize)
    if not HVHEnabled or not IsInGame() or not shadowPosition then
        HVHState = "WAITING"
        OriginalHVHPosition = nil
        return
    end
    
    -- Получаем цвет мяча
    local ballColor = WhiteColor
    if RealBall then
        ballColor = GetBallColor()
    end
    
    -- Сохраняем текущий цвет мяча
    LastBallColor = ballColor
    
    -- Обновляем визуальный мяч
    local ballPosition = UpdateVisualBall(shadowPosition, shadowSize)
    if not ballPosition then return end
    
    -- Вычисляем высоту мяча
    local ballHeight = CalculateBallHeight(shadowSize)
    local ballYPosition = shadowPosition.Y + ballHeight
    ballPosition = Vector3.new(shadowPosition.X, ballYPosition, shadowPosition.Z)
    
    -- Вычисляем скорость мяча
    local ballSpeed = BallVelocity.Magnitude
    
    -- Если мяч не белый и скорость равна 0, не выполняем HVH
    if ballColor ~= WhiteColor and ballSpeed < 0.1 then
        HVHState = "WAITING"
        return
    end
    
    -- Логика состояний HVH
    if HVHState == "WAITING" then
        -- Ждем пока мяч станет не белым и имеет скорость больше 0
        if ballColor ~= WhiteColor and ballSpeed > 0.1 then
            -- Сохраняем оригинальную позицию
            if LP.Character and LP.Character.PrimaryPart then
                OriginalHVHPosition = LP.Character.PrimaryPart.Position
                HVHState = "TELEPORTING"
            end
        end
        
    elseif HVHState == "TELEPORTING" then
        -- Нажимаем F
        VirtualInputManager:SendKeyEvent(true, "F", false, game)
        task.wait(0.000001)
        VirtualInputManager:SendKeyEvent(false, "F", false, game)
        
        -- Уменьшенная задержка до 0.000001
        task.wait(0.000001)
        
        -- Телепортируемся прямо в мяч
        if LP.Character and LP.Character.PrimaryPart then
            LP.Character.PrimaryPart.CFrame = CFrame.new(ballPosition)
            HVHState = "FOLLOWING"
        end
        
    elseif HVHState == "FOLLOWING" then
        -- Проверяем, стал ли мяч белым или скорость стала 0
        if ballColor == WhiteColor or ballSpeed < 0.1 then
            HVHState = "RETURNING"
            return
        end
        
        -- Находимся прямо в мяче
        if LP.Character and LP.Character.PrimaryPart then
            LP.Character.PrimaryPart.CFrame = CFrame.new(ballPosition)
        end
        
    elseif HVHState == "RETURNING" then
        -- Возвращаемся в исходную позицию
        if OriginalHVHPosition and LP.Character and LP.Character.PrimaryPart then
            LP.Character.PrimaryPart.CFrame = CFrame.new(OriginalHVHPosition)
            
            -- Уменьшенная задержка до 0.000001
            task.wait(0.000001)
            
            -- Возвращаемся в состояние ожидания
            HVHState = "WAITING"
            OriginalHVHPosition = nil
        else
            HVHState = "WAITING"
        end
    end
end

-- Функция для запуска/остановки постоянной работы HVH
local function ToggleHVHContinuous()
    if HVHConnection then
        HVHConnection:Disconnect()
        HVHConnection = nil
    end
    
    if HVHEnabled then
        -- Сбрасываем состояние HVH
        HVHState = "WAITING"
        OriginalHVHPosition = nil
        LastBallColor = WhiteColor
        
        HVHConnection = RunService.Heartbeat:Connect(function()
            if BallShadow then
                ExecuteHVH(BallShadow.Position, BallShadow.Size.X)
            else
                -- Если мяч не найден, возвращаемся в состояние ожидания
                if HVHState ~= "WAITING" then
                    HVHState = "WAITING"
                    OriginalHVHPosition = nil
                end
            end
        end)
    else
        -- Выключаем HVH, сбрасываем состояние
        HVHState = "WAITING"
        OriginalHVHPosition = nil
        LastBallColor = WhiteColor
        RemoveVisualBall()
    end
end

local function CreatePlayerCoordsGUI()
    if PlayerCoordsGui then
        PlayerCoordsGui:Destroy()
    end
    
    PlayerCoordsGui = Instance.new("ScreenGui")
    PlayerCoordsGui.Name = "PlayerCoordsGUI"
    PlayerCoordsGui.Parent = LP:WaitForChild("PlayerGui")
    
    local CoordsFrame = Instance.new("Frame")
    CoordsFrame.Size = UDim2.new(0, 220, 0, 90)
    CoordsFrame.Position = UDim2.new(0, 10, 0, 10)
    CoordsFrame.BackgroundColor3 = PurpleGradient[1]
    CoordsFrame.BackgroundTransparency = 0.15
    CoordsFrame.BorderSizePixel = 0
    CoordsFrame.Parent = PlayerCoordsGui
    
    local CoordsCorner = Instance.new("UICorner")
    CoordsCorner.CornerRadius = UDim.new(0, 12)
    CoordsCorner.Parent = CoordsFrame
    
    local CoordsGradient = Instance.new("UIGradient")
    CoordsGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, PurpleGradient[1]),
        ColorSequenceKeypoint.new(1, PurpleGradient[2])
    })
    CoordsGradient.Rotation = 90
    CoordsGradient.Parent = CoordsFrame
    
    local CoordsTitle = Instance.new("TextLabel")
    CoordsTitle.Size = UDim2.new(1, 0, 0, 25)
    CoordsTitle.Position = UDim2.new(0, 0, 0, 0)
    CoordsTitle.BackgroundTransparency = 1
    CoordsTitle.Text = "📊 PLAYER COORDINATES"
    CoordsTitle.TextColor3 = TextColor
    CoordsTitle.TextSize = 14
    CoordsTitle.Font = Enum.Font.GothamBold
    CoordsTitle.Parent = CoordsFrame
    
    PlayerCoordsLabel = Instance.new("TextLabel")
    PlayerCoordsLabel.Size = UDim2.new(1, 0, 0, 60)
    PlayerCoordsLabel.Position = UDim2.new(0, 0, 0, 25)
    PlayerCoordsLabel.BackgroundTransparency = 1
    PlayerCoordsLabel.Text = "X: 0.0\nY: 0.0\nZ: 0.0\nStatus: Loading..."
    PlayerCoordsLabel.TextColor3 = TextColor
    PlayerCoordsLabel.TextSize = 12
    PlayerCoordsLabel.Font = Enum.Font.Gotham
    PlayerCoordsLabel.TextXAlignment = Enum.TextXAlignment.Left
    PlayerCoordsLabel.Parent = CoordsFrame
    
    local dragging = false
    local dragStart = nil
    local startPos = nil
    
    CoordsTitle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = CoordsFrame.Position
        end
    end)
    
    CoordsTitle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            if dragging then
                local delta = input.Position - dragStart
                CoordsFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end
    end)
    
    CoordsTitle.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
end

local function UpdatePlayerCoordinates()
    if not PlayerCoordsLabel then
        return
    end
    
    local inGame = IsInGame()
    local statusText = inGame and "IN GAME" or "NOT IN GAME"
    local statusColor = inGame and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
    
    if LP.Character and LP.Character.PrimaryPart then
        local playerPos = LP.Character.PrimaryPart.Position
        PlayerCoordsLabel.Text = string.format("X: %.1f\nY: %.1f\nZ: %.1f\nStatus: %s", 
            playerPos.X, playerPos.Y, playerPos.Z, statusText)
        PlayerCoordsLabel.TextColor3 = statusColor
    else
        PlayerCoordsLabel.Text = string.format("X: 0.0\nY: 0.0\nZ: 0.0\nStatus: %s", statusText)
        PlayerCoordsLabel.TextColor3 = statusColor
    end
    
    return inGame
end

local function TeleportToIntermission()
    if not LP.Character or not LP.Character.PrimaryPart then
        return false
    end
    
    local safePosition = IntermissionCoords + Vector3.new(0, 5, 0)
    LP.Character.PrimaryPart.CFrame = CFrame.new(safePosition)
    
    return true
end

local function CheckAutoIntermission()
    if not AutoIntermissionEnabled then
        return
    end
    
    local currentTime = tick()
    if currentTime - LastIntermissionCheck < IntermissionCheckCooldown then
        return
    end
    
    LastIntermissionCheck = currentTime
    
    if not IsInGame() then
        if TeleportToIntermission() then
            print("Auto Intermission: Teleported to intermission coordinates")
        else
            print("Auto Intermission: Teleport failed")
        end
    end
end

local function FindNearestPlayer()
    local nearestPlayer = nil
    local nearestDistance = math.huge
    
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LP and player.Character and player.Character.PrimaryPart and player.Character.Humanoid and player.Character.Humanoid.Health > 0 then
            if LP.Character and LP.Character.PrimaryPart then
                local distance = (player.Character.PrimaryPart.Position - LP.Character.PrimaryPart.Position).Magnitude
                if distance < nearestDistance then
                    nearestDistance = distance
                    nearestPlayer = player
                end
            end
        end
    end
    
    return nearestPlayer
end

local function TeleportToPlayer(player)
    if not player or not player.Character or not player.Character.PrimaryPart or not LP.Character or not LP.Character.PrimaryPart then
        return false
    end
    
    local targetPos = player.Character.PrimaryPart.Position
    local safePosition = targetPos + Vector3.new(0, 5, 0)
    
    LP.Character.PrimaryPart.CFrame = CFrame.new(safePosition)
    return true
end

local function GetMaxHeightBySpeed(speedStuds)
    for _, threshold in ipairs(SpeedHeightThresholds) do
        if speedStuds <= threshold.speed then
            return threshold.maxHeight
        end
    end
    return 30
end

-- Функция для получения названия клавиши
local function GetKeyName(keyCode)
    if not keyCode then return "NONE" end
    local keyName = tostring(keyCode):gsub("Enum.KeyCode.", "")
    if keyName == "LeftControl" then return "LCTRL"
    elseif keyName == "RightControl" then return "RCTRL"
    elseif keyName == "LeftShift" then return "LSHIFT"
    elseif keyName == "RightShift" then return "RSHIFT"
    elseif keyName == "LeftAlt" then return "LALT"
    elseif keyName == "RightAlt" then return "RALT"
    else return keyName end
end

-- Функция для обновления текста кнопок с биндами
local function UpdateButtonText(button, baseText, bindKey)
    if bindKey then
        button.Text = baseText .. " (" .. GetKeyName(bindKey) .. ")"
    else
        button.Text = baseText
    end
end

-- Функция для установки бинда
local function StartBinding(button, bindType, baseText)
    if BindingInProgress then return end
    
    BindingInProgress = true
    CurrentBindingButton = button
    
    local originalText = button.Text
    button.Text = "Press any key..."
    button.BackgroundColor3 = AccentColor
    button.TextColor3 = DarkTextColor
    
    local connection
    connection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        if input.UserInputType == Enum.UserInputType.Keyboard then
            Binds[bindType] = input.KeyCode
            
            UpdateButtonText(button, baseText, input.KeyCode)
            
            -- Устанавливаем цвет в зависимости от состояния функции
            if bindType == "AutoParry" then
                button.BackgroundColor3 = AutoParryEnabled and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
            elseif bindType == "Clicker" then
                button.BackgroundColor3 = AutoClickerEnabled and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
            elseif bindType == "Target" then
                button.BackgroundColor3 = TargetEnabled and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
            elseif bindType == "HVH" then
                button.BackgroundColor3 = HVHEnabled and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
            elseif bindType == "AutoInter" then
                button.BackgroundColor3 = AutoIntermissionEnabled and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
            else
                button.BackgroundColor3 = PurpleGradient[2]
            end
            
            button.TextColor3 = DarkTextColor
            BindingInProgress = false
            CurrentBindingButton = nil
            connection:Disconnect()
        elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
            Binds[bindType] = nil
            UpdateButtonText(button, baseText, nil)
            button.BackgroundColor3 = PurpleGradient[2]
            button.TextColor3 = DarkTextColor
            
            BindingInProgress = false
            CurrentBindingButton = nil
            connection:Disconnect()
        end
    end)
end

-- Функции для Target системы
local function toggleNoclip(state)
    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
    
    if state then
        noclipEnabled = true
        
        if LP.Character then
            for _, part in pairs(LP.Character:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end
        
        noclipConnection = RunService.Stepped:Connect(function()
            if LP.Character and noclipEnabled then
                for _, part in pairs(LP.Character:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
                end
            end
        end)
    else
        noclipEnabled = false
        if LP.Character then
            for _, part in pairs(LP.Character:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = true
                end
            end
        end
    end
end

-- Оптимизированный поиск ближайшего игрока НИЖЕ максимальной высоты
local lastPlayerSearch = 0
local playerSearchInterval = 0.5
local cachedPlayers = {}

local function findNearestPlayerBelowHeight()
    local currentTime = tick()
    
    if currentTime - lastPlayerSearch >= playerSearchInterval then
        lastPlayerSearch = currentTime
        cachedPlayers = {}
        
        local myPosition = LP.Character.PrimaryPart.Position
        
        for _, otherPlayer in pairs(Players:GetPlayers()) do
            if otherPlayer ~= LP and otherPlayer.Character then
                local otherCharacter = otherPlayer.Character
                local otherHumanoidRootPart = otherCharacter.PrimaryPart
                local otherHumanoid = otherCharacter:FindFirstChild("Humanoid")
                
                if otherHumanoidRootPart and otherHumanoid and otherHumanoid.Health > 0 then
                    local targetPosition = otherHumanoidRootPart.Position
                    
                    if targetPosition.Y < MAX_HEIGHT then
                        local distance = (myPosition - targetPosition).Magnitude
                        table.insert(cachedPlayers, {
                            player = otherPlayer,
                            distance = distance,
                            position = targetPosition
                        })
                    end
                end
            end
        end
        
        table.sort(cachedPlayers, function(a, b)
            return a.distance < b.distance
        end)
    end
    
    if #cachedPlayers > 0 then
        return cachedPlayers[1].player
    end
    
    return nil
end

-- Проверка высоты текущей цели
local function checkCurrentTargetHeight()
    if not currentTarget or not currentTarget.Character then
        return false
    end
    
    local targetCharacter = currentTarget.Character
    local targetRoot = targetCharacter.PrimaryPart
    
    if targetRoot then
        local targetHeight = targetRoot.Position.Y
        return targetHeight >= MAX_HEIGHT
    end
    
    return false
end

-- Функция для вычисления позиции вращения
local function getRotatedPosition(targetPosition, angle, radius)
    local offset = Vector3.new(
        math.cos(angle) * radius,
        0,
        math.sin(angle) * radius
    )
    
    return Vector3.new(
        targetPosition.X + offset.X,
        targetPosition.Y,
        targetPosition.Z + offset.Z
    )
end

-- Оптимизированная основная функция Target
local function targetFunctionOptimized()
    if targetConnection then
        targetConnection:Disconnect()
    end
    
    local lastFrameTime = tick()
    local frameCounter = 0
    
    targetConnection = RunService.Heartbeat:Connect(function(deltaTime)
        if not TargetEnabled then
            return
        end
        
        frameCounter = frameCounter + 1
        local currentTime = tick()
        
        if currentTime - lastFrameTime < 0.016 then
            return
        end
        
        lastFrameTime = currentTime
        
        if frameCounter % 10 == 0 then
            isInGame = IsInGame()
        end
        
        if not isInGame then
            currentTarget = nil
            targetLocked = false
            return
        end
        
        if currentTarget and targetLocked then
            local isTooHigh = checkCurrentTargetHeight()
            if isTooHigh then
                currentTarget = nil
                targetLocked = false
                task.wait(0.1)
            end
        end
        
        if not targetLocked or not currentTarget or not currentTarget.Character then
            if frameCounter % 3 == 0 then
                currentTarget = findNearestPlayerBelowHeight()
                if currentTarget then
                    targetLocked = true
                    currentAngle = 0
                end
            else
                return
            end
        end
        
        if not currentTarget or not currentTarget.Character then
            return
        end
        
        local targetCharacter = currentTarget.Character
        local targetRoot = targetCharacter.PrimaryPart
        local targetHumanoid = targetCharacter:FindFirstChild("Humanoid")
        
        if not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 then
            currentTarget = nil
            targetLocked = false
            return
        end
        
        local targetPosition = targetRoot.Position
        
        if targetPosition.Y >= MAX_HEIGHT then
            currentTarget = nil
            targetLocked = false
            return
        end
        
        currentAngle = currentAngle + (rotationSpeed * deltaTime)
        if currentAngle > 2 * math.pi then
            currentAngle = currentAngle - (2 * math.pi)
        end
        
        local rotatedPosition = getRotatedPosition(targetPosition, currentAngle, currentRadius)
        
        LP.Character.PrimaryPart.CFrame = CFrame.new(rotatedPosition, Vector3.new(targetPosition.X, rotatedPosition.Y, targetPosition.Z))
    end)
end

-- Функция включения/выключения Target
local function ToggleTarget()
    if not IsInGame() then
        return
    end
    
    TargetEnabled = not TargetEnabled
    
    if TargetEnabled then
        isInGame = IsInGame()
        toggleNoclip(true)
        currentTarget = nil
        targetLocked = false
        currentAngle = 0
        targetFunctionOptimized()
    else
        toggleNoclip(false)
        if targetConnection then
            targetConnection:Disconnect()
            targetConnection = nil
        end
        currentTarget = nil
        targetLocked = false
    end
end

-- Функция для переключения HVH
local function ToggleHVH()
    HVHEnabled = not HVHEnabled
    
    ToggleHVHContinuous()
    
    if HVHEnabled and BallShadow then
        UpdateVisualBall(BallShadow.Position, BallShadow.Size.X)
    end
end

function InitializeMainScript()
    CreatePlayerCoordsGUI()
    
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "DeathBallProGUI"
    ScreenGui.Parent = LP:WaitForChild("PlayerGui")

    local MainFrame = Instance.new("Frame")
    MainFrame.Size = UDim2.new(0, 340, 0, 380)
    MainFrame.Position = UDim2.new(0.02, 0, 0.02, 0)
    MainFrame.BackgroundColor3 = PurpleGradient[1]
    MainFrame.BackgroundTransparency = 0.1
    MainFrame.BorderSizePixel = 0
    MainFrame.Parent = ScreenGui

    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 16)
    Corner.Parent = MainFrame

    local Gradient = Instance.new("UIGradient")
    Gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, PurpleGradient[1]),
        ColorSequenceKeypoint.new(0.5, PurpleGradient[2]),
        ColorSequenceKeypoint.new(1, PurpleGradient[3])
    })
    Gradient.Rotation = 120
    Gradient.Parent = MainFrame

    local TitleBar = Instance.new("Frame")
    TitleBar.Size = UDim2.new(1, 0, 0, 32)
    TitleBar.Position = UDim2.new(0, 0, 0, 0)
    TitleBar.BackgroundColor3 = PurpleGradient[3]
    TitleBar.BackgroundTransparency = 0.2
    TitleBar.BorderSizePixel = 0
    TitleBar.Parent = MainFrame

    local TitleCorner = Instance.new("UICorner")
    TitleCorner.CornerRadius = UDim.new(0, 16)
    TitleCorner.Parent = TitleBar

    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(0.7, 0, 1, 0)
    Title.Position = UDim2.new(0.02, 0, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Text = "⚡ DEATH BALL PRO"
    Title.TextColor3 = TextColor
    Title.TextSize = 16
    Title.Font = Enum.Font.GothamBold
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Parent = TitleBar

    local CloseButton = Instance.new("TextButton")
    CloseButton.Size = UDim2.new(0.25, 0, 0.7, 0)
    CloseButton.Position = UDim2.new(0.73, 0, 0.15, 0)
    CloseButton.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
    CloseButton.BorderSizePixel = 0
    CloseButton.Text = "✕"
    CloseButton.TextColor3 = TextColor
    CloseButton.TextSize = 14
    CloseButton.Font = Enum.Font.GothamBold
    CloseButton.Parent = TitleBar

    local CloseCorner = Instance.new("UICorner")
    CloseCorner.CornerRadius = UDim.new(0, 8)
    CloseCorner.Parent = CloseButton

    local BallInfoFrame = Instance.new("Frame")
    BallInfoFrame.Size = UDim2.new(0.96, 0, 0, 70)
    BallInfoFrame.Position = UDim2.new(0.02, 0, 0.09, 0)
    BallInfoFrame.BackgroundColor3 = Color3.fromRGB(40, 20, 80)
    BallInfoFrame.BackgroundTransparency = 0.3
    BallInfoFrame.BorderSizePixel = 0
    BallInfoFrame.Parent = MainFrame

    local BallInfoCorner = Instance.new("UICorner")
    BallInfoCorner.CornerRadius = UDim.new(0, 10)
    BallInfoCorner.Parent = BallInfoFrame

    local CoordinatesLabel = Instance.new("TextLabel")
    CoordinatesLabel.Size = UDim2.new(1, 0, 0.6, 0)
    CoordinatesLabel.Position = UDim2.new(0, 8, 0, 0)
    CoordinatesLabel.BackgroundTransparency = 1
    CoordinatesLabel.Text = "X: 0.0 | Y: 0.0 | Z: 0.0\nSpeed: 0.0 | Height: 0.0"
    CoordinatesLabel.TextColor3 = TextColor
    CoordinatesLabel.TextSize = 12
    CoordinatesLabel.Font = Enum.Font.Gotham
    CoordinatesLabel.TextXAlignment = Enum.TextXAlignment.Left
    CoordinatesLabel.Parent = BallInfoFrame

    local StatusLabel = Instance.new("TextLabel")
    StatusLabel.Size = UDim2.new(1, 0, 0.4, 0)
    StatusLabel.Position = UDim2.new(0, 8, 0.6, 0)
    StatusLabel.BackgroundTransparency = 1
    StatusLabel.Text = "🔍 Searching for ball..."
    StatusLabel.TextColor3 = TextColor
    StatusLabel.TextSize = 11
    StatusLabel.Font = Enum.Font.Gotham
    StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    StatusLabel.Parent = BallInfoFrame

    local MainSettingsFrame = Instance.new("Frame")
    MainSettingsFrame.Size = UDim2.new(0.96, 0, 0, 150)
    MainSettingsFrame.Position = UDim2.new(0.02, 0, 0.25, 0)
    MainSettingsFrame.BackgroundColor3 = Color3.fromRGB(40, 20, 80)
    MainSettingsFrame.BackgroundTransparency = 0.3
    MainSettingsFrame.BorderSizePixel = 0
    MainSettingsFrame.Parent = MainFrame

    local MainSettingsCorner = Instance.new("UICorner")
    MainSettingsCorner.CornerRadius = UDim.new(0, 10)
    MainSettingsCorner.Parent = MainSettingsFrame

    local DistanceFrame = Instance.new("Frame")
    DistanceFrame.Size = UDim2.new(1, -16, 0, 40)
    DistanceFrame.Position = UDim2.new(0, 8, 0, 8)
    DistanceFrame.BackgroundTransparency = 1
    DistanceFrame.Parent = MainSettingsFrame

    local DistanceLabel = Instance.new("TextLabel")
    DistanceLabel.Size = UDim2.new(1, 0, 0, 18)
    DistanceLabel.Position = UDim2.new(0, 0, 0, 0)
    DistanceLabel.BackgroundTransparency = 1
    DistanceLabel.Text = "🎯 Parry Distance: 15"
    DistanceLabel.TextColor3 = TextColor
    DistanceLabel.TextSize = 12
    DistanceLabel.Font = Enum.Font.Gotham
    DistanceLabel.TextXAlignment = Enum.TextXAlignment.Left
    DistanceLabel.Parent = DistanceFrame

    local DistanceSlider = Instance.new("Frame")
    DistanceSlider.Size = UDim2.new(1, 0, 0, 12)
    DistanceSlider.Position = UDim2.new(0, 0, 0, 22)
    DistanceSlider.BackgroundColor3 = Color3.fromRGB(60, 30, 120)
    DistanceSlider.BorderSizePixel = 0
    DistanceSlider.Parent = DistanceFrame

    local DistanceSliderCorner = Instance.new("UICorner")
    DistanceSliderCorner.CornerRadius = UDim.new(0, 6)
    DistanceSliderCorner.Parent = DistanceSlider

    local DistanceFill = Instance.new("Frame")
    DistanceFill.Size = UDim2.new(0.5, 0, 1, 0)
    DistanceFill.Position = UDim2.new(0, 0, 0, 0)
    DistanceFill.BackgroundColor3 = AccentColor
    DistanceFill.BorderSizePixel = 0
    DistanceFill.Parent = DistanceSlider

    local DistanceFillCorner = Instance.new("UICorner")
    DistanceFillCorner.CornerRadius = UDim.new(0, 6)
    DistanceFillCorner.Parent = DistanceFill

    local DistanceThumb = Instance.new("Frame")
    DistanceThumb.Size = UDim2.new(0, 18, 0, 18)
    DistanceThumb.Position = UDim2.new(0.5, -9, -0.25, 0)
    DistanceThumb.BackgroundColor3 = TextColor
    DistanceThumb.BorderSizePixel = 0
    DistanceThumb.Parent = DistanceSlider

    local DistanceThumbCorner = Instance.new("UICorner")
    DistanceThumbCorner.CornerRadius = UDim.new(0, 9)
    DistanceThumbCorner.Parent = DistanceThumb

    local TargetRadiusFrame = Instance.new("Frame")
    TargetRadiusFrame.Size = UDim2.new(1, -16, 0, 40)
    TargetRadiusFrame.Position = UDim2.new(0, 8, 0, 50)
    TargetRadiusFrame.BackgroundTransparency = 1
    TargetRadiusFrame.Parent = MainSettingsFrame

    local TargetRadiusLabel = Instance.new("TextLabel")
    TargetRadiusLabel.Size = UDim2.new(1, 0, 0, 18)
    TargetRadiusLabel.Position = UDim2.new(0, 0, 0, 0)
    TargetRadiusLabel.BackgroundTransparency = 1
    TargetRadiusLabel.Text = "🎯 Target Radius: 45"
    TargetRadiusLabel.TextColor3 = TextColor
    TargetRadiusLabel.TextSize = 12
    TargetRadiusLabel.Font = Enum.Font.Gotham
    TargetRadiusLabel.TextXAlignment = Enum.TextXAlignment.Left
    TargetRadiusLabel.Parent = TargetRadiusFrame

    local TargetRadiusSlider = Instance.new("Frame")
    TargetRadiusSlider.Size = UDim2.new(1, 0, 0, 12)
    TargetRadiusSlider.Position = UDim2.new(0, 0, 0, 22)
    TargetRadiusSlider.BackgroundColor3 = Color3.fromRGB(60, 30, 120)
    TargetRadiusSlider.BorderSizePixel = 0
    TargetRadiusSlider.Parent = TargetRadiusFrame

    local TargetRadiusSliderCorner = Instance.new("UICorner")
    TargetRadiusSliderCorner.CornerRadius = UDim.new(0, 6)
    TargetRadiusSliderCorner.Parent = TargetRadiusSlider

    local TargetRadiusFill = Instance.new("Frame")
    TargetRadiusFill.Size = UDim2.new(0.04, 0, 1, 0)
    TargetRadiusFill.Position = UDim2.new(0, 0, 0, 0)
    TargetRadiusFill.BackgroundColor3 = AccentColor
    TargetRadiusFill.BorderSizePixel = 0
    TargetRadiusFill.Parent = TargetRadiusSlider

    local TargetRadiusFillCorner = Instance.new("UICorner")
    TargetRadiusFillCorner.CornerRadius = UDim.new(0, 6)
    TargetRadiusFillCorner.Parent = TargetRadiusFill

    local TargetRadiusThumb = Instance.new("Frame")
    TargetRadiusThumb.Size = UDim2.new(0, 18, 0, 18)
    TargetRadiusThumb.Position = UDim2.new(0.04, -9, -0.25, 0)
    TargetRadiusThumb.BackgroundColor3 = TextColor
    TargetRadiusThumb.BorderSizePixel = 0
    TargetRadiusThumb.Parent = TargetRadiusSlider

    local TargetRadiusThumbCorner = Instance.new("UICorner")
    TargetRadiusThumbCorner.CornerRadius = UDim.new(0, 9)
    TargetRadiusThumbCorner.Parent = TargetRadiusThumb

    local TargetSpeedFrame = Instance.new("Frame")
    TargetSpeedFrame.Size = UDim2.new(1, -16, 0, 40)
    TargetSpeedFrame.Position = UDim2.new(0, 8, 0, 92)
    TargetSpeedFrame.BackgroundTransparency = 1
    TargetSpeedFrame.Parent = MainSettingsFrame

    local TargetSpeedLabel = Instance.new("TextLabel")
    TargetSpeedLabel.Size = UDim2.new(1, 0, 0, 18)
    TargetSpeedLabel.Position = UDim2.new(0, 0, 0, 0)
    TargetSpeedLabel.BackgroundTransparency = 1
    TargetSpeedLabel.Text = "🎯 Target Speed: 2.0"
    TargetSpeedLabel.TextColor3 = TextColor
    TargetSpeedLabel.TextSize = 12
    TargetSpeedLabel.Font = Enum.Font.Gotham
    TargetSpeedLabel.TextXAlignment = Enum.TextXAlignment.Left
    TargetSpeedLabel.Parent = TargetSpeedFrame

    local TargetSpeedSlider = Instance.new("Frame")
    TargetSpeedSlider.Size = UDim2.new(1, 0, 0, 12)
    TargetSpeedSlider.Position = UDim2.new(0, 0, 0, 22)
    TargetSpeedSlider.BackgroundColor3 = Color3.fromRGB(60, 30, 120)
    TargetSpeedSlider.BorderSizePixel = 0
    TargetSpeedSlider.Parent = TargetSpeedFrame

    local TargetSpeedSliderCorner = Instance.new("UICorner")
    TargetSpeedSliderCorner.CornerRadius = UDim.new(0, 6)
    TargetSpeedSliderCorner.Parent = TargetSpeedSlider

    local TargetSpeedFill = Instance.new("Frame")
    TargetSpeedFill.Size = UDim2.new(0.03, 0, 1, 0)
    TargetSpeedFill.Position = UDim2.new(0, 0, 0, 0)
    TargetSpeedFill.BackgroundColor3 = AccentColor
    TargetSpeedFill.BorderSizePixel = 0
    TargetSpeedFill.Parent = TargetSpeedSlider

    local TargetSpeedFillCorner = Instance.new("UICorner")
    TargetSpeedFillCorner.CornerRadius = UDim.new(0, 6)
    TargetSpeedFillCorner.Parent = TargetSpeedFill

    local TargetSpeedThumb = Instance.new("Frame")
    TargetSpeedThumb.Size = UDim2.new(0, 18, 0, 18)
    TargetSpeedThumb.Position = UDim2.new(0.03, -9, -0.25, 0)
    TargetSpeedThumb.BackgroundColor3 = TextColor
    TargetSpeedThumb.BorderSizePixel = 0
    TargetSpeedThumb.Parent = TargetSpeedSlider

    local TargetSpeedThumbCorner = Instance.new("UICorner")
    TargetSpeedThumbCorner.CornerRadius = UDim.new(0, 9)
    TargetSpeedThumbCorner.Parent = TargetSpeedThumb

    local ButtonGrid = Instance.new("Frame")
    ButtonGrid.Size = UDim2.new(0.96, 0, 0, 100)
    ButtonGrid.Position = UDim2.new(0.02, 0, 0.65, 0)
    ButtonGrid.BackgroundTransparency = 1
    ButtonGrid.Parent = MainFrame

    local buttons = {
        {name = "AutoParry", text = "🛡️ Auto", row = 0, col = 0, enabled = AutoParryEnabled},
        {name = "Clicker", text = "⚡ Clicker", row = 0, col = 1, enabled = AutoClickerEnabled},
        {name = "Target", text = "🎯 Target", row = 1, col = 0, enabled = TargetEnabled},
        {name = "HVH", text = "💥 HVH", row = 1, col = 1, enabled = HVHEnabled},
        {name = "Teleport", text = "📍 Teleport", row = 2, col = 0},
        {name = "AutoInter", text = "🏠 Auto Inter", row = 2, col = 1, enabled = AutoIntermissionEnabled}
    }

    local buttonInstances = {}

    for _, buttonInfo in ipairs(buttons) do
        local button = Instance.new("TextButton")
        button.Name = buttonInfo.name
        button.Size = UDim2.new(0.48, 0, 0, 28)
        button.Position = UDim2.new(buttonInfo.col * 0.52, 0, buttonInfo.row * 0.33, 0)
        
        if buttonInfo.enabled ~= nil then
            button.BackgroundColor3 = buttonInfo.enabled and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
        else
            button.BackgroundColor3 = PurpleGradient[2]
        end
        
        button.BorderSizePixel = 0
        button.TextColor3 = DarkTextColor
        button.TextSize = 12
        button.Font = Enum.Font.GothamBold
        button.Parent = ButtonGrid
        
        local buttonCorner = Instance.new("UICorner")
        buttonCorner.CornerRadius = UDim.new(0, 8)
        buttonCorner.Parent = button
        
        if buttonInfo.name == "AutoParry" then
            UpdateButtonText(button, buttonInfo.text .. (AutoParryEnabled and "-ON" or "-OFF"), Binds.AutoParry)
        elseif buttonInfo.name == "Clicker" then
            UpdateButtonText(button, buttonInfo.text .. (AutoClickerEnabled and " ON" or " OFF"), Binds.Clicker)
        elseif buttonInfo.name == "Target" then
            UpdateButtonText(button, buttonInfo.text .. (TargetEnabled and " ON" or " OFF"), Binds.Target)
        elseif buttonInfo.name == "HVH" then
            UpdateButtonText(button, buttonInfo.text .. (HVHEnabled and " ON" or " OFF"), Binds.HVH)
        elseif buttonInfo.name == "Teleport" then
            UpdateButtonText(button, buttonInfo.text, Binds.Teleport)
        elseif buttonInfo.name == "AutoInter" then
            UpdateButtonText(button, buttonInfo.text .. (AutoIntermissionEnabled and " ON" or " OFF"), Binds.AutoInter)
        end
        
        buttonInstances[buttonInfo.name] = button
    end

    local dragging = false
    local dragStart = nil
    local startPos = nil

    TitleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
        end
    end)

    TitleBar.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            if dragging then
                local delta = input.Position - dragStart
                MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end
    end)

    TitleBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    local function ToggleAutoIntermission()
        AutoIntermissionEnabled = not AutoIntermissionEnabled
        
        if AutoIntermissionEnabled then
            StatusLabel.Text = "🏠 Auto Intermission enabled"
            buttonInstances.AutoInter.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
            UpdateButtonText(buttonInstances.AutoInter, "🏠 Auto Inter ON", Binds.AutoInter)
        else
            StatusLabel.Text = "🏠 Auto Intermission disabled"
            buttonInstances.AutoInter.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
            UpdateButtonText(buttonInstances.AutoInter, "🏠 Auto Inter OFF", Binds.AutoInter)
        end
    end

    local function TeleportToNearestPlayer()
        local nearestPlayer = FindNearestPlayer()
        if nearestPlayer then
            if TeleportToPlayer(nearestPlayer) then
                StatusLabel.Text = "📍 Teleported to " .. nearestPlayer.Name
            else
                StatusLabel.Text = "📍 Teleport failed"
            end
        else
            StatusLabel.Text = "📍 No players found"
        end
    end

    buttonInstances.AutoParry.MouseButton2Click:Connect(function()
        StartBinding(buttonInstances.AutoParry, "AutoParry", "🛡️ Auto" .. (AutoParryEnabled and "-ON" or "-OFF"))
    end)

    buttonInstances.Clicker.MouseButton2Click:Connect(function()
        StartBinding(buttonInstances.Clicker, "Clicker", "⚡ Clicker" .. (AutoClickerEnabled and " ON" or " OFF"))
    end)

    buttonInstances.Target.MouseButton2Click:Connect(function()
        StartBinding(buttonInstances.Target, "Target", "🎯 Target" .. (TargetEnabled and " ON" or " OFF"))
    end)

    buttonInstances.HVH.MouseButton2Click:Connect(function()
        StartBinding(buttonInstances.HVH, "HVH", "💥 HVH" .. (HVHEnabled and " ON" or " OFF"))
    end)

    buttonInstances.Teleport.MouseButton2Click:Connect(function()
        StartBinding(buttonInstances.Teleport, "Teleport", "📍 Teleport")
    end)

    buttonInstances.AutoInter.MouseButton2Click:Connect(function()
        StartBinding(buttonInstances.AutoInter, "AutoInter", "🏠 Auto Inter" .. (AutoIntermissionEnabled and " ON" or " OFF"))
    end)

    buttonInstances.AutoParry.MouseButton1Click:Connect(function()
        AutoParryEnabled = not AutoParryEnabled
        buttonInstances.AutoParry.BackgroundColor3 = AutoParryEnabled and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
        UpdateButtonText(buttonInstances.AutoParry, "🛡️ Auto" .. (AutoParryEnabled and "-ON" or "-OFF"), Binds.AutoParry)
    end)

    buttonInstances.Clicker.MouseButton1Click:Connect(function()
        AutoClickerEnabled = not AutoClickerEnabled
        buttonInstances.Clicker.BackgroundColor3 = AutoClickerEnabled and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
        UpdateButtonText(buttonInstances.Clicker, "⚡ Clicker" .. (AutoClickerEnabled and " ON" or " OFF"), Binds.Clicker)
    end)

    buttonInstances.Target.MouseButton1Click:Connect(function()
        ToggleTarget()
        if TargetEnabled then
            StatusLabel.Text = "🎯 Targeting enabled"
            buttonInstances.Target.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
            UpdateButtonText(buttonInstances.Target, "🎯 Target ON", Binds.Target)
        else
            StatusLabel.Text = "🎯 Targeting disabled"
            buttonInstances.Target.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
            UpdateButtonText(buttonInstances.Target, "🎯 Target OFF", Binds.Target)
        end
    end)

    buttonInstances.HVH.MouseButton1Click:Connect(function()
        ToggleHVH()
        if HVHEnabled then
            StatusLabel.Text = "💥 HVH enabled"
            buttonInstances.HVH.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
            UpdateButtonText(buttonInstances.HVH, "💥 HVH ON", Binds.HVH)
        else
            StatusLabel.Text = "💥 HVH disabled"
            buttonInstances.HVH.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
            UpdateButtonText(buttonInstances.HVH, "💥 HVH OFF", Binds.HVH)
        end
    end)

    buttonInstances.Teleport.MouseButton1Click:Connect(function()
        TeleportToNearestPlayer()
    end)

    buttonInstances.AutoInter.MouseButton1Click:Connect(function()
        ToggleAutoIntermission()
    end)

    CloseButton.MouseButton1Click:Connect(function()
        MainFrame.Visible = false
    end)

    local function SetupSliderDrag(slider, thumb, fill, callback, minValue, maxValue, defaultValue)
        local dragging = false
        
        local function updateFromMouse()
            if not dragging then return end
            
            local mousePos = UserInputService:GetMouseLocation()
            local sliderAbsPos = slider.AbsolutePosition
            local sliderAbsSize = slider.AbsoluteSize
            
            local relativeX = (mousePos.X - sliderAbsPos.X) / sliderAbsSize.X
            relativeX = math.clamp(relativeX, 0, 1)
            
            local value = minValue + (relativeX * (maxValue - minValue))
            callback(value)
        end
        
        thumb.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                thumb.BackgroundColor3 = AccentColor
            end
        end)
        
        slider.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                updateFromMouse()
                thumb.BackgroundColor3 = AccentColor
            end
        end)
        
        UserInputService.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement then
                updateFromMouse()
            end
        end)
        
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
                thumb.BackgroundColor3 = TextColor
            end
        end)
        
        if defaultValue then
            local relativeValue = (defaultValue - minValue) / (maxValue - minValue)
            callback(defaultValue)
        end
    end

    local function UpdateDistanceSlider(value)
        ParryDistance = value
        local relativeValue = (value - 5) / 20
        DistanceFill.Size = UDim2.new(relativeValue, 0, 1, 0)
        DistanceThumb.Position = UDim2.new(relativeValue, -9, -0.25, 0)
        DistanceLabel.Text = "🎯 Parry Distance: " .. math.floor(value)
    end

    local function UpdateTargetRadiusSlider(value)
        currentRadius = value
        local relativeValue = (value - 40) / 960
        TargetRadiusFill.Size = UDim2.new(relativeValue, 0, 1, 0)
        TargetRadiusThumb.Position = UDim2.new(relativeValue, -9, -0.25, 0)
        TargetRadiusLabel.Text = "🎯 Target Radius: " .. math.floor(value)
    end

    local function UpdateTargetSpeedSlider(value)
        rotationSpeed = value
        local relativeValue = (value - 0.5) / 49.5
        TargetSpeedFill.Size = UDim2.new(relativeValue, 0, 1, 0)
        TargetSpeedThumb.Position = UDim2.new(relativeValue, -9, -0.25, 0)
        TargetSpeedLabel.Text = "🎯 Target Speed: " .. string.format("%.1f", value)
    end

    SetupSliderDrag(DistanceSlider, DistanceThumb, DistanceFill, UpdateDistanceSlider, 5, 25, 15)
    SetupSliderDrag(TargetRadiusSlider, TargetRadiusThumb, TargetRadiusFill, UpdateTargetRadiusSlider, 40, 1000, 45)
    SetupSliderDrag(TargetSpeedSlider, TargetSpeedThumb, TargetSpeedFill, UpdateTargetSpeedSlider, 0.5, 50, 2)

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        if input.KeyCode == Binds.ToggleGUI then
            MainFrame.Visible = not MainFrame.Visible
        
        elseif input.KeyCode == Binds.Clicker then
            AutoClickerEnabled = not AutoClickerEnabled
            buttonInstances.Clicker.BackgroundColor3 = AutoClickerEnabled and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
            UpdateButtonText(buttonInstances.Clicker, "⚡ Clicker" .. (AutoClickerEnabled and " ON" or " OFF"), Binds.Clicker)
        
        elseif input.KeyCode == Binds.Target then
            ToggleTarget()
            if TargetEnabled then
                StatusLabel.Text = "🎯 Targeting enabled"
                buttonInstances.Target.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
                UpdateButtonText(buttonInstances.Target, "🎯 Target ON", Binds.Target)
            else
                StatusLabel.Text = "🎯 Targeting disabled"
                buttonInstances.Target.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
                UpdateButtonText(buttonInstances.Target, "🎯 Target OFF", Binds.Target)
            end
        
        elseif input.KeyCode == Binds.Teleport then
            TeleportToNearestPlayer()
        
        elseif input.KeyCode == Binds.AutoParry then
            AutoParryEnabled = not AutoParryEnabled
            buttonInstances.AutoParry.BackgroundColor3 = AutoParryEnabled and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
            UpdateButtonText(buttonInstances.AutoParry, "🛡️ Auto" .. (AutoParryEnabled and "-ON" or "-OFF"), Binds.AutoParry)
        
        elseif input.KeyCode == Binds.HVH then
            ToggleHVH()
            if HVHEnabled then
                StatusLabel.Text = "💥 HVH enabled"
                buttonInstances.HVH.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
                UpdateButtonText(buttonInstances.HVH, "💥 HVH ON", Binds.HVH)
            else
                StatusLabel.Text = "💥 HVH disabled"
                buttonInstances.HVH.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
                UpdateButtonText(buttonInstances.HVH, "💥 HVH OFF", Binds.HVH)
            end
        
        elseif input.KeyCode == Binds.AutoInter then
            ToggleAutoIntermission()
        end
    end)

    local function UltraAutoClicker()
        if not AutoClickerEnabled then return end
        
        local currentTime = tick()
        local timeBetweenClicks = 1 / ClickSpeed
        
        if currentTime - LastClickTime >= timeBetweenClicks then
            VirtualInputManager:SendKeyEvent(true, "F", false, game)
            task.wait(0.000001)
            VirtualInputManager:SendKeyEvent(false, "F", false, game)
            LastClickTime = currentTime
        end
    end

    local function Parry()
        if IsParrying then return end
        
        IsParrying = true
        local currentTime = tick()
        
        if currentTime - LastParryTime < ParryCooldown then
            IsParrying = false
            return
        end
        
        VirtualInputManager:SendKeyEvent(true, "F", false, game)
        task.wait(0.000001)
        VirtualInputManager:SendKeyEvent(false, "F", false, game)
        
        LastParryTime = currentTime
        IsParrying = false
    end

    local function IsBallComingTowardsPlayer(ballPos, lastPos, playerPos)
        if not lastPos then return true end
        
        local ballToPlayer = (playerPos - ballPos).Unit
        local ballMovement = (ballPos - lastPos).Unit
        
        local dotProduct = ballToPlayer:Dot(ballMovement)
        
        return dotProduct > 0.1
    end

    local function CalculateOptimalParryDistance(speed, horizontalDistance, ballHeight, playerPosY, ballPosY)
        local baseDistance = ParryDistance
        local reactionDistance = speed * ReactionTime * SafetyMargin
        local optimalDistance = baseDistance + reactionDistance
        
        if speed > 20 then
            optimalDistance = optimalDistance * 1.4
        elseif speed > 12 then
            optimalDistance = optimalDistance * 1.3
        elseif speed > 6 then
            optimalDistance = optimalDistance * 1.2
        end
        
        return optimalDistance
    end

    coroutine.wrap(function()
        while true do
            UpdatePlayerCoordinates()
            wait(0.1)
        end
    end)()

    coroutine.wrap(function()
        while true do
            CheckAutoIntermission()
            wait(1)
        end
    end)()

    local LastParryCheckTime = 0
    local ParryCheckCooldown = 0.0001

    coroutine.wrap(function()
        while true do
            task.wait()
            
            if AutoClickerEnabled then
                UltraAutoClicker()
            end
            
            if not BallShadow then
                BallShadow = game.Workspace.FX:FindFirstChild("BallShadow")
            end
            
            if not RealBall then
                RealBall = workspace:FindFirstChild("Ball") or workspace:FindFirstChild("Part")
            end
            
            if BallShadow then
                if not LastBallPos then
                    LastBallPos = BallShadow.Position
                    LastBallPosForVelocity = BallShadow.Position
                    StatusLabel.Text = "🎯 Ball found"
                    
                    UpdateVisualBall(BallShadow.Position, BallShadow.Size.X)
                end
            else
                StatusLabel.Text = "🔍 Searching for ball..."
            end
            
            if BallShadow and (not BallShadow.Parent) then
                StatusLabel.Text = "⚠️ Ball removed"
                BallShadow = nil
                RealBall = nil
            end
            
            if BallShadow and LP.Character and LP.Character.PrimaryPart then
                local BallPos = BallShadow.Position
                local PlayerPos = LP.Character.PrimaryPart.Position
                
                if not LastBallPos then 
                    LastBallPos = BallPos 
                end

                if LastBallPosForVelocity then
                    local deltaTime = RunService.Heartbeat:Wait()
                    BallVelocity = (BallPos - LastBallPosForVelocity) / deltaTime
                end
                LastBallPosForVelocity = BallPos
                
                local currentShadowSize = BallShadow.Size.X
                local ballHeight = CalculateBallHeight(currentShadowSize)
                local ballPosY = BallPos.Y + ballHeight
                
                local moveDir = (LastBallPos - BallPos)
                local rawSpeed = moveDir.Magnitude
                local horizontalSpeed = Vector3.new(moveDir.X, 0, moveDir.Z).Magnitude
                local speedStuds = (horizontalSpeed + 0.25) * SpeedMulty
                
                local horizontalDistance = (Vector3.new(PlayerPos.X, 0, PlayerPos.Z) - Vector3.new(BallPos.X, 0, BallPos.Z)).Magnitude
                
                local ballColor = WhiteColor
                if RealBall then
                    ballColor = GetBallColor()
                end
                local isBallWhite = ballColor == WhiteColor
                
                local maxHeightForParry = GetMaxHeightBySpeed(speedStuds)
                
                local isComingTowardsPlayer = IsBallComingTowardsPlayer(BallPos, LastBallPos, PlayerPos)
                local optimalDistance = CalculateOptimalParryDistance(speedStuds, horizontalDistance, ballHeight, PlayerPos.Y, ballPosY)
                
                CoordinatesLabel.Text = string.format("X: %.1f | Y: %.1f | Z: %.1f\nSpeed: %.1f | Height: %.1f", 
                    BallPos.X, ballPosY, BallPos.Z, speedStuds, ballHeight)
                
                if isBallWhite then
                    StatusLabel.Text = "✅ White ball - safe"
                else
                    StatusLabel.Text = "⚠️ Dangerous - MaxH: " .. maxHeightForParry
                end
                
                UpdateVisualBall(BallPos, currentShadowSize)
                
                local currentTime = tick()
                if AutoParryEnabled and currentTime - LastParryCheckTime > ParryCheckCooldown then
                    local shouldParryNow = horizontalDistance <= optimalDistance 
                        and isComingTowardsPlayer 
                        and ballHeight <= maxHeightForParry
                        and not isBallWhite
                    
                    if shouldParryNow then
                        Parry()
                        StatusLabel.Text = "🛡️ PARRY! Speed: " .. math.floor(speedStuds) .. " MaxH: " .. maxHeightForParry
                    end
                    
                    LastParryCheckTime = currentTime
                end
                
                LastBallPos = BallPos
            else
                CoordinatesLabel.Text = "X: 0.0 | Y: 0.0 | Z: 0.0\nSpeed: 0.0 | Height: 0.0"
            end
        end
    end)()
end

InitializeMainScript()
