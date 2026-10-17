-- Ironforged: Backstory tab (your character's backstory and standing).
local ADDON, ns = ...
local UI = ns.UI
local Data = ns.Data

local PROFILE_CHAR_LIMIT = 5000

local function build(f, w, h)
  local title = UI.Label(f, "Backstory", "GameFontNormal")
  title:SetPoint("TOPLEFT", 4, -4)
  local hint = UI.Label(f, "Who is your dwarf? Guildmates see this on your roster record.", "GameFontDisableSmall")
  hint:SetPoint("LEFT", title, "RIGHT", 10, 0)
  f.backstory = UI.MultiLine(f, w - 8, 170, PROFILE_CHAR_LIMIT)
  f.backstory:SetPoint("TOPLEFT", 4, -24)
  f.backstory:SetPoint("TOPRIGHT", -4, -24)

  -- Bottom block, built upward from the bottom edge: standing text, its title, then Save.
  -- The text box fills whatever height is left above it.
  f.standing = UI.Label(f, "", "GameFontHighlightSmall")
  f.standing:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 6)
  f.standing:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
  f.standing:SetJustifyV("BOTTOM")
  f.standing:SetSpacing(2)
  local standingTitle = UI.Label(f, "Your standing", "GameFontNormal")
  standingTitle:SetPoint("BOTTOMLEFT", f.standing, "TOPLEFT", 0, 6)

  f.save = UI.Button(f, "Save backstory", 130, 22, function()
    Data.Put("profiles", ns.PlayerName(), { backstory = ns.Clean(f.backstory:GetText(), PROFILE_CHAR_LIMIT) })
    ns.Print("Your backstory is carved in stone and shared with the hold.")
  end)
  f.save:SetPoint("BOTTOMLEFT", standingTitle, "TOPLEFT", 0, 10)
  f.backstory:SetPoint("BOTTOMLEFT", f.save, "TOPLEFT", 0, 6)

  local function fill()
    local p = Data.Profile(ns.PlayerName()) or {}
    f.backstory:SetText(p.backstory or "")
  end
  f:SetScript("OnShow", fill)
  fill()
end

local function refresh(f)
  local me = ns.PlayerName()
  local info = ns.roster[me] or {}
  local m = Data.Member(me)
  local lines = {}
  local function add(label, value)
    if value and value ~= "" then lines[#lines + 1] = "|cffd4a017" .. label .. ":|r " .. value end
  end
  add("Rank", info.rankName)
  local clanId = Data.ClanOf(me)
  add("Clan", clanId and (Data.ClanName(clanId) .. (Data.IsClanLeader(me, clanId) and " (Clan Leader)" or ""))
    or "|cff999999not sworn to a clan|r")
  for _, inviteClan in ipairs(Data.PendingInvites(me)) do
    add("Invitation", "|cff40ff40clan " .. Data.ClanName(inviteClan) .. " wants you. Answer in the Clans tab.|r")
  end
  add("Title", m.title)
  add("Joined", m.joined)
  local attended, total = Data.AttendanceCount(me)
  if total > 0 then add("Attendance", attended .. " of " .. total .. " events") end
  for _, t in ipairs(Data.AssignedTrials(me)) do
    add("Trial", t.title .. " (" .. ns.RankName(t.rank) .. ") - " .. t.done .. "/" .. t.total)
  end
  if Data.Get("requests", me) then add("Promotion", "requested, awaiting a trial") end
  add("Race", ns.Gear.RaceStatus(me))
  f.standing:SetText(table.concat(lines, "\n"))
end

UI.RegisterTab("profile", "Backstory", build, refresh)
