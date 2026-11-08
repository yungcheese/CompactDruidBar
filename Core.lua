-- Compact Druid Bar - core
-- Built for the WoW Forever client (1.60.1, interface 16001).
-- Forever uses the Midnight addon restrictions: some values can be "secret".
-- Everything that does math or comparisons is guarded with readable()/pcall,
-- so the addon falls back gracefully instead of throwing errors.

local ADDON, ns = ...
_G.CompactDruidBar = ns

local TEX = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
ns.TEX = TEX

local issecret = issecretvalue or function() return false end
local function readable(...)
  for i = 1, select("#", ...) do
    if issecret((select(i, ...))) then return false end
  end
  return true
end
ns.readable = readable

------------------------------------------------------------------------
-- Defaults
------------------------------------------------------------------------
ns.MODULE_ORDER = { "health", "power", "combo", "mana", "debuffs", "cooldowns", "buffs", "clearcast" }
ns.MODULE_LABELS = {
  health = "Health",
  power = "Energy / Rage / Mana",
  combo = "Combo points",
  mana = "Mana + powershifts",
  debuffs = "Target debuffs",
  cooldowns = "Cooldowns",
  buffs = "Buffs",
  clearcast = "Clearcasting icon",
}

local DEFAULTS = {
  locked = true,
  scale = 1, width = 170, barHeight = 14, smallBarHeight = 8, iconSize = 22,
  fontSize = 10, spacing = 2, oocAlpha = 0.4,
  showText = true, energyTick = true, manaTicks = true, mergeIcons = true,
  ccGlow = true, ccSound = true, ccFlash = true,
  point = { "CENTER", "UIParent", "CENTER", 0, -160 },
  modules = {},
}
for _, k in ipairs(ns.MODULE_ORDER) do
  DEFAULTS.modules[k] = { enabled = true, detached = false, scale = 1 }
end
ns.DEFAULTS = DEFAULTS

local function CopyDefaults(src, dst)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      CopyDefaults(v, dst[k])
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end
ns.CopyDefaults = CopyDefaults

------------------------------------------------------------------------
-- Spell data (Classic spell IDs, all ranks)
------------------------------------------------------------------------
local S = {
  rip       = { 1079, 9492, 9493, 9752, 9894, 9896 },
  rake      = { 1822, 1823, 1824, 9904 },
  pounce    = { 9007, 9824, 9826 },          -- Pounce Bleed debuff
  ffFeral   = { 16857, 17390, 17391, 17392 },
  ff        = { 770, 778, 9749, 9907 },
  demo      = { 99, 1735, 9490, 9747, 9898 },
  moonfire  = { 8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835 },
  swarm     = { 5570, 24974, 24975, 24976, 24977 },
  motw      = { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 21849, 21850 },
  thorns    = { 467, 782, 1075, 8914, 9756, 9910 },
  omen      = { 16864 },
  tigers    = { 5217, 6793, 9845, 9846 },
  dash      = { 1850, 9821 },
  grasp     = { 16689, 16810, 16811, 16812, 16813, 17329 },
  barkskin  = { 22812 },
  innervate = { 29166 },
  rebirth   = { 20484, 20739, 20742, 20747, 20748 },
  bash      = { 5211, 6798, 8983 },
  charge    = { 16979 },
  enrage    = { 5229 },
  frenzied  = { 22842, 22895, 22896 },
  swiftmend = { 18562 },
  nswift    = { 17116 },
  hurricane = { 16914, 17401, 17402 },
  claw      = { 1082, 3029, 5201, 9849, 9850 },
  maul      = { 6807, 6808, 6809, 8972, 9745, 9880, 9881 },
  ht        = { 5185, 5186, 5187, 5188, 5189, 6778, 8903, 9758, 9888, 9889, 25297 },
}
local CLEARCASTING_ID = 16870
local CAT_FORM, BEAR_FORM, DIRE_BEAR_FORM = 768, 5487, 9634

local SPELL_TO_KEY = {}
for key, ids in pairs(S) do
  for _, id in ipairs(ids) do SPELL_TO_KEY[id] = SPELL_TO_KEY[id] or key end
end

-- Per form: which slots are shown. A slot is a list of keys
-- (e.g. regular + feral Faerie Fire share one slot).
local DEBUFF_SLOTS = {
  cat    = { { "rip" }, { "rake" }, { "pounce" }, { "ffFeral", "ff" } },
  bear   = { { "demo" }, { "ffFeral", "ff" } },
  caster = { { "moonfire" }, { "swarm" }, { "ff", "ffFeral" } },
}
local COOLDOWNS = {
  cat    = { "ffFeral", "dash", "grasp", "barkskin", "innervate" },
  bear   = { "charge", "bash", "enrage", "frenzied", "ffFeral", "barkskin" },
  caster = { "grasp", "barkskin", "innervate", "rebirth", "swiftmend", "nswift", "hurricane" },
}
-- reminder = red/grey when missing; otherwise only highlighted while active
local BUFFS = {
  { key = "motw", reminder = true },
  { key = "thorns", reminder = true },
  { key = "tigers", needsKnown = true, forms = { cat = true } },
  { key = "grasp", needsKnown = true },
}

local function IsKnown(id)
  return (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) or false
end
local function KnownID(key)
  local ids = S[key]
  if not ids then return end
  for i = #ids, 1, -1 do
    if IsKnown(ids[i]) then return ids[i] end
  end
end
local function SpellIcon(id)
  if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
  if GetSpellTexture then return GetSpellTexture(id) end
end
local function PowerCost(id)
  if not id then return end
  local ok, costs = pcall(function()
    if C_Spell and C_Spell.GetSpellPowerCost then return C_Spell.GetSpellPowerCost(id) end
    if GetSpellPowerCost then return GetSpellPowerCost(id) end
  end)
  if not ok or type(costs) ~= "table" or not costs[1] then return end
  return costs[1].cost
end
local function GetCooldown(id)
  if C_Spell and C_Spell.GetSpellCooldown then
    local info = C_Spell.GetSpellCooldown(id)
    if info then return info.startTime, info.duration end
  elseif GetSpellCooldown then
    local s, d = GetSpellCooldown(id)
    return s, d
  end
end

local function FormGroup()
  local id = GetShapeshiftFormID and GetShapeshiftFormID()
  if id == 1 then return "cat" end
  if id == 5 or id == 8 then return "bear" end
  return "caster"
end

------------------------------------------------------------------------
-- Widget helpers
------------------------------------------------------------------------
ns.fontStrings = {}
local function NewFS(parent, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(FONT, 10, "OUTLINE")
  fs:SetJustifyH(justify or "CENTER")
  ns.fontStrings[#ns.fontStrings + 1] = fs
  return fs
end

local function Short(v)
  if readable(v) and type(v) == "number" and AbbreviateLargeNumbers and v >= 10000 then
    return AbbreviateLargeNumbers(v)
  end
  return v
end

local function SafeText(fs, fmt, ...)
  if not ns.db.showText then fs:SetText("") return end
  if not pcall(fs.SetFormattedText, fs, fmt, ...) then fs:SetText("") end
end

local function Pct(cur, max)
  if readable(cur, max) and type(max) == "number" and max > 0 then
    return math.floor(cur / max * 100 + 0.5)
  end
end

local function CreateBar(parent)
  local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  holder:SetBackdrop({ bgFile = TEX, edgeFile = TEX, edgeSize = 1 })
  holder:SetBackdropColor(0, 0, 0, 0.55)
  holder:SetBackdropBorderColor(0, 0, 0, 1)
  local bar = CreateFrame("StatusBar", nil, holder)
  bar:SetPoint("TOPLEFT", 1, -1)
  bar:SetPoint("BOTTOMRIGHT", -1, 1)
  bar:SetStatusBarTexture(TEX)
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)
  holder.bar = bar
  holder.textL = NewFS(bar, "LEFT");   holder.textL:SetPoint("LEFT", 3, 0)
  holder.textC = NewFS(bar, "CENTER"); holder.textC:SetPoint("CENTER", 0, 0)
  holder.textR = NewFS(bar, "RIGHT");  holder.textR:SetPoint("RIGHT", -3, 0)
  return holder
end

local function SetBar(holder, cur, max)
  pcall(holder.bar.SetMinMaxValues, holder.bar, 0, max)
  pcall(holder.bar.SetValue, holder.bar, cur)
end

local function CreateIcon(parent)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetBackdrop({ edgeFile = TEX, edgeSize = 1 })
  f:SetBackdropBorderColor(0, 0, 0, 1)
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetPoint("TOPLEFT", 1, -1)
  f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
  f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
  f.cd:SetAllPoints(f.tex)
  f.cd:SetDrawEdge(false)
  if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(false) end
  return f
end

local function StyleCooldownText(icon)
  local size = math.max(8, math.floor(ns.db.iconSize * 0.42))
  for _, r in ipairs({ icon.cd:GetRegions() }) do
    if r and r.GetObjectType and r:GetObjectType() == "FontString" then
      r:SetFont(FONT, size, "OUTLINE")
    end
  end
end

local function SetIconState(icon, active, missingRed)
  icon.tex:SetDesaturated(not active)
  icon.tex:SetAlpha(active and 1 or (missingRed and 0.9 or 0.3))
  if missingRed and not active then
    icon:SetBackdropBorderColor(0.9, 0.1, 0.1, 1)
    icon.tex:SetVertexColor(1, 0.45, 0.45)
  else
    icon:SetBackdropBorderColor(0, 0, 0, 1)
    icon.tex:SetVertexColor(1, 1, 1)
  end
end

local function SetAuraTimer(icon, unit, aura)
  icon.cd:SetReverse(true)
  if C_UnitAuras and C_UnitAuras.GetAuraDuration and icon.cd.SetCooldownFromDurationObject then
    local ok, d = pcall(C_UnitAuras.GetAuraDuration, unit, aura.auraInstanceID)
    if ok and d and pcall(icon.cd.SetCooldownFromDurationObject, icon.cd, d) then
      StyleCooldownText(icon)
      return
    end
  end
  local ok = pcall(function()
    if aura.duration and aura.duration > 0 then
      icon.cd:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
    else
      icon.cd:Clear()
    end
  end)
  if not ok then icon.cd:Clear() end
  StyleCooldownText(icon)
end

local function ScanAuras(unit, filter)
  local list = {}
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return list end
  for i = 1, 40 do
    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
    if not ok or not a then break end
    list[#list + 1] = a
  end
  return list
end

------------------------------------------------------------------------
-- Modules
------------------------------------------------------------------------
ns.modules = {}
local root = CreateFrame("Frame", "CompactDruidBarRoot", UIParent)
root:SetMovable(true)
root:SetClampedToScreen(true)
root:SetSize(170, 40)
ns.root = root

local function NewModule(key)
  local f = CreateFrame("Frame", "CompactDruidBar_" .. key, UIParent)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:SetSize(100, 10)
  local m = { key = key, frame = f }
  function m:IsActive() return true end
  function m:Update() end
  ns.modules[key] = m
  return m
end

-- Health ------------------------------------------------------------
do
  local m = NewModule("health")
  m.bar = CreateBar(m.frame)
  m.bar:SetAllPoints()
  m.bar.bar:SetStatusBarColor(0.22, 0.72, 0.28)
  function m:Resize(w) self.frame:SetSize(w, ns.db.barHeight) end
  function m:Update()
    local cur, max = UnitHealth("player"), UnitHealthMax("player")
    SetBar(self.bar, cur, max)
    local pct = Pct(cur, max)
    if pct then
      SafeText(self.bar.textC, "%s / %s (%d%%)", Short(cur), Short(max), pct)
    else
      -- Secret: let the game compute the percentage (Midnight API).
      local ok = ns.db.showText and UnitHealthPercent and pcall(function()
        local p = UnitHealthPercent("player", false, CurveConstants and CurveConstants.ScaleTo100)
        self.bar.textC:SetFormattedText("%s / %s (%.0f%%)", cur, max, p)
      end)
      if not ok then SafeText(self.bar.textC, "%s / %s", cur, max) end
    end
  end
end

-- Power (energy / rage / mana) + energy tick + clearcast glow -------
do
  local POWER_COLORS = { [0] = { 0.18, 0.45, 1 }, [1] = { 0.85, 0.15, 0.15 }, [3] = { 1, 0.82, 0.1 } }
  local CC_COLOR = { 0.45, 0.92, 1 }
  local m = NewModule("power")
  m.bar = CreateBar(m.frame)
  m.bar:SetAllPoints()
  m.glow = m.frame:CreateTexture(nil, "BACKGROUND")
  m.glow:SetPoint("TOPLEFT", -3, 3)
  m.glow:SetPoint("BOTTOMRIGHT", 3, -3)
  m.glow:SetColorTexture(CC_COLOR[1], CC_COLOR[2], CC_COLOR[3], 0.7)
  m.glow:Hide()
  m.spark = m.bar.bar:CreateTexture(nil, "OVERLAY", nil, 7)
  m.spark:SetColorTexture(1, 1, 1, 0.95)
  m.spark:SetWidth(2)
  m.spark:Hide()
  m.lastTick, m.lastPower = 0, nil

  function m:Resize(w) self.frame:SetSize(w, ns.db.barHeight) end
  function m:Update()
    local pt = UnitPowerType("player")
    local cur, max = UnitPower("player", pt), UnitPowerMax("player", pt)
    SetBar(self.bar, cur, max)
    local cc = ns.clearcasting and ns.db.ccGlow
    local c = cc and CC_COLOR or POWER_COLORS[pt] or { 0.7, 0.7, 0.7 }
    self.bar.bar:SetStatusBarColor(c[1], c[2], c[3])
    self.glow:SetShown(cc and true or false)
    if pt == 0 and readable(cur, max) then
      SafeText(self.bar.textC, "%s / %s", Short(cur), Short(max))
    else
      SafeText(self.bar.textC, "%s", cur)
    end
    self.bar.textL:SetText("")
    self.bar.textR:SetText("")
  end

  -- Detect energy ticks: a gain of ~20 energy = tick (Furor = 40, ignored).
  -- If energy is secret we use the rhythm instead: ticks always land on the
  -- same point of a 2 sec cycle, regular casts land at random points.
  -- We keep a histogram of "time mod 2"; its peak is the tick moment.
  m.bins = {}
  for i = 1, 20 do m.bins[i] = 0 end
  function m:OnPowerSecret()
    local now = GetTime()
    local b = math.floor((now % 2) * 10) % 20 + 1
    local peak, peakV = 1, -1
    for i = 1, 20 do
      self.bins[i] = self.bins[i] * 0.93
      if self.bins[i] > peakV then peak, peakV = i, self.bins[i] end
    end
    self.bins[b] = self.bins[b] + 1
    local dist = math.abs(b - peak)
    if dist > 10 then dist = 20 - dist end
    if peakV >= 1.5 and dist <= 1 then self.lastTick = now end
  end
  function m:OnPower()
    if UnitPowerType("player") ~= 3 then self.lastPower = nil return end
    local e, max = UnitPower("player", 3), UnitPowerMax("player", 3)
    if not readable(e, max) then self:OnPowerSecret() return end
    if self.lastPower and e > self.lastPower then
      local d = e - self.lastPower
      if (d >= 18 and d <= 22) or (e == max and d < 20) then
        self.lastTick = GetTime()
      end
    end
    self.lastPower = e
  end

  m.frame:SetScript("OnUpdate", function()
    if ns.db and ns.db.energyTick and m.lastTick > 0 and UnitPowerType("player") == 3 then
      local w = m.bar.bar:GetWidth()
      local x = w * (((GetTime() - m.lastTick) % 2) / 2)
      m.spark:ClearAllPoints()
      m.spark:SetPoint("TOP", m.bar.bar, "TOPLEFT", x, 0)
      m.spark:SetPoint("BOTTOM", m.bar.bar, "BOTTOMLEFT", x, 0)
      m.spark:Show()
    else
      m.spark:Hide()
    end
  end)
end

-- Combo points ------------------------------------------------------
do
  local m = NewModule("combo")
  m.segs = {}
  for i = 1, 5 do
    local s = CreateFrame("Frame", nil, m.frame, "BackdropTemplate")
    s:SetBackdrop({ bgFile = TEX, edgeFile = TEX, edgeSize = 1 })
    s:SetBackdropColor(0, 0, 0, 0.55)
    s:SetBackdropBorderColor(0, 0, 0, 1)
    s.fill = s:CreateTexture(nil, "ARTWORK")
    s.fill:SetPoint("TOPLEFT", 1, -1)
    s.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    s.fill:SetColorTexture(1, 0.75, 0.1)
    m.segs[i] = s
  end
  function m:Resize(w)
    local h, gap = ns.db.smallBarHeight, 2
    self.frame:SetSize(w, h)
    local segW = (w - gap * 4) / 5
    for i, s in ipairs(self.segs) do
      s:ClearAllPoints()
      s:SetSize(segW, h)
      s:SetPoint("LEFT", self.frame, "LEFT", (i - 1) * (segW + gap), 0)
    end
  end
  function m:IsActive() return ns.form == "cat" end
  local function GetCP()
    local cp = UnitPower("player", (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4)
    if readable(cp) and (not cp or cp == 0) and GetComboPoints then
      cp = GetComboPoints("player", "target")
    end
    return cp or 0
  end
  function m:Update()
    local cp = GetCP()
    for i, s in ipairs(self.segs) do
      local ok, on = pcall(function() return cp >= i end)
      s.fill:SetShown(ok and on)
      local ok5, full = pcall(function() return cp >= 5 end)
      if ok5 and full then s.fill:SetColorTexture(1, 0.3, 0.15) else s.fill:SetColorTexture(1, 0.75, 0.1) end
    end
  end
end

-- Mana + powershifts -----------------------------------------------
do
  local m = NewModule("mana")
  m.bar = CreateBar(m.frame)
  m.bar:SetAllPoints()
  m.bar.bar:SetStatusBarColor(0.18, 0.45, 1)
  m.ticks = {}
  function m:Resize(w) self.frame:SetSize(w, ns.db.smallBarHeight); self.tickKey = nil end
  function m:IsActive()
    if UnitPowerType("player") == 0 then return false end
    local max = UnitPowerMax("player", 0)
    return not readable(max) or (max or 0) > 0
  end
  local function ShiftCost()
    local id = CAT_FORM
    if ns.form == "bear" then id = IsKnown(DIRE_BEAR_FORM) and DIRE_BEAR_FORM or BEAR_FORM end
    return PowerCost(id)
  end
  function m:PlaceTicks(cost, max)
    local key = ns.db.manaTicks and (cost .. ":" .. max .. ":" .. math.floor(self.bar.bar:GetWidth())) or "off"
    if key == self.tickKey then return end
    self.tickKey = key
    local n = 0
    if ns.db.manaTicks and cost > 0 and max > 0 then n = math.min(math.floor(max / cost), 30) end
    local w = self.bar.bar:GetWidth()
    for i = 1, math.max(n, #self.ticks) do
      local t = self.ticks[i]
      if i <= n then
        if not t then
          t = self.bar.bar:CreateTexture(nil, "OVERLAY", nil, 6)
          t:SetColorTexture(0, 0, 0, 0.85)
          t:SetWidth(1)
          self.ticks[i] = t
        end
        local x = w * (i * cost / max)
        t:ClearAllPoints()
        t:SetPoint("TOP", self.bar.bar, "TOPLEFT", x, 0)
        t:SetPoint("BOTTOM", self.bar.bar, "BOTTOMLEFT", x, 0)
        t:Show()
      elseif t then
        t:Hide()
      end
    end
  end
  function m:Update()
    local cur, max = UnitPower("player", 0), UnitPowerMax("player", 0)
    SetBar(self.bar, cur, max)
    local cost = ShiftCost()
    local costOK = readable(max, cost) and type(cost) == "number" and cost > 0 and type(max) == "number" and max > 0
    -- Tick marks only need max + cost, so they work even when current mana is secret.
    self:PlaceTicks(costOK and cost or 0, costOK and max or 0)
    if costOK and readable(cur) then
      self:HideShift()
      local n = math.floor(cur / cost)
      SafeText(self.bar.textC, "x%d   %d%%", n, Pct(cur, max) or 0)
      if n == 0 then self.bar.textC:SetTextColor(1, 0.3, 0.3) else self.bar.textC:SetTextColor(1, 1, 1) end
    elseif costOK and ns.db.showText and not self.shiftBroken and self.CurvesSupported() and self:BuildShift(cost, max) then
      -- Mana is secret: the game itself decides via curves which "xN" label is visible.
      self.bar.textC:SetText("")
      if not pcall(self.UpdateShiftAlpha, self) then
        self.shiftBroken = true
        self:HideShift()
      end
    else
      self:HideShift()
      self.bar.textC:SetTextColor(1, 1, 1)
      SafeText(self.bar.textC, "%s / %s", cur, max)
    end
  end
  m.ShiftCost = ShiftCost

  -- For every possible shift count k a label "xk" with a step curve that returns 1
  -- when mana% is between k*cost/max and (k+1)*cost/max, otherwise 0.
  m.shiftFS, m.shiftN = {}, -1
  function m.CurvesSupported()
    return C_CurveUtil and C_CurveUtil.CreateCurve and UnitPowerPercent and Enum and Enum.LuaCurveType and true or false
  end
  function m:HideShift()
    for _, fs in ipairs(self.shiftFS) do fs:Hide() end
  end
  function m:BuildShift(cost, max)
    local key = cost .. ":" .. max
    if key == self.shiftKey then return self.shiftOK end
    self.shiftKey = key
    self:HideShift()
    self.shiftOK = pcall(function()
      local n = math.min(math.floor(max / cost), 30)
      for k = 0, n do
        local c = C_CurveUtil.CreateCurve()
        c:SetType(Enum.LuaCurveType.Step)
        local lo, hi = k * cost / max, (k + 1) * cost / max
        if k == 0 then
          c:AddPoint(0, 1)
        else
          c:AddPoint(0, 0)
          c:AddPoint(lo, 1)
        end
        c:AddPoint(hi, 0)
        local fs = self.shiftFS[k + 1]
        if not fs then
          fs = NewFS(self.bar.bar, "CENTER")
          fs:SetPoint("CENTER")
          self.shiftFS[k + 1] = fs
        end
        fs:SetText("x" .. k)
        if k == 0 then fs:SetTextColor(1, 0.3, 0.3) else fs:SetTextColor(1, 1, 1) end
        fs.curve = c
      end
      self.shiftN = n
    end)
    return self.shiftOK
  end
  function m:UpdateShiftAlpha()
    for k = 0, self.shiftN do
      local fs = self.shiftFS[k + 1]
      fs:SetAlpha(UnitPowerPercent("player", 0, false, fs.curve))
      fs:Show()
    end
  end
end

-- Generic icon row ------------------------------------------------
local function IconRow(key)
  local m = NewModule(key)
  m.icons, m.count, m.isIconRow = {}, 0, true
  function m:GetIcon(i)
    if not self.icons[i] then self.icons[i] = CreateIcon(self.frame) end
    return self.icons[i]
  end
  function m:ContentWidth()
    if self.count == 0 then return 0 end
    local s, g = ns.db.iconSize, ns.db.spacing
    return self.count * s + (self.count - 1) * g
  end
  function m:IsActive() return self.count > 0 end
  function m:Resize(w)
    self.frame:SetSize(w, ns.db.iconSize)
    self:Place()
  end
  -- Icons centered inside the frame.
  function m:Place()
    local s, g = ns.db.iconSize, ns.db.spacing
    local off = math.max(0, (self.frame:GetWidth() - self:ContentWidth()) / 2)
    for i, ic in ipairs(self.icons) do
      ic:SetSize(s, s)
      ic:ClearAllPoints()
      ic:SetPoint("LEFT", self.frame, "LEFT", off + (i - 1) * (s + g), 0)
      ic:SetShown(i <= self.count)
      StyleCooldownText(ic)
    end
  end
  function m:SetCount(n)
    for i = 1, n do self:GetIcon(i) end
    local changed = n ~= self.count
    self.count = n
    if changed and ns.db then ns:Layout() else self:Place() end
  end
  return m
end

-- Target debuffs ----------------------------------------------------
do
  local m = IconRow("debuffs")
  function m:Rebuild()
    self.slots = {}
    for _, slot in ipairs(DEBUFF_SLOTS[ns.form] or {}) do
      local iconID
      for _, k in ipairs(slot) do
        local id = KnownID(k)
        if id then iconID = iconID or id end
      end
      if iconID then self.slots[#self.slots + 1] = { keys = slot, icon = SpellIcon(iconID) } end
    end
  end
  function m:Update()
    if not self.slots then self:Rebuild() end
    local auras = UnitExists("target") and ScanAuras("target", "HARMFUL|PLAYER") or {}
    local found, secretMode = {}, false
    for _, a in ipairs(auras) do
      if not readable(a.spellId) then secretMode = true break end
      local k = SPELL_TO_KEY[a.spellId]
      if k then found[k] = a end
    end

    if secretMode then
      -- Fallback: IDs are secret -> just show all of your debuffs on the target.
      local n = math.min(#auras, 8)
      self:SetCount(n)
      for i = 1, n do
        local ic, a = self.icons[i], auras[i]
        pcall(ic.tex.SetTexture, ic.tex, a.icon)
        SetIconState(ic, true)
        SetAuraTimer(ic, "target", a)
      end
      return
    end

    self:SetCount(#self.slots)
    for i, slot in ipairs(self.slots) do
      local ic = self.icons[i]
      local aura
      for _, k in ipairs(slot.keys) do aura = aura or found[k] end
      if aura then
        ic.tex:SetTexture(aura.icon or slot.icon)
        SetIconState(ic, true)
        SetAuraTimer(ic, "target", aura)
      else
        ic.tex:SetTexture(slot.icon)
        SetIconState(ic, false)
        ic.cd:Clear()
      end
    end
  end
end

-- Cooldowns ---------------------------------------------------------
do
  local m = IconRow("cooldowns")
  function m:Rebuild()
    self.spells = {}
    for _, k in ipairs(COOLDOWNS[ns.form] or {}) do
      local id = KnownID(k)
      if id then self.spells[#self.spells + 1] = id end
    end
  end
  function m:Update()
    if not self.spells then self:Rebuild() end
    self:SetCount(#self.spells)
    for i, id in ipairs(self.spells) do
      local ic = self.icons[i]
      ic.tex:SetTexture(SpellIcon(id))
      ic.cd:SetReverse(false)
      local start, dur = GetCooldown(id)
      if readable(start, dur) then
        if start and dur and dur > 1.5 then
          ic.cd:SetCooldown(start, dur)
          SetIconState(ic, false)
          ic.tex:SetAlpha(0.8)
        else
          ic.cd:Clear()
          SetIconState(ic, true)
        end
      else
        pcall(ic.cd.SetCooldown, ic.cd, start, dur)
        SetIconState(ic, true)
      end
      StyleCooldownText(ic)
    end
  end
end

-- Buffs -------------------------------------------------------------
do
  local m = IconRow("buffs")
  function m:Rebuild()
    self.slots = {}
    for _, b in ipairs(BUFFS) do
      local okForm = not b.forms or b.forms[ns.form]
      local known = KnownID(b.key)
      if okForm and (known or not b.needsKnown) then
        self.slots[#self.slots + 1] = { key = b.key, reminder = b.reminder, icon = SpellIcon(known or S[b.key][#S[b.key]]) }
      end
    end
  end
  function m:Update()
    if not self.slots then self:Rebuild() end
    local auras = ScanAuras("player", "HELPFUL")
    local found = {}
    for _, a in ipairs(auras) do
      if not readable(a.spellId) then return end -- secret: keep the previous state
      local k = SPELL_TO_KEY[a.spellId]
      if k then found[k] = a end
    end
    self:SetCount(#self.slots)
    for i, slot in ipairs(self.slots) do
      local ic, a = self.icons[i], found[slot.key]
      if a then
        ic.tex:SetTexture(a.icon or slot.icon)
        SetIconState(ic, true)
        SetAuraTimer(ic, "player", a)
      else
        ic.tex:SetTexture(slot.icon)
        SetIconState(ic, false, slot.reminder)
        ic.cd:Clear()
      end
    end
  end
end

-- Clearcasting icon ------------------------------------------------
do
  local m = NewModule("clearcast")
  m.icon = CreateIcon(m.frame)
  m.icon:SetPoint("TOP")
  m.icon.tex:SetTexture(SpellIcon(CLEARCASTING_ID) or 136170)
  m.icon:SetBackdropBorderColor(0.45, 0.92, 1, 1)
  m.text = NewFS(m.frame, "CENTER")
  m.text:SetPoint("TOP", m.icon, "BOTTOM", 0, -1)
  m.text:SetText("CLEARCAST")
  m.text:SetTextColor(0.45, 0.92, 1)
  local ag = m.icon:CreateAnimationGroup()
  ag:SetLooping("BOUNCE")
  local a = ag:CreateAnimation("Alpha")
  a:SetFromAlpha(1)
  a:SetToAlpha(0.45)
  a:SetDuration(0.35)
  m.pulse = ag
  function m:Resize()
    local s = math.floor(ns.db.iconSize * 1.5)
    self.icon:SetSize(s, s)
    self.frame:SetSize(math.max(s, 60), s + ns.db.fontSize + 4)
  end
  function m:IsActive() return ns.clearcasting end
  function m:Update()
    if ns.clearcasting then
      if not self.pulse:IsPlaying() then self.pulse:Play() end
    else
      self.pulse:Stop()
    end
  end
end

------------------------------------------------------------------------
-- Clearcasting detection + flash/sound
------------------------------------------------------------------------
local flash = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
flash:SetBackdrop({ edgeFile = TEX, edgeSize = 2 })
flash:SetBackdropBorderColor(0.45, 0.92, 1, 1)
flash:SetFrameStrata("HIGH")
flash:SetAlpha(0)
do
  local ag = flash:CreateAnimationGroup()
  for i = 1, 3 do
    local on = ag:CreateAnimation("Alpha")
    on:SetFromAlpha(0); on:SetToAlpha(1); on:SetDuration(0.1); on:SetOrder(i * 2 - 1)
    local off = ag:CreateAnimation("Alpha")
    off:SetFromAlpha(1); off:SetToAlpha(0); off:SetDuration(0.2); off:SetOrder(i * 2)
  end
  flash.anim = ag
end
ns.flash = flash

local function HasClearcasting()
  if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
    local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, CLEARCASTING_ID)
    if ok and a then return true end
  end
  -- Fallback when auras are secret in combat: while clearcasting
  -- your next spell costs 0.
  local key = (ns.form == "cat" and "claw") or (ns.form == "bear" and "maul") or "ht"
  local id = KnownID(key)
  if id then
    local cost = PowerCost(id)
    if readable(cost) and cost == 0 then return true end
  end
  return false
end

function ns:OnClearcastStart()
  if self.db.ccSound then
    local kit = SOUNDKIT and (SOUNDKIT.ALARM_CLOCK_WARNING_3 or SOUNDKIT.RAID_WARNING)
    if not (kit and pcall(PlaySound, kit, "Master")) then pcall(PlaySound, 8959, "Master") end
  end
  if self.db.ccFlash then
    flash.anim:Stop()
    flash.anim:Play()
  end
end

function ns:SetClearcasting(state)
  if state == self.clearcasting then return end
  self.clearcasting = state
  if state then self:OnClearcastStart() end
  self:Layout()
  self.modules.power:Update()
  self.modules.clearcast:Update()
end

function ns:TestClearcast()
  self:SetClearcasting(true)
  C_Timer.After(3, function() ns.testing = false; ns:SetClearcasting(HasClearcasting()) end)
  self.testing = true
end

------------------------------------------------------------------------
-- Layout, moving, scaling, detaching
------------------------------------------------------------------------
local function SavePoint(frame)
  local p, _, rp, x, y = frame:GetPoint()
  return { p, "UIParent", rp, x, y }
end

local function ApplyPoint(frame, p)
  frame:ClearAllPoints()
  frame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
end

function ns:Detach(m)
  local mdb = self.db.modules[m.key]
  local x, y = m.frame:GetCenter()
  if not x then x, y = UIParent:GetCenter() end
  mdb.detached = true
  mdb.scale = 1
  mdb.point = { "CENTER", "UIParent", "BOTTOMLEFT", x, y }
  self:Layout()
end

function ns:Attach(m)
  self.db.modules[m.key].detached = false
  self:Layout()
end

local function CreateMover(m)
  local mv = CreateFrame("Frame", nil, m.frame)
  mv:SetAllPoints()
  mv:SetFrameLevel(m.frame:GetFrameLevel() + 30)
  mv:EnableMouse(true)
  mv:EnableMouseWheel(true)
  mv:RegisterForDrag("LeftButton")
  mv.bg = mv:CreateTexture(nil, "OVERLAY")
  mv.bg:SetAllPoints()
  mv.label = NewFS(mv, "CENTER")
  mv.label:SetPoint("CENTER")
  mv:SetScript("OnDragStart", function()
    local mdb = ns.db.modules[m.key]
    if not mdb.detached and IsShiftKeyDown() then ns:Detach(m) end
    ns.moving = mdb.detached and m.frame or root
    ns.moving:StartMoving()
  end)
  mv:SetScript("OnDragStop", function()
    local f = ns.moving
    if not f then return end
    f:StopMovingOrSizing()
    pcall(f.SetUserPlaced, f, false)
    if f == root then ns.db.point = SavePoint(root) else ns.db.modules[m.key].point = SavePoint(f) end
    ns.moving = nil
    ns:Layout()
  end)
  mv:SetScript("OnMouseUp", function(_, btn)
    if btn == "RightButton" and ns.db.modules[m.key].detached then ns:Attach(m) end
  end)
  mv:SetScript("OnMouseWheel", function(_, delta)
    local mdb = ns.db.modules[m.key]
    if mdb.detached then
      mdb.scale = math.min(3, math.max(0.3, (mdb.scale or 1) + delta * 0.05))
    else
      ns.db.scale = math.min(3, math.max(0.3, ns.db.scale + delta * 0.05))
    end
    ns:Layout()
    if ns.RefreshOptions then ns.RefreshOptions() end
  end)
  mv:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(ns.MODULE_LABELS[m.key])
    if ns.db.modules[m.key].detached then
      GameTooltip:AddLine("Drag: move this element", 1, 1, 1)
      GameTooltip:AddLine("Mouse wheel: scale this element", 1, 1, 1)
      GameTooltip:AddLine("Right-click: attach back to the bar", 1, 1, 1)
    else
      GameTooltip:AddLine("Drag: move the whole bar", 1, 1, 1)
      GameTooltip:AddLine("Shift+drag: detach this element", 1, 1, 1)
      GameTooltip:AddLine("Mouse wheel: scale the whole bar", 1, 1, 1)
    end
    GameTooltip:Show()
  end)
  mv:SetScript("OnLeave", function() GameTooltip:Hide() end)
  m.mover = mv
end

function ns:Layout()
  local db = self.db
  if not db then return end
  for _, fs in ipairs(self.fontStrings) do fs:SetFont(FONT, db.fontSize, "OUTLINE") end

  root:SetScale(db.scale)
  ApplyPoint(root, db.point)

  local y, width = 0, db.width
  local flow = {}
  for _, key in ipairs(self.MODULE_ORDER) do
    local m, mdb = self.modules[key], db.modules[key]
    local f = m.frame
    m:Resize(width)
    local shown = mdb.enabled and (not db.locked or m:IsActive())
    f:ClearAllPoints()
    if mdb.detached then
      f:SetScale(db.scale * (mdb.scale or 1))
      if mdb.point then ApplyPoint(f, mdb.point) else f:SetPoint("CENTER", UIParent, "CENTER") end
    else
      f:SetScale(db.scale)
      if key == "clearcast" then
        f:SetPoint("TOPRIGHT", root, "TOPLEFT", -4, 0)
      elseif m.isIconRow and db.mergeIcons and shown then
        flow[#flow + 1] = m -- laid out together on one line below
        f:SetPoint("TOP", root, "TOP", 0, 0)
      elseif shown then
        f:SetPoint("TOP", root, "TOP", 0, -y)
        y = y + f:GetHeight() + db.spacing
      else
        f:SetPoint("TOP", root, "TOP", 0, 0)
      end
    end
    f:SetShown(shown)

    local mv = m.mover
    mv:SetShown(not db.locked and mdb.enabled)
    if mdb.detached then mv.bg:SetColorTexture(1, 0.55, 0.1, 0.4) else mv.bg:SetColorTexture(0.1, 0.6, 1, 0.35) end
    mv.label:SetText(self.MODULE_LABELS[key] .. (mdb.detached and " (detached)" or ""))
  end

  -- Icon groups (debuffs, cooldowns, buffs) side by side, centered;
  -- only wrap to a new line when they no longer fit the width.
  if #flow > 0 then
    local s, gap = db.iconSize, db.spacing + 6
    local rows, row, rowW = {}, {}, 0
    for _, m in ipairs(flow) do
      local cw = m:ContentWidth()
      if cw == 0 then cw = s * 2 end -- empty (only while unlocked)
      local add = (#row > 0 and gap or 0) + cw
      if #row > 0 and rowW + add > width then
        rows[#rows + 1] = { items = row, w = rowW }
        row, rowW, add = {}, 0, cw
      end
      row[#row + 1] = { m = m, w = cw }
      rowW = rowW + add
    end
    rows[#rows + 1] = { items = row, w = rowW }
    for _, r in ipairs(rows) do
      local x = (width - r.w) / 2
      for _, it in ipairs(r.items) do
        local f = it.m.frame
        f:SetWidth(it.w)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
        it.m:Place()
        x = x + it.w + gap
      end
      y = y + s + db.spacing
    end
  end
  root:SetSize(width, math.max(y - db.spacing, 1))

  flash:SetScale(db.scale)
  flash:ClearAllPoints()
  flash:SetPoint("TOPLEFT", root, "TOPLEFT", -4, 4)
  flash:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 4, -4)
end

function ns:RebuildRows()
  for _, k in ipairs({ "debuffs", "cooldowns", "buffs" }) do self.modules[k]:Rebuild() end
end

function ns:UpdateAll()
  for _, key in ipairs(self.MODULE_ORDER) do self.modules[key]:Update() end
end

function ns:Refresh()
  self.form = FormGroup()
  self:RebuildRows()
  self:Layout()
  self:UpdateAll()
end

function ns:SetLocked(locked)
  self.db.locked = locked
  self:Layout()
  if self.RefreshOptions then self.RefreshOptions() end
  print("|cff4fe8ffCompact Druid Bar|r: " .. (locked and "locked." or "unlocked. Drag to move, Shift+drag to detach, scroll to scale."))
end

function ns:ResetPositions()
  self.db.point = CopyDefaults(DEFAULTS.point, {})
  self.db.scale = 1
  for _, k in ipairs(self.MODULE_ORDER) do
    local mdb = self.db.modules[k]
    mdb.detached, mdb.point, mdb.scale = false, nil, 1
  end
  self:Layout()
end

function ns:ResetAll()
  wipe(CompactDruidBarDB)
  self.db = CopyDefaults(DEFAULTS, CompactDruidBarDB)
  self:Refresh()
end

------------------------------------------------------------------------
-- Visibility (dimmed out of combat)
------------------------------------------------------------------------
local function ComputeAlpha()
  local db = ns.db
  if not db.locked then return 1 end
  if UnitAffectingCombat("player") then return 1 end
  if UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then return 1 end
  local ok, full = pcall(function()
    if UnitHealth("player") < UnitHealthMax("player") then return false end
    local pt = UnitPowerType("player")
    if pt == 1 then return UnitPower("player", 1) == 0 end
    if UnitPower("player", pt) < UnitPowerMax("player", pt) then return false end
    local mmax = UnitPowerMax("player", 0)
    return mmax == 0 or UnitPower("player", 0) >= mmax
  end)
  -- Unreadable (Forever hides health/power)? Out of combat without a hostile target = dim.
  if not ok or full then return db.oocAlpha end
  return 1
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local function TryRegister(event, ...)
  if select("#", ...) > 0 then
    pcall(ev.RegisterUnitEvent, ev, event, ...)
  else
    pcall(ev.RegisterEvent, ev, event)
  end
end

ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    local _, class = UnitClass("player")
    if class ~= "DRUID" then
      print("|cff4fe8ffCompact Druid Bar|r: not a druid, addon disabled.")
      return
    end
    CompactDruidBarDB = CompactDruidBarDB or {}
    ns.db = CopyDefaults(DEFAULTS, CompactDruidBarDB)
    for _, key in ipairs(ns.MODULE_ORDER) do CreateMover(ns.modules[key]) end
    if ns.BuildOptions then ns:BuildOptions() end

    TryRegister("PLAYER_ENTERING_WORLD")
    TryRegister("UPDATE_SHAPESHIFT_FORM")
    TryRegister("UPDATE_SHAPESHIFT_FORMS")
    TryRegister("SPELLS_CHANGED")
    TryRegister("CHARACTER_POINTS_CHANGED")
    TryRegister("PLAYER_TARGET_CHANGED")
    TryRegister("SPELL_UPDATE_COOLDOWN")
    TryRegister("PLAYER_REGEN_ENABLED")
    TryRegister("PLAYER_REGEN_DISABLED")
    TryRegister("UNIT_AURA", "player", "target")
    TryRegister("UNIT_POWER_FREQUENT", "player")
    TryRegister("UNIT_DISPLAYPOWER", "player")
    TryRegister("UNIT_MAXPOWER", "player")

    ev:SetScript("OnUpdate", function(_, elapsed)
      ns.t1 = (ns.t1 or 0) + elapsed
      ns.t2 = (ns.t2 or 0) + elapsed
      if ns.t1 >= 0.05 then
        ns.t1 = 0
        for _, k in ipairs({ "health", "power", "combo", "mana" }) do
          if ns.modules[k].frame:IsShown() then ns.modules[k]:Update() end
        end
        local a = ComputeAlpha()
        for _, key in ipairs(ns.MODULE_ORDER) do ns.modules[key].frame:SetAlpha(a) end
      end
      if ns.t2 >= 0.1 then
        ns.t2 = 0
        if not ns.testing then ns:SetClearcasting(HasClearcasting()) end
      end
    end)
    ns:Refresh()
    return
  end

  if not ns.db then return end

  if event == "PLAYER_ENTERING_WORLD" or event == "UPDATE_SHAPESHIFT_FORM" or event == "UPDATE_SHAPESHIFT_FORMS"
    or event == "SPELLS_CHANGED" or event == "CHARACTER_POINTS_CHANGED" or event == "UNIT_DISPLAYPOWER"
    or event == "UNIT_MAXPOWER" then
    ns:Refresh()
  elseif event == "UNIT_AURA" then
    if arg1 == "player" then
      ns.modules.buffs:Update()
      if not ns.testing then ns:SetClearcasting(HasClearcasting()) end
    elseif arg1 == "target" then
      ns.modules.debuffs:Update()
    end
  elseif event == "PLAYER_TARGET_CHANGED" then
    ns.modules.debuffs:Update()
    ns.modules.combo:Update()
  elseif event == "SPELL_UPDATE_COOLDOWN" then
    ns.modules.cooldowns:Update()
  elseif event == "UNIT_POWER_FREQUENT" then
    ns.modules.power:OnPower()
  elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
    ns.modules.buffs:Update()
    ns.modules.debuffs:Update()
  end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SLASH_COMPACTDRUIDBAR1 = "/cdb"
SLASH_COMPACTDRUIDBAR2 = "/druidbar"
SlashCmdList.COMPACTDRUIDBAR = function(msg)
  if not ns.db then return end
  msg = strtrim((msg or ""):lower())
  local cmd, arg = msg:match("^(%S*)%s*(.-)$")
  if cmd == "unlock" or cmd == "lock" or cmd == "move" then
    ns:SetLocked(cmd == "lock" or (cmd == "move" and not ns.db.locked))
  elseif cmd == "scale" and tonumber(arg) then
    ns.db.scale = math.min(3, math.max(0.3, tonumber(arg)))
    ns:Layout()
  elseif cmd == "reset" then
    ns:ResetPositions()
    print("|cff4fe8ffCompact Druid Bar|r: positions and scale reset.")
  elseif cmd == "test" then
    ns:TestClearcast()
  elseif cmd == "debug" then
    ns:Debug()
  elseif cmd == "" or cmd == "config" or cmd == "options" then
    if ns.OpenOptions then ns:OpenOptions() end
  else
    print("|cff4fe8ffCompact Druid Bar|r: /cdb (options), /cdb unlock, /cdb lock, /cdb scale 1.2, /cdb reset, /cdb test, /cdbdebug")
  end
end

-- Separate command without arguments: in combat the text after /cdb is secret.
SLASH_COMPACTDRUIDBARDEBUG1 = "/cdbdebug"
SlashCmdList.COMPACTDRUIDBARDEBUG = function()
  if ns.db then ns:Debug() end
end

function ns:Debug()
    local function show(label, v)
      local state = readable(v) and tostring(v) or "SECRET"
      print(("  %s: %s"):format(label, state))
    end
    print("|cff4fe8ffCompact Druid Bar debug|r build 3 (secret-API: " .. tostring(issecretvalue ~= nil) .. ", in combat: " .. tostring(UnitAffectingCombat("player")) .. ")")
    show("Health", UnitHealth("player"))
    show("Health max", UnitHealthMax("player"))
    show("Power type", UnitPowerType("player"))
    show("Energy", UnitPower("player", 3))
    show("Mana", UnitPower("player", 0))
    show("Mana max", UnitPowerMax("player", 0))
    show("Combo points", UnitPower("player", 4))
    show("Shift cost", ns.modules.mana.ShiftCost())
    show("Form", ns.form)
    local a = ScanAuras("player", "HELPFUL")[1]
    if a then show("First buff spellId", a.spellId) else print("  First buff: none/unreadable") end
    local t = UnitExists("target") and ScanAuras("target", "HARMFUL|PLAYER")[1]
    if t then show("First target debuff spellId", t.spellId) else print("  Target debuff: none") end
    local function try(label, fn)
      local ok, err = pcall(fn)
      if not ok then print("  " .. label .. ": ERROR " .. tostring(err)) end
    end
    try("Cooldown", function() show("Cooldown Dash (start)", (GetCooldown(KnownID("dash") or 1850))) end)
    try("Clearcasting", function() show("Clearcasting now", HasClearcasting()) end)
    try("Curves", function()
      local mm = ns.modules.mana
      print(("  Curves available: %s, xN via curves: %s%s"):format(
        tostring(mm.CurvesSupported()), tostring(mm.shiftOK == true),
        mm.shiftBroken and " (FAILED)" or ""))
    end)
    print("  UnitHealthPercent: " .. tostring(UnitHealthPercent ~= nil))
    print(("  Energy tick known: %s"):format(tostring(ns.modules.power.lastTick > 0)))
end
