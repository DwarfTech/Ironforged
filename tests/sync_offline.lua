-- Sync with no Longbeard or guild master online: records written by someone who is now offline
-- still reach a member who logs in later, through whoever else is online.
package.path = arg[0]:gsub("sync_offline%.lua$", "?.lua") .. ";" .. package.path
local H = require("harness")
local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. label) end
end
-- nobody with officer rank runs the addon in this test
for _, r in ipairs(H.ROSTER) do
  if r[2] == "Thane" or r[2] == "Longbeard" then H.offline[r[1]] = true end
end

local M = H.makeClient("Muradin")   -- Veteran
local D = H.makeClient("Dagna")     -- Noble
local K = H.makeClient("Kurdran")   -- Vanguard
for _, c in ipairs({ M, D, K }) do H.boot(c) end
H.run(60)

-- Dagna logs off. Kurdran takes on a challenge and founds a clan, then logs off too.
H.logout(D); H.run(5)
K.level = 12
local key = K.ns.Challenges.Start("onelife"); H.run(5)
check(key and M.ns.Data.Get("challenges", key) ~= nil, "Muradin (online) gets Kurdran's challenge straight away")
check(K.ns.Data.Put("clans", "deepforge", { name = "Deepforge", founder = "Kurdran", leader = "Kurdran" }), "Kurdran founds a clan")
H.run(5)
check(M.ns.Data.Get("clans", "deepforge") ~= nil, "Muradin gets the clan straight away")
H.logout(K); H.run(5)

-- Dagna comes back while only Muradin is on. Does she catch up on what Kurdran did?
D = H.relog(D)
H.run(120)

check(D.ns.Data.Get("clans", "deepforge") ~= nil, "Dagna catches up on Kurdran's clan (always-synced)")
check(D.ns.Data.Get("challenges", key) ~= nil, "Dagna catches up on Kurdran's challenge with no officer online")

-- a member still can't forge someone else's record in a catch-up reply
local fake = { d = { name = "One Life", status = "failed", ts = 1, preset = "onelife" }, t = D.ns.Stamp(), b = "Muradin" }
M.ns.Comm.Inject("Dagna", { op = "B", c = "challenges", recs = { ["Kurdran#forged"] = fake } }, "WHISPER")
check(M.ns.Data.Get("challenges", "Kurdran#forged") == nil, "a forged record in a catch-up reply is refused (its author couldn't write it)")
local live = { d = { name = "x", status = "failed", ts = 1 }, t = D.ns.Stamp(), b = "Kurdran" }
M.ns.Comm.Inject("Dagna", { op = "P", c = "challenges", k = "Kurdran#live", r = live })
check(M.ns.Data.Get("challenges", "Kurdran#live") == nil, "a live edit in someone else's name is refused")

-- traffic: how many addon messages that took
print(string.format("%d passed, %d failed, %d messages delivered", passed, failed, H.delivered or 0))
os.exit(failed == 0 and 0 or 1)
