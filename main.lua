ver = 'V1.0.0'

local shared = (getgenv and getgenv()) or _G
local cloneref = (cloneref or clonereference) or function(obj) 
    return obj
end
local coreGui = cloneref(game:GetService('CoreGui'))
local playersService = cloneref(game:GetService('Players'))
local runService = cloneref(game:GetService("RunService"))
local userInputService = cloneref(game:GetService("UserInputService"))
local teamsService = cloneref(game:GetService("Teams"))

local lplr = playersService.LocalPlayer
local gameCamera = workspace.CurrentCamera

shared.havocgarbagecollector = function()
    -- no idea yet on how to remove the current gui, I'll do it on newer updates probably
    if shared.havoc then
        for _, obj in ipairs(shared.havoc) do
            pcall(function()
                if typeof(obj) == "RBXScriptConnection" then
                    obj:Disconnect()
                elseif typeof(obj) == "Instance" then
                    obj:Destroy()
                end
            end)
            pcall(function() obj = nil end)
        end
    end
end
shared.havocgarbagecollector()

shared.havoc = {}
local havoc = shared.havoc

local suc, res = pcall(function()
    return loadstring(game:HttpGet('https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/Library.lua'))()
end)

local libgui
if suc and (res and res ~= '') then
    libgui = res
else
    return res
end

local Window = libgui:CreateWindow({
    Title = 'Havoc '..ver,
    Center = true,
    AutoShow = true,
    TabPadding = 8,
    MenuFadeTime = 0.2
})

libgui:SetWatermarkVisibility(true)
libgui:SetWatermark('HAVOC '..ver:upper()..' TESTING')

local Tabs = {
    Automation = Window:AddTab('Automation'),
    Visuals = Window:AddTab('Visuals'),
    Miscellaneous = Window:AddTab('Miscellaneous'),
    ['UI Settings'] = Window:AddTab('Settings')
}

local TabBox = Tabs.Automation:AddLeftTabbox()
local Aim = TabBox:AddTab('Aim')
local AimSettings = TabBox:AddTab('Aim Settings')

local TabBox = Tabs.Visuals:AddLeftTabbox()
local EnemyESP = TabBox:AddTab('Enemy ESP')
local ESPSettings = TabBox:AddTab('ESP Settings')

local TabBox = Tabs.Miscellaneous:AddLeftTabbox()
local World = TabBox:AddTab('World')
local WorldSettings = TabBox:AddTab('World Settings')

local TabBox = Tabs.Miscellaneous:AddRightTabbox()
local Player = TabBox:AddTab('Player')
local PlayerSettings = TabBox:AddTab('Player Settings')

local themeManager = loadstring(game:HttpGet('https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/addons/ThemeManager.lua'))()
local saveManager = loadstring(game:HttpGet('https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/addons/SaveManager.lua'))()

themeManager:SetLibrary(libgui)
saveManager:SetLibrary(libgui)

saveManager:SetIgnoreIndexes({
    'MenuKeybind'
})

if not isfolder('havoc') then
    makefolder('havoc')
end
if not isfolder('havoc/savedgames') then
    makefolder('havoc/savedgames')
end
themeManager:SetFolder('havoc')
saveManager:SetFolder('havoc/savedgames/' .. game.PlaceId)

saveManager:BuildConfigSection(Tabs['UI Settings'])

local themeGroup = Tabs['UI Settings']:AddLeftGroupbox('Themes')
themeManager:ApplyToGroupbox(themeGroup)

saveManager:LoadAutoloadConfig()

local aimbotEnabled = false
local requireRightClick = false
local autoclickEnabled = false
local requiresLeftClick = false
local teamCheckEnabled = false
local wallCheckEnabled = false
local fovEnabled = false
local smoothingEnabled = false
local stickyEnabled = false
local checkFirstPerson = false
local messyEnabled = false
local reactionDelayEnabled = false
local maxDistanceEnabled = false
local currentTarget = nil
local messyOffset = Vector3.zero
local targetAcquireTime = 0
local currentReactionDelay = 0

local fovCircle
local aimbotConnection
local lastClick = 0

local hasTeams = #teamsService:GetChildren() > 0
teamsService.ChildAdded:Connect(function()
    hasTeams = #teamsService:GetChildren() > 0
end)
teamsService.ChildRemoved:Connect(function()
    hasTeams = #teamsService:GetChildren() > 0
end)

local function getScreenCenter()
    local vp = gameCamera.ViewportSize
    return Vector2.new(vp.X * 0.5, vp.Y * 0.5)
end

local function isFirstPerson()
    if lplr.CameraMode == Enum.CameraMode.LockFirstPerson then
        return true
    end
    if userInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
        local dist = (gameCamera.CFrame.Position - gameCamera.Focus.Position).Magnitude
        return dist < 1.5
    end
    return false
end

local function getTargetPart(character)
    if Options.TargetPart.Value == "Head" then
        return character:FindFirstChild("Head")
    end
    return character:FindFirstChild("HumanoidRootPart")
end

local function passesWallCheck(part)
    if not wallCheckEnabled then
        return true
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = { lplr.Character, part.Parent }
    local origin = gameCamera.CFrame.Position
    local direction = part.Position - origin
    return workspace:Raycast(origin, direction, params) == nil
end

local function withinMaxDistance(part)
    if not maxDistanceEnabled then
        return true
    end
    local distance = (part.Position - lplr.Character.HumanoidRootPart.Position).Magnitude
    return distance <= Options.MaxDistance.Value
end

local function updateFOVCircle()
    if fovEnabled and aimbotEnabled then
        if not fovCircle then
            fovCircle = Drawing.new("Circle")
            fovCircle.Visible = true
            fovCircle.Filled = false
            fovCircle.Thickness = 1
            fovCircle.NumSides = 128
            fovCircle.Transparency = 1
            fovCircle.Color = Color3.fromRGB(255, 255, 255)
            fovCircle.Radius = Options.FOVRadius.Value
            fovCircle.Position = getScreenCenter()
            table.insert(havoc, fovCircle)
        end
    else
        if fovCircle then
            fovCircle:Remove()
            fovCircle = nil
        end
    end
end

Aim:AddToggle("Aimbot", {
    Text = "Aimbot",
    Default = false,
    Callback = function(state)
        aimbotEnabled = state
        if aimbotConnection then
            aimbotConnection:Disconnect()
            aimbotConnection = nil
        end
        updateFOVCircle()
        if not state then
            currentTarget = nil
            return
        end
        aimbotConnection = runService.RenderStepped:Connect(function()
            if not aimbotEnabled then return end
            if checkFirstPerson and not isFirstPerson() then return end
            if requireRightClick and not userInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return end
            local cam = gameCamera
            local camPos = cam.CFrame.Position
            local screenCenter = getScreenCenter()
            if fovEnabled and fovCircle then
                fovCircle.Position = screenCenter
                fovCircle.Radius = Options.FOVRadius.Value
            end
            local closestTarget = nil
            local closestDist = math.huge
            for _, plr in ipairs(playersService:GetPlayers()) do
                if plr == lplr then continue end
                if teamCheckEnabled and hasTeams and plr.Team == lplr.Team then continue end
                local char = plr.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                local part = char and getTargetPart(char)
                if hum and hum.Health > 0 and part
                    and passesWallCheck(part)
                    and withinMaxDistance(part) then
                    local screenPos, onScreen = cam:WorldToViewportPoint(part.Position)
                    if not onScreen then continue end
                    local screenDist =
                        (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                    if fovEnabled and screenDist > Options.FOVRadius.Value then continue end
                    local worldDist = (part.Position - camPos).Magnitude
                    if worldDist < closestDist then
                        closestDist = worldDist
                        closestTarget = part
                    end
                end
            end
            currentTarget = closestTarget
            if not currentTarget then return end
            if reactionDelayEnabled then
                if not targetAcquireTime or currentTarget ~= lastTarget then
                    targetAcquireTime = tick()
                    currentReactionDelay = Options.ReactionDelay.Value + math.random() * Options.ReactionRandom.Value
                end
                if tick() - targetAcquireTime < currentReactionDelay then return end
            end
            lastTarget = currentTarget
            local camCF = cam.CFrame
            local targetPos = currentTarget.Position
            if messyEnabled then
                local intensity = Options.MessyIntensity.Value
                local smooth = math.clamp(Options.MessySmoothness.Value / 100, 0.01, 1)
                local offset = Vector3.new(
                    (math.random() - 0.5) * intensity,
                    (math.random() - 0.5) * intensity,
                    (math.random() - 0.5) * intensity
                )
                messyOffset = messyOffset:Lerp(offset, smooth)
                targetPos += messyOffset
            end
            local targetCF = CFrame.lookAt(camCF.Position, targetPos)
            if smoothingEnabled then
                local alpha = math.clamp(Options.Smoothing.Value / 100, 0.01, 1)
                cam.CFrame = camCF:Lerp(targetCF, alpha)
            else
                cam.CFrame = targetCF
            end
            if autoclickEnabled then
                if requiresLeftClick and not userInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
                    return
                end
                local delay = 1 / Options.CPS.Value
                if tick() - lastClick >= delay then
                    lastClick = tick()
                    mouse1press()
                    task.wait()
                    mouse1release()
                end
            end
        end)
        table.insert(havoc, aimbotConnection)
    end
})
Aim:AddToggle("FOV", {
    Text = "FOV",
    Tooltip = 'If anyone is in the circle, the aimbot locks onto them',
    Default = false,
    Callback = function(v)
        fovEnabled = v
        updateFOVCircle()
    end
})

-- why did i even do this?
AimSettings:AddSlider("FOVRadius", { Text = "FOV Radius", Default = 50, Min = 0, Max = 1000, Rounding = 0 })
Aim:AddToggle("RequireRightClick", { Text = "Require Right-Click", Default = false, Tooltip = 'Aimbot is only active if holding MB2', Callback = function(v) requireRightClick = v end })
Aim:AddToggle("RequiresLeftClick", { Text = "Requires Left-Click", Tooltip = 'Autoclick is only active if holding MB1', Default = false, Callback = function(v) requiresLeftClick = v end })
Aim:AddToggle("Autoclick", { Text = "Autoclick", Default = false, Tooltip = 'Autoclicks when aimbot is locked on someone', Callback = function(v) autoclickEnabled = v end })
AimSettings:AddSlider("CPS", { Text = "CPS (Clicks per second)", Default = 10, Min = 1, Max = 25, Rounding = 0 })
Aim:AddToggle("CheckFirstPerson", { Text = "First-Person Check", Default = false, Tooltip = 'Checks if you\'re in first person', Callback = function(v) checkFirstPerson = v end })
Aim:AddToggle("TeamCheck", { Text = "Team Check", Default = false, Callback = function(v) teamCheckEnabled = v end })
Aim:AddToggle("WallCheck", { Text = "Wall Check", Default = false, Callback = function(v) wallCheckEnabled = v end })
AimSettings:AddDropdown("TargetPart", { Text = "Target Part", Values = { "Head", "Torso" }, Default = 2 })
Aim:AddToggle("SmoothingToggle", { Text = "Smoothing", Default = false, Callback = function(v) smoothingEnabled = v end })
AimSettings:AddSlider("Smoothing", { Text = "Smoothing Amount", Default = 25, Min = 1, Max = 100, Rounding = 0 })

Options.FOVRadius:OnChanged(function()
    if fovCircle then
        fovCircle.Radius = Options.FOVRadius.Value
    end
end)

Aim:AddToggle("Sticky", {
    Text = "Sticky",
    Default = false,
    Tooltip = 'Prevents unlocking off the current target',
    Callback = function(v)
        stickyEnabled = v
        if not v then
            currentTarget = nil
        end
    end
})

Aim:AddToggle("Messy", {
    Text = "Messy",
    Default = false,
    Tooltip = "Makes aimbot improper",
    Callback = function(v) messyEnabled = v end
})

AimSettings:AddSlider("MessyIntensity", {
    Text = "Messy Intensity",
    Default = 10,
    Min = 0,
    Max = 500,
    Rounding = 0
})

AimSettings:AddSlider("MessySmoothness", {
    Text = "Messy Smoothness",
    Default = 25,
    Min = 1,
    Max = 100,
    Rounding = 0
})

Aim:AddToggle("ReactionDelay", {
    Text = "Reaction Delay",
    Default = false,
    Tooltip = "Waits a certain amount of time before locking onto someone",
    Callback = function(v) reactionDelayEnabled = v end
})

AimSettings:AddSlider("ReactionDelaySlider", {
    Text = "Base Delay (s)",
    Default = 0.08,
    Min = 0,
    Max = 1,
    Rounding = 2,
    Suffix = 0.01
})

AimSettings:AddSlider("ReactionRandom", {
    Text = "Random Delay (s)",
    Default = 0.04,
    Min = 0,
    Max = 0.3,
    Rounding = 2,
    Suffix = 0.01
})

Aim:AddToggle("MaxDistanceToggle", {
    Text = "Max Distance",
    Tooltip = 'Only locks people who are within the studs near you',
    Default = false,
    Callback = function(v) maxDistanceEnabled = v end
})

AimSettings:AddSlider("MaxDistance", {
    Text = "Max Distance (Studs)",
    Default = 50,
    Min = 0,
    Max = 1000,
    Rounding = 0
})

