-- Ironforged: challenges.
-- Anyone can take on a challenge at any level; the level they started at is recorded and shown.
-- Custom challenges run on the honor system. Only officers mark a custom challenge completed;
-- ready-made ones complete themselves at max level. The ready-made ones
-- are enforced by the addon: it takes off forbidden armor, keeps you PvP-flagged, closes the auction
-- house, trade and mail, and fails the challenge if a rule is broken anyway.
-- Records: "challenges" key = member .. "#" .. id
--   { name, rules, preset, ts, startLevel, lvl, status = "active"|"failed"|"completed"|"abandoned", reason, ended }
local ADDON, ns = ...
local Data = ns.Data

local C = {}
ns.Challenges = C

C.SLOT_NAMES = { [1] = "Head", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
  [9] = "Wrist", [10] = "Hands", [15] = "Back" }

C.PRESETS = {
  slayer = { name = "Slayer", noSlots = { 3, 4, 5 }, pvp = true,
    rules = "No chest or shoulder armor, no shirt, and stay flagged for PvP all the way to max level." },
  stoneskin = { name = "Stone-Skin", noSlots = { 1, 3, 5, 6, 7, 8, 9, 10, 15 },
    rules = "Wear no armor at all: weapons, rings, necklace, trinkets, shirt and tabard only." },
  selfmade = { name = "Self-Made", noAH = true, noTrade = true, noMail = true,
    rules = "No auction house, no trading and no mail. Everything you have, you earned." },
  onelife = { name = "One Life", oneLife = true,
    rules = "Die once and the challenge is over." },
  dwarffound = { name = "Dwarf Found", dwarfOnly = true,
    rules = "Trade and group only with dwarves. Everyone else is a stranger." },
}
C.ORDER = { "slayer", "stoneskin", "selfmade", "onelife", "dwarffound" }

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
function C.MyEnforced()
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
    for _, c in ipairs(C.MyEnforced()) do
      if c.data.preset == presetId then ns.Print("You're already on the " .. preset.name .. " challenge."); return false end
    end
    name, rules = preset.name, preset.rules
  else
    name, rules = ns.Clean(name, 40), ns.Clean(rules, 400)
    if name == "" then ns.Print("Give the challenge a name."); return false end
  end
  local key = me .. "#" .. string.format("%x", ns.Stamp())
  local ok = Data.Put("challenges", key, { name = name, rules = rules, preset = presetId, ts = ns.Now(),
    startLevel = level(), lvl = level(), status = "active" })
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

-- An officer marks someone's challenge completed (or failed).
function C.Judge(key, status, reason)
  local d = Data.Get("challenges", key)
  if not d or d.status ~= "active" or not ns.IAmOfficer() then return false end
  if Data.SplitKey(key) == ns.PlayerName() then ns.Print("Another officer has to judge your own challenge."); return false end
  local fields = { status = status, ended = ns.Now(), judgedBy = ns.PlayerName() }
  if reason then fields.reason = reason end
  return update(key, fields)
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

local warned = {}
function C.Enforce()
  local active = C.MyEnforced()
  if #active == 0 then wipe(wornSince); return end
  local now = GetTime and GetTime() or 0
  for _, c in ipairs(active) do
    local p = c.preset
    for _, slot in ipairs(p.noSlots or {}) do
      if worn(slot) then
        local slotName = C.SLOT_NAMES[slot] or "that"
        local what = slot == 4 and "shirt" or (slotName:lower() .. " armor")
        if unequip(slot) then
          ns.Print("|cffd4a017" .. p.name .. ":|r no " .. what .. ". It's back in your bags.")
          wornSince[slot] = nil
        else
          wornSince[slot] = wornSince[slot] or now
          if not warned[slot] then
            warned[slot] = true
            ns.Print("|cffff4040" .. p.name .. ":|r take off your " .. what .. " within a minute or the challenge fails" ..
              ((freeBagSlot() == nil) and " (your bags are full)." or "."))
          end
          if now - wornSince[slot] >= GRACE then C.Fail(c.key, "Wore " .. (slot == 4 and "a shirt" or (slotName:lower() .. " armor")) .. " at level " .. level() .. ".") end
        end
      else
        wornSince[slot] = nil
        warned[slot] = nil
      end
    end
    if p.pvp then C.KeepFlagged(p.name, c.key) end
  end
end

-- Slayer: PvP stays on. Turning it off (/pvp, the portrait menu, anything) is undone at once.
-- "Desired" is the setting the game remembers; the flag itself lingers for a few minutes after
-- it's turned off, so the setting is what gets checked.
local lastFlagMsg = 0
C.pvpLog = {} -- what the last attempts did, for /hold pvp

local function isFlagged()
  local desired = GetPVPDesired and GetPVPDesired()
  local flagged = UnitIsPVP and UnitIsPVP("player")
  return desired, flagged
end

-- Try every way the game offers to switch the PvP flag on. Returns the one that was called.
-- TogglePVP flips the setting, so it's only used when the setting is known to be off.
function C.TurnPvPOn(knownOff)
  local P = C_PvP or {}
  if SetPVP then
    local ok, err = pcall(SetPVP, 1)
    C.pvpLog[#C.pvpLog + 1] = "SetPVP(1): " .. (ok and "called" or ("error " .. tostring(err)))
    if ok then return "SetPVP" end
  end
  if P.SetPVP then
    local ok, err = pcall(P.SetPVP, true)
    C.pvpLog[#C.pvpLog + 1] = "C_PvP.SetPVP(true): " .. (ok and "called" or ("error " .. tostring(err)))
    if ok then return "C_PvP.SetPVP" end
  end
  local toggle = TogglePVP or P.TogglePVP
  if toggle and knownOff then
    local ok, err = pcall(toggle)
    C.pvpLog[#C.pvpLog + 1] = "TogglePVP(): " .. (ok and "called" or ("error " .. tostring(err)))
    if ok then return "TogglePVP" end
  end
  C.pvpLog[#C.pvpLog + 1] = "no PvP function found"
  return nil
end

-- PvP counts as on when the setting is on (or, if the game won't say, when the flag is up).
local function pvpOn()
  local desired, flagged = isFlagged()
  if desired ~= nil then return desired and true or false end
  return flagged and true or false
end
C.PVP_GRACE = 60
local unflaggedSince

function C.KeepFlagged(name, key)
  if pvpOn() then unflaggedSince = nil; return end
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
  local now = GetTime and GetTime() or 0
  -- out of time: the challenge fails
  if unflaggedSince and now - unflaggedSince >= C.PVP_GRACE then
    unflaggedSince = nil
    if key then C.Fail(key, "Wasn't flagged for PvP at level " .. level() .. ".") end
    return
  end
  while #C.pvpLog > 12 do table.remove(C.pvpLog, 1) end
  local desired, flagged = isFlagged()
  local used = C.TurnPvPOn(desired == false or (desired == nil and flagged == false))
  if not C_Timer then return end
  C_Timer.After(1.5, function()
    if pvpOn() then
      unflaggedSince = nil
      if now - lastFlagMsg > 30 or lastFlagMsg == 0 then
        lastFlagMsg = now
        ns.Print("|cffd4a017" .. name .. ":|r your PvP flag stays on for the whole challenge.")
      end
      return
    end
    C.pvpLog[#C.pvpLog + 1] = (used or "nothing") .. " did not turn PvP on"
    if unflaggedSince then return end -- already warned; the timer is running
    unflaggedSince = GetTime and GetTime() or 0
    ns.Print("|cffff4040" .. name .. ":|r you're not flagged for PvP. Type |cffffd040/pvp|r within " .. C.PVP_GRACE ..
      " seconds or the challenge fails.")
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
    if ns.UI and ns.UI.Notice then
      ns.UI.Notice({ id = "pvp", icon = "Interface\\Icons\\Ability_DualWield", title = name .. ": flag for PvP",
        text = "Type |cffffd040/pvp|r in chat within " .. C.PVP_GRACE .. " seconds, or the " .. name .. " challenge fails.",
        buttons = { { text = "OK" } }, timeout = C.PVP_GRACE })
    end
    -- come back when the time is up
    C_Timer.After(C.PVP_GRACE + 1, function() pcall(C.Enforce) end)
  end)
end

-- /hold pvp: what the PvP functions report on this server.
function C.PvPReport()
  local function yes(v) return v and "yes" or "no" end
  local desired, flagged = isFlagged()
  local P = C_PvP or {}
  ns.Print("PvP check: SetPVP " .. yes(SetPVP) .. ", TogglePVP " .. yes(TogglePVP) .. ", C_PvP.SetPVP " .. yes(P.SetPVP) ..
    ", C_PvP.TogglePVP " .. yes(P.TogglePVP) .. ", GetPVPDesired " .. yes(GetPVPDesired) .. ", UnitIsPVP " .. yes(UnitIsPVP))
  ns.Print("Right now: setting on = " .. tostring(desired) .. ", flagged = " .. tostring(flagged))
  local used = C.TurnPvPOn(desired == false or (desired == nil and flagged == false))
  ns.Print("Tried to flag you with: " .. tostring(used))
  if C_Timer then
    C_Timer.After(1.5, function()
      local d2, f2 = isFlagged()
      ns.Print("A moment later: setting on = " .. tostring(d2) .. ", flagged = " .. tostring(f2))
      for _, line in ipairs(C.pvpLog) do ns.Print("  " .. line) end
      if C.blocked then ns.Print("|cffff4040Blocked by the game:|r " .. C.blocked) end
    end)
  end
end

-- The game reports when it refuses a protected call from an addon.
ns.RegisterEvent("ADDON_ACTION_BLOCKED", function(addon, fn) if addon == ADDON then C.blocked = tostring(fn) end end)
ns.RegisterEvent("ADDON_ACTION_FORBIDDEN", function(addon, fn) if addon == ADDON then C.blocked = tostring(fn) end end)

local function pvpChanged()
  for _, c in ipairs(C.MyEnforced()) do
    if c.preset.pvp then C.KeepFlagged(c.preset.name, c.key); return end
  end
end
if hooksecurefunc then
  if TogglePVP then hooksecurefunc("TogglePVP", pvpChanged) end
  if SetPVP then hooksecurefunc("SetPVP", function(v) if not v or v == 0 then pvpChanged() end end) end
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

function C.CheckGroup()
  local name = forbids("dwarfOnly")
  if not name or not (IsInGroup and IsInGroup()) then strangerSince = nil; leavingUntil = 0; return end
  if (GetTime and GetTime() or 0) < leavingUntil then return end
  local stranger
  for _, u in ipairs(groupUnits()) do
    if UnitExists and UnitExists(u) and not (UnitIsUnit and UnitIsUnit(u, "player")) and dwarfRace(u) == false then
      stranger = ns.UnitDisplayName(u) or "someone"
      break
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
    local leave = (C_PartyInfo and C_PartyInfo.LeaveParty) or LeaveParty
    if leave then pcall(leave) end
    ns.Print("|cffd4a017" .. name .. ":|r leaving the group. You walk only with dwarves.")
  end
end
ns.RegisterEvent("GROUP_ROSTER_UPDATE", function() C.CheckGroup() end)

-- Turn down invites from guildmates known not to be dwarves.
ns.RegisterEvent("PARTY_INVITE_REQUEST", function(inviter)
  local name = forbids("dwarfOnly")
  if not name or type(inviter) ~= "string" then return end
  local full = ns.FullName(inviter)
  if ns.roster[full] and ns.Gear.IsDwarf(full) == false then
    if DeclineGroup then pcall(DeclineGroup) end
    if StaticPopup_Hide then pcall(StaticPopup_Hide, "PARTY_INVITE") end
    ns.Print("|cffd4a017" .. name .. ":|r turned down " .. ns.ShortName(inviter) .. "'s invite. Dwarves only.")
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
  for k, d in Data.Each("challenges") do
    if Data.SplitKey(k) == me and d.status == "active" then
      if d.preset and lvl >= C.MaxLevel() then
        C.Complete(k, lvl)
      else
        update(k, { lvl = lvl })
      end
    end
  end
end)

ns.On("DATA_READY", function()
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(10, function() pcall(C.Enforce); pcall(C.CheckGroup) end) end
end)

----------------------------------------------------------------------
-- Tell the guild (addon users) when a challenge starts, fails or is completed. No chat.
----------------------------------------------------------------------
local lastStatus = {}
ns.On("DATA_CHANGED", function(coll, key)
  if coll ~= "challenges" or not key then return end
  local d = Data.Get("challenges", key)
  local member = Data.SplitKey(key)
  if d and member == ns.PlayerName() and lastStatus[key] == "active" and d.status ~= "active" and d.judgedBy and d.judgedBy ~= member then
    lastStatus[key] = d.status
    local word = d.status == "completed" and "completed" or "failed"
    ns.Print("|cffd4a017Challenge:|r " .. ns.ShortName(d.judgedBy) .. " marks your " .. d.name .. " challenge " .. word .. ".")
    if ns.UI and ns.UI.Notice then
      ns.UI.Notice({ id = "challenge", icon = "Interface\\Icons\\Achievement_General", title = "Challenge " .. word,
        text = ns.ShortName(d.judgedBy) .. " marks |cffffd040" .. d.name .. "|r " .. word .. ".", buttons = { { text = "Huzzah!" } } })
    end
    return
  end
  if not d or member == ns.PlayerName() or lastStatus[key] == d.status then lastStatus[key] = d and d.status; return end
  lastStatus[key] = d.status
  if ns.Now() - (tonumber(d.ended or d.ts) or 0) > 600 then return end
  local who = ns.ShortName(member)
  if d.status == "active" then
    ns.Print("|cffd4a017Challenge:|r " .. who .. " takes on " .. d.name .. ".")
  elseif d.status == "failed" then
    ns.Print("|cffd4a017Challenge:|r " .. who .. " failed " .. d.name .. ". " .. (d.reason or ""))
  elseif d.status == "completed" then
    ns.Print("|cffd4a017Challenge:|r " .. who .. " completed " .. d.name .. "! Raise a mug.")
  end
end)
