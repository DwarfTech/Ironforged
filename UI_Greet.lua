-- Ironforged: greet a fellow dwarf. When you target another dwarf, a small bar under their portrait
-- offers Hail, Salute and Cheer. Blizzard blocks addons from doing emotes themselves, so each
-- button is a secure macro button: your click runs /hail (or /salute, /cheer) at your target, the
-- same as typing it. Secure buttons can't be shown or hidden in combat, so the bar waits for
-- the fight to end.
local ADDON, ns = ...
local UI = ns.UI

local EMOTES = { { "Hail", "/hail" }, { "Salute", "/salute" }, { "Cheer", "/cheer" } }

local bar
local hidePending = false
local function inCombat() return InCombatLockdown and InCombatLockdown() end
local function isSecret(v) return issecretvalue and issecretvalue(v) end

local function build()
  if bar or inCombat() then return bar end
  bar = CreateFrame("Frame", "IronforgedGreetBar", UIParent, "BackdropTemplate")
  bar:SetSize(236, 40)
  if TargetFrame then
    bar:SetPoint("TOP", TargetFrame, "BOTTOM", 0, 4)
  else
    bar:SetPoint("TOP", UIParent, "TOP", 120, -130)
  end
  bar:SetFrameStrata("MEDIUM")
  UI.Backdrop(bar)
  bar.buttons = {}
  local x = 8
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
