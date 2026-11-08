-- Compact Druid Bar - options panel (Esc > Options > AddOns > Compact Druid Bar, or /cdb)

local ADDON, ns = ...

function ns:BuildOptions()
  local TEX = ns.TEX
  local db = function() return ns.db end
  local panel = CreateFrame("Frame", "CompactDruidBarOptions")
  panel.name = "Compact Druid Bar"
  local refreshers = {}

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Compact Druid Bar")
  local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  sub:SetWidth(600)
  sub:SetJustifyH("LEFT")
  sub:SetText("Unlock to move. Drag moves the bar, Shift+drag detaches an element, right-click attaches it again, mouse wheel scales.")

  local function Header(x, y, text)
    local h = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h:SetPoint("TOPLEFT", x, y)
    h:SetText(text)
  end

  local function Checkbox(x, y, label, get, set)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetSize(24, 24)
    local t = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    t:SetText(label)
    cb:SetScript("OnClick", function(self)
      set(self:GetChecked() and true or false)
      ns:Refresh()
    end)
    refreshers[#refreshers + 1] = function() cb:SetChecked(get() and true or false) end
    return cb
  end

  local function Slider(x, y, label, min, max, step, key, fmt)
    local s = CreateFrame("Slider", nil, panel, "BackdropTemplate")
    s:SetPoint("TOPLEFT", x, y - 16)
    s:SetSize(220, 12)
    s:SetOrientation("HORIZONTAL")
    s:SetBackdrop({ bgFile = TEX, edgeFile = TEX, edgeSize = 1 })
    s:SetBackdropColor(0, 0, 0, 0.5)
    s:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    s:SetThumbTexture(TEX)
    local th = s:GetThumbTexture()
    th:SetSize(8, 16)
    th:SetVertexColor(1, 0.8, 0.1)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)
    local t = s:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    t:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 3)
    local function Label(v) t:SetText(label .. ": " .. string.format(fmt or "%d", v)) end
    s:SetScript("OnValueChanged", function(self, v)
      v = math.floor(v / step + 0.5) * step
      Label(v)
      if self.updating then return end
      db()[key] = v
      ns:Layout()
      ns:UpdateAll()
    end)
    s:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta * step) end)
    refreshers[#refreshers + 1] = function()
      s.updating = true
      s:SetValue(db()[key])
      Label(db()[key])
      s.updating = false
    end
  end

  -- Left column: size
  local x, y = 16, -70
  Header(x, y, "Size")
  y = y - 20
  local sliders = {
    { "Scale (bar)", 0.3, 3, 0.05, "scale", "%.2f" },
    { "Width", 80, 400, 5, "width" },
    { "Main bar height", 4, 40, 1, "barHeight" },
    { "Combo/mana bar height", 2, 30, 1, "smallBarHeight" },
    { "Icon size", 10, 60, 1, "iconSize" },
    { "Font size", 6, 20, 1, "fontSize" },
    { "Spacing", 0, 12, 1, "spacing" },
    { "Out of combat opacity", 0, 1, 0.05, "oocAlpha", "%.2f" },
  }
  for _, sl in ipairs(sliders) do
    Slider(x, y, sl[1], sl[2], sl[3], sl[4], sl[5], sl[6])
    y = y - 42
  end

  -- Right column: elements
  x, y = 300, -70
  Header(x, y, "Elements")
  local los = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  los:SetPoint("TOPLEFT", x + 190, y)
  los:SetText("Detach")
  y = y - 20
  for _, key in ipairs(ns.MODULE_ORDER) do
    Checkbox(x, y, ns.MODULE_LABELS[key],
      function() return db().modules[key].enabled end,
      function(v) db().modules[key].enabled = v end)
    Checkbox(x + 186, y, "",
      function() return db().modules[key].detached end,
      function(v)
        if v then ns:Detach(ns.modules[key]) else ns:Attach(ns.modules[key]) end
      end)
    y = y - 24
  end

  y = y - 10
  Header(x, y, "Display")
  y = y - 20
  Checkbox(x, y, "Text on bars", function() return db().showText end, function(v) db().showText = v end); y = y - 24
  Checkbox(x, y, "Energy-tick timer", function() return db().energyTick end, function(v) db().energyTick = v end); y = y - 24
  Checkbox(x, y, "Powershift marks on mana", function() return db().manaTicks end, function(v) db().manaTicks = v end); y = y - 24
  Checkbox(x, y, "Merge icons onto one line", function() return db().mergeIcons end, function(v) db().mergeIcons = v end); y = y - 24

  y = y - 10
  Header(x, y, "Clearcasting")
  y = y - 20
  Checkbox(x, y, "Highlight energy bar", function() return db().ccGlow end, function(v) db().ccGlow = v end); y = y - 24
  Checkbox(x, y, "Sound", function() return db().ccSound end, function(v) db().ccSound = v end); y = y - 24
  Checkbox(x, y, "Border flash", function() return db().ccFlash end, function(v) db().ccFlash = v end); y = y - 24

  -- Buttons
  local function Button(bx, by, w, text, onClick)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", bx, by)
    b:SetSize(w, 24)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
  end
  local by = -70 - 20 - 42 * #sliders - 10
  local lockBtn = Button(16, by, 140, "", function() ns:SetLocked(not db().locked) end)
  refreshers[#refreshers + 1] = function() lockBtn:SetText(db().locked and "Unlock" or "Lock") end
  Button(162, by, 120, "Test clearcast", function() ns:TestClearcast() end)
  Button(16, by - 30, 140, "Reset positions", function() ns:ResetPositions(); ns.RefreshOptions() end)
  Button(162, by - 30, 120, "Reset all", function() ns:ResetAll(); ns.RefreshOptions() end)

  function ns.RefreshOptions()
    for _, r in ipairs(refreshers) do r() end
  end
  panel:SetScript("OnShow", ns.RefreshOptions)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local cat = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(cat)
    ns.category = cat
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
  ns.optionsPanel = panel
end

function ns:OpenOptions()
  if self.category and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(self.category:GetID())
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
    InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
  end
end
