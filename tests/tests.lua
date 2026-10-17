package.path = arg[0]:gsub("tests%.lua$", "?.lua") .. ";" .. package.path
local H = require("harness")
local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. label) end
end

local function copyBoxText(client)
  for i = #client.frames, 1, -1 do
    local f = client.frames[i]
    if f.__kind == "EditBox" and f.__shown and type(f.__text) == "string" and f.__text:find("^/g") then return f.__text end
  end
end
-- Serializer
local A = H.makeClient("Thorin")           -- Thane (guild master)
local Ser = A.ns.Ser
local back = Ser.Decode(Ser.Encode({ a = "x;y:z|\n}{s3:", big = 1792000000123, nested = { { text = "ore" } } }))
check(back and back.a == "x;y:z|\n}{s3:" and back.big == 1792000000123 and back.nested[1].text == "ore", "serializer round trip")

local M = H.makeClient("Muradin")          -- Veteran
local D = H.makeClient("Dagna")            -- Noble
local K = H.makeClient("Kurdran")          -- Vanguard
local Hh = H.makeClient("Hilda", "Human")  -- Ironguard, not a dwarf
local B = H.makeClient("Brann")            -- Longbeard
local E = H.makeClient("Elda")             -- Elder
for _, c in ipairs({ A, M, D, K, Hh, B, E }) do H.boot(c) end
H.run(40)
local AD, MD, DD, KD, BD = A.ns.Data, M.ns.Data, D.ns.Data, K.ns.Data, B.ns.Data

-- Ranks come from the guild itself, including ranks nobody holds
check(A.ns.ranks[3] == "Overlord" and A.ns.ranks[6] == "General" and A.ns.ranks[9] == "Ironguard", "all guild ranks read from the game")
check(A.ns.RankSetting("officerRank") == 2 and A.ns.RankSetting("nobleRank") == 5 and A.ns.RankSetting("founderRank") == 7, "rank powers from rank names")
check(A.ns.IsLongbeardOrGM("Thorin-Forever") and A.ns.IsLongbeardOrGM("Brann-Forever") and not A.ns.IsLongbeardOrGM("Elda-Forever"), "Longbeard/GM check")

-- Race scan and gear
A.ns.Gear.ScanGuild()
H.run(10)
check(K.ns.Gear.IsDwarf("Gimli-Forever") == true and K.ns.Gear.IsDwarf("Grimm-Forever") == false, "race scan shared")
M.items[5] = { link = "|Hitem:100:0:0|h[Chest]|h", crafter = "Dagna" }
M.ns.Gear.Report()
H.run(5)
check(AD.SelfReport("Muradin-Forever") and AD.SelfReport("Muradin-Forever").race == "Dwarf" and AD.SelfReport("Muradin-Forever").issues == nil, "race reported, no gear check")
check(M.ns.Gear.Status == nil and M.ns.Gear.Scan == nil, "gear check removed")

-- Promotion trials
local function give(client, member, rank, id)
  return client.ns.Data.Put("progress", member .. "#" .. id, { title = "T", rank = rank,
    tasks = { { id = "a", text = "One" }, { id = "b", text = "Two" } }, done = {} }, true)
end
check(give(D, "Kurdran-Forever", 7, "p1"), "Noble gives a Veteran trial without a request")
check(not give(D, "Kurdran-Forever", 5, "p2"), "Noble cannot give a Noble trial")
check(not give(D, "Kurdran-Forever", 3, "p3"), "Noble cannot give an Overlord trial")
check(not give(D, "Dagna-Forever", 7, "p4"), "Noble cannot give themselves a trial")
check(not give(M, "Kurdran-Forever", 9, "p5"), "Veteran cannot give trials")
check(give(B, "Dagna-Forever", 4, "p6"), "Longbeard gives a Lord trial")
check(give(B, "Muradin-Forever", 3, "p7"), "Longbeard gives an Overlord trial")
check(give(A, "Thorin-Forever", 1, "p8"), "guild master can give any trial, even to self")
H.run(5)
check(#Hh.ns.Data.AssignedTrials() == 4, "everyone sees every trial")
check(DD.Put("progress", "Kurdran-Forever#p1", { title = "T", rank = 7, tasks = { { id = "a", text = "One" }, { id = "b", text = "Two" } }, done = { a = true } }), "giver marks progress")
check(not KD.Put("progress", "Kurdran-Forever#p1", { title = "T", rank = 7, tasks = {}, done = {} }, true), "member cannot edit own trial")
check(not DD.Put("progress", "Dagna-Forever#p6", { title = "T", rank = 7, tasks = {}, done = {} }, true), "cannot downgrade own trial to edit it")
H.run(5)
check(select(1, Hh.ns.Data.TrialProgress("Kurdran-Forever#p1")) == 1, "progress visible to everyone")
check(KD.Put("requests", "Kurdran-Forever", { note = "Ready", ts = 1 }), "member requests promotion")
H.run(5)
check(DD.Delete("requests", "Kurdran-Forever"), "Noble clears a request")
check(DD.Delete("progress", "Kurdran-Forever#p1"), "Noble ends a trial they can give")
check(not DD.Delete("progress", "Muradin-Forever#p7"), "Noble cannot end an Overlord trial")
H.run(5)
check(AD.Get("progress", "Kurdran-Forever#p1") == nil, "ended trial gone everywhere")

-- Trial complete: promote button, then finish and announce
check(give(D, "Kurdran-Forever", 7, "p9"), "Noble gives Kurdran a Veteran trial")
check(DD.Put("progress", "Kurdran-Forever#p9", { title = "Veteran Trial", rank = 7, tasks = { { id = "a", text = "One" } }, done = { a = true } }), "all tasks done")
D.ns.ToggleMain("trials")
local ttab
for _, f in ipairs(D.frames) do if f.panel and f.giveButton then ttab = f end end
D.ns.UI.SelectTab("trials")
for i, row in ipairs(ttab.list.rows) do
  if row.item and row.item.data == "Kurdran-Forever#p9" then row.__scripts.OnClick(row, "LeftButton") end
end
H.run(1)
local panel = ttab.panel
check(panel.promote:IsShown() and panel.promote.target == "Kurdran-Forever", "promote button ready")
panel.promote.__scripts.OnClick(panel.promote)
check(#D.chatOpened == 0 and copyBoxText(D) == "/gpromote Kurdran", "promote gives a /gpromote command to copy, nothing put in chat")
check(panel.promote.__text:find("Veteran", 1, true) ~= nil, "promote button names the rank")
check(not panel.finishButton:IsShown(), "finish hidden until promoted")
for _, r in ipairs(H.ROSTER) do if r[1] == "Kurdran-Forever" then r[2], r[3] = "Veteran", 7 end end
for _, c in ipairs({ A, M, D, K, Hh, B, E }) do H.fire(c, "GUILD_ROSTER_UPDATE") end
H.run(2)
H.run(5)
local chatBefore = #D.guildChat
check(AD.Get("progress", "Kurdran-Forever#p9") == nil and KD.Get("progress", "Kurdran-Forever#p9") == nil, "trial cleared from the list for everyone once promoted")
check(#D.guildChat == chatBefore, "clearing a trial posts nothing to guild chat")
D.ns.UI.SelectTab("trials")
H.run(1)
check(not panel.promote:IsShown(), "no promote button once cleared")
for _, r in ipairs(H.ROSTER) do if r[1] == "Kurdran-Forever" then r[2], r[3] = "Vanguard", 8 end end
for _, c in ipairs({ A, M, D, K, Hh, B, E }) do H.fire(c, "GUILD_ROSTER_UPDATE") end
H.run(2)

-- Member marks their own tasks; only the giver completes and promotes
check(give(D, "Kurdran-Forever", 7, "m1"), "Noble gives Kurdran a trial")
H.run(5)
check(KD.Put("taskmarks", "Kurdran-Forever#m1", { done = { a = true, b = true } }), "member marks their own tasks")
check(not MD.Put("taskmarks", "Kurdran-Forever#m1", { done = {} }, true), "others can't mark someone else's tasks")
check(not KD.Put("progress", "Kurdran-Forever#m1", { title = "T", rank = 7, tasks = {}, done = { a = true }, completed = 1 }, true), "member can't complete their own trial")
H.run(5)
check(select(1, DD.TrialProgress("Kurdran-Forever#m1")) == 2, "giver sees the member's marks")
K.ns.ToggleMain("trials")
local ktab
for _, f in ipairs(K.frames) do if f.panel and f.giveButton then ktab = f end end
for _, row in ipairs(ktab.list.rows) do if row.item and row.item.data == "Kurdran-Forever#m1" then row.__scripts.OnClick(row, "LeftButton") end end
H.run(1)
check(ktab.panel.saveButton:IsShown() and not ktab.panel.promote:IsShown() and not ktab.panel.finishButton:IsShown(), "member can save progress but sees no promote button")
check(ktab.panel.progress.__text:find("officer will review", 1, true) ~= nil, "member told an officer will review")
-- giver unticks one claimed task
D.ns.ToggleMain("trials")
for _, row in ipairs(ttab.list.rows) do if row.item and row.item.data == "Kurdran-Forever#m1" then row.__scripts.OnClick(row, "LeftButton") end end
H.run(1)
check(ttab.panel.checks[1].label.__text:find("marked by Kurdran", 1, true) ~= nil, "giver sees which tasks the member marked")
ttab.panel.checks[2]:SetChecked(false)
ttab.panel.saveButton.__scripts.OnClick(ttab.panel.saveButton)
H.run(5)
check(select(1, KD.TrialProgress("Kurdran-Forever#m1")) == 1, "giver can overrule a member's mark")
DD.Delete("progress", "Kurdran-Forever#m1")
H.run(3)

-- Display names drop realm suffixes; matching ignores them
check(A.ns.ShortName("Frugo Firehammer-ClassicBetaPvP") == "Frugo Firehammer", "realm suffix dropped from display")
check(A.ns.NameKey("Frugo Firehammer-ClassicBetaPvP") == "frugo firehammer", "realm suffix dropped from matching")

-- Column sorting
A.ns.ToggleMain("roster")
H.run(1)
local rt
for _, f in ipairs(A.frames) do if f.list and f.count and f.scan then rt = f end end
local lvlHeader = rt.list.headers[3]
lvlHeader.__scripts.OnClick(lvlHeader)
local ascOK = true
for i = 2, #rt.list.items do if (tonumber(rt.list.items[i].cols[3]) or 0) < (tonumber(rt.list.items[i - 1].cols[3]) or 0) then ascOK = false end end
check(ascOK and lvlHeader.label.__text:find("Arrow-Up", 1, true), "roster sorts by level ascending")
lvlHeader.__scripts.OnClick(lvlHeader)
local descOK = true
for i = 2, #rt.list.items do if (tonumber(rt.list.items[i].cols[3]) or 0) > (tonumber(rt.list.items[i - 1].cols[3]) or 0) then descOK = false end end
check(descOK, "second click reverses")
local nameHeader = rt.list.headers[1]
nameHeader.__scripts.OnClick(nameHeader)
check(rt.list.items[1].data < rt.list.items[#rt.list.items].data, "roster sorts by name")
A.ns.UI.ScheduleRefresh()
H.run(1)
check(rt.list.sortCol == 1, "sort survives a refresh")

-- Clans: founder always leads, no sponsor
local clanId = "Muradin-Forever#c1"
check(MD.Put("clans", clanId, { name = "Bronzebeard", leader = "Muradin-Forever" }), "Veteran founds clan")
check(not MD.Put("clans", clanId, { name = "Bronzebeard", leader = "Kurdran-Forever" }, true), "leader must be the founder")
check(not AD.Put("clans", "Muradin-Forever#c9", { name = "X", leader = "Thorin-Forever" }, true), "even officers cannot set another leader")
check(not KD.Put("clans", "Kurdran-Forever#c2", { name = "Y", leader = "Kurdran-Forever" }, true), "Vanguard cannot found a clan")
H.run(5)
check(KD.Clan(clanId) ~= nil, "clan active everywhere")
check(MD.Put("invites", clanId .. "#Kurdran-Forever", { by = "Muradin-Forever" }), "leader invites")
H.run(5)
check(KD.Put("clanship", "Kurdran-Forever", { clan = clanId }), "member joins")
H.run(5)
check(AD.ClanOf("Kurdran-Forever") == clanId, "membership synced")
check(not MD.Delete("clans", clanId), "founder cannot delete clan")
check(not E.ns.Data.Delete("clans", clanId), "Elder cannot delete clan")
check(BD.Delete("clans", clanId), "Longbeard deletes clan")
H.run(5)
check(KD.Clan(clanId) == nil and KD.ClanOf("Kurdran-Forever") == nil, "clan deletion synced")

-- Book of Grudges through the actual buttons
local gk = "Hilda-Forever#g1"
check(Hh.ns.Data.Put("grudges", gk, { against = "Grubnak", deed = "Camped our flight master", ts = 1 }), "anyone writes a grudge")
H.run(5)
check(KD.Get("grudges", gk) ~= nil, "everyone reads the grudge")
check(not MD.Delete("grudges", gk), "Veteran cannot strike a grudge")

local function dialogButton(client, text)
  local d = client.env.IronforgedDialog
  for _, b in ipairs(d and d.buttons or {}) do if b.__text == text then return b end end
end
B.ns.ToggleMain("grudges")
local gtab
for _, f in ipairs(B.frames) do if f.list and f.writeButton then gtab = f end end
check(gtab ~= nil, "grudges tab built")
if gtab then
  local row = gtab.list.rows[1]
  check(row.item and row.item.data == gk, "grudge listed")
  row.__scripts.OnClick(row, "LeftButton")
  local strike = dialogButton(B, "Strike it out")
  check(strike ~= nil, "strike button shown to a Longbeard")
  if strike then
    strike.__scripts.OnClick(strike)
    local d = B.env.IronforgedDialog
    check(d:IsShown() and d.title.__text == "Are you sure?", "confirmation stays open")
    local yes = dialogButton(B, "Yes")
    if yes then yes.__scripts.OnClick(yes) end
    H.run(5)
    check(AD.Get("grudges", gk) == nil and KD.Get("grudges", gk) == nil, "grudge struck everywhere")
  end
end

-- Clan applications
local c3 = "Muradin-Forever#c3"
check(MD.Put("clans", c3, { name = "Ironhand", leader = "Muradin-Forever" }), "clan for applications")
H.run(5)
check(KD.Put("applications", c3 .. "#Kurdran-Forever", { note = "Let me in", ts = 5 }), "member asks to join")
check(not KD.Put("applications", c3 .. "#Hilda-Forever", { note = "x", ts = 5 }, true), "cannot apply for someone else")
check(Hh.ns.Data.Put("applications", c3 .. "#Hilda-Forever", { note = "me too", ts = 6 }), "second applicant")
H.run(5)
check(#MD.Applications(c3) == 2, "leader sees both applications")
check(not DD.Put("invites", c3 .. "#Kurdran-Forever", { by = "Dagna-Forever" }, true), "non-leader cannot accept")
check(MD.Put("invites", c3 .. "#Kurdran-Forever", { by = "Muradin-Forever" }), "leader accepts")
check(MD.Delete("applications", c3 .. "#Hilda-Forever"), "leader denies")
H.run(5)
check(AD.ClanOf("Kurdran-Forever") == c3, "accepted applicant is in the clan everywhere")
check(AD.ClanOf("Hilda-Forever") == nil and #AD.Applications(c3) == 0, "denied applicant out, no open applications")

-- Non-dwarf invite: logged with inviter, announced, inviter shamed, Longbeard popup
M.target = { name = "Orcy", race = "Orc" }
M.env.C_GuildInfo.Invite("Orcy")
H.run(5)
check(AD.Get("invitelog", "Muradin-Forever#orcy") ~= nil, "invite logged with inviter")
local announced = false
for _, m in ipairs(K.chat) do if m:find("Muradin invited Orcy, who is not a dwarf", 1, true) then announced = true end end
check(announced, "everyone is told who invited a non-dwarf")
check(#K.ns.Gear.NonDwarfInvites("Muradin-Forever") == 1, "inviter flagged")
local bd = B.env.IronforgedDialog
check(bd and bd:IsShown() and bd.title.__text:find("non-dwarf", 1, true), "Longbeard gets a popup")
local kd = K.env.IronforgedDialog
check(not (kd and kd:IsShown() and kd.title.__text:find("non-dwarf", 1, true)), "regular member gets no popup")
table.insert(H.ROSTER, { "Orcy-Forever", "Ironguard", 9, 10, "Warrior", "WARRIOR" })
for _, c in ipairs({ A, M, D, K, Hh, B, E }) do
  H.fire(c, "CHAT_MSG_SYSTEM", "Orcy has joined the guild.")
  H.fire(c, "GUILD_ROSTER_UPDATE")
end
H.run(15)
check(A.ns.Gear.IsDwarf("Orcy-Forever") == false and K.ns.Gear.IsDwarf("Orcy-Forever") == false, "joined non-dwarf known to all")
check(A.ns.Gear.InvitersOf("Orcy-Forever")[1] == "Muradin-Forever", "inviter linked to the new member")

-- Officers (not just Longbeards) get the popup; the non-dwarf's row names the inviter
local ed = E.env.IronforgedDialog
check(not (ed and ed:IsShown() and ed.title.__text:find("non-dwarf", 1, true)), "Elder is not an officer, no popup")
check(not E.ns.IAmOfficer() and B.ns.IAmOfficer() and A.ns.IAmOfficer(), "officers are Longbeards and the guild master")
A.ns.ToggleMain("roster")
H.run(1)
local rosterTab
for _, f in ipairs(A.frames) do if f.list and f.count and f.scan then rosterTab = f end end
local orcRow
for _, item in ipairs(rosterTab.list.items) do if item.data == "Orcy-Forever" then orcRow = item end end
check(orcRow and orcRow.cols[1]:find("invited by Muradin", 1, true), "non-dwarf's roster row names the inviter")
local muradinRow
for _, item in ipairs(rosterTab.list.items) do if item.data == "Muradin-Forever" then muradinRow = item end end
check(muradinRow and muradinRow.cols[1]:find("shamed", 1, true), "inviter flagged on their roster row")

-- Remove from guild button (/gremove) behind a confirmation
A.ns.UI.ShowMember("Hilda-Forever")
local manageBtn
for _, b in ipairs(A.env.IronforgedDialog.buttons) do if b.__text == "Manage" then manageBtn = b end end
check(manageBtn ~= nil, "Manage button shown to officers")
if manageBtn then manageBtn.__scripts.OnClick(manageBtn) end
local removeB
for _, b in ipairs(A.env.IronforgedDialog.buttons) do if b.__text == "Remove" then removeB = b end end
check(removeB ~= nil, "Manage offers Remove")
removeB.__scripts.OnClick(removeB)
check(#A.chatOpened == 0 and A.guildWindowOpened == nil and copyBoxText(A) == "/gremove Hilda", "Remove gives a /gremove command to copy; nothing opened for you")
M.ns.UI.ShowMember("Hilda-Forever")
local memberManage = false
for _, b in ipairs(M.env.IronforgedDialog.buttons) do if b.__text == "Manage" and b:IsShown() then memberManage = true end end
check(not memberManage, "non-officers get no Manage button")

-- Minimap button
check(A.env.IronforgedMinimapButton ~= nil and A.env.IronforgedMinimapButton:IsShown(), "minimap button shown")
A.env.IronforgedMinimapButton.__scripts.OnClick(A.env.IronforgedMinimapButton)

-- Speak Dwarvish toggle
local eb = K.env.ChatFrame1EditBox
check(K.ns.settings.speakDwarvish == true and eb.languageID == 6, "new installs speak Dwarvish by default")
check(Hh.env.ChatFrame1EditBox.languageID ~= 6, "non-dwarves keep their own tongue by default")
K.ns.Lang.Set(false)
K.ns.ToggleMain()
local lb
for _, f in ipairs(K.frames) do if f.__text == "Dwarvish: OFF" then lb = f end end
check(lb ~= nil, "big Dwarvish toggle in the header")
if lb then lb.__scripts.OnClick(lb) end
check(eb.languageID == 6 and eb.language == "Dwarvish" and K.env.ChatFrame2EditBox.languageID == 6, "chat boxes set to Dwarvish")
check(lb and lb.__text == "Dwarvish: ON", "toggle shows ON")
check(K.ns.settings.speakDwarvish == true, "choice saved")
eb.languageID, eb.language = 7, "Common"
eb.__shown = false
eb.__scripts.OnShow(eb)
check(eb.languageID == 6, "re-applied when chat opens")
if lb then lb.__scripts.OnClick(lb) end
check(eb.languageID == 7 and eb.language == "Common", "toggle back to Common")
Hh.ns.Lang.Set(true)
check(Hh.ns.settings.speakDwarvish == false and Hh.env.ChatFrame1EditBox.languageID ~= 6, "non-dwarf cannot speak Dwarvish")
K.env.SlashCmdList.IRONFORGED("dwarvish")
check(eb.languageID == 6, "/hold dwarvish works")
local mmb = K.env.IronforgedMinimapButton
mmb.__scripts.OnClick(mmb, "RightButton")
check(eb.languageID == 7, "minimap right-click toggles Dwarvish")

-- Book of Grudges: factions, guildmates protected, avenging
check(not Hh.ns.Data.Put("grudges", "Hilda-Forever#gx", { against = "Kurdran", faction = "Horde", deed = "x", ts = 1 }, true), "guildmates can't be grudged")
check(not Hh.ns.Data.Put("grudges", "Hilda-Forever#gy", { against = "kurdran-Forever", faction = "Horde", deed = "x", ts = 1 }, true), "guildmates can't be grudged with realm or case tricks")
local hg, ag = "Hilda-Forever#h1", "Hilda-Forever#a1"
check(Hh.ns.Data.Put("grudges", hg, { against = "Grubnak", faction = "Horde", deed = "Camped the flight master", ts = 2 }), "Horde grudge written")
check(Hh.ns.Data.Put("grudges", ag, { against = "Elandril", faction = "Alliance", deed = "Ninja'd the Thunderfury bindings", ts = 3 }), "Alliance grudge written")
H.run(5)
-- sighting: Grubnak's nameplate shows up for Kurdran
K.units.nameplate1 = { name = "Grubnak", race = "Orc", faction = "Horde" }
H.fire(K, "NAME_PLATE_UNIT_ADDED", "nameplate1")
H.run(3)
local nearMsg, guildMsg = false, false
for _, m in ipairs(K.chat) do if m:find("GRUDGED FOE IS NEAR", 1, true) and m:find("Grubnak", 1, true) then nearMsg = true end end
for _, m in ipairs(D.chat) do if m:find("Kurdran sees Grubnak in Arathi Highlands", 1, true) then guildMsg = true end end
check(nearMsg, "alert when you see a grudged foe")
local doomF = K.env.IronforgedDoomFrame
check(doomF ~= nil and doomF:IsShown(), "doom popup when a grudged foe is near")
check(doomF.go:GetAttribute("type") == "macro" and doomF.go:GetAttribute("macrotext") == "/doom Grubnak", "/doom is a secure macro aimed at the foe")
if doomF then doomF.go.__scripts.PostClick(doomF.go) end
check(#K.emotes == 0, "the addon never emotes by itself (Blizzard blocks it)")
check(doomF and not doomF:IsShown(), "doom popup closes after the click")
check(guildMsg, "guild told who spotted the foe and where")
local function countMsgs(chat, needle) local n = 0; for _, m in ipairs(chat) do if m:find(needle, 1, true) then n = n + 1 end end; return n end
H.run(400)
K.units.nameplate1 = { name = "Grubnak", race = "Orc", faction = "Horde" }
H.fire(K, "NAME_PLATE_UNIT_ADDED", "nameplate1")
H.fire(K, "PLAYER_TARGET_CHANGED")
H.run(3)
check(countMsgs(K.chat, "GRUDGED FOE IS NEAR") == 1, "grudge alert only happens once")
check(countMsgs(D.chat, "Kurdran sees Grubnak") == 1, "guild sighting only once")
-- tooltip warning
local tipLines = {}
K.env.GameTooltip.GetUnit = function() return "Grubnak", "nameplate1" end
K.env.GameTooltip.AddLine = function(_, t) tipLines[#tipLines + 1] = t end
K.ns.Blood.CheckUnit("nameplate1")
local fakeTip = { GetUnit = function() return "Grubnak", "nameplate1" end,
  AddLine = function(_, t) tipLines[#tipLines + 1] = t end, Show = function() end }
K.ns.Blood._addGrudgeLines(fakeTip)
check(tipLines[1] and tipLines[1]:find("GRUDGE: 1 wrong unavenged", 1, true) and tipLines[2]:find("Camped", 1, true), "tooltip warns about the grudge")
-- an Alliance member cannot avenge by hand; an officer can
check(not KD.Put("avenged", ag, { by = "Kurdran-Forever", how = "officer", ts = 1 }, true), "member can't mark an Alliance grudge avenged")
check(not KD.Put("avenged", ag, { by = "Kurdran-Forever", how = "slain", ts = 1 }, true), "Alliance grudge isn't avenged by a kill")
-- Kurdran kills an elf and then Grubnak
K.units.nameplate2 = { name = "Sylvanor", race = "NightElf", faction = "Alliance" }
H.fire(K, "NAME_PLATE_UNIT_ADDED", "nameplate2")
H.fire(K, "CHAT_MSG_COMBAT_HONOR_GAIN", "Sylvanor dies, honorable kill Rank: Sentinel (Estimated Honor Points: 12)")
K.hk = 41
H.fire(K, "CHAT_MSG_COMBAT_HONOR_GAIN", "Grubnak dies, honorable kill Rank: Grunt (Estimated Honor Points: 9)")
H.run(12)
check(AD.Avenged(hg) and AD.Avenged(hg).by == "Kurdran-Forever" and AD.Avenged(hg).how == "slain", "Horde grudge avenged on the kill, everywhere")
Hh.ns.ToggleMain("grudges")
H.run(1)
local gtab2
for _, f in ipairs(Hh.frames) do if f.list and f.writeButton and f.targetButton then gtab2 = f end end
local stamped = false
for _, item in ipairs(gtab2.list.items) do if item.data == hg and item.cols[5]:find("AVENGED", 1, true) then stamped = true end end
check(stamped, "book shows the grudge as AVENGED")
local cheer = false
for _, m in ipairs(D.chat) do if m:find("GRUDGE AVENGED", 1, true) and m:find("Grubnak", 1, true) then cheer = true end end
check(cheer, "guild hears the grudge was avenged")
local hk, elves, av = A.ns.Blood.Tally("Kurdran-Forever")
check(hk == 41 and elves == 1 and av == 1, "Blood Tally shared: 41 Horde, 1 elf, 1 avenged")
-- witnessed death avenges too
check(Hh.ns.Data.Put("grudges", "Hilda-Forever#h2", { against = "Zug", faction = "Horde", deed = "Ganked lowbies", ts = 4 }), "second Horde grudge")
H.run(5)
D.units.nameplate3 = { name = "Zug", race = "Troll", faction = "Horde", dead = true }
H.fire(D, "NAME_PLATE_UNIT_ADDED", "nameplate3")
H.run(5)
check(AD.Avenged("Hilda-Forever#h2") and AD.Avenged("Hilda-Forever#h2").how == "witnessed", "Horde grudge avenged when seen dead")
-- officer avenges the Alliance grudge
check(B.ns.Blood.MarkAvenged(ag, "Dagna-Forever"), "officer marks Alliance grudge avenged")
H.run(5)
check(KD.Avenged(ag) and KD.Avenged(ag).by == "Dagna-Forever", "Alliance avenging synced")
check(not KD.Delete("avenged", ag), "member can't reopen")
-- Blood Tally tab
A.ns.ToggleMain("blood")
H.run(1)
local btab
for _, f in ipairs(A.frames) do if f.mine and f.list and f.note then btab = f end end
check(btab and btab.list.items[1] and btab.list.items[1].data == "Kurdran-Forever", "Kurdran tops the Blood Tally")

-- First and last names (Forever)
table.insert(H.ROSTER, { "Thrain Ironbeard-Forever", "Vanguard", 8, 30, "Warrior", "WARRIOR" })
for _, c in ipairs({ A, K, Hh }) do H.fire(c, "GUILD_ROSTER_UPDATE") end
H.run(2)
check(not Hh.ns.Data.Put("grudges", "Hilda-Forever#s1", { against = "Thrain Ironbeard", faction = "Horde", deed = "x", ts = 9 }, true), "guildmate with surname can't be grudged")
check(not Hh.ns.Data.Put("grudges", "Hilda-Forever#s2", { against = "Thrain", faction = "Horde", deed = "x", ts = 9 }, true), "bare first name of a guildmate is refused")
check(Hh.ns.Data.Put("grudges", "Hilda-Forever#s3", { against = "Thrain Bloodaxe", faction = "Horde", deed = "Stole our kills", ts = 9 }), "different surname is fine")
H.run(5)
K.target = { name = "Thrain", surname = "Bloodaxe", race = "Orc", faction = "Horde" }
K.subzone = "Refuge Pointe"
K.ns.ToggleMain("grudges")
local gtab3
for _, f in ipairs(K.frames) do if f.list and f.writeButton and f.targetButton then gtab3 = f end end
gtab3.targetButton.__scripts.OnClick(gtab3.targetButton)
local kdlg = K.env.IronforgedDialog
local prefilledName, prefilledZone = false, false
for _, f in ipairs(K.frames) do
  if f.__kind == "EditBox" and f.__text == "Thrain Bloodaxe" then prefilledName = true end
  if f.__kind == "EditBox" and f.__text == "Refuge Pointe, Arathi Highlands" then prefilledZone = true end
end
check(prefilledName, "Grudge my target fills in first and last name")
check(prefilledZone, "Grudge my target fills in the zone")
H.fire(K, "PLAYER_TARGET_CHANGED")
H.run(3)
local found = false
for _, m in ipairs(K.chat) do if m:find("GRUDGED FOE IS NEAR", 1, true) and m:find("Thrain Bloodaxe", 1, true) then found = true end end
check(found, "grudged foe with surname recognized")
H.fire(K, "CHAT_MSG_COMBAT_HONOR_GAIN", "Thrain Bloodaxe dies, honorable kill Rank: Scout (Estimated Honor Points: 5)")
H.run(6)
check(AD.Avenged("Hilda-Forever#s3") ~= nil, "surname foe avenged on kill")
K.target = nil

-- Cheers
K.bags[3] = { id = 2686, name = "Thunder Ale", count = 3 }
D.bags[1] = { id = 4540, name = "Tough Hunk of Bread", count = 5 }
D.bags[2] = { id = 99999, name = "Dark Iron Stout", count = 1 }
local beforeCount = 0
for _, c in pairs(H.clients) do beforeCount = beforeCount + #c.guildChat end
K.ns.Cheers.Call()
H.run(3)
check(not (D.env.IronforgedCheersFrame and D.env.IronforgedCheersFrame:IsShown()), "non-officers can't call for cheers")
A.ns.Cheers.Call()
H.run(3)
local kf = K.env.IronforgedCheersFrame
check(kf and kf:IsShown(), "cheers popup shown to guildmates")
local kd = K.env.IronforgedCheersDrink
check(kd and kd:GetAttribute("type") == "item" and kd:GetAttribute("item") == "item:2686" and kd:IsEnabled(), "drink button set to the Thunder Ale")
check(kd.__text:find("Thunder Ale", 1, true) ~= nil, "button names the drink")
local dd = D.env.IronforgedCheersDrink
check(dd and dd:GetAttribute("item") == "item:99999", "an unknown stout is found by its name")
local hd = Hh.env.IronforgedCheersDrink
check(hd and not hd:IsEnabled() and hd.__text:find("No ale", 1, true), "no ale, no drink button")
-- Kurdran clicks and drinks
kd.__scripts.PostClick(kd)
K.bags[3].count = 2
H.fire(K, "BAG_UPDATE_DELAYED")
H.run(4)
local heard = false
for _, m in ipairs(K.guildChat) do if m:find("Kurdran chugs a Thunder Ale! Cheers to Thorin!", 1, true) then heard = true end end
check(heard, "the hold hears who chugged an ale")
check(D.env.IronforgedCheersFrame.drinkers.__text:find("Kurdran", 1, true) ~= nil, "popup lists who has drunk")
check(not kd:IsEnabled(), "one ale per call")
A.ns.Cheers.Call()
H.run(2)
local again = 0
for _, m in ipairs(A.guildChat) do if m:find("CHEERS!", 1, true) then again = again + 1 end end
check(again == 1, "officer cooldown between calls")
local afterCount = 0
for _, c in pairs(H.clients) do afterCount = afterCount + #c.guildChat end
check(afterCount == beforeCount + 2 and #A.guildChat > 0 and A.guildChat[#A.guildChat]:find("CHEERS!", 1, true), "cheers: the call and each drink go to guild chat")

-- Cross Gambling
check(D.ns.Gamble._parseRoll("Kurdran rolls 57 (1-100)") == "Kurdran", "roll message parsed")
A.ns.Gamble.Open(100)
check(not A.ns.Gamble.game, "no game outside a raid")
A.inRaid, K.inRaid, D.inRaid, M.inRaid = true, true, true, false
A.leader = true
A.invites = {}
A.ns.settings.autoInvite = false -- hosting overrides it
A.ns.Gamble.Open(100)
H.run(2)
local raidPost, guildPost = false, false
for _, m in ipairs(A.guildChat) do
  if m:find("Type 1 to join", 1, true) then raidPost = true end
  if m:find("Whisper Thorin \"inv\" for an invite", 1, true) then guildPost = true end
end
check(raidPost, "game opened in raid chat")
check(guildPost, "guild told to whisper inv to get into the raid")
local mpop = M.env.IronforgedGambleFrame
check(mpop and mpop:IsShown() and mpop.ask:IsShown() and not mpop.join:IsShown(), "outside the raid: popup offers Ask for invite")
mpop.ask.__scripts.OnClick(mpop.ask)
H.run(2)
check(A.invites[#A.invites] == "Muradin-Forever", "asking whispers inv and the host invites")
M.inRaid = true
H.fire(M, "GROUP_ROSTER_UPDATE")
check(mpop.join:IsShown() and not mpop.ask:IsShown(), "in the raid: popup offers Join")
A.ns.settings.autoInvite = true
check(K.env.IronforgedGambleFrame and K.env.IronforgedGambleFrame:IsShown(), "guildmates get the gambling popup")
K.ns.Gamble.Join(); D.ns.Gamble.Join(); M.ns.Gamble.Join(); A.ns.Gamble.Join()
H.run(2)
check(#A.ns.Gamble.game.order == 4, "four players joined by typing 1")
M.ns.Gamble.Leave()
H.run(2)
check(#A.ns.Gamble.game.order == 3 and #K.ns.Gamble.game.order == 3, "-1 leaves, and everyone sees the table")
A.ns.Gamble.StartRolling()
H.run(2)
check(K.ns.Gamble.game.phase == "rolling", "rolling started everywhere")
K.rollQueue = { 88 }; D.rollQueue = { 88 }; A.rollQueue = { 12 }
K.ns.Gamble.Roll(); D.ns.Gamble.Roll(); A.ns.Gamble.Roll()
H.run(3)
check(A.ns.Gamble.game.phase == "tiehigh", "tie for high goes to a re-roll")
-- a faked roll report from a player's addon is ignored
K.ns.Comm.Send({ op = "XV", id = A.ns.Gamble.game.id, roll = 100 }, "WHISPER", "Thorin-Forever"); H.run(2)
check(A.ns.Gamble.game.tieRolls["Kurdran-Forever"] == nil, "a roll reported by an addon doesn't count")
K.rollQueue = { 40 }; D.rollQueue = { 70 }
K.ns.Gamble.Roll(); D.ns.Gamble.Roll()
H.run(3)
local g = A.ns.Gamble.game
check(g.phase == "done" and g.high == "Dagna-Forever" and g.low == "Thorin-Forever" and g.owed == 76, "high wins, low pays the difference (88 - 12 = 76)")
check(A.guildChat[#A.guildChat]:find("Thorin owes Dagna 76g", 1, true), "result announced in the game's chat")
H.run(5)
local st = K.ns.Gamble.Standings()
local dag, tho
for _, x in ipairs(st) do if x.name == "Dagna-Forever" then dag = x end if x.name == "Thorin-Forever" then tho = x end end
check(dag and dag.net == 76 and tho and tho.net == -76, "Hall of Fortune synced to everyone")
-- Gambling opens from the header, and the host can remove a player
A.ns.ToggleMain("roster")
local gbtn = A.env.StoneholdNone
for _, f in ipairs(A.frames) do if f.__text == "Gambling" and f.__kind == "Button" then gbtn = f end end
check(gbtn ~= nil, "Gambling button in the header")
local navGamble = 0
for _, f in ipairs(A.frames) do if f.__text == "Gambling" then navGamble = navGamble + 1 end end
check(navGamble == 1, "no Gambling entry in the side list")
A.ns.Gamble.Open(50)
H.run(2)
K.ns.Gamble.Join(); D.ns.Gamble.Join(); M.ns.Gamble.Join()
H.run(2)
gbtn.__scripts.OnClick(gbtn)
H.run(1)
local gt
for _, f in ipairs(A.frames) do if f.players and f.board then gt = f end end
local mrow
for _, row in ipairs(gt.players.rows) do if row.item and row.item.data == "Muradin-Forever" then mrow = row end end
mrow.__scripts.OnClick(mrow, "LeftButton")
local yes
for _, b in ipairs(A.env.IronforgedDialog.buttons) do if b.__text == "Yes" then yes = b end end
yes.__scripts.OnClick(yes)
H.run(2)
check(#A.ns.Gamble.game.order == 2 and #K.ns.Gamble.game.order == 2, "host removed a player by clicking their name")
A.ns.Gamble.StartRolling()
K.rollQueue = { 30 }
K.ns.Gamble.Roll()
H.run(3)
check(A.ns.Gamble.game.phase == "rolling", "still waiting on a roll")
A.ns.Gamble.Kick("Dagna-Forever")
H.run(2)
check(A.ns.Gamble.game.phase == "cancelled", "removing down to one player cancels the game")
A.inRaid, K.inRaid, D.inRaid, M.inRaid = false, false, false, false

check(not KD.Put("gambles", "Thorin-Forever#fake", { high = "Kurdran-Forever", low = "Thorin-Forever", owed = 9999, players = {} }, true), "can't record a game in someone else's name")

-- Profession directory
K.profs = { { name = "Blacksmithing", skill = 150, max = 225 }, { name = "Mining", skill = 160, max = 225 }, { name = "First Aid", skill = 141, max = 150 }, { name = "Fishing", skill = 1, max = 75 } }
K.ns.Prof.ScanSkills()
H.run(3)
check(D.ns.Data.Get("crafts", "Kurdran-Forever#First Aid") == nil and D.ns.Data.Get("crafts", "Kurdran-Forever#Fishing") == nil, "First Aid and Fishing left out")
check(D.ns.Data.Get("crafts", "Kurdran-Forever#Blacksmithing") ~= nil and D.ns.Data.Get("crafts", "Kurdran-Forever#Mining").skill == 160, "professions shared with the guild")
K.trade = { name = "Blacksmithing", skill = 151, max = 225, recipes = { [3491] = true, [2741] = true, [12259] = false } }
H.fire(K, "TRADE_SKILL_SHOW")
H.run(3)
local kb = D.ns.Data.Get("crafts", "Kurdran-Forever#Blacksmithing")
check(kb and kb.skill == 151 and D.ns.Prof.RecipeCount(kb) == 2, "known recipes recorded when the profession window opens")
local rn = D.ns.Prof.Recipes(kb)
check(rn[1] == "Big Bronze Knife" and rn[2] == "Bronze Axe", "recipe names resolved on other clients")
local sent = K.ns.Comm.stats.sent
H.fire(K, "TRADE_SKILL_SHOW"); H.run(3)
check(K.ns.Comm.stats.sent == sent, "no resend when nothing changed")
K.trade = { name = "Blacksmithing", linked = true, skill = 300, max = 300, recipes = { [3297] = true } }
H.fire(K, "TRADE_SKILL_SHOW"); H.run(3)
check(D.ns.Prof.RecipeCount(D.ns.Data.Get("crafts", "Kurdran-Forever#Blacksmithing")) == 2, "someone else's linked profession is ignored")
check(not D.ns.Data.Put("crafts", "Kurdran-Forever#Alchemy", { prof = "Alchemy", skill = 300, max = 300 }, true), "can't write someone else's professions")
-- search the directory and ask for a craft
D.ns.ToggleMain("professions")
local pt
for _, f in ipairs(D.frames) do if f.crafters and f.recipes then pt = f end end
pt.search:SetText("bronze axe")
pt.search.__scripts.OnTextChanged(pt.search)
check(pt.recipes:IsShown() and #pt.recipes.items == 1 and pt.recipes.items[1].data.member == "Kurdran-Forever", "recipe search finds the crafter")
local before = #K.chat
pt.recipes.rows[1].__scripts.OnClick(pt.recipes.rows[1], "LeftButton")
local askB
for _, b in ipairs(D.env.IronforgedDialog.buttons) do if b.__text == "Ask" then askB = b end end
askB.__scripts.OnClick(askB)
H.run(2)
local gotReq = false
for i = before + 1, #K.chat do if K.chat[i]:find("Craft request", 1, true) and K.chat[i]:find("Bronze Axe", 1, true) then gotReq = true end end
check(gotReq and K.env.IronforgedNotice and K.env.IronforgedNotice:IsShown(), "craft request reaches the crafter privately")
pt.search:SetText(""); pt.search.__scripts.OnTextChanged(pt.search)
check(pt.profs:IsShown() and #pt.profs.items == 2, "directory opens on one row per profession")
local bsRow
for _, row in ipairs(pt.profs.rows) do if row.item and row.item.data.prof == "Blacksmithing" then bsRow = row end end
bsRow.__scripts.OnClick(bsRow, "LeftButton")
check(pt.crafters:IsShown() and #pt.crafters.items == 1 and pt.crafters.items[1].data.key == "Kurdran-Forever#Blacksmithing", "clicking a profession lists its dwarves")
pt.crafters.rows[1].__scripts.OnClick(pt.crafters.rows[1], "LeftButton")
check(pt.recipes:IsShown() and #pt.recipes.items == 2, "clicking a dwarf lists their recipes")
pt.back.__scripts.OnClick(pt.back); pt.back.__scripts.OnClick(pt.back)
check(pt.profs:IsShown(), "Back returns to the professions")
K.profs = { { name = "Blacksmithing", skill = 151, max = 225 } }
K.ns.Prof.ScanSkills(); H.run(3)
check(D.ns.Data.Get("crafts", "Kurdran-Forever#Mining") == nil, "dropped profession removed")

-- Titles
D.ns.Data.Put("pvp", "Dagna-Forever", { hk = 900, elves = 3, avenged = 0 })
M.ns.Data.Put("pvp", "Muradin-Forever", { hk = 10, elves = 40, avenged = 2 })
H.run(3)
check(A.ns.Titles.Holds("Muradin-Forever", "Elfbane") and not A.ns.Titles.Holds("Dagna-Forever", "Elfbane"), "Elfbane goes to the most elves slain")
check(A.ns.Titles.Holds("Dagna-Forever", "The Hordebreaker"), "The Hordebreaker goes to the most Horde slain")
check(not K.ns.Titles.Award("Dagna-Forever", "Keg Champion"), "only officers award titles")
check(A.ns.Titles.Award("Muradin-Forever", "Keg Champion", "Drank Kurdran under the table"), "officer awards a title")
H.run(3)
check(D.ns.Titles.Text("Muradin-Forever") == "Elfbane, The Grudgebearer, Keg Champion", "titles shared, automatic ones first")
check(M.env.IronforgedNotice:IsShown() and M.env.IronforgedNotice.id == "title", "member told about their new title")
check(not A.ns.Titles.Award("Muradin-Forever", "keg champion"), "no duplicate titles")
A.ns.ToggleMain("blood")
local bt
for _, f in ipairs(A.frames) do if f.champs then bt = f end end
check(bt and bt.champs:GetText():find("Elfbane:", 1, true) and bt.champs:GetText():find("Muradin", 1, true), "Blood Tally names the Elfbane")
local mrow2
for _, row in ipairs(bt.list.rows) do if row.item and row.item.data == "Muradin-Forever" then mrow2 = row end end
check(mrow2 and mrow2.cells[2]:GetText():find("[Elfbane]", 1, true), "Elfbane highlighted in the tally")
mrow2.__scripts.OnClick(mrow2, "LeftButton")
local hasManage, hasAward = false, false
for _, b in ipairs(A.env.IronforgedDialog.buttons) do
  if b.__text == "Manage" or b.__text == "Edit record" then hasManage = true end
  if b.__text == "Award title" then hasAward = true end
end
check(not hasManage and hasAward, "no management buttons from the Blood Tally")
local tkey
for _, t in ipairs(A.ns.Titles.Of("Muradin-Forever")) do if t.key then tkey = t.key end end
A.ns.Titles.Strip(tkey); H.run(3)
check(D.ns.Titles.Text("Muradin-Forever") == "Elfbane, The Grudgebearer", "officer strips a title")

-- Challenges
local CK = K.ns.Challenges
K.level = 5
local late = CK.Start("slayer")
check(late and K.ns.Data.Get("challenges", late).startLevel == 5, "challenges can start at any level")
check(A.ns.Challenges.Label(K.ns.Data.Get("challenges", late)) == "Slayer (from level 5)", "start level shown")
CK.Abandon(late)
K.level = 1
K.equip[5] = 6125; K.equip[3] = 1000; K.equip[4] = 45; K.equip[16] = 25
K.pvp = true
local slayerKey = CK.Start("slayer")
H.run(2)
check(slayerKey and K.equip[5] == nil and K.equip[3] == nil and K.equip[4] == nil and K.equip[16] == 25, "Slayer takes off chest, shoulders and shirt, leaves the weapon")
check(D.ns.Data.Get("challenges", slayerKey) and D.ns.Data.Get("challenges", slayerKey).status == "active", "challenge shared with the guild")
-- bags full: a chest piece that can't come off fails the challenge after a minute
local savedBags = K.bags
K.bags = {}
for i = 1, 16 do K.bags[i] = { id = 1, count = 1, name = "Junk" } end
K.equip[5] = 6125
H.fire(K, "PLAYER_EQUIPMENT_CHANGED", 5)
H.run(1)
check(K.ns.Data.Get("challenges", slayerKey).status == "active", "warned first, not failed at once")
H.run(70)
local sd = D.ns.Data.Get("challenges", slayerKey)
check(sd.status == "failed" and sd.reason:find("chest", 1, true), "wearing chest armor fails Slayer")
K.bags = savedBags; K.equip[5] = nil
-- Self-Made and One Life
local smKey = CK.Start("selfmade")
H.fire(K, "TRADE_SHOW"); H.fire(K, "MAIL_SHOW"); H.fire(K, "AUCTION_HOUSE_SHOW")
check(K.closed.trade and K.closed.mail and K.closed.ah, "Self-Made shuts trade, mail and the auction house")
local olKey = CK.Start("onelife")
H.fire(K, "PLAYER_DEAD"); H.run(2)
check(K.ns.Data.Get("challenges", olKey).status == "failed", "One Life ends on death")
check(K.ns.Data.Get("challenges", smKey).status == "active", "other challenges carry on")
H.fire(K, "PLAYER_LEVEL_UP", 60); H.run(2)
check(D.ns.Data.Get("challenges", smKey).status == "completed" and D.ns.Data.Get("challenges", smKey).lvl == 60, "completed at max level")
-- Dwarf Found
local dfKey = CK.Start("dwarffound")
K.units.NPC = { name = "Hilda", race = "Human" }
K.closed.trade = nil
H.fire(K, "TRADE_SHOW")
check(K.closed.trade, "Dwarf Found cancels trades with non-dwarves")
K.units.NPC = { name = "Dagna", race = "Dwarf" }
K.closed.trade = nil
H.fire(K, "TRADE_SHOW")
check(not K.closed.trade, "trading with a dwarf is fine")
K.units.NPC = nil
K.inGroup = true
K.units.party1 = { name = "Dagna", race = "Dwarf" }
H.fire(K, "GROUP_ROSTER_UPDATE"); H.run(20)
check(not K.left, "grouping with dwarves is fine")
K.units.party2 = { name = "Hilda", race = "Human" }
H.fire(K, "GROUP_ROSTER_UPDATE"); H.run(5)
check(not K.left, "a warning first")
H.run(15)
check(K.left, "leaves a group with a non-dwarf in it")
local warnings = 0
H.fire(K, "GROUP_ROSTER_UPDATE"); H.run(3)
for _, m in ipairs(K.chat) do if m:find("is no dwarf", 1, true) then warnings = warnings + 1 end end
check(warnings == 1, "warned once, not again while leaving")
K.inGroup = false
H.fire(K, "GROUP_ROSTER_UPDATE")
K.units.party1, K.units.party2 = nil, nil
H.fire(K, "PARTY_INVITE_REQUEST", "Hilda-Forever")
check(K.declined, "declines invites from non-dwarf guildmates")
CK.Abandon(dfKey)
-- Slayer: the addon never touches the PvP flag itself (Blizzard blocks that); it warns and fails
local pvpCalls = 0
local realSet, realToggle = K.env.SetPVP, K.env.TogglePVP
K.env.SetPVP = function(...) pvpCalls = pvpCalls + 1; return realSet(...) end
K.env.TogglePVP = function(...) pvpCalls = pvpCalls + 1; return realToggle(...) end
K.pvp = false
local slayer2 = CK.Start("slayer"); H.run(3)
local asked = false
for _, m in ipairs(K.chat) do if m:find("Type |cffffd040/pvp|r within", 1, true) then asked = true end end
check(asked and K.env.IronforgedNotice:IsShown() and K.env.IronforgedNotice.id == "pvp", "not flagged: told to type /pvp")
check(pvpCalls == 0, "the addon never calls the protected PvP functions")
K.pvp = true; H.fire(K, "PLAYER_FLAGS_CHANGED", "player"); H.run(70)
check(K.ns.Data.Get("challenges", slayer2).status == "active", "flagging in time keeps the challenge")
K.pvp = false; H.fire(K, "PLAYER_FLAGS_CHANGED", "player"); H.run(30)
check(K.ns.Data.Get("challenges", slayer2).status == "active", "a minute to flag again before failing")
H.run(40)
local s2 = K.ns.Data.Get("challenges", slayer2)
check(s2.status == "failed" and s2.reason:find("PvP", 1, true), "Slayer fails if not flagged within a minute")
check(pvpCalls == 0, "still no protected calls")
K.env.SlashCmdList.IRONFORGED("pvp")
check(pvpCalls == 0, "/hold pvp only reports")
K.env.SetPVP, K.env.TogglePVP = realSet, realToggle

-- audit: experience gained while Ironforged was off leaves a quiet note on the challenge
K.level, K.xp = 20, 100
local ak = CK.Start(nil, "Audit Me", "Play fair.")
H.run(2)
CK.SaveSnapshot()
local chatBefore = #A.chat
K.xp = 900 -- played with the addon off: no events seen
CK.Audit(true); H.run(2)
local ad = D.ns.Data.Get("challenges", ak)
check(ad.flags == 1 and ad.audit:find("level 20 to 20", 1, true), "XP gained with the addon off leaves a note")
local announced = false
for i = chatBefore + 1, #A.chat do if A.chat[i]:find("Audit Me", 1, true) or A.chat[i]:find("without Ironforged", 1, true) then announced = true end end
check(not announced, "nothing is announced")
check(not A.ns.Challenges.Label(ad):find("FLAG", 1, true), "nothing on the tooltip")
CK.Audit(true); H.run(2)
check(D.ns.Data.Get("challenges", ak).flags == 1, "no new note when nothing was missed")
-- another computer (no snapshot here): XP within the same level isn't counted, a new level is
K.ns.db.xpSnap = nil
K.xp = 1500
CK.Audit(true); H.run(2)
check(D.ns.Data.Get("challenges", ak).flags == 1, "same level on another computer: no note")
K.ns.db.xpSnap = nil
K.level = 22
CK.Audit(true); H.run(2)
local ad2 = D.ns.Data.Get("challenges", ak)
check(ad2.flags == 2 and ad2.audit:find("level 20 to 22", 1, true), "levels gained with the addon off: noted")
CK.Abandon(ak); H.run(1)
K.level, K.xp = 1, 0

-- old records that said "Start at level 1" get today's wording
local oldKey = "Kurdran-Forever#old1"
K.ns.Data.Put("challenges", oldKey, { name = "One Life", preset = "onelife", rules = "Start at level 1. Die once and the challenge is over.", ts = 1, startLevel = 1, lvl = 1, status = "failed" })
K.ns.Challenges.RefreshOldRules(); H.run(2)
check(not D.ns.Data.Get("challenges", oldKey).rules:find("level 1", 1, true), "old level-1 wording replaced")

-- start form shows rules for a ready-made pick, and name/rules boxes only for your own
K.ns.UI.StartChallengeForm("slayer")
local dlg = K.env.IronforgedDialog
local hasName = false
for _, f in ipairs(K.frames) do if f.__kind == "EditBox" and f:IsShown() and f:GetParent() == dlg.body then hasName = true end end
check(not hasName, "no name box for a ready-made challenge")
K.ns.UI.StartChallengeForm("custom")
hasName = false
for _, f in ipairs(K.frames) do if f.__kind == "EditBox" and f:GetParent() == dlg.body then hasName = true end end
check(hasName, "name box for your own challenge")
dlg:Hide()

-- custom, honor system
K.level = 20
local myKey = CK.Start(nil, "No Hearthstone", "Walk everywhere.")
H.run(2)
check(myKey and D.ns.Data.Get("challenges", myKey).name == "No Hearthstone", "custom challenge any level")
check(not D.ns.Data.Put("challenges", "Kurdran-Forever#x", { name = "x", status = "failed" }, true), "can't write someone else's challenge")
CK.Complete(myKey); H.run(2)
check(D.ns.Data.Get("challenges", myKey).status == "active", "can't complete your own challenge")
check(#A.ns.Challenges.Showing("Kurdran-Forever") >= 1, "guildmates' challenges listed for the roster and tooltip")
check(A.ns.Challenges.Judge(myKey, "completed"), "an officer marks it completed")
H.run(2)
check(D.ns.Data.Get("challenges", myKey).status == "completed", "completion reaches the guild")
check(K.env.IronforgedNotice:IsShown() and K.env.IronforgedNotice.id == "challenge", "member told an officer completed it")
local own = A.ns.Challenges.Start(nil, "Thane's Trial", "x"); H.run(1)
check(not A.ns.Challenges.Judge(own, "completed"), "officers can't complete their own either")
K.level = 1

-- Invite from whispers
K.invites = {}
H.fire(K, "CHAT_MSG_WHISPER", " INV ", "Dagna-Forever")
check(K.invites[1] == "Dagna-Forever", "guildmate whispering inv gets invited")
H.fire(K, "CHAT_MSG_WHISPER", "can you inv me later", "Dagna-Forever")
H.fire(K, "CHAT_MSG_WHISPER", "inv", "Grubnak-Forever")
check(#K.invites == 1, "only the keyword, and only guildmates by default")
K.ns.settings.inviteAnyone = true
H.fire(K, "CHAT_MSG_WHISPER", "inv", "Grubnak-Forever")
check(K.invites[2] == "Grubnak-Forever", "anyone can be invited when allowed")
K.ns.settings.inviteAnyone = false
K.ns.settings.inviteKeyword = "inv, 123"
H.fire(K, "CHAT_MSG_WHISPER", "123", "Muradin-Forever")
check(K.invites[3] == "Muradin-Forever", "custom keywords work")
K.ns.settings.autoInvite = false
H.fire(K, "CHAT_MSG_WHISPER", "inv", "Muradin-Forever")
check(#K.invites == 3, "auto invite can be turned off")
K.ns.settings.autoInvite = true
K.ns.settings.inviteKeyword = "inv"
K.invites = {}

-- Looking for Dwarf
local LK = K.ns.LFD
local postKey = LK.Post("Gnomeregan", 2, "Meet at the tram")
H.run(3)
check(postKey and #D.ns.LFD.Posts() == 1, "group post reaches the guild")
check(D.env.IronforgedNotice:IsShown() and D.env.IronforgedNotice.id == "lfd", "guildmates get a sign-up popup")
local healB
for _, b in ipairs(D.env.IronforgedNotice.buttons) do if b.__text == "Healer" then healB = b end end
healB.__scripts.OnClick(healB)
H.run(3)
local joins = LK.Joins(postKey)
check(#joins == 1 and joins[1].member == "Dagna-Forever" and joins[1].role == "healer", "signed up as healer from the popup")
check(K.env.IronforgedNotice:IsShown() and K.env.IronforgedNotice.id == "lfdjoin", "leader told who answered")
local invB
for _, b in ipairs(K.env.IronforgedNotice.buttons) do if b.__text == "Invite" then invB = b end end
invB.__scripts.OnClick(invB)
check(K.invites[1] == "Dagna-Forever", "leader invites from the popup")
check(not M.ns.Data.Put("lfdjoin", postKey .. "#Dagna-Forever", { role = "tank", ts = 1 }, true), "can't sign someone else up")
check(not M.ns.Data.Put("lfd", "Kurdran-Forever#fake", { what = "x", need = 1, ts = 1 }, true), "can't post in someone else's name")
M.ns.LFD.Join(postKey, "tank"); H.run(3)
check(LK.IsFull(postKey), "post fills up")
H.clock = H.clock + 7300
check(#D.ns.LFD.Posts() == 0, "posts close after two hours")
LK.Sweep(); H.run(3)
check(D.ns.Data.Get("lfd", postKey) == nil and #D.ns.LFD.Joins(postKey) == 0, "expired post and sign-ups cleaned up")
local p2 = LK.Post("Deadmines", 4); H.run(2)
local p3 = LK.Post("Stockades", 3); H.run(2)
check(#D.ns.LFD.Posts() == 1 and D.ns.LFD.Posts()[1].data.what == "Stockades", "one post per leader")

-- Late joiner converges
local F = H.makeClient("Frugo", nil, "Frugo-Mega"); F.guidOverride = "Player-Frugo-Mega"
H.boot(F)
H.run(90)
for _, coll in ipairs(AD.COLLECTIONS) do
  check(F.ns.Data.Digest(coll) == AD.Digest(coll), "late joiner digest " .. coll)
end
check(F.ns.PlayerName() == "Frugo-Mega" and F.ns.IAmOfficer(), "matched by character ID")

-- A guildmate with a Forever surname: whispers go to their real character name
local Bc = H.makeClient("Buttercup", nil, "Buttercup Clamstone-Forever"); Bc.guidOverride = "Player-Buttercup Clamstone-Forever"
H.boot(Bc)
H.run(90)
check(Bc.ns.PlayerName() == "Buttercup Clamstone-Forever", "surnamed member recognised")
check(Bc.ns.Data.Digest("grudges") == AD.Digest("grudges"), "surnamed member syncs (whispered records arrive)")
check(A.ns.CharName("Buttercup Clamstone-Forever") == "Buttercup-Forever" and A.ns.CharName("Buttercup Clamstone-Forever", false) == "Buttercup", "real character name")
A.inRaid, K.inRaid, D.inRaid, Bc.inRaid = true, true, true, true
A.ns.Gamble.Open(100); H.run(2)
Bc.ns.Gamble.Join(); K.ns.Gamble.Join(); H.run(2)
A.ns.Gamble.StartRolling(); H.run(2)
Bc.rollQueue = { 86 }; K.rollQueue = { 12 }
Bc.ns.Gamble.Roll(); K.ns.Gamble.Roll(); H.run(4)
check(A.ns.Gamble.game.rolls["Buttercup Clamstone-Forever"] == 86 and A.ns.Gamble.game.phase == "done", "surnamed player's roll counted in a raid")
Bc.ns.Gamble.Open(50); H.run(2)
K.ns.Gamble.Join(); D.ns.Gamble.Join(); H.run(2)
Bc.ns.Gamble.StartRolling(); H.run(2)
K.rollQueue = { 40 }; D.rollQueue = { 7 }
K.ns.Gamble.Roll(); D.ns.Gamble.Roll(); H.run(4)
check(Bc.ns.Gamble.game.phase == "done" and Bc.ns.Gamble.game.rolls["Kurdran-Forever"] == 40, "rolls reach a surnamed host")
A.inRaid, K.inRaid, D.inRaid, Bc.inRaid = false, false, false, false

-- UI smoke test for every role
for _, client in ipairs({ A, M, D, K, Hh, B, F }) do
  local cns = client.ns
  local ok, err = pcall(function()
    cns.ToggleMain()
    for _, id in ipairs({ "roster", "clans", "trials", "events", "lfd", "professions", "challenges", "grudges", "blood", "gamble", "profile", "settings" }) do cns.UI.SelectTab(id) end
    H.run(1)
    cns.UI.ShowMember("Muradin-Forever")
    cns.UI.GiveTrial("Kurdran-Forever")
    local snapshot = {}
    for i, f in ipairs(client.frames) do snapshot[i] = f end
    for _, f in ipairs(snapshot) do
      if f.__kind == "Button" and f.__scripts.OnClick and f.__text ~= "" then
        CLICKS = (CLICKS or 0) + 1
        local okc, e = pcall(f.__scripts.OnClick, f, "LeftButton")
        if not okc then error("button '" .. tostring(f.__text) .. "': " .. tostring(e)) end
      end
    end
    H.run(2)
  end)
  check(ok, "UI smoke " .. client.name .. (ok and "" or (": " .. tostring(err))))
end

local ok = pcall(function()
  for _, cmd in ipairs({ "", "toast", "lore", "oath", "sync", "status", "help" }) do A.env.SlashCmdList.IRONFORGED(cmd) end
end)
check(ok and A.env.SLASH_IRONFORGED3 == "/if", "slash commands, including /if")

local anyGuild = 0
for _, c in pairs(H.clients) do
  for _, m in ipairs(c.guildChat) do if not (m:find("CHEERS!", 1, true) or m:find(" chugs ", 1, true) or m:find("Gambling", 1, true) or m:find("^%-?1$") or m:find(" owes ", 1, true) or m:find("Rolling for", 1, true) or m:find("Tie for", 1, true) or m:find("Last call", 1, true) or m:find("removed from the game", 1, true) or m:find("Not enough players", 1, true)) then anyGuild = anyGuild + 1; print("GUILDCHAT: " .. m) end end
end
check(anyGuild == 0, "only Cheers and Cross Gambling post to guild chat")
print("buttons clicked: " .. tostring(CLICKS))
print(string.format("%d passed, %d failed, %d messages delivered", passed, failed, H.delivered or 0))
os.exit(failed == 0 and 0 or 1)
