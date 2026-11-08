-- Ironforged: the Blood Tally and the hunt for grudged foes.
--   * Horde slain: your lifetime honorable kills, from the game's own PvP stats.
--   * Elves slain: honorable kills on Horde elves. The victim's race comes from what the addon
--     saw on their nameplate, target or tooltip. Honorable kills on Horde elves out in the world
--     count, solo or grouped; battleground kills don't. The same elf counts at most once an hour.
--   * World kills (Warbringer): honorable kills made outside battlegrounds, counted by this addon
--     from the moment it's installed.
--   * Horde grudges are avenged automatically when a guildmate gets an honorable kill on the
--     foe. Alliance grudges are avenged by an officer.
--   * Grudged foes get a red warning on their tooltip. The first time a grudged foe is spotted,
--     an alert goes to you and the guild; each grudge alerts only once.
local ADDON, ns = ...

local Blood = {}
ns.Blood = Blood

local Data = ns.Data

local function isSecret(v) return issecretvalue and issecretvalue(v) end

local function inBattleground()
  if UnitInBattleground and UnitInBattleground("player") then return true end
  local okI, _, kind = pcall(IsInInstance or function() end)
  return okI and kind == "pvp"
end
Blood.InBattleground = inBattleground

local function personal()
  ns.db.pvp = ns.db.pvp or {}
  local me = ns.PlayerName() or "?"
  ns.db.pvp[me] = ns.db.pvp[me] or { elves = 0, avenged = 0, world = 0 }
  return ns.db.pvp[me]
end

-- Race and faction of foes we've seen, keyed by Data.FoeKey(name).
local function foeCache()
  ns.db.foes = ns.db.foes or {}
  return ns.db.foes
end

-- Ironforged is an Alliance guild, so the elves it kills are Horde elves: on Forever that's the
-- Windshaper Skyborne (sky elves, the shen'dorei), plus Blood Elves. Skyborne also serve the
-- Alliance (the High Order), so the race alone isn't enough: a foe seen as Alliance never counts.
-- Both the race's internal name and its display name are checked.
local ELF_WORDS = { "elf", "elves", "skyborne", "windshaper", "shen'dorei", "shendorei", "sin'dorei", "sindorei" }
function Blood.IsElf(raceFile, raceName)
  -- each one on its own: either may be missing (a scoreboard gives only the display name)
  for _, r in pairs({ raceFile or false, raceName or false }) do
    if type(r) == "string" and not isSecret(r) then
      r = r:lower()
      for _, w in ipairs(ELF_WORDS) do if r:find(w, 1, true) then return true end end
    end
  end
  return false
end

-- Full "First Surname" of a unit.
local function unitName(unit)
  return ns.UnitDisplayName(unit)
end

-- Learn a hostile or friendly player's race and faction from a unit we can see.
local function learn(unit)
  if not unit or isSecret(unit) or not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
  local name = unitName(unit)
  if not name then return nil end
  local raceName, raceFile = UnitRace(unit)
  local faction = UnitFactionGroup and UnitFactionGroup(unit)
  if isSecret(raceFile) then raceFile = nil end
  if isSecret(raceName) then raceName = nil end
  if isSecret(faction) then faction = nil end
  local key = Data.FoeKey(name)
  local c = foeCache()
  local old = c[key]
  c[key] = { name = name, race = raceFile or (old and old.race), raceName = raceName or (old and old.raceName),
    faction = faction or (old and old.faction), seen = time() }
  return name
end
Blood.Learn = learn

----------------------------------------------------------------------
-- Publishing your tally
----------------------------------------------------------------------
local function lifetimeHKs()
  if not GetPVPLifetimeStats then return nil end
  local ok, hk = pcall(GetPVPLifetimeStats)
  if ok and type(hk) == "number" and not isSecret(hk) then return hk end
  return nil
end

function Blood.Publish()
  if not Data.Ready() then return end
  local me = ns.PlayerName()
  local p = personal()
  local hk = lifetimeHKs() or p.hk or 0
  p.hk = hk
  local old = Data.Get("pvp", me)
  if old and old.hk == hk and old.elves == p.elves and old.avenged == p.avenged and old.world == (p.world or 0) then return end
  Data.Put("pvp", me, { hk = hk, elves = p.elves or 0, avenged = p.avenged or 0, world = p.world or 0, ts = ns.Now() }, true)
end

local publishPending = false
local function schedulePublish(delay)
  if publishPending then return end
  publishPending = true
  local function run() publishPending = false; Blood.Publish() end
  if C_Timer then C_Timer.After(delay or 10, run) else run() end
end

function Blood.Tally(name)
  local t = Data.Get("pvp", name)
  if not t then return nil end
  return t.hk or 0, t.elves or 0, t.avenged or 0, t.world or 0
end

----------------------------------------------------------------------
-- Avenging grudges
----------------------------------------------------------------------
local function avenge(foeName, how)
  local me = ns.PlayerName()
  local count = 0
  for _, g in ipairs(Data.GrudgesAgainst(foeName)) do
    if g.data.faction == "Horde" then
      if Data.Put("avenged", g.key, { by = me, how = how or "slain", ts = ns.Now() }, true) then
        count = count + 1
      end
    end
  end
  if count > 0 then
    local p = personal()
    p.avenged = (p.avenged or 0) + count
    schedulePublish(2)
    if PlaySound and SOUNDKIT and SOUNDKIT.UI_BATTLEGROUND_COUNTDOWN_FINISHED then
      pcall(PlaySound, SOUNDKIT.UI_BATTLEGROUND_COUNTDOWN_FINISHED)
    end
  end
  return count
end
Blood.Avenge = avenge

-- Officers avenge any grudge by hand (the only way for Alliance grudges).
function Blood.MarkAvenged(grudgeKey, byName)
  return Data.Put("avenged", grudgeKey, { by = byName or ns.PlayerName(), how = "officer", marker = ns.PlayerName(), ts = ns.Now() })
end

-- Tell everyone when a grudge is avenged (once per grudge).
local function announcedTable()
  ns.db.avengedSeen = ns.db.avengedSeen or {}
  return ns.db.avengedSeen
end

local function announceAvenged()
  if not Data.Ready() then return end
  local seen = announcedTable()
  for key, a in Data.Each("avenged") do
    if not seen[key] then
      seen[key] = true
      local g = Data.Get("grudges", key)
      if g and (a.ts or 0) > ns.Now() - 3600 then
        local how = a.how == "officer" and "has been avenged" or "has fallen"
        ns.Print("|cffffd040GRUDGE AVENGED!|r " .. (g.against or "?") .. " " .. how .. ". " ..
          (a.by and ("Honor to " .. ns.Name(a.by) .. ". ") or "") .. "The book is one line lighter.")
        if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
          pcall(RaidNotice_AddMessage, RaidWarningFrame, "Grudge avenged: " .. (g.against or "?"), ChatTypeInfo.RAID_WARNING)
        end
      end
    end
  end
end

----------------------------------------------------------------------
-- Honorable kills: "%s dies, honorable kill Rank: %s (Estimated Honor Points: %d)"
----------------------------------------------------------------------
local killPatterns
local function toPattern(fmt)
  local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "%%d+"):gsub("%%%%%.?%d*f", "[%%d%%.]+")
  return "^" .. p .. "$"
end

local function victimFromHonorText(text)
  if not killPatterns then
    killPatterns = {}
    for _, g in ipairs({ "COMBATLOG_HONORGAIN", "COMBATLOG_HONORGAIN_NO_RANK", "COMBATLOG_HONORGAIN_EXHAUSTION1" }) do
      if type(_G[g]) == "string" then killPatterns[#killPatterns + 1] = toPattern(_G[g]) end
    end
    killPatterns[#killPatterns + 1] = toPattern("%s dies, honorable kill Rank: %s (Estimated Honor Points: %d)")
    killPatterns[#killPatterns + 1] = "^(.-) dies, honorable kill"
  end
  for _, p in ipairs(killPatterns) do
    local victim = text:match(p)
    if victim then return victim end
  end
  return nil
end
Blood._victimFromHonorText = victimFromHonorText

-- Count an elf kill, at most once an hour for the same elf (by name).
Blood.ELF_COOLDOWN = 60 * 60
-- The cached foe for a name. Messages may give just the first name ("Sylvanor") while units give
-- "First Surname", so fall back to the most recently seen foe with that first name.
local function findFoe(name)
  local key = Data.FoeKey(name)
  local c = foeCache()
  if c[key] then return key, c[key] end
  local first = key:match("^(%S+)")
  local bestKey, best
  for k, f in pairs(c) do
    if k:match("^(%S+)") == first and (not best or (f.seen or 0) > (best.seen or 0)) then bestKey, best = k, f end
  end
  return bestKey or key, best
end
Blood.FindFoe = findFoe

-- Who I've had targeted lately, so a kill can be checked against it.
local targetedAt = {}
-- The last Horde player I had targeted, and when I last saw them as my target.
local lastFoeTarget
local function noteTarget()
  local n = UnitExists and UnitExists("target") and ns.UnitDisplayName("target")
  if not n then return end
  targetedAt[Data.FoeKey(n)] = GetTime()
  local okP, isPlayer = pcall(UnitIsPlayer, "target")
  if not okP or isSecret(isPlayer) or not isPlayer or ns.IsGuildmateName(n) then return end
  local faction = UnitFactionGroup and UnitFactionGroup("target")
  if isSecret(faction) then faction = nil end
  if faction == "Alliance" then return end
  lastFoeTarget = { name = n, t = GetTime() }
end
Blood.LastFoeTarget = function() return lastFoeTarget end
ns.RegisterEvent("PLAYER_TARGET_CHANGED", function() pcall(noteTarget) end)

-- Did I have this player targeted when (or just before) they died?
local function wasMyTarget(victim, key)
  local first = Data.FoeKey(victim):match("^(%S+)")
  local cur = UnitExists and UnitExists("target") and ns.UnitDisplayName("target")
  if cur and Data.FoeKey(cur):match("^(%S+)") == first then return true end
  local t = targetedAt[key] or targetedAt[Data.FoeKey(victim)]
  return t ~= nil and GetTime() - t < 15
end

-- Elfbane rules: honorable kills on Horde elves out in the world count, solo or grouped.
Blood.ELF_RULES = "Elves slain counts your honorable kills on Horde elves out in the world.\n" ..
  "- Solo or in a group, every elf kill counts.\n- Battleground kills don't count.\n- The same elf counts at most once an hour."

Blood.WORLD_RULES = "World kills counts your honorable kills outside battlegrounds:\n" ..
  "the open world, solo or grouped. It starts counting from when you install this version.\n" ..
  "The most world kills holds the title Warbringer."

Blood.AVENGED_RULES = "Grudges from the Book of Grudges that you avenged.\n" ..
  "You avenge one by getting an honorable kill on a Horde player with an open grudge against them.\n" ..
  "Each open grudge counts once. Alliance grudges are marked avenged by an officer and don't add to this count."

function Blood.CountElf(victim, how)
  local key, foe = findFoe(victim)
  -- every honorable kill an Alliance dwarf gets is on the Horde, so only Horde elves can turn up here
  if not foe or foe.faction == "Alliance" or not Blood.IsElf(foe.race, foe.raceName) then return false end
  -- elves count out in the world only
  if inBattleground() then
    ns.Print("|cff999999" .. ns.Name(victim) .. " falls, but elf kills in a battleground don't count toward Elfbane.|r")
    return false
  end
  ns.db.elfCounted = ns.db.elfCounted or {}
  local last = ns.db.elfCounted[key]
  local now = ns.Now()
  if last and now - last < Blood.ELF_COOLDOWN then
    ns.Print("|cff999999" .. ns.Name(victim) .. " already counted toward your elves this hour.|r")
    return false
  end
  ns.db.elfCounted[key] = now
  local p = personal()
  p.elves = (p.elves or 0) + 1
  ns.Print("|cffd4a017An elf falls.|r " .. ns.Name(victim) .. " is the " .. p.elves .. Blood.Ordinal(p.elves) .. " elf to fall to your axe.")
  schedulePublish(5)
  return true
end

local recentKills = {}
function Blood.OnHonorableKill(victim)
  if not victim or victim == "" then return end
  local key = Data.FoeKey(victim)
  local t = GetTime()
  if recentKills[key] and t - recentKills[key] < 10 then return end -- both ways of noticing the same kill
  recentKills[key] = t
  -- remember the last few kills and the race seen for each, for /hold kills
  local _, foe = findFoe(victim)
  ns.db.lastKills = ns.db.lastKills or {}
  table.insert(ns.db.lastKills, 1, { name = victim, race = foe and foe.race, raceName = foe and foe.raceName,
    faction = foe and foe.faction, ts = ns.Now() })
  while #ns.db.lastKills > 10 do table.remove(ns.db.lastKills) end
  Blood.CountElf(victim, "kill")
  avenge(victim, "slain")
  schedulePublish(5)
end

function Blood.Ordinal(n)
  local last2, last = n % 100, n % 10
  if last2 >= 11 and last2 <= 13 then return "th" end
  if last == 1 then return "st" elseif last == 2 then return "nd" elseif last == 3 then return "rd" end
  return "th"
end

local function diag()
  ns.db.killDiag = ns.db.killDiag or { msgs = 0, named = 0, counts = 0, matched = 0 }
  return ns.db.killDiag
end
Blood.Diag = diag

ns.RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN", function(text)
  local d = diag()
  d.msgs = d.msgs + 1
  if type(text) ~= "string" or isSecret(text) then return end
  local victim = victimFromHonorText(text)
  if victim then d.named = d.named + 1; Blood.OnHonorableKill(victim) end
end)

----------------------------------------------------------------------
-- The second way to notice a kill: the game's honorable-kill count goes up. Each new kill is
-- matched to a Horde player the addon just saw die (target, nameplate or mouseover). This works
-- even when the game doesn't name the victim in chat. The same count drives world kills.
----------------------------------------------------------------------
local recentDeaths = {} -- { name, t }
local function noteDeath(unit)
  if not unit or not UnitExists or not UnitExists(unit) then return end
  local okP, isPlayer = pcall(UnitIsPlayer, unit)
  if not okP or isSecret(isPlayer) or not isPlayer then return end
  local okD, dead = pcall(UnitIsDeadOrGhost, unit)
  if not okD or isSecret(dead) or not dead then return end
  local name = learn(unit)
  if not name or ns.IsGuildmateName(name) then return end
  local f = foeCache()[Data.FoeKey(name)]
  if f and f.faction == "Alliance" then return end
  local key = Data.FoeKey(name)
  -- my own target died: an elf counts even without honor
  if unit == "target" then pcall(Blood.ElfDied, name, false) end
  for _, r in ipairs(recentDeaths) do if r.key == key and GetTime() - r.t < 10 then return end end
  table.insert(recentDeaths, 1, { name = name, key = key, t = GetTime() })
  while #recentDeaths > 20 do table.remove(recentDeaths) end
end
Blood.NoteDeath = noteDeath

-- An elf died without (or before) an honorable kill. It counts when I slew them, or when they were
-- the Horde player I was fighting (my target within the last 15 seconds). Never avenges grudges:
-- that still takes an honorable kill.
function Blood.ElfDied(name, mine)
  if not name or name == "" then return false end
  local key, foe = findFoe(name)
  if not foe or foe.faction == "Alliance" or not Blood.IsElf(foe.race, foe.raceName) then return false end
  local fighting = mine
  if not fighting then
    local first = key:match("^(%S+)")
    local lt = lastFoeTarget
    if lt and GetTime() - lt.t <= 15 and Data.FoeKey(lt.name):match("^(%S+)") == first then fighting = true end
    local cur = UnitExists and UnitExists("target") and ns.UnitDisplayName("target")
    if cur and Data.FoeKey(cur):match("^(%S+)") == first then fighting = true end
  end
  if not fighting then return false end
  -- its own record of handled deaths, so a later honorable kill still avenges grudges
  -- (the elf itself counts once either way: CountElf allows one per elf an hour)
  Blood.elfDeathAt = Blood.elfDeathAt or {}
  local t = GetTime()
  if Blood.elfDeathAt[key] and t - Blood.elfDeathAt[key] < 10 then return false end
  Blood.elfDeathAt[key] = t
  ns.db.lastKills = ns.db.lastKills or {}
  table.insert(ns.db.lastKills, 1, { name = name, race = foe.race, raceName = foe.raceName, faction = foe.faction, ts = ns.Now() })
  while #ns.db.lastKills > 10 do table.remove(ns.db.lastKills) end
  return Blood.CountElf(name, "slain")
end

-- The combat log, where the game still writes it to chat: "You have slain X!" and "X dies."
local slainPatterns, diesPatterns
local function patternsFrom(names, fallbacks)
  local out = {}
  for _, g in ipairs(names) do if type(_G[g]) == "string" then out[#out + 1] = toPattern(_G[g]) end end
  for _, f in ipairs(fallbacks) do out[#out + 1] = toPattern(f) end
  return out
end
local function deathFromText(text)
  slainPatterns = slainPatterns or patternsFrom({ "SELFKILLOTHER" }, { "You have slain %s!" })
  diesPatterns = diesPatterns or patternsFrom({ "UNITDIESOTHER" }, { "%s dies." })
  for _, p in ipairs(slainPatterns) do local v = text:match(p); if v then return v, true end end
  for _, p in ipairs(diesPatterns) do local v = text:match(p); if v then return v, false end end
end
Blood._deathFromText = deathFromText

local function onDeathMessage(text)
  local d = diag()
  d.deathMsgs = (d.deathMsgs or 0) + 1
  if type(text) ~= "string" or isSecret(text) then return end
  local victim, mine = deathFromText(text)
  if victim then pcall(Blood.ElfDied, victim, mine) end
end
ns.RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", onDeathMessage)

-- No COMBAT_LOG_EVENT_UNFILTERED: on Forever (Midnight client) registering it is a protected action
-- and the game shows "Ironforged has been blocked from an action". The chat death lines above stay.

-- Honorable kills so far: today's count where the game keeps one (it moves at once), else lifetime.
local function killCount()
  if GetPVPSessionStats then
    local ok, hk = pcall(GetPVPSessionStats)
    if ok and type(hk) == "number" and not isSecret(hk) then return hk, "session" end
  end
  local hk = lifetimeHKs()
  if hk then return hk, "lifetime" end
end

local lastCount, lastKind
function Blood.OnKillCountChanged()
  local n, kind = killCount()
  if not n then return end
  if lastCount == nil or kind ~= lastKind or n < lastCount then lastCount, lastKind = n, kind; return end -- a new day resets it
  local gained = n - lastCount
  lastCount = n
  if gained <= 0 then return end
  local d = diag()
  d.counts = d.counts + gained
  local p = personal()
  if not inBattleground() then
    p.world = (p.world or 0) + gained
  end
  -- match the new kills to players just seen dying
  local now = GetTime()
  for i = #recentDeaths, 1, -1 do if now - recentDeaths[i].t > 10 then table.remove(recentDeaths, i) end end
  local usedTarget = false
  for _ = 1, gained do
    local r = table.remove(recentDeaths, 1)
    if r then
      d.matched = d.matched + 1
      Blood.OnHonorableKill(r.name)
    elseif not usedTarget and lastFoeTarget and now - lastFoeTarget.t <= 15 then
      -- no death seen (nameplates vanish, or the game hides it): the Horde player I was fighting
      usedTarget = true
      d.fromTarget = (d.fromTarget or 0) + 1
      Blood.OnHonorableKill(lastFoeTarget.name)
    end
  end
  schedulePublish(3)
end

ns.RegisterEvent("PLAYER_PVP_KILLS_CHANGED", function()
  pcall(Blood.OnKillCountChanged)
  schedulePublish(10)
end)
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
  local n, kind = killCount()
  if n then lastCount, lastKind = n, kind end
end)

----------------------------------------------------------------------
-- Battlegrounds: the scoreboard lists every player's race and faction, so foes count as elves
-- even when the addon never saw their nameplate.
----------------------------------------------------------------------
local function learnScore(name, factionIndex, raceName)
  if type(name) ~= "string" or isSecret(name) or name == "" then return end
  if isSecret(raceName) then raceName = nil end
  local faction = (factionIndex == 0 and "Horde") or (factionIndex == 1 and "Alliance") or nil
  local n = ns.Name(name)
  if not n or ns.IsGuildmateName(n) then return end
  local key = Data.FoeKey(n)
  local c = foeCache()
  local old = c[key]
  c[key] = { name = n, race = old and old.race, raceName = raceName or (old and old.raceName),
    faction = faction or (old and old.faction), seen = time() }
end

function Blood.ReadScoreboard()
  if not GetNumBattlefieldScores then return 0 end
  local ok, n = pcall(GetNumBattlefieldScores)
  if not ok or type(n) ~= "number" or isSecret(n) then return 0 end
  local learned = 0
  for i = 1, n do
    if C_PvP and C_PvP.GetScoreInfo then
      local okI, s = pcall(C_PvP.GetScoreInfo, i)
      if okI and type(s) == "table" then learnScore(s.name, s.faction, s.raceName); learned = learned + 1 end
    elseif GetBattlefieldScore then
      -- older clients: name, killingBlows, honorableKills, deaths, honorGained, faction, rank, race, ...
      -- (no rank on newer ones, so race may be the 7th value)
      local okS, name, _, _, _, _, faction, a7, a8 = pcall(GetBattlefieldScore, i)
      if okS then
        local race = (type(a7) == "string" and a7) or (type(a8) == "string" and a8) or nil
        learnScore(name, faction, race); learned = learned + 1
      end
    end
  end
  return learned
end

ns.RegisterEvent("UPDATE_BATTLEFIELD_SCORE", function() pcall(Blood.ReadScoreboard) end)
-- while in a battleground, ask for the scoreboard now and then (a request to the game, nothing sent)
if C_Timer and C_Timer.NewTicker then
  C_Timer.NewTicker(20, function()
    if inBattleground() and RequestBattlefieldScoreData then pcall(RequestBattlefieldScoreData) end
  end)
end
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
  if C_Timer then C_Timer.After(5, function()
    if inBattleground() and RequestBattlefieldScoreData then pcall(RequestBattlefieldScoreData) end
  end) end
end)


----------------------------------------------------------------------
-- Seeing foes: learn their race, warn about grudged ones, notice when they fall.
----------------------------------------------------------------------

-- Horde players seen in the last `secs` seconds (nameplates, target, mouseover), newest first.
function Blood.RecentHorde(secs, max)
  local out, t = {}, time()
  for _, f in pairs(foeCache()) do
    if f.faction == "Horde" and type(f.name) == "string" and t - (f.seen or 0) <= secs then out[#out + 1] = f end
  end
  table.sort(out, function(a, b) return a.seen > b.seen end)
  local names = {}
  for i = 1, math.min(#out, max or 5) do names[i] = out[i].name end
  return names
end

local function zoneName()
  local z = GetZoneText and GetZoneText()
  if isSecret(z) then return "" end
  return z or ""
end

-- Each grudge raises its alert only once per character, ever.
local function alertedGrudges()
  ns.db.grudgeAlerted = ns.db.grudgeAlerted or {}
  return ns.db.grudgeAlerted
end

-- Unalerted open grudges against a foe; marks them alerted.
local function takeNewGrudges(foe)
  local done = alertedGrudges()
  local fresh = {}
  for _, g in ipairs(Data.GrudgesAgainst(foe)) do
    if not done[g.key] then
      done[g.key] = true
      fresh[#fresh + 1] = g
    end
  end
  return fresh
end

local function alertSighting(foe, spotter, zone)
  local grudges = takeNewGrudges(foe)
  if #grudges == 0 then return false end
  local deed = grudges[1].data.deed or ""
  if #deed > 60 then deed = deed:sub(1, 57) .. "..." end
  local where = (zone and zone ~= "") and (" in " .. zone) or ""
  if spotter then
    ns.Print("|cffff4040GRUDGED FOE SPOTTED:|r " .. ns.Name(spotter) .. " sees " .. foe .. where .. ". (" .. deed .. ")")
  else
    ns.Print("|cffff4040A GRUDGED FOE IS NEAR:|r " .. foe .. " - " .. deed ..
      (#grudges > 1 and (" (+" .. (#grudges - 1) .. " more grudges)") or ""))
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
      pcall(RaidNotice_AddMessage, RaidWarningFrame, "Grudged foe: " .. foe, ChatTypeInfo.RAID_WARNING)
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
    ns.Fire("GRUDGE_NEAR", foe, deed, #grudges)
  end
  return true
end

local function checkUnit(unit, fromNameplate)
  if not ns.settings or not Data.Ready() then return end
  local name = learn(unit)
  if not name or ns.IsGuildmateName(name) then return end
  local grudges = Data.GrudgesAgainst(name)
  if #grudges == 0 then return end
  -- a corpse raises no alarm (and seeing one avenges nothing: only an honorable kill does)
  local okDead, dead = pcall(UnitIsDeadOrGhost, unit)
  if okDead and dead and not isSecret(dead) then return end
  if ns.settings.grudgeAlerts == false then return end
  local zone = zoneName()
  if alertSighting(name, nil, zone) and ns.Comm then ns.Comm.BroadcastSighting(name, zone) end
end
Blood.CheckUnit = checkUnit
Blood.ZoneName = zoneName

ns.On("SIGHTING", function(sender, foe, zone)
  if ns.settings and ns.settings.grudgeAlerts == false then return end
  alertSighting(foe, sender, zone)
end)

ns.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(unit) pcall(checkUnit, unit, true) end)
ns.RegisterEvent("PLAYER_TARGET_CHANGED", function() pcall(checkUnit, "target") end)
ns.RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() pcall(checkUnit, "mouseover") end)
ns.RegisterEvent("UNIT_HEALTH", function(unit)
  if unit == "target" then pcall(noteTarget) end
  if unit == "target" or unit == "mouseover" or (type(unit) == "string" and unit:find("^nameplate")) then
    pcall(checkUnit, unit)
    pcall(noteDeath, unit)
  end
end)
ns.RegisterEvent("UNIT_FLAGS", function(unit)
  if unit == "target" or (type(unit) == "string" and unit:find("^nameplate")) then pcall(noteDeath, unit) end
end)

----------------------------------------------------------------------
-- Tooltip: red warning on grudged foes
----------------------------------------------------------------------
local function addGrudgeLines(tooltip)
  if not Data.Ready() then return end
  local okU, _, unit = pcall(tooltip.GetUnit, tooltip)
  if not okU or not unit or isSecret(unit) or not UnitIsPlayer(unit) then return end
  local name = unitName(unit)
  if not name or ns.IsGuildmateName(name) then return end
  local all = Data.GrudgesAgainst(name, true)
  if #all == 0 then return end
  local open = 0
  for _, g in ipairs(all) do if not Data.Avenged(g.key) then open = open + 1 end end
  if open > 0 then
    tooltip:AddLine("GRUDGE: " .. open .. (open == 1 and " wrong unavenged" or " wrongs unavenged"), 1, 0.25, 0.25)
    local shown = 0
    for _, g in ipairs(all) do
      if not Data.Avenged(g.key) and shown < 2 then
        shown = shown + 1
        local deed = g.data.deed or ""
        if #deed > 70 then deed = deed:sub(1, 67) .. "..." end
        tooltip:AddLine("  " .. deed, 1, 0.6, 0.6, true)
      end
    end
  else
    tooltip:AddLine("Grudge avenged", 0.95, 0.78, 0.38)
  end
  tooltip:Show()
end

Blood._addGrudgeLines = addGrudgeLines

ns.RegisterEvent("PLAYER_LOGIN", function()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
      if tooltip ~= GameTooltip then return end
      pcall(addGrudgeLines, tooltip)
    end)
  end
end)

ns.On("DATA_READY", function() schedulePublish(12) end)
ns.On("DATA_CHANGED", function(coll)
  if coll == nil or coll == "avenged" then
    if C_Timer then C_Timer.After(0.5, announceAvenged) else announceAvenged() end
  end
end)
ns.On("DATA_READY", function()
  -- don't replay old avengings on first load
  local seen = announcedTable()
  for key in Data.Each("avenged") do seen[key] = true end
end)
