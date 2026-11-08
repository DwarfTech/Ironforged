-- Ironforged: recruitment message. Officers post the guild's recruiting message to a public channel
-- (General, Trade, LookingForGroup) or say/yell it, from a button on the Roster tab. The message is
-- kept in the guild settings, so every officer posts the same one and any of them can change it.
local ADDON, ns = ...

local R = {}
ns.Recruit = R

R.COOLDOWN = 60 -- seconds between posts, so nobody floods a channel by accident

R.CHANNELS = {
  { key = "General", text = "General", channel = true },
  { key = "Trade", text = "Trade (cities)", channel = true },
  { key = "LookingForGroup", text = "LookingForGroup", channel = true },
  { key = "SAY", text = "Say" },
  { key = "YELL", text = "Yell" },
}

function R.DefaultMessage()
  local name = ns.Data and ns.Data.GuildDisplayName() or "Ironforged"
  return name .. " is recruiting dwarves! An all-dwarf roleplay guild with clans, challenges, the Book of Grudges and plenty of ale. Whisper me to join the hold!"
end

function R.Message()
  local _, guild = ns.Data.Config()
  local m = guild.recruitMessage
  if type(m) == "string" and m ~= "" then return m end
  return R.DefaultMessage()
end

-- Save the message for every officer (guild settings sync to all).
function R.SaveMessage(text)
  if not ns.IAmOfficer() then return false end
  local _, guild = ns.Data.Config()
  if guild.recruitMessage == text then return true end
  local copy = {}
  for k, v in pairs(guild) do copy[k] = v end
  copy.recruitMessage = text
  return ns.Data.Put("config", "guild", copy)
end

-- The channel number of a joined channel whose name starts with base ("General" matches
-- "General - Dun Morogh"), or nil.
function R.ChannelNumber(base)
  local lower = base:lower()
  if GetChannelList then
    local list = { pcall(GetChannelList) }
    if list[1] then
      for i = 2, #list, 3 do
        local id, name = list[i], list[i + 1]
        if type(id) == "number" and type(name) == "string" and name:lower():sub(1, #lower) == lower then return id end
      end
    end
  end
  if GetChannelName then
    local ok, id = pcall(GetChannelName, base)
    if ok and type(id) == "number" and id > 0 then return id end
  end
end

local lastSent = -math.huge

-- Post the message. Returns true, or false and why.
function R.Send(text, where)
  if not ns.IAmOfficer() then return false, "Only officers can send the recruitment message." end
  text = ns.Clean and ns.Clean(text, 255) or text
  if type(text) ~= "string" or text == "" then return false, "The message is empty." end
  local now = GetTime and GetTime() or 0
  if now - lastSent < R.COOLDOWN then
    return false, string.format("You posted it %d seconds ago. Give the channel a minute.", math.floor(now - lastSent))
  end
  local locked = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and select(2, pcall(C_ChatInfo.InChatMessagingLockdown))
  if locked == true then return false, "The game has chat locked right now. Try again in a moment." end
  local spec
  for _, c in ipairs(R.CHANNELS) do if c.key == where then spec = c end end
  spec = spec or R.CHANNELS[1]
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  if not send then return false, "The game won't let addons send chat here." end
  local ok
  if spec.channel then
    local id = R.ChannelNumber(spec.key)
    if not id then
      return false, "You're not in the " .. spec.text .. " channel here." ..
        (spec.key == "Trade" and " Trade only works in the capital cities." or "")
    end
    ok = pcall(send, text, "CHANNEL", nil, id)
  else
    ok = pcall(send, text, spec.key)
  end
  if not ok then return false, "The game wouldn't send it. Try again from the button." end
  lastSent = now
  ns.settings.recruitChannel = spec.key
  return true
end

function R.ResetCooldown() lastSent = -math.huge end
