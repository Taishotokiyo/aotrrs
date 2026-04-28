-- ╔══════════════════════════════════════════════════════╗
-- ║     ATTACK ON TITAN REVOLUTION — FARMING v1.0       ║
-- ║              by Taishotokiyo                        ║
-- ║  Section 1/4: Farming                               ║
-- ╚══════════════════════════════════════════════════════╝
-- Features:
--   • Autofarm Missions (Blades)
--   • Autofarm Missions (Titan Ripper)
--   • Autofarm Missions (Thunderspears)
--   • Autofarm Raids (Thunderspears)
--   • Autofarm Raids (Blades / Titan Ripper)
--   • Auto Streak Farmer
--   • Auto Connect (mission/raid)
--   • Instant TS Quest (watchtower/crates)
--   • Auto Leave to Lobby
--   • Max Kill Amount
--   • Wait X seconds before killing last titan
--   • HP Cutoff for bosses
--   • Stall compatibility
--   • Hitbox Extender
--   • Positioning (Above / In Front / Behind)
--   • Auto M1
--   • Auto Eject

local Players        = game:GetService("Players")
local RS             = game:GetService("ReplicatedStorage")
local RunService     = game:GetService("RunService")
local TweenService   = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local lp             = Players.LocalPlayer

repeat task.wait(0.1) until lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
task.wait(1)

pcall(function()
    local old = game:GetService("CoreGui"):FindFirstChild("AOTR_Farm")
    if old then old:Destroy() end
end)

-- ══════════════════════════════════════
--  CONFIG (edit these)
-- ══════════════════════════════════════
local CFG = {
    -- Farming
    KILL_DELAY       = 2,      -- seconds to wait before killing last titan
    MAX_KILLS        = 999,    -- max kills before auto leave
    BOSS_HP_CUTOFF   = 0.15,   -- don't kill boss below this % HP (0.15 = 15%)
    HITBOX_SIZE      = 30,     -- stud radius for hitbox extender
    POSITION_MODE    = "Above",-- "Above" / "InFront" / "Behind"
    ABOVE_OFFSET     = 14,     -- studs above titan
    FRONT_OFFSET     = 5,      -- studs in front
    BEHIND_OFFSET    = -5,     -- studs behind
    STALL_TIME       = 3,      -- seconds to stall before last kill
    STREAK_TARGET    = 10,     -- auto leave after this many streak wins
    REJOIN_DELAY     = 4,      -- seconds before rejoining after lobby leave
    TS_QUEST_DELAY   = 0.5,    -- delay between TS quest actions
}

-- ══════════════════════════════════════
--  STATE
-- ══════════════════════════════════════
local T = {
    FarmBlade      = false,
    FarmRipper     = false,
    FarmTS         = false,
    RaidTS         = false,
    RaidBlade      = false,
    AutoStreak     = false,
    AutoConnect    = false,
    InstantTSQuest = false,
    AutoLeave      = false,
    AutoM1         = false,
    AutoEject      = false,
    HitboxExtender = false,
}

local stats = {
    kills       = 0,
    missions    = 0,
    raids       = 0,
    streak      = 0,
    titansMapped = 0,
}

local lastHit    = 0
local lastEject  = 0
local lastM1     = 0
local espFolder  = nil

-- ══════════════════════════════════════
--  HELPERS
-- ══════════════════════════════════════
local function safe(f, ...) pcall(f, ...) end
local function rng(n, r) r = r or n*0.15; return n + (math.random()-0.5)*r*2 end

-- Fire remotes by keyword
local function fireKw(kws, ...)
    for _, folder in ipairs({RS, workspace}) do
        pcall(function()
            for _, r in ipairs(folder:GetDescendants()) do
                if r:IsA("RemoteEvent") or r:IsA("RemoteFunction") then
                    local n = r.Name:lower()
                    for _, k in ipairs(kws) do
                        if n:find(k, 1, true) then
                            pcall(function()
                                if r:IsA("RemoteEvent") then r:FireServer(...)
                                else r:InvokeServer(...) end
                            end)
                        end
                    end
                end
            end
        end)
    end
end

-- Click GUI buttons by keyword
local function clickBtn(kws)
    for _, obj in ipairs(lp.PlayerGui:GetDescendants()) do
        if obj:IsA("TextButton") or obj:IsA("ImageButton") then
            local t = (obj.Text or ""):lower()
            local n = obj.Name:lower()
            for _, k in ipairs(kws) do
                if t:find(k,1,true) or n:find(k,1,true) then
                    safe(function() obj.MouseButton1Click:Fire() end)
                    return true
                end
            end
        end
    end
    return false
end

-- Nape finder
local NAPE_TAGS = {"nape","napehit","weakpoint","weak","neck","killzone","neckback"}
local function getNape(model)
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then
            local n = p.Name:lower()
            for _, t in ipairs(NAPE_TAGS) do
                if n:find(t,1,true) then return p end
            end
        end
    end
    -- fallback: upper back geometry
    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
    if root then
        local best, bestScore = nil, math.huge
        for _, p in ipairs(model:GetDescendants()) do
            if p:IsA("BasePart") and p ~= root then
                local rel = root.CFrame:PointToObjectSpace(p.Position)
                local score = math.abs(rel.Y - 5) + math.abs(rel.Z + 3)
                if score < bestScore then bestScore = score; best = p end
            end
        end
        if bestScore < 9 then return best end
    end
    return root
end

-- Get all titans sorted by distance
local function getTitans(hrp, maxDist)
    local list = {}
    maxDist = maxDist or math.huge
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj ~= lp.Character and not Players:GetPlayerFromCharacter(obj) then
            local h = obj:FindFirstChildOfClass("Humanoid")
            local r = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Torso")
            if h and r and h.Health > 0 then
                local d = (hrp.Position - r.Position).Magnitude
                if d < maxDist then
                    table.insert(list, {model=obj, root=r, hum=h, dist=d})
                end
            end
        end
    end
    table.sort(list, function(a,b) return a.dist < b.dist end)
    return list
end

-- Get position offset based on mode
local function getOffset()
    if CFG.POSITION_MODE == "Above"   then return Vector3.new(0, CFG.ABOVE_OFFSET,  0) end
    if CFG.POSITION_MODE == "InFront" then return Vector3.new(0, 4, CFG.FRONT_OFFSET) end
    if CFG.POSITION_MODE == "Behind"  then return Vector3.new(0, 4, CFG.BEHIND_OFFSET) end
    return Vector3.new(0, CFG.ABOVE_OFFSET, 0)
end

-- Attack a titan
local function attackTitan(model)
    local nape = getNape(model)
    local tgt  = nape or model:FindFirstChild("HumanoidRootPart")
    if not tgt then return end
    local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    hrp.CFrame = CFrame.new(tgt.Position + getOffset())
    task.wait(0.04)
    if (hrp.Position - tgt.Position).Magnitude < CFG.HITBOX_SIZE then
        fireKw({"attack","slash","nape","execute","kill","hit","swing","damage","m1","strike"}, model)
        task.wait(0.03)
        hrp.CFrame = CFrame.new(tgt.Position + Vector3.new(0, 3, 0))
        task.wait(0.03)
        fireKw({"attack","slash","nape","execute","kill","hit"}, model)
    end
end

-- TS (Thunderspear) attack
local function attackTS(model)
    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
    if not root then return end
    local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    hrp.CFrame = CFrame.new(root.Position + Vector3.new(0, 20, 0))
    task.wait(0.04)
    fireKw({"thunderspear","ts","launch","fire","shoot","throw","spear","explode"}, model, root.Position)
    task.wait(0.05)
    fireKw({"thunderspear","ts","launch","fire","shoot","throw","spear"}, model)
end

-- Leave to lobby
local function leaveToLobby()
    fireKw({"leave","lobby","exit","disconnect","menu","returnlobby"})
    clickBtn({"leave","lobby","exit","menu","return"})
end

-- Connect to mission/raid
local function connectToGame(mode)
    -- mode = "mission" or "raid"
    fireKw({mode, "join","connect","start","play","enter"})
    clickBtn({mode, "join","connect","start","play"})
end

-- Check if we are in a mission/raid (look for titan count UI)
local function inMission()
    for _, obj in ipairs(lp.PlayerGui:GetDescendants()) do
        if obj:IsA("TextLabel") then
            local t = obj.Text:lower()
            if t:find("titan") or t:find("wave") or t:find("mission") or t:find("raid") then
                return true
            end
        end
    end
    -- also check if titans exist in workspace
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and not Players:GetPlayerFromCharacter(obj) and obj ~= lp.Character then
            local h = obj:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then return true end
        end
    end
    return false
end

-- Count alive titans
local function countTitans()
    local count = 0
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and not Players:GetPlayerFromCharacter(obj) and obj ~= lp.Character then
            local h = obj:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then count = count + 1 end
        end
    end
    return count
end

-- ══════════════════════════════════════
--  FARM LOOP FACTORY
-- ══════════════════════════════════════
local function farmLoop(mode, weaponType)
    -- mode: "mission" or "raid"
    -- weaponType: "blade" / "ripper" / "ts"
    task.spawn(function()
        local key = weaponType == "ts" and (mode=="raid" and "RaidTS" or "FarmTS")
                    or weaponType == "ripper" and "FarmRipper"
                    or mode == "raid" and "RaidBlade" or "FarmBlade"

        while T[key] do
            -- Auto connect if not in game
            if not inMission() then
                connectToGame(mode)
                task.wait(rng(5, 2))
                stats.missions = stats.missions + (mode=="mission" and 1 or 0)
                stats.raids    = stats.raids    + (mode=="raid"    and 1 or 0)
            end

            local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then task.wait(1); continue end

            local titans = getTitans(hrp)
            local alive  = #titans

            if alive == 0 then
                -- no titans, wait for next wave or auto leave
                task.wait(rng(2))
                if T.AutoLeave then
                    if stats.kills >= CFG.MAX_KILLS then
                        leaveToLobby()
                        stats.kills = 0
                        task.wait(rng(CFG.REJOIN_DELAY))
                    end
                end
            elseif alive == 1 then
                -- last titan — stall if enabled
                local titan = titans[1]
                local isBoss = titan.hum.MaxHealth > 5000

                if isBoss and titan.hum.Health / titan.hum.MaxHealth < CFG.BOSS_HP_CUTOFF then
                    -- HP cutoff — don't kill yet
                    task.wait(rng(CFG.STALL_TIME))
                else
                    task.wait(rng(CFG.KILL_DELAY))
                    if weaponType == "ts" then
                        attackTS(titan.model)
                    else
                        attackTitan(titan.model)
                    end
                    stats.kills = stats.kills + 1
                    stats.streak = stats.streak + 1
                end

                -- Streak wiper
                if T.AutoStreak and stats.streak >= CFG.STREAK_TARGET then
                    leaveToLobby()
                    stats.streak = 0
                    task.wait(rng(CFG.REJOIN_DELAY))
                end
            else
                -- multiple titans — attack all except last
                for i = 1, #titans - 1 do
                    if not T[key] then break end
                    local titan = titans[i]
                    local isBoss = titan.hum.MaxHealth > 5000
                    local hpPct  = titan.hum.Health / titan.hum.MaxHealth

                    -- skip boss if above HP cutoff
                    if isBoss and hpPct < CFG.BOSS_HP_CUTOFF then
                        continue
                    end

                    if weaponType == "ts" then
                        attackTS(titan.model)
                    else
                        attackTitan(titan.model)
                    end
                    stats.kills = stats.kills + 1
                    task.wait(rng(0.12))
                end
            end

            task.wait(rng(0.1))
        end
    end)
end

-- TS Quest (watchtower/crates)
local function runTSQuest()
    task.spawn(function()
        while T.InstantTSQuest do
            -- look for watchtower / crate objectives
            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj:IsA("Model") or obj:IsA("BasePart") then
                    local n = obj.Name:lower()
                    if n:find("watchtower") or n:find("crate") or n:find("objective") or n:find("quest") then
                        local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
                        local pos = obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChildOfClass("BasePart")) or obj
                        if hrp and pos then
                            hrp.CFrame = CFrame.new(pos.Position + Vector3.new(0, 5, 0))
                            task.wait(CFG.TS_QUEST_DELAY)
                            fireKw({"thunderspear","ts","launch","fire","shoot","spear"}, pos.Position)
                            task.wait(CFG.TS_QUEST_DELAY)
                            fireKw({"complete","quest","objective","finish","watchtower","crate"})
                            clickBtn({"complete","collect","claim","objective","watchtower","crate"})
                        end
                    end
                end
            end
            task.wait(rng(1))
        end
    end)
end

-- ══════════════════════════════════════
--  BUILD GUI
-- ══════════════════════════════════════
local sg = Instance.new("ScreenGui")
sg.Name = "AOTR_Farm"
sg.ResetOnSpawn = false
sg.DisplayOrder = 999
sg.IgnoreGuiInset = true
sg.Parent = game:GetService("CoreGui")

local win = Instance.new("Frame", sg)
win.Size = UDim2.new(0, 310, 0, 640)
win.Position = UDim2.new(0, 12, 0, 12)
win.BackgroundColor3 = Color3.fromRGB(12, 12, 17)
win.BorderSizePixel = 0
win.Active = true
win.Draggable = true
win.ClipsDescendants = true
Instance.new("UICorner", win).CornerRadius = UDim.new(0, 10)
local ws = Instance.new("UIStroke", win)
ws.Color = Color3.fromRGB(185, 22, 22)
ws.Thickness = 1.5

-- Header
local hdr = Instance.new("Frame", win)
hdr.Size = UDim2.new(1, 0, 0, 44)
hdr.BackgroundColor3 = Color3.fromRGB(140, 10, 10)
hdr.BorderSizePixel = 0

local htxt = Instance.new("TextLabel", hdr)
htxt.Size = UDim2.new(1, -70, 1, 0)
htxt.Position = UDim2.new(0, 10, 0, 0)
htxt.BackgroundTransparency = 1
htxt.Text = "⚔  AoTR Farming  |  v1.0"
htxt.TextColor3 = Color3.new(1,1,1)
htxt.Font = Enum.Font.GothamBold
htxt.TextSize = 13
htxt.TextXAlignment = Enum.TextXAlignment.Left

local verLbl = Instance.new("TextLabel", win)
verLbl.Size = UDim2.new(1,-10,0,14)
verLbl.Position = UDim2.new(0,10,0,46)
verLbl.BackgroundTransparency = 1
verLbl.Text = "Section 1/4: Farming  •  by Taishotokiyo"
verLbl.TextColor3 = Color3.fromRGB(180,80,80)
verLbl.Font = Enum.Font.Gotham
verLbl.TextSize = 10
verLbl.TextXAlignment = Enum.TextXAlignment.Left

-- Minimize
local mb = Instance.new("TextButton", hdr)
mb.Size = UDim2.new(0,26,0,26)
mb.Position = UDim2.new(1,-32,0.5,-13)
mb.BackgroundColor3 = Color3.fromRGB(80,6,6)
mb.Text = "—"
mb.TextColor3 = Color3.new(1,1,1)
mb.Font = Enum.Font.GothamBold
mb.TextSize = 11
mb.BorderSizePixel = 0
Instance.new("UICorner",mb).CornerRadius = UDim.new(0,5)
local mini = false
mb.MouseButton1Click:Connect(function()
    mini = not mini
    win.Size = mini and UDim2.new(0,310,0,44) or UDim2.new(0,310,0,640)
    mb.Text = mini and "+" or "—"
end)

-- Stats bar
local sbar = Instance.new("Frame", win)
sbar.Size = UDim2.new(1,0,0,26)
sbar.Position = UDim2.new(0,0,0,64)
sbar.BackgroundColor3 = Color3.fromRGB(20,6,6)
sbar.BorderSizePixel = 0
local slbl = Instance.new("TextLabel", sbar)
slbl.Size = UDim2.new(1,-8,1,0)
slbl.Position = UDim2.new(0,8,0,0)
slbl.BackgroundTransparency = 1
slbl.Text = "⚔0 Kills  🎮0 Missions  🔴0 Raids  🔥0 Streak"
slbl.TextColor3 = Color3.fromRGB(255,180,180)
slbl.Font = Enum.Font.Gotham
slbl.TextSize = 10
slbl.TextXAlignment = Enum.TextXAlignment.Left

local function updStats()
    slbl.Text = string.format("⚔%d Kills  🎮%d Missions  🔴%d Raids  🔥%d Streak",
        stats.kills, stats.missions, stats.raids, stats.streak)
end

-- Scroll
local scroll = Instance.new("ScrollingFrame", win)
scroll.Size = UDim2.new(1,0,1,-120)
scroll.Position = UDim2.new(0,0,0,94)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = Color3.fromRGB(185,22,22)
scroll.CanvasSize = UDim2.new(0,0,0,0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
local ll = Instance.new("UIListLayout", scroll)
ll.Padding = UDim.new(0,5)
ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
local lpad = Instance.new("UIPadding", scroll)
lpad.PaddingTop = UDim.new(0,8)
lpad.PaddingBottom = UDim.new(0,10)

-- Status bar
local stbar = Instance.new("Frame", win)
stbar.Size = UDim2.new(1,0,0,24)
stbar.Position = UDim2.new(0,0,1,-24)
stbar.BackgroundColor3 = Color3.fromRGB(140,10,10)
stbar.BorderSizePixel = 0
local stlbl = Instance.new("TextLabel", stbar)
stlbl.Size = UDim2.new(1,-8,1,0)
stlbl.Position = UDim2.new(0,8,0,0)
stlbl.BackgroundTransparency = 1
stlbl.Text = "● Idle"
stlbl.TextColor3 = Color3.fromRGB(255,200,200)
stlbl.Font = Enum.Font.Gotham
stlbl.TextSize = 10
stlbl.TextXAlignment = Enum.TextXAlignment.Left

-- ══════════════════════════════════════
--  UI COMPONENTS
-- ══════════════════════════════════════
local toggleRefs = {}

local function sec(txt)
    local f = Instance.new("Frame", scroll)
    f.Size = UDim2.new(0,284,0,20)
    f.BackgroundTransparency = 1
    local line = Instance.new("Frame",f)
    line.Size = UDim2.new(1,0,0,1)
    line.Position = UDim2.new(0,0,0.5,0)
    line.BackgroundColor3 = Color3.fromRGB(50,15,15)
    line.BorderSizePixel = 0
    local bg = Instance.new("Frame",f)
    bg.Size = UDim2.new(0,160,1,0)
    bg.Position = UDim2.new(0,5,0,0)
    bg.BackgroundColor3 = Color3.fromRGB(12,12,17)
    bg.BorderSizePixel = 0
    local l = Instance.new("TextLabel",bg)
    l.Size = UDim2.new(1,0,1,0)
    l.BackgroundTransparency = 1
    l.Text = "  "..txt
    l.TextColor3 = Color3.fromRGB(205,45,45)
    l.Font = Enum.Font.GothamBold
    l.TextSize = 11
    l.TextXAlignment = Enum.TextXAlignment.Left
end

local function tog(icon, name, desc, key, cb)
    local btn = Instance.new("TextButton", scroll)
    btn.Size = UDim2.new(0,284,0,46)
    btn.BackgroundColor3 = Color3.fromRGB(18,18,26)
    btn.BorderSizePixel = 0
    btn.Text = ""
    btn.AutoButtonColor = false
    Instance.new("UICorner",btn).CornerRadius = UDim.new(0,8)
    local bs = Instance.new("UIStroke",btn)
    bs.Color = Color3.fromRGB(30,30,48)
    bs.Thickness = 1
    local il = Instance.new("TextLabel",btn)
    il.Size = UDim2.new(0,34,1,0)
    il.BackgroundTransparency = 1
    il.Text = icon
    il.TextSize = 15
    il.Font = Enum.Font.GothamBold
    local nl = Instance.new("TextLabel",btn)
    nl.Size = UDim2.new(1,-84,0,20)
    nl.Position = UDim2.new(0,34,0,6)
    nl.BackgroundTransparency = 1
    nl.Text = name
    nl.TextColor3 = Color3.fromRGB(210,210,210)
    nl.Font = Enum.Font.GothamBold
    nl.TextSize = 12
    nl.TextXAlignment = Enum.TextXAlignment.Left
    local dl = Instance.new("TextLabel",btn)
    dl.Size = UDim2.new(1,-84,0,13)
    dl.Position = UDim2.new(0,34,0,27)
    dl.BackgroundTransparency = 1
    dl.Text = desc
    dl.TextColor3 = Color3.fromRGB(110,110,140)
    dl.Font = Enum.Font.Gotham
    dl.TextSize = 10
    dl.TextXAlignment = Enum.TextXAlignment.Left
    local pill = Instance.new("TextLabel",btn)
    pill.Size = UDim2.new(0,36,0,19)
    pill.Position = UDim2.new(1,-42,0.5,-9)
    pill.BackgroundColor3 = Color3.fromRGB(30,30,48)
    pill.Text = "OFF"
    pill.TextColor3 = Color3.fromRGB(110,110,140)
    pill.Font = Enum.Font.GothamBold
    pill.TextSize = 10
    Instance.new("UICorner",pill).CornerRadius = UDim.new(0,4)
    local function ref()
        local on = T[key]
        btn.BackgroundColor3 = on and Color3.fromRGB(36,7,7) or Color3.fromRGB(18,18,26)
        bs.Color = on and Color3.fromRGB(185,22,22) or Color3.fromRGB(30,30,48)
        nl.TextColor3 = on and Color3.fromRGB(255,190,190) or Color3.fromRGB(210,210,210)
        pill.Text = on and "ON" or "OFF"
        pill.BackgroundColor3 = on and Color3.fromRGB(140,10,10) or Color3.fromRGB(30,30,48)
        pill.TextColor3 = on and Color3.new(1,1,1) or Color3.fromRGB(110,110,140)
    end
    btn.MouseButton1Click:Connect(function()
        T[key] = not T[key]
        ref()
        if cb then task.spawn(cb, T[key]) end
    end)
    toggleRefs[key] = ref
    ref()
end

-- Slider helper
local function slider(labelTxt, minV, maxV, defaultV, fmt, onChange)
    local cont = Instance.new("Frame", scroll)
    cont.Size = UDim2.new(0,284,0,48)
    cont.BackgroundColor3 = Color3.fromRGB(18,18,26)
    cont.BorderSizePixel = 0
    Instance.new("UICorner",cont).CornerRadius = UDim.new(0,8)
    Instance.new("UIStroke",cont).Color = Color3.fromRGB(30,30,48)
    local lbl = Instance.new("TextLabel",cont)
    lbl.Size = UDim2.new(1,-10,0,20)
    lbl.Position = UDim2.new(0,10,0,4)
    lbl.BackgroundTransparency = 1
    lbl.Text = string.format(labelTxt..": "..fmt, defaultV)
    lbl.TextColor3 = Color3.fromRGB(200,200,200)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    local track = Instance.new("Frame",cont)
    track.Size = UDim2.new(1,-20,0,6)
    track.Position = UDim2.new(0,10,1,-14)
    track.BackgroundColor3 = Color3.fromRGB(30,20,40)
    track.BorderSizePixel = 0
    Instance.new("UICorner",track).CornerRadius = UDim.new(0,3)
    local pct0 = (defaultV-minV)/(maxV-minV)
    local fill = Instance.new("Frame",track)
    fill.Size = UDim2.new(pct0,0,1,0)
    fill.BackgroundColor3 = Color3.fromRGB(185,22,22)
    fill.BorderSizePixel = 0
    Instance.new("UICorner",fill).CornerRadius = UDim.new(0,3)
    local knob = Instance.new("TextButton",track)
    knob.Size = UDim2.new(0,14,0,14)
    knob.AnchorPoint = Vector2.new(0.5,0.5)
    knob.Position = UDim2.new(pct0,0,0.5,0)
    knob.BackgroundColor3 = Color3.fromRGB(220,40,40)
    knob.Text = ""
    knob.BorderSizePixel = 0
    knob.ZIndex = 5
    Instance.new("UICorner",knob).CornerRadius = UDim.new(1,0)
    local drag = false
    knob.MouseButton1Down:Connect(function() drag=true end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if not drag or i.UserInputType~=Enum.UserInputType.MouseMovement then return end
        local p = math.clamp((i.Position.X - track.AbsolutePosition.X)/track.AbsoluteSize.X,0,1)
        local val = minV + p*(maxV-minV)
        fill.Size = UDim2.new(p,0,1,0)
        knob.Position = UDim2.new(p,0,0.5,0)
        lbl.Text = string.format(labelTxt..": "..fmt, val)
        if onChange then onChange(val) end
    end)
end

-- Position selector
local function posSelector()
    local cont = Instance.new("Frame", scroll)
    cont.Size = UDim2.new(0,284,0,52)
    cont.BackgroundColor3 = Color3.fromRGB(18,18,26)
    cont.BorderSizePixel = 0
    Instance.new("UICorner",cont).CornerRadius = UDim.new(0,8)
    Instance.new("UIStroke",cont).Color = Color3.fromRGB(30,30,48)
    local lbl = Instance.new("TextLabel",cont)
    lbl.Size = UDim2.new(1,-10,0,20)
    lbl.Position = UDim2.new(0,10,0,2)
    lbl.BackgroundTransparency = 1
    lbl.Text = "📍 Position Mode"
    lbl.TextColor3 = Color3.fromRGB(200,200,200)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    local row = Instance.new("Frame",cont)
    row.Size = UDim2.new(1,-20,0,26)
    row.Position = UDim2.new(0,10,0,22)
    row.BackgroundTransparency = 1
    local rl = Instance.new("UIListLayout",row)
    rl.FillDirection = Enum.FillDirection.Horizontal
    rl.Padding = UDim.new(0,6)
    local modes = {"Above","InFront","Behind"}
    local btns = {}
    for _, m in ipairs(modes) do
        local b = Instance.new("TextButton",row)
        b.Size = UDim2.new(0,74,1,0)
        b.BackgroundColor3 = CFG.POSITION_MODE==m and Color3.fromRGB(140,10,10) or Color3.fromRGB(30,20,40)
        b.Text = m
        b.TextColor3 = Color3.new(1,1,1)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 10
        b.BorderSizePixel = 0
        Instance.new("UICorner",b).CornerRadius = UDim.new(0,6)
        btns[m] = b
        b.MouseButton1Click:Connect(function()
            CFG.POSITION_MODE = m
            for _, bm in ipairs(modes) do
                btns[bm].BackgroundColor3 = bm==m and Color3.fromRGB(140,10,10) or Color3.fromRGB(30,20,40)
            end
        end)
    end
end

-- ══════════════════════════════════════
--  BUILD ALL BUTTONS
-- ══════════════════════════════════════
sec("🗡  MISSIONS")
tog("🗡","Autofarm Missions (Blades)","Farms missions using blade attacks","FarmBlade",function(on) if on then farmLoop("mission","blade") end end)
tog("⚙","Autofarm Missions (Titan Ripper)","Farms missions using Titan Ripper","FarmRipper",function(on) if on then farmLoop("mission","ripper") end end)
tog("💥","Autofarm Missions (Thunderspears)","Farms missions using TS","FarmTS",function(on) if on then farmLoop("mission","ts") end end)

sec("🔴  RAIDS")
tog("💥","Autofarm Raids (Thunderspears)","Farms raids using Thunderspears","RaidTS",function(on) if on then farmLoop("raid","ts") end end)
tog("🗡","Autofarm Raids (Blades/Ripper)","Farms raids using Blades or Ripper","RaidBlade",function(on) if on then farmLoop("raid","blade") end end)

sec("⚡  AUTOMATION")
tog("🔥","Auto Streak Farmer","Auto leaves after streak target reached","AutoStreak")
tog("🔗","Auto Connect (Mission/Raid)","Auto joins mission or raid on lobby","AutoConnect",function(on)
    if not on then return end
    task.spawn(function()
        while T.AutoConnect do
            if not inMission() then
                connectToGame("mission")
                task.wait(rng(6,2))
            end
            task.wait(rng(2))
        end
    end)
end)
tog("⚡","Instant TS Quest","Auto completes watchtower/crate quests","InstantTSQuest",function(on) if on then runTSQuest() end end)
tog("🚪","Auto Leave to Lobby","Leaves when max kills reached","AutoLeave")

sec("⚔  COMBAT")
tog("👊","Auto M1","Spams M1 attack on nearest titan","AutoM1")
tog("🪂","Auto Eject","Auto ejects from titan grabs","AutoEject")
tog("📦","Hitbox Extender","Extends nape hitbox radius","HitboxExtender",function(on)
    CFG.HITBOX_SIZE = on and 50 or 30
end)

sec("⚙  SETTINGS")
slider("Kill Delay",  0, 10, CFG.KILL_DELAY,   "%.1fs", function(v) CFG.KILL_DELAY   = v end)
slider("Max Kills",   1, 500,CFG.MAX_KILLS,     "%.0f",  function(v) CFG.MAX_KILLS    = v end)
slider("Boss HP Cut", 0, 1,  CFG.BOSS_HP_CUTOFF,"%.0f%%",function(v) CFG.BOSS_HP_CUTOFF = v end)
slider("Hitbox Size", 5, 80, CFG.HITBOX_SIZE,   "%.0f st",function(v) CFG.HITBOX_SIZE = v end)
slider("Streak Target",1,50, CFG.STREAK_TARGET, "%.0f",  function(v) CFG.STREAK_TARGET= v end)
posSelector()

-- ══════════════════════════════════════
--  HEARTBEAT
-- ══════════════════════════════════════
RunService.Heartbeat:Connect(function()
    local char = lp.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return end
    local now = tick()

    -- Auto M1
    if T.AutoM1 and now - lastM1 > rng(0.08) then
        local titans = getTitans(hrp, 40)
        if #titans > 0 then
            attackTitan(titans[1].model)
            stats.kills = stats.kills + 1
        end
        lastM1 = now
        updStats()
    end

    -- Auto Eject
    if T.AutoEject and now - lastEject > 0.2 then
        local c = lp.Character
        if c then
            for _, v in ipairs(c:GetDescendants()) do
                if v:IsA("BoolValue") and v.Value then
                    local n = v.Name:lower()
                    if n:find("grab") or n:find("caught") or n:find("held") then
                        fireKw({"escape","eject","free","break","grab","release"})
                        hrp.CFrame = hrp.CFrame * CFrame.new(math.random(-12,12), 8, math.random(-12,12))
                        lastEject = now
                    end
                end
            end
        end
    end

    -- Status update
    local active = {}
    for k, v in pairs(T) do if v then table.insert(active, k) end end
    stlbl.Text = #active > 0 and ("● "..table.concat(active," · ")) or "● Idle"
    updStats()
end)

warn("✅ AoTR Farming v1.0 loaded!")
