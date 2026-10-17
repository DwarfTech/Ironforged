-- Ironforged: Roster tab.
local ADDON, ns = ...
local UI = ns.UI
local Data = ns.Data

local state = { search = "", onlineOnly = false, problemsOnly = false }

function UI.EditMember(name)
  local m = Data.Member(name)
  UI.OpenForm({
    title = "Hold record: " .. ns.ShortName(name),
    fields = {
      { key = "main", label = "Alt of", type = "choice", value = m.main or false, options = UI.RosterOptions(true) },
      { key = "joined", label = "Joined (YYYY-MM-DD)", type = "text", value = m.joined, maxLen = 10 },
      { key = "note", label = "Hold record (guild can see)", type = "multiline", value = m.note, maxLen = 400, height = 70 },
    },
    onSave = function(v)
      Data.Put("members", name, {
        title = m.title, -- titles are awarded separately now; keep any old one
        main = (v.main and v.main ~= name) and v.main or nil,
        joined = ns.Clean(v.joined, 10),
        note = ns.Clean(v.note, 400),
      })
    end,
  })
end

-- Blizzard only lets promotions and removals run from something the player typed or clicked in
-- Blizzard's own UI. Anything an addon puts in the chat box or opens for you is "tainted" and
-- gets blocked. So the addon only hands you the command to copy: you paste it and press Enter.
function UI.CopyCommand(command, what)
  UI.OpenForm({
    title = what,
    width = 500,
    fields = {
      { type = "info", value = "Press |cffd4a017Ctrl+C|r to copy and |cffd4a017Enter|r to close this box. Then press |cffd4a017Enter|r to open chat, |cffd4a017Ctrl+V|r to paste, and |cffd4a017Enter|r to run it." },
      { key = "cmd", label = "Command", type = "text", value = command, maxLen = 80, select = true },
      { type = "info", font = "GameFontDisableSmall",
        value = "Or open the guild window yourself (the guild key, J by default), right-click the name, and choose from the menu." },
    },
  })
end

function UI.ManageInGuildWindow(name)
  local short = ns.ShortName(name)
  local info = ns.roster[name] or {}
  UI.OpenForm({
    title = "Manage " .. short,
    width = 520,
    fields = { { type = "info", value = "|cffd4a017" .. short .. "|r  (" .. (info.rankName or "?") .. ", level " .. tostring(info.level or "?") .. ")" ..
      "\n\nBlizzard only lets you promote, demote or remove someone with a command you type yourself, or from its own guild window. Pick one and the addon gives you the command to copy." } },
    buttons = {
      { text = "Remove", onClick = function() UI.CopyCommand("/gremove " .. short, "Remove " .. short) end },
      { text = "Demote", onClick = function() UI.CopyCommand("/gdemote " .. short, "Demote " .. short) end },
      { text = "Promote", onClick = function() UI.CopyCommand("/gpromote " .. short, "Promote " .. short) end },
    },
  })
end

-- Award a title to a guildmate (officers).
function UI.AwardTitle(name)
  local opts = {}
  for _, t in ipairs(ns.Titles.PRESETS) do opts[#opts + 1] = { text = t, value = t } end
  opts[#opts + 1] = { text = "Custom (type it below)", value = false }
  UI.OpenForm({
    title = "Award a title to " .. ns.ShortName(name),
    width = 480,
    fields = {
      { key = "preset", label = "Title", type = "choice", value = ns.Titles.PRESETS[1], options = opts },
      { key = "custom", label = "Or a custom title", type = "text", value = "", maxLen = 40 },
      { key = "reason", label = "For (optional)", type = "text", value = "", maxLen = 120 },
    },
    saveText = "Award",
    onSave = function(v)
      local title = ns.Trim(v.custom or "") ~= "" and v.custom or v.preset
      if not title then ns.Print("Pick a title or type one."); return false end
      return ns.Titles.Award(name, title, v.reason) and true or false
    end,
  })
end

function UI.StripTitle(name)
  local opts = {}
  for _, t in ipairs(ns.Titles.Of(name)) do
    if t.key then opts[#opts + 1] = { text = t.title, value = t.key } end
  end
  if #opts == 0 then ns.Print("They hold no awarded titles. Automatic titles move on their own."); return end
  UI.OpenForm({
    title = "Strip a title from " .. ns.ShortName(name),
    width = 440,
    fields = { { key = "key", label = "Title", type = "choice", value = opts[1].value, options = opts } },
    saveText = "Strip",
    onSave = function(v) if v.key then ns.Titles.Strip(v.key) end end,
  })
end

-- opts.noManage: leave out Edit record and Manage (used where they don't belong, like the Blood Tally).
function UI.ShowMember(name, opts)
  opts = opts or {}
  local info = ns.roster[name] or {}
  local m = Data.Member(name)
  local p = Data.Profile(name) or {}
  local report = Data.SelfReport(name)
  local lines = {}
  local function add(label, value)
    if value and value ~= "" then lines[#lines + 1] = "|cffd4a017" .. label .. ":|r " .. value end
  end

  add("Rank", info.rankName)
  add("Level", info.level and (info.level .. " " .. (info.className or "")) or nil)
  add("Race", ns.Gear.RaceStatus(name) .. (report and report.race and (" |cff999999(" .. report.race .. ")|r") or ""))
  local inviters = ns.Gear.InvitersOf(name)
  if #inviters > 0 then
    local short = {}
    for _, n in ipairs(inviters) do short[#short + 1] = ns.ShortName(n) end
    add("Invited by", table.concat(short, ", "))
  end
  local shame = ns.Gear.NonDwarfInvites(name)
  if #shame > 0 then add("|cffff4040Invited non-dwarves|r", "|cffff4040" .. table.concat(shame, ", ") .. "|r") end
  add("Where", info.online and info.zone or ns.LastSeenText(info))
  local clanId = Data.ClanOf(name)
  if clanId then
    add("Clan", Data.ClanName(clanId) .. (Data.IsClanLeader(name, clanId) and " |cff999999(Clan Leader)|r" or ""))
  end
  local tl = {}
  for _, t in ipairs(ns.Titles.Of(name)) do
    tl[#tl + 1] = "|cffffd040" .. t.title .. "|r" .. ((t.reason and t.reason ~= "") and (" |cff999999(" .. t.reason .. ")|r") or "")
  end
  add("Titles", table.concat(tl, ", "))
  if m.main then add("Alt of", ns.ShortName(m.main)) end
  local alts = {}
  for other, om in Data.Each("members") do
    if om.main == name then alts[#alts + 1] = ns.ShortName(other) end
  end
  table.sort(alts)
  add("Alts", table.concat(alts, ", "))
  add("Joined", m.joined)
  local attended, total = Data.AttendanceCount(name)
  if total > 0 then add("Attendance", attended .. " of " .. total .. " events") end
  local hk, elves, avenged = ns.Blood.Tally(name)
  if hk then add("Blood Tally", hk .. " Horde slain, " .. elves .. " elves slain, " .. avenged .. " grudges avenged") end
  for _, t in ipairs(Data.AssignedTrials(name)) do
    add("Trial", t.title .. " (" .. ns.RankName(t.rank) .. ") - " .. t.done .. "/" .. t.total ..
      (t.done == t.total and t.total > 0 and " |cff40ff40(complete)|r" or ""))
  end
  if Data.Get("requests", name) then add("Promotion", "|cffffd040requested|r") end


  add("Public note", info.publicNote)
  if info.officerNote and info.officerNote ~= "" then add("Officer note", info.officerNote) end
  add("Hold record", m.note)
  if p.backstory and p.backstory ~= "" then
    lines[#lines + 1] = " "
    lines[#lines + 1] = "|cffd4a017Backstory:|r"
    lines[#lines + 1] = p.backstory
  end

  local buttons = {}
  if ns.IAmOfficer() then
    local hasAwarded = false
    for _, t in ipairs(ns.Titles.Of(name)) do if t.key then hasAwarded = true end end
    if hasAwarded then buttons[#buttons + 1] = { text = "Strip title", onClick = function() UI.StripTitle(name) end } end
    buttons[#buttons + 1] = { text = "Award title", onClick = function() UI.AwardTitle(name) end }
  end
  if ns.IAmOfficer() and not opts.noManage then
    buttons[#buttons + 1] = { text = "Edit record", onClick = function() UI.EditMember(name) end }
    if name ~= ns.PlayerName() then
      buttons[#buttons + 1] = { text = "Manage", onClick = function() UI.ManageInGuildWindow(name) end }
    end
  end
  UI.OpenForm({
    title = ns.ColorName(name),
    width = 500,
    fields = { { type = "info", value = table.concat(lines, "\n") } },
    buttons = buttons,
  })
end

local function build(f, w, h)
  local search = UI.EditBox(f, 170, 40)
  search:SetPoint("TOPLEFT", 6, -2)
  local hint = UI.Label(search, "Search names, clans, titles", "GameFontDisableSmall")
  hint:SetPoint("LEFT", 4, 0)
  search:SetScript("OnTextChanged", function(self)
    state.search = self:GetText():lower()
    hint:SetShown(self:GetText() == "")
    UI.ScheduleRefresh()
  end)

  local online = UI.Check(f, "Online only", function(self)
    state.onlineOnly = self:GetChecked() and true or false
    UI.ScheduleRefresh()
  end)
  online:SetPoint("LEFT", search, "RIGHT", 10, 0)
  local problems = UI.Check(f, "Rule problems", function(self)
    state.problemsOnly = self:GetChecked() and true or false
    UI.ScheduleRefresh()
  end)
  UI.SetRosterProblems = function(on)
    state.problemsOnly = on and true or false
    problems:SetChecked(state.problemsOnly)
  end
  problems:SetPoint("LEFT", online, "RIGHT", 84, 0)

  f.scan = UI.Button(f, "Scan races", 90, 22, function() ns.Gear.ScanGuild() end)
  f.scan:SetPoint("TOPRIGHT", -2, -2)
  f.count = UI.Label(f, "", "GameFontHighlightSmall")
  f.count:SetPoint("RIGHT", f.scan, "LEFT", -8, 0)

  f.list = UI.List(f, w, h - 30, {
    { title = "Name", width = 180 }, { title = "Rank", width = 84 }, { title = "Lvl", width = 28 },
    { title = "Clan", width = 100 }, { title = "Title", width = 86 }, { title = "Race", width = 46 },
    { title = "Seen", width = 62 },
  }, function(name) UI.ShowMember(name) end)
  f.list:SetPoint("TOPLEFT", 0, -28)
end

local function refresh(f)
  local items, shown, online = {}, 0, 0
  for _, name in ipairs(ns.rosterList) do
    local info = ns.roster[name]
    local m = Data.Member(name)
    local clan = Data.ClanName(Data.ClanOf(name)) or ""
    if info.online then online = online + 1 end
    local report = Data.SelfReport(name)
    local shamed = #ns.Gear.NonDwarfInvites(name) > 0
    local problem = ns.Gear.IsDwarf(name) == false or shamed
    local titles = ns.Titles.Of(name)
    local hay = (name .. " " .. clan .. " " .. ns.Titles.Text(name, " ")):lower()
    if (not state.onlineOnly or info.online) and (not state.problemsOnly or problem)
      and (state.search == "" or hay:find(state.search, 1, true)) then
      local display = ns.ColorName(name)
      if m.main then display = display .. " |cff888888(alt)|r" end
      if shamed then display = display .. " |cffff4040(shamed)|r" end
      if ns.Gear.IsDwarf(name) == false then
        local by = ns.Gear.InvitersOf(name)
        if #by > 0 then display = display .. " |cffff4040(invited by " .. ns.ShortName(by[1]) .. ")|r" end
      end
      items[#items + 1] = {
        data = name,
        sortRank = info.rankIndex or 99,
        keys = { [1] = ns.NameKey(name), [2] = info.rankIndex or 99, [7] = ns.SeenKey(info) },
        cols = { display, info.rankName or "", info.level or "", clan, titles[1] and (titles[1].title .. (#titles > 1 and (" |cff999999+" .. (#titles - 1) .. "|r") or "")) or "",
          ns.Gear.RaceStatus(name), ns.LastSeenText(info) },
      }
      shown = shown + 1
    end
  end
  table.sort(items, function(a, b)
    if a.sortRank ~= b.sortRank then return a.sortRank < b.sortRank end
    return a.data < b.data
  end)
  f.list:SetItems(items, "No guildmates match.")
  f.count:SetText(string.format("%d shown  |cff40ff40%d online|r", shown, online))
end

UI.RegisterTab("roster", "Roster", build, refresh)
