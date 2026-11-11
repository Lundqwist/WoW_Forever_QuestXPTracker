-- Quest XP Tracker
-- Lists every quest in the quest log, grouped by zone, with its XP reward, and shows how
-- far the XP from all *active* quests takes you toward the next level.
-- Also provides a minimap button and a LibDataBroker feed (shown by Titan Panel).
-- Works on Retail-style clients (WoW Forever, Midnight) through C_QuestLog and falls back
-- to the older GetQuestLogTitle / SelectQuestLogEntry API otherwise.

local ADDON_NAME = ...
local ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\QxpIcon"

----------------------------------------------------------------------------------------
-- Saved data (per character)
----------------------------------------------------------------------------------------
-- QuestXPTrackerDB = {
--   quests        = { [questID] = { title, level, zone, xp } },  -- cache, so quests under
--                                                                -- collapsed log headers stay listed
--   excluded      = { [questID] = true },                        -- "Inactive": not counted
--   collapsedZones = { [zone] = true },                          -- zone groups folded in our list
--   minimap       = { angle = degrees, hide = bool },
--   listOpen, sortKey, sortAsc, point = { point, relPoint, x, y }, shown
-- }
local DB

local DEFAULTS = {
    quests         = {},
    excluded       = {},
    collapsedZones = {},
    minimap        = {},
    listOpen       = true,
    sortKey        = "xp",
    sortAsc        = false,
    shown          = true,
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
-- Totals (shared by the window, the minimap tooltip and the Titan / LDB feed)
----------------------------------------------------------------------------------------
local function GetSummary()
    local s = { total = 0, count = 0, active = 0 }
    for id, q in pairs(DB.quests) do
        s.count = s.count + 1
        if IsActive(id) then
            s.active = s.active + 1
            s.total = s.total + (q.xp or 0)
        end
    end
    s.level = Plain(UnitLevel("player")) or 0
    s.cur = Plain(UnitXP("player")) or 0
    s.max = Plain(UnitXPMax("player")) or 0
    local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel()
    s.atMax = (s.max == 0) or (maxLevel and s.level >= maxLevel) or false
    s.needed = math.max(s.max - s.cur, 0)
    return s
end

local function AddSummaryLines(tt, s)
    if s.atMax then
        tt:AddDoubleLine("Level", s.level .. " (max)", 1, 1, 1, 1, 1, 1)
    else
        tt:AddDoubleLine("Level " .. s.level, Fmt(s.cur) .. " / " .. Fmt(s.max), 1, 1, 1, 1, 1, 1)
        tt:AddDoubleLine("Needed to level", Fmt(s.needed), 1, 1, 1, 1, 1, 1)
    end
    tt:AddDoubleLine(string.format("Active quests (%d/%d)", s.active, s.count), Fmt(s.total) .. " XP", 1, 1, 1, 0.2, 1, 0.3)
    if not s.atMax then
        if s.total >= s.needed then
            tt:AddLine(string.format("Enough to level! %s XP over.", Fmt(s.total - s.needed)), 0.2, 1, 0.3)
        else
            tt:AddLine(string.format("Short by %s XP after turning in.", Fmt(s.needed - s.total)), 1, 0.5, 0.25)
        end
    end
end

----------------------------------------------------------------------------------------
-- Main window
----------------------------------------------------------------------------------------
local FRAME_W   = 480
local ROW_H     = 18
local LIST_ROWS = 14
local LIST_H    = ROW_H * LIST_ROWS
local CONTENT_W = FRAME_W - 16 - 30   -- room for the scroll bar
local INDENT    = 18

-- column x-offsets / widths inside a row
local COL = {
    title = { x = 4,   w = 300 },
    xp    = { x = 308, w = 64 },
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

local titleIcon = frame:CreateTexture(nil, "OVERLAY")
titleIcon:SetSize(20, 20)
titleIcon:SetPoint("TOPLEFT", 10, -6)
titleIcon:SetTexture(ICON)

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("LEFT", titleIcon, "RIGHT", 6, 0)
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
HeaderButton("title",  "Zone / Quest", COL.title)
HeaderButton("xp",     "XP",           COL.xp, "RIGHT")
HeaderButton("active", "Counted",      COL.btn, "CENTER")

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

----------------------------------------------------------------------------------------
-- List rows: one frame type used for both zone headers and quests
----------------------------------------------------------------------------------------
local function Row_OnEnter(self)
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if e.kind == "zone" then
        GameTooltip:AddLine(e.zone)
        GameTooltip:AddDoubleLine("Quests", e.count, 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Active", e.active, 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Active XP", Fmt(e.xp), 1, 1, 1, 0.2, 1, 0.3)
        GameTooltip:AddLine("Click to fold or unfold.", 0.6, 0.6, 0.6)
    else
        local q = e.q
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "quest:" .. e.id .. ":" .. (q.level or 0))
        if not ok then
            GameTooltip:ClearLines()
            GameTooltip:AddLine(q.title)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("XP reward", Fmt(q.xp), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Zone", q.zone or "?", 1, 1, 1, 1, 1, 1)
        GameTooltip:AddLine("Shift-click: link in chat. Click: open in quest log.", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function Row_OnClick(self)
    local e = self.entry
    if not e then return end
    if e.kind == "zone" then
        DB.collapsedZones[e.zone] = (not DB.collapsedZones[e.zone]) or nil
        Refresh()
        return
    end
    if (IsModifiedClick and IsModifiedClick("CHATLINK")) or IsShiftKeyDown() then
        local link = QuestLink(e.id, e.q)
        if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return end
        if ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
    else
        OpenQuest(e.id, e.q)
    end
end

local function Toggle_OnClick(btn)
    local e = btn:GetParent().entry
    if not e then return end
    if e.kind == "zone" then
        -- all active -> make the whole zone inactive; otherwise make it all active
        local makeInactive = (e.active == e.count)
        for id, q in pairs(DB.quests) do
            if q.zone == e.zone then
                DB.excluded[id] = makeInactive or nil
            end
        end
    else
        DB.excluded[e.id] = (not DB.excluded[e.id]) or nil
    end
    Refresh()
end

local function GetRow(i)
    if rows[i] then return rows[i] end
    local row = CreateFrame("Button", nil, content)
    row:SetSize(CONTENT_W, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:RegisterForClicks("LeftButtonUp")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.12)

    row.fold = row:CreateTexture(nil, "ARTWORK")
    row.fold:SetSize(12, 12)
    row.fold:SetPoint("LEFT", COL.title.x, 0)

    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)

    row.xp = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.xp:SetPoint("LEFT", COL.xp.x, 0)
    row.xp:SetWidth(COL.xp.w)
    row.xp:SetJustifyH("RIGHT")

    row.toggle = SmallButton(row, "Active", COL.btn.w)
    row.toggle:SetHeight(ROW_H - 2)
    row.toggle:SetPoint("LEFT", COL.btn.x, 0)
    row.toggle:SetScript("OnClick", Toggle_OnClick)

    row:SetScript("OnEnter", Row_OnEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", Row_OnClick)
    rows[i] = row
    return row
end

local function SetRowTitle(row, x)
    row.title:ClearAllPoints()
    row.title:SetPoint("LEFT", x, 0)
    row.title:SetWidth(COL.title.w - (x - COL.title.x))
end

local function FillZoneRow(row, e)
    row.bg:SetColorTexture(0.35, 0.2, 0.55, 0.35)
    row.fold:Show()
    row.fold:SetTexture(DB.collapsedZones[e.zone] and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
    SetRowTitle(row, COL.title.x + 16)
    row.title:SetFontObject("GameFontNormal")
    row.title:SetText(string.format("%s  |cffaaaaaa(%d/%d)|r", e.zone, e.active, e.count))
    row.title:SetTextColor(1, 0.82, 0)
    row.xp:SetText("|cff20ff20" .. Fmt(e.xp) .. "|r")
    row.title:SetAlpha(1); row.xp:SetAlpha(1)
    if e.active == e.count then
        row.toggle:SetText("Active")
    elseif e.active == 0 then
        row.toggle:SetText("Inactive")
    else
        row.toggle:SetText("Mixed")
    end
end

local function FillQuestRow(row, e, stripe)
    row.bg:SetColorTexture(1, 1, 1, stripe and 0.04 or 0)
    row.fold:Hide()
    SetRowTitle(row, COL.title.x + INDENT)
    local r, g, b = DifficultyColor(e.q.level)
    local lvl = (e.q.level and e.q.level > 0) and ("[" .. e.q.level .. "] ") or ""
    row.title:SetFontObject("GameFontNormalSmall")
    row.title:SetText(lvl .. (e.q.title or "?"))
    row.title:SetTextColor(r, g, b)
    row.xp:SetText(Fmt(e.q.xp))
    local alpha = e.active and 1 or 0.4
    row.title:SetAlpha(alpha); row.xp:SetAlpha(alpha)
    row.toggle:SetText(e.active and "Active" or "Inactive")
end

----------------------------------------------------------------------------------------
-- Building the grouped list
----------------------------------------------------------------------------------------
local function Compare(va, vb, asc, tieA, tieB)
    if va == vb then return tieA < tieB end
    if asc then return va < vb else return va > vb end
end

local function BuildEntries()
    local zones, byZone = {}, {}
    for id, q in pairs(DB.quests) do
        local zname = q.zone or (UNKNOWN or "Unknown")
        local z = byZone[zname]
        if not z then
            z = { kind = "zone", zone = zname, count = 0, active = 0, xp = 0, quests = {} }
            byZone[zname] = z
            zones[#zones + 1] = z
        end
        local active = IsActive(id)
        z.count = z.count + 1
        if active then
            z.active = z.active + 1
            z.xp = z.xp + (q.xp or 0)
        end
        z.quests[#z.quests + 1] = { kind = "quest", id = id, q = q, active = active }
    end

    local key, asc = DB.sortKey, DB.sortAsc
    table.sort(zones, function(a, b)
        if key == "xp" then return Compare(a.xp, b.xp, asc, a.zone, b.zone) end
        if key == "active" then return Compare(a.active, b.active, asc, a.zone, b.zone) end
        return Compare(a.zone, b.zone, asc, a.zone, b.zone)
    end)

    local list = {}
    for _, z in ipairs(zones) do
        table.sort(z.quests, function(a, b)
            local ta, tb = a.q.title or "", b.q.title or ""
            if key == "xp" then return Compare(a.q.xp or 0, b.q.xp or 0, asc, ta, tb) end
            if key == "active" then return Compare(a.active and 1 or 0, b.active and 1 or 0, asc, ta, tb) end
            return Compare(ta, tb, asc, ta, tb)
        end)
        list[#list + 1] = z
        if not DB.collapsedZones[z.zone] then
            for _, e in ipairs(z.quests) do list[#list + 1] = e end
        end
    end
    return list
end

----------------------------------------------------------------------------------------
-- Minimap button
----------------------------------------------------------------------------------------
local minimapBtn = CreateFrame("Button", "QuestXPTrackerMinimapButton", Minimap)
minimapBtn:SetSize(31, 31)
minimapBtn:SetFrameStrata("MEDIUM")
minimapBtn:SetFrameLevel(8)
minimapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minimapBtn:RegisterForDrag("LeftButton")
minimapBtn:SetHighlightTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight

local modernMinimap = AddonCompartmentFrame ~= nil
local mmBg = minimapBtn:CreateTexture(nil, "BACKGROUND")
mmBg:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background
local mmIcon = minimapBtn:CreateTexture(nil, "ARTWORK")
mmIcon:SetTexture(ICON)
local mmBorder = minimapBtn:CreateTexture(nil, "OVERLAY")
mmBorder:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder
mmBorder:SetPoint("TOPLEFT")
if modernMinimap then
    mmBg:SetSize(24, 24);   mmBg:SetPoint("CENTER")
    mmIcon:SetSize(20, 20); mmIcon:SetPoint("CENTER")
    mmBorder:SetSize(50, 50)
else
    mmBg:SetSize(20, 20);   mmBg:SetPoint("TOPLEFT", 7, -5)
    mmIcon:SetSize(19, 19); mmIcon:SetPoint("TOPLEFT", 6, -6)
    mmBorder:SetSize(53, 53)
end

local function PlaceMinimapButton()
    local angle = math.rad(DB and DB.minimap.angle or 200)
    local x, y = math.cos(angle), math.sin(angle)
    local w = (Minimap:GetWidth() / 2) + 5
    local h = (Minimap:GetHeight() / 2) + 5
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    minimapBtn:ClearAllPoints()
    if shape == "SQUARE" then
        x = math.max(-w, math.min(x * w * 1.42, w))
        y = math.max(-h, math.min(y * h * 1.42, h))
        minimapBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    else
        minimapBtn:SetPoint("CENTER", Minimap, "CENTER", x * w, y * h)
    end
end

local function MinimapDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    DB.minimap.angle = math.deg(math.atan2(py - my, px - mx)) % 360
    PlaceMinimapButton()
end

minimapBtn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", MinimapDragUpdate)
    GameTooltip:Hide()
end)
minimapBtn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
end)

local function ToggleWindow()
    frame:SetShown(not frame:IsShown())
end

local function ShowBrokerTooltip(tt)
    tt:AddLine("Quest XP Tracker")
    AddSummaryLines(tt, GetSummary())
    tt:AddLine(" ")
    tt:AddLine("Left-click: show / hide the window", 0.6, 0.6, 0.6)
    tt:AddLine("Right-click: fold / unfold the quest list", 0.6, 0.6, 0.6)
end

local function BrokerClick(button)
    if button == "RightButton" then
        DB.listOpen = not DB.listOpen
        if not frame:IsShown() then frame:Show() end
        Refresh()
    else
        ToggleWindow()
    end
end

minimapBtn:SetScript("OnClick", function(_, button) BrokerClick(button) end)
minimapBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    ShowBrokerTooltip(GameTooltip)
    GameTooltip:AddLine("Drag: move around the minimap", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
minimapBtn:SetScript("OnLeave", GameTooltip_Hide)

-- Addon compartment (the addon list button by the minimap on modern clients)
function QuestXPTracker_OnAddonCompartmentClick(_, button)
    BrokerClick(button)
end

----------------------------------------------------------------------------------------
-- LibDataBroker feed: Titan Panel (and other broker displays) pick this up
----------------------------------------------------------------------------------------
local broker
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
if LDB then
    broker = LDB:NewDataObject(ADDON_NAME, {
        type  = "data source",
        label = "Qxp",
        text  = "0 XP",
        icon  = ICON,
        OnClick = function(_, button) BrokerClick(button) end,
        OnTooltipShow = function(tt) ShowBrokerTooltip(tt) end,
    })
end

local function UpdateBroker(s)
    if not broker then return end
    if s.atMax then
        broker.text = Fmt(s.total) .. " XP"
    elseif s.total >= s.needed and s.needed > 0 then
        broker.text = "|cff20ff20" .. Fmt(s.total) .. "|r / " .. Fmt(s.needed) .. " XP"
    else
        broker.text = Fmt(s.total) .. " / " .. Fmt(s.needed) .. " XP"
    end
end

----------------------------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------------------------
Refresh = function()
    if not DB then return end
    local s = GetSummary()
    UpdateBroker(s)
    if not frame:IsShown() then return end

    -- XP bar
    if s.atMax then
        bar:SetMinMaxValues(0, 1); bar:SetValue(1)
        projBar:SetMinMaxValues(0, 1); projBar:SetValue(1)
        barText:SetText("Level " .. s.level .. " (max level)")
        lineNeeded:SetText("")
        lineQuests:SetText("Active quests: " .. Fmt(s.total) .. " XP")
        lineResult:SetText("")
    else
        bar:SetMinMaxValues(0, s.max); bar:SetValue(s.cur)
        projBar:SetMinMaxValues(0, s.max); projBar:SetValue(math.min(s.cur + s.total, s.max))
        barText:SetText(string.format("Level %d:  %s / %s XP  (%d%%)", s.level, Fmt(s.cur), Fmt(s.max), math.floor(s.cur / s.max * 100)))
        lineNeeded:SetText(string.format("XP needed for level %d:  |cffffffff%s|r  (level %d needs %s XP in total)",
            s.level + 1, Fmt(s.needed), s.level, Fmt(s.max)))
        lineQuests:SetText(string.format("XP from active quests:  |cff20ff20%s|r  (%d%% of this level)",
            Fmt(s.total), math.floor(s.total / s.max * 100)))
        if s.total >= s.needed then
            lineResult:SetText(string.format("|cff20ff20Enough to level up!|r  %s XP over into level %d",
                Fmt(s.total - s.needed), s.level + 1))
        else
            lineResult:SetText(string.format("|cffff8040Still short after turning them all in:|r  %s XP", Fmt(s.needed - s.total)))
        end
    end

    -- dropdown header
    dropIcon:SetTexture(DB.listOpen and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
    dropText:SetText(string.format("Quests in log: %d  (%d active)", s.count, s.active))

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
    local list = BuildEntries()
    local stripe = false
    for i, e in ipairs(list) do
        local row = GetRow(i)
        row.entry = e
        if e.kind == "zone" then
            FillZoneRow(row, e)
            stripe = false
        else
            stripe = not stripe
            FillQuestRow(row, e, stripe)
        end
        row:Show()
    end
    for i = #list + 1, #rows do
        rows[i]:Hide()
        rows[i].entry = nil
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
        if DB.sortKey == "zone" then DB.sortKey = "title" end -- column removed in 1.1
        if DB.point then
            frame:ClearAllPoints()
            frame:SetPoint(DB.point[1], UIParent, DB.point[2], DB.point[3], DB.point[4])
        end
        PlaceMinimapButton()
        minimapBtn:SetShown(not DB.minimap.hide)
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
        PlaceMinimapButton()
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
    elseif msg == "minimap" then
        DB.minimap.hide = not DB.minimap.hide
        minimapBtn:SetShown(not DB.minimap.hide)
        print("|cffffd200Quest XP Tracker:|r minimap button " .. (DB.minimap.hide and "hidden" or "shown") .. ".")
    else
        ToggleWindow()
        if frame:IsShown() then QueueScan() end
    end
end
