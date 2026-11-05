-- The case from the guild: a clan is made while you're offline, its founder logs off, and the
-- players online when you come back are a mix of ones who have it and ones who missed it too.
-- Within the hour, everyone must end up with it.
package.path = arg[0]:gsub("sync_stale%.lua$", "?.lua") .. ";" .. package.path
local H = require("harness")
math.randomseed(tonumber(arg[2]) or 1)
local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. label) end
end
for _, r in ipairs(H.ROSTER) do
  if r[2] == "Thane" or r[2] == "Longbeard" then H.offline[r[1]] = true end
end
local K = H.makeClient("Kurdran")   -- founds the clan
local X = H.makeClient("Gimli")     -- online when it's founded
local M = H.makeClient("Muradin")   -- away
local D = H.makeClient("Dagna")     -- away
local G = H.makeClient("Grimm")     -- away
local Hd = H.makeClient("Hilda")    -- away
for _, c in ipairs({ K, X, M, D, G, Hd }) do H.boot(c) end
H.run(90)
for _, c in ipairs({ M, D, G, Hd }) do H.logout(c) end
H.run(5)
check(K.ns.Data.Put("clans", "deepforge", { name = "Deepforge", founder = "Kurdran", leader = "Kurdran" }), "Kurdran founds a clan")
H.run(10)
check(X.ns.Data.Get("clans", "deepforge") ~= nil, "Gimli has it")
H.logout(K); H.logout(X); H.run(5)
-- the others come back while nobody who has the clan is on, so they catch up on nothing
M = H.relog(M); G = H.relog(G); Hd = H.relog(Hd); H.run(120)
-- Gimli (has it) comes back, then Dagna
X = H.relog(X); H.run(120)
D = H.relog(D)
H.run(75 * 60) -- an hour and a quarter of normal play
for _, c in ipairs({ D, M, G, Hd }) do
  check(c.ns.Data.Get("clans", "deepforge") ~= nil, c.name .. " ends up with the clan")
end
print(string.format("%d passed, %d failed, %d messages delivered", passed, failed, H.delivered or 0))
os.exit(failed == 0 and 0 or 1)
