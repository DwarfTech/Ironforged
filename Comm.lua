-- Ironforged: guild sync over hidden addon messages.
-- To keep the one guild channel quiet, traffic flows through "relays": the online Longbeards
-- and guild master.
--   * A member whispers their own edits to one relay, who merges them and posts them to GUILD.
--   * At login a member whispers their digest to two relays, who whisper back what differs.
--     Only the changes since the last sync are sent (see `sn` in the digest).
--   * Crafts are never broadcast. Members push theirs to relays; clients pull them on demand.
--   * If no relay is online, everything falls back to guild-wide sync as before.
-- Messages are chunked and rate limited.
local ADDON, ns = ...

local Comm = {}
ns.Comm = Comm

local Ser = ns.Ser
local CHUNK = 220
local BATCH_RECORDS = 20
local PEER_TTL = 30 * 60
local RELAY_TTL = 4 * 60 * 60 -- how long a heard-from Longbeard counts as a relay
local MAX_PARTS = 600

local queue = {}
local tokens, TOKEN_CAP, TOKEN_RATE = 6, 6, 1.4 -- messages per second
local backoffUntil = 0
local msgCounter = 0
local buffers = {}

Comm.peers = {}        -- fullName -> { seen = GetTime(), version = "1.0.0" }
Comm.stats = { sent = 0, received = 0, lastSync = nil }

local function now() return GetTime and GetTime() or 0 end

local function paused()
  if InCombatLockdown and InCombatLockdown() then return true end
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
    local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
    if ok and locked then return true end
  end
  return false
end

local function targetOnline(target)
  local info = ns.roster[target]
  return info and info.online
end

local function rawSend(item)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return "drop" end
  if item.channel == "WHISPER" and not targetOnline(item.target) then return "drop" end
  local target = item.target -- already "First Surname", never with a realm
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, ns.PREFIX, item.text, item.channel, target)
  if not ok then return "drop" end
  if result == nil or result == true then return "ok" end
  if result == false then return "drop" end
  local R = Enum and Enum.SendAddonMessageResult
  if R then
    if result == R.Success then return "ok" end
    if result == R.AddonMessageThrottle or result == R.ChannelThrottle then return "retry" end
  elseif result == 0 then
    return "ok"
  end
  return "drop"
end

local function pump(elapsed)
  tokens = math.min(TOKEN_CAP, tokens + elapsed * TOKEN_RATE)
  if #queue == 0 or paused() or now() < backoffUntil then return end
  while #queue > 0 and tokens >= 1 do
    local item = queue[1]
    local res = rawSend(item)
    if res == "retry" then
      backoffUntil = now() + 2
      return
    end
    table.remove(queue, 1)
    if res == "ok" then
      tokens = tokens - 1
      Comm.stats.sent = Comm.stats.sent + 1
    end
  end
end

local pumpFrame = CreateFrame("Frame")
pumpFrame:SetScript("OnUpdate", function(_, elapsed) pump(elapsed) end)

-- Send a table to GUILD or WHISPER(target).
function Comm.Send(payload, channel, target)
  if not IsInGuild or not IsInGuild() then return end
  payload.p = ns.PROTOCOL
  local ok, packed = pcall(Ser.Pack, payload)
  if not ok then return end
  msgCounter = (msgCounter + 1) % 46656
  local id = string.format("%x", msgCounter)
  local n = math.max(1, math.ceil(#packed / CHUNK))
  for i = 1, n do
    local part = packed:sub((i - 1) * CHUNK + 1, i * CHUNK)
    queue[#queue + 1] = { text = id .. "\t" .. i .. "\t" .. n .. "\t" .. part, channel = channel, target = target }
  end
end

function Comm.QueueLength() return #queue end

----------------------------------------------------------------------
-- Relays: online Longbeards and the guild master (other than me)
----------------------------------------------------------------------
-- Online Longbeards/GM other than me. `known` keeps only those we have heard from recently,
-- i.e. who actually run the addon; a Longbeard without it would swallow whispered edits.
local function relayList(known)
  local me = ns.PlayerName()
  local t = now()
  local list = {}
  for _, name in ipairs(ns.rosterList) do
    local info = ns.roster[name]
    if info and info.online and name ~= me and ns.IsOfficer(name) then
      local peer = Comm.peers[name]
      if not known or (peer and t - peer.seen < RELAY_TTL) then list[#list + 1] = name end
    end
  end
  return list
end

-- Up to n relays, chosen the same way every time from my own name, so each member sticks to
-- the same few relays and the load spreads evenly across all of them.
-- With known=false (login, before anyone has been heard from) every online officer is a candidate.
local function pickRelays(n, known)
  local list = relayList(known)
  local out = {}
  if #list == 0 then return out end
  local start = ns.Hash(ns.PlayerName() or "") % #list
  for i = 0, math.min(n, #list) - 1 do out[#out + 1] = list[(start + i) % #list + 1] end
  return out
end
Comm.PickRelays = pickRelays

----------------------------------------------------------------------
-- Outgoing helpers
----------------------------------------------------------------------
function Comm.BroadcastRecord(coll, key, rec)
  if ns.Data.LOCAL_ONLY[coll] or ns.Data.FROZEN[coll] then return end -- crafts are pulled by hash; frozen never travel
  if ns.Data.ALWAYS_SYNC[coll] then
    Comm.Send({ op = "P", c = coll, k = key, r = rec }, "GUILD") -- everyone, immediately
    return
  end
  if ns.IAmOfficer() then
    Comm.Send({ op = "P", c = coll, k = key, r = rec }, "GUILD")
    return
  end
  local relays = pickRelays(1, true)
  if #relays == 0 then
    -- no Longbeard online: guild-wide as before
    Comm.Send({ op = "P", c = coll, k = key, r = rec }, "GUILD")
    return
  end
  Comm.Send({ op = "P", c = coll, k = key, r = rec }, "WHISPER", relays[1])
end

-- Tell the guild you've spotted a grudged foe (not stored).
function Comm.BroadcastSighting(foe, zone)
  Comm.Send({ op = "S", n = foe, z = zone }, "GUILD")
end

-- `since` (ms stamp) asks the responder for records newer than that only.
function Comm.SendDigest(channel, target, isReply, since)
  if not ns.Data.Ready() then return end
  Comm.Send({ op = "D", v = ns.VERSION, dg = ns.Data.Digests(), r = isReply or nil, sn = since }, channel, target)
end

local DAY_MS = 86400 * 1000
local SYNC_MARGIN_MS = 10 * 60 * 1000

-- When I last synced successfully; nil means ask for everything (first run, or a weekly full sync).
local function sinceStamp()
  local db = ns.db
  if not db or not db.syncedAt or not db.fullSyncAt then return nil end
  if ns.Now() * 1000 - db.fullSyncAt > 7 * DAY_MS then return nil end
  return db.syncedAt - SYNC_MARGIN_MS
end

local sendRecords

-- Always-synced rows (Clans, Promotions, Events, Grudges, War Hall, Titles), in three cheap steps:
--   1. I broadcast one short digest per collection (op H).
--   2. Up to two online members whose digests differ whisper back which collections differ (op HN);
--      an empty list means "you are in sync".
--   3. I whisper those members a token (key hash + stamp) for each row I hold in those collections
--      (op HT) and they send back rows I lack or hold in an older version.
Comm.rowsGot = 0
local rowSession

local function markRowsSynced(s)
  if s.synced or not ns.db then return end
  s.synced = true
  ns.db.rowSyncedAt = s.startMs
  if s.full then ns.db.rowFullSyncAt = s.startMs end
end

function Comm.RequestRows(attempt, since, startMs, full)
  if not ns.Data.Ready() then return end
  attempt = attempt or 1
  local s = rowSession
  if attempt == 1 or not s then
    s = { since = since, startMs = startMs, full = full, chosen = {}, count = 0 }
    rowSession = s
  end
  s.attempt = attempt
  Comm.Send({ op = "H", a = attempt, sn = since, dg = ns.Data.AlwaysDigests(since), v = ns.VERSION }, "GUILD")
  if C_Timer then
    C_Timer.After(attempt == 1 and 20 or 40, function()
      if rowSession ~= s or s.answered then return end
      if attempt < 3 then Comm.RequestRows(attempt + 1, since, startMs, full) end
    end)
  end
end

local function rowSince()
  local db = ns.db
  if not db or not db.rowSyncedAt or not db.rowFullSyncAt then return nil end
  if ns.Now() * 1000 - db.rowFullSyncAt > 7 * DAY_MS then return nil end
  return db.rowSyncedAt - SYNC_MARGIN_MS
end

-- Also runs every so often, so a message that got lost doesn't leave me out of step until my next login.
function Comm.CheckRows()
  local db = ns.db
  if db and db.rowFullSyncAt and ns.Now() - db.rowFullSyncAt / 1000 > ns.Data.MAX_TOMBSTONE_AGE then
    -- away so long that deletions may have been forgotten: start over from the guild's copy
    ns.Data.DropAlwaysSyncRows()
    db.rowSyncedAt, db.rowFullSyncAt = nil, nil
  end
  local rs = rowSince()
  Comm.RequestRows(1, rs, ns.Now() * 1000, rs == nil)
end

function Comm.RequestSync()
  Comm.stats.lastSync = ns.Now()
  Comm.syncStartMs = ns.Now() * 1000
  Comm.gotReply = false
  Comm.CheckRows()
  local since = sinceStamp()
  Comm.syncWasFull = since == nil
  local relays = ns.IAmOfficer() and {} or pickRelays(2, false)
  if #relays == 0 then
    Comm.SendDigest("GUILD", nil, nil, since)
    return
  end
  for _, relay in ipairs(relays) do Comm.SendDigest("WHISPER", relay, nil, since) end
  -- if neither relay answers (no addon, or they logged off) fall back to the guild channel
  if C_Timer then
    C_Timer.After(25, function()
      if not Comm.gotReply then Comm.SendDigest("GUILD", nil, nil, since) end
    end)
  end
end

-- Ask the guild for crafts: one profession, or all (nil). I send the hashes of the crafts rows I
-- already hold; whoever is online (the crafter first of all) sends back the rows I lack.
-- Limited to once per 5 minutes per profession, and only what changed since my last pull.
local lastPull = {}
function Comm.PullCrafts(prof)
  if not ns.Data.Ready() then return false end
  local k = prof or "*"
  local t = now()
  if lastPull[k] and t - lastPull[k] < 300 then return false end
  lastPull[k] = t
  local db = ns.db
  local since
  if db then
    db.craftsPulled = db.craftsPulled or {}
    if db.craftsPulled[k] then since = db.craftsPulled[k] - SYNC_MARGIN_MS end
    db.craftsPulled[k] = ns.Now() * 1000
  end
  Comm.Send({ op = "H", c = "crafts", pf = prof, a = 1, sn = since, h = ns.Data.CraftTokens(since, prof), v = ns.VERSION }, "GUILD")
  return true
end

function sendRecords(coll, filter, target)
  local raw = ns.Data.Raw(coll)
  if not raw then return 0 end
  local batch, count, total = {}, 0, 0
  for key, rec in pairs(raw) do
    if not filter or filter(key, rec) then
      batch[key] = rec
      count = count + 1
      total = total + 1
      if count >= BATCH_RECORDS then
        Comm.Send({ op = "B", c = coll, recs = batch }, "WHISPER", target)
        batch, count = {}, 0
      end
    end
  end
  if count > 0 then Comm.Send({ op = "B", c = coll, recs = batch }, "WHISPER", target) end
  return total
end

-- The officer who answers a given requester, chosen the same way by every client.
local function designatedResponder(requester)
  local me = ns.PlayerName()
  local list = {}
  if ns.IsOfficer(me) then list[#list + 1] = me end
  local t = now()
  for name, peer in pairs(Comm.peers) do
    if name ~= requester and name ~= me and t - peer.seen < PEER_TTL
      and ns.IsOfficer(name) and targetOnline(name) then
      list[#list + 1] = name
    end
  end
  if #list == 0 then return nil end
  table.sort(list)
  return list[(ns.Hash(requester) % #list) + 1]
end
Comm.DesignatedResponder = designatedResponder

----------------------------------------------------------------------
-- Incoming
----------------------------------------------------------------------
local function handleDigest(sender, msg, channel)
  if type(msg.dg) ~= "table" then return end
  local me = ns.PlayerName()
  local isReply = msg.r and true or false

  if isReply and channel == "WHISPER" and not Comm.gotReply then
    -- a relay answered my login digest: remember when this sync started
    Comm.gotReply = true
    local db = ns.db
    if db and Comm.syncStartMs then
      db.syncedAt = Comm.syncStartMs
      if Comm.syncWasFull then db.fullSyncAt = Comm.syncStartMs end
    end
  end

  -- Members don't answer digests broadcast to the guild while a relay is online; the relays do.
  if channel == "GUILD" and not isReply and not ns.IAmOfficer() and #relayList(true) > 0 then
    ns.Fire("PEER_ARRIVED", sender)
    return
  end

  local mine = ns.Data.Digests()
  local differs = {}
  for _, coll in ipairs(ns.Data.COLLECTIONS) do
    if not ns.Data.LOCAL_ONLY[coll] and not ns.Data.ALWAYS_SYNC[coll] and not ns.Data.FROZEN[coll] and msg.dg[coll] ~= mine[coll] then differs[#differs + 1] = coll end
  end
  local since = type(msg.sn) == "number" and msg.sn or nil
  local function recent(rec) return not since or (rec.t or 0) >= since end

  if #differs > 0 then
    if designatedResponder(sender) == me or (channel == "WHISPER" and ns.IAmOfficer()) then
      for _, coll in ipairs(differs) do sendRecords(coll, function(_, rec) return recent(rec) end, sender) end
    else
      for _, coll in ipairs(differs) do
        sendRecords(coll, function(_, rec) return rec.b == me and recent(rec) end, sender)
      end
    end
  end
  -- always answer a digest so the sender knows someone is there
  if not isReply then Comm.SendDigest("WHISPER", sender, true) end

  if channel == "GUILD" and not isReply then ns.Fire("PEER_ARRIVED", sender) end
  if channel == "WHISPER" and not isReply then ns.Fire("PEER_ARRIVED", sender) end
end

local hashSeen = {}
local function limited(k)
  local t = now()
  if hashSeen[k] and t - hashSeen[k] < 30 then return true end
  hashSeen[k] = t
  return false
end

-- Am I one of the `count` online addon users chosen for this requester? (The same choice on every
-- client, each working from the peers it has heard; later attempts pick others, the third is open.)
local function elect(sender, attempt, count)
  if attempt >= 3 then return true end
  local me = ns.PlayerName()
  local t = now()
  local list = { me }
  for name, peer in pairs(Comm.peers) do
    if name ~= sender and name ~= me and t - peer.seen < PEER_TTL and targetOnline(name) then
      list[#list + 1] = name
    end
  end
  table.sort(list)
  local start = (ns.Hash(sender) + attempt - 1) % #list
  for i = 0, math.min(count, #list) - 1 do
    if list[(start + i) % #list + 1] == me then return true end
  end
  return false
end

-- Step 2: a member logged in (or checks in) and sent digests. Chosen members say which collections differ.
local function handleDigestCheck(sender, msg)
  local attempt = tonumber(msg.a) or 1
  if limited("dg#" .. sender .. "#" .. attempt) then return end
  if not elect(sender, attempt, 2) then return end
  local since = type(msg.sn) == "number" and msg.sn or nil
  local mine = ns.Data.AlwaysDigests(since)
  local differs = {}
  for _, coll in ipairs(ns.Data.COLLECTIONS) do
    if ns.Data.ALWAYS_SYNC[coll] and msg.dg[coll] ~= mine[coll] then differs[#differs + 1] = coll end
  end
  Comm.Send({ op = "HN", a = attempt, sn = since, c = differs }, "WHISPER", sender)
end

-- Step 3a (requester): a member told me which collections differ. Send them my tokens for those.
local function handleNeed(sender, msg)
  local s = rowSession
  if not s or type(msg.c) ~= "table" then return end
  s.answered = true
  if #msg.c == 0 then markRowsSynced(s); return end
  if s.chosen[sender] or s.count >= 2 then return end
  local only, list = {}, {}
  for _, coll in ipairs(msg.c) do
    if ns.Data.ALWAYS_SYNC[coll] and not only[coll] then only[coll] = true; list[#list + 1] = coll end
  end
  if #list == 0 then return end
  s.chosen[sender] = true
  s.count = s.count + 1
  Comm.Send({ op = "HT", c = list, sn = s.since, h = ns.Data.RowTokens(s.since, only) }, "WHISPER", sender)
end

-- Someone sent a token (key hash + stamp) for each row they hold: send back the rows they lack and
-- the ones I hold in a newer version. `targeted` means they picked me (op HT); otherwise this is a
-- crafts pull to the whole guild, where the crafter always answers for his own rows and one elected
-- member answers for the rest.
local function handleHashes(sender, msg, targeted)
  if type(msg.h) ~= "string" then return end
  local attempt = tonumber(msg.a) or 1
  local crafts = msg.c == "crafts"
  local pf = type(msg.pf) == "string" and msg.pf or nil
  local only
  if not crafts then
    if type(msg.c) ~= "table" then return end
    only = {}
    for _, coll in ipairs(msg.c) do if ns.Data.ALWAYS_SYNC[coll] then only[coll] = true end end
  end
  if limited("h#" .. sender .. "#" .. attempt .. "#" .. (crafts and "c" or "r") .. "#" .. (pf or "")) then return end
  local theirs = ns.Data.ParseTokens(msg.h) -- key hash -> stamp of the version the requester holds
  local since = type(msg.sn) == "number" and msg.sn or nil
  local me = ns.PlayerName()
  local elected = targeted or elect(sender, attempt, 1)

  -- rows go out one collection after another, so parents (clans, grudges, events) precede children
  local batch, batchColl = { n = 0, recs = {} }, nil
  local function flush()
    if batchColl and batch.n > 0 then Comm.Send({ op = "B", c = batchColl, recs = batch.recs }, "WHISPER", sender) end
    batch, batchColl = { n = 0, recs = {} }, nil
  end
  local function consider(cl, key, rec, token)
    -- what the requester lacks, and what I hold in a newer version (my own stamp travels with it)
    local their = theirs[token:sub(1, 8)]
    if their and (rec.t or 0) <= their then return end
    if not (rec.b == me or elected) then return end
    if ns.Data.Departed(cl, key, rec) then return end
    if batchColl ~= cl then flush(); batchColl = cl end
    batch.recs[key] = rec
    batch.n = batch.n + 1
    if batch.n >= BATCH_RECORDS then flush() end
  end
  if crafts then
    ns.Data.EachCraft(since, pf, consider)
  else
    ns.Data.EachAlwaysRow(since, consider, only)
  end
  flush()
end

-- Rows that failed a permission check, usually because the row they depend on (the clan an invite
-- belongs to) hasn't arrived yet. They get another chance when more rows come in.
local pending = {}
local function parkRow(coll, key, rec)
  if #pending >= 100 then table.remove(pending, 1) end
  pending[#pending + 1] = { coll = coll, key = key, rec = rec, due = now() + 120 }
end

local function retryPending()
  if #pending == 0 then return false end
  local changed, t = false, now()
  for pass = 1, 2 do
    local progressed = false
    for i = #pending, 1, -1 do
      local p = pending[i]
      if t > p.due then
        table.remove(pending, i)
      elseif ns.Data.Merge(p.coll, p.key, p.rec, false) then
        table.remove(pending, i)
        changed, progressed = true, true
      end
    end
    if not progressed then break end
  end
  return changed
end

local function acceptRecord(sender, coll, key, rec)
  if type(rec) ~= "table" then return false end
  -- Always-synced rows may come from anyone (a login reply), but are still checked against the
  -- standing of the row's real author.
  if ns.Data.ALWAYS_SYNC[coll] or ns.Data.LOCAL_ONLY[coll] then return ns.Data.Merge(coll, key, rec, false) end
  -- Non-officers may only pass along records they wrote themselves.
  local officer = ns.IsOfficer(sender)
  if rec.b ~= sender and not officer then return false end
  return ns.Data.Merge(coll, key, rec, officer)
end

local function dispatch(sender, msg, channel)
  if type(msg) ~= "table" then return end
  if not ns.roster[sender] then return end -- only guildmates
  if msg.p ~= ns.PROTOCOL then
    if (msg.op == "D" or msg.op == "H") and not Comm.warnedOld and type(msg.p) == "number" and msg.p > ns.PROTOCOL then
      Comm.warnedOld = true
      ns.Print("A guildmate has a newer version of Ironforged. Update yours so your records keep syncing.")
    end
    return
  end
  Comm.peers[sender] = { seen = now(), version = tostring(msg.v or (Comm.peers[sender] and Comm.peers[sender].version) or "?") }
  Comm.stats.received = Comm.stats.received + 1

  if msg.op == "D" then
    handleDigest(sender, msg, channel)
  elseif msg.op == "H" then
    if type(msg.dg) == "table" then handleDigestCheck(sender, msg) else handleHashes(sender, msg, false) end
  elseif msg.op == "HN" then
    if channel == "WHISPER" then handleNeed(sender, msg) end
  elseif msg.op == "HT" then
    if channel == "WHISPER" then handleHashes(sender, msg, true) end
  elseif msg.op == "P" then
    if ns.Data.LOCAL_ONLY[msg.c] then return end -- crafts only travel in pulled batches
    if ns.Data.VALID[msg.c] and type(msg.k) == "string" and acceptRecord(sender, msg.c, msg.k, msg.r) then
      ns.Fire("DATA_CHANGED", msg.c, msg.k)
      -- A relay posts a member's own whispered edit to the guild for everyone else.
      if channel == "WHISPER" and ns.IAmOfficer() and type(msg.r) == "table"
        and msg.r.b == sender and not ns.IsOfficer(sender) then
        Comm.Send({ op = "P", c = msg.c, k = msg.k, r = msg.r }, "GUILD")
      end
    end
  elseif msg.op == "XS" then
    if type(msg.id) == "string" then ns.Fire("GAMBLE_STATE", sender, msg) end
  elseif msg.op == "XV" then
    if type(msg.id) == "string" then ns.Fire("GAMBLE_ROLL", sender, msg) end
  elseif msg.op == "C" then
    if type(msg.id) == "string" then ns.Fire("CHEERS_CALL", sender, msg.id) end
  elseif msg.op == "G" then
    if type(msg.id) == "string" then ns.Fire("CHEERS_DRINK", sender, msg.id, type(msg.item) == "string" and msg.item:sub(1, 60) or nil) end
  elseif msg.op == "CQ" then
    if channel == "WHISPER" and type(msg.r) == "string" then
      ns.Fire("CRAFT_REQUEST", sender, msg.r:sub(1, 80), type(msg.n) == "string" and msg.n:sub(1, 120) or "")
    end
  elseif msg.op == "S" then
    if type(msg.n) == "string" then ns.Fire("SIGHTING", sender, msg.n, tostring(msg.z or "")) end
  elseif msg.op == "B" then
    if not ns.Data.VALID[msg.c] or type(msg.recs) ~= "table" then return end
    local changed = false
    for key, rec in pairs(msg.recs) do
      if type(key) == "string" then
        local ok, why = acceptRecord(sender, msg.c, key, rec)
        if ok then changed = true
        elseif why == "perm" and ns.Data.ALWAYS_SYNC[msg.c] then parkRow(msg.c, key, rec) end
      end
    end
    if changed and retryPending() then changed = true end
    if ns.Data.ALWAYS_SYNC[msg.c] and rowSession then markRowsSynced(rowSession) end
    if changed then
      if ns.Data.ALWAYS_SYNC[msg.c] then Comm.rowsGot = Comm.rowsGot + 1 end
      Comm.stats.lastSync = ns.Now()
      ns.Fire("DATA_CHANGED", msg.c)
    end
  end
end

function Comm.OnAddonMessage(prefix, text, channel, sender)
  if prefix ~= ns.PREFIX then return end
  if channel ~= "GUILD" and channel ~= "WHISPER" then return end
  sender = ns.Name(sender)
  if sender == "" or (sender == ns.PlayerName() and not Comm.allowSelf) then return end
  if not ns.Data.Ready() then return end

  local id, i, n, part = text:match("^(%x+)\t(%d+)\t(%d+)\t(.*)$")
  i, n = tonumber(i), tonumber(n)
  if not id or not i or not n or n < 1 or n > MAX_PARTS or i > n then return end

  local msg
  if n == 1 then
    msg = Ser.Unpack(part)
  else
    local bkey = sender .. ":" .. id
    local buf = buffers[bkey]
    if not buf or buf.n ~= n then
      buf = { n = n, parts = {}, got = 0 }
      buffers[bkey] = buf
    end
    buf.time = now()
    if not buf.parts[i] then
      buf.parts[i] = part
      buf.got = buf.got + 1
    end
    if buf.got < n then return end
    buffers[bkey] = nil
    msg = Ser.Unpack(table.concat(buf.parts))
  end
  if msg then dispatch(sender, msg, channel) end
end

-- Clear half-received messages now and then.
local function sweep()
  local t = now()
  for k, buf in pairs(buffers) do
    if t - (buf.time or 0) > 120 then buffers[k] = nil end
  end
end

ns.RegisterEvent("CHAT_MSG_ADDON", function(...) Comm.OnAddonMessage(...) end)

local announced = false
ns.On("DATA_READY", function()
  if announced then return end
  announced = true
  if C_Timer then
    C_Timer.After(6 + math.random() * 6, Comm.RequestSync)
    C_Timer.NewTicker(60, sweep)
    C_Timer.NewTicker(45 * 60, function() Comm.CheckRows() end) -- catch up on anything a lost message left out
  end
end)

----------------------------------------------------------------------
-- Debug: feed a message through the real receive path as if `sender` had sent it.
-- The payload is serialised, cut into 220-byte chunks and handed to OnAddonMessage, so
-- chunk reassembly, the roster check, permission checks and merging all run for real.
-- Returns true when the message got past the roster/protocol checks into dispatch.
----------------------------------------------------------------------
local injectCounter = 0
function Comm.Inject(sender, payload, channel)
  channel = channel or "GUILD"
  if not ns.Data.Ready() then return false, "guild data isn't loaded yet" end
  local resolved = ns.Name(sender)
  if resolved == "" or not ns.roster[resolved] then
    return false, "'" .. tostring(sender) .. "' is not on your guild roster (names are matched as First Surname)"
  end
  payload.p = payload.p or ns.PROTOCOL -- a test may pose as an older version
  payload.v = payload.v or ns.VERSION
  local ok, packed = pcall(Ser.Pack, payload)
  if not ok then return false, "could not serialise: " .. tostring(packed) end
  injectCounter = injectCounter + 1
  local id = string.format("%x", 0xd000 + injectCounter)
  local n = math.max(1, math.ceil(#packed / CHUNK))
  local before = Comm.stats.received
  -- Messages from yourself are normally ignored; a test may impersonate you too.
  Comm.allowSelf = true
  local okFeed, err = pcall(function()
    for i = 1, n do
      local part = packed:sub((i - 1) * CHUNK + 1, i * CHUNK)
      Comm.OnAddonMessage(ns.PREFIX, id .. "\t" .. i .. "\t" .. n .. "\t" .. part, channel, sender)
    end
  end)
  Comm.allowSelf = false
  if not okFeed then return false, "error while handling it: " .. tostring(err) end
  if Comm.stats.received == before then
    return false, "dropped before dispatch (bad protocol or malformed message)"
  end
  return true
end

-- /sendmsg [Sender Name]: send a test backstory from a guildmate (default Frugo Forever).
-- Backstories are frozen since 2.18.0, so this now shows the receive path turning them away.
SLASH_IFSENDMSG1 = "/sendmsg"
SlashCmdList.IFSENDMSG = function(arg)
  arg = ns.Trim(arg or "")
  local sender = arg ~= "" and arg or "Frugo Forever"
  local resolved = ns.Name(sender)
  local rec = { d = { backstory = "Frugo Test Backstory" }, t = ns.Stamp(), b = resolved }
  local ok, why = Comm.Inject(sender, { op = "P", c = "profiles", k = resolved, r = rec })
  local got = ns.Data.Get("profiles", resolved)
  ns.Print(string.format("sendmsg: %s as %s, stored backstory: %s", ok and "delivered" or ("not delivered: " .. tostring(why)),
    resolved, got and got.backstory or "none"))
end
