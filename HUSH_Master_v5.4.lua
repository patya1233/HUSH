-- =========================================================================
-- HUSH: พวกเขาสามารถได้ยิน - Master Script (v5.4 Optimized / Anti-Flicker)
-- =========================================================================

if not game:IsLoaded() then
    game.Loaded:Wait()
end

if _G.HUSH_UNLOAD then
    pcall(_G.HUSH_UNLOAD)
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local import = (getrenv and getrenv().require) or require
local function GetModule(inst)
    local ok, res = pcall(import, inst)
    return ok and res or nil
end

local SharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Items = GetModule(SharedFolder:WaitForChild("Items"))
local ConfigMod = GetModule(SharedFolder:WaitForChild("Config"))
local GunsMod = GetModule(SharedFolder:WaitForChild("Guns"))

local ClientScripts = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client")
local InvKit = GetModule(ClientScripts:WaitForChild("InvKit"))

local MovementTable = ConfigMod and ConfigMod.Movement or {}
local GunDefs = GunsMod and GunsMod.Defs or {}

local SCRIPT_NAME = "HUSH Master"
local SCRIPT_VERSION = "v5.4"

local ESP_INTERVAL = 1 / 20
local TARGET_INTERVAL = 1 / 30

local OrigLighting = {
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    Brightness = Lighting.Brightness,
    GlobalShadows = Lighting.GlobalShadows,
    FogEnd = Lighting.FogEnd,
}

local OrigGunDefs = {}
for gunName, def in pairs(GunDefs) do
    if type(def) == "table" then
        OrigGunDefs[gunName] = {
            recoil = def.recoil,
            climb = def.climb,
            spread = def.spread,
            db = def.db,
            ads = def.ads,
        }
    end
end

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
if PlayerGui:FindFirstChild("HUSH_ESP_CACHE") then
    PlayerGui.HUSH_ESP_CACHE:Destroy()
end

local ESPFolder = Instance.new("Folder")
ESPFolder.Name = "HUSH_ESP_CACHE"
ESPFolder.Parent = PlayerGui

local Config = {
    Monsters = false,
    MonsterChams = false,
    MonsterMaxDist = 1500,
    Sentries = false,
    Watchers = false,

    LootBags = true,
    LootChams = true,
    SupplyDrops = true,
    SupplyChams = true,
    LootMaxDist = 3000,
    Exits = true,

    Players = true,
    PlayerChams = false,
    ShowPlayerHealth = true,
    ShowPlayerInventory = true,
    PlayerMaxDist = 2000,

    Fullbright = false,
    ClearVision = false,
    EnableFOV = false,
    CustomFOV = 70,

    InfiniteStamina = true,
    Noclip = false,

    NoRecoil = true,
    NoSpread = true,
    SilentGuns = true,
    InstantADS = true,

    Aimbot = false,
    SilentAim = false,
    AimKey = Enum.UserInputType.MouseButton2,
    TargetPart = "Head",
    TargetPlayers = true,
    TargetMonsters = true,
    WallCheck = false,
    AimSmoothness = 0.25,
    ShowFOV = true,
    FOVRadius = 150,

    InstantInteract = true,
}

local ESPObjects = {}
local HookConnections = {}
local LightingLocks = {}
local isRunning = true

local function GetTargetPartAndPos(target)
    if not target or not target.Parent then return nil, nil end

    if target:IsA("BasePart") then
        return target, target.Position
    elseif target:IsA("Model") then
        local pp = target.PrimaryPart
        if pp and pp.Parent then
            return pp, pp.Position
        end
        local hrp = target:FindFirstChild("HumanoidRootPart")
        if hrp and hrp:IsA("BasePart") then
            return hrp, hrp.Position
        end
        local anyPart = target:FindFirstChildWhichIsA("BasePart", true)
        if anyPart then
            return anyPart, anyPart.Position
        end
        return nil, target:GetPivot().Position
    elseif target:IsA("Folder") then
        local anyPart = target:FindFirstChildWhichIsA("BasePart", true)
        if anyPart then
            return anyPart, anyPart.Position
        end
    end
    return nil, nil
end

local function RemoveESP(target)
    local data = ESPObjects[target]
    if data then
        if data.GUI then data.GUI:Destroy() end
        if data.Highlight then data.Highlight:Destroy() end
        ESPObjects[target] = nil
    end
end

local function EnsureHighlight(data)
    if data.Highlight or not data.CanHighlight then return end
    local target = data.Target
    if not target or not target.Parent then return end
    local hl = Instance.new("Highlight")
    hl.Name = "ESP_Highlight"
    hl.Adornee = target
    hl.FillColor = data.Color
    hl.FillTransparency = 0.6
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.OutlineTransparency = 0.1
    hl.Enabled = false
    hl.Parent = ESPFolder
    data.Highlight = hl
end

local function CreateESP(target, name, color, isModel, isPlayer, category)
    if not target then return end
    if ESPObjects[target] then
        RemoveESP(target)
    end

    local adorneePart, pos = GetTargetPartAndPos(target)
    if not adorneePart and not pos then return end

    local bg = Instance.new("BillboardGui")
    bg.Name = "ESP_Tag"
    if adorneePart then bg.Adornee = adorneePart end
    bg.AlwaysOnTop = true
    bg.Size = isPlayer and UDim2.fromOffset(150, 78) or UDim2.fromOffset(160, 40)
    bg.StudsOffset = Vector3.new(0, isPlayer and 3.4 or 2.6, 0)
    bg.Enabled = false
    bg.Parent = ESPFolder

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, isPlayer and 32 or 38)
    label.BackgroundTransparency = 1
    label.Text = string.format("[%s]", name)
    label.TextColor3 = color
    label.TextStrokeTransparency = 0.2
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.TextSize = 12
    label.Font = Enum.Font.SourceSansBold
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.Visible = false
    label.Parent = bg

    local playerSlots = nil
    if isPlayer then
        local slotContainer = Instance.new("Frame")
        slotContainer.Name = "InventorySlots"
        slotContainer.Size = UDim2.new(1, 0, 0, 36)
        slotContainer.Position = UDim2.new(0, 0, 0, 34)
        slotContainer.BackgroundTransparency = 1
        slotContainer.Parent = bg

        playerSlots = {
            Container = slotContainer,
            Boxes = {},
            Cached = { nil, nil, nil },
        }

        for i = 1, 3 do
            local sBox = Instance.new("Frame")
            sBox.Size = UDim2.fromOffset(36, 36)
            sBox.Position = UDim2.new(0, (i - 1) * 44 + 9, 0, 0)
            sBox.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
            sBox.BorderSizePixel = 0
            sBox.Parent = slotContainer

            local sCorner = Instance.new("UICorner")
            sCorner.CornerRadius = UDim.new(0, 5)
            sCorner.Parent = sBox

            local sStroke = Instance.new("UIStroke")
            sStroke.Color = Color3.fromRGB(50, 60, 80)
            sStroke.Thickness = 1
            sStroke.Parent = sBox

            playerSlots.Boxes[i] = { Frame = sBox, Stroke = sStroke }
        end
    end

    ESPObjects[target] = {
        GUI = bg,
        Label = label,
        Slots = playerSlots,
        Highlight = nil,
        CanHighlight = target:IsA("Model") or target:IsA("BasePart"),
        Target = target,
        Part = adorneePart,
        Name = name,
        Color = color,
        IsPlayer = isPlayer,
        Category = category,
        Shown = false,
        HlOn = false,
        LastText = nil,
        LastTextColor = nil,
        SlotSig = nil,
        InvShown = nil,
        Hum = nil,
    }
end

local function ForceHideCategory(category)
    for _, data in pairs(ESPObjects) do
        if data.Category == category then
            data.Shown = false
            data.HlOn = false
            if data.GUI then data.GUI.Enabled = false end
            if data.Label then data.Label.Visible = false end
            if data.Highlight then data.Highlight.Enabled = false end
        end
    end
end

local function SetShown(data, shown, chams)
    if shown ~= data.Shown then
        data.Shown = shown
        data.GUI.Enabled = shown
        data.Label.Visible = shown
    end
    local wantHl = (shown and chams) and true or false
    if wantHl ~= data.HlOn then
        data.HlOn = wantHl
        if wantHl then EnsureHighlight(data) end
        if data.Highlight then data.Highlight.Enabled = wantHl end
    end
end

local function SetText(data, text, color)
    if data.LastText ~= text then
        data.LastText = text
        data.Label.Text = text
    end
    if color and data.LastTextColor ~= color then
        data.LastTextColor = color
        data.Label.TextColor3 = color
    end
end

local function UpdatePlayerHeadSlots(data, mainWep, secWep, meleeWep, holding)
    local slots = data.Slots
    if not slots then return end

    local showInv = Config.ShowPlayerInventory
    if data.InvShown ~= showInv then
        data.InvShown = showInv
        slots.Container.Visible = showInv
        data.GUI.Size = showInv and UDim2.fromOffset(150, 78) or UDim2.fromOffset(150, 36)
    end
    if not showInv then return end

    local sig = tostring(mainWep) .. "|" .. tostring(secWep) .. "|" .. tostring(meleeWep) .. "|" .. tostring(holding)
    if data.SlotSig == sig then return end
    data.SlotSig = sig

    local currentItems = { mainWep, secWep, meleeWep }
    for i = 1, 3 do
        local itemKey = currentItems[i]
        local box = slots.Boxes[i]

        if slots.Cached[i] ~= itemKey then
            slots.Cached[i] = itemKey
            box.Frame:ClearAllChildren()

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 5)
            corner.Parent = box.Frame

            box.Stroke = Instance.new("UIStroke")
            box.Stroke.Thickness = 1
            box.Stroke.Parent = box.Frame

            if itemKey and itemKey ~= "" and InvKit then
                pcall(function()
                    local icon = InvKit.icon(itemKey, { Size = UDim2.new(1, 0, 1, 0) })
                    if icon then icon.Parent = box.Frame end
                end)
            end
        end

        if itemKey and itemKey ~= "" then
            if holding ~= nil and holding == itemKey then
                box.Stroke.Color = Color3.fromRGB(255, 60, 60)
                box.Stroke.Thickness = 2
            else
                local def = Items and Items.Defs[itemKey]
                local rarity = def and def.rarity or "Common"
                local rColor = Items and Items.Rarity[rarity] and Items.Rarity[rarity].color or Color3.fromRGB(80, 90, 110)
                box.Stroke.Color = rColor
                box.Stroke.Thickness = 1
            end
        else
            box.Stroke.Color = Color3.fromRGB(45, 52, 70)
            box.Stroke.Thickness = 1
        end
    end
end

local function ApplyGunMods()
    for gunName, def in pairs(GunDefs) do
        if type(def) == "table" and OrigGunDefs[gunName] then
            local orig = OrigGunDefs[gunName]
            if Config.NoRecoil then
                def.recoil = 0
                def.climb = 0
            else
                def.recoil = orig.recoil
                def.climb = orig.climb
            end
            def.spread = Config.NoSpread and { 0, 0 } or orig.spread
            def.db = Config.SilentGuns and 0 or orig.db
            def.ads = Config.InstantADS and 0.01 or orig.ads
        end
    end
end

local FOVCircle = nil
pcall(function()
    if Drawing then
        FOVCircle = Drawing.new("Circle")
        FOVCircle.Thickness = 1.5
        FOVCircle.NumSides = 64
        FOVCircle.Radius = Config.FOVRadius
        FOVCircle.Filled = false
        FOVCircle.Visible = false
        FOVCircle.Color = Color3.fromRGB(255, 60, 90)
        FOVCircle.Transparency = 0.85
    end
end)

local WallParams = RaycastParams.new()
WallParams.FilterType = Enum.RaycastFilterType.Exclude

local function IsVisible(targetPart, targetModel)
    if not Config.WallCheck then return true end
    local origin = Camera.CFrame.Position
    local result = Workspace:Raycast(origin, targetPart.Position - origin, WallParams)
    return (not result) or result.Instance:IsDescendantOf(targetModel)
end

local function GetClosestTarget()
    local closestPart = nil
    local shortestDist = Config.FOVRadius
    local mousePos = UserInputService:GetMouseLocation()
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local originPos = myRoot and myRoot.Position or Camera.CFrame.Position
    local maxWorld = Config.PlayerMaxDist
    local wantPart = Config.TargetPart

    if Config.WallCheck then
        WallParams.FilterDescendantsInstances = { myChar, Camera, ESPFolder }
    end

    local function Consider(model)
        local part = model:FindFirstChild(wantPart)
            or model:FindFirstChild("Head")
            or model:FindFirstChild("HumanoidRootPart")
            or model.PrimaryPart
        if not (part and part:IsA("BasePart")) then return end

        local pos = part.Position
        if (pos - originPos).Magnitude > maxWorld then return end

        local sp, onScreen = Camera:WorldToViewportPoint(pos)
        if not onScreen then return end

        local screenDist = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
        if screenDist < shortestDist and IsVisible(part, model) then
            shortestDist = screenDist
            closestPart = part
        end
    end

    if Config.TargetPlayers then
        for _, plr in ipairs(Players:GetPlayers()) do
            local char = plr ~= LocalPlayer and plr.Character
            if char and char:GetAttribute("Downed") ~= true then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    Consider(char)
                end
            end
        end
    end

    if Config.TargetMonsters then
        local folder = Workspace:FindFirstChild("Monsters")
        if folder then
            for _, m in ipairs(folder:GetChildren()) do
                if m:IsA("Model") then Consider(m) end
            end
        end
    end

    return closestPart
end

local CurrentTargetPart = nil

pcall(function()
    if hookmetamethod and getnamecallmethod and not _G.HUSH_SILENTAIM_HOOKED then
        _G.HUSH_SILENTAIM_HOOKED = true
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            if self ~= Workspace or not isRunning or not Config.SilentAim then
                return oldNamecall(self, ...)
            end
            local target = CurrentTargetPart
            if not target or (checkcaller and checkcaller()) then
                return oldNamecall(self, ...)
            end

            local method = getnamecallmethod()
            if method == "Raycast" then
                local origin, _, params = ...
                if typeof(origin) == "Vector3" then
                    return oldNamecall(self, origin, (target.Position - origin).Unit * 1000, params)
                end
            elseif method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist" then
                local ray, a, b, c = ...
                if typeof(ray) == "Ray" then
                    local origin = ray.Origin
                    return oldNamecall(self, Ray.new(origin, (target.Position - origin).Unit * 1000), a, b, c)
                end
            end

            return oldNamecall(self, ...)
        end))
    end
end)

table.insert(HookConnections, ProximityPromptService.PromptShown:Connect(function(prompt)
    if Config.InstantInteract then
        prompt.HoldDuration = 0
    end
end))

local Library
local ok, result = pcall(function()
    local url = "https://raw.githubusercontent.com/sixfourshi/Games/refs/heads/main/fip?cb=" .. tostring(os.time())
    local chunk, compileErr = loadstring(game:HttpGet(url))
    if type(chunk) ~= "function" then
        error("library failed to compile: " .. tostring(compileErr), 0)
    end
    local lib = chunk()
    if type(lib) ~= "table" then
        error("library file did not return a table", 0)
    end
    return lib
end)

if not ok then
    error("failed to load UI library: " .. tostring(result), 0)
end
Library = result
Library:SetDefaultTheme("Rose")

local Window = Library:CreateWindow({
    Name = SCRIPT_NAME,
    LoadingSubtitle = SCRIPT_VERSION,
    ToggleUIKeybind = "RightControl",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "HushConfig",
        FileName = "visuals_v54",
    },
    ToggleButton = { Platform = "Mobile" },
    Home = {
        Title = "HUSH Master Hub",
        Tier = SCRIPT_VERSION,
        Discord = "https://discord.gg/example",
        Website = "https://example.com",
        Stats = { "Players", "Session", "FPS", "Ping" },
    },
})

local VisualsTab = Window:CreateTab({ Name = "Visuals", Icon = "eye" })
local CombatTab = Window:CreateTab({ Name = "Combat", Icon = "crosshair" })
local WorldTab = Window:CreateTab({ Name = "World", Icon = "sun" })
local PlayerTab = Window:CreateTab({ Name = "Mobility", Icon = "shield-check" })
local SettingsTab = Window:CreateTab({ Name = "Settings", Icon = "settings" })

local MonsterGroup = VisualsTab:AddLeftGroupbox({ Name = "Monsters & Threats", Icon = "skull" })
MonsterGroup:CreateToggle({
    Name = "Monster ESP", CurrentValue = false, Flag = "ToggleMonsters",
    Callback = function(val)
        Config.Monsters = val
        if not val then ForceHideCategory("Monster") end
    end,
})
MonsterGroup:CreateToggle({
    Name = "Monster Chams (Highlight)", CurrentValue = false, Flag = "ToggleMonsterChams",
    Callback = function(val) Config.MonsterChams = val end,
})
MonsterGroup:CreateToggle({
    Name = "Sentries ESP", CurrentValue = false, Flag = "ToggleSentries",
    Callback = function(val)
        Config.Sentries = val
        if not val then ForceHideCategory("Sentry") end
    end,
})
MonsterGroup:CreateToggle({
    Name = "Watchers ESP", CurrentValue = false, Flag = "ToggleWatchers",
    Callback = function(val)
        Config.Watchers = val
        if not val then ForceHideCategory("Watcher") end
    end,
})
MonsterGroup:CreateSlider({
    Name = "Monster Max Distance", Range = { 100, 3000 }, Increment = 50, CurrentValue = 1500, Flag = "MonsterMaxDist",
    Callback = function(val) Config.MonsterMaxDist = val end,
})

local PlayerGroup = VisualsTab:AddRightGroupbox({ Name = "Players", Icon = "users" })
PlayerGroup:CreateToggle({
    Name = "Player ESP", CurrentValue = true, Flag = "TogglePlayers",
    Callback = function(val)
        Config.Players = val
        if not val then ForceHideCategory("Player") end
    end,
})
PlayerGroup:CreateToggle({
    Name = "Player Chams (Highlight)", CurrentValue = false, Flag = "TogglePlayerChams",
    Callback = function(val) Config.PlayerChams = val end,
})
PlayerGroup:CreateToggle({
    Name = "Show Player Health (HP)", CurrentValue = true, Flag = "TogglePlayerHealth",
    Callback = function(val) Config.ShowPlayerHealth = val end,
})
PlayerGroup:CreateToggle({
    Name = "Show Player Inventory (3D Icons)", CurrentValue = true, Flag = "TogglePlayerInventory",
    Callback = function(val) Config.ShowPlayerInventory = val end,
})
PlayerGroup:CreateSlider({
    Name = "Player Max Distance", Range = { 100, 4000 }, Increment = 50, CurrentValue = 2000, Flag = "PlayerMaxDist",
    Callback = function(val) Config.PlayerMaxDist = val end,
})

local LootGroup = VisualsTab:AddLeftGroupbox({ Name = "Loot & Exits", Icon = "package" })
LootGroup:CreateToggle({
    Name = "Loot Bags ESP", CurrentValue = true, Flag = "ToggleLootBags",
    Callback = function(val)
        Config.LootBags = val
        if not val then ForceHideCategory("LootBag") end
    end,
})
LootGroup:CreateToggle({
    Name = "Loot Bags Chams (Glow)", CurrentValue = true, Flag = "ToggleLootChams",
    Callback = function(val) Config.LootChams = val end,
})
LootGroup:CreateToggle({
    Name = "Supply Drops ESP", CurrentValue = true, Flag = "ToggleSupplyDrops",
    Callback = function(val)
        Config.SupplyDrops = val
        if not val then ForceHideCategory("SupplyDrop") end
    end,
})
LootGroup:CreateToggle({
    Name = "Extraction Exits ESP", CurrentValue = true, Flag = "ToggleExits",
    Callback = function(val)
        Config.Exits = val
        if not val then ForceHideCategory("Exit") end
    end,
})
LootGroup:CreateSlider({
    Name = "Loot Max Distance", Range = { 100, 5000 }, Increment = 100, CurrentValue = 3000, Flag = "LootMaxDist",
    Callback = function(val) Config.LootMaxDist = val end,
})

local GunGroup = CombatTab:AddLeftGroupbox({ Name = "Gun Enhancements", Icon = "target" })
GunGroup:CreateToggle({
    Name = "No Recoil (ปืนไม่ดีด)", CurrentValue = true, Flag = "ToggleNoRecoil",
    Callback = function(val) Config.NoRecoil = val; ApplyGunMods() end,
})
GunGroup:CreateToggle({
    Name = "No Spread (กระสุนตรงเป้า 100%)", CurrentValue = true, Flag = "ToggleNoSpread",
    Callback = function(val) Config.NoSpread = val; ApplyGunMods() end,
})
GunGroup:CreateToggle({
    Name = "Silent Gunshots (ยิงปืนไร้เสียง)", CurrentValue = true, Flag = "ToggleSilentGuns",
    Callback = function(val) Config.SilentGuns = val; ApplyGunMods() end,
})
GunGroup:CreateToggle({
    Name = "Instant ADS (ยกปืนเล็งทันที)", CurrentValue = true, Flag = "ToggleInstantADS",
    Callback = function(val) Config.InstantADS = val; ApplyGunMods() end,
})

local AimGroup = CombatTab:AddRightGroupbox({ Name = "Aimbot & Silent Aim", Icon = "crosshair" })
AimGroup:CreateToggle({
    Name = "Enable Aimbot (คลิกขวาค้างล็อกเป้า)", CurrentValue = false, Flag = "ToggleAimbot",
    Callback = function(val) Config.Aimbot = val end,
})
AimGroup:CreateToggle({
    Name = "Enable Silent Aim (กระสุนเลี้ยวเข้าเป้า)", CurrentValue = false, Flag = "ToggleSilentAim",
    Callback = function(val) Config.SilentAim = val end,
})
AimGroup:CreateToggle({
    Name = "Target Players (ล็อกผู้เล่น)", CurrentValue = true, Flag = "ToggleTargetPlayers",
    Callback = function(val) Config.TargetPlayers = val end,
})
AimGroup:CreateToggle({
    Name = "Target Monsters (ล็อกผี/มอนสเตอร์)", CurrentValue = true, Flag = "ToggleTargetMonsters",
    Callback = function(val) Config.TargetMonsters = val end,
})
AimGroup:CreateToggle({
    Name = "Wall Check (เช็คกำแพงบัง)", CurrentValue = false, Flag = "ToggleWallCheck",
    Callback = function(val) Config.WallCheck = val end,
})
AimGroup:CreateDropdown({
    Name = "Target Part (จุดเล็ง)", Options = { "Head", "HumanoidRootPart" }, CurrentOption = "Head", Flag = "DropdownTargetPart",
    Callback = function(val) Config.TargetPart = type(val) == "table" and val[1] or val end,
})
AimGroup:CreateSlider({
    Name = "Aimbot Smoothness (ความสมูท)", Range = { 5, 100 }, Increment = 5, CurrentValue = 25, Flag = "SliderAimSmooth",
    Callback = function(val) Config.AimSmoothness = val / 100 end,
})
AimGroup:CreateToggle({
    Name = "Show FOV Circle (แสดงวงกลมระยะล็อก)", CurrentValue = true, Flag = "ToggleShowFOV",
    Callback = function(val) Config.ShowFOV = val end,
})
AimGroup:CreateSlider({
    Name = "FOV Radius (ขนาดวงกลม)", Range = { 30, 500 }, Increment = 10, CurrentValue = 150, Flag = "SliderFOVRadius",
    Callback = function(val) Config.FOVRadius = val end,
})

ApplyGunMods()

local LightGroup = WorldTab:AddLeftGroupbox({ Name = "Lighting & Atmosphere", Icon = "sun-medium" })

local function ClearLightingLocks()
    for _, conn in ipairs(LightingLocks) do
        if conn.Connected then conn:Disconnect() end
    end
    table.clear(LightingLocks)
end

local function ApplyFullbright()
    Lighting.Ambient = Color3.fromRGB(200, 200, 200)
    Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
    Lighting.Brightness = 2
    Lighting.GlobalShadows = false
end

local function ApplyClearVision()
    Lighting.FogEnd = 100000
    local atm = Lighting:FindFirstChildOfClass("Atmosphere")
    if atm then
        atm.Density = 0
        atm.Haze = 0
        atm.Glare = 0
    end
    local mood = Lighting:FindFirstChild("Mood")
    if mood and mood:IsA("PostEffect") then mood.Enabled = false end
    local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect") or Lighting:FindFirstChild("DepthOfField")
    if dof and dof:IsA("PostEffect") then dof.Enabled = false end
end

local function RefreshLightingLocks()
    ClearLightingLocks()

    if Config.Fullbright then
        ApplyFullbright()
        table.insert(LightingLocks, Lighting:GetPropertyChangedSignal("Ambient"):Connect(function()
            if Config.Fullbright then Lighting.Ambient = Color3.fromRGB(200, 200, 200) end
        end))
        table.insert(LightingLocks, Lighting:GetPropertyChangedSignal("OutdoorAmbient"):Connect(function()
            if Config.Fullbright then Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200) end
        end))
        table.insert(LightingLocks, Lighting:GetPropertyChangedSignal("Brightness"):Connect(function()
            if Config.Fullbright then Lighting.Brightness = 2 end
        end))
        table.insert(LightingLocks, Lighting:GetPropertyChangedSignal("GlobalShadows"):Connect(function()
            if Config.Fullbright then Lighting.GlobalShadows = false end
        end))
    else
        Lighting.Ambient = OrigLighting.Ambient
        Lighting.OutdoorAmbient = OrigLighting.OutdoorAmbient
        Lighting.Brightness = OrigLighting.Brightness
        Lighting.GlobalShadows = OrigLighting.GlobalShadows
    end

    if Config.ClearVision then
        ApplyClearVision()
        table.insert(LightingLocks, Lighting:GetPropertyChangedSignal("FogEnd"):Connect(function()
            if Config.ClearVision then Lighting.FogEnd = 100000 end
        end))
        local atm = Lighting:FindFirstChildOfClass("Atmosphere")
        if atm then
            table.insert(LightingLocks, atm:GetPropertyChangedSignal("Density"):Connect(function()
                if Config.ClearVision then atm.Density = 0 end
            end))
        end
    else
        local atm = Lighting:FindFirstChildOfClass("Atmosphere")
        if atm then atm.Density = 0.3 end
        local mood = Lighting:FindFirstChild("Mood")
        if mood and mood:IsA("PostEffect") then mood.Enabled = true end
        local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect") or Lighting:FindFirstChild("DepthOfField")
        if dof and dof:IsA("PostEffect") then dof.Enabled = true end
        Lighting.FogEnd = OrigLighting.FogEnd
    end
end

LightGroup:CreateToggle({
    Name = "Fullbright (สว่างจ้าทะลุทุกห้อง)", CurrentValue = false, Flag = "ToggleFullbright",
    Callback = function(val)
        Config.Fullbright = val
        RefreshLightingLocks()
    end,
})

LightGroup:CreateToggle({
    Name = "Clear Vision (ลบหมอก & ปิดความมืด)", CurrentValue = false, Flag = "ToggleClearVision",
    Callback = function(val)
        Config.ClearVision = val
        RefreshLightingLocks()
    end,
})

local CameraGroup = WorldTab:AddRightGroupbox({ Name = "Camera & View", Icon = "camera" })
CameraGroup:CreateToggle({
    Name = "Enable Custom FOV (เปิดใช้งานปรับ FOV)", CurrentValue = false, Flag = "ToggleCustomFOV",
    Callback = function(val)
        Config.EnableFOV = val
        if not val then Camera.FieldOfView = 70 end
    end,
})
CameraGroup:CreateSlider({
    Name = "Field of View (FOV)", Range = { 70, 120 }, Increment = 1, CurrentValue = 70, Flag = "SliderFOV",
    Callback = function(val)
        Config.CustomFOV = val
        if Config.EnableFOV then
            Camera.FieldOfView = val
        end
    end,
})

local MoveGroup = PlayerTab:AddLeftGroupbox({ Name = "Safe Movement", Icon = "shield-check" })

MoveGroup:CreateToggle({
    Name = "Infinite Stamina (วิ่งได้ตลอดกาล)", CurrentValue = true, Flag = "ToggleInfStamina",
    Callback = function(val)
        Config.InfiniteStamina = val
        if val then
            MovementTable.SprintDrain = 0
            MovementTable.StaminaRegen = 1000
            MovementTable.RegenDelay = 0
        else
            MovementTable.SprintDrain = 10
            MovementTable.StaminaRegen = 20
            MovementTable.RegenDelay = 0.8
        end
    end,
})

MovementTable.SprintDrain = 0
MovementTable.StaminaRegen = 1000
MovementTable.RegenDelay = 0

local noclipChar = nil
local noclipParts = {}
local noclipOrig = {}
local noclipConn = nil

local function RebuildNoclipParts(char)
    table.clear(noclipParts)
    table.clear(noclipOrig)
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    noclipChar = char
    if not char then return end
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then
            noclipParts[#noclipParts + 1] = d
            noclipOrig[d] = d.CanCollide
        end
    end
    noclipConn = char.DescendantAdded:Connect(function(d)
        if d:IsA("BasePart") then
            noclipParts[#noclipParts + 1] = d
            noclipOrig[d] = d.CanCollide
        end
    end)
end

local function RestoreCollision()
    for _, p in ipairs(noclipParts) do
        if p.Parent and noclipOrig[p] then p.CanCollide = true end
    end
end

MoveGroup:CreateToggle({
    Name = "Noclip (เดินทะลุกำแพง/ประตู)", CurrentValue = false, Flag = "ToggleNoclip",
    Callback = function(val)
        Config.Noclip = val
        if not val then RestoreCollision() end
    end,
})

local AutoGroup = PlayerTab:AddRightGroupbox({ Name = "Automation", Icon = "sparkles" })
AutoGroup:CreateToggle({
    Name = "Instant Interact (เก็บของ/เปิดตู้ 0 วิ)", CurrentValue = true, Flag = "ToggleInstantInteract",
    Callback = function(val) Config.InstantInteract = val end,
})

table.insert(HookConnections, RunService.Stepped:Connect(function()
    if not isRunning or not Config.Noclip then return end
    local char = LocalPlayer.Character
    if char ~= noclipChar then RebuildNoclipParts(char) end
    for i = 1, #noclipParts do
        local p = noclipParts[i]
        if p.CanCollide then p.CanCollide = false end
    end
end))
table.insert(HookConnections, { Disconnect = function()
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
end })

local Menu = SettingsTab:AddLeftGroupbox({ Name = "Menu Controls", Icon = "monitor" })
Menu:CreateKeybind({
    Name = "Toggle Menu Key", CurrentKeybind = "RightControl", Flag = "ToggleUIKey",
    Callback = function() end,
    OnChanged = function(key) Window:SetKeybind(key) end,
})
Menu:CreateButton({
    Name = "Unload Script", Icon = "power",
    Callback = function()
        Library:Confirm({
            Title = "Unload HUSH Script?",
            ConfirmText = "Unload",
            Callback = function()
                if _G.HUSH_UNLOAD then _G.HUSH_UNLOAD() end
            end,
        })
    end,
})

SettingsTab:CreateConfigManager({ Name = "Configs", Side = "Left" })
SettingsTab:CreateThemeManager({ Name = "Themes", Side = "Right" })

local function RegisterMonster(monster)
    if monster:IsA("Model") and not ESPObjects[monster] then
        local color = Color3.fromRGB(255, 60, 60)
        if monster.Name:find("Hound") then color = Color3.fromRGB(230, 60, 230)
        elseif monster.Name:find("Brute") then color = Color3.fromRGB(255, 120, 0) end
        CreateESP(monster, monster.Name, color, true, false, "Monster")
    end
end

local function RegisterLoot(loot)
    if not ESPObjects[loot] then
        CreateESP(loot, "Loot Bag", Color3.fromRGB(80, 255, 120), false, false, "LootBag")
    end
end

local function RegisterSupply(drop)
    if not ESPObjects[drop] then
        CreateESP(drop, "Supply Drop", Color3.fromRGB(255, 230, 70), drop:IsA("Model"), false, "SupplyDrop")
    end
end

local function RegisterPlayerChar(char, plr)
    if plr ~= LocalPlayer and char then
        task.spawn(function()
            task.wait(0.5)
            if isRunning and char.Parent then
                CreateESP(char, plr.DisplayName, Color3.fromRGB(255, 255, 255), true, true, "Player")
            end
        end)
    end
end

local function CreateSentry(s) CreateESP(s, s.Name, Color3.fromRGB(255, 210, 0), true, false, "Sentry") end
local function CreateWatcher(w) CreateESP(w, "Watcher", Color3.fromRGB(0, 230, 255), w:IsA("Model"), false, "Watcher") end

if Workspace:FindFirstChild("Monsters") then
    for _, m in ipairs(Workspace.Monsters:GetChildren()) do RegisterMonster(m) end
    table.insert(HookConnections, Workspace.Monsters.ChildAdded:Connect(RegisterMonster))
end

if Workspace:FindFirstChild("Sentries") then
    for _, s in ipairs(Workspace.Sentries:GetChildren()) do CreateSentry(s) end
    table.insert(HookConnections, Workspace.Sentries.ChildAdded:Connect(CreateSentry))
end

if Workspace:FindFirstChild("Watchers") then
    for _, w in ipairs(Workspace.Watchers:GetChildren()) do CreateWatcher(w) end
    table.insert(HookConnections, Workspace.Watchers.ChildAdded:Connect(CreateWatcher))
end

if Workspace:FindFirstChild("LootBags") then
    for _, l in ipairs(Workspace.LootBags:GetChildren()) do RegisterLoot(l) end
    table.insert(HookConnections, Workspace.LootBags.ChildAdded:Connect(RegisterLoot))
end

local function HookSupplyFolder(folder)
    if not folder then return end
    for _, d in ipairs(folder:GetChildren()) do RegisterSupply(d) end
    table.insert(HookConnections, folder.ChildAdded:Connect(RegisterSupply))
end
HookSupplyFolder(Workspace:FindFirstChild("SupplyDrops"))
HookSupplyFolder(Workspace:FindFirstChild("LocalSupply"))

local function HookPlayer(plr)
    if plr == LocalPlayer then return end
    if plr.Character then RegisterPlayerChar(plr.Character, plr) end
    table.insert(HookConnections, plr.CharacterAdded:Connect(function(char)
        RegisterPlayerChar(char, plr)
    end))
end
for _, p in ipairs(Players:GetPlayers()) do HookPlayer(p) end
table.insert(HookConnections, Players.PlayerAdded:Connect(HookPlayer))

if Workspace:FindFirstChild("Town") and Workspace.Town:FindFirstChild("Exits") then
    for _, exitFolder in ipairs(Workspace.Town.Exits:GetChildren()) do
        local extTarget = exitFolder:FindFirstChild("Extraction") or exitFolder
        CreateESP(extTarget, "Exit: " .. exitFolder.Name, Color3.fromRGB(0, 160, 255), extTarget:IsA("Model"), false, "Exit")
    end
end

local catRules = {
    Player = {}, Monster = {}, LootBag = {}, SupplyDrop = {}, Exit = {}, Sentry = {}, Watcher = {},
}

local function RefreshCategoryRules()
    local r = catRules
    r.Player.on, r.Player.dist, r.Player.chams = Config.Players, Config.PlayerMaxDist, Config.PlayerChams
    r.Monster.on, r.Monster.dist, r.Monster.chams = Config.Monsters, Config.MonsterMaxDist, Config.MonsterChams
    r.LootBag.on, r.LootBag.dist, r.LootBag.chams = Config.LootBags, Config.LootMaxDist, Config.LootChams
    r.SupplyDrop.on, r.SupplyDrop.dist, r.SupplyDrop.chams = Config.SupplyDrops, Config.LootMaxDist, Config.SupplyChams
    r.Exit.on, r.Exit.dist, r.Exit.chams = Config.Exits, 5000, false
    r.Sentry.on, r.Sentry.dist, r.Sentry.chams = Config.Sentries, Config.MonsterMaxDist, false
    r.Watcher.on, r.Watcher.dist, r.Watcher.chams = Config.Watchers, Config.MonsterMaxDist, false
end

local RED = Color3.fromRGB(255, 60, 60)

local function UpdateESP()
    RefreshCategoryRules()

    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local originPos = myRoot and myRoot.Position or (Camera and Camera.CFrame.Position or Vector3.zero)

    for target, data in pairs(ESPObjects) do
        if not target.Parent then
            RemoveESP(target)
        else
            local rule = catRules[data.Category]
            if not rule then
            elseif not rule.on then
                if data.Shown or data.HlOn then SetShown(data, false, false) end
            else
                local part = data.Part
                local pos
                if part and part.Parent then
                    pos = part.Position
                else
                    local newPart, newPos = GetTargetPartAndPos(target)
                    if not newPos then
                        RemoveESP(target)
                        continue
                    end
                    data.Part = newPart
                    if newPart then data.GUI.Adornee = newPart end
                    pos = newPos
                end

                local dist = math.floor((pos - originPos).Magnitude)
                if dist > rule.dist then
                    SetShown(data, false, false)
                else
                    if data.Category == "Player" then
                        local text = string.format("[%s] %dm", data.Name, dist)
                        local isDowned = target:GetAttribute("Downed") == true

                        if Config.ShowPlayerHealth then
                            if isDowned then
                                local bleedLeft = target:GetAttribute("BleedLeft")
                                local bleedStr = bleedLeft and string.format(" (Bleed: %.0fs)", bleedLeft) or ""
                                text = text .. "\n[DOWNED]" .. bleedStr
                            else
                                local hum = data.Hum
                                if not hum or not hum.Parent then
                                    hum = target:FindFirstChildOfClass("Humanoid")
                                    data.Hum = hum
                                end
                                if hum then
                                    text = text .. string.format("\nHP: %d/%d", math.floor(hum.Health), math.floor(hum.MaxHealth))
                                end
                            end
                        end

                        SetText(data, text, isDowned and RED or data.Color)
                        UpdatePlayerHeadSlots(
                            data,
                            target:GetAttribute("SlotMain"),
                            target:GetAttribute("SlotSecondary"),
                            target:GetAttribute("SlotMelee"),
                            target:GetAttribute("Gun")
                        )
                    elseif data.Category == "LootBag" then
                        SetText(data, string.format("[Loot Bag]\n%dm", dist))
                    elseif data.Category == "SupplyDrop" then
                        SetText(data, string.format("[Supply Drop]\n%dm", dist))
                    elseif data.Category == "Watcher" then
                        SetText(data, string.format("[Watcher]\n%dm", dist))
                    else
                        SetText(data, string.format("[%s]\n%dm", data.Name, dist))
                    end

                    SetShown(data, true, rule.chams)
                end
            end
        end
    end
end

local espAccum = 0
table.insert(HookConnections, RunService.Heartbeat:Connect(function(dt)
    if not isRunning then return end
    espAccum += dt
    if espAccum < ESP_INTERVAL then return end
    espAccum = 0
    UpdateESP()
end))

local lastTargetScan = 0
local renderConnection
renderConnection = RunService.RenderStepped:Connect(function()
    if not isRunning then return end

    local aimActive = Config.Aimbot or Config.SilentAim

    if FOVCircle then
        local show = Config.ShowFOV and aimActive
        if show then
            FOVCircle.Position = UserInputService:GetMouseLocation()
            FOVCircle.Radius = Config.FOVRadius
        end
        if FOVCircle.Visible ~= show then FOVCircle.Visible = show end
    end

    if aimActive then
        local now = os.clock()
        if now - lastTargetScan >= TARGET_INTERVAL then
            lastTargetScan = now
            CurrentTargetPart = GetClosestTarget()
        end
        if CurrentTargetPart and not CurrentTargetPart.Parent then
            CurrentTargetPart = nil
        end
    else
        CurrentTargetPart = nil
    end

    local isAimingKey = UserInputService:IsMouseButtonPressed(Config.AimKey)

    if Config.Aimbot and CurrentTargetPart and isAimingKey then
        local camCF = Camera.CFrame
        Camera.CFrame = camCF:Lerp(CFrame.new(camCF.Position, CurrentTargetPart.Position), Config.AimSmoothness)
    end

    if Config.EnableFOV and not isAimingKey then
        if Camera.FieldOfView ~= Config.CustomFOV then
            Camera.FieldOfView = Config.CustomFOV
        end
    end
end)

_G.HUSH_UNLOAD = function()
    isRunning = false
    ClearLightingLocks()
    if renderConnection then renderConnection:Disconnect() end
    for _, conn in ipairs(HookConnections) do
        if conn and conn.Disconnect then pcall(function() conn:Disconnect() end) end
    end
    RestoreCollision()
    for target in pairs(ESPObjects) do RemoveESP(target) end
    if ESPFolder and ESPFolder.Parent then ESPFolder:Destroy() end
    if FOVCircle then pcall(function() FOVCircle:Remove() end) end

    local camLight = Camera:FindFirstChild("FullbrightLight")
    if camLight then camLight:Destroy() end

    pcall(function()
        Lighting.Ambient = OrigLighting.Ambient
        Lighting.OutdoorAmbient = OrigLighting.OutdoorAmbient
        Lighting.Brightness = OrigLighting.Brightness
        Lighting.GlobalShadows = OrigLighting.GlobalShadows
        Lighting.FogEnd = OrigLighting.FogEnd
        local atm = Lighting:FindFirstChildOfClass("Atmosphere")
        if atm then atm.Density = 0.3 end
        local mood = Lighting:FindFirstChild("Mood")
        if mood and mood:IsA("PostEffect") then mood.Enabled = true end
        local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect") or Lighting:FindFirstChild("DepthOfField")
        if dof and dof:IsA("PostEffect") then dof.Enabled = true end
        Camera.FieldOfView = 70

        for gunName, orig in pairs(OrigGunDefs) do
            local def = GunDefs[gunName]
            if def then
                def.recoil = orig.recoil
                def.climb = orig.climb
                def.spread = orig.spread
                def.db = orig.db
                def.ads = orig.ads
            end
        end

        MovementTable.SprintDrain = 10
        MovementTable.StaminaRegen = 20
        MovementTable.RegenDelay = 0.8
    end)

    pcall(function() Window:Destroy() end)
    _G.HUSH_UNLOAD = nil
end

Window:LoadAutoload()

Library:Notify({
    Title = SCRIPT_NAME,
    Content = "HUSH Master Hub v5.4 (Anti-Flicker) Loaded!",
    Type = "Success",
    Duration = 3,
})
