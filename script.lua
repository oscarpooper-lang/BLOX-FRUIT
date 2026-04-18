-- PHANTOM ENGINE v4.2

-- step-by-step debug
print("[Phantom] Script received, starting init...")

-- anti-double-load
pcall(function()
    if type(getgenv) == "function" then
        if getgenv().PhantomLoaded then
            pcall(function()
                local cg = game:FindFirstChild("CoreGui") or game:GetService("CoreGui")
                if cg then
                    local old = cg:FindFirstChild("PhantomEngine")
                    if old then old:Destroy() end
                end
                -- also check PlayerGui
                local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
                if pg then
                    local old2 = pg:FindFirstChild("PhantomEngine")
                    if old2 then old2:Destroy() end
                end
            end)
            task.wait(0.3)
        end
        getgenv().PhantomLoaded = true
    end
end)

print("[Phantom] Step 1: Anti-double-load OK")

-- services
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

print("[Phantom] Step 2: Core services OK")

local Player = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- VirtualInputManager — not all executors have this
local VirtualInput
pcall(function() VirtualInput = game:GetService("VirtualInputManager") end)
if not VirtualInput then
    print("[Phantom] WARN: VirtualInputManager not available, using mouse1click fallback")
end

-- GUI parent — executor compat: try gethui > CoreGui > PlayerGui
local GuiParent
pcall(function()
    if type(gethui) == "function" then
        GuiParent = gethui()
        print("[Phantom] GUI parent: gethui()")
    end
end)
if not GuiParent then
    pcall(function()
        if type(syn) == "table" and syn.protect_gui then
            GuiParent = game:GetService("CoreGui")
            print("[Phantom] GUI parent: CoreGui (syn)")
        end
    end)
end
if not GuiParent then
    local ok = pcall(function()
        -- test if we can parent to CoreGui
        local test = Instance.new("Folder")
        test.Parent = game:GetService("CoreGui")
        test:Destroy()
        GuiParent = game:GetService("CoreGui")
    end)
    if ok and GuiParent then
        print("[Phantom] GUI parent: CoreGui (direct)")
    end
end
if not GuiParent then
    GuiParent = Player:WaitForChild("PlayerGui")
    print("[Phantom] GUI parent: PlayerGui (fallback)")
end

print("[Phantom] Step 3: GUI parent resolved")

-- ══════════════════════════════════════════════════════════
-- ENTITY CACHE — scans once, updates on add/remove
-- This is the #1 performance fix. No more GetDescendants() spam.
-- ══════════════════════════════════════════════════════════
local Cache = {
    Mobs = {},       -- enemy models with humanoid
    Fruits = {},     -- fruit objects in workspace
    Chests = {},     -- chest objects
    Flowers = {},    -- flower objects
    NPCs = {},       -- quest NPCs
    _connections = {},
}

local function CategorizeObject(obj)
    pcall(function()
        -- fruits
        if (obj:IsA("Tool") or obj:IsA("Model")) and obj.Name:find("Fruit") then
            Cache.Fruits[obj] = true
            return
        end
        
        -- chests
        if obj:IsA("BasePart") and obj.Name:find("Chest") then
            Cache.Chests[obj] = true
            return
        end
        
        -- flowers
        if obj:IsA("BasePart") and (obj.Name:find("Flower") or obj.Name:find("flower")) then
            Cache.Flowers[obj] = true
            return
        end
    end)
end

-- Initial scan (one-time)
task.spawn(function()
    for _, obj in ipairs(workspace:GetDescendants()) do
        CategorizeObject(obj)
        if _ % 500 == 0 then task.wait() end -- yield every 500 objects to prevent freeze
    end
end)

-- Live updates — new objects get categorized automatically
workspace.DescendantAdded:Connect(CategorizeObject)
workspace.DescendantRemoving:Connect(function(obj)
    Cache.Fruits[obj] = nil
    Cache.Chests[obj] = nil
    Cache.Flowers[obj] = nil
end)

-- ══════════════════════════════════════════════════════════
-- CONFIG
-- ══════════════════════════════════════════════════════════
local Config = {
    AutoFarm = false,
    AutoFarmMode = "Quest",
    SelectedQuest = nil,
    AutoQuestAccept = true,
    MobAura = false,
    MobAuraRange = 300,
    BringMobs = true,
    BringMobsRange = 100,
    FastAttack = true,
    SelectedWeapon = nil, -- name of weapon to equip from backpack
    AttackSpeed = 0.1,
    
    FruitSniper = false,
    FruitSniperMode = "Any",
    AutoStoreFruit = false,
    AutoEatFruit = false,
    MasteryFarm = false,
    
    AutoStats = false,
    StatMode = "Melee",
    
    KillAura = false,
    KillAuraRange = 50,
    InfiniteEnergy = false,
    AutoBuso = false,
    AutoHaki = false,
    
    AutoRaid = false,
    RaidFruit = "Buddha",
    
    Speed = false,
    SpeedValue = 150,
    Fly = false,
    FlySpeed = 200,
    Noclip = false,
    
    ESP = false,
    ESPPlayers = false,
    ESPFruits = true,
    ESPChests = false,
    ESPFlowers = false,
    ESPNPCs = false,
    ESPBoss = true,
    
    AutoSeaBeast = false,
    AutoBountyHunt = false,
    AutoCollectChests = false,
    AutoCollectFlowers = false,
    AntiAFK = true,
    FullBright = false,
    NoFog = false,
    InfiniteJump = false,
    
    _running = true,
    _guiOpen = true,
}

-- ══════════════════════════════════════════════════════════
-- ISLAND DATA
-- ══════════════════════════════════════════════════════════
local SeaData = {
    First = {
        {Name="Pirate Starter", Level=1, Quest="PirateStarterQuest", NPC="Pirate", Mob="Bandit", CFrame=CFrame.new(1060,16,1548)},
        {Name="Jungle", Level=15, Quest="JungleQuest", NPC="Jungle Sign", Mob="Monkey", CFrame=CFrame.new(-1595,37,154)},
        {Name="Pirate Village", Level=30, Quest="PirateVillageQuest", NPC="Pirate Village Sign", Mob="Pirate", CFrame=CFrame.new(-1141,5,3830)},
        {Name="Desert", Level=60, Quest="DesertQuest", NPC="Desert Sign", Mob="Desert Bandit", CFrame=CFrame.new(940,21,4325)},
        {Name="Frozen Village", Level=90, Quest="FrozenVillageQuest", NPC="Frozen Village Sign", Mob="Snow Bandit", CFrame=CFrame.new(1352,88,-1305)},
        {Name="Marine Fortress", Level=120, Quest="MarineFortressQuest", NPC="Marine Fortress Sign", Mob="Marine Lieutenant", CFrame=CFrame.new(-4607,16,4210)},
        {Name="Skylands", Level=150, Quest="SkyQuest", NPC="Sky Sign", Mob="Sky Bandit", CFrame=CFrame.new(-4869,734,-2621)},
        {Name="Prison", Level=190, Quest="PrisonQuest", NPC="Prison Sign", Mob="Dangerous Prisoner", CFrame=CFrame.new(4640,15,745)},
        {Name="Colosseum", Level=225, Quest="ColosseumQuest", NPC="Colosseum Sign", Mob="Toga Warrior", CFrame=CFrame.new(-1454,7,-3015)},
        {Name="Magma Village", Level=300, Quest="MagmaQuest", NPC="Magma Sign", Mob="Magma Ninja", CFrame=CFrame.new(-5310,13,8515)},
        {Name="Underwater City", Level=375, Quest="UnderwaterQuest", NPC="Underwater Sign", Mob="Fishman Warrior", CFrame=CFrame.new(61162,12,1819)},
        {Name="Upper Yard", Level=450, Quest="UpperYardQuest", NPC="Upper Yard Sign", Mob="God's Guard", CFrame=CFrame.new(-4811,826,-1961)},
        {Name="Fountain City", Level=625, Quest="FountainQuest", NPC="Fountain Sign", Mob="Galley Captain", CFrame=CFrame.new(5131,5,4099)},
    },
    Second = {
        {Name="Kingdom of Rose", Level=700, Quest="RoseQuest", NPC="Rose Sign", Mob="Swan Pirate", CFrame=CFrame.new(-2262,73,-10152)},
        {Name="Green Zone", Level=875, Quest="GreenZoneQuest", NPC="Green Zone Sign", Mob="Forest Pirate", CFrame=CFrame.new(-2439,73,-3298)},
        {Name="Graveyard", Level=950, Quest="GraveyardQuest", NPC="Graveyard Sign", Mob="Reborn Skeleton", CFrame=CFrame.new(-5765,210,-797)},
        {Name="Snow Mountain", Level=1000, Quest="SnowMountainQuest", NPC="Snow Mountain Sign", Mob="Arctic Warrior", CFrame=CFrame.new(605,400,-5251)},
        {Name="Hot and Cold", Level=1100, Quest="HotColdQuest", NPC="Hot and Cold Sign", Mob="Lava Pirate", CFrame=CFrame.new(-5765,73,-5279)},
        {Name="Cursed Ship", Level=1250, Quest="CursedShipQuest", NPC="Cursed Ship Sign", Mob="Cursed Captain", CFrame=CFrame.new(916,125,33244)},
        {Name="Ice Castle", Level=1350, Quest="IceCastleQuest", NPC="Ice Castle Sign", Mob="Ice Admiral", CFrame=CFrame.new(6125,294,-6867)},
        {Name="Forgotten Island", Level=1425, Quest="ForgottenIslandQuest", NPC="Forgotten Sign", Mob="Ancient Pirate", CFrame=CFrame.new(-3058,316,-10119)},
    },
    Third = {
        {Name="Port Town", Level=1500, Quest="PortTownQuest", NPC="Port Town Sign", Mob="Pirate Millionaire", CFrame=CFrame.new(-290,43,5323)},
        {Name="Hydra Island", Level=1575, Quest="HydraQuest", NPC="Hydra Sign", Mob="Hydra Warrior", CFrame=CFrame.new(-5260,313,-2820)},
        {Name="Great Tree", Level=1700, Quest="GreatTreeQuest", NPC="Great Tree Sign", Mob="Jungle Pirate", CFrame=CFrame.new(2377,25,-7058)},
        {Name="Floating Turtle", Level=1775, Quest="FloatingTurtleQuest", NPC="Floating Turtle Sign", Mob="Marine Commodore", CFrame=CFrame.new(-12892,332,-7978)},
        {Name="Castle on the Sea", Level=1825, Quest="CastleSeaQuest", NPC="Castle Sign", Mob="Pirate Raid", CFrame=CFrame.new(-5026,313,-2830)},
        {Name="Haunted Castle", Level=1975, Quest="HauntedQuest", NPC="Haunted Sign", Mob="Haunted Spirit", CFrame=CFrame.new(-9515,145,5765)},
        {Name="Tiki Outpost", Level=2075, Quest="TikiQuest", NPC="Tiki Sign", Mob="Tiki Warrior", CFrame=CFrame.new(-12105,375,-6225)},
        {Name="Mansion", Level=2175, Quest="MansionQuest", NPC="Mansion Sign", Mob="Vampire", CFrame=CFrame.new(-6295,375,-4890)},
    },
}

local FruitTiers = {
    Mythical = {"Leopard","Dragon","Spirit","Control","Venom","Dough","T-Rex","Mammoth","Kitsune"},
    Legendary = {"Buddha","Phoenix","Rumble","Pain","Gravity","Shadow","Quake","Dark","Sound","Blizzard"},
    Rare = {"Magma","Light","Ice","Flame","String","Door","Barrier","Love","Portal"},
    Uncommon = {"Chop","Spring","Bomb","Smoke","Spike","Spin","Falcon","Diamond","Rubber"},
}

-- ══════════════════════════════════════════════════════════
-- UTILITIES
-- ══════════════════════════════════════════════════════════
local function GetHRP()
    local c = Player.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function GetHum()
    local c = Player.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function Dist(a, b)
    if not a or not b then return math.huge end
    local p1 = typeof(a) == "CFrame" and a.Position or (typeof(a) == "Vector3" and a or a.Position)
    local p2 = typeof(b) == "CFrame" and b.Position or (typeof(b) == "Vector3" and b or b.Position)
    return (p1 - p2).Magnitude
end

local function TweenTo(target, speed)
    local hrp = GetHRP()
    if not hrp then return end
    local pos = typeof(target) == "CFrame" and target or CFrame.new(target)
    local time = math.clamp(Dist(hrp.CFrame, pos) / (speed or 300), 0.05, 12)
    local tw = TweenService:Create(hrp, TweenInfo.new(time, Enum.EasingStyle.Linear), {CFrame = pos})
    tw:Play()
    return tw
end

local function TweenWait(target, speed)
    local tw = TweenTo(target, speed)
    if tw then tw.Completed:Wait() end
end

local function Notify(title, text, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification", {Title = title, Text = text, Duration = dur or 3})
    end)
end

local function GetLevel()
    -- try multiple Blox Fruits level sources
    pcall(function()
        local plrData = Player:FindFirstChild("Data")
        if plrData then
            local lvl = plrData:FindFirstChild("Level")
            if lvl then return lvl.Value end
        end
    end)
    -- fallback: parse from GUI
    pcall(function()
        local main = Player.PlayerGui:FindFirstChild("Main")
        if main then
            local lvlText = main:FindFirstChild("Level", true)
            if lvlText and lvlText:IsA("TextLabel") then
                local num = tonumber(lvlText.Text:match("%d+"))
                if num then return num end
            end
        end
    end)
    return 1
end

local function GetRemotes()
    local r = RS:FindFirstChild("Remotes")
    return r and r:FindFirstChild("CommF_")
end

-- ══════════════════════════════════════════════════════════
-- WEAPON SYSTEM
-- ══════════════════════════════════════════════════════════
local Weapon = {}

function Weapon.GetAll()
    local weapons = {}
    local backpack = Player:FindFirstChild("Backpack")
    local char = Player.Character
    
    if backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") then
                table.insert(weapons, tool.Name)
            end
        end
    end
    -- also check currently equipped
    if char then
        for _, tool in ipairs(char:GetChildren()) do
            if tool:IsA("Tool") then
                -- add if not already in list
                local found = false
                for _, n in ipairs(weapons) do
                    if n == tool.Name then found = true break end
                end
                if not found then table.insert(weapons, tool.Name) end
            end
        end
    end
    return weapons
end

function Weapon.Equip(weaponName)
    if not weaponName then return false end
    local char = Player.Character
    if not char then return false end
    
    -- already equipped?
    if char:FindFirstChild(weaponName) then return true end
    
    local backpack = Player:FindFirstChild("Backpack")
    if backpack then
        local tool = backpack:FindFirstChild(weaponName)
        if tool and tool:IsA("Tool") then
            pcall(function()
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum:EquipTool(tool) end
            end)
            task.wait(0.1)
            return char:FindFirstChild(weaponName) ~= nil
        end
    end
    return false
end

function Weapon.GetEquipped()
    local char = Player.Character
    if char then
        for _, tool in ipairs(char:GetChildren()) do
            if tool:IsA("Tool") then return tool end
        end
    end
    return nil
end

function Weapon.Unequip()
    pcall(function()
        local char = Player.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum:UnequipTools() end
        end
    end)
end

-- ══════════════════════════════════════════════════════════
-- ANTI-AFK (lightweight, event-based)
-- ══════════════════════════════════════════════════════════
Player.Idled:Connect(function()
    if not Config.AntiAFK or not VirtualInput then return end
    pcall(function()
        VirtualInput:SendKeyEvent(true, Enum.KeyCode.W, false, game)
        task.wait(0.1)
        VirtualInput:SendKeyEvent(false, Enum.KeyCode.W, false, game)
    end)
end)

-- ══════════════════════════════════════════════════════════
-- QUEST MODULE (Blox Fruits specific)
-- ══════════════════════════════════════════════════════════
local Quest = {}

function Quest.GetBest()
    local lvl = GetLevel()
    local best = nil
    for _, sea in pairs({"First", "Second", "Third"}) do
        if SeaData[sea] then
            for _, q in ipairs(SeaData[sea]) do
                if lvl >= q.Level then best = q end
            end
        end
    end
    return best
end

function Quest.HasActive()
    -- method 1: check quest GUI element
    local found = false
    pcall(function()
        local g = Player.PlayerGui:FindFirstChild("Main")
        if g then
            local q = g:FindFirstChild("Quest", true)
            if q and q.Visible then found = true return end
            -- also check for quest progress text elements
            for _, desc in ipairs(g:GetDescendants()) do
                if desc:IsA("TextLabel") and desc.Visible then
                    local txt = desc.Text:lower()
                    if txt:find("defeat") or txt:find("kill") or txt:find("collect") or txt:find("/") then
                        -- looks like a quest objective "Defeat 0/5 Bandits"
                        if txt:match("%d+/%d+") then
                            found = true
                            return
                        end
                    end
                end
            end
        end
    end)
    return found
end

function Quest.IsComplete()
    -- check if quest objective shows X/X (complete)
    local complete = false
    pcall(function()
        local g = Player.PlayerGui:FindFirstChild("Main")
        if g then
            for _, desc in ipairs(g:GetDescendants()) do
                if desc:IsA("TextLabel") and desc.Visible then
                    local current, total = desc.Text:match("(%d+)/(%d+)")
                    if current and total and tonumber(current) >= tonumber(total) and tonumber(total) > 0 then
                        complete = true
                        return
                    end
                end
            end
        end
    end)
    return complete
end

function Quest.Accept(data)
    if not data then return false end
    
    -- tween to quest NPC area
    TweenWait(data.CFrame + Vector3.new(0, 20, 0), 350)
    task.wait(0.5)
    
    local remote = GetRemotes()
    if remote then
        -- try the standard Blox Fruits quest start
        pcall(function()
            remote:InvokeServer("StartQuest", data.Quest, data.Level)
        end)
        task.wait(0.3)
        
        -- also try alternative quest format
        pcall(function()
            remote:InvokeServer("StartQuest", data.Quest, 1)
        end)
        task.wait(0.5)
        return true
    end
    return false
end

-- ══════════════════════════════════════════════════════════
-- COMBAT (uses workspace.Enemies + real weapon attacks)
-- ══════════════════════════════════════════════════════════
local Combat = {}

function Combat.Nearest(range, filter)
    local hrp = GetHRP()
    if not hrp then return nil, math.huge end
    local best, bestD = nil, range or 500
    
    local enemiesFolder = workspace:FindFirstChild("Enemies")
    if not enemiesFolder then return nil, math.huge end
    
    for _, mob in ipairs(enemiesFolder:GetChildren()) do
        if mob:IsA("Model") and mob:FindFirstChild("HumanoidRootPart") and mob:FindFirstChild("Humanoid") then
            local hum = mob.Humanoid
            if hum.Health > 0 then
                if filter and not mob.Name:lower():find(filter:lower()) then continue end
                local d = Dist(hrp, mob.HumanoidRootPart)
                if d < bestD then best, bestD = mob, d end
            end
        end
    end
    return best, bestD
end

function Combat.BringMob(mob, off)
    if not mob or not mob:FindFirstChild("HumanoidRootPart") then return end
    local hrp = GetHRP()
    if not hrp then return end
    pcall(function()
        mob.HumanoidRootPart.CFrame = hrp.CFrame * (off or CFrame.new(0, -15, 0))
        mob.HumanoidRootPart.Velocity = Vector3.new(0, 0, 0)
        mob.HumanoidRootPart.CanCollide = false
    end)
end

function Combat.BringAll(range)
    local hrp = GetHRP()
    if not hrp then return end
    
    local enemiesFolder = workspace:FindFirstChild("Enemies")
    if not enemiesFolder then return end
    
    for _, mob in ipairs(enemiesFolder:GetChildren()) do
        if mob:IsA("Model") and mob:FindFirstChild("HumanoidRootPart") and mob:FindFirstChild("Humanoid") then
            if mob.Humanoid.Health > 0 and Dist(hrp, mob.HumanoidRootPart) < (range or 100) then
                Combat.BringMob(mob)
            end
        end
    end
end

-- equip selected weapon and attack with it
function Combat.EnsureWeapon()
    if Config.SelectedWeapon then
        Weapon.Equip(Config.SelectedWeapon)
    else
        -- auto-equip first weapon if none selected
        local equipped = Weapon.GetEquipped()
        if not equipped then
            local all = Weapon.GetAll()
            if #all > 0 then
                Weapon.Equip(all[1])
            end
        end
    end
end

function Combat.Attack()
    -- method 1: activate equipped tool (works for swords, guns, fighting styles)
    pcall(function()
        local tool = Weapon.GetEquipped()
        if tool then
            tool:Activate()
        end
    end)
    
    -- method 2: also send VIM click as backup (some weapons respond to this)
    if VirtualInput then
        pcall(function()
            VirtualInput:SendMouseButtonEvent(0, 0, 0, true, game, 1)
            task.wait()
            VirtualInput:SendMouseButtonEvent(0, 0, 0, false, game, 1)
        end)
    end
end

function Combat.FastAttack()
    Combat.EnsureWeapon()
    for _ = 1, 5 do
        Combat.Attack()
        task.wait(Config.AttackSpeed or 0.1)
    end
end

function Combat.Skill(key)
    if VirtualInput then
        pcall(function()
            VirtualInput:SendKeyEvent(true, key, false, game)
            task.wait(0.1)
            VirtualInput:SendKeyEvent(false, key, false, game)
        end)
    end
end

function Combat.UseAllSkills()
    Combat.Skill(Enum.KeyCode.Z)
    task.wait(0.15)
    Combat.Skill(Enum.KeyCode.X)
    task.wait(0.15)
    Combat.Skill(Enum.KeyCode.C)
    task.wait(0.15)
    Combat.Skill(Enum.KeyCode.V)
    task.wait(0.15)
    Combat.Skill(Enum.KeyCode.F)
end

-- ══════════════════════════════════════════════════════════
-- FRUIT SNIPER (uses Cache.Fruits — no scanning)
-- ══════════════════════════════════════════════════════════
local Sniper = {}

function Sniper.GetTier(name)
    for tier, list in pairs(FruitTiers) do
        for _, f in ipairs(list) do
            if name:lower():find(f:lower()) then return tier end
        end
    end
    return "Common"
end

function Sniper.Scan()
    local results = {}
    for obj in pairs(Cache.Fruits) do
        if obj.Parent then
            local part = obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart"))
                       or obj:FindFirstChild("Handle")
            if part then
                table.insert(results, {
                    Object = obj, Name = obj.Name,
                    Tier = Sniper.GetTier(obj.Name),
                    Position = part.Position,
                })
            end
        else
            Cache.Fruits[obj] = nil
        end
    end
    return results
end

function Sniper.Grab(data)
    if not data or not data.Object or not data.Object.Parent then return false end
    Notify("Sniper", "Grabbing " .. data.Name .. " (" .. data.Tier .. ")")
    TweenWait(CFrame.new(data.Position + Vector3.new(0, 5, 0)), 500)
    task.wait(0.3)
    for _, d in ipairs(data.Object:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            pcall(fireproximityprompt, d)
            task.wait(0.5)
            return true
        end
    end
    -- fallback touch
    local hrp = GetHRP()
    if hrp then hrp.CFrame = CFrame.new(data.Position) end
    task.wait(0.5)
    return true
end

-- ══════════════════════════════════════════════════════════
-- STATS
-- ══════════════════════════════════════════════════════════
local function AutoStats()
    if not Config.AutoStats then return end
    local remote = GetRemotes()
    if not remote then return end
    local d = Player:FindFirstChild("Data")
    if not d then return end
    local pts = d:FindFirstChild("Points")
    if not pts or pts.Value <= 0 then return end
    remote:InvokeServer("AddPoint", Config.StatMode, pts.Value)
end

-- ══════════════════════════════════════════════════════════
-- ESP (BillboardGui based, lazy refresh)
-- ══════════════════════════════════════════════════════════
local ESP = { _items = {} }

function ESP.Clear()
    for _, v in ipairs(ESP._items) do
        if v.Gui then v.Gui:Destroy() end
        if v.Conn then v.Conn:Disconnect() end
    end
    ESP._items = {}
end

function ESP.Add(part, text, color)
    if not part or not part.Parent then return end
    local bb = Instance.new("BillboardGui")
    bb.Name = "PE_" .. text
    bb.Adornee = part
    bb.Size = UDim2.new(0, 200, 0, 50)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.Parent = GuiParent
    
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = color or Color3.new(1,1,1)
    lbl.TextStrokeTransparency = 0.3
    lbl.TextScaled = true
    lbl.Font = Enum.Font.GothamBold
    lbl.Text = text
    lbl.Parent = bb
    
    -- update distance every 0.5s instead of every frame
    local conn
    conn = task.spawn(function()
        while bb.Parent and part.Parent and Config._running do
            local hrp = GetHRP()
            if hrp then
                lbl.Text = text .. " [" .. math.floor(Dist(hrp, part)) .. "m]"
            end
            task.wait(0.5)
        end
        bb:Destroy()
    end)
    
    table.insert(ESP._items, {Gui = bb, Conn = nil}) -- conn is a thread, no disconnect needed
end

function ESP.Refresh()
    ESP.Clear()
    if not Config.ESP then return end
    
    if Config.ESPPlayers then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= Player and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                ESP.Add(p.Character.HumanoidRootPart, p.Name, Color3.fromRGB(255, 50, 50))
            end
        end
    end
    
    if Config.ESPFruits then
        for obj in pairs(Cache.Fruits) do
            if obj.Parent then
                local part = obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart"))
                           or obj:FindFirstChild("Handle")
                if part then
                    local tier = Sniper.GetTier(obj.Name)
                    local col = tier == "Mythical" and Color3.fromRGB(255,0,255)
                        or tier == "Legendary" and Color3.fromRGB(255,215,0)
                        or tier == "Rare" and Color3.fromRGB(0,150,255)
                        or Color3.fromRGB(100,255,100)
                    ESP.Add(part, obj.Name .. " (" .. tier .. ")", col)
                end
            end
        end
    end
    
    if Config.ESPChests then
        for obj in pairs(Cache.Chests) do
            if obj.Parent then
                ESP.Add(obj, "Chest", Color3.fromRGB(255, 200, 0))
            end
        end
    end
    
    if Config.ESPFlowers then
        for obj in pairs(Cache.Flowers) do
            if obj.Parent then
                ESP.Add(obj, obj.Name, Color3.fromRGB(255, 150, 200))
            end
        end
    end
    
    if Config.ESPBoss then
        local enemiesFolder = workspace:FindFirstChild("Enemies")
        if enemiesFolder then
            for _, mob in ipairs(enemiesFolder:GetChildren()) do
                if mob:IsA("Model") and mob:FindFirstChild("Humanoid") and mob:FindFirstChild("HumanoidRootPart") then
                    if mob.Humanoid.MaxHealth >= 50000 and mob.Humanoid.Health > 0 then
                        ESP.Add(mob.HumanoidRootPart, "BOSS: " .. mob.Name, Color3.fromRGB(255, 0, 0))
                    end
                end
            end
        end
    end
end

-- ══════════════════════════════════════════════════════════
-- MOVEMENT
-- ══════════════════════════════════════════════════════════
local Move = { _speedConn = nil, _flyConn = nil, _noclipConn = nil, _bv = nil }

function Move.Speed(on)
    if Move._speedConn then Move._speedConn:Disconnect() Move._speedConn = nil end
    if on then
        Move._speedConn = RunService.Heartbeat:Connect(function()
            local h = GetHum()
            if h then h.WalkSpeed = Config.SpeedValue end
        end)
    else
        local h = GetHum()
        if h then h.WalkSpeed = 16 end
    end
end

function Move.Fly(on)
    if Move._flyConn then Move._flyConn:Disconnect() Move._flyConn = nil end
    if Move._bv then Move._bv:Destroy() Move._bv = nil end
    if on then
        local hrp = GetHRP()
        if not hrp then return end
        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
        bv.Velocity = Vector3.zero
        bv.Parent = hrp
        Move._bv = bv
        Move._flyConn = RunService.RenderStepped:Connect(function()
            if not bv.Parent then return end
            local dir = Vector3.zero
            if UIS:IsKeyDown(Enum.KeyCode.W) then dir += Camera.CFrame.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.S) then dir -= Camera.CFrame.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.A) then dir -= Camera.CFrame.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.D) then dir += Camera.CFrame.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
            if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.yAxis end
            bv.Velocity = dir.Magnitude > 0 and dir.Unit * Config.FlySpeed or Vector3.zero
        end)
    end
end

function Move.Noclip(on)
    if Move._noclipConn then Move._noclipConn:Disconnect() Move._noclipConn = nil end
    if on then
        Move._noclipConn = RunService.Stepped:Connect(function()
            local c = Player.Character
            if c then
                for _, p in ipairs(c:GetDescendants()) do
                    if p:IsA("BasePart") then p.CanCollide = false end
                end
            end
        end)
    end
end

function Move.InfJump(on)
    if on then
        UIS.JumpRequest:Connect(function()
            local h = GetHum()
            if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
        end)
    end
end

-- ══════════════════════════════════════════════════════════
-- RAID
-- ══════════════════════════════════════════════════════════
local Raid = {}

function Raid.IsInRaid()
    return workspace:FindFirstChild("_Raid") ~= nil or workspace:FindFirstChild("RaidIsland") ~= nil
end

function Raid.Farm()
    if not Raid.IsInRaid() then return end
    local area = workspace:FindFirstChild("_Raid") or workspace:FindFirstChild("RaidIsland")
    if area then
        for _, mob in ipairs(area:GetDescendants()) do
            if mob:IsA("Model") and mob:FindFirstChild("Humanoid") and mob:FindFirstChild("HumanoidRootPart") then
                if mob.Humanoid.Health > 0 then
                    Combat.BringMob(mob)
                end
            end
        end
    end
    Combat.FastClick()
end

function Raid.Start()
    local r = GetRemotes()
    if r then r:InvokeServer("RaidStart", Config.RaidFruit) end
end

-- ══════════════════════════════════════════════════════════
-- BOUNTY
-- ══════════════════════════════════════════════════════════
local function BountyAttack()
    local hrp = GetHRP()
    if not hrp then return end
    local best, bestD = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= Player and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            local h = p.Character:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then
                local d = Dist(hrp, p.Character.HumanoidRootPart)
                if d < bestD then best, bestD = p, d end
            end
        end
    end
    if best and bestD < 500 then
        hrp.CFrame = best.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, 3)
        Combat.FastClick()
        Combat.Skill(Enum.KeyCode.Z)
        Combat.Skill(Enum.KeyCode.X)
        Combat.Skill(Enum.KeyCode.C)
        Combat.Skill(Enum.KeyCode.V)
    end
end

-- ══════════════════════════════════════════════════════════
-- COLLECT
-- ══════════════════════════════════════════════════════════
local function CollectChests()
    local hrp = GetHRP()
    if not hrp then return end
    for obj in pairs(Cache.Chests) do
        if obj.Parent and Dist(hrp, obj) < 2000 then
            TweenWait(CFrame.new(obj.Position + Vector3.new(0, 3, 0)), 400)
            task.wait(0.3)
            for _, d in ipairs(obj:GetDescendants()) do
                if d:IsA("ProximityPrompt") then pcall(fireproximityprompt, d) task.wait(0.3) end
            end
            pcall(function() firetouchinterest(hrp, obj, 0) task.wait() firetouchinterest(hrp, obj, 1) end)
        end
    end
end

local function CollectFlowers()
    local hrp = GetHRP()
    if not hrp then return end
    for obj in pairs(Cache.Flowers) do
        if obj.Parent and Dist(hrp, obj) < 2000 then
            TweenWait(CFrame.new(obj.Position + Vector3.new(0, 3, 0)), 400)
            task.wait(0.3)
            for _, d in ipairs(obj:GetDescendants()) do
                if d:IsA("ProximityPrompt") then pcall(fireproximityprompt, d) task.wait(0.3) end
            end
        end
    end
end

-- ══════════════════════════════════════════════════════════
-- VISUALS
-- ══════════════════════════════════════════════════════════
local function FullBright(on)
    if on then
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.FogEnd = 1e5
        Lighting.GlobalShadows = false
        Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
        for _, v in ipairs(Lighting:GetDescendants()) do
            if v:IsA("Atmosphere") then v.Density = 0 end
            if v:IsA("BloomEffect") or v:IsA("BlurEffect") or v:IsA("ColorCorrectionEffect") then v.Enabled = false end
        end
    end
end

-- ══════════════════════════════════════════════════════════
-- SERVER HOP
-- ══════════════════════════════════════════════════════════
local function ServerHop()
    Notify("Hop", "Finding server...")
    pcall(function()
        local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/0?sortOrder=2&limit=100"
        local data = HttpService:JSONDecode(game:HttpGet(url))
        for _, s in ipairs(data.data) do
            if s.playing < s.maxPlayers and s.id ~= game.JobId then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, Player)
                return
            end
        end
    end)
end

-- ══════════════════════════════════════════════════════════
-- GUI — same aesthetics, compact code
-- ══════════════════════════════════════════════════════════
pcall(function()
    if GuiParent:FindFirstChild("PhantomEngine") then
        GuiParent:FindFirstChild("PhantomEngine"):Destroy()
    end
end)

print("[Phantom] Step 4: Building GUI...")

local Theme = {
    BG = Color3.fromRGB(15, 15, 25),
    BG2 = Color3.fromRGB(22, 22, 38),
    Accent = Color3.fromRGB(130, 80, 255),
    AccD = Color3.fromRGB(90, 50, 200),
    AccG = Color3.fromRGB(160, 120, 255),
    Text = Color3.fromRGB(240, 240, 255),
    Dim = Color3.fromRGB(150, 150, 180),
    OK = Color3.fromRGB(80, 255, 130),
    Warn = Color3.fromRGB(255, 200, 50),
    Err = Color3.fromRGB(255, 70, 70),
    Bdr = Color3.fromRGB(40, 40, 60),
    TOn = Color3.fromRGB(100, 255, 140),
    TOff = Color3.fromRGB(80, 80, 100),
}

local SG = Instance.new("ScreenGui")
SG.Name = "PhantomEngine"
SG.ResetOnSpawn = false
SG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() if syn and syn.protect_gui then syn.protect_gui(SG) end end)
SG.Parent = GuiParent
print("[Phantom] GUI created")

local MF = Instance.new("Frame")
MF.Size = UDim2.new(0, 620, 0, 460)
MF.Position = UDim2.new(0.5, -310, 0.5, -230)
MF.BackgroundColor3 = Theme.BG
MF.BorderSizePixel = 0
MF.ClipsDescendants = true
MF.Parent = SG
Instance.new("UICorner", MF).CornerRadius = UDim.new(0, 12)
local mStroke = Instance.new("UIStroke", MF)
mStroke.Color = Theme.Accent; mStroke.Thickness = 1.5; mStroke.Transparency = 0.5

-- Title bar
local TB = Instance.new("Frame")
TB.Size = UDim2.new(1, 0, 0, 40)
TB.BackgroundColor3 = Theme.BG2
TB.BorderSizePixel = 0
TB.Parent = MF
Instance.new("UICorner", TB).CornerRadius = UDim.new(0, 12)
local TBfix = Instance.new("Frame", TB)
TBfix.Size = UDim2.new(1, 0, 0, 12); TBfix.Position = UDim2.new(0, 0, 1, -12)
TBfix.BackgroundColor3 = Theme.BG2; TBfix.BorderSizePixel = 0

local TL = Instance.new("TextLabel", TB)
TL.Text = "⚡ PHANTOM ENGINE v4.2"
TL.Size = UDim2.new(0.7, 0, 1, 0); TL.Position = UDim2.new(0, 15, 0, 0)
TL.BackgroundTransparency = 1; TL.TextColor3 = Theme.AccG
TL.Font = Enum.Font.GothamBold; TL.TextSize = 16; TL.TextXAlignment = Enum.TextXAlignment.Left

local SL = Instance.new("TextLabel", TB)
SL.Name = "Status"; SL.Text = "● READY"
SL.Size = UDim2.new(0.3, -15, 1, 0); SL.Position = UDim2.new(0.7, 0, 0, 0)
SL.BackgroundTransparency = 1; SL.TextColor3 = Theme.OK
SL.Font = Enum.Font.GothamMedium; SL.TextSize = 12; SL.TextXAlignment = Enum.TextXAlignment.Right

-- drag
local dragging, dragStart, startPos
TB.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; dragStart = i.Position; startPos = MF.Position end end)
UIS.InputChanged:Connect(function(i) if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then local d = i.Position - dragStart; MF.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y) end end)
UIS.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)

-- Tab bar
local TBar = Instance.new("Frame", MF)
TBar.Size = UDim2.new(0, 130, 1, -45); TBar.Position = UDim2.new(0, 5, 0, 42)
TBar.BackgroundColor3 = Theme.BG2; TBar.BorderSizePixel = 0
Instance.new("UICorner", TBar).CornerRadius = UDim.new(0, 8)
local tl = Instance.new("UIListLayout", TBar); tl.SortOrder = Enum.SortOrder.LayoutOrder; tl.Padding = UDim.new(0, 3)
local tp = Instance.new("UIPadding", TBar); tp.PaddingTop = UDim.new(0, 5); tp.PaddingLeft = UDim.new(0, 5); tp.PaddingRight = UDim.new(0, 5)

-- Content
local CA = Instance.new("Frame", MF)
CA.Size = UDim2.new(1, -145, 1, -50); CA.Position = UDim2.new(0, 140, 0, 45)
CA.BackgroundColor3 = Theme.BG2; CA.BorderSizePixel = 0
Instance.new("UICorner", CA).CornerRadius = UDim.new(0, 8)

local Tabs, TabBtns = {}, {}

local function AddTab(name, icon)
    local btn = Instance.new("TextButton", TBar)
    btn.Size = UDim2.new(1, 0, 0, 32); btn.BackgroundColor3 = Theme.BG; btn.BorderSizePixel = 0
    btn.Text = (icon or "") .. "  " .. name; btn.TextColor3 = Theme.Dim
    btn.Font = Enum.Font.GothamMedium; btn.TextSize = 13; btn.TextXAlignment = Enum.TextXAlignment.Left; btn.AutoButtonColor = false
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    Instance.new("UIPadding", btn).PaddingLeft = UDim.new(0, 10)
    
    local pg = Instance.new("ScrollingFrame", CA)
    pg.Size = UDim2.new(1, -10, 1, -10); pg.Position = UDim2.new(0, 5, 0, 5)
    pg.BackgroundTransparency = 1; pg.BorderSizePixel = 0; pg.ScrollBarThickness = 3
    pg.ScrollBarImageColor3 = Theme.Accent; pg.CanvasSize = UDim2.new(0,0,0,0)
    pg.AutomaticCanvasSize = Enum.AutomaticSize.Y; pg.Visible = false
    local ll = Instance.new("UIListLayout", pg); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Padding = UDim.new(0, 5)
    local pp = Instance.new("UIPadding", pg); pp.PaddingTop = UDim.new(0, 5); pp.PaddingLeft = UDim.new(0, 5); pp.PaddingRight = UDim.new(0, 5)
    
    Tabs[name] = pg; TabBtns[name] = btn
    btn.MouseButton1Click:Connect(function()
        for n, p in pairs(Tabs) do
            p.Visible = (n == name)
            TweenService:Create(TabBtns[n], TweenInfo.new(0.15), {
                BackgroundColor3 = n == name and Theme.Accent or Theme.BG,
                TextColor3 = n == name and Theme.Text or Theme.Dim,
            }):Play()
        end
    end)
    return pg
end

local function Section(pg, name)
    local f = Instance.new("Frame", pg); f.Size = UDim2.new(1, 0, 0, 22); f.BackgroundTransparency = 1
    local l = Instance.new("TextLabel", f); l.Text = "— " .. name:upper() .. " —"
    l.Size = UDim2.new(1, 0, 1, 0); l.BackgroundTransparency = 1
    l.TextColor3 = Theme.Accent; l.Font = Enum.Font.GothamBold; l.TextSize = 11
end

local function Toggle(pg, name, default, cb)
    local f = Instance.new("Frame", pg); f.Size = UDim2.new(1, 0, 0, 30); f.BackgroundColor3 = Theme.BG; f.BorderSizePixel = 0
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 6)
    local l = Instance.new("TextLabel", f); l.Text = name
    l.Size = UDim2.new(1, -60, 1, 0); l.Position = UDim2.new(0, 10, 0, 0)
    l.BackgroundTransparency = 1; l.TextColor3 = Theme.Text; l.Font = Enum.Font.GothamMedium; l.TextSize = 12
    l.TextXAlignment = Enum.TextXAlignment.Left
    
    local bg = Instance.new("Frame", f); bg.Size = UDim2.new(0, 38, 0, 18)
    bg.Position = UDim2.new(1, -48, 0.5, -9); bg.BackgroundColor3 = default and Theme.TOn or Theme.TOff; bg.BorderSizePixel = 0
    Instance.new("UICorner", bg).CornerRadius = UDim.new(1, 0)
    local circ = Instance.new("Frame", bg); circ.Size = UDim2.new(0, 14, 0, 14)
    circ.Position = default and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
    circ.BackgroundColor3 = Color3.new(1,1,1); circ.BorderSizePixel = 0
    Instance.new("UICorner", circ).CornerRadius = UDim.new(1, 0)
    
    local state = default
    local b = Instance.new("TextButton", f); b.Size = UDim2.new(1,0,1,0); b.BackgroundTransparency = 1; b.Text = ""
    b.MouseButton1Click:Connect(function()
        state = not state
        TweenService:Create(bg, TweenInfo.new(0.15), {BackgroundColor3 = state and Theme.TOn or Theme.TOff}):Play()
        TweenService:Create(circ, TweenInfo.new(0.15, Enum.EasingStyle.Back), {Position = state and UDim2.new(1,-16,0.5,-7) or UDim2.new(0,2,0.5,-7)}):Play()
        if cb then cb(state) end
    end)
end

local function Dropdown(pg, name, opts, default, cb)
    local f = Instance.new("Frame", pg); f.Size = UDim2.new(1, 0, 0, 30); f.BackgroundColor3 = Theme.BG; f.BorderSizePixel = 0; f.ClipsDescendants = true
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 6)
    local l = Instance.new("TextLabel", f); l.Text = name
    l.Size = UDim2.new(0.5, -5, 0, 30); l.Position = UDim2.new(0, 10, 0, 0)
    l.BackgroundTransparency = 1; l.TextColor3 = Theme.Text; l.Font = Enum.Font.GothamMedium; l.TextSize = 12; l.TextXAlignment = Enum.TextXAlignment.Left
    
    local sel = Instance.new("TextButton", f); sel.Text = default or (opts and opts[1]) or "None"
    sel.Size = UDim2.new(0.5, -15, 0, 24); sel.Position = UDim2.new(0.5, 5, 0, 3)
    sel.BackgroundColor3 = Theme.Bdr; sel.TextColor3 = Theme.AccG; sel.Font = Enum.Font.GothamMedium; sel.TextSize = 11; sel.BorderSizePixel = 0
    Instance.new("UICorner", sel).CornerRadius = UDim.new(0, 4)
    
    local oc = Instance.new("Frame", f); oc.Size = UDim2.new(0.5, -15, 0, #opts * 22)
    oc.Position = UDim2.new(0.5, 5, 0, 30); oc.BackgroundColor3 = Theme.Bdr; oc.BorderSizePixel = 0; oc.Visible = false; oc.ZIndex = 10
    Instance.new("UICorner", oc).CornerRadius = UDim.new(0, 4)
    Instance.new("UIListLayout", oc).SortOrder = Enum.SortOrder.LayoutOrder
    
    local exp = false
    local obj = {}
    function obj:Refresh(newOpts)
        opts = newOpts
        for _, c in ipairs(oc:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
        oc.Size = UDim2.new(0.5, -15, 0, #opts * 22)
        for _, o in ipairs(opts) do
            local ob = Instance.new("TextButton", oc); ob.Text = o
            ob.Size = UDim2.new(1, 0, 0, 22); ob.BackgroundTransparency = 1
            ob.TextColor3 = Theme.Text; ob.Font = Enum.Font.Gotham; ob.TextSize = 11; ob.ZIndex = 10
            ob.MouseButton1Click:Connect(function() sel.Text = o; exp = false; oc.Visible = false; f.Size = UDim2.new(1,0,0,30); if cb then cb(o) end end)
            ob.MouseEnter:Connect(function() ob.TextColor3 = Theme.Accent end)
            ob.MouseLeave:Connect(function() ob.TextColor3 = Theme.Text end)
        end
        if #opts > 0 and not table.find(opts, sel.Text) then sel.Text = opts[1] end
        if exp then f.Size = UDim2.new(1,0,0,30 + #opts*22 + 5) end
    end
    
    obj:Refresh(opts)
    sel.MouseButton1Click:Connect(function() exp = not exp; oc.Visible = exp; f.Size = exp and UDim2.new(1,0,0,30+#opts*22+5) or UDim2.new(1,0,0,30) end)
    return obj
end

local function Button(pg, name, cb)
    local b = Instance.new("TextButton", pg); b.Size = UDim2.new(1, 0, 0, 28)
    b.BackgroundColor3 = Theme.AccD; b.BorderSizePixel = 0; b.Text = name
    b.TextColor3 = Theme.Text; b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.AutoButtonColor = false
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(function()
        if cb then cb() end
        TweenService:Create(b, TweenInfo.new(0.1), {BackgroundColor3 = Theme.AccG}):Play()
        task.delay(0.1, function() TweenService:Create(b, TweenInfo.new(0.2), {BackgroundColor3 = Theme.AccD}):Play() end)
    end)
    b.MouseEnter:Connect(function() TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = Theme.Accent}):Play() end)
    b.MouseLeave:Connect(function() TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = Theme.AccD}):Play() end)
end

local function Slider(pg, name, mn, mx, def, cb)
    local f = Instance.new("Frame", pg); f.Size = UDim2.new(1, 0, 0, 42); f.BackgroundColor3 = Theme.BG; f.BorderSizePixel = 0
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 6)
    local l = Instance.new("TextLabel", f); l.Text = name
    l.Size = UDim2.new(0.6, 0, 0, 18); l.Position = UDim2.new(0, 10, 0, 2)
    l.BackgroundTransparency = 1; l.TextColor3 = Theme.Text; l.Font = Enum.Font.GothamMedium; l.TextSize = 11; l.TextXAlignment = Enum.TextXAlignment.Left
    local vl = Instance.new("TextLabel", f); vl.Text = tostring(def)
    vl.Size = UDim2.new(0.4, -10, 0, 18); vl.Position = UDim2.new(0.6, 0, 0, 2)
    vl.BackgroundTransparency = 1; vl.TextColor3 = Theme.AccG; vl.Font = Enum.Font.GothamBold; vl.TextSize = 11; vl.TextXAlignment = Enum.TextXAlignment.Right
    
    local sbg = Instance.new("Frame", f); sbg.Size = UDim2.new(1, -20, 0, 5); sbg.Position = UDim2.new(0, 10, 0, 28)
    sbg.BackgroundColor3 = Theme.Bdr; sbg.BorderSizePixel = 0
    Instance.new("UICorner", sbg).CornerRadius = UDim.new(1, 0)
    local fill = Instance.new("Frame", sbg); local pct = (def - mn) / (mx - mn)
    fill.Size = UDim2.new(pct, 0, 1, 0); fill.BackgroundColor3 = Theme.Accent; fill.BorderSizePixel = 0
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
    local knob = Instance.new("Frame", sbg); knob.Size = UDim2.new(0, 12, 0, 12)
    knob.Position = UDim2.new(pct, -6, 0.5, -6); knob.BackgroundColor3 = Color3.new(1,1,1); knob.BorderSizePixel = 0; knob.ZIndex = 5
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
    
    local sliding = false
    local ib = Instance.new("TextButton", f); ib.Size = UDim2.new(1, 0, 0, 18); ib.Position = UDim2.new(0, 0, 0, 22); ib.BackgroundTransparency = 1; ib.Text = ""
    ib.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then sliding = true end end)
    UIS.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then sliding = false end end)
    UIS.InputChanged:Connect(function(i)
        if sliding and i.UserInputType == Enum.UserInputType.MouseMovement then
            local rx = math.clamp((i.Position.X - sbg.AbsolutePosition.X) / sbg.AbsoluteSize.X, 0, 1)
            local val = math.floor(mn + (mx - mn) * rx)
            fill.Size = UDim2.new(rx, 0, 1, 0); knob.Position = UDim2.new(rx, -6, 0.5, -6)
            vl.Text = tostring(val)
            if cb then cb(val) end
        end
    end)
end

-- ══════════════════════════════════════════════════════════
-- BUILD TABS
-- ══════════════════════════════════════════════════════════

-- FARM
local farm = AddTab("Farm", "🌾")
Section(farm, "Quest Farm")
Toggle(farm, "Auto Farm", false, function(v) Config.AutoFarm = v; SL.Text = v and "● FARMING" or "● READY"; SL.TextColor3 = v and Theme.Warn or Theme.OK end)
Dropdown(farm, "Farm Mode", {"Quest","Raid","BossOnly"}, "Quest", function(v) Config.AutoFarmMode = v end)
Toggle(farm, "Auto Quest Accept", true, function(v) Config.AutoQuestAccept = v end)
Section(farm, "Combat")
local wepList = Weapon.GetAll()
local wepDrop = Dropdown(farm, "Select Weapon", wepList, wepList[1], function(v) Config.SelectedWeapon = v end)
Button(farm, "Refresh Weapons", function() wepDrop:Refresh(Weapon.GetAll()) end)
Toggle(farm, "Mob Aura", false, function(v) Config.MobAura = v end)
Toggle(farm, "Bring Mobs", true, function(v) Config.BringMobs = v end)
Toggle(farm, "Fast Attack", true, function(v) Config.FastAttack = v end)
Toggle(farm, "Kill Aura", false, function(v) Config.KillAura = v end)
Slider(farm, "Aura Range", 50, 500, 300, function(v) Config.MobAuraRange = v end)
Slider(farm, "Bring Range", 50, 300, 100, function(v) Config.BringMobsRange = v end)
Section(farm, "Mastery")
Toggle(farm, "Mastery Farm", false, function(v) Config.MasteryFarm = v end)

-- FRUIT
local fruit = AddTab("Fruit", "🍎")
Section(fruit, "Fruit Sniper")
Toggle(fruit, "Fruit Sniper", false, function(v) Config.FruitSniper = v end)
Dropdown(fruit, "Sniper Mode", {"Any","Mythical","Legendary"}, "Any", function(v) Config.FruitSniperMode = v end)
Toggle(fruit, "Auto Store Fruit", false, function(v) Config.AutoStoreFruit = v end)
Toggle(fruit, "Auto Eat Fruit", false, function(v) Config.AutoEatFruit = v end)
Section(fruit, "Actions")
Button(fruit, "Scan Fruits Now", function()
    local f = Sniper.Scan()
    Notify("Scan", #f > 0 and ("Found " .. #f .. " fruit(s)") or "No fruits found")
end)
Button(fruit, "Server Hop (Find Fruits)", ServerHop)

-- STATS
local stats = AddTab("Stats", "📊")
Section(stats, "Auto Stats")
Toggle(stats, "Auto Stats", false, function(v) Config.AutoStats = v end)
Dropdown(stats, "Stat Focus", {"Melee","Defense","Sword","Gun","Blox Fruit"}, "Melee", function(v) Config.StatMode = v end)
Section(stats, "Haki")
Toggle(stats, "Auto Buso Haki", false, function(v) Config.AutoBuso = v end)
Toggle(stats, "Auto Observation", false, function(v) Config.AutoHaki = v end)
Toggle(stats, "Infinite Energy", false, function(v) Config.InfiniteEnergy = v
    if v then task.spawn(function() while Config.InfiniteEnergy and task.wait(0.2) do
        pcall(function() local e = Player.Character and Player.Character:FindFirstChild("Energy") if e then e.Value = 5000 end end)
    end end) end
end)

-- TELEPORT
local tp = AddTab("Teleport", "🌀")
for seaName, islands in pairs(SeaData) do
    Section(tp, seaName .. " Sea")
    for _, isl in ipairs(islands) do
        Button(tp, isl.Name .. " (Lv." .. isl.Level .. ")", function()
            Notify("TP", "Going to " .. isl.Name)
            TweenWait(isl.CFrame + Vector3.new(0, 30, 0), 500)
            Notify("TP", "Arrived at " .. isl.Name)
        end)
    end
end

-- ESP
local esp = AddTab("ESP", "👁")
Section(esp, "ESP Settings")
Toggle(esp, "Enable ESP", false, function(v) Config.ESP = v; if v then ESP.Refresh() else ESP.Clear() end end)
Toggle(esp, "Player ESP", false, function(v) Config.ESPPlayers = v; ESP.Refresh() end)
Toggle(esp, "Fruit ESP", true, function(v) Config.ESPFruits = v; ESP.Refresh() end)
Toggle(esp, "Chest ESP", false, function(v) Config.ESPChests = v; ESP.Refresh() end)
Toggle(esp, "Flower ESP", false, function(v) Config.ESPFlowers = v; ESP.Refresh() end)
Toggle(esp, "Boss ESP", true, function(v) Config.ESPBoss = v; ESP.Refresh() end)
Button(esp, "Refresh ESP", function() ESP.Refresh() end)

-- MOVEMENT
local move = AddTab("Move", "🏃")
Section(move, "Movement Hacks")
Toggle(move, "Speed Hack", false, function(v) Config.Speed = v; Move.Speed(v) end)
Slider(move, "Speed Value", 16, 500, 150, function(v) Config.SpeedValue = v end)
Toggle(move, "Fly", false, function(v) Config.Fly = v; Move.Fly(v) end)
Slider(move, "Fly Speed", 50, 1000, 200, function(v) Config.FlySpeed = v end)
Toggle(move, "Noclip", false, function(v) Config.Noclip = v; Move.Noclip(v) end)
Toggle(move, "Infinite Jump", false, function(v) Config.InfiniteJump = v; Move.InfJump(v) end)

-- RAID
local raid = AddTab("Raid", "⚔")
Section(raid, "Auto Raid")
Toggle(raid, "Auto Raid", false, function(v) Config.AutoRaid = v end)
Dropdown(raid, "Raid Fruit", {"Buddha","Phoenix","Dough","Venom","Dragon","Leopard","Control","Spirit","Rumble","Quake","Dark","Light","Magma","Ice","Flame"}, "Buddha", function(v) Config.RaidFruit = v end)
Button(raid, "Start Raid", function() Raid.Start(); Notify("Raid", "Starting " .. Config.RaidFruit .. " raid") end)
Section(raid, "Sea Events")
Toggle(raid, "Auto Sea Beast", false, function(v) Config.AutoSeaBeast = v end)

-- PVP
local pvp = AddTab("PvP", "🎯")
Section(pvp, "Bounty Hunt")
Toggle(pvp, "Auto Bounty Hunt", false, function(v) Config.AutoBountyHunt = v end)
Section(pvp, "Auto Collect")
Toggle(pvp, "Auto Collect Chests", false, function(v) Config.AutoCollectChests = v end)
Toggle(pvp, "Auto Collect Flowers", false, function(v) Config.AutoCollectFlowers = v end)
Button(pvp, "Collect All Chests", CollectChests)
Button(pvp, "Collect All Flowers", CollectFlowers)

-- MISC
local misc = AddTab("Misc", "⚙")
Section(misc, "Visual")
Toggle(misc, "Full Bright", false, function(v) Config.FullBright = v; FullBright(v) end)
Toggle(misc, "No Fog", false, function(v) Config.NoFog = v
    if v then Lighting.FogEnd = 1e5; Lighting.FogStart = 1e5
    for _, x in ipairs(Lighting:GetDescendants()) do if x:IsA("Atmosphere") then x.Density = 0 end end end
end)
Section(misc, "Utilities")
Toggle(misc, "Anti AFK", true, function(v) Config.AntiAFK = v end)
Button(misc, "Server Hop", ServerHop)
Button(misc, "Rejoin", function() TeleportService:Teleport(game.PlaceId, Player) end)
Button(misc, "Copy Game Link", function() pcall(setclipboard, "https://www.roblox.com/games/" .. game.PlaceId); Notify("OK", "Copied") end)
Button(misc, "Destroy GUI", function() Config._running = false; SG:Destroy() end)

-- manually trigger Farm tab
for n, p in pairs(Tabs) do
    p.Visible = (n == "Farm")
    if TabBtns[n] then
        TweenService:Create(TabBtns[n], TweenInfo.new(0.15), {
            BackgroundColor3 = n == "Farm" and Theme.Accent or Theme.BG,
            TextColor3 = n == "Farm" and Theme.Text or Theme.Dim,
        }):Play()
    end
end

-- ══════════════════════════════════════════════════════════
-- MAIN LOOPS — throttled, cached, no GetDescendants()
-- ══════════════════════════════════════════════════════════

-- Toggle GUI
UIS.InputBegan:Connect(function(i, gpe)
    if gpe then return end
    if i.KeyCode == Enum.KeyCode.RightShift then
        Config._guiOpen = not Config._guiOpen
        MF.Visible = Config._guiOpen
    end
end)

-- Auto Farm (0.15s tick)
task.spawn(function()
    while Config._running do
        task.wait(0.15)
        if Config.AutoFarm then
            local qd = Config.SelectedQuest or Quest.GetBest()
            if qd then
                pcall(function()
                    if not Quest.HasActive() and Config.AutoQuestAccept then
                        print("[Farm Debug] Accepting quest: " .. tostring(qd.Quest))
                        Quest.Accept(qd)
                        task.wait(1)
                    end
                end)
                
                local mob, d = Combat.Nearest(Config.MobAuraRange, qd.Mob)
                if mob and mob:FindFirstChild("HumanoidRootPart") then
                    -- disable print if we are just hitting them so we don't spam
                    if Config.BringMobs and d < Config.BringMobsRange then
                        Combat.BringMob(mob)
                    elseif d > 15 then
                        TweenTo(mob.HumanoidRootPart.CFrame * CFrame.new(0, 0, 3), 300)
                    end
                    if Config.FastAttack then Combat.FastAttack() else Combat.Attack() end
                else
                    print("[Farm Debug] No mob nearby, teleporting to spawn...")
                    local hrp = GetHRP()
                    if hrp and Dist(hrp, qd.CFrame) > 300 then
                        TweenTo(qd.CFrame + Vector3.new(0, 50, 0), 350)
                    end
                end
            else
                print("[Farm Debug] No quest data found for your level")
            end
        end
    end
end)

-- Mob/Kill Aura (0.2s tick)
task.spawn(function()
    while Config._running do
        task.wait(0.2)
        if Config.MobAura or Config.KillAura then
            if Config.BringMobs then Combat.BringAll(Config.BringMobsRange) end
            local mob = Combat.Nearest(Config.KillAura and Config.KillAuraRange or Config.MobAuraRange)
            if mob then
                if Config.FastAttack then Combat.FastAttack() else Combat.Attack() end
            end
        end
    end
end)

-- Fruit Sniper (3s tick — no need for faster)
task.spawn(function()
    while Config._running do
        task.wait(3)
        if Config.FruitSniper then
            local fruits = Sniper.Scan()
            for _, fd in ipairs(fruits) do
                local grab = Config.FruitSniperMode == "Any"
                    or (Config.FruitSniperMode == "Mythical" and fd.Tier == "Mythical")
                    or (Config.FruitSniperMode == "Legendary" and (fd.Tier == "Mythical" or fd.Tier == "Legendary"))
                if grab then Sniper.Grab(fd); task.wait(1) end
            end
        end
    end
end)

-- Stats (5s tick)
task.spawn(function()
    while Config._running do task.wait(5); AutoStats() end
end)

-- Raid (0.3s tick)
task.spawn(function()
    while Config._running do task.wait(0.3); if Config.AutoRaid then Raid.Farm() end end
end)

-- Bounty (0.5s tick)
task.spawn(function()
    while Config._running do task.wait(0.5); if Config.AutoBountyHunt then BountyAttack() end end
end)

-- Sea Beast (2s tick)
task.spawn(function()
    while Config._running do
        task.wait(2)
        if Config.AutoSeaBeast then
            for _, obj in ipairs(workspace:GetChildren()) do -- only top-level, very cheap
                if obj:IsA("Model") and obj.Name:find("SeaBeast") and obj:FindFirstChild("Humanoid") and obj.Humanoid.Health > 0 then
                    local part = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
                    if part then
                        TweenTo(part.CFrame * CFrame.new(0, 20, 30), 400)
                        task.wait(0.3)
                        Combat.Skill(Enum.KeyCode.Z); Combat.Skill(Enum.KeyCode.X); Combat.Skill(Enum.KeyCode.C)
                    end
                end
            end
        end
    end
end)

-- Collect (10s tick)
task.spawn(function()
    while Config._running do
        task.wait(10)
        if Config.AutoCollectChests then CollectChests() end
        if Config.AutoCollectFlowers then CollectFlowers() end
    end
end)

-- ESP refresh (20s tick)
task.spawn(function()
    while Config._running do task.wait(20); if Config.ESP then ESP.Refresh() end end
end)

-- Haki (2s tick)
task.spawn(function()
    while Config._running do
        task.wait(2)
        local r = GetRemotes()
        if r then
            if Config.AutoBuso then pcall(function() r:InvokeServer("Buso") end) end
            if Config.AutoHaki then pcall(function() r:InvokeServer("Ken") end) end
        end
    end
end)

-- Mastery (0.3s tick)
task.spawn(function()
    while Config._running do
        task.wait(0.3)
        if Config.MasteryFarm then
            local mob = Combat.Nearest(Config.MobAuraRange)
            if mob and mob:FindFirstChild("HumanoidRootPart") then
                Combat.BringMob(mob)
                task.wait(0.1)
                Combat.Skill(Enum.KeyCode.Z); task.wait(0.15)
                Combat.Skill(Enum.KeyCode.X); task.wait(0.15)
                Combat.Skill(Enum.KeyCode.C); task.wait(0.15)
                Combat.Skill(Enum.KeyCode.V); task.wait(0.15)
                Combat.Skill(Enum.KeyCode.F)
            end
        end
    end
end)

-- ══════════════════════════════════════════════════════════
-- DONE
-- ══════════════════════════════════════════════════════════
Notify("⚡ Phantom Engine", "v4.2 loaded! RightShift = toggle GUI", 5)
print("[Phantom Engine] v4.2 — Optimized build loaded")
print("[Phantom Engine] RightShift to toggle GUI")
