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
    parts[#parts + 1] = (on and "" or "|cff999999") .. ns.ShortName(j.member) .. " (" .. (L.ROLES[j.role] or "Damage") .. ")" .. (on and "" or " offline|r")
  end
  return #parts > 0 and table.concat(parts, ", ") or "|cff999999No one yet.|r"
end

local function showPost(postKey)
  local d = Data.Get("lfd", postKey)
  if not d then return end
  local leader = L.Leader(postKey)
  local me = ns.PlayerName()
  local joins = L.Joins(postKey)
  local lines = {
    "|cffd4a017Leader:|r " .. ns.ShortName(leader),
    "|cffd4a017Looking for:|r " .. d.need .. (d.need == 1 and " dwarf" or " dwarves") .. " for " .. d.what,
    "|cffd4a017Posted:|r " .. ago(d.ts),
  }
  if d.note and d.note ~= "" then lines[#lines + 1] = "|cffd4a017Note:|r " .. d.note end
  lines[#lines + 1] = " "
  lines[#lines + 1] = "|cffd4a017Signed up (" .. #joins .. " of " .. d.need .. "):|r " .. roleList(joins)

  local buttons = {}
  if leader == me then
    buttons[#buttons + 1] = { text = "Close post", onClick = function() L.Close(postKey) end }
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
        UI.Confirm("Take down " .. ns.ShortName(leader) .. "'s post?", function() L.Close(postKey, true) end)
      end }
    end
  end
  UI.OpenForm({ title = "Looking for Dwarf", width = 520, fields = { { type = "info", value = table.concat(lines, "\n") } }, buttons = buttons })
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
    if p.leader == me then status = "|cffd4a017Your group|r"
    elseif L.MyJoin(p.key) then status = "|cff40ff40You're in|r"
    elseif n >= need then status = "|cff999999Full|r"
    else status = "Open" end
    items[#items + 1] = {
      data = p.key,
      keys = { [3] = n, [4] = -(p.data.ts or 0) },
      cols = { ns.ColorName(p.leader), p.data.what, n .. " / " .. need, ago(p.data.ts), status },
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
  f.what = UI.EditBox(f, 190, 60)
  f.what:SetPoint("LEFT", wl, "RIGHT", 10, 0)
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
  local hint = UI.Label(f, "e.g. \"Need a healer, meet at the gates\"", "GameFontDisableSmall")
  hint:SetPoint("LEFT", f.noteBox, "RIGHT", 8, 0)

  f.mineInfo = UI.Label(f, "", "GameFontHighlightSmall")
  f.mineInfo:SetPoint("TOPLEFT", 6, -64)
  f.mineInfo:SetWidth(w - 12)
  f.mineInfo:SetWordWrap(false)

  f.list = UI.List(f, w, h - 110, {
    { title = "Leader", width = 160 }, { title = "Looking for", width = 200 }, { title = "Dwarves", width = 80 },
    { title = "Posted", width = 100 }, { title = "Status", width = 90 },
  }, function(key) showPost(key) end)
  f.list:SetPoint("TOPLEFT", 0, -82)

  f.footer = UI.Label(f, "Guildmates with Ironforged get a popup to sign up. Posts close after two hours. Click a group to sign up or manage it.", "GameFontDisableSmall")
  f.footer:SetPoint("BOTTOMLEFT", 4, 6)
  f.footer:SetWidth(w - 8)
end

UI.RegisterTab("lfd", "Looking for Dwarf", build, refresh)
