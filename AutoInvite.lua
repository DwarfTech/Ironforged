-- Ironforged: invite from whispers, like Leatrix Plus.
-- When someone whispers you the keyword (default "inv"), you invite them to your group.
-- By default only guildmates are invited; a setting opens it to anyone.
local ADDON, ns = ...

local AI = {}
ns.AutoInvite = AI

local function groupSize()
  if GetNumGroupMembers then return GetNumGroupMembers() end
  return 0
end

-- Can I invite right now? Not if I'm in someone else's group without assist, or the group is full.
local function canInvite()
  local inGroup = IsInGroup and IsInGroup()
  if not inGroup then return true end
  local lead = UnitIsGroupLeader and UnitIsGroupLeader("player")
  local assist = UnitIsGroupAssistant and UnitIsGroupAssistant("player")
  local raid = IsInRaid and IsInRaid()
  if not lead and not (raid and assist) then return false, "you're not the group leader" end
  if raid and groupSize() >= 40 then return false, "your raid is full" end
  if not raid and groupSize() >= 5 then return false, "your party is full (make it a raid to invite more)" end
  return true
end

-- The first keyword, for telling people what to whisper.
function AI.Word()
  local raw = (ns.settings and ns.settings.inviteKeyword) or "inv"
  return raw:match("[^,%s]+") or "inv"
end

function AI.Keywords()
  local raw = (ns.settings and ns.settings.inviteKeyword) or "inv"
  local out = {}
  for w in raw:lower():gmatch("[^,%s]+") do out[w] = true end
  return out
end

function AI.OnWhisper(text, sender)
  if not ns.settings then return end
  -- while I'm hosting Cross Gambling, guildmates who whisper the keyword are always invited
  local hosting = ns.Gamble and ns.Gamble.IsHost() and ns.Gamble.Active()
  if ns.settings.autoInvite == false and not hosting then return end
  if type(text) ~= "string" or type(sender) ~= "string" then return end
  if issecretvalue and (issecretvalue(text) or issecretvalue(sender)) then return end
  local msg = ns.Trim(text):lower()
  if not AI.Keywords()[msg] then return end
  local guildmate = ns.roster[ns.FullName(sender)] ~= nil
  if not guildmate and not ns.settings.inviteAnyone then return end
  local ok, why = canInvite()
  if not ok then
    ns.Print(ns.ShortName(sender) .. " asked for an invite, but " .. why .. ".")
    return
  end
  local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
  if fn and pcall(fn, ns.CharName(sender)) then
    ns.Print("Invited " .. ns.ShortName(sender) .. " (they whispered \"" .. msg .. "\").")
  end
end

ns.RegisterEvent("CHAT_MSG_WHISPER", function(text, sender) AI.OnWhisper(text, sender) end)
