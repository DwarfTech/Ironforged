-- Ironforged: main window with a side navigation of tabs.
local ADDON, ns = ...
local UI = ns.UI

local tabs = {}      -- ordered { id, label, build, refresh, frame, button }
local main
local current

-- `headerOnly` tabs have no button in the side list; a header button opens them.
function UI.RegisterTab(id, label, build, refresh, headerOnly)
  tabs[#tabs + 1] = { id = id, label = label, build = build, refresh = refresh, headerOnly = headerOnly }
end

local CONTENT_W, CONTENT_H = 640, 452
local DEFAULT_W, DEFAULT_H = CONTENT_W + 170, CONTENT_H + 88
local MIN_W, MIN_H = 720, 480
local MAX_W, MAX_H = 1500, 1100
local NAV_BASE = 156 -- width of the side list at the default window size

-- Sections of the side list. Tabs not named here go just above Settings.
local NAV_SECTIONS = {
  { title = "Guild Management", ids = { "roster", "clans", "trials", "events" } },
  { title = "In Game", ids = { "lfd", "professions", "challenges" } },
  { title = "Roleplay", ids = { "grudges", "blood", "titles", "profile" } },
  { ids = { "settings" } },
}

local function selectTab(id)
  for _, t in ipairs(tabs) do
    if t.id == id then
      if not t.frame then
        t.frame = CreateFrame("Frame", nil, main.content)
        t.frame:SetAllPoints()
        t.build(t.frame, CONTENT_W, CONTENT_H)
      end
      t.frame:Show()
      if t.button then
        t.button:LockHighlight()
        if t.button.SetBackdropColor then t.button:SetBackdropColor(0.5, 0.33, 0.12, 1) end
      end
      current = t
      if t.refresh then t.refresh(t.frame) end
    else
      if t.frame then t.frame:Hide() end
      if t.button then
        t.button:UnlockHighlight()
        if t.button.SetBackdropColor then t.button:SetBackdropColor(0.28, 0.18, 0.08, 0.95) end
      end
    end
  end
end
UI.SelectTab = selectTab

function UI.UpdateLanguageButton()
  local b = main and main.langButton
  if not b then return end
  local known = ns.Lang.Dwarvish() ~= nil
  if ns.Lang.IsOn() and known then
    b:SetText("Dwarvish: ON")
    if b.SetBackdropColor then
      b:SetBackdropColor(0.55, 0.36, 0.1, 1)
      b:SetBackdropBorderColor(1, 0.82, 0.35, 1)
    end
  else
    b:SetText(known and "Dwarvish: OFF" or "Dwarvish (dwarves only)")
    if b.SetBackdropColor then
      b:SetBackdropColor(0.18, 0.12, 0.06, 0.95)
      b:SetBackdropBorderColor(0.5, 0.36, 0.16, 1)
    end
  end
  b:SetEnabled(known)
end
ns.On("LANGUAGE", function() UI.UpdateLanguageButton() end)

-- keep the subtitle clear of the header buttons
local function fitSubtitle()
  if not main then return end
  local left = main.gambleButton:GetLeft()
  local x0 = main.subtitle:GetLeft()
  if left and x0 and left - x0 - 10 > 60 then main.subtitle:SetWidth(left - x0 - 10) else main.subtitle:SetWidth(300) end
end

local function saveSize()
  if not main or not ns.db then return end
  ns.db.mainSize = { w = math.floor((main:GetWidth() or DEFAULT_W) + 0.5), h = math.floor((main:GetHeight() or DEFAULT_H) + 0.5) }
end

-- The side list grows with the window; content fills the rest.
local function layoutNav(w)
  if not main then return end
  local navW = math.floor(math.max(NAV_BASE - 12, math.min(NAV_BASE * 1.5, NAV_BASE * (w or DEFAULT_W) / DEFAULT_W)) + 0.5)
  for _, e in ipairs(main.navLines or {}) do
    e.line:ClearAllPoints()
    e.line:SetPoint("TOPLEFT", main, "TOPLEFT", 16, e.y)
    e.line:SetPoint("TOPRIGHT", main, "TOPLEFT", navW - 12, e.y)
  end
  for _, e in ipairs(main.navButtons or {}) do
    e.b:ClearAllPoints()
    e.b:SetPoint("TOPLEFT", main, "TOPLEFT", 14, e.y)
    e.b:SetPoint("TOPRIGHT", main, "TOPLEFT", navW - 10, e.y)
  end
  main.content:ClearAllPoints()
  main.content:SetPoint("TOPLEFT", main, "TOPLEFT", navW, -72)
  main.content:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -14, 16)
end

local function updateHeader()
  if not main then return end
  UI.ApplyEmblem(main.emblem, main.shield, true)
  UI.UpdateLanguageButton()
  local officer = ns.IAmOfficer()
  main.cheersButton:SetShown(officer)
  main.gambleButton:ClearAllPoints()
  main.gambleButton:SetPoint("RIGHT", officer and main.cheersButton or main.langButton, "LEFT", -6, 0)
  main.motto:Hide()
  main.title:SetText(ns.Data.GuildDisplayName())
  local me = ns.PlayerName()
  local info = me and ns.roster[me]
  local status = ns.IAmOfficer() and "Officer of the hold" or (info and info.rankName or "")
  local online = 0
  for _, i in pairs(ns.roster) do if i.online then online = online + 1 end end
  main.subtitle:SetText(string.format("%s  |cff999999-  %d of %d online|r", status, online, #ns.rosterList))
  fitSubtitle()
end

local function build()
  main = CreateFrame("Frame", "IronforgedMainFrame", UIParent, "BackdropTemplate")
  local sz = ns.db and ns.db.mainSize
  local startW = math.max(MIN_W, math.min(MAX_W, tonumber(sz and sz.w) or DEFAULT_W))
  local startH = math.max(MIN_H, math.min(MAX_H, tonumber(sz and sz.h) or DEFAULT_H))
  main:SetSize(startW, startH)
  main:SetPoint("CENTER")
  main:SetResizable(true)
  if main.SetResizeBounds then main:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
  elseif main.SetMinResize then main:SetMinResize(MIN_W, MIN_H); if main.SetMaxResize then main:SetMaxResize(MAX_W, MAX_H) end end
  main:SetFrameStrata("HIGH")
  main:SetToplevel(true)
  main:EnableMouse(true)
  main:SetMovable(true)
  main:SetClampedToScreen(true)
  main:RegisterForDrag("LeftButton")
  main:SetScript("OnDragStart", main.StartMoving)
  main:SetScript("OnDragStop", main.StopMovingOrSizing)
  UI.Backdrop(main)
  tinsert(UISpecialFrames, "IronforgedMainFrame")

  -- guild emblem on a round shield
  local shield = main:CreateTexture(nil, "ARTWORK")
  shield:SetSize(46, 46)
  shield:SetPoint("TOPLEFT", 14, -12)
  local icon = main:CreateTexture(nil, "OVERLAY")
  icon:SetSize(46, 46)
  icon:SetPoint("CENTER", shield, "CENTER")
  main.emblem, main.shield = icon, shield

  main.title = UI.Label(main, "", "GameFontNormalLarge")
  UI.TitleFont(main.title, 26)
  main.title:SetPoint("TOPLEFT", shield, "TOPRIGHT", 12, 2)
  main.subtitle = UI.Label(main, "", "GameFontHighlightSmall")
  main.subtitle:SetPoint("TOPLEFT", main.title, "BOTTOMLEFT", 0, -4)
  main.subtitle:SetWordWrap(false)

  local close = CreateFrame("Button", nil, main, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)

  -- bronze band under the header
  local rule = main:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(0.78, 0.53, 0.22, 0.9)
  rule:SetHeight(2)
  rule:SetPoint("TOPLEFT", 12, -62)
  rule:SetPoint("TOPRIGHT", -12, -62)
  local rule2 = main:CreateTexture(nil, "ARTWORK")
  rule2:SetColorTexture(0.35, 0.22, 0.09, 0.9)
  rule2:SetHeight(1)
  rule2:SetPoint("TOPLEFT", 12, -65)
  rule2:SetPoint("TOPRIGHT", -12, -65)

  -- Big "Speak Dwarvish" toggle in the header, visible on every tab.
  local lang = UI.Button(main, "", 150, 30, function() ns.Lang.Toggle() end)
  lang:SetPoint("TOPRIGHT", -36, -16)
  local fs = lang:GetFontString()
  if fs then UI.TitleFont(fs, 15) end
  lang:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Speak Dwarvish", 0.95, 0.78, 0.38)
    GameTooltip:AddLine("Sets your chat language to Dwarvish. Fellow dwarves understand you; everyone else hears gibberish.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  lang:SetScript("OnLeave", function() GameTooltip:Hide() end)
  main.langButton = lang
  UI.UpdateLanguageButton()

  main.motto = UI.Label(main, "By hammer and hearth", "GameFontDisableSmall")
  if not main.motto:SetFont(UI.TITLE_FONT, 13, "") then main.motto:SetFontObject("GameFontDisableSmall") end
  main.motto:SetTextColor(0.7, 0.6, 0.45)
  main.motto:SetPoint("RIGHT", lang, "LEFT", -12, 0)

  -- Officers: call for cheers. Replaces the motto for officers.
  local cheers = UI.Button(main, "Call for Cheers!", 132, 30, function() ns.Cheers.Call() end)
  cheers:SetPoint("RIGHT", lang, "LEFT", -6, 0)
  local cfs = cheers:GetFontString()
  if cfs then UI.TitleFont(cfs, 14) end
  cheers:Hide()
  main.cheersButton = cheers

  -- The tavern: Cross Gambling opens from the header, beside Cheers.
  local gamble = UI.Button(main, "Gambling", 96, 30, function() selectTab("gamble") end)
  local gfs = gamble:GetFontString()
  if gfs then UI.TitleFont(gfs, 14) end
  main.gambleButton = gamble
  main.headerTabs = { gamble = gamble }

  main.content = CreateFrame("Frame", nil, main)
  main.navLines, main.navButtons = {}, {}

  -- Side list in sections: guild management, in-game tools, roleplay, then settings.
  local byId, placed = {}, {}
  for _, t in ipairs(tabs) do byId[t.id] = t end
  local sections = {}
  for _, sec in ipairs(NAV_SECTIONS) do
    local list = {}
    for _, id in ipairs(sec.ids) do
      if byId[id] and not byId[id].headerOnly then list[#list + 1] = byId[id]; placed[id] = true end
    end
    sections[#sections + 1] = { title = sec.title, tabs = list }
  end
  local rest = {}
  for _, t in ipairs(tabs) do if not placed[t.id] and not t.headerOnly then rest[#rest + 1] = t end end
  if #rest > 0 then table.insert(sections, #sections, { tabs = rest }) end
  main.navHeaders = {}
  local y = -72
  for _, sec in ipairs(sections) do
    if #sec.tabs > 0 then
      if sec.title then
        local h = UI.Label(main, sec.title, "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", 18, y - 2)
        h:SetTextColor(0.83, 0.63, 0.09)
        local line = main:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.72, 0.55, 0.2, 0.6)
        line:SetHeight(1)
        main.navLines[#main.navLines + 1] = { line = line, y = y - 16 }
        main.navHeaders[#main.navHeaders + 1] = h
        y = y - 20
      else
        y = y - 8
      end
      for _, t in ipairs(sec.tabs) do
        local b = UI.Button(main, t.label, 132, 24, function() selectTab(t.id) end)
        main.navButtons[#main.navButtons + 1] = { b = b, y = y }
        t.button = b
        y = y - 27
      end
      y = y - 4
    end
  end
  -- The window may not shrink past the last side button (Settings) and the version label.
  local minH = math.max(MIN_H, math.floor(-y + 24))
  if main.SetResizeBounds then main:SetResizeBounds(MIN_W, minH, MAX_W, MAX_H)
  elseif main.SetMinResize then main:SetMinResize(MIN_W, minH) end
  if (main:GetHeight() or 0) < minH then main:SetHeight(minH) end
  -- header buttons that open a page highlight like a tab button
  for _, t in ipairs(tabs) do
    if t.headerOnly and main.headerTabs and main.headerTabs[t.id] then t.button = main.headerTabs[t.id] end
  end

  layoutNav(startW)

  -- Resize by dragging any edge or corner.
  local function grip(sizePoint, setup)
    local g = CreateFrame("Frame", nil, main)
    g:SetFrameLevel((main:GetFrameLevel() or 1) + 10)
    setup(g)
    g:EnableMouse(true)
    g:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" then main:StartSizing(sizePoint) end end)
    g:SetScript("OnMouseUp", function() main:StopMovingOrSizing(); saveSize() end)
    return g
  end
  grip("LEFT", function(g) g:SetWidth(6); g:SetPoint("TOPLEFT", 0, -40); g:SetPoint("BOTTOMLEFT", 0, 16) end)
  grip("RIGHT", function(g) g:SetWidth(6); g:SetPoint("TOPRIGHT", 0, -40); g:SetPoint("BOTTOMRIGHT", 0, 16) end)
  grip("TOP", function(g) g:SetHeight(6); g:SetPoint("TOPLEFT", 16, 0); g:SetPoint("TOPRIGHT", -40, 0) end)
  grip("BOTTOM", function(g) g:SetHeight(6); g:SetPoint("BOTTOMLEFT", 16, 0); g:SetPoint("BOTTOMRIGHT", -16, 0) end)
  grip("TOPLEFT", function(g) g:SetSize(16, 16); g:SetPoint("TOPLEFT", 0, 0) end)
  grip("BOTTOMLEFT", function(g) g:SetSize(16, 16); g:SetPoint("BOTTOMLEFT", 0, 0) end)
  local corner = grip("BOTTOMRIGHT", function(g) g:SetSize(18, 18); g:SetPoint("BOTTOMRIGHT", -2, 2) end)
  corner:SetFrameLevel((main:GetFrameLevel() or 1) + 12)
  local gripTex = corner:CreateTexture(nil, "OVERLAY")
  gripTex:SetAllPoints()
  gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  corner:SetScript("OnEnter", function() gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight") end)
  corner:SetScript("OnLeave", function() gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up") end)

  local fitPending = false
  main:SetScript("OnSizeChanged", function(_, w)
    layoutNav(w)
    if fitPending then return end
    fitPending = true
    local function fit() fitPending = false; fitSubtitle() end
    if C_Timer then C_Timer.After(0, fit) else fit() end
  end)

  main.footer = UI.Label(main, "", "GameFontDisableSmall")
  main.footer:SetPoint("BOTTOMLEFT", 16, 12)
  main.footer:SetWidth(140)

  main:SetScript("OnShow", function()
    ns.RequestRoster()
    updateHeader()
    if current and current.refresh then current.refresh(current.frame) end
  end)
  main:Hide()
end

function ns.ToggleMain(tabId, opts)
  if not IsInGuild or not IsInGuild() then
    ns.Print("You need to be in a guild to open the hold.")
    return
  end
  if not ns.Data.Ready() then
    ns.Data.EnsureGuild()
    if not ns.Data.Ready() then
      ns.RequestRoster()
      ns.Print("Still loading your guild. Try again in a moment.")
      return
    end
  end
  if not main then build(); selectTab(tabs[1].id) end
  if tabId then
    if opts and opts.problems and UI.SetRosterProblems then UI.SetRosterProblems(true) end
    main:Show()
    selectTab(tabId)
    return
  end
  if main:IsShown() then main:Hide() else main:Show() end
end

-- Refresh the visible tab when data or roster changes (batched).
local pending = false
local function scheduleRefresh()
  if not main or not main:IsShown() or pending then return end
  pending = true
  local function run()
    pending = false
    if not main:IsShown() then return end
    updateHeader()
    if current and current.refresh then current.refresh(current.frame) end
    local q = ns.Comm.QueueLength()
    main.footer:SetText(q > 0 and ("Syncing... " .. q) or ("v" .. ns.VERSION))
  end
  if C_Timer then C_Timer.After(0.3, run) else run() end
end
ns.UI.ScheduleRefresh = scheduleRefresh
ns.On("DATA_CHANGED", scheduleRefresh)
ns.On("ROSTER", scheduleRefresh)
