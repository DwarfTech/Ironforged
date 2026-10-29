-- Ironforged: the Iron Chef challenge. Eat only food you made yourself.
-- Cooked food carries no "made by" mark, so the addon keeps a ledger: every "You create: [food]"
-- message adds to it. When you eat, the food that left your bags is checked against the ledger.
-- Food you made counts down; anything else fails the challenge. Drinks are fine.
local ADDON, ns = ...
local C = ns.Challenges

C.PRESETS.ironchef = { name = "Iron Chef", ironChef = true,
  rules = "Eat only food you cooked yourself. Bought, looted or quest food fails the challenge. Drinks are fine." }
C.ORDER[#C.ORDER + 1] = "ironchef"

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function level() return (UnitLevel and UnitLevel("player")) or 0 end
local function now() return GetTime and GetTime() or 0 end

-- Eating casts a spell called "Food" (or "Refreshment" for food and drink together).
local EAT_SPELLS = { Food = true, Refreshment = true }

local function isFood(id)
  local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not fn then return false end
  local ok, _, _, _, _, _, cls, sub = pcall(fn, id)
  return ok and cls == 0 and sub == 5
end

----------------------------------------------------------------------
-- The ledger: food this character has made, by item ID
----------------------------------------------------------------------
local function ledger()
  local me = ns.PlayerName()
  if not me or not ns.db then return {} end
  ns.db.cooked = ns.db.cooked or {}
  ns.db.cooked[me] = ns.db.cooked[me] or {}
  return ns.db.cooked[me]
end
C.CookedLedger = ledger

-- "You create: [Spiced Wolf Meat]." or "You create: [Spiced Wolf Meat]x5."
ns.RegisterEvent("CHAT_MSG_LOOT", function(text)
  if type(text) ~= "string" or isSecret(text) then return end
  local prefix = type(LOOT_ITEM_CREATED_SELF) == "string" and LOOT_ITEM_CREATED_SELF:match("^(.-)%%s") or "You create: "
  if text:sub(1, #prefix) ~= prefix and not text:find("^You create") then return end
  local id = tonumber(text:match("|Hitem:(%d+)"))
  if not id or not isFood(id) then return end
  local n = tonumber(text:match("|r[xX](%d+)")) or tonumber(text:match("[xX](%d+)%.?$")) or 1
  local l = ledger()
  l[id] = (l[id] or 0) + n
end)

----------------------------------------------------------------------
-- Eating: which food left the bags around the time you ate
----------------------------------------------------------------------
local function bagFood()
  local out = {}
  if not (C_Container and C_Container.GetContainerItemInfo) then return out end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local n = (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)) or 0
    for slot = 1, n do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID and not isSecret(info.itemID) and isFood(info.itemID) then
        out[info.itemID] = (out[info.itemID] or 0) + (info.stackCount or 1)
      end
    end
  end
  return out
end

local last = {}      -- food counts at the last bag update
local recent = {}    -- { id, n, t }: food that just left the bags
local eatAt          -- when the last "Food" cast happened, until it's matched to an item

local function chef()
  for _, c in ipairs(C.MyEnforced()) do if c.preset.ironChef then return c end end
end

local function resolve()
  if not eatAt then return end
  if now() - eatAt > 3 then eatAt = nil; return end -- couldn't tell what was eaten; let it go
  -- When food you cooked also left the bags just then, give the benefit of the doubt: that's what you ate.
  local l0 = ledger()
  local pick
  for i, r in ipairs(recent) do
    if math.abs(r.t - eatAt) <= 3 and (l0[r.id] or 0) > 0 then pick = i; break end
  end
  if not pick then
    for i, r in ipairs(recent) do if math.abs(r.t - eatAt) <= 3 then pick = i; break end end
  end
  if pick then
    local i, r = pick, recent[pick]
    do
      table.remove(recent, i)
      eatAt = nil
      local c = chef()
      if not c then return end
      local l = ledger()
      if (l[r.id] or 0) > 0 then
        l[r.id] = l[r.id] - 1
      else
        local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(r.id)) or "food you didn't cook"
        C.Fail(c.key, "Ate " .. name .. " at level " .. level() .. ".")
      end
      return
    end
  end
end

local function bagsChanged()
  local cur = bagFood()
  local t = now()
  for id, n in pairs(last) do
    local d = n - (cur[id] or 0)
    if d > 0 then recent[#recent + 1] = { id = id, n = d, t = t } end
  end
  last = cur
  for i = #recent, 1, -1 do if t - recent[i].t > 5 then table.remove(recent, i) end end
  resolve()
end
ns.RegisterEvent("BAG_UPDATE_DELAYED", function() pcall(bagsChanged) end)
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function() last = bagFood() end)

ns.RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
  if unit ~= "player" or not spellID or isSecret(spellID) then return end
  local name
  if C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(spellID) end
  if not name and GetSpellInfo then name = GetSpellInfo(spellID) end
  if type(name) ~= "string" or not EAT_SPELLS[name] then return end
  eatAt = now()
  pcall(resolve)
  if C_Timer then C_Timer.After(1, function() pcall(resolve) end) end
end)
