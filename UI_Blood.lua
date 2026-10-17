-- Ironforged: Blood Tally tab, a leaderboard of Horde slain, elves slain and grudges avenged.
local ADDON, ns = ...
local UI = ns.UI
local Data = ns.Data

-- Ranked by Horde slain; click any column title to sort by it instead.
local function build(f, w, h)
  f.mine = UI.Label(f, "", "GameFontHighlight")
  f.mine:SetPoint("TOPLEFT", 6, -7)
  f.mine:SetWidth(w - 12)
  f.mine:SetWordWrap(false)
  f.list = UI.List(f, w, h - 70, {
    { title = "#", width = 30 }, { title = "Dwarf", width = 180 }, { title = "Rank", width = 100 },
    { title = "Horde slain", width = 96 }, { title = "Elves slain", width = 96 }, { title = "Avenged", width = 90 },
  }, function(name) UI.ShowMember(name, { noManage = true }) end)
  f.list:SetPoint("TOPLEFT", 0, -46)
  f.champs = UI.Label(f, "", "GameFontHighlightSmall")
  f.champs:SetPoint("TOPLEFT", 6, -27)
  f.champs:SetWidth(w - 12)
  f.champs:SetWordWrap(false)
  f.note = UI.Label(f, "Horde slain is each dwarf's lifetime honorable kills. Elves slain counts honorable kills on elves the addon saw. Click a column title to sort.", "GameFontDisableSmall")
  f.note:SetPoint("BOTTOMLEFT", 4, 4)
  f.note:SetWidth(w - 8)
end

local function refresh(f)
  local rows = {}
  for name, t in Data.Each("pvp") do
    if ns.roster[name] then
      rows[#rows + 1] = { name = name, hk = t.hk or 0, elves = t.elves or 0, avenged = t.avenged or 0 }
    end
  end
  table.sort(rows, function(a, b)
    if a.hk ~= b.hk then return a.hk > b.hk end
    return a.name < b.name
  end)
  local items = {}
  local me = ns.PlayerName()
  local holders = ns.Titles.AutoHolders()
  local function holds(title, name) return ns.Titles.Holds(name, title) end
  local myPlace
  for i, r in ipairs(rows) do
    if r.name == me then myPlace = i end
    local medal = (i == 1 and "|cffffd700") or (i == 2 and "|cffc0c0c0") or (i == 3 and "|cffcd7f32") or "|cffffffff"
    local tags = ""
    if holds("Elfbane", r.name) then tags = tags .. " |cff7fff5f[Elfbane]|r" end
    if holds("The Hordebreaker", r.name) then tags = tags .. " |cffff6040[Hordebreaker]|r" end
    if holds("The Grudgebearer", r.name) then tags = tags .. " |cffffd040[Grudgebearer]|r" end
    items[#items + 1] = {
      data = r.name,
      keys = { [2] = ns.NameKey(r.name), [4] = r.hk, [5] = r.elves, [6] = r.avenged },
      cols = { medal .. i .. "|r", ns.ColorName(r.name) .. (r.name == me and " |cff999999(you)|r" or "") .. tags,
        (ns.roster[r.name] and ns.roster[r.name].rankName) or "", r.hk,
        holds("Elfbane", r.name) and ("|cff7fff5f" .. r.elves .. "|r") or r.elves,
        holds("The Grudgebearer", r.name) and ("|cffffd040" .. r.avenged .. "|r") or r.avenged },
    }
  end
  f.list:SetItems(items, "No tallies yet. Spill some Horde blood.")
  local function champ(title, color, unit)
    local b = holders[title]
    if not b then return "|cff" .. color .. title .. ":|r |cff888888no one yet|r" end
    local names = {}
    for _, n in ipairs(b.names) do names[#names + 1] = ns.ShortName(n) end
    return "|cff" .. color .. title .. ":|r " .. table.concat(names, ", ") .. " |cff999999(" .. b.value .. " " .. unit .. ")|r"
  end
  f.champs:SetText(champ("Elfbane", "7fff5f", "elves") .. "    " .. champ("The Hordebreaker", "ff6040", "Horde") .. "    " .. champ("The Grudgebearer", "ffd040", "avenged"))
  local hk, elves, avenged = ns.Blood.Tally(me)
  if hk then
    f.mine:SetText(string.format("|cffd4a017Your tally:|r  %d Horde slain   |   %d elves slain   |   %d grudges avenged%s",
      hk, elves, avenged, myPlace and ("   |   ranked |cffd4a017#" .. myPlace .. "|r") or ""))
  else
    f.mine:SetText("")
  end
end

UI.RegisterTab("blood", "Blood Tally", build, refresh)
