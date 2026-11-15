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
  -- my note, shown when guildmates hover this character
  f.noteLabel = UI.Label(f, "Your note (guildmates see it when they hover you):", "GameFontNormal")
  f.noteBox = UI.EditBox(f, 330, ns.CharInfo.MAX_NOTE)
  f.noteSave = UI.Button(f, "Save note", 90, 22, function()
    if ns.CharInfo.SetNote(f.noteBox:GetText()) then
      f.noteBox:ClearFocus()
      ns.Print("Note saved. Guildmates see it when they hover " .. ns.Name(ns.PlayerName()) .. ".")
    end
  end)
  f.noteBox:SetScript("OnEnterPressed", function() f.noteSave:Click() end)
  f.noteHint = UI.Label(f, "Like the name you go by in the community. Up to 60 letters. Each character has its own.", "GameFontDisableSmall")
end

local function refresh(f)
  local me = ns.PlayerName()
  local info = ns.roster[me] or {}
  local m = Data.Member(me)
  local lines = {}
  local function add(label, value)
    if value and value ~= "" then lines[#lines + 1] = "|cffd4a017" .. label .. ":|r " .. value end
  end
  add("Rank", info.rankName and ns.CharInfo.RankText(me, info.rankName))
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
  -- the note sits under the standing lines
  local h = (f.standing.GetStringHeight and f.standing:GetStringHeight()) or (#lines * 16)
  f.noteLabel:ClearAllPoints(); f.noteLabel:SetPoint("TOPLEFT", 4, -26 - h - 18)
  f.noteBox:ClearAllPoints(); f.noteBox:SetPoint("TOPLEFT", f.noteLabel, "BOTTOMLEFT", 6, -6)
  f.noteSave:ClearAllPoints(); f.noteSave:SetPoint("LEFT", f.noteBox, "RIGHT", 8, 0)
  f.noteHint:ClearAllPoints(); f.noteHint:SetPoint("TOPLEFT", f.noteBox, "BOTTOMLEFT", -6, -6)
  if not f.noteBox:HasFocus() then f.noteBox:SetText(ns.CharInfo.SuggestedNote()) end
end

UI.RegisterTab("profile", "Standing", build, refresh)
