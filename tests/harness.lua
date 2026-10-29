-- Mock WoW client environment for testing Ironforged outside the game.
local ADDON_DIR = arg[1]
local FILES = {}
for line in io.lines(ADDON_DIR .. "/Ironforged.toc") do
  if line:match("%.lua%s*$") then FILES[#FILES + 1] = line:gsub("%s+$", "") end
end

local H = { clients = {}, bus = {}, clock = 1000, server = 1792000000, ITEM_TYPES = {} }
-- the server knows a character by its full "First Surname" name; the realm is dropped when whispering
function H.charName(full) return full end
function H.baseName(n) -- same rule as the addon: a trailing "-Realm" goes; "First-Surname" becomes "First Surname"
  local base, suffix = n:match("^(.-)%-([^%s%-]+)$")
  if base and (base:find(" ", 1, true) or suffix == "Forever") then n = base end
  return (n:gsub("%-", " "))
end

local ROSTER = {
  { "Thorin-Forever", "Thane", 0, 60, "Warrior", "WARRIOR" },
  { "Elda-Forever", "Elder", 1, 60, "Priest", "PRIEST" },
  { "Brann-Forever", "Longbeard", 2, 60, "Hunter", "HUNTER" },
  { "Lordy-Forever", "Lord", 4, 60, "Paladin", "PALADIN" },
  { "Dagna-Forever", "Noble", 5, 42, "Priest", "PRIEST" },
  { "Muradin-Forever", "Veteran", 7, 58, "Paladin", "PALADIN" },
  { "Kurdran-Forever", "Vanguard", 8, 30, "Warrior", "WARRIOR" },
  { "Hilda-Forever", "Ironguard", 9, 12, "Rogue", "ROGUE" },
  { "Gimli-Forever", "Vanguard", 8, 20, "Warrior", "WARRIOR" },
  { "Grimm-Forever", "Ironguard", 9, 8, "Mage", "MAGE" },
  { "Nobody-Forever", "Ironguard", 9, 5, "Mage", "MAGE" },
  { "Frugo-Mega", "Thane", 0, 60, "Warrior", "WARRIOR" },
  { "Bruni-Mega", "Longbeard", 2, 60, "Priest", "PRIEST" },
  { "Buttercup Clamstone-Forever", "Noble", 5, 40, "Rogue", "ROGUE" }, -- Forever first + last name
}
H.RACES_BY_NAME = {}
H.ROSTER = ROSTER
local GUID_RACE = { ["Player-Gimli-Forever"] = "Dwarf", ["Player-Grimm-Forever"] = "Human" }
H.ROSTER = ROSTER

local function newStub(kind, name)
  local o = { __kind = kind, __scripts = {}, __shown = true, __w = 100, __h = 20, __text = "", __events = {} }
  local methods = {}
  function methods.SetScript(self, k, f) self.__scripts[k] = f end
  function methods.GetScript(self, k) return self.__scripts[k] end
  function methods.HookScript(self, k, f) self.__scripts[k] = f end
  function methods.Show(self) local was = self.__shown; self.__shown = true; if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end end
  function methods.Hide(self) self.__shown = false end
  function methods.IsShown(self) return self.__shown end
  function methods.IsVisible(self) return self.__shown end
  function methods.SetShown(self, v) if v then self:Show() else self:Hide() end end
  function methods.SetText(self, t) self.__text = t end
  function methods.GetText(self) return self.__text end
  function methods.SetChecked(self, v) self.__checked = v and true or false end
  function methods.GetChecked(self) return self.__checked end
  function methods.SetSize(self, w, h) self.__w, self.__h = w, h end
  function methods.SetWidth(self, w) self.__w = w end
  function methods.SetHeight(self, h) self.__h = h end
  function methods.GetWidth(self) return self.__w end
  function methods.GetHeight(self) return self.__h end
  function methods.GetStringHeight(self) local n = 1; for _ in tostring(self.__text):gmatch("\n") do n = n + 1 end; return n * 14 end
  function methods.CreateFontString(self) return newStub("FontString") end
  function methods.CreateTexture(self) return newStub("Texture") end
  function methods.RegisterEvent(self, e) self.__events[e] = true end
  function methods.SetEnabled(self, v) self.__enabled = v end
  function methods.SetAttribute(self, k, v) self.__attr = self.__attr or {}; self.__attr[k] = v end
  function methods.GetAttribute(self, k) return self.__attr and self.__attr[k] end
  function methods.Disable(self) self.__disabled = true end
  function methods.Enable(self) self.__disabled = false end
  function methods.IsEnabled(self) return not self.__disabled end
  function methods.Click(self, button) if self.__scripts.OnClick then self.__scripts.OnClick(self, button or "LeftButton") end end
  function methods.SetValue(self, v) self.__value = v; if self.__scripts.OnValueChanged then self.__scripts.OnValueChanged(self, v) end end
  return setmetatable(o, { __index = function(t, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:match("^%u") then return function() end end
    return nil
  end })
end
H.newStub = newStub

local function makeClient(shortName, race, fullName)
  local env = {}
  env._G = env
  for _, k in ipairs({ "pairs", "ipairs", "type", "tostring", "tonumber", "pcall", "error", "select", "next",
    "setmetatable", "getmetatable", "rawget", "rawset", "unpack", "assert", "print", "string", "table", "math" }) do
    env[k] = _G[k]
  end
  -- WoW's math library has no randomseed
  local wowmath = {}
  for k, v in pairs(math) do wowmath[k] = v end
  wowmath.randomseed = nil
  env.math = wowmath
  env.date = os.date
  env.time = os.time
  env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  env.tinsert = table.insert
  env.UISpecialFrames = {}
  env.SlashCmdList = {}
  local client = { name = shortName, full = fullName or (shortName .. "-Forever"), env = env, frames = {}, timers = {}, chat = {}, guildChat = {} }
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(client.chat, m) end }
  env.CreateFrame = function(kind, name, parent, template)
    local f = newStub(kind, name)
    f.__parent = parent
    f.GetParent = function(self) return self.__parent end
    table.insert(client.frames, f)
    if name then env[name] = f end
    return f
  end
  env.UIParent = newStub("Frame")
  env.Minimap = newStub("Minimap")
  env.GetCursorPosition = function() return 0, 0 end
  env.GameTooltip = newStub("GameTooltip")
  env.GetTime = function() return H.clock end
  env.GetServerTime = function() return H.server + math.floor(H.clock) end
  env.C_Timer = {
    After = function(d, f) table.insert(client.timers, { due = H.clock + d, f = f }) end,
    NewTicker = function(d, f) table.insert(client.timers, { due = H.clock + d, f = f, every = d }) end,
  }
  env.IsInGuild = function() return true end
  env.GetGuildInfo = function() return "Ironforged Kin", "x", 0 end
  env.GetNormalizedRealmName = function() return "Forever" end
  env.UnitName = function(u)
    if u == "player" then return shortName end
    if u == "target" and client.target then return client.target.name, client.target.surname end
    if client.units[u] then return client.units[u].name, client.units[u].surname end
    return nil
  end
  env.GetNumGuildMembers = function() return #ROSTER end
  local RANKS = { "Thane", "Elder", "Longbeard", "Overlord", "Lord", "Noble", "General", "Veteran", "Vanguard", "Ironguard" }
  env.GuildControlGetNumRanks = function() return #RANKS end
  env.GuildControlGetRankName = function(i) return RANKS[i] end
  env.GetGuildRosterInfo = function(i)
    local r = ROSTER[i]
    return r[1], r[2], r[3], r[4], r[5], "Ironforge", "", "", true, 0, r[6], 0, 0, false, false, 0, "Player-" .. r[1]
  end
  env.GetGuildRosterLastOnline = function() return 0, 0, 0, 0 end
  env.C_GuildInfo = { GuildRoster = function() client.rosterRequested = true end, Invite = function() end }
  env.InCombatLockdown = function() return client.inCombat and true or false end
  client.race = race or "Dwarf"
  client.items = {}
  client.units = {}
  env.UnitRace = function(u)
    if u == "player" then return client.race, client.race, 1 end
    if u == "target" and client.target then return client.target.race, client.target.race, 1 end
    if client.units[u] then return client.units[u].raceName or client.units[u].race, client.units[u].race, 1 end
    return nil
  end
  env.UnitFactionGroup = function(u)
    if u == "target" and client.target then return client.target.faction end
    if client.units[u] then return client.units[u].faction end
    return "Alliance"
  end
  env.UnitIsDeadOrGhost = function(u)
    if u == "player" then return client.dead and true or false end
    if u == "target" and client.target then return client.target.dead and true or false end
    if client.units[u] then return client.units[u].dead and true or false end
    return false
  end
  client.hk = 0
  env.GetPVPLifetimeStats = function() return client.hk, 0, 0 end
  env.GetZoneText = function() return "Arathi Highlands" end
  env.COMBATLOG_HONORGAIN = "%s dies, honorable kill Rank: %s (Estimated Honor Points: %d)"
  env.UnitIsPlayer = function() return true end
  env.UnitGUID = function(u) if u == "player" then return client.guidOverride or ("Player-" .. client.full) end end
  env.UnitExists = function(u) return (u == "target" and client.target ~= nil) or client.units[u] ~= nil end
  local baseUnitName = nil
  env.ITEM_CREATED_BY = "<Made by %s>"
  env.ERR_GUILD_JOIN_S = "%s has joined the guild."
  env.GetInventoryItemLink = function(_, slot) local it = client.items[slot]; return it and it.link end
  env.C_TooltipInfo = { GetInventoryItem = function(_, slot)
    local it = client.items[slot]
    if not it then return nil end
    local lines = { { leftText = "Some Item" } }
    if it.crafter then lines[#lines + 1] = { leftText = "|cff00ff00<Made by " .. it.crafter .. ">|r" } end
    return { lines = lines }
  end }
  env.GetItemInfoInstant = function() return 1, "Armor", "Plate", "INVTYPE_CHEST" end
  -- item id -> { classID, subclassID } for the challenges' weapon and shield rules
  env.C_Item = { GetItemInfoInstant = function(id)
    local t = H.ITEM_TYPES[id]
    if t then return id, nil, nil, nil, nil, t[1], t[2] end
  end }
  env.UnitClass = function(u) local c = client.class or "WARRIOR"; return c:sub(1, 1) .. c:sub(2):lower(), c, 1 end
  env.IsStealthed = function() return client.stealthed and true or false end
  env.IsPlayerSpell = function(id) return client.known and client.known[id] and true or false end
  env.PetAbandon = function() client.units.pet = nil end
  env.GetNumGroupMembers = function() return client.groupSize or 0 end
  env.UnitInParty = function(n) return client.partyNames and client.partyNames[n] or false end
  env.GetTitleText = function() return client.questTitle end
  env.hooksecurefunc = function(a, b, c)
    if type(a) == "table" then local orig = a[b]; a[b] = function(...) local r = orig(...); c(...); return r end
    else local orig = env[a]; env[a] = function(...) local r = orig(...); b(...); return r end end
  end
  env.Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8 } }
  env.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() end,
    SendAddonMessage = function(prefix, text, channel, target)
      assert(#prefix <= 16, "prefix too long")
      assert(#text <= 255, "addon message too long: " .. #text)
      assert(not text:find("%z"), "null byte in addon message")
      table.insert(H.bus, { from = H.charName(client.full), prefix = prefix, text = text, channel = channel, target = target })
      return 0
    end,
    SendChatMessage = function(text, channel, lang, target)
      if channel == "WHISPER" then
        H.whisperBus = H.whisperBus or {}
        table.insert(H.whisperBus, { from = H.charName(client.full), to = target, text = text })
        return
      end
      table.insert(client.guildChat, text)
      if channel == "GUILD" then H.guildBus = H.guildBus or {}; table.insert(H.guildBus, { from = client.full, text = text }) end
      if channel == "RAID" and client.inRaid then H.raidBus = H.raidBus or {}; table.insert(H.raidBus, { from = client.full, text = text }) end
    end,
  }
  env.GetPlayerInfoByGUID = function(guid)
    local race = GUID_RACE[guid]
    if not race then return nil end
    return "Warrior", "WARRIOR", race, race, 2, "x", ""
  end
  client.whoSent = {}
  client.whoResults = {}
  env.C_FriendList = {
    SendWho = function(filter, origin) table.insert(client.whoSent, filter) end,
    GetNumWhoResults = function() return #client.whoResults end,
    GetWhoInfo = function(i) return client.whoResults[i] end,
  }
  local RACEINFO = { [1] = { raceName = "Human", clientFileString = "Human" }, [3] = { raceName = "Dwarf", clientFileString = "Dwarf" },
    [2] = { raceName = "Orc", clientFileString = "Orc" } }
  env.C_CreatureInfo = { GetRaceInfo = function(id) return RACEINFO[id] end }
  client.languages = (client.race == "Dwarf") and { { "Common", 7 }, { "Dwarvish", 6 } } or { { "Common", 7 } }
  env.GetNumLanguages = function() return #client.languages end
  env.GetLanguageByIndex = function(i) local l = client.languages[i]; if l then return l[1], l[2] end end
  env.GetDefaultLanguage = function() return "Common", 7 end
  env.NUM_CHAT_WINDOWS = 2
  env.ChatFrame1EditBox = newStub("EditBox")
  env.ChatFrame2EditBox = newStub("EditBox")
  client.chatOpened = {}
  env.ChatFrame_OpenChat = function(text) table.insert(client.chatOpened, text) end
  env.ToggleGuildFrame = function() client.guildWindowOpened = (client.guildWindowOpened or 0) + 1 end
  env.GetSubZoneText = function() return client.subzone or "" end
  env.GetUnitName = function(u)
    if u == "target" and client.target then
      return client.target.surname and (client.target.name .. " " .. client.target.surname) or client.target.name
    end
    local x = client.units[u]
    if x then return x.surname and (x.name .. " " .. x.surname) or x.name end
    return env.UnitName(u)
  end
  env.WOW_PROJECT_CAMELOT, env.WOW_PROJECT_ID = 99, 99
  client.bags = {}
  env.NUM_BAG_SLOTS = 4
  env.C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end,
    GetContainerItemInfo = function(bag, slot)
      local it = bag == 0 and client.bags[slot]
      if not it then return nil end
      return { itemID = it.id, stackCount = it.count, hyperlink = "|cffffffff|Hitem:" .. it.id .. "::::::::|h[" .. it.name .. "]|h|r" }
    end,
  }
  client.level, client.equip, client.pvp, client.closed = 1, {}, false, {}
  env.UnitLevel = function(u) if u == "player" then return client.level end return 1 end
  client.xp = 0
  env.UnitXP = function(u) return client.xp end
  env.GetInventoryItemID = function(u, slot) return client.equip[slot] end
  env.ClearCursor = function() client.cursor = nil end
  env.CursorHasItem = function() return client.cursor ~= nil end
  env.PickupInventoryItem = function(slot) client.cursor = client.equip[slot]; client.equip[slot] = nil end
  env.C_Container.PickupContainerItem = function(bag, slot)
    if client.cursor then client.bags[slot] = { id = client.cursor, count = 1, name = "Gear" }; client.cursor = nil end
  end
  env.UnitIsPVP = function(u) return client.pvp end
  env.GetPVPDesired = function() return client.pvp end
  env.SetPVP = function(v) client.pvp = v == 1 or v == true end
  env.TogglePVP = function() client.pvp = not client.pvp end
  env.CancelTrade = function() client.closed.trade = true end
  env.CloseMail = function() client.closed.mail = true end
  env.C_AuctionHouse = { CloseAuctionHouse = function() client.closed.ah = true end }
  env.GetMaxPlayerLevel = function() return 60 end
  client.inGroup, client.left, client.declined = false, false, false
  client.inRaid = false
  env.LE_PARTY_CATEGORY_HOME, env.LE_PARTY_CATEGORY_INSTANCE = 1, 2
  env.IsInGroup = function(category)
    if category == env.LE_PARTY_CATEGORY_INSTANCE then return client.instanceGroup and true or false end
    return client.inGroup or client.inRaid or client.instanceGroup
  end
  env.IsInRaid = function() return client.inRaid end
  env.UnitIsGroupLeader = function(u) return client.leader and true or false end
  -- UnitInRaid by character name: in my raid if we're both in the (single) test raid
  env.UnitInRaid = function(n)
    if not client.inRaid then return nil end
    for full, c in pairs(H.clients) do
      if c.inRaid and H.baseName(full) == n then return 1 end
    end
    return nil
  end
  env.UnitExists = env.UnitExists or function(u) return client.units[u] ~= nil end
  env.GetHomePartyInfo = function() return client.homeParty end
  env.LeaveParty = function() client.left = true end -- the game drops the group a moment later
  env.C_PartyInfo = env.C_PartyInfo or {}
  env.DeclineGroup = function() client.declined = true end
  client.rollQueue = {}
  client.emotes = {}
  client.profs = {}
  client.trade = nil
  client.invites = {}
  local SPELLS = { [3491] = "Big Bronze Knife", [2741] = "Bronze Axe", [3297] = "Mining Pick", [12259] = "Silvered Bronze Leggings",
    [589] = "Shadow Word: Pain", [585] = "Smite", [2050] = "Lesser Heal", [17] = "Power Word: Shield", [635] = "Holy Light",
    [21084] = "Seal of Righteousness", [20271] = "Judgement", [465] = "Devotion Aura", [879] = "Exorcism", [8326] = "Ghost" }
  env.C_Spell = { GetSpellName = function(id) return SPELLS[id] end }
  env.GetProfessions = function() local p = client.profs; return p[1] and 1 or nil, p[2] and 2 or nil, nil, nil, nil end
  env.GetProfessionInfo = function(i) local p = client.profs[i]; if p then return p.name, 0, p.skill, p.max end end
  env.C_TradeSkillUI = {
    IsTradeSkillLinked = function() return client.trade and client.trade.linked or false end,
    GetBaseProfessionInfo = function() local t = client.trade; if t then return { professionName = t.name, skillLevel = t.skill, maxSkillLevel = t.max } end end,
    GetAllRecipeIDs = function() local out = {}; if client.trade then for id in pairs(client.trade.recipes) do out[#out + 1] = id end end; return out end,
    GetRecipeInfo = function(id) local l = client.trade and client.trade.recipes[id]; if l ~= nil then return { learned = l, name = SPELLS[id] } end end,
  }
  env.C_PartyInfo = {
    InviteUnit = function(n) table.insert(client.invites, n) end,
    LeaveParty = function(cat) client.left = true; client.leftCategory = cat end,
    ConvertToRaid = function() if client.inGroup then client.inRaid = true; client.converted = true end end,
  }
  env.DoEmote = function(token, target) table.insert(client.emotes, { token = token, target = target }) end
  env.RandomRoll = function(lo, hi)
    local r = table.remove(client.rollQueue, 1) or lo
    H.rollBus = H.rollBus or {}
    table.insert(H.rollBus, { to = client, text = string.format("%s rolls %d (%d-%d)", H.baseName(client.full), r, lo, hi) }) -- the roller's full name, no realm
  end
  env.RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
  env.Ambiguate = function(n) return (n:gsub("%-.*$", "")) end
  env.RAID_CLASS_COLORS = {}
  env.IronforgedDB = nil

  local ns = {}
  client.ns = ns
  for _, file in ipairs(FILES) do
    local chunk = assert(loadfile(ADDON_DIR .. "/" .. file))
    setfenv(chunk, env)
    chunk("Ironforged", ns)
  end
  H.clients[client.full] = client
  return client
end
H.makeClient = makeClient

function H.fire(client, event, ...)
  for _, f in ipairs(client.frames) do
    if f.__events[event] and f.__scripts.OnEvent then f.__scripts.OnEvent(f, event, ...) end
  end
end

function H.boot(client)
  H.fire(client, "ADDON_LOADED", "Ironforged")
  H.fire(client, "PLAYER_LOGIN")
  H.fire(client, "GUILD_ROSTER_UPDATE")
end

-- Advance time, run timers and OnUpdate, deliver messages.
function H.step(dt)
  H.clock = H.clock + dt
  for _, c in pairs(H.clients) do
    local due = {}
    for i = #c.timers, 1, -1 do
      local t = c.timers[i]
      if t.due <= H.clock then
        table.insert(due, t)
        if t.every then t.due = H.clock + t.every else table.remove(c.timers, i) end
      end
    end
    for _, t in ipairs(due) do t.f() end
    for _, f in ipairs(c.frames) do
      if f.__scripts.OnUpdate then f.__scripts.OnUpdate(f, dt) end
    end
  end
  local gb = H.guildBus or {}
  H.guildBus = {}
  for _, m in ipairs(gb) do
    for _, c in pairs(H.clients) do H.fire(c, "CHAT_MSG_GUILD", m.text, m.from) end
  end
  local wb = H.whisperBus or {}
  H.whisperBus = {}
  for _, m in ipairs(wb) do
    for full, c in pairs(H.clients) do if H.baseName(full) == H.baseName(m.to) then H.fire(c, "CHAT_MSG_WHISPER", m.text, m.from) end end
  end
  local raidb = H.raidBus or {}
  H.raidBus = {}
  for _, m in ipairs(raidb) do
    for _, c in pairs(H.clients) do if c.inRaid then H.fire(c, "CHAT_MSG_RAID", m.text, m.from) end end
  end
  -- a roll is seen by the roller and, in a raid, by everyone in the raid
  local rb = H.rollBus or {}
  H.rollBus = {}
  for _, m in ipairs(rb) do
    for _, c in pairs(H.clients) do
      if c == m.to or (m.to.inRaid and c.inRaid) then H.fire(c, "CHAT_MSG_SYSTEM", m.text) end
    end
  end
  local bus = H.bus
  H.bus = {}
  for _, m in ipairs(bus) do
    for full, c in pairs(H.clients) do
      if H.charName(full) ~= m.from and (m.channel == "GUILD" or (m.channel == "WHISPER" and H.baseName(m.target) == H.baseName(full))) then
        H.fire(c, "CHAT_MSG_ADDON", m.prefix, m.text, m.channel, m.from)
      end
    end
    H.delivered = (H.delivered or 0) + 1
  end
end

function H.run(seconds)
  for _ = 1, math.floor(seconds / 0.25) do H.step(0.25) end
end

return H
