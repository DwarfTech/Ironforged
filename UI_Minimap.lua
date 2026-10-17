-- Ironforged: minimap button showing the guild's emblem, and the emblem helper.
local ADDON, ns = ...
local UI = ns.UI

UI.HAMMER_ICON = "Interface\\AddOns\\Ironforged\\Media\\Hammer64"
UI.HAMMER_ICON_LARGE = "Interface\\AddOns\\Ironforged\\Media\\Hammer128"

-- The Ironforged mark: a gold hammer on a red disc. `bg` is no longer used.
function UI.ApplyEmblem(icon, bg, large)
  icon:SetTexture(large and UI.HAMMER_ICON_LARGE or UI.HAMMER_ICON)
  icon:SetTexCoord(0, 1, 0, 1)
  icon:SetVertexColor(1, 1, 1)
  if bg then bg:Hide() end
  return true
end

local button

local function radius()
  local w = Minimap and Minimap:GetWidth() or 140
  return (w / 2) + 6
end

local function place()
  if not button then return end
  local angle = math.rad(ns.settings and ns.settings.minimapAngle or 210)
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius(), math.sin(angle) * radius())
end

local function create()
  if button or not Minimap then return end
  button = CreateFrame("Button", "IronforgedMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")

  local tint = button:CreateTexture(nil, "BORDER")
  tint:Hide()
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 7, -5)
  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  button.icon, button.tint = icon, tint

  button:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then ns.Lang.Toggle() else ns.ToggleMain() end
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Ironforged", 0.95, 0.78, 0.38)
    GameTooltip:AddLine("Click to open the hold.", 1, 1, 1)
    GameTooltip:AddLine("Right-click to turn Dwarvish " .. (ns.Lang.IsOn() and "off" or "on") .. ".", 1, 1, 1)
    GameTooltip:AddLine("Drag to move this button.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      cx, cy = cx / scale, cy / scale
      local angle = math.deg((math.atan2 or atan2)(cy - my, cx - mx))
      ns.settings.minimapAngle = angle
      place()
    end)
  end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
end

function UI.UpdateMinimapButton()
  if not ns.settings then return end
  create()
  if not button then return end
  if ns.settings.minimapHidden then button:Hide(); return end
  UI.ApplyEmblem(button.icon, button.tint)
  place()
  button:Show()
end

ns.RegisterEvent("PLAYER_LOGIN", function() UI.UpdateMinimapButton() end)
ns.RegisterEvent("PLAYER_GUILD_UPDATE", function() UI.UpdateMinimapButton() end)
ns.On("DATA_READY", function() UI.UpdateMinimapButton() end)
