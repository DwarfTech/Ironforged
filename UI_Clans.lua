-- Ironforged: Clans tab.
-- Veterans and above found clans. Members join by the Clan Leader's invitation, or by
-- asking to join and being accepted from the Applications view.
-- Only Longbeards and the guild master can delete a clan.
local ADDON, ns = ...
local UI = ns.UI
local Data = ns.Data

local showClan

local function canFound(me)
  return ns.IsOfficer(me) or ns.RankAtLeast(me, ns.RankSetting("founderRank"))
end

local function editClan(id)
  local me = ns.PlayerName()
  local c = id and Data.Get("clans", id) or {}
  local officer = ns.IAmOfficer()
  local fields = {
    { key = "name", label = "Clan name", type = "text", value = c.name, maxLen = 40 },
    { key = "motto", label = "Motto", type = "text", value = c.motto, maxLen = 80 },
    { key = "desc", label = "History", type = "multiline", value = c.desc, maxLen = 600, height = 90 },
  }
  UI.OpenForm({
    title = id and ("Edit clan " .. (c.name or "")) or "Found a clan",
    width = 500,
    fields = fields,
    onSave = function(v)
      local name = ns.Clean(v.name, 40)
      if name == "" then ns.Print("A clan needs a name, and it must suit dwarven roleplay."); return false end
      local newId = id or (me .. "#" .. ns.NewId())
      local ok = Data.Put("clans", newId, {
        name = name, motto = ns.Clean(v.motto, 80), desc = ns.Clean(v.desc, 600),
        leader = Data.ClanFounder(newId), -- whoever founds the clan leads it
      })
      if ok and not id then
        ns.Print("Clan " .. name .. " is founded. Invite your kin from the clan's page.")
      end
    end,
  })
end

local function memberPicker(owner, title, filter, onPick)
  local opts = {}
  for _, name in ipairs(ns.rosterList) do
    if filter(name) then opts[#opts + 1] = { text = ns.ShortName(name), value = name } end
  end
  if #opts == 0 then ns.Print("Nobody to choose."); return end
  UI.Pick(owner, opts, onPick, title)
end

showClan = function(id)
  local c = Data.Clan(id)
  if not c then return end
  local me = ns.PlayerName()
  local officer = ns.IAmOfficer()
  local isLeader = c.leader == me
  local members = Data.ClanMembers(id)
  local myClan = Data.ClanOf(me)
  local invited = Data.Get("invites", id .. "#" .. me) ~= nil and myClan ~= id
  local applied = Data.Get("applications", id .. "#" .. me) ~= nil and myClan ~= id

  local names = {}
  for _, n in ipairs(members) do
    names[#names + 1] = ns.ColorName(n) .. (n == c.leader and " |cff999999(leader)|r" or "")
  end
  local lines = {}
  if c.motto and c.motto ~= "" then lines[#lines + 1] = "|cffd4a017\"" .. c.motto .. "\"|r" end
  lines[#lines + 1] = "|cffd4a017Clan Leader:|r " .. (c.leader and ns.ColorName(c.leader) or "?")
  if c.desc and c.desc ~= "" then lines[#lines + 1] = " "; lines[#lines + 1] = c.desc end
  lines[#lines + 1] = " "
  lines[#lines + 1] = "|cffd4a017Members (" .. #members .. "):|r " .. (#names > 0 and table.concat(names, ", ") or "none yet")
  if invited then
    lines[#lines + 1] = " "
    lines[#lines + 1] = "|cff40ff40" .. ns.ShortName(c.leader) .. " has invited you to join this clan.|r"
  elseif applied then
    lines[#lines + 1] = " "
    lines[#lines + 1] = "|cffffd040You have asked to join. The Clan Leader will answer.|r"
  end

  local buttons = {}
  local function add(text, fn, keepOpen) buttons[#buttons + 1] = { text = text, onClick = fn, keepOpen = keepOpen } end

  if invited then
    add("Decline", function() Data.Delete("invites", id .. "#" .. me) end)
    add("Join clan", function()
      if myClan and myClan ~= id and Data.IsClanLeader(me, myClan) then
        ns.Print("You lead another clan. Hand it over or disband it first.")
        return false
      end
      Data.Put("clanship", me, { clan = id })
      ns.Print("You have sworn yourself to clan " .. c.name .. ".")
    end)
  end
  if not invited and myClan ~= id and not isLeader then
    if applied then
      add("Withdraw", function() Data.Delete("applications", id .. "#" .. me) end)
    else
      add("Ask to join", function()
        UI.OpenForm({
          title = "Ask to join clan " .. c.name,
          fields = {
            { type = "info", font = "GameFontHighlightSmall", value = ns.ShortName(c.leader) .. " leads this clan and will accept or deny you." },
            { key = "note", label = "Why you'd join", type = "multiline", value = "", maxLen = 200, height = 70 },
          },
          saveText = "Send",
          onSave = function(v)
            Data.Put("applications", id .. "#" .. me, { note = ns.Clean(v.note, 200), ts = ns.Now() })
            ns.Print("Your request to join clan " .. c.name .. " has been sent.")
          end,
        })
      end)
    end
  end
  if officer or isLeader then
    add("Invite", function()
      memberPicker(_G.IronforgedDialog, "Invite to " .. c.name, function(n)
        return Data.ClanOf(n) ~= id and not Data.Get("invites", id .. "#" .. n)
      end, function(n)
        Data.Put("invites", id .. "#" .. n, { by = me })
        ns.Print("Invitation sent to " .. ns.ShortName(n) .. ".")
      end)
      return false
    end, true)
    add("Remove", function()
      memberPicker(_G.IronforgedDialog, "Remove from " .. c.name, function(n)
        return n ~= c.leader and Data.ClanOf(n) == id
      end, function(n)
        Data.Delete("invites", id .. "#" .. n)
        showClan(id)
      end)
      return false
    end, true)
  end
  if myClan == id and not isLeader then
    add("Leave clan", function()
      UI.Confirm("Leave clan " .. c.name .. "?", function()
        Data.Put("clanship", me, {})
        Data.Delete("invites", id .. "#" .. me)
        if Data.Get("applications", id .. "#" .. me) then Data.Delete("applications", id .. "#" .. me) end
      end)
    end)
  end
  if Data.ICanWrite("clans", id, { leader = c.leader }) then
    add("Edit", function() editClan(id) end)
  end
  if Data.ICanWrite("clans", id, nil) then
    add("Delete clan", function()
      UI.Confirm("Delete clan " .. c.name .. "? Its members become clanless.", function()
        Data.Delete("clans", id)
      end)
    end)
  end

  UI.OpenForm({ title = "Clan " .. c.name, width = 620, fields = { { type = "info", value = table.concat(lines, "\n") } }, buttons = buttons })
end
UI.ShowClan = showClan

local state = { view = "clans" }

local function visibleApplications(me)
  if ns.IAmOfficer() then return Data.Applications() end
  local out = {}
  for _, clanId in ipairs(Data.ClansLedBy(me)) do
    for _, a in ipairs(Data.Applications(clanId)) do out[#out + 1] = a end
  end
  return out
end

local function showApplication(key)
  local a = Data.Get("applications", key)
  if not a then return end
  local clanId, member = Data.SplitKey(key)
  local info = ns.roster[member] or {}
  local lines = {
    "|cffd4a017Wants to join:|r clan " .. (Data.ClanName(clanId) or "?"),
    "|cffd4a017Rank:|r " .. (info.rankName or "?") .. "   |cffd4a017Level:|r " .. tostring(info.level or "?"),
    "|cffd4a017Race:|r " .. ns.Gear.RaceStatus(member) .. "   |cffd4a017Asked:|r " .. ns.FormatDate(a.ts),
  }
  local current = Data.ClanOf(member)
  if current then lines[#lines + 1] = "|cffffd040Already in clan " .. Data.ClanName(current) .. ".|r" end
  if a.note and a.note ~= "" then lines[#lines + 1] = " "; lines[#lines + 1] = a.note end
  UI.OpenForm({
    title = ns.ColorName(member) .. " asks to join",
    width = 500,
    fields = { { type = "info", value = table.concat(lines, "\n") } },
    buttons = {
      { text = "Deny", onClick = function()
        Data.Delete("applications", key)
        ns.Print("Denied " .. ns.ShortName(member) .. ".")
      end },
      { text = "Accept", onClick = function()
        if Data.Put("invites", key, { by = ns.PlayerName() }) then
          ns.Print(ns.ShortName(member) .. " is now of clan " .. (Data.ClanName(clanId) or "?") .. ".")
        end
      end },
    },
  })
end

local function build(f, w, h)
  f.newButton = UI.Button(f, "Found a clan", 120, 22, function() editClan(nil) end)
  f.newButton:SetPoint("TOPLEFT", 4, -2)
  f.appsButton = UI.Button(f, "Applications", 130, 22, function()
    state.view = state.view == "apps" and "clans" or "apps"
    UI.ScheduleRefresh()
  end)
  f.appsButton:SetPoint("TOPRIGHT", -4, -2)
  f.help = UI.Label(f, "", "GameFontHighlightSmall")
  f.help:SetPoint("TOPLEFT", 132, -7)
  f.help:SetPoint("RIGHT", f.appsButton, "LEFT", -8, 0)
  f.help:SetWordWrap(false)
  f.list = UI.List(f, w, h - 30, {
    { title = "Clan", width = 150 }, { title = "Clan Leader", width = 110 }, { title = "Members", width = 60 },
    { title = "Motto", width = 260 },
  }, function(id) showClan(id) end)
  f.list:SetPoint("TOPLEFT", 0, -28)
  f.apps = UI.List(f, w, h - 30, {
    { title = "Applicant", width = 130 }, { title = "Rank", width = 90 }, { title = "Clan", width = 130 },
    { title = "Asked", width = 80 }, { title = "Note", width = 150 },
  }, function(key) showApplication(key) end)
  f.apps:SetPoint("TOPLEFT", 0, -28)
  f.apps:Hide()
end

local function refresh(f)
  local me = ns.PlayerName()
  f.newButton:SetShown(canFound(me))
  local apps = visibleApplications(me)
  local canAnswer = ns.IAmOfficer() or #Data.ClansLedBy(me) > 0
  f.appsButton:SetShown(canAnswer)
  if not canAnswer then state.view = "clans" end
  f.appsButton:SetText(state.view == "apps" and "Back to clans" or ("Applications (" .. #apps .. ")"))
  if state.view == "apps" then
    f.list:Hide(); f.apps:Show()
    f.help:SetText("Click an applicant to accept or deny them.")
    local items = {}
    for _, a in ipairs(apps) do
      local info = ns.roster[a.member] or {}
      items[#items + 1] = { data = a.key, cols = { ns.ColorName(a.member), info.rankName or "", Data.ClanName(a.clan) or "",
        ns.FormatDate(a.data.ts), ((a.data.note or ""):gsub("\n", " ")) } }
    end
    f.apps:SetItems(items, "No one is asking to join right now.")
    return
  end
  f.apps:Hide(); f.list:Show()
  local invites = Data.PendingInvites(me)
  if #invites > 0 then
    local names = {}
    for _, id in ipairs(invites) do names[#names + 1] = Data.ClanName(id) end
    f.help:SetText("|cff40ff40You're invited to join: " .. table.concat(names, ", ") .. ". Click the clan to answer.|r")
  else
    local clanId = Data.ClanOf(me)
    if clanId then
      f.help:SetText("You belong to clan |cffd4a017" .. Data.ClanName(clanId) .. "|r.")
    elseif canFound(me) then
      f.help:SetText("Found a clan, then invite your kin from the clan's page.")
    else
      f.help:SetText("Click a clan and press Ask to join. " .. ns.RankName(ns.RankSetting("founderRank")) .. "s and above may found one.")
    end
  end

  local items = {}
  for id, c in Data.Each("clans") do
    if c.status ~= "disbanded" then
      items[#items + 1] = {
        data = id, name = c.name or "",
        cols = { "|cffd4a017" .. (c.name or "?") .. "|r", c.leader and ns.ShortName(c.leader) or "",
          #Data.ClanMembers(id), c.motto or "" },
      }
    end
  end
  table.sort(items, function(a, b) return a.name < b.name end)
  f.list:SetItems(items, "No clans have been founded yet.")
end

UI.RegisterTab("clans", "Clans", build, refresh)
