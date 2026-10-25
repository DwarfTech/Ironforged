-- Ironforged: Looking for Dwarf, a group board inside the guild.
-- A leader posts what they need ("Need 2 for Gnomeregan"); guildmates with the addon get a quiet
-- popup and sign up with a role; the leader invites them. Nothing goes to chat.
-- A call for aid is a post too (aid = true): a dwarf beset by the Horde asks for up to 39 more,
-- a full raid. Guildmates get one line in their chat window, no popup, and answer in the tab.
--   "lfd"     key = leader .. "#" .. id       { what, need, note, ts, aid }
--   "lfdjoin" key = post key .. "#" .. member { role, ts }
local ADDON, ns = ...
local Data = ns.Data

local L = {}
ns.LFD = L

L.TTL = 2 * 60 * 60 -- posts close themselves after two hours
L.AID_TTL = 30 * 60 -- calls for aid after half an hour
L.MAX_NEED = 39     -- a full raid of 40

local HOME = LE_PARTY_CATEGORY_HOME or 1
local function ttl(d) return (type(d) == "table" and d.aid) and L.AID_TTL or L.TTL end
L.ROLES = { tank = "Tank", healer = "Healer", dps = "Damage" }
L.ROLE_ORDER = { "tank", "healer", "dps" }

local function first(name) return (ns.Name(name):match("^(%S+)")) or ns.Name(name) end

function L.Leader(postKey) return (Data.SplitKey(postKey)) end

function L.IsOpen(postKey, d)
  d = d or Data.Get("lfd", postKey)
  if type(d) ~= "table" then return false end
  local leader = L.Leader(postKey)
  if not leader or not ns.roster[leader] then return false end
  if ns.Now() - (tonumber(d.ts) or 0) > ttl(d) then return false end
  return leader == ns.PlayerName() or ns.roster[leader].online
end

-- Open posts: { key, leader, data, joins }
function L.Posts()
  local out = {}
  for k, d in Data.Each("lfd") do
    if L.IsOpen(k, d) then out[#out + 1] = { key = k, leader = L.Leader(k), data = d, joins = L.Joins(k) } end
  end
  -- calls for aid first, then newest first
  table.sort(out, function(a, b)
    if (a.data.aid and true or false) ~= (b.data.aid and true or false) then return a.data.aid and true or false end
    return (a.data.ts or 0) > (b.data.ts or 0)
  end)
  return out
end

-- Sign-ups for a post: { member, role, ts }, oldest first.
function L.Joins(postKey)
  local out = {}
  for k, d in Data.Each("lfdjoin") do
    local post, member = Data.SplitKey(k)
    if post == postKey and ns.roster[member] then out[#out + 1] = { key = k, member = member, role = d.role, ts = d.ts or 0 } end
  end
  table.sort(out, function(a, b) return a.ts < b.ts end)
  return out
end

function L.IsFull(postKey, d)
  d = d or Data.Get("lfd", postKey)
  return d ~= nil and #L.Joins(postKey) >= (tonumber(d.need) or 1)
end

function L.MyPost()
  local me = ns.PlayerName()
  for k, d in Data.Each("lfd") do
    if L.Leader(k) == me and L.IsOpen(k, d) then return k, d end
  end
end

function L.MyJoin(postKey)
  local me = ns.PlayerName()
  local d = me and Data.Get("lfdjoin", postKey .. "#" .. me)
  return d
end

function L.Close(postKey, quiet)
  for _, j in ipairs(L.Joins(postKey)) do Data.Delete("lfdjoin", j.key) end
  Data.Delete("lfd", postKey)
  if not quiet then ns.Print("Your Looking for Dwarf post is closed.") end
end

function L.Post(what, need, note, aid)
  what = ns.Clean(what, 60)
  need = math.floor(tonumber(need) or 0)
  if what == "" then ns.Print("Say what the group is for."); return false end
  if need < 1 or need > L.MAX_NEED then ns.Print("Need between 1 and " .. L.MAX_NEED .. " dwarves."); return false end
  local me = ns.PlayerName()
  if not me then return false end
  for k in Data.Each("lfd") do if L.Leader(k) == me then L.Close(k, true) end end
  local key = me .. "#" .. string.format("%x", ns.Stamp())
  local d = { what = what, need = need, note = ns.Clean(note or "", 120), ts = ns.Now(), aid = aid and true or nil }
  if Data.Put("lfd", key, d) then
    if aid then
      ns.Print("|cffff4040You call for aid!|r Your guildmates will see it in the Looking for Dwarf tab.")
    else
      ns.Print("Posted: looking for " .. need .. (need == 1 and " dwarf" or " dwarves") .. " for " .. what .. ".")
    end
    return key
  end
  return false
end

-- Call the guild to your side: where you are, and the Horde you saw in the last two minutes.
function L.CallForAid()
  local B = ns.Blood
  local zone = B and B.ZoneName and B.ZoneName() or ""
  local okS, sub = pcall(function() return GetSubZoneText and GetSubZoneText() end)
  if not okS or type(sub) ~= "string" or (issecretvalue and issecretvalue(sub)) or sub == zone then sub = "" end
  local where = (sub ~= "" and zone ~= "") and (sub .. ", " .. zone) or (zone ~= "" and zone or sub)
  local foes = B and B.RecentHorde and B.RecentHorde(120, 5) or {}
  local what = where ~= "" and ("Aid in " .. where) or "Aid against the Horde"
  local note = #foes > 0 and ("Foes seen: " .. table.concat(foes, ", ")) or ""
  return L.Post(what, L.MAX_NEED, note, true)
end

function L.Join(postKey, role)
  local me = ns.PlayerName()
  if not me or not L.IsOpen(postKey) then ns.Print("That group has closed."); return false end
  if L.Leader(postKey) == me then return false end
  if not L.ROLES[role] then role = "dps" end
  if Data.Put("lfdjoin", postKey .. "#" .. me, { role = role, ts = ns.Now() }) then
    local d = Data.Get("lfd", postKey)
    if d and d.aid then
      ns.Print("You heed " .. first(L.Leader(postKey)) .. "'s call for aid. Watch for the invite.")
      return true
    end
    ns.Print("You're signed up as " .. L.ROLES[role] .. " for " .. first(L.Leader(postKey)) .. "'s " .. (d and d.what or "group") .. ". Watch for the invite.")
    return true
  end
  return false
end

function L.Leave(postKey)
  local me = ns.PlayerName()
  if me then Data.Delete("lfdjoin", postKey .. "#" .. me) end
end

-- A post for more than four turns my party into a raid as soon as there is a party to turn.
local function convertToRaid()
  if not (IsInGroup and IsInGroup(HOME)) or (IsInRaid and IsInRaid(HOME)) then return false end
  if UnitIsGroupLeader and not UnitIsGroupLeader("player") then return false end
  local fn = (C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid
  return fn and pcall(fn) or false
end

local function wantsRaid(postKey)
  local d = postKey and Data.Get("lfd", postKey)
  return d ~= nil and (tonumber(d.need) or 0) > 4
end

local function grouped(member)
  local n = ns.Name(member)
  return (UnitInRaid and UnitInRaid(n)) or (UnitInParty and UnitInParty(n)) or false
end

-- Invite a guildmate to my group. Falls back to a command to copy if the game refuses.
function L.Invite(member, postKey)
  if wantsRaid(postKey) then convertToRaid() end
  local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
  local ok = fn and pcall(fn, ns.Name(member))
  if ok then
    ns.Print("Invited " .. ns.Name(member) .. ".")
  elseif ns.UI and ns.UI.CopyCommand then
    ns.UI.CopyCommand("/invite " .. ns.Name(member), "Invite " .. ns.Name(member))
  end
  return ok
end

-- A party holds five, so with no group yet only four go out; the rest follow once the party has
-- formed and been turned into a raid.
local inviteRest
function L.InviteAll(postKey)
  local raid = wantsRaid(postKey)
  if raid then convertToRaid() end
  local room = (raid and not (IsInRaid and IsInRaid(HOME)) and not (IsInGroup and IsInGroup(HOME))) and 4 or nil
  local n, left = 0, 0
  for _, j in ipairs(L.Joins(postKey)) do
    if ns.roster[j.member] and ns.roster[j.member].online and not grouped(j.member) then
      if room and n >= room then
        left = left + 1
      elseif L.Invite(j.member, postKey) then
        n = n + 1
      end
    end
  end
  if left > 0 then
    inviteRest = postKey
    ns.Print("Inviting the first four. The other " .. left .. " follow once your party forms and becomes a raid.")
  end
  if n == 0 and left == 0 then ns.Print("No one signed up is online to invite.") end
end

ns.RegisterEvent("GROUP_ROSTER_UPDATE", function()
  local mine = L.MyPost()
  if not mine or not wantsRaid(mine) then return end
  convertToRaid()
  if inviteRest == mine and IsInRaid and IsInRaid(HOME) then
    inviteRest = nil
    L.InviteAll(mine)
  end
end)

----------------------------------------------------------------------
-- Popups
----------------------------------------------------------------------
local told = {}

local function postPopup(postKey, d)
  local UI = ns.UI
  if not UI or not UI.Notice then return end
  local leader = L.Leader(postKey)
  local joined = #L.Joins(postKey)
  local buttons = {}
  for _, r in ipairs(L.ROLE_ORDER) do
    buttons[#buttons + 1] = { text = L.ROLES[r], onClick = function() L.Join(postKey, r) end }
  end
  buttons[#buttons + 1] = { text = "Dismiss" }
  UI.Notice({
    id = "lfd", icon = "Interface\\Icons\\INV_Misc_GroupNeedMore", title = "Looking for Dwarf",
    text = "|cffd4a017" .. ns.Name(leader) .. "|r needs " .. d.need .. (d.need == 1 and " dwarf" or " dwarves") ..
      " for |cffffd040" .. d.what .. "|r." .. ((d.note and d.note ~= "") and ("\n" .. d.note) or "") ..
      (joined > 0 and ("  |cff999999(" .. joined .. " signed up)|r") or "") .. "\nSign up as:",
    buttons = buttons,
    timeout = 90,
  })
end

local function joinPopup(joinKey, d)
  local UI = ns.UI
  local post, member = Data.SplitKey(joinKey)
  local p = Data.Get("lfd", post)
  if not p then return end
  local role = L.ROLES[d.role] or "Damage"
  local joined, need = #L.Joins(post), tonumber(p.need) or 1
  ns.Print("|cffd4a017Looking for Dwarf:|r " .. ns.Name(member) .. " (" .. role .. ") wants in on " .. p.what ..
    ". " .. joined .. " of " .. need .. " signed up.")
  if PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then pcall(PlaySound, SOUNDKIT.TELL_MESSAGE) end
  if UI and UI.Notice then
    UI.Notice({
      id = "lfdjoin", icon = "Interface\\Icons\\INV_Misc_GroupLooking", title = "A dwarf answers",
      text = "|cffd4a017" .. ns.Name(member) .. "|r (" .. role .. ") wants in on |cffffd040" .. p.what .. "|r.\n" ..
        joined .. " of " .. need .. " signed up.",
      buttons = { { text = "Invite", onClick = function() L.Invite(member, post) end }, { text = "Later" } },
      timeout = 60,
    })
  end
end

ns.On("DATA_CHANGED", function(coll, key)
  if not key or not ns.settings then return end
  local me = ns.PlayerName()
  if coll == "lfd" then
    local d, rec = Data.Get("lfd", key)
    if not d or told[key] or L.Leader(key) == me then return end
    told[key] = true
    if ns.Now() - (tonumber(d.ts) or 0) > 300 or not L.IsOpen(key, d) then return end
    if d.aid then
      -- one line in chat, no popup
      ns.Print("|cffff4040" .. ns.Name(L.Leader(key)) .. " calls for aid!|r Heed the call in the Looking for Dwarf tab.")
      return
    end
    if ns.settings.lfdPopup == false or L.IsFull(key, d) then return end
    postPopup(key, d)
  elseif coll == "lfdjoin" then
    local d = Data.Get("lfdjoin", key)
    local post, member = Data.SplitKey(key)
    if not d or not post or member == me or L.Leader(post) ~= me or told[key] then return end
    told[key] = true
    joinPopup(key, d)
  end
end)

-- Tidy up my own old posts and sign-ups.
local function sweep()
  if not Data.Ready() then return end
  local me = ns.PlayerName()
  if not me then return end
  for k, d in Data.Each("lfd") do
    if L.Leader(k) == me and ns.Now() - (tonumber(d.ts) or 0) > ttl(d) then L.Close(k, true) end
  end
  for k in Data.Each("lfdjoin") do
    local post, member = Data.SplitKey(k)
    if member == me then
      local p = Data.Get("lfd", post)
      if not p or ns.Now() - (tonumber(p.ts) or 0) > ttl(p) then Data.Delete("lfdjoin", k) end
    end
  end
end
L.Sweep = sweep

ns.On("DATA_READY", function()
  if C_Timer then
    C_Timer.After(20, function() pcall(sweep) end)
    if C_Timer.NewTicker then C_Timer.NewTicker(600, function() pcall(sweep) end) end
  end
end)

-- Fell with the Horde about: point the way to calling for aid.
ns.RegisterEvent("PLAYER_DEAD", function()
  if not ns.settings or not Data.Ready() or not ns.Blood or not ns.Blood.RecentHorde then return end
  if #ns.Blood.RecentHorde(30, 1) == 0 then return end
  ns.Print("You fell with the Horde about. Type |cffffd040/hold aid|r, or use Call for Aid in the Looking for Dwarf tab, to call the guild to your side.")
end)
