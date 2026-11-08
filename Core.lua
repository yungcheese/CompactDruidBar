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
ns.MODULE_ORDER = { "combo", "health", "power", "mana", "debuffs", "cooldowns", "buffs", "clearcast" }
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
  ccSoundKey = "file:shimmer", ccSoundChannel = "Master",
  bleedWarn = true, consumables = true, cpGlow = true, gcdSpark = true,
  minimap = { hide = true, minimapPos = 220 }, -- same keys LibDBIcon uses
  style = "gold", gems = true, iconBorder = true, panel = true, barSpark = true,
  iconSizes = { debuffs = 22, cooldowns = 22, buffs = 22 }, -- per icon row
  point = { "CENTER", "UIParent", "CENTER", 0, -160 },
  modules = {},
  custom = {},   -- { id, name, kind = "cd"|"buff"|"debuff", forms = { cat, bear, caster } }
  hidden = {},   -- [builtinKey] = true
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

-- Spell APIs can throw for IDs that don't exist on this client (e.g. Classic IDs
-- missing on WoW Forever), so every lookup is guarded.
local function SafeCall(fn, ...)
  if not fn then return end
  local ok, a, b = pcall(fn, ...)
  if ok then return a, b end
end
local function IsKnown(id)
  return SafeCall(IsPlayerSpell, id) or SafeCall(IsSpellKnown, id) or false
end
-- Spells whose IDs differ on some clients: also look them up by name in the spellbook.
local NAME_ALIASES = {
  ffFeral = { "Faerie Fire (Feral)" },
  pounce = { "Pounce" }, -- S.pounce holds the bleed debuff IDs, the castable spell is found by name
}
local function KnownID(key)
  local ids = S[key]
  if not ids then return end
  for i = #ids, 1, -1 do
    if IsKnown(ids[i]) then return ids[i] end
  end
  for _, name in ipairs(NAME_ALIASES[key] or {}) do
    local info = C_Spell and SafeCall(C_Spell.GetSpellInfo, name)
    if type(info) == "table" and info.spellID then
      -- Remember this client's ID so auras and casts with it are recognized too.
      SPELL_TO_KEY[info.spellID] = SPELL_TO_KEY[info.spellID] or key
      return info.spellID
    end
  end
end

-- Name -> key lookup, for spell IDs we don't know (other ranks or client-specific IDs).
local NAME_TO_KEY
local function KeyFromName(name)
  if not name or not readable(name) then return end
  if not NAME_TO_KEY then
    NAME_TO_KEY = {}
    for key, aliases in pairs(NAME_ALIASES) do
      for _, n in ipairs(aliases) do NAME_TO_KEY[n] = key end
    end
    for key, ids in pairs(S) do
      for _, id in ipairs(ids) do
        local n = C_Spell and SafeCall(C_Spell.GetSpellName, id)
        if n and not NAME_TO_KEY[n] then NAME_TO_KEY[n] = key end
      end
    end
  end
  local key = NAME_TO_KEY[name]
  if key then return key end
  -- Looser match for clients that name it differently ("Faerie Fire (Feral)", rank suffixes, ...).
  if name:find("Faerie Fire", 1, true) then
    return name:find("Feral", 1, true) and "ffFeral" or "ff"
  end
end
local function SpellIcon(id)
  if C_Spell and C_Spell.GetSpellTexture then return (SafeCall(C_Spell.GetSpellTexture, id)) end
  return (SafeCall(GetSpellTexture, id))
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
  local ok, s, d = pcall(function()
    if C_Spell and C_Spell.GetSpellCooldown then
      local info = C_Spell.GetSpellCooldown(id)
      if info then return info.startTime, info.duration end
    elseif GetSpellCooldown then
      return GetSpellCooldown(id)
    end
  end)
  if ok then return s, d end
end

-- Built-in spells per category (used by the Spells options page).
ns.S = S
ns.BUILTIN = {
  { cat = "Debuffs", keys = { "rip", "rake", "pounce", "ffFeral", "ff", "demo", "moonfire", "swarm" } },
  { cat = "Cooldowns", keys = { "dash", "grasp", "barkskin", "innervate", "rebirth", "bash", "charge", "enrage", "frenzied", "swiftmend", "nswift", "hurricane" } },
  { cat = "Buffs", keys = { "motw", "thorns", "tigers" } },
}
function ns.SpellName(id)
  if C_Spell and C_Spell.GetSpellName then return (SafeCall(C_Spell.GetSpellName, id)) end
  return (SafeCall(GetSpellInfo, id))
end
function ns.KeyName(key)
  if key == "ffFeral" then
    local id = KnownID("ffFeral")
    local n = id and ns.SpellName(id)
    if n and n:find("Feral") then return n end
    return (ns.SpellName(770) or "Faerie Fire") .. " (Feral)"
  end
  if key == "pounce" then return ns.SpellName(9005) or "Pounce" end
  for _, id in ipairs(S[key] or {}) do
    local n = ns.SpellName(id)
    if n then return n end
  end
  return key
end
local function Hidden(key) return ns.db and ns.db.hidden[key] end

-- Mana consumables (best item first). Potions share a cooldown, runes too.
local CONSUMABLES = {
  { 13444, 13443, 6149, 3827, 3385, 2455 }, -- Major .. Minor Mana Potion
  { 12662, 20520 },                          -- Demonic Rune, Dark Rune
}

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

------------------------------------------------------------------------
-- Visual styles
------------------------------------------------------------------------
ns.STYLES = {
  { "gold", "Classic gold frame" },
  { "classic", "Classic polished" },
  { "flat", "Flat" },
  { "soft", "Soft" },
}
local STYLE = {
  gold    = { tex = "Interface\\TargetingFrame\\UI-StatusBar", font = FONT, flags = "", shadow = true, accent = true, frame = true },
  classic = { tex = "Interface\\TargetingFrame\\UI-StatusBar", font = FONT, flags = "", shadow = true, accent = true },
  flat    = { tex = TEX, font = "Fonts\\ARIALN.TTF", flags = "OUTLINE" },
  soft    = { tex = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill", font = "Fonts\\ARIALN.TTF", flags = "OUTLINE" },
}
local GOLD = { 0.80, 0.63, 0.30 }
local function Style() return STYLE[ns.db and ns.db.style] or STYLE.gold end
local function IconBorderColor()
  if ns.db and ns.db.iconBorder then return 0.78, 0.62, 0.28, 1 end
  return 0, 0, 0, 1
end
ns.bars, ns.iconList = {}, {}

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
  -- Thin gold accent line around the bar (classic styles).
  holder.accent = CreateFrame("Frame", nil, holder, "BackdropTemplate")
  holder.accent:SetPoint("TOPLEFT", -1, 1)
  holder.accent:SetPoint("BOTTOMRIGHT", 1, -1)
  holder.accent:SetBackdrop({ edgeFile = TEX, edgeSize = 1 })
  holder.accent:SetBackdropBorderColor(0.42, 0.33, 0.14, 1)
  -- Spark at the end of the fill, like Blizzard's casting bar.
  holder.spark = bar:CreateTexture(nil, "OVERLAY", nil, 6)
  holder.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
  holder.spark:SetBlendMode("ADD")
  holder.spark:Hide()
  ns.bars[#ns.bars + 1] = holder
  return holder
end

local function SetBar(holder, cur, max)
  pcall(holder.bar.SetMinMaxValues, holder.bar, 0, max)
  pcall(holder.bar.SetValue, holder.bar, cur)
  local show = ns.db.barSpark
  if show and readable(cur, max) then show = cur and max and cur > 0 and cur < max end
  holder.spark:SetShown(show and true or false)
end

local function CreateIcon(parent)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetBackdrop({ edgeFile = TEX, edgeSize = 1 })
  f:SetBackdropBorderColor(0, 0, 0, 1)
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetPoint("TOPLEFT", 1, -1)
  f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
  f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  -- Soft gloss on the top half (classic icon border option).
  f.gloss = f:CreateTexture(nil, "OVERLAY")
  f.gloss:SetPoint("TOPLEFT", f.tex, "TOPLEFT")
  f.gloss:SetPoint("BOTTOMRIGHT", f.tex, "RIGHT")
  f.gloss:SetColorTexture(1, 1, 1, 1)
  if not (CreateColor and pcall(f.gloss.SetGradient, f.gloss, "VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.22))) then
    f.gloss:SetAlpha(0.08)
  end
  ns.iconList[#ns.iconList + 1] = f
  f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
  f.cd:SetAllPoints(f.tex)
  f.cd:SetDrawEdge(false)
  if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(false) end
  -- Stack/item count in the bottom-right corner, above the cooldown swipe.
  local over = CreateFrame("Frame", nil, f)
  over:SetAllPoints()
  over:SetFrameLevel(f.cd:GetFrameLevel() + 2)
  f.count = NewFS(over, "RIGHT")
  f.count:SetPoint("BOTTOMRIGHT", -1, 1)
  return f
end

local function StyleCooldownText(icon)
  local w = icon:GetWidth()
  if not w or w <= 0 then w = ns.db.iconSize end
  local size = math.max(8, math.floor(w * 0.42))
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
    icon:SetBackdropBorderColor(IconBorderColor())
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

-- Returns the list of auras plus an error text if the API refused.
local function ScanAuras(unit, filter)
  local list = {}
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return list, "no API" end
  for i = 1, 40 do
    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
    if not ok then return list, tostring(a) end
    if not a then break end
    list[#list + 1] = a
  end
  return list
end

-- On Forever auras can't be read in combat. An empty result in combat
-- therefore means "unknown", not "no auras": keep showing the last state.
local function AurasUnknown(list, err)
  return err ~= nil or (#list == 0 and UnitAffectingCombat("player"))
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
    if pt == 0 then
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
  -- We keep a histogram of "time mod 2" (40 bins of 0.05s); its peak is the tick moment.
  -- Power changes right after our own casts are ignored (energy spent / Furor),
  -- the spark only appears once the peak clearly stands out, and the phase is
  -- a weighted average, so it moves smoothly instead of jumping.
  local NB = 40
  m.bins = {}
  for i = 1, NB do m.bins[i] = 0 end
  local function Bin(i) return m.bins[(i - 1) % NB + 1] end
  function m:OnPowerSecret()
    local now = GetTime()
    if self.gcdStart and now - self.gcdStart < 0.25 then return end -- caused by our cast
    local b = math.floor((now % 2) / 2 * NB) % NB + 1
    for i = 1, NB do self.bins[i] = self.bins[i] * 0.96 end
    self.bins[b] = self.bins[b] + 1

    -- Strongest 3-bin window, and the strongest window that isn't next to it.
    local best, bestV = 1, -1
    for i = 1, NB do
      local v = Bin(i - 1) + Bin(i) + Bin(i + 1)
      if v > bestV then best, bestV = i, v end
    end
    local second = 0
    for i = 1, NB do
      local d = math.abs(i - best)
      d = math.min(d, NB - d)
      if d > 3 then second = math.max(second, Bin(i - 1) + Bin(i) + Bin(i + 1)) end
    end
    if bestV < 3 or bestV < second * 1.8 then return end -- rhythm not clear yet

    local wl, wc, wr = Bin(best - 1), Bin(best), Bin(best + 1)
    local offset = (wr - wl) / (wl + wc + wr)
    local phase = ((best - 1 + 0.5 + offset) * 2 / NB) % 2
    self.lastTick = phase + 2 -- (GetTime() - lastTick) % 2 gives the position in the cycle
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

  -- GCD spark: a thin line along the bottom of the power bar that fills during the global cooldown.
  m.gcd = m.bar.bar:CreateTexture(nil, "OVERLAY", nil, 7)
  m.gcd:SetColorTexture(1, 1, 1, 0.85)
  m.gcd:SetHeight(2)
  m.gcd:SetPoint("BOTTOMLEFT", m.bar.bar, "BOTTOMLEFT", 0, 0)
  m.gcd:Hide()
  function m:OnCast()
    self.gcdStart = GetTime()
    self.gcdDur = (ns.form == "cat") and 1.0 or 1.5
  end

  m.frame:SetScript("OnUpdate", function()
    if ns.db and ns.db.gcdSpark then
      local s, d = GetCooldown(61304) -- 61304 = global cooldown
      if not readable(s, d) then
        -- Secret in combat: estimate from our own last cast (Classic GCD: 1.0s cat, 1.5s otherwise).
        s, d = m.gcdStart, m.gcdDur
      end
      local shown = false
      if s and d and d > 0 then
        local p = (GetTime() - s) / d
        if p >= 0 and p < 1 then
          m.gcd:SetWidth(math.max(1, m.bar.bar:GetWidth() * p))
          shown = true
        end
      end
      m.gcd:SetShown(shown)
    else
      m.gcd:Hide()
    end
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
    -- Gem look: rotated squares (border, socket, gem, shine).
    local function Gem(layer, r, g, b, a)
      local t = s:CreateTexture(nil, layer)
      t:SetTexture(TEX)
      t:SetVertexColor(r, g, b, a or 1)
      if t.SetRotation then t:SetRotation(math.pi / 4) end
      t:SetPoint("CENTER")
      return t
    end
    s.gemBorder = Gem("BACKGROUND", 0.05, 0.03, 0.01)
    s.gemSocket = Gem("BORDER", 0.13, 0.10, 0.08)
    s.gemOn     = Gem("ARTWORK", 1, 0.55, 0.1)
    s.gemShine  = Gem("OVERLAY", 1, 0.9, 0.65, 0.75)
    m.segs[i] = s
  end
  -- Glow around the combo bar at 5 combo points (finisher time).
  m.glow = m.frame:CreateTexture(nil, "BACKGROUND")
  m.glow:SetPoint("TOPLEFT", -3, 3)
  m.glow:SetPoint("BOTTOMRIGHT", 3, -3)
  m.glow:SetColorTexture(1, 0.35, 0.1, 0.8)
  m.glow:Hide()
  do
    local ag = m.glow:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.25)
    a:SetDuration(0.4)
    m.glowAnim = ag
  end
  function m:Resize(w)
    local gems = ns.db.gems
    local h, gap = ns.db.smallBarHeight, 2
    if gems then h = math.max(10, ns.db.smallBarHeight + 6) end
    self.frame:SetSize(w, h)
    local segW = (w - gap * 4) / 5
    local side = h * 0.70 -- rotated 45 degrees, so the diagonal fits the height
    for i, s in ipairs(self.segs) do
      s:ClearAllPoints()
      s:SetSize(segW, h)
      s:SetPoint("LEFT", self.frame, "LEFT", (i - 1) * (segW + gap), 0)
      s:SetBackdropColor(0, 0, 0, gems and 0 or 0.55)
      s:SetBackdropBorderColor(0, 0, 0, gems and 0 or 1)
      s.gemBorder:SetSize(side, side)
      s.gemSocket:SetSize(side - 2, side - 2)
      s.gemOn:SetSize(side - 3, side - 3)
      s.gemShine:SetSize(side * 0.32, side * 0.32)
      s.gemShine:ClearAllPoints()
      s.gemShine:SetPoint("CENTER", -side * 0.14, side * 0.14)
      s.gemBorder:SetShown(gems)
      s.gemSocket:SetShown(gems)
      if not gems then s.gemOn:Hide(); s.gemShine:Hide() end
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
    local gems = ns.db.gems
    local ok5, full5 = pcall(function() return cp >= 5 end)
    full5 = ok5 and full5
    for i, s in ipairs(self.segs) do
      local ok, on = pcall(function() return cp >= i end)
      on = ok and on
      if gems then
        s.fill:Hide()
        s.gemOn:SetShown(on)
        s.gemShine:SetShown(on)
        if full5 then s.gemOn:SetVertexColor(1, 0.25, 0.1) else s.gemOn:SetVertexColor(1, 0.55, 0.1) end
      else
        s.fill:SetShown(on)
        if full5 then s.fill:SetColorTexture(1, 0.3, 0.15) else s.fill:SetColorTexture(1, 0.75, 0.1) end
      end
    end
    local ok5, full = pcall(function() return cp >= 5 end)
    local glow = ns.db.cpGlow and ok5 and full
    if glow then
      self.glow:Show()
      if not self.glowAnim:IsPlaying() then self.glowAnim:Play() end
    else
      self.glowAnim:Stop()
      self.glow:Hide()
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
  -- Icon size of this row (falls back to the global size).
  function m:Size()
    return (ns.db.iconSizes and ns.db.iconSizes[key]) or ns.db.iconSize
  end
  function m:ContentWidth()
    if self.count == 0 then return 0 end
    local s, g = self:Size(), ns.db.spacing
    return self.count * s + (self.count - 1) * g
  end
  function m:IsActive() return self.count > 0 end
  function m:Resize(w)
    self.frame:SetSize(w, self:Size())
    self:Place()
  end
  -- Icons centered inside the frame.
  function m:Place()
    local s, g = self:Size(), ns.db.spacing
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

-- Aura / custom spell helpers ---------------------------------------
local function IndexAuras(auras)
  local byKey, byId, byName = {}, {}, {}
  for _, a in ipairs(auras) do
    if not readable(a.spellId) then return nil end -- IDs are secret
    local k = SPELL_TO_KEY[a.spellId] or KeyFromName(a.name)
    if k then byKey[k] = byKey[k] or a end
    byId[a.spellId] = a
    if readable(a.name) and a.name then byName[a.name] = a end
  end
  return byKey, byId, byName
end
local function CustomFor(kind)
  local list = {}
  for _, c in ipairs(ns.db.custom) do
    if c.kind == kind and c.forms and c.forms[ns.form] then list[#list + 1] = c end
  end
  return list
end
local function CustomIcon(c) return SpellIcon(c.id) or 134400 end
local function ItemCooldown(id)
  local ok, s, d = pcall(function()
    if C_Container and C_Container.GetItemCooldown then return C_Container.GetItemCooldown(id) end
    if GetItemCooldown then return GetItemCooldown(id) end
  end)
  if ok then return s, d end
end
local function ItemCount(id)
  if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) end
  if GetItemCount then return GetItemCount(id) end
  return 0
end
local function ItemIcon(id)
  if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
  if GetItemIcon then return GetItemIcon(id) end
end

local BLEEDS = { rip = true, rake = true }

-- Cast tracking: Forever blocks target auras in combat, so we time our own
-- debuffs from our casts (like the old Classic WeakAuras did).
local DEBUFF_DURATION = { rip = 12, rake = 9, pounce = 18, ffFeral = 40, ff = 40, demo = 30, moonfire = 12, swarm = 12 }
local DURATION_OVERRIDE = { [8921] = 9 }                       -- Moonfire rank 1
local CAST_KEY = { [9005] = "pounce", [9823] = "pounce", [9827] = "pounce" } -- Pounce casts -> bleed
ns.casts = {}                                                  -- key -> { start, dur, guid }
-- Own buffs on yourself are blocked in combat too; time them from the cast.
local BUFF_DURATION = { tigers = 6, grasp = 45 }
ns.buffCasts = {}                                              -- key -> { start, dur }

local function TargetGUID()
  local g = UnitGUID and UnitGUID("target")
  if g and readable(g) then return g end
end

function ns:TrackCast(spellID)
  self.lastCastID = spellID
  if not readable(spellID) or not spellID then return end
  local key = CAST_KEY[spellID] or SPELL_TO_KEY[spellID] or KeyFromName(ns.SpellName(spellID))
  if key and BUFF_DURATION[key] then
    self.buffCasts[key] = { start = GetTime(), dur = BUFF_DURATION[key] }
    self.modules.buffs:Update()
    return
  end
  local dur = key and (DURATION_OVERRIDE[spellID] or DEBUFF_DURATION[key])
  if not dur then return end
  self.casts[key] = { start = GetTime(), dur = dur, guid = TargetGUID() }
  self.modules.debuffs:Update()
end

-- Target debuffs ----------------------------------------------------
do
  local m = IconRow("debuffs")
  function m:Rebuild()
    self.slots = {}
    for _, slot in ipairs(DEBUFF_SLOTS[ns.form] or {}) do
      local iconID, warn
      for _, k in ipairs(slot) do
        local id = not Hidden(k) and KnownID(k)
        if id then iconID = iconID or id end
        if BLEEDS[k] then warn = true end
      end
      if iconID then self.slots[#self.slots + 1] = { keys = slot, icon = SpellIcon(iconID), warn = warn } end
    end
    for _, c in ipairs(CustomFor("debuff")) do
      self.slots[#self.slots + 1] = { custom = c, icon = CustomIcon(c) }
    end
  end
  function m:Update()
    if not self.slots then self:Rebuild() end
    local auras, err = {}, nil
    if UnitExists("target") then auras, err = ScanAuras("target", "HARMFUL|PLAYER") end
    self.targetChanged = nil
    -- In combat Forever blocks target auras: show our own tracked casts instead.
    if UnitExists("target") and AurasUnknown(auras, err) then
      self:ShowFromCasts()
      return
    end
    local byKey, byId, byName = IndexAuras(auras)
    if byKey then
      -- Readable (out of combat): remember real timers so they carry into combat.
      local guid = TargetGUID()
      wipe(ns.casts)
      for k, a in pairs(byKey) do
        if DEBUFF_DURATION[k] and readable(a.expirationTime, a.duration) and a.duration and a.duration > 0 then
          ns.casts[k] = { start = a.expirationTime - a.duration, dur = a.duration, guid = guid }
        end
      end
    end

    if not byKey then
      -- Fallback: IDs are secret -> just show all of your debuffs on the target.
      local n = math.min(#auras, 8)
      self:SetCount(n)
      for i = 1, n do
        local ic, a = self.icons[i], auras[i]
        pcall(ic.tex.SetTexture, ic.tex, a.icon)
        SetIconState(ic, true)
        SetAuraTimer(ic, "target", a)
        ic.warn, ic.expires = nil, nil
      end
      return
    end

    self:SetCount(#self.slots)
    for i, slot in ipairs(self.slots) do
      local ic = self.icons[i]
      local aura
      if slot.custom then
        aura = byId[slot.custom.id] or (slot.custom.name and byName[slot.custom.name])
      else
        for _, k in ipairs(slot.keys) do aura = aura or byKey[k] end
      end
      ic.warn, ic.expires = slot.warn, nil
      if aura then
        ic.tex:SetTexture(aura.icon or slot.icon)
        SetIconState(ic, true)
        SetAuraTimer(ic, "target", aura)
        if readable(aura.expirationTime) and aura.expirationTime and aura.expirationTime > 0 then
          ic.expires = aura.expirationTime
        end
      else
        ic.tex:SetTexture(slot.icon)
        SetIconState(ic, false)
        ic.cd:Clear()
      end
    end
  end
  function m:ShowFromCasts()
    local guid, now = TargetGUID(), GetTime()
    self:SetCount(#self.slots)
    for i, slot in ipairs(self.slots) do
      if not slot.custom then -- custom debuffs have no known duration: leave as they are
        local ic, t = self.icons[i], nil
        for _, k in ipairs(slot.keys) do
          local c = ns.casts[k]
          if c and (not c.guid or not guid or c.guid == guid) and c.start + c.dur > now then t = t or c end
        end
        ic.warn = slot.warn
        ic.tex:SetTexture(slot.icon)
        if t then
          SetIconState(ic, true)
          ic.cd:SetReverse(true)
          ic.cd:SetCooldown(t.start, t.dur)
          StyleCooldownText(ic)
          ic.expires, ic.fromCast = t.start + t.dur, true
        else
          SetIconState(ic, false)
          ic.cd:Clear()
          ic.expires, ic.fromCast = nil, nil
        end
      end
    end
  end

  -- Bleed refresh warning: Rip/Rake icon blinks red during its last 2 seconds.
  m.frame:SetScript("OnUpdate", function()
    if not ns.db then return end
    local now = GetTime()
    for i = 1, m.count do
      local ic = m.icons[i]
      if ic.fromCast and ic.expires and now >= ic.expires then
        -- Tracked debuff ran out: dim the icon again.
        ic.fromCast, ic.expires = nil, nil
        SetIconState(ic, false)
      end
      local left = ic.expires and (ic.expires - now)
      if ns.db.bleedWarn and ic.warn and left and left > 0 and left < 2 then
        ic:SetAlpha(0.35 + 0.65 * math.abs(math.sin(now * 8)))
        ic:SetBackdropBorderColor(1, 0.15, 0.15, 1)
        ic.blinking = true
      elseif ic.blinking then
        ic.blinking = nil
        ic:SetAlpha(1)
        ic:SetBackdropBorderColor(IconBorderColor())
      end
    end
  end)
end

-- Cooldowns (+ mana consumables) ------------------------------------
do
  local m = IconRow("cooldowns")
  function m:Rebuild()
    self.spells = {}
    for _, k in ipairs(COOLDOWNS[ns.form] or {}) do
      local id = not Hidden(k) and KnownID(k)
      if id then self.spells[#self.spells + 1] = { spell = id } end
    end
    for _, c in ipairs(CustomFor("cd")) do
      self.spells[#self.spells + 1] = { spell = c.name or c.id, icon = CustomIcon(c) }
    end
  end
  function m:Update()
    if not self.spells then self:Rebuild() end
    local entries = {}
    for _, e in ipairs(self.spells) do entries[#entries + 1] = e end
    if ns.db.consumables then
      for _, group in ipairs(CONSUMABLES) do
        for _, itemID in ipairs(group) do
          local count = ItemCount(itemID)
          if readable(count) and count and count > 0 then
            entries[#entries + 1] = { item = itemID, count = count }
            break
          end
        end
      end
    end
    self:SetCount(#entries)
    for i, e in ipairs(entries) do
      local ic = self.icons[i]
      local start, dur
      if e.item then
        ic.tex:SetTexture(ItemIcon(e.item) or 134400)
        ic.count:SetText(e.count > 1 and e.count or "")
        start, dur = ItemCooldown(e.item)
      else
        ic.tex:SetTexture(e.icon or SpellIcon(e.spell) or 134400)
        ic.count:SetText("")
        start, dur = GetCooldown(e.spell)
      end
      ic.cd:SetReverse(false)
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
      if okForm and not Hidden(b.key) and (known or not b.needsKnown) then
        self.slots[#self.slots + 1] = { key = b.key, reminder = b.reminder, icon = SpellIcon(known or S[b.key][#S[b.key]]) }
      end
    end
    for _, c in ipairs(CustomFor("buff")) do
      self.slots[#self.slots + 1] = { custom = c, icon = CustomIcon(c) }
    end
  end
  function m:Update()
    if not self.slots then self:Rebuild() end
    local auras, err = ScanAuras("player", "HELPFUL")
    if AurasUnknown(auras, err) then
      -- Unreadable in combat: keep the previous state, but show tracked casts (Tiger's Fury etc.).
      self:ShowFromCasts()
      return
    end
    local byKey, byId, byName = IndexAuras(auras)
    if not byKey then return end -- secret: keep the previous state
    -- Readable: remember real timers so they carry into combat.
    wipe(ns.buffCasts)
    for k in pairs(BUFF_DURATION) do
      local a = byKey[k]
      if a and readable(a.expirationTime, a.duration) and a.duration and a.duration > 0 then
        ns.buffCasts[k] = { start = a.expirationTime - a.duration, dur = a.duration }
      end
    end
    self:SetCount(#self.slots)
    for i, slot in ipairs(self.slots) do
      local ic, a = self.icons[i], nil
      if slot.custom then
        a = byId[slot.custom.id] or (slot.custom.name and byName[slot.custom.name])
      else
        a = byKey[slot.key]
      end
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
  -- Only touches slots we track by cast; all other buffs keep their last known state.
  function m:ShowFromCasts()
    local now = GetTime()
    for i, slot in ipairs(self.slots) do
      local t = slot.key and ns.buffCasts[slot.key]
      local ic = self.icons[i]
      if ic and t and t.start + t.dur > now then
        ic.tex:SetTexture(slot.icon)
        SetIconState(ic, true)
        ic.cd:SetReverse(true)
        ic.cd:SetCooldown(t.start, t.dur)
        StyleCooldownText(ic)
        ic.expires, ic.fromCast = t.start + t.dur, true
      end
    end
  end
  -- Dim a tracked buff again when its timer runs out.
  m.frame:SetScript("OnUpdate", function()
    local now = GetTime()
    for i = 1, m.count do
      local ic, slot = m.icons[i], m.slots and m.slots[i]
      if ic.fromCast and ic.expires and now >= ic.expires then
        ic.fromCast, ic.expires = nil, nil
        SetIconState(ic, false, slot and slot.reminder)
        ic.cd:Clear()
      end
    end
  end)
end

-- Clearcasting icon ------------------------------------------------
do
  local m = NewModule("clearcast")
  m.icon = CreateIcon(m.frame)
  m.icon:SetPoint("TOP")
  m.icon.tex:SetTexture(SpellIcon(CLEARCASTING_ID) or 136170)
  m.icon:SetBackdropBorderColor(0.45, 0.92, 1, 1)
  m.icon.keepBorder = true
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
-- Background panel / gold frame behind the attached elements.
local panel = CreateFrame("Frame", "CompactDruidBarPanel", UIParent, "BackdropTemplate")
panel:SetFrameStrata("LOW")
panel:Hide()
ns.panel = panel

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

------------------------------------------------------------------------
-- Sounds: our own sound files (shipped with the addon, like DBM does, so
-- they work on every client), LibSharedMedia sounds from other addons, and
-- a custom SoundKit ID / FileDataID.
------------------------------------------------------------------------
local SOUND_PATH = "Interface\\AddOns\\" .. ADDON .. "\\sounds\\"
local ADDON_SOUNDS = {
  { "shimmer", "Clearcast shimmer" },
  { "chime", "Chime" },
  { "doublechime", "Double chime" },
  { "bell", "Bell" },
  { "ping", "Ping" },
  { "pluck", "Pluck" },
  { "pop", "Pop" },
  { "alert", "Alert beep" },
  { "gong", "Gong" },
  { "whoosh", "Whoosh" },
}
-- Game sounds that are audible on WoW Forever.
local GAME_SOUNDS = {
  { "ALARM_CLOCK_WARNING_3", "Alarm (game)" },
}
-- Sounds borrowed from other installed addons (we don't ship Blizzard files ourselves).
local EXTERNAL_SOUNDS = {
  { "sao", "Spell proc (Blizzard, via SpellActivationOverlay)", "SpellActivationOverlay",
    "Interface\AddOns\SpellActivationOverlay\sounds\UI_PowerAura_Generic.ogg" },
}
local function AddonLoaded(name)
  if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
  return IsAddOnLoaded and IsAddOnLoaded(name)
end
local LSM_PREFIX = "CDB: "
local DEFAULT_SOUND = "file:shimmer"
ns.DEFAULT_SOUND = DEFAULT_SOUND

local function GetLSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end

-- Share our sounds with other addons (DBM, WeakAuras, ...) through SharedMedia.
function ns:RegisterSharedMedia()
  local LSM = GetLSM()
  if not LSM or self.lsmRegistered then return end
  self.lsmRegistered = true
  for _, s in ipairs(ADDON_SOUNDS) do
    LSM:Register("sound", LSM_PREFIX .. s[2], SOUND_PATH .. s[1] .. ".mp3")
  end
end

-- Returns a list of { key, label }. Keys: "file:name", "lsm:Name", "custom".
function ns.GetSoundChoices()
  local list = {}
  for _, e in ipairs(EXTERNAL_SOUNDS) do
    if AddonLoaded(e[3]) then list[#list + 1] = { "ext:" .. e[1], e[2] } end
  end
  for _, s in ipairs(ADDON_SOUNDS) do list[#list + 1] = { "file:" .. s[1], s[2] } end
  for _, g in ipairs(GAME_SOUNDS) do
    if SOUNDKIT and SOUNDKIT[g[1]] then list[#list + 1] = { "kit:" .. g[1], g[2] } end
  end
  local LSM = GetLSM()
  if LSM then
    for _, name in ipairs(LSM:List("sound")) do
      if name ~= "None" and name:sub(1, #LSM_PREFIX) ~= LSM_PREFIX then
        list[#list + 1] = { "lsm:" .. name, name .. " (SharedMedia)" }
      end
    end
  end
  list[#list + 1] = { "custom", "Custom ID..." }
  return list
end

-- Plays the chosen (or given) sound. Returns true when the client accepted it.
-- With manual = true (preview), a failure is reported in chat.
function ns:PlayAlertSound(key, manual)
  key = key or self.db.ccSoundKey or DEFAULT_SOUND
  local ch = self.db.ccSoundChannel or "Master"
  local kind, val = key:match("^(%a+):(.+)$")
  local played, why = false, nil
  if kind == "file" then
    local ok, willPlay = pcall(PlaySoundFile, SOUND_PATH .. val .. ".mp3", ch)
    played = ok and willPlay
    why = "sound file missing"
  elseif kind == "kit" then
    if SOUNDKIT and SOUNDKIT[val] then
      local ok, willPlay = pcall(PlaySound, SOUNDKIT[val], ch)
      played = ok and willPlay
    end
    why = "game sound not available on this client"
  elseif kind == "ext" then
    for _, e in ipairs(EXTERNAL_SOUNDS) do
      if e[1] == val then
        local ok, willPlay = pcall(PlaySoundFile, e[4], ch)
        played = ok and willPlay
        why = e[3] .. " is not installed or enabled"
      end
    end
  elseif kind == "lsm" then
    local LSM = GetLSM()
    local p = LSM and LSM:Fetch("sound", val, true)
    if p then
      local ok, willPlay = pcall(PlaySoundFile, p, ch)
      played = ok and willPlay
    end
    why = "SharedMedia sound not available"
  elseif key == "custom" then
    local id = tonumber(self.db.ccSoundCustom or "")
    if id then
      -- Try as SoundKit ID first, then as FileDataID.
      local ok, willPlay = pcall(PlaySound, id, ch)
      played = ok and willPlay
      if not played then
        ok, willPlay = pcall(PlaySoundFile, id, ch)
        played = ok and willPlay
      end
      why = "ID " .. id .. " is not a playable SoundKit ID or FileDataID on this client"
    else
      why = "no sound ID entered"
    end
  end
  if not played then
    if manual then
      print("|cff4fe8ffCompact Druid Bar|r: could not play this sound (" .. (why or "unknown") .. ").")
    elseif key ~= DEFAULT_SOUND then
      return self:PlayAlertSound(DEFAULT_SOUND) -- fall back to our own sound
    end
  end
  return played
end

function ns:OnClearcastStart()
  if self.db.ccSound then self:PlayAlertSound() end
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
-- Save a frame's position relative to the screen center (in the frame's own
-- scale units), snapping to the exact center line when within SNAP pixels.
local SNAP = 12
local function SavePoint(frame)
  local fx, fy = frame:GetCenter()
  local ux, uy = UIParent:GetCenter()
  local r = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
  local x, y = fx - ux * r, fy - uy * r
  if math.abs(x) < SNAP then x = 0 end
  if math.abs(y) < SNAP then y = 0 end
  return { "CENTER", "UIParent", "CENTER", math.floor(x + 0.5), math.floor(y + 0.5) }
end

-- Convert an older saved anchor to the center-based format.
function ns:NormalizePoint()
  if root:GetCenter() then self.db.point = SavePoint(root) end
end

function ns:SetBarPosition(x, y)
  self.db.point = { "CENTER", "UIParent", "CENTER", x or 0, y or 0 }
  self:Layout()
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
    if ns.RefreshOptions then ns.RefreshOptions() end
  end)
  mv:SetScript("OnMouseUp", function(_, btn)
    if btn == "RightButton" and ns.db.modules[m.key].detached then ns:Attach(m) end
  end)
  mv:SetScript("OnMouseWheel", function(_, delta)
    local mdb = ns.db.modules[m.key]
    if m.isIconRow and IsControlKeyDown() then
      -- Ctrl+wheel on an icon row: change only this row's icon size.
      ns.db.iconSizes[m.key] = math.min(60, math.max(10, m:Size() + delta * 2))
    elseif mdb.detached then
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
    if m.isIconRow then GameTooltip:AddLine("Ctrl+mouse wheel: icon size of this row", 1, 1, 1) end
    GameTooltip:Show()
  end)
  mv:SetScript("OnLeave", function() GameTooltip:Hide() end)
  m.mover = mv
end

function ns:Layout()
  local db = self.db
  if not db then return end
  -- Apply the visual style: fonts, bar textures, accents, sparks, icon borders.
  local st = Style()
  for _, fs in ipairs(self.fontStrings) do
    if not fs:SetFont(st.font, db.fontSize, st.flags) then fs:SetFont(FONT, db.fontSize, "OUTLINE") end
    if st.shadow then
      fs:SetShadowOffset(1, -1)
      fs:SetShadowColor(0, 0, 0, 1)
    else
      fs:SetShadowOffset(0, 0)
    end
  end
  for _, h in ipairs(self.bars) do
    local r, g, b = h.bar:GetStatusBarColor()
    h.bar:SetStatusBarTexture(st.tex)
    if r then h.bar:SetStatusBarColor(r, g, b) end
    h.accent:SetShown(st.accent and true or false)
    h.spark:ClearAllPoints()
    h.spark:SetPoint("CENTER", h.bar:GetStatusBarTexture(), "RIGHT", 0, 0)
  end
  for _, ic in ipairs(self.iconList) do
    if not ic.keepBorder then ic:SetBackdropBorderColor(IconBorderColor()) end
    ic.gloss:SetShown(db.iconBorder and true or false)
  end

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
    local gap = db.spacing + 6
    local rows, row, rowW, rowH = {}, {}, 0, 0
    for _, m in ipairs(flow) do
      local s = m:Size()
      local cw = m:ContentWidth()
      if cw == 0 then cw = s * 2 end -- empty (only while unlocked)
      local add = (#row > 0 and gap or 0) + cw
      if #row > 0 and rowW + add > width then
        rows[#rows + 1] = { items = row, w = rowW, h = rowH }
        row, rowW, rowH, add = {}, 0, 0, cw
      end
      row[#row + 1] = { m = m, w = cw, h = s }
      rowW = rowW + add
      rowH = math.max(rowH, s)
    end
    rows[#rows + 1] = { items = row, w = rowW, h = rowH }
    for _, r in ipairs(rows) do
      local x = (width - r.w) / 2
      for _, it in ipairs(r.items) do
        local f = it.m.frame
        f:SetSize(it.w, it.h)
        f:ClearAllPoints()
        -- Smaller rows are centered vertically on the line.
        f:SetPoint("TOPLEFT", root, "TOPLEFT", x, -(y + (r.h - it.h) / 2))
        it.m:Place()
        x = x + it.w + gap
      end
      y = y + r.h + db.spacing
    end
  end
  root:SetSize(width, math.max(y - db.spacing, 1))

  for _, h in ipairs(self.bars) do h.spark:SetSize(12, math.max(8, (h:GetHeight() or 10) * 2.2)) end

  -- Background panel and/or gold frame around the attached elements.
  if (db.panel or st.frame) and y > 0 then
    local pad = st.frame and 8 or 4
    panel:SetScale(db.scale)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", root, "TOPLEFT", -pad, pad)
    panel:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", pad, -pad)
    if st.frame then
      panel:SetBackdrop({ bgFile = TEX, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      panel:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
    else
      panel:SetBackdrop({ bgFile = TEX, edgeFile = TEX, edgeSize = 1 })
      panel:SetBackdropBorderColor(1, 1, 1, 0.08)
    end
    panel:SetBackdropColor(0, 0, 0, db.panel and 0.55 or 0)
    panel:Show()
  else
    panel:Hide()
  end

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

-- Custom spells ------------------------------------------------------
ns.KIND_LABELS = { cd = "Cooldown", buff = "Buff on me", debuff = "Debuff on target" }

function ns:AddCustom(input, kind, forms)
  input = strtrim(input or "")
  if input == "" then return false, "Enter a spell name or spell ID." end
  local id, name = tonumber(input), nil
  if id then
    name = ns.SpellName(id)
  elseif C_Spell and C_Spell.GetSpellInfo then
    local info = SafeCall(C_Spell.GetSpellInfo, input)
    if type(info) == "table" then id, name = info.spellID, info.name end
  elseif GetSpellInfo then
    local n, _, _, _, _, _, sid = GetSpellInfo(input)
    id, name = sid, n
  end
  if not id or not name then
    return false, "Spell not found: " .. input .. " (names only work for spells in your spellbook, use the spell ID otherwise)"
  end
  if not (forms.cat or forms.bear or forms.caster) then return false, "Pick at least one form." end
  table.insert(self.db.custom, { id = id, name = name, kind = kind,
    forms = { cat = forms.cat, bear = forms.bear, caster = forms.caster } })
  self:Refresh()
  return true, "Added " .. name .. " (" .. id .. ")"
end

function ns:RemoveCustom(index)
  table.remove(self.db.custom, index)
  self:Refresh()
end

function ns:SetLocked(locked, quiet)
  self.db.locked = locked
  self:Layout()
  if self.RefreshOptions then self.RefreshOptions() end
  if quiet then return end
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
ev:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    local _, class = UnitClass("player")
    if class ~= "DRUID" then
      print("|cff4fe8ffCompact Druid Bar|r: not a druid, addon disabled.")
      return
    end
    CompactDruidBarDB = CompactDruidBarDB or {}
    -- Upgrade: start the per-row icon sizes from the existing global size.
    if CompactDruidBarDB.iconSize and not CompactDruidBarDB.iconSizes then
      local s = CompactDruidBarDB.iconSize
      CompactDruidBarDB.iconSizes = { debuffs = s, cooldowns = s, buffs = s }
    end
    ns.db = CopyDefaults(DEFAULTS, CompactDruidBarDB)
    -- Upgrade: the old game-sound choices ("kit:...") are gone, use our own sound.
    if type(ns.db.ccSoundKey) == "string" and ns.db.ccSoundKey:sub(1, 4) == "kit:"
      and ns.db.ccSoundKey ~= "kit:ALARM_CLOCK_WARNING_3" then
      ns.db.ccSoundKey = ns.DEFAULT_SOUND
    end
    for _, key in ipairs(ns.MODULE_ORDER) do CreateMover(ns.modules[key]) end
    if ns.BuildOptions then ns:BuildOptions() end

    -- Blizzard Edit Mode open = bar unlocked, closed = locked again.
    if EditModeManagerFrame and EditModeManagerFrame.HookScript then
      EditModeManagerFrame:HookScript("OnShow", function()
        if ns.db.locked then
          ns.editModeUnlocked = true
          ns:SetLocked(false, true)
        end
      end)
      EditModeManagerFrame:HookScript("OnHide", function()
        if ns.editModeUnlocked then
          ns.editModeUnlocked = nil
          ns:SetLocked(true, true)
        end
      end)
    end

    TryRegister("PLAYER_ENTERING_WORLD")
    TryRegister("UPDATE_SHAPESHIFT_FORM")
    TryRegister("UPDATE_SHAPESHIFT_FORMS")
    TryRegister("SPELLS_CHANGED")
    TryRegister("CHARACTER_POINTS_CHANGED")
    TryRegister("PLAYER_TARGET_CHANGED")
    TryRegister("SPELL_UPDATE_COOLDOWN")
    TryRegister("PLAYER_REGEN_ENABLED")
    TryRegister("PLAYER_REGEN_DISABLED")
    TryRegister("BAG_UPDATE_COOLDOWN")
    TryRegister("BAG_UPDATE_DELAYED")
    TryRegister("UNIT_AURA", "player", "target")
    TryRegister("UNIT_POWER_FREQUENT", "player")
    TryRegister("UNIT_SPELLCAST_SUCCEEDED", "player")
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
        ns.panel:SetAlpha(a)
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

  -- All addons are loaded by now, so LibDBIcon from other addons is available.
  if event == "PLAYER_ENTERING_WORLD" then
    ns:SetupMinimap()
    ns:RegisterSharedMedia()
  end

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
    -- Without a readable GUID we can't tell targets apart: forget tracked casts.
    if not TargetGUID() then wipe(ns.casts) end
    ns.modules.debuffs.targetChanged = true
    ns.modules.debuffs:Update()
    ns.modules.combo:Update()
  elseif event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" or event == "BAG_UPDATE_DELAYED" then
    ns.modules.cooldowns:Update()
  elseif event == "UNIT_POWER_FREQUENT" then
    ns.modules.power:OnPower()
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    ns.modules.power:OnCast()
    ns:TrackCast(arg3)
  elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
    ns.modules.buffs:Update()
    ns.modules.debuffs:Update()
  end
end)

------------------------------------------------------------------------
-- Launchers: Addon Compartment (minimap addon list) + optional minimap button
------------------------------------------------------------------------
local ICON = 132115 -- Cat Form

function ns:OnLauncherClick(button)
  if not self.db then return end
  if button == "RightButton" then
    self:SetLocked(not self.db.locked)
  elseif IsShiftKeyDown() then
    self:OpenOptions("spells")
  else
    self:OpenOptions()
  end
end

function ns:LauncherTooltip(tt)
  tt:AddLine("Compact Druid Bar")
  tt:AddLine("Left-click: options", 1, 1, 1)
  tt:AddLine("Shift+left-click: spells", 1, 1, 1)
  tt:AddLine("Right-click: " .. ((self.db and self.db.locked) and "unlock (move)" or "lock"), 1, 1, 1)
end

function CompactDruidBar_OnAddonCompartmentClick(_, button) ns:OnLauncherClick(button) end
function CompactDruidBar_OnAddonCompartmentEnter(_, frame)
  GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
  ns:LauncherTooltip(GameTooltip)
  GameTooltip:Show()
end
function CompactDruidBar_OnAddonCompartmentLeave() GameTooltip:Hide() end

-- Own minimap button (used when LibDBIcon isn't loaded by another addon).
local function CreateOwnMinimapButton()
  local b = CreateFrame("Button", "CompactDruidBarMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetSize(17, 17)
  icon:SetTexture(ICON)
  icon:SetPoint("TOPLEFT", 7, -6)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetPoint("TOPLEFT")

  local function UpdatePos()
    local a = math.rad(ns.db.minimap.minimapPos or 220)
    local r = Minimap:GetWidth() / 2 + 5
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
  end
  b.UpdatePos = UpdatePos

  b:SetScript("OnClick", function(_, button) ns:OnLauncherClick(button) end)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local s = Minimap:GetEffectiveScale()
      local cx, cy = GetCursorPosition()
      cx, cy = cx / s, cy / s
      local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
      ns.db.minimap.minimapPos = math.deg(atan2(cy - my, cx - mx)) % 360
      UpdatePos()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    ns:LauncherTooltip(GameTooltip)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  UpdatePos()
  return b
end

function ns:SetupMinimap()
  if self.minimapReady then return end
  self.minimapReady = true
  local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
  local DBI = LibStub and LibStub("LibDBIcon-1.0", true)
  if LDB and DBI then
    local obj = LDB:NewDataObject("CompactDruidBar", {
      type = "launcher",
      icon = ICON,
      OnClick = function(_, button) ns:OnLauncherClick(button) end,
      OnTooltipShow = function(tt) ns:LauncherTooltip(tt) end,
    })
    DBI:Register("CompactDruidBar", obj, self.db.minimap)
    self.dbi = DBI
  else
    self.minimapButton = CreateOwnMinimapButton()
  end
  self:UpdateMinimap()
end

function ns:UpdateMinimap()
  if not self.minimapReady then return end
  local show = not self.db.minimap.hide
  if self.dbi then
    if show then self.dbi:Show("CompactDruidBar") else self.dbi:Hide("CompactDruidBar") end
  elseif self.minimapButton then
    self.minimapButton:SetShown(show)
    if show then self.minimapButton.UpdatePos() end
  end
end

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
  elseif cmd == "spells" then
    if ns.OpenOptions then ns:OpenOptions("spells") end
  elseif cmd == "minimap" then
    ns.db.minimap.hide = not ns.db.minimap.hide
    ns:UpdateMinimap()
    if ns.RefreshOptions then ns.RefreshOptions() end
  elseif cmd == "" or cmd == "config" or cmd == "options" then
    if ns.OpenOptions then ns:OpenOptions() end
  else
    print("|cff4fe8ffCompact Druid Bar|r: /cdb (options), /cdb unlock, /cdb lock, /cdb scale 1.2, /cdb spells, /cdb minimap, /cdb reset, /cdb test, /cdbdebug")
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
    -- Every block is guarded: one failing lookup must not hide the rest.
    local function try(label, fn)
      local ok, err = pcall(fn)
      if not ok then print("  " .. label .. ": ERROR " .. tostring(err)) end
    end
    print("|cff4fe8ffCompact Druid Bar debug|r build 10 (secret-API: " .. tostring(issecretvalue ~= nil) .. ", in combat: " .. tostring(UnitAffectingCombat("player")) .. ")")
    show("Health", UnitHealth("player"))
    show("Health max", UnitHealthMax("player"))
    show("Power type", UnitPowerType("player"))
    show("Energy", UnitPower("player", 3))
    show("Mana", UnitPower("player", 0))
    show("Mana max", UnitPowerMax("player", 0))
    show("Combo points", UnitPower("player", 4))
    show("Shift cost", ns.modules.mana.ShiftCost())
    show("Form", ns.form)
    local buffs, berr = ScanAuras("player", "HELPFUL")
    print(("  Buffs read: %d%s"):format(#buffs, berr and (" (ERROR " .. berr .. ")") or ""))
    if buffs[1] then show("First buff spellId", buffs[1].spellId) end
    if UnitExists("target") then
      local debuffs, derr = ScanAuras("target", "HARMFUL|PLAYER")
      print(("  Your target debuffs read: %d%s"):format(#debuffs, derr and (" (ERROR " .. derr .. ")") or ""))
      if debuffs[1] then
        show("First target debuff spellId", debuffs[1].spellId)
        show("First target debuff expires", debuffs[1].expirationTime)
      end
    else
      print("  Target: none")
    end
    show("Claw cost (clearcast fallback)", PowerCost(KnownID("claw") or 1082))
    show("Last cast spellID (debuff tracking)", ns.lastCastID)
    try("Last cast", function()
      if ns.lastCastID and readable(ns.lastCastID) then
        print(("  Last cast: %s -> %s"):format(tostring(ns.SpellName(ns.lastCastID)),
          tostring(CAST_KEY[ns.lastCastID] or SPELL_TO_KEY[ns.lastCastID] or KeyFromName(ns.SpellName(ns.lastCastID)) or "not tracked")))
      end
    end)
    try("Faerie Fire IDs", function()
      print(("  Faerie Fire (Feral) ID: %s, Faerie Fire ID: %s, Pounce ID: %s"):format(
        tostring(KnownID("ffFeral")), tostring(KnownID("ff")), tostring(KnownID("pounce"))))
    end)
    try("Tracked debuffs", function()
      local tracked = {}
      for k, c in pairs(ns.casts) do
        tracked[#tracked + 1] = ("%s %ds"):format(k, math.floor(math.max(0, c.start + c.dur - GetTime())))
      end
      print("  Tracked debuffs: " .. (#tracked > 0 and table.concat(tracked, ", ") or "none"))
    end)
    try("Debuff slots", function()
      local slots = {}
      for _, slot in ipairs(ns.modules.debuffs.slots or {}) do
        slots[#slots + 1] = slot.custom and ("custom:" .. tostring(slot.custom.name)) or table.concat(slot.keys, "/")
      end
      print("  Debuff slots: " .. (#slots > 0 and table.concat(slots, ", ") or "none"))
    end)
    try("Target GUID", function() show("Target GUID", UnitGUID and UnitGUID("target")) end)
    try("Cooldown", function() show("Cooldown Dash (start)", (GetCooldown(KnownID("dash") or 1850))) end)
    try("Clearcasting", function() show("Clearcasting now", HasClearcasting()) end)
    try("Curves", function()
      local mm = ns.modules.mana
      print(("  Curves available: %s, xN via curves: %s%s"):format(
        tostring(mm.CurvesSupported()), tostring(mm.shiftOK == true),
        mm.shiftBroken and " (FAILED)" or ""))
    end)
    print("  UnitHealthPercent: " .. tostring(UnitHealthPercent ~= nil))
    try("Panel", function()
      local pw, ph = ns.panel:GetSize()
      print(("  Style: %s, panel option: %s, panel shown: %s, visible: %s, size: %dx%d, alpha: %.2f"):format(
        tostring(ns.db.style), tostring(ns.db.panel), tostring(ns.panel:IsShown()), tostring(ns.panel:IsVisible()),
        math.floor(pw or 0), math.floor(ph or 0), ns.panel:GetEffectiveAlpha() or 0))
    end)
    print(("  Energy tick known: %s"):format(tostring(ns.modules.power.lastTick > 0)))
end
