-- Ironforged: the Drunken challenge. Stay drunk all the way to max level.
-- The game can't be asked how drunk you are, but it says so in a system message whenever it
-- changes ("You feel tipsy.", "You feel sober again."). When the buzz wears off, a popup with a
-- drink button gives you 30 seconds to drink (any ale, stout, wine or spirit in your bags), or the
-- challenge fails. The clock stops while you're in combat or dead.
local ADDON, ns = ...
local UI = ns.UI

local D = {}
ns.Drunken = D

D.GRACE = 30        -- seconds to drink once you're sober
D.START_GRACE = 60  -- seconds to get a buzz going when the challenge starts, or when you log in

local function isSecret(v) return issecretvalue and issecretvalue(v) end

-- The game's own drunk messages (with the English text as a fallback).
local SOBER = { [DRUNK_MESSAGE_SELF1 or "You feel sober again."] = true, ["You feel sober again."] = true }
local BUZZ = {}
for _, m in ipairs({ DRUNK_MESSAGE_SELF2 or "You feel tipsy.", DRUNK_MESSAGE_SELF3 or "You feel drunk.",
  DRUNK_MESSAGE_SELF4 or "You feel completely smashed.", "You feel tipsy.", "You feel drunk.", "You feel completely smashed." }) do
  BUZZ[m] = true
end

local state = "unknown"  -- "buzzed", "sober" or "unknown" (just logged in)
local countdown          -- { left = seconds, reason = "sober"|"start" }
local lastTotal          -- drinks in bags, to notice one being drunk
local frame

local function active()
  local C = ns.Challenges
  if not C then return nil end
  for _, c in ipairs(C.MyEnforced()) do if c.preset.drunk then return c end end
end
D.Active = active

local function level() return (UnitLevel and UnitLevel("player")) or 0 end
local function inCombat() return InCombatLockdown and InCombatLockdown() end
local function dead() return UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") end

local function save()
  local me = ns.PlayerName()
  if not me or not ns.db then return end
  ns.db.drunk = ns.db.drunk or {}
  ns.db.drunk[me] = state
end

----------------------------------------------------------------------
-- The popup
----------------------------------------------------------------------
local function build()
  if frame or inCombat() then return frame end
  frame = CreateFrame("Frame", "IronforgedDrunkFrame", UIParent, "BackdropTemplate")
  frame:SetSize(340, 170)
  frame:SetPoint("TOP", 0, -140)
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetClampedToScreen(true)
  UI.Backdrop(frame)

  local icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetSize(40, 40)
  icon:SetPoint("TOPLEFT", 16, -16)
  icon:SetTexture("Interface\\Icons\\INV_Drink_05")

  frame.title = UI.Label(frame, "Your buzz is wearing off!", "GameFontNormalLarge")
  UI.TitleFont(frame.title, 18)
  frame.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
  frame.sub = UI.Label(frame, "", "GameFontHighlight")
  frame.sub:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
  frame.sub:SetWidth(250)
  frame.sub:SetWordWrap(true)

  -- Drinking from your bags is a protected action, so this is Blizzard's secure item button:
  -- your click uses the item, exactly as clicking it in your bags would.
  local drink = CreateFrame("Button", "IronforgedDrunkDrink", frame, "SecureActionButtonTemplate,BackdropTemplate")
  UI.StyleButton(drink)
  drink:SetSize(304, 32)
  drink:SetPoint("BOTTOM", 0, 40)
  drink:RegisterForClicks("AnyUp", "AnyDown")
  drink:SetAttribute("type", "item")
  local fs = drink:GetFontString()
  if fs then UI.TitleFont(fs, 16) end
  frame.drink = drink

  frame.note = UI.Label(frame, "", "GameFontDisableSmall")
  frame.note:SetPoint("BOTTOM", 0, 18)
  frame.note:SetWidth(304)
  frame.note:SetJustifyH("CENTER")
  frame:Hide()
  return frame
end

local function refresh()
  if not frame or not countdown then return end
  local secs = math.max(0, math.ceil(countdown.left))
  frame.title:SetText(countdown.reason == "start" and "Get a buzz going!" or "Your buzz is wearing off!")
  local why = dead() and "  |cff999999(waiting while you're dead)|r" or (inCombat() and "  |cff999999(waiting for the fight to end)|r" or "")
  frame.sub:SetText("Drink an ale within |cffff4040" .. secs .. "|r seconds or the Drunken challenge fails." .. why)
  if inCombat() then return end -- the button can't change in combat
  local id, name, count
  if ns.Cheers then id, name, count = ns.Cheers.FindDrink() end
  local b = frame.drink
  if id then
    b:SetAttribute("item", "item:" .. id)
    b:SetText("Drink a " .. ((name and name ~= "") and name or "drink"))
    b:Enable()
    frame.note:SetText(count .. " in your bags")
  else
    b:SetAttribute("item", nil)
    b:SetText("No ale in your bags!")
    b:Disable()
    frame.note:SetText("Find a drink fast: an innkeeper, a guildmate, anyone.")
  end
end

local function hide()
  if frame and not inCombat() then frame:Hide() end
end

----------------------------------------------------------------------
-- Keeping time
----------------------------------------------------------------------
local function stop()
  countdown = nil
  hide()
end

local function buzzed(fromDrink)
  local wasWaiting = countdown ~= nil
  state = "buzzed"
  save()
  stop()
  if wasWaiting and active() then ns.Print("|cffd4a017Drunken:|r ahh, there's the buzz" .. (fromDrink and "" or " again") .. ". Keep it going.") end
end
D.Buzzed = buzzed

local function tick()
  if not countdown then return end
  local c = active()
  if not c then stop(); return end
  if not (inCombat() or dead()) then countdown.left = countdown.left - 1 end
  if countdown.left <= 0 then
    stop()
    ns.Challenges.Fail(c.key, "Sobered up at level " .. level() .. ".")
    return
  end
  if frame and frame:IsShown() then refresh() elseif build() then refresh(); frame:Show() end
end
D._tick = tick

local function start(secs, reason)
  if countdown or not active() then return end
  countdown = { left = secs, reason = reason }
  lastTotal = ns.Cheers and ns.Cheers.DrinkTotal() or 0
  if build() then refresh(); frame:Show() end
  if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
  ns.Print("|cffff4040Drunken:|r " .. (reason == "start" and "get a buzz going" or "your buzz is wearing off") ..
    "! Drink within " .. secs .. " seconds or the challenge fails.")
end
D.Start = start

-- Something to drink on: no buzz known yet (just started, just logged in).
local function check()
  if not active() then stop(); return end
  if state ~= "buzzed" then start(D.START_GRACE, state == "sober" and "sober" or "start") end
end
D.Check = check

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
ns.RegisterEvent("CHAT_MSG_SYSTEM", function(text)
  if type(text) ~= "string" or isSecret(text) then return end
  if BUZZ[text] then
    buzzed(false)
  elseif SOBER[text] then
    state = "sober"
    save()
    if active() then start(D.GRACE, "sober") end
  end
end)

-- A drink leaving your bags counts at once, even before (or without) the game's "tipsy" message.
local function bagsChanged()
  if not countdown or not ns.Cheers then return end
  local total = ns.Cheers.DrinkTotal()
  if lastTotal and total < lastTotal then buzzed(true); return end
  lastTotal = total
end
ns.RegisterEvent("BAG_UPDATE_DELAYED", bagsChanged)
ns.RegisterEvent("BAG_UPDATE", function() if C_Timer then C_Timer.After(0.2, bagsChanged) else bagsChanged() end end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() if countdown and frame then refresh(); frame:Show() end end)

-- A /reload keeps the buzz you had; a fresh login has to show it again.
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
  local me = ns.PlayerName()
  local saved = me and ns.db and ns.db.drunk and ns.db.drunk[me]
  if isReload and saved == "buzzed" then state = "buzzed" elseif state ~= "buzzed" or isLogin then state = "unknown" end
  if C_Timer then C_Timer.After(8, function() pcall(check) end) end
end)

-- Taking on the challenge starts the first clock.
ns.On("DATA_CHANGED", function(coll)
  if coll ~= "challenges" or countdown then return end
  if C_Timer then C_Timer.After(1, function() pcall(check) end) else check() end
end)

-- One steady clock; it does nothing unless a countdown is running.
ns.RegisterEvent("PLAYER_LOGIN", function()
  build()
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, function() pcall(tick) end) end
end)
