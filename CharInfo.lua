-- Ironforged: character notes and account ranks.
--   * Note: a short line a member writes for their character, shown when guildmates hover them
--     (the name they're known by in the community, and the like).
--   * Account rank: the highest guild rank among the characters on the same account. A level 1
--     alt of a Veteran shows "(Veteran)" next to their own rank.
-- Each character writes its own record ("charinfo"): its note and the guild characters on its
-- account (the saved variables are shared by every character on an account). A rank is borrowed
-- only when both characters list each other, so nobody can claim someone else's rank.
local ADDON, ns = ...
local Data = ns.Data

local CI = {}
ns.CharInfo = CI

-- Regions: players pick theirs in the Standing tab, so dwarves in the same part of the world
-- (and the same hours) find each other. One choice covers every character on the account.
CI.REGIONS = {
  { key = "am", name = "Americas", search = { "americas", "america", "us", "usa", "na", "canada" } },
  { key = "eu", name = "Europe", search = { "europe", "eu", "uk" } },
  { key = "oce", name = "Australia / NZ", search = { "australia", "aussie", "aus", "nz", "new zealand", "oce", "oceania" } },
  { key = "asia", name = "Asia", search = { "asia" } },
}
local regionByKey = {}
for _, r in ipairs(CI.REGIONS) do regionByKey[r.key] = r end
function CI.RegionInfo(key) return key and regionByKey[key] or nil end

CI.MAX_NOTE = 60

-- The guild characters on this account, as the saved variables know them.
local function accountChars()
  ns.db.accountChars = ns.db.accountChars or {}
  return ns.db.accountChars
end

local function sortedAccount()
  local list = {}
  for name in pairs(accountChars()) do list[#list + 1] = name end
  table.sort(list)
  return list
end

local function sameList(a, b)
  if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

function CI.Get(name) return Data.Get("charinfo", name) end

function CI.Note(name)
  local r = CI.Get(name)
  return r and type(r.note) == "string" and r.note ~= "" and r.note or nil
end

-- Write my record if anything changed.
function CI.Publish(note)
  local me = ns.PlayerName()
  if not me or not Data.Ready() or not ns.roster[me] then return false end
  local old = CI.Get(me) or {}
  if note == nil then note = old.note end
  if note == "" then note = nil end
  local account = sortedAccount()
  local region = regionByKey[ns.db.region or ""] and ns.db.region or nil
  if old.note == note and sameList(old.account, account) and old.region == region then return true end
  return Data.Put("charinfo", me, { note = note, account = account, region = region })
end

-- A member's region key ("oce"), if they've picked one.
function CI.Region(name)
  local r = CI.Get(name)
  return r and regionByKey[r.region or ""] and r.region or nil
end
function CI.RegionName(name)
  local r = regionByKey[CI.Region(name) or ""]
  return r and r.name or nil
end

function CI.MyRegion() return regionByKey[ns.db.region or ""] and ns.db.region or nil end

-- Pick my region (nil to clear); every character on the account takes it.
function CI.SetRegion(key)
  if key ~= nil and not regionByKey[key] then return false end
  ns.db.region = key
  return CI.Publish()
end

-- A guess from the computer's clock, offered when nothing is picked yet.
function CI.GuessRegion()
  local ok, offset = pcall(function()
    local now = time()
    local utc = date("!*t", now)
    utc.isdst = false
    return (now - time(utc)) / 3600
  end)
  if not ok or type(offset) ~= "number" then return nil end
  if offset >= 8 and offset <= 14 then return "oce" end
  if offset >= -10 and offset <= -3 then return "am" end
  if offset >= -1 and offset <= 4 then return "eu" end
  if offset > 4 and offset < 8 then return "asia" end
  return nil
end

-- Guildmates in a region: { names }, online ones first.
function CI.InRegion(key, onlineOnly)
  local out = {}
  if not regionByKey[key or ""] then return out end
  for name, m in pairs(ns.roster) do
    if CI.Region(name) == key and (m.online or not onlineOnly) then out[#out + 1] = name end
  end
  table.sort(out, function(a, b)
    local ao, bo = ns.roster[a].online and 1 or 0, ns.roster[b].online and 1 or 0
    if ao ~= bo then return ao > bo end
    return a < b
  end)
  return out
end

-- Words that find a region in the Roster search ("aussie", "nz", "europe").
function CI.RegionMatches(name, query)
  local r = regionByKey[CI.Region(name) or ""]
  if not r or not query or query == "" then return false end
  if r.name:lower():find(query, 1, true) then return true end
  for _, w in ipairs(r.search) do if w == query or (#query >= 3 and w:find(query, 1, true) == 1) then return true end end
  return false
end

function CI.SetNote(text)
  text = ns.Clean and ns.Clean(text or "", CI.MAX_NOTE) or (text or "")
  text = ns.Trim(text)
  ns.db.lastNote = text ~= "" and text or ns.db.lastNote
  return CI.Publish(text)
end

-- A note to offer a character that has none yet: the last one written on this account.
function CI.SuggestedNote()
  return CI.Note(ns.PlayerName() or "") or ns.db.lastNote or ""
end

-- Two characters are on one account when each one's own record lists the other.
local function lists(name, other)
  local r = CI.Get(name)
  if not r or type(r.account) ~= "table" then return false end
  for _, n in ipairs(r.account) do if n == other then return true end end
  return false
end

-- The higher rank borrowed from another character on the same account: rankName, that character.
-- nil when the character's own rank is already the highest.
function CI.BestRank(name)
  local own = ns.roster[name]
  if not own or type(own.rankIndex) ~= "number" then return nil end
  local r = CI.Get(name)
  if not r or type(r.account) ~= "table" then return nil end
  local bestIdx, bestName, bestChar = own.rankIndex, nil, nil
  for _, other in ipairs(r.account) do
    local m = ns.roster[other]
    if other ~= name and m and type(m.rankIndex) == "number" and m.rankIndex < bestIdx and lists(other, name) then
      bestIdx, bestName, bestChar = m.rankIndex, m.rankName, other
    end
  end
  return bestName, bestChar
end

-- "Ironguard (Veteran)", or just the rank.
function CI.RankText(name, plainRank)
  local rank = plainRank or (ns.roster[name] and ns.roster[name].rankName) or ""
  local best = CI.BestRank(name)
  if best then return rank .. " |cff999999(" .. best .. ")|r" end
  return rank
end

-- Keep the account list current: this character, and any listed one that left the guild.
local function refreshAccount()
  local me = ns.PlayerName()
  if not me or not ns.roster[me] then return end
  local chars = accountChars()
  chars[me] = true
  if #(ns.rosterList or {}) > 0 then
    for name in pairs(chars) do if not ns.roster[name] then chars[name] = nil end end
  end
  CI.Publish()
end
CI.Refresh = refreshAccount

ns.On("DATA_READY", function() if C_Timer then C_Timer.After(5, refreshAccount) else refreshAccount() end end)
ns.On("ROSTER", function()
  local me = ns.PlayerName()
  if me and ns.roster[me] and not accountChars()[me] then refreshAccount() end
end)
