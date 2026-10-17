-- Ironforged: the dwarves-only rule: race reports, race scans and non-dwarf invite alerts.
-- Each client reports its own character's race and gear check to the guild.
local ADDON, ns = ...

local Gear = {}
ns.Gear = Gear

Gear.DWARF = { Dwarf = true, DarkIronDwarf = true }

local function isSecret(v) return issecretvalue and issecretvalue(v) end

local function seenCache()
  ns.db.racesSeen = ns.db.racesSeen or {}
  return ns.db.racesSeen
end

-- Race file ("Dwarf", "Human", ...) for a character, or nil if unknown.
function Gear.RaceOf(name)
  if not name then return nil end
  if name == ns.PlayerName() then
    local _, raceFile = UnitRace("player")
    return raceFile
  end
  local r = ns.Data.SelfReport(name)
  if r and r.race then return r.race end
  local scan = ns.Data.Get("racecheck", name)
  if scan and scan.race then return scan.race end
  local short = "~" .. ns.NameKey(name)
  if ns.db then
    local cache = seenCache()
    if cache[name] then return cache[name] end
    if cache[short] then return cache[short] end
  end
  -- what the inviter's client saw when they sent the guild invite
  for key, entry in ns.Data.Each("invitelog") do
    if entry.race and "~" .. (select(2, ns.Data.SplitKey(key)) or "") == short then return entry.race end
  end
  return nil
end

-- true = dwarf, false = not a dwarf, nil = unknown
function Gear.IsDwarf(name)
  local race = Gear.RaceOf(name)
  if race == nil then return nil end
  return Gear.DWARF[race] == true
end

----------------------------------------------------------------------
-- Race report: your own client tells the guild what race you are.
----------------------------------------------------------------------
function Gear.Report()
  if not ns.Data.Ready() then return end
  local _, raceFile = UnitRace("player")
  if not raceFile then return end
  local me = ns.PlayerName()
  local old = ns.Data.SelfReport(me)
  if not old or old.race ~= raceFile or old.issues then
    ns.Data.Put("selfreport", me, { race = raceFile, checked = ns.Now() }, true)
  end
end

function Gear.RaceStatus(name)
  local dwarf = Gear.IsDwarf(name)
  if dwarf == true then return "|cff40ff40Dwarf|r" end
  if dwarf == false then return "|cffff6060NOT|r" end
  return "|cff888888?|r"
end

----------------------------------------------------------------------
-- Learn races from tooltips, and warn about inviting non-dwarves.
----------------------------------------------------------------------
local function shortKey(name)
  return ns.NameKey(name or "")
end

local function remember(unit)
  if not unit or isSecret(unit) or not UnitIsPlayer(unit) then return end
  local display = ns.UnitDisplayName(unit)
  local _, raceFile = UnitRace(unit)
  if not display or not raceFile or isSecret(raceFile) then return end
  local full = ns.FullName(display)
  if ns.db then
    seenCache()[full] = raceFile
    seenCache()["~" .. ns.NameKey(display)] = raceFile
  end
end
Gear.Remember = remember

----------------------------------------------------------------------
-- Guild race scan: look up each member's race from their character ID.
-- Works for characters this client already knows about; the rest stay "?".
-- Officers share what they find with the guild.
----------------------------------------------------------------------
local function raceFromGUID(guid)
  if not guid or isSecret(guid) or not GetPlayerInfoByGUID then return nil end
  -- returns localizedClass, englishClass, localizedRace, englishRace, ...
  local ok, _, _, _, raceFile = pcall(GetPlayerInfoByGUID, guid)
  if ok and type(raceFile) == "string" and raceFile ~= "" and not isSecret(raceFile) then return raceFile end
  return nil
end

function Gear.ScanGuild()
  if not ns.Data.Ready() then return end
  if InCombatLockdown and InCombatLockdown() then ns.Print("Finish the fight first."); return end
  local officer = ns.IAmOfficer()
  local found, dwarves, others, unknown, shared = 0, 0, 0, 0, 0
  local outsiders = {}
  for _, name in ipairs(ns.rosterList) do
    local info = ns.roster[name]
    local race = raceFromGUID(info.guid)
    if race then
      found = found + 1
      seenCache()[name] = race
      seenCache()["~" .. shortKey(name)] = race
      local old = ns.Data.Get("racecheck", name)
      if officer and (not old or old.race ~= race) then
        if ns.Data.Put("racecheck", name, { race = race }, true) then shared = shared + 1 end
      end
    end
    local dwarf = Gear.IsDwarf(name)
    if dwarf == true then dwarves = dwarves + 1
    elseif dwarf == false then others = others + 1; outsiders[#outsiders + 1] = ns.ShortName(name)
    else unknown = unknown + 1 end
  end
  ns.Print(string.format("Scanned %d guildmates: %d dwarves, %d not dwarves, %d unknown.", #ns.rosterList, dwarves, others, unknown))
  if #outsiders > 0 then ns.Print("|cffff6060Not dwarves:|r " .. table.concat(outsiders, ", ")) end
  if unknown > 0 then
    ns.Print("Unknown races fill in as you group with, target or mouse over those members, or when they install Ironforged.")
  end
  if not officer and found > 0 then ns.Print("Only officers' scans are shared with the guild; this one is just for you.") end
  ns.Fire("DATA_CHANGED", "racecheck")
end

-- Check everyone in your party or raid whenever the group changes.
local function scanGroup()
  if InCombatLockdown and InCombatLockdown() then return end
  local prefix, n = "party", 4
  if IsInRaid and IsInRaid() then prefix, n = "raid", 40 end
  for i = 1, n do
    local unit = prefix .. i
    if UnitExists(unit) then pcall(remember, unit) end
  end
end
ns.RegisterEvent("GROUP_ROSTER_UPDATE", scanGroup)

----------------------------------------------------------------------
-- Guild invites: every invite is logged by the inviter's own client, with the
-- invitee's race when it's known. Non-dwarf invites are announced to everyone
-- with the addon, the inviter is flagged, and officers get a popup.
----------------------------------------------------------------------

-- Inviters who brought `name` into the guild (or tried to).
function Gear.InvitersOf(name)
  local out, want = {}, shortKey(name)
  for key in ns.Data.Each("invitelog") do
    local inviter, invitee = ns.Data.SplitKey(key)
    if invitee == want then out[#out + 1] = inviter end
  end
  table.sort(out)
  return out
end

-- Non-dwarves a member has invited: { "Name", ... }
function Gear.NonDwarfInvites(inviter)
  local out = {}
  for key, entry in ns.Data.Each("invitelog") do
    local who, invitee = ns.Data.SplitKey(key)
    if who == inviter then
      local race = entry.race or Gear.RaceOf(entry.name or invitee)
      if race and not Gear.DWARF[race] then out[#out + 1] = entry.name or invitee end
    end
  end
  table.sort(out)
  return out
end

local function logInvite(name, race)
  local me = ns.PlayerName()
  if not me or not ns.Data.Ready() then return end
  local key = me .. "#" .. shortKey(name)
  local old = ns.Data.Get("invitelog", key)
  if old and old.race == race then return end
  ns.Data.Put("invitelog", key, { name = (name:gsub("%-.*$", "")), race = race or (old and old.race) or nil, ts = ns.Now() }, true)
end

local function checkInvite(name)
  if type(name) ~= "string" or name == "" or isSecret(name) then return end
  local full = ns.FullName(name)
  if UnitExists("target") then
    local tn = ns.UnitDisplayName("target")
    if tn and ns.NameKey(tn) == ns.NameKey(name) then remember("target") end
  end
  local race = Gear.RaceOf(full)
  logInvite(name, race)
  if race and not Gear.DWARF[race] then
    ns.Print("|cffff6060" .. ns.ShortName(full) .. " is no dwarf! The law of the hold forbids inviting non-dwarves. The Longbeards will hear of this.|r")
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
  elseif not race then
    ns.Print("Make sure " .. ns.ShortName(full) .. " is a dwarf before they join the hold.")
  end
end
Gear.CheckInvite = checkInvite

-- After someone joins, the inviter's client fills in their race, and officers record it for all.
-- Remember a race we've learned, share it if we're an officer (or the inviter), and re-check the hold.
function Gear.RecordRace(name, race)
  if not name or not race then return end
  local full = ns.FullName(name)
  seenCache()[full] = race
  seenCache()["~" .. shortKey(name)] = race
  local me = ns.PlayerName()
  if ns.Data.Get("invitelog", me .. "#" .. shortKey(name)) then logInvite(name, race) end
  if ns.IAmOfficer() and ns.roster[full] then
    local old = ns.Data.Get("racecheck", full)
    if not old or old.race ~= race then ns.Data.Put("racecheck", full, { race = race }, true) end
  end
  Gear.ScheduleIntruderCheck()
end

local function resolveNewMember(who)
  local full = ns.FullName(who)
  local info = ns.roster[full]
  local race = info and raceFromGUID(info.guid) or Gear.RaceOf(full)
  if race then Gear.RecordRace(full, race) end
end

local joinPattern
ns.RegisterEvent("CHAT_MSG_SYSTEM", function(text)
  if type(text) ~= "string" or isSecret(text) then return end
  if not joinPattern then
    local tmpl = ERR_GUILD_JOIN_S or "%s has joined the guild."
    joinPattern = "^" .. tmpl:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
  end
  local who = text:match(joinPattern)
  if not who then return end
  ns.RequestRoster()
  if C_Timer then
    C_Timer.After(3, function() resolveNewMember(who) end)
    C_Timer.After(10, function() resolveNewMember(who) end)
  else
    resolveNewMember(who)
  end
end)

-- Announce new non-dwarf invites and members (once each), and alert officers with a popup.
local function alertedTable()
  local key = ns.GuildKey() or "?"
  ns.db.alerted = ns.db.alerted or {}
  ns.db.alerted[key] = ns.db.alerted[key] or { invites = {}, members = {} }
  return ns.db.alerted[key]
end

function Gear.CheckIntruders()
  if not ns.Data.Ready() or not ns.db then return end
  local seen = alertedTable()
  local popupLines = {}

  for key, entry in ns.Data.Each("invitelog") do
    local inviter, invitee = ns.Data.SplitKey(key)
    local race = entry.race or Gear.RaceOf(entry.name or invitee)
    if race and not Gear.DWARF[race] and not seen.invites[key] then
      seen.invites[key] = true
      local line = ns.ShortName(inviter) .. " invited " .. (entry.name or invitee) .. ", who is not a dwarf."
      ns.Print("|cffff6060" .. line .. "|r")
      popupLines[#popupLines + 1] = line
    end
  end

  for _, name in ipairs(ns.rosterList) do
    if Gear.IsDwarf(name) == false and not seen.members[name] then
      seen.members[name] = true
      local inviters = Gear.InvitersOf(name)
      local by = #inviters > 0 and (" Invited by " .. table.concat(inviters, ", "):gsub("%-[^,]*", "") .. ".") or ""
      local line = ns.ShortName(name) .. " is in the guild and is not a dwarf." .. by
      ns.Print("|cffff6060" .. line .. "|r")
      popupLines[#popupLines + 1] = line
    end
  end

  if #popupLines > 0 and ns.IAmOfficer() and ns.UI and ns.UI.OpenForm then
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
    ns.UI.OpenForm({
      title = "|cffff4040A non-dwarf in the hold!|r",
      width = 520,
      fields = { { type = "info", value = table.concat(popupLines, "\n") .. "\n\nOpen the roster and tick Rule problems to see them, and to remove them from the guild." } },
      buttons = { { text = "Open roster", onClick = function() ns.ToggleMain("roster", { problems = true }) end } },
    })
  end
end

local intruderPending = false
function Gear.ScheduleIntruderCheck()
  if intruderPending then return end
  intruderPending = true
  local function run() intruderPending = false; Gear.CheckIntruders() end
  if C_Timer then C_Timer.After(2, run) else run() end
end
ns.On("DATA_CHANGED", function(coll)
  if coll == nil or coll == "invitelog" or coll == "selfreport" or coll == "racecheck" then Gear.ScheduleIntruderCheck() end
end)
ns.On("DATA_READY", function() if C_Timer then C_Timer.After(15, Gear.ScheduleIntruderCheck) end end)

ns.RegisterEvent("PLAYER_LOGIN", function()
  if hooksecurefunc then
    if C_GuildInfo and C_GuildInfo.Invite then hooksecurefunc(C_GuildInfo, "Invite", checkInvite) end
    if GuildInvite then hooksecurefunc("GuildInvite", checkInvite) end
  end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
      if InCombatLockdown and InCombatLockdown() then return end
      local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
      if ok then pcall(remember, unit) end
    end)
  end
end)

ns.On("DATA_READY", function()
  if C_Timer then C_Timer.After(8, Gear.Report) else Gear.Report() end
end)
