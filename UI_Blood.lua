-- Ironforged: War Hall tab, a leaderboard of Horde slain, world kills, elves slain and grudges avenged.
local ADDON, ns = ...
local UI = ns.UI
local Data = ns.Data

-- Ranked by world kills (then Horde slain); click any column title to sort by it instead.
local function build(f, w, h)
  f.mine = UI.Label(f, "", "GameFontHighlight")
  f.mine:SetPoint("TOPLEFT", 6, -7)
  f.mine:SetPoint("TOPRIGHT", -6, -7)
  f.mine:SetWordWrap(false)
  f.list = UI.List(f, w, h - 52, {
    { title = "#", width = 30 }, { title = "Dwarf", width = 190 },
    { title = "World Kills", width = 100 }, { title = "Horde Slain", width = 100 }, { title = "Elves Slain", width = 100 },
    { title = "Avenged", width = 90 },
  }, function(name) UI.ShowMember(name, { noManage = true }) end)
  f.list:SetPoint("TOPLEFT", 0, -28)
  f.list:SetPoint("BOTTOMRIGHT", 0, 24)
  -- hover a column title for how it's counted
  local function explain(col, title, r, g, b, text)
    local hb = f.list.headers[col]
    if not hb then return end
    hb:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:AddLine(title, r, g, b)
      GameTooltip:AddLine(text, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    hb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  explain(3, "World Kills", 1, 0.5, 0.3, ns.Blood.WORLD_RULES)
  explain(4, "Horde Slain", 1, 0.38, 0.25, "Your lifetime honorable kills, straight from the game's own PvP stats.")
  explain(5, "Elves Slain", 0.5, 1, 0.37, ns.Blood.ELF_RULES)
  explain(6, "Avenged", 1, 0.82, 0.25, ns.Blood.AVENGED_RULES)
  f.note = UI.Label(f, "Hover a column title to see how it's counted.", "GameFontDisableSmall")
  f.note:SetPoint("BOTTOMLEFT", 4, 4)
  f.note:SetPoint("BOTTOMRIGHT", -4, 4)
end

local function refresh(f)
  local rows = {}
  for name, t in Data.Each("pvp") do
    if ns.roster[name] then
      rows[#rows + 1] = { name = name, hk = t.hk or 0, elves = t.elves or 0, avenged = t.avenged or 0, world = t.world or 0 }
    end
  end
  table.sort(rows, function(a, b)
    if a.world ~= b.world then return a.world > b.world end
    if a.hk ~= b.hk then return a.hk > b.hk end
    return a.name < b.name
  end)
  local items = {}
  local me = ns.PlayerName()
  -- the most elves slain is highlighted
  local topElves = 0
  for _, r in ipairs(rows) do if r.elves > topElves then topElves = r.elves end end
  local myPlace
  for i, r in ipairs(rows) do
    if r.name == me then myPlace = i end
    local medal = (i == 1 and "|cffffd700") or (i == 2 and "|cffc0c0c0") or (i == 3 and "|cffcd7f32") or "|cffffffff"
    items[#items + 1] = {
      data = r.name,
      keys = { [2] = ns.NameKey(r.name), [3] = r.world, [4] = r.hk, [5] = r.elves, [6] = r.avenged },
      cols = { medal .. i .. "|r", ns.ColorName(r.name) .. (r.name == me and " |cff999999(you)|r" or ""),
        r.world, r.hk,
        (topElves > 0 and r.elves == topElves) and ("|cff7fff5f" .. r.elves .. "|r") or r.elves, r.avenged },
    }
  end
  f.list:SetItems(items, "No tallies yet. Spill some Horde blood.")
  local hk, elves, avenged, world = ns.Blood.Tally(me)
  if hk then
    f.mine:SetText(string.format("|cffd4a017Your tally:|r  %d World Kills   |   %d Horde Slain   |   %d Elves Slain   |   %d Avenged%s",
      world or 0, hk, elves, avenged, myPlace and ("   |   ranked |cffd4a017#" .. myPlace .. "|r") or ""))
  else
    f.mine:SetText("")
  end
end

UI.RegisterTab("blood", "War Hall", build, refresh)
