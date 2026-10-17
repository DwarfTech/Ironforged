-- Ironforged: core namespace, events, roster cache, permissions, slash commands.
local ADDON, ns = ...
_G.Ironforged = ns

ns.VERSION = "2.16.6"
ns.PROTOCOL = 11
ns.PREFIX = "IRONFORGED"
ns.COLOR = "ffd4a017"

local L = {}
ns.L = L

----------------------------------------------------------------------
-- Small utilities
----------------------------------------------------------------------
function ns.Print(msg)
  local frame = DEFAULT_CHAT_FRAME
  if frame then frame:AddMessage("|c" .. ns.COLOR .. "Ironforged|r: " .. tostring(msg)) end
end

function ns.Trim(s)
  if type(s) ~= "string" then return "" end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Remove characters addon messages and saved files can't carry.
function ns.Clean(s, maxLen)
  s = ns.Trim(s or ""):gsub("%z", ""):gsub("|", "/")
  if maxLen and #s > maxLen then s = s:sub(1, maxLen) end
  return s
end

function ns.Now()
  if GetServerTime then return GetServerTime() end
  return time()
end

local lastStamp = 0
-- Monotonic revision stamp: server seconds * 1000 plus a counter.
function ns.Stamp()
  local t = ns.Now() * 1000
  if t <= lastStamp then t = lastStamp + 1 end
  lastStamp = t
  return t
end

function ns.Hash(s)
  local h = 5381
  for i = 1, #s do
    h = (h * 33 + s:byte(i)) % 2147483647
  end
  return h
end

function ns.NewId()
  return string.format("%x%x", ns.Now() % 0xFFFFFF, math.random(0, 0xFFFFF))
end

function ns.RealmSuffix()
  local realm = GetNormalizedRealmName and GetNormalizedRealmName()
  if realm and realm ~= "" then return realm end
  return nil
end

-- Canonical "Name-Realm" form so roster names and message senders match.
-- Matching key for any character name. Forever has no realms but gives characters a first
-- name and a surname, which some APIs return as "First Surname" and others as "First-Surname".
-- The key is lowercase "first surname", with any realm suffix of ours removed.
function ns.NameKey(name)
  if type(name) ~= "string" then return "" end
  name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local suffix = name:match("%-([^%s%-]+)$")
  if suffix then
    -- "First Surname-Realm": the part after the hyphen is a realm. "First-Surname" (no space):
    -- only a realm when it's one we know.
    if name:find(" ", 1, true) or suffix == ns.RealmSuffix() or (ns.knownRealms and ns.knownRealms[suffix]) then
      name = name:sub(1, -#suffix - 2)
    end
  end
  name = name:gsub("%-", " "):gsub("%s+", " ")
  return ns.Trim(name):lower()
end

-- A unit's full name, first name and surname together, e.g. "Grubnak Skullsplitter".
function ns.UnitDisplayName(unit)
  local full
  if GetUnitName then
    local ok, n = pcall(GetUnitName, unit, false)
    if ok then full = n end
  end
  if issecretvalue and issecretvalue(full) then return nil end
  local first, second = UnitName(unit)
  if issecretvalue and (issecretvalue(first) or issecretvalue(second)) then return full end
  if type(full) == "string" and full ~= "" and full ~= first then return full end
  if first and second and second ~= "" and ns.IS_FOREVER then return first .. " " .. second end
  return full or first
end

ns.IS_FOREVER = (WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT)
  or (function()
    local v = select(4, GetBuildInfo and GetBuildInfo() or nil)
    return type(v) == "number" and v >= 16000 and v < 20000
  end)()

-- Canonical name for a character. Prefers the exact form the guild roster uses, matching on the
-- name before any realm suffix, because Forever's single mega-server can report realms differently
-- in different places (roster, chat, unit names).
ns.rosterByShort = {}
function ns.FullName(name)
  if type(name) ~= "string" or name == "" then return nil end
  if ns.roster and ns.roster[name] then return name end
  local key = ns.NameKey(name)
  local known = ns.rosterByShort[key] or ns.rosterByShort[(name:gsub("%-.*$", "")):lower()]
    or ns.rosterByShort[key:match("^(%S+)%s") or ""]
  if known then return known end
  if name:find("-", 1, true) then return name end
  local realm = ns.RealmSuffix()
  if realm then return name .. "-" .. realm end
  return name
end

-- Name for display: Forever has one server, so any "-Realm" suffix is dropped.
-- "Frugo Firehammer-ClassicBetaPvP" -> "Frugo Firehammer".
function ns.ShortName(name)
  if type(name) ~= "string" then return "?" end
  local stripped = name:gsub("%-[^%s%-]+$", "")
  if stripped ~= "" then return stripped end
  return name
end

-- The name the game server knows a character by, for whispers, invites and slash commands.
-- Forever shows first and last names ("Buttercup Clamstone-ClassicBetaPvP"), but the character's
-- actual name is the first one: "Buttercup-ClassicBetaPvP". withRealm=false drops the realm too.
function ns.CharName(name, withRealm)
  if type(name) ~= "string" then return name end
  local base, realm = name:match("^(.-)%-([^%s%-]+)$")
  base = base or name
  local first = base:match("^(%S+)") or base
  if realm and withRealm ~= false then return first .. "-" .. realm end
  return first
end

-- Your own roster name, matched by character ID first (exact), then by name.
function ns.PlayerName()
  local guid = UnitGUID and UnitGUID("player")
  if guid and ns.rosterByGUID and ns.rosterByGUID[guid] then return ns.rosterByGUID[guid] end
  return ns.FullName(ns.UnitDisplayName("player"))
end

function ns.FormatDate(ts)
  if not ts then return "" end
  return date("%Y-%m-%d", ts)
end

function ns.FormatDateTime(ts)
  if not ts then return "" end
  return date("%a %b %d, %H:%M", ts)
end

function ns.CurrentPeriod()
  return date("%Y-%m", ns.Now())
end

-- "2026-11-12 19:30" -> epoch seconds, or nil.
function ns.ParseDateTime(s)
  s = ns.Trim(s or "")
  local y, mo, d, h, mi = s:match("^(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s+(%d%d?):(%d%d)$")
  if not y then
    y, mo, d = s:match("^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$")
    h, mi = 20, 0
  end
  if not y then return nil end
  y, mo, d, h, mi = tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi)
  if mo < 1 or mo > 12 or d < 1 or d > 31 or h > 23 or mi > 59 then return nil end
  return time({ year = y, month = mo, day = d, hour = h, min = mi, sec = 0 })
end

-- Money: copper <-> "12g 50s"
function ns.FormatMoney(copper)
  copper = math.floor(tonumber(copper) or 0)
  local neg = copper < 0
  copper = math.abs(copper)
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "g" end
  if s > 0 then parts[#parts + 1] = s .. "s" end
  if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
  return (neg and "-" or "") .. table.concat(parts, " ")
end

function ns.ParseMoney(text)
  text = ns.Trim(text or ""):lower()
  if text == "" then return nil end
  local plain = tonumber(text)
  if plain then return math.floor(plain * 10000 + 0.5) end
  local total, found = 0, false
  for num, unit in text:gmatch("(%d+%.?%d*)%s*([gsc])") do
    num = tonumber(num)
    if unit == "g" then total = total + num * 10000
    elseif unit == "s" then total = total + num * 100
    else total = total + num end
    found = true
  end
  if not found then return nil end
  return math.floor(total + 0.5)
end

function ns.ClassColor(classFile)
  local colors = (C_ClassColor and C_ClassColor.GetClassColor and classFile and C_ClassColor.GetClassColor(classFile))
  if colors and colors.GenerateHexColor then return colors:GenerateHexColor() end
  local c = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
  if c and c.colorStr then return c.colorStr end
  return "ffffffff"
end

function ns.ColorName(fullName)
  local info = ns.roster[fullName]
  local hex = info and ns.ClassColor(info.classFile) or "ffcccccc"
  return "|c" .. hex .. ns.ShortName(fullName) .. "|r"
end

----------------------------------------------------------------------
-- Callbacks (simple pub/sub so the UI can refresh)
----------------------------------------------------------------------
local listeners = {}
function ns.On(event, fn)
  listeners[event] = listeners[event] or {}
  table.insert(listeners[event], fn)
end
function ns.Fire(event, ...)
  local list = listeners[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok and ns.debug then ns.Print("|cffff4444error:|r " .. tostring(err)) end
  end
end

----------------------------------------------------------------------
-- Saved variables
----------------------------------------------------------------------
local SETTINGS_DEFAULTS = {
  loginGreeting = true,
  arrivalNotices = true,
  tooltips = true,
  minimapHidden = false,
  speakDwarvish = true,
  grudgeAlerts = true,
  cheersPopup = true,
  gamblePopup = true,
  doomPopup = true,
  greetBar = true,
  lfdPopup = true,
  autoInvite = true,
  inviteAnyone = false,
  inviteKeyword = "inv",
}

local function applyDefaults(t, defaults)
  for k, v in pairs(defaults) do
    if t[k] == nil then t[k] = v end
  end
end

function ns.InitDB()
  IronforgedDB = IronforgedDB or {}
  local db = IronforgedDB
  db.dbVersion = db.dbVersion or 1
  db.guilds = db.guilds or {}
  db.settings = db.settings or {}
  applyDefaults(db.settings, SETTINGS_DEFAULTS)
  ns.db = db
  ns.settings = db.settings
end

----------------------------------------------------------------------
-- Guild roster cache
----------------------------------------------------------------------
ns.roster = {}      -- fullName -> info
ns.rosterList = {}  -- array of fullNames
ns.ranks = {}       -- rankIndex -> rankName

function ns.GuildKey()
  local guildName = GetGuildInfo and GetGuildInfo("player")
  if not guildName then return nil end
  local realm = ns.RealmSuffix()
  return realm and (guildName .. "-" .. realm) or guildName
end

function ns.RefreshRoster()
  if not IsInGuild or not IsInGuild() then
    wipe(ns.roster); wipe(ns.rosterList); wipe(ns.ranks)
    return
  end
  local roster, list, ranks = {}, {}, {}
  local n = GetNumGuildMembers and GetNumGuildMembers() or 0
  for i = 1, n do
    local name, rankName, rankIndex, level, className, zone, publicNote, officerNote, online, status, classFile,
      _, _, _, _, _, guid = GetGuildRosterInfo(i)
    if name then
      local full = ns.FullName(name)
      local years, months, days, hours
      if GetGuildRosterLastOnline then years, months, days, hours = GetGuildRosterLastOnline(i) end
      roster[full] = {
        name = full, rankName = rankName, rankIndex = rankIndex, level = level,
        className = className, classFile = classFile, zone = zone,
        publicNote = publicNote, officerNote = officerNote, online = online and true or false,
        lastOnline = { years or 0, months or 0, days or 0, hours or 0 },
        guid = guid,
      }
      list[#list + 1] = full
      if rankIndex and rankName and not ranks[rankIndex] then ranks[rankIndex] = rankName end
    end
  end
  table.sort(list)
  -- Every rank the guild has, including ranks nobody holds right now.
  if GuildControlGetNumRanks and GuildControlGetRankName then
    local okN, num = pcall(GuildControlGetNumRanks)
    if okN and type(num) == "number" then
      for i = 1, num do
        local okR, rn = pcall(GuildControlGetRankName, i)
        if okR and type(rn) == "string" and rn ~= "" then ranks[i - 1] = rn end
      end
    end
  end
  local realms = {}
  for _, full in ipairs(list) do
    local r = full:find(" ", 1, true) and full:match("%-([^%s%-]+)$")
    if r then realms[r] = true end
  end
  ns.knownRealms = realms
  local byShort, byGUID = {}, {}
  for _, full in ipairs(list) do
    local key = ns.NameKey(full)
    byShort[key] = full
    local plain = (full:gsub("%-.*$", "")):lower()
    if not byShort[plain] then byShort[plain] = full end
    local first = key:match("^(%S+)%s")
    if first and not byShort[first] then byShort[first] = full end
    if roster[full].guid then byGUID[roster[full].guid] = full end
  end
  ns.roster, ns.rosterList, ns.ranks, ns.rosterByShort, ns.rosterByGUID = roster, list, ranks, byShort, byGUID
  ns.Fire("ROSTER")
end

function ns.LastSeenText(info)
  if not info then return "" end
  if info.online then return "|cff40ff40Online|r" end
  local y, m, d, h = unpack(info.lastOnline or {})
  if (y or 0) > 0 then return y .. "y ago" end
  if (m or 0) > 0 then return m .. "mo ago" end
  if (d or 0) > 0 then return d .. "d ago" end
  if (h or 0) > 0 then return h .. "h ago" end
  return "recently"
end

-- Hours since last seen, for sorting (online = -1).
function ns.SeenKey(info)
  if not info then return 1e9 end
  if info.online then return -1 end
  local y, m, d, h = unpack(info.lastOnline or {})
  return (y or 0) * 8760 + (m or 0) * 720 + (d or 0) * 24 + (h or 0)
end

function ns.RankIndexOf(name)
  local info = ns.roster[name]
  return info and info.rankIndex
end

-- Rank thresholds. Lower rank index = higher rank (0 = guild master).
-- The guild master can set each one; until then we guess from rank names.
local function rankByName(pattern)
  for i = 0, 10 do
    local n = ns.ranks[i]
    if n and n:lower():find(pattern, 1, true) then return i end
  end
  return nil
end

-- Fixed rank powers, found from the guild's rank names:
--   officers = Longbeard and above, clans founded by Veteran and above,
--   Clan Leaders give trials up to Veteran.
local RANK_RULES = {
  officerRank = function() return rankByName("longbeard") or 1 end,
  founderRank = function() return rankByName("veteran") or 4 end,
  nobleRank = function() return rankByName("noble") or 3 end,
}

function ns.RankSetting(key)
  return RANK_RULES[key]()
end

function ns.OfficerRank() return ns.RankSetting("officerRank") end

-- True if `name` holds rank index `idx` or higher.
function ns.RankAtLeast(name, idx)
  local r = ns.RankIndexOf(name)
  return r ~= nil and idx ~= nil and r <= idx
end

function ns.RankName(idx)
  return ns.ranks[idx] or ("rank " .. tostring(idx))
end

function ns.IsGuildMaster(name)
  return ns.RankIndexOf(name) == 0
end

-- Officers are the Longbeards and the guild master.
function ns.IsOfficer(name)
  return ns.IsLongbeardOrGM(name)
end

-- Is this name (with or without realm) one of our guildmates?
-- Is this name one of our guildmates? A full "First Surname" must match exactly; a bare first
-- name counts as a guildmate if any guildmate has that first name (it's ambiguous).
function ns.IsGuildmateName(name)
  if type(name) ~= "string" or name == "" then return false end
  local key = ns.NameKey(name)
  if key == "" then return false end
  local single = not key:find(" ", 1, true)
  for _, full in ipairs(ns.rosterList) do
    local rk = ns.NameKey(full)
    if rk == key then return true end
    if single and rk:match("^(%S+)") == key then return true end
  end
  return false
end

-- Only the guild master and Longbeards may delete clans and grudges.
function ns.IsLongbeardOrGM(name)
  local info = ns.roster[name]
  if not info then return false end
  if info.rankIndex == 0 then return true end
  return type(info.rankName) == "string" and info.rankName:lower():find("longbeard", 1, true) ~= nil
end

function ns.IAmOfficer()
  return ns.IsOfficer(ns.PlayerName())
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local frame = CreateFrame("Frame")
ns.eventFrame = frame
local handlers = {}

function ns.RegisterEvent(event, fn)
  handlers[event] = handlers[event] or {}
  table.insert(handlers[event], fn)
  frame:RegisterEvent(event)
end

frame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  -- each handler runs on its own, so one module's error can't stop the others
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok and ns.debug then ns.Print("|cffff4444error in " .. event .. ":|r " .. tostring(err)) end
  end
end)

local rosterPending = false
local function requestRoster()
  if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
  elseif GuildRoster then GuildRoster() end
end
ns.RequestRoster = requestRoster

ns.RegisterEvent("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  ns.InitDB()
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
  end
  requestRoster()
  if C_Timer then
    C_Timer.NewTicker(60, requestRoster)
  end
  if ns.Tooltip_Init then ns.Tooltip_Init() end
end)

ns.RegisterEvent("GUILD_ROSTER_UPDATE", function()
  if rosterPending then return end
  rosterPending = true
  local function run()
    rosterPending = false
    ns.RefreshRoster()
    if ns.Data then ns.Data.EnsureGuild() end
  end
  if C_Timer then C_Timer.After(0.5, run) else run() end
end)

ns.RegisterEvent("PLAYER_GUILD_UPDATE", function()
  requestRoster()
end)

ns.RegisterEvent("GUILD_RANKS_UPDATE", function()
  requestRoster()
end)

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------
SLASH_IRONFORGED1 = "/ironforged"
SLASH_IRONFORGED2 = "/hold"
SLASH_IRONFORGED3 = "/if"
SlashCmdList.IRONFORGED = function(msg)
  msg = ns.Trim(msg or "")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "" or cmd == "show" then
    ns.ToggleMain()
  elseif cmd == "sync" then
    ns.Comm.RequestSync()
    ns.Print("Asking the hold for the latest records...")
  elseif cmd == "cheers" then
    ns.Cheers.Call()
  elseif cmd == "dwarvish" or cmd == "lang" then
    ns.Lang.Toggle()
  elseif cmd == "pvp" then
    if ns.Challenges then ns.Challenges.PvPReport() end
  elseif cmd == "status" then
    local me = ns.PlayerName()
    local info = me and ns.roster[me]
    ns.Print("You are: " .. tostring(me) .. "  (game says " .. tostring(UnitName("player")) .. ", realm " .. tostring(ns.RealmSuffix()) .. ")")
    ns.Print("Guild: " .. tostring(GetGuildInfo("player")) .. ", " .. #ns.rosterList .. " members loaded, data " .. (ns.Data.Ready() and "ready" or "NOT ready"))
    if info then
      ns.Print("Found you on the roster: rank " .. tostring(info.rankIndex) .. " (" .. tostring(info.rankName) .. ")")
    else
      ns.Print("|cffff6060Could not find you on the roster.|r First roster name: " .. tostring(ns.rosterList[1]))
    end
    ns.Print("Officers are Longbeards and the guild master. You are " .. (ns.IAmOfficer() and "an officer." or "|cffff6060not an officer.|r"))
  elseif cmd == "debug" then
    ns.debug = not ns.debug
    ns.Print("debug " .. (ns.debug and "on" or "off"))
  else
    ns.Print("/hold  - open the hold")
    ns.Print("/hold dwarvish  - turn speaking Dwarvish on or off")
    ns.Print("/hold cheers  - officers: call the hold to raise a mug")
    ns.Print("/hold sync  - ask guildmates for the latest records")
    ns.Print("/hold pvp  - check whether the addon can flag you for PvP (for Slayer)")
  end
end

function Ironforged_OnAddonCompartmentClick()
  ns.ToggleMain()
end
