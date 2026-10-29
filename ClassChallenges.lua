-- Ironforged: class challenges. Ready-made challenges for one class or a few, enforced like the others:
--   * gear rules are checked every few seconds; forbidden weapons and shields go back in your bags,
--     and a required shield has to be put back on within a minute;
--   * spell rules watch what you cast (by spell name, so every rank counts) and fail on a forbidden one;
--   * Brute watches stealth, Rifleman watches for a pet, Doomseeker for Defensive Stance.
local ADDON, ns = ...
local Data = ns.Data
local C = ns.Challenges

local function level() return (UnitLevel and UnitLevel("player")) or 0 end
local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function now() return GetTime and GetTime() or 0 end
local function set(list) local t = {}; for _, v in ipairs(list) do t[v] = true end; return t end

----------------------------------------------------------------------
-- Spell lists (names, so all ranks match)
----------------------------------------------------------------------
local SHADOW = set({
  "Shadow Word: Pain", "Mind Blast", "Mind Flay", "Psychic Scream", "Fade", "Mind Control", "Mind Soothe",
  "Mind Vision", "Shadow Protection", "Prayer of Shadow Protection", "Shadowform", "Vampiric Embrace", "Silence",
  "Mana Burn", "Devouring Plague", "Hex of Weakness", "Shadowguard", "Touch of Weakness", "Shadow Word: Death",
  "Vampiric Touch", "Shadowfiend", "Mind Sear",
})
local PRIEST_HEALS = set({
  "Lesser Heal", "Heal", "Greater Heal", "Flash Heal", "Renew", "Prayer of Healing", "Desperate Prayer",
  "Lightwell", "Binding Heal", "Circle of Healing", "Prayer of Mending", "Penance",
})
local HOLY_DAMAGE = set({ "Smite", "Holy Fire", "Holy Nova" })
local PALADIN_HEALS = set({ "Holy Light", "Flash of Light", "Lay on Hands", "Holy Shock" })
local PALADIN_DEFENSIVE = set({
  "Divine Shield", "Divine Protection", "Blessing of Protection", "Hand of Protection", "Devotion Aura",
  "Blessing of Sanctuary", "Greater Blessing of Sanctuary", "Holy Shield", "Divine Intervention", "Blessing of Sacrifice",
})
local PALADIN_ALL = set({
  "Holy Light", "Flash of Light", "Lay on Hands", "Holy Shock", "Divine Shield", "Divine Protection",
  "Blessing of Protection", "Blessing of Might", "Blessing of Wisdom", "Blessing of Kings", "Blessing of Salvation",
  "Blessing of Light", "Blessing of Sanctuary", "Blessing of Freedom", "Blessing of Sacrifice",
  "Greater Blessing of Might", "Greater Blessing of Wisdom", "Greater Blessing of Kings",
  "Greater Blessing of Salvation", "Greater Blessing of Light", "Greater Blessing of Sanctuary",
  "Devotion Aura", "Retribution Aura", "Concentration Aura", "Sanctity Aura", "Crusader Aura",
  "Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura",
  "Hammer of Justice", "Hammer of Wrath", "Consecration", "Exorcism", "Holy Wrath", "Turn Undead", "Purify",
  "Cleanse", "Redemption", "Righteous Fury", "Holy Shield", "Repentance", "Divine Intervention", "Divine Favor",
  "Sense Undead", "Avenger's Shield", "Crusader Strike", "Avenging Wrath",
})

----------------------------------------------------------------------
-- The challenges
----------------------------------------------------------------------
local P = C.PRESETS
local WARRIOR, PALADIN, HUNTER, ROGUE, PRIEST = "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST"

P.ironbreaker = { name = "Ironbreaker", classes = set({ WARRIOR, PALADIN }), fromLevel = 5, needShield = true,
  rules = "Warriors and Paladins. From level 5, always wear a shield. Take it off and you have a minute to put one back on." }
P.doomseeker = { name = "Doomseeker", classes = set({ WARRIOR }), fromLevel = 5, noShield = true, noDefStance = true,
  canStart = function()
    if C.KnowsDefensiveStance and C.KnowsDefensiveStance() then
      ns.Print("Doomseeker: you already know Defensive Stance, so this one is out of reach for this character.")
      return false
    end
    return true
  end,
  rules = "Warriors. From level 5, never use a shield and never learn Defensive Stance. Skip the Defensive Stance quests: learning the stance fails the challenge." }
P.brawler = { name = "Brawler", classes = set({ WARRIOR, HUNTER, ROGUE, PALADIN }), weapons = set({ 13 }),
  weaponWhat = { what = "weapon other than a fist weapon", fail = "a weapon other than a fist weapon" },
  rules = "Warriors, Hunters, Rogues and Paladins. Fight with fist weapons or bare hands only. No other weapons, ranged included." }
P.hammerer = { name = "Hammerer", classes = set({ ROGUE }), fromLevel = 10, weapons = set({ 4, 5 }),
  weaponWhat = { what = "weapon that isn't a mace", fail = "a weapon that wasn't a mace" },
  rules = "Rogues. From level 10, maces are your only weapons. No other weapons, ranged included." }
P.beastmaster = { name = "Beastmaster", classes = set({ HUNTER }), fromLevel = 10, noRanged = true,
  rules = "Hunters. From level 10, no ranged weapon. You and your pet fight up close." }
P.rifleman = { name = "Rifleman", classes = set({ HUNTER }), noPet = true,
  rules = "Hunters. No pet, ever. Tame or call one and you have a minute to abandon it. Dismissing isn't enough." }
P.brute = { name = "Brute", classes = set({ ROGUE }), noStealth = true,
  rules = "Rogues. No stealth. Stay stealthed more than 5 seconds and the challenge fails." }
P.lightbringer = { name = "Lightbringer", classes = set({ PRIEST }), noWand = true,
  spellRule = function(n) if SHADOW[n] then return "a Shadow spell" end end,
  rules = "Priests. No Shadow spells and no wands." }
P.voidbringer = { name = "Voidbringer", classes = set({ PRIEST }), fromLevel = 4,
  spellRule = function(n)
    if PRIEST_HEALS[n] then return "a healing spell" end
    if HOLY_DAMAGE[n] then return "a Holy spell" end
  end,
  rules = "Priests. From level 4, no healing spells and no Holy damage spells (Smite, Holy Fire, Holy Nova). Shields and buffs are fine." }
P.oathbreaker = { name = "Oathbreaker", classes = set({ PALADIN }), noShield = true,
  spellRule = function(n)
    if PALADIN_HEALS[n] then return "a healing spell" end
    if PALADIN_DEFENSIVE[n] then return "a defensive ability" end
  end,
  rules = "Paladins. No shield, no healing spells, and no defensive abilities: Divine Shield, Divine Protection, Blessing of Protection, Devotion Aura and the like." }
P.runesmith = { name = "Runesmith", classes = set({ PALADIN }), fromLevel = 10, needProfs = { "Blacksmithing", "Enchanting" },
  spellRule = function(n)
    if n:find("^Seal of ") or n:find("^Judgement") or n == "Summon Warhorse" or n == "Summon Charger" then return nil end
    if PALADIN_ALL[n] then return "a spell other than a seal or Judgement" end
  end,
  rules = "Paladins. From level 10, you must know Blacksmithing and Enchanting, and the only spells you may cast are seals and Judgement (your mount is fine)." }

for _, id in ipairs({ "ironbreaker", "doomseeker", "brawler", "hammerer", "beastmaster", "rifleman", "brute",
  "lightbringer", "voidbringer", "oathbreaker", "runesmith" }) do
  C.ORDER[#C.ORDER + 1] = id
end

----------------------------------------------------------------------
-- Gear
----------------------------------------------------------------------
local RANGED = set({ 2, 3, 16, 18, 19 }) -- bows, guns, thrown, crossbows, wands
local SHIELD = { what = "shield", fail = "a shield" }
local RANGED_W = { what = "ranged weapon", fail = "a ranged weapon" }
local WAND = { what = "wand", fail = "a wand" }

-- Item class and subclass of what's in a slot (weapon = 2, armor = 4; shield = armor subclass 6).
local function itemType(slot)
  local id = GetInventoryItemID and GetInventoryItemID("player", slot)
  if not id or isSecret(id) then return nil end
  local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not fn then return nil end
  local ok, _, _, _, _, _, cls, sub = pcall(fn, id)
  if not ok then return nil end
  return cls, sub
end

local function hasShield()
  local cls, sub = itemType(17)
  return cls == 4 and sub == 6
end

function C.GearRules(p)
  local out = {}
  for _, slot in ipairs({ 16, 17, 18 }) do
    local cls, sub = itemType(slot)
    if cls == 4 and sub == 6 and p.noShield then
      out[slot] = SHIELD
    elseif cls == 2 and sub ~= 20 then -- a fishing pole is never a weapon
      if p.noWand and sub == 19 then out[slot] = WAND
      elseif p.weapons and not p.weapons[sub] then out[slot] = p.weaponWhat
      elseif p.noRanged and RANGED[sub] then out[slot] = RANGED_W end
    end
  end
  return out
end

-- Ironbreaker: a shield, always.
-- The minute is kept in saved variables (server time), so a /reload doesn't restart it.
local shieldWarned
local function shieldClock(v)
  local me = ns.PlayerName()
  if not me or not ns.db then return nil end
  ns.db.shieldGone = ns.db.shieldGone or {}
  if v ~= nil then ns.db.shieldGone[me] = v or nil end
  return ns.db.shieldGone[me]
end
table.insert(C.ENFORCERS, function(c)
  if not c.preset.needShield then return end
  if hasShield() then shieldClock(false); shieldWarned = nil; return end
  -- dead: a fresh minute once you're back on your feet
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then shieldClock(false); shieldWarned = nil; return end
  local since = shieldClock() or shieldClock(ns.Now())
  if not shieldWarned then
    shieldWarned = true
    ns.Print("|cffff4040" .. c.preset.name .. ":|r put a shield on within a minute or the challenge fails.")
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
  end
  if ns.Now() - since >= C.GRACE then
    shieldClock(false); shieldWarned = nil
    C.Fail(c.key, "Went without a shield at level " .. level() .. ".")
  end
end)

----------------------------------------------------------------------
-- Runesmith: the two professions
----------------------------------------------------------------------
-- Professions this character knows, and whether the game could tell us at all.
local function myProfessions()
  local out = {}
  if GetProfessions and GetProfessionInfo then
    local ok, a, b, c, d, e = pcall(GetProfessions)
    if ok then
      for _, idx in pairs({ a, b, c, d, e }) do
        local okI, name = pcall(GetProfessionInfo, idx)
        if okI and type(name) == "string" then out[name] = true end
      end
      return out, true
    end
  end
  if GetNumSkillLines and GetSkillLineInfo then -- classic-style skill list
    local okN, n = pcall(GetNumSkillLines)
    if okN and type(n) == "number" and n > 0 then
      for i = 1, n do
        local okI, name, isHeader = pcall(GetSkillLineInfo, i)
        if okI and type(name) == "string" and not isHeader then out[name] = true end
      end
      return out, true
    end
  end
  return out, false
end

local profsMissingSince, profsWarned
table.insert(C.ENFORCERS, function(c)
  local need = c.preset.needProfs
  if not need then return end
  local have, readable = myProfessions()
  if not readable then return end
  local missing = {}
  for _, n in ipairs(need) do if not have[n] then missing[#missing + 1] = n end end
  if #missing == 0 then profsMissingSince, profsWarned = nil, nil; return end
  profsMissingSince = profsMissingSince or now()
  if not profsWarned then
    profsWarned = true
    ns.Print("|cffff4040" .. c.preset.name .. ":|r you need " .. table.concat(missing, " and ") ..
      ". Learn " .. (#missing == 1 and "it" or "them") .. " within 10 minutes or the challenge fails.")
  end
  if now() - profsMissingSince >= 600 then
    profsMissingSince, profsWarned = nil, nil
    C.Fail(c.key, "Didn't know " .. table.concat(missing, " and ") .. " at level " .. level() .. ".")
  end
end)

----------------------------------------------------------------------
-- Spells
----------------------------------------------------------------------
local function spellName(id)
  if isSecret(id) then
    if ns.debug then ns.Print("debug: the game hid a spell you cast; spell challenges can't see it") end
    return nil
  end
  if not id then return nil end
  local n
  if C_Spell and C_Spell.GetSpellName then
    local ok, v = pcall(C_Spell.GetSpellName, id)
    if ok then n = v end
  end
  if not n and GetSpellInfo then
    local ok, v = pcall(GetSpellInfo, id)
    if ok then n = v end
  end
  if type(n) ~= "string" or isSecret(n) then return nil end
  return n
end

ns.RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
  if unit ~= "player" then return end
  local name = spellName(spellID)
  if not name then return end
  for _, c in ipairs(C.MyEnforced()) do
    local why = c.preset.spellRule and c.preset.spellRule(name)
    if why then C.Fail(c.key, "Cast " .. name .. " (" .. why .. ") at level " .. level() .. ".") end
  end
end)

----------------------------------------------------------------------
-- Doomseeker: no Defensive Stance, and a warning on the quests that teach it
----------------------------------------------------------------------
local DEFENSIVE_STANCE = 71
local STANCE_QUESTS = set({
  -- Dun Morogh
  "Muren Stormpike", "Vejrek", "Tormus Deepforge", "Ironband's Compound", "Grey Iron Weapons",
  -- Elwynn Forest
  "A Warrior's Training", "Bartleby the Drunk", "Beat Bartleby", "Bartleby's Mug", "Marshal Haggard", "Dead-tooth Jack",
  -- Teldrassil
  "Elanaria", "Vorlus Vilehoof", "The Shade of Elura", "Smith Mathiel", "Weapons of Elunite",
})

local function knowsDefensiveStance()
  if IsPlayerSpell then
    local ok, v = pcall(IsPlayerSpell, DEFENSIVE_STANCE)
    if ok and v and not isSecret(v) then return true end
  end
  if IsSpellKnown then
    local ok, v = pcall(IsSpellKnown, DEFENSIVE_STANCE)
    if ok and v and not isSecret(v) then return true end
  end
  return false
end

C.KnowsDefensiveStance = knowsDefensiveStance
table.insert(C.ENFORCERS, function(c)
  if c.preset.noDefStance and knowsDefensiveStance() then
    C.Fail(c.key, "Learned Defensive Stance at level " .. level() .. ".")
  end
end)
local function stanceCheck() if C_Timer then C_Timer.After(0.5, function() pcall(C.Enforce) end) end end
ns.RegisterEvent("SPELLS_CHANGED", stanceCheck)
ns.RegisterEvent("LEARNED_SPELL_IN_TAB", stanceCheck)        -- older clients
ns.RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE", stanceCheck) -- newer clients

local function doomseeker()
  for _, c in ipairs(C.MyEnforced()) do if c.preset.noDefStance then return c end end
end

local function questWarning(title)
  local c = doomseeker()
  if not c or type(title) ~= "string" or isSecret(title) or not STANCE_QUESTS[title] then return end
  ns.Print("|cffff4040Doomseeker:|r \"" .. title .. "\" leads to Defensive Stance. Don't do it: learning the stance fails the challenge.")
  if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
  if ns.UI and ns.UI.Notice then
    ns.UI.Notice({ id = "doomseeker", icon = "Ability_Warrior_DefensiveStance", title = "Doomseeker",
      text = "|cffffd040" .. title .. "|r leads to Defensive Stance.\nLearning it fails the Doomseeker challenge.",
      buttons = { { text = "Understood" } } })
  end
end
ns.RegisterEvent("QUEST_DETAIL", function() questWarning(GetTitleText and GetTitleText()) end)
ns.RegisterEvent("QUEST_ACCEPTED", function(a, b)
  local id = tonumber(b) or tonumber(a)
  local title = id and C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
  questWarning(title)
end)

----------------------------------------------------------------------
-- Brute: out of stealth within 5 seconds
----------------------------------------------------------------------
C.STEALTH_GRACE = 5
local stealthSince

local function stealthed()
  if not IsStealthed then return false end
  local ok, v = pcall(IsStealthed)
  return ok and not isSecret(v) and v and true or false
end

local function checkStealth()
  local brute
  for _, c in ipairs(C.MyEnforced()) do if c.preset.noStealth then brute = c end end
  if not brute or not stealthed() then stealthSince = nil; return end
  if not stealthSince then
    stealthSince = now()
    ns.Print("|cffff4040Brute:|r no stealth! Break it within " .. C.STEALTH_GRACE .. " seconds or the challenge fails.")
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
    if C_Timer then C_Timer.After(C.STEALTH_GRACE + 0.2, function() pcall(checkStealth) end) end
    return
  end
  if now() - stealthSince >= C.STEALTH_GRACE then
    stealthSince = nil
    C.Fail(brute.key, "Stayed in stealth at level " .. level() .. ".")
  end
end
C.CheckStealth = checkStealth
ns.RegisterEvent("UPDATE_STEALTH", function() pcall(checkStealth) end)
table.insert(C.ENFORCERS, function(c) if c.preset.noStealth then checkStealth() end end)

----------------------------------------------------------------------
-- Rifleman: no pet. Once a pet shows up it must be abandoned; dismissing it isn't enough.
----------------------------------------------------------------------
local function petOwed()
  local me = ns.PlayerName()
  return me and ns.db and ns.db.petOwed and ns.db.petOwed[me]
end
local function setPetOwed(v)
  local me = ns.PlayerName()
  if not me or not ns.db then return end
  ns.db.petOwed = ns.db.petOwed or {}
  ns.db.petOwed[me] = v
end

local function rifleman()
  for _, c in ipairs(C.MyEnforced()) do if c.preset.noPet then return c end end
end

-- Only a hunter's own tamed pet counts (not a quest or item companion, or something possessed).
local function hunterPet()
  if not (UnitExists and UnitExists("pet")) then return false end
  if HasPetUI then
    local ok, has, isHunter = pcall(HasPetUI)
    if ok and has ~= nil then return (has and isHunter) and true or false end
  end
  return true
end

local abandonHooked = false

local function checkPet()
  local c = rifleman()
  if not c then return end
  if not abandonHooked then
    if hunterPet() and not C._petReminded then
      C._petReminded = true
      ns.Print("|cffff4040Rifleman:|r no pets! (This game version doesn't let the addon see you abandon one, so it can only remind you.)")
    end
    return
  end
  local hasPet = hunterPet()
  local owed = petOwed()
  if hasPet and not owed then
    owed = ns.Now()
    setPetOwed(owed)
    ns.Print("|cffff4040Rifleman:|r no pets! Abandon it within a minute (right-click its portrait, Abandon Pet) or the challenge fails. Dismissing isn't enough.")
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
    if ns.UI and ns.UI.Notice then
      ns.UI.Notice({ id = "rifleman", icon = "Ability_Hunter_BeastTaming", title = "Rifleman: no pets",
        text = "Abandon your pet within a minute (right-click its portrait, then Abandon Pet).\nDismissing it isn't enough.",
        buttons = { { text = "OK" } }, timeout = 60 })
    end
    if C_Timer then C_Timer.After(61, function() pcall(checkPet) end) end
    return
  end
  if owed and ns.Now() - owed >= 60 then
    setPetOwed(nil)
    C.Fail(c.key, "Kept a pet at level " .. level() .. ".")
  end
end
C.CheckPet = checkPet

local function abandoned()
  if petOwed() then
    setPetOwed(nil)
    ns.Print("|cffd4a017Rifleman:|r pet abandoned. Just you and your gun.")
  end
end
if hooksecurefunc and PetAbandon then hooksecurefunc("PetAbandon", abandoned); abandonHooked = true end
if hooksecurefunc and C_PetInfo and C_PetInfo.PetAbandon then hooksecurefunc(C_PetInfo, "PetAbandon", abandoned); abandonHooked = true end

ns.RegisterEvent("UNIT_PET", function(unit) if unit == "player" then pcall(checkPet) end end)
table.insert(C.ENFORCERS, function(c) if c.preset.noPet then checkPet() end end)
