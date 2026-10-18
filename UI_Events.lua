-- Ironforged: Events, RSVPs and attendance.
local ADDON, ns = ...
local UI = ns.UI
local Data = ns.Data

local state = { showPast = false }

local KINDS = { "Raid", "Dungeon", "Gathering", "Ceremony", "PvP", "Other" }
local STATUS_TEXT = { yes = "|cff40ff40Going|r", maybe = "|cffffd040Maybe|r", no = "|cffff6060Can't|r" }

local function kindOptions()
  local o = {}
  for _, k in ipairs(KINDS) do o[#o + 1] = { text = k, value = k } end
  return o
end

local function editEvent(id)
  local e = id and Data.Get("events", id) or {}
  UI.OpenForm({
    title = id and "Edit event" or "Call a gathering",
    width = 480,
    fields = {
      { key = "title", label = "Name", type = "text", value = e.title, maxLen = 60 },
      { key = "when", label = "When (YYYY-MM-DD HH:MM, your time)", type = "text", value = e.ts and date("%Y-%m-%d %H:%M", e.ts) or date("%Y-%m-%d 20:00", ns.Now() + 86400), maxLen = 16 },
      { key = "kind", label = "Kind", type = "choice", value = e.kind or "Gathering", options = kindOptions() },
      { key = "place", label = "Meeting place", type = "text", value = e.place, maxLen = 60 },
      { key = "desc", label = "Details", type = "multiline", value = e.desc, maxLen = 500, height = 90 },
    },
    onSave = function(v)
      local title = ns.Clean(v.title, 60)
      local ts = ns.ParseDateTime(v.when)
      if title == "" then ns.Print("The event needs a name."); return false end
      if not ts then ns.Print("Use the date format 2026-11-12 19:30."); return false end
      Data.Put("events", id or ns.NewId(), {
        title = title, ts = ts, kind = v.kind, place = ns.Clean(v.place, 60), desc = ns.Clean(v.desc, 500),
        organizer = e.organizer or ns.PlayerName(),
      })
    end,
  })
end

local function setRSVP(eventId, status)
  Data.Put("rsvp", eventId .. "#" .. ns.PlayerName(), { status = status })
end

local function takeAttendance(eventId)
  local present = {}
  local existing = Data.Get("attendance", eventId)
  if existing and existing.present then
    for k, v in pairs(existing.present) do present[k] = v end
  end
  local count = 0
  local function mark(name)
    name = name and ns.Name(name)
    if name and ns.roster[name] and not present[name] then present[name] = true; count = count + 1 end
  end
  if IsInRaid and IsInRaid() then
    for i = 1, GetNumGroupMembers() do mark((GetRaidRosterInfo(i))) end
  elseif IsInGroup and IsInGroup() then
    mark(ns.PlayerName())
    for i = 1, GetNumSubgroupMembers() do
      local n = ns.UnitDisplayName("party" .. i)
      if n then mark(n) end
    end
  else
    for name, info in pairs(ns.roster) do if info.online then mark(name) end end
  end
  Data.Put("attendance", eventId, { present = present })
  ns.Print("Marked " .. count .. " more present.")
end

local function showEvent(id)
  local e = Data.Get("events", id)
  if not e then return end
  local r = Data.RSVPs(id)
  local function names(list)
    local out = {}
    for _, n in ipairs(list) do out[#out + 1] = ns.Name(n) end
    return #out > 0 and table.concat(out, ", ") or "-"
  end
  local lines = {
    "|cffd4a017When:|r " .. ns.FormatDateTime(e.ts),
    "|cffd4a017Kind:|r " .. (e.kind or ""),
  }
  if e.place and e.place ~= "" then lines[#lines + 1] = "|cffd4a017Meet at:|r " .. e.place end
  lines[#lines + 1] = "|cffd4a017Called by:|r " .. ns.Name(e.organizer)
  if e.desc and e.desc ~= "" then lines[#lines + 1] = " "; lines[#lines + 1] = e.desc end
  lines[#lines + 1] = " "
  lines[#lines + 1] = STATUS_TEXT.yes .. " (" .. #r.yes .. "): " .. names(r.yes)
  lines[#lines + 1] = STATUS_TEXT.maybe .. " (" .. #r.maybe .. "): " .. names(r.maybe)
  lines[#lines + 1] = STATUS_TEXT.no .. " (" .. #r.no .. "): " .. names(r.no)
  local a = Data.Get("attendance", id)
  if a and a.present then
    local present = {}
    for n in pairs(a.present) do present[#present + 1] = n end
    table.sort(present)
    lines[#lines + 1] = "|cffd4a017Attended (" .. #present .. "):|r " .. names(present)
  end

  local buttons = {
    { text = "Can't go", onClick = function() setRSVP(id, "no") end },
    { text = "Maybe", onClick = function() setRSVP(id, "maybe") end },
    { text = "Going", onClick = function() setRSVP(id, "yes") end },
  }
  local officerButtons
  if ns.IAmOfficer() then
    officerButtons = {
      { text = "Take attendance", onClick = function() takeAttendance(id); showEvent(id) end, keepOpen = true },
      { text = "Edit", onClick = function() editEvent(id) end },
      { text = "Delete", onClick = function()
        UI.Confirm("Delete \"" .. e.title .. "\"?", function() Data.Delete("events", id) end)
      end },
    }
  end
  UI.OpenForm({
    title = e.title,
    width = 540,
    fields = { { type = "info", value = table.concat(lines, "\n") } },
    buttons = buttons,
  })
  if officerButtons then
    -- Second row of officer buttons above the RSVP row.
    local d = _G.IronforgedDialog
    local x = 16
    for _, ob in ipairs(officerButtons) do
      local gen = d.gen
      local b = UI.Button(d, ob.text, ob.text == "Take attendance" and 120 or 70, 22, function()
        ob.onClick()
        if not ob.keepOpen and d.gen == gen then d:Hide() end
      end)
      b:SetPoint("BOTTOMLEFT", x, 40)
      x = x + b:GetWidth() + 4
      table.insert(d.buttons, b)
    end
    d:SetHeight(d:GetHeight() + 28)
  end
end

local function build(f, w, h)
  f.newButton = UI.Button(f, "New event", 110, 22, function() editEvent(nil) end)
  f.newButton:SetPoint("TOPLEFT", 4, -2)
  local past = UI.Check(f, "Show past events", function(self)
    state.showPast = self:GetChecked() and true or false
    UI.ScheduleRefresh()
  end)
  past:SetPoint("TOPRIGHT", -130, -1)

  f.list = UI.List(f, w, h - 30, {
    { title = "When", width = 128 }, { title = "Event", width = 196 }, { title = "Kind", width = 72 },
    { title = "Going", width = 46 }, { title = "Maybe", width = 46 }, { title = "You", width = 80 },
  }, function(id) showEvent(id) end)
  f.list:SetPoint("TOPLEFT", 0, -28)
  f.list:SetPoint("BOTTOMRIGHT", 0, 2)
end

local function refresh(f)
  f.newButton:SetShown(ns.IAmOfficer())
  local me = ns.PlayerName()
  local cutoff = ns.Now() - 3 * 3600
  local items = {}
  for id, e in Data.Each("events") do
    local upcoming = (e.ts or 0) >= cutoff
    if upcoming ~= state.showPast then
      local r = Data.RSVPs(id)
      local mine = Data.Get("rsvp", id .. "#" .. me)
      items[#items + 1] = {
        data = id, ts = e.ts or 0, keys = { [1] = e.ts or 0 },
        color = upcoming and nil or { 0.6, 0.6, 0.6 },
        cols = { ns.FormatDateTime(e.ts), e.title or "", e.kind or "", #r.yes, #r.maybe,
          mine and STATUS_TEXT[mine.status] or "|cff888888-|r" },
      }
    end
  end
  table.sort(items, function(a, b)
    if state.showPast then return a.ts > b.ts end
    return a.ts < b.ts
  end)
  f.list:SetItems(items, state.showPast and "No past events." or "Nothing on the calendar.")
end

UI.RegisterTab("events", "Events", build, refresh)
