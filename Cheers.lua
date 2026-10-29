-- Ironforged: Cheers! An officer calls for a toast in guild chat; every guildmate with the addon
-- gets a popup with a "Drink an ale" button that drinks one from their bags. Each drink is
-- announced in guild chat. Cheers is the only part of the addon that posts to guild chat.
local ADDON, ns = ...

local Cheers = {}
ns.Cheers = Cheers

local UI = ns.UI
local CALL_COOLDOWN = 60       -- seconds between calls from one officer
local CALL_LIFETIME = 180      -- seconds a call stays open
local DRINK_WINDOW = 8         -- seconds to see the drink leave your bags

-- Ales and other drinks of the hold, by item ID, preferred first.
local KNOWN_DRINKS = {
  2686,  -- Thunder Ale
  2596,  -- Skin of Dwarven Stout
  2594,  -- Flagon of Dwarven Mead
  3703,  -- Southshore Stout
  2894,  -- Rhapsody Malt
  19222, -- Cheap Beer
  17402, -- Greatfather's Winter Ale
  18284, -- Kreeg's Stout Beatdown
  2593,  -- Flask of Port
  2595,  -- Jug of Badlands Bourbon
  1942,  -- Bottle of Moonshine
  1941,  -- Cask of Merlot
  2723,  -- Bottle of Pinot Noir
  4595,  -- Junglevine Wine
  9260,  -- Volatile Rum
  9360,  -- Cuergo's Gold
  18287, -- Evermurky
  18288, -- Molasses Firewater
  19221, -- Darkmoon Special Reserve
  20709, -- Rumsey Rum Light
  21114, -- Rumsey Rum Dark
  21151, -- Rumsey Rum Black Label
  17196, -- Holiday Spirits
}
local KNOWN_RANK = {}
for i, id in ipairs(KNOWN_DRINKS) do KNOWN_RANK[id] = i end

-- Names that mark a drink as an ale or other brew, for drinks not on the list.
local ALE_WORDS = { "ale", "stout", "beer", "mead", "brew", "lager", "porter", "grog" }
local SPIRIT_WORDS = { "rum", "bourbon", "whiskey", "whisky", "wine", "port", "malt", "moonshine", "merlot", "firewater", "spirits" }

local function isSecret(v) return issecretvalue and issecretvalue(v) end

local function nameHas(name, words)
  local n = " " .. name:lower():gsub("[^%a]", " ") .. " "
  for _, w in ipairs(words) do
    if n:find(" " .. w .. " ", 1, true) then return true end
  end
  return false
end

local function slotInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then return info.itemID, info.stackCount, info.hyperlink end
    return nil
  end
  if GetContainerItemInfo then
    local _, count, _, _, _, _, link, _, _, id = GetContainerItemInfo(bag, slot)
    return id, count, link
  end
end

local function numSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
  if GetContainerNumSlots then return GetContainerNumSlots(bag) or 0 end
  return 0
end

local function linkName(link)
  return type(link) == "string" and link:match("%[(.-)%]") or nil
end

-- The best drink in your bags: itemID, name, total count.
function Cheers.FindDrink()
  local best, bestScore, counts, names = nil, nil, {}, {}
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, numSlots(bag) do
      local id, count, link = slotInfo(bag, slot)
      if id and not isSecret(id) then
        local name = linkName(link) or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or ""
        local score
        if KNOWN_RANK[id] then score = KNOWN_RANK[id]
        elseif nameHas(name, ALE_WORDS) then score = 100
        elseif nameHas(name, SPIRIT_WORDS) then score = 200 end
        if score then
          counts[id] = (counts[id] or 0) + (count or 1)
          names[id] = name
          if not bestScore or score < bestScore then best, bestScore = id, score end
        end
      end
    end
  end
  if not best then return nil end
  return best, names[best], counts[best]
end

-- Food & drink (consumable subclass 5), when the game can say; unknown counts as yes.
local function isDrinkItem(id)
  local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not fn then return true end
  local ok, _, _, _, _, _, cls, sub = pcall(fn, id)
  if not ok or cls == nil then return true end
  return cls == 0 and sub == 5
end
Cheers.IsDrinkItem = isDrinkItem

-- Every drink in your bags, counted together (to notice when one is drunk).
function Cheers.DrinkTotal()
  local n = 0
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, numSlots(bag) do
      local id, count, link = slotInfo(bag, slot)
      if id and not isSecret(id) then
        local name = linkName(link) or ""
        if (KNOWN_RANK[id] or nameHas(name, ALE_WORDS) or nameHas(name, SPIRIT_WORDS)) and isDrinkItem(id) then n = n + (count or 1) end
      end
    end
  end
  return n
end

local function countOf(itemID)
  local n = 0
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, numSlots(bag) do
      local id, count = slotInfo(bag, slot)
      if id == itemID then n = n + (count or 1) end
    end
  end
  return n
end

----------------------------------------------------------------------
-- State of the current call
----------------------------------------------------------------------
local current        -- { id, caller, started, drinkers = {name=true}, order = {} }
local lastCall = 0
local pending        -- { itemID, name, before, at }

-- Post to guild chat. Falls back to a local line when chat is locked (some encounters).
local function sayGuild(text)
  local locked = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and select(2, pcall(C_ChatInfo.InChatMessagingLockdown))
  if locked == true then ns.Print(text); return end
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  if not send or not pcall(send, text, "GUILD") then ns.Print(text) end
end
Cheers._sayGuild = sayGuild

local function shortFirst(name)
  return (ns.Name(name):match("^(%S+)")) or ns.Name(name)
end

----------------------------------------------------------------------
-- The popup
----------------------------------------------------------------------
local frame

local function buildFrame()
  if frame then return frame end
  frame = CreateFrame("Frame", "IronforgedCheersFrame", UIParent, "BackdropTemplate")
  frame:SetSize(340, 196)
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
  icon:SetTexture("Interface\\Icons\\INV_Drink_04")

  frame.title = UI.Label(frame, "Cheers!", "GameFontNormalLarge")
  UI.TitleFont(frame.title, 22)
  frame.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
  frame.sub = UI.Label(frame, "", "GameFontHighlight")
  frame.sub:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
  frame.sub:SetWidth(250)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)

  frame.drinkers = UI.Label(frame, "", "GameFontHighlightSmall")
  frame.drinkers:SetPoint("TOPLEFT", 18, -70)
  frame.drinkers:SetWidth(304)
  frame.drinkers:SetJustifyV("TOP")
  frame.drinkers:SetWordWrap(true)
  frame.drinkers:SetMaxLines(3)

  -- Drinking from your bags is a protected action, so this is Blizzard's secure item button:
  -- your click uses the item, exactly as clicking it in your bags would.
  local drink = CreateFrame("Button", "IronforgedCheersDrink", frame, "SecureActionButtonTemplate,BackdropTemplate")
  UI.StyleButton(drink)
  drink:SetSize(304, 32)
  drink:SetPoint("BOTTOM", 0, 44)
  drink:RegisterForClicks("AnyUp", "AnyDown")
  drink:SetAttribute("type", "item")
  local fs = drink:GetFontString()
  if fs then UI.TitleFont(fs, 16) end
  drink:SetScript("PostClick", function(self)
    if not self.itemID then return end
    pending = { itemID = self.itemID, name = self.itemName, before = self.before or countOf(self.itemID), at = GetTime() }
  end)
  frame.drink = drink

  frame.note = UI.Label(frame, "", "GameFontDisableSmall")
  frame.note:SetPoint("BOTTOM", 0, 22)
  frame.note:SetWidth(304)
  frame.note:SetJustifyH("CENTER")

  frame:Hide()
  return frame
end

local function refreshFrame()
  if not frame or not current then return end
  frame.sub:SetText(shortFirst(current.caller) .. " raises a mug to the hold!")
  local names = {}
  for _, n in ipairs(current.order) do names[#names + 1] = shortFirst(n) end
  frame.drinkers:SetText(#names > 0 and ("|cffd4a017Drunk so far (" .. #names .. "):|r " .. table.concat(names, ", ")) or "No one has drunk yet. Be the first!")

  if InCombatLockdown and InCombatLockdown() then
    frame.note:SetText("Finish the fight first.")
    return
  end
  local me = ns.PlayerName()
  local drink = frame.drink
  if current.drinkers[me] then
    drink:SetAttribute("item", nil)
    drink.itemID = nil
    drink:SetText("You've had your ale. Cheers!")
    drink:Disable()
    frame.note:SetText("")
    return
  end
  local id, name, count = Cheers.FindDrink()
  if id then
    drink:SetAttribute("item", "item:" .. id)
    drink.itemID, drink.itemName, drink.before = id, name, count
    drink:SetText("Drink a " .. (name ~= "" and name or "drink"))
    drink:Enable()
    frame.note:SetText(count .. " in your bags")
  else
    drink:SetAttribute("item", nil)
    drink.itemID = nil
    drink:SetText("No ale in your bags")
    drink:Disable()
    frame.note:SetText("Buy a round from any innkeeper, then come back.")
  end
end
Cheers.Refresh = refreshFrame

local function showFrame()
  if ns.settings and ns.settings.cheersPopup == false then return end
  buildFrame()
  refreshFrame()
  frame:Show()
end

----------------------------------------------------------------------
-- Calling, answering, announcing
----------------------------------------------------------------------
function Cheers.Call()
  local me = ns.PlayerName()
  if not ns.IsOfficer(me) then ns.Print("Only officers can call for cheers."); return end
  local now = GetTime()
  if now - lastCall < CALL_COOLDOWN then
    ns.Print("Let the mugs settle a moment before calling again.")
    return
  end
  lastCall = now
  local id = string.format("%x", ns.Hash(me .. ns.Now()) % 0xFFFFFF)
  ns.Comm.Send({ op = "C", id = id }, "GUILD")
  sayGuild("CHEERS! " .. shortFirst(me) .. " raises a mug to the hold. Grab an ale and drink!")
  Cheers.OnCall(me, id)
end

function Cheers.OnCall(caller, id)
  if not ns.IsOfficer(caller) then return end
  if current and current.id == id then return end
  current = { id = id, caller = caller, started = GetTime(), drinkers = {}, order = {} }
  if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
    pcall(RaidNotice_AddMessage, RaidWarningFrame, shortFirst(caller) .. " calls for CHEERS!", ChatTypeInfo.RAID_WARNING)
  end
  if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound, SOUNDKIT.READY_CHECK) end
  showFrame()
  if C_Timer then
    local thisId = id
    C_Timer.After(CALL_LIFETIME, function()
      if current and current.id == thisId then
        if frame then frame:Hide() end
        current = nil
      end
    end)
  end
end

function Cheers.OnDrink(drinker, id, itemName)
  if not current or current.id ~= id or current.drinkers[drinker] then return end
  current.drinkers[drinker] = true
  current.order[#current.order + 1] = drinker
  if frame and frame:IsShown() then refreshFrame() end
end

-- Confirm the drink left your bags, then tell the hold.
local function checkPending()
  if not pending or not current then return end
  if GetTime() - pending.at > DRINK_WINDOW then pending = nil; return end
  if countOf(pending.itemID) < pending.before then
    local me = ns.PlayerName()
    local name = pending.name
    pending = nil
    ns.Comm.Send({ op = "G", id = current.id, item = name }, "GUILD")
    local what = (type(name) == "string" and name ~= "") and name or "an ale"
    local n = #current.order + 1
    sayGuild(shortFirst(me) .. " chugs " .. (what:find("^an? ") and what or ("a " .. what)) .. "! Cheers to " ..
      shortFirst(current.caller) .. "!" .. (n == 1 and " First to drink!" or (" That's " .. n .. " mugs raised to the call.")))
    Cheers.OnDrink(me, current.id, name)
  end
end
Cheers._checkPending = checkPending

ns.RegisterEvent("BAG_UPDATE_DELAYED", function() checkPending() end)
ns.RegisterEvent("BAG_UPDATE", function() if C_Timer then C_Timer.After(0.2, checkPending) else checkPending() end end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() if frame and frame:IsShown() then refreshFrame() end end)

ns.On("CHEERS_CALL", function(sender, id) Cheers.OnCall(sender, id) end)
ns.On("CHEERS_DRINK", function(sender, id, item) Cheers.OnDrink(sender, id, item) end)
