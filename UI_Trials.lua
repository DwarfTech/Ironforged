-- Ironforged: Promotions tab.
-- A promotion trial is given straight to a member: the rank it earns plus a list of tasks.
-- Nobles and above give trials for ranks below Noble; Longbeards and the guild master give any.
-- Members may request a promotion, but a trial can be given without a request.
-- Everyone can see every character's trial.
local ADDON, ns = ...
local UI = ns.UI
local Data = ns.Data

local MAX_TASKS = 10
local state = { key = nil }

-- Suggested tasks by rank name, used when the giver leaves the task list blank.
local STARTER_TASKS = {
  { "ironguard", { "Claim the blood of the Horde", "Attend one of the guild's RP events" } },
  { "vanguard", { "Write your backstory in the Ironforged addon", "Attend a guild event" } },
  { "veteran", { "60 days active in the community", "Complete a complicated Veteran trial or a mighty achievement with the guild" } },
  { "general", { "6 months active in the community", "Lead guildmates into battle" } },
  { "noble", { "1 year active in the community", "Complete the Noble trial" } },
  { "overlord", { "3 years active in the community", "Complete the Overlord trial" } },
  { "lord", { "2 years active in the community", "Show lasting dedication to the guild", "Complete the Lord trial" } },
}

local function starterTasks(rank)
  local name = (ns.ranks[rank] or ""):lower()
  for _, s in ipairs(STARTER_TASKS) do
    if name:find(s[1], 1, true) then return s[2] end
  end
  return { "Complete the trial set by your officer" }
end

local function taskId(text)
  return string.format("%x", ns.Hash(text) % 0xFFFFFF)
end

local function parseTasks(text)
  local tasks, seen = {}, {}
  for line in (text or ""):gmatch("[^\r\n]+") do
    local t = ns.Clean(line, 100)
    if t ~= "" and #tasks < MAX_TASKS then
      local id = taskId(t)
      if not seen[id] then seen[id] = true; tasks[#tasks + 1] = { id = id, text = t } end
    end
  end
  return tasks
end

-- All guild ranks, top to bottom.
local function rankOptions()
  local opts = {}
  for i = 0, 10 do
    if ns.ranks[i] then opts[#opts + 1] = { text = ns.ranks[i], value = i } end
  end
  return opts
end

local function memberOptions(me)
  local opts = {}
  for _, name in ipairs(ns.rosterList) do
    if name ~= me or ns.IsGuildMaster(me) then
      opts[#opts + 1] = { text = ns.Name(name) .. " (" .. (ns.roster[name].rankName or "") .. ")", value = name }
    end
  end
  return opts
end

local function noPermissionText()
  return "You can give trials for ranks below " .. ns.RankName(ns.RankSetting("nobleRank")) ..
    ". Longbeards and the guild master give the higher trials."
end

-- Give a new trial (key == nil) or edit an existing one.
local function trialForm(member, key)
  local me = ns.PlayerName()
  local t = key and Data.Get("progress", key) or {}
  local taskLines = {}
  for _, task in ipairs(t.tasks or {}) do taskLines[#taskLines + 1] = task.text end
  local fields = {}
  if not key then
    fields[#fields + 1] = { key = "member", label = "Give it to", type = "choice", value = member or false,
      options = memberOptions(me), none = "(choose a member)" }
  end
  fields[#fields + 1] = { key = "rank", label = "Earns the rank", type = "choice", value = t.rank, options = rankOptions(), none = "(choose a rank)" }
  fields[#fields + 1] = { key = "title", label = "Trial name (optional)", type = "text", value = t.title, maxLen = 50 }
  fields[#fields + 1] = { key = "desc", label = "Details (optional)", type = "multiline", value = t.desc, maxLen = 400, height = 50 }
  fields[#fields + 1] = { key = "tasks", label = "Tasks, one per line (blank = suggested tasks)", type = "multiline",
    value = table.concat(taskLines, "\n"), maxLen = 1200, height = 130 }

  UI.OpenForm({
    title = key and ("Edit " .. ns.Name(key) .. "'s trial") or "Give a promotion trial",
    width = 540,
    fields = fields,
    saveText = key and "Save" or "Give trial",
    onSave = function(v)
      local who = key or v.member
      if not who then ns.Print("Choose who gets the trial."); return false end
      if type(v.rank) ~= "number" then ns.Print("Choose the rank this trial earns."); return false end
      if not Data.CanGiveTrial(me, who, v.rank) then
        ns.Print(who == me and "You can't give yourself a trial." or noPermissionText())
        return false
      end
      local tasks = parseTasks(v.tasks)
      if #tasks == 0 then tasks = parseTasks(table.concat(starterTasks(v.rank), "\n")) end
      local title = ns.Clean(v.title, 50)
      if title == "" then title = ns.RankName(v.rank) .. " Trial" end
      local newKey = key or who -- a character has one trial at a time
      local done = {}
      for _, task in ipairs(tasks) do
        if t.done and t.done[task.id] then done[task.id] = true end
      end
      if Data.Put("progress", newKey, { title = title, rank = v.rank, desc = ns.Clean(v.desc, 400), tasks = tasks, done = done }) then
        state.key = newKey
        if not key then
          if Data.Get("requests", who) then Data.Delete("requests", who) end
          ns.Print(ns.Name(who) .. " begins the " .. title .. ".")
        end
      end
    end,
  })
end
UI.GiveTrial = function(member) trialForm(member, nil) end

-- Remove a finished trial (and the member's own task marks) for everyone.
function UI.ClearTrial(key)
  local member = key
  local t = Data.Get("progress", key)
  if not Data.Delete("progress", key) then return false end
  if Data.Get("taskmarks", key) then Data.Delete("taskmarks", key) end
  if state.key == key then state.key = nil end
  ns.Print(ns.Name(member) .. "'s " .. ((t and t.title) or "trial") .. " is complete and cleared.")
  return true
end

-- Once a trial's tasks are all done and the member holds its rank, the promotion has been given:
-- the client of someone who could give that trial clears it from the list automatically.
local function sweepFinished()
  if not Data.Ready() then return end
  local me = ns.PlayerName()
  if not Data.CanGiveTrials(me) then return end
  for _, a in ipairs(Data.AssignedTrials()) do
    local t = Data.Get("progress", a.key)
    if t and Data.CanGiveTrial(me, a.member, t.rank) then
      local current = ns.RankIndexOf(a.member)
      local promoted = current ~= nil and type(t.rank) == "number" and current <= t.rank
      if t.completed or (promoted and a.total > 0 and a.done == a.total) then UI.ClearTrial(a.key) end
    end
  end
end
UI.SweepFinishedTrials = sweepFinished
ns.On("ROSTER", function() if C_Timer then C_Timer.After(1, sweepFinished) else sweepFinished() end end)

local function requestPromotion()
  local me = ns.PlayerName()
  if Data.Get("requests", me) then
    UI.Confirm("Withdraw your promotion request?", function() Data.Delete("requests", me) end)
    return
  end
  UI.OpenForm({
    title = "Request a promotion",
    fields = {
      { type = "info", font = "GameFontHighlightSmall",
        value = "Tell the hold which rank you're seeking and why. A Noble or higher will set you a trial." },
      { key = "note", label = "Your request", type = "multiline", value = "", maxLen = 200, height = 70 },
    },
    saveText = "Request",
    onSave = function(v)
      Data.Put("requests", me, { note = ns.Clean(v.note, 200), ts = ns.Now() })
      ns.Print("Your request has been heard. Watch for a trial.")
    end,
  })
end

local function showRequests()
  local reqs = {}
  for name, r in Data.Each("requests") do reqs[#reqs + 1] = { name = name, r = r } end
  table.sort(reqs, function(a, b) return (a.r.ts or 0) < (b.r.ts or 0) end)
  local lines = {}
  for _, q in ipairs(reqs) do
    local info = ns.roster[q.name] or {}
    lines[#lines + 1] = ns.ColorName(q.name) .. " |cff999999(" .. (info.rankName or "?") .. ", " .. ns.FormatDate(q.r.ts) .. ")|r"
    if q.r.note and q.r.note ~= "" then lines[#lines + 1] = "   " .. q.r.note end
  end
  if #lines == 0 then lines[1] = "No one is waiting on a promotion." end
  local opts = {}
  for _, q in ipairs(reqs) do opts[#opts + 1] = { text = ns.Name(q.name), value = q.name } end
  local buttons
  if #opts > 0 then
    buttons = {
      { text = "Dismiss", keepOpen = true, onClick = function()
        UI.Pick(_G.IronforgedDialog, opts, function(name) Data.Delete("requests", name); showRequests() end, "Dismiss request")
      end },
      { text = "Give trial", keepOpen = true, onClick = function()
        UI.Pick(_G.IronforgedDialog, opts, function(name) trialForm(name, nil) end, "Give a trial to")
      end },
    }
  end
  UI.OpenForm({ title = "Promotion requests", width = 500, fields = { { type = "info", value = table.concat(lines, "\n") } }, buttons = buttons })
end

local function build(f, w, h)
  local leftW = 290
  f.requestButton = UI.Button(f, "Request promotion", 140, 22, requestPromotion)
  f.requestButton:SetPoint("TOPLEFT", 4, -2)
  f.giveButton = UI.Button(f, "Give a trial", 110, 22, function() trialForm(nil, nil) end)
  f.giveButton:SetPoint("LEFT", f.requestButton, "RIGHT", 4, 0)
  f.requestsButton = UI.Button(f, "Requests", 110, 22, showRequests)
  f.requestsButton:SetPoint("LEFT", f.giveButton, "RIGHT", 4, 0)

  f.list = UI.List(f, leftW, h - 30, {
    { title = "Character", width = 104 }, { title = "Earns", width = 86 }, { title = "Done", width = 70 },
  }, function(key)
    state.key = key
    UI.ScheduleRefresh()
  end)
  f.list:SetPoint("TOPLEFT", 0, -28)
  f.list:SetPoint("BOTTOMLEFT", 0, 2)

  local panel = CreateFrame("Frame", nil, f, "BackdropTemplate")
  panel:SetPoint("TOPLEFT", f.list, "TOPRIGHT", 8, 0)
  panel:SetPoint("BOTTOMRIGHT", 0, 0)
  UI.Backdrop(panel, true)
  f.panel = panel
  local pw = w - leftW - 8
  -- text lines are as wide as the panel less a margin; kept current as the window resizes
  local wide = {}
  local function track(fs, margin) wide[#wide + 1] = { fs, margin } end
  f:HookScript("OnSizeChanged", function(_, fw)
    if fw and fw > 0 then f.list:SetWidth(math.max(160, math.floor(fw * leftW / w + 0.5))) end
  end)
  panel:HookScript("OnSizeChanged", function(_, panelW)
    if not panelW or panelW <= 0 then return end
    for _, e in ipairs(wide) do e[1]:SetWidth(math.max(40, panelW - e[2])) end
  end)

  -- Each line sits under the one above, so a long name or a wrapped line pushes the rest down.
  local function line(fs, anchor, gap)
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gap or 4))
    fs:SetWidth(pw - 24)
    track(fs, 24)
    fs:SetJustifyV("TOP")
    return fs
  end
  panel.who = UI.Label(panel, "", "GameFontNormalLarge")
  panel.who:SetPoint("TOPLEFT", 12, -10)
  panel.who:SetWidth(pw - 24)
  track(panel.who, 24)
  panel.who:SetWordWrap(false)
  panel.title = line(UI.Label(panel, "", "GameFontNormal"), panel.who, 6)
  panel.title:SetWordWrap(false)
  panel.rank = line(UI.Label(panel, "", "GameFontHighlightSmall"), panel.title, 4)
  panel.giver = line(UI.Label(panel, "", "GameFontDisableSmall"), panel.rank, 3)
  panel.giver:SetWordWrap(false)
  panel.desc = line(UI.Label(panel, "", "GameFontHighlightSmall"), panel.giver, 8)
  panel.desc:SetWordWrap(true)
  panel.desc:SetMaxLines(3)
  panel.progress = line(UI.Label(panel, "", "GameFontNormalSmall"), panel.desc, 10)
  panel.progress:SetWordWrap(true)
  panel.progress:SetMaxLines(2)

  panel.checks = {}
  for i = 1, MAX_TASKS do
    local c = UI.Check(panel, "")
    if i == 1 then c:SetPoint("TOPLEFT", panel.progress, "BOTTOMLEFT", -2, -4)
    else c:SetPoint("TOPLEFT", panel.checks[i - 1], "BOTTOMLEFT", 0, 0) end
    c.label:SetWidth(pw - 50)
    track(c.label, 50)
    c.label:SetWordWrap(false)
    panel.checks[i] = c
  end

  -- "Trial complete" hands you the /gpromote command to copy and paste; Blizzard blocks any
  -- promotion an addon starts. One promotion raises the member one rank, so the button stays
  -- until they reach the trial's rank.
  local promote = UI.Button(panel, "", pw - 20, 24, function(self)
    if not self.target then return end
    UI.CopyCommand("/gpromote " .. ns.Name(self.target), "Promote " .. ns.Name(self.target))
    if C_Timer then
      C_Timer.After(3, ns.RequestRoster)
      C_Timer.After(8, ns.RequestRoster)
    end
  end)
  promote:SetPoint("BOTTOMLEFT", 8, 38)
  promote:SetPoint("BOTTOMRIGHT", -12, 38)
  promote:Hide()
  panel.promote = promote

  -- Shown once the member holds the trial's rank: clears the finished trial from the list.
  panel.finishButton = UI.Button(panel, "Trial complete: clear it", pw - 20, 24, function()
    local key = state.key
    if key and Data.Get("progress", key) then UI.ClearTrial(key) end
  end)
  panel.finishButton:SetPoint("BOTTOMLEFT", 8, 38)
  panel.finishButton:SetPoint("BOTTOMRIGHT", -12, 38)
  panel.finishButton:Hide()

  panel.saveButton = UI.Button(panel, "Save progress", 104, 22, function()
    local key = state.key
    local t = key and Data.Get("progress", key)
    if not t then return end
    local member = key
    local me = ns.PlayerName()
    if Data.CanGiveTrial(me, member, t.rank) then
      -- the giver's ticks; unticking a task the member marked overrules their mark
      local marks = Data.Get("taskmarks", key) or {}
      local copy = {}
      for k, v in pairs(t) do copy[k] = v end
      copy.done, copy.undone = {}, {}
      for i, task in ipairs(t.tasks or {}) do
        if panel.checks[i]:GetChecked() then
          copy.done[task.id] = true
        elseif marks.done and marks.done[task.id] then
          copy.undone[task.id] = true
        end
      end
      Data.Put("progress", key, copy)
    elseif member == me then
      local done = {}
      for i, task in ipairs(t.tasks or {}) do
        if panel.checks[i]:GetChecked() then done[task.id] = true end
      end
      if Data.Put("taskmarks", key, { done = done }) then
        ns.Print("Progress saved. An officer will review your trial.")
      end
    end
  end)
  panel.saveButton:SetPoint("BOTTOMLEFT", 8, 10)
  panel.editButton = UI.Button(panel, "Edit", 60, 22, function() trialForm(nil, state.key) end)
  panel.editButton:SetPoint("LEFT", panel.saveButton, "RIGHT", 4, 0)
  panel.removeButton = UI.Button(panel, "End trial", 76, 22, function()
    local key = state.key
    local member = key
    UI.Confirm("End " .. ns.Name(member) .. "'s trial?", function()
      Data.Delete("progress", key)
      state.key = nil
    end)
  end)
  panel.removeButton:SetPoint("LEFT", panel.editButton, "RIGHT", 4, 0)
end

local function refresh(f)
  local me = ns.PlayerName()
  local canGive = Data.CanGiveTrials(me)
  f.requestButton:SetText(Data.Get("requests", me) and "Withdraw request" or "Request promotion")
  f.giveButton:SetShown(canGive)
  f.requestsButton:SetShown(canGive)
  f.requestsButton:SetText("Requests (" .. Data.Count("requests") .. ")")

  local items = {}
  for _, a in ipairs(Data.AssignedTrials()) do
    local complete = a.total > 0 and a.done == a.total
    items[#items + 1] = {
      data = a.key, member = a.member, keys = { [2] = a.rank or 99, [3] = a.total > 0 and a.done / a.total or 0 },
      cols = { ns.ColorName(a.member) .. (a.member == me and " |cff999999(you)|r" or ""), ns.RankName(a.rank),
        a.completed and "|cff40ff40Promoted|r" or ((complete and "|cff40ff40" or "") .. a.done .. "/" .. a.total .. (complete and " done|r" or "")) },
    }
  end
  table.sort(items, function(a, b)
    if (a.member == me) ~= (b.member == me) then return a.member == me end
    return a.data < b.data
  end)
  f.list:SetItems(items, "No one is on a trial right now.")

  local panel = f.panel
  if state.key and not Data.Get("progress", state.key) then state.key = nil end
  if not state.key and items[1] then state.key = items[1].data end
  local member = state.key
  local done, total, t = Data.TrialProgress(state.key)

  if not t then
    panel.who:SetText("Promotion trials")
    panel.title:SetText("")
    panel.giver:SetText("")
    panel.rank:SetText("")
    panel.desc:SetText(canGive and "Press Give a trial to set one for any member. They don't need to have asked first."
      or "Press Request promotion and a Noble or higher will set you a trial. Every character's trial shows here for the whole hold to see.")
    panel.progress:SetText("")
    for _, c in ipairs(panel.checks) do c:Hide() end
    panel.saveButton:Hide(); panel.editButton:Hide(); panel.removeButton:Hide(); panel.finishButton:Hide()
    if not InCombatLockdown() then panel.promote:Hide() end
    return
  end

  local canManage = Data.CanGiveTrial(me, member, t.rank)
  local _, rec = Data.Get("progress", state.key)
  panel.who:SetText(ns.ColorName(member))
  panel.title:SetText(t.title or "Promotion trial")
  panel.rank:SetText("Earns the rank: |cffd4a017" .. ns.RankName(t.rank) .. "|r")
  panel.giver:SetText(rec and rec.b and ("Given by " .. ns.Name(rec.b)) or "")
  panel.desc:SetText(t.desc or "")
  local complete = total > 0 and done == total
  local current = ns.RankIndexOf(member)
  if t.completed then
    panel.progress:SetText("|cff40ff40Trial complete|r  |cff888888" .. ns.FormatDate(t.completed) .. "|r")
  else
    local note = ""
    if complete then
      note = canManage and "  |cff40ff40Ready for promotion|r" or "  |cff40ff40All done. An officer will review it and promote you.|r"
    end
    panel.progress:SetText(done .. " of " .. total .. " tasks done" .. note)
  end
  local isMember = member == me
  for i, c in ipairs(panel.checks) do
    local task = t.tasks and t.tasks[i]
    if task then
      c:Show()
      local isDone, by = Data.TaskState(state.key, task.id)
      c.label:SetText(task.text .. ((isDone and by == "member" and canManage and not isMember) and "  |cff999999(marked by " .. ns.Name(member):match("^(%S+)") .. ")|r" or ""))
      c:SetChecked(isDone and true or false)
      c:SetEnabled((canManage or isMember) and not t.completed)
    else
      c:Hide()
    end
  end
  panel.saveButton:SetShown((canManage or isMember) and not t.completed)
  panel.editButton:SetShown(canManage and not t.completed)
  panel.removeButton:SetShown(canManage)

  -- Promotion step: promote while below the trial's rank, then let the giver close it out.
  local needsPromotion = canManage and complete and not t.completed and current ~= nil and type(t.rank) == "number" and current > t.rank
  panel.finishButton:SetShown(canManage and complete and not t.completed and not needsPromotion)
  if not InCombatLockdown() then
    if needsPromotion then
      local steps = current - t.rank
      panel.promote.target = member
      panel.promote:SetText("Trial complete: promote to " .. ns.RankName(current - 1) ..
        (steps > 1 and (" (" .. steps .. " clicks to " .. ns.RankName(t.rank) .. ")") or ""))
      panel.promote:Show()
    else
      panel.promote:Hide()
    end
  end
end

UI.RegisterTab("trials", "Promotions", build, refresh)
