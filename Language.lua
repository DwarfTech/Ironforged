-- Ironforged: "Speak Dwarvish" toggle. Sets the chat box's language to Dwarvish, the same as
-- picking it from the chat language menu.
-- On WoW: Forever the game blocks chat in battlegrounds and dungeons from a chat box an addon has
-- touched, and the mark lasts until you reload. So the addon only touches the chat boxes when you
-- turn Dwarvish on yourself, for that session: it's off by default, never switched on at login,
-- and never touched inside an instance. A reload clears it.
local ADDON, ns = ...

local Lang = {}
ns.Lang = Lang

local DWARVISH_ID = 6

-- The character's Dwarvish language, if they know it: name, id
function Lang.Dwarvish()
  if not GetNumLanguages or not GetLanguageByIndex then return nil end
  local okN, n = pcall(GetNumLanguages)
  if not okN or type(n) ~= "number" then return nil end
  for i = 1, n do
    local ok, name, id = pcall(GetLanguageByIndex, i)
    if ok and id == DWARVISH_ID then return name, id end
  end
  return nil
end

function Lang.Default()
  if not GetNumLanguages or not GetLanguageByIndex then return nil end
  local okN, n = pcall(GetNumLanguages)
  if not okN or type(n) ~= "number" or n < 1 then return nil end
  local def = GetDefaultLanguage and GetDefaultLanguage()
  local first, firstId
  for i = 1, n do
    local ok, name, id = pcall(GetLanguageByIndex, i)
    if ok and name then
      if not first then first, firstId = name, id end
      if name == def then return name, id end
    end
  end
  return first, firstId
end

local function editBoxes()
  local out = {}
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local eb = _G["ChatFrame" .. i .. "EditBox"]
    if eb then out[#out + 1] = eb end
  end
  return out
end

local function applyTo(eb, name, id)
  if not eb or not name then return end
  if InCombatLockdown and InCombatLockdown() then return end
  eb.language = name
  eb.languageID = id
  if eb.UpdateHeader then pcall(eb.UpdateHeader, eb)
  elseif ChatEdit_UpdateHeader then pcall(ChatEdit_UpdateHeader, eb) end
end

-- In a battleground, arena, dungeon, raid or scenario: hands off the chat boxes.
function Lang.InInstance()
  if not IsInInstance then return false end
  local ok, inside, kind = pcall(IsInInstance)
  if not ok then return false end
  return inside == true or (type(kind) == "string" and kind ~= "none")
end

local applied = false -- the chat boxes were set to Dwarvish this session

function Lang.IsOn()
  return ns.settings and ns.settings.speakDwarvish and true or false
end

-- Apply the current choice to every chat box. Outside instances only, and only when there's
-- something to change: Dwarvish on, or switching back after it was on.
function Lang.Apply()
  if Lang.InInstance() then return end
  local name, id
  if Lang.IsOn() then
    name, id = Lang.Dwarvish()
    if not name then return end
    applied = true
  else
    if not applied then return end
    name, id = Lang.Default()
    if not name then return end
    applied = false
  end
  for _, eb in ipairs(editBoxes()) do applyTo(eb, name, id) end
end

function Lang.Set(on)
  if on and not Lang.Dwarvish() then
    ns.Print("This character doesn't know Dwarvish. Only dwarves can speak it.")
    on = false
  end
  ns.settings.speakDwarvish = on and true or false
  Lang.Apply()
  if on and Lang.InInstance() then
    ns.Print("|cff40ff40You'll speak Dwarvish once you leave this place.|r In battlegrounds and dungeons the game won't let addons change your chat.")
  elseif on then
    ns.Print("|cff40ff40You now speak Dwarvish.|r Those who don't know the tongue will hear only gibberish. " ..
      "It lasts until you reload or log out. In a battleground, reload first or your chat may not send.")
  else
    ns.Print("You now speak " .. (select(1, Lang.Default()) or "Common") .. ".")
  end
  ns.Fire("LANGUAGE")
end

function Lang.Toggle() Lang.Set(not Lang.IsOn()) end

-- Each login starts in your normal language: Dwarvish lasts the session you turn it on in.
-- (Everyone who had it on from the old default is switched off once.)
function Lang.OnLogin()
  if ns.settings and not ns.settings.dwarvishSessionOnly then
    ns.settings.dwarvishSessionOnly = true
    ns.settings.speakDwarvish = false
  end
  if ns.settings then ns.settings.speakDwarvish = false end
  ns.Fire("LANGUAGE")
end
ns.RegisterEvent("PLAYER_LOGIN", function() Lang.OnLogin() end)

-- Entering an instance with chat set to Dwarvish this session: the game may block chat in there,
-- and a reload clears it, so offer one each time.
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
  if not Lang.InInstance() or not applied then return end
  if ns.UI and ns.UI.Notice then
    ns.UI.Notice({ id = "dwarvish-instance", icon = "Interface\\Icons\\INV_Misc_Book_09", title = "Speak Dwarvish",
      text = "You turned on Speak Dwarvish this session, and the game blocks chat from it in battlegrounds and dungeons. Reload so your chat works in here.",
      buttons = { { text = "Reload now", onClick = function() if ReloadUI then ReloadUI() end end }, { text = "Later" } },
      timeout = 30 })
  end
end)
