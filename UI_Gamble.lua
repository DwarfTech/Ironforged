-- Ironforged: Gambling tab and the game popup.
local ADDON, ns = ...
local UI = ns.UI
local Data = ns.Data
local G = ns.Gamble

local state = { amount = "100" }

local function first(name) return (ns.Name(name):match("^(%S+)")) or ns.Name(name) end

local PHASE_TEXT = {
  open = "Joining: type 1 in chat or press Join",
  rolling = "Rolling",
  tiehigh = "Tie for high: tied players roll again",
  tielow = "Tie for low: tied players roll again",
  done = "Finished",
  cancelled = "Cancelled",
}

local function statusText()
  local g = G.game
  if not g then return "No game running. Set an amount and open one." end
  local s = "|cffd4a017" .. g.amount .. "g|r hosted by " .. first(g.host) .. ".  " .. (PHASE_TEXT[g.phase] or "")
  if g.phase == "done" and g.high then
    if (g.owed or 0) > 0 then
      s = s .. "\n|cff40ff40" .. first(g.low) .. " owes " .. first(g.high) .. " " .. g.owed .. "g.|r Settle it by trade."
    else
      s = s .. "\nEveryone tied. No gold changes hands."
    end
  else
    local waiting = G.Waiting()
    if #waiting > 0 then
      local names = {}
      for _, n in ipairs(waiting) do names[#names + 1] = first(n) end
      s = s .. "\nWaiting on: " .. table.concat(names, ", ")
    end
  end
  return s
end

----------------------------------------------------------------------
-- Popup for guildmates when a game opens
----------------------------------------------------------------------
local pop

local function buildPopup()
  if pop then return pop end
  pop = CreateFrame("Frame", "IronforgedGambleFrame", UIParent, "BackdropTemplate")
  pop:SetSize(340, 150)
  pop:SetPoint("TOP", 0, -360)
  pop:SetFrameStrata("DIALOG")
  pop:EnableMouse(true)
  pop:SetMovable(true)
  pop:RegisterForDrag("LeftButton")
  pop:SetScript("OnDragStart", pop.StartMoving)
  pop:SetScript("OnDragStop", pop.StopMovingOrSizing)
  pop:SetClampedToScreen(true)
  UI.Backdrop(pop)
  local icon = pop:CreateTexture(nil, "ARTWORK")
  icon:SetSize(36, 36)
  icon:SetPoint("TOPLEFT", 16, -16)
  icon:SetTexture("Interface\\Icons\\INV_Misc_Dice_01")
  pop.title = UI.Label(pop, "Cross Gambling", "GameFontNormalLarge")
  UI.TitleFont(pop.title, 20)
  pop.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
  pop.sub = UI.Label(pop, "", "GameFontHighlightSmall")
  pop.sub:SetPoint("TOPLEFT", pop.title, "BOTTOMLEFT", 0, -4)
  pop.sub:SetWidth(250)
  pop.sub:SetWordWrap(true)
  pop.sub:SetMaxLines(3)
  local close = CreateFrame("Button", nil, pop, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)
  pop.join = UI.Button(pop, "Join", 96, 26, function() if G.IAmIn() then G.Leave() else G.Join() end end)
  pop.join:SetPoint("BOTTOMLEFT", 18, 18)
  pop.roll = UI.Button(pop, "Roll", 96, 26, function() G.Roll() end)
  pop.roll:SetPoint("LEFT", pop.join, "RIGHT", 8, 0)
  pop.ask = UI.Button(pop, "Ask for invite", 120, 26, function() G.AskInvite() end)
  pop.ask:SetPoint("LEFT", pop.join, "RIGHT", 8, 0)
  pop.open = UI.Button(pop, "Open tab", 96, 26, function() ns.ToggleMain("gamble") end)
  pop.open:SetPoint("BOTTOMRIGHT", -18, 18)
  pop:Hide()
  return pop
end

local function refreshPopup()
  if not pop or not pop:IsShown() then return end
  local g = G.game
  if not g or g.phase == "done" or g.phase == "cancelled" then
    if g and g.phase == "done" then pop.sub:SetText(statusText()) end
    pop.join:Hide(); pop.roll:Hide(); pop.ask:Hide()
    return
  end
  local inRaid = IsInRaid and IsInRaid()
  local inGame = G.IAmIn()
  local mustRoll = false
  for _, n in ipairs(G.Waiting()) do if n == ns.PlayerName() then mustRoll = true end end
  local text = first(g.host) .. " is gambling " .. g.amount .. "g. " .. #g.order .. (#g.order == 1 and " player" or " players") .. " in."
  if not inRaid and (g.phase == "open" or inGame) then
    text = text .. "\nRolls happen in " .. first(g.host) .. "'s raid. Ask for an invite" .. (inGame and " to roll." or ", then join.")
  end
  pop.sub:SetText(text)
  pop.join:SetShown(g.phase == "open")
  pop.join:SetText(inGame and "Leave" or "Join")
  pop.roll:SetShown(mustRoll and inRaid)
  pop.ask:SetShown(not inRaid and (g.phase == "open" or mustRoll))
end

-- joining the raid changes what the popup offers
ns.RegisterEvent("GROUP_ROSTER_UPDATE", function() refreshPopup(); if UI.ScheduleRefresh then UI.ScheduleRefresh() end end)

ns.On("GAMBLE", function(fresh)
  local g = G.game
  local inRaid = IsInRaid and IsInRaid()
  -- everyone gets the popup when a game opens; those outside the raid can ask for an invite
  if fresh and g and g.phase == "open" and not G.IsHost() and ns.settings and ns.settings.gamblePopup ~= false then
    buildPopup():Show()
  end
  -- bring the popup back when it's my turn to roll
  if g and pop and not pop:IsShown() and not G.IsHost() then
    for _, n in ipairs(G.Waiting()) do
      if n == ns.PlayerName() and ns.settings.gamblePopup ~= false then pop:Show() end
    end
  end
  refreshPopup()
  UI.ScheduleRefresh()
end)

----------------------------------------------------------------------
-- The tab
----------------------------------------------------------------------
local function build(f, w, h)
  local amountLabel = UI.Label(f, "Gold:", "GameFontNormalSmall")
  amountLabel:SetPoint("TOPLEFT", 6, -8)
  f.amountLabel = amountLabel
  f.hostNote = UI.Label(f, "Nobles and above can host Cross Gambling.", "GameFontDisableSmall")
  f.hostNote:SetPoint("TOPLEFT", 6, -10)
  f.amount = UI.EditBox(f, 70, 7)
  f.amount:SetPoint("LEFT", amountLabel, "RIGHT", 10, 0)
  f.amount:SetNumeric(true)
  f.amount:SetText(state.amount)
  f.amount:SetScript("OnTextChanged", function(self) state.amount = self:GetText() end)
  f.channel = UI.Label(f, "rolls in your raid", "GameFontHighlightSmall")
  f.channel:SetPoint("LEFT", f.amount, "RIGHT", 8, 0)

  f.openB = UI.Button(f, "Open game", 96, 22, function() G.Open(state.amount) end)
  f.openB:SetPoint("LEFT", f.channel, "RIGHT", 10, 0)
  f.lastB = UI.Button(f, "Last call", 80, 22, function() G.LastCall() end)
  f.lastB:SetPoint("LEFT", f.openB, "RIGHT", 4, 0)
  f.rollNowB = UI.Button(f, "Start rolling", 100, 22, function() G.StartRolling() end)
  f.rollNowB:SetPoint("LEFT", f.lastB, "RIGHT", 4, 0)
  f.cancelB = UI.Button(f, "Cancel", 64, 22, function() G.Cancel() end)
  f.cancelB:SetPoint("LEFT", f.rollNowB, "RIGHT", 4, 0)

  f.status = UI.Label(f, "", "GameFontHighlightSmall")
  f.status:SetPoint("TOPLEFT", 6, -36)
  f.status:SetPoint("TOPRIGHT", -6, -36)
  f.status:SetJustifyV("TOP")
  f.status:SetSpacing(2)

  f.joinB = UI.Button(f, "Join", 80, 22, function() if G.IAmIn() then G.Leave() else G.Join() end end)
  f.joinB:SetPoint("TOPLEFT", 4, -74)
  f.rollB = UI.Button(f, "Roll", 80, 22, function() G.Roll() end)
  f.rollB:SetPoint("LEFT", f.joinB, "RIGHT", 4, 0)
  f.askB = UI.Button(f, "Ask for invite", 110, 22, function() G.AskInvite() end)
  f.askB:SetPoint("LEFT", f.joinB, "RIGHT", 4, 0)

  local listW = 260
  f.players = UI.List(f, listW, h - 132, {
    { title = "Player", width = 150 }, { title = "Roll", width = 80 },
  }, function(name)
    -- the host can take a player out of the game; everyone else sees the member's record
    if G.IsHost() and G.Active() then
      UI.Confirm("Remove " .. first(name) .. " from this game?", function() G.Kick(name) end)
    else
      UI.ShowMember(name, { noManage = true })
    end
  end)
  f.players:SetPoint("TOPLEFT", 0, -102)
  f.players:SetPoint("BOTTOMLEFT", 0, 30)

  local hall = UI.Label(f, "Hall of Fortune (all recorded games)", "GameFontNormalSmall")
  hall:SetPoint("BOTTOMLEFT", f.players, "TOPRIGHT", 12, 4)
  f.board = UI.List(f, w - listW - 8, h - 132, {
    { title = "Dwarf", width = 160 }, { title = "Net gold", width = 100 }, { title = "Games", width = 80 },
  }, function(name) UI.ShowMember(name, { noManage = true }) end)
  f.board:SetPoint("TOPLEFT", f.players, "TOPRIGHT", 8, 0)
  f.board:SetPoint("BOTTOMRIGHT", 0, 30)
  -- the two lists keep their proportions as the window is resized
  f:HookScript("OnSizeChanged", function(_, fw)
    if fw and fw > 0 then f.players:SetWidth(math.max(120, math.floor(fw * listW / w + 0.5))) end
  end)

  f.note = UI.Label(f, "Rolls happen in the host's raid. Highest roll wins; lowest pays the winner the difference. Pay up by trade. Host: click a player to remove them.", "GameFontDisableSmall")
  f.note:SetPoint("BOTTOMLEFT", 4, 6)
end

local function refresh(f)
  local g = G.game
  local host = G.IsHost()
  local active = G.Active()
  local canHost = G.CanHost()
  f.openB:SetEnabled(not active or host)
  f.openB:SetShown(not active and canHost)
  f.amount:SetShown(canHost); f.amountLabel:SetShown(canHost); f.channel:SetShown(canHost)
  f.hostNote:SetShown(not canHost and not active)
  f.lastB:SetShown(host and g.phase == "open")
  f.rollNowB:SetShown(host and g.phase == "open")
  f.cancelB:SetShown(host and active)
  f.status:SetText(statusText())

  f.joinB:SetShown(g ~= nil and g.phase == "open")
  f.joinB:SetText(G.IAmIn() and "Leave" or "Join")
  local mustRoll = false
  for _, n in ipairs(G.Waiting()) do if n == ns.PlayerName() then mustRoll = true end end
  local inRaid = IsInRaid and IsInRaid()
  f.rollB:SetShown(mustRoll and inRaid)
  f.askB:SetShown(g ~= nil and not host and not inRaid and (g.phase == "open" or mustRoll))

  local items = {}
  if g then
    for _, n in ipairs(g.order or {}) do
      local r = g.rolls and g.rolls[n]
      local t = g.tieRolls and g.tieRolls[n]
      local text = r and tostring(r) or "|cff888888-|r"
      if t then text = text .. " |cffffd040/ " .. t .. "|r" end
      local color
      if g.phase == "done" and n == g.high then color = { 0.4, 1, 0.4 } elseif g.phase == "done" and n == g.low then color = { 1, 0.45, 0.45 } end
      items[#items + 1] = { data = n, color = color, keys = { [2] = r or -1 }, cols = { first(n), text } }
    end
  end
  f.players:SetItems(items, g and "No one has joined yet." or "")

  local board = {}
  for _, s in ipairs(G.Standings()) do
    local net = s.net > 0 and ("|cff40ff40+" .. s.net .. "g|r") or (s.net < 0 and ("|cffff6060" .. s.net .. "g|r") or "0g")
    board[#board + 1] = { data = s.name, keys = { [2] = s.net }, cols = { ns.ColorName(s.name), net, s.games } }
  end
  f.board:SetItems(board, "No games recorded yet.")
end

UI.RegisterTab("gamble", "Gambling", build, refresh, true)
