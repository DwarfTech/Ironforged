-- Ironforged: "Speak Dwarvish" button. The addon never touches the chat box: on WoW: Forever any
-- addon change to it marks it as addon-touched, and the game then blocks party, raid, whisper and
-- battleground chat sent from it. So the button reads which language the game has you speaking
-- and shows you how to switch it in the game's own chat menu, which is safe.
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

-- Speaking Dwarvish right now? Read from the game's chat box (reading changes nothing).
function Lang.IsOn()
  local eb = _G.ChatFrame1EditBox
  if not eb then return false end
  local ok, id = pcall(function() return eb.languageID end)
  if ok and id == DWARVISH_ID then return true end
  local name = Lang.Dwarvish()
  local ok2, lang = pcall(function() return eb.language end)
  return ok2 and name ~= nil and lang == name
end

-- How to switch, in the game's own chat menu.
function Lang.Toggle()
  local dw = Lang.Dwarvish()
  if not dw then
    ns.Print("This character doesn't know Dwarvish. Only dwarves can speak it.")
    return
  end
  local on = Lang.IsOn()
  local back = select(1, Lang.Default()) or "Common"
  local steps = on
    and ("You're speaking Dwarvish. To switch back, open the chat menu (the speech bubble button beside your chat), choose Language, then " .. back .. ".")
    or ("To speak Dwarvish, open the chat menu (the speech bubble button beside your chat), choose Language, then " .. dw .. ". It stays until you change it back.")
  ns.Print(steps)
  if ns.UI and ns.UI.Notice then
    ns.UI.Notice({ id = "dwarvish", icon = "Interface\\Icons\\INV_Misc_Book_09", title = "Speak Dwarvish",
      text = steps .. "\n\n|cff999999The addon leaves your chat alone so party, raid and whisper chat always work.|r",
      buttons = { { text = "Got it" } }, timeout = 30 })
  end
  ns.Fire("LANGUAGE")
end

function Lang.Set() Lang.Toggle() end
