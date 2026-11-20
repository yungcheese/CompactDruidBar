-- Compact Druid Bar - party buffs
-- A thin strip at the bottom of the Mark of the Wild and Thorns icons with one
-- segment per party member (your own subgroup in a raid) in class color:
-- lit = has it, red = missing, pulsing = less than 2 minutes left, faded =
-- out of range or unknown. The strip only appears while someone needs the
-- buff. Out of combat, clicking the icon casts it on the first member in range
-- who needs it.
-- Mark of the Wild goes to everyone; Thorns to tanks (group role or main tank)
-- and to the names set in the options.
-- Forever hides other players' auras in combat, so in combat we go on from
-- what we read before: the buffs' own timers, your own casts (on whoever you
-- cast them, however you targeted), and buffs dropping when someone dies.
-- Click-to-buff can't pick a target in combat (Blizzard blocks that).

local ADDON, ns = ...
local readable = ns.readable

local UNITS = { "party1", "party2", "party3", "party4" }
local SCAN_UNITS = { "player", "party1", "party2", "party3", "party4" } -- you too, for the tooltip
local EXPIRING = { motw = 120, thorns = 60 } -- warn when this many seconds are left
local GROUP_IDS = { [21849] = true, [21850] = true } -- Gift of the Wild: recognized, but not cast on click
local TRACKED = { motw = true, thorns = true }
local MISSING_COLOR = { 0.9, 0.15, 0.15 }

local P = { state = {}, strips = {}, buttons = {}, dead = {} }
-- Buff lengths, for casts we make in combat (when the real timers can't be read).
local DURATION = { motw = 1800, thorns = 600 }
local GROUP_DURATION = 3600
ns.party = P

local function Enabled() return ns.db and ns.db.partyBuffs end

-- Calls fn and returns its first result only if the client lets us read it.
local function Safe(fn, ...)
  if not fn then return end
  local ok, v, w = pcall(fn, ...)
  if ok and readable(v) and readable(w) then return v, w end
end

local function ThornsNames()
  local set = {}
  for n in (ns.db.thornsNames or ""):gmatch("[^,;%s]+") do set[n:lower()] = true end
  return set
end

local function IsTank(unit, names)
  if Safe(UnitGroupRolesAssigned, unit) == "TANK" then return true end
  if GetPartyAssignment and Safe(GetPartyAssignment, "MAINTANK", unit) then return true end
  local name = Safe(UnitName, unit)
  return name and names[name:lower()] or false
end

local function ClassColor(unit)
  local _, class = Safe(UnitClass, unit)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return c.r, c.g, c.b end
  return 0.8, 0.8, 0.8
end

-- Highest known single-target rank, by name (the client then picks the rank).
local function CastName(key)
  local ids = ns.S[key]
  for i = #ids, 1, -1 do
    if not GROUP_IDS[ids[i]] and ns.IsKnown(ids[i]) then return ns.SpellName(ids[i]) end
  end
end

------------------------------------------------------------------------
-- Reading auras (out of combat only)
------------------------------------------------------------------------
-- state[guid] = { motw = exp|false, thorns = exp|false }; exp 0 = no timer.
function P:Scan(unit)
  if InCombatLockdown() or not UnitExists(unit) then return end
  local guid = Safe(UnitGUID, unit)
  if not guid or not Safe(UnitIsVisible, unit) then return end -- too far away: keep what we knew
  local auras, err = ns.ScanAuras(unit, "HELPFUL")
  if err then return end
  local s = { motw = false, thorns = false }
  for _, a in ipairs(auras) do
    local key = (readable(a.spellId) and a.spellId and ns.SPELL_TO_KEY[a.spellId]) or ns.KeyFromName(a.name)
    if key and TRACKED[key] then
      local exp = readable(a.expirationTime) and a.expirationTime or 0
      s[key] = exp
    end
  end
  self.state[guid] = s
end

function P:ScanAll()
  if not Enabled() or InCombatLockdown() then return end
  local keep = {}
  for _, u in ipairs(SCAN_UNITS) do
    local g = UnitExists(u) and Safe(UnitGUID, u)
    if g then keep[g] = true; self:Scan(u) end
  end
  -- Forget only players who left the group.
  for g in pairs(self.state) do if not keep[g] then self.state[g] = nil end end
end

------------------------------------------------------------------------
-- Who needs what
------------------------------------------------------------------------
local targets = { motw = {}, thorns = {} }

-- status: "ok", "expiring", "missing" or "unknown", plus the seconds left (nil = no timer)
local function Status(guid, key, now)
  local s = P.state[guid]
  if not s or s[key] == nil then return "unknown" end
  local exp = s[key]
  if exp == false then return "missing" end
  if exp > 0 then
    local left = exp - now
    if left <= 0 then return "missing" end
    if left < EXPIRING[key] then return "expiring", left end
    return "ok", left
  end
  return "ok"
end

local function InRange(unit)
  local ok, inRange, checked = pcall(UnitInRange, unit)
  if not (ok and readable(inRange, checked)) then return true end
  return not checked or inRange
end

-- Fills targets[key]; returns whether anyone needs it and who to click-cast on.
local function Collect(key, names, now)
  local list = targets[key]
  wipe(list)
  local need, clickUnit
  for _, u in ipairs(UNITS) do
    local guid = UnitExists(u) and Safe(UnitGUID, u)
    local dead = guid and Safe(UnitIsDeadOrGhost, u)
    -- Dying drops every buff: after a res (also in combat) they're missing.
    if dead then P.dead[guid] = true
    elseif guid and P.dead[guid] then
      P.dead[guid] = nil
      P.state[guid] = { motw = false, thorns = false }
    end
    if guid and not dead and Safe(UnitIsConnected, u) ~= false
      and (key == "motw" or IsTank(u, names)) then
      local status, left = Status(guid, key, now)
      local range = InRange(u)
      list[#list + 1] = { unit = u, status = status, left = left, range = range }
      if status == "missing" or status == "expiring" then
        need = true
        if range and not clickUnit then clickUnit = u end
      end
    end
  end
  return need, clickUnit
end

------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------
local function GetStrip(ic)
  local st = P.strips[ic]
  if st then return st end
  st = CreateFrame("Frame", nil, ic)
  st:SetFrameLevel(ic.cd:GetFrameLevel() + 3)
  st.bg = st:CreateTexture(nil, "BACKGROUND")
  st.bg:SetAllPoints()
  st.bg:SetColorTexture(0, 0, 0, 0.85)
  st.segs = {}
  -- Count of members who need the buff, big and red in the top-right corner.
  st.badge = st:CreateFontString(nil, "OVERLAY")
  st.badge:SetTextColor(1, 0.2, 0.2)
  st:SetScript("OnHide", function()
    -- Give the icon its own border back (red if you're missing the buff yourself).
    if ic.tex:IsDesaturated() then ic:SetBackdropBorderColor(0.9, 0.1, 0.1, 1)
    else ic:SetBackdropBorderColor(ns.IconBorderColor()) end
  end)
  P.strips[ic] = st
  return st
end

local function DrawStrip(ic, list, now)
  local st = GetStrip(ic)
  local size = ic:GetHeight()
  local w = ic:GetWidth() - 2
  local h = math.max(4, math.floor(size * 0.28 + 0.5))
  local needCount = 0
  for _, t in ipairs(list) do
    if t.status == "missing" or t.status == "expiring" then needCount = needCount + 1 end
  end
  -- Pulsing red border around the whole icon.
  local pulse = 0.55 + 0.45 * math.abs(math.sin(now * 3))
  ic:SetBackdropBorderColor(1, 0.15, 0.15, pulse)
  st.badge:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", math.max(9, math.floor(size * 0.5)), "OUTLINE")
  st.badge:ClearAllPoints()
  st.badge:SetPoint("TOPRIGHT", ic, "TOPRIGHT", 2, 2)
  st.badge:SetText(needCount)
  st:ClearAllPoints()
  st:SetPoint("BOTTOMLEFT", ic, "BOTTOMLEFT", 1, 1)
  st:SetSize(w, h)
  local n, gap = #list, 1
  local segW = (w - 2 - (n - 1) * gap) / n
  for i, t in ipairs(list) do
    local seg = st.segs[i]
    if not seg then
      seg = st:CreateTexture(nil, "ARTWORK")
      st.segs[i] = seg
    end
    seg:ClearAllPoints()
    seg:SetPoint("TOPLEFT", st, "TOPLEFT", 1 + (i - 1) * (segW + gap), -1)
    seg:SetSize(segW, h - 2)
    local r, g, b
    if t.status == "missing" then r, g, b = MISSING_COLOR[1], MISSING_COLOR[2], MISSING_COLOR[3]
    else r, g, b = ClassColor(t.unit) end
    local a = 1
    if t.status == "unknown" or not t.range then a = 0.35
    elseif t.status == "expiring" then a = 0.35 + 0.65 * math.abs(math.sin(now * 4)) end
    seg:SetColorTexture(r, g, b, a)
    seg:Show()
  end
  for i = n + 1, #st.segs do st.segs[i]:Hide() end
  if not st:IsShown() then st:Show() end
end

local function HideStrips()
  for _, st in pairs(P.strips) do st:Hide() end
end

------------------------------------------------------------------------
-- Click to buff (secure buttons; only touched out of combat)
------------------------------------------------------------------------
-- "24m", "0:45", "active" (no timer), "missing", "?" (unknown); plus its color.
local function TimeText(status, left)
  if status == "missing" then return "missing", 1, 0.25, 0.25 end
  if status == "unknown" then return "?", 0.6, 0.6, 0.6 end
  local r, g, b = 1, 1, 1
  if status == "expiring" then r, g, b = 1, 0.6, 0.1 end
  if not left then return "active", r, g, b end
  if left >= 60 then return math.ceil(left / 60) .. "m", r, g, b end
  return ("0:%02d"):format(math.floor(left)), r, g, b
end

-- Owner is a buff icon (owner.partyKey) or a click button (owner.key).
local function ShowTooltip(owner)
  local key = owner.partyKey or owner.key
  if not key then return end
  local now = GetTime()
  GameTooltip:SetOwner(owner, "ANCHOR_TOP")
  local own = Safe(UnitGUID, "player")
  local text, r, g, b = TimeText(Status(own, key, now))
  GameTooltip:AddDoubleLine(ns.KeyName(key), "you: " .. text, 1, 0.82, 0, r, g, b)
  for _, t in ipairs(targets[key]) do
    local cr, cg, cb = ClassColor(t.unit)
    text, r, g, b = TimeText(t.status, t.left)
    if not t.range then text = text .. " (out of range)" end
    GameTooltip:AddDoubleLine(Safe(UnitName, t.unit) or t.unit, text, cr, cg, cb, r, g, b)
  end
  if InCombatLockdown() then
    GameTooltip:AddLine("In combat: estimated from timers and your casts", 0.6, 0.6, 0.6)
  end
  local unit = owner.GetAttribute and owner:GetAttribute("unit")
  if owner.key and unit then GameTooltip:AddLine("Click: cast on " .. (Safe(UnitName, unit) or unit), 0.4, 1, 0.4) end
  GameTooltip:Show()
end

-- Hover on the icon itself: mouse motion only, so clicks still go through to the world.
local function SetHover(ic, key)
  if ic.partyKey == key then return end
  ic.partyKey = key
  if not ic.partyHoverInit then
    ic.partyHoverInit = true
    ic:HookScript("OnEnter", function(self) if self.partyKey then ShowTooltip(self) end end)
    ic:HookScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
  end
  local on = key ~= nil
  if not (pcall(ic.SetMouseMotionEnabled, ic, on) and pcall(ic.SetMouseClickEnabled, ic, false)) then
    ic.partyKey = nil -- old client: no motion-only mouse, skip the tooltip rather than block clicks
  end
  if not on and GameTooltip:IsOwned(ic) then GameTooltip:Hide() end
end

local function GetButton(key)
  local b = P.buttons[key]
  if b or InCombatLockdown() then return b end
  b = CreateFrame("Button", "CompactDruidBarPartyBuff_" .. key, UIParent, "SecureActionButtonTemplate")
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "spell")
  b.key = key
  b:SetScript("OnEnter", ShowTooltip)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  P.buttons[key] = b
  return b
end

local function HideButtons()
  if InCombatLockdown() then return end
  for _, b in pairs(P.buttons) do
    b:Hide()
    b:ClearAllPoints()
  end
end

local function PlaceButton(key, ic, unit)
  if InCombatLockdown() then return end
  local spell = ns.db.partyClick and ns.db.locked and unit and CastName(key)
  local b = spell and GetButton(key)
  if not b then
    if P.buttons[key] then P.buttons[key]:Hide() end
    return
  end
  b:SetAttribute("spell", spell)
  b:SetAttribute("unit", unit)
  b:ClearAllPoints()
  b:SetAllPoints(ic)
  b:SetFrameStrata(ic:GetFrameStrata())
  b:SetFrameLevel(ic:GetFrameLevel() + 10)
  b:Show()
end

------------------------------------------------------------------------
-- Update loop
------------------------------------------------------------------------
function P:Draw()
  local m = ns.modules and ns.modules.buffs
  if not (Enabled() and m and m.slots) or not IsInGroup() then
    HideStrips()
    HideButtons()
    if m then for _, ic in ipairs(m.icons) do if ic.partyKey then SetHover(ic, nil) end end end
    return
  end
  local now, names = GetTime(), ThornsNames()
  local shown, placed = {}, {}
  for i, ic in ipairs(m.icons) do
    local slot = i <= m.count and m.slots[i]
    local key = slot and slot.key
    local tracked = key and TRACKED[key] and ic:IsVisible()
    SetHover(ic, tracked and key or nil)
    if tracked then
      local need, clickUnit = Collect(key, names, now)
      -- Keep an open tooltip current (twice a second is plenty).
      if GameTooltip:IsOwned(ic) and (not self.tipAt or now - self.tipAt > 0.5) then
        self.tipAt = now
        ShowTooltip(ic)
      end
      if need and #targets[key] > 0 then
        DrawStrip(ic, targets[key], now)
        shown[ic] = true
        PlaceButton(key, ic, clickUnit)
      else
        PlaceButton(key, ic, nil)
      end
      placed[key] = true
    end
  end
  for ic, st in pairs(self.strips) do if not shown[ic] then st:Hide() end end
  if InCombatLockdown() then return end
  for key, b in pairs(self.buttons) do
    -- The icon is gone (hidden spell, other form): don't leave a click area behind.
    if not placed[key] then b:Hide() end
    if b:IsShown() and GameTooltip:IsOwned(b) then ShowTooltip(b) end
  end
end

------------------------------------------------------------------------
-- Own casts: keep the state current in combat
------------------------------------------------------------------------
local pending = {} -- castGUID (or 1) -> { key, group, name }

local function UnitByName(name)
  if not name or not readable(name) then return end
  name = name:match("^[^-]+") -- drop the realm
  for _, u in ipairs(SCAN_UNITS) do
    if UnitExists(u) and Safe(UnitName, u) == name then return u end
  end
end

local function OnCastSent(target, castGUID, spellID)
  if not readable(spellID) or not spellID then return end
  local key = ns.SPELL_TO_KEY[spellID]
  if not (key and TRACKED[key]) then return end
  local id = readable(castGUID) and castGUID or 1
  pending[id] = { key = key, group = GROUP_IDS[spellID], name = target }
end

local function OnCastSucceeded(castGUID)
  local id = readable(castGUID) and castGUID or 1
  local p = pending[id] or pending[1]
  pending[id], pending[1] = nil, nil
  if not p then return end
  local now = GetTime()
  local function Give(u, dur)
    local g = Safe(UnitGUID, u)
    if not g then return end
    P.state[g] = P.state[g] or {}
    P.state[g][p.key] = now + dur
  end
  if p.group then
    for _, u in ipairs(SCAN_UNITS) do if UnitExists(u) then Give(u, GROUP_DURATION) end end
  else
    local u = UnitByName(p.name)
    if u then Give(u, DURATION[p.key]) end
  end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "UNIT_AURA", "UNIT_CONNECTION",
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }) do
  pcall(ev.RegisterEvent, ev, e)
end
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SENT", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
ev:SetScript("OnEvent", function(_, event, unit, a2, a3, a4)
  if event == "PLAYER_REGEN_DISABLED" then
    -- Fires just before the combat lockdown starts: last chance to hide the buttons.
    -- The strip stays and keeps going on timers and your casts.
    HideButtons()
    return
  end
  if not Enabled() then return end
  if event == "UNIT_SPELLCAST_SENT" then
    OnCastSent(a2, a3, a4)
    return
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    OnCastSucceeded(a2)
    P:Draw()
    return
  elseif event == "UNIT_AURA" or event == "UNIT_CONNECTION" then
    if unit == "player" or (type(unit) == "string" and unit:sub(1, 5) == "party") then P:Scan(unit) else return end
  else
    P:ScanAll()
  end
  P:Draw()
end)

local drawAcc, scanAcc = 0, 0
ev:SetScript("OnUpdate", function(_, elapsed)
  drawAcc, scanAcc = drawAcc + elapsed, scanAcc + elapsed
  if drawAcc < 0.1 then return end
  drawAcc = 0
  if not Enabled() then
    if next(P.strips) then HideStrips(); HideButtons() end
    return
  end
  -- Members walking back into view don't always send UNIT_AURA: rescan now and then.
  if scanAcc >= 2 then
    scanAcc = 0
    P:ScanAll()
  end
  P:Draw()
end)
