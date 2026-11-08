-- Compact Druid Bar - options panel (Esc > Options > AddOns > Compact Druid Bar, or /cdb)
-- Two pages: General (layout, display, alerts) and Spells (custom + built-in spells).

local ADDON, ns = ...

local refreshers = {}
local function OnRefresh(fn) refreshers[#refreshers + 1] = fn end
function ns.RefreshOptions()
  for _, r in ipairs(refreshers) do r() end
end

------------------------------------------------------------------------
-- Widget helpers (no fragile templates; everything works on old + new clients)
------------------------------------------------------------------------
local function MakePage(name, height)
  local panel = CreateFrame("Frame")
  panel.name = name
  local content = panel
  local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  if ok and scroll then
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(660, height)
    scroll:SetScrollChild(content)
  end
  panel:SetScript("OnShow", ns.RefreshOptions)
  return panel, content
end

local function Text(parent, x, y, text, font)
  local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  return fs
end
local function Header(parent, x, y, text) return Text(parent, x, y, text, "GameFontNormal") end

local function Checkbox(parent, x, y, label, get, set)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", x, y)
  cb:SetSize(24, 24)
  cb.label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  cb.label:SetText(label)
  cb:SetScript("OnClick", function(self)
    set(self:GetChecked() and true or false)
    ns:Refresh()
  end)
  OnRefresh(function() cb:SetChecked(get() and true or false) end)
  return cb
end

local function Button(parent, x, y, w, text, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetPoint("TOPLEFT", x, y)
  b:SetSize(w, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function EditBox(parent, x, y, w)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetPoint("TOPLEFT", x + 6, y)
  e:SetSize(w, 20)
  e:SetAutoFocus(false)
  e:SetScript("OnEscapePressed", e.ClearFocus)
  return e
end

local function Slider(parent, x, y, label, min, max, step, key, fmt)
  local TEX = ns.TEX
  local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
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
    ns.db[key] = v
    ns:Layout()
    ns:UpdateAll()
  end)
  s:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta * step) end)
  OnRefresh(function()
    s.updating = true
    s:SetValue(ns.db[key])
    Label(ns.db[key])
    s.updating = false
  end)
end

-- Dropdown: a button that opens a scrollable list. With `preview`, every row
-- gets a "Play" button so sounds can be heard before choosing.
local function Dropdown(parent, x, y, w, getList, get, set, preview)
  local TEX = ns.TEX
  local ROWS, ROW_H = 12, 18

  local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
  btn:SetPoint("TOPLEFT", x, y)
  btn:SetSize(w, 22)
  btn:SetBackdrop({ bgFile = TEX, edgeFile = TEX, edgeSize = 1 })
  btn:SetBackdropColor(0, 0, 0, 0.6)
  btn:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
  btn.text = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  btn.text:SetPoint("LEFT", 6, 0)
  btn.text:SetPoint("RIGHT", -18, 0)
  btn.text:SetJustifyH("LEFT")
  local arrow = btn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  arrow:SetPoint("RIGHT", -6, 0)
  arrow:SetText("v")

  local list = CreateFrame("Frame", nil, btn, "BackdropTemplate")
  list:SetFrameStrata("FULLSCREEN_DIALOG")
  list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
  list:SetWidth(w)
  list:SetBackdrop({ bgFile = TEX, edgeFile = TEX, edgeSize = 1 })
  list:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
  list:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
  list:EnableMouse(true)
  list:EnableMouseWheel(true)
  list:Hide()
  local rows, offset = {}, 0

  local function Label()
    local cur = get()
    for _, item in ipairs(getList()) do
      if item[1] == cur then btn.text:SetText(item[2]) return end
    end
    btn.text:SetText("-")
  end

  local function Row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Button", nil, list)
    r:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H)
    r:SetSize(w - 4, ROW_H)
    r:SetHighlightTexture(TEX)
    r:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.12)
    r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 4, 0)
    r.text:SetPoint("RIGHT", preview and -38 or -4, 0)
    r.text:SetJustifyH("LEFT")
    r:SetScript("OnClick", function(self)
      set(self.item[1])
      list:Hide()
      Label()
    end)
    if preview then
      local p = CreateFrame("Button", nil, r)
      p:SetSize(34, ROW_H)
      p:SetPoint("RIGHT")
      p:SetHighlightTexture(TEX)
      p:GetHighlightTexture():SetVertexColor(1, 0.8, 0.1, 0.25)
      local pt = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
      pt:SetPoint("CENTER")
      pt:SetText("Play")
      p:SetScript("OnClick", function() preview(r.item[1]) end)
    end
    rows[i] = r
    return r
  end

  local function Fill()
    local items, cur = getList(), get()
    local n = math.min(ROWS, #items)
    list:SetHeight(n * ROW_H + 4)
    for i = 1, math.max(ROWS, #rows) do
      local item = items[i + offset]
      if i <= n and item then
        local r = Row(i)
        r.item = item
        r.text:SetText(item[2])
        if item[1] == cur then r.text:SetTextColor(1, 0.82, 0) else r.text:SetTextColor(1, 1, 1) end
        r:Show()
      elseif rows[i] then
        rows[i]:Hide()
      end
    end
  end

  list:SetScript("OnMouseWheel", function(_, delta)
    local items = getList()
    offset = math.max(0, math.min(#items - ROWS, offset - delta))
    Fill()
  end)
  btn:SetScript("OnClick", function()
    if list:IsShown() then list:Hide() return end
    -- Open with the selected item in view.
    local items, cur = getList(), get()
    offset = 0
    for i, item in ipairs(items) do
      if item[1] == cur then offset = math.max(0, math.min(#items - ROWS, i - 3)) break end
    end
    Fill()
    list:Show()
  end)
  btn:SetScript("OnHide", function() list:Hide() end)
  OnRefresh(Label)
  return x + w
end

------------------------------------------------------------------------
-- Page 1: General
------------------------------------------------------------------------
local function BuildGeneral()
  local panel, c = MakePage("Compact Druid Bar", 720)
  local db = function() return ns.db end

  Text(c, 16, -16, "Compact Druid Bar", "GameFontNormalLarge")
  local sub = Text(c, 16, -40, "Unlock to move. Drag moves the bar, Shift+drag detaches an element, right-click attaches it again, mouse wheel scales.")
  sub:SetWidth(620)

  -- Left column: size
  local x, y = 16, -70
  Header(c, x, y, "Size")
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
    Slider(c, x, y, sl[1], sl[2], sl[3], sl[4], sl[5], sl[6])
    y = y - 42
  end

  y = y - 6
  local lockBtn = Button(c, 16, y, 140, "", function() ns:SetLocked(not db().locked) end)
  OnRefresh(function() lockBtn:SetText(db().locked and "Unlock" or "Lock") end)
  Button(c, 162, y, 120, "Test clearcast", function() ns:TestClearcast() end)
  y = y - 28
  Button(c, 16, y, 140, "Reset positions", function() ns:ResetPositions(); ns.RefreshOptions() end)
  Button(c, 162, y, 120, "Reset all", function() ns:ResetAll(); ns.RefreshOptions() end)

  y = y - 40
  Header(c, x, y, "Extras")
  y = y - 20
  Checkbox(c, x, y, "Rip/Rake refresh warning (last 2 sec)", function() return db().bleedWarn end, function(v) db().bleedWarn = v end); y = y - 24
  Checkbox(c, x, y, "Mana potion + rune cooldowns", function() return db().consumables end, function(v) db().consumables = v end); y = y - 24
  Checkbox(c, x, y, "Glow at 5 combo points", function() return db().cpGlow end, function(v) db().cpGlow = v end); y = y - 24
  Checkbox(c, x, y, "GCD spark on power bar", function() return db().gcdSpark end, function(v) db().gcdSpark = v end); y = y - 24

  -- Right column: elements, display, clearcasting
  x, y = 320, -70
  Header(c, x, y, "Elements")
  Text(c, x + 190, y, "Detach", "GameFontNormalSmall")
  y = y - 20
  for _, key in ipairs(ns.MODULE_ORDER) do
    Checkbox(c, x, y, ns.MODULE_LABELS[key],
      function() return db().modules[key].enabled end,
      function(v) db().modules[key].enabled = v end)
    Checkbox(c, x + 186, y, "",
      function() return db().modules[key].detached end,
      function(v)
        if v then ns:Detach(ns.modules[key]) else ns:Attach(ns.modules[key]) end
      end)
    y = y - 24
  end

  y = y - 10
  Header(c, x, y, "Display")
  y = y - 20
  Checkbox(c, x, y, "Text on bars", function() return db().showText end, function(v) db().showText = v end); y = y - 24
  Checkbox(c, x, y, "Energy tick timer", function() return db().energyTick end, function(v) db().energyTick = v end); y = y - 24
  Checkbox(c, x, y, "Powershift marks on mana", function() return db().manaTicks end, function(v) db().manaTicks = v end); y = y - 24
  Checkbox(c, x, y, "Merge icons onto one line", function() return db().mergeIcons end, function(v) db().mergeIcons = v end); y = y - 24
  Checkbox(c, x, y, "Show minimap button", function() return not db().minimap.hide end,
    function(v) db().minimap.hide = not v; ns:UpdateMinimap() end); y = y - 24

  y = y - 10
  Header(c, x, y, "Clearcasting")
  y = y - 20
  Checkbox(c, x, y, "Highlight energy bar", function() return db().ccGlow end, function(v) db().ccGlow = v end); y = y - 24
  Checkbox(c, x, y, "Border flash", function() return db().ccFlash end, function(v) db().ccFlash = v end); y = y - 24
  Checkbox(c, x, y, "Sound", function() return db().ccSound end, function(v) db().ccSound = v end); y = y - 28

  -- Sound picker
  local afterX = Dropdown(c, x, y, 200, ns.GetSoundChoices,
    function() return db().ccSoundKey end,
    function(v) db().ccSoundKey = v; ns.RefreshOptions() end,
    function(key) ns:PlayAlertSound(key) end)
  Button(c, afterX + 6, y, 50, "Play", function() ns:PlayAlertSound() end)
  y = y - 28

  local customLabel = Text(c, x, y - 4, "Sound ID:")
  local custom = EditBox(c, x + 60, y, 90)
  custom:SetNumeric(true)
  custom:SetScript("OnTextChanged", function(self) db().ccSoundCustom = self:GetText() end)
  custom:SetScript("OnEnterPressed", function(self) self:ClearFocus(); ns:PlayAlertSound() end)
  local hint = Text(c, x + 166, y - 4, "SoundKit or FileDataID (wago.tools/sounds)")
  hint:SetTextColor(0.6, 0.6, 0.6)
  OnRefresh(function()
    local show = db().ccSoundKey == "custom"
    customLabel:SetShown(show); custom:SetShown(show); hint:SetShown(show)
    if not custom:HasFocus() then custom:SetText(db().ccSoundCustom or "") end
  end)
  y = y - 28

  Text(c, x, y - 4, "Channel:")
  Dropdown(c, x + 60, y, 120,
    function() return { { "Master", "Master" }, { "SFX", "Effects" }, { "Ambience", "Ambience" }, { "Dialog", "Dialog" } } end,
    function() return db().ccSoundChannel end,
    function(v) db().ccSoundChannel = v end)

  return panel
end

------------------------------------------------------------------------
-- Page 2: Spells
------------------------------------------------------------------------
local KINDS = { { "cd", "Cooldown" }, { "buff", "Buff on me" }, { "debuff", "Debuff on target" } }

local function BuildSpells()
  local panel, c = MakePage("Spells", 760)
  local db = function() return ns.db end
  local state = { kind = "cd", forms = { cat = true, bear = false, caster = false } }

  Text(c, 16, -16, "Spells", "GameFontNormalLarge")
  local sub = Text(c, 16, -40, "Add your own cooldowns, buffs or debuffs to the bar, or hide built-in ones. Spell names work for spells in your spellbook; use the spell ID for anything else (e.g. trinket buffs).")
  sub:SetWidth(620)

  -- Add form
  local x, y = 16, -84
  Header(c, x, y, "Add a spell")
  y = y - 22
  local input = EditBox(c, x, y, 180)
  Dropdown(c, x + 196, y, 140, function() return KINDS end,
    function() return state.kind end, function(v) state.kind = v end)
  y = y - 26
  local formBoxes = {}
  for i, f in ipairs({ { "cat", "Cat" }, { "bear", "Bear" }, { "caster", "Caster" } }) do
    local cb = CreateFrame("CheckButton", nil, c, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x + (i - 1) * 80, y)
    cb:SetSize(24, 24)
    local t = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    t:SetText(f[2])
    cb:SetChecked(state.forms[f[1]])
    cb:SetScript("OnClick", function(self) state.forms[f[1]] = self:GetChecked() and true or false end)
    formBoxes[f[1]] = cb
  end
  local status = Text(c, x, y - 52, "")
  status:SetWidth(330)
  local function Add()
    local ok, msg = ns:AddCustom(input:GetText(), state.kind, state.forms)
    status:SetText(msg)
    if ok then status:SetTextColor(0.4, 1, 0.4); input:SetText("") else status:SetTextColor(1, 0.4, 0.4) end
    ns.RefreshOptions()
  end
  Button(c, x + 244, y, 80, "Add", Add)
  input:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Add() end)

  -- Custom list
  y = y - 90
  Header(c, x, y, "Your spells")
  local empty = Text(c, x, y - 22, "None yet.")
  empty:SetTextColor(0.6, 0.6, 0.6)
  local rows = {}
  local listY = y - 22
  local function Row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, c)
    r:SetSize(340, 22)
    r:SetPoint("TOPLEFT", x, listY - (i - 1) * 24)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT")
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetWidth(280)
    r.text:SetJustifyH("LEFT")
    r.del = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.del:SetSize(24, 20)
    r.del:SetPoint("RIGHT")
    r.del:SetText("X")
    rows[i] = r
    return r
  end
  OnRefresh(function()
    local list = db().custom
    empty:SetShown(#list == 0)
    for i, sp in ipairs(list) do
      local r = Row(i)
      local forms = {}
      if sp.forms.cat then forms[#forms + 1] = "Cat" end
      if sp.forms.bear then forms[#forms + 1] = "Bear" end
      if sp.forms.caster then forms[#forms + 1] = "Caster" end
      r.icon:SetTexture((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sp.id)) or 134400)
      r.text:SetText(("%s |cff888888(%d)|r - %s - %s"):format(sp.name or "?", sp.id, ns.KIND_LABELS[sp.kind] or sp.kind, table.concat(forms, ", ")))
      r.del:SetScript("OnClick", function() ns:RemoveCustom(i); ns.RefreshOptions() end)
      r:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
  end)

  -- Built-in spells (right column)
  x, y = 380, -84
  Header(c, x, y, "Built-in spells")
  y = y - 20
  for _, group in ipairs(ns.BUILTIN) do
    local h = Text(c, x, y - 4, group.cat, "GameFontNormalSmall")
    h:SetTextColor(0.8, 0.8, 0.8)
    y = y - 20
    for _, key in ipairs(group.keys) do
      local cb = Checkbox(c, x, y, key,
        function() return not db().hidden[key] end,
        function(v) db().hidden[key] = (not v) or nil end)
      OnRefresh(function() cb.label:SetText(ns.KeyName(key)) end)
      y = y - 22
    end
    y = y - 4
  end

  return panel
end

------------------------------------------------------------------------
-- Registration
------------------------------------------------------------------------
function ns:BuildOptions()
  local general = BuildGeneral()
  local spells = BuildSpells()
  if Settings and Settings.RegisterCanvasLayoutCategory then
    local cat = Settings.RegisterCanvasLayoutCategory(general, general.name)
    Settings.RegisterAddOnCategory(cat)
    ns.category = cat
    if Settings.RegisterCanvasLayoutSubcategory then
      local ok, sub = pcall(Settings.RegisterCanvasLayoutSubcategory, cat, spells, spells.name)
      if ok then ns.spellsCategory = sub end
    end
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(general)
    spells.parent = general.name
    InterfaceOptions_AddCategory(spells)
  end
  ns.optionsPanel, ns.spellsPanel = general, spells
end

function ns:OpenOptions(page)
  local cat = (page == "spells" and self.spellsCategory) or self.category
  if cat and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(cat:GetID())
  elseif InterfaceOptionsFrame_OpenToCategory then
    local p = (page == "spells") and self.spellsPanel or self.optionsPanel
    InterfaceOptionsFrame_OpenToCategory(p)
    InterfaceOptionsFrame_OpenToCategory(p)
  end
end
