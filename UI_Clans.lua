-- Ironforged: Clans tab.
-- Any guildmate founds a clan, and anyone may join any clan from its page. A Clan Leader can
-- invite kin (a nudge, not a requirement) and remove members; a removed member can't rejoin
-- until invited again. Only Longbeards and the guild master can delete a clan.
local ADDON, ns = ...
local UI = ns.UI
local Data = ns.Data

local showClan

local function canFound(me)
  return me ~= nil and ns.roster[me] ~= nil -- any guildmate may found a clan
end

local function editClan(id)
  local me = ns.PlayerName()
  local c = id and Data.Get("clans", id) or {}
  local officer = ns.IAmOfficer()
  local fields = {}
  -- the clan leader (or an officer) may rename it; its key stays the founding name's
  fields[#fields + 1] = { key = "name", label = "Clan name", type = "text", value = c.name, maxLen = 40 }
  fields[#fields + 1] = { key = "motto", label = "Motto", type = "text", value = c.motto, maxLen = 80 }
  fields[#fields + 1] = { key = "desc", label = "History", type = "multiline", value = c.desc, maxLen = 600, height = 90 }
  UI.OpenForm({
    title = id and ("Edit clan " .. (c.name or "")) or "Found a clan",
    width = 500,
    fields = fields,
    onSave = function(v)
      local name = ns.Clean(v.name, 40)
      if name == "" or Data.KeyOf(name) == "" then ns.Print("A clan needs a name, and it must suit dwarven roleplay."); return false end
      local newId = id or Data.KeyOf(name)
      -- no two clans may share a name (or the name another was founded under)
      for otherId, other in Data.Each("clans") do
        if otherId ~= newId and (Data.KeyOf(other.name or "") == Data.KeyOf(name) or otherId == Data.KeyOf(name)) then
          ns.Print("A clan called " .. name .. " already exists.")
          return false
        end
      end
      if not id and Data.Get("clans", newId) then
        ns.Print("A clan called " .. name .. " already exists.")
        return false
      end
      local founder = id and c.founder or me
      local firstName = id and (c.firstName or c.name) or nil
      if firstName == name then firstName = (c.firstName and c.firstName ~= name) and c.firstName or nil end
      local ok = Data.Put("clans", newId, {
        name = name, firstName = firstName, motto = ns.Clean(v.motto, 80), desc = ns.Clean(v.desc, 600),
        founder = founder, leader = founder, -- whoever founds the clan leads it
      })
      if ok and not id then
        ns.Print("Clan " .. name .. " is founded. Invite your kin from the clan's page.")
      elseif ok and c.name ~= name then
        ns.Print("Clan " .. (c.name or "?") .. " is now called " .. name .. ".")
      end
    end,
  })
end

UI.EditClan = editClan

local function memberPicker(owner, title, filter, onPick)
  local opts = {}
  for _, name in ipairs(ns.rosterList) do
    if filter(name) then opts[#opts + 1] = { text = ns.Name(name), value = name } end
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
  local invited = Data.InvitedToClan(id, me) and myClan ~= id
  local removed = Data.RemovedFromClan(id, me)

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
    lines[#lines + 1] = "|cff40ff40" .. ns.Name(c.leader) .. " has invited you to join this clan.|r"
  elseif removed then
    lines[#lines + 1] = " "
    lines[#lines + 1] = "|cffff4040You were removed from this clan. Only the Clan Leader can let you back in, by inviting you.|r"
  end

  local buttons = {}
  local function add(text, fn, keepOpen) buttons[#buttons + 1] = { text = text, onClick = fn, keepOpen = keepOpen } end

  if invited then add("Decline", function() Data.Delete("invites", id .. "#" .. me) end) end
  if myClan ~= id and not isLeader and not removed then
    add("Join clan", function()
      if myClan and Data.IsClanLeader(me, myClan) then
        ns.Print("You lead another clan. Hand it over or disband it first.")
        return false
      end
      Data.Put("clanship", me, { clan = id })
      ns.Print("You have sworn yourself to clan " .. c.name .. ".")
    end)
  end
  if officer or isLeader then
    add("Invite", function()
      memberPicker(_G.IronforgedDialog, "Invite to " .. c.name, function(n)
        return Data.ClanOf(n) ~= id and not Data.InvitedToClan(id, n)
      end, function(n)
        Data.Put("invites", id .. "#" .. n, { by = me })
        ns.Print("Invitation sent to " .. ns.Name(n) .. ".")
      end)
      return false
    end, true)
    add("Remove", function()
      memberPicker(_G.IronforgedDialog, "Remove from " .. c.name, function(n)
        return n ~= c.leader and Data.ClanOf(n) == id
      end, function(n)
        Data.Put("invites", id .. "#" .. n, { removed = true, by = me })
        ns.Print(ns.Name(n) .. " is no longer of clan " .. c.name .. ".")
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
  if Data.ICanWrite("clans", id, { name = c.name, firstName = c.firstName, founder = c.founder, leader = c.leader }) then
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


local function build(f, w, h)
  f.newButton = UI.Button(f, "Found a clan", 120, 22, function() editClan(nil) end)
  f.newButton:SetPoint("TOPLEFT", 4, -2)
  f.help = UI.Label(f, "", "GameFontHighlightSmall")
  f.help:SetPoint("TOPLEFT", 132, -7)
  f.help:SetPoint("RIGHT", f, "RIGHT", -8, 0)
  f.help:SetWordWrap(false)
  f.list = UI.List(f, w, h - 30, {
    { title = "Clan", width = 150 }, { title = "Clan Leader", width = 110 }, { title = "Members", width = 60 },
    { title = "Motto", width = 260 },
  }, function(id) showClan(id) end)
  f.list:SetPoint("TOPLEFT", 0, -28)
  f.list:SetPoint("BOTTOMRIGHT", 0, 2)
end

local function refresh(f)
  local me = ns.PlayerName()
  if ns.Comm and ns.Comm.ClanCatchUp and f:IsShown() then pcall(ns.Comm.ClanCatchUp) end
  f.newButton:SetShown(canFound(me))
  f.list:Show()
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
      f.help:SetText("Click a clan to join it, or found your own.")
    else
      f.help:SetText("Click a clan and press Join clan.")
    end
  end

  local items = {}
  for id, c in Data.Each("clans") do
    if c.status ~= "disbanded" then
      items[#items + 1] = {
        data = id, name = c.name or "",
        cols = { "|cffd4a017" .. (c.name or "?") .. "|r", c.leader and ns.Name(c.leader) or "",
          #Data.ClanMembers(id), c.motto or "" },
      }
    end
  end
  table.sort(items, function(a, b) return a.name < b.name end)
  f.list:SetItems(items, "No clans have been founded yet.")
end

UI.RegisterTab("clans", "Clans", build, refresh)
