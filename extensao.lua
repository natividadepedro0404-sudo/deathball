local AutoParryHelper = {}

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

function AutoParryHelper.FindTargetBall()
    for _, part in pairs(workspace:GetChildren()) do
        if part:IsA("BasePart") and part.Name == "Part" then 
            if part.Size == Vector3.new(1, 1, 1) or part:GetAttribute("ball") then
                return part
            end
        end
    end
end

function AutoParryHelper.IsPlayerTarget(ball)
    return ball:GetAttribute("target") == localPlayer.Name
end

return AutoParryHelper
