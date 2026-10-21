-- Ironforged: titles.
-- Officers award titles to guildmates ("titles" collection, key = member .. "#" .. KeyOf(title)).
-- Some titles are earned automatically and move to whoever holds the record:
--   Elfbane            most elves slain
--   The Hordebreaker   most Horde slain
--   The Grudgebearer   most grudges avenged
--   The Goldbringer    most gold won at Cross Gambling
local ADDON, ns = ...
local Data = ns.Data

local T = {}
ns.Titles = T

T.AUTO = {
  { title = "Elfbane", what = "most elves slain" },
  { title = "The Hordebreaker", what = "most Horde slain" },
  { title = "The Grudgebearer", what = "most grudges avenged" },
  { title = "The Goldbringer", what = "most gold won at Cross Gambling" },
}

-- Holders of each automatic title: { [title] = { names = {..}, value = n } }. Ties share the title.
local cache
ns.On("DATA_CHANGED", function() cache = nil end)
ns.On("ROSTER", function() cache = nil end)
function T.AutoHolders()
  if cache then return cache end
  local best = {}
  local function consider(title, name, value)
    if not value or value <= 0 then return end
    local b = best[title]
    if not b or value > b.value then best[title] = { value = value, names = { name } }
    elseif value == b.value then b.names[#b.names + 1] = name end
  end
  for name, t in Data.Each("pvp") do
    if ns.roster[name] then
      consider("Elfbane", name, t.elves)
      consider("The Hordebreaker", name, t.hk)
      consider("The Grudgebearer", name, t.avenged)
    end
  end
  if ns.Gamble and ns.Gamble.Standings then
    for _, s in ipairs(ns.Gamble.Standings()) do
      if ns.roster[s.name] then consider("The Goldbringer", s.name, s.net) end
    end
  end
  for _, b in pairs(best) do table.sort(b.names) end
  cache = best
  return best
end

function T.Holds(name, title)
  local b = T.AutoHolders()[title]
  if not b then return false end
  for _, n in ipairs(b.names) do if n == name then return true end end
  return false
end

-- Every title a member holds: { title, auto = true|nil, reason, by, key }
-- Automatic titles come first, then awarded ones oldest first.
function T.Of(name)
  local out = {}
  if not name then return out end
  for _, a in ipairs(T.AUTO) do
    if T.Holds(name, a.title) then out[#out + 1] = { title = a.title, auto = true, reason = a.what } end
  end
  local awarded = {}
  for k, d, rec in Data.Each("titles") do
    local member = Data.SplitKey(k)
    if member == name and type(d.title) == "string" then
      awarded[#awarded + 1] = { title = d.title, reason = d.reason, by = rec.b, ts = d.ts or 0, key = k }
    end
  end
  table.sort(awarded, function(a, b) return a.ts < b.ts end)
  for _, a in ipairs(awarded) do out[#out + 1] = a end
  -- a title set on the member's record before titles could be awarded
  local m = Data.Member(name)
  if m and m.title and m.title ~= "" then
    local dup = false
    for _, t in ipairs(out) do if t.title == m.title then dup = true end end
    if not dup then out[#out + 1] = { title = m.title, legacy = true } end
  end
  return out
end

function T.Text(name, sep)
  local parts = {}
  for _, t in ipairs(T.Of(name)) do parts[#parts + 1] = t.title end
  return table.concat(parts, sep or ", ")
end

function T.Award(member, title, reason)
  title = ns.Clean(title, 40)
  if title == "" then ns.Print("Name the title."); return false end
  for _, t in ipairs(T.Of(member)) do
    if t.title:lower() == title:lower() then ns.Print(ns.Name(member) .. " already holds that title."); return false end
  end
  local key = member .. "#" .. Data.KeyOf(title)
  if Data.Put("titles", key, { title = title, reason = ns.Clean(reason or "", 120), ts = ns.Now() }) then
    ns.Print(ns.Name(member) .. " is now |cffd4a017" .. title .. "|r.")
    return true
  end
  return false
end

function T.Strip(key)
  return Data.Delete("titles", key)
end

-- Tell a guildmate when an officer awards them a title.
local told = {}
ns.On("DATA_CHANGED", function(coll, key)
  if coll ~= "titles" or not key or told[key] then return end
  local d, rec = Data.Get("titles", key)
  if not d or Data.SplitKey(key) ~= ns.PlayerName() or (rec and rec.b == ns.PlayerName()) then return end
  told[key] = true
  if ns.Now() - (tonumber(d.ts) or 0) > 600 then return end
  ns.Print("|cffd4a017" .. ns.Name(rec and rec.b or "?") .. " names you " .. d.title .. ".|r" ..
    ((d.reason and d.reason ~= "") and (" " .. d.reason) or ""))
  if ns.UI and ns.UI.Notice then
    ns.UI.Notice({
      id = "title", icon = "Interface\\Icons\\INV_Misc_Note_02", title = "A new title",
      text = ns.Name(rec and rec.b or "?") .. " names you |cffffd040" .. d.title .. "|r." ..
        ((d.reason and d.reason ~= "") and ("\n" .. d.reason) or ""),
      buttons = { { text = "Huzzah!" } },
    })
  end
end)
