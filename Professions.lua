-- Ironforged: profession directory.
-- Each member's own client records their professions and skill. Opening a profession window
-- records the recipes known in it. Everything syncs, so anyone can search "who can make this?"
-- Records live in the "crafts" collection: key = member .. "#" .. profession.
local ADDON, ns = ...
local Data = ns.Data

local P = {}
ns.Prof = P

P.NAMES = {
  "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Leatherworking",
  "Mining", "Skinning", "Tailoring", "Jewelcrafting", "Inscription", "Cooking",
}
local KNOWN = {}
for _, n in ipairs(P.NAMES) do KNOWN[n] = true end
P.KNOWN = KNOWN

local function key(member, prof) return member .. "#" .. prof end

----------------------------------------------------------------------
-- Reading the directory
----------------------------------------------------------------------
-- Recipe ids are spell ids, so any client can turn them into names.
local nameCache = {}
function P.RecipeName(id)
  if nameCache[id] then return nameCache[id] end
  local n
  if ns.db and ns.db.recipeNames then n = ns.db.recipeNames[id] end
  if not n and C_Spell and C_Spell.GetSpellName then
    local ok, v = pcall(C_Spell.GetSpellName, id)
    if ok then n = v end
  end
  if not n and GetSpellInfo then
    local ok, v = pcall(GetSpellInfo, id)
    if ok then n = v end
  end
  if type(n) ~= "string" or n == "" then return nil end
  nameCache[id] = n
  return n
end

-- All recipe names in a craft record.
function P.Recipes(d)
  local out = {}
  if type(d) ~= "table" then return out end
  if type(d.ids) == "string" then
    for id in d.ids:gmatch("%d+") do
      local n = P.RecipeName(tonumber(id))
      if n then out[#out + 1] = n end
    end
  end
  if type(d.names) == "string" then
    for n in d.names:gmatch("[^;]+") do out[#out + 1] = n end
  end
  table.sort(out)
  return out
end

function P.RecipeCount(d)
  if type(d) ~= "table" then return 0 end
  local n = 0
  if type(d.ids) == "string" then for _ in d.ids:gmatch("%d+") do n = n + 1 end end
  if type(d.names) == "string" then for _ in d.names:gmatch("[^;]+") do n = n + 1 end end
  return n
end

-- Every craft record of current guildmates: { member, prof, skill, max, data }
function P.All()
  local out = {}
  for k, d in Data.Each("crafts") do
    local member = Data.SplitKey(k)
    if member and ns.roster[member] and KNOWN[d.prof] then
      out[#out + 1] = { key = k, member = member, prof = d.prof, skill = tonumber(d.skill) or 0, max = tonumber(d.max) or 0, data = d }
    end
  end
  return out
end

----------------------------------------------------------------------
-- Scanning my own professions
----------------------------------------------------------------------
-- { [name] = { skill, max } } for the professions this character has.
local function currentProfessions()
  local out, any = {}, false
  if GetProfessions and GetProfessionInfo then
    local a, b, c, d, e = GetProfessions()
    for _, idx in pairs({ a, b, c, d, e }) do
      local ok, name, _, rank, maxRank = pcall(GetProfessionInfo, idx)
      if ok and type(name) == "string" then
        any = true
        if KNOWN[name] then out[name] = { skill = rank or 0, max = maxRank or 0 } end
      end
    end
  end
  if not any and GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local ok, name, isHeader, _, rank, _, _, maxRank = pcall(GetSkillLineInfo, i)
      if ok and type(name) == "string" and not isHeader then
        any = true
        if KNOWN[name] then out[name] = { skill = rank or 0, max = maxRank or 0 } end
      end
    end
  end
  return out, any
end

local function same(a, b)
  if not a then return false end
  return a.prof == b.prof and a.skill == b.skill and a.max == b.max and a.ids == b.ids and a.names == b.names
end

local function save(prof, fields)
  local me = ns.PlayerName()
  if not me or not ns.roster[me] then return end
  local old = Data.Get("crafts", key(me, prof))
  local d = { prof = prof, skill = old and old.skill or 0, max = old and old.max or 0,
    ids = old and old.ids or nil, names = old and old.names or nil, rts = old and old.rts or nil }
  for k, v in pairs(fields) do d[k] = v end
  if fields.ids then d.names = nil end
  if fields.names then d.ids = nil end
  if same(old, d) then return end
  Data.Put("crafts", key(me, prof), d, true)
end

-- Record skill levels, and drop professions this character no longer has.
function P.ScanSkills()
  if not Data.Ready() then return end
  local me = ns.PlayerName()
  if not me or not ns.roster[me] then return end
  local profs, any = currentProfessions()
  if not any then return end
  for name, s in pairs(profs) do save(name, { skill = s.skill, max = s.max }) end
  for k, d in Data.Each("crafts") do
    local member = Data.SplitKey(k)
    if member == me and not profs[d.prof] then Data.Delete("crafts", k) end
  end
end

-- Record the recipes in the profession window I have open (my own, not a linked one).
function P.ScanRecipes()
  if not Data.Ready() then return end
  local T = C_TradeSkillUI
  if T and T.GetAllRecipeIDs then
    for _, f in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting", "IsRuneforging" }) do
      if T[f] then
        local ok, v = pcall(T[f])
        if ok and v then return end
      end
    end
    local prof, skill, max
    if T.GetBaseProfessionInfo then
      local ok, info = pcall(T.GetBaseProfessionInfo)
      if ok and type(info) == "table" then
        prof = info.parentProfessionName or info.professionName
        skill, max = info.skillLevel, info.maxSkillLevel
      end
    end
    if (not prof or not KNOWN[prof]) and T.GetTradeSkillLine then
      local ok, _, name, rank, maxRank = pcall(T.GetTradeSkillLine)
      if ok and type(name) == "string" then prof, skill, max = name, rank, maxRank end
    end
    if not prof or not KNOWN[prof] then return end
    local okIds, ids = pcall(T.GetAllRecipeIDs)
    if not okIds or type(ids) ~= "table" then return end
    local learned = {}
    ns.db.recipeNames = ns.db.recipeNames or {}
    for _, id in ipairs(ids) do
      local ok, info = pcall(T.GetRecipeInfo, id)
      if ok and type(info) == "table" and info.learned then
        learned[#learned + 1] = id
        if type(info.name) == "string" then ns.db.recipeNames[id] = info.name end
      end
    end
    if #learned == 0 then return end
    table.sort(learned)
    local fields = { ids = table.concat(learned, ","), names = nil, rts = ns.Now() }
    if skill and skill > 0 then fields.skill, fields.max = skill, max end
    save(prof, fields)
    return
  end
  -- Older trade skill window: names only.
  if GetTradeSkillLine and GetNumTradeSkills and GetTradeSkillInfo then
    local ok, prof, skill, max = pcall(GetTradeSkillLine)
    if not ok or not KNOWN[prof] then return end
    local names = {}
    for i = 1, GetNumTradeSkills() do
      local okI, name, kind = pcall(GetTradeSkillInfo, i)
      if okI and type(name) == "string" and kind ~= "header" and kind ~= "subheader" then
        names[#names + 1] = (name:gsub(";", ","))
      end
    end
    if #names == 0 then return end
    table.sort(names)
    save(prof, { names = table.concat(names, ";"), ids = nil, rts = ns.Now(), skill = skill, max = max })
  end
end

local pendingSkills, pendingRecipes = false, false
local function later(flag, fn)
  if not C_Timer then fn(); return end
  if flag == "s" then
    if pendingSkills then return end
    pendingSkills = true
    C_Timer.After(3, function() pendingSkills = false; pcall(fn) end)
  else
    if pendingRecipes then return end
    pendingRecipes = true
    C_Timer.After(1.5, function() pendingRecipes = false; pcall(fn) end)
  end
end

ns.On("DATA_READY", function()
  if C_Timer then C_Timer.After(10, function() pcall(P.ScanSkills) end) else P.ScanSkills() end
end)
ns.RegisterEvent("SKILL_LINES_CHANGED", function() later("s", P.ScanSkills) end)
for _, ev in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
  ns.RegisterEvent(ev, function() later("r", P.ScanRecipes) end)
end

----------------------------------------------------------------------
-- Craft requests: a private addon whisper, no chat
----------------------------------------------------------------------
function P.Request(crafter, recipe, note)
  local info = ns.roster[crafter]
  if not info or not info.online then
    ns.Print(ns.Name(crafter) .. " is offline. Catch them later, or send a letter.")
    return false
  end
  ns.Comm.Send({ op = "CQ", r = ns.Clean(recipe, 80), n = ns.Clean(note or "", 120) }, "WHISPER", crafter)
  ns.Print("Asked " .. ns.Name(crafter) .. " to craft |cffd4a017" .. recipe .. "|r.")
  return true
end

ns.On("CRAFT_REQUEST", function(sender, recipe, note)
  ns.Print("|cffd4a017Craft request:|r " .. ns.Name(sender) .. " asks you to make |cffffd040" .. recipe .. "|r." ..
    ((note and note ~= "") and (" \"" .. note .. "\"") or ""))
  if PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then pcall(PlaySound, SOUNDKIT.TELL_MESSAGE) end
  if ns.UI and ns.UI.Notice then
    ns.UI.Notice({
      id = "craft", icon = "Interface\\Icons\\Trade_BlackSmithing", title = "Craft request",
      text = ns.Name(sender) .. " asks you to make |cffffd040" .. recipe .. "|r." ..
        ((note and note ~= "") and ("\n\"" .. note .. "\"") or ""),
      buttons = { { text = "Got it" } },
    })
  end
end)
