-- Ironforged: small widget kit (lists, buttons, form dialogs, pick menus).
local ADDON, ns = ...

local UI = {}
ns.UI = UI

UI.GOLD = { 0.83, 0.63, 0.09 }

-- Dwarven look: dark rock behind a stone border, bronze trim, Morpheus lettering.
UI.TITLE_FONT = "Fonts\\MORPHEUS.TTF"
UI.BRONZE = { 0.78, 0.53, 0.22 }

local STONE_BACKDROP = {
  bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 256, edgeSize = 28,
  insets = { left = 8, right = 8, top = 8, bottom = 8 },
}
local PANEL_BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8X8",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = false, edgeSize = 12,
  insets = { left = 2, right = 2, top = 2, bottom = 2 },
}
local BUTTON_BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8X8",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = false, edgeSize = 10,
  insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

function UI.Backdrop(frame, panel)
  if not frame.SetBackdrop then return end
  if panel then
    frame:SetBackdrop(PANEL_BACKDROP)
    frame:SetBackdropColor(0.06, 0.05, 0.04, 0.82)
    frame:SetBackdropBorderColor(UI.BRONZE[1] * 0.7, UI.BRONZE[2] * 0.7, UI.BRONZE[3] * 0.7, 1)
  else
    -- solid underlay so the window stays dark even if the rock texture is missing
    if not frame.underlay then
      local u = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
      u:SetPoint("TOPLEFT", 8, -8)
      u:SetPoint("BOTTOMRIGHT", -8, 8)
      u:SetColorTexture(0.1, 0.085, 0.07, 0.97)
      frame.underlay = u
    end
    frame:SetBackdrop(STONE_BACKDROP)
    frame:SetBackdropColor(0.55, 0.5, 0.45, 0.9)
    frame:SetBackdropBorderColor(0.85, 0.7, 0.45, 1)
  end
end

-- Large carved-letter heading.
function UI.TitleFont(fs, size)
  if not fs.SetFont or not fs:SetFont(UI.TITLE_FONT, size or 20, "") then
    fs:SetFontObject("GameFontNormalLarge")
  end
  fs:SetTextColor(0.95, 0.78, 0.38)
  if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
end

-- Bronze plate styling for any button (also used on secure buttons).
function UI.StyleButton(b)
  if b.SetBackdrop then
    b:SetBackdrop(BUTTON_BACKDROP)
    b:SetBackdropColor(0.28, 0.18, 0.08, 0.95)
    b:SetBackdropBorderColor(UI.BRONZE[1], UI.BRONZE[2], UI.BRONZE[3], 1)
  end
  b:SetNormalFontObject("GameFontNormal")
  b:SetHighlightFontObject("GameFontHighlight")
  b:SetDisabledFontObject("GameFontDisable")
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetPoint("TOPLEFT", 3, -3)
  hl:SetPoint("BOTTOMRIGHT", -3, 3)
  hl:SetColorTexture(1, 0.8, 0.35, 0.18)
  b:SetHighlightTexture(hl)
  local pushed = b:CreateTexture(nil, "ARTWORK")
  pushed:SetPoint("TOPLEFT", 3, -3)
  pushed:SetPoint("BOTTOMRIGHT", -3, 3)
  pushed:SetColorTexture(0, 0, 0, 0.3)
  b:SetPushedTexture(pushed)
end

function UI.Label(parent, text, font, r, g, b)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  fs:SetText(text or "")
  if r then fs:SetTextColor(r, g, b) end
  fs:SetJustifyH("LEFT")
  return fs
end

function UI.Button(parent, text, width, height, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  UI.StyleButton(b)
  b:SetSize(width or 100, height or 22)
  b:SetText(text)
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

function UI.Check(parent, text, onClick)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(24, 24)
  local label = UI.Label(c, text, "GameFontHighlightSmall")
  label:SetPoint("LEFT", c, "RIGHT", 2, 0)
  c.label = label
  if onClick then c:SetScript("OnClick", onClick) end
  return c
end

function UI.EditBox(parent, width, maxLetters)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(width or 200, 20)
  e:SetAutoFocus(false)
  if maxLetters then e:SetMaxLetters(maxLetters) end
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return e
end

-- Multi-line text box inside a scroll frame.
function UI.MultiLine(parent, width, height, maxLetters)
  local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  holder:SetSize(width, height)
  UI.Backdrop(holder, true)
  local scroll = CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 6, -6)
  scroll:SetPoint("BOTTOMRIGHT", -26, 6)
  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetFontObject("ChatFontNormal")
  edit:SetWidth(width - 36)
  edit:SetAutoFocus(false)
  if maxLetters then edit:SetMaxLetters(maxLetters) end
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  scroll:SetScrollChild(edit)
  holder:SetScript("OnSizeChanged", function(_, w) edit:SetWidth(math.max(20, (w or width) - 36)) end)
  holder:EnableMouse(true)
  holder:SetScript("OnMouseDown", function() edit:SetFocus() end)
  holder.edit = edit
  function holder:SetText(t) edit:SetText(t or "") end
  function holder:GetText() return edit:GetText() end
  return holder
end

-- Show a pick list next to `owner`. options = { {text=, value=}, ... }
-- A picker with a search box, for long lists such as the guild roster.
local picker
local function buildPicker()
  if picker then return picker end
  picker = CreateFrame("Frame", "IronforgedPicker", UIParent, "BackdropTemplate")
  picker:SetSize(280, 360)
  picker:SetFrameStrata("FULLSCREEN_DIALOG")
  picker:SetToplevel(true)
  picker:EnableMouse(true)
  picker:SetClampedToScreen(true)
  UI.Backdrop(picker)
  tinsert(UISpecialFrames, "IronforgedPicker")
  picker.title = UI.Label(picker, "", "GameFontNormal")
  picker.title:SetPoint("TOPLEFT", 12, -10)
  local close = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)
  picker.search = UI.EditBox(picker, 250, 40)
  picker.search:SetPoint("TOPLEFT", 16, -32)
  picker.hint = UI.Label(picker.search, "Type to search", "GameFontDisableSmall")
  picker.hint:SetPoint("LEFT", 4, 0)
  picker.list = UI.List(picker, 268, 300, { { title = "", width = 230, noSort = true } }, function(i)
    local opt = picker.options and picker.options[i]
    if opt then picker:Hide(); picker.onPick(opt.value, opt.text) end
  end)
  picker.list:SetPoint("TOPLEFT", 6, -54)
  local function filter()
    local q = (picker.search:GetText() or ""):lower()
    picker.hint:SetShown(q == "")
    local items = {}
    for i, opt in ipairs(picker.options or {}) do
      local t = tostring(opt.text or "")
      if q == "" or t:lower():find(q, 1, true) then items[#items + 1] = { data = i, cols = { t } } end
    end
    picker.matches = items
    picker.list.offset = 0
    picker.list:SetItems(items, "No one by that name.")
  end
  picker.search:SetScript("OnTextChanged", filter)
  picker.search:SetScript("OnEnterPressed", function()
    local first = picker.matches and picker.matches[1]
    if first then local opt = picker.options[first.data]; picker:Hide(); picker.onPick(opt.value, opt.text) end
  end)
  picker.search:SetScript("OnEscapePressed", function() picker:Hide() end)
  picker.filter = filter
  picker:Hide()
  return picker
end

function UI.SearchPick(owner, options, onPick, title)
  local p = buildPicker()
  p.options, p.onPick = options, onPick
  p.title:SetText(title or "Pick one")
  p:ClearAllPoints()
  if owner then p:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2) else p:SetPoint("CENTER") end
  p.search:SetText("")
  p.filter()
  p:Show()
  p.search:SetFocus()
  return p
end

function UI.Pick(owner, options, onPick, title)
  -- long lists (the roster) get a picker with a search box
  if #options > 15 then UI.SearchPick(owner, options, onPick, title); return end
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(owner, function(_, root)
      if title and root.CreateTitle then root:CreateTitle(title) end
      if #options > 18 and root.SetScrollMode then root:SetScrollMode(360) end
      for _, opt in ipairs(options) do
        root:CreateButton(opt.text, function() onPick(opt.value, opt.text) end)
      end
    end)
    return
  end
  -- Fallback: cycle to the next option.
  owner._pickIndex = ((owner._pickIndex or 0) % #options) + 1
  local opt = options[owner._pickIndex]
  if opt then onPick(opt.value, opt.text) end
end

----------------------------------------------------------------------
-- Scrolling list with columns.
-- columns = { {title=, width=}, ... }; items = { {cols = {...}, data = any, color = {r,g,b}} }
----------------------------------------------------------------------
function UI.List(parent, width, height, columns, onClick, rowHeight)
  rowHeight = rowHeight or 20
  local list = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  list:SetSize(width, height)
  UI.Backdrop(list, true)
  list.columns = columns
  list.items = {}
  list.offset = 0
  list.onClick = onClick
  list.rows = {}
  list.visible = 0

  -- The list stretches with its anchors: column widths are scaled from the widths given here
  -- and as many rows are shown as fit the height.
  local baseInner = width - 28
  local colX, colW = {}, {}
  for c, col in ipairs(columns) do colW[c] = col.width end

  local header = CreateFrame("Frame", nil, list)
  header:SetPoint("TOPLEFT", 6, -5)
  header:SetSize(width - 28, 18)
  -- Click a column title to sort by it; click again to reverse.
  list.headers = {}
  for c, col in ipairs(columns) do
    local hb = CreateFrame("Button", nil, header)
    local fs = UI.Label(hb, col.title, "GameFontNormalSmall")
    fs:SetPoint("LEFT", 0, 0)
    fs:SetWordWrap(false)
    hb.label, hb.title = fs, col.title
    local hl = hb:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.8, 0.35, 0.12)
    if not col.noSort then
      hb:SetScript("OnClick", function()
        if list.sortCol == c then list.sortAsc = not list.sortAsc
        else list.sortCol, list.sortAsc = c, true end
        list.offset = 0 -- back to the top of the newly sorted list
        list:SetItems(list.rawItems, list.emptyText)
      end)
    end
    list.headers[c] = hb
  end
  local bar = list:CreateTexture(nil, "BORDER")
  bar:SetPoint("TOPLEFT", 3, -3)
  bar:SetPoint("TOPRIGHT", -3, -3)
  bar:SetHeight(21)
  bar:SetColorTexture(0.35, 0.22, 0.09, 0.55)
  local line = list:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(0.72, 0.55, 0.2, 0.7)
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", 6, -24)
  line:SetPoint("TOPRIGHT", -22, -24)

  local innerW = baseInner

  local function placeRow(row)
    row:SetWidth(innerW)
    for c = 1, #columns do
      local fs = row.cells[c]
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", colX[c] or 0, 0)
      fs:SetWidth(math.max(8, (colW[c] or columns[c].width) - 4))
    end
  end

  local function makeRow(i)
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(rowHeight)
    row:SetPoint("TOPLEFT", 6, -26 - (i - 1) * rowHeight)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.83, 0.63, 0.09, 0.15)
    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints()
    stripe:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0)
    row.cells = {}
    for c = 1, #columns do
      local fs = UI.Label(row, "", "GameFontHighlightSmall")
      fs:SetWordWrap(false)
      row.cells[c] = fs
    end
    placeRow(row)
    row:SetScript("OnClick", function(self, button)
      if self.item and list.onClick then list.onClick(self.item.data, self, button) end
    end)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    list.rows[i] = row
    return row
  end

  local slider = CreateFrame("Slider", nil, list)
  slider:SetPoint("TOPRIGHT", -6, -26)
  slider:SetPoint("BOTTOMRIGHT", -6, 6)
  slider:SetWidth(12)
  slider:SetOrientation("VERTICAL")
  slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  local track = slider:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  track:SetColorTexture(0, 0, 0, 0.35)
  slider:SetMinMaxValues(0, 0)
  slider:SetValueStep(1)
  slider:SetValue(0)
  slider:SetScript("OnValueChanged", function(_, value)
    local v = math.floor(value + 0.5)
    if v ~= list.offset then list.offset = v; list:Redraw() end
  end)
  list.slider = slider

  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(_, delta)
    local maxOff = math.max(0, #list.items - list.visible)
    local v = math.max(0, math.min(maxOff, list.offset - delta * 3))
    slider:SetValue(v)
  end)

  local empty = UI.Label(list, "", "GameFontDisable")
  empty:SetPoint("CENTER")
  list.empty = empty

  function list:Redraw()
    for i = 1, #self.rows do
      local row = self.rows[i]
      local item = (i <= self.visible) and self.items[i + self.offset] or nil
      row.item = item
      if item then
        for c = 1, #columns do
          row.cells[c]:SetText(item.cols[c] ~= nil and tostring(item.cols[c]) or "")
          if item.color then row.cells[c]:SetTextColor(unpack(item.color))
          else row.cells[c]:SetTextColor(1, 1, 1) end
        end
        row:Show()
      else
        row:Hide()
      end
    end
  end

  -- Fit the scroll range and the rows to the current item count and visible row count.
  function list:Update()
    local maxOff = math.max(0, #self.items - self.visible)
    if self.offset > maxOff then self.offset = maxOff end
    self.slider:SetMinMaxValues(0, maxOff)
    self.slider:SetValue(self.offset)
    if maxOff == 0 then self.slider:Hide() else self.slider:Show() end
    self:Redraw()
  end

  local function relayout(w, h)
    w, h = w or width, h or height
    innerW = math.max(60, w - 28)
    local ratio = innerW / baseInner
    header:SetWidth(innerW)
    local x = 0
    for c, col in ipairs(columns) do
      local cw = math.floor(col.width * ratio + 0.5)
      colX[c], colW[c] = x, cw
      local hb = list.headers[c]
      hb:ClearAllPoints()
      hb:SetPoint("LEFT", x, 0)
      hb:SetSize(math.max(6, cw - 2), 18)
      hb.label:SetWidth(math.max(6, cw - 4))
      x = x + cw
    end
    local vis = math.max(1, math.floor((h - 32) / rowHeight))
    for i = #list.rows + 1, vis do makeRow(i) end
    list.visible = vis
    for _, row in ipairs(list.rows) do placeRow(row) end
    list:Update()
  end
  list:SetScript("OnSizeChanged", function(_, w, h) relayout(w, h) end)

  -- Sort value for a cell: the item's own key for that column if it gave one, else the cell's
  -- text without colour codes, compared as a number when it is one.
  local function cellKey(item, c)
    if item.keys and item.keys[c] ~= nil then return item.keys[c] end
    local v = item.cols and item.cols[c]
    if type(v) == "number" then return v end
    v = tostring(v or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    local n = tonumber(v)
    if n then return n end
    return v:lower()
  end
  local function before(a, b, asc)
    local ta, tb = type(a), type(b)
    if ta ~= tb then
      if ta == "number" then return asc end -- numbers ahead of words
      return not asc
    end
    if asc then return a < b end
    return a > b
  end

  function list:SetItems(items, emptyText)
    self.rawItems, self.emptyText = items or {}, emptyText
    items = self.rawItems
    if self.sortCol then
      local c, asc = self.sortCol, self.sortAsc
      local order = {}
      for i, it in ipairs(items) do order[i] = { it = it, i = i, k = cellKey(it, c) } end
      table.sort(order, function(a, b)
        if a.k == b.k then return a.i < b.i end
        return before(a.k, b.k, asc)
      end)
      items = {}
      for i, o in ipairs(order) do items[i] = o.it end
    end
    for ci, hb in ipairs(self.headers) do
      local arrow = (self.sortCol == ci) and (self.sortAsc and " |TInterface\\Buttons\\Arrow-Up-Up:12:12|t" or " |TInterface\\Buttons\\Arrow-Down-Up:12:12|t") or ""
      hb.label:SetText(hb.title .. arrow)
    end
    self.items = items
    self.empty:SetText(#self.items == 0 and (emptyText or "Nothing here yet.") or "")
    self:Update()
  end

  relayout(width, height)
  return list
end

----------------------------------------------------------------------
-- Resizing: drag any edge or corner of `frame`. Call frame:SetResizable(true) yourself.
----------------------------------------------------------------------
function UI.AddSizeGrips(frame, onDone)
  local function grip(point, setup)
    local g = CreateFrame("Frame", nil, frame)
    g:SetFrameLevel((frame:GetFrameLevel() or 1) + 10)
    setup(g)
    g:EnableMouse(true)
    g:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" then frame:StartSizing(point) end end)
    g:SetScript("OnMouseUp", function() frame:StopMovingOrSizing(); if onDone then onDone() end end)
    return g
  end
  grip("LEFT", function(g) g:SetWidth(6); g:SetPoint("TOPLEFT", 0, -40); g:SetPoint("BOTTOMLEFT", 0, 16) end)
  grip("RIGHT", function(g) g:SetWidth(6); g:SetPoint("TOPRIGHT", 0, -40); g:SetPoint("BOTTOMRIGHT", 0, 16) end)
  grip("TOP", function(g) g:SetHeight(6); g:SetPoint("TOPLEFT", 16, 0); g:SetPoint("TOPRIGHT", -40, 0) end)
  grip("BOTTOM", function(g) g:SetHeight(6); g:SetPoint("BOTTOMLEFT", 16, 0); g:SetPoint("BOTTOMRIGHT", -16, 0) end)
  grip("TOPLEFT", function(g) g:SetSize(16, 16); g:SetPoint("TOPLEFT", 0, 0) end)
  grip("BOTTOMLEFT", function(g) g:SetSize(16, 16); g:SetPoint("BOTTOMLEFT", 0, 0) end)
  local corner = grip("BOTTOMRIGHT", function(g) g:SetSize(18, 18); g:SetPoint("BOTTOMRIGHT", -2, 2) end)
  corner:SetFrameLevel((frame:GetFrameLevel() or 1) + 12)
  local tex = corner:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints()
  tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  corner:SetScript("OnEnter", function() tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight") end)
  corner:SetScript("OnLeave", function() tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up") end)
end

function UI.SetSizeBounds(frame, minW, minH, maxW, maxH)
  if frame.SetResizeBounds then frame:SetResizeBounds(minW, minH, maxW, maxH)
  elseif frame.SetMinResize then
    frame:SetMinResize(minW, minH)
    if frame.SetMaxResize then frame:SetMaxResize(maxW, maxH) end
  end
end

----------------------------------------------------------------------
-- Form dialog. One shared modal window, rebuilt each time it opens.
-- spec = { title=, fields = { {key=, label=, type="text"|"multiline"|"choice"|"check"|"info", value=, options=, maxLen=, height=} },
--          onSave = function(values) return true end, saveText=, buttons = { {text=, onClick=function(values) end} } }
----------------------------------------------------------------------
local dialog
local fieldPool = {}

local function getDialog()
  if dialog then return dialog end
  dialog = CreateFrame("Frame", "IronforgedDialog", UIParent, "BackdropTemplate")
  dialog:SetSize(460, 300)
  dialog:SetPoint("CENTER", 0, 40)
  dialog:SetFrameStrata("DIALOG")
  dialog:SetToplevel(true)
  dialog:EnableMouse(true)
  dialog:SetMovable(true)
  dialog:RegisterForDrag("LeftButton")
  dialog:SetScript("OnDragStart", dialog.StartMoving)
  dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
  dialog:SetClampedToScreen(true)
  dialog:SetResizable(true)
  UI.AddSizeGrips(dialog)
  UI.Backdrop(dialog)
  dialog.title = UI.Label(dialog, "", "GameFontNormalLarge")
  UI.TitleFont(dialog.title, 18)
  dialog.title:SetPoint("TOPLEFT", 18, -16)
  dialog.title:SetPoint("TOPRIGHT", -36, -16)
  local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)
  dialog.body = CreateFrame("Frame", nil, dialog)
  dialog.body:SetPoint("TOPLEFT", 16, -42)
  dialog.body:SetPoint("BOTTOMRIGHT", -16, 44)
  dialog.buttons = {}
  tinsert(UISpecialFrames, "IronforgedDialog")
  dialog:Hide()
  return dialog
end

local function releaseFields()
  for _, w in ipairs(fieldPool) do
    w:Hide()
    w:ClearAllPoints()
  end
  wipe(fieldPool)
end

function UI.CloseForm()
  if dialog then dialog:Hide() end
end

function UI.OpenForm(spec)
  local d = getDialog()
  -- Each opening gets a number. A button only closes the window if no new form
  -- (such as an "Are you sure?" prompt) was opened by its click.
  d.gen = (d.gen or 0) + 1
  local gen = d.gen
  local function closeIfStill()
    if d.gen == gen then d:Hide() end
  end
  -- Fresh body each time; old widgets are hidden and dropped.
  if d.body then d.body:Hide() end
  d.body = CreateFrame("Frame", nil, d)
  d.body:SetPoint("TOPLEFT", 16, -42)
  d.body:SetPoint("BOTTOMRIGHT", -16, 44)
  releaseFields()
  for _, b in ipairs(d.buttons) do b:Hide() end
  wipe(d.buttons)

  d.title:SetText(spec.title or "")
  local body = d.body
  local width = spec.width or 460
  local labelW = 120
  local inputW = width - 32 - labelW - 8
  local y = 0
  local getters = {}
  local fields = spec.fields or {}
  -- Fields are placed after the buttons are counted (see below). The last multiline box, or
  -- failing that the last info text, takes any extra height; fields under it stay at the bottom.
  local stretchIdx
  for i, fld in ipairs(fields) do if fld.type == "multiline" then stretchIdx = i end end
  if not stretchIdx then
    for i, fld in ipairs(fields) do if fld.type == "info" then stretchIdx = i end end
  end
  local places, stretch = {}, nil
  local function put(frame, x, yy, i, right)
    frame:SetPoint("TOPLEFT", body, "TOPLEFT", x, -yy) -- provisional; measured text needs a point
    places[#places + 1] = { frame = frame, x = x, y = yy, i = i, right = right }
  end

  for i, f in ipairs(fields) do
    local h = 26
    if f.type == "info" then
      local fs = UI.Label(body, f.value or "", f.font or "GameFontHighlight")
      fs:SetWidth(width - 32)
      fs:SetJustifyV("TOP")
      fs:SetSpacing(2)
      put(fs, 0, y, i, true)
      h = math.max(16, fs:GetStringHeight() + 8)
      if i == stretchIdx then stretch = { frame = fs, bottom = y + h, shrink = math.max(0, h - 40), info = true } end
    else
      local label = UI.Label(body, f.label or "", "GameFontNormalSmall")
      label:SetWidth(labelW)
      put(label, 0, y + 4, i)
      if f.type == "multiline" then
        h = (f.height or 90) + 6
        local m = UI.MultiLine(body, inputW, f.height or 90, f.maxLen)
        put(m, labelW + 8, y, i, true)
        m:SetText(f.value or "")
        getters[f.key] = function() return m:GetText() end
        if i == stretchIdx then stretch = { frame = m, bottom = y + (f.height or 90), shrink = math.max(0, (f.height or 90) - 50) } end
      elseif f.type == "choice" then
        local current = f.value
        local btn = UI.Button(body, "", math.min(inputW, 220), 22)
        put(btn, labelW + 8, y, i)
        local function textFor(v)
          for _, o in ipairs(f.options or {}) do if o.value == v then return o.text end end
          return f.none or "(none)"
        end
        btn:SetText(textFor(current))
        btn:SetScript("OnClick", function(self)
          UI.Pick(self, f.options or {}, function(v, t)
            current = v; self:SetText(t)
            if f.onChange then f.onChange(v) end
          end, f.label)
        end)
        getters[f.key] = function() return current end
      elseif f.type == "check" then
        local c = UI.Check(body, f.checkText or "")
        put(c, labelW + 4, y - 2, i)
        c:SetChecked(f.value and true or false)
        getters[f.key] = function() return c:GetChecked() and true or false end
      else
        local e = UI.EditBox(body, inputW - 6, f.maxLen)
        put(e, labelW + 14, y, i, true)
        e:SetText(f.value or "")
        e:SetCursorPosition(0)
        if f.select then
          -- a copy box: keep the text as given and keep it selected
          local keep = f.value or ""
          e:SetScript("OnTextChanged", function(self, user) if user then self:SetText(keep); self:HighlightText() end end)
          e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
          e:SetScript("OnEnterPressed", function() d:Hide() end)
          e:SetFocus()
          e:HighlightText()
        end
        getters[f.key] = function() return e:GetText() end
      end
    end
    y = y + h + 4
  end

  local function values()
    local v = {}
    for k, g in pairs(getters) do v[k] = g() end
    return v
  end

  local bx, by, rows = -16, 14, 1
  local function addButton(text, fn)
    if -bx + 100 > width - 12 then
      bx, by, rows = -16, by + 26, rows + 1
    end
    local b = UI.Button(d, text, 100, 22, fn)
    b:SetPoint("BOTTOMRIGHT", bx, by)
    bx = bx - 104
    table.insert(d.buttons, b)
    return b
  end

  addButton(spec.onSave and "Cancel" or "Close", function() d:Hide() end)
  if spec.onSave then
    addButton(spec.saveText or "Save", function()
      if spec.onSave(values()) ~= false then closeIfStill() end
    end)
  end
  for _, extra in ipairs(spec.buttons or {}) do
    addButton(extra.text, function()
      if extra.onClick(values()) ~= false and not extra.keepOpen then closeIfStill() end
    end)
  end

  -- A protected action (like /gremove) needs Blizzard's secure button, which runs a
  -- slash command only when you click it. It can't be changed during combat.
  local inCombat = InCombatLockdown and InCombatLockdown()
  if d.secureBtn and not inCombat then d.secureBtn:Hide() end
  if spec.secure then
    if inCombat then
      ns.Print("Finish the fight first.")
    else
      if not d.secureBtn then
        local sb = CreateFrame("Button", "IronforgedSecureButton", d, "SecureActionButtonTemplate,BackdropTemplate")
        UI.StyleButton(sb)
        sb:SetSize(120, 22)
        sb:RegisterForClicks("AnyUp", "AnyDown")
        sb:SetAttribute("type", "macro")
        sb:SetScript("PostClick", function(self)
          if self.onDone then self.onDone() end
          d:Hide()
          if C_Timer then C_Timer.After(1, ns.RequestRoster) end
        end)
        d.secureBtn = sb
      end
      local sb = d.secureBtn
      if -bx + 120 > width - 12 then bx, by, rows = -16, by + 26, rows + 1 end
      sb:ClearAllPoints()
      sb:SetPoint("BOTTOMRIGHT", bx, by)
      sb:SetText(spec.secure.text)
      sb:SetAttribute("macrotext", spec.secure.macrotext)
      sb.onDone = spec.secure.onDone
      sb:Show()
    end
  end

  local dh = math.max(140, y + 100 + (rows - 1) * 26)
  local origBodyH = dh - 86
  local screenH = (UIParent and UIParent:GetHeight()) or 768
  local screenW = (UIParent and UIParent:GetWidth()) or 1024
  -- Text taller than the screen goes into a scroll frame instead of running off it.
  local cap = math.max(400, math.floor(screenH * 0.9))
  if dh > cap and stretch and stretch.info then
    local text = stretch.frame
    local scroll = CreateFrame("ScrollFrame", nil, body, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(width - 60, text:GetStringHeight() + 8)
    scroll:SetScrollChild(child)
    text:SetParent(child)
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    text:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, 0)
    local function fit()
      child:SetHeight(text:GetStringHeight() + 8)
    end
    scroll:SetScript("OnSizeChanged", function(_, sw)
      child:SetWidth(math.max(20, (sw or 100)))
      fit()
      if C_Timer then C_Timer.After(0, fit) end
    end)
    for _, p in ipairs(places) do if p.frame == text then p.frame = scroll end end
    stretch.frame = scroll
    stretch.scroll = true
    dh = cap
  end
  d:SetSize(width, dh)
  -- Anchor every field to the body so the window can be resized: fields stretch sideways, the
  -- stretch field also takes extra height and the fields below it stay pinned to the bottom.
  local bodyH = origBodyH -- distances to the bottom edge stay as laid out; only the stretch field shrinks
  for _, p in ipairs(places) do
    local fr = p.frame
    fr:ClearAllPoints()
    local below = stretchIdx and p.i > stretchIdx
    if below then
      fr:SetPoint("TOPLEFT", body, "BOTTOMLEFT", p.x, bodyH - p.y)
      if p.right then fr:SetPoint("TOPRIGHT", body, "BOTTOMRIGHT", 0, bodyH - p.y) end
    else
      fr:SetPoint("TOPLEFT", body, "TOPLEFT", p.x, -p.y)
      if p.right and not (stretch and stretch.frame == fr) then fr:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -p.y) end
    end
  end
  if stretch then stretch.frame:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", stretch.scroll and -24 or 0, bodyH - stretch.bottom) end
  UI.SetSizeBounds(d, math.max(300, math.floor(width * 0.7)), math.max(140, math.min(dh, cap) - (stretch and stretch.shrink or 0)),
    math.max(1400, screenW), math.max(1000, screenH))
  d:Show()
  d:Raise()
end

function UI.Confirm(text, onYes)
  UI.OpenForm({
    title = "Are you sure?",
    fields = { { type = "info", value = text } },
    onSave = function() onYes(); return true end,
    saveText = "Yes",
  })
end

function UI.RosterOptions(includeNone)
  local opts = {}
  if includeNone then opts[#opts + 1] = { text = "(none)", value = false } end
  for _, name in ipairs(ns.rosterList) do
    opts[#opts + 1] = { text = ns.ShortName(name), value = name }
  end
  return opts
end

----------------------------------------------------------------------
-- Small popup notice with buttons, used by Looking for Dwarf and craft requests.
-- spec = { id, icon, title, text, buttons = { { text, onClick } }, timeout }
-- One notice at a time; a new one replaces the old.
----------------------------------------------------------------------
local notice
local function buildNotice()
  if notice then return notice end
  notice = CreateFrame("Frame", "IronforgedNotice", UIParent, "BackdropTemplate")
  notice:SetSize(350, 140)
  notice:SetPoint("TOP", 0, -290)
  notice:SetFrameStrata("DIALOG")
  notice:EnableMouse(true)
  notice:SetMovable(true)
  notice:RegisterForDrag("LeftButton")
  notice:SetScript("OnDragStart", notice.StartMoving)
  notice:SetScript("OnDragStop", notice.StopMovingOrSizing)
  notice:SetClampedToScreen(true)
  UI.Backdrop(notice)
  notice.icon = notice:CreateTexture(nil, "ARTWORK")
  notice.icon:SetSize(36, 36)
  notice.icon:SetPoint("TOPLEFT", 16, -16)
  notice.title = UI.Label(notice, "", "GameFontNormalLarge")
  UI.TitleFont(notice.title, 19)
  notice.title:SetPoint("TOPLEFT", notice.icon, "TOPRIGHT", 10, -2)
  notice.text = UI.Label(notice, "", "GameFontHighlightSmall")
  notice.text:SetPoint("TOPLEFT", notice.title, "BOTTOMLEFT", 0, -4)
  notice.text:SetWidth(262)
  notice.text:SetWordWrap(true)
  notice.text:SetMaxLines(4)
  local close = CreateFrame("Button", nil, notice, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)
  notice.buttons = {}
  notice:Hide()
  return notice
end

function UI.Notice(spec)
  local n = buildNotice()
  n.id = spec.id
  n.icon:SetTexture(spec.icon or "Interface\\Icons\\INV_Misc_Note_01")
  n.title:SetText(spec.title or "")
  n.text:SetText(spec.text or "")
  for _, b in ipairs(n.buttons) do b:Hide() end
  local x = 18
  for i, bs in ipairs(spec.buttons or {}) do
    local b = n.buttons[i]
    if not b then
      b = UI.Button(n, "", 80, 24, function(self) if self.onClick then self.onClick() end; if not self.keepOpen then n:Hide() end end)
      n.buttons[i] = b
    end
    local w = math.max(70, #bs.text * 7 + 20)
    b:SetSize(w, 24)
    b:SetText(bs.text)
    b.onClick, b.keepOpen = bs.onClick, bs.keepOpen
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", x, 14)
    b:Show()
    x = x + w + 6
  end
  n:Show()
  n.shownAt = (n.shownAt or 0) + 1
  local at = n.shownAt
  if C_Timer then C_Timer.After(spec.timeout or 60, function() if n.shownAt == at then n:Hide() end end) end
  return n
end

function UI.HideNotice(id)
  if notice and notice:IsShown() and (not id or notice.id == id) then notice:Hide() end
end
