-- Ironforged: greet a fellow dwarf. When you target another dwarf, a small bar under their portrait
-- offers Hail, Salute and Cheer. Blizzard blocks addons from doing emotes themselves, so each
-- button is a secure macro button: your click runs /hail (or /salute, /cheer) at your target, the
-- same as typing it. Secure buttons can't be shown or hidden in combat, so the bar waits for
-- the fight to end. Drag the grip on its left edge to move it (out of combat); right-click the
-- grip to put it back under the target frame. The spot is saved.
local ADDON, ns = ...
local UI = ns.UI

local EMOTES = { { "Hail", "/hail" }, { "Salute", "/salute" }, { "Cheer", "/cheer" } }

local bar
local hidePending = false
local function inCombat() return InCombatLockdown and InCombatLockdown() end
local function isSecret(v) return issecretvalue and issecretvalue(v) end

local function loaded(name)
  if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
  return IsAddOnLoaded and IsAddOnLoaded(name)
end

local function usingEUI() return loaded("ElvUI") or _G.ElvUI ~= nil or loaded("EllesmereUI") end

-- Where the bar sits: the spot the player dragged it to, or under the target frame.
local function place()
  if not bar or inCombat() then return end
  bar:ClearAllPoints()
  local pos = ns.settings and ns.settings.greetPos
  if type(pos) == "table" and pos.point then
    bar:SetPoint(pos.point, UIParent, pos.rel or pos.point, tonumber(pos.x) or 0, tonumber(pos.y) or 0)
  elseif TargetFrame then
    if usingEUI() then
      bar:SetPoint("TOP", TargetFrame, "BOTTOM", -28, -36)
    else
      bar:SetPoint("TOP", TargetFrame, "BOTTOM", 0, 4)
    end
  else
    bar:SetPoint("TOP", UIParent, "TOP", 120, -130)
  end
end

local function savePosition()
  if not bar or not ns.settings then return end
  local point, _, rel, x, y = bar:GetPoint(1)
  if point then ns.settings.greetPos = { point = point, rel = rel, x = x, y = y } end
end

function UI.ResetGreetBar()
  if ns.settings then ns.settings.greetPos = nil end
  place()
  ns.Print("The greeting bar is back under your target.")
end

local function build()
  if bar or inCombat() then return bar end
  bar = CreateFrame("Frame", "IronforgedGreetBar", UIParent, "BackdropTemplate")
  bar:SetSize(248, 40)
  bar:SetMovable(true)
  bar:SetClampedToScreen(true)
  place()
  bar:SetFrameStrata("MEDIUM")
  UI.Backdrop(bar)

  -- the grip: drag to move, right-click to reset (the emote buttons fire on press, so they can't drag)
  local grip = CreateFrame("Button", "IronforgedGreetGrip", bar)
  grip:SetSize(12, 30)
  grip:SetPoint("LEFT", 3, 0)
  local tex = grip:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints()
  tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  tex:SetTexCoord(0, 1, 0, 1)
  grip:RegisterForDrag("LeftButton")
  grip:RegisterForClicks("RightButtonUp")
  grip:SetScript("OnDragStart", function()
    if inCombat() then ns.Print("Can't move the greeting bar during a fight."); return end
    bar:StartMoving()
  end)
  grip:SetScript("OnDragStop", function()
    bar:StopMovingOrSizing()
    savePosition()
  end)
  grip:SetScript("OnClick", function(_, button)
    if button == "RightButton" and not inCombat() then UI.ResetGreetBar() end
  end)
  grip:SetScript("OnEnter", function(self)
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText("Drag to move the greeting bar")
      GameTooltip:AddLine("Right-click to put it back under your target.", 1, 1, 1)
      GameTooltip:Show()
    end
  end)
  grip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  bar.grip = grip

  bar.buttons = {}
  local x = 18
  for i, e in ipairs(EMOTES) do
    local b = CreateFrame("Button", "IronforgedGreet" .. e[1], bar, "SecureActionButtonTemplate,BackdropTemplate")
    UI.StyleButton(b)
    b:SetSize(70, 24)
    b:SetText(e[1])
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", e[2]) -- an emote with no name goes to your target
    b:SetPoint("LEFT", x, 0)
    bar.buttons[i] = b
    x = x + 74
  end
  bar:Hide()
  return bar
end

-- Is my target another dwarf (a player, not me)?
local function targetIsDwarf()
  if not UnitExists or not UnitExists("target") then return false end
  local okP, isPlayer = pcall(UnitIsPlayer, "target")
  if not okP or isSecret(isPlayer) or not isPlayer then return false end
  if UnitIsUnit and UnitIsUnit("target", "player") then return false end
  local ok, _, raceFile = pcall(UnitRace, "target")
  if not ok or type(raceFile) ~= "string" or isSecret(raceFile) then return false end
  return ns.Gear.DWARF[raceFile] == true
end

local function update()
  if not ns.settings then return end
  local want = ns.settings.greetBar ~= false and targetIsDwarf()
  if inCombat() then
    if bar and bar:IsShown() and not want then hidePending = true end
    return
  end
  local b = build()
  if not b then return end
  if want then b:Show() else b:Hide() end
  hidePending = false
end
UI.UpdateGreetBar = update

ns.RegisterEvent("PLAYER_LOGIN", function() build() end)
ns.RegisterEvent("PLAYER_TARGET_CHANGED", update)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", update)
