-- Ironforged: Challenges tab.
local ADDON, ns = ...
local UI = ns.UI
local C = ns.Challenges

local state = { mine = false, finished = true }

local function startForm()
  local opts = {}
  for _, id in ipairs(C.ORDER) do opts[#opts + 1] = { text = C.PRESETS[id].name .. " (enforced)", value = id } end
  opts[#opts + 1] = { text = "My own challenge (honor system)", value = false }
  local lines = {}
  for _, id in ipairs(C.ORDER) do
    lines[#lines + 1] = "|cffd4a017" .. C.PRESETS[id].name .. ":|r " .. C.PRESETS[id].rules
  end
  UI.OpenForm({
    title = "Take on a challenge",
    width = 560,
    fields = {
      { type = "info", value = table.concat(lines, "\n") .. "\n|cff999999The addon enforces these. Your own challenges run on your honor.|r" },
      { key = "preset", label = "Challenge", type = "choice", value = C.ORDER[1], options = opts },
      { key = "name", label = "Your own: name", type = "text", value = "", maxLen = 40 },
      { key = "rules", label = "Your own: rules", type = "multiline", value = "", maxLen = 400, height = 60 },
    },
    saveText = "Accept",
    onSave = function(v)
      if v.preset then return C.Start(v.preset) and true or false end
      return C.Start(nil, v.name, v.rules) and true or false
    end,
  })
end

local function showChallenge(key)
  local d = ns.Data.Get("challenges", key)
  if not d then return end
  local member = ns.Data.SplitKey(key)
  local mine = member == ns.PlayerName()
  local lines = {
    "|cffd4a017Dwarf:|r " .. ns.ShortName(member),
    "|cffd4a017Status:|r " .. (C.STATUS[d.status] or d.status or ""),
    "|cffd4a017Kind:|r " .. (d.preset and "Ready-made, enforced by the addon" or "Their own, on their honor"),
    "|cffd4a017Started:|r " .. ns.FormatDate(d.ts) .. " at level " .. tostring(d.startLevel or "?"),
    "|cffd4a017Level now:|r " .. tostring(d.lvl or "?"),
  }
  if d.ended then lines[#lines + 1] = "|cffd4a017Ended:|r " .. ns.FormatDate(d.ended) end
  if d.reason and d.reason ~= "" then lines[#lines + 1] = "|cffd4a017Why:|r " .. d.reason end
  if d.rules and d.rules ~= "" then lines[#lines + 1] = " "; lines[#lines + 1] = d.rules end
  local buttons = {}
  if mine and d.status == "active" then
    buttons[#buttons + 1] = { text = "Give up", onClick = function()
      UI.Confirm("Give up on " .. d.name .. "?", function() C.Abandon(key) end)
    end }
    buttons[#buttons + 1] = { text = "Completed!", onClick = function()
      UI.Confirm("Mark " .. d.name .. " completed? On your honor.", function() C.Complete(key) end)
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
  for _, c in ipairs(C.All()) do
    local d = c.data
    counts[d.status] = (counts[d.status] or 0) + 1
    if (not state.mine or c.member == me) and (state.finished or d.status == "active") then
      items[#items + 1] = {
        data = c.key,
        keys = { [3] = d.ts or 0, [4] = d.lvl or 0 },
        cols = { ns.ColorName(c.member), d.name .. (d.preset and " |cff999999(enforced)|r" or ""),
          ns.FormatDate(d.ts) .. " |cff999999lvl " .. tostring(d.startLevel or "?") .. "|r", d.lvl or "",
          C.STATUS[d.status] or "" },
      }
    end
  end
  f.list:SetItems(items, "No challenges yet. Be the first to take one on.")
  f.count:SetText("|cffffd040" .. counts.active .. " under way|r   |cff40ff40" .. counts.completed .. " completed|r   |cffff4040" .. counts.failed .. " failed|r")
end

local function build(f, w, h)
  f.startB = UI.Button(f, "Take on a challenge", 150, 22, startForm)
  f.startB:SetPoint("TOPLEFT", 4, -6)
  f.mineC = UI.Check(f, "Mine only", function(self) state.mine = self:GetChecked() and true or false; refresh(f) end)
  f.mineC:SetPoint("LEFT", f.startB, "RIGHT", 12, 0)
  f.finC = UI.Check(f, "Show finished", function(self) state.finished = self:GetChecked() and true or false; refresh(f) end)
  f.finC:SetPoint("LEFT", f.mineC, "RIGHT", 90, 0)
  f.finC:SetChecked(true)
  f.count = UI.Label(f, "", "GameFontHighlightSmall")
  f.count:SetPoint("TOPRIGHT", -6, -10)

  f.list = UI.List(f, w, h - 58, {
    { title = "Dwarf", width = 150 }, { title = "Challenge", width = 190 }, { title = "Started", width = 130 },
    { title = "Level", width = 50 }, { title = "Status", width = 100 },
  }, function(key) showChallenge(key) end)
  f.list:SetPoint("TOPLEFT", 0, -34)

  f.note = UI.Label(f, "Ready-made challenges are enforced: forbidden armor comes off, the PvP flag stays on, and the auction house, trade and mail stay shut.", "GameFontDisableSmall")
  f.note:SetPoint("BOTTOMLEFT", 4, 6)
  f.note:SetWidth(w - 8)
end

UI.RegisterTab("challenges", "Challenges", build, refresh)
