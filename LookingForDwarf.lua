-- Ironforged: Looking for Dwarf, a group board inside the guild.
-- A leader posts what they need ("Need 2 for Gnomeregan"); guildmates with the addon get a quiet
-- popup and sign up with a role; the leader invites them. Nothing goes to chat.
-- A post for a dungeon on the list carries its level range, and the popup only comes up for
-- guildmates inside that range. Anything else pops up for everyone, as before.
-- A call for aid is a post too (aid = true): a dwarf beset by the Horde asks for up to 39 more,
-- a full raid. Guildmates get one line in their chat window, no popup, and answer in the tab.
--   "lfd"     key = leader .. "#" .. id       { what, need, note, ts, aid, dungeon, min, max }
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

-- WoW: Forever's dungeons and raids with the level ranges from the game's own group finder,
-- lowest first: the original dungeons (Scarlet Monastery, Dire Maul and Stratholme by wing) and
-- Forever's new ones. Typing a name or a common short name ("gnomer", "brd", "sm lib") picks it too.
L.DUNGEONS = {
  { key = "rfc", name = "Ragefire Chasm", min = 13, max = 18, alias = { "rfc", "ragefire" } },
  { key = "hot", name = "Hall of Thanes", min = 13, max = 20, alias = { "hall of thanes", "thanes", "hot" } },
  { key = "rol", name = "Ruins of Lordaeron", min = 15, max = 22, alias = { "ruins of lordaeron", "lordaeron", "rol" } },
  { key = "wc", name = "Wailing Caverns", min = 15, max = 24, alias = { "wc", "wailing" } },
  { key = "dm", name = "The Deadmines", min = 17, max = 26, alias = { "dm", "vc", "deadmines", "deadmine" } },
  { key = "sfk", name = "Shadowfang Keep", min = 20, max = 30, alias = { "sfk", "shadowfang" } },
  { key = "bfd", name = "Blackfathom Deeps", min = 24, max = 32, alias = { "bfd", "blackfathom" } },
  { key = "stocks", name = "The Stockade", min = 25, max = 29, alias = { "stocks", "stockade", "stockades" } },
  { key = "excav", name = "Excavation Site: Wetlands", min = 26, max = 33, alias = { "excavation site", "excavation", "excav", "dig site" } },
  { key = "dal", name = "City of Dalaran", min = 28, max = 35, alias = { "dalaran", "city of dalaran", "dal" } },
  { key = "rfk", name = "Razorfen Kraul", min = 29, max = 38, alias = { "rfk", "kraul" } },
  { key = "gnomer", name = "Gnomeregan", min = 29, max = 38, alias = { "gnomer", "gnomeregan" } },
  { key = "smgy", name = "Scarlet Monastery: Graveyard", min = 30, max = 38, alias = { "sm gy", "smgy", "graveyard", "sm graveyard" } },
  { key = "smlib", name = "Scarlet Monastery: Library", min = 33, max = 41, alias = { "sm lib", "smlib", "library", "sm library" } },
  { key = "drowned", name = "The Drowned City", min = 35, max = 42, alias = { "drowned city", "drowned" } },
  { key = "smarm", name = "Scarlet Monastery: Armory", min = 36, max = 44, alias = { "sm arm", "smarm", "armory", "sm armory", "armoury" } },
  { key = "rfd", name = "Razorfen Downs", min = 37, max = 46, alias = { "rfd", "downs" } },
  { key = "smcath", name = "Scarlet Monastery: Cathedral", min = 38, max = 46, alias = { "sm cath", "smcath", "cathedral", "sm cathedral", "cath" } },
  { key = "kroldok", name = "Krol'Dok Stronghold", min = 40, max = 47, alias = { "krol'dok", "kroldok", "krol dok", "krol'dok stronghold" } },
  { key = "ulda", name = "Uldaman", min = 41, max = 51, alias = { "ulda", "uld", "uldaman" } },
  { key = "zf", name = "Zul'Farrak", min = 44, max = 54, alias = { "zf", "zul'farrak", "zulfarrak", "zul farrak" } },
  { key = "mara", name = "Maraudon", min = 46, max = 55, alias = { "mara", "maraudon" } },
  { key = "alcaz", name = "Alcaz Island Prison", min = 48, max = 55, alias = { "alcaz", "alcaz island", "alcaz prison", "aip" } },
  { key = "st", name = "Sunken Temple", min = 50, max = 60, alias = { "st", "sunken temple", "temple of atal'hakkar", "atal'hakkar" } },
  { key = "brd", name = "Blackrock Depths", min = 52, max = 60, alias = { "brd", "blackrock depths" } },
  { key = "dme", name = "Dire Maul: East", min = 54, max = 60, alias = { "dme", "dm east", "dire maul east", "dire maul", "diremaul" } },
  { key = "lbrs", name = "Lower Blackrock Spire", min = 55, max = 60, alias = { "lbrs", "lower blackrock", "lower spire" } },
  { key = "blackmaw", name = "Blackmaw Hold", min = 55, max = 60, alias = { "blackmaw", "blackmaw hold" } },
  { key = "dmw", name = "Dire Maul: West", min = 56, max = 60, alias = { "dmw", "dm west", "dire maul west" } },
  { key = "dmn", name = "Dire Maul: North", min = 56, max = 60, alias = { "dmn", "dm north", "dire maul north", "tribute", "dm tribute", "dire maul tribute" } },
  { key = "shapers", name = "Shaper's Terrace", min = 58, max = 60, alias = { "shaper's terrace", "shapers terrace", "shapers", "shaper's" } },
  { key = "stratlive", name = "Stratholme: Main Gate", min = 58, max = 60, alias = { "strat", "stratholme", "strath", "strat live", "strat living", "main gate" } },
  { key = "stratud", name = "Stratholme: Service Gate", min = 58, max = 60, alias = { "strat ud", "strat undead", "service gate" } },
  { key = "scholo", name = "Scholomance", min = 58, max = 60, alias = { "scholo", "scholomance" } },
  { key = "ubrs", name = "Upper Blackrock Spire", min = 59, max = 60, alias = { "ubrs", "upper blackrock", "upper spire" } },
  -- raids
  { key = "barrow", name = "Barrow Deeps", min = 60, max = 60, alias = { "barrow deeps", "barrow" } },
  { key = "hyjal", name = "Hyjal Summit", min = 60, max = 60, alias = { "hyjal", "hyjal summit" } },
  { key = "ony", name = "Onyxia's Lair", min = 60, max = 60, alias = { "ony", "onyxia", "onyxia's lair" } },
}
local byKey = {}
for _, dg in ipairs(L.DUNGEONS) do byKey[dg.key] = dg end
function L.Dungeon(key) return key and byKey[key] or nil end

-- "Gnomeregan (29-38)", or "Molten Core (60)".
function L.DungeonLabel(dg)
  if not dg then return "" end
  return dg.name .. " (" .. (dg.min == dg.max and dg.min or (dg.min .. "-" .. dg.max)) .. ")"
end

-- The dungeon a post's text names, if any: the full name, or a short name as a whole word
-- ("gnomer run", "BRD jailbreak", "need tank for sm lib").
function L.MatchDungeon(text)
  if type(text) ~= "string" then return nil end
  local t = " " .. (text:lower():gsub("[%p]", function(c) return c == "'" and "'" or " " end):gsub("%s+", " ")) .. " "
  local best, bestLen
  for _, dg in ipairs(L.DUNGEONS) do
    local names = { (dg.name:lower():gsub("[%p]", function(c) return c == "'" and "'" or " " end):gsub("%s+", " ")) }
    for _, a in ipairs(dg.alias) do names[#names + 1] = a end
    for _, n in ipairs(names) do
      if t:find(" " .. n .. " ", 1, true) and (not bestLen or #n > bestLen) then best, bestLen = dg, #n end
    end
  end
  return best
end

-- Is this level inside the post's range? Posts with no range are for everyone.
function L.InRange(d, level)
  if type(d) ~= "table" or not tonumber(d.min) or not tonumber(d.max) then return true end
  level = tonumber(level)
  if not level or level < 1 then return true end
  return level >= tonumber(d.min) and level <= tonumber(d.max)
end

local function myLevel()
  local ok, lv = pcall(UnitLevel, "player")
  if ok and type(lv) == "number" and not (issecretvalue and issecretvalue(lv)) then return lv end
end
L.MyLevel = myLevel

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
  local dg = not aid and L.MatchDungeon(what) or nil
  if dg then d.dungeon, d.min, d.max = dg.key, dg.min, dg.max end
  if Data.Put("lfd", key, d) then
    if aid then
      ns.Print("|cffff4040You call for aid!|r Your guildmates will see it in the Looking for Dwarf tab.")
    else
      ns.Print("Posted: looking for " .. need .. (need == 1 and " dwarf" or " dwarves") .. " for " .. what ..
        (dg and (". Guildmates level " .. (dg.min == dg.max and dg.min or (dg.min .. " to " .. dg.max)) .. " get the popup.") or "."))
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

-- Room is needed beyond a party of five: the group I have now plus everyone the post asks for.
local function wantsRaid(postKey)
  local d = postKey and Data.Get("lfd", postKey)
  if not d then return false end
  local have = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  return math.max(1, have) + (tonumber(d.need) or 0) > 5
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
local invited = {} -- postKey -> { member = true }: invites already sent this session
function L.InviteAll(postKey)
  local d = Data.Get("lfd", postKey)
  local raid = wantsRaid(postKey)
  if raid then convertToRaid() end
  local room = (raid and not (IsInRaid and IsInRaid(HOME)) and not (IsInGroup and IsInGroup(HOME))) and 4 or nil
  local cap = tonumber(d and d.need) or 39
  invited[postKey] = invited[postKey] or {}
  local n, left, taken = 0, 0, 0
  for _, j in ipairs(L.Joins(postKey)) do
    if taken >= cap then break end -- first come, first served up to what the post asked for
    if ns.roster[j.member] and ns.roster[j.member].online then
      taken = taken + 1
      if grouped(j.member) or invited[postKey][j.member] then
        -- already in, or already asked
      elseif room and n >= room then
        left = left + 1
      elseif L.Invite(j.member, postKey) then
        invited[postKey][j.member] = true
        n = n + 1
      end
    end
  end
  if left > 0 then
    inviteRest = postKey
    ns.Print("Inviting the first four. The other " .. left .. " follow once your party forms and becomes a raid.")
  end
  if n == 0 and left == 0 then ns.Print("No one new to invite.") end
end

-- Only while invites are waiting on the party to form: turn it into a raid, then send the rest.
ns.RegisterEvent("GROUP_ROSTER_UPDATE", function()
  local mine = L.MyPost()
  if not mine or inviteRest ~= mine then return end
  convertToRaid()
  if IsInRaid and IsInRaid(HOME) then
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
      " for |cffffd040" .. d.what .. "|r" ..
      (tonumber(d.min) and (" (level " .. (d.min == d.max and d.min or (d.min .. "-" .. d.max)) .. ")") or "") .. "." .. ((d.note and d.note ~= "") and ("\n" .. d.note) or "") ..
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
    -- a dungeon post pops up only for guildmates inside its level range (it's still in the tab for all)
    if not L.InRange(d, myLevel()) then return end
    L.ShowWhenFree(key, false)
  elseif coll == "lfdjoin" then
    local d = Data.Get("lfdjoin", key)
    local post, member = Data.SplitKey(key)
    if not d or not post or member == me or L.Leader(post) ~= me or told[key] then return end
    told[key] = true
    L.ShowWhenFree(key, true)
  end
end)

----------------------------------------------------------------------
-- Popups wait until you're out of combat, and, if you've turned them off for instances, until
-- you're out of the dungeon or battleground. Then the ones still worth answering come up.
----------------------------------------------------------------------
local waiting = {} -- key -> true for a sign-up to me (lfdjoin), false for a group post (lfd)

local function inCombat()
  if InCombatLockdown and InCombatLockdown() then return true end
  local ok, c = pcall(UnitAffectingCombat, "player")
  return ok and c == true
end

local function inInstance()
  if not IsInInstance then return false end
  local ok, inside, kind = pcall(IsInInstance)
  return ok and (inside == true or (type(kind) == "string" and kind ~= "none"))
end
L.InInstance = inInstance

-- Can this popup show right now?
local function free(isJoin)
  if inCombat() then return false end
  if not isJoin and ns.settings.lfdPopupInstance == false and inInstance() then return false end
  return true
end

local function showNow(key, isJoin)
  if isJoin then
    local d = Data.Get("lfdjoin", key)
    local post = Data.SplitKey(key)
    if d and post and L.IsOpen(post) then joinPopup(key, d) end
  else
    local d = Data.Get("lfd", key)
    if d and L.IsOpen(key, d) and not L.IsFull(key, d) and not L.MyJoin(key)
      and ns.settings.lfdPopup ~= false and L.InRange(d, myLevel()) then
      postPopup(key, d)
    end
  end
end

function L.ShowWhenFree(key, isJoin)
  if free(isJoin) then showNow(key, isJoin) else waiting[key] = isJoin end
end

local function flush()
  for key, isJoin in pairs(waiting) do
    if free(isJoin) then waiting[key] = nil; showNow(key, isJoin) end
  end
end
L.FlushWaiting = flush
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() if C_Timer then C_Timer.After(1, flush) else flush() end end)
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function() if C_Timer then C_Timer.After(3, flush) else flush() end end)

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
