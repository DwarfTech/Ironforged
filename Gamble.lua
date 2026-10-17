-- Ironforged: Cross Gambling, in the style of the CrossGambling addon.
--   1. A host in a raid opens a game for an amount of gold. Games are raid only.
--   2. Players join by typing 1 in raid chat (or -1 to leave), or with the Join button.
--   3. The host starts the rolling; everyone rolls 1 to the amount.
--   4. Highest roll wins. Lowest roll pays the winner the difference between the two rolls.
--      Ties for highest or lowest roll again among the tied players.
-- Gold changes hands by trade between the players; the addon only keeps score.
-- The host's client runs the game. Rolls are read only from the game's own roll messages, which
-- every raid member sees, so no one can report a roll they didn't make.
local ADDON, ns = ...

local G = {}
ns.Gamble = G

local Data = ns.Data
local CHANNELS = { RAID = "Raid" }
G.CHANNELS = CHANNELS
local MAX_AMOUNT = 1000000

local function isSecret(v) return issecretvalue and issecretvalue(v) end

-- The game everyone sees. On the host this is the real game; elsewhere it's the host's last broadcast.
-- { id, host, amount, channel, phase = "open"|"rolling"|"tiehigh"|"tielow"|"done"|"cancelled",
--   players = {name=true}, order = {names}, rolls = {name=n}, tie = {names}, tieRolls = {name=n},
--   high, low, highRoll, lowRoll, owed }
G.game = nil

local function first(name) return (ns.ShortName(name):match("^(%S+)")) or ns.ShortName(name) end

local function say(text, channel)
  local locked = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and select(2, pcall(C_ChatInfo.InChatMessagingLockdown))
  if locked == true then ns.Print(text); return end
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  if not send or not pcall(send, text, channel) then ns.Print(text) end
end
G._say = say

function G.IsHost()
  return G.game ~= nil and G.game.host == ns.PlayerName()
end

function G.Active()
  local g = G.game
  return g ~= nil and g.phase ~= "done" and g.phase ~= "cancelled"
end

----------------------------------------------------------------------
-- Broadcasting the host's game to guildmates with the addon
----------------------------------------------------------------------
local pendingBroadcast = false
local function broadcast()
  if not G.IsHost() then return end
  if pendingBroadcast then return end
  pendingBroadcast = true
  local function run()
    pendingBroadcast = false
    local g = G.game
    if not g then return end
    ns.Comm.Send({ op = "XS", id = g.id, amount = g.amount, channel = g.channel, phase = g.phase,
      order = g.order, rolls = g.rolls, tie = g.tie, tieRolls = g.tieRolls,
      high = g.high, low = g.low, owed = g.owed, kw = g.kw }, "GUILD")
  end
  if C_Timer then C_Timer.After(0.3, run) else run() end
end

local function changed()
  ns.Fire("GAMBLE")
  broadcast()
end

----------------------------------------------------------------------
-- Host actions
----------------------------------------------------------------------
function G.Open(amount, channel)
  amount = math.floor(tonumber(amount) or 0)
  if amount < 2 or amount > MAX_AMOUNT then ns.Print("Pick an amount from 2 to " .. MAX_AMOUNT .. " gold."); return end
  channel = "RAID"
  if not (IsInRaid and IsInRaid()) then
    ns.Print("Cross Gambling is raid only, so every roll is seen by the game itself. Form a raid first (make your party a raid).")
    return
  end
  if G.Active() and not G.IsHost() then ns.Print(first(G.game.host) .. " is already running a game."); return end
  local me = ns.PlayerName()
  G.game = { id = string.format("%x", ns.Hash(me .. ns.Now()) % 0xFFFFFF), host = me, amount = amount, channel = channel,
    phase = "open", players = {}, order = {}, rolls = {}, tie = {}, tieRolls = {} }
  say("Ironforged Cross Gambling: " .. amount .. "g! Type 1 to join, -1 to leave.", channel)
  -- tell the guild how to get into the raid
  local word = ns.AutoInvite and ns.AutoInvite.Word() or "inv"
  G.game.kw = word
  say("Ironforged Cross Gambling: " .. amount .. "g in " .. ns.CharName(me, false) .. "'s raid! Whisper " ..
    ns.CharName(me, false) .. " \"" .. word .. "\" for an invite, then type 1 in raid chat to join.", "GUILD")
  changed()
end

function G.LastCall()
  if not G.IsHost() or G.game.phase ~= "open" then return end
  say("Last call to join for " .. G.game.amount .. "g! Type 1 to join.", G.game.channel)
end

local function rollNames(list)
  local out = {}
  for _, n in ipairs(list) do out[#out + 1] = first(n) end
  return table.concat(out, ", ")
end

function G.StartRolling()
  local g = G.game
  if not G.IsHost() or g.phase ~= "open" then return end
  if #g.order < 2 then ns.Print("At least two players must join first."); return end
  g.phase = "rolling"
  say("Rolling for " .. g.amount .. "g! " .. #g.order .. " players: " .. rollNames(g.order) .. ". Type /roll " .. g.amount .. " now.", g.channel)
  changed()
end

function G.Cancel()
  if not G.IsHost() then return end
  if G.Active() then say("Cross Gambling cancelled.", G.game.channel) end
  G.game.phase = "cancelled"
  changed()
end

-- Who still has to roll in the current phase.
function G.Waiting()
  local g = G.game
  local out = {}
  if not g then return out end
  if g.phase == "rolling" then
    for _, n in ipairs(g.order) do if not g.rolls[n] then out[#out + 1] = n end end
  elseif g.phase == "tiehigh" or g.phase == "tielow" then
    for _, n in ipairs(g.tie) do if not g.tieRolls[n] then out[#out + 1] = n end end
  end
  return out
end

-- Extremes of a set of rolls: list of names at the max (or min), and that value.
local function extremes(names, rolls, wantHigh)
  local best, who = nil, {}
  for _, n in ipairs(names) do
    local r = rolls[n]
    if r then
      if best == nil or (wantHigh and r > best) or (not wantHigh and r < best) then best, who = r, { n }
      elseif r == best then who[#who + 1] = n end
    end
  end
  return who, best
end

local function finish()
  local g = G.game
  g.owed = (g.highRoll or 0) - (g.lowRoll or 0)
  g.phase = "done"
  if g.owed <= 0 or g.high == g.low then
    say("Everyone rolled the same. No gold changes hands.", g.channel)
  else
    say(first(g.low) .. " owes " .. first(g.high) .. " " .. g.owed .. "g! (" .. g.highRoll .. " to " .. g.lowRoll .. ")", g.channel)
    local order = {}
    for _, n in ipairs(g.order) do order[#order + 1] = n end
    Data.Put("gambles", g.host .. "#" .. g.id, { amount = g.amount, high = g.high, low = g.low, owed = g.owed,
      players = order, ts = ns.Now() }, true)
  end
  changed()
end

local function startTie(kind, names)
  local g = G.game
  g.phase = kind
  g.tie = names
  g.tieRolls = {}
  say((kind == "tiehigh" and "Tie for high" or "Tie for low") .. " between " .. rollNames(names) .. "! Roll again: /roll " .. g.amount, g.channel)
  changed()
end

-- Settle high, then low, breaking ties as needed.
local function evaluate()
  local g = G.game
  if not g then return end
  if #G.Waiting() > 0 then changed(); return end
  if g.phase == "rolling" then
    local highs, hv = extremes(g.order, g.rolls, true)
    if #highs > 1 then g.highRoll = hv; startTie("tiehigh", highs); return end
    g.high, g.highRoll = highs[1], hv
    local rest = {}
    for _, n in ipairs(g.order) do if n ~= g.high then rest[#rest + 1] = n end end
    local lows, lv = extremes(rest, g.rolls, false)
    if #lows > 1 then g.lowRoll = lv; startTie("tielow", lows); return end
    g.low, g.lowRoll = lows[1], lv
    finish()
  elseif g.phase == "tiehigh" then
    local highs = extremes(g.tie, g.tieRolls, true)
    if #highs > 1 then startTie("tiehigh", highs); return end
    g.high = highs[1]
    local rest = {}
    for _, n in ipairs(g.order) do if n ~= g.high then rest[#rest + 1] = n end end
    local lows, lv = extremes(rest, g.rolls, false)
    if #lows > 1 then g.lowRoll = lv; startTie("tielow", lows); return end
    g.low, g.lowRoll = lows[1], lv
    finish()
  elseif g.phase == "tielow" then
    local lows = extremes(g.tie, g.tieRolls, false)
    if #lows > 1 then startTie("tielow", lows); return end
    g.low = lows[1]
    finish()
  end
end

-- A roll arrived (from the game's roll message, or a player's own report).
function G.OnRoll(name, roll, lo, hi)
  local g = G.game
  if not G.IsHost() or not g then return end
  name = ns.FullName(name)
  if lo ~= 1 or hi ~= g.amount then return end
  if g.phase == "rolling" then
    if not g.players[name] or g.rolls[name] then return end
    g.rolls[name] = roll
    evaluate()
  elseif g.phase == "tiehigh" or g.phase == "tielow" then
    local inTie = false
    for _, n in ipairs(g.tie) do if n == name then inTie = true end end
    if not inTie or g.tieRolls[name] then return end
    g.tieRolls[name] = roll
    evaluate()
  end
end

-- A chat message in the game's channel: "1" joins, "-1" leaves.
function G.OnChat(channel, text, sender)
  local g = G.game
  if not G.IsHost() or not g or g.phase ~= "open" then return end
  if channel ~= g.channel or type(text) ~= "string" or isSecret(text) or isSecret(sender) then return end
  local name = ns.FullName(sender)
  if not name then return end
  text = ns.Trim(text)
  if text == "1" and not g.players[name] then
    g.players[name] = true
    g.order[#g.order + 1] = name
    changed()
  elseif text == "-1" and g.players[name] then
    g.players[name] = nil
    for i, n in ipairs(g.order) do if n == name then table.remove(g.order, i) break end end
    changed()
  end
end

-- The host takes a player out of the game (wrong person, went AFK, won't roll).
function G.Kick(name)
  local g = G.game
  if not G.IsHost() or not G.Active() or not g.players[name] then return end
  g.players[name] = nil
  g.rolls[name] = nil
  for i, n in ipairs(g.order) do if n == name then table.remove(g.order, i) break end end
  local inTie = false
  for i, n in ipairs(g.tie) do if n == name then table.remove(g.tie, i); inTie = true; break end end
  g.tieRolls[name] = nil
  say(first(name) .. " has been removed from the game.", g.channel)
  if g.phase ~= "open" and #g.order < 2 then
    say("Not enough players left. Cross Gambling cancelled.", g.channel)
    g.phase = "cancelled"
    changed()
    return
  end
  if g.phase == "open" then changed(); return end
  if name == g.high or name == g.low then
    -- the settled winner or loser left: settle again from everyone's first rolls
    g.high, g.low, g.phase, g.tie, g.tieRolls = nil, nil, "rolling", {}, {}
  elseif inTie and #g.tie == 1 then
    -- one player left in the tie: they take it without rolling again
    g.tieRolls[g.tie[1]] = g.tieRolls[g.tie[1]] or 1
  end
  evaluate()
end

----------------------------------------------------------------------
-- Player actions (any guildmate, including the host)
----------------------------------------------------------------------
function G.Join() if G.game then say("1", G.game.channel) end end
function G.Leave() if G.game then say("-1", G.game.channel) end end

function G.Roll()
  local g = G.game
  if not g then return end
  if RandomRoll then
    if not pcall(RandomRoll, 1, g.amount) then ns.Print("Type /roll " .. g.amount) end
  else
    ns.Print("Type /roll " .. g.amount)
  end
end

-- Not in the host's raid yet: whisper the host their invite keyword.
function G.AskInvite()
  local g = G.game
  if not g or not g.host then return end
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  local target = ns.CharName(g.host)
  if send and pcall(send, g.kw or "inv", "WHISPER", nil, target) then
    ns.Print("Asked " .. first(g.host) .. " for an invite. Type 1 in raid chat once you're in.")
  else
    ns.Print("Whisper " .. first(g.host) .. " \"" .. (g.kw or "inv") .. "\" for an invite.")
  end
end

function G.IAmIn()
  local g = G.game
  if not g then return false end
  local me = ns.PlayerName()
  for _, n in ipairs(g.order or {}) do if n == me then return true end end
  return false
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local rollPattern
local function parseRoll(text)
  if not rollPattern then
    local tmpl = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
    rollPattern = "^" .. tmpl:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)") .. "$"
  end
  local who, roll, lo, hi = text:match(rollPattern)
  if not who then return nil end
  return who, tonumber(roll), tonumber(lo), tonumber(hi)
end
G._parseRoll = parseRoll

ns.RegisterEvent("CHAT_MSG_SYSTEM", function(text)
  if type(text) ~= "string" or isSecret(text) or not G.game then return end
  local who, roll, lo, hi = parseRoll(text)
  if not who then return end
  if G.IsHost() then G.OnRoll(who, roll, lo, hi) end
end)

for _, ev in ipairs({ "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" }) do
  local channel = ev:match("CHAT_MSG_(%u+)")
  ns.RegisterEvent(ev, function(text, sender) G.OnChat(channel, text, sender) end)
end

-- State from a host
ns.On("GAMBLE_STATE", function(host, msg)
  if G.IsHost() then return end
  if type(msg.order) ~= "table" or type(msg.rolls) ~= "table" then return end
  local fresh = not G.game or G.game.id ~= msg.id
  G.game = { id = msg.id, host = host, amount = tonumber(msg.amount) or 0, channel = "RAID",
    phase = msg.phase, order = msg.order, rolls = msg.rolls, tie = msg.tie or {}, tieRolls = msg.tieRolls or {},
    high = msg.high, low = msg.low, owed = msg.owed, players = {},
    kw = type(msg.kw) == "string" and msg.kw:sub(1, 20) or "inv" }
  for _, n in ipairs(msg.order) do G.game.players[n] = true end
  ns.Fire("GAMBLE", fresh)
end)

-- Rolls reported by a player's own addon (older versions did this outside a raid) are ignored:
-- only the game's roll messages count.

----------------------------------------------------------------------
-- Score: net gold per dwarf across recorded games
----------------------------------------------------------------------
function G.Standings()
  local net, games = {}, {}
  for _, r in Data.Each("gambles") do
    for _, n in ipairs(r.players or {}) do games[n] = (games[n] or 0) + 1 end
    if r.high and r.low and r.owed then
      net[r.high] = (net[r.high] or 0) + r.owed
      net[r.low] = (net[r.low] or 0) - r.owed
    end
  end
  local out = {}
  for n, c in pairs(games) do out[#out + 1] = { name = n, net = net[n] or 0, games = c } end
  table.sort(out, function(a, b) if a.net ~= b.net then return a.net > b.net end return a.name < b.name end)
  return out
end
