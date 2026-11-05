-- Mixed versions: one guildmate on an older release (arg[2]) alongside current clients.
-- Run: lua5.1 sync_mixed.lua .. /path/to/old/Ironforged
package.path = arg[0]:gsub("sync_mixed%.lua$", "?.lua") .. ";" .. package.path
local H = require("harness")
local OLD = arg[2]
local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. label) end
end
local function note(cond, label) print((cond and "  yes: " or "  no:  ") .. label) end

local A = H.makeClient("Thorin")      -- guild master, current
local K = H.makeClient("Kurdran")     -- current
H.versionDir = OLD
local D = H.makeClient("Dagna")       -- older release
H.versionDir = nil
for _, c in ipairs({ A, K, D }) do c.ns.debug = true; H.boot(c) end
H.run(60)
print("old client is " .. tostring(D.ns.VERSION) .. ", others " .. tostring(K.ns.VERSION))

-- live edits both ways
K.level = 12
local kc = K.ns.Challenges.Start("onelife"); H.run(5)
check(D.ns.Data.Get("challenges", kc) ~= nil, "old client gets a current client's challenge live")
check(K.ns.Data.Put("grudges", "orcface", { against = "Orcface", deed = "ganked us", ts = 1 }), "current client writes a grudge")
H.run(5)
check(D.ns.Data.Get("grudges", "orcface") ~= nil, "old client gets the grudge (always-synced)")
D.level = 20
local dc = D.ns.Challenges.Start("onelife"); H.run(5)
check(K.ns.Data.Get("challenges", dc) ~= nil and A.ns.Data.Get("challenges", dc) ~= nil, "current clients get the old client's challenge live")
check(D.ns.Data.Put("grudges", "trollguy", { against = "Trollguy", deed = "stole a node", ts = 2 }), "old client writes a grudge")
H.run(5)
check(K.ns.Data.Get("grudges", "trollguy") ~= nil, "current client gets the old client's grudge")

-- login catch-up with an officer online
H.logout(D); H.run(5)
check(K.ns.Data.Put("clans", "deepforge", { name = "Deepforge", founder = "Kurdran", leader = "Kurdran" }), "clan founded while the old client is away")
local kc2 = K.ns.Challenges.Start("dwarffound"); H.run(5)
H.versionDir = OLD; D = H.relog(D); H.versionDir = nil; D.ns.debug = true
H.run(120)
check(D.ns.Data.Get("clans", "deepforge") ~= nil, "old client catches up on a clan at login")
check(D.ns.Data.Get("challenges", kc2) ~= nil, "old client catches up on a challenge at login (officer online)")

-- the other way: the current client away, the old one writes
H.logout(K); H.run(5)
local dc2 = D.ns.Challenges.Start("slayer"); H.run(5)
K = H.relog(K); K.ns.debug = true; H.run(120)
check(dc2 and K.ns.Data.Get("challenges", dc2) ~= nil, "current client catches up on the old client's challenge at login")

-- errors: none of the clients may log a Lua error
local errs = 0
for _, c in ipairs({ A, K, D }) do
  for _, m in ipairs(c.chat) do if m:find("error in", 1, true) then errs = errs + 1; print("  " .. c.name .. ": " .. m) end end
end
check(errs == 0, "no Lua errors on any client")

print("Features that need everyone on the new version:")
local ak = K.ns.PlayerName() .. "#x"
note(true, "(appeals only exist on 2.18.0+; old clients ignore them)")
check(K.ns.Data.Put("clans", "stonefist", { name = "Stonefist", founder = "Kurdran", leader = "Kurdran" }) or true, "")
H.run(5)
local A2 = A.ns.Data
A.ns.Data.Put("clanship", A.ns.PlayerName(), { clan = "stonefist" }); H.run(10)
note(K.ns.Data.ClanOf("Thorin") == "stonefist", "current client sees an open clan join")
note(D.ns.Data.ClanOf("Thorin") == "stonefist", "old client sees an open clan join")

print(string.format("%d passed, %d failed, %d messages delivered", passed, failed, H.delivered or 0))
os.exit(failed == 0 and 0 or 1)
