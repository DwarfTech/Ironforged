-- Ironforged: "Speak Dwarvish" toggle. Sets the chat box's default language to Dwarvish,
-- the same as picking it from the chat language menu, and keeps it set every time you chat.
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

function Lang.IsOn()
  return ns.settings and ns.settings.speakDwarvish and true or false
end

-- Apply the current choice to every chat box.
function Lang.Apply()
  local name, id
  if Lang.IsOn() then name, id = Lang.Dwarvish() else name, id = Lang.Default() end
  if not name then return end
  for _, eb in ipairs(editBoxes()) do applyTo(eb, name, id) end
end

function Lang.Set(on)
  if on and not Lang.Dwarvish() then
    ns.Print("This character doesn't know Dwarvish. Only dwarves can speak it.")
    on = false
  end
  ns.settings.speakDwarvish = on and true or false
  Lang.Apply()
  if on then
    ns.Print("|cff40ff40You now speak Dwarvish.|r Those who don't know the tongue will hear only gibberish.")
  else
    ns.Print("You now speak " .. (select(1, Lang.Default()) or "Common") .. ".")
  end
  ns.Fire("LANGUAGE")
end

function Lang.Toggle() Lang.Set(not Lang.IsOn()) end

-- Re-apply whenever a chat box opens, so the game's resets don't undo it.
local hooked = {}
local function hookBoxes()
  for _, eb in ipairs(editBoxes()) do
    if not hooked[eb] and eb.HookScript then
      hooked[eb] = true
      eb:HookScript("OnShow", function(self)
        if Lang.IsOn() then
          local name, id = Lang.Dwarvish()
          if name and self.languageID ~= id then applyTo(self, name, id) end
        end
      end)
    end
  end
end

ns.RegisterEvent("PLAYER_LOGIN", function()
  hookBoxes()
  if C_Timer then C_Timer.After(2, Lang.Apply) else Lang.Apply() end
end)
ns.RegisterEvent("LANGUAGE_LIST_CHANGED", function() Lang.Apply() end)
