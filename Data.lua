-- Ironforged: synced record store.
-- Every piece of shared data is a record in a collection:
--   record = { d = <data table>, t = <revision stamp>, b = <author full name>, x = <true if deleted> }
-- Newer stamps win; ties break on author name so every client converges to the same result.
-- Permission checks may look at collections listed EARLIER in COLLECTIONS (sync sends them in order).
local ADDON, ns = ...

local Data = {}
ns.Data = Data

Data.COLLECTIONS = {
  "config",       -- guild-wide settings (rank thresholds, hold name, oath, laws)
  "members",      -- officer-kept member records (title, main/alt, joined, notes)
  "titles",       -- key = member .. "#" .. KeyOf(title); titles awarded by officers
  "clans",        -- key = KeyOf(clan name); the record names its founder
  "invites",      -- key = clan key .. "#" .. member; written by the clan leader
  "applications", -- key = clan key .. "#" .. member; a member asking to join a clan
  "clanship",     -- key = member; the member's own choice of clan (needs an invite to count)
  "progress",     -- key = member; the promotion trial given to a character (title, rank, tasks, done)
  "taskmarks",    -- key = member (same as progress); tasks the member themself marks done
  "requests",     -- key = member; promotion requests
  "events",       -- key = EventKey(title, date); guild events
  "rsvp",         -- key = event key .. "#" .. member
  "attendance",   -- key = event key
  "profiles",     -- key = member; the member's backstory
  "selfreport",   -- key = member; race, written by the member's own client
  "racecheck",    -- key = member; race found by an officer's guild scan
  "grudges",      -- key = KeyOf(the foe's name); the Book of Grudges
  "avenged",      -- key = grudge key; who avenged it and how
  "pvp",          -- key = member; Horde slain and elves slain, written by the member's own client
  "gambles",      -- key = host .. "#" .. game id; finished Cross Gambling games, written by the host
  "invitelog",    -- key = inviter .. "#" .. invitee; guild invites, logged by the inviter's own client
  "crafts",       -- key = member .. "#" .. profession; skill and known recipes, written by the member's own client
  "lfd",          -- key = leader .. "#" .. id; Looking for Dwarf group posts
  "lfdjoin",      -- key = post key .. "#" .. member; who signed up for a post
  "challenges",   -- key = member .. "#" .. id; challenges a member took on, written by their own client
}
-- Collections that are NOT part of login digests or guild-wide broadcasts. Each member's own
-- client writes them and pushes them (by whisper) to the online Longbeards, who hand them out
-- on request. Crafts are too big to flood the guild channel with.
Data.LOCAL_ONLY = { crafts = true }
-- Collections every guild member keeps in sync, always: Clans, Promotions and Events. Edits go
-- straight to the guild channel, and a member logging in sends row hashes (op "H") so any online
-- member can send back exactly the rows they lack. They are left out of the login digests.
Data.ALWAYS_SYNC = {
  clans = true, invites = true, applications = true, clanship = true,     -- Clans
  progress = true, taskmarks = true, requests = true,                     -- Promotions
  events = true, rsvp = true, attendance = true,                          -- Events
  grudges = true, avenged = true,                                         -- Book of Grudges
  pvp = true,                                                             -- War Hall
  titles = true,                                                          -- Titles
}

local VALID = {}
for _, c in ipairs(Data.COLLECTIONS) do VALID[c] = true end
Data.VALID = VALID

local MAX_TOMBSTONE_AGE = 60 * 60 * 24 * 120 -- forget deletions after ~4 months

local store -- the current guild's table in saved variables

function Data.EnsureGuild()
  if not ns.db then return false end
  local key = ns.GuildKey()
  if not key then store = nil; return false end
  local g = ns.db.guilds[key]
  if not g then
    g = { colls = {} }
    ns.db.guilds[key] = g
  end
  for _, c in ipairs(Data.COLLECTIONS) do g.colls[c] = g.colls[c] or {} end
  local changed = store ~= g
  store = g
  if changed then
    Data.PruneTombstones()
    ns.Fire("DATA_READY")
  end
  return true
end

function Data.Ready() return store ~= nil end

function Data.Raw(coll)
  return store and store.colls[coll]
end

function Data.Get(coll, key)
  local c = store and store.colls[coll]
  local rec = c and key and c[key]
  if rec and not rec.x then return rec.d, rec end
  return nil, rec
end

-- Iterate live (non-deleted) records: for key, data, rec in Data.Each("clans") do
function Data.Each(coll)
  local c = store and store.colls[coll] or {}
  local k
  return function()
    while true do
      local rec
      k, rec = next(c, k)
      if k == nil then return nil end
      if not rec.x then return k, rec.d, rec end
    end
  end
end

function Data.List(coll, sortFn)
  local out = {}
  for k, d in Data.Each(coll) do out[#out + 1] = { key = k, data = d } end
  if sortFn then table.sort(out, sortFn) end
  return out
end

local function splitKey(key)
  if type(key) ~= "string" then return nil end
  return key:match("^(.+)#([^#]+)$")
end
Data.SplitKey = splitKey

----------------------------------------------------------------------
-- Clans
----------------------------------------------------------------------
-- Natural keys: the same thing named by two people gets the same key, so rows merge instead of doubling.
function Data.KeyOf(text)
  text = tostring(text or ""):lower():gsub("[%c#@|]", ""):gsub("%s+", " ")
  return (text:gsub("^ ", ""):gsub(" $", ""))
end

-- One event per name per day (UTC, so everyone computes the same key).
function Data.EventKey(title, ts)
  return Data.KeyOf(title) .. "@" .. date("!%Y%m%d", tonumber(ts) or 0)
end

function Data.ClanFounder(clanId)
  local c = clanId and Data.Get("clans", clanId)
  return c and c.founder or nil
end

function Data.Clan(id)
  local c = id and Data.Get("clans", id)
  if c and c.status ~= "disbanded" then return c end
  return nil
end

function Data.ClanRecognized(id)
  return Data.Clan(id) ~= nil
end

function Data.ClanName(id)
  local c = Data.Clan(id)
  return c and c.name or nil
end

function Data.IsClanLeader(name, clanId)
  local c = Data.Clan(clanId)
  return c ~= nil and c.leader == name
end

-- The clan a member actually belongs to: the one they lead, or the one they joined with a standing invite.
function Data.ClanOf(name)
  if not name then return nil end
  local led
  for id, c in Data.Each("clans") do
    if c.leader == name and c.status ~= "disbanded" then
      if not led or id < led then led = id end
    end
  end
  if led then return led end
  -- Membership needs the leader's invite plus the member's consent: either they accepted
  -- (clanship) or they applied and the leader accepted the application.
  local cs = Data.Get("clanship", name)
  local id = cs and cs.clan
  if id and Data.ClanRecognized(id) and Data.Get("invites", id .. "#" .. name) then return id end
  local found
  for key in Data.Each("applications") do
    local clanId, member = splitKey(key)
    if member == name and Data.ClanRecognized(clanId) and Data.Get("invites", key) then
      if not found or clanId < found then found = clanId end
    end
  end
  return found
end

function Data.ClanMembers(id)
  local out = {}
  for _, name in ipairs(ns.rosterList) do
    if Data.ClanOf(name) == id then out[#out + 1] = name end
  end
  -- leaders or members who left the roster still count until removed
  for name in Data.Each("clanship") do
    if not ns.roster[name] and Data.ClanOf(name) == id then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

-- Open applications to a clan (or to all clans when clanId is nil): { {key=, clan=, member=, data=} }
function Data.Applications(clanId)
  local out = {}
  for key, a in Data.Each("applications") do
    local c, member = splitKey(key)
    if c and Data.Clan(c) and (not clanId or c == clanId) and not Data.Get("invites", key) then
      out[#out + 1] = { key = key, clan = c, member = member, data = a }
    end
  end
  table.sort(out, function(x, y) return (x.data.ts or 0) < (y.data.ts or 0) end)
  return out
end

-- Clans whose applications `name` may answer.
function Data.ClansLedBy(name)
  local out = {}
  for id, c in Data.Each("clans") do
    if c.leader == name then out[#out + 1] = id end
  end
  return out
end

function Data.PendingInvites(name)
  local out = {}
  for key in Data.Each("invites") do
    local clanId, member = splitKey(key)
    if member == name and Data.ClanRecognized(clanId) and Data.ClanOf(name) ~= clanId
      and not Data.Get("applications", key) then
      out[#out + 1] = clanId
    end
  end
  table.sort(out)
  return out
end

----------------------------------------------------------------------
-- Promotion trials
----------------------------------------------------------------------
-- Longbeards and the guild master may give any trial. Nobles and above may give trials
-- for ranks below Noble. Nobody gives a trial to themselves, except the guild master.
function Data.CanGiveTrial(author, member, rank)
  if not author or not ns.roster[author] then return false end
  if member == author and not ns.IsGuildMaster(author) then return false end
  if ns.IsLongbeardOrGM(author) then return true end
  local noble = ns.RankSetting("nobleRank")
  if not ns.RankAtLeast(author, noble) then return false end
  return type(rank) == "number" and rank > noble
end

function Data.CanGiveTrials(author)
  return ns.IsLongbeardOrGM(author) or ns.RankAtLeast(author, ns.RankSetting("nobleRank"))
end

----------------------------------------------------------------------
-- Permissions: who may author a record
----------------------------------------------------------------------
function Data.CanWrite(author, coll, key, data)
  if not author or not VALID[coll] or type(key) ~= "string" then return false end
  local officer = ns.IsOfficer(author)

  if coll == "config" then
    if key == "core" then return ns.IsGuildMaster(author) end
    return officer
  elseif coll == "clans" then
    if data == nil then return ns.IsLongbeardOrGM(author) end -- only Longbeards and the guild master delete clans
    local founder = data.founder
    if type(founder) ~= "string" or data.leader ~= founder then return false end -- the founder always leads
    if type(data.name) ~= "string" or key ~= Data.KeyOf(data.name) then return false end
    if officer then return true end
    if founder ~= author or ns.roster[author] == nil then return false end -- any guildmate may found a clan
    local old = Data.Get("clans", key)
    return old == nil or old.founder == author -- but nobody takes over a clan that already has a founder
  elseif coll == "grudges" then
    if data == nil then return ns.IsLongbeardOrGM(author) end -- only Longbeards and the guild master delete grudges
    if ns.roster[author] == nil then return false end
    if type(data.against) ~= "string" or key ~= Data.KeyOf(data.against) then return false end
    return not ns.IsGuildmateName(data.against) -- guildmates can't be grudged
  elseif coll == "avenged" then
    if data == nil then return officer end
    if officer then return true end
    -- anyone in the guild avenges a Horde grudge by slaying the foe
    local g = Data.Get("grudges", key)
    return ns.roster[author] ~= nil and g ~= nil and g.faction == "Horde" and data.how == "slain"
  elseif coll == "pvp" then
    return author == key
  elseif coll == "gambles" then
    if data == nil then return officer end
    return splitKey(key) == author and ns.roster[author] ~= nil
  elseif coll == "invites" then
    local clanId, member = splitKey(key)
    if not clanId then return false end
    if officer or Data.IsClanLeader(author, clanId) then return true end
    return data == nil and author == member -- the invited member may decline
  elseif coll == "applications" then
    local clanId, member = splitKey(key)
    if not clanId then return false end
    if data ~= nil then return author == member and ns.roster[author] ~= nil end
    return author == member or officer or Data.IsClanLeader(author, clanId)
  elseif coll == "crafts" then
    local member = splitKey(key)
    if data == nil then return member == author or officer end
    return member == author and ns.roster[author] ~= nil
  elseif coll == "challenges" then
    local member = splitKey(key)
    if data == nil then return member == author or officer end
    return member == author and ns.roster[author] ~= nil
  elseif coll == "lfd" then
    local leader = splitKey(key)
    if data == nil then return leader == author or officer end
    return leader == author and ns.roster[author] ~= nil
  elseif coll == "lfdjoin" then
    local post, member = splitKey(key)
    if not post then return false end
    if data ~= nil then return member == author and ns.roster[author] ~= nil end
    return member == author or splitKey(post) == author or officer
  elseif coll == "invitelog" then
    local inviter = splitKey(key)
    if data ~= nil then return inviter == author end
    return inviter == author or ns.IsLongbeardOrGM(author)
  elseif coll == "clanship" or coll == "profiles" or coll == "requests" then
    if author == key or officer then return true end
    if coll == "requests" and data == nil then return Data.CanGiveTrials(author) end
    return false
  elseif coll == "selfreport" then
    return author == key
  elseif coll == "racecheck" then
    return officer
  elseif coll == "progress" then
    local member = key
    local rank = data and data.rank
    if data == nil then
      local old = Data.Get("progress", key)
      rank = old and old.rank
    end
    return Data.CanGiveTrial(author, member, rank)
  elseif coll == "taskmarks" then
    local member = key
    if data == nil and Data.CanGiveTrials(author) then return true end -- cleared with the trial
    return member == author
  elseif coll == "rsvp" then
    local _, member = splitKey(key)
    return author == member or officer
  end
  if coll == "events" and data ~= nil and (type(data.title) ~= "string" or key ~= Data.EventKey(data.title, data.ts)) then
    return false
  end
  return officer -- members, events, attendance
end

function Data.ICanWrite(coll, key, data)
  return Data.CanWrite(ns.PlayerName(), coll, key, data)
end

----------------------------------------------------------------------
-- Merge
----------------------------------------------------------------------
-- Who a row is about (the member whose standing it describes), or nil when it is about no one.
function Data.Subject(coll, key, data)
  if coll == "clanship" or coll == "requests" or coll == "pvp" or coll == "profiles" or coll == "selfreport"
    or coll == "racecheck" or coll == "members" or coll == "progress" or coll == "taskmarks" then
    return key
  elseif coll == "titles" or coll == "crafts" or coll == "challenges" or coll == "invitelog"
    or coll == "gambles" or coll == "lfd" then
    return (splitKey(key))
  elseif coll == "invites" or coll == "applications" or coll == "rsvp" or coll == "lfdjoin" then
    return select(2, splitKey(key))
  elseif coll == "clans" then
    return data and data.founder or nil
  end
  return nil
end

-- A row whose author or subject has left the guild. Only judged once a full-looking roster is loaded.
function Data.RosterTrusted()
  local n = ns.rosterList and #ns.rosterList or 0
  if n == 0 then return false end
  local db = ns.db
  if db then
    db.rosterMax = math.max(db.rosterMax or 0, n)
    if n < db.rosterMax * 0.8 then return false end -- a partial roster must never wipe the data
  end
  return true
end

function Data.Departed(coll, key, rec)
  if not Data.RosterTrusted() then return false end
  if coll ~= "config" and rec.b and not ns.roster[rec.b] then return true end
  local who = Data.Subject(coll, key, rec.d)
  return who ~= nil and not ns.roster[who]
end

-- Forget rows written by, or about, people who are no longer in the guild.
function Data.PruneDeparted()
  if not store or not Data.RosterTrusted() then return 0 end
  local removed = 0
  for coll, c in pairs(store.colls) do
    for key, rec in pairs(c) do
      if Data.Departed(coll, key, rec) then c[key] = nil; removed = removed + 1 end
    end
  end
  if removed > 0 then ns.Fire("DATA_CHANGED") end
  return removed
end

-- A client that has been away longer than tombstones are kept can't tell a deleted row from a live
-- one, so it forgets its always-synced rows and fetches them again from the guild.
function Data.DropAlwaysSyncRows()
  if not store then return end
  for coll in pairs(Data.ALWAYS_SYNC) do store.colls[coll] = {} end
  ns.Fire("DATA_CHANGED")
end

Data.MAX_TOMBSTONE_AGE = MAX_TOMBSTONE_AGE

local function newer(a, b)
  if not b then return true end
  if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) > (b.t or 0) end
  return tostring(a.b or "") > tostring(b.b or "")
end

local function validRecord(rec)
  if type(rec) ~= "table" then return false end
  if type(rec.t) ~= "number" or type(rec.b) ~= "string" then return false end
  if rec.x then return true end
  return type(rec.d) == "table"
end

-- Merge one incoming record. Returns true if local data changed.
-- `relayed` is true when an officer passes the record along during sync. Officers only keep
-- records that passed these checks when they were written, and some rights (a Clan Leader's)
-- can end later, so history relayed by an officer is accepted as-is.
function Data.Merge(coll, key, rec, relayed)
  if not store or not VALID[coll] or type(key) ~= "string" or #key > 120 then return false end
  if not validRecord(rec) then return false end
  -- no stamps from the future (a minute of slack for clock jitter), and no tombstones old enough to be pruned
  if rec.t > (ns.Now() + 60) * 1000 then return false, "future" end
  if rec.x and rec.t < (ns.Now() - MAX_TOMBSTONE_AGE) * 1000 then return false, "old" end
  if Data.Departed(coll, key, rec) then return false, "departed" end
  if not relayed and not Data.CanWrite(rec.b, coll, key, (not rec.x) and rec.d or nil) then return false, "perm" end
  local c = store.colls[coll]
  if not newer(rec, c[key]) then return false end
  if rec.x then
    c[key] = { t = rec.t, b = rec.b, x = true }
  else
    c[key] = { d = rec.d, t = rec.t, b = rec.b }
  end
  return true
end

----------------------------------------------------------------------
-- Local writes (broadcast through Comm)
----------------------------------------------------------------------
function Data.Put(coll, key, data, quiet)
  if not store then ns.Print("Guild data isn't loaded yet."); return false end
  local me = ns.PlayerName()
  if not Data.CanWrite(me, coll, key, data) then
    if not quiet then ns.Print("You don't have the standing to change that.") end
    return false
  end
  local rec = { d = data, t = ns.Stamp(), b = me }
  store.colls[coll][key] = rec
  ns.Fire("DATA_CHANGED", coll, key)
  if ns.Comm then ns.Comm.BroadcastRecord(coll, key, rec) end
  return true
end

function Data.Delete(coll, key)
  if not store then return false end
  local me = ns.PlayerName()
  if not Data.CanWrite(me, coll, key, nil) then
    ns.Print("You don't have the standing to change that.")
    return false
  end
  local rec = { t = ns.Stamp(), b = me, x = true }
  store.colls[coll][key] = rec
  ns.Fire("DATA_CHANGED", coll, key)
  if ns.Comm then ns.Comm.BroadcastRecord(coll, key, rec) end
  return true
end

function Data.PruneTombstones()
  if not store then return end
  local cutoff = (ns.Now() - MAX_TOMBSTONE_AGE) * 1000
  for _, c in pairs(store.colls) do
    for k, rec in pairs(c) do
      if rec.x and (rec.t or 0) < cutoff then c[k] = nil end
    end
  end
end

-- Order-independent fingerprint of a collection, used to spot differences cheaply.
function Data.Digest(coll, since)
  local c = store and store.colls[coll]
  if not c then return "0:0" end
  local count, sum = 0, 0
  for k, rec in pairs(c) do
   if not since or (rec.t or 0) >= since then
    count = count + 1
    sum = (sum + ns.Hash(k .. "@" .. string.format("%.0f", rec.t or 0) .. (rec.b or ""))) % 2147483647
   end
  end
  return count .. ":" .. sum
end

-- Digests of the always-synced collections (rows newer than `since` ms when given).
function Data.AlwaysDigests(since)
  local out = {}
  for _, c in ipairs(Data.COLLECTIONS) do
    if Data.ALWAYS_SYNC[c] then out[c] = Data.Digest(c, since) end
  end
  return out
end

function Data.Digests()
  local out = {}
  for _, c in ipairs(Data.COLLECTIONS) do
    if not Data.LOCAL_ONLY[c] and not Data.ALWAYS_SYNC[c] then out[c] = Data.Digest(c) end
  end
  return out
end

-- A row is identified by its natural key and versioned by its stamp. The token is the key's
-- hash (8 hex digits) followed by the stamp of the version I hold (11 hex digits).
function Data.KeyHash(coll, key)
  return string.format("%08x", ns.Hash(coll .. "|" .. key))
end

local function stampHex(t)
  t = math.floor(tonumber(t) or 0)
  local hi = math.floor(t / 16777216) -- 32-bit string.format would overflow on millisecond stamps
  return string.format("%05x%06x", hi, t - hi * 16777216)
end

function Data.RowToken(coll, key, rec)
  return Data.KeyHash(coll, key) .. stampHex(rec.t)
end

-- "tokens" string -> { [key hash] = stamp }
function Data.ParseTokens(s)
  local out = {}
  if type(s) ~= "string" then return out end
  for kh, hi, lo in s:gmatch("(%x%x%x%x%x%x%x%x)(%x%x%x%x%x)(%x%x%x%x%x%x)") do
    out[kh] = tonumber(hi, 16) * 16777216 + tonumber(lo, 16)
  end
  return out
end

-- Rows of one collection (newer than `since` ms when given): fn(coll, key, rec, hash).
function Data.EachRow(coll, since, fn)
  local raw = Data.Raw(coll)
  if not raw then return end
  for key, rec in pairs(raw) do
    if not since or (rec.t or 0) >= since then fn(coll, key, rec, Data.RowToken(coll, key, rec)) end
  end
end

-- Every always-synced row: fn(coll, key, rec, hash).
function Data.EachAlwaysRow(since, fn, only)
  for _, c in ipairs(Data.COLLECTIONS) do
    if Data.ALWAYS_SYNC[c] and (not only or only[c]) then Data.EachRow(c, since, fn) end
  end
end

-- Crafts rows, optionally of one profession only: fn(coll, key, rec, hash).
function Data.EachCraft(since, prof, fn)
  Data.EachRow("crafts", since, function(c, key, rec, h)
    if not prof or select(2, Data.SplitKey(key)) == prof then fn(c, key, rec, h) end
  end)
end

function Data.CraftTokens(since, prof)
  local out = {}
  Data.EachCraft(since, prof, function(_, _, _, h) out[#out + 1] = h end)
  return table.concat(out)
end

-- Concatenated row tokens of everything I hold in the always-synced collections.
function Data.RowTokens(since, only)
  local out = {}
  Data.EachAlwaysRow(since, function(_, _, _, h) out[#out + 1] = h end, only)
  return table.concat(out)
end

function Data.Count(coll)
  local n = 0
  for _ in Data.Each(coll) do n = n + 1 end
  return n
end

----------------------------------------------------------------------
-- Domain helpers
----------------------------------------------------------------------
function Data.Config()
  local core = Data.Get("config", "core") or {}
  local guild = Data.Get("config", "guild") or {}
  return core, guild
end

function Data.GuildDisplayName()
  local _, guild = Data.Config()
  if guild.displayName and guild.displayName ~= "" then return guild.displayName end
  return (GetGuildInfo and GetGuildInfo("player")) or "The Hold"
end

function Data.Member(name)
  return Data.Get("members", name) or {}
end

function Data.Profile(name)
  return Data.Get("profiles", name)
end

function Data.SelfReport(name)
  return Data.Get("selfreport", name)
end

-- Progress on one trial: done count, total, trial data
-- A task counts as done when the trial giver ticked it, or the member marked it and the giver
-- hasn't unticked it.
function Data.TaskState(key, taskId)
  local t = key and Data.Get("progress", key)
  if not t then return false end
  if t.done and t.done[taskId] then return true, "giver" end
  local m = Data.Get("taskmarks", key)
  if m and m.done and m.done[taskId] and not (t.undone and t.undone[taskId]) then return true, "member" end
  return false
end

-- Progress on one trial: done count, total, trial data
function Data.TrialProgress(key)
  local t = key and Data.Get("progress", key)
  if not t then return 0, 0 end
  local done = 0
  for _, task in ipairs(t.tasks or {}) do
    if Data.TaskState(key, task.id) then done = done + 1 end
  end
  return done, #(t.tasks or {}), t
end

-- All trials, or one member's: { {key=, member=, title=, rank=, done=, total=} }
function Data.AssignedTrials(member)
  local out = {}
  for key, t in Data.Each("progress") do
    local m = key
    if not member or m == member then
      local done, total = Data.TrialProgress(key)
      out[#out + 1] = { key = key, member = m, title = t.title or "Promotion trial", rank = t.rank, done = done, total = total, completed = t.completed }
    end
  end
  return out
end

function Data.RSVPs(eventId)
  local out = { yes = {}, maybe = {}, no = {} }
  for key, r in Data.Each("rsvp") do
    local ev, member = key:match("^([^#]+)#(.+)$")
    if ev == eventId and out[r.status] then table.insert(out[r.status], member) end
  end
  for _, list in pairs(out) do table.sort(list) end
  return out
end

function Data.Avenged(grudgeKey)
  return Data.Get("avenged", grudgeKey)
end

-- Normalized name for matching foes: lowercase, no realm, no color codes.
function Data.FoeKey(name)
  return ns.NameKey(name)
end

-- Open (not yet avenged) grudges against a name: { {key=, data=} }
function Data.GrudgesAgainst(name, includeAvenged)
  local want = Data.FoeKey(name)
  local first = want:match("^(%S+)")
  local out = {}
  if want == "" then return out end
  for key, g in Data.Each("grudges") do
    local against = Data.FoeKey(g.against)
    local hit = against == want or (not against:find(" ") and against == first)
    if hit and (includeAvenged or not Data.Avenged(key)) then out[#out + 1] = { key = key, data = g } end
  end
  table.sort(out, function(a, b) return (a.data.ts or 0) < (b.data.ts or 0) end)
  return out
end

function Data.AttendanceCount(member)
  local attended, total = 0, 0
  for _, a in Data.Each("attendance") do
    total = total + 1
    if a.present and a.present[member] then attended = attended + 1 end
  end
  return attended, total
end

-- People who left the guild: forget their rows once the roster settles.
local prunePending = false
ns.On("ROSTER", function()
  if prunePending or not C_Timer then return end
  prunePending = true
  C_Timer.After(30, function()
    prunePending = false
    Data.PruneDeparted()
  end)
end)
