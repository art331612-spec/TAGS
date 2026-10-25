-- [INIT]
local Players = game:GetService("Players")
local RS = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer

local Speed, Jump, Noclip, Tracers, Fly, ESP = 16, 50, false, false, false, false
local Hitbox, Hover = false, false
local HITBOX_SIZE = 35

-- FOV: всегда 120, ползунок = только Stretch 1.0–2.0
local Stretch = 1.0
local BaseFOV = 120  -- константа, минимум = 120

local MyHumanoid, MyChar, MyHRP = nil, nil, nil
local Connections, tracerLines = {}, {}
local stickTarget = nil
local flyVel, flyGyro = nil, nil
local espData = {}
local hoverLastDodge = 0
local hoverIsHovering, hoverIsRising = false, false
local hoverY = nil
local hoverBodyPos, hoverBodyVel = nil, nil
local hoverRiseStartTime, hoverRiseStartY, hoverRiseTargetY

local DETECT_RANGE = 32
local LOSE_RANGE = 48
local HOVER_HEIGHT_FROM_GROUND = 48
local RISE_TIME = 0.5
local AIR_MOVE_SPEED = 45
local Y_VELOCITY_KILL_THRESHOLD = 8
local HOVER_COOLDOWN = 2.0

-- [TEAM DETECTION]
local function getRoleColor(plr)
    local c = plr:GetAttribute("RoleColor")
    if c and typeof(c) == "Color3" then return c end
    if plr.Character then
        local cc = plr.Character:GetAttribute("RoleColor")
        if cc and typeof(cc) == "Color3" then return cc end
    end
    return nil
end
local function isDead(plr)
    if plr:GetAttribute("DeadRole") == true then return true end
    if plr.Character and plr.Character:GetAttribute("DeadRole") == true then return true end
    return false
end
local function colorEqual(a, b)
    if not a or not b then return false end
    return math.abs(a.R - b.R) < 0.02 and math.abs(a.G - b.G) < 0.02 and math.abs(a.B - b.B) < 0.02
end
local function isWhite(c)
    if not c then return false end
    return c.R > 0.9 and c.G > 0.9 and c.B > 0.9
end
local function isEnemy(plr)
    if plr == LP or isDead(plr) then return false end
    local theirs = getRoleColor(plr)
    if not theirs then return true end
    if isWhite(theirs) then return false end
    local mine = getRoleColor(LP)
    if not mine or isWhite(mine) then return true end
    return not colorEqual(mine, theirs)
end
local function computeColor(plr)
    local c = getRoleColor(plr)
    if isDead(plr) or (c and isWhite(c)) then
        return Color3.fromRGB(230, 230, 230)
    elseif c then
        return c
    else
        return Color3.fromRGB(150, 150, 150)
    end
end

-- [ROLE HELPERS]
local function getMyRole()
    if not MyChar then return nil end
    local role = MyChar:GetAttribute("LastUpdateRole")
    if role then return role end
    return LP:GetAttribute("RagdollRole")
end
local function getTheirRole(plr)
    local char = plr.Character
    if char then
        local r = char:GetAttribute("LastUpdateRole")
        if r then return r end
    end
    return plr:GetAttribute("RagdollRole")
end
local function isCrownHolder(plr)
    local char = plr.Character
    if not char then return false end
    for _, obj in ipairs(char:GetChildren()) do
        if obj:IsA("Accessory") then
            local n = obj.Name:lower()
            if n:find("crown") or n:find("king") or n:find("monarch") then return true end
        end
    end
    for _, obj in ipairs(char:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name:lower():find("crown") then return true end
    end
    local role = getTheirRole(plr)
    if role == "Crown" or role == "Monarch" then return true end
    if plr:GetAttribute("HasCrown") == true then return true end
    if char:GetAttribute("HasCrown") == true then return true end
    return false
end
local function isPreyRole(plr)
    local myRole = getMyRole()
    local theirRole = getTheirRole(plr)
    if not myRole or not theirRole then return false end
    if myRole == "Infected" or myRole == "PatientZero" or myRole == "Patient Zero"
       or myRole == "Zombie" or myRole == "Mutant" then
        if theirRole == "Runner" or theirRole == "Survivor" or theirRole == "Human" then return true end
    end
    if myRole == "Freezer" or myRole == "Chiller" or myRole == "Slasher" then
        if theirRole == "Runner" or theirRole == "Survivor" then return true end
    end
    if myRole == "Tagger" then
        if theirRole == "Runner" or theirRole == "Survivor" then return true end
    end
    if myRole == "Bomb" or myRole == "BombTagger" or myRole == "HotPotato"
       or myRole == "FunnyBomb" or myRole == "RNG_Bomb" or myRole == "SubspaceBomb"
       or myRole == "NuclearBomb" or myRole == "RedemptionBomb" or myRole == "BombRunner" then
        if theirRole == "Runner" or theirRole == "Survivor" then return true end
    end
    return false
end

-- [UI]
local gui = Instance.new("ScreenGui")
gui.Name = "TagMenu_" .. math.random(1e6)
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent = LP:WaitForChild("PlayerGui")

local floatBtn = Instance.new("TextButton")
floatBtn.Size = UDim2.fromOffset(44, 44)
floatBtn.Position = UDim2.new(0, 55, 0.5, -22)
floatBtn.BackgroundColor3 = Color3.fromRGB(100, 80, 240)
floatBtn.Text = "⚙"
floatBtn.Font = Enum.Font.GothamBold
floatBtn.TextSize = 20
floatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
floatBtn.AutoButtonColor = false
floatBtn.Parent = gui
Instance.new("UICorner", floatBtn).CornerRadius = UDim.new(1, 0)
local floatStroke = Instance.new("UIStroke", floatBtn)
floatStroke.Color = Color3.fromRGB(140, 120, 255)
floatStroke.Thickness = 1.5
local floatGrad = Instance.new("UIGradient", floatBtn)
floatGrad.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 100, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 60, 200))
}
floatGrad.Rotation = 90

local tpCircle = Instance.new("TextButton")
tpCircle.Size = UDim2.fromOffset(56, 56)
tpCircle.Position = UDim2.new(1, -160, 0.5, 0)
tpCircle.BackgroundColor3 = Color3.fromRGB(100, 80, 240)
tpCircle.Text = "TP"
tpCircle.Font = Enum.Font.GothamBlack
tpCircle.TextSize = 16
tpCircle.TextColor3 = Color3.fromRGB(255, 255, 255)
tpCircle.AutoButtonColor = false
tpCircle.Parent = gui
Instance.new("UICorner", tpCircle).CornerRadius = UDim.new(1, 0)
local tpCircleStroke = Instance.new("UIStroke", tpCircle)
tpCircleStroke.Color = Color3.fromRGB(140, 120, 255)
tpCircleStroke.Thickness = 2
local tpCircleGrad = Instance.new("UIGradient", tpCircle)
tpCircleGrad.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 100, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 60, 200))
}
tpCircleGrad.Rotation = 90

-- МЕНЮ 280×260 — влезает в телефон
local MENU_W, MENU_H = 280, 260

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(MENU_W, MENU_H)
main.Position = UDim2.new(0.5, -MENU_W/2, 0.5, -MENU_H/2)
main.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
main.BorderSizePixel = 0
main.ClipsDescendants = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 14)
local stroke = Instance.new("UIStroke", main)
stroke.Color = Color3.fromRGB(80, 70, 140)
stroke.Thickness = 1.5
stroke.Transparency = 0.2
local grad = Instance.new("UIGradient", main)
grad.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(32, 30, 48)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 14, 20))
}
grad.Rotation = 90

local accentBar = Instance.new("Frame")
accentBar.Size = UDim2.new(1, 0, 0, 2)
accentBar.Position = UDim2.new(0, 0, 0, 0)
accentBar.BackgroundColor3 = Color3.fromRGB(140, 120, 255)
accentBar.BorderSizePixel = 0
accentBar.ZIndex = 2
accentBar.Parent = main
local accentGrad = Instance.new("UIGradient", accentBar)
accentGrad.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 80, 255)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(180, 140, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 80, 255))
}

local menuOpen = true
local function openMenu()
    menuOpen = true
    main.Visible = true
    main.Size = UDim2.fromOffset(0, 0)
    main.Position = UDim2.new(0.5, 0, 0.5, 0)
    TweenService:Create(main, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        Size = UDim2.fromOffset(MENU_W, MENU_H),
        Position = UDim2.new(0.5, -MENU_W/2, 0.5, -MENU_H/2)
    }):Play()
    TweenService:Create(floatBtn, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
        BackgroundColor3 = Color3.fromRGB(100, 80, 240)
    }):Play()
    floatStroke.Color = Color3.fromRGB(140, 120, 255)
end
local function closeMenu()
    menuOpen = false
    TweenService:Create(main, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
        Size = UDim2.fromOffset(0, 0),
        Position = UDim2.new(0.5, 0, 0.5, 0)
    }):Play()
    task.delay(0.3, function()
        if not menuOpen then main.Visible = false end
    end)
    TweenService:Create(floatBtn, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
        BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    }):Play()
    floatStroke.Color = Color3.fromRGB(70, 70, 90)
end

floatBtn.MouseButton1Click:Connect(function()
    if menuOpen then closeMenu() else openMenu() end
end)

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 30)
header.Position = UDim2.new(0, 0, 0, 4)
header.BackgroundTransparency = 1
header.Parent = main

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -50, 1, 0)
title.Position = UDim2.new(0, 14, 0, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.Text = "TAG MENU"
title.TextSize = 13
title.TextColor3 = Color3.fromRGB(240, 240, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(22, 22)
close.Position = UDim2.new(1, -28, 0, 2)
close.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
close.Text = "×"
close.Font = Enum.Font.GothamBold
close.TextSize = 13
close.TextColor3 = Color3.fromRGB(255, 255, 255)
close.AutoButtonColor = false
close.Parent = header
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 5)
close.MouseButton1Click:Connect(closeMenu)

local dragStart, startPos
header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragStart = input.Position; startPos = main.Position
    end
end)
UIS.InputChanged:Connect(function(input)
    if dragStart and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local d = input.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragStart = nil end
end)

-- Тумблеры — компактные, 2 колонки
local function mkToggle(labelText, x, y, onChange)
    local container = Instance.new("Frame")
    container.Size = UDim2.fromOffset(124, 26)
    container.Position = UDim2.new(0, x, 0, y)
    container.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
    container.BorderSizePixel = 0
    container.Parent = main
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 7)
    local cStroke = Instance.new("UIStroke", container)
    cStroke.Color = Color3.fromRGB(50, 50, 65)
    cStroke.Thickness = 1

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -48, 1, 0)
    lbl.Position = UDim2.new(0, 8, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.Text = labelText
    lbl.TextSize = 10
    lbl.TextColor3 = Color3.fromRGB(210, 210, 230)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = container

    local t = Instance.new("TextButton")
    t.Size = UDim2.fromOffset(32, 16)
    t.Position = UDim2.new(1, -38, 0.5, -8)
    t.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    t.Text = "OFF"
    t.Font = Enum.Font.GothamBold
    t.TextSize = 9
    t.TextColor3 = Color3.fromRGB(180, 180, 200)
    t.AutoButtonColor = false
    t.Parent = container
    Instance.new("UICorner", t).CornerRadius = UDim.new(0, 8)
    local ts = Instance.new("UIStroke", t)
    ts.Color = Color3.fromRGB(70, 70, 90)

    local state = false
    t.MouseButton1Click:Connect(function()
        state = not state
        TweenService:Create(t, TweenInfo.new(0.22, Enum.EasingStyle.Quad), {
            BackgroundColor3 = state and Color3.fromRGB(100, 80, 240) or Color3.fromRGB(40, 40, 50)
        }):Play()
        TweenService:Create(cStroke, TweenInfo.new(0.22, Enum.EasingStyle.Quad), {
            Color = state and Color3.fromRGB(140, 120, 255) or Color3.fromRGB(50, 50, 65)
        }):Play()
        ts.Color = state and Color3.fromRGB(140, 120, 255) or Color3.fromRGB(70, 70, 90)
        t.Text = state and "ON" or "OFF"
        onChange(state)
    end)
end

mkToggle("Noclip", 14, 38, function(v) Noclip = v end)
mkToggle("Tracers", 142, 38, function(v) Tracers = v end)
mkToggle("Fly", 14, 68, function(v)
    Fly = v
    if not v and stopFly then stopFly() end
end)
mkToggle("ESP", 142, 68, function(v)
    ESP = v
    if not v and clearAllESP then clearAllESP() end
end)
mkToggle("Hitbox", 14, 98, function(v)
    Hitbox = v
    if not v then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and plr.Character then
                local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    hrp.Size = Vector3.new(2, 2, 1)
                    hrp.Transparency = 1
                    hrp.Material = Enum.Material.Plastic
                    hrp.CanCollide = true
                end
            end
        end
    end
end)
mkToggle("Hover", 142, 98, function(v)
    Hover = v
    if not v then
        hoverIsHovering, hoverIsRising = false, false
        hoverY = nil
        if hoverBodyPos then hoverBodyPos:Destroy(); hoverBodyPos = nil end
        if hoverBodyVel then hoverBodyVel:Destroy(); hoverBodyVel = nil end
    end
end)

local function createSlider(text, y, minV, maxV, default, callback)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -28, 0, 12)
    lbl.Position = UDim2.new(0, 14, 0, y)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.Text = text..": "..default
    lbl.TextSize = 10
    lbl.TextColor3 = Color3.fromRGB(190, 190, 210)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = main

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -28, 0, 4)
    bar.Position = UDim2.new(0, 14, 0, y + 14)
    bar.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    bar.BorderSizePixel = 0
    bar.Parent = main
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 2)

    local a0 = (default - minV) / (maxV - minV)
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(a0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(120, 100, 255)
    fill.BorderSizePixel = 0
    fill.ZIndex = 2
    fill.Parent = bar
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 2)
    local fGrad = Instance.new("UIGradient", fill)
    fGrad.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 80, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 130, 255))
    }

    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(10, 10)
    dot.Position = UDim2.new(a0, -5, 0.5, -5)
    dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    dot.BorderSizePixel = 0
    dot.ZIndex = 3
    dot.Parent = bar
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    local hit = Instance.new("TextButton")
    hit.Size = UDim2.new(1, 0, 4, 0)
    hit.Position = UDim2.new(0, 0, -1.5, 0)
    hit.BackgroundTransparency = 1
    hit.Text = ""
    hit.Parent = bar

    local drag = false
    hit.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = true end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = false end
    end)
    UIS.InputChanged:Connect(function(i)
        if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local a = math.clamp((i.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
            local v = math.floor(minV + a * (maxV - minV))
            fill.Size = UDim2.new(a, 0, 1, 0)
            dot.Position = UDim2.new(a, -5, 0.5, -5)
            lbl.Text = text..": "..v
            callback(v)
        end
    end)
end

local function applyStats()
    if not MyHumanoid then return end
    pcall(function() MyHumanoid.WalkSpeed = Speed end)
    pcall(function() MyHumanoid.JumpPower = Jump end)
end

createSlider("Speed", 132, 16, 250, 16, function(v)
    Speed = v
    if MyHumanoid then pcall(function() MyHumanoid.WalkSpeed = v end) end
end)
createSlider("Jump", 164, 50, 500, 50, function(v)
    Jump = v
    if MyHumanoid then pcall(function() MyHumanoid.JumpPower = v end) end
end)

-- FOV slider — только Stretch, FOV всегда 120
local fovLbl = Instance.new("TextLabel")
fovLbl.Size = UDim2.new(1, -28, 0, 12)
fovLbl.Position = UDim2.new(0, 14, 0, 196)
fovLbl.BackgroundTransparency = 1
fovLbl.Font = Enum.Font.GothamBold
fovLbl.Text = "FOV Stretch: 1.00"
fovLbl.TextSize = 10
fovLbl.TextColor3 = Color3.fromRGB(190, 190, 210)
fovLbl.TextXAlignment = Enum.TextXAlignment.Left
fovLbl.Parent = main

local fovBar = Instance.new("Frame")
fovBar.Size = UDim2.new(1, -28, 0, 4)
fovBar.Position = UDim2.new(0, 14, 0, 210)
fovBar.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
fovBar.BorderSizePixel = 0
fovBar.Parent = main
Instance.new("UICorner", fovBar).CornerRadius = UDim.new(0, 2)

local fovFill = Instance.new("Frame")
fovFill.Size = UDim2.new(0, 0, 1, 0)
fovFill.BackgroundColor3 = Color3.fromRGB(100, 180, 255)
fovFill.BorderSizePixel = 0
fovFill.ZIndex = 2
fovFill.Parent = fovBar
Instance.new("UICorner", fovFill).CornerRadius = UDim.new(0, 2)
local fovGrad = Instance.new("UIGradient", fovFill)
fovGrad.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 100, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 180, 255))
}

local fovDot = Instance.new("Frame")
fovDot.Size = UDim2.fromOffset(10, 10)
fovDot.Position = UDim2.new(0, -5, 0.5, -5)
fovDot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
fovDot.BorderSizePixel = 0
fovDot.ZIndex = 3
fovDot.Parent = fovBar
Instance.new("UICorner", fovDot).CornerRadius = UDim.new(1, 0)

local fovHit = Instance.new("TextButton")
fovHit.Size = UDim2.new(1, 0, 4, 0)
fovHit.Position = UDim2.new(0, 0, -1.5, 0)
fovHit.BackgroundTransparency = 1
fovHit.Text = ""
fovHit.Parent = fovBar

local fovDrag = false
fovHit.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then fovDrag = true end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then fovDrag = false end
end)
UIS.InputChanged:Connect(function(i)
    if fovDrag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local a = math.clamp((i.Position.X - fovBar.AbsolutePosition.X) / fovBar.AbsoluteSize.X, 0, 1)
        Stretch = 1.0 + a * (2.0 - 1.0)  -- 1.0 до 2.0
        fovFill.Size = UDim2.new(a, 0, 1, 0)
        fovDot.Position = UDim2.new(a, -5, 0.5, -5)
        fovLbl.Text = "FOV Stretch: "..string.format("%.2f", Stretch)
    end
end)

local hintLbl = Instance.new("TextLabel")
hintLbl.Size = UDim2.new(1, -28, 0, 10)
hintLbl.Position = UDim2.new(0, 14, 0, 220)
hintLbl.BackgroundTransparency = 1
hintLbl.Font = Enum.Font.GothamBold
hintLbl.Text = "FOV = 120 always. Slider = distortion"
hintLbl.TextSize = 8
hintLbl.TextColor3 = Color3.fromRGB(140, 140, 160)
hintLbl.TextXAlignment = Enum.TextXAlignment.Left
hintLbl.Parent = main

-- [FLY]
local function startFly()
    if not MyHRP then return end
    if flyVel then return end
    flyVel = Instance.new("BodyVelocity")
    flyVel.Name = "FlyVelocity"
    flyVel.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    flyVel.Velocity = Vector3.zero
    flyVel.Parent = MyHRP
    flyGyro = Instance.new("BodyGyro")
    flyGyro.Name = "FlyGyro"
    flyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
    flyGyro.P = 1000
    flyGyro.D = 50
    flyGyro.CFrame = MyHRP.CFrame
    flyGyro.Parent = MyHRP
end

stopFly = function()
    if flyVel then flyVel:Destroy(); flyVel = nil end
    if flyGyro then flyGyro:Destroy(); flyGyro = nil end
end

-- [ESP]
local function clearESP(plr)
    local d = espData[plr]
    if not d then return end
    if d.highlight then pcall(function() d.highlight:Destroy() end) end
    espData[plr] = nil
end
clearAllESP = function()
    for p in pairs(espData) do clearESP(p) end
end
local function buildESP(plr)
    if plr == LP then return end
    local char = plr.Character
    if not char or not char:FindFirstChildOfClass("Humanoid") then return end
    if espData[plr] then return end
    local color = computeColor(plr)
    local hl = Instance.new("Highlight")
    hl.Name = "ESP_HL"
    hl.FillColor = color
    hl.FillTransparency = 0.75
    hl.OutlineColor = color
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = char
    hl.Parent = char
    espData[plr] = {highlight = hl, _color = color}
end
local function updateESP(plr)
    local d = espData[plr]
    if not d then return end
    local char = plr.Character
    if not char or not char:FindFirstChildOfClass("Humanoid") then return end
    local wantColor = computeColor(plr)
    if not colorEqual(d._color, wantColor) then
        d._color = wantColor
        if d.highlight then
            d.highlight.FillColor = wantColor
            d.highlight.OutlineColor = wantColor
        end
    end
end

-- [HOVER HELPERS]
local function findGroundY()
    if not MyHRP then return nil end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {MyChar}
    params.FilterType = Enum.RaycastFilterType.Exclude
    local result = workspace:Raycast(MyHRP.Position, Vector3.new(0, -300, 0), params)
    return result and result.Position.Y or nil
end
local function startBodyPos(y)
    if hoverBodyPos then hoverBodyPos:Destroy() end
    hoverBodyPos = Instance.new("BodyPosition")
    hoverBodyPos.MaxForce = Vector3.new(0, 1e6, 0)
    hoverBodyPos.P = 5000
    hoverBodyPos.D = 500
    hoverBodyPos.Position = Vector3.new(MyHRP.Position.X, y, MyHRP.Position.Z)
    hoverBodyPos.Parent = MyHRP
end
local function updateBodyPosY(y)
    if not hoverBodyPos or not hoverBodyPos.Parent then return end
    hoverBodyPos.Position = Vector3.new(MyHRP.Position.X, y, MyHRP.Position.Z)
end
local function ensureBodyVel()
    if hoverBodyVel and hoverBodyVel.Parent then return end
    hoverBodyVel = Instance.new("BodyVelocity")
    hoverBodyVel.Name = "HoverHorizontal"
    hoverBodyVel.MaxForce = Vector3.new(1e6, 0, 1e6)
    hoverBodyVel.P = 2000
    hoverBodyVel.Velocity = Vector3.zero
    hoverBodyVel.Parent = MyHRP
end
local function stopHoverBodies()
    if hoverBodyPos then hoverBodyPos:Destroy(); hoverBodyPos = nil end
    if hoverBodyVel then hoverBodyVel:Destroy(); hoverBodyVel = nil end
end
local function getNearestDangerEnemy()
    if not MyHRP then return math.huge, nil end
    local nearest, nearestDist = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and isEnemy(plr) and not isCrownHolder(plr) and not isPreyRole(plr) then
            local c = plr.Character
            local hrp = c and c:FindFirstChild("HumanoidRootPart")
            local h = c and c:FindFirstChildOfClass("Humanoid")
            if hrp and h and h.Health > 0 then
                local d = (hrp.Position - MyHRP.Position).Magnitude
                if d < nearestDist then
                    nearestDist = d
                    nearest = plr
                end
            end
        end
    end
    return nearestDist, nearest
end

-- [TP]
local STICK_HEIGHT = 3
local function setBtnFree()
    tpCircle.Text = "TP"
    tpCircle.BackgroundColor3 = Color3.fromRGB(100, 80, 240)
    tpCircleStroke.Color = Color3.fromRGB(140, 120, 255)
end
local function setBtnStuck(name)
    tpCircle.Text = "STUCK"
    tpCircle.BackgroundColor3 = Color3.fromRGB(200, 80, 80)
    tpCircleStroke.Color = Color3.fromRGB(220, 100, 100)
end
local function releaseStick()
    if not stickTarget then return end
    stickTarget = nil; setBtnFree()
end
local function applyHitKnockback()
    if not MyHRP then return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local look = camera.CFrame.LookVector
    local back = Vector3.new(-look.X, 0, -look.Z)
    if back.Magnitude < 0.01 then back = Vector3.new(0, 0, 1) end
    back = back.Unit
    local vel = MyHRP.AssemblyLinearVelocity
    MyHRP.AssemblyLinearVelocity = Vector3.new(vel.X + back.X * 65, 80, vel.Z + back.Z * 65)
end
local function teleportRandom()
    if stickTarget or not MyHRP then return end
    local targets = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            local c = plr.Character
            local hrp = c and c:FindFirstChild("HumanoidRootPart")
            local h = c and c:FindFirstChildOfClass("Humanoid")
            if hrp and h and h.Health > 0 and isEnemy(plr) then
                table.insert(targets, plr)
            end
        end
    end
    if #targets == 0 then
        tpCircle.Text = "0 ENEMY"
        task.delay(0.8, function() if not stickTarget then setBtnFree() end end)
        return
    end
    local tPlr = targets[math.random(1, #targets)]
    local tHRP = tPlr.Character and tPlr.Character:FindFirstChild("HumanoidRootPart")
    if not tHRP then return end
    MyHRP.CFrame = tHRP.CFrame * CFrame.new(0, STICK_HEIGHT, 0)
    MyHRP.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    stickTarget = tPlr; setBtnStuck(tPlr.Name)
end
tpCircle.MouseButton1Click:Connect(function()
    if stickTarget then releaseStick() else teleportRandom() end
end)

local touchStartPos, touchStartClock = nil, 0
UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if not stickTarget then return end
    if input.UserInputType == Enum.UserInputType.Touch then
        touchStartPos = Vector2.new(input.Position.X, input.Position.Y)
        touchStartClock = os.clock()
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
        releaseStick(); applyHitKnockback()
    end
end)
UIS.InputEnded:Connect(function(input, gp)
    if not stickTarget then touchStartPos = nil return end
    if input.UserInputType == Enum.UserInputType.Touch and touchStartPos then
        local endPos = Vector2.new(input.Position.X, input.Position.Y)
        if (endPos - touchStartPos).Magnitude < 20 and (os.clock() - touchStartClock) < 0.35 then
            releaseStick(); applyHitKnockback()
        end
        touchStartPos = nil
    end
end)

-- [CHAR]
local function onChar(char)
    MyChar = char
    MyHumanoid = char:WaitForChild("Humanoid")
    MyHRP = char:WaitForChild("HumanoidRootPart")
    hoverIsHovering, hoverIsRising = false, false
    hoverY = nil
    stopHoverBodies()
    applyStats()
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    Connections = {}
    local ok1, c1 = pcall(function()
        return MyHumanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
            if MyHumanoid.WalkSpeed ~= Speed then MyHumanoid.WalkSpeed = Speed end
        end)
    end)
    if ok1 and c1 then table.insert(Connections, c1) end
    local ok2, c2 = pcall(function()
        return MyHumanoid:GetPropertyChangedSignal("JumpPower"):Connect(function()
            if MyHumanoid.JumpPower ~= Jump then MyHumanoid.JumpPower = Jump end
        end)
    end)
    if ok2 and c2 then table.insert(Connections, c2) end
end

if LP.Character then onChar(LP.Character) end
LP.CharacterAdded:Connect(function(char)
    releaseStick()
    stopFly()
    onChar(char)
end)

for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= LP then
        plr.CharacterAdded:Connect(function() clearESP(plr) end)
    end
end
Players.PlayerAdded:Connect(function(plr)
    plr.CharacterAdded:Connect(function() clearESP(plr) end)
end)

RS.Stepped:Connect(function()
    if not Noclip or not LP.Character then return end
    for _, v in pairs(LP.Character:GetDescendants()) do
        if v:IsA("BasePart") and v.CanCollide then v.CanCollide = false end
    end
end)

-- [RENDER LOOP — FOV + Fly]
RS.RenderStepped:Connect(function()
    local cam0 = workspace.CurrentCamera
    if cam0 then
        if cam0.FieldOfView ~= BaseFOV then cam0.FieldOfView = BaseFOV end
        if Stretch ~= 1.0 then
            local cf = cam0.CFrame
            local right = cf.RightVector / Stretch
            local up = cf.UpVector / Stretch
            local look = cf.LookVector
            cam0.CFrame = CFrame.fromMatrix(cf.Position, right, up, -look)
        end
    end

    if not Fly then
        if flyVel then stopFly() end
    else
        if MyHRP and MyHumanoid then
            if not flyVel then startFly() end
            if flyVel and flyGyro then
                local camera = workspace.CurrentCamera
                if camera then
                    local camLook = camera.CFrame.LookVector
                    local camRight = camera.CFrame.RightVector
                    local bodyLook = MyHRP.CFrame.LookVector
                    if camLook:Dot(bodyLook) < 0 then
                        camLook = -camLook; camRight = -camRight
                    end
                    local camRightFlat = Vector3.new(camRight.X, 0, camRight.Z)
                    if camRightFlat.Magnitude < 0.01 then camRightFlat = Vector3.new(1, 0, 0) end
                    camRightFlat = camRightFlat.Unit
                    local move = Vector3.zero
                    if UIS:IsKeyDown(Enum.KeyCode.W) then move = move + camLook end
                    if UIS:IsKeyDown(Enum.KeyCode.S) then move = move - camLook end
                    if UIS:IsKeyDown(Enum.KeyCode.A) then move = move - camRightFlat end
                    if UIS:IsKeyDown(Enum.KeyCode.D) then move = move + camRightFlat end
                    if UIS:IsKeyDown(Enum.KeyCode.Space) then move = move + Vector3.new(0, 1, 0) end
                    if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then move = move - Vector3.new(0, 1, 0) end
                    local md = MyHumanoid.MoveDirection
                    if md.Magnitude > 0.05 then
                        local camFlat = Vector3.new(camLook.X, 0, camLook.Z)
                        if camFlat.Magnitude < 0.01 then camFlat = Vector3.new(0, 0, -1) end
                        camFlat = camFlat.Unit
                        move = move + camLook * md:Dot(camFlat) + camRightFlat * md:Dot(camRightFlat)
                    end
                    if MyHumanoid.Jump then move = move + Vector3.new(0, 1, 0) end
                    if move.Magnitude > 0 then
                        flyVel.Velocity = move.Unit * 60
                    else
                        flyVel.Velocity = Vector3.zero
                    end
                    flyGyro.CFrame = camera.CFrame
                end
            end
        end
    end
end)

-- [HOVER LOOP]
RS.Heartbeat:Connect(function()
    if not Hover or not MyChar or not MyHRP or not MyHumanoid then return end
    if MyHumanoid.Health <= 0 then return end
    local nearestDist = getNearestDangerEnemy()
    local now = os.clock()
    if not hoverIsHovering and nearestDist <= DETECT_RANGE and now - hoverLastDodge >= HOVER_COOLDOWN then
        hoverLastDodge = now
        local groundY = findGroundY() or MyHRP.Position.Y
        local targetY = groundY + HOVER_HEIGHT_FROM_GROUND
        local currentY = MyHRP.Position.Y
        if currentY >= targetY - 2 then
            hoverY = currentY
            hoverIsHovering = true
            hoverIsRising = false
            startBodyPos(hoverY); ensureBodyVel()
        else
            hoverIsHovering = true
            hoverIsRising = true
            hoverRiseStartTime = now
            hoverRiseStartY = currentY
            hoverRiseTargetY = targetY
            startBodyPos(currentY); ensureBodyVel()
        end
    end
    if hoverIsRising then
        local t = math.min((now - hoverRiseStartTime) / RISE_TIME, 1)
        hoverY = hoverRiseStartY + (hoverRiseTargetY - hoverRiseStartY) * t
        updateBodyPosY(hoverY)
        if t >= 1 then hoverIsRising = false; hoverY = hoverRiseTargetY end
    end
    if hoverIsHovering and not hoverIsRising then
        if nearestDist <= LOSE_RANGE then
            updateBodyPosY(hoverY); ensureBodyVel()
            local cam = workspace.CurrentCamera
            local moveDir = Vector3.zero
            local md = MyHumanoid.MoveDirection
            if md.Magnitude > 0.05 then moveDir = moveDir + md.Unit end
            if cam then
                local camLook = cam.CFrame.LookVector
                local camRight = cam.CFrame.RightVector
                local bodyLook = MyHRP.CFrame.LookVector
                if camLook:Dot(bodyLook) < 0 then camLook = -camLook; camRight = -camRight end
                local flatLook = Vector3.new(camLook.X, 0, camLook.Z)
                local flatRight = Vector3.new(camRight.X, 0, camRight.Z)
                if flatLook.Magnitude > 0.01 then flatLook = flatLook.Unit end
                if flatRight.Magnitude > 0.01 then flatRight = flatRight.Unit end
                local kbMove = Vector3.zero
                if UIS:IsKeyDown(Enum.KeyCode.W) then kbMove = kbMove + flatLook end
                if UIS:IsKeyDown(Enum.KeyCode.S) then kbMove = kbMove - flatLook end
                if UIS:IsKeyDown(Enum.KeyCode.A) then kbMove = kbMove - flatRight end
                if UIS:IsKeyDown(Enum.KeyCode.D) then kbMove = kbMove + flatRight end
                if kbMove.Magnitude > 0.05 then moveDir = moveDir + kbMove.Unit end
            end
            if moveDir.Magnitude > 0.05 then
                hoverBodyVel.Velocity = moveDir.Unit * AIR_MOVE_SPEED
            else
                hoverBodyVel.Velocity = Vector3.zero
            end
            local v = MyHRP.AssemblyLinearVelocity
            if math.abs(v.Y) > Y_VELOCITY_KILL_THRESHOLD then
                MyHRP.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
            end
        else
            hoverIsHovering = false
            hoverIsRising = false
            hoverY = nil
            stopHoverBodies()
        end
    end
end)

-- [MAIN LOOP — Stick + Tracers + ESP + Hitbox]
local hasLine = pcall(function() return Drawing.new("Line") end)
local function newLine()
    if not hasLine then return nil end
    local ok, l = pcall(function() return Drawing.new("Line") end)
    if ok and l then
        l.Color = Color3.fromRGB(120, 200, 255); l.Thickness = 2
        l.Transparency = 0.4; l.Visible = false; return l
    end
    return nil
end
Players.PlayerRemoving:Connect(function(plr)
    if stickTarget == plr then releaseStick() end
    clearESP(plr)
    local line = tracerLines[plr]
    if line then pcall(function() line:Remove() end); tracerLines[plr] = nil end
end)

RS.RenderStepped:Connect(function()
    if stickTarget then
        local tChar = stickTarget.Character
        local tHRP = tChar and tChar:FindFirstChild("HumanoidRootPart")
        local tHum = tChar and tChar:FindFirstChildOfClass("Humanoid")
        if not (MyHRP and tHRP and tHum and tHum.Health > 0) or isDead(stickTarget) then
            releaseStick()
        else
            MyHRP.CFrame = tHRP.CFrame * CFrame.new(0, STICK_HEIGHT, 0)
            MyHRP.AssemblyLinearVelocity = Vector3.zero
        end
    end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local vp = camera.ViewportSize
    if hasLine then
        local fromPos = Vector2.new(vp.X / 2, vp.Y)
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP then
                local line = tracerLines[plr]
                if not line then line = newLine(); if line then tracerLines[plr] = line end end
                if line then
                    if Tracers and not isDead(plr) then
                        local c = plr.Character
                        local hrp = c and c:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            local pos, onScreen = camera:WorldToViewportPoint(hrp.Position + Vector3.new(0, 1.5, 0))
                            if onScreen then
                                line.From = fromPos; line.To = Vector2.new(pos.X, pos.Y); line.Visible = true
                            else line.Visible = false end
                        else line.Visible = false end
                    else line.Visible = false end
                end
            end
        end
    end
    if ESP then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and not isDead(plr) then
                if not espData[plr] then pcall(buildESP, plr) else pcall(updateESP, plr) end
            elseif espData[plr] then pcall(clearESP, plr) end
        end
    elseif next(espData) then
        clearAllESP()
    end
    if Hitbox then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and isEnemy(plr) then
                local char = plr.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local color = computeColor(plr)
                    hrp.Size = Vector3.new(HITBOX_SIZE, HITBOX_SIZE, HITBOX_SIZE)
                    hrp.Transparency = 0.55
                    hrp.Material = Enum.Material.Neon
                    hrp.Color = color
                    hrp.CanCollide = false
                end
            else
                if plr ~= LP and plr.Character then
                    local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
                    if hrp and (hrp.Size ~= Vector3.new(2, 2, 1) or hrp.Material == Enum.Material.Neon) then
                        hrp.Size = Vector3.new(2, 2, 1)
                        hrp.Transparency = 1
                        hrp.Material = Enum.Material.Plastic
                        hrp.CanCollide = true
                    end
                end
            end
        end
    end
end)
