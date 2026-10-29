-- Ironforged: Standing tab (your rank, clan, title, trials and attendance).
local ADDON, ns = ...
local UI = ns.UI
local Data = ns.Data

-- Backstories were retired in 2.18.0 (the text is kept in saved variables but no longer shown or
-- synced); this tab now shows your standing in the hold.
local function build(f, w, h)
  local title = UI.Label(f, "Your standing", "GameFontNormal")
  title:SetPoint("TOPLEFT", 4, -4)
  f.standing = UI.Label(f, "", "GameFontHighlight")
  f.standing:SetPoint("TOPLEFT", 4, -26)
  f.standing:SetPoint("TOPRIGHT", -6, -26)
  f.standing:SetJustifyV("TOP")
  f.standing:SetSpacing(3)
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

UI.RegisterTab("profile", "Standing", build, refresh)
