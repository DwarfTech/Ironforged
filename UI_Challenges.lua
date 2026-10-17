-- Ironforged: Challenges tab.
local ADDON, ns = ...
local UI = ns.UI
local C = ns.Challenges

local state = { finished = true }

-- The form changes with the pick: a ready-made challenge shows its rules; "My own challenge"
-- shows boxes for a name and rules.
local function startForm(selected)
  selected = selected or C.ORDER[1]
  local opts = {}
  for _, id in ipairs(C.ORDER) do opts[#opts + 1] = { text = C.PRESETS[id].name, value = id } end
  opts[#opts + 1] = { text = "My own challenge", value = "custom" }
  local fields = {
    { key = "preset", label = "Challenge", type = "choice", value = selected, options = opts,
      onChange = function(v) if v ~= selected then startForm(v) end end },
  }
  local p = C.PRESETS[selected]
  if p then
    fields[#fields + 1] = { type = "info", value = "|cffd4a017Rules:|r " .. p.rules ..
      "\n\n|cff999999The addon enforces these rules, and the challenge completes itself at max level. You can start at any level; your tooltip shows the level you started at.|r" }
  else
    fields[#fields + 1] = { key = "name", label = "Name", type = "text", value = "", maxLen = 40 }
    fields[#fields + 1] = { key = "rules", label = "Rules", type = "multiline", value = "", maxLen = 400, height = 70 }
    fields[#fields + 1] = { type = "info", value = "|cff999999Your own challenge runs on your honor. An officer marks it completed when you've earned it.|r" }
  end
  UI.OpenForm({
    title = "Take on a challenge",
    width = 520,
    fields = fields,
    saveText = "Accept",
    onSave = function(v)
      if C.PRESETS[v.preset] then return C.Start(v.preset) and true or false end
      return C.Start(nil, v.name, v.rules) and true or false
    end,
  })
end
UI.StartChallengeForm = startForm

local function showChallenge(key)
  local d = ns.Data.Get("challenges", key)
  if not d then return end
  local member = ns.Data.SplitKey(key)
  local mine = member == ns.PlayerName()
  local lines = {
    "|cffd4a017Dwarf:|r " .. ns.ShortName(member),
    "|cffd4a017Status:|r " .. (C.STATUS[d.status] or d.status or ""),
    "|cffd4a017Kind:|r " .. (d.preset and "Ready-made, enforced by the addon. Completes itself at max level." or "Their own, on their honor. An officer marks it completed."),
    "|cffd4a017Started:|r " .. ns.FormatDate(d.ts) .. " at level " .. tostring(d.startLevel or "?"),
    "|cffd4a017Level now:|r " .. tostring(d.lvl or "?"),
  }
  if d.ended then lines[#lines + 1] = "|cffd4a017Ended:|r " .. ns.FormatDate(d.ended) end
  if d.reason and d.reason ~= "" then lines[#lines + 1] = "|cffd4a017Why:|r " .. d.reason end
  if C.Flagged(d) then lines[#lines + 1] = "|cffff4040Flagged:|r " .. (d.audit or "Played with Ironforged turned off.") end
  -- ready-made challenges show today's rules (older records saved "Start at level 1")
  local rules = (d.preset and C.PRESETS[d.preset] and C.PRESETS[d.preset].rules) or d.rules
  if rules and rules ~= "" then lines[#lines + 1] = " "; lines[#lines + 1] = rules end
  local buttons = {}
  if mine and d.status == "active" then
    buttons[#buttons + 1] = { text = "Give up", onClick = function()
      UI.Confirm("Give up on " .. d.name .. "?", function() C.Abandon(key) end)
    end }
  end
  if not mine and ns.IAmOfficer() and d.status == "active" then
    buttons[#buttons + 1] = { text = "Mark failed", onClick = function()
      UI.Confirm("Mark " .. ns.ShortName(member) .. "'s " .. d.name .. " failed?", function() C.Judge(key, "failed", "Marked failed by an officer.") end)
    end }
    buttons[#buttons + 1] = { text = "Mark completed", onClick = function()
      UI.Confirm("Mark " .. ns.ShortName(member) .. "'s " .. d.name .. " completed?", function() C.Judge(key, "completed") end)
    end }
  end
  if ns.IAmOfficer() or (mine and d.status ~= "active") then
    buttons[#buttons + 1] = { text = "Remove", onClick = function()
      UI.Confirm("Remove this challenge from the list?", function() C.Remove(key) end)
    end }
  end
  UI.OpenForm({ title = d.name, width = 520, fields = { { type = "info", value = table.concat(lines, "\n") } }, buttons = buttons })
end
UI.ShowChallenge = showChallenge

local function refresh(f)
  local me = ns.PlayerName()
  local items = {}
  local counts = { active = 0, completed = 0, failed = 0 }
  for _, c in ipairs(C.Of(me)) do
    local d = c.data
    counts[d.status] = (counts[d.status] or 0) + 1
    if state.finished or d.status == "active" then
      items[#items + 1] = {
        data = c.key,
        keys = { [2] = d.ts or 0, [3] = d.startLevel or 0, [4] = d.lvl or 0 },
        cols = { (C.Flagged(d) and "|cffff4040!|r " or "") .. d.name .. (d.preset and " |cff999999(enforced)|r" or ""), ns.FormatDate(d.ts),
          d.startLevel or "", d.lvl or "", C.STATUS[d.status] or "" },
      }
    end
  end
  f.list:SetItems(items, "You haven't taken on a challenge yet.")
  f.count:SetText("|cffffd040" .. counts.active .. " under way|r   |cff40ff40" .. counts.completed .. " completed|r   |cffff4040" .. counts.failed .. " failed|r")
end

local function build(f, w, h)
  f.startB = UI.Button(f, "Take on a challenge", 150, 22, function() startForm() end)
  f.startB:SetPoint("TOPLEFT", 4, -6)
  f.finC = UI.Check(f, "Show finished", function(self) state.finished = self:GetChecked() and true or false; refresh(f) end)
  f.finC:SetPoint("LEFT", f.startB, "RIGHT", 12, 0)
  f.finC:SetChecked(true)
  f.count = UI.Label(f, "", "GameFontHighlightSmall")
  f.count:SetPoint("TOPRIGHT", -6, -10)

  f.list = UI.List(f, w, h - 58, {
    { title = "Challenge", width = 250 }, { title = "Started", width = 100 }, { title = "From level", width = 80 },
    { title = "Level now", width = 80 }, { title = "Status", width = 100 },
  }, function(key) showChallenge(key) end)
  f.list:SetPoint("TOPLEFT", 0, -34)

  f.note = UI.Label(f, "Your challenges. Guildmates' challenges show on the roster and their tooltips. Ready-made ones are enforced by the addon.", "GameFontDisableSmall")
  f.note:SetPoint("BOTTOMLEFT", 4, 6)
  f.note:SetWidth(w - 8)
end

UI.RegisterTab("challenges", "Challenges", build, refresh)
