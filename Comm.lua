-- Ironforged: guild sync over hidden addon messages.
-- Live edits go to the GUILD channel. On login each client sends a digest of its data;
-- one designated officer whispers back any collections that differ, and everyone whispers
-- back the records they personally wrote. Messages are chunked and rate limited.
local ADDON, ns = ...

local Comm = {}
ns.Comm = Comm

local Ser = ns.Ser
local CHUNK = 220
local BATCH_RECORDS = 20
local PEER_TTL = 30 * 60
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
  local target = item.target
  if item.channel == "WHISPER" then target = ns.CharName(target) end -- never "First Surname-Realm"
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
-- Outgoing helpers
----------------------------------------------------------------------
function Comm.BroadcastRecord(coll, key, rec)
  Comm.Send({ op = "P", c = coll, k = key, r = rec }, "GUILD")
end

-- Tell the guild you've spotted a grudged foe (not stored).
function Comm.BroadcastSighting(foe, zone)
  Comm.Send({ op = "S", n = foe, z = zone }, "GUILD")
end

function Comm.SendDigest(channel, target, isReply)
  if not ns.Data.Ready() then return end
  Comm.Send({ op = "D", v = ns.VERSION, dg = ns.Data.Digests(), r = isReply or nil }, channel, target)
end

function Comm.RequestSync()
  Comm.SendDigest("GUILD")
  Comm.stats.lastSync = ns.Now()
end

local function sendRecords(coll, filter, target)
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
  local mine = ns.Data.Digests()
  local differs = {}
  for _, coll in ipairs(ns.Data.COLLECTIONS) do
    if msg.dg[coll] ~= mine[coll] then differs[#differs + 1] = coll end
  end
  if #differs == 0 then return end

  if designatedResponder(sender) == me then
    for _, coll in ipairs(differs) do sendRecords(coll, nil, sender) end
  else
    for _, coll in ipairs(differs) do
      sendRecords(coll, function(_, rec) return rec.b == me end, sender)
    end
  end
  if not msg.r then Comm.SendDigest("WHISPER", sender, true) end

  if channel == "GUILD" and not msg.r then ns.Fire("PEER_ARRIVED", sender) end
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
    if ns.Data.VALID[msg.c] and type(msg.k) == "string" and acceptRecord(sender, msg.c, msg.k, msg.r) then
      ns.Fire("DATA_CHANGED", msg.c, msg.k)
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
  sender = ns.FullName(sender)
  if not sender or sender == ns.PlayerName() then return end
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
