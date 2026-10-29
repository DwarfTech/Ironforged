-- Ironforged: challenges.
-- Anyone can take on a challenge at any level; the level they started at is recorded and shown.
-- Custom challenges run on the honor system. Every challenge completes itself at max level;
-- no one marks one completed by hand. The ready-made ones
-- are enforced by the addon: it takes off forbidden armor, keeps you PvP-flagged, closes the auction
-- house, trade and mail, and fails the challenge if a rule is broken anyway.
-- Records: "challenges" key = member .. "#" .. id
--   { name, rules, preset, ts, startLevel, lvl, status = "active"|"failed"|"completed"|"abandoned", reason, ended }
local ADDON, ns = ...
local Data = ns.Data

local C = {}
ns.Challenges = C

C.SLOT_NAMES = { [1] = "Head", [3] = "Shoulder", [4] = "Shirt", [19] = "Tabard", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
  [9] = "Wrist", [10] = "Hands", [15] = "Back" }

C.PRESETS = {
  slayer = { name = "Slayer", noSlots = { 3, 4, 5, 19 }, pvp = true,
    rules = "No chest or shoulder armor, no shirt or tabard, and stay flagged for PvP all the way to max level." },
  selfmade = { name = "Outlander", noAH = true, noTrade = true, noMail = true,
    rules = "No auction house, no trading and no mail. Everything you have, you earned." },
  onelife = { name = "One Life", oneLife = true,
    rules = "Die once and the challenge is over." },
  dwarffound = { name = "Dwarf Found", dwarfOnly = true,
    rules = "Trade and group only with dwarves. Everyone else is a stranger." },
  drunken = { name = "Drunken", drunk = true, fromLevel = 10,
    rules = "Stay drunk all the way to max level. From level 10 on, when your buzz wears off you have 30 seconds to drink, or the challenge fails. Carry plenty of ale." },
}
C.ORDER = { "slayer", "selfmade", "onelife", "dwarffound", "drunken" }

C.STATUS = {
  active = "|cffffd040Under way|r", completed = "|cff40ff40Completed|r",
  failed = "|cffff4040Failed|r", abandoned = "|cff999999Gave up|r",
}

local function level() return (UnitLevel and UnitLevel("player")) or 0 end

function C.MaxLevel()
  local m = GetMaxPlayerLevel and GetMaxPlayerLevel()
  if type(m) ~= "number" or m < 10 then m = 60 end
  return m
end

----------------------------------------------------------------------
-- Reading
----------------------------------------------------------------------
-- All challenges of current guildmates: { key, member, data }
function C.All()
  local out = {}
  for k, d in Data.Each("challenges") do
    local member = Data.SplitKey(k)
    if member and ns.roster[member] and type(d.name) == "string" then out[#out + 1] = { key = k, member = member, data = d } end
  end
  table.sort(out, function(a, b) return (a.data.ts or 0) > (b.data.ts or 0) end)
  return out
end

-- One member's challenges, newest first. Indexed once and kept until data or the roster changes.
local byMember
ns.On("DATA_CHANGED", function() byMember = nil end)
ns.On("ROSTER", function() byMember = nil end)
function C.Of(member)
  if not byMember then
    byMember = {}
    for _, c in ipairs(C.All()) do
      byMember[c.member] = byMember[c.member] or {}
      table.insert(byMember[c.member], c)
    end
  end
  return byMember[member] or {}
end

-- My active challenges with a ready-made rule set: { key, data, preset }
function C.MyPresets()
  local me = ns.PlayerName()
  local out = {}
  if not me or not Data.Ready() then return out end
  for k, d in Data.Each("challenges") do
    if Data.SplitKey(k) == me and d.status == "active" and d.preset and C.PRESETS[d.preset] then
      out[#out + 1] = { key = k, data = d, preset = C.PRESETS[d.preset] }
    end
  end
  return out
end

-- The ones being enforced right now: some only hold you to their rules from a certain level.
function C.MyEnforced()
  local out = {}
  for _, c in ipairs(C.MyPresets()) do
    if level() >= (c.preset.fromLevel or 1) then out[#out + 1] = c end
  end
  return out
end

-- Some challenges are for certain classes only.
local function myClass()
  local ok, _, file = pcall(UnitClass or function() end, "player")
  if ok and type(file) == "string" and not (issecretvalue and issecretvalue(file)) then return file end
end
C.MyClass = myClass

function C.ClassAllowed(preset)
  if not preset.classes then return true end
  local cls = myClass()
  return cls == nil or preset.classes[cls] == true
end

-- Ready-made challenges this character may take on, in order.
function C.Available()
  local out = {}
  for _, id in ipairs(C.ORDER) do
    if C.PRESETS[id] and C.ClassAllowed(C.PRESETS[id]) then out[#out + 1] = id end
  end
  return out
end

----------------------------------------------------------------------
-- Writing
----------------------------------------------------------------------
local function update(key, fields)
  local d = Data.Get("challenges", key)
  if not d then return false end
  local n = {}
  for k, v in pairs(d) do n[k] = v end
  for k, v in pairs(fields) do n[k] = v end
  return Data.Put("challenges", key, n, true)
end

function C.Start(presetId, name, rules)
  local me = ns.PlayerName()
  if not me then return false end
  local preset = presetId and C.PRESETS[presetId]
  if presetId and not preset then return false end
  if preset then
    if not C.ClassAllowed(preset) then ns.Print(preset.name .. " isn't a challenge for your class."); return false end
    for _, c in ipairs(C.MyPresets()) do
      if c.data.preset == presetId then ns.Print("You're already on the " .. preset.name .. " challenge."); return false end
    end
    name, rules = preset.name, preset.rules
  else
    name, rules = ns.Clean(name, 40), ns.Clean(rules, 400)
    if name == "" then ns.Print("Give the challenge a name."); return false end
  end
  local key = me .. "#" .. string.format("%x", ns.Stamp())
  local ok = Data.Put("challenges", key, { name = name, rules = rules, preset = presetId, ts = ns.Now(),
    startLevel = level(), lvl = level(), xp = (UnitXP and UnitXP("player")) or 0, seen = ns.Now(), status = "active" })
  if ok then
    ns.Print("|cffd4a017Challenge accepted:|r " .. name .. ". " .. (preset and "The addon will hold you to it." or "On your honor."))
    if preset then C.Enforce() end
  end
  return ok and key
end

function C.Fail(key, reason)
  local d = Data.Get("challenges", key)
  if not d or d.status ~= "active" then return end
  update(key, { status = "failed", reason = reason, ended = ns.Now(), lvl = level() })
  ns.Print("|cffff4040Challenge failed:|r " .. d.name .. ". " .. (reason or ""))
  if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
  if ns.UI and ns.UI.Notice then
    ns.UI.Notice({ id = "challenge", icon = "Interface\\Icons\\Ability_Creature_Cursed_02", title = "Challenge failed",
      text = "|cffffd040" .. d.name .. "|r is over.\n" .. (reason or ""), buttons = { { text = "So be it" } } })
  end
end

function C.Complete(key, atLevel)
  local d = Data.Get("challenges", key)
  if not d or d.status ~= "active" then return end
  if update(key, { status = "completed", ended = ns.Now(), lvl = atLevel or level() }) then
    ns.Print("|cff40ff40Challenge completed:|r " .. d.name .. "! The hold will hear of this.")
  end
end

-- A member's challenges worth showing on tooltips and the roster: under way and completed.
function C.Showing(member)
  local out = {}
  for _, ch in ipairs(C.Of(member)) do
    if ch.data.status == "active" or ch.data.status == "completed" then out[#out + 1] = ch end
  end
  return out
end

function C.Label(d)
  return d.name .. " (from level " .. tostring(d.startLevel or "?") .. (d.status == "completed" and ", completed" or "") .. ")"
end

function C.Abandon(key)
  local d = Data.Get("challenges", key)
  if not d or d.status ~= "active" then return end
  update(key, { status = "abandoned", ended = ns.Now(), lvl = level() })
end

function C.Remove(key) return Data.Delete("challenges", key) end

----------------------------------------------------------------------
-- Enforcing the ready-made rules
----------------------------------------------------------------------
local GRACE = 60      -- seconds a forbidden item may stay on (full bags, combat) before the challenge fails
local wornSince = {}  -- slot -> time first seen on

local function freeBagSlot()
  local CC = C_Container
  for bag = 0, 4 do
    local n = (CC and CC.GetContainerNumSlots and CC.GetContainerNumSlots(bag)) or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
    for s = 1, n do
      local info
      if CC and CC.GetContainerItemInfo then info = CC.GetContainerItemInfo(bag, s)
      elseif GetContainerItemInfo then info = GetContainerItemInfo(bag, s) end
      if not info then return bag, s end
    end
  end
end

-- Move what's in an equipment slot into the bags. Returns true if it went.
local function unequip(slot)
  if InCombatLockdown and InCombatLockdown() then return false end
  if not PickupInventoryItem then return false end
  local bag, s = freeBagSlot()
  if not bag then return false end
  if ClearCursor then ClearCursor() end
  local ok = pcall(PickupInventoryItem, slot)
  if not ok then return false end
  local CC = C_Container
  if CC and CC.PickupContainerItem then pcall(CC.PickupContainerItem, bag, s)
  elseif PickupContainerItem then pcall(PickupContainerItem, bag, s) end
  if CursorHasItem and CursorHasItem() and ClearCursor then ClearCursor() end
  return true
end

local function worn(slot)
  return GetInventoryItemID and GetInventoryItemID("player", slot) ~= nil
end

C.GRACE = GRACE
C.Unequip = unequip
C.ENFORCERS = {} -- extra checks other files add: fn(challenge)

-- Equipment a rule set forbids right now: { [slot] = { what = "shield", fail = "a shield" } }
local function forbiddenGear(p)
  local out = {}
  for _, slot in ipairs(p.noSlots or {}) do
    if worn(slot) then
      local bare = { [4] = "shirt", [19] = "tabard" } -- not armor, so named on their own
      local what = bare[slot] or ((C.SLOT_NAMES[slot] or "that"):lower() .. " armor")
      out[slot] = { what = what, fail = bare[slot] and ("a " .. bare[slot]) or what }
    end
  end
  if C.GearRules then
    for slot, w in pairs(C.GearRules(p)) do out[slot] = w end
  end
  return out
end

local warned = {}
function C.Enforce()
  local active = C.MyEnforced()
  if #active == 0 then wipe(wornSince); return end
  local now = GetTime and GetTime() or 0
  local seen = {}
  for _, c in ipairs(active) do
    local p = c.preset
    for slot, w in pairs(forbiddenGear(p)) do
      seen[slot] = true
      if unequip(slot) then
        ns.Print("|cffd4a017" .. p.name .. ":|r no " .. w.what .. ". It's back in your bags.")
        wornSince[slot] = nil
      else
        wornSince[slot] = wornSince[slot] or now
        if not warned[slot] then
          warned[slot] = true
          ns.Print("|cffff4040" .. p.name .. ":|r take off your " .. w.what .. " within a minute or the challenge fails" ..
            ((freeBagSlot() == nil) and " (your bags are full)." or "."))
        end
        if now - wornSince[slot] >= GRACE then C.Fail(c.key, "Wore " .. w.fail .. " at level " .. level() .. ".") end
      end
    end
    if p.pvp then C.KeepFlagged(p.name, c.key) end
    for _, f in ipairs(C.ENFORCERS) do f(c) end
  end
  for slot in pairs(wornSince) do if not seen[slot] then wornSince[slot] = nil end end
  for slot in pairs(warned) do if not seen[slot] then warned[slot] = nil end end
end

-- Slayer: PvP stays on. Blizzard only lets the player switch PvP on or off (an addon that tries is
-- blocked), so the addon watches instead: when you're not flagged it warns you, and if you're
-- still not flagged a minute later the challenge fails. "Desired" is the setting the game
-- remembers; the flag itself lingers for a few minutes after it's turned off, so the setting
-- is what gets checked.
C.PVP_GRACE = 60
local unflaggedSince

local function isFlagged()
  local desired = GetPVPDesired and GetPVPDesired()
  local flagged = UnitIsPVP and UnitIsPVP("player")
  return desired, flagged
end

local function pvpOn()
  local desired, flagged = isFlagged()
  if desired ~= nil then return desired and true or false end
  return flagged and true or false
end
C.PvPOn = pvpOn

function C.KeepFlagged(name, key)
  if pvpOn() then
    if unflaggedSince then ns.Print("|cffd4a017" .. name .. ":|r flagged for PvP. Keep it that way.") end
    unflaggedSince = nil
    if ns.UI and ns.UI.HideNotice then ns.UI.HideNotice("pvp") end
    return
  end
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
  local now = GetTime and GetTime() or 0
  if unflaggedSince then
    if now - unflaggedSince >= C.PVP_GRACE then
      unflaggedSince = nil
      if key then C.Fail(key, "Wasn't flagged for PvP at level " .. level() .. ".") end
    end
    return
  end
  unflaggedSince = now
  ns.Print("|cffff4040" .. name .. ":|r you're not flagged for PvP. Type |cffffd040/pvp|r within " .. C.PVP_GRACE ..
    " seconds or the challenge fails.")
  if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
  if ns.UI and ns.UI.Notice then
    ns.UI.Notice({ id = "pvp", icon = "Interface\\Icons\\Ability_DualWield", title = name .. ": flag for PvP",
      text = "Type |cffffd040/pvp|r in chat within " .. C.PVP_GRACE .. " seconds, or the " .. name .. " challenge fails.",
      buttons = { { text = "OK" } }, timeout = C.PVP_GRACE })
  end
  if C_Timer then C_Timer.After(C.PVP_GRACE + 1, function() pcall(C.Enforce) end) end
end

-- /hold pvp: what the game reports about your PvP flag. It only reads; it never changes anything.
function C.PvPReport()
  local desired, flagged = isFlagged()
  ns.Print("PvP: setting on = " .. tostring(desired) .. ", flagged right now = " .. tostring(flagged) ..
    ". Slayer counts you as " .. (pvpOn() and "|cff40ff40flagged|r." or "|cffff4040not flagged|r. Type /pvp."))
end

-- Notice at once when the player turns PvP off. Hooks only watch; they never call anything protected.
local function pvpChanged()
  if C_Timer then C_Timer.After(0.5, function() pcall(C.Enforce) end) else pcall(C.Enforce) end
end
if hooksecurefunc then
  if TogglePVP then hooksecurefunc("TogglePVP", pvpChanged) end
  if SetPVP then hooksecurefunc("SetPVP", pvpChanged) end
end

local function forbids(field)
  for _, c in ipairs(C.MyEnforced()) do if c.preset[field] then return c.preset.name end end
end

ns.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() if C_Timer then C_Timer.After(0.2, C.Enforce) else C.Enforce() end end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() C.Enforce() end)
ns.RegisterEvent("PLAYER_FLAGS_CHANGED", function(unit) if unit == "player" then C.Enforce() end end)
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function() if C_Timer then C_Timer.After(5, C.Enforce) end end)

ns.RegisterEvent("AUCTION_HOUSE_SHOW", function()
  local name = forbids("noAH")
  if not name then return end
  if C_AuctionHouse and C_AuctionHouse.CloseAuctionHouse then pcall(C_AuctionHouse.CloseAuctionHouse)
  elseif CloseAuctionHouse then pcall(CloseAuctionHouse) end
  ns.Print("|cffd4a017" .. name .. ":|r no auction house for you.")
end)
local function dwarfRace(unit)
  if not UnitRace then return nil end
  local ok, _, raceFile = pcall(UnitRace, unit)
  if not ok or type(raceFile) ~= "string" or (issecretvalue and issecretvalue(raceFile)) then return nil end
  return ns.Gear.DWARF[raceFile] == true
end

ns.RegisterEvent("TRADE_SHOW", function()
  local name = forbids("noTrade")
  if name then
    if CancelTrade then pcall(CancelTrade) end
    ns.Print("|cffd4a017" .. name .. ":|r no trading. The trade was cancelled.")
    return
  end
  name = forbids("dwarfOnly")
  if name and dwarfRace("NPC") == false then
    if CancelTrade then pcall(CancelTrade) end
    ns.Print("|cffd4a017" .. name .. ":|r you trade only with dwarves. The trade was cancelled.")
  end
end)

-- Dwarf Found: no non-dwarves in your group.
local strangerSince
local leavingUntil = 0 -- after leaving, the game takes a moment to drop the group; stay quiet meanwhile
local GROUP_GRACE = 15
local function groupUnits()
  local out = {}
  if IsInRaid and IsInRaid() then
    for i = 1, 40 do out[#out + 1] = "raid" .. i end
  else
    for i = 1, 4 do out[#out + 1] = "party" .. i end
  end
  return out
end

-- While you are in an instance group (group finder, battleground) the party units describe that
-- group, so a home party you also belong to is checked by name instead.
local function homePartyStranger()
  if not GetHomePartyInfo then return nil end
  local ok, names = pcall(GetHomePartyInfo)
  if not ok or type(names) ~= "table" then return nil end
  for _, n in ipairs(names) do
    local full = ns.Name(n)
    if ns.roster[full] and ns.Gear.IsDwarf(full) == false then return ns.Name(full) end
  end
  return nil
end

function C.CheckGroup()
  local name = forbids("dwarfOnly")
  if not name or not (IsInGroup and IsInGroup()) then strangerSince = nil; leavingUntil = 0; return end
  if (GetTime and GetTime() or 0) < leavingUntil then return end
  -- Strangers are fine in an instance group (the game picked them). Only the group you built must be all dwarves.
  local inInstance = LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
  local stranger, category
  if inInstance then
    stranger, category = homePartyStranger(), LE_PARTY_CATEGORY_HOME
  else
    for _, u in ipairs(groupUnits()) do
      if UnitExists and UnitExists(u) and not (UnitIsUnit and UnitIsUnit(u, "player")) and dwarfRace(u) == false then
        stranger = ns.UnitDisplayName(u) or "someone"
        break
      end
    end
  end
  if not stranger then strangerSince = nil; return end
  local now = GetTime and GetTime() or 0
  if not strangerSince then
    strangerSince = now
    ns.Print("|cffff4040" .. name .. ":|r " .. stranger .. " is no dwarf. Get them out of the group, or you leave it in " .. GROUP_GRACE .. " seconds.")
    if C_Timer then C_Timer.After(GROUP_GRACE + 0.5, C.CheckGroup) end
    return
  end
  if now - strangerSince >= GROUP_GRACE then
    strangerSince = nil
    leavingUntil = now + 10
    if category then
      -- leave only the home party, never the dungeon group
      if C_PartyInfo and C_PartyInfo.LeaveParty then pcall(C_PartyInfo.LeaveParty, category) end
    else
      local leave = (C_PartyInfo and C_PartyInfo.LeaveParty) or LeaveParty
      if leave then pcall(leave) end
    end
    ns.Print("|cffd4a017" .. name .. ":|r leaving the group. You walk only with dwarves.")
  end
end
ns.RegisterEvent("GROUP_ROSTER_UPDATE", function() C.CheckGroup() end)

-- Turn down invites from guildmates known not to be dwarves.
ns.RegisterEvent("PARTY_INVITE_REQUEST", function(inviter)
  local name = forbids("dwarfOnly")
  if not name or type(inviter) ~= "string" then return end
  local full = ns.Name(inviter)
  if ns.roster[full] and ns.Gear.IsDwarf(full) == false then
    if DeclineGroup then pcall(DeclineGroup) end
    if StaticPopup_Hide then pcall(StaticPopup_Hide, "PARTY_INVITE") end
    ns.Print("|cffd4a017" .. name .. ":|r turned down " .. ns.Name(inviter) .. "'s invite. Dwarves only.")
  end
end)
ns.RegisterEvent("MAIL_SHOW", function()
  local name = forbids("noMail")
  if not name then return end
  if CloseMail then pcall(CloseMail) end
  ns.Print("|cffd4a017" .. name .. ":|r no mail. The mailbox stays shut.")
end)
ns.RegisterEvent("PLAYER_DEAD", function()
  for _, c in ipairs(C.MyEnforced()) do
    if c.preset.oneLife then C.Fail(c.key, "Died at level " .. level() .. ".") end
  end
end)
ns.RegisterEvent("PLAYER_LEVEL_UP", function(newLevel)
  local me = ns.PlayerName()
  local lvl = tonumber(newLevel) or level()
  for _, c in ipairs(C.MyPresets()) do
    if c.preset.fromLevel and c.preset.fromLevel == lvl then
      ns.Print("|cffd4a017" .. c.preset.name .. ":|r level " .. lvl .. "! From now on the addon holds you to it.")
    end
  end
  if C_Timer then C_Timer.After(1, function() pcall(C.Enforce) end) end
  for k, d in Data.Each("challenges") do
    if Data.SplitKey(k) == me and d.status == "active" then
      if lvl >= C.MaxLevel() then
        C.Complete(k, lvl)
      else
        update(k, { lvl = lvl, xp = 0, seen = ns.Now() })
      end
    end
  end
  C.SaveSnapshot()
end)

----------------------------------------------------------------------
-- Audit: playing a challenge with Ironforged turned off.
-- Experience only goes up by playing, so each character keeps a snapshot of its level and XP:
-- on this computer (saved when you log out) and in the synced challenge record (every few minutes
-- and at each level). If you log in with more XP than the addon last saw, you played without it,
-- and a note is added to each challenge under way. Nothing is announced.
----------------------------------------------------------------------
local function xpNow() return level(), (UnitXP and UnitXP("player")) or 0 end

-- Level and XP at the moment of logging in, before anything this session could change them.
local loginLv, loginXp
local audited = false
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
  if not loginLv and level() > 0 then loginLv, loginXp = xpNow() end
end)

function C.SaveSnapshot()
  if not audited then return end -- keep last session's snapshot until it has been checked
  local me = ns.PlayerName()
  if not me or not ns.db then return end
  ns.db.xpSnap = ns.db.xpSnap or {}
  local lv, xp = xpNow()
  ns.db.xpSnap[me] = { lv = lv, xp = xp, t = ns.Now() }
end

local lastPush = 0
local function pushProgress(force)
  local now = GetTime and GetTime() or 0
  if not force and now - lastPush < 300 then return end
  lastPush = now
  local me = ns.PlayerName()
  local lv, xp = xpNow()
  for k, d in Data.Each("challenges") do
    if Data.SplitKey(k) == me and d.status == "active" and (d.lvl ~= lv or d.xp ~= xp) then
      update(k, { lvl = lv, xp = xp, seen = ns.Now() })
    end
  end
end

function C.Audit(force)
  if audited and not force then return end
  local me = ns.PlayerName()
  if not me or not Data.Ready() or level() < 1 then return end
  audited = true
  local lv, xp = loginLv, loginXp
  if force or not lv then lv, xp = xpNow() end
  local snap = ns.db and ns.db.xpSnap and ns.db.xpSnap[me]
  for k, d in Data.Each("challenges") do
    if Data.SplitKey(k) == me and d.status == "active" then
      -- compare with whichever the addon saw last: this computer's snapshot or the synced record
      local refLv, refXp, exact
      if snap and (snap.t or 0) >= (tonumber(d.seen or d.ts) or 0) then
        refLv, refXp, exact = snap.lv, snap.xp, true
      else
        refLv, refXp, exact = tonumber(d.lvl), tonumber(d.xp), false -- another computer: go by level
      end
      if refLv and (lv > refLv or (exact and lv == refLv and xp > (refXp or 0))) then
        -- a quiet note on the challenge itself; nothing is announced
        local note = "Played without Ironforged: level " .. refLv .. " to " .. lv .. " (" .. ns.FormatDate(ns.Now()) .. ")."
        local notes = (type(d.audit) == "string" and d.audit ~= "") and (d.audit .. "\n" .. note) or note
        if #notes > 400 then notes = notes:sub(-400) end
        update(k, { flags = (tonumber(d.flags) or 0) + 1, audit = notes, lvl = lv, xp = xp, seen = ns.Now() })
      end
    end
  end
  C.SaveSnapshot()
  pushProgress(true)
end

function C.Flagged(d) return (tonumber(d.flags) or 0) > 0 end

ns.RegisterEvent("PLAYER_XP_UPDATE", function(unit)
  if unit and unit ~= "player" then return end
  C.SaveSnapshot()
  pushProgress(false)
end)
ns.RegisterEvent("PLAYER_LOGOUT", function() C.SaveSnapshot() end)

-- Ready-made challenges keep today's name and wording (Self-Made became Outlander, rules get
-- reworded). Each member's client rewrites its own records.
function C.RefreshOldRules()
  local me = ns.PlayerName()
  if not me then return end
  for k, d in Data.Each("challenges") do
    local p = d.preset and C.PRESETS[d.preset]
    if Data.SplitKey(k) == me and p and (d.name ~= p.name or d.rules ~= p.rules) then
      update(k, { name = p.name, rules = p.rules })
    end
  end
end

ns.On("DATA_READY", function()
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(10, function() pcall(C.Enforce); pcall(C.CheckGroup) end) end
  if C_Timer then C_Timer.After(15, function() pcall(C.RefreshOldRules) end) end
  if C_Timer then C_Timer.After(20, function() pcall(C.Audit) end) end
end)

----------------------------------------------------------------------
-- Tell the guild (addon users) when a challenge starts, fails or is completed. No chat.
----------------------------------------------------------------------
local lastStatus = {}
ns.On("DATA_CHANGED", function(coll, key)
  if coll ~= "challenges" or not key then return end
  local d = Data.Get("challenges", key)
  local member = Data.SplitKey(key)
  if not d or member == ns.PlayerName() or lastStatus[key] == d.status then lastStatus[key] = d and d.status; return end
  lastStatus[key] = d.status
  if ns.Now() - (tonumber(d.ended or d.ts) or 0) > 600 then return end
  local who = ns.Name(member)
  if d.status == "active" then
    ns.Print("|cffd4a017Challenge:|r " .. who .. " takes on " .. d.name .. ".")
  elseif d.status == "failed" then
    ns.Print("|cffd4a017Challenge:|r " .. who .. " failed " .. d.name .. ". " .. (d.reason or ""))
  elseif d.status == "completed" then
    ns.Print("|cffd4a017Challenge:|r " .. who .. " completed " .. d.name .. "! Raise a mug.")
  end
end)
