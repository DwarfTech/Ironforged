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
  if old.note == note and sameList(old.account, account) then return true end
  return Data.Put("charinfo", me, { note = note, account = account })
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
