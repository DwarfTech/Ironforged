-- Ironforged: Professions tab, the guild's profession directory.
local ADDON, ns = ...
local UI = ns.UI
local P = ns.Prof

local state = { search = "", prof = nil, online = false, crafter = nil }
local MAX_ROWS = 600

local function first(name) return (ns.Name(name):match("^(%S+)")) or ns.Name(name) end

local function isOnline(member) return ns.roster[member] and ns.roster[member].online end

local function askToCraft(member, recipe)
  if not isOnline(member) then
    ns.Print(ns.Name(member) .. " is offline. Catch them later, or send a letter.")
    return
  end
  UI.OpenForm({
    title = "Ask " .. first(member) .. " to craft",
    width = 460,
    fields = {
      { type = "info", value = "Ask |cffd4a017" .. ns.Name(member) .. "|r to make |cffffd040" .. recipe .. "|r. They get a private popup; nothing goes to chat." },
      { key = "note", label = "Note (optional)", type = "text", value = "", maxLen = 120 },
    },
    saveText = "Ask",
    onSave = function(v) P.Request(member, recipe, v.note) end,
  })
end

local function showOnly(f, which)
  for _, l in ipairs({ f.profs, f.crafters, f.recipes }) do l:SetShown(l == which) end
end

local function refresh(f)
  local all = P.All()
  local search = state.search
  local items = {}
  local crafterRec

  if state.crafter then
    for _, r in ipairs(all) do if r.key == state.crafter then crafterRec = r end end
    if not crafterRec then state.crafter = nil end
  end
  f.back:SetShown(state.crafter ~= nil or state.prof ~= nil)

  if crafterRec or search ~= "" then
    -- recipes: one dwarf's, or every match for the search
    showOnly(f, f.recipes)
    local count = 0
    for _, r in ipairs(all) do
      if (not crafterRec or r == crafterRec) and (not state.prof or r.prof == state.prof) and (not state.online or isOnline(r.member)) then
        for _, recipe in ipairs(P.Recipes(r.data)) do
          if search == "" or recipe:lower():find(search, 1, true) then
            count = count + 1
            if count <= MAX_ROWS then
              local on = isOnline(r.member)
              items[#items + 1] = {
                data = { kind = "recipe", member = r.member, recipe = recipe },
                keys = { [4] = r.skill },
                color = (not on) and { 0.6, 0.6, 0.6 } or nil,
                cols = { recipe, (on and "|cff40ff40" or "|cff999999") .. ns.Name(r.member) .. "|r", r.prof, r.skill .. "/" .. r.max },
              }
            end
          end
        end
      end
    end
    if crafterRec then
      f.info:SetText("|cffd4a017" .. ns.Name(crafterRec.member) .. "|r: " .. crafterRec.prof .. " " .. crafterRec.skill .. "/" .. crafterRec.max ..
        "  |cff999999(" .. P.RecipeCount(crafterRec.data) .. " recipes)|r" .. (isOnline(crafterRec.member) and "  |cff40ff40online|r" or ""))
    else
      f.info:SetText(count .. (count == 1 and " recipe" or " recipes") .. " found" .. (state.prof and (" in " .. state.prof) or "") ..
        (count > MAX_ROWS and (", showing the first " .. MAX_ROWS) or "") .. ". Click one to ask that dwarf to craft it.")
    end
    table.sort(items, function(a, b)
      local ao, bo = isOnline(a.data.member) and 1 or 0, isOnline(b.data.member) and 1 or 0
      if ao ~= bo then return ao > bo end
      if a.data.recipe ~= b.data.recipe then return a.data.recipe < b.data.recipe end
      return a.data.member < b.data.member
    end)
    f.recipes:SetItems(items, crafterRec and "No recipes recorded yet. They need to open their profession window once." or "No dwarf in the hold knows a recipe like that yet.")
    return
  end

  if state.prof then
    -- the dwarves in one profession, best first
    showOnly(f, f.crafters)
    for _, r in ipairs(all) do
      if r.prof == state.prof and (not state.online or isOnline(r.member)) then
        local on = isOnline(r.member)
        local n = P.RecipeCount(r.data)
        items[#items + 1] = {
          data = { kind = "crafter", key = r.key },
          skill = r.skill, member = r.member,
          keys = { [2] = r.skill, [3] = n, [4] = on and 1 or 0 },
          cols = { ns.ColorName(r.member), r.skill .. "/" .. r.max, n > 0 and n or "|cff888888-|r", on and "|cff40ff40Online|r" or "|cff999999Offline|r" },
        }
      end
    end
    table.sort(items, function(a, b)
      if a.skill ~= b.skill then return a.skill > b.skill end
      return a.member < b.member
    end)
    f.info:SetText("|cffd4a017" .. state.prof .. "|r: " .. #items .. (#items == 1 and " dwarf" or " dwarves") ..
      ". Click one to see what they can make, or search to look only in " .. state.prof .. ".")
    f.crafters:SetItems(items, "No dwarf in the hold has " .. state.prof .. " yet.")
    return
  end

  -- one row per profession
  showOnly(f, f.profs)
  local byProf = {}
  for _, r in ipairs(all) do
    if not state.online or isOnline(r.member) then
      local b = byProf[r.prof]
      if not b then b = { n = 0, on = 0 }; byProf[r.prof] = b end
      b.n = b.n + 1
      if isOnline(r.member) then b.on = b.on + 1 end
      if not b.top or r.skill > b.top.skill then b.top = r end
    end
  end
  for _, name in ipairs(P.NAMES) do
    local b = byProf[name]
    if b then
      items[#items + 1] = {
        data = { kind = "prof", prof = name },
        keys = { [4] = b.top.skill },
        cols = { name, b.n, b.on > 0 and ("|cff40ff40" .. b.on .. "|r") or "|cff9999990|r",
          ns.Name(b.top.member) .. " |cff999999(" .. b.top.skill .. ")|r" },
      }
    end
  end
  table.sort(items, function(a, b) return a.cols[2] > b.cols[2] end)
  f.info:SetText("Search for a recipe, or click a profession to see who has it.")
  f.profs:SetItems(items, "No professions recorded yet. They appear as guildmates with Ironforged log in.")
end

local function build(f, w, h)
  local sl = UI.Label(f, "Search:", "GameFontNormalSmall")
  sl:SetPoint("TOPLEFT", 6, -10)
  f.search = UI.EditBox(f, 200, 40)
  f.search:SetPoint("LEFT", sl, "RIGHT", 10, 0)
  f.search:SetText(state.search)
  f.search:SetScript("OnTextChanged", function(self)
    state.search = ns.Trim(self:GetText() or ""):lower()
    refresh(f)
  end)
  f.onlineC = UI.Check(f, "Online only", function(self) state.online = self:GetChecked() and true or false; refresh(f) end)
  f.onlineC:SetPoint("LEFT", f.search, "RIGHT", 12, 0)
  f.onlineC:SetChecked(state.online)
  f.back = UI.Button(f, "Back", 64, 22, function()
    if state.crafter then state.crafter = nil else state.prof = nil end
    refresh(f)
  end)
  f.back:SetPoint("TOPRIGHT", -4, -6)

  f.info = UI.Label(f, "", "GameFontHighlightSmall")
  f.info:SetPoint("TOPLEFT", 6, -38)
  f.info:SetPoint("TOPRIGHT", -6, -38)
  f.info:SetWordWrap(false)

  local function onClick(d)
    if type(d) ~= "table" then return end
    if d.kind == "prof" then
      state.prof = d.prof
      refresh(f)
    elseif d.kind == "crafter" then
      state.crafter = d.key
      refresh(f)
    elseif d.kind == "recipe" then
      askToCraft(d.member, d.recipe)
    end
  end
  f.profs = UI.List(f, w, h - 84, {
    { title = "Profession", width = 180 }, { title = "Dwarves", width = 100 }, { title = "Online", width = 100 }, { title = "Most skilled", width = 220 },
  }, onClick)
  f.profs:SetPoint("TOPLEFT", 0, -56)
  f.profs:SetPoint("BOTTOMRIGHT", 0, 28)
  f.crafters = UI.List(f, w, h - 84, {
    { title = "Dwarf", width = 220 }, { title = "Skill", width = 110 }, { title = "Recipes", width = 110 }, { title = "Status", width = 110 },
  }, onClick)
  f.crafters:SetPoint("TOPLEFT", 0, -56)
  f.crafters:SetPoint("BOTTOMRIGHT", 0, 28)
  f.crafters:Hide()
  f.recipes = UI.List(f, w, h - 84, {
    { title = "Recipe", width = 250 }, { title = "Crafter", width = 160 }, { title = "Profession", width = 120 }, { title = "Skill", width = 80 },
  }, onClick)
  f.recipes:SetPoint("TOPLEFT", 0, -56)
  f.recipes:SetPoint("BOTTOMRIGHT", 0, 28)
  f.recipes:Hide()

  f.note = UI.Label(f, "Open each of your profession windows once so the hold can see your recipes.", "GameFontDisableSmall")
  f.note:SetPoint("BOTTOMLEFT", 4, 6)
end

UI.RegisterTab("professions", "Professions", build, refresh)
UI.AskToCraft = askToCraft
