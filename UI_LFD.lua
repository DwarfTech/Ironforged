-- Ironforged: Looking for Dwarf tab.
local ADDON, ns = ...
local UI = ns.UI
local Data = ns.Data
local L = ns.LFD

local state = { what = "", need = "4", note = "" }

local function ago(ts)
  local m = math.floor((ns.Now() - (ts or 0)) / 60)
  if m < 1 then return "just now" end
  if m < 60 then return m .. " min ago" end
  return math.floor(m / 60) .. " hr " .. (m % 60) .. " min ago"
end

local function roleList(joins)
  local parts = {}
  for _, j in ipairs(joins) do
    local on = ns.roster[j.member] and ns.roster[j.member].online
    parts[#parts + 1] = (on and "" or "|cff999999") .. ns.Name(j.member) .. " (" .. (L.ROLES[j.role] or "Damage") .. ")" .. (on and "" or " offline|r")
  end
  return #parts > 0 and table.concat(parts, ", ") or "|cff999999No one yet.|r"
end

-- "Gnomeregan (29-38)" for a dungeon post, else just the text.
local function whatText(d)
  if tonumber(d.min) and tonumber(d.max) then
    return d.what .. " |cff999999(" .. (d.min == d.max and d.min or (d.min .. "-" .. d.max)) .. ")|r"
  end
  return d.what
end

-- The dungeon list, lowest first; ones that fit your level are marked.
local function pickDungeon(owner, onPick)
  local lv = L.MyLevel()
  local options = {}
  for _, dg in ipairs(L.DUNGEONS) do
    local fits = lv and lv >= dg.min and lv <= dg.max
    options[#options + 1] = { value = dg.key, text = (fits and "|cff40ff40" or "") .. L.DungeonLabel(dg) .. (fits and "|r" or "") }
  end
  UI.Pick(owner, options, function(key) onPick(L.Dungeon(key)) end, "Pick a dungeon")
end
UI.PickDungeon = pickDungeon

local function showPost(postKey)
  local d = Data.Get("lfd", postKey)
  if not d then return end
  local leader = L.Leader(postKey)
  local me = ns.PlayerName()
  local joins = L.Joins(postKey)
  local lines
  if d.aid then
    lines = {
      "|cffff4040" .. ns.Name(leader) .. " calls for aid!|r",
      "|cffd4a017Where:|r " .. (d.what:gsub("^Aid in ", "")),
      "|cffd4a017Called:|r " .. ago(d.ts),
    }
  else
    lines = {
      "|cffd4a017Leader:|r " .. ns.Name(leader),
      "|cffd4a017Looking for:|r " .. d.need .. (d.need == 1 and " dwarf" or " dwarves") .. " for " .. d.what,
      tonumber(d.min) and ("|cffd4a017Levels:|r " .. (d.min == d.max and d.min or (d.min .. " to " .. d.max))) or nil,
      "|cffd4a017Posted:|r " .. ago(d.ts),
    }
  end
  do -- drop the empty slot left by a post with no level range
    local kept = {}
    for i = 1, 4 do if lines[i] then kept[#kept + 1] = lines[i] end end
    lines = kept
  end
  if d.note and d.note ~= "" then lines[#lines + 1] = "|cffd4a017Note:|r " .. d.note end
  lines[#lines + 1] = " "
  if d.aid then
    lines[#lines + 1] = "|cffd4a017Answering (" .. #joins .. "):|r " .. roleList(joins)
    if leader ~= me and not L.MyJoin(postKey) then lines[#lines + 1] = " "; lines[#lines + 1] = "Heed the call as:" end
  else
    lines[#lines + 1] = "|cffd4a017Signed up (" .. #joins .. " of " .. d.need .. "):|r " .. roleList(joins)
  end

  local buttons = {}
  if leader == me then
    buttons[#buttons + 1] = { text = d.aid and "End the call" or "Close post", onClick = function() L.Close(postKey) end }
    buttons[#buttons + 1] = { text = "Invite all", onClick = function() L.InviteAll(postKey) end }
  else
    if L.MyJoin(postKey) then
      buttons[#buttons + 1] = { text = "Drop out", onClick = function() L.Leave(postKey) end }
    end
    for _, r in ipairs(L.ROLE_ORDER) do
      buttons[#buttons + 1] = { text = L.ROLES[r], onClick = function() L.Join(postKey, r) end }
    end
    if ns.IAmOfficer() then
      buttons[#buttons + 1] = { text = "Remove", onClick = function()
        UI.Confirm("Take down " .. ns.Name(leader) .. "'s post?", function() L.Close(postKey, true) end)
      end }
    end
  end
  UI.OpenForm({ title = d.aid and "Call for Aid" or "Looking for Dwarf", width = 520, fields = { { type = "info", value = table.concat(lines, "\n") } }, buttons = buttons })
end
UI.ShowLFDPost = showPost

local function refresh(f)
  local mine = L.MyPost()
  f.postB:SetText(mine and "Repost" or "Post")
  f.closeB:SetShown(mine ~= nil)
  local me = ns.PlayerName()
  local items = {}
  for _, p in ipairs(L.Posts()) do
    local need = tonumber(p.data.need) or 1
    local n = #p.joins
    local status
    if p.data.aid then
      if p.leader == me then status = "|cffff4040Your call|r"
      elseif L.MyJoin(p.key) then status = "|cff40ff40Answered|r"
      else status = "|cffff4040Heed the call|r" end
    elseif p.leader == me then status = "|cffd4a017Your group|r"
    elseif L.MyJoin(p.key) then status = "|cff40ff40You're in|r"
    elseif n >= need then status = "|cff999999Full|r"
    else status = "Open" end
    items[#items + 1] = {
      data = p.key,
      keys = { [3] = n, [4] = -(p.data.ts or 0) },
      cols = { ns.ColorName(p.leader), p.data.aid and ("|cffff4040" .. p.data.what .. "|r") or whatText(p.data),
        p.data.aid and (n .. " answered") or (n .. " / " .. need), ago(p.data.ts), status },
    }
  end
  f.list:SetItems(items, "No one is looking for dwarves right now. Post a group above.")
  if mine then
    local d = Data.Get("lfd", mine)
    f.mineInfo:SetText("|cffd4a017Your post:|r " .. d.what .. ". Signed up: " .. roleList(L.Joins(mine)))
  else
    f.mineInfo:SetText("")
  end
end

local function build(f, w, h)
  local wl = UI.Label(f, "Looking for:", "GameFontNormalSmall")
  wl:SetPoint("TOPLEFT", 6, -10)
  f.dungeonB = UI.Button(f, "Dungeon", 70, 22, function(self)
    pickDungeon(self, function(dg) if dg then state.what = dg.name; f.what:SetText(dg.name) end end)
  end)
  f.dungeonB:SetPoint("LEFT", wl, "RIGHT", 8, 0)
  f.what = UI.EditBox(f, 170, 60)
  f.what:SetPoint("LEFT", f.dungeonB, "RIGHT", 10, 0)
  f.what:SetText(state.what)
  f.what:SetScript("OnTextChanged", function(self) state.what = self:GetText() end)
  local nl = UI.Label(f, "Need:", "GameFontNormalSmall")
  nl:SetPoint("LEFT", f.what, "RIGHT", 12, 0)
  f.need = UI.EditBox(f, 32, 2)
  f.need:SetPoint("LEFT", nl, "RIGHT", 8, 0)
  f.need:SetNumeric(true)
  f.need:SetText(state.need)
  f.need:SetScript("OnTextChanged", function(self) state.need = self:GetText() end)
  f.postB = UI.Button(f, "Post", 70, 22, function()
    if L.Post(state.what, state.need, state.note) then
      state.what, state.note = "", ""
      f.what:SetText(""); f.noteBox:SetText("")
    end
  end)
  f.postB:SetPoint("LEFT", f.need, "RIGHT", 10, 0)
  f.closeB = UI.Button(f, "Close my post", 110, 22, function()
    local k = L.MyPost()
    if k then L.Close(k) end
  end)
  f.closeB:SetPoint("LEFT", f.postB, "RIGHT", 4, 0)

  local ntl = UI.Label(f, "Note:", "GameFontNormalSmall")
  ntl:SetPoint("TOPLEFT", 6, -38)
  f.noteBox = UI.EditBox(f, 360, 120)
  f.noteBox:SetPoint("LEFT", ntl, "RIGHT", 10, 0)
  f.noteBox:SetScript("OnTextChanged", function(self) state.note = self:GetText() end)
  f.aidB = UI.Button(f, "Call for Aid", 110, 22, function()
    UI.Confirm("Call the guild to your side? Everyone online gets a line in chat.", function() L.CallForAid() end)
  end)
  f.aidB:SetPoint("LEFT", f.noteBox, "RIGHT", 10, 0)

  f.mineInfo = UI.Label(f, "", "GameFontHighlightSmall")
  f.mineInfo:SetPoint("TOPLEFT", 6, -64)
  f.mineInfo:SetPoint("TOPRIGHT", -6, -64)
  f.mineInfo:SetWordWrap(false)

  f.list = UI.List(f, w, h - 110, {
    { title = "Leader", width = 160 }, { title = "Looking for", width = 200 }, { title = "Dwarves", width = 80 },
    { title = "Posted", width = 100 }, { title = "Status", width = 90 },
  }, function(key) showPost(key) end)
  f.list:SetPoint("TOPLEFT", 0, -82)
  f.list:SetPoint("BOTTOMRIGHT", 0, 28)

  f.footer = UI.Label(f, "Dungeon posts pop up only for guildmates in the dungeon's level range. Groups of up to 40 (more than 4 becomes a raid). Posts close after two hours, calls for aid after 30 minutes.", "GameFontDisableSmall")
  f.footer:SetPoint("BOTTOMLEFT", 4, 6)
  f.footer:SetPoint("BOTTOMRIGHT", -4, 6)
end

UI.RegisterTab("lfd", "Looking for Dwarf", build, refresh)
