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
  local localOnly = ns.Data.LOCAL_ONLY[coll]
  if ns.IAmOfficer() then
    if not localOnly then Comm.Send({ op = "P", c = coll, k = key, r = rec }, "GUILD") end
    return
  end
  local relays = pickRelays(localOnly and 2 or 1, true)
  if #relays == 0 then
    -- no Longbeard online: guild-wide as before (crafts wait for the next login push or a pull)
    if not localOnly then Comm.Send({ op = "P", c = coll, k = key, r = rec }, "GUILD") end
    return
  end
  for _, relay in ipairs(relays) do
    Comm.Send({ op = "P", c = coll, k = key, r = rec }, "WHISPER", relay)
  end
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

-- Hand my own crafts to the relays so others can pull them.
local function pushCrafts(relays)
  local me = ns.PlayerName()
  for _, relay in ipairs(relays) do
    sendRecords("crafts", function(_, rec) return rec.b == me end, relay)
  end
end

function Comm.RequestSync()
  Comm.stats.lastSync = ns.Now()
  Comm.syncStartMs = ns.Now() * 1000
  Comm.gotReply = false
  local since = sinceStamp()
  Comm.syncWasFull = since == nil
  local relays = ns.IAmOfficer() and {} or pickRelays(2, false)
  if #relays == 0 then
    Comm.SendDigest("GUILD", nil, nil, since)
    return
  end
  for _, relay in ipairs(relays) do Comm.SendDigest("WHISPER", relay, nil, since) end
  pushCrafts(relays)
  -- if neither relay answers (no addon, or they logged off) fall back to the guild channel
  if C_Timer then
    C_Timer.After(25, function()
      if not Comm.gotReply then Comm.SendDigest("GUILD", nil, nil, since) end
    end)
  end
end

-- Ask a relay for crafts: one profession, or all (nil). Only what changed since my last pull.
-- Limited to once per 5 minutes per profession.
local lastPull = {}
function Comm.PullCrafts(prof)
  local k = prof or "*"
  local t = now()
  if lastPull[k] and t - lastPull[k] < 300 then return false end
  local relays = pickRelays(1, true)
  if #relays == 0 then return false end
  lastPull[k] = t
  local db = ns.db
  local since
  if db then
    db.craftsPulled = db.craftsPulled or {}
    if db.craftsPulled[k] then since = db.craftsPulled[k] - SYNC_MARGIN_MS end
    db.craftsPulled[k] = ns.Now() * 1000
  end
  Comm.Send({ op = "CG", pf = prof, sn = since }, "WHISPER", relays[1])
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
    if not ns.Data.LOCAL_ONLY[coll] and msg.dg[coll] ~= mine[coll] then differs[#differs + 1] = coll end
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

local function acceptRecord(sender, coll, key, rec)
  if type(rec) ~= "table" then return false end
  -- Non-officers may only pass along records they wrote themselves.
  local officer = ns.IsOfficer(sender)
  if rec.b ~= sender and not officer then return false end
  return ns.Data.Merge(coll, key, rec, officer)
end

local function dispatch(sender, msg, channel)
  if type(msg) ~= "table" then return end
  if not ns.roster[sender] then return end -- only guildmates
  if msg.p ~= ns.PROTOCOL then
    if msg.op == "D" and not Comm.warnedOld and type(msg.p) == "number" and msg.p > ns.PROTOCOL then
      Comm.warnedOld = true
      ns.Print("A guildmate has a newer version of Ironforged. Update yours so your records keep syncing.")
    end
    return
  end
  Comm.peers[sender] = { seen = now(), version = tostring(msg.v or (Comm.peers[sender] and Comm.peers[sender].version) or "?") }
  Comm.stats.received = Comm.stats.received + 1

  if msg.op == "D" then
    handleDigest(sender, msg, channel)
  elseif msg.op == "P" then
    local localOnly = ns.Data.LOCAL_ONLY[msg.c]
    if localOnly and channel ~= "WHISPER" then return end -- crafts only travel by whisper
    if ns.Data.VALID[msg.c] and type(msg.k) == "string" and acceptRecord(sender, msg.c, msg.k, msg.r) then
      ns.Fire("DATA_CHANGED", msg.c, msg.k)
      -- A relay posts a member's own whispered edit to the guild for everyone else.
      if channel == "WHISPER" and not localOnly and ns.IAmOfficer() and type(msg.r) == "table"
        and msg.r.b == sender and not ns.IsOfficer(sender) then
        Comm.Send({ op = "P", c = msg.c, k = msg.k, r = msg.r }, "GUILD")
      end
    end
  elseif msg.op == "CG" then
    -- a craft pull: any Longbeard answers what a member asks for
    if channel == "WHISPER" and ns.IAmOfficer() then
      local pf = type(msg.pf) == "string" and msg.pf or nil
      local since = type(msg.sn) == "number" and msg.sn or nil
      sendRecords("crafts", function(key, rec)
        if since and (rec.t or 0) < since then return false end
        return not pf or select(2, ns.Data.SplitKey(key)) == pf
      end, sender)
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
      if type(key) == "string" and acceptRecord(sender, msg.c, key, rec) then changed = true end
    end
    if changed then
      Comm.stats.lastSync = ns.Now()
      ns.Fire("DATA_CHANGED", msg.c)
    end
  end
end

function Comm.OnAddonMessage(prefix, text, channel, sender)
  if prefix ~= ns.PREFIX then return end
  if channel ~= "GUILD" and channel ~= "WHISPER" then return end
  sender = ns.Name(sender)
  if sender == "" or sender == ns.PlayerName() then return end
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
  end
end)

----------------------------------------------------------------------
-- Debug: /sendmsg [Sender-Realm] feeds a test backstory through Comm.OnAddonMessage as if
-- that guildmate had broadcast it (default Frugo-Forever). Sender must be on your roster.
-- NOTE: this really stores the record ("Frugo Test Backstory") in your local profiles data.
----------------------------------------------------------------------
SLASH_IFSENDMSG1 = "/sendmsg"
SlashCmdList.IFSENDMSG = function(arg)
  arg = ns.Trim and ns.Trim(arg or "") or (arg or "")
  local sender = arg ~= "" and arg or "Frugo-Forever"
  local resolved = ns.Name(sender)
  if not ns.roster[resolved] then
    ns.Print("sendmsg: '" .. sender .. "' isn't on your guild roster, so the message would be ignored.")
    return
  end
  local rec = { d = { backstory = "Frugo Test Backstory" }, t = ns.Stamp(), b = resolved }
  local packed = Ser.Pack({ p = ns.PROTOCOL, op = "P", v = ns.VERSION, c = "profiles", k = resolved, r = rec })
  local before = Comm.stats.received
  Comm.OnAddonMessage(ns.PREFIX, "dbf\t1\t1\t" .. packed, "GUILD", sender)
  local got = ns.Data.Get("profiles", resolved)
  ns.Print(string.format("sendmsg: delivered as %s (received %d -> %d), stored backstory: %s",
    resolved, before, Comm.stats.received, got and got.backstory or "none"))
end
