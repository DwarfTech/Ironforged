-- Ironforged: Settings tab (guild settings for officers, personal options, sync status).
local ADDON, ns = ...
local UI = ns.UI
local Data = ns.Data

local function editGuildSettings()
  local core, guild = Data.Config()
  local fields = {
    { key = "displayName", label = "Hold name", type = "text", value = guild.displayName or (GetGuildInfo("player")), maxLen = 40 },
  }
  UI.OpenForm({
    title = "Guild settings",
    fields = fields,
    onSave = function(v)
      local copy = {}
      for k, val in pairs(guild) do copy[k] = val end
      copy.displayName = ns.Clean(v.displayName, 40)
      Data.Put("config", "guild", copy)
    end,
  })
end

local function build(f, w, h)
  local guildTitle = UI.Label(f, "Guild", "GameFontNormal")
  guildTitle:SetPoint("TOPLEFT", 4, -4)
  f.guildInfo = UI.Label(f, "", "GameFontHighlightSmall")
  f.guildInfo:SetPoint("TOPLEFT", 4, -24)
  f.guildInfo:SetPoint("TOPRIGHT", -6, -24)
  f.guildInfo:SetJustifyV("TOP")
  f.guildButton = UI.Button(f, "Edit guild settings", 150, 22, editGuildSettings)
  f.guildButton:SetPoint("TOPLEFT", 4, -96)

  local personal = UI.Label(f, "Just for you", "GameFontNormal")
  personal:SetPoint("TOPLEFT", 4, -134)
  local function opt(key, text, y)
    local c = UI.Check(f, text, function(self) ns.settings[key] = self:GetChecked() and true or false end)
    c:SetPoint("TOPLEFT", 2, y)
    c:SetChecked(ns.settings[key])
    return c
  end
  opt("loginGreeting", "Greet me when I log in", -154)
  opt("arrivalNotices", "Tell me when guildmates with Ironforged arrive", -178)
  opt("tooltips", "Show clans and titles on guildmate tooltips", -202)
  local ai = UI.Check(f, "Invite guildmates who whisper me:", function(self)
    ns.settings.autoInvite = self:GetChecked() and true or false
  end)
  ai:SetPoint("TOPLEFT", 2, -226)
  ai:SetChecked(ns.settings.autoInvite ~= false)
  f.inviteWord = UI.EditBox(f, 70, 30)
  f.inviteWord:SetPoint("TOPLEFT", 236, -228)
  f.inviteWord:SetText(ns.settings.inviteKeyword or "inv")
  f.inviteWord:SetScript("OnTextChanged", function(self)
    local v = ns.Trim(self:GetText() or "")
    ns.settings.inviteKeyword = v ~= "" and v or "inv"
  end)
  local any = UI.Check(f, "Invite anyone who whispers it, not just guildmates", function(self)
    ns.settings.inviteAnyone = self:GetChecked() and true or false
  end)
  any:SetPoint("TOPLEFT", 2, -250)
  any:SetChecked(ns.settings.inviteAnyone == true)
  local gb = UI.Check(f, "Offer Hail, Salute and Cheer when I target a dwarf", function(self)
    ns.settings.greetBar = self:GetChecked() and true or false
    if UI.UpdateGreetBar then UI.UpdateGreetBar() end
  end)
  gb:SetPoint("TOPLEFT", 2, -274)
  gb:SetChecked(ns.settings.greetBar ~= false)
  local mm = UI.Check(f, "Show the Ironforged button on the minimap", function(self)
    ns.settings.minimapHidden = not self:GetChecked()
    UI.UpdateMinimapButton()
  end)
  mm:SetPoint("TOPLEFT", 330, -154)
  mm:SetChecked(not ns.settings.minimapHidden)
  local ga = UI.Check(f, "Warn me when a grudged foe is near", function(self)
    ns.settings.grudgeAlerts = self:GetChecked() and true or false
  end)
  ga:SetPoint("TOPLEFT", 330, -178)
  ga:SetChecked(ns.settings.grudgeAlerts ~= false)
  local cp = UI.Check(f, "Show the Cheers popup when an officer calls", function(self)
    ns.settings.cheersPopup = self:GetChecked() and true or false
  end)
  cp:SetPoint("TOPLEFT", 330, -202)
  cp:SetChecked(ns.settings.cheersPopup ~= false)
  local gp = UI.Check(f, "Show the Cross Gambling popup", function(self)
    ns.settings.gamblePopup = self:GetChecked() and true or false
  end)
  gp:SetPoint("TOPLEFT", 330, -226)
  gp:SetChecked(ns.settings.gamblePopup ~= false)
  local dp = UI.Check(f, "Offer to threaten a grudged foe nearby", function(self)
    ns.settings.doomPopup = self:GetChecked() and true or false
  end)
  dp:SetPoint("TOPLEFT", 330, -250)
  dp:SetChecked(ns.settings.doomPopup ~= false)
  local lp = UI.Check(f, "Show Looking for Dwarf popups", function(self)
    ns.settings.lfdPopup = self:GetChecked() and true or false
  end)
  lp:SetPoint("TOPLEFT", 330, -274)
  lp:SetChecked(ns.settings.lfdPopup ~= false)

  local syncTitle = UI.Label(f, "Sync", "GameFontNormal")
  syncTitle:SetPoint("TOPLEFT", 4, -304)
  f.syncInfo = UI.Label(f, "", "GameFontHighlightSmall")
  f.syncInfo:SetPoint("TOPLEFT", 4, -324)
  f.syncInfo:SetPoint("TOPRIGHT", -6, -324)
  f.syncInfo:SetJustifyV("TOP")
  f.syncInfo:SetSpacing(2)
  local syncButton = UI.Button(f, "Sync now", 100, 22, function()
    ns.Comm.RequestSync()
    ns.Print("Asking the hold for the latest records...")
  end)
  syncButton:SetPoint("BOTTOMLEFT", 4, 4)
  local note = UI.Label(f, "Records sync automatically between guildmates who have Ironforged installed.", "GameFontDisableSmall")
  note:SetPoint("LEFT", syncButton, "RIGHT", 10, 0)
end

local function refresh(f)
  local core, guild = Data.Config()
  local officer = ns.IAmOfficer()
  f.guildButton:SetShown(officer)
  f.guildInfo:SetText(string.format(
    "|cffd4a017Hold name:|r %s\n|cffd4a017Officers:|r Longbeards and the guild master\n|cffd4a017Clans:|r %s and above may found one\n|cffd4a017Trials:|r %s and above give trials below %s; Longbeards and the guild master give any trial",
    Data.GuildDisplayName(), ns.RankName(ns.RankSetting("founderRank")),
    ns.RankName(ns.RankSetting("nobleRank")), ns.RankName(ns.RankSetting("nobleRank"))))

  local peers = {}
  local t = GetTime()
  for name, p in pairs(ns.Comm.peers) do
    if t - p.seen < 1800 then peers[#peers + 1] = ns.Name(name) .. " |cff888888" .. p.version .. "|r" end
  end
  table.sort(peers)
  local peerCount = #peers
  if #peers > 12 then
    local extra = #peers - 12
    for i = #peers, 13, -1 do peers[i] = nil end
    peers[#peers + 1] = "and " .. extra .. " more"
  end
  local counts = {}
  for _, c in ipairs(Data.COLLECTIONS) do
    local n = Data.Count(c)
    if n > 0 then counts[#counts + 1] = c .. " " .. n end
  end
  local stats = ns.Comm.stats
  f.syncInfo:SetText(string.format(
    "|cffd4a017Guildmates seen using Ironforged (%d):|r %s\n|cffd4a017Messages:|r %d sent, %d received, %d waiting\n|cffd4a017Last sync:|r %s\n|cffd4a017Records:|r %s",
    peerCount, #peers > 0 and table.concat(peers, ", ") or "none yet",
    stats.sent, stats.received, ns.Comm.QueueLength(),
    stats.lastSync and ns.FormatDateTime(stats.lastSync) or "not yet",
    #counts > 0 and table.concat(counts, ", ") or "none"))
end

UI.RegisterTab("settings", "Settings", build, refresh)
