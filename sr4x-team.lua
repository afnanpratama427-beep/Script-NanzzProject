--[[
    ███████╗██████╗ ██╗  ██╗    ████████╗███████╗ █████╗ ███╗   ████╗
    ██╔════╝██╔══██╗╚██╗██╔╝    ╚══██╔══╝██╔════╝██╔══██╗████╗ ████║
    ███████╗██████╔╝ ╚███╔╝        ██║   █████╗  ███████║██╔████╔██║
    ╚════██║██╔══██╗ ██╔██╗        ██║   ██╔══╝  ██╔══██║██║╚██╔╝██║
    ███████║██║  ██║██╔╝ ██╗       ██║   ███████╗██║  ██║██║ ╚═╝ ██║
    ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝       ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝

    SR4X TEAM — v21.1 — ESP LINE + SKULL + OUTLINE FIX
    Changes from v21:
      * FIXED: ESP line crash — math.atan2 -> math.atan(y, x) (Luau has no atan2)
      * FIXED: ESP line positioning — anchor(0.5,0.5) + midpoint, correct rotation pivot
      * RESTORED: ESP skull marker (☠) with dedicated toggle
      * ADDED: ESP Outline (stroke) with color modes: Solid / RGB / 3D RGB / Gradient
      * ADDED: ESP Outline Thickness slider
      * ADDED: Wall check on Aim Magnet (Manual + Pro) — silent aim unaffected
      * ADDED: Wall check on Ninja Fire target selection
      * Everything else identical to v21
]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local Tween      = game:GetService("TweenService")
local PhysicsService = game:GetService("PhysicsService")
local TeleportSvc = game:GetService("TeleportService")
local LP         = Players.LocalPlayer

print("[SR4X] v21.1 booting...")

local Camera = workspace.CurrentCamera
if not Camera then
    for _ = 1, 20 do
        task.wait(0.1)
        Camera = workspace.CurrentCamera
        if Camera then break end
    end
end
if Camera then
    pcall(function()
        workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
            if workspace.CurrentCamera then Camera = workspace.CurrentCamera end
        end)
    end)
end

local HITBOX_GROUP = "SR4X_Hitbox"
local PLAYER_GROUP = "SR4X_Player"
pcall(function() PhysicsService:RegisterCollisionGroup(HITBOX_GROUP) end)
pcall(function() PhysicsService:RegisterCollisionGroup(PLAYER_GROUP) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable(HITBOX_GROUP, "Default", false) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable(HITBOX_GROUP, HITBOX_GROUP, false) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable(PLAYER_GROUP, HITBOX_GROUP, false) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable(PLAYER_GROUP, PLAYER_GROUP, false) end)

-- ============================================================
-- CONFIG
-- ============================================================
local Config = {
    FreezeEnabled = false, FreezeActive = false,
    Aimbot = false, AimbotFOV = 180, AimbotSmooth = 0.25, AimbotPart = "Head",
    POV_X = 0, POV_Y = 0,
    TargetPlayers = true, TargetNPCs = false, TeamCheck = true, ShowFOV = true, WallCheck = true,
    ESP_Enabled = false, ESP_Box = true, ESP_Line = true, ESP_Name = true,
    ESP_Color = Color3.fromRGB(255, 50, 50),

    -- NEW: Skull marker + Outline
    ESP_Skull = true,
    ESP_Outline = true,
    ESP_Outline_Mode = "RGB",         -- Solid / RGB / 3D RGB / Gradient
    ESP_Outline_Thickness = 1.5,

    Theme = "Gradient", AccentA = Color3.fromRGB(0, 200, 255), AccentB = Color3.fromRGB(180, 0, 255),
    BoxColor = Color3.fromRGB(30, 30, 45), BoxTransp = 0.35, OrbSize = 64, OrbThick = 60,
    FreezeOrbSize = 64, FreezeOrbThick = 60,
    FreezeInactiveColor = Color3.fromRGB(10, 10, 10),
    FreezeInactiveRGB = false,
    AutoMagnet = false,
    AimMagnetManual = false,
    AimMagnetPro = false,
    MagnetTarget = "Head",
    AutoShoot = false,
    AutoShootTarget = "Head",
    AutoShootSpeed = 0.15,
    FastReload = false,
    AntiKick = true,
    NoReload = true,
    NoclipEnabled = false,
    NoclipAuto = true,
    NoclipActive = false,
    AntiFlingEnabled = true,

    SilentAim = false,
    SilentAimHeadSize = 25,
    SilentAimRange = 500,
    SilentAimTeam = true,
    SilentAimNPCs = false,

    NinjaFire = false,
    NinjaFireDist = 4,
    NinjaFireReturnDelay = 0.05,
    NinjaFireMaxRange = 500,

    AntiBanEnabled = true,
}

-- ============================================================
-- WALL CHECK HELPER
-- ============================================================
local function isVisible(targetModel, targetPosition)
    if not Config.WallCheck or not Camera then return true end
    local origin = Camera.CFrame.Position
    local direction = targetPosition - origin
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignoreList = {}
    if LP.Character then table.insert(ignoreList, LP.Character) end
    if Camera then table.insert(ignoreList, Camera) end
    params.FilterDescendantsInstances = ignoreList
    local result = workspace:Raycast(origin, direction, params)
    if result then
        return result.Instance:IsDescendantOf(targetModel)
    end
    return true
end

-- ============================================================
-- SHARED STATE
-- ============================================================
local _targetsDirty  = true
local _cachedTargets = {}
local _lastTargetUpdate = 0
local npcCache, lastScan = {}, 0

local function invalidateTargets() _targetsDirty = true end
Players.PlayerAdded:Connect(invalidateTargets)
Players.PlayerRemoving:Connect(invalidateTargets)

local function refreshNPCs()
    if os.clock() - lastScan < 0.5 then return end
    lastScan = os.clock()
    npcCache = {}
    for _, m in ipairs(workspace:GetDescendants()) do
        if m:IsA("Model") and m:FindFirstChild("HumanoidRootPart") then
            local hum = m:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 and not Players:GetPlayerFromCharacter(m) then
                npcCache[#npcCache+1] = m
            end
        end
    end
end

local function collectTargets()
    local out = {}
    local myTeam = LP.Team
    if Config.TargetPlayers then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and p.Character then
                local hum = p.Character:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 and not (Config.TeamCheck and myTeam and p.Team == myTeam) then
                    out[#out+1] = p.Character
                end
            end
        end
    end
    if Config.TargetNPCs then
        refreshNPCs()
        for _, m in ipairs(npcCache) do if m.Parent then out[#out+1] = m end end
    end
    return out
end

local function getCachedTargets()
    local now = os.clock()
    if _targetsDirty or now - _lastTargetUpdate > 0.5 then
        _cachedTargets = collectTargets()
        _lastTargetUpdate = now
        _targetsDirty = false
    end
    return _cachedTargets
end

local function getCharTeam(model)
    local plr = Players:GetPlayerFromCharacter(model)
    return plr and plr.Team or nil
end

-- ============================================================
-- BIG HEAD — ADDITIVE METHOD
-- ============================================================
local frozenData = {}

local function collectBigHeadTargets()
    local out = {}
    local myTeam = LP.Team
    local range = Config.SilentAimRange or 500
    local camPos = Camera and Camera.CFrame.Position or Vector3.zero

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character and not frozenData[p.Character] then
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hum and hum.Health > 0 and hrp then
                local teamOk = not (Config.SilentAimTeam and myTeam and p.Team == myTeam)
                local rangeOk = (camPos - hrp.Position).Magnitude <= range
                if teamOk and rangeOk then
                    out[#out+1] = p.Character
                end
            end
        end
    end

    if Config.SilentAimNPCs then
        refreshNPCs()
        for _, m in ipairs(npcCache) do
            if m.Parent and not frozenData[m] then
                local hrp = m:FindFirstChild("HumanoidRootPart")
                if hrp and (camPos - hrp.Position).Magnitude <= range then
                    out[#out+1] = m
                end
            end
        end
    end
    return out
end

local bigHeadState = {}

local function applyBigHead(model)
    if not model or not model.Parent then return end
    if bigHeadState[model] then return end
    local head = model:FindFirstChild("Head")
    if not head or not head:IsA("BasePart") then return end

    bigHeadState[model] = {
        head = head,
        origSize = head.Size,
        origTrans = head.Transparency,
        origCanQuery = head.CanQuery,
        origCastShadow = head.CastShadow,
        origCanCollide = head.CanCollide,
        origMassless = head.Massless,
    }

    local s = Config.SilentAimHeadSize
    local offset = Vector3.new(s, s, s)
    pcall(function()
        head.Size = head.Size + offset
        head.Transparency = 0
        head.CanQuery = true
        head.CastShadow = false
        head.CanCollide = false
        head.Massless = true
    end)
end

local function clearBigHead(model)
    local d = bigHeadState[model]
    if not d then return end
    if d.head and d.head.Parent then
        pcall(function()
            d.head.Size = d.origSize
            d.head.Transparency = d.origTrans
            d.head.CanQuery = d.origCanQuery
            d.head.CastShadow = d.origCastShadow
            d.head.CanCollide = d.origCanCollide
            d.head.Massless = d.origMassless
        end)
    end
    bigHeadState[model] = nil
end

local function clearAllBigHeads()
    local keys = {}
    for m in pairs(bigHeadState) do table.insert(keys, m) end
    for _, m in ipairs(keys) do clearBigHead(m) end
end

task.spawn(function()
    while task.wait(0.1) do
        local ok, err = pcall(function()
            if Config.SilentAim then
                local targets = collectBigHeadTargets()
                local targetSet = {}
                for _, m in ipairs(targets) do targetSet[m] = true end

                for _, model in ipairs(targets) do
                    local st = bigHeadState[model]
                    if st and st.head ~= model:FindFirstChild("Head") then
                        clearBigHead(model)
                    end
                    if not bigHeadState[model] then applyBigHead(model) end
                end

                local keys = {}
                for m in pairs(bigHeadState) do table.insert(keys, m) end
                for _, m in ipairs(keys) do
                    if not targetSet[m] or not m.Parent then clearBigHead(m) end
                end
            else
                if next(bigHeadState) ~= nil then clearAllBigHeads() end
            end
        end)
        if not ok then warn("[SR4X] bigHead apply err: " .. tostring(err)) end
    end
end)

RunService.Heartbeat:Connect(function()
    if not Config.SilentAim then return end
    local s = Config.SilentAimHeadSize
    local offset = Vector3.new(s, s, s)
    for _, st in pairs(bigHeadState) do
        local h = st.head
        if h and h.Parent then
            local targetSize = st.origSize + offset
            if h.Size ~= targetSize then
                pcall(function() h.Size = targetSize end)
            end
            if h.Transparency ~= 0 then
                pcall(function() h.Transparency = 0 end)
            end
            if h.CanQuery ~= true then
                pcall(function() h.CanQuery = true end)
            end
            if h.CanCollide ~= false then
                pcall(function() h.CanCollide = false end)
            end
        end
    end
end)

-- ============================================================
-- NINJA FIRE
-- ============================================================
local function findNearestNinjaTarget()
    if not Camera then return nil end
    local vs = Camera.ViewportSize
    if not vs or vs.X <= 0 then return nil end
    local center = Vector2.new(vs.X/2, vs.Y/2)
    local myTeam = LP.Team
    local best, bestDist = nil, Config.NinjaFireMaxRange or 500
    for _, model in ipairs(getCachedTargets()) do
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if hrp then
            local team = getCharTeam(model)
            if not (Config.SilentAimTeam and myTeam and team == myTeam) then
                if isVisible(model, hrp.Position) then
                    local ok, sp = pcall(function() return Camera:WorldToViewportPoint(hrp.Position) end)
                    if ok and sp and sp.Z > 0 then
                        local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                        local worldD = (Camera.CFrame.Position - hrp.Position).Magnitude
                        if d < 400 and worldD < bestDist then
                            best = model
                            bestDist = worldD
                        end
                    end
                end
            end
        end
    end
    return best
end

local function getWeaponTool()
    local char = LP.Character
    if char then return char:FindFirstChildOfClass("Tool") end
    return nil
end

local function ninjaFire()
    local char = LP.Character
    local myHRP = char and char:FindFirstChild("HumanoidRootPart")
    if not myHRP then return end
    local targetModel = findNearestNinjaTarget()
    if not targetModel then return end
    local targetHRP = targetModel:FindFirstChild("HumanoidRootPart")
    if not targetHRP then return end

    local origCF = myHRP.CFrame
    local behindCF = targetHRP.CFrame * CFrame.new(0, 0, Config.NinjaFireDist)

    pcall(function() myHRP.CFrame = behindCF end)
    task.wait(Config.NinjaFireReturnDelay)
    local tool = getWeaponTool()
    if tool then pcall(function() tool:Activate() end) end
    task.wait(Config.NinjaFireReturnDelay)
    pcall(function() myHRP.CFrame = origCF end)
end

-- ============================================================
-- ANTI-BAN
-- ============================================================
do
    local installed = false
    pcall(function()
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if Config.AntiBanEnabled then
                if method == "Kick" or method == "kick" then
                    warn("[SR4X] Blocked Kick")
                    return nil
                end
                if (method == "Disconnect" or method == "disconnect") and (self == game or self == LP) then
                    warn("[SR4X] Blocked Disconnect")
                    return nil
                end
                if self == TeleportSvc and (method == "Teleport" or method == "TeleportAsync" or method == "TeleportToPlaceInstance") then
                    local placeId = select(1, ...)
                    if typeof(placeId) == "number" and placeId ~= game.PlaceId then
                        warn("[SR4X] Blocked cross-place Teleport")
                        return nil
                    end
                end
            end
            return oldNamecall(self, ...)
        end)
        installed = true
    end)
    if installed then
        print("[SR4X] Anti-Ban installed successfully.")
    else
        warn("[SR4X] Anti-Ban FAILED — executor does not support hookmetamethod.")
    end
end

-- ============================================================
-- NOCLIP + ANTI-FLING
-- ============================================================
local ourPartsCache = {}
local function rebuildOurParts()
    ourPartsCache = {}
    local char = LP.Character
    if not char then return end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then table.insert(ourPartsCache, p) end
    end
end
rebuildOurParts()
LP.CharacterAdded:Connect(function() task.wait(0.15); rebuildOurParts() end)

task.spawn(function()
    while task.wait(0.15) do
        local active = Config.NoclipEnabled or (Config.NoclipAuto and Config.SilentAim)
        Config.NoclipActive = active
    end
end)

local lastFallAssistTime = 0
RunService.Heartbeat:Connect(function()
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local now = os.clock()

    if Config.NoclipActive then
        for _, p in ipairs(ourPartsCache) do
            if p.Parent and p.CollisionGroup ~= PLAYER_GROUP then
                pcall(function() p.CollisionGroup = PLAYER_GROUP end)
            end
        end
        if hum and hrp and now - lastFallAssistTime > 0.3 then
            local state = hum:GetState()
            local vel = hrp.AssemblyLinearVelocity
            if (state == Enum.HumanoidStateType.Running or state == Enum.HumanoidStateType.Landed) and vel.Magnitude < 8 then
                local params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances = {char}
                local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -4, 0), params)
                if hit and hit.Instance.CollisionGroup == HITBOX_GROUP then
                    lastFallAssistTime = now
                    pcall(function()
                        hum:ChangeState(Enum.HumanoidStateType.Freefall)
                        hrp.AssemblyLinearVelocity = Vector3.new(vel.X, -30, vel.Z)
                    end)
                end
            end
        end
    elseif hrp and Config.AntiFlingEnabled then
        local vel = hrp.AssemblyLinearVelocity
        if vel.Magnitude > 600 then
            pcall(function()
                hrp.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0)
                hrp.AssemblyAngularVelocity = Vector3.zero
            end)
        end
    end
end)

-- ============================================================
-- GUI PARENT
-- ============================================================
local function getGuiParent()
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then
            local test = Instance.new("ScreenGui")
            test.Enabled = true
            local okP = pcall(function() test.Parent = hui end)
            if okP and test.Parent then
                pcall(function() test:Destroy() end)
                return hui
            end
            pcall(function() test:Destroy() end)
        end
    end
    local pg = LP:FindFirstChild("PlayerGui")
    if pg then return pg end
    local pg2 = LP:WaitForChild("PlayerGui", 2)
    if pg2 then return pg2 end
    local ok3, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok3 and cg then return cg end
    return nil
end

local guiParent = getGuiParent()
if not guiParent then
    warn("[SR4X] FATAL: no GUI parent found.")
end

local ESP_Colors = {{name="Red", color=Color3.fromRGB(255, 50, 50)},{name="Green", color=Color3.fromRGB(50, 255, 50)},{name="Blue", color=Color3.fromRGB(50, 150, 255)},{name="Yellow", color=Color3.fromRGB(255, 255, 50)},{name="White", color=Color3.fromRGB(255, 255, 255)}}
local ThemePresets = {
    { name="Aqua-Violet", box=Color3.fromRGB(30,30,45),  a=Color3.fromRGB(0,200,255),   b=Color3.fromRGB(180,0,255) },
    { name="Red-Orange",  box=Color3.fromRGB(45,20,20),  a=Color3.fromRGB(255,60,60),   b=Color3.fromRGB(255,160,0) },
    { name="Green-Cyan",  box=Color3.fromRGB(20,40,30),  a=Color3.fromRGB(60,255,120),  b=Color3.fromRGB(0,200,255) },
    { name="Pink-Yellow", box=Color3.fromRGB(40,20,35),  a=Color3.fromRGB(255,80,180),  b=Color3.fromRGB(255,240,80) },
    { name="Pure White",  box=Color3.fromRGB(25,25,25),  a=Color3.fromRGB(255,255,255), b=Color3.fromRGB(200,200,255) },
}
local FreezeInactiveColors = {{name="Hitam", color=Color3.fromRGB(10, 10, 10)},{name="Putih", color=Color3.fromRGB(240, 240, 240)},{name="Merah", color=Color3.fromRGB(200, 40, 40)},{name="Biru", color=Color3.fromRGB(30, 90, 255)},{name="RGB", color=Color3.fromRGB(255, 255, 255)}}

local BASE_DO = 1000000000

-- ============================================================
-- ESP GUI
-- ============================================================
local espGui = Instance.new("ScreenGui")
espGui.Name = "SR4X_ESP"
espGui.ResetOnSpawn = false
espGui.IgnoreGuiInset = true
espGui.Enabled = true
espGui.DisplayOrder = BASE_DO + 0
espGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
if guiParent then espGui.Parent = guiParent end

local espObjects = {}

local function getESPObject(plr)
    if espObjects[plr] then return espObjects[plr] end
    local box = Instance.new("Frame")
    box.AnchorPoint = Vector2.new(0.5, 0.5)
    box.BackgroundTransparency = 1
    box.BorderSizePixel = 0
    box.Visible = false
    box.ZIndex = 1
    box.Parent = espGui
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1
    stroke.Color = Color3.fromRGB(255, 50, 50)
    stroke.Parent = box
    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new(Color3.fromRGB(255, 50, 50))
    grad.Parent = stroke

    local line = Instance.new("Frame")
    line.AnchorPoint = Vector2.new(0.5, 0.5)
    line.BorderSizePixel = 0
    line.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    line.BackgroundTransparency = 0
    line.Visible = false
    line.ZIndex = 1
    line.Parent = espGui

    local nameLbl = Instance.new("TextLabel")
    nameLbl.AnchorPoint = Vector2.new(0.5, 1)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Font = Enum.Font.Code
    nameLbl.TextSize = 14
    nameLbl.TextColor3 = Color3.fromRGB(255, 50, 50)
    nameLbl.TextStrokeTransparency = 0
    nameLbl.Visible = false
    nameLbl.ZIndex = 2
    nameLbl.Parent = espGui

    local skull = Instance.new("TextLabel")
    skull.AnchorPoint = Vector2.new(0.5, 0.5)
    skull.BackgroundTransparency = 1
    skull.Font = Enum.Font.SourceSansBold
    skull.TextSize = 24
    skull.Text = "☠"
    skull.TextColor3 = Color3.fromRGB(255, 50, 50)
    skull.TextStrokeTransparency = 0.25
    skull.Size = UDim2.fromOffset(26, 26)
    skull.Visible = false
    skull.ZIndex = 3
    skull.Parent = espGui

    espObjects[plr] = { box = box, stroke = stroke, grad = grad, line = line, name = nameLbl, skull = skull }
    return espObjects[plr]
end

local function hideESPObject(plr)
    local o = espObjects[plr]
    if not o then return end
    if o.box then o.box.Visible = false end
    if o.line then o.line.Visible = false end
    if o.name then o.name.Visible = false end
    if o.skull then o.skull.Visible = false end
end

local function updateESP()
    if not Camera then return end
    if not Config.ESP_Enabled then
        for plr in pairs(espObjects) do hideESPObject(plr) end
        return
    end
    local vs = Camera.ViewportSize
    if not vs or vs.X <= 0 then return end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character then
            local head = plr.Character:FindFirstChild("Head")
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")
            if head and hrp and hum and hum.Health > 0 then
                if Config.TeamCheck and LP.Team and plr.Team == LP.Team then
                    hideESPObject(plr)
                else
                    local headPos, headOnScreen = Camera:WorldToViewportPoint(head.Position)
                    local hrpPos, hrpOnScreen = Camera:WorldToViewportPoint(hrp.Position)
                    if headOnScreen and hrpOnScreen and headPos.Z > 0 and hrpPos.Z > 0 then
                        local o = getESPObject(plr)
                        local height = math.abs(headPos.Y - hrpPos.Y) * 2.2
                        local width = math.max(height / 2, 8)
                        local cx = hrpPos.X
                        local cy = (headPos.Y + hrpPos.Y) / 2
                        local dist = (Camera.CFrame.Position - hrp.Position).Magnitude

                        if Config.ESP_Box then
                            o.box.Visible = true
                            o.box.Size = UDim2.fromOffset(width, height)
                            o.box.Position = UDim2.fromOffset(cx, cy)
                        else
                            o.box.Visible = false
                        end

                        if Config.ESP_Outline and Config.ESP_Box then
                            o.stroke.Thickness = Config.ESP_Outline_Thickness
                            o.stroke.Transparency = 0
                            local mode = Config.ESP_Outline_Mode
                            if mode == "Solid" then
                                o.stroke.Color = Config.ESP_Color
                                o.grad.Color = ColorSequence.new(Config.ESP_Color)
                            elseif mode == "RGB" then
                                local c = Color3.fromHSV((tick() * 0.6) % 1, 1, 1)
                                o.stroke.Color = c
                                o.grad.Color = ColorSequence.new(c)
                            elseif mode == "3D RGB" then
                                local t = (tick() * 0.4) % 1
                                local c1 = Color3.fromHSV(t, 1, 1)
                                local c2 = Color3.fromHSV((t + 0.33) % 1, 1, 1)
                                local c3 = Color3.fromHSV((t + 0.66) % 1, 1, 1)
                                o.stroke.Color = c1
                                o.grad.Color = ColorSequence.new{
                                    ColorSequenceKeypoint.new(0, c1),
                                    ColorSequenceKeypoint.new(0.5, c2),
                                    ColorSequenceKeypoint.new(1, c3),
                                }
                            elseif mode == "Gradient" then
                                o.stroke.Color = Config.AccentA
                                o.grad.Color = ColorSequence.new(Config.AccentA, Config.AccentB)
                            end
                        else
                            o.stroke.Thickness = 0
                            o.stroke.Transparency = 1
                        end

                        if Config.ESP_Name then
                            o.name.Visible = true
                            o.name.Text = string.format("%s [%d]", plr.Name, math.floor(dist))
                            o.name.TextColor3 = Config.ESP_Color
                            o.name.Size = UDim2.fromOffset(math.max(width * 4, 120), 18)
                            local nameY = headPos.Y - 6
                            if Config.ESP_Skull then nameY = headPos.Y - 32 end
                            o.name.Position = UDim2.fromOffset(cx, nameY)
                        else
                            o.name.Visible = false
                        end

                        if Config.ESP_Skull then
                            o.skull.Visible = true
                            o.skull.Position = UDim2.fromOffset(cx, headPos.Y - 8)
                            o.skull.TextColor3 = Config.ESP_Color
                        else
                            o.skull.Visible = false
                        end

                        if Config.ESP_Line then
                            local fromX = vs.X / 2
                            local fromY = vs.Y
                            local toX = hrpPos.X
                            local toY = hrpPos.Y
                            local dx = toX - fromX
                            local dy = toY - fromY
                            local length = math.sqrt(dx*dx + dy*dy)
                            if length >= 1 then
                                o.line.Visible = true
                                local angle = math.deg(math.atan(dy, dx))
                                o.line.Size = UDim2.fromOffset(length, 1)
                                o.line.Position = UDim2.fromOffset((fromX + toX) / 2, (fromY + toY) / 2)
                                o.line.Rotation = angle
                                o.line.BackgroundColor3 = Config.ESP_Color
                            else
                                o.line.Visible = false
                            end
                        else
                            o.line.Visible = false
                        end
                    else
                        hideESPObject(plr)
                    end
                end
            else
                hideESPObject(plr)
            end
        else
            hideESPObject(plr)
        end
    end
end

Players.PlayerRemoving:Connect(function(plr)
    local o = espObjects[plr]
    if o then
        if o.box then o.box:Destroy() end
        if o.line then o.line:Destroy() end
        if o.name then o.name:Destroy() end
        if o.skull then o.skull:Destroy() end
        espObjects[plr] = nil
    end
end)

RunService.RenderStepped:Connect(function() pcall(updateESP) end)

-- ============================================================
-- MAIN GUI
-- ============================================================
local gui = Instance.new("ScreenGui")
gui.Name = "SR4X_MainUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = true
gui.DisplayOrder = BASE_DO + 1
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() gui.OnTopOfCoreBlur = true end)
pcall(function() gui.ClipToDeviceSafeArea = false end)
if guiParent then gui.Parent = guiParent end
print("[SR4X] Main GUI parented to: " .. (gui.Parent and gui.Parent:GetFullName() or "NIL"))

local themeEls = { boxes = {}, strokes = {}, accents = {} }
local toggleRegistry = {}
local function applyTheme()
    for _, b in ipairs(themeEls.boxes) do if b and b.Parent then b.BackgroundColor3 = Config.BoxColor b.BackgroundTransparency = Config.BoxTransp end end
    for _, t in ipairs(toggleRegistry) do if t.btn and t.btn.Parent then if t.getActive() then t.btn.BackgroundColor3 = t.activeColor t.btn.BackgroundTransparency = 0.5 t.btn.TextColor3 = Color3.fromRGB(255,255,255) else t.btn.BackgroundColor3 = Config.BoxColor t.btn.BackgroundTransparency = Config.BoxTransp t.btn.TextColor3 = Color3.fromRGB(220,220,220) end end end
    for _, s in ipairs(themeEls.strokes) do if s and s.Parent then s.Color = Config.AccentA end end
    for _, a in ipairs(themeEls.accents) do if a and a.Parent then a.TextColor3 = Config.AccentA end end
end

local chGui = Instance.new("ScreenGui")
chGui.Name = "SR4X_Crosshair"
chGui.ResetOnSpawn = false
chGui.IgnoreGuiInset = true
chGui.Enabled = true
chGui.DisplayOrder = BASE_DO + 2
pcall(function() chGui.OnTopOfCoreBlur = true end)
pcall(function() chGui.ClipToDeviceSafeArea = false end)
if guiParent then chGui.Parent = guiParent end

local crosshairRing = Instance.new("Frame") crosshairRing.Size = UDim2.fromOffset(20, 20) crosshairRing.AnchorPoint = Vector2.new(0.5, 0.5) crosshairRing.Position = UDim2.fromScale(0.5, 0.5) crosshairRing.BackgroundTransparency = 1 crosshairRing.Visible = false crosshairRing.Parent = chGui Instance.new("UICorner", crosshairRing).CornerRadius = UDim.new(1, 0)
local chStroke = Instance.new("UIStroke") chStroke.Thickness = 3.5 chStroke.Color = Color3.fromRGB(255, 50, 50) chStroke.Parent = crosshairRing
local crosshairDot = Instance.new("Frame") crosshairDot.Size = UDim2.fromOffset(5, 5) crosshairDot.AnchorPoint = Vector2.new(0.5, 0.5) crosshairDot.Position = UDim2.fromScale(0.5, 0.5) crosshairDot.BackgroundColor3 = Color3.fromRGB(255, 50, 50) crosshairDot.BorderSizePixel = 0 crosshairDot.Visible = false crosshairDot.Parent = chGui Instance.new("UICorner", crosshairDot).CornerRadius = UDim.new(1, 0)
local fovFrame = Instance.new("Frame") fovFrame.AnchorPoint = Vector2.new(0.5, 0.5) fovFrame.Position = UDim2.fromScale(0.5, 0.5) fovFrame.BackgroundTransparency = 1 fovFrame.BorderSizePixel = 0 fovFrame.Visible = false fovFrame.ZIndex = 1 fovFrame.Parent = gui Instance.new("UICorner", fovFrame).CornerRadius = UDim.new(1, 0)
local fovStroke = Instance.new("UIStroke") fovStroke.Thickness = 1.5 fovStroke.Transparency = 0.5 fovStroke.Parent = fovFrame table.insert(themeEls.strokes, fovStroke)

local btn = Instance.new("TextButton") btn.Size = UDim2.fromOffset(Config.OrbSize, Config.OrbSize) btn.Position = UDim2.new(0, 24, 0.5, -Config.OrbSize/2) btn.BackgroundColor3 = Color3.fromRGB(18,18,22) btn.Text = "◎" btn.TextColor3 = Color3.fromRGB(255,255,255) btn.Font = Enum.Font.SourceSansBold btn.TextSize = 24 btn.AutoButtonColor = false btn.BorderSizePixel = 0 btn.Active = true btn.ZIndex = 5 btn.Parent = gui Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0) local btnStroke = Instance.new("UIStroke") btnStroke.Parent = btn local btnGrad = Instance.new("UIGradient") btnGrad.Parent = btnStroke table.insert(themeEls.strokes, btnStroke)

local freezeBtn = Instance.new("TextButton")
freezeBtn.Size = UDim2.fromOffset(Config.FreezeOrbSize, Config.FreezeOrbSize)
freezeBtn.Position = UDim2.new(0, 24, 0.5, 40)
freezeBtn.BackgroundColor3 = Config.FreezeInactiveColor
freezeBtn.Text = "❄"
freezeBtn.TextColor3 = Color3.fromRGB(255,255,255)
freezeBtn.Font = Enum.Font.SourceSansBold
freezeBtn.TextSize = math.clamp(Config.FreezeOrbSize * 0.42, 12, 60)
freezeBtn.AutoButtonColor = false
freezeBtn.BorderSizePixel = 0
freezeBtn.Active = true
freezeBtn.Visible = false
freezeBtn.ZIndex = 5
freezeBtn.Parent = gui
Instance.new("UICorner", freezeBtn).CornerRadius = UDim.new(1, 0)
local freezeStroke = Instance.new("UIStroke") freezeStroke.Thickness = 2 freezeStroke.Color = Color3.fromRGB(255,255,255) freezeStroke.Parent = freezeBtn
local pindahLabel = Instance.new("TextLabel") pindahLabel.Size = UDim2.fromOffset(80, 20) pindahLabel.AnchorPoint = Vector2.new(0.5, 1) pindahLabel.Position = UDim2.new(0.5, 0, 0, -6) pindahLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0) pindahLabel.BackgroundTransparency = 0.3 pindahLabel.Text = "PINDAH" pindahLabel.Font = Enum.Font.GothamBold pindahLabel.TextSize = 10 pindahLabel.TextColor3 = Color3.fromRGB(0, 255, 150) pindahLabel.Visible = false pindahLabel.ZIndex = 6 pindahLabel.Parent = freezeBtn Instance.new("UICorner", pindahLabel).CornerRadius = UDim.new(0, 6)

local ninjaBtn = Instance.new("TextButton")
ninjaBtn.Name = "SR4X_NinjaBtn"
ninjaBtn.Size = UDim2.fromOffset(64, 64)
ninjaBtn.Position = UDim2.new(1, -88, 0.5, -32)
ninjaBtn.BackgroundColor3 = Color3.fromRGB(255, 140, 0)
ninjaBtn.BackgroundTransparency = 0.15
ninjaBtn.Text = "⚡"
ninjaBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ninjaBtn.Font = Enum.Font.SourceSansBold
ninjaBtn.TextSize = 34
ninjaBtn.AutoButtonColor = false
ninjaBtn.BorderSizePixel = 0
ninjaBtn.Active = true
ninjaBtn.Visible = false
ninjaBtn.ZIndex = 5
ninjaBtn.Parent = gui
Instance.new("UICorner", ninjaBtn).CornerRadius = UDim.new(1, 0)
local ninjaStroke = Instance.new("UIStroke")
ninjaStroke.Thickness = 2
ninjaStroke.Color = Color3.fromRGB(255, 220, 100)
ninjaStroke.Parent = ninjaBtn

do
    local draggingN, dragStartN, startPosN, movedN = false, nil, nil, false
    ninjaBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingN = true; movedN = false
            dragStartN = input.Position; startPosN = ninjaBtn.Position
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if draggingN and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStartN
            if d.Magnitude > 6 then movedN = true end
            ninjaBtn.Position = UDim2.new(startPosN.X.Scale, startPosN.X.Offset + d.X, startPosN.Y.Scale, startPosN.Y.Offset + d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if draggingN and not movedN then
                task.spawn(ninjaFire)
            end
            draggingN = false
        end
    end)
end

local function applyOrbThickness(v) Config.OrbThick = v local alpha = v / 100 btnStroke.Thickness = alpha * 12 btnStroke.Transparency = 1 - alpha btn.BackgroundTransparency = 1 - alpha btn.TextTransparency = 1 - alpha end
local function applyFreezeThickness(v) Config.FreezeOrbThick = v local alpha = v / 100 freezeStroke.Thickness = alpha * 12 freezeStroke.Transparency = 1 - alpha freezeBtn.BackgroundTransparency = 1 - alpha freezeBtn.TextTransparency = 1 - alpha end
local function applyFreezeSize(v) Config.FreezeOrbSize = v freezeBtn.Size = UDim2.fromOffset(v, v) freezeBtn.TextSize = math.clamp(v * 0.42, 10, 70) end
applyOrbThickness(Config.OrbThick) applyFreezeThickness(Config.FreezeOrbThick) applyFreezeSize(Config.FreezeOrbSize)

local panel = Instance.new("Frame") panel.Size = UDim2.fromOffset(290, 460) panel.Position = UDim2.new(0.5, -145, 0.5, -230) panel.BackgroundColor3 = Config.BoxColor panel.BackgroundTransparency = Config.BoxTransp panel.Visible = false panel.BorderSizePixel = 0 panel.ZIndex = 10 panel.Parent = gui Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16) local pStroke = Instance.new("UIStroke") pStroke.Color = Color3.fromRGB(255,255,255) pStroke.Transparency = 0.55 pStroke.Thickness = 1 pStroke.Parent = panel table.insert(themeEls.boxes, panel)

local panelScale = Instance.new("UIScale")
panelScale.Parent = panel
local function updatePanelScale()
    local vp = Vector2.new(1280, 720)
    if Camera then pcall(function() vp = Camera.ViewportSize end) end
    local s = math.min(1, vp.Y / 540)
    if s < 0.55 then s = 0.55 end
    panelScale.Scale = s
end
pcall(updatePanelScale)
if Camera then
    pcall(function() Camera:GetPropertyChangedSignal("ViewportSize"):Connect(updatePanelScale) end)
end

local title = Instance.new("TextLabel") title.Size = UDim2.new(1, -50, 0, 32) title.Position = UDim2.fromOffset(14, 6) title.BackgroundTransparency = 1 title.Text = "SR4X TEAM v21.1" title.TextColor3 = Config.AccentA title.Font = Enum.Font.SourceSansBold title.TextSize = 16 title.TextXAlignment = Enum.TextXAlignment.Left title.ZIndex = 11 title.Parent = panel table.insert(themeEls.accents, title)

local dragHandle = Instance.new("Frame")
dragHandle.Size = UDim2.new(1, -50, 0, 34)
dragHandle.Position = UDim2.fromOffset(0, 2)
dragHandle.BackgroundTransparency = 1
dragHandle.Active = true
dragHandle.ZIndex = 12
dragHandle.Parent = panel

local closeBtn = Instance.new("TextButton") closeBtn.Size = UDim2.fromOffset(28, 28) closeBtn.Position = UDim2.new(1, -36, 0, 8) closeBtn.BackgroundColor3 = Color3.fromRGB(255,80,80) closeBtn.Text = "X" closeBtn.TextColor3 = Color3.fromRGB(255,255,255) closeBtn.Font = Enum.Font.SourceSansBold closeBtn.TextSize = 14 closeBtn.ZIndex = 13 closeBtn.Parent = panel Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8) closeBtn.MouseButton1Click:Connect(function() panel.Visible = false end)

do
    local pDrag, pStart, pOrigin = false, nil, nil
    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            pDrag = true; pStart = input.Position; pOrigin = panel.Position
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if pDrag and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - pStart
            panel.Position = UDim2.new(pOrigin.X.Scale, pOrigin.X.Offset + d.X, pOrigin.Y.Scale, pOrigin.Y.Offset + d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then pDrag = false end
    end)
end

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -52)
scroll.Position = UDim2.fromOffset(10, 44)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = UIS.TouchEnabled and 8 or 4
scroll.ScrollBarImageColor3 = Color3.fromRGB(255,255,255)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.ScrollingDirection = Enum.ScrollingDirection.Y
scroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
scroll.ZIndex = 11
scroll.Parent = panel

local layout = Instance.new("UIListLayout") layout.Padding = UDim.new(0, 8) layout.SortOrder = Enum.SortOrder.LayoutOrder layout.Parent = scroll

-- ============================================================
-- UI HELPERS (MERGED FROM PART 2)
-- ============================================================
local function makeToggle(text, initial, cb, activeColor)
    activeColor = activeColor or Config.AccentA
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 34)
    b.BackgroundColor3 = Config.BoxColor
    b.BackgroundTransparency = Config.BoxTransp
    b.TextColor3 = Color3.fromRGB(220,220,220)
    b.Font = Enum.Font.SourceSans
    b.TextSize = 14
    b.Parent = scroll
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    table.insert(themeEls.boxes, b)
    local state = { value = initial }
    local entry = { btn = b, getActive = function() return state.value end, activeColor = activeColor }
    table.insert(toggleRegistry, entry)
    local function render()
        b.Text = text .. ": " .. (state.value and "ON" or "OFF")
        if state.value then
            b.BackgroundColor3 = activeColor
            b.BackgroundTransparency = 0.5
            b.TextColor3 = Color3.fromRGB(255,255,255)
        else
            b.BackgroundColor3 = Config.BoxColor
            b.BackgroundTransparency = Config.BoxTransp
            b.TextColor3 = Color3.fromRGB(220,220,220)
        end
    end
    render()
    b.MouseButton1Click:Connect(function() state.value = not state.value render() cb(state.value) end)
    return b
end

local function makeNumber(t, initial, min, max, step, onChange)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 34)
    row.BackgroundColor3 = Config.BoxColor
    row.BackgroundTransparency = Config.BoxTransp
    row.Parent = scroll
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
    table.insert(themeEls.boxes, row)
    local lbl = Instance.new("TextButton")
    lbl.Size = UDim2.new(1, -84, 1, 0)
    lbl.Position = UDim2.fromOffset(10, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = t .. ": " .. initial
    lbl.TextColor3 = Color3.fromRGB(255,255,255)
    lbl.Font = Enum.Font.SourceSans
    lbl.TextSize = 14
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.AutoButtonColor = false
    lbl.Parent = row
    local inputBox = Instance.new("TextBox")
    inputBox.Size = UDim2.new(1, -84, 1, 0)
    inputBox.Position = UDim2.fromOffset(10, 0)
    inputBox.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
    inputBox.BackgroundTransparency = 0.3
    inputBox.TextColor3 = Color3.fromRGB(255,255,255)
    inputBox.Font = Enum.Font.SourceSans
    inputBox.TextSize = 14
    inputBox.TextXAlignment = Enum.TextXAlignment.Left
    inputBox.ClearTextOnFocus = false
    inputBox.Visible = false
    inputBox.Parent = row
    Instance.new("UICorner", inputBox).CornerRadius = UDim.new(0, 6)
    local val = initial
    local function setVal(v)
        v = math.clamp(tonumber(v) or val, min, max)
        val = v
        lbl.Text = t .. ": " .. val
        onChange(val)
    end
    lbl.MouseButton1Click:Connect(function()
        inputBox.Text = tostring(val)
        inputBox.Visible = true
        lbl.Visible = false
        inputBox:CaptureFocus()
    end)
    inputBox.FocusLost:Connect(function()
        local n = tonumber(inputBox.Text)
        if n then setVal(n) else inputBox.Text = tostring(val) end
        inputBox.Visible = false
        lbl.Visible = true
    end)
    local minus = Instance.new("TextButton")
    minus.Size = UDim2.fromOffset(32, 26)
    minus.Position = UDim2.new(1, -74, 0.5, -13)
    minus.BackgroundTransparency = 0.3
    minus.BackgroundColor3 = Config.AccentA
    minus.Text = "-"
    minus.TextColor3 = Color3.fromRGB(255,255,255)
    minus.Font = Enum.Font.SourceSansBold
    minus.Parent = row
    Instance.new("UICorner", minus).CornerRadius = UDim.new(0, 6)
    local plus = Instance.new("TextButton")
    plus.Size = UDim2.fromOffset(32, 26)
    plus.Position = UDim2.new(1, -38, 0.5, -13)
    plus.BackgroundTransparency = 0.3
    plus.BackgroundColor3 = Config.AccentA
    plus.Text = "+"
    plus.TextColor3 = Color3.fromRGB(255,255,255)
    plus.Font = Enum.Font.SourceSansBold
    plus.Parent = row
    Instance.new("UICorner", plus).CornerRadius = UDim.new(0, 6)
    minus.MouseButton1Click:Connect(function() setVal(val - step) end)
    plus.MouseButton1Click:Connect(function() setVal(val + step) end)
end

local function makeCycle(t, items, initialIdx, onChange)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 34)
    b.BackgroundColor3 = Config.BoxColor
    b.BackgroundTransparency = Config.BoxTransp
    b.TextColor3 = Color3.fromRGB(255,255,255)
    b.Font = Enum.Font.SourceSans
    b.TextSize = 14
    b.Parent = scroll
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    table.insert(themeEls.boxes, b)
    local i = initialIdx
    local function render() b.Text = t .. ": " .. tostring(items[i].name or items[i]) end
    render()
    b.MouseButton1Click:Connect(function() i = i % #items + 1 render() onChange(i, items[i]) end)
    return b
end

-- ============================================================
-- FREEZE ENGINE
-- ============================================================
local freezeConn = nil local lastCollect = 0
local function freezeModel(model)
    if frozenData[model] then return end
    local hrp = model:FindFirstChild("HumanoidRootPart")
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hrp then return end
    frozenData[model] = { cf = hrp.CFrame, origSize = hrp.Size, origTrans = hrp.Transparency,
        speed = hum and hum.WalkSpeed or 16, jump = hum and hum.JumpPower or 50,
        jheight = hum and hum.JumpHeight or 7.2 }
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            pcall(function() part.Anchored = true part.CanCollide = false part.Velocity = Vector3.zero part.RotVelocity = Vector3.zero end)
        end
    end
    pcall(function() hrp.Size = Vector3.new(15, 15, 15) hrp.Transparency = 1 hrp.CanQuery = true hrp.CanTouch = true hrp.Massless = true end)
    if hum then
        pcall(function()
            hum.WalkSpeed = 0 hum.JumpPower = 0 hum.JumpHeight = 0
            hum.PlatformStand = true hum.AutoRotate = false
            hum:ChangeState(Enum.HumanoidStateType.Physics)
        end)
    end
end
local function unfreezeModel(model)
    local data = frozenData[model]
    if not data then return end
    local hum = model:FindFirstChildOfClass("Humanoid")
    local hrp = model:FindFirstChild("HumanoidRootPart")
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then pcall(function() part.Anchored = false; part.CanCollide = true end) end
    end
    if hrp then pcall(function() hrp.Size = data.origSize hrp.Transparency = data.origTrans hrp.CanCollide = true hrp.Massless = false end) end
    if hum then pcall(function() hum.WalkSpeed = data.speed; hum.JumpPower = data.jump hum.JumpHeight = data.jheight; hum.PlatformStand = false hum.AutoRotate = true end) end
    frozenData[model] = nil
end
local function freezeTick()
    if not Config.FreezeActive then return end
    for model, data in pairs(frozenData) do
        if not model.Parent then frozenData[model] = nil
        else
            local hrp = model:FindFirstChild("HumanoidRootPart")
            if hrp then pcall(function() hrp.CFrame = data.cf hrp.Velocity = Vector3.zero hrp.RotVelocity = Vector3.zero hrp.Anchored = true hrp.Transparency = 1 end) end
            local hum = model:FindFirstChildOfClass("Humanoid")
            if hum then pcall(function() hum.WalkSpeed = 0 hum.JumpPower = 0 hum.PlatformStand = true hum:ChangeState(Enum.HumanoidStateType.Physics) end) end
        end
    end
    if os.clock() - lastCollect > 0.5 then
        lastCollect = os.clock()
        for _, model in ipairs(getCachedTargets()) do
            if not frozenData[model] then freezeModel(model) end
        end
    end
end
local function setFreezeActive(v)
    Config.FreezeActive = v
    if v then
        freezeBtn.BackgroundColor3 = Color3.fromRGB(75, 145, 255)
        if not freezeConn then freezeConn = RunService.PreSimulation:Connect(freezeTick) end
    else
        if Config.FreezeInactiveRGB then freezeBtn.BackgroundColor3 = Color3.fromHSV((tick() % 5)/5, 0.8, 1) else freezeBtn.BackgroundColor3 = Config.FreezeInactiveColor end
        if freezeConn then freezeConn:Disconnect(); freezeConn = nil end
        for model in pairs(frozenData) do pcall(unfreezeModel, model) end
        frozenData = {}
    end
end
local function startFreeze() if Config.FreezeActive then return end for _, model in ipairs(getCachedTargets()) do if not frozenData[model] then freezeModel(model) end end setFreezeActive(true) end
local function stopFreeze() if not Config.FreezeActive then return end setFreezeActive(false) end

-- ============================================================
-- UI SECTIONS
-- ============================================================
section("FREEZE")
makeToggle("Freeze Module", Config.FreezeEnabled, function(v)
    Config.FreezeEnabled = v
    freezeBtn.Visible = v
    if not v and Config.FreezeActive then stopFreeze() end
    invalidateTargets()
end, Color3.fromRGB(0, 150, 255))

section("FREEZE BUTTON SETTING (PISAH)")
makeNumber("Besar Tombol Freeze", Config.FreezeOrbSize, 20, 120, 4, function(v) applyFreezeSize(v) end)
makeNumber("Ketebalan Freeze", Config.FreezeOrbThick, 0, 100, 5, function(v) applyFreezeThickness(v) end)
makeCycle("Warna OFF (Sebelum Aktif)", FreezeInactiveColors, 1, function(_, v)
    if v.name == "RGB" then
        Config.FreezeInactiveRGB = true
    else
        Config.FreezeInactiveRGB = false
        Config.FreezeInactiveColor = v.color
        if not Config.FreezeActive then freezeBtn.BackgroundColor3 = v.color end
    end
end)

section("SILENT AIM (BIG HEAD - ADDITIVE, NO WALL CHECK)")
makeToggle("Silent Aim (Big Head)", Config.SilentAim, function(v)
    Config.SilentAim = v
    if not v then clearAllBigHeads() end
    if v then
        task.delay(0.6, function()
            local n = 0
            for _ in pairs(bigHeadState) do n = n + 1 end
            print("[SR4X] Big Head applied to " .. n .. " targets (offset=" .. Config.SilentAimHeadSize .. ", range=" .. Config.SilentAimRange .. " studs)")
        end)
    end
end, Color3.fromRGB(255, 50, 100))
makeNumber("Head Offset (additive)", Config.SilentAimHeadSize, 1, 100, 1, function(v)
    Config.SilentAimHeadSize = v
    clearAllBigHeads()
end)
makeNumber("Max Range (studs)", Config.SilentAimRange, 50, 2000, 50, function(v)
    Config.SilentAimRange = v
end)
makeToggle("Silent Team Check", Config.SilentAimTeam, function(v) Config.SilentAimTeam = v end)
makeToggle("Silent NPCs", Config.SilentAimNPCs, function(v) Config.SilentAimNPCs = v end)

section("NINJA FIRE (ON-SCREEN ⚡ BUTTON, WALL CHECK)")
makeToggle("Ninja Fire", Config.NinjaFire, function(v)
    Config.NinjaFire = v
    ninjaBtn.Visible = v
end, Color3.fromRGB(255, 140, 0))
makeNumber("Ninja Offset (studs)", Config.NinjaFireDist, 2, 15, 1, function(v) Config.NinjaFireDist = v end)
makeNumber("Return Delay (x1000s)", math.floor(Config.NinjaFireReturnDelay*1000), 10, 300, 10, function(v) Config.NinjaFireReturnDelay = v/1000 end)

section("AIMBOT (VISUAL, WALL CHECK)")
makeToggle("Aimbot", Config.Aimbot, function(v) Config.Aimbot = v end)
makeNumber("FOV (px)", Config.AimbotFOV, 40, 600, 20, function(v) Config.AimbotFOV = v end)
makeNumber("Smooth x100", math.floor(Config.AimbotSmooth*100), 0, 95, 5, function(v) Config.AimbotSmooth = v/100 end)
makeCycle("Target Part", { {name="Head"}, {name="HRP"} }, 1, function(_, v) Config.AimbotPart = v.name end)
makeToggle("Target Players", Config.TargetPlayers, function(v) Config.TargetPlayers = v invalidateTargets() end)
makeToggle("Target NPCs", Config.TargetNPCs, function(v) Config.TargetNPCs = v invalidateTargets() end)
makeToggle("Team Check", Config.TeamCheck, function(v) Config.TeamCheck = v invalidateTargets() end)
makeToggle("Wall Check", Config.WallCheck, function(v) Config.WallCheck = v end)
makeToggle("Show FOV Circle", Config.ShowFOV, function(v) Config.ShowFOV = v end)

section("AIMBOT POV ADJUSTMENT")
makeNumber("POV X", Config.POV_X, -100, 100, 5, function(v) Config.POV_X = v end)
makeNumber("POV Y", Config.POV_Y, -100, 100, 5, function(v) Config.POV_Y = v end)

section("AIM MAGNET (OP, WALL CHECK)")
makeToggle("Magnet Manual (POV)", Config.AimMagnetManual, function(v) Config.AimMagnetManual = v if v then Config.AimMagnetPro = false end end, Color3.fromRGB(255, 0, 255))
makeToggle("Magnet Pro (Global)", Config.AimMagnetPro, function(v) Config.AimMagnetPro = v if v then Config.AimMagnetManual = false end end, Color3.fromRGB(255, 0, 255))
makeCycle("Magnet Target", {{name="Head"}, {name="HRP"}}, 1, function(_, v) Config.MagnetTarget = v.name end)

section("NOCLIP (AUTO SAAT SILENT ON)")
makeToggle("Noclip Master", Config.NoclipEnabled, function(v) Config.NoclipEnabled = v end, Color3.fromRGB(0, 255, 150))
makeToggle("Noclip Auto (tied Silent Aim)", Config.NoclipAuto, function(v) Config.NoclipAuto = v end, Color3.fromRGB(0, 255, 150))
makeToggle("Anti-Fling", Config.AntiFlingEnabled, function(v) Config.AntiFlingEnabled = v end, Color3.fromRGB(0, 255, 150))

section("ANTI-BAN")
makeToggle("Anti-Ban Master (Kick/DC/TP Block)", Config.AntiBanEnabled, function(v) Config.AntiBanEnabled = v Config.AntiKick = v end, Color3.fromRGB(0, 255, 100))
makeToggle("Anti-Kick (legacy)", Config.AntiKick, function(v) Config.AntiKick = v end, Color3.fromRGB(0, 255, 150))

section("AUTO SHOOT & UTILITY")
makeToggle("Auto Shoot (Triggerbot)", Config.AutoShoot, function(v) Config.AutoShoot = v end, Color3.fromRGB(255, 100, 0))
makeCycle("Shoot Target", {{name="Head"}, {name="HRP"}}, 1, function(_, v) Config.AutoShootTarget = v.name end)
makeNumber("Shoot Speed (ms)", math.floor(Config.AutoShootSpeed*1000), 80, 500, 10, function(v) Config.AutoShootSpeed = v/1000 end)
makeToggle("Fast Reload", Config.FastReload, function(v) Config.FastReload = v end, Color3.fromRGB(0, 255, 255))
makeToggle("No Reload Bypass", Config.NoReload, function(v) Config.NoReload = v end, Color3.fromRGB(0, 255, 0))
makeToggle("Auto Magnet (Item)", Config.AutoMagnet, function(v) Config.AutoMagnet = v end, Color3.fromRGB(255, 215, 0))

section("ESP SETTINGS (SCREEN-BASED)")
makeToggle("Enable ESP", Config.ESP_Enabled, function(v) Config.ESP_Enabled = v end)
makeToggle("ESP Box", Config.ESP_Box, function(v) Config.ESP_Box = v end)
makeToggle("ESP Line", Config.ESP_Line, function(v) Config.ESP_Line = v end)
makeToggle("ESP Name", Config.ESP_Name, function(v) Config.ESP_Name = v end)
makeToggle("ESP Skull (☠)", Config.ESP_Skull, function(v) Config.ESP_Skull = v end)
makeCycle("ESP Color", ESP_Colors, 1, function(_, v) Config.ESP_Color = v.color end)

section("ESP OUTLINE (3D RGB)")
makeToggle("ESP Outline", Config.ESP_Outline, function(v) Config.ESP_Outline = v end, Color3.fromRGB(0, 255, 200))
makeCycle("Outline Mode", {
    {name="Solid"}, {name="RGB"}, {name="3D RGB"}, {name="Gradient"}
}, 3, function(_, v) Config.ESP_Outline_Mode = v.name end)
makeNumber("Outline Thickness", Config.ESP_Outline_Thickness, 0.5, 10, 0.5, function(v) Config.ESP_Outline_Thickness = v end)

section("THEME")
makeCycle("Mode", { {name="Gradient"}, {name="RGB"}, {name="Solid"} }, 1, function(_, v) Config.Theme = v.name end)
makeCycle("Preset", ThemePresets, 1, function(_, v)
    Config.BoxColor = v.box; Config.AccentA = v.a; Config.AccentB = v.b
    applyTheme()
end)

section("ORB MENU THICKNESS (0-100)")
makeNumber("Ketebalan Menu", Config.OrbThick, 0, 100, 5, function(v) applyOrbThickness(v) end)
applyTheme()

print("[SR4X] UI sections built.")

-- ============================================================
-- THEME LOOP
-- ============================================================
local rgbT = 0
RunService.RenderStepped:Connect(function(dt)
    pcall(function()
        local currentRGB = Color3.fromHSV((tick() * 0.6) % 1, 1, 1)
        chStroke.Color = currentRGB; crosshairDot.BackgroundColor3 = currentRGB
        crosshairRing.Position = UDim2.fromScale(0.5, 0.5); crosshairDot.Position = UDim2.fromScale(0.5, 0.5)
        fovFrame.Position = UDim2.new(0.5, Config.POV_X, 0.5, Config.POV_Y)
        fovFrame.Size = UDim2.fromOffset(Config.AimbotFOV*2, Config.AimbotFOV*2)
        if not Config.FreezeActive and Config.FreezeInactiveRGB then freezeBtn.BackgroundColor3 = Color3.fromHSV((tick() * 0.5) % 1, 0.9, 1) end
        if Config.Theme == "RGB" then
            rgbT = rgbT + dt
            local c1 = Color3.fromHSV((rgbT*0.3)%1, 1, 1)
            local c2 = Color3.fromHSV((rgbT*0.3+0.5)%1, 1, 1)
            btnStroke.Color = c1; btnGrad.Color = ColorSequence.new(c1, c2); fovStroke.Color = c1
        elseif Config.Theme == "Gradient" then
            btnStroke.Color = Config.AccentA; btnGrad.Color = ColorSequence.new(Config.AccentA, Config.AccentB); fovStroke.Color = Config.AccentA
        else
            btnStroke.Color = Config.AccentA; btnGrad.Color = ColorSequence.new(Config.AccentA, Config.AccentA); fovStroke.Color = Config.AccentA
        end
        fovFrame.Visible = Config.ShowFOV
    end)
end)

-- ============================================================
-- DRAG ORB & FREEZE ORB
-- ============================================================
local draggingMain, dragStartMain, startPosMain, movedMain
btn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        draggingMain = true; movedMain = false
        dragStartMain = input.Position; startPosMain = btn.Position
    end
end)
UIS.InputChanged:Connect(function(input)
    if draggingMain and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local d = input.Position - dragStartMain
        if d.Magnitude > 6 then movedMain = true end
        btn.Position = UDim2.new(startPosMain.X.Scale, startPosMain.X.Offset + d.X, startPosMain.Y.Scale, startPosMain.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        if draggingMain and not movedMain then panel.Visible = not panel.Visible end
        draggingMain = false
    end
end)

local freezeLocked = true; local holdingFreeze = false; local holdThread = nil; local movedFreeze = false
local dragStartFreeze, startPosFreeze
local function lockFreeze() freezeLocked = true; pindahLabel.Visible = false; freezeStroke.Color = Color3.fromRGB(255, 255, 255) end
local function unlockFreeze() freezeLocked = false; pindahLabel.Visible = true; freezeStroke.Color = Color3.fromRGB(0, 255, 150) pcall(function() Tween:Create(freezeBtn, TweenInfo.new(0.1, Enum.EasingStyle.Bounce), {Size = UDim2.fromOffset(Config.FreezeOrbSize+6, Config.FreezeOrbSize+6)}):Play() task.wait(0.1) Tween:Create(freezeBtn, TweenInfo.new(0.1), {Size = UDim2.fromOffset(Config.FreezeOrbSize, Config.FreezeOrbSize)}):Play() end) end
freezeBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        holdingFreeze = true; movedFreeze = false
        dragStartFreeze = input.Position; startPosFreeze = freezeBtn.Position
        if holdThread then task.cancel(holdThread) end
        holdThread = task.delay(2, function() if holdingFreeze and not movedFreeze then unlockFreeze() end end)
    end
end)
UIS.InputChanged:Connect(function(input)
    if holdingFreeze and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local d = input.Position - dragStartFreeze
        if d.Magnitude > 8 then movedFreeze = true end
        if not freezeLocked and movedFreeze then
            freezeBtn.Position = UDim2.new(startPosFreeze.X.Scale, startPosFreeze.X.Offset + d.X, startPosFreeze.Y.Scale, startPosFreeze.Y.Offset + d.Y)
        end
    end
end)
UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        if holdingFreeze then
            if holdThread then task.cancel(holdThread) holdThread = nil end
            if freezeLocked then
                if not movedFreeze then
                    if Config.FreezeActive then stopFreeze() else startFreeze() end
                end
            else
                lockFreeze()
            end
        end
        holdingFreeze = false; movedFreeze = false
    end
end)

-- ============================================================
-- VISUAL AIMBOT
-- ============================================================
local function targetPos(model)
    if not model then return nil end
    if Config.AimbotPart == "Head" then
        local h = model:FindFirstChild("Head")
        if h then return h.Position end
    end
    local hrp = model:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position or nil
end

local function pickTarget()
    if not Camera then return nil end
    local vs = Camera.ViewportSize
    if not vs or vs.X <= 0 or vs.Y <= 0 then return nil end
    local best, bestDist = nil, Config.AimbotFOV
    local center = Vector2.new(vs.X/2 + Config.POV_X, vs.Y/2 + Config.POV_Y)
    local myTeam = LP.Team
    local function consider(model, team, isPlayer)
        local pos = targetPos(model)
        if not pos then return end
        if isPlayer and Config.TeamCheck and myTeam and team == myTeam then return end
        local ok, sp = pcall(function() return Camera:WorldToViewportPoint(pos) end)
        if ok and sp and sp.Z > 0 then
            local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
            if d < bestDist then
                if isVisible(model, pos) then best, bestDist = pos, d end
            end
        end
    end
    if Config.TargetPlayers then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and p.Character then
                local hum = p.Character:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 and p.Character:FindFirstChild("HumanoidRootPart") then
                    consider(p.Character, p.Team, true)
                end
            end
        end
    end
    if Config.TargetNPCs then
        refreshNPCs()
        for _, m in ipairs(npcCache) do if m.Parent then consider(m, nil, false) end end
    end
    return best
end

RunService:BindToRenderStep("SR4XAimbotCamera", Enum.RenderPriority.Camera.Value + 1, function()
    if not Camera then return end
    if not Config.Aimbot then crosshairRing.Visible = false; crosshairDot.Visible = false return end
    crosshairRing.Visible = true; crosshairDot.Visible = true
    local tpos = pickTarget()
    if not tpos then return end
    local camPos = Camera.CFrame.Position
    if (tpos - camPos).Magnitude < 0.1 then return end
    pcall(function()
        local desired = CFrame.lookAt(camPos, tpos)
        local factor = math.clamp(1 - Config.AimbotSmooth, 0, 1)
        Camera.CFrame = Camera.CFrame:Lerp(desired, factor)
    end)
end)

-- ============================================================
-- AUTO MAGNET
-- ============================================================
task.spawn(function()
    while task.wait(1) do
        if Config.AutoMagnet then
            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj:IsA("ProximityPrompt") then
                    pcall(function()
                        if not obj:GetAttribute("SR4X_Magnet") then
                            obj:SetAttribute("SR4X_Magnet", true)
                            obj:SetAttribute("OrigMaxDist", obj.MaxActivationDistance)
                            obj:SetAttribute("OrigLOS", obj.RequiresLineOfSight)
                            obj:SetAttribute("OrigHold", obj.HoldDuration)
                        end
                        obj.MaxActivationDistance = 1000
                        obj.RequiresLineOfSight = false
                        obj.HoldDuration = 0
                    end)
                end
            end
        else
            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj:IsA("ProximityPrompt") and obj:GetAttribute("SR4X_Magnet") then
                    pcall(function()
                        obj.MaxActivationDistance = obj:GetAttribute("OrigMaxDist") or 10
                        obj.RequiresLineOfSight = obj:GetAttribute("OrigLOS") ~= false
                        obj.HoldDuration = obj:GetAttribute("OrigHold") or 0
                        obj:SetAttribute("SR4X_Magnet", nil)
                    end)
                end
            end
        end
    end
end)

-- ============================================================
-- AIM MAGNET
-- ============================================================
local magnetData = {}
RunService.RenderStepped:Connect(function()
    if not Camera then return end
    if not Config.AimMagnetManual and not Config.AimMagnetPro then
        for model, data in pairs(magnetData) do
            if model.Parent then
                local hrp = model:FindFirstChild("HumanoidRootPart")
                if hrp then pcall(function() hrp.Anchored = data.origAnchored hrp.CanCollide = data.origCanCollide hrp.CFrame = data.origCF end) end
            end
        end
        magnetData = {}; return
    end
    local targetModel = nil; local nearestDist = math.huge
    local vs = Camera.ViewportSize
    if not vs then return end
    local center = Vector2.new(vs.X/2 + Config.POV_X, vs.Y/2 + Config.POV_Y)
    for _, model in ipairs(getCachedTargets()) do
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if hrp then
            local isInsideFOV = false
            local sp, onScreen = Camera:WorldToViewportPoint(hrp.Position)
            if onScreen and sp.Z > 0 then
                local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                if d <= Config.AimbotFOV then isInsideFOV = true end
            end
            if Config.AimMagnetPro or (Config.AimMagnetManual and isInsideFOV) then
                if isVisible(model, hrp.Position) then
                    local dist = (Camera.CFrame.Position - hrp.Position).Magnitude
                    if dist < nearestDist then nearestDist = dist; targetModel = model end
                end
            end
        end
    end
    if targetModel then
        local hrp = targetModel:FindFirstChild("HumanoidRootPart")
        if not magnetData[targetModel] then
            magnetData[targetModel] = { origCF = hrp.CFrame, origAnchored = hrp.Anchored, origCanCollide = hrp.CanCollide }
        end
        pcall(function()
            hrp.Anchored = true; hrp.CanCollide = false
            local centerRay = Camera:ViewportPointToRay(Camera.ViewportSize.X/2 + Config.POV_X, Camera.ViewportSize.Y/2 + Config.POV_Y)
            local targetPos = centerRay.Origin + centerRay.Direction * 15
            if Config.MagnetTarget == "Head" and targetModel:FindFirstChild("Head") then
                local head = targetModel.Head
                local headOffset = hrp.CFrame:ToObjectSpace(head.CFrame)
                hrp.CFrame = CFrame.lookAt(targetPos, Camera.CFrame.Position) * headOffset:Inverse()
            else
                hrp.CFrame = CFrame.lookAt(targetPos, Camera.CFrame.Position)
            end
        end)
    end
end)

-- ============================================================
-- FAST RELOAD / NO RELOAD
-- ============================================================
task.spawn(function()
    while task.wait(0.05) do
        if Config.FastReload then
            local tool = getWeaponTool()
            if tool then
                pcall(function()
                    for _, v in pairs(tool:GetDescendants()) do
                        if v:IsA("ValueBase") and (v.Name:lower():find("ammo") or v.Name:lower():find("clip")) then
                            if v.Value < 99 then v.Value = 99 end
                        end
                    end
                    local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
                    if hum and hum:FindFirstChildOfClass("Animator") then
                        for _, track in ipairs(hum.Animator:GetPlayingAnimationTracks()) do
                            if track.Name:lower():find("reload") then track:AdjustSpeed(10) end
                        end
                    end
                end)
            end
        end
    end
end)

task.spawn(function()
    while task.wait(0.05) do
        if Config.NoReload then
            local tool = getWeaponTool()
            if tool then
                pcall(function()
                    for _, v in pairs(tool:GetDescendants()) do
                        if v:IsA("ValueBase") and (v.Name:lower():find("ammo") or v.Name:lower():find("clip") or v.Name:lower():find("mag")) then
                            v.Value = 999
                        end
                    end
                    local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
                    if hum and hum:FindFirstChildOfClass("Animator") then
                        for _, track in ipairs(hum.Animator:GetPlayingAnimationTracks()) do
                            if track.Name:lower():find("reload") then track:Stop(0) end
                        end
                    end
                end)
            end
        end
    end
end)

-- ============================================================
-- AUTO SHOOT
-- ============================================================
task.spawn(function()
    local lastShot = 0
    while task.wait(0.01) do
        if Config.AutoShoot and Camera then
            local now = tick()
            if now - lastShot >= Config.AutoShootSpeed then
                local targetFound = false
                pcall(function()
                    local vs = Camera.ViewportSize
                    if not vs then return end
                    local center = Vector2.new(vs.X/2 + Config.POV_X, vs.Y/2 + Config.POV_Y)
                    for _, model in ipairs(getCachedTargets()) do
                        local part = model:FindFirstChild(Config.AutoShootTarget == "Head" and "Head" or "HumanoidRootPart")
                        if part then
                            local sp, onScreen = Camera:WorldToViewportPoint(part.Position)
                            if onScreen and sp.Z > 0 then
                                local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                                if d < Config.AimbotFOV and isVisible(model, part.Position) then
                                    targetFound = true; break
                                end
                            end
                        end
                    end
                end)
                if targetFound then
                    local tool = getWeaponTool()
                    if tool and tool.Enabled then pcall(function() tool:Activate() end) end
                    lastShot = now
                end
            end
        end
    end
end)

-- ============================================================
-- INTRO
-- ============================================================
local DURATION = 9.83
local introDone = false
local introConn
local startTime = os.clock()
local introGui, intro

local function showSuccessNotif()
    if not guiParent then return end
    local ok = pcall(function()
        local notifGui = Instance.new("ScreenGui")
        notifGui.Name = "SR4X_SuccessNotif"
        notifGui.ResetOnSpawn = false
        notifGui.Enabled = true
        notifGui.DisplayOrder = BASE_DO + 4
        pcall(function() notifGui.IgnoreGuiInset = true end)
        notifGui.Parent = guiParent
        local notifFrame = Instance.new("Frame")
        notifFrame.Size = UDim2.fromOffset(280, 50) notifFrame.AnchorPoint = Vector2.new(0.5, 0)
        notifFrame.Position = UDim2.new(0.5, 0, 0, -60)
        notifFrame.BackgroundColor3 = Color3.fromRGB(20, 80, 40)
        notifFrame.BackgroundTransparency = 0.1 notifFrame.BorderSizePixel = 0 notifFrame.ZIndex = 10000 notifFrame.Parent = notifGui
        Instance.new("UICorner", notifFrame).CornerRadius = UDim.new(0, 12)
        local nStroke = Instance.new("UIStroke") nStroke.Color = Color3.fromRGB(0, 255, 100) nStroke.Thickness = 1.5 nStroke.Parent = notifFrame
        local nLabel = Instance.new("TextLabel")
        nLabel.Size = UDim2.new(1, 0, 1, 0) nLabel.BackgroundTransparency = 1
        nLabel.Text = "LOADING SUCCESS ✅" nLabel.Font = Enum.Font.GothamBold nLabel.TextSize = 16
        nLabel.TextColor3 = Color3.fromRGB(255, 255, 255) nLabel.ZIndex = 10001 nLabel.Parent = notifFrame
        Tween:Create(notifFrame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = UDim2.new(0.5, 0, 0, 20)}):Play()
        task.delay(2.5, function()
            Tween:Create(notifFrame, TweenInfo.new(0.4), {Position = UDim2.new(0.5, 0, 0, -60), BackgroundTransparency = 1}):Play()
            task.wait(0.5)
            pcall(function() notifGui:Destroy() end)
        end)
    end)
    if not ok then warn("[SR4X] notif failed") end
end

local function endIntro()
    if introDone then return end
    introDone = true
    if introConn then pcall(function() introConn:Disconnect() end) end
    if introGui and introGui.Parent then
        pcall(function()
            for _, obj in ipairs(introGui:GetDescendants()) do
                if obj:IsA("TextLabel") then
                    Tween:Create(obj, TweenInfo.new(0.4), {TextTransparency = 1}):Play()
                elseif obj:IsA("Frame") then
                    Tween:Create(obj, TweenInfo.new(0.4), {BackgroundTransparency = 1}):Play()
                end
            end
        end)
        task.delay(0.5, function()
            if introGui and introGui.Parent then pcall(function() introGui:Destroy() end) end
            showSuccessNotif()
        end)
    else
        showSuccessNotif()
    end
end
task.delay(DURATION, endIntro)

if guiParent then
    local ok, err = pcall(function()
        introGui = Instance.new("ScreenGui")
        introGui.Name = "SR4X_Loading"
        introGui.ResetOnSpawn = false
        introGui.IgnoreGuiInset = true
        introGui.Enabled = true
        introGui.DisplayOrder = BASE_DO + 3
        introGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
        pcall(function() introGui.OnTopOfCoreBlur = true end)
        introGui.Parent = guiParent
        intro = Instance.new("Frame")
        intro.Size = UDim2.fromScale(1, 1) intro.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        intro.BorderSizePixel = 0 intro.Active = true intro.ZIndex = 100 intro.Parent = introGui

        local particles = {}
        for i = 1, 60 do
            local p = Instance.new("Frame")
            p.Size = UDim2.fromOffset(math.random(2, 5), math.random(2, 5))
            p.Position = UDim2.fromScale(math.random(), math.random())
            p.BackgroundColor3 = Color3.fromHSV(math.random(), 1, 1)
            p.BorderSizePixel = 0 p.ZIndex = 101 p.Parent = intro
            Instance.new("UICorner", p).CornerRadius = UDim.new(1, 0)
            table.insert(particles, { frame = p, speedX = (math.random() - 0.5) * 0.05, speedY = (math.random() - 0.5) * 0.05, hue = math.random() })
        end

        local teamName = Instance.new("TextLabel")
        teamName.Size = UDim2.new(1, 0, 0, 80) teamName.AnchorPoint = Vector2.new(0.5, 0.5)
        teamName.Position = UDim2.fromScale(0.5, 0.4) teamName.BackgroundTransparency = 1
        teamName.Text = "SR4X TEAM" teamName.Font = Enum.Font.SourceSansBold teamName.TextSize = 60
        teamName.TextColor3 = Color3.fromRGB(255, 255, 255) teamName.ZIndex = 102 teamName.Parent = intro

        local statusText = Instance.new("TextLabel")
        statusText.Size = UDim2.new(1, 0, 0, 30) statusText.AnchorPoint = Vector2.new(0.5, 0.5)
        statusText.Position = UDim2.fromScale(0.5, 0.55) statusText.BackgroundTransparency = 1
        statusText.Text = "Menyiapkan data..." statusText.TextColor3 = Color3.fromRGB(200, 200, 200)
        statusText.Font = Enum.Font.SourceSans statusText.TextSize = 18 statusText.ZIndex = 102 statusText.Parent = intro

        local barBg = Instance.new("Frame")
        barBg.Size = UDim2.new(0.7, 0, 0, 10) barBg.AnchorPoint = Vector2.new(0.5, 0.5)
        barBg.Position = UDim2.fromScale(0.5, 0.62) barBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        barBg.BorderSizePixel = 0 barBg.ZIndex = 103 barBg.Parent = intro
        Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)

        local barFill = Instance.new("Frame")
        barFill.Size = UDim2.new(0, 0, 1, 0) barFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        barFill.BorderSizePixel = 0 barFill.ZIndex = 104 barFill.Parent = barBg
        Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

        local pctLabel = Instance.new("TextLabel")
        pctLabel.Size = UDim2.new(1, 0, 0, 20) pctLabel.Position = UDim2.new(0, 0, 1, 5)
        pctLabel.BackgroundTransparency = 1 pctLabel.Text = "0%"
        pctLabel.TextColor3 = Color3.fromRGB(200, 200, 200) pctLabel.Font = Enum.Font.SourceSansBold
        pctLabel.TextSize = 14 pctLabel.ZIndex = 104 pctLabel.Parent = barBg

        local footer = Instance.new("TextLabel")
        footer.Size = UDim2.new(1, 0, 0, 20) footer.Position = UDim2.new(0, 0, 1, -30)
        footer.BackgroundTransparency = 1 footer.Text = "Dibuat oleh NanzzzProject | 2026"
        footer.TextColor3 = Color3.fromRGB(120, 120, 120) footer.Font = Enum.Font.Code
        footer.TextSize = 11 footer.ZIndex = 105 footer.Parent = intro

        local statusMessages = { "Menyiapkan data...", "Memuat script SR4X...", "Menginjeksi module...", "Menghubungkan ke server...", "Menyelesaikan setup...", "Selesai!" }
        intro.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                endIntro()
            end
        end)

        introConn = RunService.RenderStepped:Connect(function(dt)
            pcall(function()
                local t = os.clock()
                local pct = math.clamp((t - startTime) / DURATION, 0, 1)
                for _, p in ipairs(particles) do
                    local pos = p.frame.Position
                    local newX = pos.X.Scale + p.speedX * dt
                    local newY = pos.Y.Scale + p.speedY * dt
                    if newX < 0 then newX = 1 elseif newX > 1 then newX = 0 end
                    if newY < 0 then newY = 1 elseif newY > 1 then newY = 0 end
                    p.frame.Position = UDim2.fromScale(newX, newY)
                    p.hue = (p.hue + dt * 0.5) % 1
                    p.frame.BackgroundColor3 = Color3.fromHSV(p.hue, 1, 1)
                end
                barFill.Size = UDim2.new(pct, 0, 1, 0)
                barFill.BackgroundColor3 = Color3.fromHSV((t * 0.3) % 1, 0.8, 1)
                teamName.TextColor3 = Color3.fromHSV((t * 0.3) % 1, 0.8, 1)
                pctLabel.Text = string.format("%d%%", math.floor(pct * 100))
                local msgIdx = math.clamp(math.floor(pct * #statusMessages) + 1, 1, #statusMessages)
                statusText.Text = statusMessages[msgIdx]
                if pct >= 1 then endIntro() end
            end)
        end)
    end)
    if not ok then
        warn("[SR4X] Intro failed to build: " .. tostring(err))
        introDone = true
    end
else
    warn("[SR4X] No guiParent — intro skipped")
    introDone = true
end

print("[SR4X] v21.1 — ESP Line fixed (math.atan) + Skull restored + Outline (Solid/RGB/3D RGB/Gradient) + Wall check on Magnet/Ninja.")