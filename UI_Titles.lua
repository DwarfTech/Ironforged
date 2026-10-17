-- Ironforged: Titles tab. Every title in the hold: the automatic ones and who holds them now,
-- then every title an officer has awarded.
local ADDON, ns = ...
local UI = ns.UI
local Data = ns.Data
local T = ns.Titles

-- Officers award a title: who, the title (their own words), and why.
local function awardForm()
  local opts = UI.RosterOptions(false)
  UI.OpenForm({
    title = "Award a title",
    width = 460,
    fields = {
      { key = "who", label = "To", type = "choice", value = opts[1] and opts[1].value, options = opts },
      { key = "title", label = "Title", type = "text", value = "", maxLen = 40 },
      { key = "reason", label = "For (optional)", type = "text", value = "", maxLen = 120 },
    },
    saveText = "Award",
    onSave = function(v)
      if not v.who then return false end
      return T.Award(v.who, v.title, v.reason) and true or false
    end,
  })
end
UI.AwardTitleForm = awardForm

local function refresh(f)
  local items = {}
  local holders = T.AutoHolders()
  local units = { Elfbane = "elves slain", ["The Hordebreaker"] = "Horde slain", ["The Grudgebearer"] = "grudges avenged",
    ["The Goldbringer"] = "gold won" }
  for i, a in ipairs(T.AUTO) do
    local b = holders[a.title]
    local names = {}
    if b then for _, n in ipairs(b.names) do names[#names + 1] = ns.ColorName(n) end end
    items[#items + 1] = {
      data = { kind = "auto", name = b and b.names[1] },
      order = i,
      keys = { [4] = 0 },
      cols = { "|cffffd040" .. a.title .. "|r", #names > 0 and table.concat(names, ", ") or "|cff888888no one yet|r",
        "Automatic: " .. a.what .. (b and (" |cff999999(" .. b.value .. " " .. units[a.title] .. ")|r") or ""), "" },
    }
  end
  local awarded = {}
  for k, d, rec in Data.Each("titles") do
    local member = Data.SplitKey(k)
    if member and ns.roster[member] and type(d.title) == "string" then
      awarded[#awarded + 1] = { key = k, member = member, d = d, by = rec.b }
    end
  end
  table.sort(awarded, function(a, b) return (a.d.ts or 0) > (b.d.ts or 0) end)
  for i, a in ipairs(awarded) do
    items[#items + 1] = {
      data = { kind = "awarded", key = a.key, name = a.member, title = a.d.title },
      order = 100 + i,
      keys = { [4] = a.d.ts or 0 },
      cols = { a.d.title, ns.ColorName(a.member),
        "Awarded by " .. ns.ShortName(a.by or "?") .. ((a.d.reason and a.d.reason ~= "") and (": " .. a.d.reason) or ""),
        ns.FormatDate(a.d.ts) },
    }
  end
  table.sort(items, function(a, b) return a.order < b.order end)
  f.list:SetItems(items, "")
  f.awardB:SetShown(ns.IAmOfficer())
end

local function build(f, w, h)
  f.awardB = UI.Button(f, "Award a title", 120, 22, awardForm)
  f.awardB:SetPoint("TOPLEFT", 4, -6)
  f.info = UI.Label(f, "Automatic titles move to whoever holds the record. Officers award the rest.", "GameFontHighlightSmall")
  f.info:SetPoint("LEFT", f.awardB, "RIGHT", 12, 0)
  f.list = UI.List(f, w, h - 40, {
    { title = "Title", width = 150 }, { title = "Held by", width = 150 }, { title = "How", width = 240 }, { title = "Since", width = 70 },
  }, function(d)
    if type(d) ~= "table" then return end
    if d.kind == "awarded" and ns.IAmOfficer() then
      UI.Confirm("Strip " .. ns.ShortName(d.name) .. " of the title " .. d.title .. "?", function() T.Strip(d.key) end)
    elseif d.name then
      UI.ShowMember(d.name, { noManage = true })
    end
  end)
  f.list:SetPoint("TOPLEFT", 0, -34)
  f.list:SetPoint("BOTTOMRIGHT", 0, 6)
end

UI.RegisterTab("titles", "Titles", build, refresh)
