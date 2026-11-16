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
  -- my region: dwarves who play from the same part of the world find each other
  f.regionLabel = UI.Label(f, "Your region:", "GameFontNormal")
  f.regionButton = UI.Button(f, "Pick your region", 150, 22, function(self)
    local options = {}
    for _, r in ipairs(ns.CharInfo.REGIONS) do options[#options + 1] = { text = r.name, value = r.key } end
    options[#options + 1] = { text = "|cff999999None|r", value = "none" }
    UI.Pick(self, options, function(key)
      ns.CharInfo.SetRegion(key ~= "none" and key or nil)
      UI.ScheduleRefresh()
    end, "Where do you play from?")
  end)
  f.regionShow = UI.Button(f, "Show them in the Roster", 160, 22, function()
    UI.ShowRegionInRoster(ns.CharInfo.MyRegion())
  end)
  f.regionInfo = UI.Label(f, "", "GameFontHighlightSmall")
  f.regionInfo:SetJustifyH("LEFT")
  f.regionInfo:SetWordWrap(true)
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
  -- region
  local CI = ns.CharInfo
  local mine = CI.MyRegion()
  f.regionLabel:ClearAllPoints(); f.regionLabel:SetPoint("TOPLEFT", f.noteHint, "BOTTOMLEFT", 0, -18)
  f.regionButton:ClearAllPoints(); f.regionButton:SetPoint("LEFT", f.regionLabel, "RIGHT", 8, 0)
  f.regionShow:ClearAllPoints(); f.regionShow:SetPoint("LEFT", f.regionButton, "RIGHT", 6, 0)
  f.regionInfo:ClearAllPoints(); f.regionInfo:SetPoint("TOPLEFT", f.regionLabel, "BOTTOMLEFT", 0, -10)
  f.regionInfo:SetPoint("RIGHT", f, "RIGHT", -10, 0)
  if mine then
    f.regionButton:SetText(CI.RegionInfo(mine).name)
    f.regionShow:Show()
    local all = CI.InRegion(mine)
    local on = {}
    for _, n in ipairs(all) do if ns.roster[n].online and n ~= ns.PlayerName() then on[#on + 1] = ns.ColorName(n) end end
    local shown = {}
    for i = 1, math.min(#on, 8) do shown[i] = on[i] end
    f.regionInfo:SetText(#all .. " in the guild play from " .. CI.RegionInfo(mine).name .. ". " ..
      (#on > 0 and ("Online now: " .. table.concat(shown, ", ") .. (#on > 8 and (" and " .. (#on - 8) .. " more") or ""))
        or "None of them are online right now."))
  else
    f.regionButton:SetText("Pick your region")
    f.regionShow:Hide()
    local guess = CI.RegionInfo(CI.GuessRegion())
    f.regionInfo:SetText("Pick where you play from, and guildmates from the same part of the world can find you." ..
      (guess and (" Your clock says " .. guess.name .. ".") or ""))
  end
end

UI.RegisterTab("profile", "Standing", build, refresh)
