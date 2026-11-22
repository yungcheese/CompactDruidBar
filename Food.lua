-- Compact Druid Bar - click-to-eat on the food buff icon
-- Left-click the food icon to eat the food you picked; right-click to pick
-- which food (from your bags). Eating is a protected action, so this is a
-- secure button laid over the icon, only placed and changed out of combat
-- (you can't eat in combat anyway).

local ADDON, ns = ...

local F = {}
ns.food = F
local FOOD_CLASS, FOOD_SUBCLASS = 0, 5 -- Consumable > Food & Drink

local function Safe(fn, ...)
  if not fn then return end
  local ok, a, b, c, d, e, f, g = pcall(fn, ...)
  if ok then return a, b, c, d, e, f, g end
end

local function Picked() return ns.charData and ns.charData.foodItem end

local function ItemName(id)
  local n = C_Item and C_Item.GetItemNameByID and Safe(C_Item.GetItemNameByID, id)
  if not n and GetItemInfo then n = Safe(GetItemInfo, id) end
  return n
end
local function ItemCount(id)
  if C_Item and C_Item.GetItemCount then return Safe(C_Item.GetItemCount, id) or 0 end
  return GetItemCount and Safe(GetItemCount, id) or 0
end
local function ItemIcon(id)
  return C_Item and C_Item.GetItemIconByID and Safe(C_Item.GetItemIconByID, id)
end

-- Food & drink in your bags: list of { id, name, icon, count }, one row per item.
function F:BagFood()
  local list, seen = {}, {}
  if not (C_Container and C_Container.GetContainerNumSlots) then return list end
  for bag = 0, 4 do
    for slot = 1, (Safe(C_Container.GetContainerNumSlots, bag) or 0) do
      local info = Safe(C_Container.GetContainerItemInfo, bag, slot)
      local id = info and info.itemID
      if id and not seen[id] then
        local _, _, _, _, icon, classID, subClassID = Safe(C_Item.GetItemInfoInstant, id)
        if classID == FOOD_CLASS and subClassID == FOOD_SUBCLASS then
          seen[id] = true
          list[#list + 1] = { id = id, name = ItemName(id) or ("item " .. id), icon = icon or info.iconFileID, count = ItemCount(id) }
        end
      end
    end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

------------------------------------------------------------------------
-- Picker (right-click)
------------------------------------------------------------------------
local picker
local ROW_H = 20
local function BuildPicker()
  picker = CreateFrame("Frame", "CompactDruidBarFoodPicker", UIParent, "BackdropTemplate")
  picker:SetFrameStrata("DIALOG")
  picker:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  picker:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
  picker:SetBackdropBorderColor(0.85, 0.68, 0.25, 1)
  picker:EnableMouse(true)
  picker:SetClampedToScreen(true)
  picker.title = picker:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  picker.title:SetPoint("TOPLEFT", 10, -9)
  picker.title:SetText("Pick the food to eat")
  local close = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() picker:Hide() end)
  picker.rows = {}
  picker:Hide()
  tinsert(UISpecialFrames, "CompactDruidBarFoodPicker") -- Escape closes it
end

local function Row(i)
  local r = picker.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, picker)
  r:SetSize(220, ROW_H)
  r:SetPoint("TOPLEFT", 8, -28 - (i - 1) * ROW_H)
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.icon:SetPoint("LEFT", 2, 0)
  r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  r.text:SetPoint("RIGHT", -4, 0)
  r.text:SetJustifyH("LEFT")
  picker.rows[i] = r
  return r
end

function F:ShowPicker(anchor)
  if not picker then BuildPicker() end
  local list = self:BagFood()
  local rows = {}
  for _, f in ipairs(list) do rows[#rows + 1] = f end
  rows[#rows + 1] = { clear = true }
  for i, f in ipairs(rows) do
    local r = Row(i)
    if f.clear then
      r.icon:SetTexture(nil)
      r.text:SetText(#list == 0 and "|cff999999No food or drink in your bags.|r" or "|cff999999(none: don't eat on click)|r")
    else
      r.icon:SetTexture(f.icon)
      local mark = (f.id == Picked()) and " |cff40ff40(picked)|r" or ""
      r.text:SetText(("%s |cff999999x%d|r%s"):format(f.name, f.count or 0, mark))
    end
    r:SetScript("OnClick", function()
      if ns.charData then ns.charData.foodItem = (not f.clear) and f.id or nil end
      picker:Hide()
      F:Update()
    end)
    r:Show()
  end
  for i = #rows + 1, #picker.rows do picker.rows[i]:Hide() end
  picker:SetSize(236, 38 + #rows * ROW_H)
  picker:ClearAllPoints()
  picker:SetPoint("BOTTOMLEFT", anchor or UIParent, "TOPLEFT", 0, 6)
  picker:Show()
end

------------------------------------------------------------------------
-- Secure button over the food icon
------------------------------------------------------------------------
local button
local function ShowTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:AddLine("Food buff")
  local id = Picked()
  if id then
    local n, c = ItemName(id) or ("item " .. id), ItemCount(id)
    if c > 0 then
      GameTooltip:AddLine(("Left-click: eat %s (%d left)"):format(n, c), 1, 1, 1)
    else
      GameTooltip:AddLine(("%s: none left in your bags"):format(n), 1, 0.4, 0.4)
    end
  else
    GameTooltip:AddLine("Left-click: pick a food first", 1, 1, 1)
  end
  GameTooltip:AddLine("Right-click: pick which food to eat", 1, 1, 1)
  GameTooltip:Show()
end

local function GetButton()
  if button or InCombatLockdown() then return button end
  button = CreateFrame("Button", "CompactDruidBarFoodButton", UIParent, "SecureActionButtonTemplate")
  button:RegisterForClicks("AnyUp", "AnyDown")
  button:SetAttribute("type2", nil)
  -- Right-click (or left-click with nothing picked) opens the picker; that part isn't protected.
  button:HookScript("OnClick", function(self, mouse, down)
    if down then return end
    if mouse == "RightButton" or not Picked() then F:ShowPicker(self) end
  end)
  button:SetScript("OnEnter", ShowTooltip)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  button:Hide()
  return button
end

local function FoodIcon()
  local m = ns.modules and ns.modules.buffs
  if not (m and m.slots) then return end
  for i, slot in ipairs(m.slots) do
    local ic = m.icons[i]
    if slot.food and i <= m.count and ic and ic:IsVisible() then return ic end
  end
end

function F:Update()
  if InCombatLockdown() then return end
  local ic = ns.db and ns.db.foodClick and ns.db.locked and FoodIcon()
  if not ic then
    if button then button:Hide() end
    return
  end
  local b = GetButton()
  if not b then return end
  local id = Picked()
  if id and ItemCount(id) > 0 then
    b:SetAttribute("type1", "item")
    b:SetAttribute("item1", "item:" .. id)
  else
    b:SetAttribute("type1", nil)
    b:SetAttribute("item1", nil)
  end
  b:ClearAllPoints()
  b:SetAllPoints(ic)
  b:SetFrameStrata(ic:GetFrameStrata())
  b:SetFrameLevel(ic:GetFrameLevel() + 10)
  b:Show()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function() F:Update() end)
-- Follow the icon when the bar is rearranged (twice a second is plenty).
local acc = 0
ev:SetScript("OnUpdate", function(_, elapsed)
  acc = acc + elapsed
  if acc < 0.5 then return end
  acc = 0
  F:Update()
end)
