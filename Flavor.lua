-- Ironforged: dwarven flavor text, toasts, greetings and the unit tooltip.
local ADDON, ns = ...

local Flavor = {}
ns.Flavor = Flavor

Flavor.lines = {
  greeting = {
    "Welcome home, %s. The forge fires are burning hot today.",
    "Hail, %s! Stamp the snow off your boots and pull up a stool.",
    "The great doors open for %s. Mind the low beam, it's older than your grandsire.",
    "%s returns to the hold. Someone fetch a fresh keg.",
    "Stone remembers, %s. And so do we. Welcome back.",
    "By hammer and hearth, %s is home again.",
  },
  arrival = {
    "%s has come down the mountain road.",
    "The gatekeeper sounds the horn: %s has arrived.",
    "%s stomps in from the cold.",
    "Clear a seat by the fire, %s is here.",
    "%s has entered the hold.",
  },
  toast = {
    "To stone that holds and steel that's true!",
    "May your beard grow long and your mug never run dry!",
    "To the forge, the hearth and the friends between them!",
    "Here's to deep mines, full vaults and short goblins!",
    "May the mountain shelter us and the ale find us!",
    "To those who stood the line, and those who'll stand it next!",
    "Hammer high, mugs higher!",
  },
  lore = {
    "A dwarf's word is set in stone. Breaking it is the deepest shame a hold can know.",
    "Old smiths say the first forge was lit from the heart of the mountain itself.",
    "Grudges are kept in ledgers, and some ledgers are older than the oldest living dwarf.",
    "A clan's hall is measured not in gold, but in the names carved over its hearth.",
    "Never hurry a brewer, a stonemason or a dwarf with a grudge.",
    "Runes cut into a doorway are a promise: what lies beyond will be defended.",
    "When a dwarf earns a new title, the whole hold drinks to it. Usually twice.",
  },
  promotion = {
    "%s has proven their mettle and earned the rank of %s. Raise your mugs!",
    "Carve a new name over the hearth: %s rises to %s!",
    "%s has completed their trial and stands now as %s. To the forge and the hearth!",
  },
}

Flavor.DEFAULT_OATH = "By stone and steel, by hammer and hearth, I stand with this hold."

function Flavor.Random(kind, ...)
  local list = Flavor.lines[kind]
  if not list or #list == 0 then return "" end
  local line = list[math.random(1, #list)]
  if select("#", ...) > 0 then return line:format(...) end
  return line
end

-- The addon never posts to guild chat. Every message it shows is a local chat line,
-- and data between guildmates travels on the hidden addon channel.

-- Greeting printed only for you, once per session.
local greeted = false
ns.On("DATA_READY", function()
  if greeted or not ns.settings.loginGreeting then return end
  greeted = true
  local function greet()
    local me = ns.PlayerName()
    ns.Print(Flavor.Random("greeting", ns.ShortName(me)))
    local apps = 0
    for _, clanId in ipairs(ns.Data.ClansLedBy(me)) do apps = apps + #ns.Data.Applications(clanId) end
    if apps > 0 then
      ns.Print(apps .. (apps == 1 and " dwarf asks" or " dwarves ask") .. " to join your clan. See Applications in the Clans tab.")
    end
    for _, clanId in ipairs(ns.Data.PendingInvites(me)) do
      ns.Print("Clan " .. (ns.Data.ClanName(clanId) or "?") .. " has invited you to join. Answer in the Clans tab.")
    end
  end
  if C_Timer then C_Timer.After(4, greet) else greet() end
end)

ns.On("PEER_ARRIVED", function(sender)
  if not ns.settings.arrivalNotices then return end
  ns.Print(Flavor.Random("arrival", ns.ShortName(sender)))
end)

----------------------------------------------------------------------
-- Unit tooltip: show title and clan for guildmates.
----------------------------------------------------------------------
local function isSecret(v)
  return issecretvalue and issecretvalue(v)
end

local function addTooltipLines(tooltip)
  if not ns.settings or not ns.settings.tooltips or not ns.Data.Ready() then return end
  if InCombatLockdown and InCombatLockdown() then return end
  local _, unit = tooltip:GetUnit()
  if not unit or isSecret(unit) then return end
  if not UnitIsPlayer(unit) then return end
  local display = ns.UnitDisplayName(unit)
  if not display then return end
  local full = ns.FullName(display)
  if not ns.roster[full] then return end

  local m = ns.Data.Member(full)
  local clanId = ns.Data.ClanOf(full)
  local clan = ns.Data.ClanName(clanId)
  local parts = {}
  local titles = ns.Titles.Text(full)
  if titles ~= "" then parts[#parts + 1] = titles end
  if clan then
    parts[#parts + 1] = (ns.Data.IsClanLeader(full, clanId) and "Leader of clan " or "of clan ") .. clan
  end
  local added = false
  if #parts > 0 then
    tooltip:AddLine(table.concat(parts, " "), 0.83, 0.63, 0.09)
    added = true
  end
  for _, ch in ipairs(ns.Challenges.Showing(full)) do
    local d = ch.data
    if d.status == "completed" then
      tooltip:AddLine("Challenge: " .. ns.Challenges.Label(d), 0.25, 1, 0.25)
    else
      tooltip:AddLine("Challenge: " .. ns.Challenges.Label(d), 1, 0.82, 0.25)
    end
    added = true
  end
  if added then tooltip:Show() end
end

function ns.Tooltip_Init()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
      if tooltip ~= GameTooltip then return end
      pcall(addTooltipLines, tooltip)
    end)
  end
end
