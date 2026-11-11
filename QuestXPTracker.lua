-- Quest XP Tracker
-- Lists every quest in the quest log with its zone and XP reward, and shows how far
-- the XP from all *active* quests takes you toward the next level.
-- Works on Retail and Classic clients: it uses C_QuestLog when present and falls back
-- to the older GetQuestLogTitle / SelectQuestLogEntry API otherwise.

local ADDON_NAME = ...

----------------------------------------------------------------------------------------
-- Saved data (per character)
----------------------------------------------------------------------------------------
-- QuestXPTrackerDB = {
--   quests   = { [questID] = { title, level, zone, xp } },  -- cache, so quests under
--                                                           -- collapsed headers stay listed
--   excluded = { [questID] = true },                        -- "Inactive": not counted
--   listOpen, sortKey, sortAsc, point = { point, relPoint, x, y }, shown
-- }
local DB

local DEFAULTS = {
    quests   = {},
    excluded = {},
    listOpen = true,
    sortKey  = "xp",
    sortAsc  = false,
    shown    = true,
}

----------------------------------------------------------------------------------------
-- Quest log API wrappers (Retail vs Classic)
----------------------------------------------------------------------------------------
local HAS_INFO = C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetNumQuestLogEntries and true or false
local IsOnQuest = C_QuestLog and C_QuestLog.IsOnQuest

local function NumEntries()
    if HAS_INFO then
        return C_QuestLog.GetNumQuestLogEntries() or 0
    end
    return (GetNumQuestLogEntries()) or 0
end

local function GetEntry(i)
    if HAS_INFO then
        local info = C_QuestLog.GetInfo(i)
        if not info then return nil end
        return {
            title       = info.title,
            level       = info.level,
            isHeader    = info.isHeader,
            isCollapsed = info.isCollapsed,
            questID     = info.questID,
            isHidden    = info.isHidden or info.isBounty,
        }
    end
    local title, level, _, isHeader, isCollapsed, _, _, questID = GetQuestLogTitle(i)
    if not title then return nil end
    return {
        title       = title,
        level       = level,
        isHeader    = isHeader,
        isCollapsed = isCollapsed,
        questID     = questID,
    }
end

-- The modern client (Forever / Midnight) can return "secret" values in some situations;
-- treat those as unknown instead of erroring on arithmetic.
local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

local function ReadXP(index, questID)
    if HAS_INFO then
        return Plain(GetQuestLogRewardXP(questID)) or 0
    end
    -- Classic: the reward functions read the currently selected quest.
    SelectQuestLogEntry(index)
    return Plain(GetQuestLogRewardXP()) or 0
end

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function Fmt(n)
    n = math.floor((n or 0) + 0.5)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    local s = tostring(n)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

local function IsActive(questID)
    return not DB.excluded[questID]
end

local function QuestLink(questID, q)
    if GetQuestLink then
        local ok, link
        if HAS_INFO then
            ok, link = pcall(GetQuestLink, questID)
        elseif q.index then
            ok, link = pcall(GetQuestLink, q.index)
        end
        if ok and link then return link end
    end
    return string.format("|cffffff00|Hquest:%d:%d|h[%s]|h|r", questID, q.level or 0, q.title or "?")
end

local function OpenQuest(questID, q)
    if HAS_INFO and QuestMapFrame_OpenToQuestDetails then
        QuestMapFrame_OpenToQuestDetails(questID)
        return
    end
    if QuestLogFrame and ShowUIPanel then
        ShowUIPanel(QuestLogFrame)
        if q.index and QuestLog_SetSelection then
            QuestLog_SetSelection(q.index)
            if QuestLog_Update then QuestLog_Update() end
        end
    elseif ToggleQuestLog then
        ToggleQuestLog()
    end
end

local function DifficultyColor(level)
    if GetQuestDifficultyColor and level and level > 0 then
        local c = GetQuestDifficultyColor(level)
        if c then return c.r, c.g, c.b end
    end
    return 1, 0.82, 0
end

----------------------------------------------------------------------------------------
-- UI
----------------------------------------------------------------------------------------
local FRAME_W   = 480
local ROW_H     = 18
local LIST_ROWS = 14
local LIST_H    = ROW_H * LIST_ROWS
local CONTENT_W = FRAME_W - 16 - 30   -- room for the scroll bar

-- column x-offsets / widths inside a row
local COL = {
    title = { x = 4,   w = 190 },
    zone  = { x = 198, w = 118 },
    xp    = { x = 318, w = 54 },
    btn   = { x = 378, w = 56 },
}

local frame, bar, projBar, barText, lineNeeded, lineQuests, lineResult
local dropBtn, dropIcon, dropText, colHeader, scroll, content, emptyText
local rows = {}
local Refresh -- forward declaration

frame = CreateFrame("Frame", "QuestXPTrackerFrame", UIParent, "BackdropTemplate")
frame:SetSize(FRAME_W, 140)
frame:SetPoint("CENTER")
frame:SetFrameStrata("MEDIUM")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    if DB then DB.point = { p, rp, x, y } end
end)
frame:SetScript("OnHide", function() if DB then DB.shown = false end end)
frame:SetScript("OnShow", function() if DB then DB.shown = true end; if Refresh then Refresh() end end)
frame:Hide()
tinsert(UISpecialFrames, "QuestXPTrackerFrame") -- Escape closes it

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", 12, -10)
title:SetText("Quest XP Tracker")

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -2, -2)

-- XP bar: projected (current + active quest XP) behind, current XP in front
projBar = CreateFrame("StatusBar", nil, frame)
projBar:SetPoint("TOPLEFT", 12, -34)
projBar:SetSize(FRAME_W - 24, 20)
projBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
projBar:SetStatusBarColor(0.1, 0.85, 0.2, 0.55)
local barBg = projBar:CreateTexture(nil, "BACKGROUND")
barBg:SetAllPoints()
barBg:SetColorTexture(0, 0, 0, 0.6)

bar = CreateFrame("StatusBar", nil, projBar)
bar:SetAllPoints(projBar)
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
bar:SetStatusBarColor(0.58, 0.0, 0.85, 1)
bar:SetFrameLevel(projBar:GetFrameLevel() + 1)

local barBorder = CreateFrame("Frame", nil, bar, "BackdropTemplate")
barBorder:SetPoint("TOPLEFT", -3, 3)
barBorder:SetPoint("BOTTOMRIGHT", 3, -3)
barBorder:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
barBorder:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)

barText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
barText:SetPoint("CENTER")

projBar:EnableMouse(true)
projBar:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Experience")
    GameTooltip:AddLine("Purple: XP you have this level.", 0.75, 0.4, 1)
    GameTooltip:AddLine("Green: XP you get from turning in all active quests.", 0.2, 1, 0.3)
    GameTooltip:Show()
end)
projBar:SetScript("OnLeave", GameTooltip_Hide)

lineNeeded = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
lineNeeded:SetPoint("TOPLEFT", 14, -62)
lineQuests = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
lineQuests:SetPoint("TOPLEFT", 14, -76)
lineResult = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
lineResult:SetPoint("TOPLEFT", 14, -90)

-- Dropdown header
dropBtn = CreateFrame("Button", nil, frame)
dropBtn:SetPoint("TOPLEFT", 10, -108)
dropBtn:SetSize(FRAME_W - 150, 20)
dropIcon = dropBtn:CreateTexture(nil, "ARTWORK")
dropIcon:SetSize(14, 14)
dropIcon:SetPoint("LEFT", 2, 0)
dropText = dropBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
dropText:SetPoint("LEFT", dropIcon, "RIGHT", 6, 0)
local dropHl = dropBtn:CreateTexture(nil, "HIGHLIGHT")
dropHl:SetAllPoints()
dropHl:SetColorTexture(1, 1, 1, 0.06)
dropBtn:SetScript("OnClick", function()
    DB.listOpen = not DB.listOpen
    Refresh()
end)

local function SmallButton(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 18)
    b:SetText(text)
    b:SetNormalFontObject("GameFontNormalSmall")
    b:SetHighlightFontObject("GameFontHighlightSmall")
    b:SetDisabledFontObject("GameFontDisableSmall")
    return b
end

local allOn = SmallButton(frame, "All active", 64)
allOn:SetPoint("TOPRIGHT", -78, -109)
allOn:SetScript("OnClick", function()
    wipe(DB.excluded)
    Refresh()
end)
local allOff = SmallButton(frame, "None", 60)
allOff:SetPoint("TOPRIGHT", -14, -109)
allOff:SetScript("OnClick", function()
    for id in pairs(DB.quests) do DB.excluded[id] = true end
    Refresh()
end)

-- Column headers (click to sort)
colHeader = CreateFrame("Frame", nil, frame)
colHeader:SetPoint("TOPLEFT", 12, -132)
colHeader:SetSize(CONTENT_W, 16)

local headerButtons = {}
local function HeaderButton(key, label, col, justify)
    local b = CreateFrame("Button", nil, colHeader)
    b:SetPoint("TOPLEFT", col.x, 0)
    b:SetSize(col.w, 16)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetAllPoints()
    fs:SetJustifyH(justify or "LEFT")
    b.label, b.fs, b.key = label, fs, key
    b:SetScript("OnClick", function(self)
        if not self.key then return end
        if DB.sortKey == self.key then
            DB.sortAsc = not DB.sortAsc
        else
            DB.sortKey = self.key
            DB.sortAsc = (self.key ~= "xp")
        end
        Refresh()
    end)
    headerButtons[#headerButtons + 1] = b
    return b
end
HeaderButton("title", "Quest", COL.title)
HeaderButton("zone",  "Zone",  COL.zone)
HeaderButton("xp",    "XP",    COL.xp, "RIGHT")
HeaderButton("active", "Counted", COL.btn, "CENTER")

-- Scrolling list
scroll = CreateFrame("ScrollFrame", "QuestXPTrackerScroll", frame, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 12, -150)
scroll:SetSize(CONTENT_W, LIST_H)
content = CreateFrame("Frame", nil, scroll)
content:SetSize(CONTENT_W, LIST_H)
scroll:SetScrollChild(content)

emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
emptyText:SetPoint("TOP", 0, -20)
emptyText:SetText("Your quest log is empty.")

local function Row_OnEnter(self)
    if not self.questID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "quest:" .. self.questID .. ":" .. (self.quest.level or 0))
    if not ok then
        GameTooltip:ClearLines()
        GameTooltip:AddLine(self.quest.title)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("XP reward", Fmt(self.quest.xp), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Zone", self.quest.zone or "?", 1, 1, 1, 1, 1, 1)
    GameTooltip:AddLine("Shift-click: link in chat. Click: open in quest log.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function Row_OnClick(self)
    if not self.questID then return end
    if IsModifiedClick and IsModifiedClick("CHATLINK") or IsShiftKeyDown() then
        local link = QuestLink(self.questID, self.quest)
        if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return end
        if ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
    else
        OpenQuest(self.questID, self.quest)
    end
end

local function GetRow(i)
    if rows[i] then return rows[i] end
    local row = CreateFrame("Button", nil, content)
    row:SetSize(CONTENT_W, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:RegisterForClicks("LeftButtonUp")

    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints()
    stripe:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.12)

    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.title:SetPoint("LEFT", COL.title.x, 0)
    row.title:SetWidth(COL.title.w)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)

    row.zone = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.zone:SetPoint("LEFT", COL.zone.x, 0)
    row.zone:SetWidth(COL.zone.w)
    row.zone:SetJustifyH("LEFT")
    row.zone:SetWordWrap(false)

    row.xp = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.xp:SetPoint("LEFT", COL.xp.x, 0)
    row.xp:SetWidth(COL.xp.w)
    row.xp:SetJustifyH("RIGHT")

    row.toggle = SmallButton(row, "Active", COL.btn.w)
    row.toggle:SetHeight(ROW_H - 2)
    row.toggle:SetPoint("LEFT", COL.btn.x, 0)
    row.toggle:SetScript("OnClick", function(btn)
        local id = btn:GetParent().questID
        if not id then return end
        if DB.excluded[id] then DB.excluded[id] = nil else DB.excluded[id] = true end
        Refresh()
    end)

    row:SetScript("OnEnter", Row_OnEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", Row_OnClick)
    rows[i] = row
    return row
end

----------------------------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------------------------
local function SortedQuests()
    local list = {}
    for id, q in pairs(DB.quests) do
        list[#list + 1] = { id = id, q = q, active = IsActive(id) }
    end
    local key, asc = DB.sortKey, DB.sortAsc
    table.sort(list, function(a, b)
        local va, vb
        if key == "xp" then
            va, vb = a.q.xp or 0, b.q.xp or 0
        elseif key == "zone" then
            va, vb = a.q.zone or "", b.q.zone or ""
        elseif key == "active" then
            va, vb = a.active and 1 or 0, b.active and 1 or 0
        else
            va, vb = a.q.title or "", b.q.title or ""
        end
        if va == vb then return (a.q.title or "") < (b.q.title or "") end
        if asc then return va < vb else return va > vb end
    end)
    return list
end

Refresh = function()
    if not DB or not frame:IsShown() then return end

    -- totals
    local list = SortedQuests()
    local total, activeCount = 0, 0
    for _, e in ipairs(list) do
        if e.active then
            total = total + (e.q.xp or 0)
            activeCount = activeCount + 1
        end
    end

    -- XP bar
    local level = Plain(UnitLevel("player")) or 0
    local cur, max = Plain(UnitXP("player")) or 0, Plain(UnitXPMax("player")) or 0
    local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel()
    local atMax = (max == 0) or (maxLevel and level >= maxLevel)

    if atMax then
        bar:SetMinMaxValues(0, 1); bar:SetValue(1)
        projBar:SetMinMaxValues(0, 1); projBar:SetValue(1)
        barText:SetText("Level " .. level .. " (max level)")
        lineNeeded:SetText("")
        lineQuests:SetText("Active quests: " .. Fmt(total) .. " XP")
        lineResult:SetText("")
    else
        local needed = max - cur
        bar:SetMinMaxValues(0, max); bar:SetValue(cur)
        projBar:SetMinMaxValues(0, max); projBar:SetValue(math.min(cur + total, max))
        barText:SetText(string.format("Level %d:  %s / %s XP  (%d%%)", level, Fmt(cur), Fmt(max), math.floor(cur / max * 100)))
        lineNeeded:SetText(string.format("XP needed for level %d:  |cffffffff%s|r  (level %d needs %s XP in total)",
            level + 1, Fmt(needed), level, Fmt(max)))
        lineQuests:SetText(string.format("XP from active quests:  |cff20ff20%s|r  (%d%% of this level)",
            Fmt(total), math.floor(total / max * 100)))
        if total >= needed then
            lineResult:SetText(string.format("|cff20ff20Enough to level up!|r  %s XP over into level %d",
                Fmt(total - needed), level + 1))
        else
            lineResult:SetText(string.format("|cffff8040Still short after turning them all in:|r  %s XP", Fmt(needed - total)))
        end
    end

    -- dropdown header
    dropIcon:SetTexture(DB.listOpen and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
    dropText:SetText(string.format("Quests in log: %d  (%d active)", #list, activeCount))

    colHeader:SetShown(DB.listOpen)
    scroll:SetShown(DB.listOpen)
    allOn:SetShown(DB.listOpen)
    allOff:SetShown(DB.listOpen)
    frame:SetHeight(DB.listOpen and (150 + LIST_H + 12) or 138)

    for _, b in ipairs(headerButtons) do
        local label = b.label
        if b.key == DB.sortKey then
            b.fs:SetTextColor(1, 1, 1)
            label = label .. (DB.sortAsc and " ^" or " v")
        else
            b.fs:SetTextColor(1, 0.82, 0)
        end
        b.fs:SetText(label)
    end

    if not DB.listOpen then return end

    -- rows
    for i, e in ipairs(list) do
        local row = GetRow(i)
        row.questID, row.quest = e.id, e.q
        local r, g, b = DifficultyColor(e.q.level)
        local lvl = (e.q.level and e.q.level > 0) and ("[" .. e.q.level .. "] ") or ""
        row.title:SetText(lvl .. (e.q.title or "?"))
        row.title:SetTextColor(r, g, b)
        row.zone:SetText(e.q.zone or "")
        row.xp:SetText(Fmt(e.q.xp))
        local alpha = e.active and 1 or 0.4
        row.title:SetAlpha(alpha); row.zone:SetAlpha(alpha); row.xp:SetAlpha(alpha)
        row.toggle:SetText(e.active and "Active" or "Inactive")
        row:Show()
    end
    for i = #list + 1, #rows do
        rows[i]:Hide()
        rows[i].questID = nil
    end
    emptyText:SetShown(#list == 0)
    content:SetHeight(math.max(#list * ROW_H, LIST_H))
end

----------------------------------------------------------------------------------------
-- Scanning
----------------------------------------------------------------------------------------
local scanAfterCombat = false
local function ScanQuestLog()
    if not DB then return end
    if InCombatLockdown and InCombatLockdown() then
        scanAfterCombat = true   -- rescan on PLAYER_REGEN_ENABLED
        Refresh()
        return
    end
    local n = NumEntries()
    if n == 0 then
        -- Can be a not-yet-loaded log at login; only clear the cache when the game
        -- can confirm we're on none of the cached quests.
        if IsOnQuest then
            for id in pairs(DB.quests) do
                if not IsOnQuest(id) then DB.quests[id] = nil; DB.excluded[id] = nil end
            end
        end
        Refresh()
        return
    end

    local prevSel = (not HAS_INFO and GetQuestLogSelection) and GetQuestLogSelection() or nil
    local seen, zone, sawCollapsed = {}, UNKNOWN or "Unknown", false

    for i = 1, n do
        local e = GetEntry(i)
        if e then
            if e.isHeader then
                zone = e.title or zone
                if e.isCollapsed then sawCollapsed = true end
            elseif e.questID and e.questID > 0 and e.title and not e.isHidden then
                local q = DB.quests[e.questID] or {}
                q.title = e.title
                q.level = e.level
                q.zone  = zone
                q.xp    = ReadXP(i, e.questID)
                q.index = i
                DB.quests[e.questID] = q
                seen[e.questID] = true
            end
        end
    end

    if prevSel and prevSel > 0 and SelectQuestLogEntry then
        SelectQuestLogEntry(prevSel)
    end

    -- Forget quests that are no longer in the log. Quests hidden under a collapsed
    -- header are kept (with their last known XP) until they're turned in or abandoned.
    for id, q in pairs(DB.quests) do
        if not seen[id] then
            q.index = nil
            local keep
            if IsOnQuest then keep = IsOnQuest(id) else keep = sawCollapsed end
            if not keep then
                DB.quests[id] = nil
                DB.excluded[id] = nil
            end
        end
    end

    Refresh()
end

local scanPending = false
local function QueueScan()
    if scanPending then return end
    scanPending = true
    C_Timer.After(0.3, function()
        scanPending = false
        ScanQuestLog()
    end)
end

----------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------
local events = CreateFrame("Frame")

local function SafeRegister(ev)
    pcall(events.RegisterEvent, events, ev)
end

events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        QuestXPTrackerDB = QuestXPTrackerDB or {}
        DB = QuestXPTrackerDB
        for k, v in pairs(DEFAULTS) do
            if DB[k] == nil then DB[k] = (type(v) == "table") and {} or v end
        end
        if DB.point then
            frame:ClearAllPoints()
            frame:SetPoint(DB.point[1], UIParent, DB.point[2], DB.point[3], DB.point[4])
        end
        events:UnregisterEvent("ADDON_LOADED")
        SafeRegister("PLAYER_ENTERING_WORLD")
        SafeRegister("QUEST_LOG_UPDATE")
        SafeRegister("QUEST_ACCEPTED")
        SafeRegister("QUEST_REMOVED")
        SafeRegister("QUEST_TURNED_IN")
        SafeRegister("PLAYER_LEVEL_UP")
        SafeRegister("PLAYER_XP_UPDATE")
        SafeRegister("PLAYER_REGEN_ENABLED")
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if scanAfterCombat then
            scanAfterCombat = false
            QueueScan()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if DB.shown then frame:Show() end
        QueueScan()
    elseif (event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED") and arg1 then
        DB.quests[arg1] = nil
        DB.excluded[arg1] = nil
        QueueScan()
    elseif event == "PLAYER_XP_UPDATE" then
        Refresh()
    else
        QueueScan()
    end
end)

----------------------------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------------------------
SLASH_QUESTXPTRACKER1 = "/qxp"
SLASH_QUESTXPTRACKER2 = "/questxp"
SlashCmdList.QUESTXPTRACKER = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "reset" then
        DB.point = nil
        frame:ClearAllPoints()
        frame:SetPoint("CENTER")
        frame:Show()
        print("|cffffd200Quest XP Tracker:|r window position reset.")
    elseif msg == "scan" then
        ScanQuestLog()
    else
        frame:SetShown(not frame:IsShown())
        if frame:IsShown() then QueueScan() end
    end
end
