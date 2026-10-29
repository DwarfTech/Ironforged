-- Ironforged: appeals. A member whose challenge failed through a mishap or a bug can appeal it.
-- The guild master and Longbeards read the appeal and restore the challenge or deny it.
-- Only a member's own client writes their challenge record, so a restored challenge comes back
-- to life on the member's client (at once if online, otherwise at their next login).
--   "appeals" key = challenge key   { text, ts, failed = the failure being appealed (its time),
--                                     ruling = nil | "restored" | "denied", judge, rts }
local ADDON, ns = ...
local Data = ns.Data
local C = ns.Challenges

local A = {}
ns.Appeals = A

local function first(name) return (ns.Name(name):match("^(%S+)")) or ns.Name(name) end

function A.Get(key) return Data.Get("appeals", key) end

-- Can this failed challenge of mine be appealed? (one appeal per failure)
function A.CanAppeal(key)
  local d = Data.Get("challenges", key)
  if not d or d.status ~= "failed" or Data.SplitKey(key) ~= ns.PlayerName() then return false end
  local a = A.Get(key)
  return not a or (tonumber(a.failed) or 0) ~= (tonumber(d.ended) or 0)
end

function A.File(key, text)
  if not A.CanAppeal(key) then ns.Print("That challenge can't be appealed."); return false end
  text = ns.Clean(text or "", 300)
  if text == "" then ns.Print("Say what happened."); return false end
  local d = Data.Get("challenges", key)
  if Data.Put("appeals", key, { text = text, ts = ns.Now(), failed = d.ended }) then
    ns.Print("Appeal sent. The Thane and the Longbeards will look at it.")
    return true
  end
  return false
end

-- Pending appeals of current guildmates, oldest first: { key, member, data, challenge }
function A.Pending()
  local out = {}
  for k, a in Data.Each("appeals") do
    local member = Data.SplitKey(k)
    local ch = Data.Get("challenges", k)
    if not a.ruling and member and ns.roster[member] and ch and ch.status == "failed" then
      out[#out + 1] = { key = k, member = member, data = a, challenge = ch }
    end
  end
  table.sort(out, function(x, y) return (x.data.ts or 0) < (y.data.ts or 0) end)
  return out
end

function A.Rule(key, ruling)
  if not ns.IsLongbeardOrGM(ns.PlayerName()) then ns.Print("Only the Thane and the Longbeards rule on appeals."); return false end
  local a = A.Get(key)
  if not a or a.ruling then return false end
  local n = {}
  for k, v in pairs(a) do n[k] = v end
  n.ruling, n.judge, n.rts = ruling, ns.PlayerName(), ns.Now()
  if Data.Put("appeals", key, n) then
    local member = Data.SplitKey(key)
    ns.Print((ruling == "restored" and "Restored " or "Denied ") .. ns.Name(member) .. "'s appeal.")
    return true
  end
  return false
end

----------------------------------------------------------------------
-- The member's own client brings a restored challenge back, once per ruling
----------------------------------------------------------------------
function A.ApplyMine()
  local me = ns.PlayerName()
  if not me or not Data.Ready() then return end
  for k, a in Data.Each("appeals") do
    if Data.SplitKey(k) == me and a.ruling == "restored" then
      local d = Data.Get("challenges", k)
      if d and d.status == "failed" and (tonumber(d.restoredAt) or 0) < (tonumber(a.rts) or 0) then
        local n = {}
        for f, v in pairs(d) do n[f] = v end
        local note = "Failed (" .. (d.reason or "no reason given") .. "), restored on appeal by " .. ns.Name(a.judge or "?") ..
          " on " .. ns.FormatDate(a.rts) .. "."
        n.status, n.ended, n.reason, n.restoredAt = "active", nil, nil, a.rts
        n.history = (type(d.history) == "string" and d.history ~= "") and (d.history .. "\n" .. note) or note
        if #n.history > 400 then n.history = n.history:sub(-400) end
        if Data.Put("challenges", k, n, true) then
          ns.Print("|cff40ff40Appeal granted:|r " .. d.name .. " is under way again. Restored by " .. ns.Name(a.judge or "?") .. ".")
          if C.Enforce then pcall(C.Enforce) end
        end
      end
    end
  end
end

----------------------------------------------------------------------
-- Notices
----------------------------------------------------------------------
local told = {}
ns.On("DATA_CHANGED", function(coll, key)
  if coll ~= "appeals" then return end
  if C_Timer then C_Timer.After(1, function() pcall(A.ApplyMine) end) else A.ApplyMine() end
  if not key then return end
  local a = A.Get(key)
  if not a then return end
  local member = Data.SplitKey(key)
  local me = ns.PlayerName()
  local stamp = key .. "#" .. tostring(a.ruling or "filed")
  if told[stamp] then return end
  told[stamp] = true
  if ns.Now() - (tonumber(a.rts or a.ts) or 0) > 600 then return end -- old news from a sync
  local ch = Data.Get("challenges", key)
  local what = ch and ch.name or "a challenge"
  if not a.ruling and member ~= me and ns.IsLongbeardOrGM(me) then
    ns.Print("|cffd4a017Appeal:|r " .. ns.Name(member) .. " appeals their failed " .. what .. " challenge. See the Challenges tab.")
  elseif a.ruling == "denied" and member == me then
    ns.Print("|cffff4040Appeal denied:|r " .. what .. " stays failed. (" .. ns.Name(a.judge or "?") .. ")")
  end
end)

ns.On("DATA_READY", function()
  if C_Timer then C_Timer.After(25, function() pcall(A.ApplyMine) end) end
end)
