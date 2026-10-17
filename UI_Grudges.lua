-- Ironforged: the Book of Grudges. Anyone may write a grudge against someone outside the guild;
-- everyone can read them. Horde grudges are avenged when the foe falls to a guildmate;
-- Alliance grudges are avenged by an officer. Only officers strike grudges out.
local ADDON, ns = ...
local UI = ns.UI
local Data = ns.Data

local state = { showAvenged = true }
local SIDES = { { text = "Horde", value = "Horde" }, { text = "Alliance", value = "Alliance" } }

local function guessSide(name)
  local c = ns.db and ns.db.foes and ns.db.foes[Data.FoeKey(name)]
  return c and c.faction or nil
end

local function currentZone()
  local zone = GetZoneText and GetZoneText() or ""
  local sub = GetSubZoneText and GetSubZoneText() or ""
  if issecretvalue and (issecretvalue(zone) or issecretvalue(sub)) then return "" end
  if sub ~= "" and sub ~= zone then return sub .. ", " .. zone end
  return zone or ""
end

local function writeGrudge(prefill, where)
  local guess = prefill and guessSide(prefill)
  UI.OpenForm({
    title = "Write in the Book of Grudges",
    width = 540,
    fields = {
      { type = "info", font = "GameFontHighlightSmall",
        value = "For wrongs done by those outside the guild. A Horde grudge is avenged when the foe falls to one of us. An Alliance grudge is avenged when an officer says so." },
      { key = "against", label = "Who wronged us (first and last name)", type = "text", value = prefill or "", maxLen = 60 },
      { key = "faction", label = "Their side", type = "choice", value = guess or "Horde", options = SIDES },
      { key = "where", label = "Where", type = "text", value = where or "", maxLen = 60 },
      { key = "deed", label = "What they did", type = "multiline", value = "", maxLen = 500, height = 100 },
    },
    saveText = "Record it",
    onSave = function(v)
      local against = ns.Clean(v.against, 60)
      local deed = ns.Clean(v.deed, 500)
      if against == "" or deed == "" then ns.Print("Name the wrongdoer and say what they did."); return false end
      if ns.IsGuildmateName(against) then
        if not ns.NameKey(against):find(" ", 1, true) then
          ns.Print("|cffff6060A guildmate is named " .. against .. ". Add the foe's surname so we grudge the right dwarf-hater.|r")
        else
          ns.Print("|cffff6060" .. against .. " is one of us. Guildmates can't be grudged. Take it to a Longbeard.|r")
        end
        return false
      end
      Data.Put("grudges", ns.PlayerName() .. "#" .. ns.NewId(), {
        against = against, faction = v.faction or "Horde", where = ns.Clean(v.where, 60), deed = deed, ts = ns.Now(),
      })
      ns.Print("The grudge is written. It will not be forgotten.")
    end,
  })
end
UI.WriteGrudge = writeGrudge

local function avengedText(a)
  if not a then return nil end
  if a.how == "officer" then
    return "Avenged" .. (a.by and (", credited to " .. ns.ShortName(a.by)) or "") .. " (marked by " .. ns.ShortName(a.marker or a.by) .. ")"
  elseif a.how == "witnessed" then
    return "Avenged: seen falling by " .. ns.ShortName(a.by)
  end
  return "Avenged: slain by " .. ns.ShortName(a.by)
end

local function showGrudge(key)
  local g = Data.Get("grudges", key)
  if not g then return end
  local author = Data.SplitKey(key)
  local a = Data.Avenged(key)
  local lines = {
    "|cffd4a017Against:|r " .. (g.against or "?") .. "  |cff999999(" .. (g.faction or "?") .. ")|r",
    "|cffd4a017Written:|r " .. ns.FormatDate(g.ts) .. " by " .. ns.ColorName(author),
  }
  if g.where and g.where ~= "" then lines[#lines + 1] = "|cffd4a017Where:|r " .. g.where end
  lines[#lines + 1] = " "
  lines[#lines + 1] = g.deed or ""
  lines[#lines + 1] = " "
  if a then
    lines[#lines + 1] = "|cffffd040AVENGED.|r " .. avengedText(a) .. " on " .. ns.FormatDate(a.ts) .. "."
  elseif g.faction == "Horde" then
    lines[#lines + 1] = "|cffff6060Unavenged.|r It will be avenged when " .. (g.against or "the foe") .. " falls to one of us."
  else
    lines[#lines + 1] = "|cffff6060Unavenged.|r An officer will mark it avenged when justice is done."
  end

  local buttons = {}
  local officer = ns.IsLongbeardOrGM(ns.PlayerName())
  if officer and not a then
    buttons[#buttons + 1] = { text = "Mark avenged", keepOpen = true, onClick = function()
      local opts = { { text = "(no one in particular)", value = false } }
      for _, o in ipairs(UI.RosterOptions(false)) do opts[#opts + 1] = o end
      UI.Pick(_G.IronforgedDialog, opts, function(who)
        if ns.Blood.MarkAvenged(key, who or nil) then showGrudge(key) end
      end, "Who avenged it?")
    end }
  end
  if officer and a then
    buttons[#buttons + 1] = { text = "Reopen", onClick = function() Data.Delete("avenged", key) end }
  end
  if officer then
    buttons[#buttons + 1] = { text = "Strike it out", onClick = function()
      UI.Confirm("Strike this grudge from the book?", function() Data.Delete("grudges", key) end)
    end }
  end
  UI.OpenForm({ title = "Grudge against " .. (g.against or "?") .. (a and "  |cffffd040AVENGED|r" or ""), width = 560,
    fields = { { type = "info", value = table.concat(lines, "\n") } }, buttons = buttons })
end

local function build(f, w, h)
  f.writeButton = UI.Button(f, "Write a grudge", 130, 22, function() writeGrudge(nil) end)
  f.writeButton:SetPoint("TOPLEFT", 4, -2)
  f.targetButton = UI.Button(f, "Grudge my target", 130, 22, function()
    local name = UnitExists("target") and UnitIsPlayer("target") and ns.UnitDisplayName("target")
    if not name then ns.Print("Target the wrongdoer first."); return end
    ns.Blood.Learn("target")
    writeGrudge(name, currentZone())
  end)
  f.targetButton:SetPoint("LEFT", f.writeButton, "RIGHT", 4, 0)
  local avengedBox = UI.Check(f, "Show avenged", function(self)
    state.showAvenged = self:GetChecked() and true or false
    UI.ScheduleRefresh()
  end)
  avengedBox:SetChecked(true)
  avengedBox:SetPoint("LEFT", f.targetButton, "RIGHT", 10, 0)
  f.count = UI.Label(f, "", "GameFontHighlightSmall")
  f.count:SetPoint("TOPRIGHT", -6, -7)
  f.list = UI.List(f, w, h - 30, {
    { title = "Date", width = 74 }, { title = "Against", width = 118 }, { title = "Side", width = 58 },
    { title = "What they did", width = 200 }, { title = "Status", width = 140 },
  }, function(key) showGrudge(key) end)
  f.list:SetPoint("TOPLEFT", 0, -28)
end

local function refresh(f)
  local items, open, avenged = {}, 0, 0
  for key, g in Data.Each("grudges") do
    local a = Data.Avenged(key)
    if a then avenged = avenged + 1 else open = open + 1 end
    if state.showAvenged or not a then
      local status
      if a then
        status = "|cffffd040AVENGED|r |cff999999" .. ns.ShortName(a.by) .. "|r"
      else
        status = "|cffff6060Unavenged|r"
      end
      items[#items + 1] = {
        data = key, ts = g.ts or 0, open = not a, keys = { [1] = g.ts or 0, [5] = a and 1 or 0 },
        color = a and { 0.65, 0.6, 0.5 } or nil,
        cols = { ns.FormatDate(g.ts), (a and "|cff998866" or "|cffff8060") .. (g.against or "?") .. "|r",
          g.faction == "Alliance" and "|cff6699ffAlliance|r" or "|cffff4040Horde|r",
          ((g.deed or ""):gsub("\n", " ")), status },
      }
    end
  end
  table.sort(items, function(a, b)
    if a.open ~= b.open then return a.open end
    return a.ts > b.ts
  end)
  f.list:SetItems(items, "The book is empty. For now.")
  f.count:SetText("|cffff6060" .. open .. " unavenged|r   |cffffd040" .. avenged .. " avenged|r")
end

UI.RegisterTab("grudges", "Book of Grudges", build, refresh)

----------------------------------------------------------------------
-- Popup when a grudged foe is near: threaten them with /doom
----------------------------------------------------------------------
local doom

-- Blizzard blocks addons from doing emotes themselves, so the /doom button is a secure macro
-- button: the click is yours, and the game runs "/doom Name" as if you typed it. Secure buttons
-- can't be changed, shown or hidden in combat, so a sighting in combat waits until combat ends.
local hidePending, pendingDoom = false, nil
local function inCombat() return InCombatLockdown and InCombatLockdown() end

local function hideDoom()
  if not doom then return end
  if inCombat() then hidePending = true else doom:Hide() end
end

local function buildDoom()
  if doom then return doom end
  doom = CreateFrame("Frame", "IronforgedDoomFrame", UIParent, "BackdropTemplate")
  doom:SetSize(340, 136)
  doom:SetPoint("TOP", 0, -220)
  doom:SetFrameStrata("DIALOG")
  doom:EnableMouse(true)
  doom:SetMovable(true)
  doom:RegisterForDrag("LeftButton")
  doom:SetScript("OnDragStart", doom.StartMoving)
  doom:SetScript("OnDragStop", doom.StopMovingOrSizing)
  doom:SetClampedToScreen(true)
  UI.Backdrop(doom)
  local icon = doom:CreateTexture(nil, "ARTWORK")
  icon:SetSize(36, 36)
  icon:SetPoint("TOPLEFT", 16, -16)
  icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
  doom.title = UI.Label(doom, "A grudged foe is near", "GameFontNormalLarge")
  UI.TitleFont(doom.title, 19)
  doom.title:SetTextColor(1, 0.35, 0.3)
  doom.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
  doom.sub = UI.Label(doom, "", "GameFontHighlightSmall")
  doom.sub:SetPoint("TOPLEFT", doom.title, "BOTTOMLEFT", 0, -4)
  doom.sub:SetWidth(250)
  doom.sub:SetWordWrap(true)
  doom.sub:SetMaxLines(3)
  local close = CreateFrame("Button", nil, doom, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)
  close:SetScript("OnClick", hideDoom)
  local go = CreateFrame("Button", "IronforgedDoomButton", doom, "SecureActionButtonTemplate,BackdropTemplate")
  UI.StyleButton(go)
  go:SetSize(120, 26)
  go:SetText("Threaten")
  go:RegisterForClicks("AnyUp", "AnyDown")
  go:SetAttribute("type", "macro")
  go:SetScript("PostClick", function() hideDoom() end)
  go:SetPoint("BOTTOMLEFT", 18, 16)
  doom.go = go
  doom.no = UI.Button(doom, "Not now", 96, 26, hideDoom)
  doom.no:SetPoint("LEFT", doom.go, "RIGHT", 8, 0)
  doom:Hide()
  return doom
end

local function showDoom(foe, deed, count)
  local d = buildDoom()
  d.foe = foe
  -- the emote finds them by their character name
  local who = ns.CharName(foe, false)
  d.go:SetAttribute("macrotext", "/doom " .. who)
  d.sub:SetText("|cffff8060" .. foe .. "|r" .. ((deed and deed ~= "") and (": " .. deed) or "") ..
    ((count or 1) > 1 and ("  |cff999999(+" .. (count - 1) .. " more)|r") or ""))
  d:Show()
  d.shownAt = GetTime and GetTime() or 0
  local at = d.shownAt
  if C_Timer then C_Timer.After(30, function() if d.shownAt == at then hideDoom() end end) end
end

ns.On("GRUDGE_NEAR", function(foe, deed, count)
  if not ns.settings or ns.settings.doomPopup == false then return end
  if inCombat() then
    pendingDoom = { foe = foe, deed = deed, count = count, at = GetTime and GetTime() or 0 }
    return
  end
  showDoom(foe, deed, count)
end)

ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
  if hidePending and doom then hidePending = false; doom:Hide() end
  local p = pendingDoom
  pendingDoom = nil
  if p and (GetTime and GetTime() or 0) - p.at < 60 then showDoom(p.foe, p.deed, p.count) end
end)
